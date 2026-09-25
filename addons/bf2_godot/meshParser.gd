# MeshParser.gd
# Complete BF2 .staticmesh / .bundledmesh / .skinnedmesh file parser for Godot 4
# Based on bf2-blender Python implementation

extends RefCounted

# --- CONSTANTS ---
const TYPE_FLOAT1 = 0
const TYPE_FLOAT2 = 1
const TYPE_FLOAT3 = 2
const TYPE_FLOAT4 = 3
const TYPE_D3DCOLOR = 4
const TYPE_UBYTE4 = 5
const TYPE_SHORT2 = 6
const TYPE_SHORT4 = 7
const TYPE_UNUSED = 17

const USAGE_POSITION = 0
const USAGE_BLENDWEIGHT = 1
const USAGE_BLENDINDICES = 2
const USAGE_NORMAL = 3
const USAGE_PSIZE = 4
const USAGE_TEXCOORD0 = 5
const USAGE_TANGENT = 6
const USAGE_BINORMAL = 7
const USAGE_TEXCOORD1 = (1 << 8) | 5
const USAGE_TEXCOORD2 = (2 << 8) | 5
const USAGE_TEXCOORD3 = (3 << 8) | 5
const USAGE_TEXCOORD4 = (4 << 8) | 5

const PRIMITIVE_TRIANGLELIST = 4
const PRIMITIVE_TRIANGLESTRIP = 5

const ATTRIB_USED = 0
const ATTRIB_UNUSED = 255

const SKIN_BIND_MATRIX_NEEDS_INVERSION := false

enum AlphaMode {
	NONE = 0,
	ALPHA_BLEND = 1,
	ALPHA_TEST = 2
}

# --- HELPER CLASSES ---

class VertexAttribute:
	var flag: int = 0
	var offset: int = 0
	var vartype: int = 0
	var usage: int = 0
	
	func get_size() -> int:
		match vartype:
			TYPE_FLOAT1: return 4
			TYPE_FLOAT2: return 8
			TYPE_FLOAT3: return 12
			TYPE_FLOAT4: return 16
			TYPE_D3DCOLOR: return 4
			TYPE_UBYTE4: return 4
			TYPE_SHORT2: return 4
			TYPE_SHORT4: return 8
			_: return 0

class BF2Material:
	var alpha_mode: int = AlphaMode.NONE
	var fxfile: String = ""
	var technique: String = ""
	var maps: Array = []  # Texture paths
	
	var vstart: int = 0
	var istart: int = 0
	var inum: int = 0
	var vnum: int = 0
	
	var min_bounds: Vector3 = Vector3.ZERO
	var max_bounds: Vector3 = Vector3.ZERO
	
	var u4: int = 0
	var u5: int = 0

class LodPart:
	var mesh: ArrayMesh = null
	var materials: Array = []

class Lod:
	var materials: Array = []       # Array of BF2Material
	var min_bounds: Vector3 = Vector3.ZERO
	var max_bounds: Vector3 = Vector3.ZERO
	# SkinnedMesh only: Array of rigs, one per material (same order), each rig is an
	# Array of {"id": int, "matrix": Array[16]} dicts - a per-material bone palette.
	var rigs: Array = []
	# BundledMesh only: per-part index ranges within this LOD's shared index buffer.
	# One entry per animatable geometry part (mesh1, mesh2, ...).
	# Each entry: {"istart": int, "inum": int}
	# Empty for StaticMesh and SkinnedMesh.
	var parts_num: int = 0
	var parts: Array = []
	var mesh: ArrayMesh = null
	

class Geom:
	var lods: Array = []

# --- UTILITY FUNCTIONS ---

func _get_attrib_by_usage(attribs: Array, usage_id: int) -> VertexAttribute:
	for attrib in attribs:
		if attrib is VertexAttribute and attrib.usage == usage_id:
			return attrib
	return null

func _read_vb6_string(file: FileAccess) -> String:
	var length: int = file.get_32()
	if length > 0:
		var data_buffer: PackedByteArray = file.get_buffer(length)
		while data_buffer.size() > 0 and data_buffer[data_buffer.size() - 1] == 0:
			data_buffer.remove_at(data_buffer.size() - 1)
		return data_buffer.get_string_from_ascii()
	return ""

func _read_vec3(file: FileAccess) -> Vector3:
	var x: float = file.get_float()
	var y: float = file.get_float()
	var z: float = file.get_float()
	return Vector3(x, y, z)

func _read_mat4(file: FileAccess) -> Array:
	var m := []
	for i in range(16):
		m.append(file.get_float())
	return m

# Converts a BF2 row-major 4x4 matrix (used as v' = v * M, D3D row-vector convention)
# into a Godot Transform3D (used as v' = M * v, column-vector convention).
#
# For row-vector matrices, M's ROW i directly IS the vector describing where local
# axis i maps to - which is exactly what a Godot Basis COLUMN represents. So each
# Basis column = the corresponding matrix ROW, taken directly (verified against a
# concrete rotation-about-Z test case). Translation (row 3) carries over as-is.
func _mat4_array_to_transform3d(m: Array) -> Transform3D:
	if m.size() < 16:
		return Transform3D.IDENTITY
	var basis := Basis(
		Vector3(m[0], m[1], m[2]),
		Vector3(m[4], m[5], m[6]),
		Vector3(m[8], m[9], m[10])
	)
	var origin := Vector3(m[12], m[13], m[14])
	return Transform3D(basis, origin)

