class_name PassionInfographic
extends Control
## Passion zones reference.
##   • HOVER the combat Passion readout → a quick OVERVIEW: the five tiers, what each
##     does, and where you stand.
##   • CLICK it (or use the deck screen's "Passion Zones" button) → the full PAGE:
##     HOVER a zone to preview its cards on the right, or CLICK a zone to PIN it; the
##     right pane then stays on that zone until you click another. Cards render as full
##     cards (art and all) with the zone's damage change shown.
##
## Reads run-persistent state (RunManager.passion + current_deck). The zone modifier:
## extremes ±25% on/off-type; the mid-leans (Inspired/Wavering) a graduated ±12%; the
## dispassionate center (Steady) is flat: that's the generalist pool.

const TIER_ORDER := [
	PassionState.Tier.BLAZING, PassionState.Tier.INSPIRED, PassionState.Tier.STEADY,
	PassionState.Tier.WAVERING, PassionState.Tier.HOLLOW,
]

# --- full-page instance state (the modal is an instance so it can hold the pin) ---
var _ctx: Dictionary
var _pinned_tier: int
var _flow: HFlowContainer
var _right_title: Label
var _rows: Dictionary = {}  # tier -> PanelContainer


static func _tier_color(tier: int) -> Color:
	# Warm (fiery, +Passion primary pole) → cool (cold, -Passion secondary pole).
	match tier:
		PassionState.Tier.BLAZING: return Color(0.95, 0.45, 0.15)
		PassionState.Tier.INSPIRED: return Color(0.9, 0.66, 0.32)
		PassionState.Tier.STEADY: return Color(0.62, 0.62, 0.64)
		PassionState.Tier.WAVERING: return Color(0.45, 0.62, 0.86)
		PassionState.Tier.HOLLOW: return Color(0.4, 0.48, 0.85)
	return Color.WHITE


## The pole a tier favors, and the damage multiplier it applies to that pole's cards.
## Extremes buff ×1.25; the mid-leans give the graduated ×1.12; center is flat and
## shows the neutral/generalist pool.
static func _tier_focus(tier: int) -> Dictionary:
	match tier:
		PassionState.Tier.BLAZING:
			return {"pole": CardData.PersonalityType.PRIMARY, "mult": CombatEngine.ZONE_EXTREME_BONUS}
		PassionState.Tier.INSPIRED:
			return {"pole": CardData.PersonalityType.PRIMARY, "mult": CombatEngine.ZONE_LEAN_BONUS}
		PassionState.Tier.STEADY:
			return {"pole": CardData.PersonalityType.NEUTRAL, "mult": 1.0}
		PassionState.Tier.WAVERING:
			return {"pole": CardData.PersonalityType.SECONDARY, "mult": CombatEngine.ZONE_LEAN_BONUS}
		PassionState.Tier.HOLLOW:
			return {"pole": CardData.PersonalityType.SECONDARY, "mult": CombatEngine.ZONE_EXTREME_BONUS}
	return {"pole": CardData.PersonalityType.NEUTRAL, "mult": 1.0}


## Current Passion state + character labels, gathered once per build.
static func _make_ctx() -> Dictionary:
	var value := 0
	if RunManager.passion:
		value = RunManager.passion.current_value
	var chr: CharacterData = RunManager.current_character
	var prim := "Primary"
	var sec := "Secondary"
	var thresholds := [50, 18, -18, -50]
	if chr:
		if chr.primary_personality != "":
			prim = chr.primary_personality
		if chr.secondary_personality != "":
			sec = chr.secondary_personality
		if chr.passion_thresholds.size() >= 4:
			thresholds = chr.passion_thresholds
	return {"value": value, "tier": RunManager.get_passion_tier(),
		"prim": prim, "sec": sec, "thresholds": thresholds}


# ============================================================
# OVERVIEW: combat hover (static, non-interactive)
# ============================================================

