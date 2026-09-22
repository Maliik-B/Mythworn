extends Control
## Crown decision after defeating a Camelot act boss while holding Excalibur.
##
## Phase 1 (current): Two-button shell. Both routes lead back to standard act
## transition flow. Take Crown awards King of Camelot title; Refuse Crown
## awards Camelot's Champion. Emits Events.crown_decided(took_crown: bool) so
## Phase 2 can hook governing philosophy modifiers off the same signal without
## restructuring this scene.
##
## Triggered from card_reward_scene._return_to_map when:
##   RunManager.pending_act_complete == true
##   AND RunManager.has_excalibur()
##   AND RunManager.current_realm_id == &"camelot"


func _ready() -> void:
	_build_ui()
	AudioManager.play_music("rest")


func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.6;
	float vig = smoothstep(0.15, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.02, vig * 0.7);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 28)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "The Crown"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = ("The boss is fallen. Camelot kneels. The crown that has waited a generation "
		+ "for a hand worthy of it now waits for yours.\n\nDo you take it?")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 20)
	desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 40)
	vbox.add_child(btn_row)

	btn_row.add_child(_make_choice_button(
		"Take the Crown",
		"Rule Camelot. The realm's strength flows to you.",
		Color(1.0, 0.85, 0.35),
		_on_take_crown))

	btn_row.add_child(_make_choice_button(
		"Refuse the Crown",
		"The throne is not yours to claim. Walk your own path.",
		Color(0.65, 0.65, 0.7),
		_on_refuse_crown))


func _make_choice_button(label: String, sub: String, accent: Color,
		callback: Callable) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 160)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.16, 0.96)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = accent
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var title = Label.new()
	title.text = label
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", accent)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title)

	var subtitle = Label.new()
	subtitle.text = sub
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(subtitle)

	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			callback.call()
	)
	return panel


func _on_take_crown() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.award_title(&"king_of_camelot")
	Events.crown_decided.emit(true)
	_proceed()


func _on_refuse_crown() -> void:
	AudioManager.play_sfx("button_click")
	# Camelot's Champion is the "advisor" path title from REALM_CAMELOT.md.
	# In Phase 2 this becomes a sub-decision (Wander / Advise / Leave).
	RunManager.award_title(&"camelots_champion")
	Events.crown_decided.emit(false)
	_proceed()


func _proceed() -> void:
	# Whatever the player chose, the run advances to the act transition.
	# Phase 2 will inject governing philosophy + sub-options before this point.
	SceneTransition.change_scene("res://scenes/act/act_transition_scene.tscn")
