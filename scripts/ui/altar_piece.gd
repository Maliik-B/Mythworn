class_name AltarPiece
extends SetPiece
## "The name comes back." A forgotten relic wakes at a record site: it lands on a plinth in the
## dark under the name it has worn down to, one shaft of plain light falls, and that name dissolves
## left to right as the one it had inks in behind it, the thing itself coming back in the same sweep.
## Then the relic's own sentence of waking. Every word here is the relic's own data.
##
## The plinth, the light and the words are chrome. The figures are owned art, one data slot each.
##
## Trigger, once a run has started:
##   await AltarPiece.play(parent, AltarPiece.HERO_RELIC).finished

## The stage's one grid, in screen pixels. Every figure's scale is a whole multiple of it.
const GRID := 6
const PLINTH_TOP := 470.0
const PLINTH_W := 90
const PLINTH_H := 26
const NAME_Y := 650.0
const NAME_WIDTH := 1200.0

## The relics that have art: a sprite on transparent ground and the screen pixels per art pixel. The
## worn form is the same art with its colour taken out, or its own sprite when the slot names a
## `worn_path` (two bakes of one render, the same silhouette, so the sweep changes only the colour).
## A relic not listed stands on its name alone, so a bought sprite is one line here and nothing else.
const FIGURES := {
	"A Plain Shield": {"path": "res://assets/sprites/icons/in_the_void/individual/shield.png", "scale": 12},
	"A Bare Scabbard": {
		"path": "res://assets/sprites/set_pieces/scabbard_ornate.png",
		"worn_path": "res://assets/sprites/set_pieces/scabbard_bare.png",
		"scale": 6,
	},
}
## The relic the clip stages: the scabbard, bare and then in its kermes and gold.
const HERO_RELIC := "A Bare Scabbard"


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
	var shaft := add_shaft(960.0, 820.0, Color(1.0, 0.95, 0.84), 0.0, PLINTH_TOP + PLINTH_H * GRID)
	var plinth_x := VIEW.x / 2.0 - PLINTH_W * GRID / 2.0
	var plinth := add_figure(SetPiece.pixel_texture(_plinth_image(), GRID), Vector2(plinth_x, PLINTH_TOP))
	plinth.modulate = Color(0.75, 0.75, 0.75)

	# The thing itself: the worn form, then the woken form over it, written in by the same sweep as
	# the name. A relic with no figure yet stands on its name alone.
	var figures := AltarPiece.figures_for(dormant_name)
	var worn: Sprite2D = null
	var whole: Sprite2D = null
	if not figures.is_empty():
		var worn_tex: Texture2D = figures["worn"]
		var whole_tex: Texture2D = figures["whole"]
		var at := Vector2(VIEW.x / 2.0 - worn_tex.get_width() / 2.0, PLINTH_TOP - worn_tex.get_height() + 4.0)
		worn = add_figure(worn_tex, at)
		whole = add_figure(whole_tex, at)
		make_inkable(whole, 0.0, whole_tex.get_width())
	var veil := add_shaft(960.0, 620.0, Color(1.0, 0.95, 0.84), 0.0, PLINTH_TOP + PLINTH_H * GRID)

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

	var line := add_line(dormant.wake_line, BODY_FACE, 50, BONE, 752.0)
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


## The worn and woken forms of a relic's figure from its slot, or empty if it has none yet. Trimmed
## to the thing itself, or an empty margin floats it above the plinth.
static func figures_for(dormant_name: String) -> Dictionary:
	if not FIGURES.has(dormant_name):
		return {}
	var slot: Dictionary = FIGURES[dormant_name]
	var art: Texture2D = load(slot["path"])
	var sheet := art.get_image()
	sheet.decompress()
	var image := sheet.get_region(sheet.get_used_rect())
	var plain: Image = image.duplicate()
	if slot.has("worn_path"):
		var worn_art: Texture2D = load(slot["worn_path"])
		plain = worn_art.get_image()
		plain.decompress()
		plain = plain.get_region(plain.get_used_rect())
	else:
		for x in plain.get_width():
			for y in plain.get_height():
				var c := plain.get_pixel(x, y)
				var v := c.get_luminance() * 0.7
				plain.set_pixel(x, y, Color(v, v * 0.98, v * 0.94, c.a))
	return {
		"worn": SetPiece.pixel_texture(plain, slot["scale"]),
		"whole": SetPiece.pixel_texture(image, slot["scale"]),
	}
