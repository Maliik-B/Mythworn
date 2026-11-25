class_name ArtifactsOverlay
extends Control
## Read-only review of the artifacts the player already carries, relics and titles,
## so they can plan shop purchases around what they own (no duplicate relics, spot
## synergies, see which titles are working). Openable from any scene; it never mutates
## state and, unlike the rest scene's titles overlay, carries no equip/unequip controls.

const PANEL_W := 920.0
const PANEL_H := 700.0


## Builds the overlay, parents it to `host`, and returns it. Clicking the dim backdrop
## or the Close button tears it down.
static func open(host: Node) -> ArtifactsOverlay:
	var overlay := ArtifactsOverlay.new()
	host.add_child(overlay)
	overlay._build()
	return overlay


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Fill the viewport immediately: anchor-based full-rect sizing only resolves on the
	# next layout pass, and until then the overlay is a zero-size box in the corner,
	# which would confine the dim backdrop and the centered panel there too.
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dim backdrop: clicking it closes the review.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_input)
	add_child(dim)

	var panel := PanelContainer.new()
	# Center reliably regardless of layout timing: middle anchors + fixed half-size
	# offsets, growing both ways.
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W / 2.0
	panel.offset_top = -PANEL_H / 2.0
	panel.offset_right = PANEL_W / 2.0
	panel.offset_bottom = PANEL_H / 2.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.12, 0.98)
	panel_style.set_corner_radius_all(10)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.5, 0.45, 0.32)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Your Artifacts"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	vbox.add_child(header)

	var subtitle := Label.new()
	subtitle.text = "What you already carry. Plan your purchases around it."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	vbox.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	_build_relics_section(content)
	_build_titles_section(content)
	add_child(HoverNote.new())  # a relic's keywords, on hover

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 42)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 18)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close)
	vbox.add_child(close)


# ============================================================
# RELICS
# ============================================================

func _build_relics_section(parent: VBoxContainer) -> void:
	_section_header(parent, "Relics (%d)" % RunManager.relics.size(), Color(0.7, 0.55, 0.9))
	if RunManager.relics.is_empty():
		_empty_note(parent, "No relics yet. One from these shelves would be your first.")
		return

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(grid)
	for relic in RunManager.relics:
		grid.add_child(_relic_card(relic))


func _relic_card(relic: RelicData) -> PanelContainer:
	var rarity_colors := {
		RelicData.RelicRarity.COMMON: Color(0.6, 0.6, 0.6),
		RelicData.RelicRarity.UNCOMMON: Color(0.3, 0.7, 0.9),
		RelicData.RelicRarity.RARE: Color(0.95, 0.8, 0.2),
		RelicData.RelicRarity.BOSS: Color(0.9, 0.3, 0.3),
	}
	var color: Color = rarity_colors.get(relic.rarity, Color(0.6, 0.6, 0.6))
	# A forgotten relic's tell: dead gold while it sleeps, burnished once it has its name back.
	if relic.is_dormant():
		color = Color(0.6, 0.52, 0.3)
	elif relic.is_woken():
		color = Color(1.0, 0.85, 0.4)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(270, 92)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.11, 0.2)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = color
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = relic.relic_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", color)
	vbox.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = relic.description
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)
	RelicKeywords.mark(panel, relic)
	return panel


# ============================================================
# TITLES
# ============================================================

func _build_titles_section(parent: VBoxContainer) -> void:
	var earned: int = RunManager.earned_title_ids.size()
	var equipped_ids: Array = []
	for sid in RunManager.active_title_slots:
		if sid != &"":
			equipped_ids.append(sid)

	_section_header(parent, "Titles (%d equipped · %d earned)" % [equipped_ids.size(), earned],
		Color(0.85, 0.7, 0.4))

	if earned == 0:
		_empty_note(parent, "No titles yet. Major realm decisions grant titles that shape your identity.")
		return

	if not equipped_ids.is_empty():
		_subheader(parent, "─── Equipped ───")
		var eq_grid := _title_grid()
		parent.add_child(eq_grid)
		for id in equipped_ids:
			eq_grid.add_child(_title_card(id, true))

	var bench: Array = []
	for id in RunManager.earned_title_ids:
		if not (id in RunManager.active_title_slots):
			bench.append(id)
	if not bench.is_empty():
		_subheader(parent, "─── Earned (not equipped) ───")
		var bench_grid := _title_grid()
		parent.add_child(bench_grid)
		for id in bench:
			bench_grid.add_child(_title_card(id, false))


func _title_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return grid


func _title_card(id: StringName, equipped: bool) -> PanelContainer:
	var data: TitleData = TitlePool.get_title(id)
	var tier: TitleData.Tier = RunManager.get_title_tier(id)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 128)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 1.0 if equipped else 0.7)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2 if equipped else 1)
	style.border_color = data.accent_color if equipped else data.accent_color.darkened(0.4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = data.get_name_for_tier(tier)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color",
		data.accent_color if equipped else data.accent_color.darkened(0.3))
	vbox.add_child(name_lbl)

	# Tier marker only matters for realm titles (they degrade with distance).
	if data.is_realm_title():
		var tier_str := ""
		match tier:
			TitleData.Tier.ORIGINAL: tier_str = "● ORIGINAL"
			TitleData.Tier.DEGRADED: tier_str = "○ DEGRADED"
			TitleData.Tier.RETURNING: tier_str = "◐ RETURNING"
		var tier_lbl := Label.new()
		tier_lbl.text = tier_str
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
		vbox.add_child(tier_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = data.get_description_for_tier(tier)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color",
		Color(0.75, 0.72, 0.68) if equipped else Color(0.5, 0.48, 0.45))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)
	return panel


# ============================================================
# SHARED BITS
# ============================================================

func _section_header(parent: VBoxContainer, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)


func _subheader(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
	parent.add_child(lbl)


func _empty_note(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(lbl)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	queue_free()
