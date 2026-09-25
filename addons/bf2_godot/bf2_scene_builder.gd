# bf2_scene_builder.gd
# Core BF2 .con / mesh scene-building logic, refactored from the original
# EditorScript (conParser2.gd) into plain functions that BUILD and RETURN a root
# Node, rather than injecting into whatever scene the editor happens to have open.
# Callable from the manual import dock (bf2_import_dock.gd) or any future importer.
#
# Nearly identical to conParser2.gd - the only structural change is how `root` is
# obtained (freshly created here instead of fetched via get_editor_interface()) and
# that each top-level function returns it. One real bug fixed in the process:
# importCollisionMeshToParts used vehicle_root.get_tree().edited_scene_root to find
# an owner, which only works inside a LIVE, open scene tree - not true here, so
# `root` is now passed through explicitly instead.

extends RefCounted

# --- PUBLIC ENTRY POINTS ---

func build_scene_from_con(con_path: String) -> Node:
	var objectData = processCon(con_path)
	
	if objectData == null or objectData["objectName"] == "":
		push_error("Failed to parse .con file or no object name found: %s" % con_path)
		return null
	
	print(objectData)
	
	var mesh_dir = con_path.get_base_dir() + "/meshes/"
	var base_name = con_path.get_file().get_basename()
	
	var staticmesh_file = mesh_dir + base_name + ".staticmesh"
	var bundledmesh_file = mesh_dir + base_name + ".bundledmesh"
	var skinnedmesh_file = mesh_dir + base_name + ".skinnedmesh"
	
	if FileAccess.file_exists(bundledmesh_file):
		return importBundledMesh(bundledmesh_file, objectData)
	elif FileAccess.file_exists(staticmesh_file):
		return importStaticMesh(staticmesh_file, objectData)
	elif FileAccess.file_exists(skinnedmesh_file):
		return importSkinnedMesh(skinnedmesh_file, objectData)
	else:
		push_error("No mesh file found for " + base_name)
		return null

