extends Node
## Run-layer balance harness — the whole-run companion to combat_harness.
##
## Walks a representative Act-1 node sequence with the REAL systems: EnemyPool
## encounters, the shared HarnessCombat policy over the real CombatEngine, CardPool
## reward drafting, EventPool events, and RunManager state (HP / gold / Passion / deck)
## PERSISTING across nodes exactly as in a real run. Non-combat nodes are resolved by
## decision policies operating on the real pools — not by clicking UI.
##
## It answers the questions the playtest raised: does a demo run traverse the Passion
## tiers, arrive at the boss committed and at a sane HP, and actually spend its gold?
##
## Run headless:
##   godot --headless --path D:\Applications\Fable res://tools/run_harness.tscn
##
## MODEL of a Water-committing player (the shared planning policy) — sets bands; playtest finalizes.

const RUNS := 100
const MAX_TURNS := 60
const COMMIT_TARGET := 50

## A plausible Act-1 layout (StS-shaped): hallway fights, 2 elites, 2 events, 2 rests,
## 1 shop, the Sword-in-the-Stone guardian at centre, 1 boss. Floor = index + 1 (drives
## encounter scaling + the curated lone-Knight opener on floor 1).
const LAYOUT := [
	"combat", "combat", "event", "combat", "elite",
	"rest", "sword", "shop", "event", "combat",
	"elite", "rest", "combat", "boss",
]

var _cbt := HarnessCombat.new()
var _character: CharacterData
var _aborted := false  # set when a combat passes the memory ceiling


func _ready() -> void:
	# No sound: every play() here would be kept until the run ends (see AudioManager.enabled).
	AudioManager.enabled = false
	print("\n===============================================================")
	print(" Fable RUN harness — %d runs, real Act-1 walk (%d nodes)" % [RUNS, LAYOUT.size()])
	print("===============================================================")
	_character = _build_emo_hybrid()

	var agg := _fresh_agg()
	for r in RUNS:
		_walk_run(r, agg)
		if _aborted:
			print("\n== run harness ABORTED at the memory ceiling in run %d; no report ==\n" % r)
			return
	_report(agg)

	print("\n  %s" % _cbt.memory_summary())
	print("\n== run harness done ==\n")
	get_tree().quit()


# ============================================================
# ONE RUN
# ============================================================

func _walk_run(seed_val: int, agg: Dictionary) -> void:
	RunManager.start_run(_character, seed_val)

	var tiers_seen := {}
	var min_p := 0
	var max_p := 0
	var died_floor := -1
	var boss_start_hp := -1
	var gold_spent := 0

	for i in LAYOUT.size():
		var node: String = LAYOUT[i]
		var floor_num := i + 1
		match node:
			"combat", "elite", "boss":
				if node == "boss":
					boss_start_hp = RunManager.current_hp
				var enemies := _encounter(node, floor_num)
				var won := _run_combat(enemies)
				if not won:
					died_floor = floor_num
				else:
					_award_gold(node, floor_num)
					if node == "elite" or node == "boss":
						_award_relic(node == "boss")  # StS: a relic per elite + boss
					if node != "boss":
						_draft_reward()
			"sword":
				# Sword-in-the-Stone guardian: beat the Beast at the Stone mid-run to EARN
				# Excalibur (it's no longer a free pickup). Losing here ends the run.
				# The reward is the event's "Take up Excalibur", applied in the event's order:
				# +3 Passion, The Sword's Bearer, then the relic. The player then wears the
				# title, since nothing else this harness models competes for a slot.
				if _run_combat(EnemyPool.get_sword_guardian()):
					RunManager.change_passion(3)
					RunManager.award_title(&"swords_bearer")
					RunManager.add_relic(RelicPool.get_relic_by_name("Excalibur"))
					RunManager.equip_title(0, &"swords_bearer")
				else:
					died_floor = floor_num
			"rest":
				_rest_action()
			"shop":
				gold_spent += _shop_action()
			"event":
				_event_action()

		# Sample Passion after every node.
		var p := RunManager.passion.current_value
		min_p = mini(min_p, p)
		max_p = maxi(max_p, p)
		tiers_seen[RunManager.get_passion_tier()] = true
		if died_floor >= 0 or _aborted:
			break

	# Fold this run into the aggregate.
	var reached_boss := died_floor < 0
	agg["wins"] += 1 if reached_boss else 0
	if died_floor >= 0:
		agg["deaths"].append(died_floor)
	agg["end_hp"] += RunManager.current_hp
	agg["min_p"] += min_p
	agg["max_p"] += max_p
	agg["tiers"] += tiers_seen.size()
	agg["end_tier"][RunManager.get_passion_tier()] += 1
	if boss_start_hp >= 0:
		agg["boss_hp_sum"] += boss_start_hp
		agg["boss_hp_n"] += 1
		agg["boss_passion_sum"] += RunManager.passion.current_value
	agg["gold_earned"] += RunManager.run_stats.get("gold_earned", 0)
	agg["gold_spent"] += gold_spent
	agg["gold_end"] += RunManager.gold
	agg["deck_size"] += RunManager.current_deck.size()


