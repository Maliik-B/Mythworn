class_name CardFace
extends RefCounted
## The card in the combat hand: one size, fixed zones, so a row of them lines up and nothing
## reflows with the text. Top to bottom: cost, type and school; the name; a slab with the hit after
## Passion, in a numeral big enough to read when the rules cannot be; the rules; and a foot with the
## Passion sentence and Exhaust. A card with no number (a Power, a draw) has no slab and gives the
## room to its rules. No word is written here: CardData.get_face_text only says which zone each
## sentence sits in.
##
## The band is one level line: the cost coin and the school coin sit at the same height, the same
## distance in from either edge, with the type centred between them. A card with no school coin
## gets a faint empty one, so every band is the same shape. Rarity, flavor and keyword reminders are
## not on the face; the inspect view (CardInspect) shows them.

const SIZE := Vector2(200, 290)

# The one place the faces name their fonts, so trying another is a one-line change.
const TITLE_FONT_PATH := "res://assets/fonts/grenze_gotisch/GrenzeGotisch-Bold.tres"
const RULES_FONT_PATH := "res://assets/fonts/eb_garamond/EBGaramond-Variable.ttf"
const NUMERAL_FONT_PATH := "res://assets/fonts/castoro_titling/CastoroTitling-Regular.ttf"  # the slab's numeral and the cost coin

const INSET := 12.0
const HEADER_H := 40.0
const SCHOOL_COIN_W := 46.0  # the school coin's place in the header's right corner
const NAME_Y := 40.0
const NAME_H := 46.0
const SLAB_Y := 86.0
const SLAB_H := 66.0
const EMBLEM := 36.0  # the slab's icon, and the gap to the numeral: one unit, centred on the slab
const UNIT_GAP := 10.0
const COIN := 32.0  # the cost coin and the school coin are the same disc
const COIN_INSET := 25.0  # a coin's centre, in from the card's edge
const COIN_Y := 24.0  # and down from its top
const RULES_GAP := 6.0
const FOOT_H := 28.0
const FOOT_H_TRICK := 44.0  # a Trick's reminder runs to two lines
const RULES_SIZE := 18
const RULES_SIZE_TIGHT := 16
const RULES_LINE_SPACING := -2
const NUMBER_SIZE := 50
const MAX_PIPS := 4

const NAME_SIZE := 28
const NAME_SIZE_MIN := 20
const KIND_SIZE := 13

const TYPE_NAMES := ["Attack", "Skill", "Power"]
const RARITY_NAMES := ["Starter", "Common", "Uncommon", "Rare"]  # the inspect view's
const RARITY_COLORS := ["card_dim", "card_dim", "card_uncommon", "card_rare"]

const NUMBER_GLOW := preload("res://assets/ui/card_number_glow.tres")


