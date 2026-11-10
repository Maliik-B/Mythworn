class_name CombatEngine
extends Node
## Drives combat: state machine, turn flow, card resolution, enemy actions.
## Effects route through this engine so it can emit signals and handle side effects.

enum Phase {
	PLAYER_TURN_START,
	PLAYER_TURN,
	ANIMATING,
	PLAYER_TURN_END,
	ENEMY_TURN,
	BATTLE_WON,
	BATTLE_LOST,
}

const HAND_SIZE := 5
const MAX_ENERGY := 3

## Chilled (Cairn's signature Water DoT) tuning. CHILL_CHIP is the FLAT end-of-turn damage
## (not per-stack — the stacks are a freeze gauge, not a damage scale). Once stacks reach
## CHILL_FREEZE_THRESHOLD the chill converts to Frozen and is spent. Starting values; tune
## against tools/combat_harness alongside the per-card Chilled numbers in card_pool.
const CHILL_CHIP := 2
const CHILL_FREEZE_THRESHOLD := 10

var phase: Phase = Phase.PLAYER_TURN_START
var energy: int = MAX_ENERGY
var turn_number: int = 0
var player_stats: CombatantStats
var enemies: Array[EnemyCombatState] = []
var piles: PileManager
var _current_card: CardData = null # Set during card resolution for zone penalty
## A staged moment on the scene (a boss going down and getting up into his next phase) holds the
## fight: no card is played, nothing in the pack is used, the turn does not end, and the enemy turn
## waits before anyone acts. Counted, so two holds need two releases. The harness never holds.
var _holds := 0
## Energy spent by the X-cost card currently resolving (X). Read by x_scaled effects
## so a torrent repeats once per energy; 0 outside an X-cost resolution.
var _current_x: int = 0
## Blooded Edge (raider questline relic): bonus damage still owed to the player's FIRST
## attack this combat. Primed at start_combat from the relic's value, spent on the first
## card-dealt damage instance, then 0 for the rest of the fight. 0 when the relic isn't held.
var _blooded_edge_pending: int = 0

## The Compassionate title: a one-per-combat clutch mend. _clutch_heal holds the HP to restore
## (0 unless the title is equipped), _clutch_used flags that this combat's save has fired. The
## first player damage that drops them below half HP triggers it, resolved BEFORE the lethal
## check — and since HP floors at 0, it also pulls the player back from an otherwise-killing blow.
var _clutch_heal: int = 0
var _clutch_used: bool = false

## The Merciful title: HP restored each time an enemy dies (0 unless the title is equipped).
## Cached at combat start like the clutch heal, rather than polled on every death, because
## get_title_passive_total rebuilds the whole title registry on each call.
var _mercy_heal: int = 0

## Momentum relic: a within-turn damage ramp. _momentum_per_hit is the per-hit bonus from the
## relic's value (0 unless held); _momentum is the bonus accrued so far THIS turn, added to each
## player attack and reset at the start of every player turn. Read directly, like Blooded Edge.
var _momentum: int = 0
var _momentum_per_hit: int = 0

## The Sword's Bearer: the per-hit damage bonus from equipped titles. _sword_base is the tier
## value (0 unless a damage title is worn), cached at combat start rather than polled on every
## hit because get_title_passive_total rebuilds the whole title registry on each call. At
## Original tier the base doubles with the turn count, capped at SWORD_MAX_DOUBLINGS, which is
## what keeps a long fight from squaring the per-hit multiplier. Degraded tiers stay flat.
var _sword_base: int = 0
var _sword_escalates := false

## Three doublings, so the curve keeps its whole character through turn 8 and the unbounded
## tail goes away. The lever, if +8 a hit proves too hot against the harness, is this cap and
## not the schedule: the feel lives in the curve and the risk lives in the top step.
const SWORD_MAX_DOUBLINGS := 3

## The Thurible relic (Reliquary): the per-turn Passion swing magnitude, primed from the
## relic's value (0 unless held). At the start of each player turn combat pushes Passion by
## this amount, signed by the pole the player chose on the map (RunManager.thurible_mode).
## Read directly, like Blooded Edge / Momentum, since a fixed GAIN_PASSION value can't flip sign.
var _thurible_swing: int = 0

## Blade Oil (consumable): bonus damage owed to the first hit of the next attack card the player
## plays. Set by use_consumable, spent on the first card-dealt hit after it, then 0. Gated on
## _current_card like Blooded Edge, so a poison tick or a lash never spends it.
var _blade_oil_pending: int = 0

## A Champion's Favour (consumable): true while the favour is armed. The next blow that would
## land on the player after it is used does not, and the flag clears. Reset every combat.
var _favour_ward: bool = false

## The Green Girdle (a woken forgotten relic): once a combat, a blow that would fell the player
## leaves them at _girdle_hp instead. Armed at combat start from the relic's value2 (0 unless
## held), spent by the blow it turns. Resolved after the clutch heal in _on_damage_dealt, so the
## title's save goes first and the girdle catches what it did not.
var _girdle_ward: bool = false
var _girdle_hp: int = 0

## Excalibur's Scabbard (a woken forgotten relic): every enemy hit on the player deals this much
## less, read from the relic's value2 (0 unless held). Only an enemy's blow is softened; a
## self-inflicted cost is not a wound the sheath can keep in.
var _scabbard_guard: int = 0

## The Unfading (title): true until the first card of the combat is played. That card goes back
## to the hand instead of the discard pile, unless it was spent (it exhausts, it is a Power, or
## it is a companion's Trick card). Armed at combat start from the equipped titles.
var _unfading_pending: bool = false

## Named flags a card raises on the combat for another card to read and spend (CombatFlagEffect,
## DamageEffect.bonus_flag): the hawk is waiting on until its Stoop comes down. Cleared with the
## fight.
var combat_flags: Dictionary = {}

## The companion's deck for this fight (PetPool.build_cards): shuffled on the deck rng when it is
## first needed, one card handed over at every player turn, rebuilt and reshuffled when it runs
## out. Empty when no companion travels with the player.
var _pet_deck: Array[CardData] = []

## When true, the enemy-turn coroutine skips its pacing timers and resolves
## synchronously. The balance harness (tools/combat_harness) sets this so it can
## run thousands of trials against the REAL engine without waiting real seconds.
## Gameplay leaves it false so the paced "Enemy Turn" beats read normally.
var instant: bool = false

