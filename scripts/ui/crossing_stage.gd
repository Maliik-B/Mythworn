class_name CrossingStage
extends MapFlourish
## The crossing, staged for the clip. Nothing in the game calls this and it changes no map data: the
## real node is built elsewhere and stays out of the clip. By default the crossing is only its node
## icon: a face of plain light, a ring in its destination's colour, and a little fine snow drifting off
## it. Each destination has its own colour, so a player can hunt for the one they want and can read
## where a crossing goes before stepping on it. Stepping through swaps the map
## itself. The other map's ground turns up outward from the icon on a stepped front, each node pinching
## shut or opening as the front reaches it, until the whole map is a different one with the icon still
## where it was, now the way back. Nothing here carries a word: it is unnamed. The other map is a
## throwaway from the generator and never reaches the run. Light.SLIT, EATEN and NONE are the earlier
## looks, with their hard cut to a cold frame and the hand.
##
## The light has no glow, swirl, rim or tear: it is the icon's own face, in one flat tone, with nothing
## behind it. The snow is flat white, and shrinks to nothing rather than fading, because white at part
## alpha over a dark field reads as grey. Camelot's palette is left alone until the front reaches it.
## No creatures, and none of the other realm's aurora or wisps.
##
## Trigger, on a map scene open for at least two frames:
##   var crossing := CrossingStage.play(get_tree().current_scene)
##   await crossing.stepped  # the frame the swap starts
##   await crossing.held     # about 3 s in; the other map stays up until crossing.close()

signal stepped
signal held

enum Light {
	ICON,  # the node's own face is the light, and stepping through swaps the map
	SLIT,  # a slit a person could only just step through, opening slowly
	EATEN,  # a patch with its edge eaten back, thin enough for the map to show through
	NONE,  # no shape: only the snow, the white, and the map's own ink fading where it falls
}
const DEFAULT_LIGHT := Light.ICON

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

# One look per destination: a crossing node wears the colour of where it goes. Glyphs are the real
# node's placeholders, and this is the same table as MapNode.CROSSING_LOOKS on the realm branch.
const CROSSING_LOOKS := {
	&"yggdrasil": {"glyph": "❄", "color": Color(0.42, 0.55, 0.78)},
	&"camelot": {"glyph": "☀", "color": Color(0.99, 0.83, 0.42)},
}
const SWAP_HOME := &"camelot"

# The icon.
const ICON_ON_FRAME := Vector2(960, 540)
const ICON_STEP_AT := 1.5
const ICON_FROM_ZOOM := 1.5
const ICON_TO_ZOOM := 1.62
const ICON_FACE := Color(0.94, 0.94, 0.92)
const ICON_INK := Color(0.16, 0.2, 0.27)
const ICON_RING := 7
const ICON_FONT := 26
const ICON_BREATH := 0.75  # seconds each way, at the scale below: enough to catch the eye, no more
const ICON_BREATH_SCALE := 1.1
const ICON_SNOW_AMOUNT := 24
const ICON_SNOW_LIFETIME := 1.3
const ICON_SNOW_SPEED := Vector2(18, 42)  # canvas units a second, so it stays near the icon's footprint
const ICON_SNOW_SCALE := Vector2(1.0, 1.7)
const ICON_SNOW_DRIFT := Vector2(0.45, 1.0)
const ICON_SNOW_SPREAD := 50.0
const ICON_SNOW_FROM := 16.0

# The swap: a front running out from the icon at one speed, while the camera lets go to show the map.
const SWAP_LEN := 0.85
const SWAP_REACH := 1100.0  # canvas units
const SWAP_END_ZOOM := 1.08
const SWAP_FLIP := 0.09  # each half of a node's turn
const SWAP_POP := 1.22
const SWAP_HEADER_OUT := 0.18
const SWAP_ROAD_FEATHER := 36.0
const SWAP_ROAD_WIDTH := 3.0
const SWAP_SNOW_AMOUNT := 170
const SWAP_SNOW_SPEED := Vector2(120, 210)  # frame pixels a second
const SWAP_SNOW_SCALE := Vector2(1.0, 2.0)
const SWAP_GRAPH_SEED := 7741  # a fixed throwaway map, so every take is the same one
const SWAP_REALM := &"yggdrasil"
const SWAP_ICE_MIX := 0.05  # how much of a node's own colour stays: more, and red turns mauve
# The cold map's rows lifted, as COLD_LAYERS, only far enough to clear the bottom bar.
const COLD_MAP_LIFTS: Array[int] = [0, 2, 4, 6, 6]
const COLD_MAP_GROUND_FROM := 203

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
const COLD_GROUND_SHADER := preload("res://assets/shaders/cold_ground.gdshader")

