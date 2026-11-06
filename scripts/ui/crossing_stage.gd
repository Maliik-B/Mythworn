class_name CrossingStage
extends MapFlourish
## The crossing, staged for the clip. Nothing in the game calls this and it changes no map data: the
## real node is built elsewhere and stays out of the clip. At one map node the picture stops in a plain
## patch of light, white snow is driven out of it across the field, the ground goes white around it,
## then one hard cut to a cold frame with your hand of cards on screen. Nothing here carries a word:
## it is unnamed.
##
## The light has no glow, swirl, rim or tear. The snow is flat white, and shrinks to nothing rather
## than fading, because white at part alpha over a dark field reads as grey. Camelot's palette around
## it is left alone: no dimming and no cold tint on this side of the cut. No creatures on the far one.
##
## Trigger, on a map scene open for at least two frames:
##   var crossing := CrossingStage.play(get_tree().current_scene)
##   await crossing.stepped  # the frame of the hard cut
##   await crossing.held     # about 3 s in; the cold frame stays up until crossing.close()

signal stepped
signal held

# The far side's layers, back to front, on the 384x216 grid. The real pack's five layers go in this
# list and nothing else changes. This one is a stand-in cut from the pack's page cover.
const COLD_LAYERS: Array[String] = ["res://assets/sprites/realms/cold_edge/snowy_mountains_standin.png"]
const COLD_PIXEL := 5
const SUN_AT := Vector2(915, 105)  # the sun like the moon, flat, over the first layer
const SUN_RADIUS := 13
const SUN_COLOR := Color(0.84, 0.84, 0.81)

const STEP_AT := 1.9
const HELD_AT := 3.0
const LIGHT_IN := 0.25
const GROUND_LEN := 1.4

# Where the node lands on the frame: low in the crop, so the white meets the field by the castle.
const NODE_ON_FRAME := Vector2(760, 880)
const FROM_ZOOM := 1.45
const TO_ZOOM := 1.62
const LIGHT_SIZE := Vector2(180, 236)  # canvas units
const LIGHT_SINK := 18.0  # how far its foot goes down into the white
const GROUND_SIZE := Vector2(440, 96)
const GROUND_DOWNWIND := 46.0

# Driven snow: one wind on both sides of the cut, so the same weather carries across it.
const WIND := Vector2(1.0, 0.72)
const FLAKE_PX := 4
const NEAR_AMOUNT := 230
const NEAR_LIFETIME := 1.7
const NEAR_SPEED := Vector2(170, 300)  # canvas units a second
const NEAR_SCALE := Vector2(1.2, 2.4)
const FAR_AMOUNT := 300
const FAR_LIFETIME := 2.0
const FAR_SPEED := Vector2(280, 480)  # frame pixels a second, as the near snow lands at TO_ZOOM
const FAR_SCALE := Vector2(1.6, 3.2)

const HAND_SIZE := 5
const HAND_TOP := 770.0  # the combat hand's row
const HAND_LEFT := 440.0
const HAND_STEP := 210.0

const LIGHT_SHADER := preload("res://assets/shaders/plain_light.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/snow_patch.gdshader")

## Where the node stands on the frame, for a drawn cursor to step onto.
var target_on_frame := NODE_ON_FRAME

var _scene: Node
var _node_btn: Button
var _far: SetPiece
var _stepped := false


## Starts the shot on an open map scene. `node_id` -1 picks an ordinary node on floors 8 to 10.
static func play(map_scene: Node, node_id := -1) -> CrossingStage:
	var stage := CrossingStage.new()
	map_scene.add_child(stage)
	stage._run(map_scene, node_id)
	return stage


## The hard cut, now. Runs by itself at STEP_AT; a director may call it to land it on its own frame.
func step_through() -> void:
	if _stepped:
		return
	_stepped = true
	_far.visible = true
	_far.zoom_to(1.035, HELD_AT - STEP_AT + 0.5)
	stepped.emit()


## Takes the whole stage away and hands the map back as it was.
func close() -> void:
	if is_instance_valid(_far):
		_far.queue_free()
	finish_now()


