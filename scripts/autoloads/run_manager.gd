extends Node
## Manages the lifecycle of a single run.
## Owns all persistent run state: deck, relics, equipment, gold, passion, act progression.

var current_character: CharacterData
var current_deck: Array[CardData] = []
var relics: Array[RelicData] = []
var equipment: Dictionary = {} # EquipmentData.EquipmentSlot -> EquipmentData (deprecated, see Titles)
var perks: Array[PerkData] = []
## Held consumables: the fourth power layer. A hard cap of CONSUMABLE_SLOTS, and no relic widens
## it, so "which two" means the same thing from the first node to the last. See ConsumableData.
var consumables: Array[ConsumableData] = []
## The companion travelling with the player (PetPool id), or &"" for none. A source with its own
## card pool: on a chance each player turn one of its cards arrives in hand
## (CombatEngine._maybe_pet_arrival). One companion per run for now.
var pet_id: StringName = &""
var gold: int = 0
var current_act: int = 0
var current_hp: int = 0
var max_hp: int = 0
var passion: PassionState
var run_active: bool = false
var current_map: MapData
var pending_enemies: Array[EnemyData] = []
var pending_gold_reward: int = 0
var pending_relic_reward: bool = false
var pending_relic_is_boss: bool = false
var pending_act_complete: bool = false
## When non-empty, the event scene renders a hand-authored special event
## instead of pulling from EventPool. Used for realm signature nodes like
## Camelot's Sword in the Stone. Cleared on consumption.
var pending_special_event: StringName = &""
## Count of ORDINARY (random-pool) event nodes entered this run. Quest/signature events
## route through pending_special_event before the scene change, so they never reach the
## random branch and never advance this count — it tracks only the player's "Nth event".
var ordinary_event_count: int = 0
## Pins a scripted story beat to a given ordinary-event ordinal: {ordinal:int -> event id}.
## Lets a beat play on, say, the player's 2nd event (Cass's intro) while the rest stay
## random. Empty = fully random. Populated per run in start_run; the ids resolve through
## event_scene._build_special_event, the same authoring path as the signature events.
var scripted_event_schedule := {}
## True while a fight that was LAUNCHED FROM AN EVENT is in progress, so combat victory
## routes back to event_scene (which reads pending_special_event for the follow-up beat)
## rather than the normal reward flow. Used by the Sword-in-the-Stone guardian and the
## raider questline payoff. Cleared when consumed.
var pending_event_combat: bool = false
## A VN segment queued for vn_scene to play (realm-entry, the Fable send-off, story beats).
## vn_scene reads + clears it, applies its chosen choice's consequences, then pulls the
## next segment from pending_vn_queue (below), and only routes to pending_vn_next when the
## queue is empty. Cleared at run start.
var pending_vn: VNData = null
## Follow-on VN segments played after pending_vn, in order. The run-start sequencer loads
## this with [Camelot realm-entry] so the flow is: send-off -> realm-entry -> map.
var pending_vn_queue: Array[VNData] = []
var pending_vn_next: String = "res://scenes/map/map_scene.tscn"
## A realm map_boon queued by apply_realm_config, resolved once when the map next opens
## (map_scene._ready -> consume_map_boon). StringName id; &"" = nothing pending.
var pending_map_boon: StringName = &""
## A one-shot boon queued by an event, applied at the START of the next combat and then
## cleared (CombatEngine._apply_pending_combat_boon). StringName id; &"" = nothing pending.
## The Shade at the Cross queues &"wandering_vigor" (+2 Strength for that one fight).
var pending_combat_boon: StringName = &""
## When true, the next map node the player enters is passed through: position advances and the
## node is marked visited, but its content (combat/shop/event/...) is skipped. Set by the
## Tourney's walk-on shortcut; consumed by map_scene on the next node entry. Never skips a boss.
var pending_skip_node: bool = false
var run_start_time: int = 0 # msec from Time.get_ticks_msec()
var run_stats: Dictionary = {}

# --- Realm tracking ---
# current_realm is a StringName id; resolve via RealmRegistry.get_realm()
var current_realm_id: StringName = &"camelot"
# Tracks which realms have been visited this run (in entry order).
# Used by the Realm Selection screen to exclude already-visited realms.
var visited_realm_ids: Array[StringName] = []
# The current realm's run-shape config (difficulty / economy / map knobs), set by the
# realm-entry VN choice (Camelot: court vs common folk). Neutral by default; reset at run
# start and re-set on entering each realm. See RealmConfig + docs/REALM_CAMELOT.md.
var realm_config := RealmConfig.new()

# --- Titles ---
# All title ids the player has earned this run (whether equipped or not).
var earned_title_ids: Array[StringName] = []
# Slot 0 and slot 1; an empty StringName (&"") means no title equipped.
var active_title_slots: Array[StringName] = [&"", &""]
# For each realm title, whether the player has left its origin realm at least once.
# title_id -> bool. Drives Degraded vs Original tier resolution.
var _title_has_left_origin: Dictionary[StringName, bool] = {}
# For each realm title, whether the player has returned to origin after leaving.
# Triggers Returning tier (or restoration to Original if reclamation succeeded).
var _title_has_returned: Dictionary[StringName, bool] = {}
# For each realm title, whether a reclamation succeeded since the most recent return.
# When true, the title resolves to Original even though has_returned is true.
var _title_reclaimed: Dictionary[StringName, bool] = {}
# How much max HP the currently-equipped titles have added. Tracked so we can apply
# deltas cleanly when titles change tier or are swapped out, without double-counting.
var _title_applied_max_hp_bonus: int = 0
# Active-title charges remaining in the current period. title_id -> charges left.
# Only titles with an active block are tracked. Titles are a pull model everywhere else
# (every passive is polled at its use site through get_title_passive_total), so this is
# the one piece of title state that is pushed: it is spent, it runs out, and the map has
# to be able to see it. Refreshed on the period boundary by _refresh_title_charges.
var _title_active_charges: Dictionary[StringName, int] = {}

