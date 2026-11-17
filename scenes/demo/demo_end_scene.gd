extends Control
## The demo boundary. Shown after the Act-1 Camelot boss (Sir Caedmon) instead of letting
## the player continue into the stubbed Act 2. The keeper's part in this telling is played
## out: a send-off that reflects their crown choice, a run summary, a call to follow the game
## (the wishlist once a Steam page exists), and a clean Play Again / Return to Title. Act 2+ stays intact behind the gate for post-demo.
##
## Visually a sibling of act_transition_scene (the beat this replaces): golden rising
## particles, the same stat panel, the same procedural chrome.

## The Steam store-page URL. Empty = the follow block shows instead of the wishlist block;
## fill this in when the Steam page is live and the wishlist button opens it via OS.shell_open.
const WISHLIST_URL := ""
## Where the follow block sends a player while there is no Steam page to wishlist.
const SITE_URL := "https://mythworn.com"
const DISCORD_URL := "https://discord.gg/cyk9Q74pYn"

var _particles: Array[ColorRect] = []
var _time := 0.0


func _ready() -> void:
	# A people's champion who never pulled Excalibur earns the title here (the crown scene's
	# refuse path covers Excalibur-holders). This used to live in act_transition, but the demo
	# gate routes here before that runs, so this scene owns the Act-1 Camelot wrap-up now.
	if RunManager.is_peoples_champion() and not RunManager.has_excalibur() \
			and not RunManager.has_abdicated:
		RunManager.award_title(&"peoples_champion")
	_build_ui()
	AudioManager.play_music("victory")


func _process(delta: float) -> void:
	_time += delta
	_update_particles(delta)


func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.15)
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
	float dist = length(uv) * 1.4;
	float vig = smoothstep(0.25, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vig * 0.6);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

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
	vbox.add_theme_constant_override("separation", 22)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "The Tale Pauses Here"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	title.modulate.a = 0.0
	title.scale = Vector2(0.6, 0.6)
	title.pivot_offset = Vector2(960, 29)
	vbox.add_child(title)
	var t = create_tween().set_parallel(true)
	t.tween_property(title, "modulate:a", 1.0, 0.8)
	t.tween_property(title, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Send-off body
	var desc = Label.new()
	desc.text = _send_off_text()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(900, 0)
	desc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.78, 0.76, 0.68))
	vbox.add_child(desc)

	_build_summary(vbox)
	if WISHLIST_URL != "":
		_build_wishlist(vbox)
	else:
		_build_follow(vbox)
	_build_nav(vbox)


## The crown-outcome vignette (reflecting the player's Act-1 Camelot choice) followed by a
## demo-boundary send-off. The vignette logic mirrors act_transition_scene._waystation_text,
## but the tail is the demo's edge, not the between-acts "step back into the realm" interval.
## The prose stays in the world; the literal demo and wishlist words stay in the UI chrome below.
func _send_off_text() -> String:
	var vignette := ""
	var champ := RunManager.is_peoples_champion()
	var had_crown_offer := RunManager.has_excalibur()
	if RunManager.has_abdicated:
		vignette = ("You set the crown down where they could all watch you do it, and walked. "
			+ "No double follows you out; there is no role left to keep warm, only a throne you "
			+ "emptied on your way to the door.")
	elif RunManager.earned_title_ids.has(&"king_of_camelot"):
		if champ:
			vignette = ("You take the crown, and it is the lower town that roars for it, not the "
				+ "court. Down in the market a child is lifted onto someone's shoulders to see you. "
				+ "You find yourself wondering how long a crown the people gave stays the people's.")
		else:
			vignette = ("You leave the coronation to carry itself, down a servants' stair, while "
				+ "behind you a double is already easing into the chamber, into the crown, into the "
				+ "reign. It will wear your face better than you did.")
	elif champ and had_crown_offer:
		vignette = ("You will not take it, and you say so where they can all hear. The court "
			+ "doesn't understand, and the people do. You were never going to be their king. You "
			+ "were only ever going to be theirs, and they line the road out to tell you so.")
	elif champ:
		vignette = ("No one offers you a crown; you never went for the sword. But the lower town "
			+ "knows what you did for it, and the lower town is not the court. They see you to the "
			+ "edge of the fields the way you would see off one of your own.")
	elif RunManager.earned_title_ids.has(&"camelots_champion"):
		vignette = ("You are gone before the court can turn to name a king. Head down, through the "
			+ "market crowd, into the cool shadow of a borough wall, and you wait for the noise to "
			+ "thin.")
	else:
		vignette = ("The realm is quiet behind you. Caedmon is down, whatever moved him has drawn "
			+ "back out of reach for now, and for the first time in a long while Camelot gets to be only "
			+ "itself.")

	var tail := ("Your part in this telling is played out, and the tale does not go on past "
		+ "here. Not yet. F.A.B.L.E. holds the rest of it the way they hold everything, close "
		+ "and out of reach, until there is more to tell.\n\nYou came the whole first stretch of "
		+ "the road. Thank you for that. When the way opens again, I hope you'll want to see "
		+ "where it goes.")
	return vignette + "\n\n" + tail