# Standalone mesh (no .con) - geometry + materials only, no collision/skeleton
# (those need .con-referenced side files).
func build_scene_from_raw_mesh(mesh_file: String) -> Node:
	var parser = preload("res://addons/bf2_godot/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	
	var mesh_name = mesh_file.get_file().get_basename()
	var root := Node3D.new()
	root.name = mesh_name
	
	var meshes = parser.create_array_meshes(parsed_data)
	var mesh_index = 0
	
	for geom_idx in range(parsed_data.geoms.size()):
		var geom = parsed_data.geoms[geom_idx]
		var geom_node = root
		if parsed_data.geoms.size() > 1:
			geom_node = Node3D.new()
			geom_node.name = "Geom%d" % geom_idx
			root.add_child(geom_node)
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
				var surface_count = mesh_instance.mesh.get_surface_count()
				for mat in lod.materials:
					if matcount < surface_count:
						apply_material(mesh_instance, mat, matcount)
						matcount += 1
					else:
						print("Skipping material assignment for empty surface index %d" % matcount)
				
				if lod_idx > 0:
					lod_node.visible = false
				
				mesh_index += 1
	
	root.scale = Vector3(1.0, 1.0, -1.0)
	return root

# --- .con / .tweak PARSING ---

func read_con_tweak(path, objectData):
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Error opening file: ", FileAccess.get_open_error())
		return
		
	var currentTemplate = ""
	## Track the last addTemplate child so setPosition/setRotation on the
	## NEXT line(s) can be applied without any peek-ahead / line consuming.
	var lastAddedChild = ""
	
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
			objectData["objectName"] = parts[2]
			objectData["meshType"] = parts[1].to_lower()
			objectData["geometryType"] = parts[1]  # StaticMesh, BundledMesh, SkinnedMesh, etc.
			## The root object is always part 0 — register it so children can find it
			var rootKey = parts[2].to_lower()
			if not objectData["geomPartData"].has(rootKey):
				objectData["geomPartData"][rootKey] = {
					"name": parts[2], "geometryPart": 0,
					"parent": "", "position": [0.0,0.0,0.0], "rotation": [0.0,0.0,0.0],
				}
				
			
		elif line.begins_with("ObjectTemplate.collisionMesh"):
			objectData["hasCollision"] = true
			lastAddedChild = ""  ## position lines after this are not for a child
			
		elif line.begins_with("ObjectTemplate.skeleton1P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["skeleton1P"] = parts[1]
			
		elif line.begins_with("ObjectTemplate.hasCollisionPhysics"):
			objectData["hasCollisionPhysics"] = int(line.split(' ')[1])
			
		elif line.begins_with("ObjectTemplate.skeleton3P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["skeleton3P"] = parts[1]
		
		elif line.begins_with("ObjectTemplate.animationSystem1P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["animationSystem1P"] = parts[1]
		
		elif line.begins_with("ObjectTemplate.animationSystem3P"):
			var parts = line.split(' ')
			if parts.size() >= 2:
				objectData["animationSystem3P"] = parts[1]
			
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
			
		elif line.begins_with("ObjectTemplate.geometryPart"):
			if currentTemplate != "" and objectData["geomPartData"].has(currentTemplate):
				objectData["geomPartData"][currentTemplate]["geometryPart"] = int(line.split(' ')[1])
			lastAddedChild = ""

		elif line.begins_with("ObjectTemplate.activeSafe"):
			var parts = line.split(' ')
			if parts.size() >= 3:
				currentTemplate = parts[2].to_lower()
			lastAddedChild = ""
			
		elif line.begins_with("ObjectTemplate.setPosition"):
			if lastAddedChild != "" and objectData["pendingParents"].has(lastAddedChild):
				var pv = line.split(' ')[1].split('/')
				objectData["pendingParents"][lastAddedChild]["position"] = [float(pv[0]), float(pv[1]), float(pv[2])]
				
		## setRotation — applies to the last addTemplate child if one is pending
		elif line.begins_with("ObjectTemplate.setRotation"):
			if lastAddedChild != "" and objectData["pendingParents"].has(lastAddedChild):
				var rv = line.split(' ')[1].split('/')
				objectData["pendingParents"][lastAddedChild]["rotation"] = [float(rv[0]), float(rv[1]), float(rv[2])]
		
		elif line.begins_with('ObjectTemplate.addTemplate'):
			lastAddedChild = ""
			
			var template = line.split(' ')[1]
			var childKey = template.to_lower()
			
			objectData["templates"].append([template, [0.0,0.0,0.0], [0.0,0.0,0.0]])

			## Register in pendingParents (first occurrence wins)
			if not objectData["pendingParents"].has(childKey):
				objectData["pendingParents"][childKey] = {
					"parent": currentTemplate,
					"position": [0.0, 0.0, 0.0],
					"rotation": [0.0, 0.0, 0.0],
				}
				lastAddedChild = childKey  ## position/rotation lines go to this child
			
		elif line.begins_with("ObjectTemplate.create"):
			lastAddedChild = ""  ## a new create block ends any addTemplate context
			if not line.begins_with("ObjectTemplate.createdInEditor") and \
			   not line.begins_with("ObjectTemplate.createComponent"):
				var parts = line.split(' ')
				if parts.size() >= 3:
					var objectType = parts[1]
					var objectName = parts[2]
					currentTemplate = objectName.to_lower()
					objectData['isSoldier'] = objectType == "Soldier"
					objectData["children"].append([objectType, objectName])
					if not objectData["geomPartData"].has(currentTemplate):
						objectData["geomPartData"][currentTemplate] = {
							"name": objectName, "geometryPart": -1,
							"parent": "", "position": [0.0,0.0,0.0], "rotation": [0.0,0.0,0.0],
						}
					
			else:
				print("SKIPPED: " + line)
			
		elif line.begins_with('include'):
			objectData["hasTweak"] = true
	file.close()
	return objectData

func processCon(conFile):
	var tweakFile = conFile.replace('.con', '.tweak')
	
	var objectData = {}
	objectData["objectName"] = ""
	objectData["meshType"] = ""
	objectData["objectType"] = ""
	objectData["geometryType"] = ""
	objectData["hasCollision"] = false
	objectData["hasCollisionPhysics"] = 0
	objectData["materials"] = {}
	objectData["anchor"] = [0.0, 0.0, 0.0]
	objectData["hasTweak"] = false
	objectData["lodDistance"] = []
	objectData["templates"] = []
	objectData["children"] = []
	objectData["geomPartData"] = {}
	objectData["pendingParents"] = {}
	objectData["skeleton1P"] = ""
	objectData["skeleton3P"] = ""
	objectData["animationSystem1P"] = ""
	objectData["animationSystem3P"] = ""
	objectData["isSoldier"] = false
	objectData = read_con_tweak(conFile, objectData)
	
	if objectData["hasTweak"]:
		var original_type = objectData['objectType']
		objectData = read_con_tweak(tweakFile, objectData)
		objectData['objectType'] = original_type
	

	
	## Apply pending parent relationships now that all templates are registered
	for childKey in objectData["pendingParents"].keys():
		var pending = objectData["pendingParents"][childKey]
		if objectData["geomPartData"].has(childKey):
			var entry = objectData["geomPartData"][childKey]
			## Only set if not already set by a previous pass
			if entry["parent"] == "":
				entry["parent"] = pending["parent"]
				entry["position"] = pending["position"]
				entry["rotation"] = pending["rotation"]

	## Build geomPartMap: geomIdx(int) → geomPartData entry
	var geomPartMap = {}
	for key in objectData["geomPartData"].keys():
		var entry = objectData["geomPartData"][key]
		if entry["geometryPart"] >= 0:
			geomPartMap[entry["geometryPart"]] = entry
	objectData["geomPartMap"] = geomPartMap

	print("\n--- geomPartMap ---")
	for idx in geomPartMap.keys():
		var e = geomPartMap[idx]
		print("  Geom %d → %s  (parent: '%s')" % [idx, e["name"], e["parent"]])
	return objectData

# --- BundledMesh ---
func importBundledMesh(mesh_file, objectData):
	var parser = preload("res://addons/bf2_godot/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	
	var mesh_name = objectData["objectName"]
	
	
	var root = Node3D.new()
	root.owner = root
	var mesh_root = Node3D.new()
	mesh_root.name = "root_" + mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)
	
	var visualMeshNode = Node3D.new()
	visualMeshNode.name = parsed_data.mesh_type.capitalize()
	mesh_root.add_child(visualMeshNode)
	visualMeshNode.set_owner(root)

	## partNodes and geomNodes only populated for bundled meshes
	var partNodes = {}
	var geomNodes = {}   ## file geom index → Node3D (for Geom0/Geom2)

	parser.create_part_meshes_bundled(parsed_data)
	var result = _buildBundledScene(parsed_data, visualMeshNode, objectData, root)
	partNodes = result[0]
	geomNodes = result[1]

	print("\n✓ Successfully created mesh hierarchy: %s" % mesh_name)
	return root


## Returns [partNodes, geomNodes]
##   partNodes: part_id(int) → Node3D  (the named part nodes inside Geom1)
##   geomNodes: file_geom_idx(int) → Node3D  (Geom0, Geom1 wrapper, Geom2)
func _buildBundledScene(parsed_data, visualMeshNode, objectData, root) -> Array:
	var geomPartMap = objectData["geomPartMap"]

	## Find the main geom (most LODs with parts_num > 1)
	var main_geom_idx = 0
	var best_lod_count = 0
	for gi in range(parsed_data.geoms.size()):
		var g = parsed_data.geoms[gi]
		if g.lods.size() > best_lod_count and g.lods.size() > 0 and g.lods[0].parts_num > 1:
			best_lod_count = g.lods.size()
			main_geom_idx = gi

	var main_geom = parsed_data.geoms[main_geom_idx]
	var num_parts = main_geom.lods[0].parts_num if main_geom.lods.size() > 0 else 0
	print("  Using Geom %d as main view (%d LODs, %d parts)" % [main_geom_idx, main_geom.lods.size(), num_parts])

	## geom_idx → Node3D for all file geoms (Geom0 shadow, Geom1 main, Geom2 wreck)
	var geomNodes = {}

	## Geom wrapper node for the main view
	var mainGeomNode = Node3D.new()
	mainGeomNode.name = "Geom%d" % main_geom_idx
	visualMeshNode.add_child(mainGeomNode)
	mainGeomNode.set_owner(root)
	geomNodes[main_geom_idx] = mainGeomNode

	## Step 1 — create one Node3D per part_id under the Geom wrapper
	## part_id → Node3D
	var partNodes = {}

	for part_id in range(num_parts):
		var entry = geomPartMap.get(part_id, null)
		var node_name = entry["name"] if entry else ("Part%d" % part_id)

		var part_node = Node3D.new()
		part_node.name = node_name
		mainGeomNode.add_child(part_node)
		part_node.set_owner(root)
		partNodes[part_id] = part_node

		## Attach LOD meshes for this part from the main geom
		var finalDistance = 0
		for lod_idx in range(main_geom.lods.size()):
			var lod = main_geom.lods[lod_idx]
			if part_id >= lod.parts.size():
				continue
			var lod_part = lod.parts[part_id]
			if lod_part == null or lod_part.mesh == null:
				continue

			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			part_node.add_child(lod_node)
			lod_node.set_owner(root)

			var mi = MeshInstance3D.new()
			mi.mesh = lod_part.mesh
			mi.name = "Mesh"
			lod_node.add_child(mi)
			mi.set_owner(root)

			_applyMaterials(mi, lod_part.materials)
			finalDistance = _applyLodRanges(mi, part_id, lod_idx, main_geom.lods.size(), objectData, finalDistance)

		print("  Created part %d: %s" % [part_id, node_name])

	## Step 3 — add the non-main geoms (shadow/wreck) as simple GeomN nodes
	for gi in range(parsed_data.geoms.size()):
		if gi == main_geom_idx:
			continue
		var other_geom = parsed_data.geoms[gi]
		var geom_node = Node3D.new()
		geom_node.name = "Geom%d" % gi
		visualMeshNode.add_child(geom_node)
		geom_node.set_owner(root)
		geomNodes[gi] = geom_node

		for lod_idx in range(other_geom.lods.size()):
			var lod = other_geom.lods[lod_idx]
			if lod.parts.size() == 0:
				continue
			var lod_part = lod.parts[0]
			if lod_part == null or lod_part.mesh == null:
				continue
			var lod_node = Node3D.new()
			lod_node.name = "LOD%d" % lod_idx
			geom_node.add_child(lod_node)
			lod_node.set_owner(root)
			var mi = MeshInstance3D.new()
			mi.mesh = lod_part.mesh
			mi.name = "Mesh"
			lod_node.add_child(mi)
			mi.set_owner(root)
			_applyMaterials(mi, lod_part.materials)
		print("  Created Geom%d (%d LODs)" % [gi, other_geom.lods.size()])

	## Step 2 — reparent part nodes to mirror the con file hierarchy
	for part_id in partNodes.keys():
		var entry = geomPartMap.get(part_id, null)
		if entry == null or entry["parent"] == "":
			continue
		var parentKey = entry["parent"]
		for parent_part_id in geomPartMap.keys():
			if geomPartMap[parent_part_id]["name"].to_lower() == parentKey:
				var child_node = partNodes[part_id]
				var parent_node = partNodes[parent_part_id]
				child_node.reparent(parent_node, false)
				var pos = entry["position"]
				var rot = entry["rotation"]
				child_node.position = Vector3(pos[0], pos[1], pos[2])
				child_node.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
				break

	return [partNodes, geomNodes]
	
# --- StaticMesh ---

func importStaticMesh(mesh_file, objectData) -> Node:
	var parser = preload("res://addons/bf2_godot/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	
	var mesh_name = objectData["objectName"]
	var root := Node3D.new()
	root.name = "root_" + mesh_name
	
	var mesh_index = 0
	var meshes = parser.create_array_meshes(parsed_data)
	
	var visualMeshNode = Node3D.new()
	visualMeshNode.name = "StaticMesh"
	root.add_child(visualMeshNode)
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
		importCollisionMesh(collision_mesh_path, root, objectData, root)
	
	var collisionMeshNode = root.find_child("CollisionMesh")
	var mesh_anchor = Marker3D.new()
	mesh_anchor.gizmo_extents = 5
	mesh_anchor.name = mesh_name + "_anchor"
	mesh_anchor.position.x = objectData["anchor"][0]
	mesh_anchor.position.y = objectData["anchor"][1]
	mesh_anchor.position.z = objectData["anchor"][2]
	root.add_child(mesh_anchor)
	mesh_anchor.set_owner(root)
	#visualMeshNode.reparent(mesh_anchor)
	if collisionMeshNode:
		collisionMeshNode.reparent(mesh_anchor)
	
	#mesh_anchor.position = Vector3(0, 0, 0)
	mesh_anchor.scale = Vector3(1.0, 1.0, -1.0)
	mesh_anchor.name = mesh_name + "_anchor"
	
	print("\n✓ Successfully created StaticMesh: %s" % mesh_name)
	
	# FLIP ROOT
	root.scale.z = -1
	return root

# --- SkinnedMesh ---

func importSkinnedMesh(mesh_file, objectData) -> Node:
#func importSkinnedMesh(mesh_file: String, objectData: Dictionary) -> void:
	var parser = preload("res://addons/bf2_mesh_importer/meshParser.gd").new()
	var parsed_data = parser.parse_bf2_mesh(mesh_file)
	var root = Node3D.new()
	if not root:
		print("ERROR: No scene root found!")
		return
 
	var mesh_name: String = objectData["objectName"]
 
	var mesh_root = Node3D.new()
	mesh_root.name = mesh_name
	root.add_child(mesh_root)
	mesh_root.set_owner(root)
 
	var mesh_index := 0
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
 
		var testBafPath = ""
		# Full soldier animation system — 3P only. 1P animations are weapon-view
		# specific and out of scope for the soldier importer.
		if objectData["isSoldier"] and skeleton_label == "3P" and skeleton3d != null:
			importSoldierAnimations(geom_node, skeleton3d, objectData, root)
			
		elif skeleton3d != null and testBafPath != "":
			var baf_parser = preload("res://addons/bf2_godot/BF2BafParser.gd").new()
			var animation: Animation = baf_parser.import_animation(testBafPath, skeleton3d, NodePath(skeleton3d.name))
			if animation != null:
				var anim_player = AnimationPlayer.new()
				anim_player.name = "AnimationPlayer"
				geom_node.add_child(anim_player)
				anim_player.set_owner(root)
				var lib := AnimationLibrary.new()
				lib.add_animation(animation.resource_name, animation)
				anim_player.add_animation_library("", lib)
				anim_player.play(animation.resource_name)
				print("  Playing test animation '%s' on Geom%d" % [animation.resource_name, geom_idx])
 
		var previous_lod_end := 0.0
 
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
 
				var matcount := 0
				for mat in lod.materials:
					apply_material(mesh_instance, mat, matcount, "SkinnedMesh")
					matcount += 1
 
				# Override every Skin bind pose with the value derived from the
				# already-verified-correct Skeleton3D rest transform. The file's
				# own per-bone bind matrix convention proved ambiguous/unreliable.
				# We keep the file's rig data only for WHICH bone each slot maps to.
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
				_set_lod_visibility(mesh_instance, lod_idx, geom.lods.size(), previous_lod_end, lod_end_distance)
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
	return root

func _set_lod_visibility(mesh_instance: MeshInstance3D, lod_idx: int, lod_count: int, previous_end: float, end_distance: float) -> void:
	if lod_idx == 0:
		mesh_instance.visibility_range_begin = 0.0
		mesh_instance.visibility_range_end = end_distance
	elif lod_idx == lod_count - 1:
		mesh_instance.visibility_range_begin = previous_end
		mesh_instance.visibility_range_end = 0.0
	else:
		mesh_instance.visibility_range_begin = previous_end
		mesh_instance.visibility_range_end = end_distance
		
# --- Soldier Animation System ---

func importSoldierAnimations(geom_node: Node3D, skeleton3d: Skeleton3D, objectData: Dictionary, root: Node):
	if objectData["animationSystem3P"] == "":
		print("  No animationSystem3P path found - skipping animation import")
		return
	
	var anim_sys_path = "res://" + objectData["animationSystem3P"].to_lower()
	
	var builder = preload("res://addons/bf2_godot/BF2AnimationBuilder.gd").new()
	var built = builder.build(anim_sys_path, skeleton3d)
	if built["library"] == null:
		return
	
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	geom_node.add_child(anim_player)
	anim_player.set_owner(root)
	anim_player.add_animation_library("", built["library"])
	
	# Wrap the movement state machine in a BlendTree with a filtered upper-body
	# layer reserved for weapon animations. Defaults to blend_amount 0.0 (fully
	# "lower_body"/movement) - arms naturally rest-pose since movement clips carry
	# no arm tracks. A runtime weapon-equip script builds a NEW state machine the
	# same way (via BF2AnimationBuilder, from the weapon's own
	# AnimationSystem3p.inc) and swaps it into the "upper_body" slot.
	const UPPER_BODY_ROOT_BONE := "torso"
	var upper_body_bones := _collect_bone_and_descendants(skeleton3d, UPPER_BODY_ROOT_BONE)
	
	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node("lower_body", built["state_machine"], Vector2(-300, 0))
	
	var upper_body_slot := AnimationNodeAnimation.new()
	blend_tree.add_node("upper_body", upper_body_slot, Vector2(-300, 250))
	
	var blend2 := AnimationNodeBlend2.new()
	blend2.filter_enabled = true
	if upper_body_bones.size() > 0:
		for bone_idx in upper_body_bones:
			var bone_name: String = skeleton3d.get_bone_name(bone_idx)
			blend2.set_filter_path(NodePath(str(skeleton3d.name) + ":" + bone_name), true)
	else:
		push_warning("Upper-body root bone '%s' not found on skeleton - weapon layer filter will be empty" % UPPER_BODY_ROOT_BONE)
	blend_tree.add_node("upper_body_blend", blend2, Vector2(0, 125))
	
	blend_tree.connect_node("upper_body_blend", 0, "lower_body")
	blend_tree.connect_node("upper_body_blend", 1, "upper_body")
	blend_tree.connect_node("output", 0, "upper_body_blend")
	
	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = blend_tree
	geom_node.add_child(anim_tree)
	anim_tree.set_owner(root)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	anim_tree["parameters/upper_body_blend/blend_amount"] = 0.0
	
	print("  Built AnimationTree: BlendTree(lower_body=StateMachine[%d bundles], upper_body=weapon slot filtered to %d bone(s) under '%s')" % [built["bundle_count"], upper_body_bones.size(), UPPER_BODY_ROOT_BONE])

func _collect_bone_and_descendants(skeleton: Skeleton3D, bone_name: String) -> Array:
	var result: Array = []
	var root_idx := skeleton.find_bone(bone_name)
	if root_idx < 0:
		return result
	var stack := [root_idx]
	while stack.size() > 0:
		var idx = stack.pop_back()
		result.append(idx)
		for child_idx in skeleton.get_bone_children(idx):
			stack.append(child_idx)
	return result

# --- Shared helpers ---

func get_lod_distance(lod_distances: Array, geom_idx: int, lod_idx: int) -> float:
	for lod_data in lod_distances:
		if lod_data[0] == geom_idx and lod_data[1] == lod_idx:
			return float(lod_data[2])
	return 0.0


## ── Material application ─────────────────────────────────────────────────
func _applyMaterials(mesh_instance, materials):
	var matcount = 0
	for mat in materials:
		if mat.maps.size() == 0:
			matcount += 1
			continue
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
		if mat.technique == "ColormapGloss":
			new_material.set_shader_parameter("DiffuseTexture", load("res://" + mat.maps[0]))
			new_material.set_shader_parameter("NormalTexture", load("res://" + mat.maps[1]))
		if mat.technique == "EnvMapColormapGloss":
			new_material.set_shader_parameter("DiffuseTexture", load("res://" + mat.maps[0]))
			new_material.set_shader_parameter("NormalTexture", load("res://" + mat.maps[1]))
			new_material.set_shader_parameter("EnvMapTexture", load("res://" + mat.maps[2]))
		if mat.technique == "Alpha_TestColormapGloss":
			new_material.set_shader_parameter("DiffuseTexture", load("res://" + mat.maps[0]))
			new_material.set_shader_parameter("NormalTexture", load("res://" + mat.maps[1]))
		mesh_instance.set_surface_override_material(matcount, new_material)
		matcount += 1

## ── LOD visibility ranges ────────────────────────────────────────────────
func _applyLodRanges(mesh_instance, geom_idx, lod_idx, lod_count, objectData, finalDistance):
	var counter = 0
	for entry in objectData["lodDistance"]:
		if entry[0] == geom_idx and entry[1] == lod_idx:
			if lod_idx == 0:
				mesh_instance.visibility_range_end = entry[2]
			elif lod_idx > 0:
				if counter > 0:
					mesh_instance.visibility_range_begin = objectData["lodDistance"][counter - 1][2]
				mesh_instance.visibility_range_end = entry[2]
				finalDistance = entry[2]
		counter += 1
	if lod_idx == lod_count - 1:
		mesh_instance.visibility_range_begin = finalDistance
	return finalDistance
	
	
func apply_material(mesh_instance: MeshInstance3D, mat, matcount: int, force_technique: String = ""):
	if not mesh_instance.mesh:
		return
		
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
				new_material.set_shader_parameter("Colour", load("res://" + mat.maps[0]))
			if mat.maps.size() > 1:
				new_material.set_shader_parameter("Normal_os", load("res://" + mat.maps[1]))
			if mat.maps.size() > 2:
				new_material.set_shader_parameter("Normal_b", load("res://" + mat.maps[2]))
		
		_:
			print("    NOTE: Unmapped technique '%s' (maps=%d) - applying generic BaseTexture fallback." % [technique_key, mat.maps.size()])
			if mat.maps.size() > 0:
				new_material.set_shader_parameter("BaseTexture", load("res://" + mat.maps[0]))
	
	mesh_instance.set_surface_override_material(matcount, new_material)

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
		var position = Vector3(template_data[1][0], template_data[1][1], template_data[1][2])
		var rotation = Vector3(template_data[2][0], template_data[2][1], template_data[2][2])
		
		var node = find_node_by_name(vehicle_root, template_name)
		if node:
			node.position = position
			node.rotation_degrees = rotation
			
			# Compensate mesh instance vertices so global offset isn't applied twice
			for child in node.get_children():
				if child.name.begins_with("LOD"):
					for mesh_inst in child.get_children():
						if mesh_inst is MeshInstance3D:
							mesh_inst.position = -position
			print("  Applied transform to %s: pos=%s rot=%s" % [template_name, node.position, node.rotation_degrees])

func find_node_by_name(parent: Node, node_name: String) -> Node:
	if parent.name == node_name:
		return parent
	for child in parent.get_children():
		var result = find_node_by_name(child, node_name)
		if result:
			return result
	return null

# root is now passed explicitly (was previously fetched via
# vehicle_root.get_tree().edited_scene_root, which only works inside a live, open
# scene tree - not true during standalone construction).
func importCollisionMeshToParts(collision_mesh_path: String, root: Node3D, objectData: Dictionary, part_count: int):
	var reader = preload("res://addons/bf2_godot/BF2CollisionMeshparser.gd").new()
	
	if not FileAccess.file_exists(collision_mesh_path):
		print("No collision mesh found")
		return
	
	var collision_meshes = reader.import_collision_mesh(collision_mesh_path)
	
	for i in range(min(collision_meshes.size(), part_count)):
		var part_node = root.get_child(i)
		
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.mesh = collision_meshes[i]
		mesh_instance.name = "Collision_" + collision_meshes[i].resource_name
		mesh_instance.visible = false
		part_node.add_child(mesh_instance)
		mesh_instance.set_owner(root)
		mesh_instance.create_trimesh_collision()
		
		var col_body = mesh_instance.get_child(0)
		if col_body and col_body is StaticBody3D:
			setup_collision_layers(col_body, collision_meshes[i].resource_name)

# bf2_scene_builder.gd -> importCollisionMesh()
func importCollisionMesh(collision_mesh_path: String, root: Node, objectData: Dictionary, mesh_root: Node3D):
	var reader = preload("res://addons/bf2_godot/BF2CollisionMeshparser.gd").new()
	
	if not FileAccess.file_exists(collision_mesh_path):
		print("No collision mesh found")
		return
	
	var collision_meshes = reader.create_collision_meshes(reader.parse_collision_mesh(collision_mesh_path))
	
	var colNode = Node3D.new()
	colNode.name = "CollisionMesh"
	mesh_root.add_child(colNode)
	colNode.visible = false
	
	for i in range(collision_meshes.size()):
		var col_mesh = collision_meshes[i]
		var shape = col_mesh.create_trimesh_shape()
		if shape:
			var col_body = StaticBody3D.new()
			col_body.name = col_mesh.resource_name + "_body"
			
			var col_shape_node = CollisionShape3D.new()
			col_shape_node.name = "CollisionShape3D"
			col_shape_node.shape = shape
			
			col_body.add_child(col_shape_node)
			colNode.add_child(col_body)
			setup_collision_layers(col_body, col_mesh.resource_name)
			
	## Ensure collision is the same direction as the mesh
	#colNode.scale.z = -1

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
