# MeshParser.gd
# Complete BF2 .staticmesh file parser for Godot 4
# Based on bf2-blender Python implementation

extends RefCounted

# --- CONSTANTS ---
# D3DDECLTYPE (vertex attribute data types)
const TYPE_FLOAT1 = 0
const TYPE_FLOAT2 = 1
const TYPE_FLOAT3 = 2
const TYPE_FLOAT4 = 3
const TYPE_D3DCOLOR = 4
const TYPE_UBYTE4 = 5
const TYPE_SHORT2 = 6
const TYPE_SHORT4 = 7
const TYPE_UNUSED = 17

# D3DDECLUSAGE (vertex attribute semantic usage)
const USAGE_POSITION = 0
const USAGE_BLENDWEIGHT = 1
const USAGE_BLENDINDICES = 2
const USAGE_NORMAL = 3
const USAGE_PSIZE = 4
const USAGE_TEXCOORD0 = 5
const USAGE_TANGENT = 6
const USAGE_BINORMAL = 7
const USAGE_TEXCOORD1 = (1 << 8) | 5  # 261
const USAGE_TEXCOORD2 = (2 << 8) | 5  # 517
const USAGE_TEXCOORD3 = (3 << 8) | 5  # 773
const USAGE_TEXCOORD4 = (4 << 8) | 5  # 1029

# D3DPRIMITIVETYPE
const PRIMITIVE_TRIANGLELIST = 4
const PRIMITIVE_TRIANGLESTRIP = 5

# Vertex Attribute flags
const ATTRIB_USED = 0
const ATTRIB_UNUSED = 255

# Alpha modes for materials
enum AlphaMode {
	NONE = 0,
	ALPHA_BLEND = 1,
	ALPHA_TEST = 2
}

# --- HELPER CLASSES ---

class VertexAttribute:
	var flag: int = 0
	var offset: int = 0  # Byte offset within vertex stride
	var vartype: int = 0  # D3DDECLTYPE
	var usage: int = 0    # D3DDECLUSAGE
	
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
	var maps: Array = []  # Texture paths (untyped to avoid errors)
	
	# Geometry data
	var vstart: int = 0   # Vertex buffer start index
	var istart: int = 0   # Index buffer start index
	var inum: int = 0     # Number of indices
	var vnum: int = 0     # Number of vertices
	
	# Material bounds
	var min_bounds: Vector3 = Vector3.ZERO
	var max_bounds: Vector3 = Vector3.ZERO
	
	# Unknowns
	var u4: int = 0
	var u5: int = 0

class Lod:
	var materials: Array = []  # Array of BF2Material (untyped)
	var min_bounds: Vector3 = Vector3.ZERO
	var max_bounds: Vector3 = Vector3.ZERO

class Geom:
	var lods: Array = []  # Array of Lod (untyped)

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
		return data_buffer.get_string_from_ascii().rstrip("\\x00")
	return ""

