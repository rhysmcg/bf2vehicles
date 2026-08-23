extends Resource
class_name MaterialDatabase

# Use an exported dictionary to store materials, keyed by their 'active' ID
# The key type is int, the value type is your custom resource
@export var materials_by_id: Dictionary = {} 

func get_material_by_id(id_num: int) -> BF2PhysicsMaterial:
	if materials_by_id.has(id_num):
		return materials_by_id[id_num]
	else:
		print("Error: Material ID %s not found in Database." % id_num)
		return null
