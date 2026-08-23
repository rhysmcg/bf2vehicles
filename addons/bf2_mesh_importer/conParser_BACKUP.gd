# test_mesh_parser.gd
@tool
extends EditorScript

## TO DO
# Handle bundles (eg: Hotel has a ladder)

func read_con_tweak(path, objectData):
	var file = FileAccess.open(path, FileAccess.READ)

	if file == null:
		print("Error opening file: ", FileAccess.get_open_error())
		return
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("rem"):
			continue
			
		elif line.begins_with("GeometryTemplate.setSubGeometryLodDistance"):
			var geomNum = int(line.split(' ')[1])
			var lodNum = int(line.split(' ')[2])
			var distance = int(line.split(' ')[3])
			objectData["lodDistance"].append([geomNum, lodNum, distance])
		
		elif line.begins_with("GeometryTemplate.create StaticMesh"):
			objectData["objectName"] = line.split(' ')[2]
			
		elif line.begins_with("ObjectTemplate.collisionMesh"):
			objectData["hasCollision"] = true
			
		elif line.begins_with("ObjectTemplate.hasCollisionPhysics"):
			objectData["hasCollisionPhysics"] = int(line.split(' ')[1])
		
		elif line.begins_with("ObjectTemplate.mapMaterial"):
			var collisionMaterialIndex = int(line.split(' ')[1])
			var collisionMaterialName = line.split(' ')[2]
			var collisionValueIndex = int(line.split(' ')[3])
			objectData["materials"][collisionMaterialIndex] = [collisionMaterialName, collisionValueIndex]
	
		elif line.begins_with("ObjectTemplate.hasMobilePhysics"):
			objectData["hasMobilePhysics"] = int(line.split(' ')[1])

		elif line.begins_with("ObjectTemplate.physicsType"):
			objectData["physicsType"] = line.split(' ')[1]
			
		elif line.begins_with('ObjectTemplate.anchor'):
			var anchor = []
			var anchorData = line.split(' ')[1].split('/')
			for x in anchorData:
				anchor.append(float(x))
				
			objectData["anchor"] = anchor
		
		elif line.begins_with('ObjectTemplate.addTemplate'):
			var template = line.split(' ')[1]
			var nextLine = file.get_line().strip_edges()
			var nextNextLine = file.get_line().strip_edges()
			var template_position = [0,0,0]
			var template_rotation = [0,0,0]
			
			## Add Template Positions
			if nextLine.begins_with("ObjectTemplate.setPosition"):
				var positions = nextLine.split(' ')[1].split('/')
				template_position = []
				for x in positions:
					template_position.append(float(x))
			
			## Add Template Rotations
			if nextLine.begins_with("ObjectTemplate.setRotation"):
				var rotations = nextLine.split(' ')[1].split('/')
				template_rotation = []
				for x in rotations:
					template_rotation.append(float(x))
			
			elif nextNextLine.begins_with("ObjectTemplate.setRotation"):
				var rotations = nextNextLine.split(' ')[1].split('/')
				template_rotation = []
				for x in rotations:
					template_rotation.append(float(x))
			
			
			objectData["templates"].append([template, template_position, template_rotation])
			
		elif line.begins_with("ObjectTemplate.create"):
			var objectType = line.split(' ')[1]
			var objectName = line.split(' ')[2]
			objectData["children"].append([objectType,objectName])
		
		elif line.begins_with('include'):
			objectData["hasTweak"] = true

	file.close()
	return objectData


func processCon(conFile):
	
	var tweakFile = conFile.replace('.con', '.tweak')
	
	## Set the initial objectData values
	var objectData = {}
	objectData["objectName"] = ""
	objectData["hasCollision"] = false
	objectData["hasCollisionPhysics"] = 0
	objectData["materials"] = {}
	objectData["anchor"] = [0,0,0]
	objectData["hasTweak"] = false
	objectData["lodDistance"] = []
	objectData["templates"] = []
	objectData["children"] = []
	objectData = read_con_tweak(conFile, objectData)
	
	## If the object has a tweak file, then read that too
	if objectData["hasTweak"]:
		objectData = read_con_tweak(tweakFile, objectData)
		
	return objectData




func _run():
	
	var filePath = "res://objects/staticobjects/_middle-east/city/city_architecture/hotel/hotel.con"
	var objectData
	objectData = processCon(filePath)
	print(objectData)
	
	# if staticObject, bundledObject, skinnedobject change the importer function!
	
	importStaticMesh(filePath, objectData)

