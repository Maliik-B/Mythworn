extends Control
## The shop, as a stall on the page. The keeper stands on the ground at the left under his place's
## name, his greeting and his answer to what you do; the cards hang their prices under them on the
## upper shelf; artifacts, provisions and the removal are slips on the lower shelf; and the gold, the
## pack and the ways out sit on the desk below, where the fight keeps its numbers and End Turn. The
## page is CombatStage's at the shop's own ground line, so every colour on it is StageSkin's. A ware
## keeps its place on the shelf when another is bought, and a bought one leaves its gap.

const CARD_REMOVE_COST := 50
const CARD_COUNT := 5
const RELIC_COUNT := 2
const CONSUMABLE_COUNT := 2
## Stacking cap for shop discounts from titles + future relics.
const SHOP_DISCOUNT_CAP := 50

# Shopkeeper greetings, rotated randomly. One line each: the keeper's column wraps them.
const SHOPKEEPER_GREETINGS = [
	"Ah, a traveller! Come, browse my wares... Everything has a price, but nothing costs more than leaving empty-handed.",
	"Step closer, friend. These shelves hold more than trinkets. They hold the difference between life and death.",
	"Welcome, welcome! I've been expecting someone of your... particular talents. See anything that catches your eye?",
	"Another soul drawn to my humble shop. Fate has a way of bringing the right buyer to the right blade.",
	"In all my years of trade, I've learned one truth: the wise spend gold before the grave spends them.",
]
const INFO_LINE := "Click a card, relic or provision to purchase"

# The page, as the stall was mocked and picked: the ground and the page's lower
# edge, the two shelves and their planks, the keeper's column and the keeper.
const GROUND_Y := 884.0
const PAGE_BOTTOM := 990.0  # the desk strip runs from here to the foot of the screen
const SHELF_LEFT := 610.0
const SHELF_SPAN := 1250.0
const CARD_SCALE := 1.15
const CARD_TOP := 64.0
const TICKET_Y := 424.0  # a ticket's top; its string runs up toward the card
const TICKET_W := 128.0
const PLANK_H := 30.0
const PLANK_LABEL_SIZE := 24
const WARES_PLANK_Y := 470.0
const SLIP_TOP := 532.0
const SLIP_H := 306.0
const SLIP_GAP := 20.0
const SLIP_SLOTS := 5  # two artifacts, two provisions and the removal
const SLIP_PAD := 14.0
const SLIP_SEP := 6.0
const HOVER_LIFT := 10.0
const HOVER_GROW := 1.06
const COLUMN_POS := Vector2(84, 40)
const COLUMN_W := 440.0
const KEEPER_SET := "wizard2"  # the Evil Wizard sheet, read from the fight's sprite table
const KEEPER_CROP := Rect2(100, 60, 72, 110)  # within an idle frame: the figure and his staff
const KEEPER_FEET_ROW := 168.0  # the frame's row under his feet
const KEEPER_SCALE := 5.0
const KEEPER_FEET := Vector2(300, GROUND_Y + 24)
const DESK_ROW_X := 84.0
const REMOVE_SCALE := 0.8
const REMOVE_COLUMNS := 9
const REMOVE_GAP := 18

var shop_cards: Array[CardData] = []
var card_prices: Dictionary = {} # CardData -> int
var shop_relics: Array[RelicData] = []
var relic_prices: Dictionary = {} # RelicData -> int
## Consumables on offer: the shop's second source after events. Realm-fitting stock (a Camelot
## shop sells Camelot's own items beside the generics), never combat drops.
var shop_consumables: Array[ConsumableData] = []
var consumable_prices: Dictionary = {} # ConsumableData -> int
var card_shelf: Control  # the upper shelf's wares
var slip_shelf: Control  # the lower shelf's
var gold_label: Label
var info_label: Label
var consumable_bar: ConsumableBar
var _slot: Dictionary = {}  # a ware -> its place on its shelf, set when the shop opens
var _card_slots := 0
var _remove_slot := 0
var _removal: Control = null
var _inspect: Control
var _hover_note: HoverNote
var _italic: FontVariation = null
var _keeper: AtlasTexture = null
var _keeper_fw := 0
var _keeper_frames := 1
var _keeper_fps := 0.0
var _keeper_time := 0.0


