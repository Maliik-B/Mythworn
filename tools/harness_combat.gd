class_name HarnessCombat
extends RefCounted
## Shared "decent player" combat policy for the balance harnesses. Drives the REAL
## CombatEngine (instant mode), so combat_harness (single fights) and run_harness (whole
## runs) share ONE policy that can't diverge.
##
## The player plans each turn as a whole and counts everything in one currency: the HP it
## expects to lose over the rest of the fight. A candidate plan is played out on a copy of
## the fight exactly as the engine would resolve it, the enemy turn after it included, and
## what is left of the fight beyond that is priced by a race estimate (_future_loss). The
## cheapest plan wins; its first card is played and the rest is followed while the hand
## still matches it. A committing player below its Passion target first makes all the progress
## toward it the turn allows.
##
## Instance-based (not static) so it can carry what it has seen this combat. Make one and
## reuse it across trials; it notices a new combat by the engine it is handed.

const PLAN_NODE_BUDGET := 800  # plans weighed per decision before the search stops
const DEATH_COST := 100000.0   # a plan the player does not survive ranks below every one it does
## Between two plans that cost the same HP, the one leaving less enemy HP standing: a hundredth
## of an HP per point. It only breaks ties, such as an enemy whose attacks have been weakened to 0,
## where HP alone would leave the player no reason to finish the fight.
const PROGRESS_EPS := 0.01

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

# What the player has dealt this combat, for the race estimate's damage rate.
var _combat_id := 0
var _dealt := 0.0
var _turns_seen := 0

# Each enemy's moveset digested once per combat (see _moves_of); reset with the combat so the
# freshly built enemies of every trial are not kept.
var _move_info := {}

# This turn's plan, followed card by card while the hand still matches it.
var _plan_combat := 0
var _plan_turn_no := -1
var _plan_hand: Array = []
var _plan_rest: Array = []


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


## Play one full player turn: keep choosing and playing cards until the plan is spent or
## nothing is worth playing. commit_target is the Passion (>=) a "committing" player tries to
## reach and hold, making progress toward it each turn. Also records the damage this turn
## dealt, which feeds the race estimate's idea of how fast this player kills.
func play_turn(eng: CombatEngine, commit: bool, commit_target: int) -> void:
	if eng.get_instance_id() != _combat_id:
		_combat_id = eng.get_instance_id()
		_dealt = 0.0
		_turns_seen = 0
		_move_info = {}
	var before := _pool_total(_line_copy(eng))
	var guard := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and guard < 30:
		guard += 1
		var play := choose_play(eng, commit, commit_target)
		if play.is_empty():
			break
		if not eng.play_card(play[0], play[1]):
			break
	_dealt += maxf(0.0, before - _pool_total(_line_copy(eng)))
	_turns_seen += 1
	# The plan belongs to this turn; holding its cards past it would keep them alive.
	_plan_hand = []
	_plan_rest = []


## The next card to play, or null to end the turn.
func choose_card(eng: CombatEngine, commit: bool, commit_target: int) -> CardData:
	var play := choose_play(eng, commit, commit_target)
	return play[0] if not play.is_empty() else null


## The next card and its target as [card, target stats], or [] to end the turn. An attack
## whose Enraged lash alone would finish the player is never played.
func choose_play(eng: CombatEngine, commit: bool, commit_target: int) -> Array:
	if _living(eng).is_empty():
		return []
	var ctx := _context(eng, commit, commit_target)
	var enraged := false
	for en in eng.enemies:
		if not en.stats.is_dead() and en.stats.has_status(StatusEffects.ENRAGED):
			enraged = true
	var playable: Array = []
	for c in eng.piles.hand:
		if c.unplayable or c.energy_cost > eng.energy:
			continue
		if enraged and c.card_type == CardData.CardType.ATTACK:
			var line := _line_copy(eng)
			_sim_card(eng, ctx, c, line)
			if line["php"] <= 0:
				continue
		playable.append(c)
	if playable.is_empty():
		return []
	var card := _follow_plan(eng, playable)
	if card == null:
		var plan := _plan_turn(eng, ctx, playable)
		_plan_combat = eng.get_instance_id()
		_plan_turn_no = eng.turn_number
		_plan_hand = eng.piles.hand.duplicate()
		if plan.is_empty():
			_plan_rest = []
			return []
		card = plan[0]
		_plan_rest = plan.slice(1)
	return [card, _target_for(eng, card)]


## The plan's next card, if this turn's plan still fits the hand: a card the plan never saw (a
## draw, an injected copy) or a planned card that can no longer be played means re-planning.
func _follow_plan(eng: CombatEngine, playable: Array) -> CardData:
	if _plan_combat != eng.get_instance_id() or _plan_turn_no != eng.turn_number \
			or _plan_rest.is_empty():
		return null
	for c in eng.piles.hand:
		if not _plan_hand.has(c):
			return null
	var next: CardData = _plan_rest[0]
	if not playable.has(next):
		return null
	_plan_rest = _plan_rest.slice(1)
	return next


## Where a card is aimed: a single-target attack at the focus enemy (_focus_index), anything
## else at the player, which play_card ignores for self and area cards.
func _target_for(eng: CombatEngine, card: CardData) -> CombatantStats:
	if card.target_type == CardData.TargetType.SINGLE_ENEMY:
		var i := _focus_index(_line_copy(eng))
		if i >= 0:
			return eng.enemies[i].stats
	return eng.player_stats


# ============================================================
# PLANNING
# ============================================================

