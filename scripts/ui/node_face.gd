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
## prime() measures every look the map and the crossing can wear before any of them is shown, so
## the first map of a session opens with each glyph already in place and nothing moves on screen.
## The splash and the title call it, and the map waits on settled() if it was opened before they did.
##
## The same reading serves a loose glyph in a Label (the card's cost and school coins): centre_glyph
## takes the box the glyph is centred in and a callback that is handed the shift to apply, so the
## caller decides whether it moves a position or an anchor offset.
##
## Does nothing in a headless run, which draws nothing to read.

const PROBE_PAD := 24  # transparent room around the probe button, in case a glyph overhangs its line
const DEFAULT_FONT := 20  # a look with no "font" of its own (MapNode)
const CROSSING_FONT := 26  # CrossingStage.ICON_FONT, which wears the same button
const COIN_COST_FONT := 21  # CardFace's cost numeral, in the coin of this size
const COIN_COST_BOX := Vector2(32, 32)
const COIN_SCHOOL_SIZES := [22, 28]  # the school glyph's flat and resonant sizes
const COIN_SCHOOL_BOX := Vector2(42, 42)
const COIN_SCHOOL_GLYPHS := ["≈", "+", "⚔"]

static var _shifts: Dictionary = {}  # key -> Vector2, once measured
static var _waiting: Dictionary = {}  # key -> the buttons waiting on a measurement
static var _primed := false
static var _measuring := 0  # probes drawn and not yet read back


## prime() for the map's own node size, which is the one every button wears.
static func prime_for_map() -> void:
	var size: int = load("res://scenes/map/map_scene.gd").NODE_SIZE
	prime(Vector2.ONE * size)


## Measures every glyph the map and the crossing can show, for a node button `box` big. Safe to call
## again: the second call finds the first's work done or under way.
static func prime(box: Vector2) -> void:
	if _primed:
		return
	_primed = true
	var template := Button.new()
	var font: Font = template.get_theme_font("font")
	template.free()
	var wanted: Array = []
	for look in MapNode.TYPE_LOOKS.values():
		wanted.append([look["glyph"], look.get("font", DEFAULT_FONT)])
	for look in MapNode.SCRIPTED_LOOKS.values():
		wanted.append([look["glyph"], look.get("font", DEFAULT_FONT)])
	wanted.append([MapNode.WEAKENED_ELITE_LOOK["glyph"], DEFAULT_FONT])
	wanted.append([MapNode.QUEST_MARK_LOOK["glyph"], MapNode.QUEST_MARK_LOOK.get("font", DEFAULT_FONT)])
	for look in CrossingStage.CROSSING_LOOKS.values():
		wanted.append([look["glyph"], CROSSING_FONT])
	for pair in wanted:
		var key := "%s|%d|%d|%d" % [pair[0], pair[1], int(box.x), font.get_rid().get_id() if font else 0]
		if _shifts.has(key) or _waiting.has(key):
			continue
		_waiting[key] = []
		_measure(key, font, pair[0], pair[1], box)
	_prime_coins()


## The card's two coins: every cost it can print and every school glyph at each size it wears, so a
## hand dealt on the first turn of a session has its glyphs centred when it is first drawn.
static func _prime_coins() -> void:
	var cost_font: Font = load(CardFace.NUMERAL_FONT_PATH)
	var school_font: Font = load(StageSkin.LINE_FONT_PATH)
	for glyph in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "X"]:
		_prime_glyph(glyph, cost_font, COIN_COST_FONT, COIN_COST_BOX)
	for glyph in COIN_SCHOOL_GLYPHS:
		for size in COIN_SCHOOL_SIZES:
			_prime_glyph(glyph, school_font, size, COIN_SCHOOL_BOX)


static func _prime_glyph(glyph: String, font: Font, font_size: int, box: Vector2) -> void:
	var key := _glyph_key(glyph, font, font_size, box)
	if _shifts.has(key) or _waiting.has(key):
		return
	_waiting[key] = []
	_measure(key, font, glyph, font_size, box)


## True when nothing is left to measure, so a map built now draws its glyphs where they belong.
static func is_settled() -> bool:
	return _measuring == 0


## Waits for every probe prime() started. Returns at once when there are none.
static func settled() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	while _measuring > 0 and loop != null:
		await loop.process_frame


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


## Centres `glyph`, drawn in `font` at `font_size`, on the middle of a `box` it is centred in by
## line box. `place` is called with the shift to apply, at once if the glyph is already measured and
## otherwise two frames after the first draw; it is not called in a headless run.
static func centre_glyph(glyph: String, font: Font, font_size: int, box: Vector2, place: Callable) -> void:
	if glyph == "":
		return
	var key := _glyph_key(glyph, font, font_size, box)
	if _shifts.has(key):
		place.call(_shifts[key])
		return
	if _waiting.has(key):
		_waiting[key].append(place)
		return
	_waiting[key] = [place]
	_measure(key, font, glyph, font_size, box)


static func _glyph_key(glyph: String, font: Font, font_size: int, box: Vector2) -> String:
	return "%s|%d|%d|%d" % [glyph, font_size, int(box.x), font.get_rid().get_id() if font else 0]


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
	# Deferred, since the splash primes from its _ready while the root is still adding it, and the root
	# refuses a child then: the probe would never draw and every glyph would read as centred. It still
	# joins the tree before the frame is drawn.
	loop.root.add_child.call_deferred(viewport)
	_measuring += 1
	await loop.process_frame
	await loop.process_frame
	_measuring -= 1
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	var shift := _shift_from(image, box)
	_shifts[key] = shift
	for waiter in _waiting.get(key, []):
		if waiter is Callable:
			if waiter.is_valid():
				waiter.call(shift)
		elif is_instance_valid(waiter) and _key(waiter) == key:
			_apply(waiter, shift)
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