func _ready() -> void:
	_generate_shop()
	_build_ui()
	AudioManager.play_music("shop")


## The keeper idles as a body on the fight's stage does: his idle strip, looped at its own speed.
func _process(delta: float) -> void:
	if _keeper == null or _keeper_fps <= 0.0:
		return
	_keeper_time += delta
	var frame := int(_keeper_time * _keeper_fps) % _keeper_frames
	_keeper.region = Rect2(frame * _keeper_fw + KEEPER_CROP.position.x, KEEPER_CROP.position.y,
		KEEPER_CROP.size.x, KEEPER_CROP.size.y)


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
	# The desk under everything and the page on it, as in the fight.
	var desk := _rect(self, Vector2.ZERO, Vector2(1920, 1080), StageSkin.c("desk"))
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(CombatStage.new(GROUND_Y, PAGE_BOTTOM))

	_build_keeper_column()
	_build_keeper()

	# Every ware's place is fixed now, so a sale leaves a gap instead of moving the rest.
	_card_slots = shop_cards.size()
	for i in shop_cards.size():
		_slot[shop_cards[i]] = i
	var slip := 0
	for relic in shop_relics:
		_slot[relic] = slip
		slip += 1
	for item in shop_consumables:
		_slot[item] = slip
		slip += 1
	_remove_slot = slip

	_plank(WARES_PLANK_Y, [["Wares", SHELF_LEFT]])
	var lower_labels := []
	if shop_relics.size() > 0:
		lower_labels.append(["Artifacts", _slip_rect(0).position.x])
	if shop_consumables.size() > 0:
		lower_labels.append(["Provisions", _slip_rect(shop_relics.size()).position.x])
	_plank(SLIP_TOP + SLIP_H + 10.0, lower_labels)
	card_shelf = _layer()
	slip_shelf = _layer()

	_build_desk()

	# What a pack item does, in the page's panel. Only over the pack itself, and never under a view
	# opened over the shop.
	_hover_note = HoverNote.new()
	_hover_note.blocked = func() -> bool:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or consumable_bar.is_menu_open() or is_instance_valid(_inspect) \
				or is_instance_valid(_removal):
			return true
		# Over the pack, or over a relic on the shelf.
		var over_pack := hovered == consumable_bar or consumable_bar.is_ancestor_of(hovered)
		return not (over_pack or slip_shelf.is_ancestor_of(hovered))
	add_child(_hover_note)

	_refresh_wares()
	_update_gold()


# ============================================================
# THE KEEPER
# ============================================================

## His place's name with its initial in the rubric's red, as a card's name is set; his greeting
## under it; and his answer to what you do, which is where the shop's replies land.
func _build_keeper_column() -> void:
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.position = COLUMN_POS
	column.custom_minimum_size.x = COLUMN_W
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	var name_lbl := RichTextLabel.new()
	name_lbl.bbcode_enabled = true
	name_lbl.fit_content = true
	name_lbl.scroll_active = false
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_override("normal_font", load(CardFace.TITLE_FONT_PATH))
	name_lbl.add_theme_font_size_override("normal_font_size", 46)
	name_lbl.add_theme_color_override("default_color", StageSkin.c("ink"))
	var shop_name := "The Chronicler's Bazaar"
	name_lbl.text = "[color=#%s]%s[/color]%s" % [StageSkin.c("card_rubric_attack").to_html(false),
		shop_name.left(1), shop_name.substr(1)]
	column.add_child(name_lbl)

	var greeting_idx = RngManager.loot_rng.randi_range(0, SHOPKEEPER_GREETINGS.size() - 1)
	var greeting_lbl := _label(SHOPKEEPER_GREETINGS[greeting_idx], _italic_face(), 23, StageSkin.c("ink_soft"))
	greeting_lbl.name = "Greeting"
	greeting_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(greeting_lbl)

	info_label = _label(INFO_LINE, load(CardFace.RULES_FONT_PATH), 21, StageSkin.c("card_dim"))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info_label)


