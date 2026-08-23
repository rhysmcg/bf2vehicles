# BF2CollisionMeshParser.gd
# Complete BF2 .collisionmesh file parser for Godot 4
# Based on bf2_collmesh.py Python implementation

extends RefCounted

# Collision types
enum ColType {
	PROJECTILE = 0,
	VEHICLE = 1,
	SOLDIER = 2,
	AI = 3
}

# --- HELPER CLASSES ---

class Vec3:
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	
	func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0):
		x = px
		y = py
		z = pz
	
	static func load(file: FileAccess) -> Vec3:
		var v = Vec3.new()
		v.x = file.get_float()
		v.y = file.get_float()
		v.z = file.get_float()
		return v
	
	func to_vector3() -> Vector3:
		return Vector3(x, y, z)

class Face:
	var verts: PackedInt32Array = PackedInt32Array()  # 3 vertex indices
	var material: int = 0
	
	func _init():
		verts.resize(3)
	
	static func load(file: FileAccess) -> Face:
		var f = Face.new()
		f.verts[0] = file.get_16()
		f.verts[1] = file.get_16()
		f.verts[2] = file.get_16()
		f.material = file.get_16()
		return f

class BSPNode:
	var split_plane_val: float = 0.0
	var split_plane_axis: int = 0  # 0=YZ plane, 1=XZ plane, 2=XY plane
	
	var parent: BSPNode = null
	var children: Array = [null, null]  # front/back
	var faces: Array = [[], []]  # front/back face lists
	
	var _face_refs_idx: Array = [[], []]
	var _children_idx: Array = [null, null]
	
	static func load(file: FileAccess) -> BSPNode:
		var node = BSPNode.new()
		node.split_plane_val = file.get_float()
		var flags: int = file.get_32()
		node.split_plane_axis = flags & 0b11
		
		for i in range(2):
			var is_leaf: bool = bool((4 << i) & flags)
			
			if is_leaf:
				var face_ref_count: int = (flags >> (i * 8 + 16)) & 0xFF
				var face_ref_start: int = file.get_32()
				for j in range(face_ref_count):
					node._face_refs_idx[i].append(face_ref_start + j)
				node._children_idx[i] = null
			else:
				node._children_idx[i] = file.get_32()
		
		return node
	
	func load_children_and_faces(nodes: Array, face_ref_to_face: Dictionary):
		for i in range(2):
			var child_idx = _children_idx[i]
			if child_idx != null:
				children[i] = nodes[child_idx]
				children[i].parent = self
			else:
				for j in _face_refs_idx[i]:
					faces[i].append(face_ref_to_face[j])

class BSP:
	var min: Vec3 = Vec3.new()
	var max: Vec3 = Vec3.new()
	var root: BSPNode = null
	
	static func load(file: FileAccess, col_faces: Array) -> BSP:
		var bsp = BSP.new()
		bsp.min = Vec3.load(file)
		bsp.max = Vec3.load(file)
		
		var node_count: int = file.get_32()
		var nodes: Array = []
		for i in range(node_count):
			nodes.append(BSPNode.load(file))
		
		var face_ref_count: int = file.get_32()
		var face_refs: PackedInt32Array = PackedInt32Array()
		for i in range(face_ref_count):
			face_refs.append(file.get_16())
		
		# Build face reference map
		var face_ref_to_face: Dictionary = {}
		for i in range(face_refs.size()):
			face_ref_to_face[i] = col_faces[face_refs[i]]
		
		# Load children and faces for all nodes
		for node in nodes:
			node.load_children_and_faces(nodes, face_ref_to_face)
		
		# Find root node
		for node in nodes:
			if node.parent == null:
				if bsp.root == null:
					bsp.root = node
				else:
					push_error("BSP: found multiple root nodes")
		
		if bsp.root == null:
			push_error("BSP: root node not found")
		
		return bsp