# Decodes up to 4 blend (bone) indices at the given vertex attribute offset.
func _decode_blend_indices(vertex_buffer: PackedByteArray, base_offset: int, attrib: VertexAttribute) -> PackedInt32Array:
	var result := PackedInt32Array([0, 0, 0, 0])
	if attrib == null:
		return result
	var offset: int = base_offset + attrib.offset
	match attrib.vartype:
		TYPE_D3DCOLOR, TYPE_UBYTE4:
			for k in range(4):
				result[k] = vertex_buffer.decode_u8(offset + k)
		TYPE_SHORT4:
			for k in range(4):
				result[k] = vertex_buffer.decode_u16(offset + k * 2)
		TYPE_SHORT2:
			result[0] = vertex_buffer.decode_u16(offset)
			result[1] = vertex_buffer.decode_u16(offset + 2)
		TYPE_FLOAT1:
			result[0] = int(vertex_buffer.decode_float(offset))
		_:
			push_warning("Unhandled BLENDINDICES vartype: %d" % attrib.vartype)
	return result

# Decodes up to 4 blend weights at the given vertex attribute offset.
func _decode_blend_weights(vertex_buffer: PackedByteArray, base_offset: int, attrib: VertexAttribute) -> PackedFloat32Array:
	var result := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
	if attrib == null:
		return result
	var offset: int = base_offset + attrib.offset
	match attrib.vartype:
		TYPE_FLOAT4:
			for k in range(4):
				result[k] = vertex_buffer.decode_float(offset + k * 4)
		TYPE_FLOAT3:
			for k in range(3):
				result[k] = vertex_buffer.decode_float(offset + k * 4)
			result[3] = 0.0
		TYPE_FLOAT2:
			result[0] = vertex_buffer.decode_float(offset)
			result[1] = vertex_buffer.decode_float(offset + 4)
		TYPE_FLOAT1:
			# Single stored weight - treated as a rigid single-bone weight
			# (blend-index[0] gets full weight). A 2-bone-blend interpretation
			# was tried and reverted - it made no observable difference, and the
			# actual arm/torso distortion bug turned out to be the skin bind
			# pose issue (see conParser's importSkinnedMesh comments).
			result[0] = vertex_buffer.decode_float(offset)
			result[1] = 0.0
			result[2] = 0.0
			result[3] = 0.0
		TYPE_UBYTE4, TYPE_D3DCOLOR:
			for k in range(4):
				result[k] = vertex_buffer.decode_u8(offset + k) / 255.0
		_:
			push_warning("Unhandled BLENDWEIGHT vartype: %d" % attrib.vartype)
	return result

# --- MAIN PARSING FUNCTION ---