## The keeper large on the ground, from the fight's own entry for his sheet, with the fight's flat
## shadow under his feet.
func _build_keeper() -> void:
	var sset: Dictionary = load("res://scenes/combat/combat_scene.gd").SPRITE_SETS[KEEPER_SET]
	var dir: String = sset["baked"] if StageSkin.is_page() and sset.has("baked") else sset["dir"]
	var idle: Array = sset["anims"]["idle"]
	_keeper_fw = int(sset.get("fw", sset.get("cell", 150)))
	_keeper_frames = maxi(1, int(idle[1]))
	_keeper_fps = float(idle[2])
	_keeper = AtlasTexture.new()
	_keeper.atlas = load(dir + idle[0])
	_keeper.region = KEEPER_CROP

	var s := KEEPER_SCALE
	_rect(self, Vector2(KEEPER_FEET.x - 34 * s, KEEPER_FEET.y - 2 * s), Vector2(68 * s, 3 * s), StageSkin.c("shadow"))
	var body := TextureRect.new()
	body.name = "Keeper"
	body.texture = _keeper
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_SCALE
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = KEEPER_CROP.size * s
	body.position = Vector2(KEEPER_FEET.x - body.size.x / 2.0, KEEPER_FEET.y - (KEEPER_FEET_ROW - KEEPER_CROP.position.y) * s)
	add_child(body)


# ============================================================
# THE SHELVES
# ============================================================

## The middle of a card's place on the upper shelf, for however many cards the shop opened with.
static func card_centre(slot: int, count: int) -> float:
	return SHELF_LEFT + SHELF_SPAN * (2 * slot + 1) / (2.0 * maxi(1, count))


## A slip's place on the lower shelf. The width is set for a full shelf, so a short one keeps its
## slips the same size, from the left.
static func _slip_rect(slot: int) -> Rect2:
	var w := (SHELF_SPAN - (SLIP_SLOTS - 1) * SLIP_GAP) / SLIP_SLOTS
	return Rect2(SHELF_LEFT + slot * (w + SLIP_GAP), SLIP_TOP, w, SLIP_H)


## Redraws both shelves from the stock and the gold, so a sale also fades whatever the gold left
## can no longer buy.
func _refresh_wares() -> void:
	for shelf in [card_shelf, slip_shelf]:
		for child in shelf.get_children():
			shelf.remove_child(child)
			child.queue_free()
	var card_w := CardFace.SIZE.x * CARD_SCALE
	for card in shop_cards:
		var ware := _create_shop_card(card, card_prices[card])
		ware.position = Vector2(card_centre(_slot[card], _card_slots) - card_w / 2.0, CARD_TOP)
		card_shelf.add_child(ware)
	for relic in shop_relics:
		var slip := _create_slip(_slip_rect(_slot[relic]), relic.relic_name, _rarity_colour(relic.rarity),
			_rarity_name(relic.rarity), relic.description, relic_prices[relic], _on_shop_relic_input.bind(relic))
		RelicKeywords.mark(slip, relic)
		slip_shelf.add_child(slip)
	for item in shop_consumables:
		slip_shelf.add_child(_create_slip(_slip_rect(_slot[item]), item.display_name, StageSkin.c("ink"),
			item.use_context_label().trim_prefix("Use: "), item.description, consumable_prices[item],
			_on_shop_consumable_input.bind(item)))
	var remove := _create_slip(_slip_rect(_remove_slot), "Remove a Card", StageSkin.c("ink"),
		"Your Deck (%d cards)" % RunManager.current_deck.size(), "", _effective_remove_cost(), _on_remove_input)
	remove.name = "RemoveSlip"
	slip_shelf.add_child(remove)


