class_name ExcaliburPiece
extends SetPiece
## The Sword in the Stone's two answers, on one stage. Nobody cheers on either. Taking it is held,
## the only hold in the game: the blade comes up in steps, everything stops, one shaft of plain light,
## and its name. Leaving it is the same stone in the same light, but you are the thing that moves:
## the world backs away, the dark closes in from both sides, the hilt goes dull and the words stand
## on what is left. Every word on this stage is read from the event, so none of it can drift from
## the prose.
##
## One world at one scale: the stage's grid is GRID pixels, as a lone figure is in combat, and
## everything stands on it, so a sword is a sword a person could lift and the man beside it is a man.
## The stone is chrome, drawn in code. The figures are owned art, one data slot each, so a bought
## sprite is a one-line swap.
##
## Trigger, from anything with a tree, once a run has started (the event scene does this too):
##   await ExcaliburPiece.play_take(parent, choice, true).finished    # true: the camera holds
##   await ExcaliburPiece.play_leave(parent, event_name, choice).finished

## How long the blade takes under a steady hold.
const PULL_SECONDS := 1.8
## The stage's one grid, in screen pixels. Every figure's scale is a whole multiple of it.
const GRID := 6
const STONE_W := 52
const STONE_H := 30
const STONE_TOP := 550.0
## The sword: hilt up, tip down, on transparent ground. `scale` is screen pixels per art pixel.
## `seated_rows` is how much shows above the stone before it moves (sunk to the hilt); `guard_row` is
## where the light catches it. It is 75 art pixels tall on the man's own grid (scale 6), a CC0 model
## rendered and baked to the page look by tools/bake_prop.py, so a sword here is as dense as he is.
const SWORD := {
	"path": "res://assets/sprites/set_pieces/excalibur_sword.png",
	"scale": 6,
	"seated_rows": 22,
	"guard_row": 15,
}
## The man at the foot of the stone. `cell` is one frame of the strip; `flip` turns him to the stone.
## `slumped` is the take, `hunched` the refusal's opening, `settled` its one cut.
const CHAMPION := {
	"path": "res://assets/sprites/enemies/camelot/man_at_arms/Death.png",
	"cell": Vector2i(184, 137),
	"scale": 6,
	"flip": true,
	"slumped": 7,
	"hunched": 4,
	"settled": 5,
}
## The trees you step back into. Empty: no owned sprite fits yet, so it is plain darkness closing in.
## A vertical sprite's path here stands in for the dark, one per side, with no other change.
const TREE_PATH := ""
## Where the closing dark's inner edges come to rest, and how far off stage they start.
const CLOSED_LEFT := 640.0
const CLOSED_RIGHT := 1280.0
const CLOSED_MARGIN := 300.0
## What a hold-less tap gives, so a tap still does something and tapping alone can finish it.
const TAP_NUDGE := 0.12
const SINK_PER_SECOND := 0.18
## Past this it comes the rest of the way by itself, whether or not you are still holding: it comes
## free surprisingly easily, and letting go at the very top must not leave it hanging there.
const COMES_FREE_AT := 0.8

var _sword: Sprite2D
var _stone: Sprite2D
var _grit: CPUParticles2D
var _rule: ColorRect
var _seated_y := 0.0
var _free_y := 0.0


## Taking it. `camera_holds` plays the hold for itself, for the capture rig.
static func play_take(parent: Node, choice: EventData.EventChoice, camera_holds := false) -> ExcaliburPiece:
	var piece := ExcaliburPiece.new()
	parent.add_child(piece)
	piece._run_take(choice, camera_holds)
	return piece


## Leaving it in the stone.
static func play_leave(parent: Node, event_name: String, choice: EventData.EventChoice) -> ExcaliburPiece:
	var piece := ExcaliburPiece.new()
	parent.add_child(piece)
	piece._run_leave(event_name, choice)
	return piece


## The line the take ends on, read from the choice's own prose.
static func take_line(choice: EventData.EventChoice) -> String:
	return SetPiece.sentence_with(choice.result_text, "impossibly light")


