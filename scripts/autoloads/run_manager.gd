extends Node
## Manages the lifecycle of a single run.
## Owns all persistent run state: deck, relics, equipment, gold, passion, act progression.

var current_character: CharacterData
var current_deck: Array[CardData] = []
var relics: Array[RelicData] = []
var equipment: Dictionary = {} # EquipmentData.EquipmentSlot -> EquipmentData (deprecated, see Titles)
var perks: Array[PerkData] = []
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
## True while the Sword-in-the-Stone guardian fight is in progress, so combat victory
## routes to the "beast unmade" follow-up beat (which grants Excalibur) rather than a
## normal reward. Cleared when consumed.
var pending_guardian_fight: bool = false
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

# --- Excalibur dual-mode ---
# Sword (0) adds the Excalibur power card to the player's draw pile at start of
# each combat. Sight (1) is passive — reveals enemy intents one turn ahead.
# Defaults to Sword. The toggle is only meaningful when the player holds the
# Excalibur relic; if they don't, this value is ignored.
enum ExcaliburMode { SWORD, SIGHT }
var excalibur_mode: int = ExcaliburMode.SWORD

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
# Per-realm reputation that swings on commitments and betrayals. Default 0;
# negative on betrayal (abdication after building trust, breaking event
# commitments). Gates content via get_realm_hostility_level().
var realm_standing: Dictionary[StringName, int] = {}

const MAX_ACTS := 3
const DEFAULT_STARTING_REALM: StringName = &"camelot"
const TITLE_SLOT_COUNT := 2
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


func _ready() -> void:
	# Listen for combat completion to apply title-based post-combat effects
	# (gold and healing bonuses from equipped titles).
	Events.combat_won.connect(_on_combat_won)


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
	run_active = true
	current_map = null
	realm_config = RealmConfig.new()  # neutral until the realm-entry VN sets it
	pending_enemies.clear()
	pending_gold_reward = 0
	pending_relic_reward = false
	pending_relic_is_boss = false
	pending_special_event = &""
	pending_guardian_fight = false
	pending_vn = null
	pending_vn_queue.clear()
	pending_vn_next = "res://scenes/map/map_scene.tscn"
	pending_map_boon = &""
	pending_act_complete = false
	excalibur_mode = ExcaliburMode.SWORD
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
			var r := RelicPool.get_relic_by_name("Peasant Militia")
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


## Returns the standing for a realm. Defaults to 0 (neutral) if never set.
func get_realm_standing(realm_id: StringName) -> int:
	return realm_standing.get(realm_id, 0)


## Mutate per-realm standing. Negative deltas represent betrayals; positive
## deltas represent loyalty-earning acts. Emits realm_standing_changed with
## the old/new values so UI and events can react.
func change_realm_standing(realm_id: StringName, delta: int) -> void:
	if delta == 0:
		return
	var old_value := get_realm_standing(realm_id)
	var new_value := old_value + delta
	realm_standing[realm_id] = new_value
	Events.realm_standing_changed.emit(realm_id, old_value, new_value)


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