## Where the node stands on the frame, for a drawn cursor to step onto.
var target_on_frame := NODE_ON_FRAME

var _scene: Node
var _node_btn: Button
var _far: SetPiece
var _stepped := false
var _light := DEFAULT_LIGHT
var _inked_roads: Array[Line2D] = []
var _inked_nodes: Array[Button] = []
var _at := Vector2.ZERO
var _camera_tween: Tween
var _icon_snow: CPUParticles2D
var _cold_rect: TextureRect
var _cold_mat: ShaderMaterial
var _cold_snow: CPUParticles2D
var _cold_roads: Array[Line2D] = []
var _old_roads: Array[Line2D] = []
var _cold_nodes: Array[Button] = []
var _header: Control
var _ice := Color.WHITE


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
	if _light == Light.ICON:
		_swap_the_map()
	else:
		_far.visible = true
		_far.zoom_to(1.035, HELD_AT - STEP_AT + 0.5)
	stepped.emit()


## Takes the whole stage away and hands the map back as it was.
func close() -> void:
	if is_instance_valid(_far):
		_far.queue_free()
	for road in _inked_roads:
		road.gradient = null
	for road in _old_roads:
		road.gradient = null
	if _light == Light.ICON and is_instance_valid(_node_btn):
		_take_off_the_face(_node_btn)
	if is_instance_valid(_header):
		_header.modulate.a = 1.0
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
	var at: Vector2 = _scene._get_node_center(node)
	if _light == Light.ICON:
		_run_icon(at)
		return
	_node_btn.modulate.a = 0.0  # no glyph to name it: the light stands where the node did

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
# THE ICON, AND THE SWAP
# ============================================================

func _run_icon(at: Vector2) -> void:
	_at = at
	target_on_frame = ICON_ON_FRAME
	_begin(Rect2(ICON_ON_FRAME - Vector2.ONE, Vector2(2, 2)))
	_camera_step(1.0, _focus, _zoom, at, ICON_FROM_ZOOM)
	_camera_tween = _tween()
	_camera_tween.tween_method(_camera_step.bind(at, ICON_FROM_ZOOM, at, ICON_TO_ZOOM), 0.0, 1.0, ICON_STEP_AT)

	_put_on_the_face(_node_btn, CROSSING_LOOKS[SWAP_REALM])
	var breath := _tween().set_loops()
	breath.tween_property(_node_btn, "scale", Vector2(ICON_BREATH_SCALE, ICON_BREATH_SCALE), ICON_BREATH) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property(_node_btn, "scale", Vector2.ONE, ICON_BREATH) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_icon_snow = _make_snow(ICON_SNOW_AMOUNT, ICON_SNOW_LIFETIME, ICON_SNOW_SPEED, ICON_SNOW_SCALE)
	_icon_snow.direction = ICON_SNOW_DRIFT.normalized()
	_icon_snow.spread = ICON_SNOW_SPREAD
	_icon_snow.position = at
	_icon_snow.emission_rect_extents = Vector2(ICON_SNOW_FROM, ICON_SNOW_FROM)
	_canvas.add_child(_icon_snow)
	_props.append(_icon_snow)

	_build_the_other_map(at)

	var timeline := _tween_at(ICON_STEP_AT)
	timeline.tween_callback(step_through)
	timeline.tween_interval(HELD_AT - ICON_STEP_AT)
	timeline.tween_callback(func() -> void: held.emit())


