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
		if layer.has_text:
			var td: Dictionary = layer.text_data
			print("%sTEXT name=\"%s\" clip=%s text=\"%s\" size=%s raw_size=%s scale=%s color=%s bounds=(%d,%d,%d,%d) keys=%s" % [
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
				str(layer.info_keys),
			])
		elif layer.is_group:
			print("%sGROUP name=\"%s\" clip=%s children=%d keys=%s" % [
				indent,
				layer.name,
				str(layer.is_clipping_mask),
				layer.children.size(),
				str(layer.info_keys),
			])
		elif layer.is_clipping_mask:
			print("%sCLIP name=\"%s\" bounds=(%d,%d,%d,%d) keys=%s" % [
				indent,
				layer.name,
				layer.left,
				layer.top,
				layer.right,
				layer.bottom,
				str(layer.info_keys),
			])

		if not layer.children.is_empty():
			_dump_layers(layer.children, indent + "  ")
