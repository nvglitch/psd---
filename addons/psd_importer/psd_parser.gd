@tool
# psd_parser.gd 鈥?Parse Adobe Photoshop PSD binary format
# V1: 8-bit RGB/RGBA, RLE-compressed layers, groups, text layers
#
# PSD binary layout reference:
#   https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/

class_name PSDParser
extends RefCounted


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Public types
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

class LayerData:
	var name: String = ""
	var left: int = 0
	var top: int = 0
	var right: int = 0
	var bottom: int = 0
	var opacity: float = 1.0        # 0.0 .. 1.0
	var visible: bool = true
	var blend_mode: String = "norm"
	var is_group: bool = false
	var is_group_end: bool = false
	var is_clipping_mask: bool = false
	var is_adjustment: bool = false # true for adjustment layers (curves, levels, etc.)
	var is_solid_color: bool = false # true for SoCo solid color fill layers
	var solid_color: Color = Color.BLACK
	var has_text: bool = false      # true if TySh text engine data was found
	var children: Array = []        # Array[LayerData]
	var image: Image                # RGBA8 image (null for groups / adjustment layers)
	var texture_path: String = ""   # External PNG path written by the importer
	var text_data: Dictionary       # {text: "", font: "", size: float, color: Color}
	var effects: Dictionary = {}    # Photoshop layer styles parsed from lfx2/lrFX
	var mask_info: Dictionary = {}  # debug: layer mask metadata, if present
	var info_keys: Array[String] = []  # debug: additional info keys found

	func width() -> int:  return right - left
	func height() -> int: return bottom - top


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Public API
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

var psd_width: int = 0
var psd_height: int = 0
var layers: Array[LayerData] = []   # top-level (tree) after parse()