func parse_bf2_mesh(filepath: String) -> Dictionary:
	var mesh_data = {
		"geoms": [],
		"vertex_attributes": [],
		"vertex_buffer": PackedByteArray(),
		"index_buffer": PackedInt32Array(),
		"vertex_stride": 0,
		"vertex_count": 0,
		"index_count": 0,
		"version": 0,
		"mesh_type": "unknown"  # "staticmesh", "bundledmesh", or "skinnedmesh"
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return mesh_data

	print("\n=== Parsing BF2 Mesh: %s ===" % filepath.get_file())
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return mesh_data

	file.big_endian = false
	
	# --- 1. HEADER ---
	var head_u1: int = file.get_32()
	var version: int = file.get_32()
	var head_u3: int = file.get_32()
	var head_u4: int = file.get_32()
	var head_u5: int = file.get_32()
	file.get_8()  # version flag
	
	mesh_data.version = version
	
	var ext := filepath.get_extension()
	if ext == "staticmesh":
		mesh_data.mesh_type = "staticmesh"
	elif ext == "bundledmesh":
		mesh_data.mesh_type = "bundledmesh"
	elif ext == "skinnedmesh":
		mesh_data.mesh_type = "skinnedmesh"
	else:
		mesh_data.mesh_type = "staticmesh" if version == 11 else "bundledmesh"
	
	print("Version: %d" % version)
	print("Mesh Type: %s" % mesh_data.mesh_type)
	
	var is_staticmesh = (mesh_data.mesh_type == "staticmesh")
	var is_bundledmesh = (mesh_data.mesh_type == "bundledmesh")
	var is_skinnedmesh = (mesh_data.mesh_type == "skinnedmesh")
	
	# 2. Geometry table
	var geom_count: int = file.get_32()
	print("Geometry Count: %d" % geom_count)
	var lod_counts: Array[int] = []
	for i in range(geom_count):
		var lc: int = file.get_32()
		lod_counts.append(lc)
		print("  Geom %d: %d LODs" % [i, lc])

	for i in range(geom_count):
		var geom = Geom.new()
		for j in range(lod_counts[i]):
			geom.lods.append(Lod.new())
		mesh_data.geoms.append(geom)
		
	# --- 3. VERTEX ATTRIBUTES ---
	var vert_attrib_count: int = file.get_32()
	var vert_attribs: Array[VertexAttribute] = []
	
	print("\nVertex Attributes:")
	for i in range(vert_attrib_count):
		var attrib = VertexAttribute.new()
		attrib.flag = file.get_16()
		attrib.offset = file.get_16()
		attrib.vartype = file.get_16()
		attrib.usage = file.get_16()
		
		vert_attribs.append(attrib)
		
		var usage_name = _get_usage_name(attrib.usage)
		print("  [%d] %s: offset=%d, type=%d, flag=%d" % [i, usage_name, attrib.offset, attrib.vartype, attrib.flag])
	
	if vert_attribs.size() > 0 and vert_attribs[-1].flag == ATTRIB_UNUSED:
		vert_attribs.pop_back()
	
	mesh_data.vertex_attributes = vert_attribs
	
	# --- 4. PRIMITIVE TYPE ---
	var primitive_type: int = file.get_32()
	if primitive_type != PRIMITIVE_TRIANGLELIST:
		push_warning("Non-standard primitive type: %d (expected %d)" % [primitive_type, PRIMITIVE_TRIANGLELIST])
	
	# --- 5. VERTEX BUFFER ---
	var vert_stride: int = file.get_32()
	var vert_count: int = file.get_32()
	
	print("\nVertex Data:")
	print("  Count: %d" % vert_count)
	print("  Stride: %d bytes" % vert_stride)
	
	var vertex_buffer: PackedByteArray = file.get_buffer(vert_stride * vert_count)
	
	mesh_data.vertex_buffer = vertex_buffer
	mesh_data.vertex_stride = vert_stride
	mesh_data.vertex_count = vert_count
	
	# --- 6. INDEX BUFFER ---
	var index_count: int = file.get_32()
	var indices: PackedInt32Array = PackedInt32Array()
	
	for i in range(index_count):
		indices.append(file.get_16())
	
	mesh_data.index_buffer = indices
	mesh_data.index_count = index_count
	
	print("\nIndex Count: %d" % index_count)
	
	# --- 7. ALPHA BLEND INDEX NUMBER ---
	# Only present for MaterialWithTransparency-based formats (StaticMesh, BundledMesh).
	var alpha_blend_indexnum: int = 0
	if not is_skinnedmesh:
		alpha_blend_indexnum = file.get_32()
		print("Alpha blend index num: %d" % alpha_blend_indexnum)
	
	# --- 8. LOD BOUNDS + PARTS/RIGS ---
	print("\nProcessing LODs:")
	print("File position before LOD processing: %d / %d bytes" % [file.get_position(), file.get_length()])
	
	for i in range(geom_count):
		var geom = mesh_data.geoms[i]
		
		for j in range(lod_counts[i]):
			var lod = geom.lods[j]
			lod.min_bounds = _read_vec3(file)
			lod.max_bounds = _read_vec3(file)
			if version <= 6:
				_read_vec3(file)  # old-format pivot
			if is_staticmesh:
				var parts_count: int = file.get_32()
				for p in range(parts_count):
					file.get_buffer(64)
			elif is_bundledmesh:
				lod.parts_num = file.get_32()
				print("  Geom %d LOD %d: parts_num=%d" % [i, j, lod.parts_num])
			elif is_skinnedmesh:
				var rig_count: int = file.get_32()
				print("    Rigs: %d" % rig_count)
				lod.rigs = []
				for r in range(rig_count):
					var bone_count: int = file.get_32()
					var bones := []
					for b in range(bone_count):
						var bone_id: int = file.get_32()
						var bone_matrix: Array = _read_mat4(file)
						bones.append({"id": bone_id, "matrix": bone_matrix})
					lod.rigs.append(bones)
					print("      Rig %d: %d bones" % [r, bone_count])
	
	# Second pass: Read all materials
	print("\nProcessing Materials:")
	for i in range(geom_count):
		var geom = mesh_data.geoms[i]
		
		for j in range(lod_counts[i]):
			var lod = geom.lods[j]
			
			print("  Processing materials for Geom %d LOD %d (file pos: %d)" % [i, j, file.get_position()])
			
			var mat_count: int = file.get_32()
			print("    Materials: %d (file pos: %d)" % [mat_count, file.get_position()])
			
			if mat_count < 0 or mat_count > 100:
				push_error("Unreasonable material count: %d at position %d" % [mat_count, file.get_position()])
				file.close()
				return mesh_data
			
			for k in range(mat_count):
				var mat = BF2Material.new()
				
				print("      Reading material %d (file pos: %d)" % [k, file.get_position()])
				
				if not is_skinnedmesh:
					mat.alpha_mode = file.get_32()
				
				mat.fxfile = _read_vb6_string(file)
				mat.technique = _read_vb6_string(file)
				
				var map_count: int = file.get_32()
				
				if map_count < 0 or map_count > 20:
					push_error("Unreasonable map count: %d at position %d" % [map_count, file.get_position()])
					file.close()
					return mesh_data
				
				for m in range(map_count):
					mat.maps.append(_read_vb6_string(file))
				
				mat.vstart = file.get_32()
				mat.istart = file.get_32()
				mat.inum = file.get_32()
				mat.vnum = file.get_32()
				
				mat.u4 = file.get_32()
				mat.u5 = file.get_32()
				
				if  version == 11:
					mat.min_bounds = _read_vec3(file)
					mat.max_bounds = _read_vec3(file)
				
				lod.materials.append(mat)
				
				print("      [%d] fx='%s' technique='%s' - verts:%d (start:%d), indices:%d (start:%d), alpha:%d" % 
					  [k, mat.fxfile, mat.technique, mat.vnum, mat.vstart, mat.inum, mat.istart, mat.alpha_mode])
				if mat.maps.size() > 0:
					print("           Textures: %s" % str(mat.maps))
	
	file.close()
	
	print("\n=== Parsing Complete ===\n")
	return mesh_data

func _get_usage_name(usage: int) -> String:
	match usage:
		USAGE_POSITION: return "POSITION"
		USAGE_BLENDWEIGHT: return "BLENDWEIGHT"
		USAGE_BLENDINDICES: return "BLENDINDICES"
		USAGE_NORMAL: return "NORMAL"
		USAGE_PSIZE: return "PSIZE"
		USAGE_TEXCOORD0: return "TEXCOORD0"
		USAGE_TANGENT: return "TANGENT"
		USAGE_BINORMAL: return "BINORMAL"
		USAGE_TEXCOORD1: return "TEXCOORD1"
		USAGE_TEXCOORD2: return "TEXCOORD2"
		USAGE_TEXCOORD3: return "TEXCOORD3"
		USAGE_TEXCOORD4: return "TEXCOORD4"
		_: return "UNKNOWN(%d)" % usage

# --- MESH CREATION ---

# Returns Array[Dictionary], each entry: {"mesh": ArrayMesh, "skin": Skin or null}.
#
# For StaticMesh and SkinnedMesh: one entry per LOD, containing all materials as
# surfaces on the single ArrayMesh (unchanged from before).
#
# For BundledMesh WITH parts data: one entry per PART per LOD. Each part owns a
# contiguous slice of the index buffer (lod.parts[p].istart / .inum). Vertices
# referenced by that slice are extracted from the shared vertex buffer and remapped
# to a compact 0-based local index. Materials are matched by vertex range overlap
# and applied as surfaces on that part's ArrayMesh. This gives the mesh1/mesh2/...
# separation required for independently-animatable weapon/vehicle parts.
#
# For BundledMesh WITHOUT parts data (lod.parts is empty, shouldn't happen with a
# correctly-parsed file but kept as a fallback): falls back to one-mesh-per-LOD.
func create_array_meshes(parsed_data: Dictionary) -> Array[Dictionary]:
	var meshes: Array[Dictionary] = []
	
	var vertex_buffer: PackedByteArray = parsed_data.vertex_buffer
	var index_buffer: PackedInt32Array = parsed_data.index_buffer
	var vertex_stride: int = parsed_data.vertex_stride
	var vert_attribs: Array = parsed_data.vertex_attributes
	
	var pos_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_POSITION)
	var normal_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_NORMAL)
	var uv0_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD0)
	var uv1_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD1)
	var uv2_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD2)
	var uv3_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD3)
	var uv4_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD4)
	var tangent_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TANGENT)
	var blendweight_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_BLENDWEIGHT)
	var blendindices_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_BLENDINDICES)
	
	if not pos_attrib:
		push_error("No position attribute found!")
		return meshes
	
	print("\n=== Creating Meshes ===")
	
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			
			if lod.materials.size() == 0:
				continue
				
			print("  Geom %d LOD %d: %d materials" % [geom_idx, lod_idx, lod.materials.size()])
			_create_lod_mesh(
				meshes, lod, geom_idx, lod_idx,
				vertex_buffer, index_buffer, vertex_stride,
				pos_attrib, normal_attrib, uv0_attrib, uv1_attrib,
				uv2_attrib, uv3_attrib, uv4_attrib, tangent_attrib,
				blendweight_attrib, blendindices_attrib
			)
	
	print("\n=== Created %d total mesh entries ===" % meshes.size())
	return meshes

