@tool
extends EditorScript

var filePath = "res://Objects/soldiers/Us/us_light_soldier.con"

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
			var parts = line.split(' ')
			var geomNum = int(parts[1])
			var lodNum = int(parts[2])
			var distance = int(parts[3])
			objectData["lodDistance"].append([geomNum, lodNum, distance])
		
		elif line.begins_with("GeometryTemplate.create"):
			var parts = line.split(' ')
			if parts.size() >= 3:
				objectData["objectName"] = parts[2]
				objectData["geometryType"] = parts[1]  # StaticMesh, BundledMesh, SkinnedMesh, etc.
			
		elif line.begins_with("ObjectTemplate.collisionMesh"):
			objectData["hasCollision"] = true
			
		elif line.begins_with("ObjectTemplate.skeleton1P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["skeleton1P"] = parts[1]
			
		elif line.begins_with("ObjectTemplate.skeleton3P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["skeleton3P"] = parts[1]
			
		elif line.begins_with("ObjectTemplate.hasCollisionPhysics"):
			objectData["hasCollisionPhysics"] = int(line.split(' ')[1])
		
		elif line.begins_with("ObjectTemplate.mapMaterial"):
			var parts = line.split(' ')
			var collisionMaterialIndex = int(parts[1])
			var collisionMaterialName = parts[2]
			var collisionValueIndex = int(parts[3])
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
			var template_position = [0.0, 0.0, 0.0]
			var template_rotation = [0.0, 0.0, 0.0]
			
			if nextLine.begins_with("ObjectTemplate.setPosition"):
				var positions = nextLine.split(' ')[1].split('/')
				template_position = []
				for x in positions:
					template_position.append(float(x))
			
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
			if not line.begins_with("ObjectTemplate.createdInEditor"):
				var parts = line.split(' ')
				if parts.size() >= 3:
					var objectType = parts[1]
					var objectName = parts[2]
					objectData["children"].append([objectType, objectName])
				else:
					print("SKIPPED (incomplete): " + line)
			
		elif line.begins_with('include'):
			objectData["hasTweak"] = true
	file.close()
	return objectData

func processCon(conFile):
	var tweakFile = conFile.replace('.con', '.tweak')
	
	var objectData = {}
	objectData["objectName"] = ""
	objectData["geometryType"] = ""
	objectData["hasCollision"] = false
	objectData["hasCollisionPhysics"] = 0
	objectData["materials"] = {}
	objectData["anchor"] = [0.0, 0.0, 0.0]
	objectData["hasTweak"] = false
	objectData["lodDistance"] = []
	objectData["templates"] = []
	objectData["children"] = []
	objectData["skeleton1P"] = ""
	objectData["skeleton3P"] = ""
	objectData = read_con_tweak(conFile, objectData)
	
	if objectData["hasTweak"]:
		objectData = read_con_tweak(tweakFile, objectData)
	
	return objectData

func _run():
	var objectData = processCon(filePath)
	
	if objectData == null or objectData["objectName"] == "":
		print("ERROR: Failed to parse .con file or no object name found")
		return
	
	print(objectData)
	
	var mesh_dir = filePath.get_base_dir() + "/meshes/"
	var base_name = filePath.get_file().get_basename()
	
	var staticmesh_file = mesh_dir + base_name + ".staticmesh"
	var bundledmesh_file = mesh_dir + base_name + ".bundledmesh"
	var skinnedmesh_file = mesh_dir + base_name + ".skinnedmesh"
	
	if FileAccess.file_exists(bundledmesh_file):
		importBundledMesh(bundledmesh_file, objectData)
	elif FileAccess.file_exists(staticmesh_file):
		importStaticMesh(staticmesh_file, objectData)
	elif FileAccess.file_exists(skinnedmesh_file):
		importSkinnedMesh(skinnedmesh_file, objectData)
	else:
		print("ERROR: No mesh file found for " + base_name)

# BundledMesh importer with part hierarchy
func importBundledMesh(mesh_file, objectData):
	var parser = preload("res://addons/bf2_mesh_importer/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("ERROR: No scene root found!")
		return
	var mesh_name = objectData["objectName"]
	
	var vehicle_root = Node3D.new()
	vehicle_root.name = mesh_name
	root.add_child(vehicle_root)
	vehicle_root.set_owner(root)
	
	var meshes = parser.create_array_meshes(parsed_data)
	var mesh_index = 0
	
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		var part_node = Node3D.new()
		part_node.name = "Part%d" % geom_idx
		vehicle_root.add_child(part_node)
		part_node.set_owner(root)
		
		var previous_lod_end = 0.0
		
		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			
			if lod.materials.size() == 0:
				continue
			
			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			part_node.add_child(lod_node)
			lod_node.set_owner(root)
			
			if mesh_index < meshes.size():
				var mesh_instance = MeshInstance3D.new()
				mesh_instance.mesh = meshes[mesh_index]["mesh"]
				mesh_instance.name = "Mesh"
				lod_node.add_child(mesh_instance)
				mesh_instance.set_owner(root)
				
				var matcount = 0
				for mat in lod.materials:
					apply_material(mesh_instance, mat, matcount)
					matcount += 1
				
				var lod_end_distance = get_lod_distance(objectData["lodDistance"], geom_idx, lod_idx)
				
				if lod_idx == 0:
					mesh_instance.visibility_range_begin = 0
					mesh_instance.visibility_range_end = lod_end_distance
				elif lod_idx == geom.lods.size() - 1:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = 0
				else:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = lod_end_distance
				
				previous_lod_end = lod_end_distance
				
				print("  Part%d/LOD%d visibility: %d to %d" % [geom_idx, lod_idx, mesh_instance.visibility_range_begin, mesh_instance.visibility_range_end])
				
				mesh_index += 1
	
	if objectData["hasCollision"]:
		var collision_mesh_path = mesh_file.get_base_dir() + "/" + mesh_file.get_file().get_basename() + ".collisionmesh"
		importCollisionMeshToParts(collision_mesh_path, vehicle_root, objectData, parsed_data.geoms.size())
	
	apply_part_transforms(vehicle_root, objectData)
	
	vehicle_root.scale = Vector3(1.0, 1.0, -1.0)
	
	print("\n✓ Successfully created BundledMesh: %s" % mesh_name)
	print("  - %d Parts (Geoms)" % parsed_data.geoms.size())

# StaticMesh importer (original logic with anchor)
func importStaticMesh(mesh_file, objectData):
	var parser = preload("res://addons/bf2_mesh_importer/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("ERROR: No scene root found!")
		return
	var mesh_name = objectData["objectName"]
	
	var mesh_root = Node3D.new()
	mesh_root.name = "root_" + mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)
	
	var mesh_index = 0
	var meshes = parser.create_array_meshes(parsed_data)
	
	var visualMeshNode = Node3D.new()
	visualMeshNode.name = "StaticMesh"
	mesh_root.add_child(visualMeshNode)
	visualMeshNode.set_owner(root)
	
	var previous_lod_end = 0.0
	
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		
		var geom_node = visualMeshNode
		if parsed_data.geoms.size() > 1:
			geom_node = Node3D.new()
			geom_node.name = "Geom%d" % geom_idx
			visualMeshNode.add_child(geom_node)
			geom_node.set_owner(root)
		
		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]
			
			if lod.materials.size() == 0:
				continue
			
			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			geom_node.add_child(lod_node)
			lod_node.set_owner(root)
			
			if mesh_index < meshes.size():
				var mesh_instance = MeshInstance3D.new()
				mesh_instance.mesh = meshes[mesh_index]["mesh"]
				mesh_instance.name = "Mesh"
				lod_node.add_child(mesh_instance)
				mesh_instance.set_owner(root)
				
				var matcount = 0
				for mat in lod.materials:
					apply_material(mesh_instance, mat, matcount)
					matcount += 1
				
				var lod_end_distance = get_lod_distance(objectData["lodDistance"], geom_idx, lod_idx)
				
				if lod_idx == 0:
					mesh_instance.visibility_range_begin = 0
					mesh_instance.visibility_range_end = lod_end_distance
				elif lod_idx == geom.lods.size() - 1:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = 0
				else:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = lod_end_distance
				
				previous_lod_end = lod_end_distance
				
				mesh_index += 1
			
			print("  Created %s/LOD%d with %d materials" % [geom_node.name, lod_idx, lod.materials.size()])
	
	if objectData["hasCollision"]:
		var collision_mesh_path = mesh_file.get_base_dir() + "/" + mesh_file.get_file().get_basename() + ".collisionmesh"
		importCollisionMesh(collision_mesh_path, root, objectData, mesh_root)
	
	var collisionMeshNode = mesh_root.find_child("CollisionMesh")
	var mesh_anchor = Marker3D.new()
	mesh_anchor.gizmo_extents = 5
	mesh_anchor.name = mesh_name + "_anchor"
	mesh_anchor.position.x = objectData["anchor"][0]
	mesh_anchor.position.y = objectData["anchor"][1]
	mesh_anchor.position.z = objectData["anchor"][2]
	root.add_child(mesh_anchor)
	mesh_anchor.set_owner(root)
	visualMeshNode.reparent(mesh_anchor)
	if collisionMeshNode:
		collisionMeshNode.reparent(mesh_anchor)
	
	mesh_root.queue_free()
	
	mesh_anchor.position = Vector3(0, 0, 0)
	mesh_anchor.scale = Vector3(1.0, 1.0, -1.0)
	mesh_anchor.name = mesh_name
	
	print("\n✓ Successfully created StaticMesh: %s" % mesh_name)

# SkinnedMesh importer (soldiers/weapons)
func importSkinnedMesh(mesh_file, objectData):
	var parser = preload("res://addons/bf2_mesh_importer/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	var root = get_editor_interface().get_edited_scene_root()
	if not root:
		print("ERROR: No scene root found!")
		return

	var mesh_name = objectData["objectName"]

	var mesh_root = Node3D.new()
	mesh_root.name = mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)

	var mesh_index = 0
	var meshes = parser.create_array_meshes(parsed_data)

	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]

		var geom_node = mesh_root
		if parsed_data.geoms.size() > 1:
			geom_node = Node3D.new()
			geom_node.name = "Geom%d" % geom_idx
			mesh_root.add_child(geom_node)
			geom_node.set_owner(root)

		# Attach the matching skeleton for this geom.
		var skeleton_path: String = objectData["skeleton3P"]
		var skeleton_label: String = "3P"
		if geom_idx == 0 and objectData["skeleton1P"] != "":
			skeleton_path = objectData["skeleton1P"]
			skeleton_label = "1P"

		var skeleton3d: Skeleton3D = null
		if skeleton_path != "":
			var full_skeleton_path = "res://" + skeleton_path.to_lower()
			if FileAccess.file_exists(full_skeleton_path):
				var ske_parser = preload("res://addons/bf2_mesh_importer/BF2SkeletonParser.gd").new()
				skeleton3d = ske_parser.import_skeleton(full_skeleton_path)
				if skeleton3d:
					skeleton3d.name = "Skeleton3D_%s" % skeleton_label
					geom_node.add_child(skeleton3d)
					skeleton3d.set_owner(root)
					print("  Attached %s skeleton to Geom%d (%d bones)" % [skeleton_label, geom_idx, skeleton3d.get_bone_count()])
			else:
				print("  WARNING: Skeleton file not found: %s" % full_skeleton_path)

		var previous_lod_end = 0.0

		for lod_idx in range(geom.lods.size()):
			var lod = geom.lods[lod_idx]

			if lod.materials.size() == 0:
				continue

			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			geom_node.add_child(lod_node)
			lod_node.set_owner(root)

			if mesh_index < meshes.size():
				var mesh_result = meshes[mesh_index]
				var mesh_instance = MeshInstance3D.new()
				mesh_instance.mesh = mesh_result["mesh"]
				mesh_instance.name = "Mesh"
				lod_node.add_child(mesh_instance)
				mesh_instance.set_owner(root)

				var matcount = 0
				for mat in lod.materials:
					apply_material(mesh_instance, mat, matcount, "SkinnedMesh")
					matcount += 1

				# Step 2: bind the mesh to the skeleton via the Skin resource built in
				# create_array_meshes(). The file's own per-bone bind matrix convention
				# proved ambiguous/unreliable (tested both direct and inverted - both
				# distorted arms/torso), so instead we OVERRIDE every bind pose here
				# using the already-verified-correct Skeleton3D's own rest transform.
				# We only keep the file's rig data for WHICH bone each slot maps to
				# (skin.get_bind_bone), not for the transform values themselves.
				if mesh_result["skin"] != null and skeleton3d != null:
					var skin: Skin = mesh_result["skin"]
					for bi in range(skin.get_bind_count()):
						var bone_idx: int = skin.get_bind_bone(bi)
						if bone_idx >= 0 and bone_idx < skeleton3d.get_bone_count():
							skin.set_bind_pose(bi, skeleton3d.get_bone_global_rest(bone_idx).affine_inverse())
					mesh_instance.skeleton = mesh_instance.get_path_to(skeleton3d)
					mesh_instance.skin = skin
					print("  Bound skin to Geom%d/LOD%d (%d binds, poses derived from skeleton rest)" % [geom_idx, lod_idx, skin.get_bind_count()])
				elif skeleton3d != null:
					print("  NOTE: Geom%d/LOD%d has no skin data - mesh will not deform" % [geom_idx, lod_idx])

				var lod_end_distance = get_lod_distance(objectData["lodDistance"], geom_idx, lod_idx)

				if lod_idx == 0:
					mesh_instance.visibility_range_begin = 0
					mesh_instance.visibility_range_end = lod_end_distance
				elif lod_idx == geom.lods.size() - 1:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = 0
				else:
					mesh_instance.visibility_range_begin = previous_lod_end
					mesh_instance.visibility_range_end = lod_end_distance

				previous_lod_end = lod_end_distance

				mesh_index += 1

	if objectData["hasCollision"]:
		var collision_mesh_path = mesh_file.get_base_dir() + "/" + mesh_file.get_file().get_basename() + ".collisionmesh"
		if FileAccess.file_exists(collision_mesh_path):
			importCollisionMesh(collision_mesh_path, root, objectData, mesh_root)
		else:
			print("  (hasCollision set but no .collisionmesh found - normal for many soldier/weapon skinnedmeshes)")

	mesh_root.scale = Vector3(1.0, 1.0, -1.0)

	print("\n✓ Successfully created SkinnedMesh: %s" % mesh_name)
	print("  - %d Geom(s)" % parsed_data.geoms.size())
	print("  - %d total mesh(es) created" % mesh_index)

# Helper: Get LOD distance from objectData
func get_lod_distance(lod_distances: Array, geom_idx: int, lod_idx: int) -> float:
	for lod_data in lod_distances:
		if lod_data[0] == geom_idx and lod_data[1] == lod_idx:
			return float(lod_data[2])
	return 0.0

# Helper: Apply material to mesh instance.
func apply_material(mesh_instance: MeshInstance3D, mat, matcount: int, force_technique: String = ""):
	var technique_key: String = force_technique if force_technique != "" else mat.technique
	var shader_path = "res://shaders/" + technique_key + ".gdshader"
	
	if not FileAccess.file_exists(shader_path):
		print("    WARNING: Shader not found: " + shader_path)
		return
	
	var new_material = ShaderMaterial.new()
	new_material.shader = load(shader_path)
	
	match technique_key:
		"Base":
			if mat.maps.size() > 0:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
		
		"BaseDetail":
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
		
		"BaseDetailNDetail":
			if mat.maps.size() > 2:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
				new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[2]))
		
		"BaseDetailDirtNDetail":
			if mat.maps.size() > 3:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
				new_material.set_shader_parameter("DirtTexture", load("res://" + mat.maps[2]))
				new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[3]))
		
		"BaseDetailCrackNDetailNCrack":
			if mat.maps.size() > 4:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("DetailTexture", load("res://" + mat.maps[1]))
				new_material.set_shader_parameter("CrackTexture", load("res://" + mat.maps[2]))
				new_material.set_shader_parameter("NDetailTexture", load("res://" + mat.maps[3]))
				new_material.set_shader_parameter("NCrackTexture", load("res://" + mat.maps[4]))
		
		"ColormapGloss":
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("GlossTexture", load("res://" + mat.maps[1]))
		
		"EnvMapColormapGloss":
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("GlossTexture", load("res://" + mat.maps[1]))
		
		"Alpha_TestColormapGloss":
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
				new_material.set_shader_parameter("GlossTexture", load("res://" + mat.maps[1]))
		
		"SkinnedMesh":
			if mat.maps.size() > 0:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("NormalTexture", load("res://" + mat.maps[1]))
			if mat.maps.size() > 2:
				new_material.set_shader_parameter("SpecularLUT", load("res://" + mat.maps[2]))
		
		_:
			print("    NOTE: Unmapped technique '%s' (maps=%d) - applying generic BaseTexture fallback." % [technique_key, mat.maps.size()])
			if mat.maps.size() > 0:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
	
	mesh_instance.set_surface_override_material(matcount, new_material)

