class_name SetPiece
extends CanvasLayer
## The stage a set piece stands on, shared by every later one, so nothing here knows about events.
## A piece is a subclass: it puts its figures in `world` (or `fore`), its words in `words`, runs its
## timeline with `beat()`, and ends with `close()`. The kit is a dim, letterbox bars and a grade
## over everything beneath them; ink that writes or leaves; a drain that takes colour out; one
## additive shaft of plain light; a seal stamp. Muted by design: there is no sound on the stage
## yet, because no one has cleared any. No purple and no veins: corruption here is subtraction.
##
## A click or the accept key is the only input. A piece reads `held` and `presses` while it wants
## them, and once it sets `skippable`, a press hurries the rest of the timeline to its end.
## All timing runs on process frames, so it pauses with the tree and is frame-exact under
## --fixed-fps, which is how the capture rig films it.

signal finished

## Below TitleEarnedPopup (90) and SceneTransition (100).
const STAGE_LAYER := 80
const VIEW := Vector2(1920, 1080)
## The bars' inner edges sit on the phone crop's edges (a 1000x900 centre), so whatever a piece keeps
## between them and inside x 460..1460 survives both aspects.
const BAR_H := 90.0
const SAFE_W := 1000.0
## How wide a line of words runs by default, a little inside the crop's edges.
const LINE_W := 940.0
## The two faces, read from the card face so a font swap stays one line there: the title face is not
## finally picked.
const TITLE_FACE := CardFace.TITLE_FONT_PATH
const BODY_FACE := CardFace.RULES_FONT_PATH

const BLACK := Color(0.018, 0.016, 0.014)
const BONE := Color(0.90, 0.87, 0.80)
const ASH := Color(0.60, 0.58, 0.54)
const GOLD := Color(0.95, 0.79, 0.42)

const GRADE_SHADER := preload("res://assets/shaders/set_piece_grade.gdshader")
const INK_SHADER := preload("res://assets/shaders/ink_dissolve.gdshader")
const DRAIN_SHADER := preload("res://assets/shaders/drain.gdshader")
const SHAFT_SHADER := preload("res://assets/shaders/shaft.gdshader")
const GLOW_SHADER := preload("res://assets/shaders/stage_glow.gdshader")

var root: Control
var world: Node2D
var fore: Node2D
var words: Control
var held := false
var presses := 0
var skippable := false

var _dim: ColorRect
var _grade: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _hurrying := false
var _zoom := 1.0
var _zoom_pivot := VIEW / 2.0


func _init() -> void:
	layer = STAGE_LAYER
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(root)

	_dim = ColorRect.new()
	_dim.color = BLACK
	_dim.modulate.a = 0.0
	_dim.size = VIEW
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)

	world = Node2D.new()
	root.add_child(world)
	fore = Node2D.new()
	root.add_child(fore)

	_grade = ColorRect.new()
	_grade.size = VIEW
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.visible = false
	var grade_mat := ShaderMaterial.new()
	grade_mat.shader = GRADE_SHADER
	grade_mat.set_shader_parameter("saturation", 1.0)
	grade_mat.set_shader_parameter("tint", Vector3.ONE)
	_grade.material = grade_mat
	root.add_child(_grade)

	_bar_top = _make_bar()
	_bar_bottom = _make_bar()
	_bar_bottom.position.y = VIEW.y

	words = Control.new()
	words.size = VIEW
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(words)


