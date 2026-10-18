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

## Memory ceiling for the batch harnesses. They run every trial inside one synchronous _ready,
## so --quit-after (which counts frames) and the failsafe timer cannot stop them, and anything
## a trial leaves behind piles up until the run ends. A healthy combat_harness run holds about
## 2,000 objects and 26 MB of static memory from its first trial to its last; run_harness sits
## close to that. The bounds are about five times that: never reached by a healthy run, and
## crossed within the first couple of hundred trials by the audio leak that once took a full run
## to 6.9 GB.
const CEILING_OBJECTS := 10000
const CEILING_STATIC_MB := 128

var peak_objects := 0
var peak_static_mb := 0.0


## Samples the process against the memory ceiling and keeps the peak for memory_summary().
## Returns false, after a push_error naming where it happened, once either bound is passed;
## the caller stops its trials and quits non-zero.
func within_memory_ceiling(where: String) -> bool:
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var static_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	peak_objects = maxi(peak_objects, objects)
	peak_static_mb = maxf(peak_static_mb, static_mb)
	if objects <= CEILING_OBJECTS and static_mb <= CEILING_STATIC_MB:
		return true
	push_error("memory ceiling passed at %s: %d objects (ceiling %d), %.1f MB static (ceiling %d MB). Something a trial creates is being kept; aborting instead of letting it grow." % [
		where, objects, CEILING_OBJECTS, static_mb, CEILING_STATIC_MB])
	return false


func memory_summary() -> String:
	return "memory: peak %d objects, %.1f MB static (ceiling %d objects, %d MB)" % [
		peak_objects, peak_static_mb, CEILING_OBJECTS, CEILING_STATIC_MB]


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
## survive a spike -> hold the pole (commit) -> set up Vulnerable -> the most damage the
## energy left can buy -> spend leftover energy on block.
func choose_card(eng: CombatEngine, commit: bool, commit_target: int) -> CardData:
	var living := _living(eng)
	if living.is_empty():
		return null
	var incoming := 0
	var piercing := 0  # the part of incoming that block cannot stop
	var biggest := 0
	for en in living:
		var d := _intent_damage(eng, en)
		incoming += d[0]
		piercing += d[1]
		biggest = maxi(biggest, d[0])
	var block := eng.player_stats.block
	var blockable := incoming - piercing
	var unblocked := maxi(0, blockable - block) + piercing
	var hp := eng.player_stats.current_hp
	var maxhp := eng.player_stats.max_hp

	var playable: Array[CardData] = []
	for c in eng.piles.hand:
		if not c.unplayable and c.energy_cost <= eng.energy:
			playable.append(c)
	if playable.is_empty():
		return null

	# The most damage this turn's energy can buy, as [damage, cards]. Lethal is judged on it
	# rather than on every attack in hand, which could add up to more than the energy pays
	# for. The lethal check is only trustworthy for a single target (burst doesn't split).
	var attacks := playable.filter(func(c): return c.card_type == CardData.CardType.ATTACK \
			and _card_est_damage(eng, c) > 0)
	var plan := _best_attack_plan(eng, attacks)
	var can_lethal := false
	if living.size() == 1:
		can_lethal = plan[0] >= living[0].stats.current_hp + living[0].stats.block

	# 1) Survive: block a telegraphed spike or a hit that drops us below the margin. Block is
	# only worth playing against the part of the hit it can stop; a pierce goes straight through.
	var threatened := biggest >= SPIKE or float(hp - unblocked) < SAFETY_FRAC * maxhp
	if not can_lethal and threatened and unblocked > CHIP_TOLERANCE:
		if blockable - block > CHIP_TOLERANCE:
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

	# 4) The most damage the energy left can buy, on the lowest-HP enemy. Play the plan's
	# biggest hit first; an X-cost card goes last, since it spends whatever is left.
	var first: CardData = null
	for c in plan[1]:
		if not c.x_cost and (first == null \
				or _card_est_damage(eng, c) > _card_est_damage(eng, first)):
			first = c
	if first == null and not plan[1].is_empty():
		first = plan[1][0]
	if first != null:
		return first

	# 5) Leftover energy: keep blocking if a hit block can stop is still coming.
	if block < blockable:
		var blk2 := _cheapest(playable.filter(_gives_block))
		if blk2 != null:
			return blk2

	return null


## What the enemy's telegraphed intent will do to the player, as [damage, the part of it that
## pierces block], hit by hit in deal_damage's order: Strength, Weak, then the player's
## Vulnerable and Intangible. The player's own statuses lose a stack at the end of the player's
## turn, before any enemy acts, so one counts only if it has a second stack to survive that. A
## Frozen enemy forfeits its action, so it threatens nothing this turn.
func _intent_damage(eng: CombatEngine, enemy: EnemyCombatState) -> Array:
	if enemy.current_intent == null or enemy.stats.has_status(StatusEffects.STUN):
		return [0, 0]
	var estr := enemy.stats.get_status_stacks(StatusEffects.STRENGTH)
	var eweak := enemy.stats.has_status(StatusEffects.WEAK)
	var player_vuln := eng.player_stats.get_status_stacks(StatusEffects.VULNERABLE) >= 2
	var player_intangible := eng.player_stats.get_status_stacks(StatusEffects.INTANGIBLE) >= 2
	var dmg := 0
	var pierced := 0
	for e in enemy.current_intent.effects:
		if e is DamageEffect:
			var per: int = e._effective_value() + estr
			if eweak:
				per = int(per * 0.75)
			if player_vuln:
				per = int(per * 1.5)
			per = maxi(0, per)
			if per > 0 and player_intangible:
				per = 1
			dmg += per * e.hits
			pierced += mini(e.pierce, per) * e.hits
	return [dmg, pierced]