static func build_overview_panel() -> PanelContainer:
	var ctx := _make_ctx()
	var panel := _shell()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	root.add_child(_header(ctx))
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for t in TIER_ORDER:
		bar.add_child(_make_zone_row(ctx, t))
	root.add_child(bar)

	var hint := Label.new()
	hint.text = "Click Passion for your cards by zone →"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	root.add_child(hint)
	return panel


# ============================================================
# FULL PAGE: click / deck-screen button (instance, holds the pin)
# ============================================================

## Opens the full page centered on a dim backdrop. The instance IS the overlay so it
## can hold the pinned-zone state across hovers.
static func open_modal(host: Node) -> Control:
	var inst := PassionInfographic.new()
	host.add_child(inst)
	inst._build_modal()
	return inst


func _build_modal() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			queue_free())
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	_ctx = _make_ctx()
	_pinned_tier = _ctx.tier

	var panel := _shell()
	col.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	root.add_child(_header(_ctx))

	var hint := Label.new()
	hint.text = "Hover a zone to preview · click to pin"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	root.add_child(hint)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	root.add_child(cols)

	# Right pane (built before the bar so its hover/click can drive it).
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	_right_title = Label.new()
	_right_title.add_theme_font_size_override("font_size", 17)
	_right_title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.55))
	right.add_child(_right_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 560)
	# Clamp the card flow to the pane width so cards wrap LEFT→RIGHT (filling the row)
	# instead of stacking in a single column; overflow scrolls vertically.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 10)
	_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_flow)
	right.add_child(scroll)

	# Left: interactive zone bar (hover previews, click pins).
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	for t in TIER_ORDER:
		var row := _make_zone_row(_ctx, t)
		var tier_val: int = t
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.mouse_entered.connect(func(): _preview_zone(tier_val))
		row.mouse_exited.connect(_leave_zone)
		row.gui_input.connect(func(e): _on_row_input(e, tier_val))
		_rows[t] = row
		bar.add_child(row)
	cols.add_child(bar)
	cols.add_child(right)

	_populate_cards(_pinned_tier)
	_restyle_rows(-1)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 40)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 16)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(queue_free)
	col.add_child(close)


func _on_row_input(event: InputEvent, tier: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pinned_tier = tier
		_populate_cards(tier)
		_restyle_rows(-1)


func _preview_zone(tier: int) -> void:
	_populate_cards(tier)
	_restyle_rows(tier)


func _leave_zone() -> void:
	_populate_cards(_pinned_tier)
	_restyle_rows(-1)


## Brightens the hovered row most, the pinned row a little, others normal, so it's
## clear both where the cursor is and which zone is locked in.
func _restyle_rows(hovered: int) -> void:
	for t in _rows:
		var row: PanelContainer = _rows[t]
		if t == hovered:
			row.modulate = Color(1.3, 1.3, 1.3)
		elif t == _pinned_tier:
			row.modulate = Color(1.16, 1.16, 1.16)
		else:
			row.modulate = Color.WHITE


## Fills the right pane with the full cards from the deck that `tier` favors.
func _populate_cards(tier: int) -> void:
	for c in _flow.get_children():
		c.queue_free()

	var focus := _tier_focus(tier)
	var pole: int = focus.pole
	var mult: float = focus.mult
	var pole_name := "Flexible / Neutral"
	if pole == CardData.PersonalityType.PRIMARY:
		pole_name = "%s (Primary)" % _ctx.prim
	elif pole == CardData.PersonalityType.SECONDARY:
		pole_name = "%s (Secondary)" % _ctx.sec
	var suffix := ("  +%d%% damage" % roundi((mult - 1.0) * 100.0)) if mult > 1.0 else ""
	var pin_tag := "  (pinned)" if tier == _pinned_tier else ""
	_right_title.text = "%s: %s cards%s%s" % [PassionState.tier_name(tier), pole_name, suffix, pin_tag]

	var deck: Array = RunManager.current_deck if RunManager.current_deck else []
	var found := false
	for card in deck:
		if _card_in_pole(card, pole):
			_flow.add_child(CardVisuals.render_full(card, mult))
			found = true
	if not found:
		var none := Label.new()
		none.text = "No %s cards in your deck yet." % pole_name
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
		_flow.add_child(none)


static func _card_in_pole(card: CardData, pole: int) -> bool:
	if pole == CardData.PersonalityType.NEUTRAL:
		# The center's "matching" bucket = everything not committed to a pole.
		return card.personality == CardData.PersonalityType.NEUTRAL \
			or card.personality == CardData.PersonalityType.NEGATIVE
	return card.personality == pole


# ============================================================
# SHARED PIECES
# ============================================================

static func _shell() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.075, 0.07, 0.98)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.55, 0.3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func _header(ctx: Dictionary) -> Label:
	var header := Label.new()
	header.text = "⚡ Passion   %d  (%s)" % [ctx.value, PassionState.tier_name(ctx.tier)]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", _tier_color(ctx.tier).lightened(0.2))
	return header


