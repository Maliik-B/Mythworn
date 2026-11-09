class_name CardFace
extends RefCounted
## The card in the combat hand: one size, fixed zones, so a row of them lines up and nothing
## reflows with the text. Top to bottom: cost, type and school; the name; a slab with the hit after
## Passion, in a numeral big enough to read when the rules cannot be; the rules; and a foot with the
## Passion sentence and Exhaust. A card with no number (a Power, a draw) has no slab and gives the
## room to its rules. No word is written here: CardData.get_face_text only says which zone each
## sentence sits in.

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
const SLAB_NUMBER_X := 48.0  # the emblem sits to the left of this, the numeral to the right
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
const RARITY_NAMES := ["Starter", "Common", "Uncommon", "Rare"]
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
	inset.position = Vector2(3, 3)
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
	var coin := PanelContainer.new()
	coin.position = Vector2(9, 8)
	coin.size = Vector2(32, 32)
	var coin_style := StyleBoxFlat.new()
	coin_style.set_corner_radius_all(16)
	coin_style.bg_color = StageSkin.c("card_coin_" + _colour_key(card))
	coin_style.set_border_width_all(2)
	coin_style.border_color = StageSkin.c("card_coin_edge")
	if coin_style.border_color.a <= 0.0:
		coin_style.border_color = coin_style.bg_color
	coin.add_theme_stylebox_override("panel", coin_style)
	var cost := Label.new()
	cost.text = card.cost_label()
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_theme_font_override("font", load(NUMERAL_FONT_PATH))
	cost.add_theme_font_size_override("font_size", 21)
	cost.add_theme_color_override("font_color", StageSkin.c("card_coin_text"))
	coin.add_child(cost)
	zones.add_child(coin)

	var kind := Label.new()
	kind.text = _kind_line(card)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kind.add_theme_font_override("font", load(RULES_FONT_PATH))
	kind.add_theme_font_size_override("font_size", KIND_SIZE)
	kind.add_theme_color_override("font_color", StageSkin.c(RARITY_COLORS[card.rarity]))
	# Clipped so its first measure, in the default font before the override reaches it, cannot
	# widen the label and pull the text off centre.
	kind.clip_text = true
	kind.position = Vector2(42, 0)
	kind.size = Vector2(SIZE.x - 42.0 - SCHOOL_COIN_W, HEADER_H + 4.0)
	zones.add_child(kind)

	if sigil:
		var holder := CenterContainer.new()
		holder.position = Vector2(SIZE.x - SCHOOL_COIN_W, 2.0)
		holder.size = Vector2(42, 42)
		holder.add_child(sigil)
		zones.add_child(holder)


## "ATTACK · COMMON". A Trick and a memory card say so, since that is what they are.
static func _kind_line(card: CardData) -> String:
	var kind: String = "Memory" if card.is_memory else TYPE_NAMES[card.card_type]
	var grade: String = "Trick" if card.trick else RARITY_NAMES[card.rarity]
	var line := "%s · %s" % [kind, grade]
	return line if StageSkin.is_page() else line.to_upper()


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
	glow.position = Vector2(SLAB_NUMBER_X + 8.0, -14.0)
	glow.size = Vector2(slab.size.x - SLAB_NUMBER_X - 16.0, SLAB_H + 28.0)
	slab.add_child(glow)

	var number := Label.new()
	number.name = "SlabNumber"
	number.position = Vector2(SLAB_NUMBER_X, 0)
	number.size = Vector2(slab.size.x - SLAB_NUMBER_X, SLAB_H)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_override("font", load(NUMERAL_FONT_PATH))
	number.add_theme_font_size_override("font_size", NUMBER_SIZE)
	slab.add_child(number)
	_apply_number(number, glow, value)


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


## The card's icon if it has one, else the glyph for its type: the same art today's frame carried.
static func _make_emblem(card: CardData, card_style: StyleBoxFlat) -> Control:
	var box := Vector2(SLAB_NUMBER_X, SLAB_H)
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
		icon.position = Vector2(8, (SLAB_H - 36.0) / 2.0)
		icon.size = Vector2(36, 36)
		icon.material = StageSkin.icon_material()
		return icon
	var glyph := Label.new()
	glyph.text = "★"
	glyph.size = box
	glyph.position = Vector2(2, 0)
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
