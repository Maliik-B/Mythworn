class_name CardInspect
extends RefCounted
## The enlarged card a right-click opens: the face, bigger, and beside it what the face no longer
## carries (its rarity, its flavor line, and a reminder for each keyword it uses). Every word comes
## from the card's own data: the flavor is CardData.flavor_text, a Trick's reminder is
## CardData.trick_reminder, a status keyword is the status's own name and description. Nothing here
## is written for the view.
##
## It is a dim over the whole fight with the card and its notes on it. Any click on the dim closes
## it, which is how a second right-click and a click elsewhere both work; Escape is the scene's, so
## it can run before anything else sees the key.

const SCALE := 1.6
const GAP := 28.0
const NOTES_W := 330.0
const NOTES_PAD := 16.0
const NAME_SIZE := 24
const BODY_SIZE := 20
const FLAVOR_SIZE := 19


## `face` is CardFace.build's panel for `card`, made by the caller because the school coin on it
## belongs to combat. The overlay owns it from here.
static func build(card: CardData, face: PanelContainer, on_close: Callable) -> Control:
	var overlay := Control.new()
	overlay.name = "CardInspect"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 90
	overlay.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			on_close.call()
			overlay.accept_event())

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)

	var notes := _notes(card)
	var card_size: Vector2 = CardFace.SIZE * SCALE
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", int(GAP))
	group.alignment = BoxContainer.ALIGNMENT_CENTER
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(group)

	# The face is drawn at its own size and scaled, in a holder that has the room it will fill.
	var holder := Control.new()
	holder.custom_minimum_size = card_size
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.pivot_offset = Vector2.ZERO
	face.scale = Vector2(SCALE, SCALE)
	face.position = Vector2.ZERO
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(face)
	group.add_child(holder)

	# The notes hang from the card's top edge, so the panel starts on the cost-coin line on every
	# card and only grows downward; a column the card's height keeps it level with the face.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(NOTES_W, card_size.y)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(notes)
	group.add_child(side)
	return overlay


## The side panel: the rarity always, then the flavor line and each keyword the card has.
static func _notes(card: CardData) -> Control:
	var key: String = CardFace._colour_key(card)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = NOTES_W
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = StageSkin.c("card_bg_" + key)
	style.border_color = StageSkin.c("card_edge_" + key)
	style.set_border_width_all(2)
	style.set_corner_radius_all(0 if StageSkin.is_page() else 10)
	style.set_content_margin_all(NOTES_PAD)
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)

	var rarity := _rarity_line(card)
	column.add_child(_label(rarity, CardFace.TITLE_FONT_PATH, NAME_SIZE, StageSkin.c(CardFace.RARITY_COLORS[card.rarity])))

	if card.flavor_text != "":
		column.add_child(_rule(style))
		column.add_child(_label(card.flavor_text, CardFace.RULES_FONT_PATH, FLAVOR_SIZE, StageSkin.c("card_dim")))

	var keywords := _keywords(card)
	for entry in keywords:
		column.add_child(_rule(style))
		column.add_child(_label(entry["name"], CardFace.TITLE_FONT_PATH, BODY_SIZE, StageSkin.c("card_ink")))
		column.add_child(_label(entry["text"], CardFace.RULES_FONT_PATH, BODY_SIZE - 2, StageSkin.c("card_ink")))
	return panel


## The card's rarity as the game words it. A memory card is its own kind and has no rarity to show.
static func _rarity_line(card: CardData) -> String:
	if card.is_memory:
		return "Memory"
	return CardFace.RARITY_NAMES[card.rarity]


## Each keyword the card uses, once, as {name, text}: a Trick's reminder, and the name and
## description of every status it applies.
static func _keywords(card: CardData) -> Array:
	var out: Array = []
	var seen := {}
	if card.trick:
		out.append({"name": "Trick", "text": card.trick_reminder()})
	if card.exhaust:
		out.append({"name": "Exhaust", "text": CardData.EXHAUST_REMINDER})
	for effect in card.get_active_effects():
		if effect is StatusApplyEffect and effect.status_effect != null:
			var status: StatusEffectData = effect.status_effect
			if status.effect_name == "" or seen.has(status.effect_name):
				continue
			seen[status.effect_name] = true
			if status.description != "":
				out.append({"name": status.effect_name, "text": status.description})
	return out


static func _label(text: String, font_path: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = NOTES_W - NOTES_PAD * 2.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


static func _rule(style: StyleBoxFlat) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = style.border_color.darkened(0.2)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
