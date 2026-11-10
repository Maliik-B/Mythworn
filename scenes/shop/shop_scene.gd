extends Control
## Shop scene — redesigned with shopkeeper identity, card art, energy ornaments,
## personality tags, and gold-themed styling.

const CARD_REMOVE_COST := 50
const CARD_COUNT := 5
const RELIC_COUNT := 2
const CONSUMABLE_COUNT := 2
## Stacking cap for shop discounts from titles + future relics. See § Titles in GAME_DESIGN.md.
const SHOP_DISCOUNT_CAP := 50

# Shopkeeper greetings — rotated randomly
const SHOPKEEPER_GREETINGS = [
	"Ah, a traveller! Come, browse my wares...\nEverything has a price, but nothing costs\nmore than leaving empty-handed.",
	"Step closer, friend. These shelves hold\nmore than trinkets — they hold the\ndifference between life and death.",
	"Welcome, welcome! I've been expecting\nsomeone of your... particular talents.\nSee anything that catches your eye?",
	"Another soul drawn to my humble shop.\nFate has a way of bringing the right\nbuyer to the right blade.",
	"In all my years of trade, I've learned\none truth: the wise spend gold before\nthe grave spends them.",
]

var shop_cards: Array[CardData] = []
var card_prices: Dictionary = {} # CardData -> int
var shop_relics: Array[RelicData] = []
var relic_prices: Dictionary = {} # RelicData -> int
## Consumables on offer: the shop's second source after events. Realm-fitting stock (a Camelot
## shop sells Camelot's own items beside the generics), never combat drops.
var shop_consumables: Array[ConsumableData] = []
var consumable_prices: Dictionary = {} # ConsumableData -> int
var card_row: HBoxContainer
var relic_row: HBoxContainer
var consumable_row: HBoxContainer
var gold_label: Label
var info_label: Label
var deck_section: VBoxContainer
var deck_visible := false
var _main_vbox: VBoxContainer
var _inspect: Control


func _ready() -> void:
	_generate_shop()
	_build_ui()
	AudioManager.play_music("shop")


func _generate_shop() -> void:
	var discount := _get_shop_discount_percent()
	# Realm-config economy knob: a "greedy court" realm marks prices up, a "common folk"
	# realm down. Applied to the base before the title discount so both compose.
	var price_mult: float = RunManager.realm_config.shop_price_mult

	shop_cards = CardPool.get_reward_choices(RngManager.loot_rng, CARD_COUNT)
	for card in shop_cards:
		var base := 50
		match card.rarity:
			CardData.CardRarity.COMMON:
				base = 40 + RngManager.loot_rng.randi_range(-5, 5)
			CardData.CardRarity.UNCOMMON:
				base = 60 + RngManager.loot_rng.randi_range(-5, 10)
			CardData.CardRarity.RARE:
				base = 90 + RngManager.loot_rng.randi_range(-5, 15)
		card_prices[card] = _apply_discount(int(round(base * price_mult)), discount)

	var owned = RunManager.get_owned_relic_names()
	shop_relics = RelicPool.get_reward_choices(RngManager.loot_rng, RELIC_COUNT, owned)
	for relic in shop_relics:
		var base := 110
		match relic.rarity:
			RelicData.RelicRarity.COMMON:
				base = 75 + RngManager.loot_rng.randi_range(-10, 10)
			RelicData.RelicRarity.UNCOMMON:
				base = 110 + RngManager.loot_rng.randi_range(-10, 15)
			RelicData.RelicRarity.RARE:
				base = 150 + RngManager.loot_rng.randi_range(-10, 20)
		relic_prices[relic] = _apply_discount(int(round(base * price_mult)), discount)

	# Provisions are rolled LAST, so adding them leaves the cards and relics a seed already
	# produced exactly as they were. Items the player already carries are not offered again.
	var held_ids: Array[StringName] = []
	for held in RunManager.consumables:
		held_ids.append(held.id)
	shop_consumables = ConsumablePool.get_shop_stock(
		RngManager.loot_rng, RunManager.current_realm_id, CONSUMABLE_COUNT, held_ids)
	for item in shop_consumables:
		consumable_prices[item] = _apply_discount(int(round(item.price * price_mult)), discount)


