class_name CombatStage
extends Control
## The ground a fight stands on: a wall, the realm's skyline washed flat against it, and the ground
## with a line where they meet. Bodies stand in front of the line. Nothing here takes input or any
## part in layout. Colours come from StageSkin; nothing here knows which look is on.

const HEIGHT := 698.0  # the stage's bottom edge, just above the player bar
const GROUND_LINE_Y := 532.0
const ART_PX := 4  # the world's grid: one sprite pixel at a regular's scale
const RULING_STEP := 36
const RULING_MARGIN := 56

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
	_add_rect(Vector2(0, GROUND_LINE_Y), Vector2(1920, HEIGHT - GROUND_LINE_Y), StageSkin.c("ground"))
	_add_rect(Vector2(0, GROUND_LINE_Y), Vector2(1920, ART_PX), StageSkin.c("ground_line"))


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