## A card on the shelf: the face as the hand draws it, its price on a ticket hung under it. Too dear,
## the face fades into the page and the price goes red.
func _create_shop_card(card: CardData, price: int) -> Control:
	var can_afford := RunManager.gold >= price
	var ware := Control.new()
	ware.size = CardFace.SIZE * CARD_SCALE
	var shade := _shade(ware.size)
	ware.add_child(shade)
	var face := CardFace.build(card, null, CardSigil.build(card))
	face.pivot_offset = CardFace.SIZE / 2.0
	face.scale = Vector2.ONE * CARD_SCALE
	face.position = CardFace.SIZE * (CARD_SCALE - 1.0) / 2.0
	if not can_afford:
		face.modulate.a = 0.45
	ware.add_child(face)
	ware.add_child(_make_ticket(ware.size.x / 2.0, TICKET_Y - CARD_TOP, price, can_afford))
	ware.set_meta("face", face)

	_ignore_mouse_recursive(ware)
	ware.mouse_filter = Control.MOUSE_FILTER_STOP
	ware.gui_input.connect(_on_shop_card_input.bind(card))
	if can_afford:
		ware.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_lift_on_hover(ware, face, shade, HOVER_GROW)
	return ware


## A price ticket on a string, hung from the shelf under a card.
func _make_ticket(centre_x: float, top: float, price: int, afford: bool) -> Control:
	var ticket := Control.new()
	ticket.name = "Ticket"
	ticket.position = Vector2(centre_x - TICKET_W / 2.0, top)
	_rect(ticket, Vector2(TICKET_W / 2.0 - 1, -14), Vector2(2, 14), StageSkin.c("ink_soft"))
	_rect(ticket, Vector2(-2, -2), Vector2(TICKET_W + 4, 40), StageSkin.c("card_edge_attack"))
	_rect(ticket, Vector2.ZERO, Vector2(TICKET_W, 36), StageSkin.c("card_bg_attack"))
	var lbl := _label("%d gold" % price, load(CardFace.RULES_FONT_PATH), 23, _price_colour(afford))
	lbl.name = "Price"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0, 2)
	lbl.size = Vector2(TICKET_W, 32)
	ticket.add_child(lbl)
	return ticket


## A ware that is not a card: a leaf of the card's paper with its price, its name in its rarity's
## colour, what kind of thing it is, a rule and its words. The words step down a size or two if
## they would run past the slip.
func _create_slip(rect: Rect2, title: String, title_col: Color, kind: String, body: String,
		price: int, on_click: Callable) -> Control:
	var can_afford := RunManager.gold >= price
	var ware := Control.new()
	ware.position = rect.position
	ware.size = rect.size
	var shade := _shade(rect.size)
	ware.add_child(shade)

	var panel := PanelContainer.new()
	panel.name = "Slip"
	var st := StyleBoxFlat.new()
	st.bg_color = StageSkin.c("card_bg_attack")
	st.border_color = StageSkin.c("card_edge_attack")
	st.set_border_width_all(2)
	st.set_content_margin_all(SLIP_PAD)
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = rect.size
	panel.size = rect.size
	ware.add_child(panel)

	var rules_font: Font = load(CardFace.RULES_FONT_PATH)
	var title_font: Font = load(CardFace.TITLE_FONT_PATH)
	var inner_w := rect.size.x - 2 * SLIP_PAD
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(SLIP_SEP))
	panel.add_child(col)
	var p := _label("%d gold" % price, rules_font, 22, _price_colour(can_afford))
	p.name = "Price"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(p)
	var t := _label(title, title_font, 26, title_col)
	t.name = "Title"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	var k := _label(kind, rules_font, 16, StageSkin.c("card_dim"))
	k.name = "Kind"
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(k)
	var rule := ColorRect.new()
	rule.color = StageSkin.c("card_inset")
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)
	if body != "":
		var used := rules_font.get_height(22) + title_font.get_multiline_string_size(title,
			HORIZONTAL_ALIGNMENT_CENTER, inner_w, 26).y + rules_font.get_height(16) + 2 + 4 * SLIP_SEP
		var room := rect.size.y - 2 * SLIP_PAD - used
		var body_size := 18
		while body_size > 14 and rules_font.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_CENTER,
				inner_w, body_size).y > room:
			body_size -= 1
		var b := _label(body, rules_font, body_size, StageSkin.c("card_ink"))
		b.name = "Words"
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_constant_override("line_spacing", -2)
		col.add_child(b)
	if not can_afford:
		panel.modulate.a = 0.45

	_ignore_mouse_recursive(ware)
	ware.mouse_filter = Control.MOUSE_FILTER_STOP
	ware.gui_input.connect(on_click)
	if can_afford:
		ware.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_lift_on_hover(ware, panel, shade, 1.0)
	return ware