func _run(map_scene: Node, node_id: int) -> void:
	_scene = map_scene
	setup(_scene.map_canvas)
	_scene._end_flourish()
	_scene._pledge_anim_active = true  # holds the map; the node stays in its data as it was
	finished.connect(_scene._finish_pledge_changes)

	var map: MapData = RunManager.current_map
	var node: MapNode = map.get_node(node_id) if node_id >= 0 else _pick_node(map)
	_node_btn = _scene.node_buttons[node.id]
	_node_btn.modulate.a = 0.0  # no glyph to name it: the light stands where the node did
	var at: Vector2 = _scene._get_node_center(node)

	_begin(Rect2(NODE_ON_FRAME - Vector2.ONE, Vector2(2, 2)))
	_camera_step(1.0, _focus, _zoom, at, FROM_ZOOM)
	_tween().tween_method(_camera_step.bind(at, FROM_ZOOM, at, TO_ZOOM), 0.0, 1.0, STEP_AT)

	_clear_nodes_around(at)
	_add_ground(at)
	_add_light(at)
	_add_snow(at)
	_far = _build_far_side()

	var timeline := _tween_at(STEP_AT)
	timeline.tween_callback(step_through)
	timeline.tween_interval(HELD_AT - STEP_AT)
	timeline.tween_callback(func() -> void: held.emit())


## An ordinary node on floors 8 to 10, nearest the middle of the map. Nothing a quest or a scripted
## event sits on, and no landmark.
func _pick_node(map: MapData) -> MapNode:
	var best: MapNode = null
	var best_off := INF
	var middle := (MapGenerator.MAP_WIDTH - 1) / 2.0
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.floor_num < 8 or n.floor_num > 10:
			continue
		if n.quest_giver_id != &"" or n.quest_payoff_id != &"" or n.scripted_event_id != &"":
			continue
		if n.look().get("landmark", false):
			continue
		var off := absf(n.column + n.x_jitter - middle)
		if off < best_off:
			best_off = off
			best = n
	return best


# ============================================================
# THE NEAR SIDE, ON THE MAP'S OWN CANVAS
# ============================================================

## Hides, for the shot, any node the light or the white would sit on: a dark disc left standing in a
## plain patch reads as an eye. Their data is untouched, and close() puts their looks back.
func _clear_nodes_around(at: Vector2) -> void:
	var map: MapData = RunManager.current_map
	var room := Vector2(_scene.NODE_SIZE, _scene.NODE_SIZE)
	var light_box := Rect2(at - Vector2(LIGHT_SIZE.x / 2.0, LIGHT_SIZE.y - LIGHT_SINK), LIGHT_SIZE).grow(room.x / 2.0)
	var ground_box := Rect2(at + Vector2(GROUND_DOWNWIND, 0.0) - GROUND_SIZE / 2.0, GROUND_SIZE).grow(room.x / 2.0)
	for id in map.nodes:
		var center: Vector2 = _scene._get_node_center(map.nodes[id])
		if light_box.has_point(center) or ground_box.has_point(center):
			_scene.node_buttons[id].modulate.a = 0.0


