@tool
extends Node3D

@export_category("Terrain Import Settings")
@export var file_path = "res://Levels/Strike_at_Karkand/HeightmapPrimary.raw"
@export var input_size_x = 512
@export var input_size_y = 512
@export var input_height_scale = 0.00457764
@export var terrain_scale = 2.0
@export var PATCH_SIZE = 128
@export var water_level = 146
@export_tool_button("Generate Heightmap", "MeshInstance3D") var heightmap_action = generate_heightmap


@export_category("Static Object Import Settings")
@export var static_object_files = "res://Levels/Strike_at_Karkand/StaticObjects.con"
@export var createStaticScenes : bool = false
@export_tool_button("Load Static Objects", "Node3D") var staticobject_action = load_staticobjects

#@export_category("Terrain Collision")
#@export_tool_button("Create Collision", "CollisionObject3D") var createCollision_action = createCollision



const MAX_RAW_HEIGHT = 65535
const BYTES_PER_PIXEL = 2.0


## Default Value is apparently 163.84 * 0.00457764 = 0.75000054 (*100)
## Water = 146
var height_scale = input_height_scale * MAX_RAW_HEIGHT
var size_x = input_size_x + 1
var size_y = input_size_x + 1

# Store ALL height data for collision
var all_height_data: PackedFloat32Array = PackedFloat32Array()


func convert_bf2_rotation(rotations):
	
	print("Rotating to bf2")
	var A = rotations.x
	var P = rotations.y
	var R = rotations.z
	#var roll_offset_degrees = 90
	var x = P               # pitch
	var y = -A - 180         # yaw
	var z = -R              # roll
	return Vector3(x, y, z) # Godot rotation_degrees


func _cleanup_children() -> void:
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()
			await get_tree().process_frame

func generate_heightmap():

	
	var detailMaps = get_detail_textures("res://Levels/Strike_at_Karkand/terraindata.raw")
	
	
	## Set the scales, Add a pixel to each size x and y


		
	
	
	# RESET ALL SCALE, POSITION AND ROTATION
	position.x = 0
	position.y = -1 * height_scale
	position.z = 0
	
	scale = Vector3.ONE
	rotation_degrees = Vector3.ZERO


	# 1. Open the RAW file
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("ERROR: Failed to open file: %s" % file_path)
		return
	file.big_endian = false
	
	var expected_size = size_x * size_y * BYTES_PER_PIXEL
	if file.get_length() < expected_size:
		print("ERROR: File size mismatch. Expected: %d bytes. Got: %d bytes. Check size_x/size_y." % [expected_size, file.get_length()])
		return
	var buffer: PackedByteArray = file.get_buffer(expected_size)
	file.close()
	
	print("File loaded successfully. Starting mesh generation...")
	

	await _cleanup_children()
	all_height_data.clear()
	all_height_data.resize((size_x * terrain_scale) * (size_y * terrain_scale))
	

	
	var num_chunks_x: int = size_x / (PATCH_SIZE - 1)
	var num_chunks_y: int = size_y / (PATCH_SIZE - 1)

	# Loop through all chunks
	for cy in range(num_chunks_y):
		for cx in range(num_chunks_x):
			var patch_origin_x: int = cx * (PATCH_SIZE - 1)
			var patch_origin_y: int = cy * (PATCH_SIZE - 1)

			# Note: We pass PATCH_SIZE for the local width/depth, as each chunk needs
			# PATCH_SIZE * PATCH_SIZE vertices to form (PATCH_SIZE-1) * (PATCH_SIZE-1) quads.
			var chunk_name = "tx%02dx%02d" % [cx, cy]
			create_mesh_chunk(buffer, chunk_name, patch_origin_x, patch_origin_y, PATCH_SIZE, PATCH_SIZE, detailMaps)
			
	create_terrain_collision()

	
