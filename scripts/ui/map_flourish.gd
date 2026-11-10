class_name MapFlourish
extends Node
## The map's two set pieces: the road rewriting itself after a pledge, and a quest marked on it.
## Presentation only. The nodes and the quest have already changed by the time one of these plays;
## it shows the player what changed, and a click can hurry it to the same end state.
##
## The camera is the canvas's own scale and position, so the scroll bar never moves and rest is
## exactly scale 1 at position 0. Whatever a flourish adds to the canvas goes with it. Muted: there
## is no sound here until one has been cleared.

signal finished

# The canvas's layers while a flourish plays, over the roads and every node left at rest. A z_index
# outranks the tree, so the veil also dims the header, which helps; what must read above it, such as
# the quest's toast, takes ABOVE_Z.
const VEIL_Z := 1
const RING_Z := 2
const LINE_Z := 3
const RAISED_Z := 4
const ABOVE_Z := 5

# Where a beat's action must land on the 1920x1080 frame: inside the phone crop, a 1000 wide centre
# running from 90 to 990 down, and under the header. The mark's sits lower, to clear its two-line toast.
const REWRITE_AREA := Rect2(460, 190, 1000, 790)
const MARK_AREA := Rect2(460, 320, 1000, 660)
const NODE_MARGIN := 80.0  # canvas room around a node, for its flip size
const ZOOM_MIN := 1.04  # a wide frame takes only this, to keep every node in the crop
const ZOOM_MAX := 1.5
const CREEP := 1.03  # the push keeps going a little through the hold, so the frame never dies
const CAMERA_LEAD := 0.5
const GLIDE_BACK := 0.5
const VEIL_ALPHA := 0.5
const VEIL_IN := 0.35

# The wave: spreads fast and slows, as ink does, and a node flips as the front reaches it.
const WAVE_START := 0.2
const WAVE_LEN := 1.5
const WAVE_COLOR := Color(0.96, 0.86, 0.62, 0.9)
const FLIP_GAP := 0.16  # two nodes the same distance out still flip one after the other
const FLIP_SIZE := 2.2
const FLIP_IN := 0.16
const FLIP_SWAP := 0.18
const FLIP_HOLD := 0.22
const FLIP_OUT := 0.22
const SETTLED_SIZE := 1.35  # the changed nodes stay a little large until the camera lets go
const REWRITE_HOLD := 0.2

# The mark: a ring from your node, a line down the road, the glyph coming down at the end of it.
const MARK_RING_AT := 0.1
const MARK_RING_LEN := 0.7
const MARK_RING_REACH := 260.0
const LINE_AT := 0.3
const LINE_LEN := 0.85
const LINE_WIDTH := 7.0
const LINE_GLOW_WIDTH := 22.0
const STAMP_FROM := 3.8
const STAMP_SIZE := 2.2
const STAMP_FALL := 0.12
const STAMP_RING_LEN := 0.45
const STAMP_RING_REACH := 190.0
const STAMP_KNOCK := 8.0
const MARK_HOLD := 1.1  # long enough to read the toast with the mark still large

## How long the player must have seen a flourish before a click hurries it. A click meant for the
## screen before this one must not skip the thing it just caused.
const HURRY_AFTER := 0.7

const RING_SHADER := preload("res://assets/shaders/ink_ring.gdshader")

## False for a reveal the player has not seen yet: it plays to its end whatever is clicked. A
## replay, and the quest's mark, can be hurried once HURRY_AFTER has passed.
var hurriable := true

var _canvas: Control
var _anchor := Vector2.ZERO
var _focus := Vector2.ZERO
var _zoom := 1.0
var _knock := 0.0
var _age := 0.0
var _done := false
var _tweens: Array[Tween] = []
var _props: Array[CanvasItem] = []
var _raised: Array[Control] = []
var _due: Array[Callable] = []  # what must still happen if the flourish is hurried
var _veil: ColorRect
var _line_points := PackedVector2Array()
var _line_lengths := PackedFloat32Array()
var _line_core: Line2D
var _line_glow: Line2D


## `canvas` is the node this flourish moves and draws on. It must not be a container's direct child.
func setup(canvas: Control) -> void:
	_canvas = canvas


func _process(delta: float) -> void:
	_age += delta


## True once a click may hurry this flourish.
func can_hurry() -> bool:
	return hurriable and _age >= HURRY_AFTER


# ============================================================
# THE REWRITE
# ============================================================