# --- Excalibur dual-mode ---
# Sword (0) adds the Excalibur power card to the player's draw pile at start of
# each combat. Sight (1) is passive — reveals enemy intents one turn ahead.
# Defaults to Sword. The toggle is only meaningful when the player holds the
# Excalibur relic; if they don't, this value is ignored.
enum ExcaliburMode { SWORD, SIGHT }
var excalibur_mode: int = ExcaliburMode.SWORD

# --- The Thurible (Reliquary censer relic) ---
# A per-fight toggle: each fight the player picks which pole the censer swings their
# Passion toward — Blazing (+) or Hollow (-). Combat reads the mode at the start of each
# player turn and pushes Passion by the relic's value in that direction. Defaults to
# Blazing. Only meaningful while the player holds The Thurible; otherwise ignored.
enum ThuribleMode { BLAZING, HOLLOW }
var thurible_mode: int = ThuribleMode.BLAZING

# --- Crown & Reign (Phase 2) ---
# Set once when the player takes the crown at the Act 1 Camelot boss.
# philosophy_id values: &"iron_fist", &"leave_to_me", &"together", &""
# together_subchoice values (only set if philosophy_id == &"together"):
#   &"wealth", &"wisdom", &"faith"
# philosophy_strength_tier is the BTK tier rolled at the Act 1 boss (0-3),
# snapshotted at crown-taking and immutable for the rest of the run — this
# is the "moment in time" that sets modifier magnitude for the chosen path.
# kings_reputation is a separate 0-1 running dial fed by subsequent boss rolls
# (weighted recent: new = 0.4 * old + 0.6 * latest). It's the score the realm
# uses at narrative beats — true ending checks, king's-roll events — and is
# NOT used to set modifier magnitude.
# last_btk_score is the score from the most recent boss fight, preserved for
# narrative display in the post-fight crown / abdication scenes before it's
# folded into kings_reputation.
var philosophy_id: StringName = &""
var philosophy_strength_tier: int = 0
var together_subchoice: StringName = &""
var kings_reputation: float = 0.0
var last_btk_score: float = 0.0
# Tier from the most recent boss BTK roll (BeTheKing.Tier value). Snapshotted
# into philosophy_strength_tier the moment the crown is taken; thereafter the
# tier field continues to update with later boss rolls but only kings_reputation
# and narrative phrases consume it.
var last_btk_tier: int = 0
var has_abdicated: bool = false
# Per-realm court<->folk standing: positive = the people's favor, negative = the court's
# favor, 0 = neutral. The "A Realm Divided" pledge plants you on one side (Folk +, Court -
# via RealmConfig.standing_init), and faction-aligned event choices nudge it from there.
# Read by favor-gated event options (has_folk_favor / has_court_favor) and the run's ending.
var realm_standing: Dictionary[StringName, int] = {}
# Standing magnitude that counts as a faction's favor. The pledge's +-25 clears it, so the
# pledged side's favor-gated options unlock immediately; crossing to the other side's favor
# takes committed play. Tunable with the pledge values in the balance pass.
const FAVOR_THRESHOLD := 20
# Standing that marks a "people's champion" at run's end: deliberately above the Folk pledge
# alone (+25), so you must reinforce the pledge with at least one pro-folk act (the tithe's
# folk option +12, or taking the raider hunt +8) to clear it. Drives the ending variant.
const PEOPLES_CHAMPION_THRESHOLD := 33

# --- Cross-map questlines (the raider hunt, a Campfire-revealed treasure cache) ---
# Active questlines keyed by id. Each value tracks whether the payoff node's one-shot arm-
# reveal flourish has played and whether the payoff has been claimed. A dict, not a single id,
# so independent questlines can be live at once: the placed raider hunt you accepted at a plea
# AND a treasure cache a random Campfire exposed, both armed in the same act. The id keys the
# reveal text + payoff routing in map_scene. See MapNode.quest_giver_id / quest_payoff_id.
var active_quests: Dictionary = {}  # StringName -> {"revealed": bool, "completed": bool}

const MAX_ACTS := 3
const DEFAULT_STARTING_REALM: StringName = &"camelot"
const TITLE_SLOT_COUNT := 2
## The consumable cap. Deliberately the same shape as the title slots: with a fixed cap and no
## inventory tech, an item's value never depends on what else is carried, and hoarding is handled
## by the cap rather than by tuning.
const CONSUMABLE_SLOTS := 2
# Weighted-recent blend factor for King's Reputation updates.
const KINGS_REP_WEIGHT_OLD := 0.4
const KINGS_REP_WEIGHT_NEW := 0.6


## True if the player currently holds Excalibur (granted by Sword in the Stone).
func has_excalibur() -> bool:
	return has_relic("Excalibur")


## Toggles Excalibur between Sword and Sight mode. Only valid between combats.
## Emits Events.excalibur_mode_changed so the map UI can re-render the toggle.
func toggle_excalibur_mode() -> void:
	excalibur_mode = (ExcaliburMode.SIGHT
		if excalibur_mode == ExcaliburMode.SWORD
		else ExcaliburMode.SWORD)
	Events.excalibur_mode_changed.emit(excalibur_mode)


