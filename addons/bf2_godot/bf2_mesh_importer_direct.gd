# bf2_mesh_importer_direct.gd
# EditorImportPlugin for standalone .staticmesh/.bundledmesh/.skinnedmesh files
# (no accompanying .con) - geometry + materials only, since collision and skeleton
# paths are only known via a .con file. Useful for quickly previewing a single mesh.

@tool
extends EditorImportPlugin

func _get_importer_name() -> String:
	return "bf2.mesh_importer"

func _get_visible_name() -> String:
	return "BF2 Mesh (.staticmesh/.bundledmesh/.skinnedmesh)"

func _get_recognized_extensions() -> PackedStringArray:
	return ["staticmesh", "bundledmesh", "skinnedmesh"]

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

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var builder = preload("res://addons/bf2_godot/bf2_scene_builder.gd").new()
	var scene_root: Node = builder.build_scene_from_raw_mesh(source_file)
	
	if scene_root == null:
		push_error("BF2 mesh import failed for %s" % source_file)
		return ERR_PARSE_ERROR
	
	var packed_scene := PackedScene.new()
	var pack_result := packed_scene.pack(scene_root)
	scene_root.queue_free()
	
	if pack_result != OK:
		push_error("Failed to pack scene for %s (error %d)" % [source_file, pack_result])
		return pack_result
	
	return ResourceSaver.save(packed_scene, "%s.%s" % [save_path, _get_save_extension()])
