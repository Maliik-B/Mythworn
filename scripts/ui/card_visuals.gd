class_name CardVisuals
## Single source for card art icons + a shared "full card" renderer. Centralizes the
## CARD_ICONS map that combat and the reward screen each kept their own copy of, and
## gives the deck screen / Passion page a real full-size card render (art + text),
## instead of a glyph-only stand-in.

const _CR := "res://assets/sprites/icons/clockwork_raven/Clockwork raven - Weapons and Potions - Free pack/individual_64x64/"
const _ITV := "res://assets/sprites/icons/in_the_void/individual/"
const _CUS := "res://assets/sprites/icons/custom/"

const CARD_ICONS := {
	# Starter attacks
	"Strike": _CR + "tile000.png",
	"Stagger": _CR + "tile025.png",
	"Noxious Strike": _CUS + "noxious_strike.png",
	"Wide Arc": _CR + "tile004.png",
	# Outpouring + the Water pool use the neutral frame until Water art lands.
	# Generic attacks
	"Paired Strikes": _CUS + "twin_strike.png",
	"Sweep": _CR + "tile011.png",
	"Havoc": _CR + "tile041.png",
	"Poison Fang": _CUS + "poison_fang.png",
	"Armor Break": _CR + "tile016.png",
	"Execute": _CR + "tile012.png",
	# Secondary (Physical) attacks
	"Power Slash": _CR + "tile006.png",
	"Quick Jab": _CR + "tile005.png",
	"Rampage": _CR + "tile050.png",
	"Devastating Blow": _CR + "tile030.png",
	# Starter skills
	"Defend": _ITV + "shield.png",
	"Meditate": _CUS + "meditate.png",
	# Generic skills
	"Bracing Blow": _ITV + "gem_blue.png",
	"Shield Wall": _ITV + "gauntlet.png",
	"Dark Pact": _CUS + "dark_pact.png",
	"Inner Fire": _CUS + "inner_fire.png",
	"Weaken": _ITV + "scroll_red.png",
	"Second Wind": _CR + "tile083.png",
	"Phantom Guard": _CUS + "apparition.png",
	# Secondary (Physical) skills
	"Brace": _ITV + "chestplate.png",
	"Iron Curtain": _CUS + "iron_curtain.png",
	"Riposte": _CR + "tile009.png",
	"Bulwark": _ITV + "shield.png",
}


static func icon_path(card_name: String) -> String:
	return CARD_ICONS.get(card_name, "")


static func _type_style(card: CardData, green_tint: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	match card.card_type:
		CardData.CardType.ATTACK:
			style.bg_color = Color(0.28, 0.1, 0.08)
			style.border_color = Color(0.8, 0.2, 0.18)
		CardData.CardType.SKILL:
			style.bg_color = Color(0.08, 0.12, 0.28)
			style.border_color = Color(0.2, 0.38, 0.8)
		CardData.CardType.POWER:
			style.bg_color = Color(0.28, 0.24, 0.08)
			style.border_color = Color(0.8, 0.65, 0.15)
	if green_tint:
		style.border_color = style.border_color.lerp(Color(0.3, 0.9, 0.3), 0.55)
	return style


## Full-size card render: real art icon (glyph fallback), cost, name, type/rarity,
## description, flavor. `dmg_mult` scales the shown attack damage for a Passion-zone
## preview and, when it changes the number, appends a green (buffed) / red (nerfed)
## "zone" readout so the effect of standing in that tier is legible on the card.
static func render_full(card: CardData, dmg_mult: float = 1.0, green_tint: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(190, 262)
	var style := _type_style(card, green_tint or dmg_mult > 1.0)
	panel.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	panel.add_child(vb)

	var cost := Label.new()
	cost.text = "%s ◆" % card.cost_label()
	cost.add_theme_font_size_override("font_size", 19)
	cost.add_theme_color_override("font_color", Color(0.95, 0.9, 0.3))
	vb.add_child(cost)

	var name_lbl := Label.new()
	name_lbl.text = card.card_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", style.border_color.lightened(0.4))
	vb.add_child(name_lbl)

	var type_names := ["Attack", "Skill", "Power"]
	var rarity_names := ["Starter", "Common", "Uncommon", "Rare"]
	var type_lbl := Label.new()
	type_lbl.text = "%s - %s" % [type_names[card.card_type], rarity_names[card.rarity]]
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vb.add_child(type_lbl)

	# Art frame — real icon where we have one, else the type glyph.
	var art_frame := PanelContainer.new()
	art_frame.custom_minimum_size = Vector2(0, 74)
	var art_style := StyleBoxFlat.new()
	art_style.set_corner_radius_all(6)
	art_style.bg_color = style.bg_color.lightened(0.06)
	art_style.set_border_width_all(1)
	art_style.border_color = style.border_color.darkened(0.2)
	art_frame.add_theme_stylebox_override("panel", art_style)
	var path := icon_path(card.card_name)
	if path != "" and ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art_frame.add_child(art)
	else:
		var glyph := Label.new()
		match card.card_type:
			CardData.CardType.ATTACK: glyph.text = "⚔"
			CardData.CardType.SKILL: glyph.text = "◆"
			CardData.CardType.POWER: glyph.text = "★"
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 34)
		glyph.add_theme_color_override("font_color", style.border_color.lightened(0.3))
		art_frame.add_child(glyph)
	vb.add_child(art_frame)

	var desc := Label.new()
	desc.text = card.get_generated_description()
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(desc)

	# Zone readout — only when this tier actually changes the card's damage.
	if dmg_mult != 1.0:
		var base := _first_damage(card)
		if base > 0:
			var mod := int(base * dmg_mult)
			if mod != base:
				var zone := Label.new()
				zone.text = "⚔ %d → %d in this zone" % [base, mod]
				zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				zone.add_theme_font_size_override("font_size", 13)
				zone.add_theme_color_override("font_color",
					Color(0.4, 0.9, 0.45) if mod > base else Color(0.95, 0.45, 0.4))
				vb.add_child(zone)

	if card.flavor_text != "":
		var flavor := Label.new()
		flavor.text = card.flavor_text
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.add_theme_font_size_override("font_size", 11)
		flavor.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
		vb.add_child(flavor)

	return panel


static func _first_damage(card: CardData) -> int:
	for e in card.get_active_effects():
		if e is DamageEffect:
			return e.value
	return 0