## The line the refusal ends on, read from the choice's own prose.
static func leave_line(choice: EventData.EventChoice) -> String:
	return SetPiece.sentence_with(choice.result_text, "The choice not to reach")


# ============================================================
# THE STAGE BOTH ANSWERS SHARE
# ============================================================

func _stone_foot() -> float:
	return STONE_TOP + STONE_H * GRID


func _build_stone_and_sword() -> void:
	set_zoom_pivot(Vector2(VIEW.x / 2.0, STONE_TOP))
	world.modulate = Color(0, 0, 0, 1)

	var floor_glow := add_glow(Vector2(960, _stone_foot() + 4.0), Vector2(1400, 220))
	floor_glow.material.set_shader_parameter("intensity", 0.16)

	var sheet: Texture2D = load(SWORD["path"])
	var image := sheet.get_image()
	image.decompress()
	var scale_up: int = SWORD["scale"]
	_sword = add_figure(SetPiece.pixel_texture(image, scale_up), Vector2.ZERO)
	_sword.position.x = snappedf(VIEW.x / 2.0 - _sword.texture.get_width() / 2.0, GRID)
	_seated_y = STONE_TOP - int(SWORD["seated_rows"]) * scale_up
	# Clear of the stone by a hand's width when it is free, so nobody reads it as still seated.
	_free_y = STONE_TOP - _sword.texture.get_height() - GRID * 8
	_seat_sword(_seated_y)
	make_drainable(_sword, 0.8)

	var stone_x := snappedf(VIEW.x / 2.0 - STONE_W * GRID / 2.0, GRID)
	_stone = add_figure(SetPiece.pixel_texture(SetPiece.stone_image(STONE_W, STONE_H, 41), GRID), Vector2(stone_x, STONE_TOP))


## Sets the blade's height. What is still inside the stone is simply not drawn.
func _seat_sword(y: float) -> void:
	var full: Vector2 = _sword.texture.get_size()
	_sword.position.y = y
	_sword.region_enabled = true
	_sword.region_rect = Rect2(0, 0, full.x, clampf(STONE_TOP + GRID * 4 - y, 0.0, full.y))


## One frame of the man's strip, its feet on the ground and its stone-side edge at `stone_side_x`.
## Measured from the art, so a bought sprite in the slot stands where it should with no new numbers.
func _add_champion(frame: int, stone_side_x: float, tone: float) -> Sprite2D:
	var sheet: Texture2D = load(CHAMPION["path"])
	var cell: Vector2i = CHAMPION["cell"]
	var scale_up: int = CHAMPION["scale"]
	var man := add_figure(SetPiece.strip_frame(sheet, cell.x, cell.y, frame), Vector2.ZERO)
	man.flip_h = CHAMPION["flip"]
	man.scale = Vector2(scale_up, scale_up)
	man.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var body := _body_of_frame(frame)
	var side_in_cell: int = cell.x - body.position.x if man.flip_h else body.end.x
	man.position = Vector2(
		snappedf(stone_side_x - side_in_cell * scale_up, GRID),
		snappedf(_stone_foot() - body.end.y * scale_up, GRID))
	man.modulate = Color(tone, tone * 0.97, tone * 0.93)
	make_drainable(man, 1.0)
	return man


## Where a frame's figure actually sits inside its cell.
func _body_of_frame(frame: int) -> Rect2i:
	var sheet: Texture2D = load(CHAMPION["path"])
	var cell: Vector2i = CHAMPION["cell"]
	var image := sheet.get_image()
	image.decompress()
	return image.get_region(Rect2i(cell.x * frame, 0, cell.x, cell.y)).get_used_rect()


func _open_stage() -> void:
	dim_in(0.3)
	bars_in(0.35)
	grade(0.3)


func _world_up(dur: float) -> void:
	var t := create_tween()
	t.tween_property(world, "modulate", Color.WHITE, _d(dur))


# ============================================================
# TAKING IT
# ============================================================