## Drives one combat with the shared policy over the real engine. Persists the
## post-fight HP; Passion is mutated live on RunManager by the played cards.
func _run_combat(enemies: Array[EnemyData]) -> bool:
	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)
	var deck: Array[CardData] = []
	for c in RunManager.current_deck:
		deck.append(c.duplicate_card())
	eng.start_combat(deck, RunManager.current_hp, RunManager.max_hp, enemies)

	var guard := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and eng.turn_number < MAX_TURNS:
		guard += 1
		if guard > 400:
			break
		_cbt.play_turn(eng, true, COMMIT_TARGET)  # commit=true: a Water-pole player
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		eng.end_player_turn()

	var won := eng.phase == CombatEngine.Phase.BATTLE_WON
	RunManager.current_hp = maxi(0, eng.player_stats.current_hp)
	if won:
		eng.process_combat_end_relics()  # combat-end heals/gold apply to the post-fight HP
	eng.free()
	if not _cbt.within_memory_ceiling("run %d, after a combat" % RngManager.run_seed):
		_aborted = true
		get_tree().quit(1)
	return won


func _encounter(node: String, floor_num: int) -> Array[EnemyData]:
	match node:
		"elite":
			return EnemyPool.get_elite_encounter()
		"boss":
			return EnemyPool.get_boss()
		_:
			return EnemyPool.get_combat_encounter(floor_num)


## A relic reward after an elite/boss (the real reward flow offers 3; we take the
## first offered = average luck, not best-case, so sustain isn't over-modelled) —
## skipping only a relic that would fight the modeled build's pole (see below).
func _award_relic(is_boss: bool) -> void:
	var owned := RunManager.get_owned_relic_names()
	var choices: Array[RelicData]
	if is_boss:
		choices = RelicPool.get_boss_reward_choices(RngManager.loot_rng, owned)
	else:
		choices = RelicPool.get_reward_choices(RngManager.loot_rng, 3, owned)
	for c in choices:
		if not _relic_against_commit(c):
			RunManager.add_relic(c)
			return
	if choices.size() > 0:
		RunManager.add_relic(choices[0])


## True if a relic swings Passion the WRONG way for the modeled Water-commit build (an
## ON_TURN_START −Passion relic like Leaden Vow). A real Water player would never draft
## it, so the model shouldn't either — otherwise the swing gear pollutes the passion arc.
func _relic_against_commit(r: RelicData) -> bool:
	return r.trigger == RelicData.RelicTrigger.ON_TURN_START \
		and r.effect == RelicData.RelicEffect.GAIN_PASSION \
		and signi(r.value) != signi(COMMIT_TARGET)


## Post-combat gold, mirroring map_scene's scaling.
func _award_gold(node: String, floor_num: int) -> void:
	var g := 16 + floor_num * 2
	if node == "elite":
		g = 34 + floor_num * 2
	elif node == "boss":
		g = 50 + floor_num * 2
	RunManager.add_gold(g)


# ============================================================
# NON-COMBAT NODE POLICIES
# ============================================================

## Draft the strongest offered card for a Water build (prefer the water pole,
## then rarity). A demo player almost always takes a card, so we never skip.
func _draft_reward() -> void:
	var choices := CardPool.get_reward_choices(RngManager.loot_rng)
	var best := _best_card(choices)
	if best != null:
		RunManager.add_card_to_deck(best)