class Col:
	var col_type: int = ColType.PROJECTILE
	var faces: Array = []  # Array of Face
	var verts: Array = []  # Array of Vec3
	var vert_materials: PackedInt32Array = PackedInt32Array()
	var min: Vec3 = Vec3.new()
	var max: Vec3 = Vec3.new()
	var bsp: BSP = null
	var debug_mesh: PackedInt32Array = PackedInt32Array()
	
	static func load(file: FileAccess, version: Array) -> Col:
		var col = Col.new()
		col.col_type = file.get_32()
		
		# Load faces
		var face_count: int = file.get_32()
		for i in range(face_count):
			col.faces.append(Face.load(file))
		
		# Load vertices
		var vert_count: int = file.get_32()
		for i in range(vert_count):
			col.verts.append(Vec3.load(file))
		
		# Load vertex materials
		col.vert_materials.resize(vert_count)
		for i in range(vert_count):
			col.vert_materials[i] = file.get_16()
		
		# Load bounds
		col.min = Vec3.load(file)
		col.max = Vec3.load(file)
		
		# Load BSP tree if present
		var bsp_present: int = file.get_8()  # ASCII '0' or '1'
		if bsp_present == 0x31:  # ASCII '1'
			col.bsp = BSP.load(file, col.faces)
		
		# Load debug mesh (version 10+)
		if version[0] == 0 and version[1] >= 10:
			var debug_count: int = file.get_32()
			col.debug_mesh.resize(debug_count)
			for i in range(debug_count):
				col.debug_mesh[i] = file.get_32()  # Can be -1
		
		return col

class Geom:
	var cols: Array = []  # Array of Col
	
	static func load(file: FileAccess, version: Array) -> Geom:
		var geom = Geom.new()
		var col_count: int = file.get_32()
		for i in range(col_count):
			geom.cols.append(Col.load(file, version))
		return geom

class GeomPart:
	var geoms: Array = []  # Array of Geom
	
	static func load(file: FileAccess, version: Array) -> GeomPart:
		var part = GeomPart.new()
		var geom_count: int = file.get_32()
		for i in range(geom_count):
			part.geoms.append(Geom.load(file, version))
		return part

# --- MAIN PARSING FUNCTION ---

func parse_collision_mesh(filepath: String) -> Dictionary:
	var collmesh_data = {
		"name": filepath.get_file().get_basename(),
		"geom_parts": [],  # Array of GeomPart
		"version": [0, 0]
	}
	
	if not FileAccess.file_exists(filepath):
		push_error("File not found: %s" % filepath)
		return collmesh_data
	
	print("\n=== Parsing BF2 Collision Mesh: %s ===" % filepath.get_file())
	
	var file: FileAccess = FileAccess.open(filepath, FileAccess.READ)
	if not file:
		push_error("Error opening file: %s" % FileAccess.get_open_error())
		return collmesh_data
	
	file.big_endian = false
	
	# Read version
	var v1: int = file.get_32()
	var v2: int = file.get_32()
	var version: Array = [v1, v2]
	
	collmesh_data.version = version
	print("Version: %d.%d" % [v1, v2])
	
	# Validate version
	if v1 != 0 or v2 < 9 or v2 > 10:
		push_error("Unsupported .collisionmesh version %d.%d" % [v1, v2])
		file.close()
		return collmesh_data
	
	# Load geometry parts
	var geom_part_count: int = file.get_32()
	print("Geometry Parts: %d" % geom_part_count)
	
	for i in range(geom_part_count):
		collmesh_data.geom_parts.append(GeomPart.load(file, version))
	
	# Verify we read the entire file
	if file.get_length() != file.get_position():
		push_warning("File pointer (%d) != file size (%d)" % [file.get_position(), file.get_length()])
	
	file.close()
	
	print("=== Parsing Complete ===\n")
	return collmesh_data

# --- MESH CREATION ---