## The cheapest plan for this turn, as cards in the order to play them: every affordable set of
## the playable cards, each played in a sensible fixed order (_canonical_order) and then, when a
## kill is in reach and order decides what is wasted, with the attacks smallest first as well.
## A committing player below its target first makes all the Passion progress toward its pole the
## turn allows (up to the target), as the archetype always has, and only then the cheapest such
## plan; it gives that up only when every such plan loses the fight this turn and another does
## not, and a plan that wins the fight outright needs no progress.
func _plan_turn(eng: CombatEngine, ctx: Dictionary, playable: Array) -> Array:
	var start := _line_copy(eng)
	var best := {"nodes": 0, "any": [], "any_cost": INF, "any_won": false,
		"pole": [], "pole_cost": INF, "pole_progress": -1}
	_plan_search(eng, ctx, _canonical_order(eng, playable, false), 0, _copy_line(start), [], best)
	var total_attack := 0.0
	for c in playable:
		total_attack += _neutral_damage(eng, c)[0]
	for f in start["foes"]:
		var reach: float = total_attack * (1.5 if f["vuln"] > 0 else 1.0)
		if not f["dead"] and reach >= f["hp"] + f["block"]:
			_plan_search(eng, ctx, _canonical_order(eng, playable, true), 0, _copy_line(start), [],
				best)
			break
	if ctx["pole_dir"] == 0 or best["any_won"] or best["pole_cost"] == INF:
		return best["any"]
	if best["pole_cost"] >= DEATH_COST and best["any_cost"] < DEATH_COST:
		return best["any"]
	return best["pole"]


## Every set of cards in canonical order, depth first, each prefix weighed as a plan that stops
## there. Two copies of the same card are interchangeable, so only the first is tried at a step.
## A node is weighed after its extensions, because weighing plays the enemy turn on the line.
func _plan_search(eng: CombatEngine, ctx: Dictionary, cards: Array, from: int, line: Dictionary,
		plan: Array, best: Dictionary) -> void:
	for i in range(from, cards.size()):
		if best["nodes"] >= PLAN_NODE_BUDGET:
			break
		var c: CardData = cards[i]
		if i > from and c.card_name == cards[i - 1].card_name:
			continue
		if not c.x_cost and c.energy_cost > line["energy"]:
			continue
		var next := _copy_line(line)
		_sim_card(eng, ctx, c, next)
		if next["php"] <= 0:
			continue
		_plan_search(eng, ctx, cards, i + 1, next, plan + [c], best)
	_weigh(eng, ctx, line, plan, best)


## Prices one plan, consuming its line: the HP lost by the end of the coming enemy turn, plus
## what the rest of the fight is expected to cost from there, plus PROGRESS_EPS for every point
## of enemy HP left standing. A plan that wins the fight costs only what it lost getting there;
## one the player does not survive costs DEATH_COST, less the further it got.
func _weigh(eng: CombatEngine, ctx: Dictionary, line: Dictionary, plan: Array,
		best: Dictionary) -> void:
	best["nodes"] += 1
	var cost: float
	var won := _all_down(line)
	if won:
		cost = ctx["start_hp"] - line["php"]
	else:
		_sim_enemy_turn(eng, ctx, line)
		if line["php"] <= 0:
			cost = DEATH_COST + _pool_total(line)
		else:
			cost = ctx["start_hp"] - line["php"] + _future_loss(eng, ctx, line) 				+ PROGRESS_EPS * _pool_total(line)
	if cost < best["any_cost"]:
		best["any_cost"] = cost
		best["any"] = plan
		best["any_won"] = won
	if ctx["pole_dir"] != 0:
		var progress: int = clampi((line["passion"] - ctx["passion0"]) * ctx["pole_dir"], 0,
			absi(ctx["pole_target"] - ctx["passion0"]))
		if progress > best["pole_progress"] \
				or (progress == best["pole_progress"] and cost < best["pole_cost"]):
			best["pole_progress"] = progress
			best["pole_cost"] = cost
			best["pole"] = plan


## The order a set of cards is played in: energy, draw, powers, self-buffs and Passion first, so
## what they enable or raise is in place; then skills that debuff enemies; then attacks, those
## applying Vulnerable first and the rest biggest first (or smallest first, when asked, so a
## small card can finish an enemy and save a big one for the next); then block and healing; X-
## cost cards last, since they spend whatever energy is left. Ties keep identical cards adjacent.
func _canonical_order(eng: CombatEngine, cards: Array, small_first: bool) -> Array:
	var keyed: Array = []
	for i in cards.size():
		var c: CardData = cards[i]
		var dmg: int = _neutral_damage(eng, c)[0]
		var rank: int
		if c.x_cost:
			rank = 5
		elif c.card_type == CardData.CardType.ATTACK:
			rank = 2 if _applies_to_enemy(c, StatusEffects.VULNERABLE) else 3
		elif _debuffs_enemies(c):
			rank = 1
		elif _blocks_or_heals(c):
			rank = 4
		else:
			rank = 0
		var size := float(dmg) if small_first else -float(dmg)
		keyed.append([rank, size if rank == 3 else 0.0, c.card_name, i, c])
	keyed.sort_custom(func(a, b):
		if a[0] != b[0]: return a[0] < b[0]
		if a[1] != b[1]: return a[1] < b[1]
		if a[2] != b[2]: return a[2] < b[2]
		return a[3] < b[3])
	var out: Array = []
	for k in keyed:
		out.append(k[4])
	return out


# ============================================================
# THE FIGHT, COPIED: what a plan does this turn
# ============================================================