## A card's face. `source` is the player's stats in combat, so its numbers are what a hit will land
## for; null outside combat, which shows the printed numbers. `sigil` is the school coin, built by
## the caller because the live Passion zone it reflects belongs to combat.
static func build(card: CardData, source: CombatantStats, sigil: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SIZE
	panel.pivot_offset = SIZE / 2.0
	var style := _card_style(card)
	panel.add_theme_stylebox_override("panel", style)
	if card.unplayable:
		panel.modulate = Color(0.85, 0.85, 0.85)

	var zones := Control.new()
	panel.add_child(zones)
	_add_inset(zones)
	_add_header(zones, card, sigil)
	_add_name(zones, card)

	var text := card.get_face_text(source)
	var slab_value := _slab_value(card, source, null)
	var rules_top := NAME_Y + NAME_H
	if not slab_value.is_empty():
		_add_slab(zones, card, style, slab_value)
		rules_top = SLAB_Y + SLAB_H + RULES_GAP

	var foot_h := FOOT_H_TRICK if text["trick"] != "" else FOOT_H
	var foot_top := SIZE.y - foot_h - 2.0

	var rules := Label.new()
	rules.name = "CardDesc"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.position = Vector2(INSET, rules_top)
	rules.size = Vector2(SIZE.x - INSET * 2.0, foot_top - rules_top - 2.0)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.add_theme_font_override("font", load(RULES_FONT_PATH))
	rules.add_theme_color_override("font_color", StageSkin.c("card_ink"))
	rules.add_theme_constant_override("line_spacing", RULES_LINE_SPACING)
	zones.add_child(rules)
	_set_rules(rules, text["rules"])

	_add_foot(zones, card, style, text, foot_top)
	return panel


## Re-reads the numbers against a target, for a card being dragged: the rules' bracket and the
## slab both show what the hit would land for on that enemy, and go back with no target.
static func show_target(panel: PanelContainer, card: CardData, source: CombatantStats, target: CombatantStats) -> void:
	var rules: Label = panel.find_child("CardDesc", true, false)
	if rules:
		_set_rules(rules, card.get_face_text(source, target)["rules"])
	var number: Label = panel.find_child("SlabNumber", true, false)
	if number:
		_apply_number(number, panel.find_child("SlabGlow", true, false), _slab_value(card, source, target))


## "attack", "skill", "power" or "curse": which of the look's colours a card takes.
static func _colour_key(card: CardData) -> String:
	# Unplayable curses read as sickly and dead: they only clog a hand slot.
	if card.unplayable:
		return "curse"
	return ["attack", "skill", "power"][card.card_type]


static func _card_style(card: CardData) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var key := _colour_key(card)
	style.set_corner_radius_all(0 if StageSkin.is_page() else 10)
	style.set_border_width_all(2 if StageSkin.is_page() else 3)
	# The zones are laid out in the card's own 200x290, so the border takes no room from them: with
	# the border's width as margin every zone sat 2 px right of where it was placed, and the band was
	# 14 px in from the left edge and 10 from the right.
	style.set_content_margin_all(0)
	style.bg_color = StageSkin.c("card_bg_" + key)
	style.border_color = StageSkin.c("card_edge_" + key)
	if card.upgraded:
		style.border_color = style.border_color.lerp(Color(0.3, 0.9, 0.3), 0.5)
	return style


## A leaf's inner rule, in a look that has one.
static func _add_inset(zones: Control) -> void:
	var color := StageSkin.c("card_inset")
	if color.a <= 0.0:
		return
	var inset := Panel.new()
	inset.position = Vector2(5, 5)
	inset.size = SIZE - Vector2(10, 10)
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(1)
	style.border_color = color
	inset.add_theme_stylebox_override("panel", style)
	zones.add_child(inset)


## The rules inside a card, between its slab and its foot.
static func _rule_color(card_style: StyleBoxFlat) -> Color:
	var color := StageSkin.c("card_inset")
	return color if color.a > 0.0 else card_style.border_color.darkened(0.3)


static func _add_header(zones: Control, card: CardData, sigil: Control) -> void:
	var half := COIN / 2.0
	var coin := Panel.new()
	coin.name = "CostCoin"
	coin.position = Vector2(COIN_INSET - half, COIN_Y - half)
	coin.size = Vector2(COIN, COIN)
	var coin_style := StyleBoxFlat.new()
	coin_style.set_corner_radius_all(int(half))
	coin_style.bg_color = StageSkin.c("card_coin_" + _colour_key(card))
	coin_style.set_border_width_all(2)
	coin_style.border_color = StageSkin.c("card_coin_edge")
	if coin_style.border_color.a <= 0.0:
		coin_style.border_color = coin_style.bg_color
	coin.add_theme_stylebox_override("panel", coin_style)
	zones.add_child(coin)
	var cost := Label.new()
	cost.text = card.cost_label()
	cost.size = coin.size
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cost_font: Font = load(NUMERAL_FONT_PATH)
	cost.add_theme_font_override("font", cost_font)
	cost.add_theme_font_size_override("font_size", NodeFace.COIN_COST_FONT)
	cost.add_theme_color_override("font_color", StageSkin.c("card_coin_text"))
	coin.add_child(cost)
	# The numeral is set by what it inks, not by its line: a "1" sat 2.5 px high in this coin.
	NodeFace.centre_glyph(cost.text, cost_font, NodeFace.COIN_COST_FONT, coin.size,
		func(shift: Vector2) -> void:
			if is_instance_valid(cost):
				cost.position = shift)

	# The school coin's place, mirrored: an empty ring under whatever sits there, so a card with no
	# school (a Power, a Trick) still ends its band the way the others do.
	var school_centre := Vector2(SIZE.x - COIN_INSET, COIN_Y)
	var ring := Panel.new()
	ring.name = "SchoolRing"
	ring.position = school_centre - Vector2(half, half)
	ring.size = Vector2(COIN, COIN)
	var ring_style := StyleBoxFlat.new()
	ring_style.draw_center = false
	ring_style.set_corner_radius_all(int(half))
	ring_style.set_border_width_all(2)
	var ring_colour := StageSkin.c("card_dim")
	ring_style.border_color = Color(ring_colour.r, ring_colour.g, ring_colour.b, 0.4)
	ring.add_theme_stylebox_override("panel", ring_style)
	zones.add_child(ring)

	var kind := Label.new()
	kind.name = "CardKind"
	kind.text = _kind_line(card)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kind.add_theme_font_override("font", load(RULES_FONT_PATH))
	kind.add_theme_font_size_override("font_size", KIND_SIZE)
	kind.add_theme_color_override("font_color", StageSkin.c("card_dim"))
	# Clipped so its first measure, in the default font before the override reaches it, cannot
	# widen the label and pull the text off centre. It spans the card, so its middle is the card's.
	kind.clip_text = true
	kind.position = Vector2(0, COIN_Y - 24.0)
	kind.size = Vector2(SIZE.x, 48.0)
	zones.add_child(kind)

	if sigil:
		var holder := Control.new()
		holder.name = "SchoolCoin"
		var box := NodeFace.COIN_SCHOOL_BOX
		holder.position = school_centre - box / 2.0
		holder.size = box
		sigil.size = box
		holder.add_child(sigil)
		zones.add_child(holder)


## The type alone, "Attack": rarity and the Trick keyword are not the band's (the Trick's reminder is
## in the foot, and the inspect view carries the rarity). A memory card says so.
static func _kind_line(card: CardData) -> String:
	var kind: String = "Memory" if card.is_memory else TYPE_NAMES[card.card_type]
	return kind if StageSkin.is_page() else kind.to_upper()


## The name, a size smaller or on two lines if it needs them, its initial rubricated in a look that
## does that: red for an attack, lapis for a skill, the logo's own move.
static func _add_name(zones: Control, card: CardData) -> void:
	var font: Font = load(TITLE_FONT_PATH)
	var width := SIZE.x - 16.0
	var font_size := NAME_SIZE
	while font_size > NAME_SIZE_MIN and font and font.get_string_size(card.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 2
	var lines := 1
	if font and font.get_string_size(card.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		lines = 2
	var line_h: float = font.get_height(font_size) - 6.0 if font else 24.0
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.scroll_active = false
	title.clip_contents = false
	title.position = Vector2(8, NAME_Y + (NAME_H - line_h * lines) / 2.0 - 3.0)
	title.size = Vector2(width, line_h * lines + 8.0)
	title.add_theme_font_override("normal_font", font)
	title.add_theme_font_size_override("normal_font_size", font_size)
	title.add_theme_constant_override("line_separation", -6)
	title.add_theme_color_override("default_color", StageSkin.c("card_ink"))
	var rubric := StageSkin.c("card_rubric_" + _colour_key(card))
	if rubric.a > 0.0:
		title.text = "[center][color=#%s]%s[/color]%s[/center]" % [rubric.to_html(false),
			card.card_name.substr(0, 1), card.card_name.substr(1)]
	else:
		title.text = "[center]%s[/center]" % card.card_name
	zones.add_child(title)


## What the slab shows: the card's first damage effect, else its first Block, as the number that
## will land. Empty when it has neither, and a Power never has a slab.
static func _slab_value(card: CardData, source: CombatantStats, target: CombatantStats) -> Dictionary:
	if card.card_type == CardData.CardType.POWER:
		return {}
	var zone := CombatEngine.zone_multiplier(card.personality) if source else 1.0
	for effect in card.get_active_effects():
		if effect is DamageEffect and not effect.apply_to_source:
			var hit: int = effect.modified_value(source, target, zone) if source else effect.value
			var shown := str(hit)
			if effect.x_scaled:
				shown += "×X"
			elif effect.hits > 1:
				shown += "×%d" % effect.hits
			return {"text": shown, "number": hit, "printed": effect.value}
		if effect is BlockEffect:
			var block: int = effect.modified_value(source) if source else effect.value
			return {"text": str(block), "number": block, "printed": effect.value}
	return {}


static func _add_slab(zones: Control, card: CardData, card_style: StyleBoxFlat, value: Dictionary) -> void:
	var slab := Panel.new()
	slab.name = "Slab"
	slab.position = Vector2(INSET, SLAB_Y)
	slab.size = Vector2(SIZE.x - INSET * 2.0, SLAB_H)
	var style := StyleBoxFlat.new()
	style.bg_color = card_style.bg_color if StageSkin.is_page() else card_style.bg_color.darkened(0.38)
	style.set_border_width_all(1)
	style.border_color = _rule_color(card_style)
	slab.add_theme_stylebox_override("panel", style)
	zones.add_child(slab)

	slab.add_child(_make_emblem(card, card_style))

	var glow := TextureRect.new()
	glow.name = "SlabGlow"
	glow.texture = NUMBER_GLOW
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = additive
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	slab.add_child(glow)

	var number := Label.new()
	number.name = "SlabNumber"
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", load(NUMERAL_FONT_PATH))
	number.add_theme_font_size_override("font_size", NUMBER_SIZE)
	slab.add_child(number)
	_apply_number(number, glow, value)


## The icon and the numeral as one unit, a fixed gap apart, centred on the slab. The unit's width
## follows the numeral ("6" or "12×3"), so it is laid out again whenever the text changes.
static func _place_unit(slab: Control) -> void:
	var emblem: Control = slab.get_child(0)
	var glow: Control = slab.find_child("SlabGlow", false, false)
	var number: Label = slab.find_child("SlabNumber", false, false)
	if emblem == null or glow == null or number == null:
		return
	var font: Font = number.get_theme_font("font")
	var width: float = font.get_string_size(number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_SIZE).x
	var left: float = (slab.size.x - (EMBLEM + UNIT_GAP + width)) / 2.0
	emblem.position = Vector2(left, (SLAB_H - EMBLEM) / 2.0)
	emblem.size = Vector2(EMBLEM, EMBLEM)
	number.position = Vector2(left + EMBLEM + UNIT_GAP, 0)
	number.size = Vector2(width, SLAB_H)
	glow.position = Vector2(number.position.x - 8.0, -14.0)
	glow.size = Vector2(width + 16.0, SLAB_H + 28.0)


## Warm and lit when Passion lifts the hit, grey when it cuts it, plain when it leaves it alone.
static func _apply_number(number: Label, glow: Control, value: Dictionary) -> void:
	if value.is_empty():
		return
	number.text = value["text"]
	var up: bool = value["number"] > value["printed"]
	var down: bool = value["number"] < value["printed"]
	number.add_theme_color_override("font_color",
		StageSkin.c("card_number_up") if up else (StageSkin.c("card_number_down") if down else StageSkin.c("card_ink")))
	if glow:
		glow.visible = up and not StageSkin.is_page()
	if number.get_parent() is Control:
		_place_unit(number.get_parent())


## The card's icon if it has one, else the glyph for its type: the same art today's frame carried.
static func _make_emblem(card: CardData, card_style: StyleBoxFlat) -> Control:
	var icon_file := CardVisuals.icon_path(card.card_name)
	if icon_file == "" and card.card_type == CardData.CardType.ATTACK:
		icon_file = CardVisuals.DEFAULT_ATTACK_ICON
	elif icon_file == "" and card.card_type == CardData.CardType.SKILL:
		icon_file = CardVisuals.DEFAULT_SKILL_ICON
	if icon_file != "":
		var icon := TextureRect.new()
		icon.texture = load(icon_file)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.material = StageSkin.icon_material()
		return icon
	var glyph := Label.new()
	glyph.text = "★"
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 24)
	glyph.add_theme_color_override("font_color", StageSkin.c("card_dim") if StageSkin.is_page() else card_style.border_color.lightened(0.3))
	glyph.material = StageSkin.no_purple()
	return glyph


## Sets the rules, a size smaller if they would run into the foot at full size.
static func _set_rules(rules: Label, text: String) -> void:
	rules.text = text
	var font: Font = load(RULES_FONT_PATH)
	var size := RULES_SIZE
	if font and _rules_height(font, text, rules.size.x, RULES_SIZE) > rules.size.y:
		size = RULES_SIZE_TIGHT
	rules.add_theme_font_size_override("font_size", size)


static func _rules_height(font: Font, text: String, width: float, font_size: int) -> float:
	var line_h := font.get_height(font_size)
	var raw := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
	var lines := roundi(raw.y / line_h)
	return lines * (line_h + RULES_LINE_SPACING)


static func _add_foot(zones: Control, card: CardData, card_style: StyleBoxFlat, text: Dictionary, foot_top: float) -> void:
	var rule := ColorRect.new()
	rule.color = _rule_color(card_style)
	rule.position = Vector2(INSET, foot_top)
	rule.size = Vector2(SIZE.x - INSET * 2.0, 1)
	zones.add_child(rule)

	var font: Font = load(RULES_FONT_PATH)
	if text["trick"] != "":
		var reminder := _foot_label(font, 14, StageSkin.c("card_dim"))
		reminder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reminder.text = text["trick"]
		reminder.position = Vector2(INSET, foot_top + 2.0)
		reminder.size = Vector2(SIZE.x - INSET * 2.0, FOOT_H_TRICK - 4.0)
		reminder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reminder.add_theme_constant_override("line_spacing", -2)
		zones.add_child(reminder)
		return

	if text["passion"] != "":
		var warm: bool = text["passion_total"] > 0
		var col := StageSkin.c("card_passion_up") if warm else StageSkin.c("card_passion_down")
		var sentence := _foot_label(font, 15, col)
		sentence.text = text["passion"]
		sentence.position = Vector2(INSET + 2.0, foot_top + 2.0)
		sentence.size = Vector2(SIZE.x - INSET * 2.0, FOOT_H - 4.0)
		zones.add_child(sentence)
		var pips := PassionPips.new()
		pips.count = clampi(absi(text["passion_total"]), 1, MAX_PIPS)
		pips.up = warm
		pips.color = col
		var sentence_w := font.get_string_size(text["passion"], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x if font else 70.0
		pips.position = Vector2(INSET + 2.0 + sentence_w + 6.0, foot_top + 9.0)
		pips.size = Vector2(PassionPips.STEP * MAX_PIPS, 10)
		zones.add_child(pips)

	if card.exhaust:
		var exhaust := _foot_label(font, 15, StageSkin.c("card_dim"))
		exhaust.text = "Exhaust"
		exhaust.position = Vector2(INSET, foot_top + 2.0)
		exhaust.size = Vector2(SIZE.x - INSET * 2.0 - 2.0, FOOT_H - 4.0)
		exhaust.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		zones.add_child(exhaust)


static func _foot_label(font: Font, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


## The Passion lean as small triangles, drawn so they need no glyph from any font.
class PassionPips extends Control:
	const STEP := 11.0
	var count := 1
	var up := true
	var color := Color.WHITE

	func _draw() -> void:
		for i in count:
			var x := i * STEP
			if up:
				draw_colored_polygon(PackedVector2Array([Vector2(x, 9), Vector2(x + 9, 9), Vector2(x + 4.5, 1)]), color)
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(x, 1), Vector2(x + 9, 1), Vector2(x + 4.5, 9)]), color)
