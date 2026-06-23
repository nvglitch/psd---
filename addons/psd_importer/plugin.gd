@tool
extends EditorPlugin

var importer: EditorImportPlugin


func _enter_tree() -> void:
	importer = load("res://addons/psd_importer/psd_importer.gd").new()
	add_import_plugin(importer)
	print_rich("[color=cyan][PSD Importer][/color] Plugin enabled — .psd files will be auto-imported.")


func _exit_tree() -> void:
	if importer:
		remove_import_plugin(importer)
		importer = null
	print_rich("[color=gray][PSD Importer][/color] Plugin disabled.")
