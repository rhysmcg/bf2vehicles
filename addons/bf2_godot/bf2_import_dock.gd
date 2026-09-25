# bf2_import_dock.gd
# Manual import dock: pick ONE .con file, click Import, it's built and added as a
# child of whatever scene you currently have open in the editor (same convenience
# as the old "File -> Run" EditorScript workflow, but with a file picker instead of
# a hardcoded path). No automatic scanning of the project - you control exactly
# when and what gets imported.

@tool
extends VBoxContainer

var editor_plugin: EditorPlugin

var path_label: Label
var status_label: Label
var file_dialog: EditorFileDialog
var selected_path: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)
	
	var title := Label.new()
	title.text = "BF2 Object Importer"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	
	add_child(HSeparator.new())
	
	var browse_button := Button.new()
	browse_button.text = "Browse for .con file..."
	browse_button.pressed.connect(_on_browse_pressed)
	add_child(browse_button)
	
	path_label = Label.new()
	path_label.text = "(no file selected)"
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(path_label)
	
	add_child(HSeparator.new())
	
	var import_button := Button.new()
	import_button.text = "Import into current scene"
	import_button.pressed.connect(_on_import_pressed)
	add_child(import_button)
	
	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	file_dialog.add_filter("*.con", "BF2 Object Definition")
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

func _on_browse_pressed() -> void:
	file_dialog.popup_centered_ratio(0.6)

func _on_file_selected(path: String) -> void:
	selected_path = path
	path_label.text = path
	status_label.text = ""

func _on_import_pressed() -> void:
	if selected_path == "":
		status_label.text = "Pick a .con file first."
		return
	
	var root := editor_plugin.get_editor_interface().get_edited_scene_root()
	if not root:
		status_label.text = "ERROR: no scene open - create/open a scene first."
		return
	
	status_label.text = "Importing..."
	
	var builder = preload("res://addons/bf2_godot/bf2_scene_builder.gd").new()
	var built: Node = builder.build_scene_from_con(selected_path)
	
	if built == null:
		status_label.text = "Import FAILED - check the Output panel for details."
		return
	
	root.add_child(built)
	built.owner = root
	_reown_recursive(built, root)
	
	status_label.text = "Imported '%s'. Remember to save the scene." % built.name

# The builder already sets owner=root for everything it created (using its OWN
# temporary root as the owner reference), but that temporary root isn't the same
# node as the actual open scene's root - re-point ownership at the real root so
# everything gets saved when you save the scene.
func _reown_recursive(node: Node, real_root: Node) -> void:
	for child in node.get_children():
		child.owner = real_root
		_reown_recursive(child, real_root)
