class_name NodeFace
extends RefCounted
## Puts a node's glyph on the middle of its circle by what is inked, not by the line it sits in.
##
## A Button centres the text's line box, and a symbol glyph rarely sits in its font's line box the
## way a letter does: a fallback font's ascent and descent are its own, so the swords sat 2 px high
## and the star 4 px low in a circle that was centred. Which way it errs depends on the glyph and on
## the font the platform falls back to, so no table of nudges could hold. This measures instead: the
## glyph is drawn once in a probe button of the same size and font, the ink's box is read back, and
## the difference from the centre is written into the button's content margins, which the Button
## centres its text inside. The answer is cached per glyph, font and size, so a game pays for each
## look once. A control only draws a frame after it is made, so a glyph not yet measured is centred
## two frames after it is first painted, and every one waiting on it is moved together.
##
## Does nothing in a headless run, which draws nothing to read.

const PROBE_PAD := 24  # transparent room around the probe button, in case a glyph overhangs its line

static var _shifts: Dictionary = {}  # key -> Vector2, once measured
static var _waiting: Dictionary = {}  # key -> the buttons waiting on a measurement


## Re-centres the glyph `btn` wears, in every state's stylebox. Call after the styleboxes and the
## font size are set. A button with no glyph, or a stylebox that is not a flat one, is left alone.
static func centre(btn: Button) -> void:
	var key := _key(btn)
	if key == "":
		return
	if _shifts.has(key):
		_apply(btn, _shifts[key])
		return
	if _waiting.has(key):
		_waiting[key].append(btn)
		return
	_waiting[key] = [btn]
	_measure(key, btn.get_theme_font("font"), btn.text, btn.get_theme_font_size("font_size"), btn.size)


static func _key(btn: Button) -> String:
	if btn.text == "" or btn.size.x <= 0.0:
		return ""
	var font: Font = btn.get_theme_font("font")
	return "%s|%d|%d|%d" % [btn.text, btn.get_theme_font_size("font_size"), int(btn.size.x), font.get_rid().get_id() if font else 0]


static func _apply(btn: Button, shift: Vector2) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := btn.get_theme_stylebox(state) as StyleBoxFlat
		if style == null:
			continue
		# The Button centres its text between the margins, so a margin on one side moves the text by
		# half of it away from that side. They start at nothing, not at the ring's width: a glyph taller
		# than the room inside the ring is no longer centred at all, only pinned to the top.
		style.content_margin_left = maxf(2.0 * shift.x, 0.0)
		style.content_margin_right = maxf(-2.0 * shift.x, 0.0)
		style.content_margin_top = maxf(2.0 * shift.y, 0.0)
		style.content_margin_bottom = maxf(-2.0 * shift.y, 0.0)


static func _measure(key: String, font: Font, glyph: String, font_size: int, box: Vector2) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or DisplayServer.get_name() == "headless":
		_waiting.erase(key)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(box) + Vector2i.ONE * PROBE_PAD * 2
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var probe := Button.new()
	probe.position = Vector2.ONE * PROBE_PAD
	probe.size = box
	probe.text = glyph
	probe.add_theme_font_override("font", font)
	probe.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		probe.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		probe.add_theme_color_override(state, Color.WHITE)
	viewport.add_child(probe)
	loop.root.add_child(viewport)
	await loop.process_frame
	await loop.process_frame
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	var shift := _shift_from(image, box)
	_shifts[key] = shift
	for btn in _waiting.get(key, []):
		if is_instance_valid(btn) and _key(btn) == key:
			_apply(btn, shift)
	_waiting.erase(key)


## From the probe's picture: how far to move the ink, right and down, to put it on the box's middle.
static func _shift_from(image: Image, box: Vector2) -> Vector2:
	if image == null or image.is_empty():
		return Vector2.ZERO
	var ink := Rect2i()
	var found := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.3:
				if not found:
					ink = Rect2i(x, y, 1, 1)
					found = true
				else:
					ink = ink.expand(Vector2i(x, y))
	if not found:
		return Vector2.ZERO
	var ink_centre := Vector2(ink.position) + (Vector2(ink.size) + Vector2.ONE) / 2.0
	return (Vector2.ONE * PROBE_PAD + box / 2.0 - ink_centre).snapped(Vector2(0.5, 0.5))
