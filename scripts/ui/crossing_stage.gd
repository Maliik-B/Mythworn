class_name CrossingStage
extends MapFlourish
## The crossing, staged for the clip. Nothing in the game calls this and it changes no map data: the
## real node is built elsewhere and stays out of the clip. At one map node a slit of plain light opens,
## white snow is driven out of it along the field, the ground takes a low drift of white, then one hard
## cut to a cold frame with your hand of cards on screen. Nothing here carries a word: it is unnamed.
## Light picks the look of the light, to choose between by eye.
##
## The light has no glow, swirl, rim or tear. The snow is flat white, and shrinks to nothing rather
## than fading, because white at part alpha over a dark field reads as grey. It flies more than it
## falls, sparse and far, because snow pouring down from one point onto a round white reads as a spill.
## Camelot's palette around it is left alone: no dimming and no cold tint on this side of the cut. No
## creatures on the far one.
##
## Trigger, on a map scene open for at least two frames:
##   var crossing := CrossingStage.play(get_tree().current_scene)
##   await crossing.stepped  # the frame of the hard cut
##   await crossing.held     # about 3 s in; the cold frame stays up until crossing.close()

signal stepped
signal held

enum Light {
	SLIT,  # a slit a person could only just step through, opening slowly
	EATEN,  # a patch with its edge eaten back, thin enough for the map to show through
	NONE,  # no shape: only the snow, the white, and the map's own ink fading where it falls
}
const DEFAULT_LIGHT := Light.SLIT

# The far side's layers, back to front, on the 384x216 grid: Admurin's Snowy Mountains, in its own
# palette. [file, rows lifted], so the trees stand clear of the hand's row. Flat snow under the lot.
const COLD_DIR := "res://assets/sprites/realms/cold_edge/"
const COLD_LAYERS: Array = [
	["snowy_sky.png", 0],
	["snowy_mountains.png", 10],
	["snowy_pines_far.png", 20],
	["snowy_pines_near.png", 30],
	["snowy_ground.png", 30],
]
const COLD_GROUND_FROM := 178  # the row the flat snow starts on, under the ground layer's own strip
const COLD_GROUND := Color(0.93, 0.94, 0.94)
const COLD_PIXEL := 5
const SUN_AT := Vector2(915, 105)  # the sun like the moon, flat, over the first layer
const SUN_RADIUS := 13
const SUN_COLOR := Color(0.84, 0.84, 0.81)

const STEP_AT := 1.9
const HELD_AT := 3.0
const LIGHT_IN := 0.15
const GROUND_LEN := 1.5

# Where the node lands on the frame: low in the crop, so the white meets the field by the castle.
const NODE_ON_FRAME := Vector2(760, 880)
const FROM_ZOOM := 1.45
const TO_ZOOM := 1.62
const SLIT_SIZE := Vector2(26, 340)  # canvas units
const SLIT_FROM := 0.06  # the share of its width it starts at
const EATEN_SIZE := Vector2(130, 270)
const NONE_SIZE := Vector2(30, 240)  # no light here: only where the snow comes from
const LIGHT_SINK := 6.0  # how far its foot goes down into the white
const GROUND_SIZE := Vector2(520, 60)
const GROUND_UPWIND := 44.0  # how much of it lies upwind of the foot

# Where the ink fades, for Light.NONE.
const INK_REACH := 300.0
const INK_STOPS := 8

# Driven snow: one wind on both sides of the cut, so the same weather carries across it.
const WIND := Vector2(1.0, 0.38)
const WIND_SPREAD := 6.0
const FLAKE_PX := 4
const NEAR_AMOUNT := 130
const NEAR_LIFETIME := 2.4
const NEAR_SPEED := Vector2(120, 210)  # canvas units a second
const NEAR_SCALE := Vector2(1.0, 2.0)
const FAR_AMOUNT := 240
const FAR_LIFETIME := 2.4
const FAR_SPEED := Vector2(195, 340)  # frame pixels a second, as the near snow lands at TO_ZOOM
const FAR_SCALE := Vector2(1.6, 3.2)