## The icon's face is the plain light: one flat tone, with nothing shining around it. Its ring is the
## ring every node has, in the colour of where it goes. Worn on the button directly, so its look and its
## place in the legend stay what they were. close() takes it off.
func _put_on_the_face(btn: Button, look: Dictionary) -> void:
	var face := StyleBoxFlat.new()
	face.set_corner_radius_all(_scene.NODE_SIZE / 2)
	face.bg_color = ICON_FACE
	face.set_border_width_all(ICON_RING)
	face.border_color = look["color"]
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, face)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ICON_INK)
	btn.add_theme_font_size_override("font_size", ICON_FONT)
	btn.text = look["glyph"]
	btn.modulate = Color.WHITE
	btn.pivot_offset = btn.size / 2.0
	btn.z_index = RAISED_Z
	if not _raised.has(btn):
		_raised.append(btn)


func _take_off_the_face(btn: Button) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.remove_theme_color_override(state)
	_scene._paint_node(btn, btn.get_meta("look"))


## Built hidden and whole before the shot needs it, so the swap has nothing still loading.
func _build_the_other_map(at: Vector2) -> void:
	var accent: Color = RealmRegistry.get_realm(SWAP_REALM).get_accent_for_act(1)
	_ice = accent.lerp(Color.WHITE, 0.55)
	_build_cold_ground()

	var rng := RandomNumberGenerator.new()
	rng.seed = SWAP_GRAPH_SEED
	var map: MapData = MapGenerator.generate(rng, SWAP_REALM, 1, 1.0, false)
	# The whole map is nudged so one of its nodes lands on the icon: the icon stays where it is, and it
	# is the world around it that has changed.
	var landing: MapNode = null
	var best := INF
	for id in map.nodes:
		var d: float = _scene._get_node_center(map.nodes[id]).distance_squared_to(at)
		if d < best:
			best = d
			landing = map.nodes[id]
	var nudge: Vector2 = at - _scene._get_node_center(landing)

	var first_button := 0
	for i in _canvas.get_child_count():
		var child := _canvas.get_child(i)
		if child is Line2D and child.points.size() == 2 and not _props.has(child):
			_old_roads.append(child)
		if child is Button:
			first_button = i
			break
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		var from: Vector2 = _scene._get_node_center(node) + nudge
		for next_id in node.next_nodes:
			var road := Line2D.new()
			road.add_point(from)
			road.add_point(_scene._get_node_center(map.get_node(next_id)) + nudge)
			road.width = SWAP_ROAD_WIDTH
			road.default_color = Color(_ice.r, _ice.g, _ice.b, 0.85)
			road.gradient = Gradient.new()
			road.visible = false
			_canvas.add_child(road)
			_canvas.move_child(road, first_button)
			first_button += 1
			_props.append(road)
			_cold_roads.append(road)
		if node == landing:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(_scene.NODE_SIZE, _scene.NODE_SIZE)
		btn.size = btn.custom_minimum_size
		btn.position = from - btn.size / 2.0
		btn.pivot_offset = btn.size / 2.0
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.scale = Vector2(0.0, 1.0)
		_scene._paint_node(btn, _cold_look(node.look()))
		btn.visible = false
		_canvas.add_child(btn)
		_props.append(btn)
		_cold_nodes.append(btn)


## A node of the other map keeps its glyph, in the realm's own cold palette.
func _cold_look(look: Dictionary) -> Dictionary:
	var cold := look.duplicate()
	cold["color"] = _ice.lerp(look["color"], SWAP_ICE_MIX)
	return cold


## The pack's layers flattened into one picture, under the map's canvas and over everything Camelot
## has behind it, with the bottom bar left on top. Its front stays at nothing until the swap.
func _build_cold_ground() -> void:
	var picture: Image = null
	for i in COLD_LAYERS.size():
		var layer: Texture2D = load(COLD_DIR + COLD_LAYERS[i][0])
		var image: Image = layer.get_image()
		image.convert(Image.FORMAT_RGBA8)
		if picture == null:
			picture = image
			picture.blend_rect(_sun_image(), Rect2i(Vector2i.ZERO, _sun_image().get_size()), Vector2i(SUN_AT / COLD_PIXEL))
			continue
		if i == COLD_LAYERS.size() - 1:
			var rows := picture.get_height() - COLD_MAP_GROUND_FROM
			picture.fill_rect(Rect2i(0, COLD_MAP_GROUND_FROM, picture.get_width(), rows), COLD_GROUND)
		picture.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, -COLD_MAP_LIFTS[i]))
	_cold_rect = TextureRect.new()
	_cold_rect.texture = SetPiece.pixel_texture(picture, COLD_PIXEL)
	_cold_rect.size = SetPiece.VIEW
	_cold_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cold_mat = ShaderMaterial.new()
	_cold_mat.shader = COLD_GROUND_SHADER
	_cold_mat.set_shader_parameter("center", ICON_ON_FRAME)
	_cold_mat.set_shader_parameter("reach", 0.0)
	_cold_rect.material = _cold_mat
	_scene.add_child(_cold_rect)
	_scene.move_child(_cold_rect, _scene.scroll_container.get_index() - 1)
	_props.append(_cold_rect)
	_cold_snow = _make_snow(SWAP_SNOW_AMOUNT, FAR_LIFETIME, SWAP_SNOW_SPEED, SWAP_SNOW_SCALE)
	_cold_snow.emitting = false
	_cold_rect.add_child(_cold_snow)