func parse(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("[PSDParser] Cannot open: ", path)
		return ERR_FILE_CANT_OPEN

	# PSD files use big-endian (Motorola) byte order
	f.big_endian = true

	var err := _parse_header(f)
	if err != OK:
		return err

	_skip_block(f)   # Color Mode Data
	_skip_block(f)   # Image Resources

	err = _parse_layer_and_mask(f)
	f.close()
	return err


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Header (26 bytes)
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _parse_header(f: FileAccess) -> int:
	if f.get_length() < 26:
		return _fail("File too small")

	var sig := f.get_buffer(4).get_string_from_ascii()
	if sig != "8BPS":
		return _fail("Not a PSD (sig=%s)" % sig)
	if f.get_16() != 1:
		return _fail("Unsupported PSD version")

	f.get_buffer(6)            # reserved
	var ch := f.get_16()       # channel count
	psd_height = f.get_32()
	psd_width  = f.get_32()
	var depth   := f.get_16()
	var mode    := f.get_16()

	print_rich("[PSDParser] %dx%d  ch=%d  depth=%d  mode=%d" % [psd_width, psd_height, ch, depth, mode])

	if depth != 8:
		return _fail("Only 8-bit supported (depth=%d)" % depth)
	if mode != 3:   # RGB
		return _fail("Only RGB mode supported (mode=%d)" % mode)
	return OK


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Layer & Mask Information section
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _parse_layer_and_mask(f: FileAccess) -> int:
	var section_len := _read_u32(f)
	if section_len == 0:
		return OK
	var section_end := f.get_position() + section_len

	var info_len := _read_u32(f)
	if info_len == 0:
		f.seek(section_end)
		return OK

	var layer_count := abs(_s16(f.get_16()))
	if layer_count == 0:
		f.seek(section_end)
		return OK

	print_rich("[PSDParser] %d layer records" % layer_count)

	# 鈹€鈹€ Pass 1: read every layer record's metadata 鈹€鈹€
	var records: Array[Dictionary] = []
	for _i in layer_count:
		var rec := _read_layer_record(f)
		if rec.is_empty():
			break
		records.append(rec)

	# 鈹€鈹€ Pass 2: read channel image data that follows all records 鈹€鈹€
	for rec in records:
		_read_layer_channels(f, rec)

	# 鈹€鈹€ Build tree 鈹€鈹€
	layers = _build_tree(records)

	f.seek(section_end)
	return OK


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Single layer record (metadata only)
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _read_layer_record(f: FileAccess) -> Dictionary:
	var rec := {
		"top": 0, "left": 0, "bottom": 0, "right": 0,
		"opacity": 1.0, "visible": true, "blend_mode": "norm",
		"name": "", "unicode_name": "",
		"is_group": false, "is_group_end": false,
		"is_clipping_mask": false,
		"channel_ids": [],
		"text_data": {},
		"effects": {},
		"mask_info": {},
	}

	rec["top"]    = _s32(f.get_32())
	rec["left"]   = _s32(f.get_32())
	rec["bottom"] = _s32(f.get_32())
	rec["right"]  = _s32(f.get_32())

	var ch_count := f.get_16()
	var channels: Array[Dictionary] = []
	for _c in ch_count:
		var ci := {"id": int(_s16(f.get_16())), "data_len": _read_u32(f)}
		channels.append(ci)
		rec["channel_ids"].append(ci["id"])
	rec["_channels"] = channels   # temp, used in pass 2

	# Blend mode
	var sig := f.get_buffer(4).get_string_from_ascii()
	if sig != "8BIM":
		return {}
	rec["blend_mode"] = f.get_buffer(4).get_string_from_ascii()

	rec["opacity"]  = f.get_8() / 255.0
	var clipping    := f.get_8()
	rec["is_clipping_mask"] = clipping != 0
	var flags       := f.get_8()
	rec["visible"]  = (flags & 0x02) == 0   # bit 1 clear 鈫?visible
	f.get_8()  # filler

	# 鈹€鈹€ Extra data 鈹€鈹€
	var extra_len := _read_u32(f)
	var extra_end := f.get_position() + extra_len

	# Layer mask data
	var mask_len := _read_u32(f)
	rec["mask_info"] = _read_layer_mask_info(f, mask_len)

	# Blending ranges
	var br_len := _read_u32(f)
	f.seek(f.get_position() + br_len)

	# Layer name (Pascal, padded to 4)
	var name_len := f.get_8()
	if name_len > 0:
		rec["name"] = f.get_buffer(name_len).get_string_from_ascii()
	var pad := (4 - ((1 + name_len) % 4)) % 4
	f.seek(f.get_position() + pad)

	# 鈹€鈹€ Additional info blocks 鈹€鈹€
	var info_keys: Array[String] = []
	while f.get_position() + 8 <= extra_end:
		var tag := f.get_buffer(4).get_string_from_ascii()
		if tag != "8BIM" and tag != "8B64":
			break
		var key := f.get_buffer(4).get_string_from_ascii()
		var dlen := _read_u32(f)
		var dstart := f.get_position()

		info_keys.append(key)

		match key:
			"luni":
				rec["unicode_name"] = _read_unicode(f)
			"TySh":
				rec["text_data"] = _read_tysh(f)
				_scan_text_block_for_style(f, dstart, dlen, rec["text_data"])
			"tySh":
				rec["text_data"] = _read_tysh(f)
				_scan_text_block_for_style(f, dstart, dlen, rec["text_data"])
			"lsct":
				var st := f.get_32()
				if st == 1 or st == 2:
					rec["is_group"] = true
					print_rich("[color=dim_gray][PSDParser][/color]   lsct: group OPEN (type=%d) \"%s\"" % [st, rec.get("name", "?")])
				elif st == 3:
					rec["is_group_end"] = true
					print_rich("[color=dim_gray][PSDParser][/color]   lsct: group CLOSE \"%s\"" % rec.get("name", "?"))
				else:
					print_rich("[color=dim_gray][PSDParser][/color]   lsct: section_type=%d (normal layer)" % st)
			"SoCo":
				# Solid Color fill layer 鈥?store the color descriptor
				rec["solid_color"] = _read_descriptor(f)
				rec["is_solid_color"] = true
			"lfx2", "lrFX":
				var parsed_effects := _parse_layer_effects(f.get_buffer(dlen))
				if not parsed_effects.is_empty():
					rec["effects"] = parsed_effects

		f.seek(dstart + dlen)
		if dlen % 2 != 0:
			f.get_8()  # alignment pad

	rec["info_keys"] = info_keys
	f.seek(extra_end)
	return rec


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Channel image data (pass 2)
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _read_layer_channels(f: FileAccess, rec: Dictionary) -> void:
	var w: int = int(rec["right"]) - int(rec["left"])
	var h: int = int(rec["bottom"]) - int(rec["top"])
	var ch_infos: Array = rec["_channels"]
	var layer_name: String = rec.get("name", "?")

	# 鈹€鈹€ Debug: log channel info BEFORE reading 鈹€鈹€
	var ch_debug := "  ch=%d" % ch_infos.size()
	for ci in ch_infos:
		ch_debug += " [id=%d len=%d]" % [ci["id"], ci["data_len"]]
	print_rich("[color=dim_gray][PSDParser][/color] \"%s\" %dx%d%s" % [layer_name, w, h, ch_debug])

	# Zero-size layers (adjustment layers) 鈥?MUST consume channel data to keep
	# file position aligned for subsequent layers.
	if w <= 0 or h <= 0:
		for ci in ch_infos:
			var data_len: int = ci["data_len"]
			if data_len >= 2:
				f.seek(f.get_position() + data_len)
			else:
				# Fallback: read compression type to determine skip
				var comp: int = f.get_16()
				print_rich("[color=dim_gray][PSDParser][/color]   zero-size skip: comp=%d" % comp)
				if comp == 1 and h > 0:
					f.seek(f.get_position() + h * 2)
		rec["image"] = null
		rec.erase("_channels")
		return

	# Skip solid color layers 鈥?they have SoCo data, no real pixel data
	if rec.get("is_solid_color", false):
		print_rich("[color=dim_gray][PSDParser][/color]   SoCo layer 鈥?skipping channel data")
		for ci in ch_infos:
			var data_len: int = ci["data_len"]
			if data_len >= 2:
				f.seek(f.get_position() + data_len)
			else:
				f.seek(f.get_position() + 2)
		rec["image"] = null
		rec.erase("_channels")
		return

	# Normal layers: build a dict channel_id 鈫?decompressed PackedByteArray
	var ch_pixels: Dictionary = {}

	for ci in ch_infos:
		var channel_start := f.get_position()
		var channel_end: int = channel_start + int(ci["data_len"])
		var comp: int = f.get_16()
		var raw: PackedByteArray

		# Debug: log compression + first row_len for RLE
		var debug_extra := ""

		if comp == 0:   # Raw
			raw = f.get_buffer(min(w * h, max(0, channel_end - f.get_position())))
			if raw.size() < w * h:
				raw.resize(w * h)
			debug_extra = "raw %dB" % (w * h)
		elif comp == 1: # RLE (PackBits)
			var row_lens: Array[int] = []
			for _r in h:
				if f.get_position() + 2 <= channel_end:
					row_lens.append(f.get_16())
				else:
					row_lens.append(0)
			if row_lens.size() > 0:
				debug_extra = "RLE row0_len=%d" % row_lens[0]
			raw = _decompress_rle(f, row_lens, w, channel_end)
		else:
			printerr("[PSDParser] Unsupported comp=%d for \"%s\" ch_id=%d data_len=%d; skipping channel" % [comp, layer_name, ci["id"], ci["data_len"]])
			raw = _make_solid(w, h, 0 if int(ci["id"]) == -1 else 255)

		f.seek(channel_end)

		print_rich("[color=dim_gray][PSDParser][/color]   ch_id=%d comp=%d %s" % [ci["id"], comp, debug_extra])
		ch_pixels[ci["id"]] = raw

	# Composite into RGBA8 Image.
	# PSD layer channel IDs are 0=R, 1=G, 2=B, -1=transparency.
	var r_chan := ch_pixels.get(0, _make_solid(w, h, 255))
	var g_chan := ch_pixels.get(1, _make_solid(w, h, 255))
	var b_chan := ch_pixels.get(2, _make_solid(w, h, 255))
	var a_chan := ch_pixels.get(-1, _make_solid(w, h, 255))

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var idx: int = y * w + x
			var r: int = r_chan[idx] if idx < r_chan.size() else 255
			var g: int = g_chan[idx] if idx < g_chan.size() else 255
			var b: int = b_chan[idx] if idx < b_chan.size() else 255
			var a: int = a_chan[idx] if idx < a_chan.size() else 255
			img.set_pixel(x, y, Color(r / 255.0, g / 255.0, b / 255.0, a / 255.0))

	rec["image"] = img
	rec.erase("_channels")  # clean up temp


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# RLE (PackBits) decompression
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _decompress_rle(f: FileAccess, row_lens: Array[int], row_width: int, channel_end: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(row_width * row_lens.size())

	for row in row_lens.size():
		var comp_len: int = min(row_lens[row], max(0, channel_end - f.get_position()))
		var out_offset: int = row * row_width
		var in_bytes := f.get_buffer(comp_len)
		var i := 0

		while i < in_bytes.size() and out_offset < out.size():
			var n: int = int(in_bytes[i])
			i += 1
			if n >= 128:            # run: repeat next byte (257-n) times
				var count: int = 257 - n
				if i >= in_bytes.size():
					break
				var val: int = in_bytes[i]
				i += 1
				for _c in count:
					if out_offset >= out.size():
						break
					out[out_offset] = val
					out_offset += 1
			elif n >= 0:            # literal: copy (n+1) bytes
				var count: int = n + 1
				for _c in count:
					if i >= in_bytes.size() or out_offset >= out.size():
						break
					out[out_offset] = in_bytes[i]
					out_offset += 1
					i += 1
			# n == 128 is no-op

	return out


func _parse_layer_effects(bytes: PackedByteArray) -> Dictionary:
	var out := {}

	var color_overlay := _parse_color_style(bytes, ["SoFi", "solidFillMulti"])
	if not color_overlay.is_empty():
		out["color_overlay"] = color_overlay

	var stroke := _parse_color_style(bytes, ["FrFX", "frameFXMulti"])
	if not stroke.is_empty():
		stroke["size"] = _read_unit_float_in_style(bytes, stroke["_start"], stroke["_end"], ["Sz  UntF", "sizeUntF"])
		stroke.erase("_start")
		stroke.erase("_end")
		out["stroke"] = stroke

	var outer_glow := _parse_color_style(bytes, ["OrGl", "outerGlowMulti"])
	if not outer_glow.is_empty():
		outer_glow["size"] = _read_unit_float_in_style(bytes, outer_glow["_start"], outer_glow["_end"], ["blurUntF", "CkmtUntF", "Sz  UntF"])
		outer_glow.erase("_start")
		outer_glow.erase("_end")
		out["outer_glow"] = outer_glow

	var drop_shadow := _parse_color_style(bytes, ["DrSh", "dropShadowMulti"])
	if not drop_shadow.is_empty():
		drop_shadow["size"] = _read_unit_float_in_style(bytes, drop_shadow["_start"], drop_shadow["_end"], ["blurUntF", "CkmtUntF", "Sz  UntF"])
		drop_shadow["distance"] = _read_unit_float_in_style(bytes, drop_shadow["_start"], drop_shadow["_end"], ["DstnUntF", "laglUntF"])
		drop_shadow["angle"] = _read_unit_float_in_style(bytes, drop_shadow["_start"], drop_shadow["_end"], ["laglUntF", "AnglUntF"])
		drop_shadow.erase("_start")
		drop_shadow.erase("_end")
		out["drop_shadow"] = drop_shadow

	for key in out.keys():
		if out[key] is Dictionary:
			out[key].erase("_start")
			out[key].erase("_end")
	return out


func _parse_color_style(bytes: PackedByteArray, markers: Array[String]) -> Dictionary:
	var start := _find_first_marker_bytes(bytes, markers, 0)
	if start < 0:
		return {}

	var end := _find_next_effect_section_bytes(bytes, start + 4)
	if end <= start:
		end = bytes.size()

	if _find_bytes(bytes, "enabbool".to_ascii_buffer(), start, end) >= 0 and not _read_bool_after_marker(bytes, start, end, "enabbool"):
		return {}

	var color := _read_color_in_style(bytes, start, end)
	if color.a <= 0.0:
		return {}

	var opacity := _read_unit_float_in_style(bytes, start, end, ["OpctUntF"])
	if opacity <= 0.0:
		opacity = 100.0

	return {
		"color": color,
		"opacity": clamp(opacity / 100.0, 0.0, 1.0),
		"_start": start,
		"_end": end,
	}


func _find_first_marker_bytes(bytes: PackedByteArray, markers: Array[String], from: int) -> int:
	var best := -1
	for marker in markers:
		var pos := _find_bytes(bytes, marker.to_ascii_buffer(), from, bytes.size())
		if pos >= 0 and (best < 0 or pos < best):
			best = pos
	return best


func _read_color_in_style(bytes: PackedByteArray, start: int, end: int) -> Color:
	var rd_pos := _find_bytes(bytes, "Rd  doub".to_ascii_buffer(), start, end)
	var grn_pos := _find_bytes(bytes, "Grn doub".to_ascii_buffer(), start, end)
	var bl_pos := _find_bytes(bytes, "Bl  doub".to_ascii_buffer(), start, end)
	if rd_pos < 0 or grn_pos < 0 or bl_pos < 0:
		return Color(0, 0, 0, 0)
	if rd_pos >= end or grn_pos >= end or bl_pos >= end:
		return Color(0, 0, 0, 0)

	var r := _read_be_double_at(bytes, rd_pos + 8) / 255.0
	var g := _read_be_double_at(bytes, grn_pos + 8) / 255.0
	var b := _read_be_double_at(bytes, bl_pos + 8) / 255.0
	return Color(clamp(r, 0.0, 1.0), clamp(g, 0.0, 1.0), clamp(b, 0.0, 1.0), 1.0)


func _read_unit_float_in_style(bytes: PackedByteArray, start: int, end: int, markers: Array[String]) -> float:
	for marker in markers:
		var pos := _find_bytes(bytes, marker.to_ascii_buffer(), start, end)
		if pos >= 0 and pos + 20 <= end:
			return _read_be_double_at(bytes, pos + 12)
	return 0.0


func _find_next_effect_marker(text: String, from: int) -> int:
	var markers := ["dropShadowMulti", "innerShadowMulti", "outerGlowMulti", "innerGlowMulti", "bevelEmbossMulti", "solidFillMulti", "gradientFillMulti", "patternFillMulti", "FrFX", "IrSh", "OrGl", "IrGl", "ebbl", "SoFi", "GrFl", "patternFill"]
	var best := -1
	for marker in markers:
		var pos := text.find(marker, from)
		if pos >= 0 and (best < 0 or pos < best):
			best = pos
	return best


func _find_next_effect_section_bytes(bytes: PackedByteArray, from: int) -> int:
	var markers := ["dropShadowMulti", "innerShadowMulti", "outerGlowMulti", "innerGlowMulti", "bevelEmbossMulti", "solidFillMulti", "gradientFillMulti", "patternFillMulti", "frameFXMulti"]
	var best := -1
	for marker in markers:
		var pos := _find_bytes(bytes, marker.to_ascii_buffer(), from, bytes.size())
		if pos >= 0 and (best < 0 or pos < best):
			best = pos
	return best


func _read_bool_after_marker(bytes: PackedByteArray, start: int, end: int, marker: String) -> bool:
	var pos := _find_bytes(bytes, marker.to_ascii_buffer(), start, end)
	if pos < 0 or pos + marker.length() >= end:
		return true
	return bytes[pos + marker.length()] != 0


func _find_bytes(bytes: PackedByteArray, needle: PackedByteArray, start: int, end: int) -> int:
	if needle.is_empty():
		return -1
	var max_start: int = min(end, bytes.size()) - needle.size()
	var i: int = max(0, start)
	while i <= max_start:
		var matched := true
		for j in needle.size():
			if bytes[i + j] != needle[j]:
				matched = false
				break
		if matched:
			return i
		i += 1
	return -1


func _read_be_double_at(bytes: PackedByteArray, pos: int) -> float:
	if pos < 0 or pos + 8 > bytes.size():
		return 0.0
	var scratch := PackedByteArray()
	scratch.resize(8)
	for i in 8:
		scratch[i] = bytes[pos + i]
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.data_array = scratch
	return stream.get_double()


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# TySh (text engine data) parser
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Strategy:
#   1. Try full descriptor parsing to extract text/size/color/font
#   2. If descriptor parsing fails to find "Txt ", scan raw bytes for the
#      "Txt " + "TEXT" pattern as a fallback.

func _read_tysh(f: FileAccess) -> Dictionary:
	var out := {
		"text": "",
		"font": "",
		"size": 16.0,
		"color": Color(1, 1, 1, 1),
		"transform": [],
		"transform_scale": Vector2.ONE,
	}

	var ver: int = f.get_16()
	if ver != 1:
		return out

	# Transform matrix: xx, xy, yx, yy, tx, ty.
	var transform: Array[float] = []
	for _i in 6:
		transform.append(f.get_double())
	out["transform"] = transform
	out["transform_scale"] = Vector2(
		sqrt(transform[0] * transform[0] + transform[2] * transform[2]),
		sqrt(transform[1] * transform[1] + transform[3] * transform[3])
	)

	var _text_ver: int = f.get_16()
	var _desc_ver: int = f.get_32()

	# Try descriptor parsing
	var desc := _read_descriptor(f)
	if not desc.is_empty():
		_extract_text_data(desc, out)
	_apply_text_transform_scale(out)

	return out


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Photoshop Descriptor parser
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Handles all known Photoshop OSTypes so descriptor parsing never breaks
# mid-stream. Unknown types print a warning but don't stop parsing 鈥?# the caller is responsible for seeking to block end.

func _read_descriptor(f: FileAccess) -> Dictionary:
	"""Read a Photoshop OSType descriptor, return {key: value, ...} dict."""

	# Name: Unicode string (4-byte length in chars + UTF-16BE)
	var name := _read_unicode_string_padded(f)

	# Class ID: 4-byte length + ASCII string (or 4 zero bytes = "null")
	var class_id := _read_id_string(f)

	# Item count
	var item_count: int = f.get_32()

	if item_count < 0 or item_count > 10000:
		print_rich("[color=yellow][PSDParser][/color] Descriptor item_count=%d 鈥?aborting" % item_count)
		return {}

	var result := {}

	for _item in item_count:
		var key := _read_id_string(f)
		var ostype := _read_ostype(f)

		match ostype:
			"TEXT":
				result[key] = _read_unicode_string_padded(f)
			"doub":
				result[key] = f.get_double()
			"long", "indx", "Idnt", "Cmpt":
				result[key] = f.get_32()
			"bool":
				result[key] = f.get_8() != 0
			"UntF":
				var unit := _read_ostype(f)
				var val: float = f.get_double()
				result[key] = [unit, val]
			"enum":
				var type_id := _read_id_string(f)
				var enum_val := _read_id_string(f)
				result[key] = enum_val
			"type":
				result[key] = _read_id_string(f)
			"GlbC":
				result[key] = _read_id_string(f)  # class name
			"rele":
				# Reference list: 4-byte count + references
				var rcount: int = f.get_32()
				for _ri in rcount:
					# Each reference: 4-byte OSType + variable data 鈥?just read and discard
					var rtype := _read_ostype(f)
					match rtype:
						"prop":
							_read_id_string(f)  # name
							_read_id_string(f)  # class
							_read_id_string(f)  # key
						"Clss":
							_read_id_string(f)  # name
							_read_id_string(f)  # class
						"Enmr":
							_read_id_string(f)  # name
							_read_id_string(f)  # class
							_read_id_string(f)  # enum
						"rele":
							_read_id_string(f)  # name
							_read_id_string(f)  # class
							f.get_32()               # offset
						"Idnt":
							f.get_32()               # identifier
						"indx":
							f.get_32()               # index
						"name":
							_read_unicode_string_padded(f)  # name
						_:
							# Unknown reference type, skip 4 bytes
							f.get_32()
				result[key] = "<rele:%d>" % rcount
			"Objc", "GlbO":
				result[key] = _read_descriptor(f)
			"tdta":
				var dlen: int = f.get_32()
				result[key] = _bytes_to_text(f.get_buffer(dlen))
			"alis":
				var alen: int = f.get_32()
				f.seek(f.get_position() + alen)
				result[key] = "<alias>"
			"ObAr":
				# Object array: count + class_id + items (each is a full descriptor)
				var acount: int = f.get_32()
				var aclass := _read_id_string(f)
				for _ai in acount:
					_read_descriptor(f)  # read and discard each item
				result[key] = "<array:%d>" % acount
			"UnFl":
				# Unit float list: count + (unit + double)*
				var ucount: int = f.get_32()
				for _ui in ucount:
					_read_ostype(f)  # unit
					f.get_double()            # value
				result[key] = "<unit_float_list:%d>" % ucount
			"VlLs":
				# Value list: count + items (type + value)
				var vcount: int = f.get_32()
				for _vi in vcount:
					var vtype := _read_ostype(f)
					_skip_descriptor_value(f, vtype)
				result[key] = "<value_list:%d>" % vcount
			"name":
				result[key] = _read_unicode_string_padded(f)
			"Clss":
				var cname := _read_id_string(f)
				var cid := _read_id_string(f)
				result[key] = "%s:%s" % [cname, cid]
			_:
				# Unknown type 鈥?try to skip it by guessing it's 4 bytes
				# (common for simple integer types we might have missed)
				print_rich("[color=dim_gray][PSDParser][/color]   descriptor: unknown OSType '%s' for key '%s' 鈥?guessing 4-byte skip" % [ostype, key])
				f.get_32()
				result[key] = "<unknown:%s>" % ostype
				# NOTE: don't break 鈥?caller fixes position via seek

	return result


func _skip_descriptor_value(f: FileAccess, ostype: String) -> void:
	"""Skip a single descriptor value of given type without storing it."""
	match ostype:
		"TEXT":
			_read_unicode_string_padded(f)
		"doub":
			f.get_double()
		"long", "indx", "Idnt", "Cmpt":
			f.get_32()
		"bool":
			f.get_8()
		"UntF":
			_read_ostype(f)
			f.get_double()
		"enum":
			_read_id_string(f)
			_read_id_string(f)
		"type":
			_read_id_string(f)
		"GlbC":
			_read_id_string(f)
		"Objc", "GlbO":
			_read_descriptor(f)
		"tdta":
			var dlen: int = f.get_32()
			f.seek(f.get_position() + dlen)
		"alis":
			var alen: int = f.get_32()
			f.seek(f.get_position() + alen)
		"ObAr":
			var acount: int = f.get_32()
			_read_id_string(f)  # class
			for _ai in acount:
				_read_descriptor(f)
		"UnFl":
			var ucount: int = f.get_32()
			for _ui in ucount:
				_read_ostype(f)
				f.get_double()
		"VlLs":
			var vcount: int = f.get_32()
			for _vi in vcount:
				var vt := _read_ostype(f)
				_skip_descriptor_value(f, vt)
		_:
			f.get_32()  # guess 4 bytes


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Descriptor helpers
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _read_unicode_string_padded(f: FileAccess) -> String:
	"""Read a Unicode string: 4-byte char count, then UTF-16BE chars.
	Length is in characters, not bytes. No padding needed after."""
	var char_count: int = f.get_32()
	if char_count <= 0 or char_count > 10000:
		return ""
	var s := ""
	for _i in char_count:
		var c: int = f.get_16()
		if c != 0:
			s += char(c)
	return s


func _read_fourbyte_string(f: FileAccess) -> String:
	"""Read a 4-byte length-prefixed ASCII string. If length=0 (4 zero bytes), return ''."""
	var length: int = f.get_32()
	if length <= 0 or length > 256:
		return ""
	return f.get_buffer(length).get_string_from_ascii()


func _read_id_string(f: FileAccess) -> String:
	"""Read a Photoshop descriptor ID string. A zero length means the next 4 bytes are the ID."""
	var length: int = f.get_32()
	if length == 0:
		return _read_ostype(f)
	if length < 0 or length > 4096:
		return ""
	return f.get_buffer(length).get_string_from_ascii()


func _read_ostype(f: FileAccess) -> String:
	return f.get_buffer(4).get_string_from_ascii()


func _extract_text_data(desc: Dictionary, out: Dictionary) -> void:
	if desc.has("Txt "):
		out["text"] = str(desc["Txt "]).replace("\r", "\n")

	var style = _find_first_key(desc, ["TxtS", "EngineData"])
	if style is Dictionary:
		_extract_text_style(style, out)
	elif style is String:
		_extract_engine_data_style(style, out)

	var nested_text = _find_first_key(desc, ["Txt "])
	if out.get("text", "").is_empty() and nested_text != null:
		out["text"] = str(nested_text).replace("\r", "\n")


func _extract_text_style(style: Dictionary, out: Dictionary) -> void:
	var size_val = _find_first_key(style, ["Sz  ", "FontSize"])
	if size_val is Array and size_val.size() >= 2:
		out["size"] = float(size_val[1])
		out["raw_size"] = out["size"]
	elif size_val is float or size_val is int:
		out["size"] = float(size_val)
		out["raw_size"] = out["size"]

	var font_val = _find_first_key(style, ["Font", "FntN", "Name"])
	if font_val != null:
		out["font"] = str(font_val)

	var color_val = _find_first_key(style, ["Clr ", "FillColor"])
	if color_val is Dictionary:
		var r: float = float(color_val.get("Rd__", color_val.get("Rd  ", 255.0)))
		var g: float = float(color_val.get("Grn ", 255.0))
		var b: float = float(color_val.get("Bl__", color_val.get("Bl  ", 255.0)))
		out["color"] = Color(r / 255.0, g / 255.0, b / 255.0, 1.0)


func _extract_engine_data_style(engine_data: String, out: Dictionary) -> void:
	var font_size := _extract_number_after(engine_data, "/FontSize")
	if font_size > 0.0:
		out["size"] = font_size
		out["raw_size"] = font_size

	var fill_pos := engine_data.find("/FillColor")
	if fill_pos >= 0:
		var open_pos := engine_data.find("[", fill_pos)
		var close_pos := engine_data.find("]", open_pos)
		if open_pos >= 0 and close_pos > open_pos:
			var parts := engine_data.substr(open_pos + 1, close_pos - open_pos - 1).split(" ", false)
			var offset := 1 if parts.size() >= 4 else 0
			if parts.size() >= offset + 3:
				var r := clamp(float(parts[offset]), 0.0, 1.0)
				var g := clamp(float(parts[offset + 1]), 0.0, 1.0)
				var b := clamp(float(parts[offset + 2]), 0.0, 1.0)
				out["color"] = Color(r, g, b, 1.0)


func _apply_text_transform_scale(out: Dictionary) -> void:
	if not out.has("size") or not out.has("transform_scale"):
		return
	var scale: Vector2 = out["transform_scale"]
	var sy := abs(scale.y)
	if sy <= 0.0 or is_equal_approx(sy, 1.0):
		return
	var base_size := float(out.get("raw_size", out["size"]))
	out["raw_size"] = base_size
	out["size"] = base_size * sy


func _extract_number_after(text: String, marker: String) -> float:
	var pos := text.find(marker)
	if pos < 0:
		return -1.0
	pos += marker.length()
	while pos < text.length() and text[pos] <= " ":
		pos += 1

	var start := pos
	while pos < text.length():
		var ch := text[pos]
		if not ((ch >= "0" and ch <= "9") or ch == "." or ch == "-" or ch == "+"):
			break
		pos += 1

	if pos <= start:
		return -1.0
	return float(text.substr(start, pos - start))


func _bytes_to_text(bytes: PackedByteArray) -> String:
	var text := bytes.get_string_from_ascii()
	if text.find("/FontSize") >= 0 or text.find("/EngineData") >= 0:
		return text
	return bytes.get_string_from_utf8()


func _scan_text_block_for_style(f: FileAccess, start: int, length: int, out: Dictionary) -> void:
	var old_pos := f.get_position()
	f.seek(start)
	var raw := f.get_buffer(length)
	f.seek(old_pos)

	var text := _bytes_to_search_text(raw)
	_extract_engine_data_style(text, out)
	_apply_text_transform_scale(out)


func _read_layer_mask_info(f: FileAccess, mask_len: int) -> Dictionary:
	var info := {
		"length": mask_len,
	}
	var start := f.get_position()
	var end := start + mask_len
	if mask_len <= 0:
		return info
	if mask_len < 20:
		f.seek(end)
		return info

	var top := _s32(f.get_32())
	var left := _s32(f.get_32())
	var bottom := _s32(f.get_32())
	var right := _s32(f.get_32())
	info["top"] = top
	info["left"] = left
	info["bottom"] = bottom
	info["right"] = right
	info["width"] = right - left
	info["height"] = bottom - top
	info["default_color"] = f.get_8()
	var flags := f.get_8()
	info["flags"] = flags
	info["position_relative"] = (flags & 0x01) != 0
	info["disabled"] = (flags & 0x02) != 0
	info["invert_on_blend"] = (flags & 0x04) != 0

	f.seek(end)
	return info


func _bytes_to_search_text(bytes: PackedByteArray) -> String:
	var ascii := ""
	var utf16be := ""
	var utf16le := ""

	for b in bytes:
		if b >= 32 and b <= 126:
			ascii += char(b)
		else:
			ascii += " "

	for i in range(0, bytes.size() - 1, 2):
		var be := int(bytes[i]) << 8 | int(bytes[i + 1])
		var le := int(bytes[i + 1]) << 8 | int(bytes[i])
		utf16be += char(be) if be >= 32 and be <= 126 else " "
		utf16le += char(le) if le >= 32 and le <= 126 else " "

	return ascii + "\n" + utf16be + "\n" + utf16le


func _find_first_key(value, keys: Array) -> Variant:
	if value is Dictionary:
		for key in keys:
			if value.has(key):
				return value[key]
		for child in value.values():
			var found = _find_first_key(child, keys)
			if found != null:
				return found
	elif value is Array:
		for child in value:
			var found = _find_first_key(child, keys)
			if found != null:
				return found
	return null


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Tree building from flat record list (using group markers)
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _build_tree(records: Array[Dictionary]) -> Array[LayerData]:
	var containers: Array = [[]]

	for i in range(records.size() - 1, -1, -1):
		var rec := records[i]
		var ld := _rec_to_layerdata(rec)

		if ld.is_group_end:
			containers.append([])
			continue

		if ld.is_group:
			if containers.size() > 1:
				ld.children = containers.pop_back()
			_fit_group_bounds_to_children(ld)
			print_rich("[color=dim_gray][PSDParser][/color] tree: group \"%s\" (%d children)" % [ld.name, ld.children.size()])

		containers.back().append(ld)

	while containers.size() > 1:
		var unclosed: Array = containers.pop_back()
		for ld in unclosed:
			containers.back().append(ld)

	var roots: Array[LayerData] = []
	for ld in containers[0]:
		roots.append(ld)

	print_rich("[PSDParser] Tree: %d root nodes" % roots.size())
	for root_ld in roots:
		_print_tree(root_ld, "  ")

	return roots


func _fit_group_bounds_to_children(group: LayerData) -> void:
	if group.children.is_empty():
		return

	var left := 2147483647
	var top := 2147483647
	var right := -2147483648
	var bottom := -2147483648
	for child in group.children:
		if child.width() <= 0 and child.height() <= 0 and not child.is_group:
			continue
		left = min(left, child.left)
		top = min(top, child.top)
		right = max(right, child.right)
		bottom = max(bottom, child.bottom)

	if left <= right and top <= bottom:
		group.left = left
		group.top = top
		group.right = right
		group.bottom = bottom


func _print_tree(ld: LayerData, indent: String) -> void:
	var kind := "bitmap"
	if ld.is_group:
		kind = "group"
	elif ld.is_solid_color:
		kind = "solid_color"
	elif ld.has_text:
		kind = "text"
	elif ld.is_adjustment:
		kind = "adjustment"
	var img_info := ""
	if ld.image != null:
		img_info = " %dx%d" % [ld.image.get_width(), ld.image.get_height()]
	elif ld.is_group:
		img_info = " (%d children)" % ld.children.size()
	else:
		img_info = " (no image)"
	var key_info := ""
	if not ld.info_keys.is_empty():
		key_info = "  keys=" + str(ld.info_keys)
	print_rich("[PSDParser] %s[%s] \"%s\"%s%s" % [indent, kind, ld.name, img_info, key_info])
	for child in ld.children:
		_print_tree(child, indent + "  ")


func _rec_to_layerdata(rec: Dictionary) -> LayerData:
	var ld := LayerData.new()

	# Name: prefer Unicode (luni), fallback to Pascal string
	var uname: String = rec.get("unicode_name", "")
	if not uname.is_empty():
		ld.name = uname
	else:
		ld.name = rec.get("name", "Layer")

	ld.left       = rec.get("left", 0)
	ld.top        = rec.get("top", 0)
	ld.right      = rec.get("right", 0)
	ld.bottom     = rec.get("bottom", 0)
	ld.opacity    = rec.get("opacity", 1.0)
	ld.visible    = rec.get("visible", true)
	ld.blend_mode = rec.get("blend_mode", "norm")
	ld.is_group   = rec.get("is_group", false)
	ld.is_group_end = rec.get("is_group_end", false)
	ld.is_clipping_mask = rec.get("is_clipping_mask", false)
	ld.image      = rec.get("image", null)
	ld.text_data  = rec.get("text_data", {})
	ld.effects    = rec.get("effects", {})
	ld.mask_info  = rec.get("mask_info", {})
	ld.info_keys  = rec.get("info_keys", [])

	# Solid color fill
	ld.is_solid_color = rec.get("is_solid_color", false)
	if ld.is_solid_color:
		var sc: Dictionary = rec.get("solid_color", {})
		# SoCo descriptor has Clr_ key which is a color object with Rd__/Grn /Bl__
		if sc.has("Clr "):
			var clr = sc["Clr "]
			if clr is Dictionary:
				var r: float = float(clr.get("Rd__", 0.0))
				var g: float = float(clr.get("Grn ", 0.0))
				var b: float = float(clr.get("Bl__", 0.0))
				ld.solid_color = Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
				ld.text_data["color"] = ld.solid_color

	# Detect text layers (TySh data present)
	ld.has_text = not ld.text_data.is_empty() and not ld.text_data.get("text", "").is_empty()

	# Classification: text/solid-color layers are NOT adjustment layers
	# even if they have zero pixel area in PSD
	if ld.is_group or ld.is_group_end or ld.has_text or ld.is_solid_color:
		ld.is_adjustment = false
	elif ld.width() <= 0 or ld.height() <= 0:
		ld.is_adjustment = true

	return ld


# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲
# Utilities
# 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲

func _skip_block(f: FileAccess) -> void:
	var n := _read_u32(f)
	f.seek(f.get_position() + n)

func _read_u32(f: FileAccess) -> int:
	return f.get_32()

func _s16(v: int) -> int:
	"""Convert unsigned 16-bit to signed."""
	return v - 65536 if v > 32767 else v

func _s32(v: int) -> int:
	"""Convert unsigned 32-bit to signed."""
	return v - 4294967296 if v > 2147483647 else v

func _read_unicode(f: FileAccess) -> String:
	"""Read a luni-style Unicode string: 4-byte char count, UTF-16BE."""
	var n: int = f.get_32()
	if n <= 0 or n > 10000:
		return ""
	var s := ""
	for _i in n:
		var c: int = f.get_16()
		if c != 0:
			s += char(c)
	return s

func _make_solid(w: int, h: int, val: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(w * h)
	a.fill(val)
	return a

func _fail(msg: String) -> int:
	printerr("[PSDParser] ", msg)
	return ERR_FILE_CORRUPT
