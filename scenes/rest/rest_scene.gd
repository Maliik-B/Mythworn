extends Control
## Rest site. Choose to heal 30% max HP or upgrade a card.

var main_vbox: VBoxContainer
var info_label: Label
var choice_container: HBoxContainer
var deck_container: Control
var titles_overlay: Control


func _ready() -> void:
	_build_ui()
	AudioManager.play_music("rest")


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.12, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Warm vignette for rest
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
	COLOR = vec4(0.0, 0.02, 0.0, vig * 0.5);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)

	main_vbox = VBoxContainer.new()
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 30)
	margin.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "Rest Site"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	main_vbox.add_child(title)

	# HP display
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 22)
	info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(info_label)
	_update_info()

	# The two rest actions — one of these ends the rest.
	choice_container = HBoxContainer.new()
	choice_container.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_container.add_theme_constant_override("separation", 40)
	main_vbox.add_child(choice_container)

	var heal_amount = int(RunManager.max_hp * 0.3)
	_add_choice_button("Rest", "Heal %d HP (30%%)" % heal_amount,
		Color(0.3, 0.8, 0.4), _on_heal)

	var has_upgradable = _get_upgradable_cards().size() > 0
	var upgrade_btn = _add_choice_button("Smith", "Upgrade a card",
		Color(0.9, 0.6, 0.2), _on_upgrade)
	if not has_upgradable:
		upgrade_btn.modulate = Color(0.4, 0.4, 0.4)
		upgrade_btn.disabled = true

	# Free side-actions, set apart below the two rest choices so it's clear they
	# don't consume the rest: manage titles and peek at the map. Banners and the
	# map view can both be used freely, then you still get to Rest or Smith.
	var free_caption = Label.new()
	free_caption.text = "Free — these don't use your rest"
	free_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	free_caption.add_theme_font_size_override("font_size", 14)
	free_caption.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
	main_vbox.add_child(free_caption)

	var free_container = HBoxContainer.new()
	free_container.alignment = BoxContainer.ALIGNMENT_CENTER
	free_container.add_theme_constant_override("separation", 24)
	main_vbox.add_child(free_container)

	var has_titles = RunManager.earned_title_ids.size() > 0
	var banners_btn = _add_free_button("Banners", "Swap your titles",
		Color(0.85, 0.78, 0.45), _on_banners, free_container)
	if not has_titles:
		banners_btn.modulate = Color(0.4, 0.4, 0.4)
		banners_btn.disabled = true

	_add_free_button("View Map", "See your route", Color(0.55, 0.6, 0.85),
		_on_view_map, free_container)

	# Deck section (hidden until upgrade chosen)
	deck_container = VBoxContainer.new()
	deck_container.add_theme_constant_override("separation", 14)
	deck_container.visible = false
	main_vbox.add_child(deck_container)


func _update_info() -> void:
	info_label.text = "HP: %d / %d" % [RunManager.current_hp, RunManager.max_hp]


func _add_choice_button(title_text: String, desc_text: String,
		color: Color, callback: Callable) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(280, 120)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(callback)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.bg_color = color.darkened(0.7)
	style.border_color = color
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = color.darkened(0.5)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.8)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.16, 0.14, 0.2)
	disabled_style.border_color = Color(0.3, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# Build label content manually since Button only supports single-line text
	btn.text = "%s\n%s" % [title_text, desc_text]

	choice_container.add_child(btn)
	return btn


## Compact button for the free side-actions (Banners / View Map). Same visual
## language as the rest choices but smaller, so they read as secondary and
## clearly outside the two rest options above.
func _add_free_button(title_text: String, desc_text: String,
		color: Color, callback: Callable, parent: HBoxContainer) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(200, 74)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(callback)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.bg_color = color.darkened(0.72)
	style.border_color = color.darkened(0.1)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = color.darkened(0.55)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.82)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.16, 0.14, 0.2)
	disabled_style.border_color = Color(0.3, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.text = "%s\n%s" % [title_text, desc_text]

	parent.add_child(btn)
	return btn


func _on_view_map() -> void:
	MapPreviewOverlay.open(self)


# ============================================================
# HEAL
# ============================================================

func _on_heal() -> void:
	var heal_amount = int(RunManager.max_hp * 0.3)
	RunManager.heal(heal_amount)
	AudioManager.play_sfx("heal")
	info_label.text = "Healed %d HP! (HP: %d / %d)" % [
		heal_amount, RunManager.current_hp, RunManager.max_hp]
	info_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	_show_done()


# ============================================================
# UPGRADE
# ============================================================

func _on_upgrade() -> void:
	var upgradable = _get_upgradable_cards()
	if upgradable.size() == 0:
		info_label.text = "No cards to upgrade!"
		return

	choice_container.visible = false
	info_label.text = "Choose a card to upgrade"
	deck_container.visible = true

	for child in deck_container.get_children():
		child.queue_free()

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 320
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_container.add_child(scroll)

	var card_row = HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 20)
	scroll.add_child(card_row)

	for i in RunManager.current_deck.size():
		var card = RunManager.current_deck[i]
		if card.upgraded:
			continue
		var panel = _create_upgrade_card(card, i)
		card_row.add_child(panel)

	# Back button
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(160, 45)
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_btn.pressed.connect(_on_upgrade_back)
	deck_container.add_child(back_btn)
	# Center the back button
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _get_upgradable_cards() -> Array[CardData]:
	var result: Array[CardData] = []
	for card in RunManager.current_deck:
		if not card.upgraded:
			result.append(card)
	return result


