# MeshParser.gd

# Class for handling BF2 .staticmesh file parsing
# Attach this script to a Node or autoload it.
extends RefCounted

# Add this helper function to your BF2MeshParser class (before parse_bf2_mesh)
func _get_attrib_by_usage(attribs: Array, usage_id: int) -> BF2VertexAttribute:
	for attrib in attribs:
		if attrib is BF2VertexAttribute and attrib.usage == usage_id:
			return attrib
	return null # Returns null if not found
	
	

const MAX_15B = 1 << 15
const MAX_16B = 1 << 16
func unsigned16_to_signed(unsigned):
	return (unsigned + MAX_15B) % MAX_16B - MAX_15B
	


# --- CONSTANTS ---
# D3DDECLTYPE (4 bytes/float size)
const TYPE_FLOAT2 = 1
const TYPE_FLOAT3 = 2
const TYPE_FLOAT4 = 3

# D3DDECLUSAGE (Vertex Attribute Usages)
const USAGE_POSITION = 0
const USAGE_NORMAL = 3
const USAGE_TEXCOORD0 = 5 # UV1
# ... other usages ...

# Helper class to store vertex attribute details
class BF2VertexAttribute:
	var flag: int
	var offset: int # Byte offset within the vertex stride
	var vartype: int
	var usage: int


# Helper function for reading VB6-style strings (Long length + ASCII bytes)
func _read_vb6_string(file: FileAccess) -> String:
	# Reads a 4-byte length (Long, unsigned 32-bit integer)
	var length: int = file.get_32()
	
	if length > 0:
		# Reads the raw string bytes
		var data_buffer: PackedByteArray = file.get_buffer(length)
		# Decode and remove null terminator (if present)
		var result_string: String = data_buffer.get_string_from_ascii().trim_suffix("\\0")
		return result_string
		
	return ""


