extends Control
## Minimal test combat scene. Builds UI programmatically, wires into the
## Events bus, creates sample cards/enemies, and runs a full combat loop.

# -- UI references (built in _build_ui) --
var combat_engine: CombatEngine
var hand_container: HBoxContainer
var _hand_spacer: Control  # left of the hand, keeps it centred on the screen against End Turn
var enemy_container: HBoxContainer
var _player_bar: PanelContainer
var hp_label: Label
var energy_label: Label
var block_label: Label
var passion_label: Label
var _passion_popup: Control
var _map_overlay: MapPreviewOverlay = null  # read-only route peek (see _on_view_map)
var player_status_prefix: Label
var player_status_chips: HFlowContainer
var player_powers_prefix: Label
var player_powers_chips: HFlowContainer
var draw_label: Button
var discard_label: Button
var exhaust_label: Button
var end_turn_btn: Button
## The pack, centred in the top bar: the held consumables, usable on the player's turn.
var consumable_bar: ConsumableBar
var log_text: RichTextLabel
var pile_popup: PanelContainer

# -- Interaction state --
var selected_card: CardData = null
var card_nodes: Dictionary = {} # CardData -> PanelContainer
var enemy_nodes: Dictionary = {} # EnemyCombatState -> PanelContainer
var _enemy_anims: Dictionary = {} # EnemyCombatState -> animator state dict (see _build_enemy_portrait)
var _hand_coins: Dictionary = {} # CardData -> halo-coin Panel (pole cards only), for threshold fades


var continue_btn: Button
var _main_container: MarginContainer
var _hover_popup: PanelContainer
var _status_pin: PanelContainer  # click-pinned status/effect description (see _show_status_pin)
var _last_play_ms := -100000  # when a card last played, for the double-click guard

# Enemy sprite animation. Each enemy maps to a "sprite set" (one LuizMelo sheet folder),
# and each set lists its strips as [file, frame_count, fps]. Every strip is a horizontal
# row of square cells (cell size = the PNG's height); the animator (see _process /
# _anim_tick) steps the AtlasTexture region across the row. Real per-enemy art is the B5 track --
# these are shared CC0 stand-ins until it lands. Attack strips run fast so the swing lands on the
# engine's wind-up beat (CombatEngine.start_enemy_turn): change one with the other.
#
# Bodies are drawn at one whole-number scale per fight, feet on one ground: a regular at 4, a boss
# who stands alone at 6, and small things stay small. Where a body sits in its cell is measured
# from the sheet (see _sheet_body), so a new sheet needs nothing but its entry here.
const BODY_SCALE_REGULAR := 4
const BODY_SCALE_BOSS := 6
const STAGE_FEET_Y := 556.0  # bodies stand here, a little in front of CombatStage.GROUND_LINE_Y
const STAGE_TOP_Y := 68.0  # the top of the enemy area, under the top bar
const BODY_MAX_H := STAGE_FEET_Y - STAGE_TOP_Y
const BODY_FIT_H := STAGE_FEET_Y - 56.0  # a body may rise to the top bar's lower edge
const STATUS_COLUMN_W := 124.0  # beside the feet, on each side, so statuses never move a body
const ENEMY_MIN_W := 320.0
const LOG_RECT := Rect2(1370, 68, 520, 624)
# A boss's line runs as a subtitle on the ground under his feet, where his name and bar were.
const STAGE_LINE_RECT := Rect2(440, 562, 1040, 132)  # inside the centre square, for a phone crop
const STAGE_LINE_SIZE := 46
const STAGE_LINE_CHARS_PER_SEC := 30.0
const STAGE_LINE_HOLD := 1.7
const BREAK_DRAIN_TIME := 1.6
const COIN_STAGGER := 0.04
const TARGET_LIT_BODY := Color(1.16, 1.13, 1.06)
const TARGET_LIGHT_FADE := 0.08
const DRAG_CARD_CLEARANCE := 8.0
const DOUBLE_CLICK_GUARD_MS := 250
const CARD_FLIGHT := 0.14
const END_TURN_W := 140.0
const MAIN_W := 1860.0  # the 1920 frame less the main margins
const HAND_SEP := 10
const BOTTOM_ROW_SEP := 20
const CHIP_SEP := 6
const CHIP_ROW_MAX_W := 400.0

const STAGE_BODY_SHADER := preload("res://assets/ui/stage_body.gdshader")

const SPRITE_SETS := {
	"goblin": {
		"dir": "res://assets/sprites/enemies/monsters_main/Monsters_Creatures_Fantasy/Goblin/",
		"baked": "res://assets/sprites/baked/goblin/",
		"cell": 150,
		"anims": {"idle": ["Idle.png", 4, 7], "attack": ["Attack.png", 8, 18], "hit": ["Take Hit.png", 4, 13], "death": ["Death.png", 4, 9]},
	},
	"skeleton": {
		"dir": "res://assets/sprites/enemies/monsters_main/Monsters_Creatures_Fantasy/Skeleton/",
		"baked": "res://assets/sprites/baked/skeleton/", "lapis": true,
		"cell": 150,
		"anims": {"idle": ["Idle.png", 4, 7], "attack": ["Attack.png", 8, 18], "hit": ["Take Hit.png", 4, 13], "death": ["Death.png", 4, 9]},
	},
	"flyingeye": {
		"dir": "res://assets/sprites/enemies/monsters_main/Monsters_Creatures_Fantasy/Flying eye/",
		"baked": "res://assets/sprites/baked/flyingeye/",
		"cell": 150,
		"anims": {"idle": ["Flight.png", 8, 10], "attack": ["Attack.png", 8, 18], "hit": ["Take Hit.png", 4, 13], "death": ["Death.png", 4, 9]},
	},
	"mushroom": {
		"dir": "res://assets/sprites/enemies/monsters_main/Monsters_Creatures_Fantasy/Mushroom/",
		"baked": "res://assets/sprites/baked/mushroom/",
		"cell": 150,
		"anims": {"idle": ["Idle.png", 4, 7], "attack": ["Attack.png", 8, 18], "hit": ["Take Hit.png", 4, 13], "death": ["Death.png", 4, 9]},
	},
	"worm": {
		"dir": "res://assets/sprites/enemies/fire_worm/Fire Worm/Sprites/Worm/",
		"baked": "res://assets/sprites/baked/worm/",
		"cell": 90,
		"anims": {"idle": ["Idle.png", 9, 10], "attack": ["Attack.png", 16, 24], "hit": ["Get Hit.png", 3, 12], "death": ["Death.png", 8, 10]},
	},
	"wizard2": {
		"dir": "res://assets/sprites/bosses/evil_wizard_2/EVil Wizard 2/Sprites/",
		"baked": "res://assets/sprites/baked/wizard2/",
		"cell": 250,
		"anims": {"idle": ["Idle.png", 8, 9], "attack": ["Attack1.png", 8, 18], "hit": ["Take hit.png", 3, 12], "death": ["Death.png", 7, 10]},
	},
	# Sir Caedmon's one slot, one line, as tools/bake_sheet.py prints it: a bought sheet replaces this
	# line and nothing else. A "break" strip, given with --strip, plays as his bar breaks in place of
	# "hit". A stand-in until then: the Man-at-Arms in living colour, whose lapis is what drains.
	"caedmon": {"dir": "res://assets/sprites/baked/caedmon/", "baked": "res://assets/sprites/baked/caedmon/", "lapis": true, "fw": 184, "fh": 137, "anims": {"idle": ["Idle.png", 6, 8], "attack": ["Attack1.png", 4, 18], "hit": ["Hit.png", 3, 13], "death": ["Death.png", 9, 10]}},
	# The Man-at-Arms in living colour: the source the shader drains for the hollow one beside him.
	"man_at_arms_whole": {
		"dir": "res://assets/sprites/enemies/camelot/man_at_arms_whole/",
		"baked": "res://assets/sprites/baked/man_at_arms_whole/", "lapis": true,
		"fw": 184, "fh": 137,
		"anims": {"idle": ["Idle.png", 6, 8], "attack": ["Attack1.png", 4, 18], "hit": ["Hit.png", 3, 13], "death": ["Death.png", 9, 10]},
	},
	# Real Camelot per-enemy art (LuizMelo, CC0), corruption-recolored. Non-square frames.
	"medieval_warrior": {
		"dir": "res://assets/sprites/enemies/camelot/man_at_arms/",
		"baked": "res://assets/sprites/baked/medieval_warrior/",
		"fw": 184, "fh": 137,
		"anims": {"idle": ["Idle.png", 6, 8], "attack": ["Attack1.png", 4, 18], "hit": ["Hit.png", 3, 13], "death": ["Death.png", 9, 10]},
	},
}

# enemy_name -> sprite set. Shared CC0 stand-ins chosen so no paired composition shows two
# identical sprites -- e.g. the Pikeman is a goblin so pikeman_knight reads goblin + skeleton,
# and the Herald is the robed wizard so herald_knight doesn't double the skeleton. Distinct
# per-enemy art is the B5 track item.
const ENEMY_SPRITE_SET := {
	"Slime": "mushroom",
	"Goblin": "goblin",
	"Orc Brute": "skeleton",
	"Realm Guardian": "flyingeye",
	# Camelot regular roster.
	"Unmarked Knight": "skeleton",
	"Court Conspirator": "goblin",
	"Empty Harness": "worm",
	"Realm Shade": "flyingeye",
	# Camelot elites + Act-1 boss.
	"Champion of the Usurper": "skeleton",
	"The Beast at the Stone": "skeleton",
	"The False Prophet": "wizard2",
	"Sir Caedmon": "caedmon",
	"Hollow Warden": "worm",
	"Fable's End": "wizard2",
	# Sep/Oct-2026 roster (thickening + content furnishing).
	"Man-at-Arms": "medieval_warrior",
	"Masterless Squire": "goblin",
	"Prophet's Acolyte": "wizard2",
	"Bannerless Pikeman": "goblin",
	"Hollow Herald": "wizard2",
	"Wasting Knight": "skeleton",
	"The Iron Verdict": "skeleton",
	"The Hollow Prelate": "wizard2",
	# Raider questline band: the Boar reads big (worm sheet) vs the two small goblin raiders.
	"The Boar": "worm",
	"Weald Raider": "goblin",
	# The Reliquary chapel beast -- ethereal/reforming, so the floating-eye sheet.
	"The Shattered Choir": "flyingeye",
}
# Card icon mapping: card_name -> full res:// path
# Card art icons live in CardVisuals (single source, shared with the reward screen
# and the deck / Passion full-card renders).
var _hp_trail_bars: Dictionary = {} # ProgressBar -> trail ProgressBar
var _damage_flash: ColorRect
var _dragging_card: CardData = null
var _drag_panel: PanelContainer = null
var _drag_offset := Vector2.ZERO
var _drag_hint: Label = null        # "right-click to cancel" affordance during a drag
var _enemy_lights: Dictionary = {}  # EnemyCombatState -> the targeting light on it (see _set_lit_enemies)
var _sheet_bodies: Dictionary = {}  # sprite set key -> where its body sits in the cell (see _sheet_body)
var _shadow_tex: GradientTexture2D = null
var _stage: CombatStage = null
var _stage_line: Label = null
var _passion_gauge: PassionGauge = null
var _lapis_taken := false  # a body in this fight already carries the frame's lapis
var _target_glow_tex: GradientTexture2D = null
var _target_glow_mat: CanvasItemMaterial = null


func _ready() -> void:
	_build_ui()
	_connect_events()
	_start_combat()


# ============================================================
# ENEMY SPRITE ANIMATION
# Idle loops; attack/hit/death play once (on combat events) then fall back to idle.
# Driven from _process so a single loop ticks every live enemy animator.
# ============================================================

func _process(delta: float) -> void:
	if _enemy_anims.is_empty():
		return
	for enemy in _enemy_anims:
		_anim_tick(_enemy_anims[enemy], delta)


## Where the body sits in a sheet: the columns of its first idle frame and the rows of the whole
## idle strip, so an idle that bobs still stands on one spot. Measured once per sheet.
func _sheet_body(set_key: String) -> Rect2i:
	if _sheet_bodies.has(set_key):
		return _sheet_bodies[set_key]
	var sset: Dictionary = SPRITE_SETS[set_key]
	var fw: int = int(sset.get("fw", sset.get("cell", 150)))
	var fh: int = int(sset.get("fh", sset.get("cell", 150)))
	var strip: Image = load(_sheet_dir(sset) + sset["anims"]["idle"][0]).get_image()
	var rows := strip.get_used_rect()
	var columns := strip.get_region(Rect2i(0, 0, fw, fh)).get_used_rect()
	var body := Rect2i(columns.position.x, rows.position.y, columns.size.x, rows.size.y)
	_sheet_bodies[set_key] = body
	return body


## Where a sprite set's strips are in the look that is on: the page wants its bake.
func _sheet_dir(sset: Dictionary) -> String:
	return sset["baked"] if StageSkin.is_page() and sset.has("baked") else sset["dir"]


## This fight's scale for a body: the boss who stands alone is large, everyone else regular. A
## sheet too tall for the stage at that scale steps down until it fits under the top bar.
func _body_scale(set_key: String) -> int:
	var wanted := BODY_SCALE_REGULAR
	if combat_engine.enemies.size() == 1 and (RunManager.pending_relic_is_boss \
			or combat_engine.enemies[0].enemy_data.phase_hps.size() > 1):
		wanted = BODY_SCALE_BOSS
	return mini(wanted, floori(BODY_FIT_H / _sheet_body(set_key).size.y))


## Builds the animated body for an enemy and registers its animator in _enemy_anims. Returns the
## stand: a box exactly the body's size, on the ground, that everything aimed at the enemy (numbers,
## lights, the lunge, a thrown card) reads. The cell hangs off it uncropped, so a swing can leave it.
func _build_enemy_body(set_key: String, enemy) -> Control:
	var sset: Dictionary = SPRITE_SETS[set_key]
	# Frame cell: square sets give just "cell"; packs with non-square frames give fw/fh.
	var fw: int = int(sset.get("fw", sset.get("cell", 150)))
	var fh: int = int(sset.get("fh", sset.get("cell", 150)))
	var scale_px := _body_scale(set_key)
	var body := _sheet_body(set_key)
	# Preload every strip once so state swaps are instant.
	var textures := {}
	for state in sset["anims"]:
		textures[state] = load(_sheet_dir(sset) + sset["anims"][state][0])
	var atlas := AtlasTexture.new()
	atlas.atlas = textures["idle"]
	atlas.region = Rect2(0, 0, fw, fh)

	var stand := _make_stand(Vector2(body.size) * scale_px)
	var portrait := TextureRect.new()
	portrait.texture = atlas
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size = Vector2(fw, fh) * scale_px
	portrait.position = -Vector2(body.position) * scale_px
	var mat := ShaderMaterial.new()
	mat.shader = STAGE_BODY_SHADER
	mat.set_shader_parameter("baked", _sheet_dir(sset) == sset.get("baked", ""))
	# One lapis object to a frame: the first body in the fight to carry it keeps it.
	var drained: float = enemy.enemy_data.drained
	if sset.get("lapis", false) and StageSkin.is_page() and drained <= 0.0:
		drained = 1.0 if _lapis_taken else 0.0
		_lapis_taken = true
	mat.set_shader_parameter("drain", drained)
	portrait.material = mat
	stand.add_child(_make_body_shadow())
	stand.add_child(_make_target_light(enemy, portrait))
	stand.add_child(portrait)

	var anim := {
		"set": set_key, "fw": fw, "fh": fh, "atlas": atlas, "rect": portrait,
		"textures": textures, "state": "idle", "frame": 0, "elapsed": 0.0,
		"frames": 1, "fps": 7.0, "loop": true,
	}
	_enemy_anims[enemy] = anim
	_anim_set_state(anim, "idle")
	return stand