## A shelf's plank, its front in ink with the shelf's names on it, and its shadow on the page.
func _plank(y: float, labels: Array) -> void:
	var rect := Rect2(SHELF_LEFT - 10, y, SHELF_SPAN + 20, PLANK_H)
	_rect(self, Vector2(rect.position.x, rect.end.y), Vector2(rect.size.x, 8), StageSkin.c("shadow"))
	_rect(self, rect.position, rect.size, StageSkin.c("ink"))
	for entry in labels:
		var lbl := _label(entry[0], load(CardFace.TITLE_FONT_PATH), PLANK_LABEL_SIZE, StageSkin.c("end_text"))
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(entry[1], y)
		lbl.size = Vector2(300, PLANK_H)
		add_child(lbl)


## A hovered ware lifts off the shelf, a card a little larger, with its shadow left on the page.
func _lift_on_hover(ware: Control, body: Control, shade: Control, grow: float) -> void:
	var rest_pos := body.position
	var rest_scale := body.scale
	var move := func(up: bool) -> void:
		shade.visible = up
		if body.has_meta("lift"):
			(body.get_meta("lift") as Tween).kill()
		var tw := body.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(body, "scale", rest_scale * (grow if up else 1.0), 0.12)
		tw.tween_property(body, "position", rest_pos + (Vector2(0, -HOVER_LIFT) if up else Vector2.ZERO), 0.12)
		body.set_meta("lift", tw)
	ware.mouse_entered.connect(move.bind(true))
	ware.mouse_exited.connect(move.bind(false))


func _shade(shade_size: Vector2) -> ColorRect:
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = StageSkin.c("shadow")
	shade.position = Vector2(8, 10)
	shade.size = shade_size
	shade.visible = false
	return shade


# ============================================================
# THE DESK
# ============================================================

## The gold in the stat line's face, the pack as the map shows it, any title's discount, and the
## ways out as the fight's End Turn slab.
func _build_desk() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(DESK_ROW_X, PAGE_BOTTOM)
	row.size = Vector2(1080, 1080 - PAGE_BOTTOM)
	row.add_theme_constant_override("separation", 44)
	add_child(row)

	gold_label = _label("", load(CardFace.RULES_FONT_PATH), 32, StageSkin.c("stat_passion"))
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(gold_label)

	# The pack. Heals and standing items are usable here as on the map; combat-only items wait.
	consumable_bar = ConsumableBar.new()
	consumable_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	consumable_bar.setup(ConsumableBar.Mode.MAP)
	row.add_child(consumable_bar)

	# Discount notice, only when titles grant a shop discount.
	var discount := _get_shop_discount_percent()
	if discount > 0:
		var discount_label := _label("✦ Favor of your titles: %d%% off all prices ✦" % discount,
			load(CardFace.RULES_FONT_PATH), 20, StageSkin.c("end_edge"))
		discount_label.name = "Discount"
		discount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(discount_label)

	var artifacts_btn := _make_slab("Your Artifacts", Rect2(1180, PAGE_BOTTOM + 16, 230, 58), 28)
	artifacts_btn.pressed.connect(_on_view_artifacts)
	var map_btn := _make_slab("View Map", Rect2(1430, PAGE_BOTTOM + 16, 190, 58), 28)
	map_btn.pressed.connect(_on_view_map)
	var leave_btn := _make_slab("Leave Shop", Rect2(1640, PAGE_BOTTOM + 16, 220, 58), 30)
	leave_btn.pressed.connect(_on_leave)