## True if the player currently holds The Thurible (granted by the Reliquary event).
func has_thurible() -> bool:
	return has_relic("The Thurible")


## Toggles The Thurible between swinging Passion toward Blazing and toward Hollow. Only
## meaningful between combats. Emits Events.thurible_mode_changed so the map UI re-renders.
func toggle_thurible_mode() -> void:
	thurible_mode = (ThuribleMode.HOLLOW
		if thurible_mode == ThuribleMode.BLAZING
		else ThuribleMode.BLAZING)
	Events.thurible_mode_changed.emit(thurible_mode)


func _ready() -> void:
	# Listen for combat completion to apply title-based post-combat effects
	# (gold and healing bonuses from equipped titles).
	Events.combat_won.connect(_on_combat_won)
	# Per-act charges come back when the act does. Act 1 is seeded by start_run and by
	# award_title, since act_started only fires on an act transition.
	Events.act_started.connect(_on_act_started_refresh_charges)


func add_gold(amount: int) -> void:
	gold += amount
	if run_active and amount > 0:
		run_stats["gold_earned"] = run_stats.get("gold_earned", 0) + amount


func start_run(character: CharacterData, seed_value: int = -1, starting_realm: StringName = DEFAULT_STARTING_REALM) -> void:
	current_character = character
	current_hp = character.max_health
	max_hp = character.max_health
	current_act = 1
	gold = 50  # base starting purse so the first shop isn't empty-handed
	relics.clear()
	equipment.clear()
	perks.clear()
	consumables.clear()
	pet_id = &""
	run_active = true
	current_map = null
	realm_config = RealmConfig.new()  # neutral until the realm-entry VN sets it
	pending_enemies.clear()
	pending_gold_reward = 0
	pending_relic_reward = false
	pending_relic_is_boss = false
	pending_special_event = &""
	pending_event_combat = false
	ordinary_event_count = 0
	# Scheduled story beats pinned to an ordinary-event ordinal (empty = fully random).
	# Camelot's demo beat: Cass's "The Room That Isn't" is guaranteed as the 2nd event so
	# her introduction always lands, with the rest of the run's events staying random.
	scripted_event_schedule = {}
	if starting_realm == &"camelot":
		scripted_event_schedule[2] = &"room_that_isnt"
	active_quests = {}
	pending_vn = null
	pending_vn_queue.clear()
	pending_vn_next = "res://scenes/map/map_scene.tscn"
	pending_map_boon = &""
	pending_combat_boon = &""
	pending_skip_node = false
	pending_act_complete = false
	excalibur_mode = ExcaliburMode.SWORD
	thurible_mode = ThuribleMode.BLAZING
	philosophy_id = &""
	philosophy_strength_tier = 0
	together_subchoice = &""
	kings_reputation = 0.0
	last_btk_score = 0.0
	last_btk_tier = 0
	has_abdicated = false
	realm_standing.clear()
	run_start_time = Time.get_ticks_msec()
	run_stats = {
		"cards_played": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"enemies_killed": 0,
		"gold_earned": 0,
		"floors_cleared": 0,
	}

	# Initialize realm tracking
	visited_realm_ids.clear()
	set_current_realm(starting_realm)

	# Initialize title state
	earned_title_ids.clear()
	active_title_slots.clear()
	for i in TITLE_SLOT_COUNT:
		active_title_slots.append(&"")
	_title_has_left_origin.clear()
	_title_has_returned.clear()
	_title_reclaimed.clear()
	_title_applied_max_hp_bonus = 0
	_title_active_charges.clear()

	# Build starting deck (deep copy so upgrades don't modify templates)
	current_deck.clear()
	for card in character.starting_deck:
		current_deck.append(card.duplicate_card())

	# Initialize passion
	passion = PassionState.new()
	passion.current_value = passion.starting_value

	# Setup deterministic RNG
	if seed_value < 0:
		seed_value = RngManager.generate_seed()
	RngManager.setup_run(seed_value)

	# Fresh encounter memory so this run's elite bag doesn't inherit the last run's state.
	EnemyPool.reset_encounter_state()

	Events.run_started.emit(character)


## Advances the ordinary-event ordinal and returns the scripted event id pinned to this
## visit, or &"" to draw from the random pool. Called by event_scene when an ordinary (non-
## signature) event node is entered, so a story beat can be guaranteed on the player's Nth
## event while the rest stay random. General: any ordinal in scripted_event_schedule works.
func next_ordinary_event_script() -> StringName:
	ordinary_event_count += 1
	return scripted_event_schedule.get(ordinary_event_count, &"")


func advance_act() -> void:
	Events.act_ended.emit(current_act)
	current_act += 1
	current_map = null
	pending_act_complete = false
	Events.act_started.emit(current_act)


func end_run(victory: bool) -> void:
	run_active = false
	Events.run_ended.emit(victory)


func add_card_to_deck(card: CardData) -> void:
	current_deck.append(card.duplicate_card())


func remove_card_from_deck(index: int) -> void:
	if index >= 0 and index < current_deck.size():
		current_deck.remove_at(index)


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	if relic.trigger == RelicData.RelicTrigger.ON_PICKUP:
		_apply_pickup_relic(relic)
	Events.relic_acquired.emit(relic)


func has_relic(relic_name: String) -> bool:
	for r in relics:
		if r.relic_name == relic_name:
			return true
	return false