# Splits a BundledMesh LOD into one ArrayMesh per geometry part.
# Each part owns lod.parts[p] = {istart, inum} — a contiguous slice of the
# global index buffer. Vertices referenced by that slice are extracted into a
# compact local array (global→local remap via PackedInt32Array for O(1) lookup
# with no Variant boxing). Material is matched by checking which material's
# vstart..vstart+vnum range contains the part's first vertex — one surface per
# part, which matches BF2's actual per-part material assignment in practice.
func _create_bundledmesh_parts(
		meshes: Array,
		lod: Lod,
		geom_idx: int,
		lod_idx: int,
		vertex_buffer: PackedByteArray,
		index_buffer: PackedInt32Array,
		vertex_stride: int,
		pos_attrib: VertexAttribute,
		normal_attrib: VertexAttribute,
		uv0_attrib: VertexAttribute,
		uv1_attrib: VertexAttribute,
		uv2_attrib: VertexAttribute,
		uv3_attrib: VertexAttribute,
		uv4_attrib: VertexAttribute,
		tangent_attrib: VertexAttribute) -> void:

	var total_verts: int = vertex_buffer.size() / vertex_stride if vertex_stride > 0 else 0

	for part_idx in range(lod.parts.size()):
		var part = lod.parts[part_idx]
		var part_istart: int = part["istart"]
		var part_inum: int = part["inum"]

		if part_inum == 0 or part_istart >= index_buffer.size():
			meshes.append({"mesh": null, "skin": null})
			print("    Part %d: empty" % part_idx)
			continue

		var actual_inum: int = mini(part_inum, index_buffer.size() - part_istart)

		# --- Global → local vertex remap ---
		# PackedInt32Array sized to total vertex count, filled -1 = "not seen yet".
		# Direct index lookup: no Dictionary, no Variant boxing, no crashes on
		# large meshes.
		var global_to_local := PackedInt32Array()
		global_to_local.resize(total_verts)
		global_to_local.fill(-1)

		var local_indices := PackedInt32Array()
		local_indices.resize(actual_inum)
		var ordered_globals := PackedInt32Array()  # local_idx → global_idx

		for i in range(actual_inum):
			var g: int = index_buffer[part_istart + i]
			if g < 0 or g >= total_verts:
				local_indices[i] = 0  # clamp degenerate index
				continue
			if global_to_local[g] == -1:
				global_to_local[g] = ordered_globals.size()
				ordered_globals.append(g)
			local_indices[i] = global_to_local[g]

		# Reverse triangle winding: BF2 left-hand → Godot right-hand
		var wi := 0
		while wi + 2 < local_indices.size():
			var tmp: int = local_indices[wi + 1]
			local_indices[wi + 1] = local_indices[wi + 2]
			local_indices[wi + 2] = tmp
			wi += 3

		var remainder: int = local_indices.size() % 3
		if remainder != 0:
			local_indices.resize(local_indices.size() - remainder)

		if local_indices.size() == 0 or ordered_globals.size() == 0:
			meshes.append({"mesh": null, "skin": null})
			continue

		# --- Build vertex arrays ---
		var vert_count: int = ordered_globals.size()

		var vertices := PackedVector3Array(); vertices.resize(vert_count)
		var normals  := PackedVector3Array()
		var uvs      := PackedVector2Array()
		var uv2s     := PackedVector2Array()
		var tangents := PackedFloat32Array()
		var custom0s := PackedColorArray()
		var custom1s := PackedColorArray()

		if normal_attrib:  normals.resize(vert_count)
		if uv0_attrib:     uvs.resize(vert_count)
		if uv1_attrib:     uv2s.resize(vert_count)
		if tangent_attrib: tangents.resize(vert_count * 4)

		var need_extra_uvs := (uv2_attrib != null or uv3_attrib != null or uv4_attrib != null)
		if need_extra_uvs:
			custom0s.resize(vert_count)
			custom1s.resize(vert_count)

		for li in range(vert_count):
			var g: int = ordered_globals[li]
			var base: int = g * vertex_stride

			var p: int = base + pos_attrib.offset
			vertices[li] = Vector3(
				vertex_buffer.decode_float(p),
				vertex_buffer.decode_float(p + 4),
				vertex_buffer.decode_float(p + 8))

			if normal_attrib:
				var n: int = base + normal_attrib.offset
				normals[li] = Vector3(
					vertex_buffer.decode_float(n),
					vertex_buffer.decode_float(n + 4),
					vertex_buffer.decode_float(n + 8))

			if uv0_attrib:
				var u: int = base + uv0_attrib.offset
				uvs[li] = Vector2(
					vertex_buffer.decode_float(u),
					vertex_buffer.decode_float(u + 4))

			if uv1_attrib:
				var u: int = base + uv1_attrib.offset
				uv2s[li] = Vector2(
					vertex_buffer.decode_float(u),
					vertex_buffer.decode_float(u + 4))

			if tangent_attrib:
				var t: int = base + tangent_attrib.offset
				var ti: int = li * 4
				tangents[ti]     = vertex_buffer.decode_float(t)
				tangents[ti + 1] = vertex_buffer.decode_float(t + 4)
				tangents[ti + 2] = vertex_buffer.decode_float(t + 8)
				tangents[ti + 3] = 1.0

			if need_extra_uvs:
				var u3 := 0.0; var v3 := 0.0
				var u4 := 0.0; var v4 := 0.0
				var u5 := 0.0; var v5 := 0.0
				if uv2_attrib:
					var o: int = base + uv2_attrib.offset
					u3 = vertex_buffer.decode_float(o)
					v3 = vertex_buffer.decode_float(o + 4)
				if uv3_attrib:
					var o: int = base + uv3_attrib.offset
					u4 = vertex_buffer.decode_float(o)
					v4 = vertex_buffer.decode_float(o + 4)
				if uv4_attrib:
					var o: int = base + uv4_attrib.offset
					u5 = vertex_buffer.decode_float(o)
					v5 = vertex_buffer.decode_float(o + 4)
				custom0s[li] = Color(v3, u3, v4, u4)
				custom1s[li] = Color(v5, u5, 0.0, 0.0)

		# --- Find the material that owns this part ---
		# Check which material's vertex range contains our first global vertex.
		# In BF2 each geometry part maps to exactly one material; this is a
		# reliable O(materials) check with no per-triangle work.
		var first_global: int = ordered_globals[0]
		var best_mat = lod.materials[0]  # fallback: first material
		for mat in lod.materials:
			if first_global >= mat.vstart and first_global < mat.vstart + mat.vnum:
				best_mat = mat
				break

		# --- Assemble ArrayMesh (one surface = one part) ---
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX]  = local_indices
		if normals.size()  > 0: arrays[Mesh.ARRAY_NORMAL]  = normals
		if uvs.size()      > 0: arrays[Mesh.ARRAY_TEX_UV]  = uvs
		if uv2s.size()     > 0: arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		if tangents.size() > 0: arrays[Mesh.ARRAY_TANGENT] = tangents
		if custom0s.size() > 0: arrays[Mesh.ARRAY_CUSTOM0] = custom0s.to_byte_array()
		if custom1s.size() > 0: arrays[Mesh.ARRAY_CUSTOM1] = custom1s.to_byte_array()
		


		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(0, best_mat.technique)

		meshes.append({"mesh": mesh, "skin": null})
		print("    Part %d (mesh%d): %d verts, %d tris, mat='%s'" % [
			part_idx, part_idx + 1,
			vert_count,
			local_indices.size() / 3,
			best_mat.technique])