func create_terrain_collision() -> void:
	print("Creating terrain collision...")
	
	# Get or create StaticBody3D
	var static_body: StaticBody3D = find_child("TerrainCollisionBody")
	if not is_instance_valid(static_body):
		static_body = StaticBody3D.new()
		static_body.name = "TerrainCollisionBody"
		add_child(static_body)
		static_body.set_owner(get_owner())

	# Get or create CollisionShape3D
	var collision_shape: CollisionShape3D = static_body.find_child("TerrainCollisionShape")
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "TerrainCollisionShape"
		static_body.add_child(collision_shape)
		collision_shape.set_owner(get_owner())

	# Create HeightMapShape3D resource
	var heightmap_shape = HeightMapShape3D.new()
	heightmap_shape.map_width = size_x * terrain_scale
	heightmap_shape.map_depth = size_y * terrain_scale
	heightmap_shape.map_data = all_height_data

	# Apply the shape
	collision_shape.shape = heightmap_shape
	
	# Position collision to match the mesh
	# HeightMapShape3D centers itself, so we need to offset it
	var offset_x = -float(size_x - 1) * terrain_scale / 2.0
	var offset_z = -float(size_y - 1) * terrain_scale / 2.0
	static_body.position = Vector3(offset_x, 0.0, offset_z)
	
	print("Terrain collision created with %d height samples" % all_height_data.size())


	
#



