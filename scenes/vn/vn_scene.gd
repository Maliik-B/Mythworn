extends Control
## Renders a VNData segment: dialogue beats advanced by click/Enter, then an optional
## choice set whose consequence (a RealmConfig) applies before handing off to the next
## scene. Content-agnostic plumbing — the realm-entry VN and the Fable send-off both feed
## it a VNData via RunManager.pending_vn. See VNData + docs/GAME_DESIGN.md § Realms.

var _vn: VNData
var _next_scene: String = "res://scenes/map/map_scene.tscn"
var _beat_index: int = 0
var _at_choices: bool = false
var _finishing: bool = false

var _speaker_label: Label
var _text_label: RichTextLabel
var _prompt_label: Label
var _choices_box: VBoxContainer


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

	# Dialogue panel across the lower third.
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = -340
	panel.offset_bottom = -80
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.14, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.72, 0.35, 0.8)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

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


func _show_beat(idx: int) -> void:
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
		btn.text = c.label
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(_on_choice.bind(c))
		_choices_box.add_child(btn)
	_choices_box.visible = true


func _on_choice(choice: VNData.VNChoice) -> void:
	# Apply the realm-shape consequence (if any) — this is how the realm-entry VN sets the
	# run's realm state before the map opens.
	if choice.config != null:
		RunManager.realm_config = choice.config
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
	SceneTransition.change_scene(_next_scene)


func _fallback_vn() -> VNData:
	var vn := VNData.new()
	vn.add_beat("Bram", "Filled it with everything we still have on Camelot. Lore never sticks around more than a couple days.")
	vn.add_beat("Neve", "Go on. Come back in one piece. You're bad at that.")
	return vn