# Main function to parse the mesh file
func parse_bf2_mesh(filepath: String) -> Dictionary:
	var mesh_data = {}
	
	if not FileAccess.file_exists(filepath):
		print("File not found: %s" % filepath)
		return mesh_data

	print("--- Parsing BF2 Static Mesh: %s ---" % filepath.get_file())
	
	# 1. Open the file
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		print("Error opening file: %s" % FileAccess.get_open_error())
		return mesh_data

	# Set byte order to Little-Endian (Crucial step!)
	# file.set_endian_mode(FileAccess.ENDIAN_LITTLE)
	file.big_endian = false
	# --- 1. HEADER (bf2head) - 20 bytes ---
	# Struct: <5I (u1, version, u3, u4, u5)
	
	print("File at: %d" % file.get_position)
	
	# Read 5 Longs (unsigned 32-bit integers) sequentially
	var head_u1: int = file.get_32()
	var head_version: int = file.get_32()
	var head_u3: int = file.get_32()
	var head_u4: int = file.get_32()
	var head_u5: int = file.get_32()
	
	print("File Version: %d" % head_version)
	file.get_8() # Reads one byte

	# --- 2. GEOM TABLE (geomnum + list of lodnums) ---
	var geom_num: int = file.get_32()
	print("Geometry Count: %d" % geom_num)
	
	var lod_nums: Array[int] = []
	for i in range(geom_num):
		var lod_num: int = file.get_32()
		lod_nums.append(lod_num)
		print("  Geom %d has %d LODs." % [i, lod_num])

	# --- 3. VERTEX ATTRIBUTE TABLE (bf2vertattrib) ---
	var vert_attrib_num: int = file.get_32()
	var vert_attribs: Array[BF2VertexAttribute] = []
	
	# Struct: <4h (flag, offset, vartype, usage) - 8 bytes
	for i in range(vert_attrib_num):
		var attrib = BF2VertexAttribute.new()
		# Read 4 Integers (signed 16-bit integers) sequentially
		attrib.flag = unsigned16_to_signed(file.get_16())
		attrib.offset = unsigned16_to_signed(file.get_16())
		attrib.vartype = unsigned16_to_signed(file.get_16())
		attrib.usage = unsigned16_to_signed(file.get_16())
		
		vert_attribs.append(attrib)
		
		if attrib.usage == USAGE_POSITION:
			print("  Position Attrib: Offset=%d bytes" % attrib.offset)
	
	# --- 4. VERTICES (vert_format, vert_stride, vert_num) ---
	var vert_format: int = file.get_32() # Should be 4 (size of a Single/Float)
	var vert_stride: int = file.get_32() # Total size of one vertex
	var vert_num: int = file.get_32()
	print("\nVertices: %d, Stride: %d bytes" % [vert_num, vert_stride])
	
	var total_bytes: int = vert_stride * vert_num
	
	# The vertex buffer is read as a single raw buffer
	var vertex_buffer: PackedByteArray = file.get_buffer(total_bytes)
	
	# We will use this list later to populate a Mesh
	var vertices: PackedVector3Array = PackedVector3Array()
	var uv_coords: PackedVector2Array = PackedVector2Array()

	# Find the byte offsets for Position and UV0
	##var pos_attrib: BF2VertexAttribute = vert_attribs.find(func(a): return a.usage == USAGE_POSITION)
	#var uv0_attrib: BF2VertexAttribute = vert_attribs.find(func(a): return a.usage == USAGE_TEXCOORD0)
	#var pos_attrib: int = vert_attribs.find(func(a): return a.usage == USAGE_POSITION)
	#var uv0_attrib: int = vert_attribs.find(func(a): return a.usage == USAGE_TEXCOORD0)
	var pos_attrib: BF2VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_POSITION)
	var uv0_attrib: BF2VertexAttribute = _get_attrib_by_usage(vert_attribs, USAGE_TEXCOORD0)
		
	if pos_attrib != null:
		# Loop through the raw buffer to extract data
		for i in range(vert_num):
			var base_offset: int = i * vert_stride
			
			# --- Extract Position (XYZ) ---
			#var pos_offset: int = base_offset + vert_attribs[pos_attrib].offset
			var pos_offset: int = base_offset + pos_attrib.offset
			# Use decode_float() to manually convert 4 bytes starting at pos_offset
			var x: float = vertex_buffer.decode_float(pos_offset)
			var y: float = vertex_buffer.decode_float(pos_offset + 4)
			var z: float = vertex_buffer.decode_float(pos_offset + 8)
			vertices.append(Vector3(x, y, z))

			# --- Extract UV0 (U, V) ---
			if uv0_attrib != null:
				#var uv_offset: int = base_offset + vert_attribs[uv0_attrib].offset
				var uv_offset: int = base_offset + uv0_attrib.offset
				var u: float = vertex_buffer.decode_float(uv_offset)
				var v: float = vertex_buffer.decode_float(uv_offset + 4)
				uv_coords.append(Vector2(u, v))
			
			if i < 3:
				print("  Vertex %d: X=%0.4f, Y=%0.4f, Z=%0.4f" % [i, x, y, z])
				
	# --- 5. INDICES (indexnum) ---
	var index_num: int = file.get_32()
	# Indices are 'Integer' (2 bytes / unsigned 16-bit integer)
	var indices_bytes: PackedByteArray = file.get_buffer(index_num * 2)
	var indices: PackedInt32Array = PackedInt32Array()
	
	# Manually unpack the 2-byte indices into a list of 32-bit integers
	for i in range(0, indices_bytes.size(), 2):
		# We read two bytes and interpret them as an unsigned 16-bit value
		var index: int = indices_bytes.decode_u16(i)
		indices.append(index)
		
	print("\nIndex Count: %d" % index_num)
	print("First 10 Indices: %s..." % indices.slice(0, 9))
	
	# --- 6. LOD and Material Data (Skipping raw parsing of material data for brevity) ---
	
	# Skip unknown u2 (4 bytes)
	file.get_32()
	
	var materials: Array = []
	for i in range(geom_num):
		for j in range(lod_nums[i]):
			
			# Skip Bounds (6 floats / 24 bytes)
			file.get_buffer(24) 
			
			if head_version <= 6:
				# Skip Pivot/Unknown (3 floats / 12 bytes)
				file.get_buffer(12)
			
			# Nodes (nodenum + matrix array)
			var nodenum: int = file.get_32()
			# Skip matrices (nodenum * 64 bytes)
			file.get_buffer(nodenum * 64)
			
			# ReadGeomLod (Material Groups)
			var mat_num: int = file.get_32()
			for k in range(mat_num):
				var material_entry = {}
				
				# alphamode (4 bytes)
				material_entry.alphamode = file.get_32()
				
				# fxfile (string)
				material_entry.fxfile = _read_vb6_string(file)
				
				# technique (string/material name)
				material_entry.technique = _read_vb6_string(file)
				
				# mapnum (4 bytes)
				var map_num: int = file.get_32()
				
				# Textures/Maps
				material_entry.textures = []
				for m in range(map_num):
					var map_name: String = _read_vb6_string(file)
					material_entry.textures.append(map_name)
				
				# Geometry Info (vstart, istart, inum, vnum) - 4 Longs (16 bytes)
				material_entry.vstart = file.get_32()
				material_entry.istart = file.get_32()
				material_entry.inum = file.get_32()
				material_entry.vnum = file.get_32()

				# Unknown u4, u5 (8 bytes)
				file.get_buffer(8)
				
				# Per-material bounds (mmin, mmax) - 6 floats (24 bytes)
				file.get_buffer(24) 
				
				materials.append(material_entry)
				
	file.close()
	
	mesh_data.vertices = vertices
	mesh_data.indices = indices
	mesh_data.uvs = uv_coords
	mesh_data.materials = materials
	
	print(mesh_data)
	return mesh_data
	
	
	