func _add_ground(at: Vector2) -> void:
	var ground := ColorRect.new()
	ground.size = GROUND_SIZE
	ground.position = at + Vector2(GROUND_DOWNWIND, 0.0) - GROUND_SIZE / 2.0
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("rect_size", GROUND_SIZE)
	mat.set_shader_parameter("cell", 3.0)
	mat.set_shader_parameter("grow", 0.1)
	ground.material = mat
	_canvas.add_child(ground)
	_props.append(ground)
	# In over the roads and under the nodes, so a road still arrives at something.
	for i in _canvas.get_child_count():
		if _canvas.get_child(i) is Button:
			_canvas.move_child(ground, i)
			break
	_tween().tween_property(mat, "shader_parameter/grow", 1.0, GROUND_LEN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The patch stands on the ground with its foot in the white, so nothing shows where they meet.
func _add_light(at: Vector2) -> void:
	var light := ColorRect.new()
	light.size = LIGHT_SIZE
	light.position = at - Vector2(LIGHT_SIZE.x / 2.0, LIGHT_SIZE.y - LIGHT_SINK)
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = LIGHT_SHADER
	mat.set_shader_parameter("fade", 0.0)
	light.material = mat
	_canvas.add_child(light)
	_props.append(light)
	_tween().tween_property(mat, "shader_parameter/fade", 1.0, LIGHT_IN)


func _add_snow(at: Vector2) -> void:
	var snow := _make_snow(NEAR_AMOUNT, NEAR_LIFETIME, NEAR_SPEED, NEAR_SCALE)
	snow.position = at - Vector2(0.0, LIGHT_SIZE.y / 2.0 - LIGHT_SINK)
	snow.emission_rect_extents = LIGHT_SIZE * Vector2(0.36, 0.42)
	_canvas.add_child(snow)
	_props.append(snow)


## Flat white squares, driven. A flake grows in and shrinks away; its colour never changes.
func _make_snow(amount: int, lifetime: float, speed: Vector2, flake_scale: Vector2) -> CPUParticles2D:
	var snow := CPUParticles2D.new()
	snow.amount = amount
	snow.lifetime = lifetime
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.direction = WIND.normalized()
	snow.spread = 13.0
	snow.gravity = Vector2.ZERO
	snow.initial_velocity_min = speed.x
	snow.initial_velocity_max = speed.y
	snow.angle_min = 0.0
	snow.angle_max = 90.0
	snow.scale_amount_min = flake_scale.x
	snow.scale_amount_max = flake_scale.y
	var ramp := Curve.new()
	ramp.add_point(Vector2(0.0, 0.0))
	ramp.add_point(Vector2(0.05, 1.0))
	ramp.add_point(Vector2(0.92, 1.0))
	ramp.add_point(Vector2(1.0, 0.0))
	snow.scale_amount_curve = ramp
	snow.color = Color.WHITE
	var flake := Image.create(FLAKE_PX, FLAKE_PX, false, Image.FORMAT_RGBA8)
	flake.fill(Color.WHITE)
	snow.texture = ImageTexture.create_from_image(flake)
	snow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return snow


# ============================================================
# THE FAR SIDE
# ============================================================

## Built hidden and whole, so the cut is one frame with nothing still arriving.
func _build_far_side() -> SetPiece:
	var far := SetPiece.new()
	far.visible = false
	_scene.add_child(far)
	for i in COLD_LAYERS.size():
		var layer: Texture2D = load(COLD_LAYERS[i])
		far.add_figure(SetPiece.pixel_texture(layer.get_image(), COLD_PIXEL), Vector2.ZERO)
		if i == 0:
			far.add_figure(SetPiece.pixel_texture(_sun_image(), COLD_PIXEL), SUN_AT)
	var snow := _make_snow(FAR_AMOUNT, FAR_LIFETIME, FAR_SPEED, FAR_SCALE)
	snow.position = Vector2(760, 300)
	snow.emission_rect_extents = Vector2(1300, 650)
	snow.preprocess = FAR_LIFETIME  # already falling on the first frame
	far.fore.add_child(snow)
	_add_hand(far)
	return far


func _sun_image() -> Image:
	var size := SUN_RADIUS * 2 + 1
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			if Vector2(x - SUN_RADIUS, y - SUN_RADIUS).length_squared() <= SUN_RADIUS * SUN_RADIUS:
				image.set_pixel(x, y, SUN_COLOR)
	return image


## Your hand, on the combat row, in the run's own cards. Its words are the cards' own.
func _add_hand(far: SetPiece) -> void:
	var chosen: Array[CardData] = []
	var seen := {}
	for card in RunManager.current_deck:
		if not seen.has(card.card_name) and chosen.size() < HAND_SIZE:
			seen[card.card_name] = true
			chosen.append(card)
	for card in RunManager.current_deck:
		if chosen.size() < HAND_SIZE:
			chosen.append(card)
	for i in chosen.size():
		var panel := CardFace.build(chosen[i], null, null)
		panel.position = Vector2(HAND_LEFT + HAND_STEP * i, HAND_TOP)
		panel.size = CardFace.SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		far.words.add_child(panel)