## Returns the owned relic instance with this name, or null. Lets combat read a relic's
## tunable `value` (e.g. Blooded Edge's first-attack bonus) without rescanning the pool.
func get_relic(relic_name: String) -> RelicData:
	for r in relics:
		if r.relic_name == relic_name:
			return r
	return null


func get_owned_relic_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for r in relics:
		names.append(r.relic_name)
	return names


func _apply_pickup_relic(relic: RelicData) -> void:
	match relic.effect:
		RelicData.RelicEffect.GAIN_MAX_HP:
			max_hp += relic.value
			current_hp += relic.value
		RelicData.RelicEffect.HEAL:
			heal(relic.value)
		RelicData.RelicEffect.GAIN_GOLD:
			add_gold(relic.value)


func equip(item: EquipmentData) -> void:
	var old = equipment.get(item.slot)
	equipment[item.slot] = item
	Events.equipment_changed.emit(item.slot, old, item)


func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	Events.player_damaged.emit(amount, current_hp)
	if current_hp <= 0:
		end_run(false)


func get_run_elapsed_seconds() -> int:
	return (Time.get_ticks_msec() - run_start_time) / 1000


func get_run_time_string() -> String:
	var total = get_run_elapsed_seconds()
	var minutes = total / 60
	var seconds = total % 60
	return "%d:%02d" % [minutes, seconds]


func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)


func change_passion(amount: int) -> void:
	if passion and current_character:
		var adjusted = int(amount * current_character.passion_volatility)
		_set_passion(passion.current_value + adjusted)


## Clamps to the meter's bounds, writes the value, and emits changed / tier-changed.
## Shared by change_passion and pull_passion_toward so both go through one path.
func _set_passion(new_value: int) -> void:
	if not passion:
		return
	var old_value = passion.current_value
	passion.current_value = clampi(new_value, passion.min_value, passion.max_value)
	Events.passion_changed.emit(old_value, passion.current_value)
	var old_tier = get_passion_tier_for_value(old_value)
	var new_tier = get_passion_tier_for_value(passion.current_value)
	if old_tier != new_tier:
		Events.passion_tier_changed.emit(old_tier, new_tier)


## The dispassionate center of the signed axis: 0 (midpoint of the Steady band via
## the character's symmetric thresholds). Where the two personalities balance and
## neither zone bonus applies.
func passion_center() -> int:
	if current_character and current_character.passion_thresholds.size() >= 3:
		return int((current_character.passion_thresholds[1]
			+ current_character.passion_thresholds[2]) / 2.0)
	if passion:
		return int((passion.min_value + passion.max_value) / 2.0)
	return 0


## Absolute distance of current Passion from the dispassionate center — how far committed
## to EITHER pole. The memory card "Everything I Carried Out" scales its damage with this:
## the harder I feel, the heavier the blow lands.
func passion_distance_from_center() -> int:
	if not passion:
		return 0
	return absi(passion.current_value - passion_center())


## Pulls Passion toward `target` by up to `magnitude` (volatility-scaled), never
## crossing past the target. An additive utility (kept for directional effects).
func pull_passion_toward(target: int, magnitude: int) -> void:
	if not (passion and current_character):
		return
	var cur := passion.current_value
	if cur == target:
		return
	var dir := signi(target - cur)
	var adjusted := int(magnitude * current_character.passion_volatility)
	var new_val := cur + dir * adjusted
	if dir > 0:
		new_val = mini(new_val, target)
	else:
		new_val = maxi(new_val, target)
	_set_passion(new_val)


## Multiplicatively pulls Passion toward 0 by `strength` (0..1 fraction, volatility-
## scaled): keeps (1 - strength) of the current value. Self-scaling on the signed
## axis — hard when you're committed to a pole, gentle near center, and it can never
## overshoot 0. The False Prophet's "strip your conviction" tool.
func pull_passion_to_center(strength: float) -> void:
	if not (passion and current_character):
		return
	var eff := clampf(strength * current_character.passion_volatility, 0.0, 1.0)
	_set_passion(int(round(passion.current_value * (1.0 - eff))))


func get_passion_tier() -> int:
	if not passion or not current_character:
		return PassionState.Tier.STEADY
	return get_passion_tier_for_value(passion.current_value)


func get_passion_tier_for_value(value: int) -> int:
	if not current_character:
		return PassionState.Tier.STEADY
	var thresholds = current_character.passion_thresholds
	# thresholds = [blazing_min, inspired_min, steady_min, wavering_min]
	# Values below wavering_min are Hollow
	if value >= thresholds[0]:
		return PassionState.Tier.BLAZING
	elif value >= thresholds[1]:
		return PassionState.Tier.INSPIRED
	elif value >= thresholds[2]:
		return PassionState.Tier.STEADY
	elif value >= thresholds[3]:
		return PassionState.Tier.WAVERING
	else:
		return PassionState.Tier.HOLLOW


# --- Realm tracking ---

## Returns the RealmData for the current realm, or null if not set / unknown.
func get_current_realm() -> RealmData:
	return RealmRegistry.get_realm(current_realm_id)


## Sets the current realm and appends it to visited_realm_ids if new.
## Drives title tier changes (degraded when leaving origin, returning when re-entering).
## Emits Events.realm_changed for UI listeners.
func set_current_realm(realm_id: StringName) -> void:
	var previous_id := current_realm_id
	current_realm_id = realm_id
	if not visited_realm_ids.has(realm_id):
		visited_realm_ids.append(realm_id)
	if previous_id != realm_id:
		_update_title_tiers_on_realm_change(previous_id, realm_id)
		_expire_consumables_at_border(realm_id)
		Events.realm_changed.emit(previous_id, realm_id)


