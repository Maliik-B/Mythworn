class_name MapFlourish
extends Node
## The map's set pieces: the road rewriting itself after a pledge, and a quest marked on it. Both are
## one move, a slow climb up the map: a front rises from where you stand, the view lifts to keep it
## at the reading line, and what changed changes as the front reaches it. Then the view comes home.
## Presentation only. The nodes and the quest have already changed by the time one of these plays;
## it shows the player what changed, and a click can hurry it to the same end state.
##
## The view is the canvas's own position, so the scroll bar never moves and rest is exactly scale 1
## at position 0. Whatever a flourish adds to the canvas goes with it. Muted: there is no sound here
## until one has been cleared.

signal finished

# The canvas's layers while a flourish plays, over the roads and every node left at rest. A z_index
# outranks the tree, so the veil also dims the header, which helps; what must read above it, such as
# the quest's toast, takes ABOVE_Z.
const VEIL_Z := 1
const RING_Z := 2
const LINE_Z := 3
const RAISED_Z := 4
const ABOVE_Z := 5

const VEIL_ALPHA := 0.3  # light enough that the map reads as it goes by
const VEIL_IN := 0.35
const GLIDE_BACK := 0.5

# The climb. The reading line is measured down from the top of the view: under the header, above the
# middle, where a node has been in sight a moment before it changes.
const READ_Y := 420.0
const CLIMB_SPEED := 240.0  # canvas px a second, once under way
const CLIMB_EASE := 0.6  # seconds to get under way, and to stop
const LIFT_KNEE := 70.0  # the view takes up the front this softly, and lets go of it at the top as softly
const CLIMB_LEAD := 0.6  # the map is seen at rest this long before anything moves
const GLIDE_HOME := 1.0  # the view comes back down to where you stand

# The rewrite: each changed node flips as the front reaches it, with a small ring of ink of its own.
# A flip takes its time, so the last ones are still turning as the view reaches the
# top, and the view goes home once the last has ended.
const WAVE_COLOR := Color(0.96, 0.86, 0.62, 0.9)
const FLIP_GAP := 0.16  # two nodes on one floor still flip one after the other
const FLIP_SIZE := 2.2
const FLIP_IN := 0.28
const FLIP_SWAP := 0.3
const FLIP_HOLD := 0.42
const FLIP_OUT := 0.4
const FLIP_RING_REACH := 110.0
const FLIP_RING_LEN := 0.7
const SETTLED_SIZE := 1.35  # the changed nodes stay a little large until the view comes home
const REWRITE_HOLD := 0.35  # the least time the view stays at the top before it goes home

# The mark: a ring from your node, a line inked up the road at the front, the glyph coming down at
# the end of it.
const MARK_RING_AT := 0.1
const MARK_RING_LEN := 0.7
const MARK_RING_REACH := 260.0
const LINE_AT := 0.3
const LINE_LEN := 0.85  # a road that does not climb is inked in this long
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
var _lift := 0.0
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