## A copy of everything a card or an enemy action reads or changes: each enemy's HP, block,
## statuses, lifebar, telegraphed and pre-rolled moves; the player's HP, block, statuses and
## powers; and the turn's energy, Passion, Momentum, Blooded Edge and cards drawn.
func _line_copy(eng: CombatEngine) -> Dictionary:
	var foes: Array = []
	for en in eng.enemies:
		var s := en.stats
		foes.append({
			"hp": s.current_hp, "max": s.max_hp, "block": s.block,
			"vuln": s.get_status_stacks(StatusEffects.VULNERABLE),
			"weak": s.get_status_stacks(StatusEffects.WEAK),
			"intangible": s.get_status_stacks(StatusEffects.INTANGIBLE),
			"enraged": s.get_status_stacks(StatusEffects.ENRAGED),
			"strength": s.get_status_stacks(StatusEffects.STRENGTH),
			"poison": s.get_status_stacks(StatusEffects.POISON),
			"chilled": s.get_status_stacks(StatusEffects.CHILLED),
			"stun": s.get_status_stacks(StatusEffects.STUN),
			"dex": s.get_status_stacks(StatusEffects.DEXTERITY),
			"phase": en.phase_index, "data": en.enemy_data, "intent": en.current_intent,
			"next": en.next_intent, "dead": s.is_dead(), "unknown_intent": false,
		})
	var ps := eng.player_stats
	var powers := {}
	for p in ps.powers:
		powers[p.id] = ps.powers[p]
	return {
		"foes": foes, "php": ps.current_hp, "pmax": ps.max_hp, "pblock": ps.block,
		"pstr": ps.get_status_stacks(StatusEffects.STRENGTH),
		"pweak": ps.get_status_stacks(StatusEffects.WEAK),
		"pvuln": ps.get_status_stacks(StatusEffects.VULNERABLE),
		"pint": ps.get_status_stacks(StatusEffects.INTANGIBLE),
		"pdex": ps.get_status_stacks(StatusEffects.DEXTERITY),
		"ppoison": ps.get_status_stacks(StatusEffects.POISON),
		"powers": powers, "energy": eng.energy,
		"passion": RunManager.passion.current_value if RunManager.passion else 0,
		"momentum": eng._momentum, "blooded": eng._blooded_edge_pending, "draws": 0,
	}


## A copy of a line deep enough that changing one cannot change the other: each enemy's and the
## powers' dictionaries are copied, the resources they point at (enemy data, moves) are shared.
func _copy_line(line: Dictionary) -> Dictionary:
	var c := line.duplicate()
	var foes: Array = []
	for f in line["foes"]:
		foes.append(f.duplicate())
	c["foes"] = foes
	c["powers"] = line["powers"].duplicate()
	return c


## Plays one card on the copied line the way play_card and the effects' apply() would, effect
## by effect: damage hit by hit through deal_damage's order (with lifebars, overkill, hits on a
## fallen enemy, Enraged lash, Momentum and Blooded Edge), block, statuses (and Water's control-
## heal), healing, Passion, energy, draws and powers. A single-target card strikes the focus
## enemy; an area card every enemy still standing when each of its effects resolves.
func _sim_card(eng: CombatEngine, ctx: Dictionary, card: CardData, line: Dictionary) -> void:
	var x := 0
	if card.x_cost:
		x = line["energy"]
		line["energy"] = 0
	else:
		line["energy"] -= card.energy_cost
	var foes: Array = line["foes"]
	var single := -1
	if card.target_type == CardData.TargetType.SINGLE_ENEMY:
		single = _focus_index(line)
	for e in card.get_active_effects():
		var targets: Array = []  # foe indices; -1 is the player
		match card.target_type:
			CardData.TargetType.SELF, CardData.TargetType.NONE:
				targets = [-1]
			CardData.TargetType.SINGLE_ENEMY:
				if single >= 0:
					targets = [single]
			CardData.TargetType.ALL_ENEMIES:
				for i in foes.size():
					if not foes[i]["dead"]:
						targets.append(i)
		for t in targets:
			_sim_effect(eng, ctx, card, e, t, x, line)


func _sim_effect(eng: CombatEngine, ctx: Dictionary, card: CardData, e, t: int,
		x: int, line: Dictionary) -> void:
	var foes: Array = line["foes"]
	if e is DamageEffect:
		if t < 0:
			return
		var hits: int = e.hits
		if e.x_scaled:
			hits = x
		var tier: int = RunManager.get_passion_tier_for_value(line["passion"])
		if hits > 1 and tier == PassionState.Tier.BLAZING:
			hits += line["powers"].get(&"overflow", 0)
		var f: Dictionary = foes[t]
		var zone := _zone_at(card.personality, tier)
		for h in hits:
			_player_hit(ctx, e, zone, f, line)
		if e.energy_on_kill > 0 and f["dead"]:
			line["energy"] += e.energy_on_kill
	elif e is BlockEffect:
		line["pblock"] += e.value + line["pdex"]
	elif e is StatusApplyEffect:
		if e.apply_to_allies:
			for i in foes.size():
				if not foes[i]["dead"]:
					_apply_status(ctx, line, i, e.status_effect, e.value)
		elif e.apply_to_source:
			_apply_status(ctx, line, -1, e.status_effect, e.value)
		else:
			_apply_status(ctx, line, t, e.status_effect, e.value)
	elif e is HealEffect:
		if e.apply_to_source and line["php"] > 0:
			line["php"] = mini(line["pmax"], line["php"] + maxi(0, e.value))
	elif e is PassionEffect:
		_move_passion(ctx, line, int(e.value * ctx["volatility"]))
	elif e is EnergyEffect:
		line["energy"] = maxi(0, line["energy"] + e.value)
	elif e is DrawEffect:
		line["draws"] += e.value
	elif e is GainPowerEffect:
		if e.power:
			line["powers"][e.power.id] = line["powers"].get(e.power.id, 0) + e.stacks