# --- Be the King scoring snapshot (Camelot crown-stakes boss fights) ---
# Only populated when start_combat is invoked for a Camelot boss with
# Excalibur held or the player already crowned. Consumed in check_battle_end
# on victory, then cleared. _btk_active gates the whole pathway so non-boss
# combats pay zero cost.
var _btk_active: bool = false
var _btk_start_hp: int = 0
var _btk_starting_passion_tier: int = 0
var _btk_passion_tier_changed: bool = false


func start_combat(deck: Array[CardData], player_hp: int, player_max_hp: int,
		enemy_datas: Array[EnemyData]) -> void:
	player_stats = CombatantStats.new(player_hp, player_max_hp)

	# Excalibur (Sword mode) injects its signature card into the draw pile for
	# this combat only — the persistent deck stays clean. Toggling to Sight
	# between combats removes the card from future combats automatically.
	var effective_deck: Array[CardData] = deck.duplicate()
	if RunManager.has_excalibur() and RunManager.excalibur_mode == RunManager.ExcaliburMode.SWORD:
		effective_deck.append(CardPool.build_excalibur_card())

	piles = PileManager.new()
	piles.setup(effective_deck)

	enemies.clear()
	for data in enemy_datas:
		var enemy = EnemyCombatState.new(data)
		# Statuses the enemy starts armed with (e.g. an Enraged-retaliation elite).
		for pair in data.starting_statuses:
			enemy.stats.apply_status(pair[0], pair[1])
		enemy.select_intent()
		enemies.append(enemy)

	turn_number = 0
	# Blooded Edge: prime the first-attack bonus from the relic's tunable value (0 if unheld).
	var blooded := RunManager.get_relic("Blooded Edge")
	_blooded_edge_pending = blooded.value if blooded else 0
	# The Compassionate: arm the once-per-combat clutch heal from the equipped title (0 if unworn).
	_clutch_heal = RunManager.get_title_passive_total(TitleData.EffectType.CLUTCH_HEAL)
	_clutch_used = false
	# The Merciful: arm the per-death mend from the equipped title (0 if unworn).
	_mercy_heal = RunManager.get_title_passive_total(TitleData.EffectType.HEAL_ON_ENEMY_DEATH)
	# The Sword's Bearer: arm the per-hit bonus and whether this tier escalates (0 if unworn).
	_sword_base = RunManager.get_title_passive_total(TitleData.EffectType.DAMAGE_BONUS_FLAT)
	_sword_escalates = RunManager.title_damage_bonus_escalates()
	# The Unfading: arm the first-card echo from the equipped title (false if unworn).
	_unfading_pending = RunManager.get_title_passive_total(
		TitleData.EffectType.FIRST_CARD_RETURNS) > 0
	# Momentum: prime the per-hit ramp from the relic (0 if unheld); the accrued bonus starts empty.
	var mom := RunManager.get_relic("Momentum")
	_momentum_per_hit = mom.value if mom else 0
	_momentum = 0
	# The Thurible: prime the per-turn swing magnitude (0 if unheld). Its sign is chosen
	# per-fight via RunManager.thurible_mode and applied at each player turn-start.
	var thur := RunManager.get_relic("The Thurible")
	_thurible_swing = thur.value if thur else 0
	# The woken forgotten relics the engine reads by name (0 or unarmed unless held).
	var girdle := RunManager.get_relic("The Green Girdle")
	_girdle_hp = girdle.value2 if girdle else 0
	_girdle_ward = _girdle_hp > 0
	var scabbard := RunManager.get_relic("Excalibur's Scabbard")
	_scabbard_guard = scabbard.value2 if scabbard else 0
	# Consumable effects are per fight: nothing armed carries in from a previous combat.
	_blade_oil_pending = 0
	_favour_ward = false
	# Flags and the companion's deck are per fight too.
	combat_flags.clear()
	_pet_deck.clear()
	_arm_be_the_king(player_hp)
	# Whiplash power listens on tier crossings for the fight; no-op unless the player
	# actually holds Whiplash (checked in the handler). Disconnected at combat end.
	if not Events.passion_tier_changed.is_connected(_on_passion_tier_changed_whiplash):
		Events.passion_tier_changed.connect(_on_passion_tier_changed_whiplash)
	# The Merciful listens on enemy deaths for the fight. Same teardown discipline as the
	# tier listener above, and for the same reason: this is a global signal and a freed
	# engine still connected to it is a hard crash.
	if _mercy_heal > 0 and not Events.enemy_died.is_connected(_on_enemy_died_mercy):
		Events.enemy_died.connect(_on_enemy_died_mercy)
	Events.combat_started.emit()
	_process_relics(RelicData.RelicTrigger.ON_COMBAT_START)
	_apply_pending_combat_boon()
	start_player_turn()


## Decide whether this combat is a Be the King fight and snapshot the inputs.
## Gating rule: pending_act_complete is set by map_scene only on boss nodes,
## and the realm must be Camelot with the player either holding Excalibur
## (Act 1 path to crown) or already crowned (Act 2+ reputation update).
## We listen on passion_tier_changed for the duration of the fight so the
## stability bonus reflects this fight only, not the run-level history.
func _arm_be_the_king(start_hp: int) -> void:
	_btk_active = false
	_btk_passion_tier_changed = false
	if not RunManager.pending_act_complete:
		return
	if RunManager.current_realm_id != &"camelot":
		return
	if not (RunManager.has_excalibur() or RunManager.is_crowned()):
		return
	_btk_active = true
	_btk_start_hp = start_hp
	_btk_starting_passion_tier = RunManager.get_passion_tier()
	if not Events.passion_tier_changed.is_connected(_on_passion_tier_changed_btk):
		Events.passion_tier_changed.connect(_on_passion_tier_changed_btk)


## Per-fight passion tier tracker. The signal fires for any tier change in
## either direction; either way we flag the fight as non-stable for BTK
## scoring purposes. Disconnect happens in _resolve_be_the_king when the
## fight ends.
func _on_passion_tier_changed_btk(_old_tier: int, _new_tier: int) -> void:
	_btk_passion_tier_changed = true


## Whiplash power: a passion tier crossing (either direction) draws cards. No-op
## unless the player holds Whiplash; skipped once the fight is decided.
func _on_passion_tier_changed_whiplash(_old_tier: int, _new_tier: int) -> void:
	if phase == Phase.BATTLE_WON or phase == Phase.BATTLE_LOST:
		return
	if not player_stats.has_power(Powers.WHIPLASH):
		return
	var n := Powers.WHIPLASH_DRAW * player_stats.get_power_stacks(Powers.WHIPLASH)
	for card in piles.draw_cards(n):
		Events.card_drawn.emit(card)