func _make_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color.BLACK
	bar.size = Vector2(VIEW.x, 0.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return bar


func _input(event: InputEvent) -> void:
	var is_click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	var is_accept: bool = event.is_action("ui_accept") and not event.is_echo()
	if not (is_click or is_accept):
		return
	get_viewport().set_input_as_handled()
	held = event.is_pressed()
	if held:
		presses += 1
		if skippable:
			_hurrying = true


# ============================================================
# TIME
# ============================================================

## Waits this long on the stage's clock: stops for a pause, ends at once when hurried.
func beat(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not _hurrying:
		await get_tree().process_frame
		if not get_tree().paused:
			left -= get_process_delta_time()


## Runs the rest of the timeline straight to its end. A press does this once a piece is skippable.
func hurry() -> void:
	_hurrying = true


## A duration, or next to nothing once the player has hurried the stage on.
func _d(seconds: float) -> float:
	return 0.001 if _hurrying else seconds


## Lets the stage go: a fade back to whatever is beneath it, then `finished`.
func close(fade := 0.4) -> void:
	skippable = false
	var t := create_tween()
	t.tween_property(root, "modulate:a", 0.0, 0.1 if _hurrying else fade)
	await t.finished
	finished.emit()
	queue_free()


# ============================================================
# THE STAGE: DIM, BARS, GRADE, PUSH
# ============================================================

func dim_in(dur := 0.3, alpha := 1.0) -> Tween:
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", alpha, _d(dur))
	return t


func bars_in(dur := 0.3) -> Tween:
	var t := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(_bar_top, "size:y", BAR_H, _d(dur))
	t.tween_property(_bar_bottom, "size:y", BAR_H, _d(dur))
	t.tween_property(_bar_bottom, "position:y", VIEW.y - BAR_H, _d(dur))
	return t


## Takes everything beneath the bars toward this saturation, 1.0 being untouched.
func grade(saturation: float, dur := 0.0, tint := Color.WHITE) -> Tween:
	_grade.visible = true
	var mat: ShaderMaterial = _grade.material
	var t := create_tween().set_parallel(true)
	t.tween_property(mat, "shader_parameter/saturation", saturation, maxf(_d(dur), 0.001))
	t.tween_property(mat, "shader_parameter/tint", Vector3(tint.r, tint.g, tint.b), maxf(_d(dur), 0.001))
	return t


func set_zoom_pivot(pivot: Vector2) -> void:
	_zoom_pivot = pivot
	_apply_zoom(_zoom)


## Pushes in or pulls out on the world around the pivot. `fore` stays put, for parallax.
func zoom_to(amount: float, dur: float, trans := Tween.TRANS_SINE) -> Tween:
	var t := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(trans)
	t.tween_method(_apply_zoom, _zoom, amount, _d(dur))
	return t


func _apply_zoom(amount: float) -> void:
	_zoom = amount
	world.scale = Vector2(amount, amount)
	world.position = _zoom_pivot * (1.0 - amount)


## A small knock to the world, for something landing. Quiet: a few pixels, gone in a moment.
func jolt(pixels := 4.0) -> void:
	var rest := world.position
	world.position = rest + Vector2(0, pixels)
	var t := create_tween()
	t.tween_property(world, "position", rest, _d(0.12)).set_ease(Tween.EASE_OUT)


# ============================================================
# LIGHT
# ============================================================

## One shaft of plain light, off until `shaft_to` or `shaft_fall`. Added to `world` by default, so
## add it after whatever it should fall across.
func add_shaft(center_x: float, width: float, tint := Color(1.0, 0.95, 0.84), top := 0.0, bottom := VIEW.y) -> ColorRect:
	var shaft := ColorRect.new()
	shaft.position = Vector2(center_x - width / 2.0, top)
	shaft.size = Vector2(width, bottom - top)
	shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("rect_size", shaft.size)
	shaft.material = mat
	world.add_child(shaft)
	return shaft


func shaft_to(shaft: ColorRect, intensity: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(shaft.material, "shader_parameter/intensity", intensity, _d(dur))
	return t


## The light comes down from the top of the shaft rather than brightening where it stands.
func shaft_fall(shaft: ColorRect, intensity: float, dur: float) -> Tween:
	var mat: ShaderMaterial = shaft.material
	mat.set_shader_parameter("reach", 0.0)
	mat.set_shader_parameter("intensity", intensity)
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(mat, "shader_parameter/reach", 1.15, _d(dur))
	return t


## A soft pool of additive light, off until `glow_to`.
func add_glow(center: Vector2, box: Vector2, tint := Color(1.0, 0.95, 0.84), parent: Node = null) -> ColorRect:
	var glow := ColorRect.new()
	glow.position = center - box / 2.0
	glow.size = box
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("intensity", 0.0)
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	glow.material = mat
	(parent if parent != null else world).add_child(glow)
	return glow


func glow_to(glow: ColorRect, intensity: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(glow.material, "shader_parameter/intensity", intensity, _d(dur))
	return t


# ============================================================
# INK
# ============================================================

## A line of words, centred on the stage, written by `ink_in`. Unwritten until then.
func add_line(text: String, face: String, font_size: int, color: Color, y: float, width := LINE_W) -> Label:
	var font := _face(face)
	var line := Label.new()
	line.text = text
	line.add_theme_font_override("font", font)
	line.add_theme_font_size_override("font_size", font_size)
	line.add_theme_color_override("font_color", color)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.position = Vector2((VIEW.x - width) / 2.0, y)
	line.size = Vector2(width, 0.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(line)
	var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
	# One line sweeps across its own letters; a wrapped block inks down its lines.
	var wrapped := measured.y > font.get_height(font_size) * 1.5
	var inset := (width - minf(measured.x, width)) / 2.0
	make_inkable(line, inset, minf(measured.x, width), measured.y if wrapped else 0.0)
	return line


## A stage face, or the engine's fallback if it is missing: words on the stage, whatever happens.
static func _face(path: String) -> Font:
	var font: Font = load(path) if ResourceLoader.exists(path) else null
	return font if font != null else ThemeDB.fallback_font


## Gives any canvas item the ink shader, measured in its own pixels. Items given the same origin and
## span sweep together.
func make_inkable(item: CanvasItem, origin_x: float, span_x: float, span_y := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = INK_SHADER
	mat.set_shader_parameter("origin_x", origin_x)
	mat.set_shader_parameter("span_x", span_x)
	mat.set_shader_parameter("span_y", span_y)
	mat.set_shader_parameter("progress", 0.0)
	item.material = mat
	return mat


func ink_in(item: CanvasItem, dur: float) -> Tween:
	var mat: ShaderMaterial = item.material
	mat.set_shader_parameter("leaving", false)
	mat.set_shader_parameter("progress", 0.0)
	var t := create_tween()
	t.tween_property(mat, "shader_parameter/progress", 1.0, _d(dur))
	return t


func ink_out(item: CanvasItem, dur: float) -> Tween:
	var mat: ShaderMaterial = item.material
	mat.set_shader_parameter("leaving", true)
	mat.set_shader_parameter("progress", 0.0)
	var t := create_tween()
	t.tween_property(mat, "shader_parameter/progress", 1.0, _d(dur))
	return t


# ============================================================
# THE DRAIN
# ============================================================

## Gives a canvas item the drain, at this amount. Replaces whatever material it had.
func make_drainable(item: CanvasItem, amount := 0.0, dim := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = DRAIN_SHADER
	mat.set_shader_parameter("amount", amount)
	mat.set_shader_parameter("dim", dim)
	item.material = mat
	return mat


## Takes colour out of a thing (toward 1.0) or lets it come back (toward 0.0).
func drain_to(item: CanvasItem, amount: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(item.material, "shader_parameter/amount", amount, _d(dur))
	return t


# ============================================================
# THE STAMP
# ============================================================

## A word in a plain ruled frame, ready to be stamped. Invisible until `stamp`.
func add_stamp_plate(text: String, font_size: int, color: Color, center: Vector2, tilt_degrees := -2.5) -> Control:
	var plate := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = color
	box.set_border_width_all(3)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 4
	box.content_margin_bottom = 8
	plate.add_theme_stylebox_override("panel", box)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var word := Label.new()
	word.text = text
	word.add_theme_font_override("font", _face(TITLE_FACE))
	word.add_theme_font_size_override("font_size", font_size)
	word.add_theme_color_override("font_color", color)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(word)
	words.add_child(plate)
	var plate_size := plate.get_combined_minimum_size()
	plate.size = plate_size
	plate.position = center - plate_size / 2.0
	plate.pivot_offset = plate_size / 2.0
	plate.rotation_degrees = tilt_degrees
	plate.modulate.a = 0.0
	return plate


## Comes down hard from above the stage and lands dead. Works on anything with a scale and modulate.
func stamp(item: CanvasItem, dur := 0.13) -> Tween:
	item.set("scale", Vector2(1.7, 1.7))
	item.modulate.a = 0.0
	var t := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	t.tween_property(item, "scale", Vector2.ONE, _d(dur))
	t.tween_property(item, "modulate:a", 1.0, _d(dur * 0.6))
	t.chain().tween_callback(jolt.bind(3.0))
	return t


# ============================================================
# FIGURES
# ============================================================

## A sprite added to the world or the given parent, top-left at `pos`.
func add_figure(texture: Texture2D, pos: Vector2, parent: Node = null) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = pos
	(parent if parent != null else world).add_child(sprite)
	return sprite


## One frame of a horizontal sprite strip, for standing a roster sprite on the stage.
static func strip_frame(sheet: Texture2D, frame_w: int, frame_h: int, index: int) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = sheet
	frame.region = Rect2(frame_w * index, 0, frame_w, frame_h)
	return frame


## Blows a small low-resolution image up to pixel size with hard edges baked in, so the stage can
## scale it smoothly without the pixels shimmering.
static func pixel_texture(image: Image, pixel_size: int) -> ImageTexture:
	var big: Image = image.duplicate()
	big.resize(image.get_width() * pixel_size, image.get_height() * pixel_size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(big)


## A worn block of granite, drawn from a fixed seed so it never touches a run's RNG. Lit from above,
## its shoulders knocked off, its sides leaning in toward the top, its foot going down into the
## dark. Nothing cracked or stained.
static func stone_image(w: int, h: int, stone_seed: int, shoulder := 7, lean := 4) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = stone_seed
	var blotch := FastNoiseLite.new()
	blotch.seed = stone_seed
	blotch.frequency = 0.11
	var edge := FastNoiseLite.new()
	edge.seed = stone_seed + 1
	edge.frequency = 0.07
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for x in w:
		var from_side := mini(x, w - 1 - x)
		var knocked := 0
		if from_side < shoulder:
			knocked = int(pow(float(shoulder - from_side) / float(shoulder), 2.0) * shoulder)
		var top := 1 + int(round(edge.get_noise_1d(x) * 3.0)) + knocked
		for y in range(maxi(top, 0), h):
			var leaning_in := int((1.0 - float(y) / float(h)) * lean)
			if from_side < leaning_in:
				continue
			var depth := float(y - top) / float(h)
			var side := float(x) / float(w)
			var value := 0.30 - depth * 0.20 - side * 0.05
			value += blotch.get_noise_2d(x, y) * 0.055
			if rng.randf() < 0.10:
				value += 0.025
			if y == maxi(top, 0):
				value += 0.14
			elif y == maxi(top, 0) + 1:
				value += 0.05
			# A short ramp of tones rather than a smooth one, so it reads as pixels and not as mush.
			value = maxf(snappedf(value, 0.035), 0.03)
			image.set_pixel(x, y, Color(value * 1.03, value, value * 0.95))
	return image


## Pulls a whole sentence out of shipped prose by a phrase inside it, so a stage line can never drift
## from the event's words: if the text is rewritten and the phrase goes, this comes back empty and
## roster_test fails rather than the stage quoting something the game no longer says.
static func sentence_with(text: String, phrase: String) -> String:
	var at := text.find(phrase)
	if at == -1:
		return ""
	var start := text.rfind(". ", at)
	start = 0 if start == -1 else start + 2
	var end := text.find(". ", at)
	end = text.length() if end == -1 else end + 1
	return text.substr(start, end - start).strip_edges()