## Rest: heal if wounded, otherwise upgrade the costliest un-upgraded card.
func _rest_action() -> void:
	if RunManager.current_hp < int(0.6 * RunManager.max_hp):
		RunManager.heal(int(0.3 * RunManager.max_hp))
		return
	var best: CardData = null
	for c in RunManager.current_deck:
		if c.upgraded:
			continue
		if best == null or c.energy_cost > best.energy_cost:
			best = c
	if best != null:
		best.upgrade_card()
	else:
		RunManager.heal(int(0.3 * RunManager.max_hp))


## Shop: buy the best affordable relic first (the high-value purchase), then up to two
## cards. Uses the REAL shop_scene prices — cards 40/60/90, relics 100/150/200 by
## rarity — so the economy readout reflects the actual sinks. Returns gold spent.
func _shop_action() -> int:
	var spent := 0
	var owned := RunManager.get_owned_relic_names()
	for r in RelicPool.get_reward_choices(RngManager.loot_rng, 2, owned):
		if _relic_against_commit(r):
			continue
		var rp := _relic_price(r)
		if RunManager.gold >= rp:
			RunManager.gold -= rp
			spent += rp
			RunManager.add_relic(r)
			break  # one relic per shop is plenty
	var wares := CardPool.get_reward_choices(RngManager.loot_rng, 5)
	wares.sort_custom(func(a, b): return _card_score(a) > _card_score(b))
	var bought := 0
	for w in wares:
		if bought >= 2:
			break
		var price := _card_price(w)
		if RunManager.gold >= price:
			RunManager.gold -= price
			spent += price
			RunManager.add_card_to_deck(w)
			bought += 1
	return spent


func _relic_price(r: RelicData) -> int:
	match r.rarity:
		RelicData.RelicRarity.RARE: return 200
		RelicData.RelicRarity.UNCOMMON: return 150
		_: return 100


## Event: pick the best choice by a simple value heuristic (guarded against death /
## unaffordable gold costs), then apply its effects through RunManager.
func _event_action() -> void:
	var ev := EventPool.get_random_event(RngManager.event_rng)
	var best: EventData.EventChoice = null
	var best_score := -999999
	for choice in ev.choices:
		var s := _event_score(choice)
		if s > best_score:
			best_score = s
			best = choice
	if best == null:
		return
	# Apply. HP is applied directly (events bypass block), clamped; gold/passion/max_hp
	# through the normal paths; card_reward/remove_card mutate the deck.
	if best.max_hp_change != 0:
		RunManager.max_hp += best.max_hp_change
	RunManager.current_hp = clampi(RunManager.current_hp + best.hp_change, 0, RunManager.max_hp)
	if best.gold_change != 0:
		if best.gold_change > 0:
			RunManager.add_gold(best.gold_change)
		else:
			RunManager.gold = maxi(0, RunManager.gold + best.gold_change)
	if best.passion_change != 0:
		RunManager.change_passion(best.passion_change)
	if best.card_reward:
		_draft_reward()
	if best.remove_card and RunManager.current_deck.size() > 1:
		RunManager.remove_card_from_deck(_worst_card_index())


func _event_score(choice: EventData.EventChoice) -> int:
	# Unaffordable gold cost or a lethal HP hit → hard no.
	if choice.gold_change < 0 and RunManager.gold < -choice.gold_change:
		return -999998
	if RunManager.current_hp + choice.hp_change <= 0:
		return -999997
	var s := 0
	s += 50 if choice.card_reward else 0
	s += 15 if choice.remove_card else 0
	s += choice.gold_change
	s += choice.max_hp_change * 3
	s += choice.hp_change            # negative HP hurts
	s += choice.passion_change       # a Water build likes + Passion
	return s


# ============================================================
# CARD SCORING (Water-build draft heuristic)
# ============================================================

func _best_card(choices: Array[CardData]) -> CardData:
	var best: CardData = null
	for c in choices:
		if best == null or _card_score(c) > _card_score(best):
			best = c
	return best


func _card_score(c: CardData) -> int:
	var s := int(c.rarity) * 10
	if c.personality == CardData.PersonalityType.PRIMARY:
		s += 100    # commit to Water
	elif c.personality == CardData.PersonalityType.SECONDARY:
		s -= 40     # off-pole
	elif _grants_block(c):
		s += 55     # glass Water still values a little neutral defense to survive
	return s