## One place giving way to another: the front runs out from the icon, and each thing turns over as it
## is reached, by distance alone, so the swap is one motion and no node is a beat of its own.
func _swap_the_map() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_icon_snow.emitting = false
	_cold_snow.emitting = true
	_cold_snow.position = ICON_ON_FRAME
	for road in _old_roads:
		road.gradient = Gradient.new()  # runs black to white until _set_front gives it its colours
	_set_front(0.0)
	for road in _cold_roads:
		road.visible = true
	_tween().tween_method(_camera_step.bind(_at, _zoom, _at, SWAP_END_ZOOM), 0.0, 1.0, SWAP_LEN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween().tween_method(_set_front, 0.0, SWAP_REACH, SWAP_LEN)

	var speed := SWAP_REACH / SWAP_LEN
	for id in _scene.node_buttons:
		var btn: Button = _scene.node_buttons[id]
		if btn == _node_btn:
			continue
		if not _raised.has(btn):
			_raised.append(btn)
		var out := _tween_at((btn.position + btn.size / 2.0).distance_to(_at) / speed)
		btn.pivot_offset = btn.size / 2.0
		out.tween_property(btn, "scale:x", 0.0, SWAP_FLIP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		out.tween_callback(func() -> void: btn.modulate.a = 0.0)
	for btn in _cold_nodes:
		var open := _tween_at((btn.position + btn.size / 2.0).distance_to(_at) / speed)
		open.tween_callback(func() -> void:
			btn.visible = true
			btn.scale = Vector2(0.0, SWAP_POP))
		open.tween_property(btn, "scale:x", SWAP_POP, SWAP_FLIP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		open.tween_property(btn, "scale", Vector2.ONE, SWAP_FLIP * 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# The icon turns over too, in place: it is the way back now, so it wears the colour of home.
	var turn := _tween()
	turn.tween_property(_node_btn, "scale:x", 0.0, SWAP_FLIP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	turn.tween_callback(_put_on_the_face.bind(_node_btn, CROSSING_LOOKS[SWAP_HOME]))
	turn.tween_property(_node_btn, "scale:x", 1.0, SWAP_FLIP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Nothing on the frame may still say where you were.
	_header = _scene._legend_row.get_parent().get_parent().get_parent()
	_tween().tween_property(_header, "modulate:a", 0.0, SWAP_HEADER_OUT)


func _set_front(reach: float) -> void:
	_cold_mat.set_shader_parameter("reach", reach * _zoom)
	var on_frame := reach * _zoom
	_cold_snow.emission_rect_extents = Vector2(minf(on_frame, 1300.0), minf(on_frame, 800.0))
	for road in _old_roads:
		_hand_over(road, reach, false)
	for road in _cold_roads:
		_hand_over(road, reach, true)


## A road turns over along its length as the front passes it: the old map's goes, the new map's comes.
func _hand_over(road: Line2D, reach: float, arriving: bool) -> void:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var col: Color = road.default_color
	for i in INK_STOPS:
		var along := float(i) / (INK_STOPS - 1)
		var reached := smoothstep(reach - SWAP_ROAD_FEATHER, reach + SWAP_ROAD_FEATHER,
			road.points[0].lerp(road.points[1], along).distance_to(_at))
		offsets.append(along)
		colors.append(Color(col.r, col.g, col.b, col.a * ((1.0 - reached) if arriving else reached)))
	road.gradient.offsets = offsets
	road.gradient.colors = colors


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
