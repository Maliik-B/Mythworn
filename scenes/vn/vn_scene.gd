extends Control
## Renders a VNData segment: dialogue beats advanced by click/Enter, then an optional
## choice set whose consequence (a RealmConfig) applies before handing off to the next
## scene. Content-agnostic plumbing — the realm-entry VN and the Fable send-off both feed
## it a VNData via RunManager.pending_vn. See VNData + docs/GAME_DESIGN.md § Realms.

# The running head: a setting beat's place and time, set above the panel in the card title's face.
const HEAD_FONT_SIZE := 40
const HEAD_COLOR := Color(0.88, 0.76, 0.48)
const HEAD_RULE_LENGTH := 150.0
const HEAD_FADE := 0.35
const PANEL_HEIGHT := 260.0
# An option's trade, set under its label in the summaries' gold, wrapped at this width.
const DETAIL_COLOR := Color(0.9, 0.8, 0.4)
const DETAIL_FONT_SIZE := 16
const DETAIL_WIDTH := 1300.0

var _vn: VNData
var _next_scene: String = "res://scenes/map/map_scene.tscn"
var _beat_index: int = 0
var _at_choices: bool = false
var _finishing: bool = false

var _speaker_label: Label
var _text_label: RichTextLabel
var _prompt_label: Label
var _choices_box: VBoxContainer
var _head: Control
var _head_label: Label


func _ready() -> void:
	_vn = RunManager.pending_vn
	if RunManager.pending_vn_next != "":
		_next_scene = RunManager.pending_vn_next
	RunManager.pending_vn = null
	if _vn == null or _vn.beats.is_empty():
		_vn = _fallback_vn()  # direct-launch debug so the scene renders standalone
	_build_ui()
	_show_beat(0)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# The running head over the dialogue panel, stacked up from the bottom of the screen, so a panel
	# that grows (options with their trade set under them) pushes the head up instead of running under
	# it. The head sits centred with a fine rule either side, hidden until a segment names its place.
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stack.offset_left = 120
	stack.offset_right = -120
	stack.offset_top = -80
	stack.offset_bottom = -80
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.add_theme_constant_override("separation", 14)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_head = CenterContainer.new()
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.visible = false
	stack.add_child(_head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 28)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_head.add_child(head_row)
	head_row.add_child(_head_rule())
	_head_label = Label.new()
	_head_label.add_theme_font_override("font", load(CardFace.TITLE_FONT_PATH))
	_head_label.add_theme_font_size_override("font_size", HEAD_FONT_SIZE)
	_head_label.add_theme_color_override("font_color", HEAD_COLOR)
	head_row.add_child(_head_label)
	head_row.add_child(_head_rule())

	# Dialogue panel across the lower third.
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = PANEL_HEIGHT
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.14, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.72, 0.35, 0.8)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	stack.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_speaker_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.custom_minimum_size = Vector2(0, 110)
	_text_label.add_theme_font_size_override("normal_font_size", 20)
	vbox.add_child(_text_label)

	_prompt_label = Label.new()
	_prompt_label.text = "▸  click to continue"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt_label.modulate = Color(1, 1, 1, 0.5)
	vbox.add_child(_prompt_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	_choices_box.visible = false
	vbox.add_child(_choices_box)


func _head_rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(HEAD_COLOR, 0.55)
	rule.custom_minimum_size = Vector2(HEAD_RULE_LENGTH, 1.5)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## A new place fades in over the old one; the same place named again changes nothing.
func _set_head(text: String) -> void:
	if _head.visible and _head_label.text == text:
		return
	_head_label.text = text
	_head.visible = true
	_head.modulate.a = 0.0
	create_tween().tween_property(_head, "modulate:a", 1.0, HEAD_FADE)


func _show_beat(idx: int) -> void:
	# Setting beats are read as the head, not as lines: each one passed over replaces the head, and the
	# panel shows the first ordinary beat after them, so a setting costs no click.
	while idx < _vn.beats.size() and _vn.beats[idx].setting:
		_set_head(_vn.beats[idx].text)
		idx += 1
	if idx >= _vn.beats.size():
		# A segment that ends on a setting line has nothing under it; the next click moves on.
		_beat_index = _vn.beats.size() - 1
		_speaker_label.visible = false
		_text_label.text = ""
		_prompt_label.visible = _vn.choices.is_empty()
		return
	_beat_index = idx
	var beat: VNData.VNBeat = _vn.beats[idx]
	_speaker_label.text = beat.speaker
	_speaker_label.modulate = beat.speaker_color
	_speaker_label.visible = beat.speaker != ""
	_text_label.text = beat.text
	var last := idx >= _vn.beats.size() - 1
	# Hide the "click to continue" prompt only when the next input is a choice, not a click.
	_prompt_label.visible = not (last and not _vn.choices.is_empty())


func _input(event: InputEvent) -> void:
	if _at_choices or _finishing:
		return
	var advance := false
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	elif event.is_action_pressed("ui_accept"):
		advance = true
	if advance:
		_advance()


func _advance() -> void:
	if _beat_index < _vn.beats.size() - 1:
		_show_beat(_beat_index + 1)
	elif _vn.choices.is_empty():
		_finish()
	else:
		_show_choices()


func _show_choices() -> void:
	_at_choices = true
	_prompt_label.visible = false
	for c in _vn.choices:
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_choice.bind(c))
		if c.detail == "":
			btn.text = c.label
		else:
			_set_choice_detail(btn, c)
		_choices_box.add_child(btn)
	_choices_box.visible = true


