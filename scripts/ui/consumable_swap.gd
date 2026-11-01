class_name ConsumableSwap
extends Control
## The "your hands are full" prompt. Raised whenever an event or a shop hands the player a
## consumable and both slots are taken. The player leaves one thing behind: either one of the two
## they carry, or the new one. Nothing is decided until a button is pressed, and the host is told
## what happened through `resolved`.
##
## The cap is the reason this exists. With two slots and no way to widen them, taking a third
## thing is always a trade, and the trade is the decision.

## Emitted once, when the player has chosen. `taken` is true if the new item went into the pack
## (a held one was dropped to make room) and false if the player left the new item behind.
signal resolved(taken: bool)

var _new_item: ConsumableData


## Builds the prompt over `host` and returns it. `new_item` is what is on offer.
static func open(host: Node, new_item: ConsumableData) -> ConsumableSwap:
	var swap := ConsumableSwap.new()
	swap._new_item = new_item
	host.add_child(swap)
	swap._build()
	return swap


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 90

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -330.0
	panel.offset_top = -190.0
	panel.offset_right = 330.0
	panel.offset_bottom = 190.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.07, 0.98)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.62, 0.52, 0.32)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Your hands are full."
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.78, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var offer := Label.new()
	offer.text = "%s\n%s" % [_new_item.display_name, _new_item.description]
	offer.add_theme_font_size_override("font_size", 18)
	offer.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	offer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	offer.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(offer)

	var ask := Label.new()
	ask.text = "You can carry two. Leave one behind."
	ask.add_theme_font_size_override("font_size", 16)
	ask.add_theme_color_override("font_color", Color(0.65, 0.62, 0.54))
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ask)

	for held in RunManager.consumables:
		var btn := _make_button("Drop %s (%s)" % [held.display_name, held.description])
		btn.pressed.connect(_on_drop_held.bind(held))
		vbox.add_child(btn)

	var leave := _make_button("Leave %s behind" % _new_item.display_name)
	leave.pressed.connect(_on_leave_new)
	vbox.add_child(leave)


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 46)
	btn.add_theme_font_size_override("font_size", 16)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


func _on_drop_held(held: ConsumableData) -> void:
	AudioManager.play_sfx("button_click")
	RunManager.discard_consumable(held)
	RunManager.add_consumable(_new_item)
	_finish(true)


func _on_leave_new() -> void:
	AudioManager.play_sfx("button_click")
	_finish(false)


func _finish(taken: bool) -> void:
	resolved.emit(taken)
	queue_free()