# Builds one ArrayMesh for the whole LOD (StaticMesh, SkinnedMesh, or BundledMesh
# fallback). One surface per material, exactly as before.
func _create_lod_mesh(
		meshes: Array,
		lod: Lod,
		geom_idx: int,
		lod_idx: int,
		vertex_buffer: PackedByteArray,
		index_buffer: PackedInt32Array,
		vertex_stride: int,
		pos_attrib: VertexAttribute,
		normal_attrib: VertexAttribute,
		uv0_attrib: VertexAttribute,
		uv1_attrib: VertexAttribute,
		uv2_attrib: VertexAttribute,
		uv3_attrib: VertexAttribute,
		uv4_attrib: VertexAttribute,
		tangent_attrib: VertexAttribute,
		blendweight_attrib: VertexAttribute,
		blendindices_attrib: VertexAttribute) -> void:

	var mesh := ArrayMesh.new()
	var surface_count := 0
	
	# Build unified skin bind list for SkinnedMesh LODs. Godot's Skin resource is
	# per-MeshInstance3D (shared across all surfaces), unlike BF2's per-material
	# palettes, so this remap is required.
	var has_skin: bool = lod.rigs.size() > 0
	var unified_bone_ids: Array = []
	var unified_bind_slot: Dictionary = {}
	var unified_bind_matrix: Dictionary = {}
	
	if has_skin:
		for mi in range(lod.materials.size()):
			if mi >= lod.rigs.size():
				continue
			for bone_entry in lod.rigs[mi]:
				var bid = bone_entry["id"]
				if not unified_bind_slot.has(bid):
					unified_bind_slot[bid] = unified_bone_ids.size()
					unified_bone_ids.append(bid)
					unified_bind_matrix[bid] = bone_entry["matrix"]
		print("    Skin: %d unique bone(s) across %d rig(s)" % [unified_bone_ids.size(), lod.rigs.size()])
	
	for mat_idx in range(lod.materials.size()):
		var mat = lod.materials[mat_idx]
		
		if mat.vnum == 0 or mat.inum == 0:
			print("    Material %d '%s': SKIPPED (vnum=%d, inum=%d)" % [mat_idx, mat.technique, mat.vnum, mat.inum])
			continue
		
		var total_vertex_count: int = (vertex_buffer.size() / vertex_stride) if vertex_stride > 0 else 0
		if mat.vstart + mat.vnum > total_vertex_count:
			push_error("Material vertex range out of bounds: vstart=%d vnum=%d total=%d" % [mat.vstart, mat.vnum, total_vertex_count])
			continue
		
		if mat.istart + mat.inum > index_buffer.size():
			push_error("Material index range out of bounds: istart=%d inum=%d total=%d" % [mat.istart, mat.inum, index_buffer.size()])
			continue
		
		var rig: Array = []
		if has_skin and mat_idx < lod.rigs.size():
			rig = lod.rigs[mat_idx]
		
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var custom0s := PackedByteArray()
		var custom1s := PackedByteArray()
		var tangents := PackedFloat32Array()
		var bone_ids_arr := PackedInt32Array()
		var bone_weights_arr := PackedFloat32Array()
		
		for i in range(mat.vnum):
			var vert_idx: int = mat.vstart + i
			var base_offset: int = vert_idx * vertex_stride
			
			var pos_offset: int = base_offset + pos_attrib.offset
			vertices.append(Vector3(
				vertex_buffer.decode_float(pos_offset),
				vertex_buffer.decode_float(pos_offset + 4),
				vertex_buffer.decode_float(pos_offset + 8)
			))
			
			if normal_attrib:
				var norm_offset: int = base_offset + normal_attrib.offset
				normals.append(Vector3(
					vertex_buffer.decode_float(norm_offset),
					vertex_buffer.decode_float(norm_offset + 4),
					vertex_buffer.decode_float(norm_offset + 8)
				))
			
			if uv0_attrib:
				var uv_offset: int = base_offset + uv0_attrib.offset
				uvs.append(Vector2(
					vertex_buffer.decode_float(uv_offset),
					vertex_buffer.decode_float(uv_offset + 4)
				))
			
			if uv1_attrib:
				var uv2_offset: int = base_offset + uv1_attrib.offset
				uv2s.append(Vector2(
					vertex_buffer.decode_float(uv2_offset),
					vertex_buffer.decode_float(uv2_offset + 4)
				))
			
			if uv2_attrib or uv3_attrib or uv4_attrib:
				var uv3_u := 0.0; var uv3_v := 0.0
				var uv4_u := 0.0; var uv4_v := 0.0
				var uv5_u := 0.0; var uv5_v := 0.0
				if uv2_attrib:
					var offset: int = base_offset + uv2_attrib.offset
					uv3_u = vertex_buffer.decode_float(offset)
					uv3_v = vertex_buffer.decode_float(offset + 4)
				if uv3_attrib:
					var offset: int = base_offset + uv3_attrib.offset
					uv4_u = vertex_buffer.decode_float(offset)
					uv4_v = vertex_buffer.decode_float(offset + 4)
				if uv4_attrib:
					var offset: int = base_offset + uv4_attrib.offset
					uv5_u = vertex_buffer.decode_float(offset)
					uv5_v = vertex_buffer.decode_float(offset + 4)
					
				
				custom0s.append(clampi(int(uv3_u * 255.0), 0, 255))
				custom0s.append(clampi(int(uv3_v * 255.0), 0, 255))
				
				custom0s.append(clampi(int(uv4_u * 255.0), 0, 255))
				custom0s.append(clampi(int(uv4_v * 255.0), 0, 255))
				
				custom1s.append(clampi(int(uv5_u * 255.0), 0, 255))
				custom1s.append(clampi(int(uv5_v * 255.0), 0, 255))
				
				custom1s.append(0)
				custom1s.append(0)
			
			if tangent_attrib:
				var tan_offset: int = base_offset + tangent_attrib.offset
				tangents.append(vertex_buffer.decode_float(tan_offset))
				tangents.append(vertex_buffer.decode_float(tan_offset + 4))
				tangents.append(vertex_buffer.decode_float(tan_offset + 8))
				tangents.append(1.0)
			
			if has_skin:
				var raw_indices: PackedInt32Array = _decode_blend_indices(vertex_buffer, base_offset, blendindices_attrib)
				var raw_weights: PackedFloat32Array = _decode_blend_weights(vertex_buffer, base_offset, blendweight_attrib)
				
				if blendweight_attrib and blendweight_attrib.vartype == TYPE_FLOAT3:
					raw_weights[3] = clampf(1.0 - (raw_weights[0] + raw_weights[1] + raw_weights[2]), 0.0, 1.0)
				
				var final_bones := PackedInt32Array([0, 0, 0, 0])
				var final_weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
				
				for k in range(4):
					var palette_idx: int = raw_indices[k]
					var w: float = raw_weights[k]
					if w <= 0.0:
						continue
					if palette_idx < 0 or palette_idx >= rig.size():
						continue
					var skeleton_bone_id = rig[palette_idx]["id"]
					if not unified_bind_slot.has(skeleton_bone_id):
						continue
					final_bones[k] = unified_bind_slot[skeleton_bone_id]
					final_weights[k] = w
				
				var wsum: float = final_weights[0] + final_weights[1] + final_weights[2] + final_weights[3]
				if wsum > 0.0:
					for k in range(4):
						final_weights[k] = final_weights[k] / wsum
				else:
					final_weights[0] = 1.0
				
				for k in range(4):
					bone_ids_arr.append(final_bones[k])
					bone_weights_arr.append(final_weights[k])
		
		var local_indices := PackedInt32Array()
		for i in range(mat.inum):
			if mat.istart + i >= index_buffer.size():
				break
			var idx: int = index_buffer[mat.istart + i]
			if idx < 0 or idx >= mat.vnum:
				if i < 10:
					print("      WARNING: Index %d: value=%d (out of range 0-%d)" % [i, idx, mat.vnum - 1])
			local_indices.append(idx)
		
		for i in range(0, local_indices.size() - 2, 3):
			var temp = local_indices[i + 1]
			local_indices[i + 1] = local_indices[i + 2]
			local_indices[i + 2] = temp
		
		var remainder := local_indices.size() % 3
		if remainder != 0:
			local_indices.resize(local_indices.size() - remainder)
		
		if local_indices.size() == 0 or vertices.size() == 0:
			print("    Material %d '%s': SKIPPED (no valid triangles)" % [mat_idx, mat.technique])
			continue
		
		var tri_count := local_indices.size() / 3
		
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = local_indices
		if normals.size() > 0: arrays[Mesh.ARRAY_NORMAL] = normals
		if uvs.size() > 0: arrays[Mesh.ARRAY_TEX_UV] = uvs
		if uv2s.size() > 0: arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		if custom0s.size() > 0: arrays[Mesh.ARRAY_CUSTOM0] = custom0s
		if custom1s.size() > 0: arrays[Mesh.ARRAY_CUSTOM1] = custom1s
		if tangents.size() > 0: arrays[Mesh.ARRAY_TANGENT] = tangents
		if has_skin and bone_ids_arr.size() > 0:
			arrays[Mesh.ARRAY_BONES] = bone_ids_arr
			arrays[Mesh.ARRAY_WEIGHTS] = bone_weights_arr
		
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, mat.technique)
		surface_count += 1
		print("    Material %d '%s': OK - %d verts, %d tris" % [mat_idx, mat.technique, vertices.size(), tri_count])
	
	# Build unified Skin resource for SkinnedMesh LODs.
	var lod_skin: Skin = null
	if has_skin and unified_bone_ids.size() > 0:
		lod_skin = Skin.new()
		lod_skin.set_bind_count(unified_bone_ids.size())
		for slot in range(unified_bone_ids.size()):
			var bid = unified_bone_ids[slot]
			lod_skin.set_bind_bone(slot, bid)
			var bind_transform := _mat4_array_to_transform3d(unified_bind_matrix[bid])
			if SKIN_BIND_MATRIX_NEEDS_INVERSION:
				bind_transform = bind_transform.affine_inverse()
			lod_skin.set_bind_pose(slot, bind_transform)
		print("    Built Skin with %d bind(s)" % unified_bone_ids.size())
	
	if mesh.get_surface_count() > 0:
		meshes.append({"mesh": mesh, "skin": lod_skin})
		print("  → Created mesh with %d surfaces%s" % [surface_count, " + skin" if lod_skin != null else ""])