## A button as the fight's End Turn is drawn: a slab of the desk, its words in the title face.
func _make_slab(text: String, rect: Rect2, font_size: int, parent: Control = null) -> Button:
	if parent == null:
		parent = self
	var btn := Button.new()
	btn.text = text
	# The title face stands tall in its line; the fight's End Turn pulls its lines in the same way.
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	btn.add_theme_font_override("font", load(CardFace.TITLE_FONT_PATH))
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_constant_override("line_spacing", -int(font_size * 0.35))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.set_border_width_all(2)
	style.bg_color = StageSkin.c("end_bg")
	style.border_color = StageSkin.c("end_edge")
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = style.bg_color.lightened(0.1)
	hover.border_color = style.border_color.lightened(0.25)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = style.bg_color.darkened(0.25)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", StageSkin.c("end_text"))
	btn.add_theme_color_override("font_hover_color", StageSkin.c("end_text").lightened(0.2))
	btn.custom_minimum_size = rect.size
	btn.position = rect.position
	btn.size = rect.size
	parent.add_child(btn)
	return btn


# ============================================================
# GOLD
# ============================================================

func _update_gold() -> void:
	gold_label.text = "Gold: %d" % RunManager.gold


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
	accept_event()
	# After the click has been handled, since a sale redraws the shelf the click came from.
	_buy_card.call_deferred(card)


func _buy_card(card: CardData) -> void:
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
	_refresh_wares()


## The card enlarged, with its rarity, flavor and keyword reminders; any click closes it.
func _open_inspect(card: CardData) -> void:
	_close_inspect()
	_hover_note.dismiss()
	_inspect = CardInspect.build(card, CardFace.build(card, null, CardSigil.build(card)), _close_inspect)
	add_child(_inspect)


func _close_inspect() -> void:
	if is_instance_valid(_inspect):
		_inspect.queue_free()
	_inspect = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_instance_valid(_inspect):
		_close_inspect()
		get_viewport().set_input_as_handled()
	elif is_instance_valid(_removal):
		_on_cancel_remove()
		get_viewport().set_input_as_handled()


# ============================================================
# BUYING RELICS
# ============================================================

func _on_shop_relic_input(event: InputEvent, relic: RelicData) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	_buy_relic.call_deferred(relic)


func _buy_relic(relic: RelicData) -> void:
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
	_refresh_wares()


# ============================================================
# BUYING PROVISIONS (CONSUMABLES)
# ============================================================

func _on_shop_consumable_input(event: InputEvent, item: ConsumableData) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	_buy_consumable.call_deferred(item)


func _buy_consumable(item: ConsumableData) -> void:
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
	_hover_note.dismiss()
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
	consumable_bar.refresh()
	_refresh_wares()


# ============================================================
# REMOVING CARDS
# ============================================================

func _on_remove_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	_on_remove_pressed.call_deferred()


func _on_remove_pressed() -> void:
	if is_instance_valid(_removal):
		_on_cancel_remove()
		return

	var cost := _effective_remove_cost()
	if RunManager.gold < cost:
		info_label.text = "Not enough gold! (Need %d)" % cost
		return

	if RunManager.current_deck.size() <= 1:
		info_label.text = "Can't remove your last card!"
		return

	_show_deck_for_removal()


## The deck as the map's deck view lays it out, over the desk's dim: a click on a card removes it.
func _show_deck_for_removal() -> void:
	_close_removal()
	_hover_note.dismiss()
	var cost := _effective_remove_cost()
	info_label.text = "Click a card to remove it (%d gold)" % cost

	_removal = Control.new()
	_removal.name = "Removal"
	_removal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_removal.mouse_filter = Control.MOUSE_FILTER_STOP  # the shelves under it take nothing
	add_child(_removal)
	_rect(_removal, Vector2.ZERO, Vector2(1920, 1080), Color(StageSkin.c("desk"), 0.95))
	var header := _label("Your Deck (%d cards)" % RunManager.current_deck.size(),
		load(CardFace.TITLE_FONT_PATH), 40, StageSkin.c("end_text"))
	header.position = Vector2(60, 34)
	_removal.add_child(header)
	var ask := _label("Click a card to remove it (%d gold)" % cost, load(CardFace.RULES_FONT_PATH), 26,
		StageSkin.c("ground"))
	ask.position = Vector2(60, 92)
	_removal.add_child(ask)
	var cancel := _make_slab("Cancel", Rect2(1700, 36, 160, 60), 30, _removal)
	cancel.pressed.connect(_on_cancel_remove)

	# Room above the first row for a lifted card, and a scroll for a deck past three rows.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 146)
	scroll.size = Vector2(1920, 1080 - 146 - 16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_removal.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 14)
	centre.add_child(pad)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = REMOVE_COLUMNS
	grid.add_theme_constant_override("h_separation", REMOVE_GAP)
	grid.add_theme_constant_override("v_separation", REMOVE_GAP)
	pad.add_child(grid)
	for i in RunManager.current_deck.size():
		grid.add_child(_removal_card(RunManager.current_deck[i], i))


