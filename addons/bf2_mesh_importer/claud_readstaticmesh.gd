# test_mesh_parser.gd
@tool
extends EditorScript

# This function is executed when you right-click the script and select "Run".
func _run():
	# Define the file path you want to test
	#const FILE_PATH = "res://meshes/evil_box/evil_box.staticmesh"
	#const FILE_PATH = "res://meshes/cardbox_cod/Meshes/cardbox_cod.staticmesh"
	#@const FILE_PATH = "res://meshes/house_double_01/meshes/house_double_01.staticmesh"
	#const FILE_PATH = "res://meshes/bridge/div_citybrdgsloop_small.staticmesh"
	
	const FILE_PATH = "res://meshes/gas_station/meshes/gas_station.staticmesh"
	
	var parser = preload("res://addons/bf2_mesh_importer/ClaudmeshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(FILE_PATH)
	
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("ERROR: No scene root found!")
		return
	

	# Get the base name from the file
	var mesh_name = FILE_PATH.get_file().get_basename()
	
	# Create root node for this mesh
	var mesh_root = Node3D.new()
	mesh_root.name = mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)
	
	# Track mesh index for the flat array returned by create_array_meshes
	var mesh_index = 0
	var meshes = parser.create_array_meshes(parsed_data)
	
	# Create hierarchy: Geom → LOD → MeshInstance
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		# Create Geom node (only if multiple geoms exist)
		var geom_node = mesh_root
		if parsed_data.geoms.size() > 1:
			geom_node = Node3D.new()
			geom_node.name = "Geom%d" % geom_idx
			mesh_root.add_child(geom_node)
			geom_node.set_owner(root)
		
		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			
			# Skip LODs with no materials
			if lod.materials.size() == 0:
				continue
			
			# Create LOD node
			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			geom_node.add_child(lod_node)
			lod_node.set_owner(root)
			
			# Get the corresponding mesh from the array
			if mesh_index < meshes.size():
				var mesh_instance = MeshInstance3D.new()
				mesh_instance.mesh = meshes[mesh_index]
				mesh_instance.name = "Mesh"
				lod_node.add_child(mesh_instance)
				mesh_instance.set_owner(root)
				
		
				
				var matcount = 0
				for mat in lod.materials:
					var new_material = ShaderMaterial.new()
					new_material.shader = load("res://shaders/" + mat.technique + ".gdshader")
					
					if mat.technique == "Base":
						new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
					
					if mat.technique == "BaseDetail":
						new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
						new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
						
					if mat.technique == "BaseDetailNDetail":
						new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
						new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
						new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[2]))
					
					if mat.technique == "BaseDetailDirtNDetail":
						new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
						new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
						new_material.set_shader_parameter("DirtTexture", load("res://" + mat.maps[2]))
						new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[3]))

					if mat.technique == "BaseDetailCrackNDetailNCrack":
						new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
						new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
						new_material.set_shader_parameter("CrackTexture", load("res://" + mat.maps[2]))
						new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[3]))
						new_material.set_shader_parameter("NCrackTexture", load("res://" + mat.maps[4]))					
					
					mesh_instance.set_surface_override_material(matcount, new_material)
					
					matcount += 1
					

					
				# Set visibility distance for LODs (optional)
				if lod_idx > 0:
					# Hide higher LODs by default, or set up visibility ranges
					# You can configure LOD distances here based on your needs
					lod_node.visible = false
				
				mesh_index += 1
			
			# Debug: print LOD info
			print("  Created %s/LOD%d with %d materials" % [geom_node.name, lod_idx, lod.materials.size()])
	
	print("\n✓ Successfully created mesh hierarchy: %s" % mesh_name)
	print("  - %d Geom(s)" % parsed_data.geoms.size())
	print("  - %d total mesh(es) created" % mesh_index)



	# Get CollisoinMesh
	var reader = preload("res://addons/bf2_mesh_importer/ClaudCollisionMeshParser.gd").new()
	var collision_meshes  = reader.import_collision_mesh("res://meshes/gas_station/meshes/gas_station.collisionmesh")
	for i in range(collision_meshes.size()):
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = collision_meshes[i]
		mesh_instance.name = collision_meshes[i].resource_name  # e.g., "col0_projectile"
		root.add_child(mesh_instance)
		mesh_instance.set_owner(root)
