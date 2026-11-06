class_name AltarPiece
extends SetPiece
## "The name comes back." A forgotten relic wakes at a record site: it lands on a plinth in the
## dark under the name it has worn down to, one shaft of plain light falls, and that name dissolves
## left to right as the one it had inks in behind it, the thing itself coming back in the same sweep.
## Then the relic's own sentence of waking. Every word here is the relic's own data.
##
## Trigger, once a run has started:
##   await AltarPiece.play(parent, "A Bare Scabbard").finished

const PIXEL := 8
const PLINTH_TOP := 450.0
const PLINTH_W := 80
const PLINTH_H := 24
const NAME_Y := 672.0
const NAME_WIDTH := 1200.0

const SHIELD_ICON := "res://assets/sprites/icons/in_the_void/individual/shield.png"


## Stages the waking of this dormant relic. Reads names and line from RelicPool.
static func play(parent: Node, dormant_name: String) -> AltarPiece:
	var piece := AltarPiece.new()
	parent.add_child(piece)
	piece._run(dormant_name)
	return piece


func _run(dormant_name: String) -> void:
	var dormant := RelicPool.get_relic_by_name(dormant_name)
	var woken := RelicPool.get_relic_by_name(String(dormant.wakes_into)) if dormant != null else null
	if dormant == null or woken == null:
		push_warning("Altar has no relic pair for: %s" % dormant_name)
		await close(0.01)
		return

	world.modulate = Color(0, 0, 0, 1)
	# The shaft falls behind the plinth and the thing on it, so the thing keeps its own colour.
	var shaft := add_shaft(960.0, 820.0, Color(1.0, 0.95, 0.84), 0.0, PLINTH_TOP + PLINTH_H * PIXEL)
	var plinth_x := VIEW.x / 2.0 - PLINTH_W * PIXEL / 2.0
	var plinth := add_figure(SetPiece.pixel_texture(_plinth_image(), PIXEL), Vector2(plinth_x, PLINTH_TOP))
	plinth.modulate = Color(0.75, 0.75, 0.75)

	# The thing itself: the worn form, then the woken form over it, written in by the same sweep as
	# the name. A relic with no figure yet stands on its name alone.
	var figures := _figures_for(dormant_name)
	var worn: Sprite2D = null
	var whole: Sprite2D = null
	if not figures.is_empty():
		var worn_tex: Texture2D = figures["worn"]
		var whole_tex: Texture2D = figures["whole"]
		var at := Vector2(VIEW.x / 2.0 - worn_tex.get_width() / 2.0, PLINTH_TOP - worn_tex.get_height() + 4.0)
		worn = add_figure(worn_tex, at)
		whole = add_figure(whole_tex, at)
		make_inkable(whole, 0.0, whole_tex.get_width())
	var veil := add_shaft(960.0, 620.0, Color(1.0, 0.95, 0.84), 0.0, PLINTH_TOP + PLINTH_H * PIXEL)

	var old_name := add_line(dormant.relic_name, TITLE_FACE, 72, ASH, NAME_Y, NAME_WIDTH)
	var new_name := add_line(woken.relic_name, TITLE_FACE, 72, GOLD, NAME_Y, NAME_WIDTH)
	# Both names cross the same stretch of stage, so the one writes where the other leaves.
	var span := _shared_span(old_name, new_name)
	for label in [old_name, new_name]:
		label.material.set_shader_parameter("origin_x", (NAME_WIDTH - span) / 2.0)
		label.material.set_shader_parameter("span_x", span)

	dim_in(0.25)
	bars_in(0.3)
	var t := create_tween()
	t.tween_property(world, "modulate", Color.WHITE, _d(0.3))
	skippable = true
	await beat(0.3)

	# It lands. Everything else waits on this.
	if worn != null:
		var rest := worn.position.y
		worn.position.y = rest - 26.0
		whole.position.y = rest - 26.0
		var drop := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		drop.tween_property(worn, "position:y", rest, _d(0.1))
		drop.tween_property(whole, "position:y", rest, _d(0.1))
		await beat(0.1)
		jolt(4.0)
	ink_in(old_name, 0.25)
	await beat(0.6)

	shaft_fall(shaft, 0.55, 0.4)
	shaft_fall(veil, 0.06, 0.4)
	var lit := create_tween()
	lit.tween_property(plinth, "modulate", Color(1.35, 1.3, 1.2), _d(0.5))
	await beat(0.4)

	ink_out(old_name, 1.6)
	ink_in(new_name, 1.6)
	if whole != null:
		ink_in(whole, 1.6)
	await beat(2.0)

	var line := add_line(dormant.wake_line, BODY_FACE, 50, BONE, 776.0)
	ink_in(line, 0.7)
	await beat(2.8)
	await close()


func _shared_span(a: Label, b: Label) -> float:
	var font := SetPiece._face(TITLE_FACE)
	var widest := 0.0
	for label: Label in [a, b]:
		widest = maxf(widest, font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x)
	return widest