func create_array_mesh(parsed_data: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var all_vertices: PackedVector3Array = parsed_data.vertices
	var all_indices: PackedInt32Array = parsed_data.indices
	var all_uvs: PackedVector2Array = parsed_data.uvs
	var materials_data: Array = parsed_data.materials

	# Debug: show global vertex/index counts
	print("DEBUG: total vertices =", all_vertices.size(), " total indices =", all_indices.size())

	for mat_group in materials_data:
		var vstart: int = mat_group.vstart
		var vnum: int = mat_group.vnum
		var istart: int = mat_group.istart
		var inum: int = mat_group.inum

		if inum == 0 or vnum == 0:
			continue

		# Validate bounds first (print warnings if out-of-range)
		if vstart < 0 or vstart + vnum > all_vertices.size():
			push_warning("Material vstart/vnum out of range: vstart=%d vnum=%d total_vertices=%d" % [vstart, vnum, all_vertices.size()])

		if istart < 0 or istart + inum > all_indices.size():
			push_warning("Material istart/inum out of range: istart=%d inum=%d total_indices=%d" % [istart, inum, all_indices.size()])

		# --- 1. Copy vertices and uvs for this material (explicit loop to avoid slice ambiguity) ---
		var subset_vertices := PackedVector3Array()
		for i in range(vnum):
			var gv := all_vertices[vstart + i]
			subset_vertices.append(gv)

		var subset_uvs := PackedVector2Array()
		if all_uvs.size() > 0:
			for i in range(vnum):
				# defensively check uv array size
				if vstart + i < all_uvs.size():
					subset_uvs.append(all_uvs[vstart + i])
				else:
					subset_uvs.append(Vector2.ZERO)

		# --- 2. Collect raw global indices for this material and filter them ---
		var raw_global_indices := []
		var global_max := vstart + vnum - 1
		var global_min := vstart

		# iterate index zone [istart, istart+inum)
		var idx_end := istart + inum
		if idx_end > all_indices.size():
			idx_end = all_indices.size()

		for gi in range(istart, idx_end):
			var gindex: int = all_indices[gi]
			# accept only indices that fall within this material's vertex range
			if gindex >= global_min and gindex <= global_max:
				raw_global_indices.append(gindex)
			# else: ignore sentinel/strip/restart/out-of-range indices

		# Trim to multiple of 3 (each triangle needs 3 indices)
		var trim_len := raw_global_indices.size() - (raw_global_indices.size() % 3)
		if trim_len != raw_global_indices.size():
			# warn that we trimmed
			print("DEBUG: trimmed indices for material from %d to %d (must be multiple of 3)" % [raw_global_indices.size(), trim_len])
			raw_global_indices.resize(trim_len)

		# --- 3. Re-index to local (0..vnum-1) and build PackedInt32Array ---
		var subset_indices_local := PackedInt32Array()
		for gindex in raw_global_indices:
			var lindex: int = gindex - vstart
			# (sanity clamp -- should never happen because we filtered)
			if lindex < 0:
				lindex = 0
			elif lindex >= vnum:
				lindex = vnum - 1
			subset_indices_local.append(lindex)

		# Final safety check: indices should be within [0, vnum-1]
		for i in subset_indices_local:
			if i < 0 or i >= vnum:
				push_error("Final local index out of range: %d (vnum=%d)" % [i, vnum])
				# continue still, but this indicates a parsing bug

		# --- 4. Build arrays for ArrayMesh ---
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = subset_vertices
		arrays[Mesh.ARRAY_INDEX] = subset_indices_local
		if subset_uvs.size() > 0:
			arrays[Mesh.ARRAY_TEX_UV] = subset_uvs

		# Create surface
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		# (Optional) you could set material on the surface here using mesh.surface_set_material(...)
		# but that's separate and depends on your material creation code.

	return mesh