# Apply part transforms from .con children data
func apply_part_transforms(vehicle_root: Node3D, objectData: Dictionary):
	var child_index = 0
	for child_data in objectData["children"]:
		var child_name = child_data[1]
		if child_index < vehicle_root.get_child_count():
			var part_node = vehicle_root.get_child(child_index)
			part_node.name = child_name
			child_index += 1
	
	for template_data in objectData["templates"]:
		var template_name = template_data[0]
		var position = template_data[1]
		var rotation = template_data[2]
		
		var node = find_node_by_name(vehicle_root, template_name)
		if node:
			node.position = Vector3(position[0], position[1], position[2])
			node.rotation_degrees = Vector3(rotation[0], rotation[1], rotation[2])
			print("  Applied transform to %s: pos=%s rot=%s" % [template_name, node.position, node.rotation_degrees])

func find_node_by_name(parent: Node, node_name: String) -> Node:
	if parent.name == node_name:
		return parent
	for child in parent.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	return null

# Import collision and parent to parts (BundledMesh)
func importCollisionMeshToParts(collision_mesh_path: String, vehicle_root: Node3D, objectData: Dictionary, part_count: int):
	var reader = preload("res://addons/bf2_mesh_importer/ClaudCollisionMeshParser.gd").new()
	
	if not FileAccess.file_exists(collision_mesh_path):
		print("No collision mesh found")
		return
	
	var collision_meshes = reader.import_collision_mesh(collision_mesh_path)
	
	for i in range(min(collision_meshes.size(), part_count)):
		var part_node = vehicle_root.get_child(i)
		
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = collision_meshes[i]
		mesh_instance.name = "Collision_" + collision_meshes[i].resource_name
		mesh_instance.visible = false
		part_node.add_child(mesh_instance)
		mesh_instance.set_owner(vehicle_root.get_tree().edited_scene_root)
		mesh_instance.create_trimesh_collision()
		
		var col_body = mesh_instance.get_child(0)
		if col_body and col_body is StaticBody3D:
			setup_collision_layers(col_body, collision_meshes[i].resource_name)