## True if the player has visited this realm in the current run.
func has_visited_realm(realm_id: StringName) -> bool:
	return visited_realm_ids.has(realm_id)


# --- Realm configuration (A2) ---

## Install a realm-shape config (from the realm-entry VN choice: Camelot court vs common
## folk). Sets the run's realm_config, queues its map_boon for the next map open, applies
## its one-shot passion_shift, and emits realm_configured so UI/codex can react. This is
## the single apply path — vn_scene calls it when a choice carries a config, and the
## mid-run Court Intrigue / Peasant's Plea events retune through it too.
func apply_realm_config(config: RealmConfig) -> void:
	if config == null:
		return
	realm_config = config
	pending_map_boon = config.map_boon
	if config.passion_shift != 0:
		change_passion(config.passion_shift)
	# The pledge plants your court<->folk standing (Folk +, Court -). Non-zero only on the
	# pledge configs, so neutral configs + mid-run retunes leave standing untouched.
	if config.standing_init != 0:
		set_realm_standing(current_realm_id, config.standing_init)
	Events.realm_configured.emit(get_current_realm())


## Resolve the queued realm map_boon exactly once (called from map_scene._ready). Boons
## are keyed by id; the catalogue is small for the demo. Clears the pending slot first so
## a map reload (every node return re-runs _ready) never re-grants it.
func consume_map_boon() -> void:
	var boon := pending_map_boon
	pending_map_boon = &""
	match boon:
		&"":
			return
		&"militia":
			# Common folk: the town musters a shield-wall militia at your side.
			var r := RelicPool.get_relic_by_name("The People's Line")
			if r:
				add_relic(r)
		_:
			push_warning("consume_map_boon: unknown boon id '%s'" % boon)


## Grant a Fable liaison's run-start gift (the send-off boon — separate from realm_config).
## Bram (Records) leans info, Neve (Dispatch) leans supplies; each is a bespoke quest-pool
## relic so it never appears in shops or reward rolls. See docs/REALM_CAMELOT.md § Run-start.
func apply_liaison_gift(liaison: StringName) -> void:
	var relic_name := ""
	match liaison:
		&"bram":
			relic_name = "Bram's Briefing"
		&"neve":
			relic_name = "Neve's Kit"
		_:
			push_warning("apply_liaison_gift: unknown liaison '%s'" % liaison)
			return
	var r := RelicPool.get_relic_by_name(relic_name)
	if r:
		add_relic(r)


# --- Companion ---

## Takes a companion on (an event grants it). An unknown id is refused with a warning and leaves
## the current companion alone; a second grant replaces the first.
func set_pet(id: StringName) -> void:
	if PetPool.get_pet(id) == null:
		push_warning("set_pet: unknown pet id '%s'" % id)
		return
	pet_id = id


## The companion's data, or null if none travels with the player.
func get_pet() -> PetData:
	return PetPool.get_pet(pet_id)


# --- Consumables ---

## True if a slot is free. Events and shops ask this before handing something over, and open
## the swap prompt (leave one behind) when it is false.
func has_consumable_room() -> bool:
	return consumables.size() < CONSUMABLE_SLOTS


## Puts an item in the pack. Returns false and changes nothing if both slots are full.
func add_consumable(item: ConsumableData) -> bool:
	if item == null or not has_consumable_room():
		return false
	consumables.append(item)
	Events.consumables_changed.emit()
	return true


## Throws an item away to free its slot. Returns false if it was not held. A quest item that
## has nothing left to do is dropped this way, and so is any dud once the cap bites.
func discard_consumable(item: ConsumableData) -> bool:
	var index := consumables.find(item)
	if index < 0:
		return false
	consumables.remove_at(index)
	Events.consumables_changed.emit()
	return true


func has_consumable(id: StringName) -> bool:
	return get_consumable_by_id(id) != null


## The held item with this id, or null. Events gate options on it (the raider lair's chalice).
func get_consumable_by_id(id: StringName) -> ConsumableData:
	for c in consumables:
		if c.id == id:
			return c
	return null


## Spends a held item by id from an event choice (a quest item is spent where it is delivered,
## not by the use button). Returns false if it was not held.
func spend_consumable_by_id(id: StringName) -> bool:
	var item := get_consumable_by_id(id)
	return item != null and discard_consumable(item)


## True if the item is usable from the map screen right now. A heal at full health is refused so
## it is never wasted by a stray click.
func can_use_consumable_on_map(item: ConsumableData) -> bool:
	if item == null or not consumables.has(item) or not item.usable_on_map:
		return false
	match item.effect:
		ConsumableData.Effect.HEAL, ConsumableData.Effect.HEAL_DRIFT_HOLLOW:
			return current_hp < max_hp
	return true


## Uses a map-usable item and spends it. Combat-only items are refused here: the combat engine
## owns their effects (CombatEngine.use_consumable).
func use_consumable_on_map(item: ConsumableData) -> bool:
	if not can_use_consumable_on_map(item):
		return false
	match item.effect:
		ConsumableData.Effect.HEAL:
			heal(item.value)
		ConsumableData.Effect.HEAL_DRIFT_HOLLOW:
			heal(item.value)
			change_passion(-item.value2)
		ConsumableData.Effect.STANDING_SHIFT:
			change_realm_standing(current_realm_id, item.value)
		_:
			return false
	discard_consumable(item)
	return true