## A box of the body's size, standing on the ground at the middle of the enemy's column.
func _make_stand(body_size: Vector2) -> Control:
	var stand := Control.new()
	stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stand.anchor_left = 0.5
	stand.anchor_right = 0.5
	stand.anchor_top = 1.0
	stand.anchor_bottom = 1.0
	stand.offset_left = -body_size.x / 2.0
	stand.offset_right = body_size.x / 2.0
	stand.offset_top = -body_size.y
	stand.offset_bottom = 0.0
	stand.pivot_offset = Vector2(body_size.x / 2.0, body_size.y)
	return stand


## The shadow on the ground under a body. Anchored to the stand, so it fits any size of body.
func _make_body_shadow() -> TextureRect:
	if _shadow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		grad.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = grad
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to = Vector2(1.0, 0.5)
	var shadow := TextureRect.new()
	shadow.texture = _shadow_tex
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.modulate = StageSkin.c("shadow")
	shadow.anchor_left = -0.12
	shadow.anchor_right = 1.12
	shadow.anchor_bottom = 1.0
	shadow.anchor_top = 1.0
	shadow.offset_top = -9.0
	shadow.offset_bottom = 9.0
	return shadow


## Switches an animator to a state (idle/attack/hit/death). Only idle loops; the others
## play through once and _anim_tick returns them to idle.
func _anim_set_state(anim: Dictionary, state: String) -> void:
	var sset: Dictionary = SPRITE_SETS[anim["set"]]
	if not sset["anims"].has(state):
		state = "idle"
	var info: Array = sset["anims"][state]
	anim["atlas"].atlas = anim["textures"][state]
	anim["frames"] = int(info[1])
	anim["fps"] = float(info[2])
	anim["loop"] = (state == "idle")
	anim["state"] = state
	anim["frame"] = 0
	anim["elapsed"] = 0.0
	_anim_apply_frame(anim)


func _anim_apply_frame(anim: Dictionary) -> void:
	var fw: int = int(anim["fw"])
	anim["atlas"].region = Rect2(anim["frame"] * fw, 0, fw, int(anim["fh"]))


func _anim_tick(anim: Dictionary, delta: float) -> void:
	if not is_instance_valid(anim.get("rect")):
		return
	var fps: float = anim["fps"]
	if fps <= 0.0:
		return
	anim["elapsed"] += delta
	var frame_time := 1.0 / fps
	while anim["elapsed"] >= frame_time:
		anim["elapsed"] -= frame_time
		anim["frame"] = int(anim["frame"]) + 1
		if anim["frame"] >= int(anim["frames"]):
			if anim["loop"]:
				anim["frame"] = 0
			else:
				# One-shot done: hold its last frame a beat, then return to idle.
				anim["frame"] = int(anim["frames"]) - 1
				_anim_apply_frame(anim)
				_anim_set_state(anim, "idle")
				return
		_anim_apply_frame(anim)


## Plays a one-shot state on an enemy's animator (no-op if it has none, or is dead).
func _enemy_play(enemy, state: String) -> void:
	var anim = _enemy_anims.get(enemy)
	if anim == null or not is_instance_valid(anim.get("rect")):
		return
	if anim["state"] == "death":
		return
	_anim_set_state(anim, state)


