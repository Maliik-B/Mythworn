extends Control
## Shown after a boss is defeated.
## If more acts remain, advances to the next act. Otherwise shows run victory.

var is_final_act: bool
var _particles: Array[ColorRect] = []
var _time := 0.0


func _ready() -> void:
	# Demo boundary: Camelot Act 1 is the whole demo. Beating Caedmon routes here instead of
	# into the stubbed Act 2 (the enemy pool has no Act-2 content). Reaching act_transition
	# already means a boss was beaten (pending_act_complete) and the crown decision is
	# resolved, so the outcome is final. The demo-end scene owns the Act-1 Camelot wrap-up
	# (including the people's-champion award below). Acts 2-3 + the final-victory path are
	# untouched; they need current_act >= 2 / >= MAX_ACTS, which never matches this guard.
	if RunManager.current_act == 1 and RunManager.current_realm_id == &"camelot":
		SceneTransition.change_scene("res://scenes/demo/demo_end_scene.tscn")
		return
	is_final_act = RunManager.current_act >= RunManager.MAX_ACTS
	# (The Act-1 Camelot people's-champion award moved to demo_end_scene, which now owns that
	# wrap-up; the demo gate above returns before this point for Act-1 Camelot.)
	_build_ui()
	if is_final_act:
		AudioManager.play_music("victory")
	else:
		AudioManager.stop_music()


func _process(delta: float) -> void:
	_time += delta
	_update_particles(delta)


func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Vignette
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.4;
	float vig = smoothstep(0.25, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vig * 0.6);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	# Rising golden particles (behind text)
	_spawn_particles()

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 80)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	if is_final_act:
		_build_victory(vbox)
	else:
		_build_act_complete(vbox)


## The between-acts beat. A keeper's place in a realm is a loan: when the work is done,
## a double steps into your outline and F.A.B.L.E. holds you at the Waystation boundary,
## an interval it can't control, which is why the realm has moved on when you return. The
## opening vignette reflects the Act-1 Camelot crown outcome (took / refused / abdicated),
## keyed off the earned title since philosophy_id isn't set until Reign Phase 2. Later
## acts (and other realms) get the shared frame alone. Abdication exists but is out of
## demo scope.
func _waystation_text() -> String:
	var tail := ("You make your report: the work in the realm is done. This is how it ends "
		+ "for a keeper, every time. Your place was only ever a loan, and a double steps into "
		+ "your outline to keep the story warm once your part is played.\n\n"
		+ "F.A.B.L.E. holds the boundary here at the Waystation. They do not hold the time. "
		+ "Whatever passes while you wait, they cannot account for it. When the way opens, you "
		+ "step back into a realm that has gone on without you.")

	var vignette := ""
	if RunManager.current_act == 1 and RunManager.current_realm_id == &"camelot":
		var champ := RunManager.is_peoples_champion()
		var had_crown_offer := RunManager.has_excalibur()  # gated the crown decision
		if RunManager.has_abdicated:
			vignette = ("You set the crown down where they could all watch you do it, and "
				+ "walked. No double follows you out; there is no role left to keep warm, only a "
				+ "throne you emptied on your way to the door. You feel the realm's regard cool "
				+ "at your back.")
		elif RunManager.earned_title_ids.has(&"king_of_camelot"):
			if champ:
				vignette = ("You take the crown, and it is the lower town that roars for it, not "
					+ "the court. The courtiers clap a half-beat late, having wanted a different "
					+ "king and been handed yours. Down in the market a child is lifted onto "
					+ "someone's shoulders to see you. You find yourself wondering how long a crown "
					+ "the people gave stays the people's.")
			else:
				vignette = ("You leave the coronation to carry itself. Out of the royal apartments, "
					+ "out of the king's mantle, down a servants' stair, and behind you your double "
					+ "is already easing into the chamber, into the crown, into the reign. It will "
					+ "wear your face better than you did.")
		elif champ and had_crown_offer:
			# Refused the crown having held the people's line: their champion, not their king.
			vignette = ("You will not take it, and you say so where they can all hear. For a "
				+ "moment the court doesn't understand, and the people do. You were never going to "
				+ "be their king. You were only ever going to be theirs, and they line the road out "
				+ "of the lower town to tell you so, quietly and all at once. Behind you the court "
				+ "is already closing ranks over a crown that will have to find another head.")
		elif champ:
			# Held the people's line but never pulled Excalibur, so no crown was ever offered.
			vignette = ("No one offers you a crown. You never went for the sword, and a kingdom "
				+ "does not hand itself to a stranger who did not reach for it. But the lower town "
				+ "knows what you did for it, and the lower town is not the court. They see you to "
				+ "the edge of the fields the way you would see off one of your own. It is worth "
				+ "more than a coronation, and you both know it.")
		elif RunManager.earned_title_ids.has(&"camelots_champion"):
			vignette = ("You are gone before the court can turn to name a king. Head down, "
				+ "through the market crowd, into the cool shadow of a borough wall, and you wait "
				+ "for the noise to thin. When you look up, the street is not there. The "
				+ "Waystation is.")

	return tail if vignette == "" else vignette + "\n\n" + tail