## The road rewrites itself. `flips` holds one {"btn", "at", "swap"} per changed node: its button, its
## canvas position, and the callable that paints its new look. `origin` is where the ink starts.
func play_rewrite(origin: Vector2, flips: Array) -> void:
	var reach := 1.0
	for flip in flips:
		reach = maxf(reach, origin.distance_to(flip["at"]))
	var ring_end := reach + NODE_MARGIN
	flips.sort_custom(func(a, b): return origin.distance_squared_to(a["at"]) < origin.distance_squared_to(b["at"]))

	# When the front reaches each node. The ring's radius eases out, so invert that curve.
	var times: Array[float] = []
	var prev := -FLIP_GAP
	for flip in flips:
		var share: float = origin.distance_to(flip["at"]) / ring_end
		var at := WAVE_START + WAVE_LEN * (1.0 - sqrt(1.0 - share))
		at = maxf(at, prev + FLIP_GAP)
		times.append(at)
		prev = at

	var flip_len := FLIP_IN + FLIP_SWAP + FLIP_HOLD + FLIP_OUT
	var glide_at: float = prev + flip_len + REWRITE_HOLD

	_begin(REWRITE_AREA)
	_add_veil()
	_veil_track(glide_at)
	_add_ring(origin, ring_end, WAVE_START, WAVE_LEN, WAVE_COLOR, 12.0)

	var points: Array = []
	for flip in flips:
		points.append(flip["at"])
	var with_origin := points.duplicate()
	with_origin.append(origin)
	var framed := _frame(_box(with_origin), REWRITE_AREA)
	if not framed["fits"]:
		framed = _frame(_box(points), REWRITE_AREA)
	var keys: Array = []
	for i in flips.size():
		# Arrive as the swap lands. The first move gets a floor, or a near node would make it a jerk.
		var arrive: float = maxf(times[i] + FLIP_IN + FLIP_SWAP * 0.5, CAMERA_LEAD)
		keys.append([arrive, _focus_showing(flips[i]["at"], framed["focus"], framed["zoom"], REWRITE_AREA), framed["zoom"]])
	_run_camera(keys, glide_at)

	for i in flips.size():
		var btn: Button = flips[i]["btn"]
		var swap: Callable = flips[i]["swap"]
		_due.append(swap)
		_raise(btn)
		_tweens.append(RevealAnim.play_node(self, btn, times[i], {
			"enlarge": FLIP_SIZE,
			"enlarge_t": FLIP_IN,
			"swap_t": FLIP_SWAP,
			"hold_t": FLIP_HOLD,
			"deenlarge_t": FLIP_OUT,
			"start_scale": 1.0,
			"start_alpha": 1.0,
			"end_scale": SETTLED_SIZE,
		}, _do.bind(swap)))
		_tween_at(glide_at).tween_property(btn, "scale", Vector2.ONE, GLIDE_BACK) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


# ============================================================
# THE QUEST MARK
# ============================================================