func _read_vec3(file: FileAccess) -> Vector3:
	var x: float = file.get_float()
	var y: float = file.get_float()
	var z: float = file.get_float()
	return Vector3(x, y, z)

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
		"version": 0
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return mesh_data

	print("\n=== Parsing BF2 Static Mesh: %s ===" % filepath.get_file())
	
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
	print("Version: %d" % version)
	
	# --- 2. GEOMETRY TABLE ---
	var geom_count: int = file.get_32()
	print("Geometry Count: %d" % geom_count)
	
	var lod_counts: Array[int] = []
	for i in range(geom_count):
		var lod_count: int = file.get_32()
		lod_counts.append(lod_count)
		print("  Geom %d: %d LODs" % [i, lod_count])
	
	# Create geom structure
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
	
	# Remove last unused attribute if present
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
	
	# --- 7. ALPHA BLEND INDEX NUMBER (for StaticMesh) ---
	var alpha_blend_indexnum: int = file.get_32()
	print("Alpha blend index num: %d" % alpha_blend_indexnum)
	
	# --- 8. LOD BOUNDS, PARTS, AND MATERIALS ---
	print("\nProcessing LODs:")
	print("File position before LOD processing: %d / %d bytes" % [file.get_position(), file.get_length()])
	
	# First pass: Read all LOD bounds and parts
	for i in range(geom_count):
		var geom = mesh_data.geoms[i]
		
		for j in range(lod_counts[i]):
			var lod = geom.lods[j]
			
			print("  Reading bounds for Geom %d LOD %d (file pos: %d)" % [i, j, file.get_position()])
			
			# Read LOD bounds
			lod.min_bounds = _read_vec3(file)
			lod.max_bounds = _read_vec3(file)
			
			print("    Bounds: min=%s, max=%s" % [lod.min_bounds, lod.max_bounds])
			
			# Old format pivot/unknown
			if version <= 6:
				_read_vec3(file)  # Skip pivot
			
			# Read parts (matrices) - StaticMesh specific
			var parts_count: int = file.get_32()
			print("    Parts (matrices): %d" % parts_count)
			# Skip matrices (64 bytes each = 16 floats)
			for p in range(parts_count):
				file.get_buffer(64)
	
	# Second pass: Read all materials
	print("\nProcessing Materials:")
	for i in range(geom_count):
		var geom = mesh_data.geoms[i]
		
		for j in range(lod_counts[i]):
			var lod = geom.lods[j]
			
			print("  Processing materials for Geom %d LOD %d (file pos: %d)" % [i, j, file.get_position()])
			
			# --- READ MATERIALS ---
			var mat_count: int = file.get_32()
			print("    Materials: %d (file pos: %d)" % [mat_count, file.get_position()])
			
			# Safety check for unreasonable material counts
			if mat_count < 0 or mat_count > 100:
				push_error("Unreasonable material count: %d at position %d" % [mat_count, file.get_position()])
				file.close()
				return mesh_data
			
			for k in range(mat_count):
				var mat = BF2Material.new()
				
				print("      Reading material %d (file pos: %d)" % [k, file.get_position()])
				
				# Alpha mode
				mat.alpha_mode = file.get_32()
				
				# Shader info
				mat.fxfile = _read_vb6_string(file)
				mat.technique = _read_vb6_string(file)
				
				# Textures
				var map_count: int = file.get_32()
				
				# Safety check for unreasonable map counts
				if map_count < 0 or map_count > 20:
					push_error("Unreasonable map count: %d at position %d" % [map_count, file.get_position()])
					file.close()
					return mesh_data
				
				for m in range(map_count):
					mat.maps.append(_read_vb6_string(file))
				
				# Geometry info
				mat.vstart = file.get_32()
				mat.istart = file.get_32()
				mat.inum = file.get_32()
				mat.vnum = file.get_32()
				
				# Unknowns
				mat.u4 = file.get_32()
				mat.u5 = file.get_32()
				
				# Material bounds (version 11 only for StaticMesh)
				if version == 11:
					mat.min_bounds = _read_vec3(file)
					mat.max_bounds = _read_vec3(file)
				
				
				
				
				
				lod.materials.append(mat)
				
				print("      [%d] '%s' - verts:%d (start:%d), indices:%d (start:%d), alpha:%d" % 
					  [k, mat.technique, mat.vnum, mat.vstart, mat.inum, mat.istart, mat.alpha_mode])
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

