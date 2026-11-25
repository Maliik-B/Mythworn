class_name HoverNote
extends CanvasLayer
## The one panel that says what a thing on the screen is: a status, a power, an item in the pack.
## Hovering a marked control shows it at once; a click on a control marked to pin keeps it up, where
## it is, until a click anywhere else. It replaces the engine tooltip on those controls, so there is
## only ever one panel and it reads on the page: parchment, ink and the card faces' type.
##
## A host adds one (`add_child(HoverNote.new())`) and marks controls with `HoverNote.mark`. Sources
## are found by hit-testing a group rather than by hover signals, since the hosts rebuild their
## chips on every refresh and a chip freed under the cursor never says the mouse left it.

const GROUP := &"hover_note"
const WIDTH := 320.0
const PAD := 14.0
const GAP := 8.0  # between the panel and the thing it describes
const EDGE := 10.0  # the closest the panel comes to the screen's edge
const TITLE_SIZE := 22
const BODY_SIZE := 18
const ASIDE_SIZE := 17
## How long a note stays up after the pointer leaves the control it describes, so it can be read
## while the pointer drifts off.
const LINGER_SEC := 2.0

## Returns true while the host wants no panel at all (a card being dragged, a view open over the
## scene). Optional.
var blocked: Callable = Callable()

var _panel: PanelContainer = null
var _shown_key := ""
var _pinned := false
var _left_msec := -1  # when the pointer left the control the panel describes; -1 while it is on one


## Marks `control` as described by the panel. `kind` is a short line under the title (a status's
## kind, an item's use); `aside` is set dim at the foot (a flavor line, how a status fades). With
## `pins`, a click on it keeps the panel up and is used up, so it cannot also land on what is behind;
## leave it off for a button, whose click must still press it. With `below`, the panel sits under the
## control (above it only when there is no room), for a card that is read from its top.
static func mark(control: Control, title: String, body: String, kind := "", aside := "",
		pins := false, below := false) -> void:
	control.tooltip_text = ""
	control.add_to_group(GROUP)
	control.set_meta("note", {"title": title, "kind": kind, "body": body, "aside": aside})
	control.set_meta("note_pins", pins)
	control.set_meta("note_below", below)


func _init() -> void:
	layer = 98  # over the scene and its effects, under the pause menu (99) and the fade (100)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _is_blocked():
		_close()
		return
	if _pinned:
		return
	var source := _source_at(get_viewport().get_mouse_position())
	if source != null:
		_left_msec = -1
		_show_for(source)
	elif _panel != null:
		var now := Time.get_ticks_msec()
		if _left_msec < 0:
			_left_msec = now
		if not linger_holds(float(now - _left_msec) / 1000.0):
			_close()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _is_blocked():
		return
	var source := _source_at(event.position)
	if source != null and source.get_meta("note_pins", false):
		_pinned = false
		_show_for(source)
		_pinned = true
		get_viewport().set_input_as_handled()
	elif _pinned:
		_pinned = false
		_close()
	elif source == null:
		_close()  # a click anywhere else ends a lingering note at once


## Whether a note whose pointer left `seconds` ago is still up. Pure, so a test can read the rule.
static func linger_holds(seconds: float) -> bool:
	return seconds < LINGER_SEC


## True while the panel is pinned. For the host's own clicks and for tests.
func is_pinned() -> bool:
	return _pinned


## The panel's words, or "" with none up. For tests.
func shown_title() -> String:
	return _panel.get_meta("title", "") if _panel != null else ""


## Takes the panel down, pinned or not. Hosts call this when they open something over the scene.
func dismiss() -> void:
	_pinned = false
	_close()


func _is_blocked() -> bool:
	if get_tree().paused:
		return true
	return blocked.is_valid() and blocked.call()


## The topmost visible marked control under `pos`, or null.
func _source_at(pos: Vector2) -> Control:
	var best: Control = null
	for node in get_tree().get_nodes_in_group(GROUP):
		if node is Control and node.is_visible_in_tree() and not node.is_queued_for_deletion() \
				and node.get_global_rect().has_point(pos):
			if best == null or node.is_greater_than(best):
				best = node
	return best


func _show_for(source: Control) -> void:
	var note: Dictionary = source.get_meta("note")
	var key := "%s|%s|%s|%s" % [note["title"], note["kind"], note["body"], note["aside"]]
	if key != _shown_key or _panel == null:
		_close()
		_shown_key = key
		_panel = _build(note)
		add_child(_panel)
	_place(source.get_global_rect(), source.get_meta("note_below", false))


func _close() -> void:
	_left_msec = -1
	if _panel != null:
		remove_child(_panel)
		_panel.queue_free()
		_panel = null
	_shown_key = ""


func _build(note: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_meta("title", note["title"])
	var style := StyleBoxFlat.new()
	style.bg_color = StageSkin.c("note_bg")
	style.border_color = StageSkin.c("note_edge")
	style.set_border_width_all(2)
	style.set_corner_radius_all(0 if StageSkin.is_page() else 8)
	style.set_content_margin_all(PAD)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	column.add_child(_label(note["title"], CardFace.TITLE_FONT_PATH, TITLE_SIZE, StageSkin.c("note_ink")))
	if note["kind"] != "":
		column.add_child(_label(note["kind"], CardFace.RULES_FONT_PATH, ASIDE_SIZE, StageSkin.c("note_dim")))
	if note["body"] != "":
		column.add_child(_label(note["body"], CardFace.RULES_FONT_PATH, BODY_SIZE, StageSkin.c("note_ink")))
	if note["aside"] != "":
		var rule := ColorRect.new()
		rule.color = StageSkin.c("note_dim")
		rule.custom_minimum_size = Vector2(0, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(rule)
		column.add_child(_label(note["aside"], CardFace.RULES_FONT_PATH, ASIDE_SIZE, StageSkin.c("note_dim")))
	return panel


func _label(text: String, font_path: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - PAD * 2.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


## Above the thing it describes, its left edges lined up; below it when there is no room above.
func _place(around: Rect2, below := false) -> void:
	var screen := get_viewport().get_visible_rect().size
	var size := _panel.get_combined_minimum_size()
	_panel.size = size
	var y := around.end.y + GAP if below else around.position.y - size.y - GAP
	if below and y + size.y > screen.y - EDGE:
		y = around.position.y - size.y - GAP  # no room underneath
	elif y < EDGE:
		y = around.end.y + GAP
	var x := clampf(around.position.x, EDGE, screen.x - size.x - EDGE)
	_panel.position = Vector2(x, minf(y, screen.y - size.y - EDGE))