func _run_take(choice: EventData.EventChoice, camera_holds: bool) -> void:
	_build_stone_and_sword()
	# He has gone still at the foot of the stone: the last of the roster's fall.
	var man := _add_champion(CHAMPION["slumped"], _stone.position.x + GRID * 2, 0.6)
	world.move_child(man, _sword.get_index())
	_grit = _make_grit()
	world.add_child(_grit)
	# The shaft falls behind the blade, so the steel stays steel, with a breath of it in front.
	var shaft := add_shaft(960.0, 560.0, Color(1.0, 0.95, 0.84), 0.0, _stone_foot() + 30.0)
	world.move_child(shaft, _sword.get_index())
	var veil := add_shaft(960.0, 420.0, Color(1.0, 0.95, 0.84), 0.0, _stone_foot() + 30.0)

	_open_stage()
	_world_up(0.5)
	await beat(0.75)

	var prompt := add_line(choice.text, BODY_FACE, 52, ASH, 868.0)
	ink_in(prompt, 0.4)
	_rule = ColorRect.new()
	_rule.color = ASH
	_rule.position = Vector2(VIEW.x / 2.0, 948.0)
	_rule.size = Vector2(0.0, 2.0)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(_rule)
	await beat(0.25)

	await _pull(camera_holds)

	# Free. Everything stops. In sound this is the cut to nothing; muted, it is a held still frame.
	_grit.emitting = false
	_rule.visible = false
	ink_out(prompt, 0.25)
	skippable = true
	await beat(0.5)

	shaft_fall(shaft, 0.55, 0.5)
	shaft_fall(veil, 0.10, 0.5)
	drain_to(_sword, 0.0, 0.7)
	_light_stone(0.7)
	grade(0.85, 0.8)
	await beat(0.55)

	var sword_name := add_line(String(choice.granted_relic_id), TITLE_FACE, 96, BONE, 752.0)
	ink_in(sword_name, 0.9)
	await beat(1.1)

	var line := add_line(ExcaliburPiece.take_line(choice), BODY_FACE, 54, ASH, 878.0)
	ink_in(line, 0.8)
	await beat(2.6)
	await close()


func _light_stone(dur: float) -> void:
	var t := create_tween()
	t.tween_property(_stone, "modulate", Color(1.5, 1.45, 1.32), _d(dur))


## The hold itself. The blade climbs on the pixel grid, grit falls from the seat, the world pushes in
## a little with it. Let go and it sinks back slowly; a tap still moves it, so nobody can be stuck.
func _pull(camera_holds: bool) -> void:
	var progress := 0.0
	var seen := presses
	while progress < 1.0 and not _hurrying:
		await get_tree().process_frame
		if get_tree().paused:
			continue
		var dt := get_process_delta_time()
		var holding := held or camera_holds or progress >= COMES_FREE_AT
		progress += dt / PULL_SECONDS if holding else -dt * SINK_PER_SECOND
		if presses > seen:
			progress += TAP_NUDGE
			seen = presses
		progress = clampf(progress, 0.0, 1.0)
		_grit.emitting = holding
		_set_pull(progress)
	_set_pull(1.0)


func _set_pull(progress: float) -> void:
	var climbed := lerpf(0.0, _seated_y - _free_y, pow(progress, 1.35))
	_seat_sword(_seated_y - snappedf(climbed, GRID))
	_apply_zoom(1.0 + 0.06 * progress)
	_rule.size.x = 480.0 * progress
	_rule.position.x = VIEW.x / 2.0 - _rule.size.x / 2.0


func _make_grit() -> CPUParticles2D:
	var grit := CPUParticles2D.new()
	grit.position = Vector2(VIEW.x / 2.0, STONE_TOP + 2.0)
	grit.amount = 26
	grit.lifetime = 0.75
	grit.emitting = false
	grit.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	grit.emission_rect_extents = Vector2(22, 1)
	grit.direction = Vector2(0, -1)
	grit.spread = 70.0
	grit.initial_velocity_min = 30.0
	grit.initial_velocity_max = 120.0
	grit.gravity = Vector2(0, 980)
	grit.scale_amount_min = 3.0
	grit.scale_amount_max = 6.0
	grit.color = Color(0.46, 0.44, 0.41)
	return grit


# ============================================================
# LEAVING IT
# ============================================================