## Aggregates discount from all sources (titles, future relics) and applies the
## stacking cap. Returns an integer percentage in [0, SHOP_DISCOUNT_CAP].
func _get_shop_discount_percent() -> int:
	var total := RunManager.get_title_passive_total(TitleData.EffectType.SHOP_DISCOUNT_PERCENT)
	return clampi(total, 0, SHOP_DISCOUNT_CAP)


## Applies a percentage discount to a base price. Floors result to a minimum of 1 gold
## so generosity never produces free items.
func _apply_discount(base: int, percent: int) -> int:
	if percent <= 0:
		return base
	return maxi(1, base - int(round(base * percent / 100.0)))


## The effective cost of removing a card, after discount.
func _effective_remove_cost() -> int:
	return _apply_discount(CARD_REMOVE_COST, _get_shop_discount_percent())


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.15)
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
	COLOR = vec4(0.0, 0.0, 0.02, vig * 0.5);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	# Main scroll so the entire shop can scroll if content overflows
	var main_scroll = ScrollContainer.new()
	main_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(main_scroll)

	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.custom_minimum_size.x = 1920
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	main_scroll.add_child(margin)

	_main_vbox = VBoxContainer.new()
	_main_vbox.add_theme_constant_override("separation", 16)
	margin.add_child(_main_vbox)

	# ── Shopkeeper banner ──
	_build_shopkeeper_banner()

	# ── Gold display ──
	gold_label = Label.new()
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override("font_size", 22)
	gold_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_main_vbox.add_child(gold_label)

	# Info label
	info_label = Label.new()
	info_label.text = "Click a card, relic or provision to purchase"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_main_vbox.add_child(info_label)

	# Discount notice — visible only when titles grant a shop discount.
	var discount := _get_shop_discount_percent()
	if discount > 0:
		var discount_label = Label.new()
		discount_label.text = "✦ Favor of your titles: %d%% off all prices ✦" % discount
		discount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		discount_label.add_theme_font_size_override("font_size", 15)
		discount_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
		_main_vbox.add_child(discount_label)

	# ── Section: Wares ──
	_add_section_header("Wares", Color(0.9, 0.7, 0.3))

	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 340
	_main_vbox.add_child(scroll)

	card_row = HBoxContainer.new()
	card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # so the centring has the width to centre in
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 20)
	scroll.add_child(card_row)

	_refresh_shop_cards()

	# ── Section: Artifacts ──
	if shop_relics.size() > 0:
		_add_section_header("Artifacts", Color(0.7, 0.55, 0.9))

		relic_row = HBoxContainer.new()
		relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
		relic_row.add_theme_constant_override("separation", 20)
		_main_vbox.add_child(relic_row)

		_refresh_shop_relics()

	# ── Section: Provisions ──
	if shop_consumables.size() > 0:
		_add_section_header("Provisions", Color(0.75, 0.68, 0.4))

		consumable_row = HBoxContainer.new()
		consumable_row.alignment = BoxContainer.ALIGNMENT_CENTER
		consumable_row.add_theme_constant_override("separation", 20)
		_main_vbox.add_child(consumable_row)

		_refresh_shop_consumables()

	# ── Divider ──
	var divider = HSeparator.new()
	divider.add_theme_constant_override("separation", 8)
	divider.add_theme_stylebox_override("separator", _make_divider_style())
	_main_vbox.add_child(divider)

	# ── Section: Actions ──
	_add_section_header("Actions", Color(0.5, 0.75, 0.6))

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 30)
	_main_vbox.add_child(btn_row)

	var remove_btn = _make_gold_button("Remove a Card  (%d gold)" % _effective_remove_cost(), Vector2(280, 52))
	remove_btn.pressed.connect(_on_remove_pressed)
	btn_row.add_child(remove_btn)

	var artifacts_btn = _make_gold_button("Your Artifacts", Vector2(200, 52))
	artifacts_btn.pressed.connect(_on_view_artifacts)
	btn_row.add_child(artifacts_btn)

	var map_btn = _make_gold_button("View Map", Vector2(180, 52))
	map_btn.pressed.connect(_on_view_map)
	btn_row.add_child(map_btn)

	var leave_btn = _make_gold_button("Leave Shop", Vector2(200, 52))
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)

	# Deck section (hidden by default, shown for card removal)
	deck_section = VBoxContainer.new()
	deck_section.add_theme_constant_override("separation", 10)
	deck_section.visible = false
	_main_vbox.add_child(deck_section)

	_update_gold()