## The one-line headline of how the run ended, from the earned titles + champion / abdication
## state (same priority order as the send-off vignette).
func _outcome_headline() -> String:
	if RunManager.has_abdicated:
		return "Abdicated the crown"
	if RunManager.earned_title_ids.has(&"king_of_camelot"):
		return "King of Camelot, the people's king" if RunManager.is_peoples_champion() else "King of Camelot"
	if RunManager.is_peoples_champion() and RunManager.has_excalibur():
		return "Refused the crown: the People's Champion"
	if RunManager.is_peoples_champion():
		return "The People's Champion"
	if RunManager.earned_title_ids.has(&"camelots_champion"):
		return "Camelot's Champion"
	return "Champion of Camelot"


func _build_summary(vbox: VBoxContainer) -> void:
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

	var s = VBoxContainer.new()
	s.add_theme_constant_override("separation", 8)
	panel.add_child(s)

	_add_stat_line(s, "Outcome", _outcome_headline(), Color(0.95, 0.85, 0.3))
	_add_stat_line(s, "HP", "%d / %d" % [RunManager.current_hp, RunManager.max_hp], Color(0.9, 0.3, 0.3))
	_add_stat_line(s, "Gold", str(RunManager.gold), Color(0.95, 0.85, 0.3))
	_add_stat_line(s, "Deck", "%d cards" % RunManager.current_deck.size(), Color(0.7, 0.7, 0.7))
	_add_stat_line(s, "Enemies", str(RunManager.run_stats.get("enemies_killed", 0)), Color(0.8, 0.5, 0.5))
	_add_stat_line(s, "Cards", str(RunManager.run_stats.get("cards_played", 0)), Color(0.6, 0.7, 0.8))
	_add_stat_line(s, "Damage", str(RunManager.run_stats.get("damage_dealt", 0)), Color(0.85, 0.55, 0.3))

	if RunManager.relics.size() > 0:
		_add_stat_line(s, "Relics", ", ".join(RunManager.get_owned_relic_names()), Color(0.7, 0.6, 0.8))

	if RunManager.passion:
		var tier = RunManager.get_passion_tier()
		_add_stat_line(s, "Passion",
			"%d (%s)" % [RunManager.passion.current_value, PassionState.tier_name(tier)],
			Color(0.9, 0.5, 0.2))

	var title_names: Array[String] = []
	for id in RunManager.earned_title_ids:
		var td = TitlePool.get_title(id)
		if td:
			title_names.append(td.original_name)
	if not title_names.is_empty():
		_add_stat_line(s, "Titles", ", ".join(title_names), Color(0.8, 0.7, 0.45))

	_add_stat_line(s, "Time", RunManager.get_run_time_string(), Color(0.55, 0.55, 0.55))


