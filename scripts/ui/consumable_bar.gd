class_name ConsumableBar
extends HBoxContainer
## The pack: the two consumable slots, as small buttons, on the map bar and the combat top bar.
## Click an item for its menu: Use, or Drop. Which items are usable depends on where the bar sits
## (a heal is fine on either, a supper is map only, an oil is combat only), and an item that cannot
## be used right now stays visible, dimmed, with the reason in its HoverNote panel and on its greyed
## Use, so the player sees what they are carrying and why it is waiting. The host supplies the
## HoverNote, and keeps it down while the menu is open (is_menu_open).
##
## One script for both places. The map hands it nothing; combat hands it the live engine, since
## the combat engine owns the effects that touch a fight.

enum Mode { MAP, COMBAT }

## Emitted after an item has been used, so the host can log it and redraw its own readouts.
signal item_used(item: ConsumableData)

const COLOR_ITEM := Color(0.86, 0.78, 0.55)
const COLOR_ITEM_HOVER := Color(1.0, 0.92, 0.65)
const COLOR_DISABLED := Color(0.5, 0.48, 0.42)
const COLOR_SPENT := Color(0.62, 0.5, 0.42)
const COLOR_EMPTY := Color(0.38, 0.36, 0.33)

const MENU_W := 190.0
const MENU_PAD := 10.0
const MENU_GAP := 6.0  # between the item and its menu
const MENU_USE_SIZE := 22
const MENU_DROP_SIZE := 20
const MENU_REASON_SIZE := 16

var mode: Mode = Mode.MAP
var engine: CombatEngine = null

var _shown_key := "(never built)"  # what the slots were last built from; see _state_key
var _menu_layer: CanvasLayer = null
var _menu: PanelContainer = null
var _menu_item: ConsumableData = null


## Builds the bar's contents and wires it to the run's pack. `combat_engine` is required in
## COMBAT mode and ignored on the map.
func setup(bar_mode: Mode, combat_engine: CombatEngine = null) -> void:
	mode = bar_mode
	engine = combat_engine
	add_theme_constant_override("separation", 8)
	# The menu draws over everything, the host's modulate on the bar included.
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 97  # under the HoverNote (98), the pause menu and the fade
	add_child(_menu_layer)
	if not Events.consumables_changed.is_connected(refresh):
		Events.consumables_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	if Events.consumables_changed.is_connected(refresh):
		Events.consumables_changed.disconnect(refresh)


## Brings the slots up to date with the run's pack. Hosts call this whenever something that might
## change what is usable has moved (combat's HP and phase), and the pack's own signal calls it on
## any change; the slots are rebuilt only when what they would show is different.
func refresh() -> void:
	var key := _state_key()
	if key == _shown_key:
		return
	_shown_key = key
	close_menu()
	# Out of the row now, not at the end of the frame: a slot still waiting to be freed counts
	# toward the bar's width, and the bar's width toward the whole layout's.
	for child in get_children():
		if child != _menu_layer:
			remove_child(child)
			child.queue_free()
	var caption := Label.new()
	caption.text = "Pack:"
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color(0.7, 0.66, 0.5))
	add_child(caption)
	for i in RunManager.CONSUMABLE_SLOTS:
		if i < RunManager.consumables.size():
			add_child(_make_slot(RunManager.consumables[i]))
		else:
			var empty := Label.new()
			empty.text = "[empty]"
			empty.add_theme_font_size_override("font_size", 18)
			empty.add_theme_color_override("font_color", COLOR_EMPTY)
			empty.mouse_filter = Control.MOUSE_FILTER_STOP
			HoverNote.mark(empty, "Empty slot", "You can carry two consumables, and nothing widens that.")
			add_child(empty)


## Everything a slot shows, as one string: each held item, whether it is spent, and why it waits.
func _state_key() -> String:
	var parts: PackedStringArray = []
	for item in RunManager.consumables:
		var spent := RunManager.is_consumable_spent(item)
		parts.append("%s|%s|%s" % [item.id, spent, _why_unusable(item, spent)])
	return ";".join(parts)


## An item in the pack. Never disabled: a waiting item still opens its menu, so it can be dropped.
func _make_slot(item: ConsumableData) -> Control:
	var spent := RunManager.is_consumable_spent(item)
	var why_not := _why_unusable(item, spent)

	var button := Button.new()
	button.flat = true
	button.text = item.display_name + (" (spent)" if spent else "")
	button.add_theme_font_size_override("font_size", 18)
	var tint := COLOR_ITEM
	if why_not != "":
		tint = COLOR_SPENT if spent else COLOR_DISABLED
	button.add_theme_color_override("font_color", tint)
	button.add_theme_color_override("font_hover_color", COLOR_ITEM_HOVER)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_mark_item(button, item, spent, why_not)
	button.pressed.connect(_open_menu.bind(item, button))
	return button