func _create_upgrade_card(card: CardData, index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 280)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12

	match card.card_type:
		CardData.CardType.ATTACK:
			style.bg_color = Color(0.3, 0.12, 0.1)
			style.border_color = Color(0.9, 0.25, 0.2)
		CardData.CardType.SKILL:
			style.bg_color = Color(0.1, 0.14, 0.3)
			style.border_color = Color(0.25, 0.45, 0.9)
		CardData.CardType.POWER:
			style.bg_color = Color(0.28, 0.24, 0.08)
			style.border_color = Color(0.9, 0.75, 0.15)

	# Upgraded card green border tint
	if card.upgraded:
		style.border_color = style.border_color.lerp(Color(0.3, 0.9, 0.3), 0.5)

	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Cost
	var cost_lbl = Label.new()
	cost_lbl.text = str(card.energy_cost)
	cost_lbl.add_theme_font_size_override("font_size", 24)
	cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.3))
	vbox.add_child(cost_lbl)

	# Name
	var name_lbl = Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Current description
	var desc_lbl = Label.new()
	desc_lbl.text = card.get_generated_description()
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	# Arrow
	var arrow = Label.new()
	arrow.text = ">> Upgrade >>"
	arrow.add_theme_font_size_override("font_size", 14)
	arrow.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(arrow)

	# Preview upgraded description
	var preview = card.duplicate_card()
	preview.upgrade_card()
	var preview_lbl = Label.new()
	preview_lbl.text = preview.get_generated_description()
	preview_lbl.add_theme_font_size_override("font_size", 14)
	preview_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	preview_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(preview_lbl)

	_ignore_mouse_recursive(vbox)

	panel.gui_input.connect(_on_upgrade_card_input.bind(index))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel


func _on_upgrade_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_upgrade_card(index)


func _on_upgrade_back() -> void:
	deck_container.visible = false
	choice_container.visible = true
	_update_info()
	info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))


func _upgrade_card(index: int) -> void:
	var card = RunManager.current_deck[index]
	card.upgrade_card()
	AudioManager.play_sfx("card_upgrade")
	info_label.text = "Upgraded %s!" % card.card_name
	info_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	deck_container.visible = false
	_show_done()


# ============================================================
# DONE
# ============================================================

func _show_done() -> void:
	choice_container.visible = false

	var leave_btn = Button.new()
	leave_btn.text = "Continue"
	leave_btn.custom_minimum_size = Vector2(200, 55)
	leave_btn.add_theme_font_size_override("font_size", 20)
	leave_btn.pressed.connect(_on_leave)
	main_vbox.add_child(leave_btn)


func _on_leave() -> void:
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)


# ============================================================
# BANNERS (Title Swap)
# ============================================================

## Open the title-swap modal. Doesn't end the rest — the player can still heal
## or upgrade after managing their titles. Modal reuses styling from the map's
## titles popup but adds interactive equip/unequip buttons per card.
func _on_banners() -> void:
	if titles_overlay:
		return
	_build_titles_overlay()


func _build_titles_overlay() -> void:
	# Full-screen dim backdrop
	titles_overlay = Control.new()
	titles_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	titles_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(titles_overlay)

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	titles_overlay.add_child(dim)

	# Center panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 600)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = -panel.custom_minimum_size / 2.0
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.08, 0.13, 0.98)
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.55, 0.5, 0.35)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	titles_overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "Manage Banners"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	vbox.add_child(header)

	var subtitle = Label.new()
	subtitle.text = "Swap which titles you wear. Effects update instantly."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	vbox.add_child(subtitle)

	# Build the actual interactive content
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	vbox.add_child(content)
	_populate_titles_overlay_content(content)

	# Close button
	var close = Button.new()
	close.text = "Done"
	close.custom_minimum_size = Vector2(160, 42)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 18)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close_titles_overlay)
	vbox.add_child(close)


