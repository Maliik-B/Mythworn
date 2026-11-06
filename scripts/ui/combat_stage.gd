class_name CombatStage
extends Control
## The ground a fight stands on: a wall, the realm's skyline washed flat against it, and the ground
## with a line where they meet. Bodies stand in front of the line. Nothing here takes input or any
## part in layout. Colours come from StageSkin; nothing here knows which look is on.
##
## On the page, the wall is a leaf of the book, and it is the book's wear that shows: its lower edge
## gone in places and one corner missing. That wear is only absence, the same in every realm and
## still for the whole fight. A realm's own loss belongs on its ground and its bodies, never here,
## and nothing is ever written on this page or taken off it.

const HEIGHT := 706.0  # the stage's bottom edge, just above the player bar's words
const GROUND_LINE_Y := 532.0
const ART_PX := 4  # the world's grid: one sprite pixel at a regular's scale
const RULING_STEP := 36
const RULING_MARGIN := 56
# Where the page's lower edge is gone: [from x, to x, height], on the art grid. Fixed, so it is the
# same page in every realm and every fight.
const WORN_EDGE := [[48, 120, 8], [168, 184, 4], [200, 264, 8], [400, 416, 4], [560, 592, 12], [872, 884, 4],
	[948, 960, 8], [1008, 1048, 4], [1080, 1104, 8], [1144, 1224, 4], [1288, 1300, 8], [1372, 1388, 12],
	[1552, 1648, 4], [1696, 1796, 4], [1820, 1880, 4]]
# The missing corner, top right, in steps: [from x, y, height].
const WORN_CORNER := [[1864, 0, 4], [1872, 4, 4], [1880, 8, 4], [1888, 12, 4], [1896, 16, 8], [1904, 24, 8], [1912, 32, 12]]

const MOOD_LEAN := 0.09
const MOOD_POLE := 0.2
const MOOD_FLARE := 0.14
const GROUND_FLARE := 1.3  # how far past its new colour the ground runs before it settles
const WEATHER_AT_LEAN := 16
const WEATHER_AT_POLE := 46

var _ground: ColorRect = null
var _ground_tween: Tween = null
var _mood: ColorRect = null
var _mood_tween: Tween = null
var _embers: CPUParticles2D = null
var _frost: CPUParticles2D = null
var _dim: ColorRect = null
var _dim_tween: Tween = null

# A realm's skyline, as flat washes on the art grid. A realm with none here has a bare wall.
const WASHES := {
	&"camelot": ["res://assets/sprites/realms/horizon_camelot_far.png", "res://assets/sprites/realms/horizon_camelot_near.png"],
}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT


func _ready() -> void:
	_add_rect(Vector2.ZERO, Vector2(1920, HEIGHT), StageSkin.c("wall"))
	var ruled := Control.new()
	ruled.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ruled.set_anchors_preset(Control.PRESET_FULL_RECT)
	ruled.draw.connect(_draw_ruling.bind(ruled))
	add_child(ruled)
	var washes: Array = WASHES.get(RunManager.current_realm_id, [])
	if washes.size() == 2:
		_add_wash(washes[0], StageSkin.c("wash_far"))
		_add_wash(washes[1], StageSkin.c("wash_near"))
	_ground = _add_rect(Vector2(0, GROUND_LINE_Y), Vector2(1920, HEIGHT - GROUND_LINE_Y), StageSkin.c("ground"))
	_add_rect(Vector2(0, GROUND_LINE_Y), Vector2(1920, ART_PX), StageSkin.c("ground_line"))
	_mood = _add_rect(Vector2.ZERO, Vector2(1920, HEIGHT), Color(0, 0, 0, 0))
	_embers = _make_weather(StageSkin.c("ember"), GROUND_LINE_Y, Vector2(0.1, -1.0), 60.0)
	_frost = _make_weather(StageSkin.c("frost"), 0.0, Vector2(-0.15, 1.0), 42.0)
	var wear := Control.new()
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.set_anchors_preset(Control.PRESET_FULL_RECT)
	wear.draw.connect(_draw_wear.bind(wear))
	add_child(wear)


## The stage takes on the Passion band you stand in: warm above Steady, cold below it, more so at a
## pole, with embers or frost where the look has any. The page has none, since a speck on it reads
## as a stain. It stays behind the bodies, so a body keeps its own colour on it. A change flares past
## its mark, then settles. On the page only the ground band takes it (see StageSkin); the leaf itself
## keeps its hue and value, and the skyline washed on it.
func set_mood(tier: int, instant := false) -> void:
	if StageSkin.passion_on_keeper():
		_set_ground_mood(tier, instant)
		return
	var strength := 0.0
	var gain: float = StageSkin.MOOD_GAIN[StageSkin.active]
	match tier:
		PassionState.Tier.BLAZING, PassionState.Tier.HOLLOW:
			strength = MOOD_POLE * gain
		PassionState.Tier.INSPIRED, PassionState.Tier.WAVERING:
			strength = MOOD_LEAN * gain
	var warm := tier == PassionState.Tier.BLAZING or tier == PassionState.Tier.INSPIRED
	var cold := tier == PassionState.Tier.HOLLOW or tier == PassionState.Tier.WAVERING
	_set_weather(_embers, warm, strength)
	_set_weather(_frost, cold, strength)
	var color: Color = PassionInfographic._tier_color(tier)
	if _mood_tween:
		_mood_tween.kill()
	_mood.color = Color(color.r, color.g, color.b, _mood.color.a)
	if instant:
		_mood.color.a = strength
		return
	_mood_tween = create_tween()
	_mood_tween.tween_property(_mood, "color:a", strength + MOOD_FLARE * StageSkin.MOOD_GAIN[StageSkin.active], 0.18).set_trans(Tween.TRANS_SINE)
	_mood_tween.tween_property(_mood, "color:a", strength, 0.9).set_trans(Tween.TRANS_SINE)


