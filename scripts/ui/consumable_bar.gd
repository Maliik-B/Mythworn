class_name ConsumableBar
extends HBoxContainer
## The pack: the two consumable slots, as small buttons, on the map bar and the combat top bar.
## Click an item to use it, the cross beside it to drop it. Which items are usable depends on
## where the bar sits (a heal is fine on either, a supper is map only, an oil is combat only),
## and an item that cannot be used right now stays visible and disabled with the reason in its
## tooltip, so the player sees what they are carrying and why it is waiting.
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

var mode: Mode = Mode.MAP
var engine: CombatEngine = null

var _confirm: ConfirmationDialog
var _pending_drop: ConsumableData = null
var _shown_key := "(never built)"  # what the slots were last built from; see _state_key


## Builds the bar's contents and wires it to the run's pack. `combat_engine` is required in
## COMBAT mode and ignored on the map.
func setup(bar_mode: Mode, combat_engine: CombatEngine = null) -> void:
	mode = bar_mode
	engine = combat_engine
	add_theme_constant_override("separation", 8)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_on_drop_confirmed)
	add_child(_confirm)
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
	# Out of the row now, not at the end of the frame: a slot still waiting to be freed counts
	# toward the bar's width, and the bar's width toward the whole layout's.
	for child in get_children():
		if child != _confirm:
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
			empty.tooltip_text = "An empty slot. You can carry two consumables, and nothing widens that."
			add_child(empty)


## Everything a slot shows, as one string: each held item, whether it is spent, and why it waits.
func _state_key() -> String:
	var parts: PackedStringArray = []
	for item in RunManager.consumables:
		var spent := RunManager.is_consumable_spent(item)
		parts.append("%s|%s|%s" % [item.id, spent, _why_unusable(item, spent)])
	return ";".join(parts)


func _make_slot(item: ConsumableData) -> Control:
	var slot := HBoxContainer.new()
	slot.add_theme_constant_override("separation", 2)

	var spent := RunManager.is_consumable_spent(item)
	var why_not := _why_unusable(item, spent)

	var use_btn := Button.new()
	use_btn.flat = true
	use_btn.text = item.display_name + (" (spent)" if spent else "")
	use_btn.add_theme_font_size_override("font_size", 18)
	var tint := COLOR_SPENT if spent else COLOR_ITEM
	use_btn.add_theme_color_override("font_color", tint)
	use_btn.add_theme_color_override("font_hover_color", COLOR_ITEM_HOVER)
	use_btn.add_theme_color_override("font_disabled_color", COLOR_SPENT if spent else COLOR_DISABLED)
	use_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	use_btn.tooltip_text = _tooltip_for(item, spent, why_not)
	use_btn.disabled = why_not != ""
	if use_btn.disabled:
		use_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	use_btn.pressed.connect(_on_use_pressed.bind(item))
	slot.add_child(use_btn)

	var drop_btn := Button.new()
	drop_btn.flat = true
	drop_btn.text = "x"
	drop_btn.add_theme_font_size_override("font_size", 16)
	drop_btn.add_theme_color_override("font_color", Color(0.6, 0.45, 0.4))
	drop_btn.add_theme_color_override("font_hover_color", Color(0.95, 0.6, 0.5))
	drop_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	drop_btn.tooltip_text = "Drop %s to free the slot." % item.display_name
	drop_btn.pressed.connect(_on_drop_pressed.bind(item))
	slot.add_child(drop_btn)
	return slot


## The reason an item cannot be used here and now, or "" if it can. Shown in the tooltip, so a
## waiting item is never a silent dead button.
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


func _tooltip_for(item: ConsumableData, spent: bool, why_not: String) -> String:
	var text := item.description
	if item.flavor != "":
		text += "\n" + item.flavor
	text += "\n" + item.use_context_label()
	if why_not != "" and not spent:
		text += "\n(" + why_not + ")"
	elif spent:
		text += "\n(" + why_not + ")"
	return text


func _on_use_pressed(item: ConsumableData) -> void:
	AudioManager.play_sfx("button_click")
	var ok := false
	if mode == Mode.COMBAT:
		ok = engine != null and engine.use_consumable(item)
	else:
		ok = RunManager.use_consumable_on_map(item)
	if ok:
		item_used.emit(item)


func _on_drop_pressed(item: ConsumableData) -> void:
	AudioManager.play_sfx("button_click")
	_pending_drop = item
	_confirm.dialog_text = "Drop %s? It cannot be picked back up." % item.display_name
	_confirm.popup_centered()


func _on_drop_confirmed() -> void:
	if _pending_drop != null:
		RunManager.discard_consumable(_pending_drop)
	_pending_drop = null