## True if a quest item has nothing left to do: its questline is done, or its payoff node is
## behind the player or gone from the map. The pack says so, and the player is meant to drop it.
func is_consumable_spent(item: ConsumableData) -> bool:
	if item == null or item.quest_id == &"":
		return false
	if is_quest_completed(item.quest_id) or not is_quest_active(item.quest_id):
		return true
	if current_map == null:
		return false
	return not MapGenerator.quest_payoff_ahead(current_map, item.quest_id)


## Internal: a realm-exclusive item leaves the pack when the player crosses into a different
## realm, unless it has an answer for what it means out there (expires_at_border false). The
## default leans to expiry, case by case: an indulgence from Camelot's church means nothing under
## the world-tree.
func _expire_consumables_at_border(new_realm: StringName) -> void:
	var kept: Array[ConsumableData] = []
	for c in consumables:
		var leaves: bool = c.expires_at_border and c.realm_id != &"" and c.realm_id != new_realm
		if not leaves:
			kept.append(c)
	if kept.size() != consumables.size():
		consumables = kept
		Events.consumables_changed.emit()


# --- Titles ---

## Award a title to the player. Adds it to earned_title_ids but does NOT auto-equip.
## Returns true if it was newly awarded, false if already owned.
func award_title(title_id: StringName) -> bool:
	if earned_title_ids.has(title_id):
		return false
	var data := TitlePool.get_title(title_id)
	if not data:
		push_warning("award_title: unknown title id '%s'" % title_id)
		return false
	earned_title_ids.append(title_id)
	# A title earned mid-act arrives with its charges, so the event that grants it can
	# spend one immediately (the Vigil's dawn skip does exactly that).
	if data.has_active_effect():
		_title_active_charges[title_id] = data.active_charges
	# Realm titles earned in their origin realm start at Original tier (default state).
	# Personality titles always use Original tier.
	if data.category == TitleData.Category.REALM:
		_title_has_left_origin[title_id] = false
		_title_has_returned[title_id] = false
		_title_reclaimed[title_id] = false
	Events.title_earned.emit(title_id)
	return true


## Equip a title in the given slot (0 or 1). Pass &"" to unequip.
## Returns true on success, false if the title isn't owned or slot is invalid.
func equip_title(slot: int, title_id: StringName) -> bool:
	if slot < 0 or slot >= TITLE_SLOT_COUNT:
		return false
	if title_id != &"" and not earned_title_ids.has(title_id):
		return false
	# If equipping an owned title that's already in the other slot, swap them.
	if title_id != &"":
		var other := 1 - slot
		if active_title_slots[other] == title_id:
			active_title_slots[other] = active_title_slots[slot]
	var previous := active_title_slots[slot]
	active_title_slots[slot] = title_id
	_recompute_title_max_hp_bonus()
	Events.title_equipped.emit(slot, previous, title_id)
	return true


## Returns the TitleData for an equipped slot, or null if empty.
func get_equipped_title(slot: int) -> TitleData:
	if slot < 0 or slot >= TITLE_SLOT_COUNT:
		return null
	var id := active_title_slots[slot]
	if id == &"":
		return null
	return TitlePool.get_title(id)


## Returns the effective current tier for a title given the player's current realm
## and reclamation/return history. Personality titles always return ORIGINAL.
func get_title_tier(title_id: StringName) -> TitleData.Tier:
	var data := TitlePool.get_title(title_id)
	if not data or data.category == TitleData.Category.PERSONALITY:
		return TitleData.Tier.ORIGINAL
	if current_realm_id == data.origin_realm_id:
		# We're in the origin realm. If we've returned and reclaimed, back to Original.
		# If we've returned but not reclaimed, Returning. Otherwise (still on original visit), Original.
		var has_returned: bool = _title_has_returned.get(title_id, false)
		var reclaimed: bool = _title_reclaimed.get(title_id, false)
		if has_returned and not reclaimed:
			return TitleData.Tier.RETURNING
		return TitleData.Tier.ORIGINAL
	# We're in a foreign realm.
	var has_left: bool = _title_has_left_origin.get(title_id, false)
	if has_left:
		return TitleData.Tier.DEGRADED
	# Edge case: we earned the title but were never actually in its origin realm.
	# Treat as Degraded to keep the system consistent.
	return TitleData.Tier.DEGRADED


## Marks a realm title as reclaimed (its origin realm restored to Original tier).
## Called by reclamation event success paths.
func mark_title_reclaimed(title_id: StringName) -> void:
	if not earned_title_ids.has(title_id):
		return
	_title_reclaimed[title_id] = true
	_recompute_title_max_hp_bonus()
	Events.title_tier_changed.emit(title_id, get_title_tier(title_id))


## Sums the value of all equipped titles' passive effects for the given effect type.
## Returns 0 if no equipped title grants this effect. Used by gameplay systems
## (shop pricing, combat block, etc.) to apply title bonuses.
func get_title_passive_total(effect: TitleData.EffectType) -> int:
	var total := 0
	for slot in range(TITLE_SLOT_COUNT):
		var data := get_equipped_title(slot)
		if not data or data.passive_effect != effect:
			continue
		var tier := get_title_tier(data.title_id)
		total += data.get_value_for_tier(tier)
	return total


## Charges an active title has left in the current period. 0 for a title that has no
## active block, is unknown, or has spent everything it had.
func get_title_active_charges(title_id: StringName) -> int:
	return _title_active_charges.get(title_id, 0)


## True if the player can spend a charge of this title right now. A title has to be
## WORN to be spent, not merely earned: the two slots are the whole point of the system.
func can_spend_title_charge(title_id: StringName) -> bool:
	if not active_title_slots.has(title_id):
		return false
	var data := TitlePool.get_title(title_id)
	if not data or not data.has_active_effect():
		return false
	return get_title_active_charges(title_id) > 0


