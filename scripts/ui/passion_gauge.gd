class_name PassionGauge
extends Control
## Passion as a place you stand: a tall spine at the stage's left edge, zero at the middle, warm above
## and cold below, with a needle on it and the name of the band you are in. Moving inside a band only
## moves the needle. Crossing into another stamps the new name large, and it settles small beside the
## needle. Shows what RunManager holds and decides nothing. Takes no input.

const RECT := Rect2(44, 84, 20, 596)
const NAME_X := 56.0  # from the spine's left edge to the name's
const NAME_SIZE := 56
const NAME_REST_SCALE := 0.5  # Steady's, and the smallest
const NAME_LEAN_SCALE := 0.68  # Inspired and Wavering
const NAME_POLE_SCALE := 0.9  # Blazing and Hollow rest large, so a pole reads from across the room
const NEEDLE_TIME := 0.32
const STAMP_FROM := 1.45
const STAMP_TIME := 0.14
const STAMP_HOLD := 0.95
const DIM_BAND := 0.34

var _needle: Polygon2D
var _name: Label
var _name_tween: Tween = null
var _needle_tween: Tween = null
var _tier: int = PassionState.Tier.STEADY


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = RECT.position
	size = RECT.size
	_needle = Polygon2D.new()
	_needle.polygon = PackedVector2Array([
		Vector2(-6, -3), Vector2(RECT.size.x + 6, -3), Vector2(RECT.size.x + 6, -10),
		Vector2(RECT.size.x + 26, 0), Vector2(RECT.size.x + 6, 10), Vector2(RECT.size.x + 6, 3), Vector2(-6, 3)])
	_needle.color = StageSkin.c("ink")
	add_child(_needle)
	_name = Label.new()
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_font_override("font", load(StageSkin.NAME_FONT_PATH))
	_name.add_theme_font_size_override("font_size", NAME_SIZE)
	_name.add_theme_color_override("font_outline_color", StageSkin.c("number_outline"))
	_name.add_theme_constant_override("outline_size", 10)
	add_child(_name)


## Puts the needle and name where Passion stands, with no motion: the start of a fight.
func show_now() -> void:
	_tier = RunManager.get_passion_tier()
	_needle.position.y = _y_of(RunManager.passion.current_value)
	_set_name()
	_name.scale = Vector2.ONE * _rest_scale()
	_place_name(_needle.position.y)
	queue_redraw()


## The needle goes to a new value and overshoots a little. Crossing a band stamps its name.
func move_to(value: int) -> void:
	var y := _y_of(value)
	if _needle_tween:
		_needle_tween.kill()
	_needle_tween = create_tween().set_parallel(true)
	_needle_tween.tween_property(_needle, "position:y", y, NEEDLE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_needle_tween.tween_property(_name, "position:y", _name_y(y), NEEDLE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tier: int = RunManager.get_passion_tier_for_value(value)
	if tier != _tier:
		_tier = tier
		_stamp()
		queue_redraw()


func _stamp() -> void:
	_set_name()
	if _name_tween:
		_name_tween.kill()
	_name.scale = Vector2.ONE * STAMP_FROM
	_name.modulate.a = 0.0
	_name_tween = create_tween()
	_name_tween.set_parallel(true)
	_name_tween.tween_property(_name, "modulate:a", 1.0, 0.05)
	_name_tween.tween_property(_name, "scale", Vector2.ONE, STAMP_TIME) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_name_tween.chain().tween_interval(STAMP_HOLD)
	_name_tween.chain().tween_property(_name, "scale", Vector2.ONE * _rest_scale(), 0.25) \
		.set_trans(Tween.TRANS_SINE)


## How large the name rests at in this band: the poles largest, Steady smallest.
func _rest_scale() -> float:
	match _tier:
		PassionState.Tier.BLAZING, PassionState.Tier.HOLLOW:
			return NAME_POLE_SCALE
		PassionState.Tier.INSPIRED, PassionState.Tier.WAVERING:
			return NAME_LEAN_SCALE
	return NAME_REST_SCALE


func _set_name() -> void:
	_name.text = PassionState.tier_name(_tier)
	var color: Color = StageSkin.gauge_color(_tier)
	_name.add_theme_color_override("font_color", color.darkened(0.3) if StageSkin.is_page() else color)
	_name.reset_size()
	_name.pivot_offset = Vector2(0.0, _name.size.y / 2.0)
	_name.position.x = NAME_X


func _place_name(needle_y: float) -> void:
	_name.position.y = _name_y(needle_y)


## The name's top for a needle at this y, kept on the spine's own height.
func _name_y(needle_y: float) -> float:
	var half := _name.size.y / 2.0
	return clampf(needle_y - half, -half * NAME_REST_SCALE, RECT.size.y - half)


func _y_of(value: int) -> float:
	var low: float = RunManager.passion.min_value
	var high: float = RunManager.passion.max_value
	return RECT.size.y * (1.0 - (float(value) - low) / (high - low))


## The bands, warm above and cold below, the one you stand in lit.
func _draw() -> void:
	if not RunManager.passion or not RunManager.current_character:
		return
	var t: Array = RunManager.current_character.passion_thresholds
	var low: int = RunManager.passion.min_value
	var high: int = RunManager.passion.max_value
	var edges: Array = [high, t[0], t[1], t[2], t[3], low]
	var tiers: Array = [PassionState.Tier.BLAZING, PassionState.Tier.INSPIRED, PassionState.Tier.STEADY,
		PassionState.Tier.WAVERING, PassionState.Tier.HOLLOW]
	for i in tiers.size():
		var top := _y_of(edges[i])
		var bottom := _y_of(edges[i + 1])
		var color: Color = StageSkin.gauge_color(tiers[i])
		if tiers[i] != _tier:
			color = color.lerp(StageSkin.c("wall"), 1.0 - DIM_BAND)
		draw_rect(Rect2(0, top, RECT.size.x, bottom - top - 2.0), color)
