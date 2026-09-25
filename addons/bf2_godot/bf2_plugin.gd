
# plugin.gd
# Adds a manual "Import BF2 Object" dock instead of automatic EditorImportPlugin
# recognition. Automatic import-on-scan was retired: it runs synchronously on the
# main thread on EVERY project scan (including editor startup), so a hang/crash in
# any single .con/.staticmesh/.bundledmesh/.skinnedmesh file can freeze the whole
# editor on every future launch until manually disabled. A manual, one-file-at-a-time
# trigger avoids that entirely and matches the actual desired workflow (deliberate
# .con-by-.con importing, not mass project scanning).

@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://addons/bf2_godot/bf2_import_dock.gd").new()
	dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