func _removal_card(card: CardData, index: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = CardFace.SIZE * REMOVE_SCALE
	var shade := _shade(holder.custom_minimum_size)
	holder.add_child(shade)
	var face := CardFace.build(card, null, CardSigil.build(card))
	face.pivot_offset = CardFace.SIZE / 2.0
	face.scale = Vector2.ONE * REMOVE_SCALE
	face.position = CardFace.SIZE * (REMOVE_SCALE - 1.0) / 2.0
	holder.add_child(face)
	_ignore_mouse_recursive(holder)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	holder.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_on_remove_card.call_deferred(index))
	_lift_on_hover(holder, face, shade, HOVER_GROW)
	return holder


func _close_removal() -> void:
	if is_instance_valid(_removal):
		_removal.queue_free()
	_removal = null


func _on_cancel_remove() -> void:
	_close_removal()
	info_label.text = INFO_LINE


## One card goes, the gold is paid, and the page comes back with the deck's new count on the slip.
func _on_remove_card(index: int) -> void:
	if index < 0 or index >= RunManager.current_deck.size():
		return
	var card = RunManager.current_deck[index]
	RunManager.add_gold(-_effective_remove_cost())
	RunManager.remove_card_from_deck(index)
	AudioManager.play_sfx("card_exhaust")
	_close_removal()
	info_label.text = "Removed %s!" % card.card_name
	_update_gold()
	_refresh_wares()


# ============================================================
# LEAVE
# ============================================================

func _on_leave() -> void:
	AudioManager.play_sfx("button_click")
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


## Read-only map peek: doesn't leave the shop.
func _on_view_map() -> void:
	_hover_note.dismiss()
	MapPreviewOverlay.open(self)


## Read-only artifact review: the relics + titles you already carry, for purchase
## planning. Doesn't leave the shop or mutate anything.
func _on_view_artifacts() -> void:
	_hover_note.dismiss()
	ArtifactsOverlay.open(self)


# ============================================================
# PIECES
# ============================================================

func _layer() -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _rect(parent: Control, pos: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = pos
	r.size = rect_size
	r.color = color
	parent.add_child(r)
	return r


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The rules' face leaning, for the keeper's own words.
func _italic_face() -> FontVariation:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = load(CardFace.RULES_FONT_PATH)
		_italic.variation_transform = Transform2D(Vector2(1.0, 0.18), Vector2(0.0, 1.0), Vector2.ZERO)
	return _italic


func _price_colour(afford: bool) -> Color:
	return StageSkin.c("ink") if afford else StageSkin.c("card_rubric_attack")


func _rarity_colour(rarity: int) -> Color:
	match rarity:
		RelicData.RelicRarity.UNCOMMON:
			return StageSkin.c("card_uncommon")
		RelicData.RelicRarity.RARE:
			return StageSkin.c("card_rare")
		RelicData.RelicRarity.BOSS:
			return StageSkin.c("card_rubric_attack")
	return StageSkin.c("ink")


func _rarity_name(rarity: int) -> String:
	match rarity:
		RelicData.RelicRarity.UNCOMMON:
			return "Uncommon"
		RelicData.RelicRarity.RARE:
			return "Rare"
		RelicData.RelicRarity.BOSS:
			return "Boss"
	return "Common"


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)
