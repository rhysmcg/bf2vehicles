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

# EXPERIMENTAL TOGGLE: if skinned meshes deform wildly at bones with large rest-pose
# rotations (e.g. shoulders/torso) while bones with near-identity rotation (legs) look
# fine, the stored rig matrix may be the FORWARD bind transform (bone's placement in
# mesh space) rather than the INVERSE bind transform Godot's Skin.set_bind_pose()
# expects - causing the bone's rotation to effectively be applied twice at render time.
# Flip this to true and re-test if that symptom appears.
const SKIN_BIND_MATRIX_NEEDS_INVERSION := true

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

class Lod:
	var materials: Array = []       # Array of BF2Material
	var min_bounds: Vector3 = Vector3.ZERO
	var max_bounds: Vector3 = Vector3.ZERO
	# SkinnedMesh only: Array of rigs, one per material (same order), each rig is an
	# Array of {"id": int, "matrix": Array[16]} dicts - a per-material bone palette.
	var rigs: Array = []

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
			# Single stored weight - meaning unconfirmed (could be a 2-bone blend
			# remainder, or simply unused/always-1.0). Defaulting to full weight on
			# blend-index[0] only, until confirmed otherwise against a working import.
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
	
	# --- 2. GEOMETRY TABLE ---
	var geom_count: int = file.get_32()
	print("Geometry Count: %d" % geom_count)
	
	var lod_counts: Array[int] = []
	for i in range(geom_count):
		var lod_count: int = file.get_32()
		lod_counts.append(lod_count)
		print("  Geom %d: %d LODs" % [i, lod_count])
	
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
			
			print("  Reading bounds for Geom %d LOD %d (file pos: %d)" % [i, j, file.get_position()])
			
			lod.min_bounds = _read_vec3(file)
			lod.max_bounds = _read_vec3(file)
			
			print("    Bounds: min=%s, max=%s" % [lod.min_bounds, lod.max_bounds])
			
			if version <= 6:
				_read_vec3(file)  # old-format pivot
			
			if is_staticmesh:
				var parts_count: int = file.get_32()
				print("    Parts (matrices): %d" % parts_count)
				for p in range(parts_count):
					file.get_buffer(64)
			elif is_bundledmesh:
				var parts_num: int = file.get_32()
				print("    Parts num: %d" % parts_num)
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
				
				if is_staticmesh and version == 11:
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
# "skin" is non-null only for SkinnedMesh LODs that carry rig (bone palette) data.
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
			
			var mesh := ArrayMesh.new()
			var surface_count := 0
			
			print("  Geom %d LOD %d: %d materials" % [geom_idx, lod_idx, lod.materials.size()])
			
			# --- STEP 1: build a unified skin bind list for this LOD, merging every
			# material's local bone palette (rig) into one shared list. Godot's Skin
			# resource is per-MeshInstance3D (shared across all surfaces), unlike BF2's
			# per-material palettes, so this remap is required.
			var has_skin: bool = lod.rigs.size() > 0
			var unified_bone_ids: Array = []            # ordered list of skeleton bone ids
			var unified_bind_slot: Dictionary = {}        # skeleton_bone_id -> unified slot idx
			var unified_bind_matrix: Dictionary = {}      # skeleton_bone_id -> Array[16] (bind matrix)
			
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
				
				if mat.vstart + mat.vnum > parsed_data.vertex_count:
					push_error("Material vertex range out of bounds: vstart=%d vnum=%d total=%d" % [mat.vstart, mat.vnum, parsed_data.vertex_count])
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
				var custom0s := PackedColorArray()
				var custom1s := PackedColorArray()
				var tangents := PackedFloat32Array()
				var bone_ids_arr := PackedInt32Array()
				var bone_weights_arr := PackedFloat32Array()
				
				for i in range(mat.vnum):
					var vert_idx: int = mat.vstart + i
					var base_offset: int = vert_idx * vertex_stride
					
					var pos_offset: int = base_offset + pos_attrib.offset
					var x: float = vertex_buffer.decode_float(pos_offset)
					var y: float = vertex_buffer.decode_float(pos_offset + 4)
					var z: float = vertex_buffer.decode_float(pos_offset + 8)
					vertices.append(Vector3(x, y, z))
					
					if normal_attrib:
						var norm_offset: int = base_offset + normal_attrib.offset
						var nx: float = vertex_buffer.decode_float(norm_offset)
						var ny: float = vertex_buffer.decode_float(norm_offset + 4)
						var nz: float = vertex_buffer.decode_float(norm_offset + 8)
						normals.append(Vector3(nx, ny, nz))
					
					if uv0_attrib:
						var uv_offset: int = base_offset + uv0_attrib.offset
						var u: float = vertex_buffer.decode_float(uv_offset)
						var v: float = vertex_buffer.decode_float(uv_offset + 4)
						uvs.append(Vector2(u, v))
					
					if uv1_attrib:
						var uv2_offset: int = base_offset + uv1_attrib.offset
						var u2: float = vertex_buffer.decode_float(uv2_offset)
						var v2: float = vertex_buffer.decode_float(uv2_offset + 4)
						uv2s.append(Vector2(u2, v2))
					
					if uv2_attrib or uv3_attrib or uv4_attrib:
						var uv3_u := 0.0
						var uv3_v := 0.0
						var uv4_u := 0.0
						var uv4_v := 0.0
						var uv5_u := 0.0
						var uv5_v := 0.0
						
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
						
						custom0s.append(Color(uv3_v, uv3_u, uv4_v, uv4_u))
						custom1s.append(Color(uv5_v, uv5_u, 0.0, 0.0))
					
					if tangent_attrib:
						var tan_offset: int = base_offset + tangent_attrib.offset
						var tx: float = vertex_buffer.decode_float(tan_offset)
						var ty: float = vertex_buffer.decode_float(tan_offset + 4)
						var tz: float = vertex_buffer.decode_float(tan_offset + 8)
						tangents.append(tx)
						tangents.append(ty)
						tangents.append(tz)
						tangents.append(1.0)
					
					# --- STEP 1 (per-vertex): decode blend indices/weights, remap
					# this material's local palette index into the unified LOD bind list.
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
							final_weights[0] = 1.0  # fallback: fully bound to slot 0
						
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
				
				if normals.size() > 0:
					arrays[Mesh.ARRAY_NORMAL] = normals
				
				if uvs.size() > 0:
					arrays[Mesh.ARRAY_TEX_UV] = uvs
				
				if uv2s.size() > 0:
					arrays[Mesh.ARRAY_TEX_UV2] = uv2s
				
				if custom0s.size() > 0:
					arrays[Mesh.ARRAY_CUSTOM0] = custom0s
				
				if custom1s.size() > 0:
					arrays[Mesh.ARRAY_CUSTOM1] = custom1s
				
				if tangents.size() > 0:
					arrays[Mesh.ARRAY_TANGENT] = tangents
				
				if has_skin and bone_ids_arr.size() > 0:
					arrays[Mesh.ARRAY_BONES] = bone_ids_arr
					arrays[Mesh.ARRAY_WEIGHTS] = bone_weights_arr
				
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				
				var surface_idx = mesh.get_surface_count() - 1
				mesh.surface_set_name(surface_idx, mat.technique)
				
				surface_count += 1
				print("    Material %d '%s': OK - %d verts, %d tris" % [mat_idx, mat.technique, vertices.size(), tri_count])
			
			# --- STEP 1 (finalize): build the unified Skin resource for this LOD, if any.
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
	
	print("\n=== Created %d total meshes ===" % meshes.size())
	return meshes
