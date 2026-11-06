class_name ExcaliburPiece
extends SetPiece
## The Sword in the Stone's two answers, on one stage. Nobody cheers on either. Taking it is held,
## the only hold in the game: the blade comes up in steps, everything stops, one shaft of plain light,
## and its name. Leaving it is the same stone in the same light, but you are the thing that moves:
## the world backs away, the trees come in, the hilt goes dull and the words stand on what is left.
## Every word on this stage is read from the event, so none of it can drift from the prose.
##
## Trigger, from anything with a tree, once a run has started (the event scene does this too):
##   await ExcaliburPiece.play_take(parent, choice, true).finished    # true: the camera holds
##   await ExcaliburPiece.play_leave(parent, event_name, choice).finished

## How long the blade takes under a steady hold.
const PULL_SECONDS := 1.8
const PIXEL := 6
const STONE_TOP := 550.0
const STONE_FOOT := 742.0
const STONE_X := 780.0
const SWORD_ROWS := 66
## How many rows of the blade's length show above the stone before it moves: sunk to the hilt.
const SEATED_ROWS := 20
## What a hold-less tap gives, so a tap still does something and tapping alone can finish it.
const TAP_NUDGE := 0.12
const SINK_PER_SECOND := 0.18
## Past this it comes the rest of the way by itself, whether or not you are still holding: it comes
## free surprisingly easily, and letting go at the very top must not leave it hanging there.
const COMES_FREE_AT := 0.8

const CHAMPION_SHEET := "res://assets/sprites/enemies/camelot/man_at_arms/Death.png"
const CHAMPION_W := 184
const CHAMPION_H := 137

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

func _build_stone_and_sword() -> void:
	set_zoom_pivot(Vector2(VIEW.x / 2.0, STONE_TOP))
	world.modulate = Color(0, 0, 0, 1)

	var floor_glow := add_glow(Vector2(960, STONE_FOOT + 4.0), Vector2(1400, 220))
	floor_glow.material.set_shader_parameter("intensity", 0.16)

	_sword = add_figure(SetPiece.pixel_texture(_sword_image(), PIXEL), Vector2.ZERO)
	_sword.position.x = VIEW.x / 2.0 - _sword.texture.get_width() / 2.0
	_seated_y = STONE_TOP - SEATED_ROWS * PIXEL
	_free_y = STONE_TOP - SWORD_ROWS * PIXEL - 12.0
	_seat_sword(_seated_y)
	make_drainable(_sword, 0.8)

	_stone = add_figure(SetPiece.pixel_texture(SetPiece.stone_image(60, 32, 41), PIXEL), Vector2(STONE_X, STONE_TOP))


## Sets the blade's height. What is still inside the stone is simply not drawn.
func _seat_sword(y: float) -> void:
	var full: Vector2 = _sword.texture.get_size()
	_sword.position.y = y
	_sword.region_enabled = true
	_sword.region_rect = Rect2(0, 0, full.x, clampf(STONE_TOP + 24.0 - y, 0.0, full.y))


## The man at the foot of the stone, on one frame of the roster's Man-at-Arms, in shadow.
func _add_champion(frame: int, foot_x: float, tone: float) -> Sprite2D:
	var sheet: Texture2D = load(CHAMPION_SHEET)
	var man := add_figure(SetPiece.strip_frame(sheet, CHAMPION_W, CHAMPION_H, frame), Vector2.ZERO)
	man.flip_h = true
	man.scale = Vector2(3, 3)
	man.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	man.position = Vector2(foot_x, STONE_FOOT - 125.0 * 3.0)
	man.modulate = Color(tone, tone * 0.97, tone * 0.93)
	make_drainable(man, 1.0)
	return man