## The Sword's Bearer's bonus for the current turn. Flat at a degraded tier; at full tier it
## doubles on a doubling timer, so the interval between steps doubles along with the value:
## turn 1 pays the base, turn 2 twice it, turn 4 four times, turn 8 eight times, and there it
## stops. Formally base * 2^min(floor(log2(turn)), SWORD_MAX_DOUBLINGS). Resets with the fight,
## because turn_number does.
func sword_bonus() -> int:
	if _sword_base <= 0:
		return 0
	if not _sword_escalates:
		return _sword_base
	var doublings := 0
	while doublings < SWORD_MAX_DOUBLINGS and turn_number >= (2 << doublings):
		doublings += 1
	return _sword_base * (1 << doublings)


## Tell the combat UI where the two escalating per-hit bonuses stand. Called when either can
## have moved: the start of a player turn (the sword steps, Momentum resets) and each hit the
## player lands (Momentum climbs).
func _emit_damage_ramp() -> void:
	Events.damage_ramp_changed.emit(sword_bonus(), _momentum)


func _disconnect_whiplash() -> void:
	if Events.passion_tier_changed.is_connected(_on_passion_tier_changed_whiplash):
		Events.passion_tier_changed.disconnect(_on_passion_tier_changed_whiplash)


func _disconnect_mercy() -> void:
	if Events.enemy_died.is_connected(_on_enemy_died_mercy):
		Events.enemy_died.disconnect(_on_enemy_died_mercy)


## The Merciful: a body goes down and the title mends you for it, while the fight is still
## happening. Dead players are not healed, and a mend that would do nothing is skipped by
## heal_combatant itself.
func _on_enemy_died_mercy(_enemy) -> void:
	if _mercy_heal <= 0 or player_stats == null or player_stats.is_dead():
		return
	heal_combatant(player_stats, _mercy_heal)


## Deterministic teardown. The engine listens on the global Events.passion_tier_changed autoload
## for the fight's duration; the per-feature disconnects only fire on a CLEAN battle end. If the
## engine is freed another way -- the balance harness disposing a trial, or the player leaving a
## combat mid-fight -- those connections would otherwise dangle on a destroyed Node, and the next
## tier change emitted into a freed receiver is a hard crash (intermittent SIGILL). Disconnecting
## in _exit_tree (which free()/scene-change always triggers) guarantees no stale connection
## survives this object, no matter how the combat ended. Idempotent via the is_connected guards.
func _exit_tree() -> void:
	_disconnect_whiplash()
	_disconnect_mercy()
	if Events.passion_tier_changed.is_connected(_on_passion_tier_changed_btk):
		Events.passion_tier_changed.disconnect(_on_passion_tier_changed_btk)


## Compute and emit the Be the King result on a crown-stakes win. Stores the
## raw score + tier on RunManager so the crown / abdication scene can read
## them for the narrative reveal, and folds the score into kings_reputation
## if the player is already crowned (Act 2+ rolls only — the Act 1 roll sets
## philosophy_strength_tier separately when the crown is actually taken).
func _resolve_be_the_king() -> void:
	if not _btk_active:
		return
	if Events.passion_tier_changed.is_connected(_on_passion_tier_changed_btk):
		Events.passion_tier_changed.disconnect(_on_passion_tier_changed_btk)
	var result := BeTheKing.score_fight(
		_btk_start_hp,
		player_stats.current_hp,
		player_stats.max_hp,
		turn_number,
		_btk_passion_tier_changed,
	)
	RunManager.last_btk_score = result["score"]
	RunManager.last_btk_tier = result["tier"]
	Events.be_the_king_scored.emit(result["score"], result["tier"])
	# Already-crowned players feed the rolling reputation dial. Pre-crown
	# (Act 1) players have nothing to update yet — the score waits for the
	# crown decision scene to read it.
	if RunManager.is_crowned():
		RunManager.update_kings_reputation(result["score"])
	_btk_active = false


# -- Turn Flow --

func start_player_turn() -> void:
	turn_number += 1
	phase = Phase.PLAYER_TURN_START

	energy = MAX_ENERGY
	_momentum = 0  # Momentum relic: the within-turn damage ramp resets each player turn.
	_emit_damage_ramp()  # the sword may have stepped on this turn boundary, and Momentum reset
	# Block falls at the start of every turn but the first. Block a relic gives at combat start
	# (Steadfast Binding, Packed Tight, The People's Line, Barrow-Warden's Mail, A Plain Shield)
	# is given before this turn begins and has to stand through the first enemy turn, or the relic
	# never did anything; the reset used to run on turn one as well, and those relics were dead.
	if turn_number > 1:
		player_stats.reset_block()
	tick_start_of_turn(player_stats)

	if player_stats.is_dead():
		phase = Phase.BATTLE_LOST
		Events.combat_lost.emit()
		return

	_process_relics(RelicData.RelicTrigger.ON_TURN_START)
	_apply_thurible_turn_start()
	_apply_title_turn_start_effects()
	_process_powers()

	var drawn = piles.draw_cards(HAND_SIZE)
	for card in drawn:
		Events.card_drawn.emit(card)
	_pet_arrival()

	phase = Phase.PLAYER_TURN
	Events.player_turn_started.emit()


## The companion: on every player turn one card from the pet's deck arrives in hand, drawn like
## the player's own, without replacement and reshuffled when the deck is spent, so each card shows
## once a cycle and the player can count on it. It is an ordinary card in every way that matters:
## it costs energy, it competes with the hand, and it can be left unplayed. It enters no pile. The
## shuffle is on the deck rng, so a seeded run replays identically, and a run with no companion
## touches the rng not at all, leaving every seed that never met one exactly as it was.
func _pet_arrival() -> void:
	var pet := RunManager.get_pet()
	if pet == null:
		return
	if _pet_deck.is_empty():
		_pet_deck = PetPool.build_cards(pet.id)
		if _pet_deck.is_empty():
			return
		RngManager.shuffle(_pet_deck, RngManager.deck_rng)
	var card: CardData = _pet_deck.pop_back()
	piles.hand.append(card)
	Events.card_drawn.emit(card)
	Events.combat_note.emit("%s brings you %s." % [pet.display_name, card.card_name])


# -- Combat flags (a card raises one, another reads and spends it) --

func raise_flag(flag: StringName) -> void:
	if flag != &"":
		combat_flags[flag] = true


func has_flag(flag: StringName) -> bool:
	return combat_flags.get(flag, false)


func spend_flag(flag: StringName) -> void:
	combat_flags.erase(flag)