## One player hit on a copied enemy, in deal_damage's order. The zone is the card's at the tier
## when its damage effect resolves.
func _player_hit(ctx: Dictionary, e: DamageEffect, zone: float, f: Dictionary,
		line: Dictionary) -> void:
	var amount: int = e.value
	if e.passion_bonus_divisor > 0:
		amount += absi(line["passion"] - ctx["center"]) / e.passion_bonus_divisor
	amount += line["pstr"]
	if line["pweak"] > 0:
		amount = int(amount * 0.75)
	amount += ctx["sword"] + line["momentum"]
	if line["blooded"] > 0:
		amount += line["blooded"]
		line["blooded"] = 0
	amount = int(amount * zone)
	if f["vuln"] > 0:
		amount = int(amount * 1.5)
	amount = maxi(0, amount)
	if amount > 0 and f["intangible"] > 0:
		amount = 1
	var direct := mini(e.pierce, amount)
	var absorbed: int = mini(f["block"], amount - direct)
	f["block"] -= absorbed
	var through: int = amount - absorbed
	f["hp"] = maxi(0, f["hp"] - through)
	if f["hp"] == 0 and not f["dead"]:
		_bar_down(ctx, line, f)
	line["momentum"] += ctx["momentum_per_hit"]
	if through > 0 and f["enraged"] > 0:
		line["php"] = maxi(0, line["php"] - f["enraged"])


## An enemy brought to 0: a boss with another lifebar starts it full, with no block, its
## statuses cleared, its entry Strength and Enraged, and lashes the player on entering; it
## rolls a new move the player has not seen. Anything else falls.
func _bar_down(_ctx: Dictionary, line: Dictionary, f: Dictionary) -> void:
	var data: EnemyData = f["data"]
	if data.phase_hps.size() > f["phase"] + 1:
		f["phase"] += 1
		var p: int = f["phase"]
		f["hp"] = data.phase_hps[p]
		f["max"] = data.phase_hps[p]
		f["block"] = 0
		for k in ["vuln", "weak", "intangible", "enraged", "strength", "poison", "chilled",
				"stun", "dex"]:
			f[k] = 0
		if data.phase_enter_self_strength.size() > p:
			f["strength"] = data.phase_enter_self_strength[p]
		if data.phase_enter_enraged.size() > p:
			f["enraged"] = data.phase_enter_enraged[p]
		if data.phase_enter_damage.size() > p:
			line["php"] = maxi(0, line["php"] - data.phase_enter_damage[p])
		f["intent"] = null
		f["next"] = null
		f["unknown_intent"] = true
	else:
		f["dead"] = true


## A status landing on a copied combatant (index -1 is the player), stacked as the engine
## stacks it, with Water's control-heal when Weak or Frozen lands on an enemy.
func _apply_status(ctx: Dictionary, line: Dictionary, t: int, status: StatusEffectData,
		stacks: int) -> void:
	var key := _status_key(status)
	if key == "":
		return
	if t < 0:
		var pkey: String = {"vuln": "pvuln", "weak": "pweak", "intangible": "pint",
			"strength": "pstr", "dex": "pdex", "poison": "ppoison"}.get(key, "")
		if pkey != "":
			line[pkey] += stacks
		return
	var f: Dictionary = line["foes"][t]
	if key == "stun":
		f["stun"] = maxi(f["stun"], stacks)
	else:
		f[key] += stacks
	if (key == "weak" or key == "stun") and line["php"] > 0 and ctx["control_heal"] > 0:
		line["php"] = mini(line["pmax"], line["php"] + ctx["control_heal"])


func _status_key(status: StatusEffectData) -> String:
	if status == StatusEffects.VULNERABLE: return "vuln"
	if status == StatusEffects.WEAK: return "weak"
	if status == StatusEffects.INTANGIBLE: return "intangible"
	if status == StatusEffects.ENRAGED: return "enraged"
	if status == StatusEffects.STRENGTH: return "strength"
	if status == StatusEffects.POISON: return "poison"
	if status == StatusEffects.CHILLED: return "chilled"
	if status == StatusEffects.STUN: return "stun"
	if status == StatusEffects.DEXTERITY: return "dex"
	return ""


## Passion moves on the copy as it would on the meter, clamped; crossing into a new tier draws
## Whiplash's cards.
func _move_passion(ctx: Dictionary, line: Dictionary, amount: int) -> void:
	var before: int = line["passion"]
	line["passion"] = clampi(before + amount, ctx["pmin"], ctx["pmax_passion"])
	if RunManager.get_passion_tier_for_value(before) \
			!= RunManager.get_passion_tier_for_value(line["passion"]):
		line["draws"] += line["powers"].get(&"whiplash", 0) * Powers.WHIPLASH_DRAW


## The enemy turn after the plan, on the copy, as the engine runs it: the player's statuses tick
## first, every enemy's block resets, then enemy by enemy: Poison ticks (and can fell it before it
## acts), a Frozen enemy forfeits its action, otherwise its move resolves (an unseen move, after
## a lifebar broke, at the moveset's average), then Chilled bites or freezes and its statuses tick.
## Last, any Poison on the player ticks, as it does when the next player turn starts.
func _sim_enemy_turn(_eng: CombatEngine, ctx: Dictionary, line: Dictionary) -> void:
	for k in ["pvuln", "pweak", "pint", "pdex"]:
		line[k] = maxi(0, line[k] - 1)
	var foes: Array = line["foes"]
	for f in foes:
		if not f["dead"]:
			f["block"] = 0
	for f in foes:
		if f["dead"] or line["php"] <= 0:
			continue
		if f["poison"] > 0:
			var tick: int = 1 if f["intangible"] > 0 else f["poison"]
			f["hp"] = maxi(0, f["hp"] - tick)
			f["poison"] -= 1
			if f["hp"] == 0:
				_bar_down(ctx, line, f)
				if f["dead"]:
					continue
		if f["stun"] > 0:
			f["stun"] -= 1
		elif f["unknown_intent"] or f["intent"] == null:
			_enemy_strikes(line, f, _moves_of(f, f["phase"], 0, _hp_frac(f))[0], 0)
		else:
			for e in f["intent"].effects:
				_enemy_effect(ctx, line, f, e)
				if line["php"] <= 0:
					return
		if f["chilled"] > 0:
			var chip: int = 1 if f["intangible"] > 0 else CombatEngine.CHILL_CHIP
			f["hp"] = maxi(0, f["hp"] - chip)
			if f["hp"] == 0:
				_bar_down(ctx, line, f)
			# A chip that fells the enemy ends Chilled's turn, but its statuses still tick below.
			if f["dead"]:
				pass
			elif f["chilled"] >= CombatEngine.CHILL_FREEZE_THRESHOLD:
				f["stun"] = maxi(f["stun"], 1)
				f["chilled"] = 0
				if line["php"] > 0 and ctx["control_heal"] > 0:
					line["php"] = mini(line["pmax"], line["php"] + ctx["control_heal"])
			elif f["chilled"] > 0:
				f["chilled"] -= 1
		for k in ["vuln", "weak", "intangible", "dex"]:
			f[k] = maxi(0, f[k] - 1)
	if line["php"] > 0 and line["ppoison"] > 0:
		var tick: int = 1 if line["pint"] > 0 else line["ppoison"]
		line["php"] = maxi(0, line["php"] - tick)
		line["ppoison"] -= 1