const HAND_SIZE := 5
const HAND_TOP := 770.0  # the combat hand's row
const HAND_LEFT := 440.0
const HAND_STEP := 210.0

const SLIT_SHADER := preload("res://assets/shaders/plain_light.gdshader")
const EATEN_SHADER := preload("res://assets/shaders/eaten_light.gdshader")
const GROUND_SHADER := preload("res://assets/shaders/snow_patch.gdshader")

## Where the node stands on the frame, for a drawn cursor to step onto.
var target_on_frame := NODE_ON_FRAME

var _scene: Node
var _node_btn: Button
var _far: SetPiece
var _stepped := false
var _light := DEFAULT_LIGHT
var _inked_roads: Array[Line2D] = []
var _inked_nodes: Array[Button] = []


## Starts the shot on an open map scene. `node_id` -1 picks an ordinary node on floors 8 to 10.
static func play(map_scene: Node, node_id := -1, light := DEFAULT_LIGHT) -> CrossingStage:
	var stage := CrossingStage.new()
	stage._light = light
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
	for road in _inked_roads:
		road.gradient = null
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

	_add_ground(at)
	match _light:
		Light.SLIT:
			_clear_nodes_around(at, SLIT_SIZE)
			_add_slit(at)
		Light.EATEN:
			_clear_nodes_around(at, EATEN_SIZE)
			_add_eaten_light(at)
		Light.NONE:
			_clear_nodes_around(at, NONE_SIZE)
			_fade_the_ink(at)
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

func _light_box(at: Vector2, light_size: Vector2) -> Rect2:
	return Rect2(at - Vector2(light_size.x / 2.0, light_size.y - LIGHT_SINK), light_size)


func _ground_box(at: Vector2) -> Rect2:
	return Rect2(at - Vector2(GROUND_UPWIND, GROUND_SIZE.y / 2.0), GROUND_SIZE)


## Hides, for the shot, any node the light or the white would sit on: a dark disc left standing in
## plain light reads as an eye. Their data is untouched, and close() puts their looks back.
func _clear_nodes_around(at: Vector2, light_size: Vector2) -> void:
	var map: MapData = RunManager.current_map
	var room: float = _scene.NODE_SIZE / 2.0
	var light_box := _light_box(at, light_size).grow(room)
	var ground_box := _ground_box(at).grow(room)
	for id in map.nodes:
		var center: Vector2 = _scene._get_node_center(map.nodes[id])
		if light_box.has_point(center) or ground_box.has_point(center):
			_scene.node_buttons[id].modulate.a = 0.0


func _add_ground(at: Vector2) -> void:
	var ground := ColorRect.new()
	var box := _ground_box(at)
	ground.position = box.position
	ground.size = box.size
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("rect_size", GROUND_SIZE)
	mat.set_shader_parameter("grow", 0.14)
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


func _add_light_rect(at: Vector2, light_size: Vector2, shader: Shader) -> ShaderMaterial:
	var light := ColorRect.new()
	var box := _light_box(at, light_size)
	light.position = box.position
	light.size = box.size
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("rect_size", light_size)
	light.material = mat
	_canvas.add_child(light)
	_props.append(light)
	_tween().tween_property(mat, "shader_parameter/fade", 1.0, LIGHT_IN)
	return mat