func _build_act_complete(vbox: VBoxContainer) -> void:
	var title = Label.new()
	title.text = "Act %d Complete" % RunManager.current_act
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = _waystation_text()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(900, 0)
	desc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.78, 0.76, 0.68))
	vbox.add_child(desc)

	# Stats summary
	_build_stats_summary(vbox)

	var next_btn = Button.new()
	next_btn.text = "Enter Act %d" % (RunManager.current_act + 1)
	next_btn.custom_minimum_size = Vector2(260, 60)
	next_btn.add_theme_font_size_override("font_size", 22)
	next_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	next_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next_btn.pressed.connect(_on_next_act)
	vbox.add_child(next_btn)


func _build_victory(vbox: VBoxContainer) -> void:
	var title = Label.new()
	title.text = "Victory!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
	title.modulate.a = 0.0
	title.scale = Vector2(0.5, 0.5)
	title.pivot_offset = Vector2(960, 29)
	vbox.add_child(title)

	var t = create_tween().set_parallel(true)
	t.tween_property(title, "modulate:a", 1.0, 0.8)
	t.tween_property(title, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var desc = Label.new()
	desc.text = "You have conquered the realm. Your fable is complete."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	vbox.add_child(desc)

	# Stats summary
	_build_stats_summary(vbox)

	var restart_btn = Button.new()
	restart_btn.text = "New Run"
	restart_btn.custom_minimum_size = Vector2(220, 60)
	restart_btn.add_theme_font_size_override("font_size", 22)
	restart_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(_on_new_run)
	vbox.add_child(restart_btn)


func _build_stats_summary(vbox: VBoxContainer) -> void:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.8)
	style.set_corner_radius_all(8)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(panel)

	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(stats_vbox)

	_add_stat_line(stats_vbox, "HP", "%d / %d" % [RunManager.current_hp, RunManager.max_hp],
		Color(0.9, 0.3, 0.3))
	_add_stat_line(stats_vbox, "Gold", str(RunManager.gold),
		Color(0.95, 0.85, 0.3))
	_add_stat_line(stats_vbox, "Deck", "%d cards" % RunManager.current_deck.size(),
		Color(0.7, 0.7, 0.7))

	if RunManager.relics.size() > 0:
		_add_stat_line(stats_vbox, "Relics",
			", ".join(RunManager.get_owned_relic_names()),
			Color(0.7, 0.6, 0.8))

	if RunManager.passion:
		var tier = RunManager.get_passion_tier()
		_add_stat_line(stats_vbox, "Passion",
			"%d (%s)" % [RunManager.passion.current_value, PassionState.tier_name(tier)],
			Color(0.9, 0.5, 0.2))

	_add_stat_line(stats_vbox, "Time", RunManager.get_run_time_string(),
		Color(0.55, 0.55, 0.55))


func _add_stat_line(parent: VBoxContainer, label: String, value: String,
		color: Color) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	lbl.custom_minimum_size.x = 80
	hbox.add_child(lbl)

	var val = Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 20)
	val.add_theme_color_override("font_color", color)
	hbox.add_child(val)


func _spawn_particles() -> void:
	for i in 28:
		var p = ColorRect.new()
		p.custom_minimum_size = Vector2(2, 2)
		p.size = Vector2(2, 2)
		var brightness = randf_range(0.7, 1.0)
		p.color = Color(
			brightness,
			brightness * 0.85,
			brightness * 0.3,
			randf_range(0.15, 0.4))
		p.position = Vector2(randf_range(0, 1920), randf_range(0, 1080))
		p.set_meta("vel_y", randf_range(-15, -5))
		p.set_meta("phase", randf_range(0, TAU))
		add_child(p)
		_particles.append(p)


func _update_particles(delta: float) -> void:
	for p in _particles:
		var vy: float = p.get_meta("vel_y")
		var phase: float = p.get_meta("phase")
		p.position.x += sin(_time * 0.4 + phase) * 0.4
		p.position.y += vy * delta
		p.modulate.a = 0.3 + sin(_time * 0.7 + phase) * 0.15
		# Wrap at top back to bottom
		if p.position.y < -10:
			p.position.y = 1090
			p.position.x = randf_range(0, 1920)


func _on_next_act() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.advance_act()
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


func _on_new_run() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.run_active = false
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")
