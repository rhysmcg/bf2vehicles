# bf2_con_importer.gd
# EditorImportPlugin: makes .con files a recognized, auto-importing asset type.
# Builds a full BF2 object (mesh/skin/skeleton/collision/soldier animations, per
# bf2_scene_builder.gd) and saves it as a PackedScene - the same workflow as
# Godot's built-in glTF/FBX importers.

@tool
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "bf2.con_importer"

func _get_visible_name() -> String:
	return "BF2 Object (.con)"

func _get_recognized_extensions() -> PackedStringArray:
	return ["con"]

func _get_save_extension() -> String:
	return "scn"

func _get_resource_type() -> String:
	return "PackedScene"

func _get_priority() -> float:
	return 1.0

func _get_import_order() -> int:
	return 0

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Default"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return []

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

# Helper snippet inside your builder or importer:
func _set_owner_recursive(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_set_owner_recursive(child, root)

	
func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var builder = preload("res://addons/bf2_godot/bf2_scene_builder.gd").new()
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()

	var line = file.get_line()
	print(source_file)
	print(line)
	print("LETS test CON FILE IMPORTS")

	# 1. Create the root node
	var root_node := Node3D.new()
	root_node.name = source_file.get_file().get_basename()



	# Free the temporary node memory after packing
	
	root_node = builder.build_scene_from_con(source_file)
	
	var packed_scene := PackedScene.new()
	if root_node != null:
		_set_owner_recursive(root_node, root_node)
		var pack_result = packed_scene.pack(root_node)
		root_node.queue_free()
	
		if pack_result != OK:
			push_error("Failed to pack scene for %s (error %d)" % [source_file, pack_result])
			return pack_result
	else:
		print("root node is null!")
	
	var output_filename := "%s.%s" % [save_path, _get_save_extension()]
	return ResourceSaver.save(packed_scene, output_filename)
	
