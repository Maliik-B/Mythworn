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

var phase: Phase = Phase.PLAYER_TURN_START
var energy: int = MAX_ENERGY
var turn_number: int = 0
var player_stats: CombatantStats
var enemies: Array[EnemyCombatState] = []
var piles: PileManager
var _current_card: CardData = null # Set during card resolution for zone penalty
## Energy spent by the X-cost card currently resolving (X). Read by x_scaled effects
## so a torrent repeats once per energy; 0 outside an X-cost resolution.
var _current_x: int = 0
## Blooded Edge (raider questline relic): bonus damage still owed to the player's FIRST
## attack this combat. Primed at start_combat from the relic's value, spent on the first
## card-dealt damage instance, then 0 for the rest of the fight. 0 when the relic isn't held.
var _blooded_edge_pending: int = 0

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
	_arm_be_the_king(player_hp)
	# Whiplash power listens on tier crossings for the fight; no-op unless the player
	# actually holds Whiplash (checked in the handler). Disconnected at combat end.
	if not Events.passion_tier_changed.is_connected(_on_passion_tier_changed_whiplash):
		Events.passion_tier_changed.connect(_on_passion_tier_changed_whiplash)
	Events.combat_started.emit()
	_process_relics(RelicData.RelicTrigger.ON_COMBAT_START)
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


func _disconnect_whiplash() -> void:
	if Events.passion_tier_changed.is_connected(_on_passion_tier_changed_whiplash):
		Events.passion_tier_changed.disconnect(_on_passion_tier_changed_whiplash)


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
	player_stats.reset_block()
	tick_start_of_turn(player_stats)

	if player_stats.is_dead():
		phase = Phase.BATTLE_LOST
		Events.combat_lost.emit()
		return

	_process_relics(RelicData.RelicTrigger.ON_TURN_START)
	_apply_title_turn_start_effects()
	_process_powers()

	var drawn = piles.draw_cards(HAND_SIZE)
	for card in drawn:
		Events.card_drawn.emit(card)

	phase = Phase.PLAYER_TURN
	Events.player_turn_started.emit()


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
	phase = Phase.PLAYER_TURN_END
	tick_end_of_turn(player_stats)

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
	# Let the "Enemy Turn" banner read before anyone acts.
	await _pace(0.55)

	for enemy in enemies:
		if enemy.stats.is_dead():
			continue
		# Per-enemy: tick start -> announce + wind-up -> act -> settle -> tick end
		tick_start_of_turn(enemy.stats)
		if enemy.stats.is_dead():
			Events.enemy_died.emit(enemy)
			continue
		# Frozen enemies forfeit their action this turn. Poison still ticked above;
		# other end-of-turn statuses still count down below. One stack = one turn.
		if enemy.stats.has_status(StatusEffects.STUN):
			_reduce_status(enemy.stats, StatusEffects.STUN)
			Events.enemy_stunned.emit(enemy)
			await _pace(0.5)
			tick_end_of_turn(enemy.stats)
			continue
		Events.enemy_action_started.emit(enemy, enemy.current_intent)
		await _pace(0.35)                             # anticipation / wind-up
		execute_enemy_turn(enemy)                     # effect lands (damage flash/shake here)
		tick_end_of_turn(enemy.stats)
		await _pace(0.45)                             # let the hit read before the next enemy
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

	await _pace(0.25)
	start_player_turn()


## Enemy-turn pacing beat. Awaits a real timer during normal play; returns
## immediately when `instant` is set (the balance harness), so the exact same
## turn logic runs either paced-for-readability or as fast as the CPU allows.
func _pace(seconds: float) -> void:
	if instant:
		return
	await get_tree().create_timer(seconds).timeout


func execute_enemy_turn(enemy: EnemyCombatState) -> void:
	if not enemy.current_intent:
		return
	for effect in enemy.current_intent.effects:
		effect.apply(enemy.stats, player_stats, self)


# -- Card Play --