func create_collision_meshes(parsed_data: Dictionary) -> Array[ArrayMesh]:
	var meshes: Array[ArrayMesh] = []
	
	print("\n=== Creating Collision Meshes ===")
	
	var col_index: int = 0
	
	for part_idx in range(parsed_data.geom_parts.size()):
		var geom_part: GeomPart = parsed_data.geom_parts[part_idx]
		
		for geom_idx in range(geom_part.geoms.size()):
			var geom: Geom = geom_part.geoms[geom_idx]
			
			for col_idx_local in range(geom.cols.size()):
				var col: Col = geom.cols[col_idx_local]
				
				if col.faces.size() == 0 or col.verts.size() == 0:
					print("  col%d: SKIPPED (no geometry)" % col_index)
					col_index += 1
					continue
				
				var mesh := ArrayMesh.new()
				
				# Convert vertices
				var vertices := PackedVector3Array()
				for v in col.verts:
					vertices.append(v.to_vector3())
				
				# Group faces by material
				var material_faces: Dictionary = {}  # material_id -> array of faces
				for face in col.faces:
					if not material_faces.has(face.material):
						material_faces[face.material] = []
					material_faces[face.material].append(face)
				
				# Sort material IDs for consistent ordering
				var material_ids := material_faces.keys()
				material_ids.sort()
				
				print("  col%d (%s): %d verts, %d materials" % [
					col_index,
					_get_col_type_name(col.col_type),
					vertices.size(),
					material_ids.size()
				])
				
				# Create a surface for each material
				var surface_idx := 0
				for mat_id in material_ids:
					var faces_for_mat = material_faces[mat_id]
					
					# Convert faces to indices for this material
					var indices := PackedInt32Array()
					for face in faces_for_mat:
						indices.append(face.verts[0])
						indices.append(face.verts[1])
						indices.append(face.verts[2])
					
					# Generate colors based on material ID
					var color := _get_material_color(mat_id)
					var colors := PackedColorArray()
					colors.resize(vertices.size())
					colors.fill(color)
					
					# Build mesh arrays
					var arrays := []
					arrays.resize(Mesh.ARRAY_MAX)
					arrays[Mesh.ARRAY_VERTEX] = vertices
					arrays[Mesh.ARRAY_INDEX] = indices
					arrays[Mesh.ARRAY_COLOR] = colors
					
					# Add surface
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					mesh.surface_set_name(surface_idx, "material_%d" % mat_id)
					
					print("    Surface %d (material_%d): %d tris, color: %s" % [
						surface_idx,
						mat_id,
						indices.size() / 3,
						color
					])
					
					surface_idx += 1
				
				# Set metadata
				var col_type_name: String = _get_col_type_name(col.col_type)
				mesh.resource_name = "col%d" % [col_index]
				
				print("    Bounds: %s to %s" % [col.min.to_vector3(), col.max.to_vector3()])
				
				meshes.append(mesh)
				
				col_index += 1
	
	print("\n=== Created %d collision meshes ===" % meshes.size())
	return meshes

func _get_col_type_name(col_type: int) -> String:
	match col_type:
		ColType.PROJECTILE: return "projectile"
		ColType.VEHICLE: return "vehicle"
		ColType.SOLDIER: return "soldier"
		ColType.AI: return "ai"
		_: return "unknown"

func _get_material_color(material_id: int) -> Color:
	"""
	Generate distinct colors for each material ID.
	Uses a color palette that's easy to distinguish.
	"""
	var colors := [
		Color(1.0, 0.2, 0.2),  # Red - material 0 (rubber)
		Color(0.7, 0.7, 0.7),  # Gray - material 1 (metal_solid)
		Color(0.4, 0.6, 1.0),  # Light Blue - material 2 (metal_plate_thin)
		Color(0.6, 0.6, 0.5),  # Tan - material 3 (concrete)
		Color(1.0, 0.8, 0.2),  # Yellow - material 4 (plastic)
		Color(0.3, 0.8, 1.0),  # Cyan - material 5 (glass_common)
		Color(0.2, 1.0, 0.3),  # Green - material 6
		Color(1.0, 0.5, 0.0),  # Orange - material 7
		Color(0.8, 0.2, 1.0),  # Purple - material 8
		Color(1.0, 0.4, 0.7),  # Pink - material 9
	]
	
	if material_id < colors.size():
		return colors[material_id]
	else:
		# Generate pseudo-random color for materials beyond our palette
		var hue := fmod(material_id * 0.618033988749895, 1.0)  # Golden ratio for good distribution
		return Color.from_hsv(hue, 0.7, 0.9)


# --- CONVENIENCE FUNCTION ---

func import_collision_mesh(filepath: String) -> Array[ArrayMesh]:
	"""
	One-shot function to parse and create meshes in one call.
	Returns an array of ArrayMesh instances.
	"""
	var parsed_data = parse_collision_mesh(filepath)
	if parsed_data.geom_parts.size() == 0:
		return []
	return create_collision_meshes(parsed_data)