# ============================================================
# SHOPKEEPER BANNER
# ============================================================

func _build_shopkeeper_banner() -> void:
	var banner = PanelContainer.new()
	var banner_style = StyleBoxFlat.new()
	banner_style.set_corner_radius_all(12)
	banner_style.bg_color = Color(0.1, 0.08, 0.16)
	banner_style.set_border_width_all(2)
	banner_style.border_color = Color(0.55, 0.4, 0.2, 0.7)
	banner_style.content_margin_left = 24
	banner_style.content_margin_right = 24
	banner_style.content_margin_top = 16
	banner_style.content_margin_bottom = 16
	banner.add_theme_stylebox_override("panel", banner_style)
	_main_vbox.add_child(banner)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(hbox)

	# Shopkeeper portrait — sprite portrait like enemies
	var portrait_frame = PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(90, 100)
	var pf_style = StyleBoxFlat.new()
	pf_style.set_corner_radius_all(8)
	pf_style.bg_color = Color(0.12, 0.09, 0.06)
	pf_style.set_border_width_all(2)
	pf_style.border_color = Color(0.65, 0.5, 0.25)
	pf_style.content_margin_left = 4
	pf_style.content_margin_right = 4
	pf_style.content_margin_top = 4
	pf_style.content_margin_bottom = 4
	portrait_frame.add_theme_stylebox_override("panel", pf_style)
	hbox.add_child(portrait_frame)

	# Sprite portrait using Evil Wizard 2 idle sheet (robed chronicler figure)
	var sheet: Texture2D = load("res://assets/sprites/bosses/evil_wizard_2/EVil Wizard 2/Sprites/Idle.png")
	var atlas = AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(100, 64, 72, 110)
	var portrait_tex = TextureRect.new()
	portrait_tex.texture = atlas
	portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_tex.custom_minimum_size = Vector2(80, 90)
	portrait_tex.modulate = Color(1.0, 0.9, 0.7) # Warm parchment tint
	portrait_frame.add_child(portrait_tex)

	# Right side: name + greeting
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 6)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_vbox)

	var name_lbl = Label.new()
	name_lbl.text = "The Chronicler's Bazaar"
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	text_vbox.add_child(name_lbl)

	var greeting_lbl = Label.new()
	var greeting_idx = RngManager.loot_rng.randi_range(0, SHOPKEEPER_GREETINGS.size() - 1)
	greeting_lbl.text = SHOPKEEPER_GREETINGS[greeting_idx]
	greeting_lbl.add_theme_font_size_override("font_size", 15)
	greeting_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	greeting_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_vbox.add_child(greeting_lbl)


# ============================================================
# SECTION HEADERS
# ============================================================

func _add_section_header(text: String, color: Color) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_vbox.add_child(hbox)

	# Left flourish
	var left = Label.new()
	left.text = "---"
	left.add_theme_font_size_override("font_size", 16)
	left.add_theme_color_override("font_color", color.darkened(0.4))
	hbox.add_child(left)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", color)
	hbox.add_child(lbl)

	# Right flourish
	var right = Label.new()
	right.text = "---"
	right.add_theme_font_size_override("font_size", 16)
	right.add_theme_color_override("font_color", color.darkened(0.4))
	hbox.add_child(right)