func _set_ground_mood(tier: int, instant: bool) -> void:
	var target: Color = StageSkin.keeper_tint(tier)["ground"]
	if _ground_tween:
		_ground_tween.kill()
	if instant:
		_ground.color = target
		return
	_ground_tween = create_tween()
	_ground_tween.tween_property(_ground, "color", _ground.color.lerp(target, GROUND_FLARE), 0.18).set_trans(Tween.TRANS_SINE)
	_ground_tween.tween_property(_ground, "color", target, 0.9).set_trans(Tween.TRANS_SINE)


func _set_weather(weather: CPUParticles2D, on: bool, strength: float) -> void:
	if not on or strength <= 0.0 or weather.color_ramp.colors[1].a <= 0.0:
		weather.emitting = false
		return
	weather.amount = WEATHER_AT_POLE if strength >= MOOD_POLE * StageSkin.MOOD_GAIN[StageSkin.active] else WEATHER_AT_LEAN
	weather.emitting = true


func _make_weather(color: Color, y: float, direction: Vector2, speed: float) -> CPUParticles2D:
	var weather := CPUParticles2D.new()
	weather.emitting = false
	weather.amount = WEATHER_AT_LEAN
	weather.lifetime = 5.0
	weather.position = Vector2(960, y)
	weather.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	weather.emission_rect_extents = Vector2(960, 12)
	weather.direction = direction
	weather.spread = 14.0
	weather.gravity = Vector2.ZERO
	weather.initial_velocity_min = speed * 0.6
	weather.initial_velocity_max = speed * 1.4
	weather.scale_amount_min = float(ART_PX) * 0.75
	weather.scale_amount_max = float(ART_PX)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(color, 0.0), color, color, Color(color, 0.0)])
	weather.color_ramp = fade
	add_child(weather)
	return weather


## Darkens the ground around the bodies for this long, then lets it back. They stand in front of it.
func dim(seconds: float) -> void:
	if not is_instance_valid(_dim):
		_dim = _add_rect(Vector2.ZERO, Vector2(1920, HEIGHT), StageSkin.c("dim"))
	if _dim_tween:
		_dim_tween.kill()
	_dim.modulate.a = 0.0
	_dim_tween = create_tween()
	_dim_tween.tween_property(_dim, "modulate:a", 1.0, 0.25)
	_dim_tween.tween_interval(maxf(0.0, seconds - 0.25))
	_dim_tween.tween_property(_dim, "modulate:a", 0.0, 0.5)


func _add_rect(pos: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.position = pos
	rect.size = rect_size
	rect.color = color
	add_child(rect)
	return rect


func _add_wash(path: String, color: Color) -> void:
	var wash := TextureRect.new()
	wash.texture = load(path)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wash.modulate = color
	wash.size = wash.texture.get_size() * ART_PX
	wash.position = Vector2(0, GROUND_LINE_Y + ART_PX - wash.size.y)
	add_child(wash)


## The page's wear, in the desk's colour. Fully transparent in a look with no page.
func _draw_wear(canvas: Control) -> void:
	var color := StageSkin.c("wear")
	if color.a <= 0.0:
		return
	for piece in WORN_EDGE:
		canvas.draw_rect(Rect2(piece[0], HEIGHT - piece[2], piece[1] - piece[0], piece[2]), color)
	for step in WORN_CORNER:
		canvas.draw_rect(Rect2(step[0], step[1], 1920 - step[0], step[2]), color)


## Lines for words that are not there. Fully transparent in a look with no ruling.
func _draw_ruling(canvas: Control) -> void:
	var color := StageSkin.c("ruling")
	if color.a <= 0.0:
		return
	var y := RULING_STEP
	while y < GROUND_LINE_Y:
		canvas.draw_rect(Rect2(RULING_MARGIN, y, 1920 - 2 * RULING_MARGIN, ART_PX), color)
		y += RULING_STEP
	canvas.draw_rect(Rect2(RULING_MARGIN, 0, ART_PX, GROUND_LINE_Y), color)
	canvas.draw_rect(Rect2(1920 - RULING_MARGIN - ART_PX, 0, ART_PX, GROUND_LINE_Y), color)