func _add_stat_line(parent: VBoxContainer, label: String, value: String, color: Color) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	parent.add_child(hbox)

	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	lbl.custom_minimum_size.x = 90
	hbox.add_child(lbl)

	var val = Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 20)
	val.add_theme_color_override("font_color", color)
	hbox.add_child(val)


func _build_wishlist(vbox: VBoxContainer) -> void:
	var header = Label.new()
	header.text = "Wishlist Mythworn on Steam"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	vbox.add_child(header)

	var btn := _make_button("Wishlist on Steam" if WISHLIST_URL != "" else "Wishlist: coming soon",
		Vector2(300, 56))
	if WISHLIST_URL != "":
		btn.pressed.connect(_on_wishlist_pressed)
	else:
		btn.disabled = true
	vbox.add_child(btn)

	if WISHLIST_URL == "":
		var note = Label.new()
		note.text = "Steam page coming soon."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 14)
		note.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
		vbox.add_child(note)


## Shown in place of the wishlist block until a Steam page exists: the game's site and its
## Discord, each opened in the browser (a new tab in the browser build).
func _build_follow(vbox: VBoxContainer) -> void:
	var header = Label.new()
	header.text = "Follow Mythworn as it grows"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	vbox.add_child(header)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	var site := _make_button("mythworn.com", Vector2(260, 52))
	site.pressed.connect(_on_link_pressed.bind(SITE_URL))
	row.add_child(site)

	var discord := _make_button("Join the Discord", Vector2(260, 52))
	discord.pressed.connect(_on_link_pressed.bind(DISCORD_URL))
	row.add_child(discord)


func _build_nav(vbox: VBoxContainer) -> void:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	vbox.add_child(row)

	var again := _make_button("Play Again")
	again.pressed.connect(_on_play_again)
	row.add_child(again)

	var title_btn := _make_button("Return to Title")
	title_btn.pressed.connect(_on_return_to_title)
	row.add_child(title_btn)


## Gold-on-dark button in the shared settings/title style, so the demo-end chrome matches the
## rest of the menus rather than hand-rolling a one-off look.
func _make_button(text: String, min_size := Vector2(220, 52)) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 20)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var s = StyleBoxFlat.new()
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.bg_color = Color(0.18, 0.13, 0.26)
	s.border_color = Color(0.8, 0.6, 0.25)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", s)

	var h = s.duplicate()
	h.bg_color = Color(0.26, 0.2, 0.36)
	h.border_color = Color(1.0, 0.78, 0.3)
	b.add_theme_stylebox_override("hover", h)

	var p = s.duplicate()
	p.bg_color = Color(0.12, 0.09, 0.18)
	b.add_theme_stylebox_override("pressed", p)

	var d = s.duplicate()
	d.bg_color = Color(0.12, 0.1, 0.16)
	d.border_color = Color(0.35, 0.3, 0.3)
	b.add_theme_stylebox_override("disabled", d)

	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.48, 0.44))
	return b


func _spawn_particles() -> void:
	for i in 28:
		var p = ColorRect.new()
		p.custom_minimum_size = Vector2(2, 2)
		p.size = Vector2(2, 2)
		var brightness = randf_range(0.7, 1.0)
		p.color = Color(brightness, brightness * 0.85, brightness * 0.3, randf_range(0.15, 0.4))
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
		if p.position.y < -10:
			p.position.y = 1090
			p.position.x = randf_range(0, 1920)


func _on_wishlist_pressed() -> void:
	AudioManager.play_sfx("button_click")
	if WISHLIST_URL != "":
		OS.shell_open(WISHLIST_URL)


func _on_link_pressed(url: String) -> void:
	AudioManager.play_sfx("button_click")
	OS.shell_open(url)


func _on_play_again() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.run_active = false
	SceneTransition.change_scene("res://scenes/character_select/character_select_scene.tscn")


func _on_return_to_title() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.run_active = false
	SceneTransition.change_scene("res://scenes/title/title_screen.tscn")