## The reason an item cannot be used here and now, or "" if it can. Shown in its panel and on the
## menu's greyed Use, so a waiting item is never a silent dead button.
func _why_unusable(item: ConsumableData, spent: bool) -> String:
	if spent:
		return "It has nothing left to do. Drop it to free the slot."
	if item.is_quest_item():
		return "Carried to its payoff. It is spent there, not here."
	if mode == Mode.MAP:
		if not item.usable_on_map:
			return "Combat only."
		if not RunManager.can_use_consumable_on_map(item):
			return "Already at full health."
		return ""
	# Combat.
	if not item.usable_in_combat:
		return "Map only."
	if engine == null or not engine.can_use_consumable(item):
		if engine != null and engine.phase != CombatEngine.Phase.PLAYER_TURN:
			return "Wait for your turn."
		return "It would do nothing right now."
	return ""


## The item's panel: what it does, where it can be used, and why it waits if it does.
func _mark_item(button: Control, item: ConsumableData, spent: bool, why_not: String) -> void:
	var body := item.description
	if why_not != "":
		body += "\n(" + why_not + ")"
	HoverNote.mark(button, item.display_name + (" (spent)" if spent else ""), body,
		item.use_context_label(), item.flavor)


# ============================================================
# THE MENU: Use or Drop
# ============================================================

## True while an item's menu is open. Hosts keep the HoverNote down meanwhile.
func is_menu_open() -> bool:
	return _menu != null


## The item whose menu is open, or null. For tests.
func menu_item() -> ConsumableData:
	return _menu_item


func close_menu() -> void:
	if _menu != null:
		_menu_layer.remove_child(_menu)
		_menu.queue_free()
	_menu = null
	_menu_item = null


## Opens `item`'s menu by its button: below it, or above it when the screen ends first (the map's
## bar is at the bottom). A second click on the same item closes it.
func _open_menu(item: ConsumableData, anchor: Control) -> void:
	AudioManager.play_sfx("button_click")
	if _menu_item == item:
		close_menu()
		return
	close_menu()
	_menu_item = item
	var why_not := _why_unusable(item, RunManager.is_consumable_spent(item))

	_menu = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = StageSkin.c("note_bg")
	style.border_color = StageSkin.c("note_edge")
	style.set_border_width_all(2)
	style.set_corner_radius_all(0 if StageSkin.is_page() else 8)
	style.set_content_margin_all(MENU_PAD)
	_menu.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_menu.add_child(column)

	var use := _menu_button("Use", MENU_USE_SIZE, StageSkin.c("note_ink"))
	use.disabled = why_not != ""
	use.pressed.connect(_on_menu_use)
	column.add_child(use)
	if why_not != "":
		var reason := Label.new()
		reason.text = why_not
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.custom_minimum_size.x = MENU_W - MENU_PAD * 2.0
		reason.add_theme_font_override("font", load(CardFace.RULES_FONT_PATH))
		reason.add_theme_font_size_override("font_size", MENU_REASON_SIZE)
		reason.add_theme_color_override("font_color", StageSkin.c("note_dim"))
		column.add_child(reason)
	var rule := ColorRect.new()
	rule.color = StageSkin.c("note_dim")
	rule.custom_minimum_size = Vector2(MENU_W - MENU_PAD * 2.0, 1)
	column.add_child(rule)
	var drop := _menu_button("Drop", MENU_DROP_SIZE, StageSkin.c("note_warn"))
	drop.pressed.connect(_on_menu_drop)
	column.add_child(drop)

	_menu_layer.add_child(_menu)
	var menu_size := _menu.get_combined_minimum_size()
	_menu.size = menu_size
	var around := anchor.get_global_rect()
	var screen := get_viewport().get_visible_rect().size
	var y := around.end.y + MENU_GAP
	if y + menu_size.y > screen.y:
		y = around.position.y - menu_size.y - MENU_GAP
	_menu.position = Vector2(clampf(around.position.x, 0.0, screen.x - menu_size.x), y)


func _menu_button(text: String, font_size: int, ink: Color) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", load(CardFace.TITLE_FONT_PATH))
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink.lightened(0.25))
	button.add_theme_color_override("font_disabled_color", StageSkin.c("note_dim"))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _on_menu_use() -> void:
	var item := _menu_item
	close_menu()
	if item != null:
		_on_use_pressed(item)


func _on_menu_drop() -> void:
	var item := _menu_item
	close_menu()
	if item != null:
		AudioManager.play_sfx("button_click")
		RunManager.discard_consumable(item)


## A click outside an open menu closes it and goes no further, so it cannot also play a card or
## pick a node; Escape closes it too.
func _input(event: InputEvent) -> void:
	if _menu == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if _menu.get_global_rect().has_point(event.position):
			return
		for child in get_children():
			if child is Button and child.get_global_rect().has_point(event.position):
				return  # another item's own click opens its menu, or closes this one
		close_menu()
		get_viewport().set_input_as_handled()


func _on_use_pressed(item: ConsumableData) -> void:
	AudioManager.play_sfx("button_click")
	var ok := false
	if mode == Mode.COMBAT:
		ok = engine != null and engine.use_consumable(item)
	else:
		ok = RunManager.use_consumable_on_map(item)
	if ok:
		item_used.emit(item)