# ============================================================
# STYLED BUTTONS
# ============================================================

func _make_gold_button(text: String, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 18)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal = StyleBoxFlat.new()
	normal.set_corner_radius_all(8)
	normal.bg_color = Color(0.18, 0.13, 0.26)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.8, 0.6, 0.25)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal)

	var hover = normal.duplicate()
	hover.bg_color = Color(0.26, 0.2, 0.36)
	hover.border_color = Color(0.95, 0.75, 0.3)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.12, 0.09, 0.18)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.8))

	return btn


func _make_divider_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.4, 0.3, 0.18, 0.4)
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	return s


# ============================================================
# GOLD
# ============================================================

func _update_gold() -> void:
	gold_label.text = "Gold: %d" % RunManager.gold


# ============================================================
# SHOP CARDS
# ============================================================

func _refresh_shop_cards() -> void:
	for child in card_row.get_children():
		child.queue_free()

	for card in shop_cards:
		var price = card_prices[card]
		var panel = _create_shop_card(card, price)
		card_row.add_child(panel)


func _create_shop_card(card: CardData, price: int) -> Control:
	var can_afford = RunManager.gold >= price

	# The face is the card as the hand draws it; the price sits above it, outside the face.
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)

	var price_lbl = Label.new()
	price_lbl.text = "%d gold" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 18)
	price_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.3) if can_afford else Color(0.7, 0.3, 0.3))
	holder.add_child(price_lbl)

	var face := CardFace.build(card, null, CardSigil.build(card))
	if not can_afford:
		face.modulate = Color(0.5, 0.5, 0.5)
	holder.add_child(face)

	_ignore_mouse_recursive(holder)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_on_shop_card_input.bind(card))
	if can_afford:
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The scale is the face's own (its pivot is its middle), so the price stays put.
	holder.mouse_entered.connect(func():
		if can_afford:
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(face, "scale", Vector2(1.06, 1.06), 0.12)
	)
	holder.mouse_exited.connect(func():
		var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(face, "scale", Vector2.ONE, 0.12)
	)

	return holder


# ============================================================
# BUYING CARDS
# ============================================================

func _on_shop_card_input(event: InputEvent, card: CardData) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_open_inspect(card)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var price = card_prices.get(card, 0)
	if RunManager.gold < price:
		info_label.text = "Not enough gold!"
		return

	RunManager.add_gold(-price)
	RunManager.add_card_to_deck(card)
	shop_cards.erase(card)
	card_prices.erase(card)
	info_label.text = "Bought %s!" % card.card_name
	AudioManager.play_sfx("shop_buy")
	_update_gold()
	_refresh_shop_cards()


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


# ============================================================
# SHOP RELICS
# ============================================================

func _refresh_shop_relics() -> void:
	if not relic_row:
		return
	for child in relic_row.get_children():
		child.queue_free()
	for relic in shop_relics:
		var price = relic_prices[relic]
		relic_row.add_child(_create_shop_relic(relic, price))