## One zone-bar row (range + effect text), marking the current tier with ▶. Child
## controls ignore the mouse so the row itself receives hover/click on the full page.
static func _make_zone_row(ctx: Dictionary, t: int) -> PanelContainer:
	var prim: String = ctx.prim
	var sec: String = ctx.sec
	var thresholds: Array = ctx.thresholds
	var here: bool = t == ctx.tier
	var lean_pct := roundi((CombatEngine.ZONE_LEAN_BONUS - 1.0) * 100.0)
	var ext_pct := roundi((CombatEngine.ZONE_EXTREME_BONUS - 1.0) * 100.0)

	var ranges := {
		PassionState.Tier.BLAZING: "%d+" % thresholds[0],
		PassionState.Tier.INSPIRED: "%d…%d" % [thresholds[1], thresholds[0] - 1],
		PassionState.Tier.STEADY: "%d…%d" % [thresholds[2], thresholds[1] - 1],
		PassionState.Tier.WAVERING: "%d…%d" % [thresholds[3], thresholds[2] - 1],
		PassionState.Tier.HOLLOW: "<%d" % thresholds[3],
	}
	var effects := {
		PassionState.Tier.BLAZING: "%s +%d%%   ·   %s −%d%%" % [prim, ext_pct, sec, ext_pct],
		PassionState.Tier.INSPIRED: "%s +%d%%   ·   %s −%d%%  (leaning)" % [prim, lean_pct, sec, lean_pct],
		PassionState.Tier.STEADY: "balanced: the generalist's pool (no zone modifier)",
		PassionState.Tier.WAVERING: "%s +%d%%   ·   %s −%d%%  (leaning)" % [sec, lean_pct, prim, lean_pct],
		PassionState.Tier.HOLLOW: "%s +%d%%   ·   %s −%d%%" % [sec, ext_pct, prim, ext_pct],
	}

	var row := PanelContainer.new()
	var col := _tier_color(t)
	var rs := StyleBoxFlat.new()
	rs.set_corner_radius_all(5)
	rs.bg_color = col.darkened(0.55) if not here else col.darkened(0.2)
	rs.set_border_width_all(3 if here else 1)
	rs.border_color = col.lightened(0.3) if here else col.darkened(0.15)
	rs.content_margin_left = 10
	rs.content_margin_right = 10
	rs.content_margin_top = 5
	rs.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", rs)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var name_lbl := Label.new()
	name_lbl.text = ("▶ " if here else "   ") + PassionState.tier_name(t)
	name_lbl.custom_minimum_size = Vector2(110, 0)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1) if here else Color(0.8, 0.8, 0.82))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(name_lbl)

	var range_lbl := Label.new()
	range_lbl.text = ranges[t]
	range_lbl.custom_minimum_size = Vector2(72, 0)
	range_lbl.add_theme_font_size_override("font_size", 14)
	range_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.75))
	range_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(range_lbl)

	var eff_lbl := Label.new()
	eff_lbl.text = effects[t]
	eff_lbl.add_theme_font_size_override("font_size", 14)
	eff_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85) if here else Color(0.68, 0.68, 0.7))
	eff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(eff_lbl)

	return row