## A quest marked on the road. `road` holds the canvas points from your node to the quest node, along
## roads the player can walk. `lit` are the buttons along it, `mark` the quest node's. `swap` paints
## the glyph on, and `landed` runs as it hits, which is where the toast goes.
func play_mark(road: PackedVector2Array, lit: Array, mark: Button, swap: Callable, landed: Callable) -> void:
	_due.append(swap)
	_due.append(landed)
	var stamp_at := LINE_AT + LINE_LEN
	var hit_at := stamp_at + STAMP_FALL
	var glide_at := hit_at + MARK_HOLD

	_begin(MARK_AREA)
	_add_veil()
	_veil_track(glide_at)
	_add_ring(road[0], MARK_RING_REACH, MARK_RING_AT, MARK_RING_LEN, MapNode.QUEST_MARK_LOOK["color"], 9.0)

	var points: Array = Array(road)
	var framed := _frame(_box(points), MARK_AREA)
	var ends := [road[0], road[road.size() - 1]]
	_run_camera([
		[CAMERA_LEAD, _focus_showing(ends[0], framed["focus"], framed["zoom"], MARK_AREA), framed["zoom"]],
		[stamp_at, _focus_showing(ends[1], framed["focus"], framed["zoom"], MARK_AREA), framed["zoom"]],
	], glide_at)

	for btn in lit:
		_raise(btn)
		btn.modulate = Color.WHITE
	_raise(mark)
	_start_line(road)
	_tween_at(LINE_AT).tween_method(_draw_line_to, 0.0, 1.0, LINE_LEN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var stamp := _tween_at(stamp_at)
	stamp.tween_callback(func() -> void:
		_do(swap)
		mark.pivot_offset = mark.size / 2.0
		mark.scale = Vector2(STAMP_FROM, STAMP_FROM)
		mark.modulate = Color(1, 1, 1, 0))
	stamp.tween_property(mark, "scale", Vector2(STAMP_SIZE, STAMP_SIZE), STAMP_FALL) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	stamp.parallel().tween_property(mark, "modulate:a", 1.0, STAMP_FALL * 0.6)
	stamp.tween_callback(func() -> void:
		_do(landed)
		_add_ring(mark.position + mark.size / 2.0, STAMP_RING_REACH, 0.0, STAMP_RING_LEN, MapNode.QUEST_MARK_LOOK["color"], 11.0)
		_set_knock(STAMP_KNOCK))
	stamp.tween_method(_set_knock, STAMP_KNOCK, 0.0, 0.14).set_ease(Tween.EASE_OUT)

	var back := _tween_at(glide_at)
	back.tween_property(mark, "scale", Vector2.ONE, GLIDE_BACK).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	back.parallel().tween_property(_line_core, "modulate:a", 0.0, GLIDE_BACK)
	back.parallel().tween_property(_line_glow, "modulate:a", 0.0, GLIDE_BACK)


# ============================================================
# THE END, HOWEVER IT GETS THERE
# ============================================================

## Ends the flourish now, at the same state it would have reached: anything it still owed the player
## happens, and the canvas is back at rest with nothing of this left on it.
func finish_now() -> void:
	if _done:
		return
	_done = true
	for tw in _tweens:
		if tw.is_valid():
			tw.kill()
	for due in _due.duplicate():
		_do(due)
	_canvas.scale = Vector2.ONE
	_canvas.position = Vector2.ZERO
	for btn in _raised:
		btn.scale = Vector2.ONE
		btn.z_index = 0
	for prop in _props:
		prop.queue_free()
	finished.emit()
	queue_free()


func _do(once: Callable) -> void:
	if _due.has(once):
		_due.erase(once)
		once.call()


func _raise(btn: Control) -> void:
	if not _raised.has(btn):
		_raised.append(btn)
	btn.z_index = RAISED_Z


# ============================================================
# THE CAMERA
# ============================================================

## Rest is the focus that puts the canvas at position 0, so a flourish starts and ends with no pop.
func _begin(area: Rect2) -> void:
	var holder_at: Vector2 = _canvas.get_parent().global_position
	_anchor = area.get_center() - holder_at
	_focus = _anchor
	_zoom = 1.0


func _apply_camera() -> void:
	_canvas.scale = Vector2(_zoom, _zoom)
	_canvas.position = _anchor - _focus * _zoom + Vector2(0.0, _knock)


func _set_knock(amount: float) -> void:
	_knock = amount
	_apply_camera()


func _camera_step(u: float, from_focus: Vector2, from_zoom: float, to_focus: Vector2, to_zoom: float) -> void:
	_focus = from_focus.lerp(to_focus, u)
	_zoom = lerpf(from_zoom, to_zoom, u)
	_apply_camera()


## Moves through `keys`, each [arrive time, focus, zoom], creeps in until `glide_at`, then goes home
## and ends the flourish.
func _run_camera(keys: Array, glide_at: float) -> void:
	var tw := _tween()
	var t := 0.0
	var focus := _focus
	var zoom := _zoom
	for key in keys:
		var dur: float = key[0] - t
		if dur <= 0.0:
			continue
		tw.tween_method(_camera_step.bind(focus, zoom, key[1], key[2]), 0.0, 1.0, dur) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t = key[0]
		focus = key[1]
		zoom = key[2]
	if glide_at > t:
		tw.tween_method(_camera_step.bind(focus, zoom, focus, zoom * CREEP), 0.0, 1.0, glide_at - t)
		zoom *= CREEP
	tw.tween_method(_camera_step.bind(focus, zoom, _anchor, 1.0), 0.0, 1.0, GLIDE_BACK) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(finish_now)


func _box(points: Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box.grow(NODE_MARGIN)


## The focus and zoom that show `box` in `area`, and whether it really fits at the least push.
func _frame(box: Rect2, area: Rect2) -> Dictionary:
	var zoom := clampf(minf(area.size.x / box.size.x, area.size.y / box.size.y), ZOOM_MIN, ZOOM_MAX)
	return {
		"focus": box.get_center(),
		"zoom": zoom,
		"fits": box.size.x * zoom <= area.size.x and box.size.y * zoom <= area.size.y,
	}


## The focus nearest `want` that keeps `point` inside `area`, so a frame too big to fit follows the
## action and a frame that fits holds still.
func _focus_showing(point: Vector2, want: Vector2, zoom: float, area: Rect2) -> Vector2:
	var center := area.get_center()
	var inner := area.grow(-NODE_MARGIN)
	var lo: Vector2 = point - (inner.end - center) / zoom
	var hi: Vector2 = point - (inner.position - center) / zoom
	return Vector2(clampf(want.x, lo.x, hi.x), clampf(want.y, lo.y, hi.y))


# ============================================================
# THE PROPS
# ============================================================

func _tween() -> Tween:
	var tw := create_tween()
	_tweens.append(tw)
	return tw


func _tween_at(at: float) -> Tween:
	var tw := _tween()
	if at > 0.0:
		tw.tween_interval(at)
	return tw


## A dark wash over the backdrop, the roads and every node left at rest, so what moves is what reads.
## Oversized, since the camera can carry the canvas's edge across the frame.
func _add_veil() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.015, 0.01)
	_veil.position = Vector2(-2400, -2400)
	_veil.size = _canvas.size + Vector2(4800, 4800)
	_veil.modulate.a = 0.0
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.z_index = VEIL_Z
	_canvas.add_child(_veil)
	_props.append(_veil)


func _veil_track(glide_at: float) -> void:
	var tw := _tween()
	tw.tween_property(_veil, "modulate:a", VEIL_ALPHA, VEIL_IN)
	tw.tween_interval(maxf(0.0, glide_at - VEIL_IN))
	tw.tween_property(_veil, "modulate:a", 0.0, GLIDE_BACK)


## One ring from `center` out to `reach` in canvas units, starting `at` seconds from now.
func _add_ring(center: Vector2, reach: float, at: float, dur: float, tint: Color, line_width: float) -> void:
	var half := reach + 40.0
	var ring := ColorRect.new()
	ring.position = center - Vector2(half, half)
	ring.size = Vector2(half, half) * 2.0
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.z_index = RING_Z
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("fade", 0.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("line_width", line_width)
	ring.material = mat
	_canvas.add_child(ring)
	_props.append(ring)
	var grow := _tween_at(at)
	grow.tween_property(mat, "shader_parameter/radius", reach, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var fade := _tween_at(at)
	fade.tween_property(mat, "shader_parameter/fade", 1.0, 0.05)
	fade.tween_interval(dur * 0.55)
	fade.tween_property(mat, "shader_parameter/fade", 0.0, dur * 0.45)


## Builds the gold line, undrawn. Subdivides the road and lets it wander a little, so it reads as a
## line someone is inking and not as a highlight laid over the road. Fixed curves, not the run's RNG.
func _start_line(road: PackedVector2Array) -> void:
	var walked := 0.0
	_line_points = PackedVector2Array([road[0]])
	_line_lengths = PackedFloat32Array([0.0])
	var total := 0.0
	for i in road.size() - 1:
		total += road[i].distance_to(road[i + 1])
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var seg: float = a.distance_to(b)
		var steps := maxi(1, int(seg / 12.0))
		var normal: Vector2 = (b - a).orthogonal().normalized() if seg > 0.0 else Vector2.ZERO
		for s in range(1, steps + 1):
			var along := float(s) / steps
			var at := walked + seg * along
			var settle := minf(1.0, minf(at, total - at) / 30.0)
			var wander := (sin(at * 0.021) * 2.4 + sin(at * 0.057 + 1.7) * 1.2) * settle
			_line_points.append(a.lerp(b, along) + normal * wander)
			_line_lengths.append(at)
		walked += seg
	_line_glow = _make_line(LINE_GLOW_WIDTH, 0.22)
	_line_core = _make_line(LINE_WIDTH, 1.0)


func _make_line(width: float, alpha: float) -> Line2D:
	var line := Line2D.new()
	line.width = width
	var col: Color = MapNode.QUEST_MARK_LOOK["color"]
	col.a = alpha
	line.default_color = col
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.z_index = LINE_Z
	_canvas.add_child(line)
	_props.append(line)
	return line


## The line drawn as far as `u` of its length, with its head between two points.
func _draw_line_to(u: float) -> void:
	var total: float = _line_lengths[_line_lengths.size() - 1]
	var head := u * total
	var drawn := PackedVector2Array([_line_points[0]])
	for i in range(1, _line_points.size()):
		if _line_lengths[i] >= head:
			var span: float = _line_lengths[i] - _line_lengths[i - 1]
			var part: float = (head - _line_lengths[i - 1]) / span if span > 0.0 else 1.0
			drawn.append(_line_points[i - 1].lerp(_line_points[i], part))
			break
		drawn.append(_line_points[i])
	_line_core.points = drawn
	_line_glow.points = drawn