func _create_shop_relic(relic: RelicData, price: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 150)

	var rarity_colors = {
		RelicData.RelicRarity.COMMON: Color(0.6, 0.6, 0.6),
		RelicData.RelicRarity.UNCOMMON: Color(0.3, 0.7, 0.9),
		RelicData.RelicRarity.RARE: Color(0.95, 0.8, 0.2),
		RelicData.RelicRarity.BOSS: Color(0.9, 0.3, 0.3),
	}
	var border_color = rarity_colors.get(relic.rarity, Color(0.5, 0.5, 0.5))
	var can_afford = RunManager.gold >= price

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.bg_color = Color(0.16, 0.13, 0.22)
	style.border_color = border_color
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	if not can_afford:
		panel.modulate = Color(0.5, 0.5, 0.5)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	# Price
	var price_lbl = Label.new()
	price_lbl.text = "%d gold" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 15)
	price_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.3) if can_afford else Color(0.7, 0.3, 0.3))
	vbox.add_child(price_lbl)

	# Relic name
	var name_lbl = Label.new()
	name_lbl.text = relic.relic_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", border_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Rarity tag
	var rarity_tags = {
		RelicData.RelicRarity.COMMON: "Common",
		RelicData.RelicRarity.UNCOMMON: "Uncommon",
		RelicData.RelicRarity.RARE: "Rare",
		RelicData.RelicRarity.BOSS: "Boss",
	}
	var rarity_lbl = Label.new()
	rarity_lbl.text = rarity_tags.get(relic.rarity, "")
	rarity_lbl.add_theme_font_size_override("font_size", 11)
	rarity_lbl.add_theme_color_override("font_color", border_color.darkened(0.2))
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_lbl)

	# Description
	var desc_lbl = Label.new()
	desc_lbl.text = relic.description
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	_ignore_mouse_recursive(vbox)

	panel.gui_input.connect(_on_shop_relic_input.bind(relic))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.pivot_offset = Vector2(120, 75)
	if can_afford:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.mouse_entered.connect(func():
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(panel, "scale", Vector2(1.05, 1.05), 0.12)
		)
		panel.mouse_exited.connect(func():
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(panel, "scale", Vector2.ONE, 0.12)
		)

	return panel


func _on_shop_relic_input(event: InputEvent, relic: RelicData) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var price = relic_prices.get(relic, 0)
	if RunManager.gold < price:
		info_label.text = "Not enough gold!"
		return

	RunManager.add_gold(-price)
	RunManager.add_relic(relic)
	shop_relics.erase(relic)
	relic_prices.erase(relic)
	info_label.text = "Bought %s!" % relic.relic_name
	AudioManager.play_sfx("shop_buy")
	_update_gold()
	_refresh_shop_relics()


# ============================================================
# SHOP PROVISIONS (CONSUMABLES)
# ============================================================

func _refresh_shop_consumables() -> void:
	if not consumable_row:
		return
	for child in consumable_row.get_children():
		child.queue_free()
	for item in shop_consumables:
		consumable_row.add_child(_create_shop_consumable(item, consumable_prices[item]))


func _create_shop_consumable(item: ConsumableData, price: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 150)
	var can_afford = RunManager.gold >= price
	var border_color := Color(0.75, 0.68, 0.4)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.bg_color = Color(0.16, 0.13, 0.1)
	style.border_color = border_color
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	if not can_afford:
		panel.modulate = Color(0.5, 0.5, 0.5)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var price_lbl = Label.new()
	price_lbl.text = "%d gold" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 15)
	price_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.85, 0.3) if can_afford else Color(0.7, 0.3, 0.3))
	vbox.add_child(price_lbl)

	var name_lbl = Label.new()
	name_lbl.text = item.display_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", border_color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var tag_lbl = Label.new()
	tag_lbl.text = item.use_context_label().trim_prefix("Use: ")
	tag_lbl.add_theme_font_size_override("font_size", 11)
	tag_lbl.add_theme_color_override("font_color", border_color.darkened(0.2))
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tag_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = item.description
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	_ignore_mouse_recursive(vbox)

	panel.gui_input.connect(_on_shop_consumable_input.bind(item))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if can_afford:
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return panel


func _on_shop_consumable_input(event: InputEvent, item: ConsumableData) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var price = consumable_prices.get(item, 0)
	if RunManager.gold < price:
		info_label.text = "Not enough gold!"
		return

	# A full pack asks first: you leave one thing behind (or the new one), and the gold only
	# changes hands if the new one goes into the pack.
	if RunManager.has_consumable_room():
		RunManager.add_consumable(item)
		_complete_consumable_purchase(item, price)
		return
	var swap := ConsumableSwap.open(self, item)
	swap.resolved.connect(func(taken: bool):
		if taken:
			_complete_consumable_purchase(item, price)
		else:
			info_label.text = "You leave %s on the counter." % item.display_name)