## A straight sword, hilt up, drawn on the pixel grid so it stands true where a rotated icon would
## not. Colour is in the guard and the grip; the blade is plain steel.
func _sword_image() -> Image:
	var w := 11
	var image := Image.create(w, SWORD_ROWS, false, Image.FORMAT_RGBA8)
	var gold := Color(0.78, 0.60, 0.27)
	var gold_lit := Color(0.96, 0.82, 0.46)
	var gold_dark := Color(0.47, 0.34, 0.14)
	var grip := Color(0.22, 0.13, 0.09)
	var grip_lit := Color(0.33, 0.21, 0.14)
	var steel := [Color(0.90, 0.91, 0.92), Color(0.70, 0.71, 0.74), Color(0.44, 0.45, 0.49),
		Color(0.62, 0.63, 0.66), Color(0.38, 0.39, 0.42)]
	for y in range(0, 3):
		for x in range(3, 8):
			image.set_pixel(x, y, gold_lit if x == 4 and y == 1 else (gold if x < 6 else gold_dark))
	for y in range(3, 13):
		for x in range(4, 7):
			image.set_pixel(x, y, grip_lit if (y % 2 == 0 and x < 6) else grip)
	for x in range(0, w):
		image.set_pixel(x, 13, gold_lit if x < 4 else gold)
		image.set_pixel(x, 14, gold_dark)
	var tip_start := SWORD_ROWS - 7
	for y in range(15, SWORD_ROWS):
		var narrow := 0
		if y >= tip_start:
			narrow = int(ceil(float(y - tip_start + 1) / 3.0))
		for x in range(3 + narrow, 8 - narrow):
			image.set_pixel(x, y, steel[x - 3])
	return image


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
	var man := _add_champion(5, 345.0, 0.6)
	world.move_child(man, _sword.get_index())
	_grit = _make_grit()
	world.add_child(_grit)
	# The shaft falls behind the blade, so the steel stays steel, with a breath of it in front.
	var shaft := add_shaft(960.0, 560.0, Color(1.0, 0.95, 0.84), 0.0, STONE_FOOT + 30.0)
	world.move_child(shaft, _sword.get_index())
	var veil := add_shaft(960.0, 420.0, Color(1.0, 0.95, 0.84), 0.0, STONE_FOOT + 30.0)

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
	_seat_sword(_seated_y - snappedf(climbed, PIXEL))
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
	var man := _add_champion(4, 330.0, 0.42)
	world.move_child(man, _sword.get_index())
	var shaft := add_shaft(960.0, 560.0, Color(1.0, 0.95, 0.84), 0.0, STONE_FOOT + 30.0)
	world.move_child(shaft, _sword.get_index())
	_stone.modulate = Color(1.5, 1.45, 1.32)
	var glint := add_glow(Vector2(960, _seated_y + 84.0), Vector2(170, 170))
	var left_back := _add_trunk(true, 52, 0.7, 0.085)
	var right_back := _add_trunk(false, 58, 0.7, 0.085)
	var left_front := _add_trunk(true, 91, 1.25, 0.04)
	var right_front := _add_trunk(false, 97, 1.25, 0.04)

	_open_stage()
	_apply_zoom(1.06)
	shaft_to(shaft, 0.5, 0.3)
	glow_to(glint, 0.55, 0.3)
	_world_up(0.35)
	drain_to(_sword, 0.0, 0.3)
	var heading := add_line(event_name, TITLE_FACE, 72, BONE, 112.0)
	ink_in(heading, 0.55)
	await beat(1.05)
	skippable = true

	# You are what moves. The world backs away, the trees come in between, the hilt goes dull.
	zoom_to(0.6, 2.7)
	_slide_trunk(left_back, 575.0, true, 2.7)
	_slide_trunk(right_back, 1345.0, false, 2.7)
	_slide_trunk(left_front, 330.0, true, 2.4)
	_slide_trunk(right_front, 1600.0, false, 2.4)
	shaft_to(shaft, 0.0, 1.9)
	glow_to(glint, 0.0, 0.9)
	var dull := create_tween()
	dull.tween_property(_stone, "modulate", Color(0.8, 0.8, 0.8), _d(1.9))
	drain_to(_sword, 1.0, 1.4)
	ink_out(heading, 1.2)
	await beat(1.3)
	# Behind you the beast settles over its stone again: one cut, never seen moving.
	man.texture = SetPiece.strip_frame(load(CHAMPION_SHEET), CHAMPION_W, CHAMPION_H, 5)
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


## A tree between you and the stone: dark bark on the pixel grid, rounded by a little shading, its
## inner edge wandering and its roots flaring toward the clearing, with some of the stone's light
## on that edge. Waits just off stage until it is slid in.
func _add_trunk(on_left: bool, trunk_seed: int, scale_up: float, tone: float) -> Sprite2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = trunk_seed
	var bark := FastNoiseLite.new()
	bark.seed = trunk_seed
	bark.frequency = 0.16
	var w := 46
	var h := int(1240.0 / (PIXEL * scale_up))
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var body_edge := 13
	for y in h:
		if rng.randf() < 0.2:
			body_edge = clampi(body_edge + rng.randi_range(-1, 1), 10, 17)
		var from_foot := h - 1 - y
		var flare := 0
		if from_foot < 34:
			flare = (34 - from_foot) * (34 - from_foot) / 90
		var edge := maxi(0, body_edge - flare)
		for x_px in w:
			var inner: int = (w - 1 - x_px) if on_left else x_px
			if inner < edge:
				continue
			var across := float(inner - edge) / float(w - edge)
			var rounded := 1.0 - absf(across * 2.0 - 1.0)
			var value := tone * (0.55 + 0.45 * rounded) + bark.get_noise_2d(x_px * 2.0, y * 0.5) * tone * 0.3
			if inner == edge:
				value += tone * 0.7
			image.set_pixel(x_px, y, Color(value * 1.02, value, value * 0.94))
	var trunk := add_figure(SetPiece.pixel_texture(image, PIXEL), Vector2.ZERO, fore)
	trunk.scale = Vector2(scale_up, scale_up)
	var width := w * PIXEL * scale_up
	trunk.position = Vector2(-width if on_left else VIEW.x, -60.0)
	return trunk


## Slides a trunk in until its inner side stands at this x.
func _slide_trunk(trunk: Sprite2D, inner_x: float, on_left: bool, dur: float) -> void:
	var width: float = trunk.texture.get_width() * trunk.scale.x
	var t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(trunk, "position:x", inner_x - width if on_left else inner_x, _d(dur))
