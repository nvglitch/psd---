@tool
# psd_importer.gd — EditorImportPlugin: converts .psd → .tscn scene file
#
# Registered by plugin.gd via add_import_plugin().
#
# On import:
#   1. Parse PSD binary → layer tree + per-layer RGBA8 images
#   2. Build node tree (Control / Node2D) with embedded ImageTextures
#   3. Pack into a PackedScene and return it (Godot saves it)

extends EditorImportPlugin


# ══════════════════════════════════════════════════════════════════════
# EditorImportPlugin interface
# ══════════════════════════════════════════════════════════════════════

func _get_importer_name() -> String:
	return "psd_importer_v1"


func _get_visible_name() -> String:
	return "PSD Layers (V1)"


func _get_recognized_extensions() -> PackedStringArray:
	return ["psd"]


func _get_save_extension() -> String:
	return "tscn"


func _get_resource_type() -> String:
	return "PackedScene"


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 2


func _get_preset_name(preset_index: int) -> String:
	match preset_index:
		0: return "2D Sprites"
		1: return "UI (Control)"
		_: return "Custom"


func _get_preset_options(preset_index: int) -> Dictionary:
	match preset_index:
		0: return {"root_type": 0}
		1: return {"root_type": 1}
		_: return {"root_type": 1}


func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [
		{
			"name": "root_type",
			"default_value": 1,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": "Node2D,Control",
		},
		{
			"name": "import_text_layers",
			"default_value": true,
			"property_hint": PROPERTY_HINT_NONE,
		},
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


# ══════════════════════════════════════════════════════════════════════
# Core import logic
# ══════════════════════════════════════════════════════════════════════

func _import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	platform_variants: Array[String],
	gen_files: Array[String]
) -> Error:

	print_rich("[color=cyan][PSD Importer][/color] Importing: ", source_file)

	# ── 1. Parse PSD ──
	var parser := PSDParser.new()
	var err := parser.parse(source_file)
	if err != OK:
		printerr("[PSD Importer] Parse failed: ", source_file, " (err=", err, ")")
		return err

	if parser.layers.is_empty():
		printerr("[PSD Importer] No layers found: ", source_file)
		return ERR_FILE_CORRUPT

	print_rich("[PSD Importer] %d top-level layers, %dx%d" % [
		parser.layers.size(), parser.psd_width, parser.psd_height
	])

	# ── 2. Build scene (textures embedded as ImageTexture) ──
	var builder := PSDSceneBuilder.new()
	builder.root_type = options.get("root_type", PSDSceneBuilder.RootType.CONTROL) as int

	var root := builder.build(parser)

	# Count total nodes
	var node_count := _count_nodes(root)
	print_rich("[PSD Importer] Scene built: %d nodes" % node_count)

	# ── 3. Pack scene ──
	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		printerr("[PSD Importer] Pack failed: ", pack_err)
		if is_instance_valid(root):
			root.free()
		return pack_err

	if is_instance_valid(root):
		root.free()

	# ── 4. Save .tscn via ResourceSaver ──
	var save_err := ResourceSaver.save(packed, save_path + ".tscn")
	if save_err != OK:
		printerr("[PSD Importer] Save failed: ", save_err)
		return save_err

	print_rich("[color=green][PSD Importer][/color] Import OK → ", save_path, ".tscn")
	return OK


func _count_nodes(node: Node) -> int:
	if node == null:
		return 0
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
