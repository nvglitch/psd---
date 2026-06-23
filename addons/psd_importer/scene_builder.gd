@tool
# scene_builder.gd — Build a Godot node tree from PSDParser.LayerData.
#
# Supports two root types:
#   "Control"  → TextureRect + Label + Control (for UI)
#   "Node2D"   → Sprite2D  + Label + Node2D  (for 2D sprites)
#
# Textures are embedded as ImageTexture directly (no external files).
# Adjustment layers are skipped (they have no meaningful pixel content for Godot).

class_name PSDSceneBuilder
extends RefCounted


enum RootType {
	NODE_2D,
	CONTROL,
}


# ══════════════════════════════════════════════════════════════════════
# Public
# ══════════════════════════════════════════════════════════════════════

var root_type: RootType = RootType.CONTROL
var canvas_size: Vector2 = Vector2.ZERO


func build(parser: PSDParser) -> Node:
	"""Build and return the root Node from parsed PSD data, with textures embedded."""
	canvas_size = Vector2(float(parser.psd_width), float(parser.psd_height))
	var root: Node
	match root_type:
		RootType.CONTROL:
			root = Control.new()
		RootType.NODE_2D:
			root = Node2D.new()
		_:
			root = Control.new()

	root.name = _sanitize_name("PSD_Scene")
	if root is Control:
		root.size = canvas_size
		root.clip_contents = true

	_add_layers_with_clipping(root, _drawing_order(parser.layers), Vector2.ZERO)
	for child in root.get_children():
		_set_owner_recursive(child, root)

	return root


# ══════════════════════════════════════════════════════════════════════
# Internal node builders
# ══════════════════════════════════════════════════════════════════════

func _build_node(layer, parent_origin: Vector2 = Vector2.ZERO) -> Node:
	if layer == null:
		return null

	# Skip true adjustment layers
	if layer.is_adjustment:
		return null

	if layer.is_group:
		return _build_group(layer, parent_origin)
	if layer.is_group_end:
		return null

	# Solid color fill → ColorRect
	if layer.is_solid_color:
		return _build_solid_color(layer, parent_origin)

	# Text layer → Label
	if layer.has_text:
		return _build_label(layer, parent_origin)

	# Smart object or regular bitmap layer → TextureRect / Sprite2D
	return _build_texture_node(layer, parent_origin)


func _build_group(layer, parent_origin: Vector2) -> Node:
	var node: Node
	match root_type:
		RootType.CONTROL:
			node = Control.new()
		RootType.NODE_2D:
			node = Node2D.new()

	node.name = _sanitize_name(layer.name)
	node.visible = layer.visible
	_apply_position(node, layer, parent_origin)
	_apply_size(node, layer)
	_apply_opacity(node, layer)

	var group_origin := Vector2(float(layer.left), float(layer.top))
	_add_layers_with_clipping(node, _drawing_order(layer.children), group_origin)

	return node


func _add_layers_with_clipping(parent: Node, ordered_layers: Array, parent_origin: Vector2) -> void:
	var i := 0
	while i < ordered_layers.size():
		var layer = ordered_layers[i]
		if layer == null or layer.is_group_end:
			i += 1
			continue
		if layer.is_clipping_mask:
			i += 1
			continue

		var node := _build_node(layer, parent_origin)
		if node == null:
			i += 1
			continue
		parent.add_child(node)

		var clip_layers: Array = []
		var j := i + 1
		while j < ordered_layers.size():
			var clip_layer = ordered_layers[j]
			if clip_layer == null or not clip_layer.is_clipping_mask:
				break
			clip_layers.append(clip_layer)
			j += 1

		if not clip_layers.is_empty():
			_enable_child_clipping(node)
			var base_origin := Vector2(float(layer.left), float(layer.top))
			for clip_layer in clip_layers:
				var clip_node := _build_node(clip_layer, base_origin)
				if clip_node:
					node.add_child(clip_node)

		i = j


func _enable_child_clipping(node: Node) -> void:
	if node is CanvasItem:
		node.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	if node is Control and node.size == Vector2.ZERO:
		node.size = _node_fallback_size(node)