func _complete_consumable_purchase(item: ConsumableData, price: int) -> void:
	RunManager.add_gold(-price)
	shop_consumables.erase(item)
	consumable_prices.erase(item)
	info_label.text = "Bought %s!" % item.display_name
	AudioManager.play_sfx("shop_buy")
	_update_gold()
	_refresh_shop_consumables()


# ============================================================
# REMOVING CARDS
# ============================================================

func _on_remove_pressed() -> void:
	if deck_visible:
		deck_section.visible = false
		deck_visible = false
		info_label.text = "Click a card, relic or provision to purchase"
		return

	var cost := _effective_remove_cost()
	if RunManager.gold < cost:
		info_label.text = "Not enough gold! (Need %d)" % cost
		return

	if RunManager.current_deck.size() <= 1:
		info_label.text = "Can't remove your last card!"
		return

	_show_deck_for_removal()


func _show_deck_for_removal() -> void:
	deck_visible = true
	deck_section.visible = true
	info_label.text = "Click a card to remove it (%d gold)" % _effective_remove_cost()

	for child in deck_section.get_children():
		child.queue_free()

	var header_row = HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_theme_constant_override("separation", 20)
	deck_section.add_child(header_row)

	var header = Label.new()
	header.text = "Your Deck (%d cards)" % RunManager.current_deck.size()
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	header_row.add_child(header)

	var cancel_btn = _make_gold_button("Cancel", Vector2(100, 36))
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(_on_cancel_remove)
	header_row.add_child(cancel_btn)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	deck_section.add_child(scroll)

	var flow = HBoxContainer.new()
	flow.add_theme_constant_override("separation", 8)
	scroll.add_child(flow)

	for i in RunManager.current_deck.size():
		var card = RunManager.current_deck[i]
		var btn = Button.new()
		btn.text = card.card_name
		btn.custom_minimum_size = Vector2(140, 40)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_remove_card.bind(i))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var btn_style = StyleBoxFlat.new()
		btn_style.set_corner_radius_all(6)
		btn_style.content_margin_left = 8
		btn_style.content_margin_right = 8
		btn_style.content_margin_top = 6
		btn_style.content_margin_bottom = 6
		match card.card_type:
			CardData.CardType.ATTACK:
				btn_style.bg_color = Color(0.35, 0.14, 0.12)
				btn_style.border_color = Color(0.7, 0.22, 0.2)
			CardData.CardType.SKILL:
				btn_style.bg_color = Color(0.14, 0.17, 0.35)
				btn_style.border_color = Color(0.22, 0.38, 0.7)
			CardData.CardType.POWER:
				btn_style.bg_color = Color(0.35, 0.3, 0.08)
				btn_style.border_color = Color(0.7, 0.55, 0.1)
		if card.upgraded:
			btn_style.border_color = btn_style.border_color.lerp(Color(0.3, 0.9, 0.3), 0.5)
		btn_style.set_border_width_all(2)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style = btn_style.duplicate()
		hover_style.bg_color = hover_style.bg_color.lightened(0.2)
		btn.add_theme_stylebox_override("hover", hover_style)

		flow.add_child(btn)


func _on_cancel_remove() -> void:
	deck_section.visible = false
	deck_visible = false
	info_label.text = "Click a card, relic or provision to purchase"


func _on_remove_card(index: int) -> void:
	var card = RunManager.current_deck[index]
	RunManager.add_gold(-_effective_remove_cost())
	RunManager.remove_card_from_deck(index)
	AudioManager.play_sfx("card_exhaust")
	info_label.text = "Removed %s!" % card.card_name
	_update_gold()
	_show_deck_for_removal()


# ============================================================
# LEAVE
# ============================================================

func _on_leave() -> void:
	AudioManager.play_sfx("button_click")
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


## Read-only map peek — doesn't leave the shop.
func _on_view_map() -> void:
	MapPreviewOverlay.open(self)


## Read-only artifact review — the relics + titles you already carry, for purchase
## planning. Doesn't leave the shop or mutate anything.
func _on_view_artifacts() -> void:
	ArtifactsOverlay.open(self)


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)
