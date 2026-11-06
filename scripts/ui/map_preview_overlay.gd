class_name MapPreviewOverlay
extends Control
## Read-only, scrollable preview of the current act's map. Openable from any
## non-map scene (rest / shop / event) so the player can glance at their route
## and what's ahead without leaving — it never mutates map state or navigates.
##
## Reuses the persistent map in RunManager.current_map and MapNode's static
## type helpers, but renders its own compact, non-interactive node graph so it
## carries none of the map scene's clicking / scrolling / effect machinery.

const SPACING_X := 96
const SPACING_Y := 66
const NODE := 42
const MARGIN := 48

var _scroll: ScrollContainer
var _current_y := 0.0
var _has_current := false


## Builds the overlay, parents it to `host`, and returns it. Sits on top of
## whatever scene opened it; the Close button (or clicking the dim backdrop)
## tears it down.
static func open(host: Node) -> MapPreviewOverlay:
	var overlay := MapPreviewOverlay.new()
	host.add_child(overlay)
	overlay._build()
	return overlay


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Match the viewport right away. Anchor-based full-rect sizing only resolves on the
	# next layout pass; until then the overlay is a zero-size box in the corner, which
	# confines the dim backdrop and the (anchor-centered) panel there too. Setting the
	# size explicitly makes both fill/centre correctly the moment the overlay opens.
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop — clicking it closes the preview.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 620)
	# Center reliably. The panel is built the same frame the overlay is added, before
	# it has been laid out, so a PRESET_CENTER bakes its offsets against a zero-size
	# parent and lands the panel in the corner. Anchoring to the middle (0.5) with
	# fixed half-size offsets lets the engine recompute the rect correctly once the
	# parent takes its real size.
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380.0
	panel.offset_top = -310.0
	panel.offset_right = 380.0
	panel.offset_bottom = 310.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.075, 0.07, 0.98)
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.5, 0.45, 0.32)
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Map: Act %d" % RunManager.current_act
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "Your route so far and what lies ahead: ◈ marks where you stand."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	vbox.add_child(subtitle)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(700, 480)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	var canvas := Control.new()
	_scroll.add_child(canvas)
	_render_map(canvas)

	# Open centred on where the player stands (mirrors the map scene), not scrolled
	# to the boss at the top. Deferred so the ScrollContainer has laid out first.
	if _has_current:
		_scroll_to_current.call_deferred()

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 42)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 18)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close)
	vbox.add_child(close)


func _node_center(node: MapNode, floor_count: int) -> Vector2:
	# Floor 0 at the bottom, boss at the top — mirrors the real map's orientation,
	# including the generator's cosmetic x/y jitter so the preview matches.
	var x := MARGIN + (node.column + node.x_jitter) * SPACING_X + NODE / 2.0
	var y := MARGIN + (floor_count - 1 - node.floor_num + node.y_jitter) * SPACING_Y + NODE / 2.0
	return Vector2(x, y)


func _render_map(canvas: Control) -> void:
	var map: MapData = RunManager.current_map
	if map == null:
		var none := Label.new()
		none.text = "No map to show."
		none.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		canvas.add_child(none)
		canvas.custom_minimum_size = Vector2(300, 100)
		return

	# Size the canvas so the ScrollContainer can reach every node.
	var max_col := 0
	for id in map.nodes:
		max_col = maxi(max_col, map.nodes[id].column)
	canvas.custom_minimum_size = Vector2(
		MARGIN * 2 + max_col * SPACING_X + NODE,
		MARGIN * 2 + (map.floor_count - 1) * SPACING_Y + NODE)

	var available := map.get_available_next_ids()

	# Edges first, behind the node dots. Traversed edges (from a visited node into
	# the current node) are drawn brighter so the taken path stands out.
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		var from_pos := _node_center(node, map.floor_count)
		for next_id in node.next_nodes:
			var next_node: MapNode = map.get_node(next_id)
			if next_node == null:
				continue
			var line := Line2D.new()
			line.add_point(from_pos)
			line.add_point(_node_center(next_node, map.floor_count))
			var travelled := node.visited and next_node.visited
			line.width = 3.0 if travelled else 2.0
			line.default_color = Color(0.8, 0.7, 0.4, 0.8) if travelled \
				else Color(0.36, 0.34, 0.3, 0.6)
			canvas.add_child(line)

	# Node dots.
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		var is_current: bool = id == map.current_node_id
		var dot := _make_dot(node, is_current, id in available)
		var center := _node_center(node, map.floor_count)
		dot.position = center - Vector2(NODE / 2.0, NODE / 2.0)
		canvas.add_child(dot)
		if is_current:
			_current_y = center.y
			_has_current = true


func _scroll_to_current() -> void:
	if not _scroll:
		return
	var view_h := _scroll.size.y
	var target := int(_current_y - view_h / 2.0)
	_scroll.scroll_vertical = maxi(0, target)


## A single non-interactive node marker, styled by type and state.
func _make_dot(node: MapNode, is_current: bool, is_available: bool) -> Control:
	# The same look the map itself paints, so the peek gives away nothing the map hides.
	var look := node.look(node.quest_payoff_id != &"" and RunManager.is_quest_active(node.quest_payoff_id))
	var color: Color = look["color"]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NODE, NODE)
	panel.size = Vector2(NODE, NODE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.tooltip_text = look["name"]

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(NODE / 2)
	style.set_border_width_all(3)
	style.bg_color = color.darkened(0.5)
	style.border_color = color

	var landmark: bool = look.get("landmark", false)

	if is_current:
		# Where the player stands — bright fill + thick pale-gold ring + ◈ badge.
		style.bg_color = color.darkened(0.15)
		style.set_border_width_all(5)
		style.border_color = Color(1.0, 0.92, 0.55)
	elif is_available:
		style.bg_color = color.darkened(0.3)
		style.border_color = color.lightened(0.25)
	elif node.visited:
		style.bg_color = color.darkened(0.7)
		style.border_color = color.darkened(0.2)
	elif not landmark:
		# Out-of-reach future node — dim it (landmarks stay vivid below).
		style.bg_color = color.darkened(0.65)
		style.border_color = color.darkened(0.35)

	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = "◈" if is_current else look["glyph"]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22 if (is_current or landmark) else 18)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if node.visited and not is_current:
		lbl.modulate = Color(1, 1, 1, 0.7)
	panel.add_child(lbl)
	return panel


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	queue_free()