# The climb in hand: where the front starts and how far it goes (canvas y, up is smaller), the view's
# scroll at rest, how far the view can lift before the map's top edge, and the climb's ramps.
var _front_from := 0.0
var _climb := 0.0
var _rest_scroll := 0.0
var _lift_max := 0.0
var _ramp := 0.0
var _peak := 0.0
var _cruise := 0.0


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
## canvas position, and the callable that paints its new look. The front starts at the reading line;
## a node already below it has been seen, so it changes first, and the rest as the front reaches them.
## The climb goes on to the top of the map, so the whole road the pledge has changed is seen.
func play_rewrite(flips: Array) -> void:
	flips.sort_custom(func(a, b): return a["at"].y > b["at"].y)
	var view := _start_climb()
	var from: float = _rest_scroll + READ_Y
	# The lift lags the front by a knee as it starts and closes on the top over another.
	var to_top := _lift_max + 2.0 * LIFT_KNEE
	_plan_climb(from, maxf(from - flips[flips.size() - 1]["at"].y, to_top))

	var times: Array[float] = []
	var prev := -INF
	for flip in flips:
		var at := CLIMB_LEAD + _time_to_climb(from - flip["at"].y)
		at = maxf(at, prev + FLIP_GAP)
		times.append(at)
		prev = at
	var flip_len := FLIP_IN + FLIP_SWAP + FLIP_HOLD + FLIP_OUT
	var glide_at: float = maxf(prev + flip_len, CLIMB_LEAD + _climb_time() + REWRITE_HOLD)

	_add_veil()
	_veil_track(glide_at)
	_run_climb(glide_at, view)
	for i in flips.size():
		var btn: Button = flips[i]["btn"]
		var swap: Callable = flips[i]["swap"]
		_due.append(swap)
		_raise(btn)
		_add_ring(flips[i]["at"], FLIP_RING_REACH, times[i] + FLIP_IN, FLIP_RING_LEN, WAVE_COLOR, 8.0)
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
		_tween_at(glide_at).tween_property(btn, "scale", Vector2.ONE, GLIDE_HOME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


# ============================================================
# THE QUEST MARK
# ============================================================

## A quest marked on the road. `road` holds the canvas points from your node to the quest node, along
## roads the player can walk. `lit` are the buttons along it, `mark` the quest node's. `swap` paints
## the glyph on, and `landed` runs as it hits, which is where the toast goes. The line is inked up the
## road at the front, so the view climbs with its head.
func play_mark(road: PackedVector2Array, lit: Array, mark: Button, swap: Callable, landed: Callable) -> void:
	_due.append(swap)
	_due.append(landed)
	var view := _start_climb()
	var rise := road[0].y - road[road.size() - 1].y
	_plan_climb(road[0].y, maxf(0.0, rise))
	var climbs := rise > 1.0
	var ink_len := _climb_time() if climbs else LINE_LEN
	var stamp_at := LINE_AT + ink_len
	var hit_at := stamp_at + STAMP_FALL
	var glide_at := hit_at + MARK_HOLD

	_add_veil()
	_veil_track(glide_at)
	_add_ring(road[0], MARK_RING_REACH, MARK_RING_AT, MARK_RING_LEN, MapNode.QUEST_MARK_LOOK["color"], 9.0)
	_run_climb(glide_at, view, LINE_AT)

	for btn in lit:
		_raise(btn)
		btn.modulate = Color.WHITE
	_raise(mark)
	_start_line(road)
	var ink := _tween_at(LINE_AT)
	if climbs:
		ink.tween_method(func(t: float) -> void: _draw_line_to(_road_share_at(road, _front_at(t))),
			0.0, ink_len, ink_len)
	else:
		ink.tween_method(_draw_line_to, 0.0, 1.0, ink_len).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
# THE CLIMB
# ============================================================

## Reads where the view rests: the scroll the canvas hangs in, and how far it can lift before the map's
## top edge comes down into the view. Returns the scroll, or null when the canvas hangs in none.
func _start_climb() -> ScrollContainer:
	_lift = 0.0
	_knock = 0.0
	var view := _canvas.get_parent().get_parent() as ScrollContainer
	_rest_scroll = float(view.scroll_vertical) if view != null else 0.0
	_lift_max = _rest_scroll
	return view


## A climb of `climb` canvas px up from `from`: under way over CLIMB_EASE, on at CLIMB_SPEED, and
## stopping over CLIMB_EASE. A short one never reaches full speed, at the same easing.
func _plan_climb(from: float, climb: float) -> void:
	_front_from = from
	_climb = maxf(0.0, climb)
	if _climb >= CLIMB_SPEED * CLIMB_EASE:
		_ramp = CLIMB_EASE
		_peak = CLIMB_SPEED
		_cruise = (_climb - CLIMB_SPEED * CLIMB_EASE) / CLIMB_SPEED
	else:
		_ramp = sqrt(_climb * CLIMB_EASE / CLIMB_SPEED)
		_peak = CLIMB_SPEED * _ramp / CLIMB_EASE
		_cruise = 0.0


func _climb_time() -> float:
	return 2.0 * _ramp + _cruise


## How far the front has climbed `t` seconds into the climb.
func _climbed(t: float) -> float:
	if _climb <= 0.0 or t <= 0.0:
		return 0.0
	var pull := _peak / _ramp if _ramp > 0.0 else 0.0
	var total := _climb_time()
	if t >= total:
		return _climb
	if t < _ramp:
		return pull * t * t / 2.0
	if t < _ramp + _cruise:
		return _peak * _ramp / 2.0 + _peak * (t - _ramp)
	var left := total - t
	return _climb - pull * left * left / 2.0


## When the front has climbed `dist`: at once for anything it starts above.
func _time_to_climb(dist: float) -> float:
	if dist <= 0.0:
		return 0.0
	if dist >= _climb:
		return _climb_time()
	var lo := 0.0
	var hi := _climb_time()
	for i in 40:
		var mid := (lo + hi) / 2.0
		if _climbed(mid) < dist:
			lo = mid
		else:
			hi = mid
	return hi


func _front_at(t: float) -> float:
	return _front_from - _climbed(t)


## How far the view has lifted `t` seconds into the climb: enough to keep the front at the reading
## line once the front has reached it, taken up and let go of softly, and never past the map's top.
func _lift_at(t: float) -> float:
	var wanted := _rest_scroll + READ_Y - _front_at(t)
	var lift := _soft_cap(_soft_start(wanted, LIFT_KNEE), _lift_max, LIFT_KNEE)
	return clampf(lift, 0.0, _lift_max)


## `x` from 0 up, taken up softly: nothing below 0, `x - knee` from `2 * knee` on, a curve between.
func _soft_start(x: float, knee: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 2.0 * knee:
		return x - knee
	return x * x / (4.0 * knee)


## `x` held under `top`, let go of softly over `knee` either side of it.
func _soft_cap(x: float, top: float, knee: float) -> float:
	var under := top - x
	if under >= knee:
		return x
	if under <= -knee:
		return top
	return top - (under + knee) * (under + knee) / (4.0 * knee)


## The view lifts with the front from `start`, holds until `glide_at`, then comes home and ends.
func _run_climb(glide_at: float, view: ScrollContainer, start := CLIMB_LEAD) -> void:
	var tw := _tween()
	var climbed_by := 0.0
	if view != null and _lift_max > 0.0 and _climb > 0.0:
		tw.tween_interval(start)
		tw.tween_method(func(t: float) -> void: _set_lift(_lift_at(t)), 0.0, _climb_time(), _climb_time())
		climbed_by = start + _climb_time()
	if glide_at > climbed_by:
		tw.tween_interval(glide_at - climbed_by)
	tw.tween_method(_set_lift_home, 1.0, 0.0, GLIDE_HOME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(finish_now)


func _set_lift(lift: float) -> void:
	_lift = lift
	_apply_lift()


## The way home: the lift at its height, eased down to nothing.
func _set_lift_home(share: float) -> void:
	_canvas.scale = Vector2.ONE
	_canvas.position = Vector2(0.0, _lift * share + _knock)


func _apply_lift() -> void:
	_canvas.scale = Vector2.ONE
	_canvas.position = Vector2(0.0, _lift + _knock)


func _set_knock(amount: float) -> void:
	_knock = amount
	_apply_lift()


## How much of the road lies below canvas height `y`, as a share of its length. The road climbs a
## floor at a time, so each height is passed once.
func _road_share_at(road: PackedVector2Array, y: float) -> float:
	var total := 0.0
	for i in road.size() - 1:
		total += road[i].distance_to(road[i + 1])
	if total <= 0.0:
		return 1.0
	var walked := 0.0
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var seg: float = a.distance_to(b)
		if y >= b.y:
			var part := clampf((a.y - y) / (a.y - b.y), 0.0, 1.0) if a.y > b.y else 1.0
			return (walked + seg * part) / total
		walked += seg
	return 1.0


# ============================================================
# THE CAMERA (the crossing's: a push in on one point)
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


func _camera_step(u: float, from_focus: Vector2, from_zoom: float, to_focus: Vector2, to_zoom: float) -> void:
	_focus = from_focus.lerp(to_focus, u)
	_zoom = lerpf(from_zoom, to_zoom, u)
	_apply_camera()


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
## Oversized, since the view can carry the canvas's edge across the frame.
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
	tw.tween_property(_veil, "modulate:a", 0.0, GLIDE_HOME)


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