func _populate_titles_overlay_content(parent: VBoxContainer) -> void:
	# Equipped slots
	var slots_header = Label.new()
	slots_header.text = "─── Equipped ───"
	slots_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slots_header.add_theme_font_size_override("font_size", 14)
	slots_header.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
	parent.add_child(slots_header)

	var slot_row = HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 16)
	parent.add_child(slot_row)
	for slot in range(RunManager.TITLE_SLOT_COUNT):
		slot_row.add_child(_build_swap_slot_card(slot))

	# Bench
	var unequipped: Array = []
	for id in RunManager.earned_title_ids:
		if not (id in RunManager.active_title_slots):
			unequipped.append(id)

	var bench_header = Label.new()
	bench_header.text = "─── Earned (not equipped) ───"
	bench_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench_header.add_theme_font_size_override("font_size", 14)
	bench_header.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
	parent.add_child(bench_header)

	if unequipped.size() == 0:
		var empty = Label.new()
		empty.text = "All earned titles equipped."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color(0.45, 0.42, 0.4))
		parent.add_child(empty)
		return

	var bench_row = HBoxContainer.new()
	bench_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bench_row.add_theme_constant_override("separation", 12)
	parent.add_child(bench_row)
	for id in unequipped:
		bench_row.add_child(_build_swap_bench_card(id))


func _build_swap_slot_card(slot: int) -> PanelContainer:
	var id: StringName = RunManager.active_title_slots[slot]
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 170)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var slot_label = Label.new()
	slot_label.text = "Slot %d" % (slot + 1)
	slot_label.add_theme_font_size_override("font_size", 12)
	slot_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	vbox.add_child(slot_label)

	if id == &"":
		style.bg_color = Color(0.1, 0.09, 0.14)
		style.border_color = Color(0.25, 0.22, 0.3)
		panel.add_theme_stylebox_override("panel", style)
		var empty = Label.new()
		empty.text = "— empty —"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
		vbox.add_child(empty)
		return panel

	var data: TitleData = TitlePool.get_title(id)
	var tier: TitleData.Tier = RunManager.get_title_tier(id)
	style.bg_color = Color(0.12, 0.1, 0.18)
	style.border_color = data.accent_color
	panel.add_theme_stylebox_override("panel", style)

	var name_lbl = Label.new()
	name_lbl.text = data.get_name_for_tier(tier)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", data.accent_color)
	vbox.add_child(name_lbl)

	if data.is_realm_title():
		var tier_lbl = Label.new()
		var tier_str := ""
		match tier:
			TitleData.Tier.ORIGINAL: tier_str = "● ORIGINAL"
			TitleData.Tier.DEGRADED: tier_str = "○ DEGRADED"
			TitleData.Tier.RETURNING: tier_str = "◐ RETURNING"
		tier_lbl.text = tier_str
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
		vbox.add_child(tier_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = data.get_description_for_tier(tier)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	var unequip = Button.new()
	unequip.text = "Unequip"
	unequip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	unequip.custom_minimum_size = Vector2(120, 30)
	unequip.add_theme_font_size_override("font_size", 13)
	unequip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	unequip.pressed.connect(_on_unequip_slot.bind(slot))
	vbox.add_child(unequip)
	return panel


func _build_swap_bench_card(id: StringName) -> PanelContainer:
	var data: TitleData = TitlePool.get_title(id)
	var tier: TitleData.Tier = RunManager.get_title_tier(id)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 170)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.7)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = data.accent_color.darkened(0.4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var name_lbl = Label.new()
	name_lbl.text = data.get_name_for_tier(tier)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", data.accent_color.darkened(0.2))
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = data.get_description_for_tier(tier)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	# Equip buttons
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	for slot in range(RunManager.TITLE_SLOT_COUNT):
		var btn = Button.new()
		btn.text = "→ Slot %d" % (slot + 1)
		btn.custom_minimum_size = Vector2(96, 28)
		btn.add_theme_font_size_override("font_size", 12)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_equip_to_slot.bind(id, slot))
		btn_row.add_child(btn)
	return panel


func _on_unequip_slot(slot: int) -> void:
	RunManager.equip_title(slot, &"")
	_refresh_titles_overlay()


func _on_equip_to_slot(id: StringName, slot: int) -> void:
	RunManager.equip_title(slot, id)
	_refresh_titles_overlay()


func _refresh_titles_overlay() -> void:
	if not titles_overlay:
		return
	# Rebuild in place — find the content VBox by tag traversal
	# Simpler: tear down and reopen.
	_close_titles_overlay()
	_build_titles_overlay()


func _close_titles_overlay() -> void:
	if titles_overlay:
		titles_overlay.queue_free()
		titles_overlay = null
	_update_info()
