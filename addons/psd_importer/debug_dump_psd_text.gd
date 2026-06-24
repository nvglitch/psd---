@tool
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("Usage: godot --headless --script res://addons/psd_importer/debug_dump_psd_text.gd -- <psd-path>")
		quit(1)
		return

	var parser := PSDParser.new()
	var err := parser.parse(args[0])
	if err != OK:
		printerr("PSD parse failed: ", err)
		quit(err)
		return

	print("PSD: ", args[0], "  canvas=", parser.psd_width, "x", parser.psd_height)
	_dump_layers(parser.layers, "")
	quit()


func _dump_layers(layers: Array, indent: String) -> void:
	for layer in layers:
		var mask_text := _mask_text(layer.mask_info)
		if layer.has_text:
			var td: Dictionary = layer.text_data
			print("%sTEXT name=\"%s\" clip=%s text=\"%s\" size=%s raw_size=%s scale=%s color=%s bounds=(%d,%d,%d,%d)%s keys=%s" % [
				indent,
				layer.name,
				str(layer.is_clipping_mask),
				td.get("text", ""),
				str(td.get("size", "<missing>")),
				str(td.get("raw_size", "<missing>")),
				str(td.get("transform_scale", "<missing>")),
				str(td.get("color", "<missing>")),
				layer.left,
				layer.top,
				layer.right,
				layer.bottom,
				mask_text,
				str(layer.info_keys),
			])
		elif layer.is_group:
			print("%sGROUP name=\"%s\" clip=%s children=%d%s keys=%s" % [
				indent,
				layer.name,
				str(layer.is_clipping_mask),
				layer.children.size(),
				mask_text,
				str(layer.info_keys),
			])
		elif layer.is_clipping_mask:
			print("%sCLIP name=\"%s\" bounds=(%d,%d,%d,%d)%s keys=%s" % [
				indent,
				layer.name,
				layer.left,
				layer.top,
				layer.right,
				layer.bottom,
				mask_text,
				str(layer.info_keys),
			])
		else:
			print("%sBITMAP name=\"%s\" clip=%s opacity=%.3f blend=%s bounds=(%d,%d,%d,%d)%s keys=%s" % [
				indent,
				layer.name,
				str(layer.is_clipping_mask),
				layer.opacity,
				layer.blend_mode,
				layer.left,
				layer.top,
				layer.right,
				layer.bottom,
				mask_text,
				str(layer.info_keys),
			])

		if not layer.children.is_empty():
			_dump_layers(layer.children, indent + "  ")


func _mask_text(mask_info: Dictionary) -> String:
	var length := int(mask_info.get("length", 0))
	if length <= 0:
		return ""
	return " mask={len=%d bounds=(%d,%d,%d,%d) default=%s flags=%s disabled=%s}" % [
		length,
		int(mask_info.get("left", 0)),
		int(mask_info.get("top", 0)),
		int(mask_info.get("right", 0)),
		int(mask_info.get("bottom", 0)),
		str(mask_info.get("default_color", "?")),
		str(mask_info.get("flags", "?")),
		str(mask_info.get("disabled", "?")),
	]