## Spend one charge of an equipped active title and apply its effect.
## Returns false and changes nothing if the title cannot be spent right now.
func spend_title_charge(title_id: StringName) -> bool:
	if not can_spend_title_charge(title_id):
		return false
	var data := TitlePool.get_title(title_id)
	var remaining: int = get_title_active_charges(title_id) - 1
	_title_active_charges[title_id] = remaining
	_apply_title_active(data)
	Events.title_active_spent.emit(title_id, remaining)
	return true


## Internal: route an active title's effect to the state it actually sets. Kept small on
## purpose. A new active effect belongs here and in TitleData.EffectType, nowhere else.
func _apply_title_active(data: TitleData) -> void:
	match data.active_effect:
		TitleData.EffectType.SKIP_NODE:
			pending_skip_node = true
		_:
			push_warning("spend_title_charge: unhandled active effect on '%s'" % data.title_id)


## Internal: refresh the charges of every earned title whose period just came round.
## Earned rather than equipped on purpose: a title left in the pack still refills, so
## swapping one in does not hand the player a charge that the act already spent.
func _refresh_title_charges(period: TitleData.ActivePeriod) -> void:
	for title_id in earned_title_ids:
		var data := TitlePool.get_title(title_id)
		if not data or not data.has_active_effect():
			continue
		if data.active_period != period:
			continue
		_title_active_charges[title_id] = data.active_charges


func _on_act_started_refresh_charges(_act_number: int) -> void:
	_refresh_title_charges(TitleData.ActivePeriod.ACT)


## True if an equipped per-hit damage title is at its full tier, which is the only tier whose
## bonus escalates. The schema can give a tier a smaller number but not a different shape, so
## this one title's curve is gated in code; a degraded sword keeps a flat bonus at its own
## value. See TITLE_DESIGN 5.12 and the rider-block note in 6.3.
func title_damage_bonus_escalates() -> bool:
	for slot in range(TITLE_SLOT_COUNT):
		var data := get_equipped_title(slot)
		if not data or data.passive_effect != TitleData.EffectType.DAMAGE_BONUS_FLAT:
			continue
		if get_title_tier(data.title_id) == TitleData.Tier.ORIGINAL:
			return true
	return false


## Extra card options the equipped titles add to a card reward (The Gracious). Reward sites
## widen their pick by this. The shop deliberately does not read it: buying a card is a
## purchase, not a reward, and widening the stock would be a discount in disguise.
func get_card_reward_bonus() -> int:
	return get_title_passive_total(TitleData.EffectType.CARD_REWARD_CHOICES)


## Internal: update title tier tracking when the player changes realms.
func _update_title_tiers_on_realm_change(previous_realm: StringName, new_realm: StringName) -> void:
	var tier_changed := false
	for title_id in earned_title_ids:
		var data := TitlePool.get_title(title_id)
		if not data or data.category != TitleData.Category.REALM:
			continue
		var origin := data.origin_realm_id
		# Leaving the origin: title is now in foreign territory.
		if previous_realm == origin and new_realm != origin:
			_title_has_left_origin[title_id] = true
			_title_reclaimed[title_id] = false  # Leaving resets any prior reclamation
			tier_changed = true
			Events.title_tier_changed.emit(title_id, TitleData.Tier.DEGRADED)
		# Returning to origin after having left.
		elif new_realm == origin and previous_realm != origin:
			if _title_has_left_origin.get(title_id, false):
				_title_has_returned[title_id] = true
				# Reclamation must be explicitly granted via mark_title_reclaimed().
				# Default state on return is Returning tier.
				_title_reclaimed[title_id] = false
				tier_changed = true
				Events.title_tier_changed.emit(title_id, TitleData.Tier.RETURNING)
	if tier_changed:
		_recompute_title_max_hp_bonus()


## Recompute the player's max HP bonus from currently-equipped titles.
## Applies the delta against the previously-applied bonus to avoid double-counting
## across tier changes and swaps. Current HP is clamped down if max drops below it,
## but is NOT auto-healed when max increases (STS-style behavior).
func _recompute_title_max_hp_bonus() -> void:
	var desired := get_title_passive_total(TitleData.EffectType.MAX_HP_BONUS)
	var delta := desired - _title_applied_max_hp_bonus
	if delta == 0:
		return
	max_hp = maxi(1, max_hp + delta)
	if current_hp > max_hp:
		current_hp = max_hp
	_title_applied_max_hp_bonus = desired


# --- Crown & Reign (Phase 2) ---

## True if the player has taken the crown this run (any philosophy chosen).
func is_crowned() -> bool:
	return philosophy_id != &""


## Locks in the philosophy choice + Act 1 BTK tier as the modifier magnitude.
## together_sub is required when philosophy == &"together"; ignored otherwise.
## Subsequent calls (Phase 2 doesn't expose any, but defensive) leave the
## strength tier alone — Act 1 is immutable.
func set_philosophy(id: StringName, strength_tier: int,
		together_sub: StringName = &"") -> void:
	philosophy_id = id
	philosophy_strength_tier = clampi(strength_tier, 0, 3)
	together_subchoice = together_sub if id == &"together" else &""
	Events.philosophy_chosen.emit(id, philosophy_strength_tier)