## What a player attack would deal if played now. See _card_strike.
func _card_est_damage(eng: CombatEngine, card: CardData, x_energy: int = -1) -> int:
	return _card_strike(eng, card, x_energy)[0]


## What a player attack would do if played now, as [damage, hits landed], hit by hit the way
## deal_damage resolves it: the effect's base with its Passion-distance rider, + Strength, then
## Weak, + the Sword's Bearer bonus and the Momentum built so far this turn, then the card's
## Passion zone, then each target's Vulnerable or Intangible. The hits are the effect's own (X
## for an X-cost card, at x_energy or all the energy left) plus Overflow's extras at Blazing,
## landing on the lowest enemy, which is what play_turn targets, or on every living enemy for an
## area attack. Momentum's further climb and Blooded Edge belong to the turn and the combat
## rather than to one card, so _best_attack_plan adds them once to the plan as a whole.
func _card_strike(eng: CombatEngine, card: CardData, x_energy: int = -1) -> Array:
	var targets: Array[EnemyCombatState] = []
	if card.target_type == CardData.TargetType.ALL_ENEMIES:
		targets = _living(eng)
	else:
		var low := _lowest(eng)
		if low != null:
			targets.append(low)
	var ps := eng.player_stats
	var pstr := ps.get_status_stacks(StatusEffects.STRENGTH)
	var pweak := ps.has_status(StatusEffects.WEAK)
	var flat := eng.sword_bonus() + eng._momentum
	var zone := CombatEngine.zone_multiplier(card.personality)
	var overflow := 0
	if ps.has_power(Powers.OVERFLOW) and RunManager.get_passion_tier() == PassionState.Tier.BLAZING:
		overflow = ps.get_power_stacks(Powers.OVERFLOW)
	var damage := 0
	var landed := 0
	for e in card.get_active_effects():
		if not e is DamageEffect:
			continue
		var hits: int = e.hits
		if e.x_scaled:
			hits = eng.energy if x_energy < 0 else x_energy
		if hits > 1:
			hits += overflow
		var per: int = e._effective_value() + pstr
		if pweak:
			per = int(per * 0.75)
		per = int((per + flat) * zone)
		for t in targets:
			var hit := per
			if t.stats.has_status(StatusEffects.VULNERABLE):
				hit = int(hit * 1.5)
			hit = maxi(0, hit)
			if hit > 0 and t.stats.has_status(StatusEffects.INTANGIBLE):
				hit = 1
			damage += hit * hits
			landed += hits
	return [damage, landed]


## The most damage the energy left this turn can buy from these attacks, as [damage, cards]:
## a 0/1 knapsack over energy cost, so two cheap hits can beat one expensive one. An X-cost
## card spends whatever is left when it is played, so it is weighed on top of each cheaper
## fixed-cost set. Ties keep hand order, which keeps the choice deterministic.
##
## With the Momentum relic every hit raises every later hit this turn, so a set's worth also
## depends on how many hits it lands in total: the t-th hit carries t times the per-hit bonus
## on top of what _card_strike counted. The knapsack then also tracks hits, and the plan adds
## that climb once. Blooded Edge's first-hit bonus is added once to any plan that attacks.
## Both are counted before the zone and Vulnerable multipliers, the one approximation left.
func _best_attack_plan(eng: CombatEngine, attacks: Array) -> Array:
	var cap: int = eng.energy
	var per_hit: int = eng._momentum_per_hit
	var fixed: Array = []
	var x_cards: Array = []
	for c in attacks:
		if c.x_cost:
			x_cards.append(c)
		else:
			fixed.append(c)
	var plan: Array
	if per_hit <= 0:
		var best: Array = []  # best[e]: the most damage from fixed-cost attacks for at most e energy
		for e in cap + 1:
			best.append([0, []])
		for c in fixed:
			var cost: int = c.energy_cost
			var dmg := _card_est_damage(eng, c)
			for e in range(cap, cost - 1, -1):
				var with_c: int = best[e - cost][0] + dmg
				if with_c > best[e][0]:
					best[e] = [with_c, best[e - cost][1] + [c]]
		plan = best[cap]
		for x in x_cards:
			for e in cap + 1:
				var with_x: int = best[e][0] + _card_est_damage(eng, x, cap - e)
				if with_x > plan[0]:
					plan = [with_x, best[e][1] + [x]]
	else:
		# table[e][hits]: the most damage from fixed-cost attacks landing exactly that many hits
		# for at most e energy.
		var table: Array = []
		for e in cap + 1:
			table.append({0: [0, []]})
		for c in fixed:
			var cost: int = c.energy_cost
			var s := _card_strike(eng, c)
			for e in range(cap, cost - 1, -1):
				var before: Dictionary = table[e - cost].duplicate()
				for h in before:
					var cand: int = before[h][0] + s[0]
					var hh: int = h + s[1]
					if not table[e].has(hh) or cand > table[e][hh][0]:
						table[e][hh] = [cand, before[h][1] + [c]]
		plan = [0, []]
		for h in table[cap]:
			var v: int = table[cap][h][0] + per_hit * h * (h - 1) / 2
			if v > plan[0]:
				plan = [v, table[cap][h][1]]
		for x in x_cards:
			for e in cap + 1:
				var xs := _card_strike(eng, x, cap - e)
				for h in table[e]:
					var total_hits: int = h + xs[1]
					var v: int = table[e][h][0] + xs[0] + per_hit * total_hits * (total_hits - 1) / 2
					if v > plan[0]:
						plan = [v, table[e][h][1] + [x]]
	if eng._blooded_edge_pending > 0 and not plan[1].is_empty():
		plan = [plan[0] + eng._blooded_edge_pending, plan[1]]
	return plan


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