func create_array_meshes(parsed_data: Dictionary) -> Array[ArrayMesh]:
	var meshes: Array[ArrayMesh] = []
	
	var vertex_buffer: PackedByteArray = parsed_data.vertex_buffer
	var index_buffer: PackedInt32Array = parsed_data.index_buffer
	var vertex_stride: int = parsed_data.vertex_stride
	var vert_attribs: Array = parsed_data.vertex_attributes
	
	# Find attribute offsets
	var pos_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_POSITION)
	var normal_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_NORMAL)
	var uv0_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD0)
	var uv1_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD1)
	var uv2_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD2)
	var uv3_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD3)
	var uv4_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD4)
	var tangent_attrib: VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TANGENT)
	
	if not pos_attrib:
		push_error("No position attribute found!")
		return meshes
	
	print("\n=== Creating Meshes ===")
	
	# Create one mesh per Geom/LOD combination
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			
			if lod.materials.size() == 0:
				continue
			
			var mesh := ArrayMesh.new()
			var surface_count := 0
			
			print("  Geom %d LOD %d: %d materials" % [geom_idx, lod_idx, lod.materials.size()])
			
			for mat_idx in range(lod.materials.size()):
				var mat = lod.materials[mat_idx]
				
				if mat.vnum == 0 or mat.inum == 0:
					print("    Material %d '%s': SKIPPED (vnum=%d, inum=%d)" % [mat_idx, mat.technique, mat.vnum, mat.inum])
					continue
				
				# Validate ranges
				if mat.vstart + mat.vnum > parsed_data.vertex_count:
					push_error("Material vertex range out of bounds: vstart=%d vnum=%d total=%d" % [mat.vstart, mat.vnum, parsed_data.vertex_count])
					continue
				
				if mat.istart + mat.inum > index_buffer.size():
					push_error("Material index range out of bounds: istart=%d inum=%d total=%d" % [mat.istart, mat.inum, index_buffer.size()])
					continue
				
				# Extract vertex data for this material's DECLARED vertex range
				var vertices := PackedVector3Array()
				var normals := PackedVector3Array()
				var uvs := PackedVector2Array()
				var uv2s := PackedVector2Array()  # Detail UVs
				var custom0s := PackedColorArray()  # UV3 and UV4 packed
				var custom1s := PackedColorArray()  # UV5 (and UV6 if needed)
				var tangents := PackedFloat32Array()
				
				for i in range(mat.vnum):
					var vert_idx: int = mat.vstart + i
					var base_offset: int = vert_idx * vertex_stride
					
					# Position
					var pos_offset: int = base_offset + pos_attrib.offset
					var x: float = vertex_buffer.decode_float(pos_offset)
					var y: float = vertex_buffer.decode_float(pos_offset + 4)
					var z: float = vertex_buffer.decode_float(pos_offset + 8)
					vertices.append(Vector3(x, y, z))
					
					# Normal
					if normal_attrib:
						var norm_offset: int = base_offset + normal_attrib.offset
						var nx: float = vertex_buffer.decode_float(norm_offset)
						var ny: float = vertex_buffer.decode_float(norm_offset + 4)
						var nz: float = vertex_buffer.decode_float(norm_offset + 8)
						normals.append(Vector3(nx, ny, nz))
					
					# UV0 (Base texture)
					if uv0_attrib:
						var uv_offset: int = base_offset + uv0_attrib.offset
						var u: float = vertex_buffer.decode_float(uv_offset)
						var v: float = vertex_buffer.decode_float(uv_offset + 4)
						uvs.append(Vector2(u, v))
					
					# UV1 (Detail texture - maps to UV2 in Godot)
					if uv1_attrib:
						var uv2_offset: int = base_offset + uv1_attrib.offset
						var u2: float = vertex_buffer.decode_float(uv2_offset)
						var v2: float = vertex_buffer.decode_float(uv2_offset + 4)
						uv2s.append(Vector2(u2, v2))
					
					# Tangent
					if tangent_attrib:
						var tan_offset: int = base_offset + tangent_attrib.offset
						var tx: float = vertex_buffer.decode_float(tan_offset)
						var ty: float = vertex_buffer.decode_float(tan_offset + 4)
						var tz: float = vertex_buffer.decode_float(tan_offset + 8)
						tangents.append(tx)
						tangents.append(ty)
						tangents.append(tz)
						tangents.append(1.0)
				
				# Extract indices - they are ALREADY local to this material!
				var local_indices := PackedInt32Array()
				
				for i in range(mat.inum):
					if mat.istart + i >= index_buffer.size():
						break
					
					var idx: int = index_buffer[mat.istart + i]
					
					# Validate range (should be 0 to vnum-1)
					if idx < 0 or idx >= mat.vnum:
						if i < 10:  # Only log first 10 to avoid spam
							print("      WARNING: Index %d: value=%d (out of range 0-%d)" % [i, idx, mat.vnum - 1])
					
					local_indices.append(idx)
				
				# Reverse winding order for Godot (BF2 uses opposite winding)
				for i in range(0, local_indices.size() - 2, 3):
					var temp = local_indices[i + 1]
					local_indices[i + 1] = local_indices[i + 2]
					local_indices[i + 2] = temp
				
				# Ensure we have complete triangles
				var remainder := local_indices.size() % 3
				if remainder != 0:
					local_indices.resize(local_indices.size() - remainder)
				
				if local_indices.size() == 0 or vertices.size() == 0:
					print("    Material %d '%s': SKIPPED (no valid triangles)" % [mat_idx, mat.technique])
					continue
				
				var tri_count := local_indices.size() / 3
				
				# Build ArrayMesh surface
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = vertices
				arrays[Mesh.ARRAY_INDEX] = local_indices
				
				if normals.size() > 0:
					arrays[Mesh.ARRAY_NORMAL] = normals
				
				if uvs.size() > 0:
					arrays[Mesh.ARRAY_TEX_UV] = uvs
				
				if uv2s.size() > 0:
					arrays[Mesh.ARRAY_TEX_UV2] = uv2s  # Detail UVs
				
				if tangents.size() > 0:
					arrays[Mesh.ARRAY_TANGENT] = tangents
				
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				
				# Store material metadata in mesh
				var surface_idx = mesh.get_surface_count() - 1
				mesh.surface_set_name(surface_idx, mat.technique)
				
				surface_count += 1
				print("    Material %d '%s': OK - %d verts, %d tris" % [mat_idx, mat.technique, vertices.size(), tri_count])
			
			if mesh.get_surface_count() > 0:
				meshes.append(mesh)
				print("  → Created mesh with %d surfaces" % surface_count)
	
	print("\n=== Created %d total meshes ===" % meshes.size())
	return meshes