func can_play_card(card: CardData) -> bool:
	if phase != Phase.PLAYER_TURN:
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
	elif card.exhaust:
		piles.exhaust_pile.append(card)
		Events.card_exhausted.emit(card)
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

	# Title damage bonus: flat damage added to all player attacks (not enemies).
	# Applied before zone penalty so the penalty scales the boosted total uniformly.
	if source == player_stats:
		amount += RunManager.get_title_passive_total(TitleData.EffectType.DAMAGE_BONUS_FLAT)

	# Blooded Edge: the first attack damage the player lands this combat hits harder. Gated
	# on _current_card so only a played card's hit spends it (not a poison tick or lash), and
	# applied alongside the title bonus so all flat player bonuses scale uniformly under zones.
	if source == player_stats and _current_card != null and _blooded_edge_pending > 0:
		amount += _blooded_edge_pending
		_blooded_edge_pending = 0

	# Zone modifier: at a committed extreme, the dominant personality's cards hit
	# harder (+25%) and the off-type suffers (-25%). Only for player cards, never
	# enemies or neutrals. The dispassionate middle is flat — no bonus, no penalty.
	if _current_card and source == player_stats:
		amount = _apply_zone_modifier(amount, _current_card.personality)

	# Target modifiers
	if target.has_status(StatusEffects.VULNERABLE):
		amount = int(amount * 1.5)

	amount = maxi(0, amount)

	# Intangible clamps any single damage source to 1. Emo Hybrid's "Soulstep"
	# uses this for a deliberately defensive turn skip.
	if amount > 0 and target.has_status(StatusEffects.INTANGIBLE):
		amount = 1

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


## Mends a combatant up to its max HP (the Hollow Prelate's self-heal — the DPS-check
## elite). Clamps to the missing HP and emits enemy_healed for the matching enemy so the
## UI refreshes the bar. The player heals through RunManager, so a player_stats target
## finds no match here and emits nothing — enemy self-heals only.
func heal_combatant(target: CombatantStats, amount: int) -> void:
	if amount <= 0 or target.is_dead():
		return
	var healed := mini(amount, target.max_hp - target.current_hp)
	if healed <= 0:
		return
	target.current_hp += healed
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
		match relic.effect:
			RelicData.RelicEffect.HEAL:
				RunManager.heal(relic.value)
			RelicData.RelicEffect.GAIN_GOLD:
				RunManager.add_gold(relic.value)


func _apply_relic_effect(relic: RelicData) -> void:
	match relic.effect:
		RelicData.RelicEffect.GAIN_BLOCK:
			apply_block(player_stats, relic.value)
		RelicData.RelicEffect.GAIN_STRENGTH:
			apply_status_effect(player_stats, StatusEffects.STRENGTH, relic.value)
		RelicData.RelicEffect.GAIN_DEXTERITY:
			apply_status_effect(player_stats, StatusEffects.DEXTERITY, relic.value)
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL:
			for enemy in enemies:
				if not enemy.stats.is_dead():
					apply_status_effect(enemy.stats, StatusEffects.VULNERABLE, relic.value)
		RelicData.RelicEffect.APPLY_WEAK_ALL:
			for enemy in enemies:
				if not enemy.stats.is_dead():
					apply_status_effect(enemy.stats, StatusEffects.WEAK, relic.value)
		RelicData.RelicEffect.DRAW_CARDS:
			draw_cards(relic.value)
		RelicData.RelicEffect.GAIN_PASSION:
			RunManager.change_passion(relic.value)
		RelicData.RelicEffect.HEAL:
			player_stats.current_hp = mini(
				player_stats.current_hp + relic.value, player_stats.max_hp)


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
		# Resolve BTK BEFORE emitting combat_won so RunManager.last_btk_score
		# is populated when other listeners (RunManager._on_combat_won, etc.)
		# react. The crown_decision_scene reads these fields on its own _ready
		# after card_reward_scene routes there, but eager listeners benefit
		# from the strict ordering.
		_resolve_be_the_king()
		Events.combat_won.emit()
