@tool
extends EditorPlugin

var importer

func _enter_tree():
	importer = preload("res://addons/dds_permissive_importer/import_dds.gd").new()
	add_import_plugin(importer)
	print("DDS Importer Registered")

func _exit_tree():
	remove_import_plugin(importer)
