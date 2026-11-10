extends Control
## Shows gold reward and 3 card choices after combat victory. Player picks one or skips.

# Card art icons live in CardVisuals (single source, shared with combat + the
# deck / Passion full-card renders).

var card_choices: Array[CardData] = []
var card_panels: Dictionary = {} # CardData -> PanelContainer
var gold_earned: int = 0
var _inspect: Control


func _ready() -> void:
	# Award gold immediately
	gold_earned = RunManager.pending_gold_reward
	RunManager.add_gold(gold_earned)
	RunManager.pending_gold_reward = 0

	# Boss rewards (pending_act_complete is set on boss nodes) get the richer offer:
	# a guaranteed rare + uncommon-or-better, instead of the tier-split hallway reward.
	# The Gracious widens either offer by one card; the row is an HBox, so it just gets wider.
	var reward_count := 3 + RunManager.get_card_reward_bonus()
	if RunManager.pending_act_complete:
		card_choices = CardPool.get_boss_reward_choices(RngManager.loot_rng, reward_count)
	else:
		card_choices = CardPool.get_reward_choices(RngManager.loot_rng, reward_count)
	_build_ui()


# ============================================================
# UI
# ============================================================

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
	float vig = smoothstep(0.3, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vig * 0.5);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	margin.add_child(vbox)

	# Header with entrance animation
	var title = Label.new()
	title.text = "Victory!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	title.modulate.a = 0.0
	title.scale = Vector2(0.5, 0.5)
	title.pivot_offset = Vector2(960, 24)
	vbox.add_child(title)

	var title_tween = create_tween().set_parallel(true)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.5)
	title_tween.tween_property(title, "scale", Vector2.ONE, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Gold reward
	if gold_earned > 0:
		var gold_lbl = Label.new()
		gold_lbl.text = "+%d Gold (Total: %d)" % [gold_earned, RunManager.gold]
		gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gold_lbl.add_theme_font_size_override("font_size", 24)
		gold_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
		vbox.add_child(gold_lbl)

	# Subtitle with passion value + tier (the value drives which pole the reward split
	# favors, so surface the number, not just the tier name).
	var subtitle = Label.new()
	var tier = RunManager.get_passion_tier()
	var tier_name = PassionState.tier_name(tier)
	var passion_value := RunManager.passion.current_value if RunManager.passion else 0
	subtitle.text = "Choose a card. Passion: %d (%s)" % [passion_value, tier_name]
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(subtitle)

	# Card choices
	var card_row = HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 40)
	vbox.add_child(card_row)

	var delay := 0.0
	for card in card_choices:
		var panel = _create_card_panel(card)
		panel.modulate.a = 0.0
		panel.position.y = 40
		card_row.add_child(panel)
		card_panels[card] = panel
		var t = create_tween().set_parallel(true)
		t.tween_property(panel, "modulate:a", 1.0, 0.24).set_delay(delay + 0.1)
		t.tween_property(panel, "position:y", 0, 0.24).set_delay(delay + 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		delay += 0.08

	# Skip button
	var skip_btn = Button.new()
	skip_btn.text = "Skip Reward"
	skip_btn.custom_minimum_size = Vector2(200, 50)
	skip_btn.add_theme_font_size_override("font_size", 18)
	skip_btn.pressed.connect(_on_skip)
	vbox.add_child(skip_btn)

	# Bottom info
	var info_bar = HBoxContainer.new()
	info_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	info_bar.add_theme_constant_override("separation", 40)
	vbox.add_child(info_bar)

	var deck_lbl = Label.new()
	deck_lbl.text = "Deck: %d cards" % RunManager.current_deck.size()
	deck_lbl.add_theme_font_size_override("font_size", 16)
	deck_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	info_bar.add_child(deck_lbl)

	var hp_lbl = Label.new()
	hp_lbl.text = "HP: %d / %d" % [RunManager.current_hp, RunManager.max_hp]
	hp_lbl.add_theme_font_size_override("font_size", 16)
	hp_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	info_bar.add_child(hp_lbl)

	var gold_total = Label.new()
	gold_total.text = "Gold: %d" % RunManager.gold
	gold_total.add_theme_font_size_override("font_size", 16)
	gold_total.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	info_bar.add_child(gold_total)


# ============================================================
# CARD PANEL
# ============================================================

func _create_card_panel(card: CardData) -> PanelContainer:
	var panel := CardFace.build(card, null, CardSigil.build(card))

	# Make all children pass clicks through to the panel
	_ignore_mouse_recursive(panel.get_child(0))

	# Click handler: a left click takes the card, a right click opens it enlarged.
	panel.gui_input.connect(_on_card_input.bind(card))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Hover animation
	panel.mouse_entered.connect(func():
		var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(panel, "scale", Vector2(1.06, 1.06), 0.12)
	)
	panel.mouse_exited.connect(func():
		var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(panel, "scale", Vector2.ONE, 0.12)
	)

	return panel



func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)


func _on_card_input(event: InputEvent, card: CardData) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_open_inspect(card)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_pick_card(card)


## The card enlarged, with its rarity, flavor and keyword reminders; any click closes it.
func _open_inspect(card: CardData) -> void:
	_close_inspect()
	_inspect = CardInspect.build(card, CardFace.build(card, null, CardSigil.build(card)), _close_inspect)
	add_child(_inspect)


func _close_inspect() -> void:
	if is_instance_valid(_inspect):
		_inspect.queue_free()
	_inspect = null


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_inspect):
		_close_inspect()
		get_viewport().set_input_as_handled()


func _pick_card(card: CardData) -> void:
	AudioManager.play_sfx("button_click")
	RunManager.add_card_to_deck(card)
	_return_to_map()


func _on_skip() -> void:
	AudioManager.play_sfx("button_click")
	_return_to_map()


func _return_to_map() -> void:
	if RunManager.pending_act_complete:
		# Camelot act bosses with Excalibur in hand trigger the Crown decision
		# before standard act progression. Other realms (and Camelot without
		# Excalibur) skip straight to the act transition.
		if RunManager.current_realm_id == &"camelot" and RunManager.has_excalibur():
			SceneTransition.change_scene("res://scenes/camelot/crown_decision_scene.tscn")
		else:
			SceneTransition.change_scene("res://scenes/act/act_transition_scene.tscn")
	else:
		SceneTransition.change_scene("res://scenes/map/map_scene.tscn")