## The Thurible relic: swings the player's Passion toward the pole chosen on the map screen
## at the start of each player turn — +_thurible_swing toward Blazing, or -_thurible_swing
## toward Hollow. Read directly (NONE effect) because a fixed GAIN_PASSION value can't flip
## sign per-fight; the sign comes from RunManager.thurible_mode, toggled between combats.
func _apply_thurible_turn_start() -> void:
	if _thurible_swing <= 0:
		return
	var dir := 1 if RunManager.thurible_mode == RunManager.ThuribleMode.BLAZING else -1
	RunManager.change_passion(dir * _thurible_swing)


## One-shot next-combat boons queued by an event (RunManager.pending_combat_boon). Applied once
## at the start of the combat following the event, then cleared, so the boon lasts exactly one
## fight. Small id->effect catalogue, like RunManager.consume_map_boon. Keep the ids in sync with
## event_scene._combat_boon_label (the player-facing summary text).
func _apply_pending_combat_boon() -> void:
	var boon := RunManager.pending_combat_boon
	if boon == &"":
		return
	RunManager.pending_combat_boon = &""
	match boon:
		&"wandering_vigor":
			# The Shade at the Cross lends his courage for one fight: open with +2 Strength.
			apply_status_effect(player_stats, StatusEffects.STRENGTH, 2)
		_:
			push_warning("Unknown pending_combat_boon: %s" % boon)


## True if this held consumable can be used right now: it is the player's turn, the item is in the
## pack and meant for combat, and using it would do something (a heal at full health, a favour
## already armed and an oil already waiting are refused so a stray click never wastes one).
func can_use_consumable(item: ConsumableData) -> bool:
	if phase != Phase.PLAYER_TURN or is_held() or item == null or not item.usable_in_combat:
		return false
	if not RunManager.consumables.has(item):
		return false
	match item.effect:
		ConsumableData.Effect.HEAL, ConsumableData.Effect.HEAL_DRIFT_HOLLOW:
			return player_stats.current_hp < player_stats.max_hp
		ConsumableData.Effect.NEXT_ATTACK_BONUS:
			return _blade_oil_pending == 0
		ConsumableData.Effect.WARD_NEXT_BLOW:
			return not _favour_ward
		ConsumableData.Effect.PASSION_TOWARD_POLE:
			return RunManager.passion != null
	return true


## Uses a held consumable and spends it. Costs no energy: the player picks the moment, which is
## the whole identity of the layer. Heals go through heal_combatant so they show live (the
## end-of-combat HP sync would otherwise overwrite a RunManager heal made mid-fight).
func use_consumable(item: ConsumableData) -> bool:
	if not can_use_consumable(item):
		return false
	match item.effect:
		ConsumableData.Effect.HEAL:
			heal_combatant(player_stats, item.value)
		ConsumableData.Effect.HEAL_DRIFT_HOLLOW:
			heal_combatant(player_stats, item.value)
			RunManager.change_passion(-item.value2)
		ConsumableData.Effect.NEXT_ATTACK_BONUS:
			_blade_oil_pending = item.value
		ConsumableData.Effect.PASSION_TOWARD_POLE:
			# The pole you already lean to: at or above the dispassionate center that is
			# Blazing (+), below it Hollow (-). Dead center leans Blazing.
			var dir := 1 if RunManager.passion.current_value >= RunManager.passion_center() else -1
			RunManager.change_passion(dir * item.value)
		ConsumableData.Effect.STRENGTH_THIS_FIGHT:
			apply_status_effect(player_stats, StatusEffects.STRENGTH, item.value)
		ConsumableData.Effect.WARD_NEXT_BLOW:
			_favour_ward = true
		_:
			return false
	RunManager.discard_consumable(item)
	return true


## Applies equipped title effects that fire at the start of each player turn.
## Currently: BLOCK_ON_TURN_START. Block from titles uses the same apply_block
## pathway as other sources, so Dexterity scales it and block_gained is emitted.
func _apply_title_turn_start_effects() -> void:
	var block_bonus := RunManager.get_title_passive_total(TitleData.EffectType.BLOCK_ON_TURN_START)
	if block_bonus > 0:
		apply_block(player_stats, block_bonus)


## Character POWERS fire here each turn (StS-style), dispatched by power id.
## Detachment: cool Passion toward center and steel into stacking Strength — trading
## your zone spike for raw, growing force (the center-as-a-build identity).
func _process_powers() -> void:
	var tier := RunManager.get_passion_tier()
	var at_extreme := tier == PassionState.Tier.BLAZING or tier == PassionState.Tier.HOLLOW
	for power in player_stats.powers:
		var stacks: int = player_stats.powers[power]
		if stacks <= 0:
			continue
		if power == Powers.DETACHMENT:
			RunManager.pull_passion_toward(0, Powers.DETACHMENT_DRIFT)
			apply_status_effect(player_stats, StatusEffects.STRENGTH,
				Powers.DETACHMENT_STRENGTH * stacks)
		elif power == Powers.CONVICTION:
			# Reward committing to a pole with tempo.
			if at_extreme:
				energy += Powers.CONVICTION_ENERGY * stacks
		elif power == Powers.GROUNDED:
			# The defensive (Hollow) pole's payoff.
			if tier == PassionState.Tier.HOLLOW:
				apply_block(player_stats, Powers.GROUNDED_BLOCK * stacks)


func end_player_turn() -> void:
	if is_held():
		return
	phase = Phase.PLAYER_TURN_END
	tick_end_of_turn(player_stats)

	# A companion's card the player did not play vanishes: out of the game, not into the discard
	# pile (it was never part of the deck). A bankable trick (retain) stays like any retained card.
	for card in piles.hand.duplicate():
		if card.trick and not card.retain:
			piles.hand.erase(card)

	for card in piles.hand:
		if not card.retain:
			Events.card_discarded.emit(card)
	piles.discard_hand()

	Events.turn_ended.emit()

	if phase == Phase.BATTLE_WON or phase == Phase.BATTLE_LOST:
		return
	start_enemy_turn()


