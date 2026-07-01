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
		{
			"name": "apply_basic_blend_modes",
			"default_value": false,
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

	# ── 2. Write layer images as PNG files ──
	var texture_dir := _generated_texture_dir(source_file)
	var tex_err := _write_layer_textures(parser.layers, texture_dir, gen_files)
	if tex_err != OK:
		printerr("[PSD Importer] Texture export failed: ", tex_err)
		return tex_err

	# ── 3. Build scene (textures reference generated PNG files) ──
	var builder := PSDSceneBuilder.new()
	builder.root_type = options.get("root_type", PSDSceneBuilder.RootType.CONTROL) as int
	builder.apply_basic_blend_modes = bool(options.get("apply_basic_blend_modes", false))

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


func _generated_texture_dir(source_file: String) -> String:
	var base_name := source_file.get_file().get_basename()
	return "res://psd_generated/%s_layers" % _ascii_slug(base_name)


func _write_layer_textures(layers: Array, texture_dir: String, gen_files: Array[String]) -> Error:
	var abs_dir := ProjectSettings.globalize_path(texture_dir)
	_clear_generated_dir(abs_dir)
	var make_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if make_err != OK:
		return make_err

	var used_names := {}
	var counter := [0]
	var err := _write_layer_textures_recursive(layers, texture_dir, used_names, counter, gen_files)
	if err != OK:
		return err
	return OK


func _write_layer_textures_recursive(layers: Array, texture_dir: String, used_names: Dictionary, counter: Array, gen_files: Array[String]) -> Error:
	for layer in layers:
		if layer == null:
			continue
		if layer.children.size() > 0:
			var child_err := _write_layer_textures_recursive(layer.children, texture_dir, used_names, counter, gen_files)
			if child_err != OK:
				return child_err

		if layer.image == null:
			continue

		_expand_layer_for_effects(layer)

		counter[0] = int(counter[0]) + 1
		var file_name := _unique_texture_name(layer.name, int(counter[0]), used_names)
		var res_path := "%s/%s.png" % [texture_dir, file_name]
		var save_err: Error = layer.image.save_png(res_path)
		if save_err != OK:
			return save_err
		layer.texture_path = res_path
		gen_files.append(res_path)

	return OK


func _expand_layer_for_effects(layer) -> void:
	if layer.image == null:
		return
	var pad := _effect_padding(layer.effects)
	if pad.x <= 0 and pad.y <= 0 and pad.z <= 0 and pad.w <= 0:
		return

	var old_img: Image = layer.image
	var new_w := old_img.get_width() + int(pad.x) + int(pad.z)
	var new_h := old_img.get_height() + int(pad.y) + int(pad.w)
	if new_w <= old_img.get_width() or new_h <= old_img.get_height():
		return

	var new_img := Image.create(new_w, new_h, false, Image.FORMAT_RGBA8)
	new_img.fill(Color(0, 0, 0, 0))
	new_img.blit_rect(old_img, Rect2i(Vector2i.ZERO, old_img.get_size()), Vector2i(int(pad.x), int(pad.y)))
	layer.image = new_img
	layer.left -= int(pad.x)
	layer.top -= int(pad.y)
	layer.right += int(pad.z)
	layer.bottom += int(pad.w)


func _effect_padding(effects: Dictionary) -> Vector4i:
	var left := 0
	var top := 0
	var right := 0
	var bottom := 0

	if effects.has("stroke"):
		var stroke: Dictionary = effects["stroke"]
		var amount := int(ceil(max(0.0, float(stroke.get("size", 0.0)))))
		left = max(left, amount)
		top = max(top, amount)
		right = max(right, amount)
		bottom = max(bottom, amount)

	if effects.has("outer_glow"):
		var glow: Dictionary = effects["outer_glow"]
		var amount := int(ceil(max(0.0, float(glow.get("size", 0.0)))))
		left = max(left, amount)
		top = max(top, amount)
		right = max(right, amount)
		bottom = max(bottom, amount)

	if effects.has("drop_shadow"):
		var shadow: Dictionary = effects["drop_shadow"]
		var angle := deg_to_rad(float(shadow.get("angle", 135.0)))
		var distance := float(shadow.get("distance", 0.0))
		var blur := max(0.0, float(shadow.get("size", 0.0)))
		var offset := Vector2(cos(angle), -sin(angle)) * distance
		left = max(left, int(ceil(blur + max(0.0, -offset.x))))
		top = max(top, int(ceil(blur + max(0.0, -offset.y))))
		right = max(right, int(ceil(blur + max(0.0, offset.x))))
		bottom = max(bottom, int(ceil(blur + max(0.0, offset.y))))

	return Vector4i(left, top, right, bottom)


func _clear_generated_dir(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		var path := abs_dir.path_join(entry)
		if dir.current_is_dir():
			_clear_generated_dir(path)
			DirAccess.remove_absolute(path)
		else:
			DirAccess.remove_absolute(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _unique_texture_name(layer_name: String, index: int, used_names: Dictionary) -> String:
	var base := "%04d_%s" % [index, _ascii_slug(layer_name)]
	if base.length() > 80:
		base = base.substr(0, 80)
	var name := base
	var suffix := 2
	while used_names.has(name):
		name = "%s_%d" % [base, suffix]
		suffix += 1
	used_names[name] = true
	return name


func _sanitize_path_part(raw: String) -> String:
	var s := raw.replace("/", "_").replace("\\", "_").replace(":", "_")
	s = s.replace("*", "_").replace("?", "_").replace('"', "'")
	s = s.replace("<", "_").replace(">", "_").replace("|", "_")
	s = s.strip_edges()
	return s if not s.is_empty() else "Layer"


func _ascii_slug(raw: String) -> String:
	var s := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 48 and c <= 57:
			s += char(c)
		elif c >= 65 and c <= 90:
			s += char(c)
		elif c >= 97 and c <= 122:
			s += char(c)
		else:
			s += "_"
	while s.find("__") >= 0:
		s = s.replace("__", "_")
	s = s.strip_edges()
	while s.begins_with("_"):
		s = s.substr(1)
	while s.ends_with("_"):
		s = s.substr(0, s.length() - 1)
	return s if not s.is_empty() else "layer"