func _input(event: InputEvent) -> void:
	# The map-peek overlay is modal (own dim backdrop + Close). Since _input runs
	# before GUI routing, a click here would otherwise hit-test status chips behind
	# the overlay and swallow the event before its backdrop/Close could. Yield to it.
	if is_instance_valid(_map_overlay):
		return

	# Status-chip click, resolved before GUI routing. Clicking a status/effect chip pins
	# its description (immediate, and it stays until the next click elsewhere); clicking
	# anywhere else dismisses an open pin. Manual hit-testing (rather than the chip's
	# gui_input) because the chips live in PASS-filtered flow containers that don't
	# reliably deliver gui_input, and consuming the event here stops an enemy-side chip
	# click from also targeting the enemy behind it.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not _dragging_card:
		var chip := _status_chip_at(event.global_position)
		if chip:
			_show_status_pin(chip, chip.get_meta("status_effect"), chip.get_meta("status_stacks"))
			get_viewport().set_input_as_handled()
			return
		if _status_pin:
			_hide_status_pin()

	# While a card is mid-drag, own motion + release HERE (before GUI routing) so the
	# drop always resolves. If the mouse-up falls through to _unhandled_input instead,
	# any card/enemy Control under the cursor can swallow it — leaving _dragging_card
	# set and soft-locking the turn (every card bails on `if _dragging_card`). See #7.
	if not (_dragging_card and _drag_panel):
		return
	if event is InputEventMouseMotion:
		_drag_panel.global_position = _drag_card_pos(event.global_position)
		_update_drag_target_highlight(event.global_position)
		if _drag_hint:
			_drag_hint.global_position = event.global_position + Vector2(20, 16)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_complete_drag(event.global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if combat_engine == null or combat_engine.phase != CombatEngine.Phase.PLAYER_TURN:
		return

	# Keyboard: Space/Enter to end turn
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			_on_end_turn_pressed()
			get_viewport().set_input_as_handled()
			return
		# Number keys 1-9 to select cards
		var key_num := -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			key_num = event.keycode - KEY_1
		if key_num >= 0 and key_num < combat_engine.piles.hand.size():
			var card = combat_engine.piles.hand[key_num]
			_on_card_input(_make_click_event(), card)
			get_viewport().set_input_as_handled()
			return

	# Right-click to deselect a click-selected card (drag cancel is handled in _input).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_card:
			selected_card = null
			_update_card_highlights()
			get_viewport().set_input_as_handled()
			return


func _make_click_event() -> InputEventMouseButton:
	var ev = InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	return ev


# ============================================================
# UI CONSTRUCTION
# ============================================================

func _build_ui() -> void:
	# The desk under everything, and the stage on it.
	var bg = ColorRect.new()
	bg.color = StageSkin.c("desk")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_stage = CombatStage.new()
	add_child(_stage)

	# Vignette
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.3;
	float vig = smoothstep(0.35, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vig * 0.6);
}
"""
	mat.shader = shader
	vignette.material = mat
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.visible = not StageSkin.is_page()
	add_child(vignette)

	# Damage flash overlay (hidden by default)
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.8, 0.05, 0.05, 0.0)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.z_index = 40

	# Main layout with margins
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	_main_container = margin

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Top bar: pile counts
	vbox.add_child(_build_top_bar())

	# Enemy area. The row sits in a plain Control so that a tall panel (a boss's status rows)
	# can never push the player bar and the hand down: this area takes whatever is left.
	var enemy_area := Control.new()
	enemy_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(enemy_area)

	enemy_container = HBoxContainer.new()
	enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_container.add_theme_constant_override("separation", 40)
	enemy_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_area.add_child(enemy_container)

	# Player info bar
	_player_bar = _build_player_bar()
	vbox.add_child(_player_bar)

	# Hand + End Turn
	vbox.add_child(_build_bottom_area())

	# Combat log: closed until asked for, over the stage so opening it moves nothing.
	log_text = RichTextLabel.new()
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	log_text.scroll_active = true
	log_text.position = LOG_RECT.position
	log_text.size = LOG_RECT.size
	log_text.z_index = 50
	log_text.visible = false
	var log_style = StyleBoxFlat.new()
	log_style.bg_color = Color(0.07, 0.065, 0.06, 0.96)
	log_style.set_corner_radius_all(6)
	log_style.content_margin_left = 12
	log_style.content_margin_right = 12
	log_style.content_margin_top = 8
	log_style.content_margin_bottom = 8
	log_text.add_theme_stylebox_override("normal", log_style)
	add_child(log_text)

	_passion_gauge = PassionGauge.new()
	add_child(_passion_gauge)

	# Add damage flash on top of everything
	add_child(_damage_flash)


func _build_top_bar() -> HBoxContainer:
	var bar = HBoxContainer.new()

	# Map peek — glance at your route / what's ahead without leaving combat. Sits at
	# the far left (map-in-the-corner), set apart from the pile counts on the right.
	var map_btn = _make_pile_button(StageSkin.c("pile_map"))
	map_btn.text = "Map ▸"
	map_btn.tooltip_text = "Peek the map: your route so far and what lies ahead"
	map_btn.pressed.connect(_on_view_map)
	bar.add_child(map_btn)

	var map_spacer = Control.new()
	map_spacer.custom_minimum_size.x = 34
	bar.add_child(map_spacer)

	draw_label = _make_pile_button(StageSkin.c("pile_draw"))
	draw_label.pressed.connect(_on_pile_clicked.bind("draw"))
	bar.add_child(draw_label)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# The pack sits between the piles. The engine does not exist yet at build time; _start_combat
	# hands it over, and until then every item reads as waiting.
	consumable_bar = ConsumableBar.new()
	consumable_bar.setup(ConsumableBar.Mode.COMBAT)
	consumable_bar.item_used.connect(_on_consumable_used)
	consumable_bar.modulate = StageSkin.c("pack_tint")
	bar.add_child(consumable_bar)

	var pack_spacer = Control.new()
	pack_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(pack_spacer)

	exhaust_label = _make_pile_button(StageSkin.c("pile_exhaust"))
	exhaust_label.pressed.connect(_on_pile_clicked.bind("exhaust"))
	bar.add_child(exhaust_label)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size.x = 30
	bar.add_child(spacer2)

	discard_label = _make_pile_button(StageSkin.c("pile_discard"))
	discard_label.pressed.connect(_on_pile_clicked.bind("discard"))
	bar.add_child(discard_label)

	var spacer3 = Control.new()
	spacer3.custom_minimum_size.x = 30
	bar.add_child(spacer3)

	var log_btn = _make_pile_button(StageSkin.c("pile_exhaust"))
	log_btn.text = "Log"
	log_btn.tooltip_text = "What has happened this fight"
	log_btn.pressed.connect(func(): log_text.visible = not log_text.visible)
	bar.add_child(log_btn)

	return bar


func _make_pile_button(color: Color) -> Button:
	var btn = Button.new()
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_hover_color", color.lightened(0.3))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn


func _build_player_bar() -> PanelContainer:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.098, 0.09, 0.95)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 40)
	panel.add_child(bar)

	# Character POWERS slot — anchored at the left (character) end, ahead of the
	# resource stats, and visually distinct (gold) from the status chips. Persistent
	# powers read as "who I am this fight." Hidden until a POWER is active. The two chip
	# sides share the spare width equally, so the stats hold the bar's centre and a chip
	# landing never moves them.
	var powers_side := _make_chip_side(BoxContainer.ALIGNMENT_END)
	bar.add_child(powers_side)

	player_powers_prefix = _make_stat_label(Color(0.9, 0.78, 0.4))
	player_powers_prefix.text = "Powers:"
	player_powers_prefix.visible = false
	powers_side.add_child(player_powers_prefix)

	player_powers_chips = HFlowContainer.new()
	player_powers_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_powers_chips.add_theme_constant_override("h_separation", CHIP_SEP)
	player_powers_chips.add_theme_constant_override("v_separation", 4)
	powers_side.add_child(player_powers_chips)

	hp_label = _make_stat_label(Color(0.9, 0.3, 0.3))
	bar.add_child(hp_label)

	block_label = _make_stat_label(Color(0.3, 0.6, 0.9))
	bar.add_child(block_label)

	energy_label = _make_stat_label(Color(0.9, 0.9, 0.3))
	bar.add_child(energy_label)

	passion_label = _make_stat_label(Color(0.9, 0.5, 0.2))
	passion_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	passion_label.mouse_entered.connect(_show_passion_infographic)
	passion_label.mouse_exited.connect(_hide_passion_infographic)
	passion_label.gui_input.connect(_on_passion_label_input)
	bar.add_child(passion_label)

	# Status effects live on this readout as individual, hover-describable chips.
	# A small "Effects:" caption names the area (both hidden when nothing's active).
	var status_side := _make_chip_side(BoxContainer.ALIGNMENT_BEGIN)
	bar.add_child(status_side)

	player_status_prefix = _make_stat_label(Color(0.7, 0.7, 0.55))
	player_status_prefix.text = "Effects:"
	player_status_prefix.visible = false
	status_side.add_child(player_status_prefix)

	player_status_chips = HFlowContainer.new()
	player_status_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_status_chips.add_theme_constant_override("h_separation", CHIP_SEP)
	player_status_chips.add_theme_constant_override("v_separation", 4)
	status_side.add_child(player_status_chips)

	return panel


func _make_chip_side(alignment: BoxContainer.AlignmentMode) -> HBoxContainer:
	var side := HBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = alignment
	side.add_theme_constant_override("separation", CHIP_SEP)
	return side


## A flow container inside a box only gets its widest child's width, so chips would stack in a
## column and grow the bar. This gives it room for its chips on one row, up to the cap; past that
## they wrap. Returns how many chips it holds.
func _fit_chip_row(flow: HFlowContainer) -> int:
	var width := 0.0
	var count := 0
	for chip in flow.get_children():
		if chip is Control and not chip.is_queued_for_deletion():
			width += chip.get_combined_minimum_size().x + CHIP_SEP
			count += 1
	flow.custom_minimum_size.x = minf(width, CHIP_ROW_MAX_W)
	return count


## Hovering the Passion readout pops a quick OVERVIEW above the bar: the five tiers
## with thresholds + effects and where you stand. Non-interactive (ignores the
## mouse) so it never eats input; it clears when the pointer leaves the readout.
## Clicking the readout opens the full page (see _on_passion_label_input).
func _show_passion_infographic() -> void:
	if _passion_popup or not RunManager.passion:
		return
	_passion_popup = PassionInfographic.build_overview_panel()
	_passion_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_passion_popup.z_index = 60
	add_child(_passion_popup)
	_position_passion_popup.call_deferred()


## Click the Passion readout → the full zone page (hover a zone to see your matching
## cards as full renders). Dismiss the hover overview first so they don't overlap.
func _on_passion_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and RunManager.passion:
		_hide_passion_infographic()
		PassionInfographic.open_modal(self)


func _position_passion_popup() -> void:
	if not _passion_popup:
		return
	var lbl := passion_label.global_position
	var sz := _passion_popup.size
	var x := lbl.x + passion_label.size.x / 2.0 - sz.x / 2.0
	x = clampf(x, 10.0, 1920.0 - sz.x - 10.0)
	var y := lbl.y - sz.y - 12.0
	_passion_popup.global_position = Vector2(x, maxf(10.0, y))


func _hide_passion_infographic() -> void:
	if _passion_popup:
		_passion_popup.queue_free()
		_passion_popup = null


## Map peek: opens the shared read-only route overlay over combat (reused from
## rest/shop/event). Dismiss the transient passion popup + status pin first so they
## don't linger under it, and raise it above combat's z-indexed FX so it reads clean.
func _on_view_map() -> void:
	if is_instance_valid(_map_overlay):
		return
	_hide_passion_infographic()
	_hide_status_pin()
	_map_overlay = MapPreviewOverlay.open(self)
	_map_overlay.z_index = 100


func _build_bottom_area() -> HBoxContainer:
	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", BOTTOM_ROW_SEP)

	# Matches End Turn plus the separation, so the hand's centre is the screen's centre.
	_hand_spacer = Control.new()
	_hand_spacer.custom_minimum_size.x = END_TURN_W
	_hand_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_hand_spacer)

	hand_container = HBoxContainer.new()
	hand_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_container.add_theme_constant_override("separation", 10)
	hand_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# A fixed height, held on the enemy turn too when the hand is empty, so the player bar and the
	# enemies keep their places from round to round.
	hand_container.custom_minimum_size.y = CardFace.SIZE.y
	bottom.add_child(hand_container)

	end_turn_btn = Button.new()
	end_turn_btn.text = "End Turn"
	end_turn_btn.custom_minimum_size = Vector2(END_TURN_W, 60)
	end_turn_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_turn_btn.add_theme_font_size_override("font_size", 20)
	end_turn_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var et_style = StyleBoxFlat.new()
	et_style.set_corner_radius_all(10)
	et_style.set_border_width_all(2)
	et_style.bg_color = Color(0.24, 0.17, 0.08)
	et_style.border_color = Color(0.8, 0.6, 0.2)
	et_style.content_margin_left = 12
	et_style.content_margin_right = 12
	et_style.content_margin_top = 8
	et_style.content_margin_bottom = 8
	end_turn_btn.add_theme_stylebox_override("normal", et_style)

	var et_hover = et_style.duplicate()
	et_hover.bg_color = Color(0.34, 0.24, 0.08)
	et_hover.border_color = Color(1.0, 0.78, 0.25)
	end_turn_btn.add_theme_stylebox_override("hover", et_hover)

	var et_pressed = et_style.duplicate()
	et_pressed.bg_color = Color(0.16, 0.12, 0.04)
	end_turn_btn.add_theme_stylebox_override("pressed", et_pressed)

	var et_disabled = et_style.duplicate()
	et_disabled.bg_color = Color(0.12, 0.12, 0.12)
	et_disabled.border_color = Color(0.3, 0.3, 0.3)
	end_turn_btn.add_theme_stylebox_override("disabled", et_disabled)
	end_turn_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	end_turn_btn.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	end_turn_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.5))
	end_turn_btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))

	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	bottom.add_child(end_turn_btn)

	return bottom


func _make_hp_bar(width: int, height: int) -> Control:
	# Container holds trail bar behind main bar
	var container = Control.new()
	container.custom_minimum_size = Vector2(width, height)
	# Keep the bar a fixed width, centered, so every enemy's HP bar is uniform. A
	# plain Control in a VBox otherwise stretches to the widest sibling, so a long
	# name ("Champion of the Usurper") blew the bar frame out past its 180px fill,
	# leaving a dark gap that misread as ~65% HP.
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var trail = ProgressBar.new()
	trail.custom_minimum_size = Vector2(width, height)
	trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	trail.show_percentage = false
	trail.max_value = 100
	trail.value = 100
	var trail_bg = StyleBoxFlat.new()
	trail_bg.bg_color = StageSkin.c("bar_back")
	trail_bg.set_corner_radius_all(3)
	trail.add_theme_stylebox_override("background", trail_bg)
	var trail_fill = StyleBoxFlat.new()
	trail_fill.bg_color = StageSkin.c("bar_trail")
	trail_fill.set_corner_radius_all(3)
	trail.add_theme_stylebox_override("fill", trail_fill)
	container.add_child(trail)

	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	bg_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = StageSkin.c("bar_high")
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill_style)
	container.add_child(bar)

	_hp_trail_bars[bar] = trail
	return container


func _make_stat_label(color: Color) -> Label:
	var lbl = Label.new()
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _on_pile_clicked(pile_name: String) -> void:
	# Toggle off if already showing
	if pile_popup:
		pile_popup.queue_free()
		pile_popup = null
		return

	var cards: Array = []
	var title: String
	match pile_name:
		"draw":
			cards = combat_engine.piles.draw_pile.duplicate()
			title = "Draw Pile"
		"discard":
			cards = combat_engine.piles.discard_pile.duplicate()
			title = "Discard Pile"
		"exhaust":
			cards = combat_engine.piles.exhaust_pile.duplicate()
			title = "Exhaust Pile"

	_show_pile_popup(title, cards)


func _show_pile_popup(title: String, cards: Array) -> void:
	pile_popup = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.085, 0.078, 0.97)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.46, 0.38)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	pile_popup.add_theme_stylebox_override("panel", style)
	pile_popup.set_anchors_preset(Control.PRESET_CENTER)
	pile_popup.custom_minimum_size = Vector2(500, 300)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	pile_popup.add_child(vbox)

	# Title row
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl = Label.new()
	title_lbl.text = "%s (%d)" % [title, cards.size()]
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(_close_pile_popup)
	header.add_child(close_btn)

	# Card type breakdown
	var pile_type_counts := {CardData.CardType.ATTACK: 0, CardData.CardType.SKILL: 0, CardData.CardType.POWER: 0}
	for card in cards:
		pile_type_counts[card.card_type] = pile_type_counts.get(card.card_type, 0) + 1
	var pile_stats_lbl = Label.new()
	pile_stats_lbl.text = "%d Attack / %d Skill / %d Power" % [
		pile_type_counts[CardData.CardType.ATTACK],
		pile_type_counts[CardData.CardType.SKILL],
		pile_type_counts[CardData.CardType.POWER]]
	pile_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile_stats_lbl.add_theme_font_size_override("font_size", 16)
	pile_stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(pile_stats_lbl)

	# Card list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	if cards.size() == 0:
		var empty = Label.new()
		empty.text = "(empty)"
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		list.add_child(empty)
	else:
		var grid = GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for card in cards:
			var cpanel = PanelContainer.new()
			cpanel.custom_minimum_size = Vector2(160, 100)
			var cs = StyleBoxFlat.new()
			cs.set_corner_radius_all(6)
			cs.set_border_width_all(2)
			cs.content_margin_left = 6
			cs.content_margin_right = 6
			cs.content_margin_top = 4
			cs.content_margin_bottom = 4
			match card.card_type:
				CardData.CardType.ATTACK:
					cs.bg_color = Color(0.28, 0.1, 0.08)
					cs.border_color = Color(0.8, 0.2, 0.18)
				CardData.CardType.SKILL:
					cs.bg_color = Color(0.08, 0.12, 0.28)
					cs.border_color = Color(0.2, 0.38, 0.8)
				CardData.CardType.POWER:
					cs.bg_color = Color(0.28, 0.24, 0.08)
					cs.border_color = Color(0.8, 0.65, 0.15)
			# Upgraded card green border tint
			if card.upgraded:
				cs.border_color = cs.border_color.lerp(Color(0.3, 0.9, 0.3), 0.5)
			cpanel.add_theme_stylebox_override("panel", cs)
			var cvb = VBoxContainer.new()
			cvb.add_theme_constant_override("separation", 2)
			cpanel.add_child(cvb)
			var cn = Label.new()
			cn.text = "[%s] %s" % [card.cost_label(), card.card_name]
			cn.add_theme_font_size_override("font_size", 14)
			cn.add_theme_color_override("font_color", cs.border_color.lightened(0.4))
			cvb.add_child(cn)
			var cd = Label.new()
			cd.text = card.get_generated_description()
			cd.add_theme_font_size_override("font_size", 11)
			cd.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
			cd.autowrap_mode = TextServer.AUTOWRAP_WORD
			cvb.add_child(cd)
			grid.add_child(cpanel)

	add_child(pile_popup)


func _close_pile_popup() -> void:
	if pile_popup:
		pile_popup.queue_free()
		pile_popup = null


# ============================================================
# EVENT CONNECTIONS
# ============================================================

func _connect_events() -> void:
	Events.combat_started.connect(_on_combat_started)
	Events.combat_won.connect(_on_combat_won)
	Events.combat_lost.connect(_on_combat_lost)
	Events.card_played.connect(_on_card_played)
	Events.card_exhausted.connect(_on_card_exhausted)
	Events.player_turn_started.connect(_on_player_turn_started)
	Events.enemy_turn_started.connect(_on_enemy_turn_started)
	Events.enemy_action_started.connect(_on_enemy_action_started)
	Events.enemy_stunned.connect(_on_enemy_stunned)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_healed.connect(_on_player_healed)
	Events.enemy_damaged.connect(_on_enemy_damaged)
	Events.enemy_healed.connect(_on_enemy_healed)
	Events.enemy_died.connect(_on_enemy_died)
	Events.enemy_phase_changed.connect(_on_enemy_phase_changed)
	Events.block_gained.connect(_on_block_gained)
	Events.passion_changed.connect(_on_passion_changed)
	Events.status_applied.connect(_on_status_applied)
	Events.status_removed.connect(_on_status_removed)
	Events.combat_note.connect(_on_combat_note)


# ============================================================
# COMBAT SETUP
# ============================================================

func _start_combat() -> void:
	# If no run is active, start a test run (direct scene launch for debugging)
	if not RunManager.run_active:
		var character = _create_test_character()
		RunManager.start_run(character)

	combat_engine = CombatEngine.new()
	combat_engine.name = "CombatEngine"
	add_child(combat_engine)
	consumable_bar.engine = combat_engine

	# Use pending enemies from map, or fall back to test enemies
	var enemy_datas: Array[EnemyData] = []
	if RunManager.pending_enemies.size() > 0:
		enemy_datas = RunManager.pending_enemies.duplicate()
		RunManager.pending_enemies.clear()
	else:
		enemy_datas = [_create_slime(), _create_goblin()]

	combat_engine.start_combat(
		RunManager.current_deck,
		RunManager.current_hp,
		RunManager.max_hp,
		enemy_datas
	)
	_log("[color=gold]Combat begins![/color]")


func _create_test_character() -> CharacterData:
	var c = CharacterData.new()
	c.character_name = "Emo Hybrid Caster"
	c.max_health = 80
	c.passion_volatility = 1.0
	c.passion_thresholds.assign([50, 18, -18, -50])
	c.primary_personality = "Water"
	c.secondary_personality = "Physical"

	var strike = _make_card("Strike", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_make_damage(6)])
	var defend = _make_card("Defend", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, [_make_block(5)])
	var bash = _make_card("Stagger", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_make_damage(8), _make_status(StatusEffects.VULNERABLE, 2)])
	var noxious = _make_card("Noxious Strike", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_make_damage(4), _make_status(StatusEffects.POISON, 3)])
	var flame_strike = _make_card("Outpouring", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_make_damage(9), _make_passion(3)])
	flame_strike.personality = CardData.PersonalityType.PRIMARY
	flame_strike.flavor_text = "He lets it pour out of him. For a moment, the ache goes with it."
	var meditate = _make_card("Meditate", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, [_make_block(4), _make_passion(3)])

	for i in 2:
		c.starting_deck.append(strike)
	for i in 2:
		c.starting_deck.append(defend)
	var cleave = _make_card("Wide Arc", 1, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, [_make_damage(6)])
	c.starting_deck.append(bash)
	c.starting_deck.append(noxious)
	c.starting_deck.append(cleave)
	c.starting_deck.append(flame_strike)
	c.starting_deck.append(meditate)

	# Personality card pools for tier-based rewards
	c.primary_cards = CardPool.build_emo_primary_pool()
	c.secondary_cards = CardPool.build_emo_secondary_pool()

	return c


func _create_slime() -> EnemyData:
	var e = EnemyData.new()
	e.enemy_name = "Slime"
	e.max_health = 42

	var tackle = EnemyMove.new()
	tackle.move_name = "Tackle"
	tackle.intent_type = EnemyMove.IntentType.ATTACK
	tackle.effects.assign([_make_damage(6)])
	tackle.weight = 2.0

	var harden = EnemyMove.new()
	harden.move_name = "Harden"
	harden.intent_type = EnemyMove.IntentType.DEFEND
	harden.effects.assign([_make_block(5)])
	harden.weight = 1.0

	var slam = EnemyMove.new()
	slam.move_name = "Slam"
	slam.intent_type = EnemyMove.IntentType.ATTACK
	slam.effects.assign([_make_damage(12)])
	slam.weight = 0.5

	var spit = EnemyMove.new()
	spit.move_name = "Spit"
	spit.intent_type = EnemyMove.IntentType.DEBUFF
	spit.effects.assign([_make_status(StatusEffects.WEAK, 1)])
	spit.weight = 1.0

	e.moves.assign([tackle, harden, slam, spit])
	return e


func _create_goblin() -> EnemyData:
	var e = EnemyData.new()
	e.enemy_name = "Goblin"
	e.max_health = 26

	var stab = EnemyMove.new()
	stab.move_name = "Stab"
	stab.intent_type = EnemyMove.IntentType.ATTACK
	stab.effects.assign([_make_damage(4)])
	stab.weight = 2.0

	var slash = EnemyMove.new()
	slash.move_name = "Slash"
	slash.intent_type = EnemyMove.IntentType.ATTACK
	slash.effects.assign([_make_damage(8)])
	slash.weight = 1.0

	var poison_dart = EnemyMove.new()
	poison_dart.move_name = "Poison Dart"
	poison_dart.intent_type = EnemyMove.IntentType.ATTACK
	poison_dart.effects.assign([_make_damage(2), _make_status(StatusEffects.POISON, 2)])
	poison_dart.weight = 0.7

	e.moves.assign([stab, slash, poison_dart])
	return e


# -- Factory helpers --

func _make_card(card_name: String, cost: int, type: CardData.CardType,
		target: CardData.TargetType, card_effects: Array) -> CardData:
	var c = CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = type
	c.target_type = target
	for e in card_effects:
		c.effects.append(e)
	return c


func _make_damage(amount: int) -> DamageEffect:
	var e = DamageEffect.new()
	e.value = amount
	return e


func _make_block(amount: int) -> BlockEffect:
	var e = BlockEffect.new()
	e.value = amount
	return e


func _make_status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e = StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e


func _make_passion(amount: int) -> PassionEffect:
	var e = PassionEffect.new()
	e.value = amount
	return e


func _get_personality_label(pers: CardData.PersonalityType) -> String:
	if pers == CardData.PersonalityType.NEGATIVE:
		return "Curse"
	if RunManager.current_character:
		if pers == CardData.PersonalityType.PRIMARY:
			return RunManager.current_character.primary_personality
		if pers == CardData.PersonalityType.SECONDARY:
			return RunManager.current_character.secondary_personality
	var names = {
		CardData.PersonalityType.PRIMARY: "Primary",
		CardData.PersonalityType.SECONDARY: "Secondary",
	}
	return names.get(pers, "")


func _get_personality_color(pers: CardData.PersonalityType) -> Color:
	if pers == CardData.PersonalityType.PRIMARY:
		return Color(0.9, 0.5, 0.2) # Warm orange for magic
	if pers == CardData.PersonalityType.SECONDARY:
		return Color(0.4, 0.6, 0.9) # Cool blue for physical
	if pers == CardData.PersonalityType.NEGATIVE:
		return Color(0.55, 0.5, 0.42) # Dead ash for curses
	return Color(0.6, 0.6, 0.6)


func _personality_sigil(pers: CardData.PersonalityType) -> String:
	# A persistent identity glyph: rippling water for the Water pole, crossed blades
	# for Physical. The water glyph also distinguishes the pole from the ✦ used by
	# the Sword-in-the-Stone map node.
	if pers == CardData.PersonalityType.PRIMARY:
		return "≈"  # water ripples
	if pers == CardData.PersonalityType.SECONDARY:
		return "⚔"  # ⚔
	return ""


## The corner badge: the pool SIGIL (≈ Water / ⚔ Physical) the card wears via its SCHOOL. For a
## true pole card it reflects the live zone: FAVORED = an empowered glyph (brighter + a breathing
## pulse), and at the DEEP end (+25% extreme) the glyph sits on a glowing HALO coin — the coin is
## the at-a-glance tell that separates a fresh +12% lean from a deep +25% extreme, and it FADES in/
## out when you cross the extreme threshold (see _relight_coins). DISFAVORED = greyed +
## faded (uniform across −12% / −25%). A NEUTRAL-personality card that merely wears a school symbol
## never rides the zone, so it stays flat + muted (no coin). Returns null for a school-less card.
func _make_resonance_sigil(card: CardData) -> Control:
	var pole := card.symbol_pole()
	var glyph := _personality_sigil(pole)
	if glyph == "":
		return null
	var col := _get_personality_color(pole)
	var pole_name := _get_personality_label(pole)
	# Only a true pole card rides the zone; a neutral-schooled card just wears a flat symbol.
	var rides_zone := card.personality == CardData.PersonalityType.PRIMARY \
		or card.personality == CardData.PersonalityType.SECONDARY
	var zm := CombatEngine.zone_multiplier(card.personality) if rides_zone else 1.0

	var lbl := Label.new()
	lbl.text = glyph
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.material = StageSkin.no_purple()

	if zm > 1.0:
		# FAVORED — an empowered glyph, styled the SAME at the lean and extreme tiers: the halo
		# COIN (below, pole cards only) is what marks the deep +25%, so the glyph itself doesn't
		# have to carry the lean/extreme distinction.
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", col.lightened(0.34))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_outline_color", Color(col.r, col.g, col.b, 0.85))
		lbl.tooltip_text = "%s. Resonant: +%d%% damage at your current Passion." \
			% [pole_name, roundi((zm - 1.0) * 100.0)]
		var pulse := lbl.create_tween().set_loops()
		pulse.tween_property(lbl, "modulate", Color(1.18, 1.18, 1.18, 1.0), 0.65) \
			.set_trans(Tween.TRANS_SINE)
		pulse.tween_property(lbl, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.65) \
			.set_trans(Tween.TRANS_SINE)
	elif zm < 1.0:
		# Disfavored: greyed + faded, uniform across the −12% / −25% tiers.
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", col.lerp(Color(0.45, 0.45, 0.45), 0.6))
		lbl.modulate.a = 0.55
		lbl.tooltip_text = "%s. Dissonant: -%d%% damage at your current Passion." \
			% [pole_name, roundi((1.0 - zm) * 100.0)]
	else:
		# Flat: the identity colour, muted. A NEUTRAL card wearing a school symbol (never rides
		# the zone) OR an uncommitted pole card at Steady. Tooltip tells them apart.
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", col)
		lbl.modulate.a = 0.8
		if card.personality == CardData.PersonalityType.NEUTRAL:
			lbl.tooltip_text = "%s-aligned: a neutral card, so no zone bonus or penalty." % pole_name
		else:
			lbl.tooltip_text = "%s card. Commit to its Passion pole for +25%% damage." % pole_name

	# A neutral-schooled card never rides the zone → no coin; a bare glyph is enough.
	if not rides_zone:
		return lbl

	# A pole card sits in a fixed 42×42 holder (so the glyph never shifts across tiers) over a halo
	# COIN that is only opaque at the extreme (+25%). The coin is kept present-but-transparent at
	# every tier so it can FADE in/out on a threshold crossing. Disc + glyph are click-through so
	# the card panel keeps its hover; the holder carries the tooltip.
	var extreme := zm >= (CombatEngine.ZONE_LEAN_BONUS + CombatEngine.ZONE_EXTREME_BONUS) * 0.5
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(42, 42)
	holder.tooltip_text = lbl.tooltip_text
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(col.r, col.g, col.b, 0.30)
	ds.set_corner_radius_all(21)
	ds.shadow_color = Color(col.r, col.g, col.b, 0.5)
	ds.shadow_size = 8
	disc.add_theme_stylebox_override("panel", ds)
	disc.modulate.a = 1.0 if extreme else 0.0
	holder.add_child(disc)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The ⚔ glyph's ink sits high in its font box; nudge it down so it centres inside the coin.
	var nudge := _sigil_v_nudge(pole)
	lbl.offset_top = nudge
	lbl.offset_bottom = nudge
	holder.add_child(lbl)
	holder.set_meta("halo_disc", disc)
	return holder


## The ⚔ (Physical) glyph's ink sits high in its font box, so plain vertical-centring leaves it
## near the top of the halo coin; nudge it down. ≈ (Water) is already close to centred.
func _sigil_v_nudge(pole: CardData.PersonalityType) -> int:
	if pole == CardData.PersonalityType.SECONDARY:
		return 4
	return 1


# ============================================================
# CARD UI
# ============================================================

func _create_card_panel(card: CardData) -> PanelContainer:
	var sigil = _make_resonance_sigil(card)
	if sigil and sigil.has_meta("halo_disc"):
		_hand_coins[card] = sigil.get_meta("halo_disc")
	var source: CombatantStats = combat_engine.player_stats if combat_engine else null
	var panel := CardFace.build(card, source, sigil)
	panel.size_flags_vertical = Control.SIZE_SHRINK_END

	# Make all children pass clicks through to the panel
	_ignore_mouse_recursive(panel.get_child(0))

	# Click handler
	panel.gui_input.connect(_on_card_input.bind(card))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Hover animation only. The old detail popup was removed: the hand card is already
	# fully legible, and the popup floated up over the enemies' intents. A card at rest
	# still shows everything; the enlarge-on-hover is enough of an affordance.
	panel.mouse_entered.connect(func():
		# Comes forward, since the hand overlaps once it is too wide for the row.
		panel.z_index = 5
		if panel.modulate != Color(0.5, 0.5, 0.5):
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(panel, "scale", Vector2(1.08, 1.08), 0.12)
		_light_card_targets(card)
	)
	panel.mouse_exited.connect(func():
		# A card in flight or being dragged owns its own scale and z.
		if panel.mouse_filter != Control.MOUSE_FILTER_IGNORE and panel != _drag_panel:
			panel.z_index = 0
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(panel, "scale", Vector2.ONE, 0.12)
		if not _dragging_card:
			_set_lit_enemies([])
	)

	return panel


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)


## Appends an italicized flavor line beneath the description, if the card has one.
## Used by both the in-hand card render and the larger hover popup so flavor
## styling stays consistent. Skipped when the card has no flavor text set.
func _add_flavor_label(parent: Control, card: CardData) -> void:
	if card.flavor_text == "":
		return
	var flavor_lbl = Label.new()
	flavor_lbl.text = card.flavor_text
	flavor_lbl.add_theme_font_size_override("font_size", 11)
	flavor_lbl.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	flavor_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flavor_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Subtle italic via font (no proper italic font in the project — letterspacing
	# substitutes as a soft visual cue without requiring a new font asset).
	flavor_lbl.add_theme_constant_override("outline_size", 0)
	parent.add_child(flavor_lbl)


func _on_card_input(event: InputEvent, card: CardData) -> void:
	# No engine (e.g. the card manifest reuses this render outside combat) → not interactive.
	if combat_engine == null:
		return
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if combat_engine.phase != CombatEngine.Phase.PLAYER_TURN:
		return
	if _dragging_card:
		return
	# The hand closes up the moment a card plays, so the second press of a double-click lands on
	# whatever slid under the cursor. Only that press is dropped: a click that has moved plays at
	# once, however fast it follows.
	if event.double_click and Time.get_ticks_msec() - _last_play_ms < DOUBLE_CLICK_GUARD_MS:
		return

	if not combat_engine.can_play_card(card):
		_log("[color=red]Not enough energy![/color]")
		return

	selected_card = card

	match card.target_type:
		CardData.TargetType.SELF, CardData.TargetType.NONE:
			_play_selected_card(combat_engine.player_stats)
		CardData.TargetType.ALL_ENEMIES:
			_play_selected_card(null)
		CardData.TargetType.SINGLE_ENEMY:
			var living := _living_enemies()
			if living.size() == 1:
				# Only one possible target — no need to aim. Play it straight away.
				_play_selected_card(living[0].stats)
			else:
				# Multiple targets: drag onto one; right-click cancels.
				_start_drag(card, event)
				_update_card_highlights()
				_log("Drag onto an enemy, or right-click to cancel...")


## The effect lands on the click and the card's flight is only a flourish behind it, so nothing
## waits on it: no input is held and End Turn cannot strand a card mid-air.
func _play_selected_card(target: CombatantStats) -> void:
	if not selected_card:
		return
	var card = selected_card
	selected_card = null
	_set_lit_enemies([])
	_last_play_ms = Time.get_ticks_msec()
	var panel: PanelContainer = card_nodes.get(card)
	if panel:
		# Find target position
		var target_pos := Vector2(960, 300)
		if target:
			for enemy in combat_engine.enemies:
				if enemy.stats == target:
					var epanel = enemy_nodes.get(enemy)
					if epanel:
						target_pos = _body_rect(epanel).get_center()
					break
		else:
			# AoE — fly to center of enemy area
			target_pos = enemy_container.global_position + enemy_container.size / 2.0

		# Reparent card for animation
		var start_pos = panel.global_position
		panel.get_parent().remove_child(panel)
		add_child(panel)
		panel.global_position = start_pos
		panel.z_index = 30
		# Still a card under the cursor as far as clicks go, and this one has been played.
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_nodes.erase(card)

		var t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.set_parallel(true)
		t.tween_property(panel, "global_position", target_pos - panel.size / 2.0, CARD_FLIGHT)
		t.tween_property(panel, "scale", Vector2(0.5, 0.5), CARD_FLIGHT)
		t.tween_property(panel, "modulate:a", 0.0, CARD_FLIGHT * 0.6).set_delay(CARD_FLIGHT * 0.4)
		t.chain().tween_callback(panel.queue_free)

	combat_engine.play_card(card, target)
	_refresh_ui()


func _update_card_highlights() -> void:
	for card in card_nodes:
		var panel: PanelContainer = card_nodes[card]
		if card == selected_card:
			panel.modulate = Color(1.4, 1.4, 1.1)
		elif not combat_engine.can_play_card(card):
			panel.modulate = Color(0.5, 0.5, 0.5)
		else:
			panel.modulate = Color.WHITE


# ============================================================
# DRAG AND DROP
# ============================================================

func _start_drag(card: CardData, event: InputEvent) -> void:
	var panel: PanelContainer = card_nodes.get(card)
	if not panel:
		return
	_dragging_card = card
	_hide_card_hover()
	var start_pos = panel.global_position
	_drag_offset = event.global_position - start_pos if event is InputEventMouseButton else panel.size / 2.0
	panel.get_parent().remove_child(panel)
	add_child(panel)
	panel.global_position = start_pos
	panel.z_index = 35
	panel.rotation_degrees = 0
	panel.modulate = Color(1.3, 1.3, 1.0, 0.9)
	_drag_panel = panel

	# Right-click cancel affordance, following the cursor.
	_drag_hint = Label.new()
	_drag_hint.text = "⊘ right-click to cancel"
	_drag_hint.add_theme_font_size_override("font_size", 14)
	_drag_hint.add_theme_color_override("font_color", Color(0.95, 0.72, 0.72))
	_drag_hint.add_theme_constant_override("outline_size", 4)
	_drag_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_drag_hint.z_index = 41
	_drag_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_hint)


func _complete_drag(drop_pos: Vector2) -> void:
	if not _dragging_card or not _drag_panel:
		return
	_clear_drag_visuals()
	var card = _dragging_card
	var target_enemy := _drag_target_at(drop_pos)
	if target_enemy:
		_drag_panel.queue_free()
		card_nodes.erase(card)
		_dragging_card = null
		_drag_panel = null
		selected_card = card
		_play_selected_card(target_enemy.stats)
	else:
		_cancel_drag()


func _cancel_drag() -> void:
	_clear_drag_visuals()
	if _drag_panel:
		_drag_panel.queue_free()
	_dragging_card = null
	_drag_panel = null
	_refresh_ui()


func _clear_drag_visuals() -> void:
	_set_lit_enemies([])
	if _drag_hint:
		_drag_hint.queue_free()
		_drag_hint = null


## The dragged card follows the cursor but stops short of the enemies, so it never covers the
## one it is about to hit: with no aim line, the light on the enemy is the whole read.
func _drag_card_pos(cursor: Vector2) -> Vector2:
	var pos := cursor - _drag_offset
	pos.y = maxf(pos.y, _enemies_bottom() + DRAG_CARD_CLEARANCE)
	return pos


## The enemy a drop at this position hits: the one under it, otherwise the closest living one
## anywhere above the player bar. On or below the bar there is no target, and the drop cancels.
## The highlight and the drop both read this, so what is lit is what gets hit.
func _drag_target_at(pos: Vector2) -> EnemyCombatState:
	var closest: EnemyCombatState = null
	var closest_dist := INF
	for enemy in _living_enemies():
		var epanel: PanelContainer = enemy_nodes.get(enemy)
		if not epanel:
			continue
		var rect := epanel.get_global_rect()
		if rect.has_point(pos):
			return enemy
		var dist := rect.get_center().distance_to(pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	return closest if pos.y < _player_bar.global_position.y else null


func _living_enemies() -> Array:
	var out := []
	for enemy in combat_engine.enemies:
		if not enemy.stats.is_dead():
			out.append(enemy)
	return out


## During a drag, light the enemy this drop would hit so the player can see exactly
## who they are about to hit. Also live-updates the dragged card's damage bracket against
## that enemy, so target-side modifiers (Vulnerable ×1.5, composing with Weak) show the
## real number the moment the card would land on them, and revert when it's pulled away.
func _update_drag_target_highlight(pos: Vector2) -> void:
	var target := _drag_target_at(pos)
	_set_lit_enemies([target] if target else [])

	if _drag_panel and _dragging_card and combat_engine.player_stats:
		CardFace.show_target(_drag_panel, _dragging_card, combat_engine.player_stats, target.stats if target else null)


## A card that needs no aiming already knows what it will hit, so hovering it says so: an
## all-enemy card lights them all, and a single-target card with one enemy left lights that one.
func _light_card_targets(card: CardData) -> void:
	if combat_engine == null or _dragging_card \
			or combat_engine.phase != CombatEngine.Phase.PLAYER_TURN \
			or not combat_engine.can_play_card(card):
		return
	var living := _living_enemies()
	if card.target_type == CardData.TargetType.ALL_ENEMIES \
			or (card.target_type == CardData.TargetType.SINGLE_ENEMY and living.size() == 1):
		_set_lit_enemies(living)


## The targeting light: the sprite brightens a little and a soft warm glow comes up on the
## ground under it. Nothing touches the panel, and neither piece takes part in layout.
func _set_lit_enemies(targets: Array) -> void:
	for enemy in _enemy_lights:
		var light: Dictionary = _enemy_lights[enemy]
		var lit: bool = enemy in targets
		if lit == light["lit"] or not is_instance_valid(light["glow"]):
			continue
		light["lit"] = lit
		if light["tween"]:
			light["tween"].kill()
		var t := create_tween().set_parallel(true)
		t.tween_property(light["glow"], "modulate:a", 1.0 if lit else 0.0, TARGET_LIGHT_FADE)
		if is_instance_valid(light["body"]):
			t.tween_property(light["body"], "modulate", TARGET_LIT_BODY if lit else Color.WHITE, TARGET_LIGHT_FADE)
		light["tween"] = t


## Registers the targeting light for an enemy and returns its glow, ready to go behind the body.
## The glow is anchored to whatever holds it, so it scales with the sprite box.
func _make_target_light(enemy: EnemyCombatState, body: CanvasItem) -> TextureRect:
	if _target_glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		var mid := StageSkin.c("glow_mid")
		grad.colors = PackedColorArray([StageSkin.c("glow_core"), mid, Color(mid.r, mid.g, mid.b, 0.0)])
		_target_glow_tex = GradientTexture2D.new()
		_target_glow_tex.gradient = grad
		_target_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_target_glow_tex.fill_from = Vector2(0.5, 0.5)
		_target_glow_tex.fill_to = Vector2(1.0, 0.5)
		_target_glow_mat = CanvasItemMaterial.new()
		_target_glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX if StageSkin.is_page() else CanvasItemMaterial.BLEND_MODE_ADD
	var glow := TextureRect.new()
	glow.texture = _target_glow_tex
	glow.material = _target_glow_mat
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = -0.15
	glow.anchor_right = 1.15
	glow.anchor_top = 0.68
	glow.anchor_bottom = 1.12
	glow.modulate.a = 0.0
	_enemy_lights[enemy] = {"glow": glow, "body": body, "lit": false, "tween": null}
	return glow


# ============================================================
# ENEMY UI
# ============================================================

func _create_enemy_panel(enemy: EnemyCombatState) -> PanelContainer:
	var panel = PanelContainer.new()
	# No chrome: the body stands on the ground, and its name, bar and intent sit on the ground under
	# it. Hung from the top with a fixed body height, so feet line up across a fight and nothing that
	# changes below them can move a body. The gap left under the panel is where the turn banner sits
	# (see _show_turn_banner).
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# The body's place: a column that stands the body on the ground, with the statuses beside its feet.
	var place := Control.new()
	place.name = "Place"
	place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(place)

	# Animated spritesheet (idle loops; attack/hit/death play on combat events, then fall back to
	# idle). See SPRITE_SETS / _build_enemy_body.
	var set_key: String = enemy.enemy_data.sprite_set
	if set_key == "":
		set_key = ENEMY_SPRITE_SET.get(enemy.enemy_data.enemy_name, "")
	var stand: Control
	if set_key != "" and SPRITE_SETS.has(set_key):
		stand = _build_enemy_body(set_key, enemy)
	else:
		# Fallback for unknown enemies
		stand = _make_stand(Vector2(130, 130))
		var port_icon = Label.new()
		port_icon.text = "?"
		port_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		port_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		port_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		port_icon.add_theme_font_size_override("font_size", 72)
		stand.add_child(_make_body_shadow())
		stand.add_child(_make_target_light(enemy, port_icon))
		stand.add_child(port_icon)
	place.add_child(stand)
	panel.set_meta("stand", stand)
	var body_w: float = stand.offset_right - stand.offset_left
	place.custom_minimum_size = Vector2(maxf(ENEMY_MIN_W, body_w + 2.0 * STATUS_COLUMN_W), BODY_MAX_H)

	# Statuses as the same hover-describable chips as the player's, stacked up from the feet.
	var status_chips = VBoxContainer.new()
	status_chips.name = "Statuses"
	status_chips.alignment = BoxContainer.ALIGNMENT_END
	status_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_chips.add_theme_constant_override("separation", 4)
	status_chips.anchor_left = 0.5
	status_chips.anchor_right = 0.5
	status_chips.anchor_top = 1.0
	status_chips.anchor_bottom = 1.0
	status_chips.offset_left = body_w / 2.0 + 10.0
	status_chips.offset_right = status_chips.offset_left + STATUS_COLUMN_W
	status_chips.offset_top = -BODY_MAX_H
	place.add_child(status_chips)

	var name_lbl = Label.new()
	name_lbl.name = "EnemyName"
	name_lbl.text = enemy.enemy_data.enemy_name
	name_lbl.add_theme_font_override("font", load(StageSkin.NAME_FONT_PATH))
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", StageSkin.c("ink"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var hp_bar_container = _make_hp_bar(240, 22)
	hp_bar_container.name = "HPBarContainer"
	var enemy_hp_bar: ProgressBar = hp_bar_container.get_child(1)
	enemy_hp_bar.name = "HPBar"
	enemy_hp_bar.max_value = enemy.enemy_data.max_health
	enemy_hp_bar.value = enemy.stats.current_hp
	var enemy_trail: ProgressBar = hp_bar_container.get_child(0)
	enemy_trail.max_value = enemy.enemy_data.max_health
	enemy_trail.value = enemy.stats.current_hp
	# HP text overlaid inside the bar
	var hp_lbl = Label.new()
	hp_lbl.name = "HP"
	hp_lbl.add_theme_font_size_override("font_size", 15)
	hp_lbl.add_theme_color_override("font_color", StageSkin.c("bar_text"))
	hp_lbl.add_theme_color_override("font_shadow_color", StageSkin.c("bar_text_shadow"))
	hp_lbl.add_theme_constant_override("shadow_offset_x", 1)
	hp_lbl.add_theme_constant_override("shadow_offset_y", 1)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar_container.add_child(hp_lbl)
	# Block sits off the bar's left end, outside its width, so the bar holds the column's centre.
	var block_lbl = Label.new()
	block_lbl.name = "Block"
	block_lbl.add_theme_font_size_override("font_size", 18)
	block_lbl.add_theme_color_override("font_color", StageSkin.c("block"))
	block_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	block_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block_lbl.anchor_top = 0.0
	block_lbl.anchor_bottom = 1.0
	block_lbl.offset_left = -112.0
	block_lbl.offset_right = -8.0
	hp_bar_container.add_child(block_lbl)
	vbox.add_child(hp_bar_container)

	# The intent, one line: the move's name in ink, then the threat in its category's colour, so the
	# number never reads as part of the name.
	var intent_row = HBoxContainer.new()
	intent_row.name = "IntentRow"
	intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
	intent_row.add_theme_constant_override("separation", 10)
	vbox.add_child(intent_row)

	var intent_name_lbl = Label.new()
	intent_name_lbl.name = "IntentName"
	intent_name_lbl.add_theme_font_size_override("font_size", 20)
	intent_name_lbl.add_theme_color_override("font_color", StageSkin.c("ink_soft"))
	intent_row.add_child(intent_name_lbl)

	var intent_lbl = Label.new()
	intent_lbl.name = "Intent"
	intent_lbl.add_theme_font_size_override("font_size", 20)
	intent_lbl.add_theme_color_override("font_color", StageSkin.c("intent_attack"))
	intent_lbl.material = StageSkin.no_purple()
	intent_row.add_child(intent_lbl)

	# Sight mode peek — only rendered when player has Excalibur in Sight mode.
	# Sits below the current intent in a dimmer color: "Then: <move>".
	var next_intent_lbl = Label.new()
	next_intent_lbl.name = "NextIntent"
	next_intent_lbl.add_theme_font_size_override("font_size", 14)
	next_intent_lbl.add_theme_color_override("font_color", StageSkin.c("ink_soft"))
	next_intent_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_intent_lbl.visible = false
	vbox.add_child(next_intent_lbl)

	# Click to target
	panel.gui_input.connect(_on_enemy_input.bind(enemy))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	return panel


func _on_enemy_input(event: InputEvent, enemy: EnemyCombatState) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if enemy.stats.is_dead():
		return
	# Complete drag onto enemy
	if _dragging_card and _drag_panel:
		var card = _dragging_card
		_drag_panel.queue_free()
		card_nodes.erase(card)
		_dragging_card = null
		_drag_panel = null
		selected_card = card
		_play_selected_card(enemy.stats)
		return
	if selected_card:
		_play_selected_card(enemy.stats)


## True if an enemy move pushes the player's Passion — a flat PassionEffect (Whisper,
## Hollowing Gaze) or the Prophet's multiplicative PassionCenterEffect. Drives the
## dedicated passion intent glyph so identity attacks read differently from HP/stat ones.
func _intent_affects_passion(move: EnemyMove) -> bool:
	for e in move.effects:
		if e is PassionEffect or e is PassionCenterEffect:
			return true
	return false


## Short readout for a passion intent: the signed shift for a flat drain, or a
## "toward center" note for the Prophet's multiplicative pull.
func _passion_intent_readout(move: EnemyMove) -> String:
	for e in move.effects:
		if e is PassionEffect:
			return " Passion %d" % e.value
		if e is PassionCenterEffect:
			return " Passion → center"
	return " Passion"


## The recoil glyph: a move that costs its own user (the Beast at the Stone's Breaking Blow)
## wears it beside the sword, and the cost beside the damage, so the body breaking is read
## before it happens. The tooltip on the intent spells it out.
const SELF_COST_GLYPH := "↯"


## The flat HP a move costs its own user (a DamageEffect with apply_to_source), or 0.
func _self_cost_of(move: EnemyMove) -> int:
	for e in move.effects:
		if e is DamageEffect and e.apply_to_source:
			return e.value
	return 0


## The intent tooltip for a move that costs its user: what it does to you, then what it does
## to him, with the recoil glyph as the thing to notice.
func _self_cost_tooltip(move: EnemyMove, cost: int) -> String:
	var to_you := ""
	for e in move.effects:
		if e is DamageEffect and not e.apply_to_source:
			if e.hits > 1:
				to_you = "Deals %d damage %d times to you. " % [e.value, e.hits]
			else:
				to_you = "Deals %d damage to you. " % e.value
			break
	return "%s\n%s%s Costs him %d HP, flat. The blow breaks the body that throws it." % [
		move.move_name, to_you, SELF_COST_GLYPH, cost]


## Short single-line summary of an EnemyMove for the Sight-mode "Then:" preview.
## Strips the modifier-aware bracket form used in current-intent rendering —
## the next move hasn't resolved yet, so showing modified values is misleading.
func _format_intent_preview(move: EnemyMove, _enemy: EnemyCombatState) -> String:
	var icon := "•"
	var value_str := ""
	match move.intent_type:
		EnemyMove.IntentType.ATTACK:
			icon = "⚔"
			for effect in move.effects:
				if effect is DamageEffect and not effect.apply_to_source:
					value_str = " %d" % effect.value
					break
		EnemyMove.IntentType.DEFEND:
			icon = "◆"
		EnemyMove.IntentType.ATTACK_DEBUFF:
			icon = "⚔☠"
			for effect in move.effects:
				if effect is DamageEffect and not effect.apply_to_source:
					value_str = " %d" % effect.value
					break
		EnemyMove.IntentType.DEBUFF:
			icon = "☠"
			for effect in move.effects:
				if effect is StatusApplyEffect:
					value_str = " %s" % effect.status_effect.effect_name
					break
		EnemyMove.IntentType.BUFF:
			icon = "★"
			for effect in move.effects:
				if effect is StatusApplyEffect:
					value_str = " %s" % effect.status_effect.effect_name
					break
		EnemyMove.IntentType.UNKNOWN:
			icon = "?"
	var self_cost := _self_cost_of(move)
	if self_cost > 0:
		icon += SELF_COST_GLYPH
		value_str += " (%s%d)" % [SELF_COST_GLYPH, self_cost]
	# Name first, then the icon+value readout (kept inline for the compact "Then:" peek).
	return "%s %s%s" % [move.move_name, icon, value_str]


func _update_enemy_panel(enemy: EnemyCombatState) -> void:
	var panel: PanelContainer = enemy_nodes.get(enemy)
	if not panel:
		return
	# A dead enemy's panel belongs to _animate_enemy_death (fade + shrink + remove).
	# Never touch it here — otherwise each refresh resets its modulate/HP bar and the
	# corpse flickers back to life or churns size as more cards are played.
	if enemy.stats.is_dead():
		return

	var vbox = panel.get_child(0)
	var hp_container = vbox.get_node("HPBarContainer")
	var block_lbl: Label = hp_container.get_node("Block")
	var status_chips: VBoxContainer = vbox.get_node("Place/Statuses")
	var intent_name_lbl: Label = vbox.get_node("IntentRow/IntentName")
	var intent_lbl: Label = vbox.get_node("IntentRow/Intent")
	var next_intent_lbl: Label = vbox.get_node("NextIntent")

	if hp_container:
		var hp_lbl: Label = hp_container.get_node("HP")
		hp_lbl.text = "%d / %d" % [enemy.stats.current_hp, enemy.stats.max_hp]
		var hp_bar: ProgressBar = hp_container.get_child(1)
		hp_bar.max_value = enemy.stats.max_hp
		_animate_hp_bar(hp_bar, enemy.stats.current_hp)
		var ep = float(enemy.stats.current_hp) / enemy.stats.max_hp
		var ef: StyleBoxFlat = hp_bar.get_theme_stylebox("fill")
		if ep > 0.5:
			ef.bg_color = StageSkin.c("bar_high")
		elif ep > 0.25:
			ef.bg_color = StageSkin.c("bar_mid")
		else:
			ef.bg_color = StageSkin.c("bar_low")

	if enemy.stats.block > 0:
		block_lbl.text = "Block: %d" % enemy.stats.block
		block_lbl.visible = true
	else:
		block_lbl.text = ""
		block_lbl.visible = false

	_populate_status_chips(status_chips, enemy.stats)

	if enemy.current_intent:
		var icon := ""
		var intent_color := StageSkin.c("ink")
		var value_str := ""
		match enemy.current_intent.intent_type:
			EnemyMove.IntentType.ATTACK, EnemyMove.IntentType.ATTACK_DEBUFF:
				icon = "⚔"
				intent_color = StageSkin.c("intent_attack")
				for effect in enemy.current_intent.effects:
					if effect is DamageEffect and not effect.apply_to_source:
						var modified = effect.value
						modified += enemy.stats.get_status_stacks(StatusEffects.STRENGTH)
						if enemy.stats.has_status(StatusEffects.WEAK):
							modified = int(modified * 0.75)
						modified = maxi(0, modified)
						var hits: int = effect.hits
						if hits > 1:
							# Multi-hit: show per-hit (base [modified]) plus the real total, so
							# "⚔ 6×3 (18)" never reads as a single 6-damage poke.
							if modified != effect.value:
								value_str = " %d [%d]×%d (%d)" % [effect.value, modified, hits, modified * hits]
							else:
								value_str = " %d×%d (%d)" % [effect.value, hits, effect.value * hits]
						elif modified != effect.value:
							value_str = " %d [%d]" % [effect.value, modified]
						else:
							value_str = " %d" % effect.value
						break
			EnemyMove.IntentType.DEFEND:
				icon = "◆"
				intent_color = StageSkin.c("intent_defend")
				for effect in enemy.current_intent.effects:
					if effect is BlockEffect:
						var modified = effect.value + enemy.stats.get_status_stacks(StatusEffects.DEXTERITY)
						if modified != effect.value:
							value_str = " %d [%d]" % [effect.value, modified]
						else:
							value_str = " %d" % effect.value
						break
			EnemyMove.IntentType.DEBUFF:
				icon = "☠"
				intent_color = StageSkin.c("intent_debuff")
				for effect in enemy.current_intent.effects:
					if effect is StatusApplyEffect:
						value_str = " %s" % effect.status_effect.effect_name
						break
			EnemyMove.IntentType.BUFF:
				icon = "★"
				intent_color = StageSkin.c("intent_buff")
				for effect in enemy.current_intent.effects:
					if effect is StatusApplyEffect:
						value_str = " %s" % effect.status_effect.effect_name
						break
		# A block-bypassing bolt reads as unfair if it's silent, so the pierce is
		# spelled out on the intent beside the damage number.
		for pierce_eff in enemy.current_intent.effects:
			if pierce_eff is DamageEffect and pierce_eff.pierce > 0:
				value_str += " (pierce %d)" % pierce_eff.pierce
				break
		# A blow that costs its own user (the Beast at the Stone's Breaking Blow) takes the recoil
		# glyph beside the sword, the cost beside the damage, and a tooltip that spells it out.
		# Labels ignore the mouse by default, so the tooltip needs them to pass it; the tooltip
		# is cleared again on any move without a cost.
		var self_cost := _self_cost_of(enemy.current_intent)
		if self_cost > 0:
			icon += SELF_COST_GLYPH
			value_str += " (%s%d)" % [SELF_COST_GLYPH, self_cost]
			intent_lbl.tooltip_text = _self_cost_tooltip(enemy.current_intent, self_cost)
			intent_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			intent_name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		else:
			intent_lbl.tooltip_text = ""
		intent_name_lbl.tooltip_text = intent_lbl.tooltip_text
		# A self-heal intent (the Hollow Prelate) carries no status, so the BUFF branch
		# leaves the readout blank — fill in the heal here so it's telegraphed.
		for heal_eff in enemy.current_intent.effects:
			if heal_eff is HealEffect and heal_eff.apply_to_source:
				value_str = " Heal %d" % heal_eff.value
				break
		# An attack that also debuffs (the Wasting Knight's wasting cut) keeps the
		# attack's damage readout but takes the crossed glyph and names the status.
		if enemy.current_intent.intent_type == EnemyMove.IntentType.ATTACK_DEBUFF:
			icon = "⚔☠"
			for debuff_eff in enemy.current_intent.effects:
				if debuff_eff is StatusApplyEffect and not debuff_eff.apply_to_source:
					value_str += " %s" % debuff_eff.status_effect.effect_name
					break
		# Passion pressure is its own threat category — an attack on your identity, not
		# your HP or your stats. Override the generic (usually DEBUFF) readout with a
		# distinct spark glyph + the Passion readout's own colour, so the eye goes to that stat.
		if _intent_affects_passion(enemy.current_intent):
			icon = "✧"
			intent_color = StageSkin.c("intent_passion")
			value_str = _passion_intent_readout(enemy.current_intent)
		# Name stays a muted constant color (flavor); the emphasized value carries the
		# intent color so the threat category reads from the big number, not the name.
		intent_lbl.add_theme_color_override("font_color", intent_color)
		intent_name_lbl.text = enemy.current_intent.move_name
		intent_name_lbl.visible = true
		intent_lbl.text = "%s%s" % [icon, value_str]
	else:
		intent_name_lbl.text = ""
		intent_name_lbl.visible = false
		intent_lbl.text = ""

	# Sight mode: render the next-turn intent below the current one. Hidden when
	# the player doesn't hold Excalibur or has it set to Sword mode.
	var sight_active = RunManager.has_excalibur() \
		and RunManager.excalibur_mode == RunManager.ExcaliburMode.SIGHT
	if sight_active and enemy.next_intent and not enemy.stats.is_dead():
		next_intent_lbl.text = "Then: %s" % _format_intent_preview(enemy.next_intent, enemy)
		next_intent_lbl.visible = true
	else:
		next_intent_lbl.visible = false

	panel.modulate = Color(0.4, 0.4, 0.4, 0.5) if enemy.stats.is_dead() else Color.WHITE


# ============================================================
# FULL UI REFRESH
# ============================================================

func _refresh_ui() -> void:
	if not combat_engine or not combat_engine.player_stats:
		return

	# Player stats
	hp_label.text = "HP: %d / %d" % [combat_engine.player_stats.current_hp,
		combat_engine.player_stats.max_hp]
	block_label.text = "Block: %d" % combat_engine.player_stats.block
	energy_label.text = "Energy: %d / %d" % [combat_engine.energy, CombatEngine.MAX_ENERGY]

	if RunManager.passion:
		var tier = RunManager.get_passion_tier()
		passion_label.text = "Passion: %d (%s)" % [
			RunManager.passion.current_value, PassionState.tier_name(tier)]
		if RunManager.current_character:
			var t = RunManager.current_character.passion_thresholds
			var c = RunManager.current_character
			passion_label.tooltip_text = (
				"Passion determines which personality dominates.\n" +
				"High = %s (Primary)  |  Low = %s (Secondary)\n\n" % [
					c.primary_personality, c.secondary_personality] +
				"Blazing: %d+  (Primary at full power)\n" % t[0] +
				"Inspired: %d-%d  (Primary favored)\n" % [t[1], t[0] - 1] +
				"Steady: %d-%d  (Balanced)\n" % [t[2], t[1] - 1] +
				"Wavering: %d-%d  (Secondary favored)\n" % [t[3], t[2] - 1] +
				"Hollow: <%d  (Secondary at full power)" % t[3])
	else:
		passion_label.text = "Passion: --"

	_populate_status_chips(player_status_chips, combat_engine.player_stats)
	player_status_prefix.visible = _fit_chip_row(player_status_chips) > 0

	_populate_power_chips(player_powers_chips, combat_engine.player_stats)
	player_powers_prefix.visible = _fit_chip_row(player_powers_chips) > 0

	# Piles
	draw_label.text = "Draw: %d" % combat_engine.piles.draw_pile.size()
	discard_label.text = "Discard: %d" % combat_engine.piles.discard_pile.size()
	exhaust_label.text = "Exhaust: %d" % combat_engine.piles.exhaust_pile.size()

	# Hand. The rebuild frees the hovered card without its mouse_exited, so its light goes here.
	if not _dragging_card:
		_set_lit_enemies([])
	# Out of the container now, not at the end of the frame: its minimum width counts every child,
	# and a full hand counted twice would push the whole layout off the screen for that frame.
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()
	card_nodes.clear()
	_hand_coins.clear()

	_fit_hand()
	for card in combat_engine.piles.hand:
		var panel = _create_card_panel(card)
		hand_container.add_child(panel)
		card_nodes[card] = panel

	# Enemies
	for enemy in combat_engine.enemies:
		_update_enemy_panel(enemy)

	_update_card_highlights()

	# End turn button
	var can_act = combat_engine.phase == CombatEngine.Phase.PLAYER_TURN
	end_turn_btn.disabled = not can_act

	# What the pack can do changes with HP and phase, so it redraws with everything else.
	consumable_bar.refresh()


## The hand keeps a gap while it fits the row, and past that overlaps by exactly what its size
## needs, so it never pushes End Turn or runs under the spacer.
func _fit_hand() -> void:
	var count: int = combat_engine.piles.hand.size()
	var separation := HAND_SEP
	if count > 1:
		var row_w := MAIN_W - 2.0 * (_hand_spacer.custom_minimum_size.x + BOTTOM_ROW_SEP)
		separation = mini(HAND_SEP, floori((row_w - CardFace.SIZE.x * count) / (count - 1)))
	hand_container.add_theme_constant_override("separation", separation)


# ============================================================
# COMBAT LOG
# ============================================================

# Small glyphs for statuses that have an obvious, well-supported symbol; the rest
# rely on the name + buff/debuff coloring. Kept to glyphs the game font already
# renders elsewhere (☠ ❄).
const STATUS_ICONS := {
	"Poison": "☠",
	"Frozen": "❄",
	"Chilled": "❅",
}


## Rebuilds `container` with one hover-describable chip per active status on `stats`.
## Replaces the old single merged label so each effect can be inspected on its own.
func _populate_status_chips(container: Node, stats: CombatantStats) -> void:
	for child in container.get_children():
		child.queue_free()
	for effect in stats.statuses:
		var stacks: int = stats.statuses[effect]
		if stacks > 0:
			container.add_child(_make_status_chip(effect, stacks))


## Rebuilds `container` with one chip per active character POWER. Distinct gold look
## from the status chips so persistent powers read apart from transient combat state.
func _populate_power_chips(container: Node, stats: CombatantStats) -> void:
	for child in container.get_children():
		child.queue_free()
	for power in stats.powers:
		var stacks: int = stats.powers[power]
		if stacks > 0:
			container.add_child(_make_power_chip(power, stacks))


func _make_power_chip(power: PowerData, stacks: int) -> PanelContainer:
	var chip = PanelContainer.new()
	var accent := Color(0.92, 0.78, 0.38)  # heraldic gold — the "power" color
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = accent
	style.bg_color = accent.darkened(0.68)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = ("✦ %s ×%d" % [power.power_name, stacks]) if stacks > 1 else ("✦ %s" % power.power_name)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", accent.lightened(0.5))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)

	chip.tooltip_text = "%s  (Power ×%d)\n%s" % [power.power_name, stacks, power.description]
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.mouse_entered.connect(func(): chip.modulate = Color(1.25, 1.25, 1.25))
	chip.mouse_exited.connect(func(): chip.modulate = Color.WHITE)
	return chip


## One status chip: name (+ optional glyph) and stack count, tinted green for buffs
## and red for debuffs, with a rich tooltip (kind · stacks, what it does, how it
## fades) and a subtle hover-highlight so it reads as inspectable.
func _make_status_chip(effect: StatusEffectData, stacks: int) -> PanelContainer:
	var chip = PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var accent := Color(0.4, 0.75, 0.45) if effect.is_buff else Color(0.82, 0.4, 0.4)
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = accent.darkened(0.1)
	style.bg_color = accent.darkened(0.72)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	var glyph: String = STATUS_ICONS.get(effect.effect_name, "")
	lbl.text = ("%s %s %d" % [glyph, effect.effect_name, stacks]) if glyph != "" \
		else ("%s %d" % [effect.effect_name, stacks])
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", accent.lightened(0.45))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)

	# Hover = the normal delayed engine tooltip (auto-hides). Click = show the same text
	# immediately and PIN it. The click is caught by manual hit-testing in _input (the
	# chips sit in PASS-filtered flow containers that don't reliably deliver gui_input),
	# so we expose the effect + stacks via group membership + metadata for that lookup.
	chip.tooltip_text = _status_desc_text(effect, stacks)
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_to_group("status_chip")
	chip.set_meta("status_effect", effect)
	chip.set_meta("status_stacks", stacks)
	# Subtle hover pop so it reads as individually inspectable.
	chip.mouse_entered.connect(func(): chip.modulate = Color(1.25, 1.25, 1.25))
	chip.mouse_exited.connect(func(): chip.modulate = Color.WHITE)
	return chip


## Shared rich description for a status effect: "Name (n) · kind\nwhat it does\nhow it
## fades". Used verbatim by both the hover tooltip and the click-pinned popup.
func _status_desc_text(effect: StatusEffectData, stacks: int) -> String:
	return "%s  (%d) · %s\n%s\n%s" % [
		effect.effect_name, stacks, effect.kind_label(),
		effect.description, effect.decay_note()]


## The topmost visible status chip under `pos` (viewport space), or null. Backs the
## click-to-pin hit-test in _input. Chips register in the "status_chip" group.
func _status_chip_at(pos: Vector2) -> Control:
	for node in get_tree().get_nodes_in_group("status_chip"):
		if node is Control and node.is_visible_in_tree() and node.get_global_rect().has_point(pos):
			return node
	return null


## Click-pinned status description. Unlike the hover tooltip (delayed, auto-hiding),
## this appears instantly on click and stays put until the player clicks elsewhere
## (dismiss hook lives at the top of _input). Positioned just above the clicked chip.
func _show_status_pin(anchor: Control, effect: StatusEffectData, stacks: int) -> void:
	_hide_status_pin()
	_status_pin = PanelContainer.new()
	_status_pin.z_index = 60
	_status_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent := Color(0.4, 0.75, 0.45) if effect.is_buff else Color(0.82, 0.4, 0.4)
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.border_color = accent
	style.bg_color = Color(0.09, 0.085, 0.078, 0.98)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	_status_pin.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = _status_desc_text(effect, stacks)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.93, 0.9, 0.85))
	lbl.custom_minimum_size.x = 230
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_pin.add_child(lbl)

	add_child(_status_pin)
	await get_tree().process_frame
	if not is_instance_valid(anchor) or not is_instance_valid(_status_pin):
		_hide_status_pin()
		return
	var pos = anchor.global_position
	_status_pin.global_position = Vector2(
		clampf(pos.x - 8, 10, 1920 - _status_pin.size.x - 10),
		maxf(10, pos.y - _status_pin.size.y - 8)
	)


func _hide_status_pin() -> void:
	if _status_pin:
		_status_pin.queue_free()
		_status_pin = null


func _log(msg: String) -> void:
	log_text.append_text(msg + "\n")


func _log_relic_activations(trigger: RelicData.RelicTrigger) -> void:
	for relic in RunManager.relics:
		if relic.trigger == trigger:
			_log("[color=cyan]>> %s: %s[/color]" % [relic.relic_name, relic.description])


# ============================================================
# EVENT HANDLERS
# ============================================================

func _on_combat_started() -> void:
	_lapis_taken = false
	_enemy_anims.clear()
	_enemy_lights.clear()
	for enemy in combat_engine.enemies:
		var panel = _create_enemy_panel(enemy)
		enemy_container.add_child(panel)
		enemy_nodes[enemy] = panel
	_log_relic_activations(RelicData.RelicTrigger.ON_COMBAT_START)
	if RunManager.passion:
		_passion_gauge.show_now()
		_stage.set_mood(RunManager.get_passion_tier(), true)
	_refresh_ui()
	_animate_card_draw()


func _on_card_played(card: CardData, _target) -> void:
	_log("Played [color=white]%s[/color]." % card.card_name)
	RunManager.run_stats["cards_played"] = RunManager.run_stats.get("cards_played", 0) + 1
	_refresh_ui()


## A consumable was used from the pack: say so in the log. The effect's own readouts (a heal, a
## status chip, the Passion bar) arrive through their usual signals; this only adds the line.
func _on_consumable_used(item: ConsumableData) -> void:
	_log("Used [color=white]%s[/color]. %s" % [item.display_name, item.description])
	_refresh_ui()


## A one-line note from a system with no log of its own (the Champion's Favour turning a blow).
func _on_combat_note(text: String) -> void:
	_log("[color=gold]%s[/color]" % text)
	_refresh_ui()


func _on_card_exhausted(card: CardData) -> void:
	_log("[color=gray]%s exhausted.[/color]" % card.card_name)


func _on_player_turn_started() -> void:
	_log("[color=cyan]--- Your Turn %d ---[/color]" % combat_engine.turn_number)
	_log_relic_activations(RelicData.RelicTrigger.ON_TURN_START)
	_show_turn_banner("Your Turn", StageSkin.c("banner_you"))
	_refresh_ui()
	_animate_card_draw()


func _on_enemy_turn_started() -> void:
	_log("[color=orange]--- Enemy Turn ---[/color]")
	_show_turn_banner("Enemy Turn", StageSkin.c("banner_enemy"))
	# Per-enemy "X uses Y" is announced as each one acts, in _on_enemy_action_started.
	_refresh_ui()


## Each enemy's beat: announce the move, lunge the model, then (0.35s later, from the
## engine) the effect lands. Makes the enemy turn play out readably.
func _on_enemy_action_started(enemy, move) -> void:
	if enemy == null or move == null:
		return
	_log("%s uses [color=white]%s[/color]!" % [enemy.enemy_data.enemy_name, move.move_name])
	var epanel: Control = enemy_nodes.get(enemy)
	if epanel:
		# Wind-up lunge: a quick scale punch from the feet. The name and bar under the body hold still.
		var stand: Control = epanel.get_meta("stand", epanel)
		var t = create_tween()
		t.tween_property(stand, "scale", Vector2(1.08, 1.08), 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(stand, "scale", Vector2(1.0, 1.0), 0.20).set_trans(Tween.TRANS_QUAD)
		_float_move_callout(epanel, move.move_name)
	# Play the attack strip for offensive intents; defends/buffs stay on idle.
	if move.intent_type == EnemyMove.IntentType.ATTACK \
			or move.intent_type == EnemyMove.IntentType.ATTACK_DEBUFF:
		_enemy_play(enemy, "attack")


## A Frozen enemy forfeits its turn. Mirror the move-callout beat with a "Frozen!"
## float and a soft blue shiver so the skip reads clearly instead of a silent gap.
func _on_enemy_stunned(enemy) -> void:
	if enemy == null:
		return
	_log("%s is [color=aqua]Frozen[/color] and skips its turn." % enemy.enemy_data.enemy_name)
	var epanel: Control = enemy_nodes.get(enemy)
	if epanel:
		epanel.pivot_offset = epanel.size / 2.0
		var t = create_tween()
		t.tween_property(epanel, "modulate", Color(0.6, 0.85, 1.15, 1.0), 0.18)
		t.tween_property(epanel, "modulate", Color(1, 1, 1, 1.0), 0.35)
		_float_move_callout(epanel, "Frozen!")


## The body an enemy panel holds, in screen space; the panel itself if it has none.
func _body_rect(epanel: Control) -> Rect2:
	var stand: Control = epanel.get_meta("stand", epanel)
	return stand.get_global_rect()


## Floats the move name up beside the enemy's head and fades it — the visible "X uses Y" beat.
func _float_move_callout(epanel: Control, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", load(StageSkin.NAME_FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", StageSkin.c("callout"))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", StageSkin.c("callout_outline"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size.x = 480.0
	lbl.z_index = 45
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var body := _body_rect(epanel)
	var start := Vector2(body.get_center().x - 240.0, maxf(body.position.y - 44.0, STAGE_TOP_Y + 42.0))
	lbl.global_position = start
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "global_position:y", start.y - 42, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.35)
	t.chain().tween_callback(lbl.queue_free)


func _on_player_damaged(amount: int, new_hp: int) -> void:
	if amount <= 0:
		# The attack was fully absorbed by block — no HP lost. Give a soft "absorbed"
		# cue (blue, no screen shake) instead of the misleading red damage flash.
		_log("[color=aqua]Absorbed.[/color]")
		_flash_absorb_overlay()
		_refresh_ui()
		return
	_log("[color=red]You take %d damage! (HP: %d)[/color]" % [amount, new_hp])
	RunManager.run_stats["damage_taken"] = RunManager.run_stats.get("damage_taken", 0) + amount
	# Scale the reaction to the hit so a chip reads differently from a haymaker.
	var mag := clampf(float(amount) / 18.0, 0.4, 1.6)
	_screen_shake(10.0 * mag, 0.25)
	_flash_damage_overlay(mag)
	_refresh_ui()


## The control-heal passive (or any heal) fired. Green log + bar refresh so the player
## sees they recovered by stilling the enemy. No screen shake — recovery, not a hit.
func _on_player_healed(amount: int, new_hp: int) -> void:
	if amount <= 0:
		return
	_log("[color=lightgreen]You recover %d HP. (HP: %d)[/color]" % [amount, new_hp])
	_refresh_ui()


func _on_enemy_damaged(enemy, amount: int, new_hp: int) -> void:
	_log("%s takes [color=yellow]%d damage[/color]. (HP: %d)" % [
		enemy.enemy_data.enemy_name, amount, new_hp])
	RunManager.run_stats["damage_dealt"] = RunManager.run_stats.get("damage_dealt", 0) + amount
	var panel = enemy_nodes.get(enemy)
	_spawn_damage_number("-%d" % amount, StageSkin.c("number_hurt"), panel)
	# Flinch on a real hit; a killing blow skips straight to the death throe below.
	if amount > 0 and new_hp > 0:
		_enemy_play(enemy, "hit")
	_refresh_ui()


## An enemy mended itself (the Hollow Prelate's self-heal). Green log + float + bar
## refresh so the player reads the DPS check: out-damage the heal or the fight drags.
func _on_enemy_healed(enemy, amount: int, new_hp: int) -> void:
	if amount <= 0:
		return
	_log("[color=lightgreen]%s recovers %d HP. (HP: %d)[/color]" % [
		enemy.enemy_data.enemy_name, amount, new_hp])
	var panel = enemy_nodes.get(enemy)
	_spawn_damage_number("+%d" % amount, StageSkin.c("number_heal"), panel)
	_refresh_ui()


func _on_enemy_died(enemy) -> void:
	_log("[color=green]%s defeated![/color]" % enemy.enemy_data.enemy_name)
	RunManager.run_stats["enemies_killed"] = RunManager.run_stats.get("enemies_killed", 0) + 1
	# Play the death strip under the fade-out _animate_enemy_death runs on the panel.
	_enemy_play(enemy, "death")
	# Boss death beat: a final line as the enemy falls (e.g. Caedmon, freed from the
	# compulsion — the Act-2 Puppeteer tease). Float it BEFORE _animate_enemy_death erases
	# the panel from enemy_nodes; the combat log keeps a permanent copy either way.
	var final_line: String = enemy.enemy_data.death_line
	if final_line != "":
		var panel: Control = enemy_nodes.get(enemy)
		if panel:
			_log("[color=wheat]%s: \"%s\"[/color]" % [enemy.enemy_data.enemy_name, final_line])
			_show_stage_line(final_line)
	_animate_enemy_death(enemy)
	_refresh_ui()


## A multi-phase boss crossed into a new phase: its bar refilled and its moveset swapped. The clip
## opens on this, so it has room: his bar shatters and his name and intent leave the ground, the
## stage dims around him, the colour goes out of him, and what he says runs large where they were.
## Nothing here holds input; the fight can go on under it, and the bar and intent come back with
## the new phase when the line is done.
func _on_enemy_phase_changed(enemy, _phase_index: int, line: String) -> void:
	_log("[color=wheat]%s changes![/color]" % enemy.enemy_data.enemy_name)
	var panel: Control = enemy_nodes.get(enemy)
	if panel:
		_shatter_bar(panel)
		_screen_shake(8.0, 0.3)
		_enemy_play(enemy, "break" if _has_strip(enemy, "break") else "hit")
		_drain_body(enemy)
		if line != "":
			var seconds := _show_stage_line(line)
			_stage.dim(seconds)
			_hide_enemy_words(panel, seconds)
	_refresh_ui()


func _has_strip(enemy, state: String) -> bool:
	var anim = _enemy_anims.get(enemy)
	return anim != null and SPRITE_SETS[anim["set"]]["anims"].has(state)


## The old bar in pieces, thrown off where it was. They are loose on the scene, so the panel's own
## bar can already be the new phase's underneath them.
func _shatter_bar(panel: Control) -> void:
	var bar: Control = panel.get_child(0).get_node("HPBarContainer")
	var rect := bar.get_global_rect()
	var pieces := 16
	var w := rect.size.x / pieces
	for i in pieces:
		var piece := ColorRect.new()
		piece.color = StageSkin.c("bar_high")
		piece.size = Vector2(w - 1.0, rect.size.y)
		piece.position = rect.position + Vector2(i * w, 0.0)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.z_index = 30
		add_child(piece)
		var off := (float(i) - (pieces - 1) / 2.0) / pieces
		var across := create_tween()
		across.tween_property(piece, "position:x", piece.position.x + off * randf_range(180.0, 420.0), 0.7)
		var flight := create_tween()
		flight.tween_property(piece, "position:y", piece.position.y - randf_range(20.0, 70.0), 0.16) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		flight.tween_property(piece, "position:y", piece.position.y + randf_range(40.0, 110.0), 0.54) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		var fade := create_tween()
		fade.tween_interval(0.35)
		fade.tween_property(piece, "modulate:a", 0.0, 0.35)
		fade.tween_callback(piece.queue_free)


## A blink of light, then the colour goes out of the body and stays out. A shaking hand with it.
func _drain_body(enemy) -> void:
	var anim = _enemy_anims.get(enemy)
	if anim == null or not is_instance_valid(anim["rect"]):
		return
	var body: TextureRect = anim["rect"]
	var flash := create_tween()
	flash.tween_property(body, "modulate", Color(1.7, 1.7, 1.7), 0.05)
	flash.tween_property(body, "modulate", Color.WHITE, 0.3)
	var mat: ShaderMaterial = body.material
	var drain := create_tween()
	drain.tween_method(func(v: float): mat.set_shader_parameter("drain", v), 0.0, 1.0, BREAK_DRAIN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# He shakes by a whole sprite pixel, to stay on the grid.
	var px: float = body.size.x / float(anim["fw"])
	var home := body.position
	var shake := create_tween().set_loops(10)
	shake.tween_callback(func(): if is_instance_valid(body): body.position.x = home.x + px)
	shake.tween_interval(0.12)
	shake.tween_callback(func(): if is_instance_valid(body): body.position.x = home.x)
	shake.tween_interval(0.12)


## The name, the bar and the intent leave the ground for as long as a line runs on it.
func _hide_enemy_words(panel: Control, seconds: float) -> void:
	for child in panel.get_child(0).get_children():
		if child.name == &"Place":
			continue
		var t := create_tween()
		t.tween_property(child, "modulate:a", 0.0, 0.12)
		t.tween_interval(seconds - 0.12)
		t.tween_property(child, "modulate:a", 1.0, 0.3)


## A line said out loud, run out large on the ground under the bodies. Returns how long it stays.
func _show_stage_line(text: String) -> float:
	if is_instance_valid(_stage_line):
		_stage_line.queue_free()
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = STAGE_LINE_RECT.position
	lbl.size = STAGE_LINE_RECT.size
	lbl.z_index = 60
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_override("font", load(StageSkin.LINE_FONT_PATH))
	lbl.add_theme_font_size_override("font_size", STAGE_LINE_SIZE)
	lbl.add_theme_constant_override("line_spacing", -6)
	lbl.add_theme_color_override("font_color", StageSkin.c("line"))
	lbl.add_theme_color_override("font_outline_color", StageSkin.c("line_outline"))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.visible_ratio = 0.0
	add_child(lbl)
	_stage_line = lbl
	var run := text.length() / STAGE_LINE_CHARS_PER_SEC
	var t := create_tween()
	t.tween_interval(0.25)
	t.tween_property(lbl, "visible_ratio", 1.0, run)
	t.tween_interval(STAGE_LINE_HOLD)
	t.tween_property(lbl, "modulate:a", 0.0, 0.3)
	t.tween_callback(lbl.queue_free)
	return 0.25 + run + STAGE_LINE_HOLD


## For a capture: breaks an enemy's bar through the engine's real path, wherever its HP stands.
func trigger_boss_break(enemy) -> void:
	var left: int = enemy.stats.current_hp
	enemy.stats.current_hp = 0
	combat_engine._on_damage_dealt(enemy.stats, left)


func _on_block_gained(target, amount: int) -> void:
	# A negative amount is Block taken away (the hawk's Bind strips a guard): the same signal,
	# read as a loss, so the bar and the number both show it going.
	var number := ("+%d" if amount >= 0 else "%d") % amount
	if target == combat_engine.player_stats:
		if amount >= 0:
			_log("Gained [color=cyan]%d Block[/color]." % amount)
		else:
			_log("Lost [color=cyan]%d Block[/color]." % -amount)
		_spawn_damage_number(number, StageSkin.c("number_block"), null)
	else:
		for enemy in combat_engine.enemies:
			if enemy.stats == target:
				if amount >= 0:
					_log("%s gains [color=cyan]%d Block[/color]." % [
						enemy.enemy_data.enemy_name, amount])
				else:
					_log("%s loses [color=cyan]%d Block[/color]." % [
						enemy.enemy_data.enemy_name, -amount])
				var panel = enemy_nodes.get(enemy)
				_spawn_damage_number(number, StageSkin.c("number_block"), panel)
				break
	_refresh_ui()


func _on_passion_changed(old_value: int, new_value: int) -> void:
	var diff = new_value - old_value
	if diff > 0:
		_log("[color=orange]Passion +%d (%d)[/color]" % [diff, new_value])
	else:
		_log("[color=orange]Passion %d (%d)[/color]" % [diff, new_value])
	_refresh_ui()
	_passion_gauge.move_to(new_value)
	var old_tier: int = RunManager.get_passion_tier_for_value(old_value)
	var new_tier: int = RunManager.get_passion_tier_for_value(new_value)
	if old_tier != new_tier:
		_stage.set_mood(new_tier)
		# Deferred: the rest of this card's effects rebuild the hand again, and would free the coins.
		_relight_coins.call_deferred(old_value, new_value)


## Crossing a band, the coins relight across the hand one after another, left to right. Each rises
## from what it showed before and settles on what the new band gives it: lit at a pole, out elsewhere.
func _relight_coins(old_value: int, new_value: int) -> void:
	var i := 0
	for card in combat_engine.piles.hand:
		var disc = _hand_coins.get(card)
		if disc == null or not is_instance_valid(disc):
			continue
		disc.modulate.a = 1.0 if _is_extreme_favored(card.personality, old_value) else 0.0
		var settle := 1.0 if _is_extreme_favored(card.personality, new_value) else 0.0
		var tw: Tween = disc.create_tween()
		tw.tween_interval(i * COIN_STAGGER)
		tw.tween_property(disc, "modulate:a", 1.0, 0.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(disc, "modulate:a", settle, 0.3).set_trans(Tween.TRANS_SINE)
		i += 1


## Would this card's pole sit at its EXTREME favored tier (Blazing for Water / Hollow for Physical)
## at the given Passion value? Drives the halo-coin fade exactly on the threshold crossing, without
## depending on the live-Passion globals that zone_multiplier reads.
func _is_extreme_favored(personality: CardData.PersonalityType, passion_value: int) -> bool:
	if not RunManager.current_character:
		return false
	var t = RunManager.current_character.passion_thresholds
	if t.size() < 4:
		return false
	if personality == CardData.PersonalityType.PRIMARY:
		return passion_value >= t[0]
	if personality == CardData.PersonalityType.SECONDARY:
		return passion_value < t[3]
	return false


func _on_status_applied(target, effect: StatusEffectData, stacks: int) -> void:
	var name = _get_combatant_name(target)
	var color = "green" if effect.is_buff else "salmon"
	_log("[color=%s]%s: +%d %s[/color]" % [color, name, stacks, effect.effect_name])
	_refresh_ui()


func _on_status_removed(target, effect: StatusEffectData) -> void:
	var name = _get_combatant_name(target)
	_log("[color=gray]%s: %s wore off.[/color]" % [name, effect.effect_name])
	_refresh_ui()


func _get_combatant_name(stats) -> String:
	if stats == combat_engine.player_stats:
		return "You"
	for enemy in combat_engine.enemies:
		if enemy.stats == stats:
			return enemy.enemy_data.enemy_name
	return "???"


func _show_turn_banner(text: String, color: Color) -> void:
	if not is_inside_tree():
		return
	# Containers lay out after the frame they change in, and turn one starts inside _ready, so
	# the gap can only be read once layout has run.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var banner = Label.new()
	banner.text = text
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 34)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_outline_color", StageSkin.c("banner_outline"))
	banner.add_theme_constant_override("outline_size", 6)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 20
	# Full width so the text is truly screen-centered, placed in the gap between the
	# enemy panels and the player readout: computed, not hardcoded.
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var banner_h := 48.0
	var gap_y := _turn_banner_gap_center() - banner_h / 2.0
	banner.offset_left = 0
	banner.offset_right = 0
	banner.offset_top = gap_y
	banner.offset_bottom = gap_y + banner_h
	banner.modulate.a = 0.0
	add_child(banner)
	var t = create_tween()
	t.tween_property(banner, "modulate:a", 1.0, 0.1)
	t.tween_interval(0.4)
	t.tween_property(banner, "modulate:a", 0.0, 0.2)
	t.tween_callback(banner.queue_free)


## The middle of the gap between the lowest living enemy panel and the top of the player bar.
func _turn_banner_gap_center() -> float:
	return (_enemies_bottom() + _player_bar.global_position.y) / 2.0


func _enemies_bottom() -> float:
	var bottom := enemy_container.global_position.y
	for enemy in enemy_nodes:
		var epanel: Control = enemy_nodes[enemy]
		if is_instance_valid(epanel) and epanel.is_visible_in_tree():
			bottom = maxf(bottom, epanel.global_position.y + epanel.size.y)
	return bottom


func _screen_shake(intensity: float = 8.0, duration: float = 0.2) -> void:
	if not _main_container:
		return
	# The settings "Screen Shake" toggle gates all shake (a real accessibility/comfort
	# option now, not a dead print). Persisted via ProfileManager.
	if not ProfileManager.screen_shake:
		return
	var base_pos = _main_container.position
	var tween = create_tween()
	var steps := 6
	for i in steps:
		var offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		intensity *= 0.7
		tween.tween_property(_main_container, "position", base_pos + offset, duration / steps)
	tween.tween_property(_main_container, "position", base_pos, duration / steps)


func _spawn_damage_number(text: String, color: Color, target_panel: Control) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", load(StageSkin.NAME_FONT_PATH))
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", StageSkin.c("number_outline"))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size.x = 200.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 10

	if target_panel:
		# Over the chest, a little to the side, so it never covers the face.
		var body := _body_rect(target_panel)
		lbl.position = Vector2(body.get_center().x - 100.0 + body.size.x * 0.3, body.position.y + body.size.y * 0.25)
	else:
		# The player has no body on the stage: their numbers rise off the player bar.
		lbl.position = Vector2(hp_label.global_position.x - 260.0, _player_bar.global_position.y - 64.0)

	add_child(lbl)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 60, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(lbl.queue_free)


func _on_combat_won() -> void:
	_log("\n[color=gold]========== VICTORY! ==========[/color]")
	AudioManager.play_sfx("gold_gain")
	end_turn_btn.disabled = true
	_spawn_victory_particles()
	# Sync HP back to RunManager
	RunManager.current_hp = combat_engine.player_stats.current_hp
	# Process end-of-combat relics
	combat_engine.process_combat_end_relics()
	for relic in RunManager.relics:
		if relic.trigger == RelicData.RelicTrigger.ON_COMBAT_END:
			_log("[color=cyan]%s: %s[/color]" % [relic.relic_name, relic.description])
	# Show continue button
	_show_continue_button("Continue", _on_continue_pressed)


func _on_combat_lost() -> void:
	_log("\n[color=red]========== DEFEAT ==========[/color]")
	end_turn_btn.disabled = true
	RunManager.end_run(false)
	_show_continue_button("Game Over", _on_game_over_pressed)


func _on_end_turn_pressed() -> void:
	if combat_engine.phase == CombatEngine.Phase.PLAYER_TURN:
		AudioManager.play_sfx("button_click")
		if _dragging_card:
			_cancel_drag()
		selected_card = null
		_animate_hand_discard()
		combat_engine.end_player_turn()


## Flies the non-retained hand cards to the discard-pile indicator (a quick fading,
## shrinking stagger) so the end-of-turn discard reads as intentional instead of the
## hand popping empty during the (now paced) enemy turn. The panels are reparented
## out of the hand first so the imminent _refresh_ui hand rebuild can't free them
## mid-flight; retained cards are left in hand.
func _animate_hand_discard() -> void:
	var target := discard_label.global_position + discard_label.size / 2.0
	var i := 0
	for card in card_nodes.keys():
		if card.retain:
			continue
		var panel: Control = card_nodes[card]
		if not is_instance_valid(panel):
			continue
		var start_pos: Vector2 = panel.global_position
		panel.get_parent().remove_child(panel)
		add_child(panel)
		panel.global_position = start_pos
		panel.z_index = 25
		panel.pivot_offset = panel.size / 2.0
		var delay := i * 0.035
		var t = create_tween().set_parallel(true)
		t.tween_property(panel, "global_position", target, 0.32).set_delay(delay) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.tween_property(panel, "scale", Vector2(0.25, 0.25), 0.32).set_delay(delay)
		t.tween_property(panel, "modulate:a", 0.0, 0.26).set_delay(delay + 0.08)
		t.chain().tween_callback(panel.queue_free)
		i += 1


func _show_continue_button(text: String, callback: Callable) -> void:
	continue_btn = Button.new()
	continue_btn.text = text
	continue_btn.custom_minimum_size = Vector2(200, 60)
	continue_btn.add_theme_font_size_override("font_size", 22)
	continue_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	continue_btn.pressed.connect(callback)
	# Add next to the end turn button, and widen the spacer by as much so the hand stays centred.
	end_turn_btn.get_parent().add_child(continue_btn)
	_hand_spacer.custom_minimum_size.x += continue_btn.custom_minimum_size.x + BOTTOM_ROW_SEP
	_fit_hand()


func _on_continue_pressed() -> void:
	# A fight launched from an event (the Sword guardian, the raider ambush) skips the
	# normal reward — victory routes back to event_scene, which reads pending_special_event
	# for the follow-up beat that grants the quest reward.
	if RunManager.pending_event_combat:
		RunManager.pending_event_combat = false
		SceneTransition.change_scene("res://scenes/event/event_scene.tscn")
		return
	if RunManager.pending_relic_reward:
		# Check if relics are actually available before showing relic screen
		var owned = RunManager.get_owned_relic_names()
		var has_relics = false
		if RunManager.pending_relic_is_boss:
			has_relics = RelicPool.get_boss_reward_choices(RngManager.loot_rng, owned).size() > 0
		else:
			has_relics = RelicPool.get_reward_choices(RngManager.loot_rng, 3, owned).size() > 0
		RunManager.pending_relic_reward = false
		if has_relics:
			SceneTransition.change_scene("res://scenes/reward/relic_reward_scene.tscn")
		else:
			SceneTransition.change_scene("res://scenes/reward/card_reward_scene.tscn")
	else:
		SceneTransition.change_scene("res://scenes/reward/card_reward_scene.tscn")


func _on_game_over_pressed() -> void:
	SceneTransition.change_scene("res://scenes/game_over/game_over_scene.tscn")


# ============================================================
# ANIMATED HP BARS
# ============================================================

func _animate_hp_bar(bar: ProgressBar, new_value: float) -> void:
	var old_value = bar.value
	bar.value = new_value
	# Animate trail bar with delay
	var trail: ProgressBar = _hp_trail_bars.get(bar)
	if trail:
		trail.max_value = bar.max_value
		if new_value < old_value:
			# Damage: trail lags behind
			var t = create_tween()
			t.tween_property(trail, "value", new_value, 0.6).set_delay(0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		else:
			# Heal: trail catches up instantly
			trail.value = new_value


# ============================================================
# CARD HOVER DETAIL POPUP
# ============================================================

func _show_card_hover(card: CardData, source_panel: PanelContainer) -> void:
	_hide_card_hover()
	_hover_popup = PanelContainer.new()
	_hover_popup.custom_minimum_size = Vector2(260, 340)
	_hover_popup.z_index = 50
	_hover_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	match card.card_type:
		CardData.CardType.ATTACK:
			style.bg_color = Color(0.25, 0.08, 0.06, 0.97)
			style.border_color = Color(1.0, 0.3, 0.2)
		CardData.CardType.SKILL:
			style.bg_color = Color(0.06, 0.1, 0.28, 0.97)
			style.border_color = Color(0.25, 0.5, 1.0)
		CardData.CardType.POWER:
			style.bg_color = Color(0.25, 0.22, 0.04, 0.97)
			style.border_color = Color(1.0, 0.85, 0.15)

	# Upgraded card green border tint
	if card.upgraded:
		style.border_color = style.border_color.lerp(Color(0.3, 0.9, 0.3), 0.5)

	_hover_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_hover_popup.add_child(vbox)

	# Cost circle
	var cost_lbl = Label.new()
	cost_lbl.text = card.cost_label() + " Energy"
	cost_lbl.add_theme_font_size_override("font_size", 20)
	cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.3))
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)

	# Name
	var name_lbl = Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	# Type + Rarity
	var type_names = ["Attack", "Skill", "Power"]
	var rarity_names = ["Starter", "Common", "Uncommon", "Rare"]
	var rarity_colors = [Color(0.5, 0.5, 0.5), Color(0.55, 0.55, 0.55), Color(0.3, 0.7, 0.9), Color(0.95, 0.8, 0.2)]
	var tr_lbl = Label.new()
	tr_lbl.text = "%s - %s" % [type_names[card.card_type], rarity_names[card.rarity]]
	tr_lbl.add_theme_font_size_override("font_size", 15)
	tr_lbl.add_theme_color_override("font_color", rarity_colors[card.rarity])
	tr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tr_lbl)

	# Personality
	if card.personality != CardData.PersonalityType.NEUTRAL:
		var pers_lbl = Label.new()
		pers_lbl.text = _get_personality_label(card.personality)
		pers_lbl.add_theme_font_size_override("font_size", 14)
		pers_lbl.add_theme_color_override("font_color", _get_personality_color(card.personality))
		pers_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(pers_lbl)

	# Art area
	var art = PanelContainer.new()
	art.custom_minimum_size = Vector2(0, 60)
	var art_s = StyleBoxFlat.new()
	art_s.set_corner_radius_all(6)
	art_s.content_margin_top = 8
	art_s.content_margin_bottom = 8
	match card.card_type:
		CardData.CardType.ATTACK:
			art_s.bg_color = Color(0.4, 0.1, 0.08)
		CardData.CardType.SKILL:
			art_s.bg_color = Color(0.08, 0.15, 0.35)
		CardData.CardType.POWER:
			art_s.bg_color = Color(0.35, 0.28, 0.06)
	art.add_theme_stylebox_override("panel", art_s)
	var icon_file2 = CardVisuals.icon_path(card.card_name)
	if icon_file2 != "":
		var art_icon = TextureRect.new()
		art_icon.texture = load(icon_file2)
		art_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art_icon.custom_minimum_size = Vector2(48, 48)
		art.add_child(art_icon)
	else:
		var art_lbl = Label.new()
		match card.card_type:
			CardData.CardType.ATTACK: art_lbl.text = "⚔"
			CardData.CardType.SKILL: art_lbl.text = "◆"
			CardData.CardType.POWER: art_lbl.text = "★"
		art_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		art_lbl.add_theme_font_size_override("font_size", 32)
		art_lbl.add_theme_color_override("font_color", style.border_color.lightened(0.3))
		art.add_child(art_lbl)
	vbox.add_child(art)

	# Description
	var desc = Label.new()
	if combat_engine and combat_engine.player_stats:
		desc.text = card.get_modified_description(combat_engine.player_stats)
	else:
		desc.text = card.get_generated_description()
	desc.add_theme_font_size_override("font_size", 18)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)

	# Optional flavor text (hover popup uses larger font for legibility)
	if card.flavor_text != "":
		var flavor = Label.new()
		flavor.text = card.flavor_text
		flavor.add_theme_font_size_override("font_size", 13)
		flavor.add_theme_color_override("font_color", Color(0.65, 0.6, 0.54))
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(flavor)

	# Exhaust tag
	if card.exhaust:
		var ex = Label.new()
		ex.text = "Exhaust"
		ex.add_theme_font_size_override("font_size", 14)
		ex.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4))
		ex.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(ex)

	# Target type
	var target_lbl = Label.new()
	match card.target_type:
		CardData.TargetType.SINGLE_ENEMY: target_lbl.text = "Target: Single Enemy"
		CardData.TargetType.ALL_ENEMIES: target_lbl.text = "Target: All Enemies"
		CardData.TargetType.SELF: target_lbl.text = "Target: Self"
		_: target_lbl.text = ""
	if target_lbl.text:
		target_lbl.add_theme_font_size_override("font_size", 13)
		target_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(target_lbl)

	_ignore_mouse_recursive(_hover_popup)

	# Position above the source card
	add_child(_hover_popup)
	await get_tree().process_frame
	if not is_instance_valid(source_panel) or not is_instance_valid(_hover_popup):
		if is_instance_valid(_hover_popup):
			_hover_popup.queue_free()
			_hover_popup = null
		return
	var pos = source_panel.global_position
	_hover_popup.global_position = Vector2(
		clampf(pos.x - 50, 10, 1920 - _hover_popup.size.x - 10),
		maxf(10, pos.y - _hover_popup.size.y - 10)
	)


func _hide_card_hover() -> void:
	if _hover_popup:
		_hover_popup.queue_free()
		_hover_popup = null


# ============================================================
# VICTORY PARTICLES
# ============================================================

func _spawn_victory_particles() -> void:
	for i in 30:
		var p = ColorRect.new()
		p.custom_minimum_size = Vector2(4, 4)
		p.size = Vector2(4, 4)
		var brightness = randf_range(0.7, 1.0)
		p.color = Color(brightness, brightness * 0.85, brightness * 0.3, randf_range(0.3, 0.8))
		p.position = Vector2(randf_range(200, 1720), randf_range(400, 700))
		p.z_index = 25
		add_child(p)
		var t = create_tween().set_parallel(true)
		t.tween_property(p, "position:y", p.position.y - randf_range(200, 500), randf_range(1.0, 2.5)).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "position:x", p.position.x + randf_range(-100, 100), randf_range(1.0, 2.5))
		t.tween_property(p, "modulate:a", 0.0, 1.5).set_delay(0.8)
		t.chain().tween_callback(p.queue_free)


# ============================================================
# DAMAGE FLASH
# ============================================================

func _flash_damage_overlay(intensity: float = 1.0) -> void:
	if not _damage_flash:
		return
	_damage_flash.color = Color(0.8, 0.05, 0.05, clampf(0.35 * intensity, 0.12, 0.55))
	var t = create_tween()
	t.tween_property(_damage_flash, "color:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)


## Soft blue "absorbed" pulse for a fully-blocked hit — distinct from the red
## damage flash, and no screen shake, so block reads as safe rather than as a hit.
func _flash_absorb_overlay() -> void:
	if not _damage_flash:
		return
	_damage_flash.color = Color(0.3, 0.6, 0.95, 0.16)
	var t = create_tween()
	t.tween_property(_damage_flash, "color:a", 0.0, 0.25).set_ease(Tween.EASE_OUT)
	# Restore the red base so the next real hit flashes red, not blue.
	t.tween_callback(func(): _damage_flash.color = Color(0.8, 0.05, 0.05, 0.0))


# ============================================================
# ENEMY DEATH ANIMATION
# ============================================================

func _animate_enemy_death(enemy: EnemyCombatState) -> void:
	var panel: PanelContainer = enemy_nodes.get(enemy)
	if not panel:
		return
	# Burst particles from the enemy position
	var center := _body_rect(panel).get_center()
	for i in 15:
		var p = ColorRect.new()
		p.custom_minimum_size = Vector2(5, 5)
		p.size = Vector2(5, 5)
		p.color = Color(randf_range(0.6, 1.0), randf_range(0.2, 0.5), randf_range(0.1, 0.3), 0.8)
		p.position = center
		p.z_index = 20
		add_child(p)
		var angle = randf_range(0, TAU)
		var dist = randf_range(60, 180)
		var target_pos = center + Vector2(cos(angle), sin(angle)) * dist
		var t = create_tween().set_parallel(true)
		t.tween_property(p, "position", target_pos, randf_range(0.4, 0.8)).set_ease(Tween.EASE_OUT)
		t.tween_property(p, "modulate:a", 0.0, 0.6).set_delay(0.2)
		t.chain().tween_callback(p.queue_free)
	# Fade and sink the panel, then remove it. Detach it from enemy_nodes up front so any refresh in
	# the same frame can't re-touch the corpse. An empty column of its width takes its place, so the
	# bodies still standing don't slide across the stage.
	panel.pivot_offset = Vector2(panel.size.x / 2.0, BODY_MAX_H)
	enemy_nodes.erase(enemy)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(panel, "modulate:a", 0.0, 0.5)
	t.tween_property(panel, "scale", Vector2(0.3, 0.3), 0.5).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(_leave_empty_column.bind(panel))


func _leave_empty_column(panel: Control) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.x = panel.size.x
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_container.add_child(gap)
	enemy_container.move_child(gap, panel.get_index())
	panel.queue_free()


# ============================================================
# CARD DRAW ANIMATION
# ============================================================

func _animate_card_draw() -> void:
	var delay := 0.0
	for card in card_nodes:
		var panel: PanelContainer = card_nodes[card]
		panel.pivot_offset = panel.custom_minimum_size / 2.0
		panel.scale = Vector2(0.0, 0.0)
		panel.modulate.a = 0.0
		var t = create_tween().set_parallel(true)
		# from(): the hand's sort resets scale before a delayed tween starts, and without it every
		# card but the first would skip the pop.
		t.tween_property(panel, "scale", Vector2.ONE, 0.18).from(Vector2.ZERO).set_delay(delay) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(panel, "modulate:a", 1.0, 0.12).set_delay(delay)
		delay += 0.05