func _build_texture_node(layer, parent_origin: Vector2) -> Node:
	var node: Node

	match root_type:
		RootType.CONTROL:
			var tr := TextureRect.new()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP
			node = tr
		RootType.NODE_2D:
			var sp := Sprite2D.new()
			sp.centered = false
			node = sp

	node.name = _sanitize_name(layer.name)
	node.visible = layer.visible
	_apply_position(node, layer, parent_origin)
	_apply_size(node, layer)
	_apply_opacity(node, layer)

	# Embed the layer image as an ImageTexture directly (may be null for failed layers)
	if layer.image != null:
		var tex := ImageTexture.create_from_image(layer.image)
		if node is TextureRect:
			node.texture = tex
		elif node is Sprite2D:
			node.texture = tex

	return node


func _build_label(layer, parent_origin: Vector2) -> Node:
	var td: Dictionary = layer.text_data
	var label := Label.new()
	var text := str(td.get("text", "")).strip_edges()
	label.name = _sanitize_name(text if not text.is_empty() else layer.name)
	label.text = text
	label.visible = layer.visible
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Font size
	var font_size := 16
	if td.has("size") and td["size"] > 0:
		font_size = max(1, int(td["size"]))
	label.add_theme_font_size_override("font_size", font_size)

	# Color
	if td.has("color"):
		var clr: Color = td["color"]
		label.add_theme_color_override("font_color", clr)
	else:
		label.add_theme_color_override("font_color", Color.WHITE)

	_apply_position(label, layer, parent_origin)
	_apply_size(label, layer)
	if label.size.x <= 0.0 or label.size.y <= 0.0:
		label.size = _estimate_label_size(text, font_size)
	label.custom_minimum_size = label.size
	_apply_opacity(label, layer)

	return label


func _build_solid_color(layer, parent_origin: Vector2) -> Node:
	"""Solid color fill layer → ColorRect"""
	var cr := ColorRect.new()
	cr.name = _sanitize_name(layer.name)
	cr.color = layer.solid_color
	cr.visible = layer.visible

	# Size the ColorRect to the layer bounds
	if layer.width() > 0 and layer.height() > 0:
		cr.size = Vector2(float(layer.width()), float(layer.height()))
	else:
		# Full canvas size for full-frame solid color layers
		cr.size = Vector2(float(layer.right), float(layer.bottom))

	_apply_position(cr, layer, parent_origin)
	_apply_opacity(cr, layer)

	return cr


# ══════════════════════════════════════════════════════════════════════
# Position & opacity helpers
# ══════════════════════════════════════════════════════════════════════

func _apply_position(node: Node, layer, parent_origin: Vector2 = Vector2.ZERO) -> void:
	var pos := Vector2(float(layer.left), float(layer.top)) - parent_origin
	if node is Control:
		node.position = pos
	elif node is Node2D:
		node.position = pos


func _apply_size(node: Node, layer) -> void:
	if node is Control and layer.width() > 0 and layer.height() > 0:
		node.size = Vector2(float(layer.width()), float(layer.height()))


func _apply_opacity(node: Node, layer) -> void:
	if node is CanvasItem:
		node.self_modulate.a = layer.opacity


func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)


func _drawing_order(source: Array) -> Array:
	var ordered := source.duplicate()
	ordered.reverse()
	return ordered


func _estimate_label_size(text: String, font_size: int) -> Vector2:
	var lines := text.split("\n")
	var max_chars := 1
	for line in lines:
		max_chars = max(max_chars, line.length())
	var line_count = max(1, lines.size())
	return Vector2(float(max_chars * font_size), float(line_count * font_size * 2))


func _node_fallback_size(node: Node) -> Vector2:
	if node is TextureRect and node.texture != null:
		return Vector2(node.texture.get_width(), node.texture.get_height())
	if node is Label:
		return node.size
	return canvas_size


# ══════════════════════════════════════════════════════════════════════
# Utility
# ══════════════════════════════════════════════════════════════════════

func _sanitize_name(raw: String) -> String:
	var s := raw.replace("/", "_").replace(":", "_").replace('"', "'")
	s = s.replace("\\", "_").replace("*", "_").replace("?", "_")
	s = s.replace("<", "_").replace(">", "_").replace("|", "_")
	s = s.strip_edges()
	return s if not s.is_empty() else "Layer"