## Paced coroutine: the enemy turn plays out over time with a beat per enemy
## (announce -> model lunge -> effect lands -> settle) so the turn is readable and
## the "Enemy Turn"/"Your Turn" banners are separated by real time. Called without
## await from end_player_turn; it yields at the first timer and continues on its own.
func start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN

	# Reset enemy block at start of their turn (block gained persists through player's turn)
	for enemy in enemies:
		if not enemy.stats.is_dead():
			enemy.stats.reset_block()

	Events.enemy_turn_started.emit()
	# Let the "Enemy Turn" banner register before anyone acts.
	await _pace(0.25)

	for enemy in enemies:
		if enemy.stats.is_dead():
			continue
		# Per-enemy: tick start -> announce + wind-up -> act -> settle -> tick end
		tick_start_of_turn(enemy.stats)
		await _until_released()  # a tick can break a boss's bar, and he gets up before anyone acts
		if enemy.stats.is_dead():
			Events.enemy_died.emit(enemy)
			continue
		# Frozen enemies forfeit their action this turn. Poison still ticked above;
		# other end-of-turn statuses still count down below. One stack = one turn.
		if enemy.stats.has_status(StatusEffects.STUN):
			_reduce_status(enemy.stats, StatusEffects.STUN)
			Events.enemy_stunned.emit(enemy)
			await _pace(0.3)
			resolve_chilled(enemy.stats)              # the chill still bites through a skipped turn
			tick_end_of_turn(enemy.stats)
			continue
		Events.enemy_action_started.emit(enemy, enemy.current_intent)
		await _pace(0.22)                             # anticipation / wind-up
		execute_enemy_turn(enemy)                     # effect lands (damage flash/shake here)
		resolve_chilled(enemy.stats)                  # Chilled ticks/freezes at the enemy's turn-end
		tick_end_of_turn(enemy.stats)
		await _pace(0.45)                             # let the hit be felt before the next enemy
		if player_stats.is_dead():
			break

	if player_stats.is_dead():
		phase = Phase.BATTLE_LOST
		Events.combat_lost.emit()
		return

	check_battle_end()
	if phase == Phase.BATTLE_WON:
		return

	# Select new intents for next turn
	for enemy in enemies:
		if not enemy.stats.is_dead():
			enemy.select_intent()

	await _pace(0.05)
	start_player_turn()


## Enemy-turn pacing beat. Awaits a real timer during normal play; returns
## immediately when `instant` is set (the balance harness), so the exact same
## turn logic runs either paced-for-readability or as fast as the CPU allows.
## Every beat also waits out a hold, so nothing resolves under a staged moment.
func _pace(seconds: float) -> void:
	if not instant:
		await get_tree().create_timer(seconds).timeout
	await _until_released()


func hold() -> void:
	_holds += 1


func release() -> void:
	_holds = maxi(0, _holds - 1)


func is_held() -> bool:
	return _holds > 0


## Returns once nothing holds the fight. At once when nothing does, as in the harness.
func _until_released() -> void:
	while _holds > 0 and is_inside_tree():
		await get_tree().process_frame


func execute_enemy_turn(enemy: EnemyCombatState) -> void:
	if not enemy.current_intent:
		return
	for effect in enemy.current_intent.effects:
		effect.apply(enemy.stats, player_stats, self)


# -- Card Play --

func can_play_card(card: CardData) -> bool:
	if phase != Phase.PLAYER_TURN or is_held():
		return false
	if card.unplayable:
		return false
	if card.energy_cost > energy:
		return false
	if card not in piles.hand:
		return false
	return true


## Routes an externally-injected card into a player pile. Called by AddCardEffect:
## the Corruption curse shuffles into the draw pile; Anger-style self-replication
## (Inner Fire) drops the copy into the discard pile.
func add_card_to_pile(card: CardData, to_discard: bool = false) -> void:
	if to_discard:
		piles.add_card_to_discard(card)
	else:
		piles.add_card_to_draw(card)


func play_card(card: CardData, target: CombatantStats) -> bool:
	if not can_play_card(card):
		return false

	# X-cost cards spend ALL remaining energy; _current_x is the amount spent (X),
	# read by x_scaled effects. Normal cards just pay their fixed cost.
	if card.x_cost:
		_current_x = energy
		energy = 0
	else:
		energy -= card.energy_cost
	piles.hand.erase(card)

	# The Unfading's echo belongs to the first card played this combat, whatever it is, so it is
	# used up here even when this card turns out to be spent and does not come back.
	var echoes := _unfading_pending
	_unfading_pending = false

	# Track current card for zone penalty in deal_damage
	_current_card = card

	# Resolve effects — route to correct targets based on card targeting
	for effect in card.get_active_effects():
		match card.target_type:
			CardData.TargetType.SELF, CardData.TargetType.NONE:
				effect.apply(player_stats, player_stats, self)
			CardData.TargetType.ALL_ENEMIES:
				for enemy in enemies:
					if not enemy.stats.is_dead():
						effect.apply(player_stats, enemy.stats, self)
			CardData.TargetType.SINGLE_ENEMY:
				effect.apply(player_stats, target, self)

	_current_card = null
	_current_x = 0
	Events.card_played.emit(card, target)

	if card.card_type == CardData.CardType.POWER:
		# Powers vanish into their persistent effect — they don't return to any pile
		# this combat (StS behavior). The GainPowerEffect has already applied them.
		pass
	elif card.trick:
		# A companion's card leaves play when it resolves. It is not exhausted (that would put
		# it where a recall can bring it back) and not discarded (it was never in the deck).
		pass
	elif card.exhaust:
		piles.exhaust_pile.append(card)
		Events.card_exhausted.emit(card)
	elif echoes:
		# Back to the hand, and only the card: the energy it cost stays spent.
		piles.hand.append(card)
		Events.card_drawn.emit(card)
		Events.combat_note.emit("%s comes back to your hand." % card.card_name)
	else:
		piles.discard_pile.append(card)
		Events.card_discarded.emit(card)

	check_battle_end()
	return true


# -- Methods called by CardEffect subclasses --

## X for the X-cost card currently resolving (energy it spent). x_scaled effects
## read this to repeat once per energy. 0 when no X-cost card is mid-resolution.
func current_x() -> int:
	return _current_x


