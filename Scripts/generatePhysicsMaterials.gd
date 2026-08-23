@tool
extends EditorScript


func _run():
	var path = "res://Common/Material/materialManagerDefine.con"
	var file = FileAccess.open(path, FileAccess.READ)
	
	var materials = []
	var currentDict = {}

	if file == null:
		print("Error opening file: ", FileAccess.get_open_error())
		return
	while not file.eof_reached():
		var matCount = 0
		var line = file.get_line().strip_edges()
		var active : int
		var name : String
		var type : int
		var friction: float
		var elasticity: int
		var resistance : float
		var damageLoss : int
		var minDamageLoss : int
		var maxDamageLoss : int
		var penetrationDeviation: int
		var hasWaterPhysics : bool
		var projectileCollisionHardness : float
		var overrideNeverPenetrate : bool
		var isSeeThrough : bool
		
		#if line.is_empty() or line.begins_with("//") or line.begins_with("rem"):
			#continue
		
		
		
		## GDSCRIPT uses friction, rough TRUE/FALSE, bounce, Aborbent True/False	
		
		if line.begins_with("Material.active"):
			active = int(line.split(' ')[1])
			currentDict["active"] = active
			
		elif line.begins_with("Material.name"):
			name = line.split(' ')[1].split('"')[1].split('"')[0]
			currentDict["name"] = name
		
		elif line.begins_with("Material.type"):
			type = int(line.split(' ')[1])
			currentDict["type"] = type
			
		elif line.begins_with("Material.friction"):
			friction = float(line.split(' ')[1])
			currentDict["friction"] = friction

		elif line.begins_with("Material.elasticity"):
			elasticity = int(line.split(' ')[1])
			currentDict["elasticity"] = elasticity
			
		elif line.begins_with("Material.resistance"):
			resistance = float(line.split(' ')[1])
			currentDict["resistance"] = resistance

			
		if line.is_empty():
			materials.append(currentDict)
			matCount = matCount + 1
			currentDict = {}
			
	
	
	## Create the resources
	
	var matdb = MaterialDatabase.new()
	
	for mat in materials:
		
		if mat != { }:
			var bf2_mat = BF2PhysicsMaterial.new()
			bf2_mat.active = mat.active
			bf2_mat.name = mat.name
			bf2_mat.type = mat.type
			bf2_mat.friction = mat.friction
			bf2_mat.resistance = mat.resistance
			
			var godotPhysicsMaterial = PhysicsMaterial.new()
			godotPhysicsMaterial.friction = mat.friction
			godotPhysicsMaterial.bounce = mat.elasticity
			
			bf2_mat.physics_material = godotPhysicsMaterial
			
			matdb.materials_by_id[bf2_mat.active] = bf2_mat
			
		# Save the entire MaterialDatabase resource to disk
	var save_path = "res://Common/Material/bf2_material_database.tres"
	var error = ResourceSaver.save(matdb, save_path)

	if error == OK:
		print("Successfully saved MaterialDatabase to %s" % save_path)
	else:
		print("Error saving database: %s" % error)