## Fold a fresh BTK score into kings_reputation using the weighted-recent blend.
## Called for boss fights AFTER the Act 1 crown — the Act 1 roll itself sets
## philosophy_strength_tier and is NOT mixed into reputation (it's the locked
## moment in time). Emits kings_reputation_updated on every call.
func update_kings_reputation(latest_score: float) -> void:
	var blended := KINGS_REP_WEIGHT_OLD * kings_reputation \
			+ KINGS_REP_WEIGHT_NEW * latest_score
	kings_reputation = clampf(blended, 0.0, 1.0)
	Events.kings_reputation_updated.emit(kings_reputation)


## Returns the court<->folk standing for a realm (+ = people, - = court). 0 if never set.
func get_realm_standing(realm_id: StringName) -> int:
	return realm_standing.get(realm_id, 0)


## Directly set a realm's standing (the pledge plants the initial value). Emits
## realm_standing_changed with the old/new values so UI and events can react.
func set_realm_standing(realm_id: StringName, value: int) -> void:
	var old_value := get_realm_standing(realm_id)
	if value == old_value:
		return
	realm_standing[realm_id] = value
	Events.realm_standing_changed.emit(realm_id, old_value, value)
	_check_peoples_champion(realm_id)


## Nudge a realm's court<->folk standing by a signed delta: positive toward the people,
## negative toward the court. Faction-aligned event choices call this. Emits
## realm_standing_changed with the old/new values so UI and events can react.
func change_realm_standing(realm_id: StringName, delta: int) -> void:
	if delta == 0:
		return
	var old_value := get_realm_standing(realm_id)
	var new_value := old_value + delta
	realm_standing[realm_id] = new_value
	Events.realm_standing_changed.emit(realm_id, old_value, new_value)
	_check_peoples_champion(realm_id)


## Internal: hand over The People's Champion the first time standing crosses its bar. Called
## from both standing writers, so there is no path that moves standing without checking.
## award_title dedupes, so this is safe to call on every change, and the terminal awards at the
## crown and demo-end scenes stay where they are as harmless no-ops.
func _check_peoples_champion(realm_id: StringName) -> void:
	if not is_peoples_champion(realm_id):
		return
	award_title(&"peoples_champion")


## True if the player holds the given realm's people's favor (standing at/above the
## threshold). Defaults to the current realm. Drives folk-gated event options.
func has_folk_favor(realm_id: StringName = &"") -> bool:
	var rid: StringName = realm_id if realm_id != &"" else current_realm_id
	return get_realm_standing(rid) >= FAVOR_THRESHOLD


## True if the player holds the given realm's court favor (standing at/below the negative
## threshold). Defaults to the current realm. Drives court-gated event options.
func has_court_favor(realm_id: StringName = &"") -> bool:
	var rid: StringName = realm_id if realm_id != &"" else current_realm_id
	return get_realm_standing(rid) <= -FAVOR_THRESHOLD


## True if the player held the people's line deep enough to be their champion (standing
## at/above PEOPLES_CHAMPION_THRESHOLD). Read at the run's crown/ending beats. Defaults to
## the current realm.
func is_peoples_champion(realm_id: StringName = &"") -> bool:
	var rid: StringName = realm_id if realm_id != &"" else current_realm_id
	return get_realm_standing(rid) >= PEOPLES_CHAMPION_THRESHOLD


# --- Cross-map questline state ---

## Arms a questline (idempotent). The payoff node reveals on the next return to the map.
## Keyed by id so more than one hunt can be live; re-arming an active id is a no-op.
func arm_quest(quest_id: StringName) -> void:
	if quest_id == &"" or active_quests.has(quest_id):
		return
	active_quests[quest_id] = {"revealed": false, "completed": false}


## True if the questline is armed (regardless of whether its payoff is claimed yet).
func is_quest_active(quest_id: StringName) -> bool:
	return quest_id != &"" and active_quests.has(quest_id)


## True once the questline's payoff has been claimed. Stops the payoff node re-triggering.
func is_quest_completed(quest_id: StringName) -> bool:
	return active_quests.has(quest_id) and active_quests[quest_id].completed


## Marks the payoff claimed (called from the victory beat).
func complete_quest(quest_id: StringName) -> void:
	if active_quests.has(quest_id):
		active_quests[quest_id].completed = true


## Marks the one-shot arm-reveal flourish as played so it never replays.
func mark_quest_revealed(quest_id: StringName) -> void:
	if active_quests.has(quest_id):
		active_quests[quest_id].revealed = true


## The first armed questline whose reveal hasn't played yet (&"" = none pending). At most one
## is pending per map return: arming only happens inside an event, and the player always passes
## back through the map between events, so each armed quest reveals on its own return.
func first_unrevealed_quest() -> StringName:
	for quest_id in active_quests:
		if not active_quests[quest_id].revealed:
			return quest_id
	return &""


## Coarse-grained hostility readout for content gating. Map / encounter
## generation read this rather than the raw number so we have one place to
## tune the thresholds. 0 = neutral, 1 = uneasy, 2 = hostile.
func get_realm_hostility_level(realm_id: StringName = &"") -> int:
	var rid: StringName = realm_id if realm_id != &"" else current_realm_id
	var s := get_realm_standing(rid)
	if s <= -30:
		return 2
	if s <= -10:
		return 1
	return 0


## Handler for combat victories. Applies post-combat title effects (gold, healing).
func _on_combat_won() -> void:
	if not run_active:
		return
	var gold_bonus := get_title_passive_total(TitleData.EffectType.GOLD_ON_COMBAT_END)
	var heal_bonus := get_title_passive_total(TitleData.EffectType.HEAL_ON_COMBAT_END)
	if gold_bonus > 0:
		add_gold(gold_bonus)
	if heal_bonus > 0:
		heal(heal_bonus)