func _enemy_effect(ctx: Dictionary, line: Dictionary, f: Dictionary, e) -> void:
	if e is DamageEffect:
		# A blow that costs its user (the Beast at the Stone's Breaking Blow): a flat loss off
		# its own HP, as CombatEngine.self_damage resolves it, breaking a bar the same way.
		if e.apply_to_source:
			f["hp"] = maxi(0, f["hp"] - e.value)
			if f["hp"] == 0 and not f["dead"]:
				_bar_down(ctx, line, f)
			return
		var base: int = e.value
		for h in e.hits:
			_enemy_strikes(line, f, base, e.pierce)
			if line["php"] <= 0:
				return
	elif e is BlockEffect:
		f["block"] += e.value + f["dex"]
	elif e is StatusApplyEffect:
		var foes: Array = line["foes"]
		if e.apply_to_allies:
			for i in foes.size():
				if not foes[i]["dead"]:
					_apply_status(ctx, line, i, e.status_effect, e.value)
		elif e.apply_to_source:
			var key := _status_key(e.status_effect)
			if key == "stun":
				f["stun"] = maxi(f["stun"], e.value)
			elif key != "":
				f[key] += e.value
		else:
			_apply_status(ctx, line, -1, e.status_effect, e.value)
	elif e is HealEffect:
		if e.apply_to_source:
			f["hp"] = mini(f["max"], f["hp"] + maxi(0, e.value))


## One enemy hit on the player, in deal_damage's order: Strength, Weak, the player's Vulnerable
## and Intangible, then block (less any pierce) before HP.
func _enemy_strikes(line: Dictionary, f: Dictionary, base: float, pierce: int) -> void:
	var amount: int = int(base) + f["strength"]
	if f["weak"] > 0:
		amount = int(amount * 0.75)
	if line["pvuln"] > 0:
		amount = int(amount * 1.5)
	amount = maxi(0, amount)
	if amount > 0 and line["pint"] > 0:
		amount = 1
	var direct := mini(pierce, amount)
	var absorbed: int = mini(line["pblock"], amount - direct)
	line["pblock"] -= absorbed
	line["php"] = maxi(0, line["php"] - (amount - absorbed))


# ============================================================
# THE REST OF THE FIGHT: the race estimate
# ============================================================