# ---------------------------------------------------------------------------
# create_part_meshes_bundled
#
# For each Geom/LOD: reads blendindices[0] per vertex to find part_id,
# splits geometry into per-part buckets, builds one ArrayMesh per part,
# and stores it on lod.parts[part_id].mesh.
#
# After this call, conParser can do:
#   lod.parts[part_idx].mesh   → the ArrayMesh for that part
#   lod.parts[part_idx].materials → list of BF2Material that contributed
# ---------------------------------------------------------------------------
func create_part_meshes_bundled(parsed_data: Dictionary) -> void:
	var vertex_buffer: PackedByteArray  = parsed_data.vertex_buffer
	var index_buffer:  PackedInt32Array = parsed_data.index_buffer
	var vertex_stride: int              = parsed_data.vertex_stride
	var vert_attribs:  Array            = parsed_data.vertex_attributes

	var pos_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_POSITION)
	var normal_attrib  = _get_attrib_by_usage(vert_attribs, USAGE_NORMAL)
	var uv0_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD0)
	var uv1_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD1)
	var uv2_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD2)
	var uv3_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD3)
	var uv4_attrib     = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD4)
	var tangent_attrib = _get_attrib_by_usage(vert_attribs, USAGE_TANGENT)
	var blend_attrib   = _get_attrib_by_usage(vert_attribs, USAGE_BLENDINDICES)

	if not pos_attrib:
		push_error("No position attribute!"); return
	if not blend_attrib:
		push_error("No BLENDINDICES attribute — cannot split bundled mesh parts!")
		return

	print("\n=== Splitting BundledMesh by part (blendindices) ===")

	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]

		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			if lod.materials.size() == 0:
				continue

			var num_parts = lod.parts_num
			print("  Geom %d LOD %d: %d parts, %d materials" % [geom_idx, lod_idx, num_parts, lod.materials.size()])

			# Initialise LodPart slots
			lod.parts.clear()
			for p in range(num_parts):
				lod.parts.append(LodPart.new())

			# Per-part accumulator: part_id → {verts: Array, old_to_new: Dict, indices: PackedInt32Array}
			# We accumulate surfaces from ALL materials into the same part bucket,
			# adding one surface per material on the resulting ArrayMesh.
			# (Each material produces exactly one surface on the part's ArrayMesh.)

			for mat_idx in range(lod.materials.size()):
				var mat = lod.materials[mat_idx]
				if mat.vnum == 0 or mat.inum == 0: continue
				if mat.vstart + mat.vnum > parsed_data.vertex_count: continue
				if mat.istart + mat.inum  > index_buffer.size(): continue

				# --- Step 1: read part_id for every vertex in this material ---
				# vert_part[i] = part_id of the i-th vertex in this material's range
				var vert_part := PackedByteArray()
				vert_part.resize(mat.vnum)
				for i in range(mat.vnum):
					var base_offset = (mat.vstart + i) * vertex_stride
					vert_part[i] = vertex_buffer[base_offset + blend_attrib.offset]

				# --- Step 2: for each triangle, determine its part ---
				# A triangle's part = part_id of its first vertex.
				# (All three verts of a triangle are always in the same part in BF2.)
				# Bucket: part_id → { verts[], old_to_new{}, indices[] }
				var buckets := {}

				for tri in range(mat.inum / 3):
					var base_i = mat.istart + tri * 3
					if base_i + 2 >= index_buffer.size(): break

					var i0 := index_buffer[base_i]
					var i1 := index_buffer[base_i + 1]
					var i2 := index_buffer[base_i + 2]

					# Validate indices
					if i0 >= mat.vnum or i1 >= mat.vnum or i2 >= mat.vnum:
						continue

					var part_id := vert_part[i0]
					if part_id >= num_parts:
						part_id = 0  # Safety clamp

					if not buckets.has(part_id):
						buckets[part_id] = { "verts": [], "old_to_new": {}, "indices": PackedInt32Array() }

					var bucket = buckets[part_id]
					var old_to_new: Dictionary = bucket["old_to_new"]

					for old_idx in [i0, i1, i2]:
						if not old_to_new.has(old_idx):
							# Extract and store full vertex data
							var base_offset = (mat.vstart + old_idx) * vertex_stride
							var v := {}

							var po = base_offset + pos_attrib.offset
							v["pos"] = Vector3(vertex_buffer.decode_float(po),
											   vertex_buffer.decode_float(po + 4),
											   vertex_buffer.decode_float(po + 8))
							if normal_attrib:
								var no = base_offset + normal_attrib.offset
								v["normal"] = Vector3(vertex_buffer.decode_float(no),
													  vertex_buffer.decode_float(no + 4),
													  vertex_buffer.decode_float(no + 8))
							if uv0_attrib:
								var uo = base_offset + uv0_attrib.offset
								v["uv0"] = Vector2(vertex_buffer.decode_float(uo),
												   vertex_buffer.decode_float(uo + 4))
							if uv1_attrib:
								var uo = base_offset + uv1_attrib.offset
								v["uv1"] = Vector2(vertex_buffer.decode_float(uo),
												   vertex_buffer.decode_float(uo + 4))
							if tangent_attrib:
								var to_ = base_offset + tangent_attrib.offset
								v["tangent"] = Vector4(vertex_buffer.decode_float(to_),
													   vertex_buffer.decode_float(to_ + 4),
													   vertex_buffer.decode_float(to_ + 8),
													   1.0)

							var new_idx: int = bucket["verts"].size()
							old_to_new[old_idx] = new_idx
							bucket["verts"].append(v)

					# Add remapped triangle indices
					# Winding is reversed here (BF2 → Godot)
					bucket["indices"].append(old_to_new[i0])
					bucket["indices"].append(old_to_new[i2])   # swap i1/i2
					bucket["indices"].append(old_to_new[i1])

				# --- Step 3: build an ArrayMesh surface per bucket and store on LodPart ---
				for part_id in buckets.keys():
					var bucket = buckets[part_id]
					var vlist: Array = bucket["verts"]
					var ilist: PackedInt32Array = bucket["indices"]
					if vlist.size() == 0 or ilist.size() == 0: continue

					var vertices  := PackedVector3Array()
					var normals   := PackedVector3Array()
					var uvs       := PackedVector2Array()
					var uv2s      := PackedVector2Array()
					var tangents  := PackedFloat32Array()

					for v in vlist:
						vertices.append(v["pos"])
						if v.has("normal"): normals.append(v["normal"])
						if v.has("uv0"):    uvs.append(v["uv0"])
						if v.has("uv1"):    uv2s.append(v["uv1"])
						if v.has("tangent"):
							var t: Vector4 = v["tangent"]
							tangents.append(t.x); tangents.append(t.y)
							tangents.append(t.z); tangents.append(t.w)

					var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
					arrays[Mesh.ARRAY_VERTEX] = vertices
					arrays[Mesh.ARRAY_INDEX]  = ilist
					if normals.size()  > 0: arrays[Mesh.ARRAY_NORMAL]  = normals
					if uvs.size()      > 0: arrays[Mesh.ARRAY_TEX_UV]  = uvs
					if uv2s.size()     > 0: arrays[Mesh.ARRAY_TEX_UV2] = uv2s
					if tangents.size() > 0: arrays[Mesh.ARRAY_TANGENT] = tangents

					# Ensure the part slot exists (parts_num might be wrong)
					while lod.parts.size() <= part_id:
						lod.parts.append(LodPart.new())

					var lod_part: LodPart = lod.parts[part_id]
					if lod_part.mesh == null:
						lod_part.mesh = ArrayMesh.new()

					lod_part.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					var surf_idx := lod_part.mesh.get_surface_count() - 1
					lod_part.mesh.surface_set_name(surf_idx, mat.technique)
					lod_part.materials.append(mat)

				print("    Mat %d '%s': split into %d part buckets" % [mat_idx, mat.technique, buckets.size()])

	print("=== BundledMesh part splitting complete ===")