func deal_damage(target: CombatantStats, base_amount: int,
		source: CombatantStats = null, pierce: int = 0) -> void:
	var amount = base_amount

	# Source modifiers
	if source:
		amount += source.get_status_stacks(StatusEffects.STRENGTH)
		if source.has_status(StatusEffects.WEAK):
			amount = int(amount * 0.75)

	# Title damage bonus: damage added to all player attacks (not enemies). Applied before the
	# zone penalty so the penalty scales the boosted total uniformly.
	# INTENDED, not a bug: this is per HIT, not per card -- it sits on the same line as
	# Strength, so a multi-hit card adds it once per hit. Multi-hit decks are meant to be able
	# to point themselves at it; that per-hit scaling is the title's whole synergy hook, and it
	# is why the bonus opens at +1 rather than at +3.
	# Momentum (relic) rides the same block: the bonus accrued earlier this turn is added here,
	# so it scales under zones like the title bonus. _momentum is 0 on the turn's first hit.
	if source == player_stats:
		amount += sword_bonus()
		amount += _momentum

	# Blooded Edge: the first attack damage the player lands this combat hits harder. Gated
	# on _current_card so only a played card's hit spends it (not a poison tick or lash), and
	# applied alongside the title bonus so all flat player bonuses scale uniformly under zones.
	if source == player_stats and _current_card != null and _blooded_edge_pending > 0:
		amount += _blooded_edge_pending
		_blooded_edge_pending = 0

	# Blade Oil: the same shape, spent by the first card-dealt hit after the player poured it.
	if source == player_stats and _current_card != null and _blade_oil_pending > 0:
		amount += _blade_oil_pending
		_blade_oil_pending = 0

	# Zone modifier: at a committed extreme, the dominant personality's cards hit
	# harder (+25%) and the off-type suffers (-25%). Only for player cards, never
	# enemies or neutrals. The dispassionate middle is flat — no bonus, no penalty.
	if _current_card and source == player_stats:
		amount = _apply_zone_modifier(amount, _current_card.personality)

	# Target modifiers
	if target.has_status(StatusEffects.VULNERABLE):
		amount = int(amount * 1.5)

	amount = maxi(0, amount)

	# Excalibur's Scabbard: an enemy's blow on the player lands for a little less. After every
	# modifier, so it is the last point off the hit, and never on a cost the player paid themselves.
	if _scabbard_guard > 0 and target == player_stats and source != null \
			and source != player_stats and amount > 0:
		amount = maxi(0, amount - _scabbard_guard)

	# Intangible clamps any single damage source to 1. Emo Hybrid's "Slip the Tide"
	# uses this for a deliberately defensive turn skip.
	if amount > 0 and target.has_status(StatusEffects.INTANGIBLE):
		amount = 1

	# A Champion's Favour: the next blow that would land on the player does not. Only an enemy's
	# attack can be turned (self-inflicted costs never come through here), and the favour is
	# spent by the blow it turns, even if block would have soaked it.
	if _favour_ward and target == player_stats and source != player_stats and amount > 0:
		_favour_ward = false
		amount = 0
		Events.combat_note.emit("The favour turns the blow.")

	# Piercing: a portion of the hit bypasses block and lands straight on HP; the
	# remainder soaks block as usual. Clamped to the (post-modifier) amount so a
	# pierce larger than the hit never deals bonus damage. Intangible has already
	# clamped `amount` to 1 above, so a pierced hit still honours Intangible.
	var actual: int
	if pierce > 0:
		var direct := mini(pierce, amount)
		actual = target.take_damage(amount - direct) + target.take_direct_damage(direct)
	else:
		actual = target.take_damage(amount)
	_on_damage_dealt(target, actual)

	# Momentum: each hit the player lands on an enemy builds the ramp for the REST of this turn.
	# Added after the hit resolves, so the first hit is +0 and each subsequent hit climbs — a
	# multi-hit card ramps mid-combo. Gated to the player striking an enemy; reset each turn.
	if _momentum_per_hit > 0 and source == player_stats and target != player_stats:
		_momentum += _momentum_per_hit
		_emit_damage_ramp()

	# Enraged: a struck combatant strikes its attacker back for its Enraged stacks.
	# Ignores block (a raw lash) and fires per hit, so multi-hit bursts cost more — the
	# anti-burst pressure for Caedmon's compelled phase. Guarded so it can't chain (the
	# attacker isn't the one Enraged) or fire on a fully-blocked chip.
	if actual > 0 and source != null and source != target \
			and target.has_status(StatusEffects.ENRAGED):
		var lash := target.get_status_stacks(StatusEffects.ENRAGED)
		source.take_direct_damage(lash)
		_on_damage_dealt(source, lash)


func apply_block(target: CombatantStats, amount: int) -> void:
	var actual = amount + target.get_status_stacks(StatusEffects.DEXTERITY)
	target.gain_block(actual)
	Events.block_gained.emit(target, actual)


## Takes every point of a combatant's Block away (the hawk's Bind). Sent down the block signal as
## a negative gain, so the bar and the log read it as the guard going.
func strip_block(target: CombatantStats) -> void:
	if target.block <= 0:
		return
	var lost := target.block
	target.reset_block()
	Events.block_gained.emit(target, -lost)


## A flat HP loss a combatant inflicts on itself (a DamageEffect with apply_to_source: the
## Beast at the Stone's Breaking Blow). Skips every modifier and block, so the cost is the
## number on the move, and goes through _on_damage_dealt so the bar updates and a bar that
## empties this way breaks or kills exactly as one the player emptied would.
func self_damage(stats: CombatantStats, amount: int) -> void:
	if amount <= 0 or stats.is_dead():
		return
	stats.take_direct_damage(amount)
	_on_damage_dealt(stats, amount)


## Mends a combatant up to its max HP, clamped to the missing HP, and emits the matching
## heal signal so the UI refreshes the bar. Used by the Hollow Prelate's self-heal AND by
## player heal cards (the memory card "The House That Was") -- routing a player heal through
## the live player_stats here, rather than RunManager.heal, is what makes it show in combat
## (RunManager.current_hp is only synced from player_stats on victory, so a RunManager heal
## mid-fight would be invisible and then overwritten).
func heal_combatant(target: CombatantStats, amount: int) -> void:
	if amount <= 0 or target.is_dead():
		return
	var healed := mini(amount, target.max_hp - target.current_hp)
	if healed <= 0:
		return
	target.current_hp += healed
	if target == player_stats:
		Events.player_healed.emit(healed, target.current_hp)
		return
	for enemy in enemies:
		if enemy.stats == target:
			Events.enemy_healed.emit(enemy, healed, target.current_hp)
			return


func draw_cards(count: int) -> void:
	var drawn = piles.draw_cards(count)
	for card in drawn:
		Events.card_drawn.emit(card)


## Returns up to `count` random cards from the exhaust pile back to the hand.
## Used by Emo Hybrid's recall-themed cards. Picks are deterministic via
## RngManager.deck_rng so seeded runs replay identically.
func recall_from_exhaust(count: int) -> void:
	if piles.exhaust_pile.is_empty() or count <= 0:
		return
	var available = piles.exhaust_pile.size()
	var n = mini(count, available)
	for i in n:
		var idx = RngManager.deck_rng.randi_range(0, piles.exhaust_pile.size() - 1)
		var card: CardData = piles.exhaust_pile[idx]
		piles.exhaust_pile.remove_at(idx)
		piles.hand.append(card)
		Events.card_drawn.emit(card)