## What the rest of the fight is expected to cost in HP, from the state after the enemy turn.
## The player kills at its damage rate (_context), and kills enemies in the order that loses
## least: the most damage per point of HP first (Smith's rule for weighted completion time),
## each enemy hitting every turn until it falls, a boss at each lifebar's own rate and its entry
## lash on top. Enemies escalate as their movesets do, on average: Strength an enemy gains, or
## its allies rally into it, makes every later hit harder; block and healing it gains each turn
## slow the kill; cards it shuffles into the player's deck dilute the player's damage. What the
## plan leaves behind adjusts it: Weak and Frozen spare attacks, Poison and Chilled take HP on
## their own, Vulnerable speeds the first kill, Strength and powers raise the rate or give block,
## and cards drawn with energy left to play them count as damage now. With Excalibur in Sight
## mode the next move is known and used. Block and healing per turn from relics and powers come
## off the total.
func _future_loss(_eng: CombatEngine, ctx: Dictionary, line: Dictionary) -> float:
	var foes: Array = []
	for f in line["foes"]:
		if not f["dead"]:
			foes.append(f)
	if foes.is_empty():
		return 0.0
	var tier: int = RunManager.get_passion_tier_for_value(line["passion"])
	var extreme := tier == PassionState.Tier.BLAZING or tier == PassionState.Tier.HOLLOW
	var powers: Dictionary = line["powers"]
	var p0: Dictionary = ctx["powers0"]
	var rate: float = ctx["D"] + (line["pstr"] - ctx["str0"]) * ctx["hits_turn"]
	if tier == PassionState.Tier.BLAZING:
		rate += (powers.get(&"overflow", 0) - p0.get(&"overflow", 0)) \
			* ctx["multi_turn"] * ctx["multi_hit_dmg"]
	if extreme:
		rate += (powers.get(&"conviction", 0) - p0.get(&"conviction", 0)) \
			* Powers.CONVICTION_ENERGY * ctx["dpe"]
	var str_turn: float = ctx["str_turn"] \
		+ (powers.get(&"detachment", 0) - p0.get(&"detachment", 0)) * Powers.DETACHMENT_STRENGTH
	var block_turn: float = ctx["block_turn"]
	if tier == PassionState.Tier.HOLLOW:
		block_turn += (powers.get(&"grounded", 0) - p0.get(&"grounded", 0)) * Powers.GROUNDED_BLOCK
	# Rallies reach every living enemy; cards shuffled in pile up in the player's deck.
	var rally := 0.0
	var curses := 0.0
	for f in foes:
		var m := _moves_of(f, f["phase"], f["strength"], _hp_frac(f))
		rally += m[3]
		curses += m[6]
	var pool := 0.0
	var order: Array = []  # [kill-order key, enemy, its segments]
	for f in foes:
		var segs := _segments(f, rally)
		for seg in segs:
			pool += seg[0]
		order.append([segs[0][1] / maxf(1.0, segs[0][0]), f, segs])
	rate = maxf(1.0, rate)
	var length := pool / rate
	# Strength gained every turn raises the rate as the fight goes on: use its average.
	rate += str_turn * ctx["hits_turn"] * (length + 1.0) / 2.0
	if curses > 0.0:
		rate *= ctx["deck_size"] / (ctx["deck_size"] + curses * length / 2.0)
	if line["pweak"] > 0:
		rate *= 1.0 - 0.25 * minf(line["pweak"], length) / maxf(1.0, length)
	rate = maxf(1.0, rate)
	# Drawn cards are worth something now only if energy is left to play them.
	var drawn_damage: float = minf(line["draws"] * ctx["avg_cost"], line["energy"]) * ctx["dpe"]
	order.sort_custom(func(a, b): return a[0] > b[0])
	var clock := 0.0
	var loss := 0.0
	var incoming := 0.0
	var first := true
	for entry in order:
		var f: Dictionary = entry[1]
		var segs: Array = entry[2]
		for si in segs.size():
			var seg: Array = segs[si]
			var hp_left: float = seg[0]
			if si == 0:
				hp_left = maxf(0.0, hp_left - _dot_damage(f))
				if first:
					hp_left = maxf(0.0, hp_left - drawn_damage)
			var kill_rate := maxf(0.25 * rate, rate - seg[3])
			var t: float
			if si == 0 and first and f["vuln"] > 0:
				var fast: float = 1.5 * kill_rate * f["vuln"]
				t = hp_left / (1.5 * kill_rate) if hp_left <= fast \
					else f["vuln"] + (hp_left - fast) / kill_rate
			else:
				t = hp_left / kill_rate
			var seg_start := clock
			clock += t
			var a: float = seg[1]
			var growth: float = seg[2]
			var attacks: float
			if si == 0:
				attacks = maxf(0.0, clock - 0.5)
				var spared: float = minf(f["stun"], attacks)
				loss -= a * spared
				loss -= 0.25 * a * minf(maxf(0.0, f["weak"] - spared), attacks - spared)
				if ctx["sight"] and f["next"] != null and f["stun"] == 0:
					loss += (_move_damage(f["next"], f["strength"]) - a) * minf(1.0, attacks)
				incoming += a
			else:
				attacks = maxf(0.0, clock - 0.5) - maxf(0.0, seg_start - 0.5)
				loss += seg[4]
			loss += a * attacks + growth * maxf(0.0, attacks * (attacks - 1.0) / 2.0)
		first = false
	var turns := maxf(0.0, clock - 0.5)
	var pp: int = line["ppoison"]
	loss += pp * (pp + 1) / 2.0
	loss -= minf(block_turn, incoming) * turns
	loss -= ctx["heal_turn"] * turns
	return maxf(0.0, loss)


## An enemy's remaining lifebars as [[HP, damage per turn, growth of that per turn, block and
## healing per turn, entry lash]]: the current bar with its block, then each bar still to come at
## that phase's moveset and entry Strength. Growth is the Strength it gains each turn, its own and
## rallied, times its hits per turn.
func _segments(f: Dictionary, rally: float) -> Array:
	var data: EnemyData = f["data"]
	var m := _moves_of(f, f["phase"], f["strength"], _hp_frac(f))
	var segs: Array = [[float(f["hp"] + f["block"]), m[0], (m[2] + rally) * m[1], m[4] + m[5], 0.0]]
	for p in range(f["phase"] + 1, data.phase_hps.size()):
		var strength: int = data.phase_enter_self_strength[p] \
			if data.phase_enter_self_strength.size() > p else 0
		var lash: float = float(data.phase_enter_damage[p]) \
			if data.phase_enter_damage.size() > p else 0.0
		var mp := _moves_of(f, p, strength, 1.0)
		segs.append([float(data.phase_hps[p]), mp[0], (mp[2] + rally) * mp[1], mp[4] + mp[5], lash])
	return segs


## Damage Poison and Chilled will take off an enemy on their own: Poison's falling ticks, and
## Chilled's chip each turn while it melts (a new freeze needs more chill, which is not assumed).
func _dot_damage(f: Dictionary) -> float:
	var p: int = f["poison"]
	return p * (p + 1) / 2.0 + CombatEngine.CHILL_CHIP * f["chilled"]


## The kill-order key: damage per turn per point of HP left. Highest goes first.
func _smith(f: Dictionary) -> float:
	return _attack_rate(f) / maxf(1.0, f["hp"] + f["block"])


## The enemy a single-target card goes at: the living one with the most damage per point of HP
## left, so the player removes damage as fast as it can; ties go to the one closest to falling.
func _focus_index(line: Dictionary) -> int:
	var foes: Array = line["foes"]
	var best := -1
	for i in foes.size():
		var f: Dictionary = foes[i]
		if f["dead"]:
			continue
		if best < 0:
			best = i
			continue
		var b: Dictionary = foes[best]
		var sf := _smith(f)
		var sb := _smith(b)
		if sf > sb or (sf == sb and f["hp"] + f["block"] < b["hp"] + b["block"]):
			best = i
	return best


## An enemy's average damage per turn at its current HP and Strength.
func _attack_rate(f: Dictionary) -> float:
	return _moves_of(f, f["phase"], f["strength"], _hp_frac(f))[0]


func _hp_frac(f: Dictionary) -> float:
	return float(f["hp"]) / maxf(1.0, f["max"])