## Opens slowly from a line, and is still opening at the cut.
func _add_slit(at: Vector2) -> void:
	var mat := _add_light_rect(at, SLIT_SIZE, SLIT_SHADER)
	mat.set_shader_parameter("open", SLIT_FROM)
	_tween().tween_property(mat, "shader_parameter/open", 1.0, STEP_AT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _add_eaten_light(at: Vector2) -> void:
	_add_light_rect(at, EATEN_SIZE, EATEN_SHADER)


## No light at all: the map's roads and nodes lose their ink outward from where the snow begins.
func _fade_the_ink(at: Vector2) -> void:
	var map: MapData = RunManager.current_map
	for child in _canvas.get_children():
		if child is Line2D and child.points.size() == 2:
			var nearest := Geometry2D.get_closest_point_to_segment(at, child.points[0], child.points[1])
			if nearest.distance_to(at) < INK_REACH:
				child.gradient = Gradient.new()
				_inked_roads.append(child)
	for id in map.nodes:
		var btn: Button = _scene.node_buttons[id]
		if btn.modulate.a > 0.0 and _scene._get_node_center(map.nodes[id]).distance_to(at) < INK_REACH:
			_inked_nodes.append(btn)
	_set_ink_reach(1.0, at)
	_tween().tween_method(_set_ink_reach.bind(at), 1.0, INK_REACH, GROUND_LEN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_ink_reach(reach: float, at: Vector2) -> void:
	for road in _inked_roads:
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		var col: Color = road.default_color
		for i in INK_STOPS:
			var along := float(i) / (INK_STOPS - 1)
			var point: Vector2 = road.points[0].lerp(road.points[1], along)
			offsets.append(along)
			colors.append(Color(col.r, col.g, col.b, col.a * smoothstep(reach * 0.55, reach, point.distance_to(at))))
		road.gradient.offsets = offsets
		road.gradient.colors = colors
	for btn in _inked_nodes:
		var center: Vector2 = btn.position + btn.size / 2.0
		btn.modulate.a = smoothstep(reach * 0.55, reach, center.distance_to(at))


func _add_snow(at: Vector2) -> void:
	var source: Vector2 = {Light.SLIT: SLIT_SIZE, Light.EATEN: EATEN_SIZE, Light.NONE: NONE_SIZE}[_light]
	var snow := _make_snow(NEAR_AMOUNT, NEAR_LIFETIME, NEAR_SPEED, NEAR_SCALE)
	snow.position = at - Vector2(0.0, source.y / 2.0 - LIGHT_SINK)
	snow.emission_rect_extents = source * Vector2(0.36, 0.45)
	_canvas.add_child(snow)
	_props.append(snow)


## Flat white squares, driven. A flake grows in and shrinks away; its colour never changes.
func _make_snow(amount: int, lifetime: float, speed: Vector2, flake_scale: Vector2) -> CPUParticles2D:
	var snow := CPUParticles2D.new()
	snow.amount = amount
	snow.lifetime = lifetime
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.direction = WIND.normalized()
	snow.spread = WIND_SPREAD
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
		var layer: Texture2D = load(COLD_DIR + COLD_LAYERS[i][0])
		var lifted := Vector2(0.0, -COLD_LAYERS[i][1] * COLD_PIXEL)
		if i == COLD_LAYERS.size() - 1:
			_add_cold_ground(far)
		far.add_figure(SetPiece.pixel_texture(layer.get_image(), COLD_PIXEL), lifted)
		if i == 0:
			far.add_figure(SetPiece.pixel_texture(_sun_image(), COLD_PIXEL), SUN_AT)
	var snow := _make_snow(FAR_AMOUNT, FAR_LIFETIME, FAR_SPEED, FAR_SCALE)
	snow.position = Vector2(760, 300)
	snow.emission_rect_extents = Vector2(1300, 650)
	snow.preprocess = FAR_LIFETIME  # already falling on the first frame
	far.fore.add_child(snow)
	_add_hand(far)
	return far


func _add_cold_ground(far: SetPiece) -> void:
	var ground := ColorRect.new()
	ground.color = COLD_GROUND
	ground.position = Vector2(0.0, COLD_GROUND_FROM * COLD_PIXEL)
	ground.size = Vector2(SetPiece.VIEW.x, SetPiece.VIEW.y - ground.position.y)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	far.world.add_child(ground)


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