## An option that says what it will change: its label, and the trade under it in the summaries'
## gold. The button keeps the height of the two, however the trade wraps.
func _set_choice_detail(btn: Button, c: VNData.VNChoice) -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)
	var label := Label.new()
	label.text = c.label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	col.add_child(label)
	var detail := Label.new()
	detail.text = c.detail
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = DETAIL_WIDTH
	detail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	detail.add_theme_font_size_override("font_size", DETAIL_FONT_SIZE)
	detail.add_theme_color_override("font_color", DETAIL_COLOR)
	col.add_child(detail)
	var fit := func(): btn.custom_minimum_size.y = col.get_combined_minimum_size().y + 20.0
	col.minimum_size_changed.connect(fit)
	fit.call()


func _on_choice(choice: VNData.VNChoice) -> void:
	# Apply the realm-shape consequence (if any) — this is how the realm-entry VN sets the
	# run's realm state before the map opens. apply_realm_config also queues the map_boon,
	# applies any passion_shift, and emits realm_configured.
	if choice.config != null:
		RunManager.apply_realm_config(choice.config)
	_choices_box.visible = false
	for ch in _choices_box.get_children():
		ch.queue_free()
	if choice.result_text != "":
		# Show the outcome as a closing narration beat; the next click finishes. Clearing
		# choices makes _advance route to _finish.
		_vn.choices.clear()
		_vn.beats.append(VNData.VNBeat.new("", choice.result_text, Color(0.75, 0.78, 0.85)))
		_at_choices = false
		_show_beat(_vn.beats.size() - 1)
	else:
		_finish()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	# Chain to the next queued VN segment (send-off -> realm-entry), if any; otherwise
	# hand off to the final destination captured at _ready (the map by default).
	if not RunManager.pending_vn_queue.is_empty():
		RunManager.pending_vn = RunManager.pending_vn_queue.pop_front()
		SceneTransition.change_scene("res://scenes/vn/vn_scene.tscn")
	else:
		SceneTransition.change_scene(_next_scene)


func _fallback_vn() -> VNData:
	var vn := VNData.new()
	vn.add_beat("Bram", "Filled it with everything we still have on Camelot. Lore never sticks around more than a couple days.")
	vn.add_beat("Neve", "Go on. Come back in one piece. You're bad at that.")
	return vn
