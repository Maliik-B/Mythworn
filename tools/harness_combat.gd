class_name HarnessCombat
extends RefCounted
## Shared "decent player" combat policy for the balance harnesses. Drives the REAL
## CombatEngine (instant mode) with a greedy heuristic, so combat_harness (single
## fights) and run_harness (whole runs) share ONE policy that can't diverge.
##
## Instance-based (not static) purely so the filter lambdas can call sibling helpers
## via `self` without qualification. Make one and reuse it across trials.

const SAFETY_FRAC := 0.35    # below this fraction of max HP, block hard
const CHIP_TOLERANCE := 5    # incoming HP the player will eat before over-blocking
const SPIKE := 12            # a single telegraphed hit >= this is worth blocking


## Play one full player turn: keep choosing+playing cards until nothing useful
## remains or energy runs out. commit_target is the Passion (>=) a "committing"
## player tries to hold by spending a pole card each turn.
func play_turn(eng: CombatEngine, commit: bool, commit_target: int) -> void:
	var guard := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and guard < 30:
		guard += 1
		var card := choose_card(eng, commit, commit_target)
		if card == null:
			return
		var target: CombatantStats = eng.player_stats
		var low := _lowest(eng)
		if low != null:
			target = low.stats
		if not eng.play_card(card, target):
			return


## The single best card to play right now, or null to end the turn. Priority:
## survive a spike -> hold the pole (commit) -> set up Vulnerable -> maximise damage
## -> spend leftover energy on block.
func choose_card(eng: CombatEngine, commit: bool, commit_target: int) -> CardData:
	var living := _living(eng)
	if living.is_empty():
		return null
	var player_vuln := eng.player_stats.has_status(StatusEffects.VULNERABLE)
	var incoming := 0
	var biggest := 0
	for en in living:
		var d := _intent_damage(en, player_vuln)
		incoming += d
		biggest = maxi(biggest, d)
	var block := eng.player_stats.block
	var unblocked := maxi(0, incoming - block)
	var hp := eng.player_stats.current_hp
	var maxhp := eng.player_stats.max_hp

	var playable: Array[CardData] = []
	for c in eng.piles.hand:
		if not c.unplayable and c.energy_cost <= eng.energy:
			playable.append(c)
	if playable.is_empty():
		return null

	# Lethal check is only trustworthy for a single target (burst doesn't split).
	var can_lethal := false
	if living.size() == 1:
		var burst := 0
		for c in playable:
			if c.card_type == CardData.CardType.ATTACK:
				burst += _card_est_damage(eng, c)
		can_lethal = burst >= living[0].stats.current_hp + living[0].stats.block

	# 1) Survive: block a telegraphed spike or a hit that drops us below the margin.
	var threatened := biggest >= SPIKE or float(hp - unblocked) < SAFETY_FRAC * maxhp
	if not can_lethal and threatened and block < incoming - CHIP_TOLERANCE:
		var blk := _cheapest(playable.filter(_gives_block))
		if blk != null:
			return blk
		# A glass Water deck has no block — its defense is EVASION and CONTROL. Model
		# that so the pole isn't read as far more fragile than a real player would run it:
		# Intangible (Slip the Tide) negates the whole incoming turn, and a Freeze deletes the
		# biggest attacker's action. Reserve both for a genuine spike (they're scarce /
		# exhausting), not routine chip.
		if biggest >= SPIKE:
			var intang := _cheapest(playable.filter(_gives_intangible))
			if intang != null:
				return intang
			var freeze := _cheapest(playable.filter(_freezes))
			if freeze != null:
				return freeze

	# 2) Hold the pole: spend one Passion card to move toward the committed target.
	# Signed, so this validates BOTH poles: a positive target (Water) plays a
	# +Passion card while below it; a negative target (Physical) plays a -Passion
	# card while above it. Once past the target we stop and let damage take over.
	# The target is a FLOOR (water) or CEILING (physical), gated by the pole's sign —
	# not a set-point. A Water build climbs while below +target and never pulls back
	# down once past it; a Physical build sinks while above -target. So we only ever
	# push FURTHER toward the committed extreme.
	if commit and not can_lethal:
		var cur := RunManager.passion.current_value
		if commit_target >= 0 and cur < commit_target:
			var up := playable.filter(func(c): return _passion_gain(c) > 0)
			if not up.is_empty():
				up.sort_custom(func(a, b): return _passion_gain(a) > _passion_gain(b))
				return up[0]
		elif commit_target < 0 and cur > commit_target:
			var down := playable.filter(func(c): return _passion_gain(c) < 0)
			if not down.is_empty():
				down.sort_custom(func(a, b): return _passion_gain(a) < _passion_gain(b))
				return down[0]

	# 3) Set up Vulnerable on a healthy lowest target before committing damage.
	var target := _lowest(eng)
	if target != null and target.stats.current_hp > 14 \
			and not target.stats.has_status(StatusEffects.VULNERABLE):
		var vuln := _cheapest(playable.filter(_applies_vuln))
		if vuln != null:
			return vuln

	# 4) Biggest effective damage on the lowest-HP enemy.
	var atks := playable.filter(func(c): return c.card_type == CardData.CardType.ATTACK \
			and _card_est_damage(eng, c) > 0)
	if not atks.is_empty():
		atks.sort_custom(func(a, b): return _card_est_damage(eng, a) > _card_est_damage(eng, b))
		return atks[0]

	# 5) Leftover energy: keep blocking if a hit is still coming.
	if block < incoming:
		var blk2 := _cheapest(playable.filter(_gives_block))
		if blk2 != null:
			return blk2

	return null