## Returns up to `count` random cards from the discard pile back to the hand (the ferret's Dig).
## The same shape as recall_from_exhaust, on the same rng.
func recall_from_discard(count: int) -> void:
	if piles.discard_pile.is_empty() or count <= 0:
		return
	var n: int = mini(count, piles.discard_pile.size())
	for i in n:
		var idx: int = RngManager.deck_rng.randi_range(0, piles.discard_pile.size() - 1)
		var card: CardData = piles.discard_pile[idx]
		piles.discard_pile.remove_at(idx)
		piles.hand.append(card)
		Events.card_drawn.emit(card)


func change_energy(amount: int) -> void:
	energy = maxi(0, energy + amount)


func apply_status_effect(target: CombatantStats, effect: StatusEffectData,
		stacks: int) -> void:
	target.apply_status(effect, stacks)
	Events.status_applied.emit(target, effect, stacks)
	_try_control_heal(target, effect)


## The Emo Hybrid's innate attrition answer (CharacterData.control_heal): landing a
## crowd-control status (Weak or Frozen) on an ENEMY mends the player. Gated to enemy
## targets so an enemy Weakening the player never heals them, and to Water's control
## statuses so a Physical build (Vulnerable/Strength) never triggers it — the sustain
## auto-follows the glass build that needs it. Fires per application, so Deep Freeze
## (Frozen + Weak) mends twice.
func _try_control_heal(target: CombatantStats, effect: StatusEffectData) -> void:
	if target == player_stats:
		return
	if effect != StatusEffects.WEAK and effect != StatusEffects.STUN:
		return
	var amount := 0
	if RunManager.current_character:
		amount = RunManager.current_character.control_heal
	if amount <= 0 or player_stats.is_dead():
		return
	var healed := mini(amount, player_stats.max_hp - player_stats.current_hp)
	if healed <= 0:
		return
	player_stats.current_hp += healed
	Events.player_healed.emit(healed, player_stats.current_hp)


# -- Status Effect Ticking --

func tick_start_of_turn(stats: CombatantStats) -> void:
	if stats.has_status(StatusEffects.POISON):
		var stacks = stats.get_status_stacks(StatusEffects.POISON)
		var dmg = stacks
		# Intangible reduces poison ticks to 1, matching STS semantics
		# ("all damage and HP loss reduced to 1").
		if stats.has_status(StatusEffects.INTANGIBLE) and dmg > 0:
			dmg = 1
		stats.take_direct_damage(dmg)
		_on_damage_dealt(stats, dmg)
		_reduce_status(stats, StatusEffects.POISON)


func tick_end_of_turn(stats: CombatantStats) -> void:
	_reduce_status(stats, StatusEffects.VULNERABLE)
	_reduce_status(stats, StatusEffects.WEAK)
	_reduce_status(stats, StatusEffects.INTANGIBLE)
	_reduce_status(stats, StatusEffects.DEXTERITY)  # Poise: a temporary composure that fades


## Chilled (Cairn's signature Water DoT) resolves at the END of the afflicted's turn:
## a small FLAT chip, then EITHER a freeze (when the chill has built to the threshold —
## spending all of it, so it reads as a freeze gauge rather than a damage scale) OR a
## one-stack melt. Call this just before tick_end_of_turn for whoever's turn is ending so
## the chip honours Intangible (still present pre-decay), matching the Poison tick. Applying
## Frozen at turn-end lets the start-of-turn STUN check skip the afflicted's NEXT turn. The
## freeze routes through apply_status_effect so Water's control-heal fires, like Deep Freeze.
func resolve_chilled(stats: CombatantStats) -> void:
	if not stats.has_status(StatusEffects.CHILLED):
		return
	var dmg := CHILL_CHIP
	# Intangible reduces the chip to 1, matching the Poison tick's STS semantics.
	if stats.has_status(StatusEffects.INTANGIBLE) and dmg > 0:
		dmg = 1
	stats.take_direct_damage(dmg)
	_on_damage_dealt(stats, dmg)
	if stats.is_dead():
		return
	if stats.get_status_stacks(StatusEffects.CHILLED) >= CHILL_FREEZE_THRESHOLD:
		apply_status_effect(stats, StatusEffects.STUN, 1)
		stats.remove_status(StatusEffects.CHILLED)
		Events.status_removed.emit(stats, StatusEffects.CHILLED)
	else:
		_reduce_status(stats, StatusEffects.CHILLED)


func _reduce_status(stats: CombatantStats, effect: StatusEffectData) -> void:
	if not stats.has_status(effect):
		return
	stats.statuses[effect] -= 1
	if stats.get_status_stacks(effect) <= 0:
		stats.remove_status(effect)
		Events.status_removed.emit(stats, effect)


func _on_damage_dealt(target: CombatantStats, amount: int) -> void:
	if target == player_stats:
		Events.player_damaged.emit(amount, target.current_hp)
		# The Compassionate (title): the first blow each combat that drops the player below half
		# HP triggers a clutch mend. Resolved BEFORE the lethal check, and HP floors at 0, so it
		# also catches an otherwise-killing blow — the player is left standing at _clutch_heal HP.
		# Healed inline (not via heal_combatant, whose dead-guard would refuse a 0-HP revive).
		if _clutch_heal > 0 and not _clutch_used and target.current_hp < target.max_hp / 2:
			_clutch_used = true
			var mended := mini(_clutch_heal, player_stats.max_hp - player_stats.current_hp)
			if mended > 0:
				player_stats.current_hp += mended
				Events.player_healed.emit(mended, player_stats.current_hp)
		# The Green Girdle: a blow that would fell the player leaves them standing instead, once
		# a combat. After the clutch heal, so it only catches what the title did not.
		if _girdle_ward and target.is_dead():
			_girdle_ward = false
			target.current_hp = _girdle_hp
			Events.player_healed.emit(_girdle_hp, target.current_hp)
			Events.combat_note.emit("The girdle holds, and nicks you.")
		if target.is_dead():
			phase = Phase.BATTLE_LOST
			Events.combat_lost.emit()
	else:
		for enemy in enemies:
			if enemy.stats == target:
				Events.enemy_damaged.emit(enemy, amount, target.current_hp)
				if target.is_dead():
					# Multi-phase bosses transition to the next lifebar instead of
					# dying, so overkill on one phase doesn't spill into the next —
					# you can't burst him past a phase. Only the final phase dies.
					if enemy.can_advance_phase():
						var line := enemy.advance_phase()
						_apply_phase_enter(enemy)
						Events.enemy_phase_changed.emit(enemy, enemy.phase_index, line)
					else:
						Events.enemy_died.emit(enemy)
				break


