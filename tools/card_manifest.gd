extends Control
## CARD MANIFEST: an interactive QA view of every card face. The Passion TOGGLE at the top drives
## the live zone, so you can watch each school sigil empower / grey and the halo coin EBB in/out on
## a threshold crossing: the real combat behaviour (it reuses combat_scene._create_card_panel and
## _fade_coin_transitions, so what you see == what combat shows, with no drift). Cards are pulled
## straight from the pools, so new cards appear automatically as content grows.
##
## Run:  godot --path D:\Applications\Fable res://tools/card_manifest.tscn
## A reference PNG of the initial state is also written to screenshots/card_manifest.png.

const CombatScene = preload("res://scenes/combat/combat_scene.gd")
const COLUMNS := 6
const PNG_PATH := "D:/Applications/Fable/screenshots/card_manifest.png"

# Passion presets for the toggle, one value comfortably inside each tier.
const TIERS := [[-55, "HOLLOW"], [-30, "WAVERING"], [0, "STEADY"], [30, "INSPIRED"], [55, "BLAZING"]]

var _render_host: Control            # bare combat_scene, reused only for its card render
var _grid: GridContainer
var _cards: Array[CardData] = []
var _passion := 0
var _readout: Label


func _ready() -> void:
	RunManager.current_character = CharacterPool.build_emo_hybrid()
	RunManager.current_act = 1
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = 0
	_render_host = CombatScene.new()
	_cards = _all_cards()

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 10
	root.offset_right = -12
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "CARD MANIFEST: toggle Passion to watch the school sigils empower/grey and the halo coin EBB in/out (the real combat behaviour)"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	root.add_child(title)

	root.add_child(_build_toggle_bar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	_rebuild(false)

	# A reference PNG of the initial (Steady) state, so the layout can be eyeballed headlessly too.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("D:/Applications/Fable/screenshots")
	var err := img.save_png(PNG_PATH)
	print("MANIFEST PNG (%dx%d) -> %s  [err %d]" % [img.get_width(), img.get_height(), PNG_PATH, err])


func _build_toggle_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var plabel := Label.new()
	plabel.text = "Passion:"
	plabel.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
	bar.add_child(plabel)

	var minus := Button.new()
	minus.text = "−5"
	minus.pressed.connect(func(): _set_passion(clampi(_passion - 5, -60, 60)))
	bar.add_child(minus)

	for t in TIERS:
		var b := Button.new()
		b.text = "%s (%d)" % [t[1], t[0]]
		var val: int = t[0]
		b.pressed.connect(func(): _set_passion(val))
		bar.add_child(b)

	var plus := Button.new()
	plus.text = "+5"
	plus.pressed.connect(func(): _set_passion(clampi(_passion + 5, -60, 60)))
	bar.add_child(plus)

	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_color", Color(0.85, 0.8, 0.45))
	bar.add_child(_readout)
	return bar


## Set the live Passion and re-render, animating the halo-coin fade across the crossing.
func _set_passion(value: int) -> void:
	if value == _passion:
		return
	var old := _passion
	_passion = value
	RunManager.passion.current_value = value
	_rebuild(true, old)


func _rebuild(animate: bool, old_value: int = 0) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_render_host._hand_coins.clear()
	for card in _cards:
		_grid.add_child(_render_host._create_card_panel(card.duplicate_card()))
	_update_readout()
	if animate:
		# Panels (and their coin discs) are now in-tree, so the fade tweens run.
		_render_host._fade_coin_transitions(old_value, _passion)


func _update_readout() -> void:
	var tier = RunManager.get_passion_tier()
	_readout.text = "    now: %d  (%s)    ·    Water zone %s    ·    Physical zone %s" % [
		_passion, PassionState.tier_name(tier),
		_zone_str(CardData.PersonalityType.PRIMARY), _zone_str(CardData.PersonalityType.SECONDARY)]


func _zone_str(pers: CardData.PersonalityType) -> String:
	var zm := CombatEngine.zone_multiplier(pers)
	if zm > 1.0:
		return "+%d%%" % roundi((zm - 1.0) * 100.0)
	if zm < 1.0:
		return "-%d%%" % roundi((1.0 - zm) * 100.0)
	return "flat"


## Every card, straight from the pools (dedup by name) so new content shows up automatically:
## the starter deck first, then Water (primary), Physical (secondary), and the generic pool.
func _all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	var seen := {}
	for src in [CharacterPool.emo_starting_deck(), CardPool.build_emo_primary_pool(),
			CardPool.build_emo_secondary_pool(), CardPool._build_generic_pool()]:
		for c in src:
			if not seen.has(c.card_name):
				seen[c.card_name] = true
				out.append(c)
	return out


func _exit_tree() -> void:
	if is_instance_valid(_render_host):
		_render_host.free()