## Attack damage the enemy's telegraphed intent will deal, mirroring deal_damage's
## Strength -> Weak -> Vulnerable order so the policy blocks the right amount.
func _intent_damage(enemy: EnemyCombatState, player_vuln: bool) -> int:
	if enemy.current_intent == null:
		return 0
	var estr := enemy.stats.get_status_stacks(StatusEffects.STRENGTH)
	var eweak := enemy.stats.has_status(StatusEffects.WEAK)
	var dmg := 0
	for e in enemy.current_intent.effects:
		if e is DamageEffect:
			var per := e.value + estr
			if eweak:
				per = int(per * 0.75)
			dmg += maxi(0, per) * e.hits
	if player_vuln:
		dmg = int(dmg * 1.5)
	return dmg


## Effective single-target damage of a player attack card, including Strength, Weak,
## and the Passion zone modifier (so the policy values on-type cards correctly).
func _card_est_damage(eng: CombatEngine, card: CardData) -> int:
	var pstr := eng.player_stats.get_status_stacks(StatusEffects.STRENGTH)
	var pweak := eng.player_stats.has_status(StatusEffects.WEAK)
	var total := 0
	for e in card.get_active_effects():
		if e is DamageEffect:
			var per := e.value + pstr
			if pweak:
				per = int(per * 0.75)
			per = _zone_adjust(per, card.personality)
			# X-cost torrent (Maelstrom): strikes once per energy on cast, so value it at
			# the energy it would spend right now, not a flat single hit.
			var reps: int = e.hits
			if e.x_scaled:
				reps = eng.energy
			total += maxi(0, per) * reps
	return total


func _zone_adjust(amount: int, pers: CardData.PersonalityType) -> int:
	if CombatEngine.zone_bonus_active(pers):
		return int(amount * 1.25)
	if CombatEngine.is_zone_penalized(pers):
		return int(amount * 0.75)
	return amount


func _gives_block(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is BlockEffect:
			return true
	return false


func _applies_vuln(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is StatusApplyEffect and not e.apply_to_source \
				and e.status_effect == StatusEffects.VULNERABLE:
			return true
	return false


## Grants the player Intangible (all incoming reduced to 1) — Water's evasion defense.
func _gives_intangible(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is StatusApplyEffect and e.apply_to_source \
				and e.status_effect == StatusEffects.INTANGIBLE:
			return true
	return false


## Applies Frozen to an enemy (skips its next action) — Water's control defense.
func _freezes(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is StatusApplyEffect and not e.apply_to_source \
				and e.status_effect == StatusEffects.STUN:
			return true
	return false


func _passion_gain(c: CardData) -> int:
	var total := 0
	for e in c.get_active_effects():
		if e is PassionEffect:
			total += e.value
	return total


func _cheapest(cards: Array) -> CardData:
	var best: CardData = null
	for c in cards:
		if best == null or c.energy_cost < best.energy_cost:
			best = c
	return best


func _living(eng: CombatEngine) -> Array[EnemyCombatState]:
	var out: Array[EnemyCombatState] = []
	for en in eng.enemies:
		if not en.stats.is_dead():
			out.append(en)
	return out


func _lowest(eng: CombatEngine) -> EnemyCombatState:
	var best: EnemyCombatState = null
	for en in eng.enemies:
		if en.stats.is_dead():
			continue
		if best == null or en.stats.current_hp < best.stats.current_hp:
			best = en
	return best