## Applies a multi-phase boss's one-time on-enter effects for the phase just entered:
## a Strength gain and Enraged (retaliation) on the boss, then an unavoidable lash at the
## player. Called right after advance_phase (which cleared the previous phase's statuses).
func _apply_phase_enter(enemy: EnemyCombatState) -> void:
	var data := enemy.enemy_data
	var i := enemy.phase_index
	if i < data.phase_enter_self_strength.size() and data.phase_enter_self_strength[i] > 0:
		apply_status_effect(enemy.stats, StatusEffects.STRENGTH, data.phase_enter_self_strength[i])
	if i < data.phase_enter_enraged.size() and data.phase_enter_enraged[i] > 0:
		apply_status_effect(enemy.stats, StatusEffects.ENRAGED, data.phase_enter_enraged[i])
	if i < data.phase_enter_damage.size() and data.phase_enter_damage[i] > 0:
		var lash: int = data.phase_enter_damage[i]
		player_stats.take_direct_damage(lash)
		_on_damage_dealt(player_stats, lash)


# -- Relic Processing --

func _process_relics(trigger: RelicData.RelicTrigger) -> void:
	for relic in RunManager.relics:
		if relic.trigger != trigger:
			continue
		_apply_relic_effect(relic)


func process_combat_end_relics() -> void:
	for relic in RunManager.relics:
		if relic.trigger != RelicData.RelicTrigger.ON_COMBAT_END:
			continue
		_apply_combat_end_slot(relic.effect, relic.value)
		_apply_combat_end_slot(relic.effect2, relic.value2)


func _apply_combat_end_slot(effect: RelicData.RelicEffect, value: int) -> void:
	match effect:
		RelicData.RelicEffect.HEAL:
			RunManager.heal(value)
		RelicData.RelicEffect.GAIN_GOLD:
			RunManager.add_gold(value)


## A relic's effect and, for a woken forgotten relic, the second one joined to it, in that order
## (so a shield's Block lands before the Poise that would have enlarged it).
func _apply_relic_effect(relic: RelicData) -> void:
	_apply_relic_slot(relic.effect, relic.value)
	_apply_relic_slot(relic.effect2, relic.value2)


func _apply_relic_slot(effect: RelicData.RelicEffect, value: int) -> void:
	match effect:
		RelicData.RelicEffect.GAIN_BLOCK:
			apply_block(player_stats, value)
		RelicData.RelicEffect.GAIN_STRENGTH:
			apply_status_effect(player_stats, StatusEffects.STRENGTH, value)
		RelicData.RelicEffect.GAIN_DEXTERITY:
			apply_status_effect(player_stats, StatusEffects.DEXTERITY, value)
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL:
			for enemy in enemies:
				if not enemy.stats.is_dead():
					apply_status_effect(enemy.stats, StatusEffects.VULNERABLE, value)
		RelicData.RelicEffect.APPLY_WEAK_ALL:
			for enemy in enemies:
				if not enemy.stats.is_dead():
					apply_status_effect(enemy.stats, StatusEffects.WEAK, value)
		RelicData.RelicEffect.DRAW_CARDS:
			draw_cards(value)
		RelicData.RelicEffect.GAIN_PASSION:
			RunManager.change_passion(value)
		RelicData.RelicEffect.HEAL:
			player_stats.current_hp = mini(
				player_stats.current_hp + value, player_stats.max_hp)


# -- Passion Zone Damage Modifier --

## Damage multipliers for the passion zone. Committing to an extreme powers up your
## dominant personality's cards and weakens the other; the mid-lean tiers (Inspired /
## Wavering) apply HALF that swing — a graduated on-the-way bonus/penalty — and the
## dispassionate center (Steady) is flat. Neutrals are never affected.
const ZONE_EXTREME_BONUS := 1.25
const ZONE_EXTREME_PENALTY := 0.75
const ZONE_LEAN_BONUS := 1.12    # Inspired/Wavering: ~half the extreme's on-type bonus (+12%)
const ZONE_LEAN_PENALTY := 0.88  # ...and ~half its off-type penalty (-12%)


## Single source for the zone damage multiplier at the CURRENT tier, given a card's
## personality. UI (card text, infographic) and combat (_apply_zone_modifier) both
## read this so the shown number and the dealt number can't diverge.
static func zone_multiplier(personality: CardData.PersonalityType) -> float:
	if personality == CardData.PersonalityType.NEUTRAL \
			or personality == CardData.PersonalityType.NEGATIVE:
		return 1.0
	var tier = RunManager.get_passion_tier()
	var primary_favored := false
	var lean := false
	match tier:
		PassionState.Tier.BLAZING:
			primary_favored = true
		PassionState.Tier.INSPIRED:
			primary_favored = true
			lean = true
		PassionState.Tier.HOLLOW:
			primary_favored = false
		PassionState.Tier.WAVERING:
			primary_favored = false
			lean = true
		_:  # STEADY — flat
			return 1.0
	var on_type := (personality == CardData.PersonalityType.PRIMARY) == primary_favored
	if on_type:
		return ZONE_LEAN_BONUS if lean else ZONE_EXTREME_BONUS
	return ZONE_LEAN_PENALTY if lean else ZONE_EXTREME_PENALTY


func _apply_zone_modifier(amount: int, personality: CardData.PersonalityType) -> int:
	return int(amount * zone_multiplier(personality))


## True if the off-type damage penalty currently applies. Used by UI to show
## modified damage on cards.
static func is_zone_penalized(personality: CardData.PersonalityType) -> bool:
	return zone_multiplier(personality) < 1.0


## True if the on-type damage bonus currently applies. UI companion to is_zone_penalized.
static func zone_bonus_active(personality: CardData.PersonalityType) -> bool:
	return zone_multiplier(personality) > 1.0


# -- Battle End Check --

func check_battle_end() -> void:
	if player_stats.is_dead():
		phase = Phase.BATTLE_LOST
		_disconnect_whiplash()
		_disconnect_mercy()
		Events.combat_lost.emit()
		return

	var all_dead = true
	for enemy in enemies:
		if not enemy.stats.is_dead():
			all_dead = false
			break

	if all_dead:
		phase = Phase.BATTLE_WON
		_disconnect_whiplash()
		_disconnect_mercy()
		# Resolve BTK BEFORE emitting combat_won so RunManager.last_btk_score
		# is populated when other listeners (RunManager._on_combat_won, etc.)
		# react. The crown_decision_scene reads these fields on its own _ready
		# after card_reward_scene routes there, but eager listeners benefit
		# from the strict ordering.
		_resolve_be_the_king()
		Events.combat_won.emit()