# Import collision as separate node (StaticMesh)
func importCollisionMesh(collision_mesh_path: String, root: Node, objectData: Dictionary, mesh_root: Node3D):
	var reader = preload("res://addons/bf2_mesh_importer/ClaudCollisionMeshParser.gd").new()
	
	if not FileAccess.file_exists(collision_mesh_path):
		print("No collision mesh found")
		return
	
	var collision_meshes = reader.import_collision_mesh(collision_mesh_path)
	
	var colNode = Node3D.new()
	colNode.name = "CollisionMesh"
	mesh_root.add_child(colNode)
	colNode.set_owner(root)
	colNode.visible = false
	
	for i in range(collision_meshes.size()):
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = collision_meshes[i]
		mesh_instance.name = collision_meshes[i].resource_name
		colNode.add_child(mesh_instance)
		mesh_instance.set_owner(root)
		mesh_instance.create_trimesh_collision()
		
		var col_body = mesh_instance.get_child(0)
		if col_body and col_body is StaticBody3D:
			col_body.reparent(colNode)
			setup_collision_layers(col_body, collision_meshes[i].resource_name)
			mesh_instance.queue_free()

func setup_collision_layers(col_body: StaticBody3D, col_name: String):
	if col_name.begins_with("col0"):
		col_body.set_collision_layer_value(1, true)
		col_body.set_collision_mask_value(1, false)
		col_body.set_collision_mask_value(2, true)
		col_body.set_collision_mask_value(3, true)
		col_body.set_collision_mask_value(4, true)
	elif col_name.begins_with("col1"):
		col_body.set_collision_layer_value(1, false)
		col_body.set_collision_layer_value(2, true)
		col_body.set_collision_mask_value(1, true)
		col_body.set_collision_mask_value(3, true)
		col_body.set_collision_mask_value(4, true)
	elif col_name.begins_with("col2"):
		col_body.set_collision_layer_value(1, false)
		col_body.set_collision_layer_value(3, true)
		col_body.set_collision_mask_value(1, true)
		col_body.set_collision_mask_value(2, true)
		col_body.set_collision_mask_value(4, true)
	elif col_name.begins_with("col3"):
		col_body.set_collision_layer_value(1, false)
		col_body.set_collision_layer_value(4, true)
		col_body.set_collision_mask_value(1, true)
		col_body.set_collision_mask_value(2, true)
		col_body.set_collision_mask_value(3, true)