func _run_leave(event_name: String, choice: EventData.EventChoice) -> void:
	_build_stone_and_sword()
	_sword.material.set_shader_parameter("amount", 1.0)
	var man := _add_champion(CHAMPION["hunched"], _stone.position.x - GRID * 2, 0.42)
	world.move_child(man, _sword.get_index())
	var shaft := add_shaft(960.0, 560.0, Color(1.0, 0.95, 0.84), 0.0, _stone_foot() + 30.0)
	world.move_child(shaft, _sword.get_index())
	_stone.modulate = Color(1.5, 1.45, 1.32)
	var glint := add_glow(Vector2(960, _seated_y + int(SWORD["guard_row"]) * int(SWORD["scale"])), Vector2(170, 170))
	var left_side := _add_closing_side(true)
	var right_side := _add_closing_side(false)

	_open_stage()
	_apply_zoom(1.06)
	shaft_to(shaft, 0.5, 0.3)
	glow_to(glint, 0.26, 0.3)
	_world_up(0.35)
	drain_to(_sword, 0.0, 0.3)
	var heading := add_line(event_name, TITLE_FACE, 72, BONE, 112.0)
	ink_in(heading, 0.55)
	await beat(1.05)
	skippable = true

	# You are what moves. The world backs away, the dark comes in from both sides, the hilt goes dull.
	zoom_to(0.6, 2.7)
	_slide_side(left_side, CLOSED_LEFT, 2.7)
	_slide_side(right_side, CLOSED_RIGHT, 2.7)
	shaft_to(shaft, 0.0, 1.9)
	glow_to(glint, 0.0, 0.9)
	var dull := create_tween()
	dull.tween_property(_stone, "modulate", Color(0.8, 0.8, 0.8), _d(1.9))
	drain_to(_sword, 1.0, 1.4)
	ink_out(heading, 1.2)
	await beat(1.3)
	# Behind you the beast settles over its stone again: one cut, never seen moving.
	var cell: Vector2i = CHAMPION["cell"]
	man.texture = SetPiece.strip_frame(load(CHAMPION["path"]), cell.x, cell.y, CHAMPION["settled"])
	await beat(1.0)

	var line := add_line(ExcaliburPiece.leave_line(choice), BODY_FACE, 56, BONE, 684.0)
	ink_in(line, 0.9)
	await beat(1.25)

	var title := TitlePool.get_title(choice.awarded_title_id)
	if title != null:
		var plate := add_stamp_plate(title.original_name, 58, GOLD, Vector2(VIEW.x / 2.0, 900.0))
		stamp(plate)
	await beat(2.4)
	await close()


## One side of what closes in as you back away, off stage until slid: the tree slot's sprite if it
## holds one, otherwise plain darkness with a soft inner edge. Its origin is that inner edge.
func _add_closing_side(on_left: bool) -> Node2D:
	var side := Node2D.new()
	fore.add_child(side)
	if TREE_PATH != "":
		var trunk := add_figure(load(TREE_PATH), Vector2.ZERO, side)
		trunk.scale = Vector2(GRID, GRID)
		trunk.position.x = -trunk.texture.get_width() * GRID if on_left else 0.0
	else:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(BLACK, 1.0))
		ramp.set_color(1, Color(BLACK, 0.0))
		ramp.add_point(0.86, Color(BLACK, 1.0))
		var fill := GradientTexture2D.new()
		fill.gradient = ramp
		fill.width = int(VIEW.x)
		fill.height = 4
		fill.fill_from = Vector2(0, 0) if on_left else Vector2(1, 0)
		fill.fill_to = Vector2(1, 0) if on_left else Vector2(0, 0)
		var dark := TextureRect.new()
		dark.texture = fill
		dark.size = VIEW
		dark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dark.stretch_mode = TextureRect.STRETCH_SCALE
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dark.position.x = -VIEW.x if on_left else 0.0
		side.add_child(dark)
	side.position.x = -CLOSED_MARGIN if on_left else VIEW.x + CLOSED_MARGIN
	return side


## Slides one side in until its inner edge stands at this x.
func _slide_side(side: Node2D, inner_x: float, dur: float) -> void:
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(side, "position:x", inner_x, _d(dur))