## An enemy's moveset in a phase, averaged by weight over the moves it could pick at that HP:
## [damage per turn at that Strength, hits per turn, Strength it gains, Strength it rallies to
## every ally (itself included), block, healing, cards it shuffles into the player's deck].
## A moveset with no HP-gated moves gives the same answer at any HP, so it is kept per Strength.
func _moves_of(f: Dictionary, phase: int, strength: int, hp_frac: float) -> Array:
	var digest: Dictionary = _digest(f["data"], phase)
	var memo: Dictionary = digest["memo"]
	if not digest["banded"] and memo.has(strength):
		return memo[strength]
	var out := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var weight := 0.0
	for d in digest["moves"]:
		if hp_frac < d[1] - 0.0001 or hp_frac > d[2] + 0.0001:
			continue
		var w: float = d[0]
		weight += w
		var dmg := 0.0
		for part in d[3]:
			dmg += maxi(0, part[0] + strength) * part[1]
		out[0] += w * dmg
		for k in range(1, 7):
			out[k] += w * d[k + 3]
	if weight > 0.0:
		for k in 7:
			out[k] /= weight
	if not digest["banded"]:
		memo[strength] = out
	return out


## A phase's moves read once per combat: whether any move is HP-gated, each move as [weight, min
## HP fraction, max HP fraction, damage parts as [value, hits], hits, Strength gained, Strength
## rallied, block, healing, cards shuffled in], and a memo of averages by Strength.
func _digest(data: EnemyData, phase: int) -> Dictionary:
	if not _move_info.has(data):
		_move_info[data] = {}
	var by_phase: Dictionary = _move_info[data]
	if by_phase.has(phase):
		return by_phase[phase]
	var moves: Array = data.phase_movesets[phase] if data.phase_movesets.size() > phase else data.moves
	var out: Array = []
	var banded := false
	for m in moves:
		if m.min_hp_percent > 0.0 or m.max_hp_percent < 1.0:
			banded = true
		var parts: Array = []
		var hits := 0
		var self_str := 0
		var ally_str := 0
		var block := 0
		var heal := 0
		var curses := 0
		for e in m.effects:
			if e is DamageEffect:
				if e.apply_to_source:
					# A blow that costs its user: HP it loses each turn it throws it, which the
					# race counts as healing below zero on its own bar.
					heal -= e.value
				else:
					parts.append([e.value, e.hits])
					hits += e.hits
			elif e is StatusApplyEffect and e.status_effect == StatusEffects.STRENGTH:
				if e.apply_to_allies:
					ally_str += e.value
				elif e.apply_to_source:
					self_str += e.value
			elif e is BlockEffect:
				block += e.value
			elif e is HealEffect and e.apply_to_source:
				heal += e.value
			elif e is AddCardEffect:
				curses += 1
			elif e is StatusApplyEffect and e.status_effect == StatusEffects.POISON \
					and not e.apply_to_source and not e.apply_to_allies:
				parts.append([e.value * (e.value + 1) / 2, 1])  # every tick it will deal
		out.append([m.weight, m.min_hp_percent, m.max_hp_percent, parts, hits, self_str, ally_str,
			block, heal, curses])
	var digest := {"banded": banded, "moves": out, "memo": {}}
	by_phase[phase] = digest
	return digest


func _move_damage(m: EnemyMove, strength: int) -> float:
	var d := 0.0
	for e in m.effects:
		if e is DamageEffect and not e.apply_to_source:
			d += maxi(0, e.value + strength) * e.hits
	return d


## What does not change while a turn is planned: where HP starts, the Passion meter's shape,
## the player's damage rate for the race estimate, and what relics and powers already give
## each turn. The damage rate is the deck's: every attack's damage per energy at the current
## Strength, zone and title bonus, against an unguarded target (a free card counts as half an
## energy), spent at a turn's full energy. Once the player has turns behind it in this combat,
## what it actually dealt is blended in, the deck's figure weighing as one turn. The deck's
## figures are read once per turn (_turn_rates); the rest is current.
func _context(eng: CombatEngine, commit: bool, commit_target: int) -> Dictionary:
	var ps := eng.player_stats
	var ctx: Dictionary = _turn_rates(eng).duplicate()
	var passion0: int = RunManager.passion.current_value if RunManager.passion else 0
	var pole_dir := 0
	if commit and RunManager.passion:
		if commit_target >= 0 and passion0 < commit_target:
			pole_dir = 1
		elif commit_target < 0 and passion0 > commit_target:
			pole_dir = -1
		if pole_dir != 0:
			var any := false
			for c in eng.piles.hand:
				if signi(_passion_gain(c)) == pole_dir and not c.unplayable \
						and c.energy_cost <= eng.energy:
					any = true
			if not any:
				pole_dir = 0
	var character := RunManager.current_character
	ctx["start_hp"] = float(ps.current_hp)
	ctx["sight"] = RunManager.has_excalibur() \
		and RunManager.excalibur_mode == RunManager.ExcaliburMode.SIGHT
	ctx["control_heal"] = character.control_heal if character else 0
	ctx["volatility"] = character.passion_volatility if character else 1.0
	ctx["pmin"] = RunManager.passion.min_value if RunManager.passion else -100
	ctx["pmax_passion"] = RunManager.passion.max_value if RunManager.passion else 100
	ctx["center"] = RunManager.passion_center()
	ctx["sword"] = eng.sword_bonus()
	ctx["momentum_per_hit"] = eng._momentum_per_hit
	ctx["pole_dir"] = pole_dir
	ctx["pole_target"] = commit_target
	ctx["passion0"] = passion0
	return ctx


var _rates_combat := 0
var _rates_turn := -1
var _rates := {}