## A plain square block with a plain cap. No steps and no stepped base: a plinth, nothing more.
func _plinth_image() -> Image:
	var image := SetPiece.stone_image(PLINTH_W, PLINTH_H, 73, 1, 0)
	for x in PLINTH_W:
		image.set_pixel(x, 0, Color(0.34, 0.33, 0.31))
		image.set_pixel(x, 1, Color(0.24, 0.23, 0.22))
		image.set_pixel(x, 2, Color(0.07, 0.07, 0.065))
	return image


## The worn and woken forms of a relic's figure, or empty if it has none yet. Relic art is a
## commission: the scabbard is plain code-drawn chrome until then, and the shield is the licensed
## icon, drained for its worn form.
func _figures_for(dormant_name: String) -> Dictionary:
	match dormant_name:
		"A Bare Scabbard":
			return {
				"worn": SetPiece.pixel_texture(_scabbard_image(false), PIXEL),
				"whole": SetPiece.pixel_texture(_scabbard_image(true), PIXEL),
			}
		"A Plain Shield":
			var icon: Texture2D = load(SHIELD_ICON)
			var sheet := icon.get_image()
			sheet.decompress()
			# Trimmed to the shield itself, or its empty margin floats it above the plinth.
			var image := sheet.get_region(sheet.get_used_rect())
			var plain: Image = image.duplicate()
			for x in plain.get_width():
				for y in plain.get_height():
					var c := plain.get_pixel(x, y)
					var v := c.get_luminance() * 0.7
					plain.set_pixel(x, y, Color(v, v * 0.98, v * 0.94, c.a))
			return {
				"worn": SetPiece.pixel_texture(plain, PIXEL),
				"whole": SetPiece.pixel_texture(image, PIXEL),
			}
	return {}


## A long scabbard lying on its side, throat to the left, narrowing a pixel at a time to a small
## chape. Worn: leather rubbed smooth, one tired brown, the fittings gone dull, the device gone.
## Whole: the same shape with the tooling back on it and the fittings bright.
func _scabbard_image(whole: bool) -> Image:
	var w := 72
	var h := 12
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var leather := Color(0.36, 0.17, 0.11) if whole else Color(0.25, 0.22, 0.19)
	var leather_lit := Color(0.50, 0.26, 0.16) if whole else Color(0.33, 0.29, 0.25)
	var leather_dark := Color(0.21, 0.10, 0.07) if whole else Color(0.15, 0.13, 0.12)
	var metal := Color(0.82, 0.64, 0.30) if whole else Color(0.34, 0.32, 0.30)
	var metal_lit := Color(0.97, 0.84, 0.50) if whole else Color(0.44, 0.42, 0.39)
	var metal_dark := Color(0.50, 0.36, 0.15) if whole else Color(0.22, 0.21, 0.19)
	var tooling := Color(0.90, 0.72, 0.36)
	for x in w:
		var top := _scabbard_top(x)
		var bottom := _scabbard_bottom(x, h)
		var fitted := x < 5 or (x >= 14 and x < 17) or x >= 61
		for y in range(top, bottom + 1):
			var c := metal if fitted else leather
			if y == top:
				c = metal_lit if fitted else leather_lit
			elif y == bottom:
				c = metal_dark if fitted else leather_dark
			image.set_pixel(x, y, c)
		# The throat's collar stands proud of the body.
		if x < 3:
			image.set_pixel(x, top - 1, metal_lit)
			image.set_pixel(x, bottom + 1, metal_dark)
	# The ring it hung by, on the locket.
	for x in [7, 8, 9, 10]:
		image.set_pixel(x, 0, metal)
	image.set_pixel(7, 1, metal_dark)
	image.set_pixel(10, 1, metal_dark)
	if whole:
		# The tooling: a running line along each edge and a repeat of small lozenges between.
		for x in range(18, 60):
			var top := _scabbard_top(x)
			var bottom := _scabbard_bottom(x, h)
			image.set_pixel(x, top + 1, tooling.darkened(0.3))
			image.set_pixel(x, bottom - 1, tooling.darkened(0.4))
		for x in range(20, 57, 7):
			var mid := (_scabbard_top(x + 1) + _scabbard_bottom(x + 1, h)) / 2
			image.set_pixel(x, mid, tooling)
			image.set_pixel(x + 2, mid, tooling)
			image.set_pixel(x + 1, mid - 1, tooling.lightened(0.15))
			image.set_pixel(x + 1, mid + 1, tooling.darkened(0.1))
	return image


## The scabbard's upper edge at this column: it loses a pixel a side, in turns, toward the tip.
func _scabbard_top(x: int) -> int:
	var top := 2
	if x > 22:
		top += 1
	if x > 46:
		top += 1
	if x > 67:
		top += 1
	return top


func _scabbard_bottom(x: int, h: int) -> int:
	var bottom := h - 3
	if x > 34:
		bottom -= 1
	if x > 58:
		bottom -= 1
	if x > 67:
		bottom -= 1
	return bottom