## True if a card grants any Block — the survival floor a committed Water drafter still
## reaches for (Shield Wall / Phantom Guard / Bracing Blow), since the Water pole itself
## no longer carries block.
func _grants_block(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is BlockEffect:
			return true
	return false


func _card_price(c: CardData) -> int:
	match c.rarity:
		CardData.CardRarity.RARE: return 90
		CardData.CardRarity.UNCOMMON: return 60
		_: return 40


## Index of the least-wanted deck card to remove (a basic Strike/Defend first).
func _worst_card_index() -> int:
	for i in RunManager.current_deck.size():
		var n: String = RunManager.current_deck[i].card_name
		if n == "Strike" or n == "Defend":
			return i
	return 0


# ============================================================
# AGGREGATION + REPORT
# ============================================================

func _fresh_agg() -> Dictionary:
	return {
		"wins": 0, "deaths": [], "end_hp": 0, "min_p": 0, "max_p": 0, "tiers": 0,
		"end_tier": [0, 0, 0, 0, 0],  # HOLLOW..BLAZING
		"boss_hp_sum": 0, "boss_hp_n": 0, "boss_passion_sum": 0,
		"gold_earned": 0, "gold_spent": 0, "gold_end": 0, "deck_size": 0,
	}


func _report(a: Dictionary) -> void:
	var n := float(RUNS)
	print("\nCLEAR RATE (reached + beat the Act-1 boss): %.0f%% (%d/%d)" % [
		100.0 * a["wins"] / n, a["wins"], RUNS])
	if a["deaths"].size() > 0:
		var hist := {}
		for f in a["deaths"]:
			hist[f] = hist.get(f, 0) + 1
		var floors: Array = hist.keys()
		floors.sort()
		var parts: PackedStringArray = []
		for f in floors:
			parts.append("f%d (%s): %d" % [f, LAYOUT[f - 1], hist[f]])
		print("  deaths by floor: %s" % ", ".join(parts))

	print("\nPASSION ARC (the playtest's main gripe — did it move?):")
	print("  distinct tiers visited / run: %.1f of 5" % (float(a["tiers"]) / n))
	print("  swing per run: avg low %.0f  ->  avg high %.0f" % [
		float(a["min_p"]) / n, float(a["max_p"]) / n])
	if a["boss_hp_n"] > 0:
		print("  Passion at the boss: avg %.0f (%s)" % [
			float(a["boss_passion_sum"]) / a["boss_hp_n"],
			_tier_name(int(round(float(a["boss_passion_sum"]) / a["boss_hp_n"])))])
	var tnames := ["Hollow", "Wavering", "Steady", "Inspired", "Blazing"]
	var parts: PackedStringArray = []
	for t in 5:
		parts.append("%s %d%%" % [tnames[t], int(round(100.0 * a["end_tier"][t] / n))])
	print("  end-of-run tier mix: %s" % ", ".join(parts))

	print("\nHP / SURVIVAL:")
	if a["boss_hp_n"] > 0:
		print("  HP arriving at the boss: avg %.0f / 80" % (float(a["boss_hp_sum"]) / a["boss_hp_n"]))
	print("  HP at run end (winners incl.): avg %.0f / 80" % (float(a["end_hp"]) / n))

	print("\nECONOMY (playtest: 'no gold spent'):")
	print("  gold earned/run %.0f  ·  spent %.0f  ·  leftover at end %.0f" % [
		float(a["gold_earned"]) / n, float(a["gold_spent"]) / n, float(a["gold_end"]) / n])
	print("  final deck size: avg %.1f cards (started 9)" % (float(a["deck_size"]) / n))


func _tier_name(v: int) -> String:
	return PassionState.tier_name(RunManager.get_passion_tier_for_value(v))


# ============================================================
# CHARACTER (mirrors the real Emo Hybrid; shares CardPool pools)
# ============================================================

func _build_emo_hybrid() -> CharacterData:
	return CharacterPool.build_emo_hybrid()


func _fresh_deck() -> Array[CardData]:
	return CharacterPool.emo_starting_deck()


func _mk(card_name: String, cost: int, type: CardData.CardType,
		target: CardData.TargetType, effects: Array) -> CardData:
	var c := CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = type
	c.target_type = target
	for e in effects:
		c.effects.append(e)
	return c


func _dmg(v: int, hits: int = 1) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.hits = hits
	return e


func _block(v: int) -> BlockEffect:
	var e := BlockEffect.new()
	e.value = v
	return e


func _status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e


func _passion(v: int) -> PassionEffect:
	var e := PassionEffect.new()
	e.value = v
	return e