func _turn_rates(eng: CombatEngine) -> Dictionary:
	if _rates_combat == eng.get_instance_id() and _rates_turn == eng.turn_number:
		return _rates
	var ps := eng.player_stats
	var tier := RunManager.get_passion_tier()
	var extreme := tier == PassionState.Tier.BLAZING or tier == PassionState.Tier.HOLLOW
	var deck: Array = []
	deck.append_array(eng.piles.hand)
	deck.append_array(eng.piles.draw_pile)
	deck.append_array(eng.piles.discard_pile)
	var total_cost := 0.0
	var dmg := 0.0
	var hits := 0.0
	var multi_cards := 0.0
	var multi_hit := 0.0
	var count := 0
	for c in deck:
		if c.unplayable:
			continue
		count += 1
		total_cost += CombatEngine.MAX_ENERGY if c.x_cost else maxf(0.5, c.energy_cost)
		if c.card_type != CardData.CardType.ATTACK:
			continue
		var r := _neutral_damage(eng, c)
		dmg += r[0]
		hits += r[1]
		if r[1] > 1:
			multi_cards += 1.0
			multi_hit += float(r[0]) / r[1]
	var energy: float = CombatEngine.MAX_ENERGY
	if extreme:
		energy += ps.get_power_stacks(Powers.CONVICTION) * Powers.CONVICTION_ENERGY
	var dpe := dmg / total_cost if total_cost > 0.0 else 0.0
	var d0 := energy * dpe
	var block_turn := 0.0
	var heal_turn := 0.0
	var str_turn: float = ps.get_power_stacks(Powers.DETACHMENT) * Powers.DETACHMENT_STRENGTH
	if tier == PassionState.Tier.HOLLOW:
		block_turn += ps.get_power_stacks(Powers.GROUNDED) * Powers.GROUNDED_BLOCK
	for r in RunManager.relics:
		if r.trigger != RelicData.RelicTrigger.ON_TURN_START:
			continue
		match r.effect:
			RelicData.RelicEffect.GAIN_BLOCK: block_turn += r.value
			RelicData.RelicEffect.HEAL: heal_turn += r.value
			RelicData.RelicEffect.GAIN_STRENGTH: str_turn += r.value
	var powers0 := {}
	for p in ps.powers:
		powers0[p.id] = ps.powers[p]
	_rates = {
		"D": (d0 + _dealt) / (1.0 + _turns_seen) if eng.get_instance_id() == _combat_id else d0,
		"dpe": dpe,
		"hits_turn": energy * hits / total_cost if total_cost > 0.0 else 0.0,
		"multi_turn": energy * multi_cards / total_cost if total_cost > 0.0 else 0.0,
		"multi_hit_dmg": multi_hit / multi_cards if multi_cards > 0.0 else 0.0,
		"avg_cost": total_cost / count if count > 0 else 1.0,
		"deck_size": float(maxi(1, count)),
		"str0": ps.get_status_stacks(StatusEffects.STRENGTH),
		"powers0": powers0, "block_turn": block_turn, "heal_turn": heal_turn,
		"str_turn": str_turn,
	}
	_rates_combat = eng.get_instance_id()
	_rates_turn = eng.turn_number
	return _rates


## An attack's [damage, hits] against an unguarded, unafflicted target at the current state, for
## the deck's damage rate and the canonical play order.
func _neutral_damage(eng: CombatEngine, card: CardData) -> Array:
	if card.card_type != CardData.CardType.ATTACK:
		return [0, 0]
	var ps := eng.player_stats
	var tier := RunManager.get_passion_tier()
	var dmg := 0
	var hits := 0
	for e in card.get_active_effects():
		if not e is DamageEffect:
			continue
		var n: int = e.hits
		if e.x_scaled:
			n = CombatEngine.MAX_ENERGY
		if n > 1 and tier == PassionState.Tier.BLAZING:
			n += ps.get_power_stacks(Powers.OVERFLOW)
		var per: int = e._effective_value() + ps.get_status_stacks(StatusEffects.STRENGTH)
		if ps.has_status(StatusEffects.WEAK):
			per = int(per * 0.75)
		per = int((per + eng.sword_bonus()) * _zone_at(card.personality, tier))
		dmg += maxi(0, per) * n
		hits += n
	return [dmg, hits]


## CombatEngine.zone_multiplier at a given tier rather than the meter's current one.
func _zone_at(pers: CardData.PersonalityType, tier: int) -> float:
	if pers == CardData.PersonalityType.NEUTRAL or pers == CardData.PersonalityType.NEGATIVE:
		return 1.0
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
		_:
			return 1.0
	var on_type := (pers == CardData.PersonalityType.PRIMARY) == primary_favored
	if on_type:
		return CombatEngine.ZONE_LEAN_BONUS if lean else CombatEngine.ZONE_EXTREME_BONUS
	return CombatEngine.ZONE_LEAN_PENALTY if lean else CombatEngine.ZONE_EXTREME_PENALTY


# ============================================================
# SMALL HELPERS
# ============================================================

## The HP and block still standing between the player and a win: every enemy's current bar and
## every bar to come.
func _pool_total(line: Dictionary) -> float:
	var total := 0.0
	for f in line["foes"]:
		if f["dead"]:
			continue
		total += f["hp"] + f["block"]
		var data: EnemyData = f["data"]
		for p in range(f["phase"] + 1, data.phase_hps.size()):
			total += data.phase_hps[p]
	return total


func _all_down(line: Dictionary) -> bool:
	for f in line["foes"]:
		if not f["dead"]:
			return false
	return true


func _blocks_or_heals(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is BlockEffect or e is HealEffect:
			return true
	return false


func _applies_to_enemy(c: CardData, status: StatusEffectData) -> bool:
	for e in c.get_active_effects():
		if e is StatusApplyEffect and not e.apply_to_source and e.status_effect == status:
			return true
	return false


func _debuffs_enemies(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is StatusApplyEffect and not e.apply_to_source:
			return true
	return false


func _passion_gain(c: CardData) -> int:
	var total := 0
	for e in c.get_active_effects():
		if e is PassionEffect:
			total += e.value
	return total


func _living(eng: CombatEngine) -> Array[EnemyCombatState]:
	var out: Array[EnemyCombatState] = []
	for en in eng.enemies:
		if not en.stats.is_dead():
			out.append(en)
	return out