func create_mesh_chunk(buffer: PackedByteArray, chunk_name: String, start_x: int, start_y: int, chunk_width: int, chunk_depth: int, detailMaps) -> void:

	# Create the MeshInstance3D node for this chunk
	var chunk_mesh_node: MeshInstance3D = MeshInstance3D.new()
	chunk_mesh_node.name = chunk_name
	add_child(chunk_mesh_node,true)
	chunk_mesh_node.set_owner(get_owner())

	# Calculate half-size for centering the entire terrain (used for global positioning)
	var total_half_x: float = float(size_x - 1) * terrain_scale / 2.0
	var total_half_y: float = float(size_y - 1) * terrain_scale / 2.0

	# Calculate the chunk's visual offset to keep the entire terrain centered at (0, 0, 0)
	var chunk_offset_x = float(start_x) * terrain_scale - total_half_x
	var chunk_offset_z = float(start_y) * terrain_scale - total_half_y # Z is depth

	# Move the chunk mesh node into its correct global position
	#chunk_mesh_node.transform.origin = Vector3(chunk_offset_x, 0.0, chunk_offset_z)
	# Flip the Z to make it work for BF2
	chunk_mesh_node.transform.origin = Vector3(chunk_offset_x, 0.0, -chunk_offset_z)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var height_data: PackedFloat32Array = PackedFloat32Array()

	for j in range(chunk_depth):
		for i in range(chunk_width):
			var global_i = start_x + i
			var global_j = start_y + j
			
			if global_i >= size_x || global_j >= size_y:
				continue
			
			
			var index: int = (global_j * size_x + global_i) * BYTES_PER_PIXEL
			var raw_height: int = (buffer[index + 1] << 8) | buffer[index]
			raw_height = MAX_RAW_HEIGHT + raw_height
			
			# Normalize the raw height (0 to 65535) and scale it
			var height: float = float(raw_height) / MAX_RAW_HEIGHT * height_scale
			height_data.append(height)
			
			var collision_index = global_j * size_x + global_i
			all_height_data[collision_index] = height
			
			var vertex_position: Vector3 = Vector3(float(i) * terrain_scale, height, -float(j) * terrain_scale)
			
			



			
			var uv: Vector2 = Vector2(float(i) / float(chunk_width - 1), float(j) / float(chunk_depth - 1))
			uv = Vector2(uv[0], uv[1])
			
			
			st.set_uv(uv)
			st.add_vertex(vertex_position)

	# --- TRIANGLE INDICES PASS ---
	# Connect the vertices to form triangles (2 triangles per quad)
	for j in range(chunk_depth - 1):
		for i in range(chunk_width - 1):
			var v00: int = j * chunk_width + i
			var v10: int = (j + 1) * chunk_width + i
			var v01: int = j * chunk_width + i + 1
			var v11: int = (j + 1) * chunk_width + i + 1

			# First triangle (v00, v10, v01)
			st.add_index(v00)
			st.add_index(v10)
			st.add_index(v01)

			# Second triangle (v01, v10, v11)
			st.add_index(v01)
			st.add_index(v10)
			st.add_index(v11)


	st.generate_normals()
	var generated_mesh: ArrayMesh = st.commit()
	chunk_mesh_node.mesh = generated_mesh
	
	
	
	## Generate Material
	var tx_material = ShaderMaterial.new()
	chunk_mesh_node.set_surface_override_material(0, tx_material)
	print(chunk_name)
	print(detailMaps)

	tx_material.shader = load("res://shaders/Terrain.gdshader")
	
	tx_material.set_shader_parameter("ColorMap", load("res://Levels/Strike_at_Karkand/Colormaps/" + chunk_name + ".dds"))
	tx_material.set_shader_parameter("LightMap", load("res://Levels/Strike_at_Karkand/lightmaps/" + chunk_name + ".dds"))
	tx_material.set_shader_parameter("SplatMap1", load("res://Levels/Strike_at_Karkand/Detailmaps/" + chunk_name + "_1.dds"))
	
	if FileAccess.file_exists("res://Levels/Strike_at_Karkand/Detailmaps/" + chunk_name + "_2.dds"):	
		tx_material.set_shader_parameter("SplatMap2", load("res://Levels/Strike_at_Karkand/Detailmaps/" + chunk_name + "_2.dds"))
	tx_material.set_shader_parameter("LowDetailComponent", load("res://Levels/Strike_at_Karkand/LowDetailmaps/" + chunk_name + ".dds"))
	
	# DetailMaps
	tx_material.set_shader_parameter("DetailMap1", load(detailMaps[0]))
	tx_material.set_shader_parameter("DetailMap2", load(detailMaps[1]))
	tx_material.set_shader_parameter("DetailMap3", load(detailMaps[2]))
	tx_material.set_shader_parameter("DetailMap4", load(detailMaps[3]))
	tx_material.set_shader_parameter("DetailMap5", load(detailMaps[4]))
	tx_material.set_shader_parameter("DetailMap6", load(detailMaps[5]))
	
	# LowDetailMap
	tx_material.set_shader_parameter("LowDetailMap", load("res://Levels/Strike_at_Karkand/lowdetailtexture.dds"))
	
	## Other Variables (later)
	tx_material.set_shader_parameter("SunIntensity", 4.0)
	


	

	# 6. Generate Collision for this chunk
	#if generate_collision:
	##create_collision(chunk_mesh_node, height_data, chunk_width, chunk_depth)
		# 1. Get or create StaticBody3D

func get_detail_textures(path):
	var file = FileAccess.open(path, FileAccess.READ)
	var data = file.get_buffer(file.get_length())

	var text = ""
	var results = []

	for byte in data:
		if byte >= 32 and byte <= 126:
			text += char(byte)
		else:
			if text.length() >= 5 and "common\\terrain\\textures\\detail" in text.to_lower():
				var texture = "res://" + text.replace("\\", "/")
				texture += ".dds"
				results.append(texture)
			text = ""

	return results

	