func importStaticMesh(filePath, objectData):
	
	var staticmesh_file = filePath.get_base_dir() + "/meshes/" + filePath.get_file().get_basename() + ".staticmesh"


	var parser = preload("res://addons/bf2_mesh_importer/ClaudmeshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(staticmesh_file)
	var root = get_editor_interface().get_edited_scene_root() ## This part i could change to staticbody?
	if not root:
		print("ERROR: No scene root found!")
		return

	# Get the base name from the file
	#var mesh_name = filePath.get_file().get_basename()
	var mesh_name = objectData["objectName"]
	

	var mesh_root = Node3D.new()
	mesh_root.name = mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)
	

	# Track mesh index for the flat array returned by create_array_meshes
	var mesh_index = 0
	var meshes = parser.create_array_meshes(parsed_data)
	
	var visualMeshNode = Node3D.new()
	visualMeshNode.name = "StaticMesh"
	mesh_root.add_child(visualMeshNode)
	visualMeshNode.set_owner(root)
	
	
	# Create hierarchy: Geom → LOD → MeshInstance
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		# Create Geom node (only if multiple geoms exist)
		var geom_node = mesh_root
		if parsed_data.geoms.size() > 0:
			geom_node = Node3D.new()
			geom_node.name = "Geom%d" % geom_idx
			visualMeshNode.add_child(geom_node)
			geom_node.set_owner(root)
		
		var finalDistance = 0
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
					

				## SET UP Visibility Ranges
				var geomloddistancecounter = 0
				
				for geomloddistance in objectData["lodDistance"]:
					var distanceGeom = geomloddistance[0]
					var distanceLod = geomloddistance[1]
					var distanceValue = geomloddistance[2]
					if geom_idx == distanceGeom:
						if distanceLod == lod_idx:
							## First LOD
							if lod_idx == 0:
								mesh_instance.visibility_range_end = distanceValue
							## LODS in between
							elif lod_idx < geom.lods.size() and lod_idx > 0:
								mesh_instance.visibility_range_begin = objectData["lodDistance"][geomloddistancecounter - 1][2]
								mesh_instance.visibility_range_end = distanceValue
								finalDistance = distanceValue
					geomloddistancecounter += 1
					
				if lod_idx == (geom.lods.size() - 1):
					print("FINAL DISTANCE IS...")
					print(finalDistance)
					mesh_instance.visibility_range_begin = finalDistance
				
				
							
				
				mesh_index += 1
			
			# Debug: print LOD info
			print("  Created %s/LOD%d with %d materials" % [geom_node.name, lod_idx, lod.materials.size()])
	
	
	print("\n✓ Successfully created mesh hierarchy: %s" % mesh_name)
	print("  - %d Geom(s)" % parsed_data.geoms.size())
	print("  - %d total mesh(es) created" % mesh_index)

	## ADD ANCHOR
	var mesh_anchor = Marker3D.new()
	mesh_anchor.gizmo_extents = 5 # Make a gizmo to represent the anchor
	mesh_anchor.name = mesh_name + "_anchor"
	mesh_root.add_child(mesh_anchor)
	mesh_anchor.position.x = objectData["anchor"][0]
	mesh_anchor.position.y = objectData["anchor"][1]
	mesh_anchor.position.z = objectData["anchor"][2]
	mesh_anchor.set_owner(root)
	
	visualMeshNode.reparent(mesh_anchor)
	
	## CHANGE SCENE ROOT
	
	#var scene_tree = get_editor_interface().get_edited_scene_tree()
	#var root1 = .get_edited_scene_root()
	
	#scene_tree.set_current_scene(mesh_root)
	
	
	if objectData["hasCollision"]:
		importCollisionMesh(filePath, root)


func importCollisionMesh(filePath, root):
	# Get CollisionMesh
	var reader = preload("res://addons/bf2_mesh_importer/ClaudCollisionMeshParser.gd").new()
	
	print("Import Collision")
	
	var collision_mesh = filePath.get_base_dir() + "/meshes/" + filePath.get_file().get_basename() + ".collisionmesh"
	print(collision_mesh)
	var collision_meshes  = reader.import_collision_mesh(collision_mesh)
	var colNode = Node3D.new()
	colNode.name = "CollisionMesh"
	var objectNode = root.get_child(0)
	

	objectNode.add_child(colNode)
	colNode.set_owner(root)
	colNode.visible = false
	for i in range(collision_meshes.size()):
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = collision_meshes[i]
		mesh_instance.name = collision_meshes[i].resource_name  # e.g., "col0_projectile"
		colNode.add_child(mesh_instance)
		mesh_instance.set_owner(root)
		mesh_instance.create_trimesh_collision()
		
	if "anchor" in objectNode.get_child(0).name:
		var anchorNode = objectNode.get_child(0)
		colNode.reparent(anchorNode)
		
	
	## Organise layer groups
	for node in colNode.get_children():
		var colStaticBodyNode = node.get_child(0)
		colStaticBodyNode.reparent(colNode)
		if colStaticBodyNode.name.begins_with("col0"):
			colStaticBodyNode.set_collision_layer_value(1, true)
			colStaticBodyNode.set_collision_mask_value(1, false)
			colStaticBodyNode.set_collision_mask_value(2, true)
			colStaticBodyNode.set_collision_mask_value(3, true)
			colStaticBodyNode.set_collision_mask_value(4, true)
		elif colStaticBodyNode.name.begins_with("col1"):
			colStaticBodyNode.set_collision_layer_value(1, false)
			colStaticBodyNode.set_collision_layer_value(2, true)
			colStaticBodyNode.set_collision_mask_value(1, true)
			colStaticBodyNode.set_collision_mask_value(3, true)
			colStaticBodyNode.set_collision_mask_value(4, true)
		elif colStaticBodyNode.name.begins_with("col2"):
			colStaticBodyNode.set_collision_layer_value(1, false)
			colStaticBodyNode.set_collision_layer_value(3, true)
			colStaticBodyNode.set_collision_mask_value(1, true)
			colStaticBodyNode.set_collision_mask_value(2, true)
			colStaticBodyNode.set_collision_mask_value(4, true)
		elif colStaticBodyNode.name.begins_with("col3"):
			colStaticBodyNode.set_collision_layer_value(1, false)
			colStaticBodyNode.set_collision_layer_value(4, true)
			colStaticBodyNode.set_collision_mask_value(1, true)
			colStaticBodyNode.set_collision_mask_value(2, true)
			colStaticBodyNode.set_collision_mask_value(3, true)
			
		node.queue_free()
			
		
	