func load_staticobjects():
	print("LODING)")
	
	const MeshSceneImporterClass = preload("res://addons/bf2_mesh_importer/conParser_GenerateScene.gd")
	var importer = MeshSceneImporterClass.new()
	
	#var test_file = "res://objects/staticobjects/_middle-east/city/city_architecture/gas_station/gas_station.con"
	#importer.import_and_save_mesh(test_file)

	
	## CLEAN UP STATICOBJECTS
	var parent = get_parent()
	
	for child in parent.get_children():
		if "StaticObjects" in child.name:
			if is_instance_valid(child):
				child.queue_free()
				await get_tree().process_frame

	# create StaticObjectsNode 3D
	
	var staticObjects_node =  Node3D.new()
	staticObjects_node.name = "StaticObjects"
	
	
	parent.add_child(staticObjects_node, true)
	staticObjects_node.set_owner(get_owner())
	
	# Flip it around
	staticObjects_node.scale.x = 1.0
	staticObjects_node.scale.y = 1.0
	staticObjects_node.scale.z = 1.0
	
	staticObjects_node.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	
	
	# rotate it to al
	#staticObjects_node.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	
	

		
	var staticObjectsfile: FileAccess = FileAccess.open(static_object_files, FileAccess.READ)
	if not staticObjectsfile:
		print("ERROR: Failed to open file: %s" % static_object_files)
		return

	var staticObjectPaths = []
	
	var objectName = ""
	var objectPosition = Vector3(0.0,0.0,0.0)
	var objectRotation = Vector3(0.0,0.0,0.0)
	var objectLayer = 1
	while not staticObjectsfile.eof_reached():
		var line = staticObjectsfile.get_line()
		line = line.strip_edges()
		
		
		## Load each tscn file here
		## Figure out a way to ignore
		if line.begins_with('run '):
			pass
			var conFile = "res://" + line.split('run /')[1]
			var tscnFile = conFile.replace('.con', '.tscn')
			
			if createStaticScenes:
				#if not FileAccess.file_exists(tscnFile):
				importer.import_and_save_mesh(conFile)
					
					
			staticObjectPaths.append(tscnFile)
			
				
			
			## SCRIPT TO LOAD CON FILE AND MAKE SCENE HERE!
		
	
		# Create Object Here
		if line.begins_with('Object.create '):
			
			var staticObjectScene : Node
			
			
			
			objectName = line.split(' ')[1].strip_edges()

			
			for staticObjectPath in staticObjectPaths:
				if staticObjectPath.ends_with(objectName + ".tscn"):
					print(objectName + "has this path: " + staticObjectPath)
					
					## Check if file exists and then instantiate it
					if FileAccess.file_exists(staticObjectPath):
						
						staticObjectScene = load(staticObjectPath).instantiate()
				#else:
					#print("Couldn't find" + objectName)
			
			
			var nextLine = staticObjectsfile.get_line()
			var nextNextLine = staticObjectsfile.get_line()
			
			if nextLine.begins_with('Object.absolutePosition '):
				var absolutePositionsString = nextLine.split(' ')[1].split('/')
				
				var absolutePositions = []
				for pos in absolutePositionsString:
					absolutePositions.append(float(pos))
					
				objectPosition = Vector3(absolutePositions[0], absolutePositions[1], -absolutePositions[2])


			## Organise Rotation
			if nextLine.begins_with('Object.rotation '):
				var rotationString = nextLine.split(' ')[1].split('/')
				
				var rotations = []
				for rot in rotationString:
					rotations.append(float(rot))
				objectRotation = Vector3(rotations[0], rotations[1], rotations[2])
					
			elif nextNextLine.begins_with('Object.rotation '):
				var rotationString = nextNextLine.split(' ')[1].split('/')
				
				var rotations = []
				for rot in rotationString:
					rotations.append(float(rot))
				objectRotation = Vector3(rotations[0],rotations[1], rotations[2])
			else:
				objectRotation = Vector3(0.0, 0.0, 0.0)

		
			
			staticObjectScene.name = objectName
			staticObjectScene.transform.origin = objectPosition
			staticObjectScene.scale.x = -1
			#if objectRotation != Vector3(0.0,0.0,0.0):
				#objectRotation = convert_bf2_rotation(objectRotation)
			staticObjectScene.rotation_degrees = convert_bf2_rotation(objectRotation)
			#staticObjectScene.set_scale(Vector3(1,1,-1))
			staticObjects_node.add_child(staticObjectScene, true)
			staticObjectScene.set_owner(get_owner())
	
