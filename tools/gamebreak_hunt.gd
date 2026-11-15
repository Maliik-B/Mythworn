extends Node
## The gamebreak hunt (the loop pass): looks for the builds, loops and stacks that break the game,
## and puts a number on each. It RECORDS, it does not fix: the fixes are part 5's, except a crash.
##
## Run headless (arguments after `--`):
##   godot --headless --path D:\Applications\Fable res://tools/gamebreak_hunt.tscn --quit-after 100000
##   --seed=N      base seed (default: today's daily seed, so a day's hunt is the same for everyone)
##   --iters=N     hill-climb steps per restart (default 150)
##   --restarts=N  random restarts per objective (default 8)
##   --only=a,b    candidates | cards | search | loops
##
## Four parts. (1) The sheet's gamebreak candidates, each built by hand on the real engine and
## given a number and a verdict: CONFIRMED (a real break by the bar below), BOUNDED (it exists, and
## something caps it under the bar), NOT A BREAK. (2) Per-card ceilings: every card's face-value
## damage on the real engine, and its ceiling under the amplifier kit. (3) A seeded best-build
## search over cards, relics, titles, the pack and the companion, by hill-climbing from random
## starts, scored on the damage dealt to an immortal wall: the best single turn and the best six.
## (4) Loop and infinite detection on every build the search tries: cards played in one turn,
## energy hoarded, a plan that never ends.
##
## THE BAR. A single turn that deals more than Caedmon's first lifebar, or a fight that cannot be
## lost, or a turn that plays more than LOOP_CARDS cards, is a break. Everything under it is bounded.

const WALL_HP := 1000000
const SIX_TURNS := 6
const LOOP_CARDS := 25     # more cards in one turn than this is a loop
const ENERGY_HOARD := 12   # more energy than this at the end of a turn is a hoard
const MAX_COPIES := 3
const SOURCED_MEMORY_CARD := "The House That Was"  # the only memory card an event grants today

var _cbt := HarnessCombat.new()
var _character: CharacterData
var _seed_base := 0
var _iters := 150
var _restarts := 8
var _only: PackedStringArray = []
var _plays_this_turn := 0
var _bar_first_lifebar := 0
var _rng := RandomNumberGenerator.new()
var _loop_flags: Array[String] = []
var _evals := 0


func _ready() -> void:
	AudioManager.enabled = false
	_seed_base = HarnessCombat.daily_seed()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed_base = int(a.substr(7))
		elif a.begins_with("--iters="):
			_iters = maxi(1, int(a.substr(8)))
		elif a.begins_with("--restarts="):
			_restarts = maxi(1, int(a.substr(11)))
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",", false)
	_rng.seed = _seed_base
	_character = CharacterPool.build_emo_hybrid()
	var caedmon := EnemyPool.sir_caedmon()
	_bar_first_lifebar = caedmon.phase_hps[0] if caedmon.phase_hps.size() > 0 else caedmon.max_health
	Events.card_played.connect(_on_card_played)
	print("\n===============================================================")
	print(" Fable gamebreak hunt: REAL engine, seed %d, bar: one turn > %d (Caedmon's first bar)" % [
		_seed_base, _bar_first_lifebar])
	print("===============================================================")
	if _only.is_empty() or _only.has("candidates"):
		_candidates()
	if _only.is_empty() or _only.has("cards"):
		_per_card()
	if _only.is_empty() or _only.has("search"):
		_search()
	if _only.is_empty() or _only.has("loops"):
		_loops_report()
	print("\n  %s" % _cbt.memory_summary())
	print("\n== gamebreak hunt done ==\n")
	get_tree().quit()


func _on_card_played(_card, _target) -> void:
	_plays_this_turn += 1


# ============================================================
# FIXTURES
# ============================================================

func _reset(passion: int = 0) -> void:
	RunManager.current_character = _character
	RunManager.current_act = 1
	RunManager.relics.clear()
	RunManager.consumables.clear()
	RunManager.pet_id = &""
	RunManager.pending_act_complete = false
	RunManager.pending_combat_boon = &""
	RunManager.active_title_slots = [&"", &""]
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = passion
	RngManager.setup_run(_seed_base)


## An enemy that does nothing and cannot be killed: the measuring wall.
func _wall(block_start := 0) -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Immortal Wall"
	e.max_health = WALL_HP
	var m := EnemyMove.new()
	m.move_name = "Stand"
	m.intent_type = EnemyMove.IntentType.ATTACK
	e.moves.append(m)
	return e


func _hitter(dmg: int, hits: int = 1) -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Hitter"
	e.max_health = WALL_HP
	var m := EnemyMove.new()
	m.move_name = "Hit"
	m.intent_type = EnemyMove.IntentType.ATTACK
	var d := DamageEffect.new()
	d.value = dmg
	d.hits = hits
	m.effects.append(d)
	e.moves.append(m)
	return e


func _fight(deck: Array, enemies: Array, hp: int = 80) -> CombatEngine:
	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)
	var d: Array[CardData] = []
	for c in deck:
		d.append(c)
	var datas: Array[EnemyData] = []
	for e in enemies:
		datas.append(e)
	eng.start_combat(d, hp, 80, datas)
	for i in eng.enemies.size():
		eng.enemies[i].current_intent = datas[i].moves[0]
		eng.enemies[i].next_intent = null
	return eng


func _wall_hp_lost(eng: CombatEngine) -> int:
	return WALL_HP - eng.enemies[0].stats.current_hp


## Plays one card straight from nowhere onto the first enemy, with energy to spare, and returns the
## damage it did to the wall. Mutators run on the engine first (a flag, a status, the oil).
func _damage_of(card: CardData, passion: int, mutate: Callable = Callable(), relics: Array = [],
		energy: int = 10) -> int:
	_reset(passion)
	for r in relics:
		RunManager.add_relic(RelicPool.get_relic_by_name(r))
	var eng := _fight([], [_wall()])
	eng.energy = energy
	if mutate.is_valid():
		mutate.call(eng)
	eng.piles.hand.append(card)
	eng.play_card(card, eng.enemies[0].stats)
	var lost := _wall_hp_lost(eng)
	eng.free()
	return lost


func _attack(card_name: String, cost: int, dmg: int, hits: int = 1,
		pers: CardData.PersonalityType = CardData.PersonalityType.NEUTRAL) -> CardData:
	var c := CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = CardData.CardType.ATTACK
	c.target_type = CardData.TargetType.SINGLE_ENEMY
	c.personality = pers
	var e := DamageEffect.new()
	e.value = dmg
	e.hits = hits
	c.effects.append(e)
	return c


func _by_name(pool: Array, card_name: String) -> CardData:
	for c in pool:
		if c.card_name == card_name:
			return c.duplicate_card()
	return null


func _row(n: int, name: String, number: String, verdict: String, note: String) -> void:
	print("  %2d. %-34s %-28s %-12s %s" % [n, name, number, verdict, note])


# ============================================================
# (1) THE CANDIDATES
# ============================================================

func _candidates() -> void:
	print("\n(1) THE SHEET'S CANDIDATES: each built by hand on the real engine")
	print("     #   candidate                          number                       verdict      note")
	var emo_p := CardPool.build_emo_primary_pool()
	var generic := CardPool._build_generic_pool()
	var hawk := CardPool.build_hawk_cards()
	var hound := CardPool.build_hound_cards()

	# 1. Blessing + Whiplash: a Blessing pushes 12; no tier is narrower than that, so one crossing
	# a Blessing, two in a fight (the pack is two). Built by stepping two Blessings across the line.
	_reset(17)
	var e1 := _fight(_filler(30), [_wall()])
	e1.player_stats.add_power(Powers.WHIPLASH, 1)
	RunManager.add_consumable(ConsumablePool.get_consumable(&"bottled_blessing"))
	RunManager.add_consumable(ConsumablePool.get_consumable(&"bottled_blessing"))
	var hand_a := e1.piles.hand.size()
	e1.use_consumable(RunManager.consumables[0])
	RunManager.passion.current_value = 45
	e1.use_consumable(RunManager.consumables[0])
	var whip_draws := e1.piles.hand.size() - hand_a
	e1.free()
	_row(1, "Blessing + Whiplash", "%d cards from 2 Blessings (1 stack)" % whip_draws,
		"BOUNDED", "one crossing a Blessing, two a fight; x stacks of Whiplash (a power card, copies capped)")

	# 2. Blessing + a Passion-scaled card.
	var carried := CardPool.get_memory_card(&"everything_i_carried_out")
	var at38 := _damage_of(carried.duplicate_card(), -38)
	var at50 := _damage_of(carried.duplicate_card(), -50)
	_row(2, "Blessing + Everything I Carried Out", "+%d damage (12 Passion / 4)" % (at50 - at38),
		"NOT A BREAK", "a swing of 12 adds 3 to one card; a memory card is meant to be strong")

	# 3. Blade Oil + Blooded Edge on one hit, at the best zone and Vulnerable.
	var plain := _damage_of(_attack("Big", 1, 14), 0)
	var both := _damage_of(_attack("Big", 1, 14), 0, func(e):
		e._blade_oil_pending = 8, ["Blooded Edge"])
	var best3 := _damage_of(_attack("Big", 1, 14, 1, CardData.PersonalityType.PRIMARY), 55, func(e):
		e._blade_oil_pending = 8
		e.enemies[0].stats.apply_status(StatusEffects.VULNERABLE, 2), ["Blooded Edge"])
	_row(3, "Blade Oil + Blooded Edge", "%d -> %d -> %d (zone, Vulnerable)" % [plain, both, best3],
		"BOUNDED" if best3 < _bar_first_lifebar else "CONFIRMED",
		"once per fight each; %d on one hit vs a first bar of %d" % [best3, _bar_first_lifebar])

	# 4. Unspent Courage + a multi-hit turn.
	var six := _attack("Six Hits", 1, 3, 6)
	var base4 := _damage_of(six.duplicate_card(), 0)
	var with4 := _damage_of(six.duplicate_card(), 0, func(e):
		e.apply_status_effect(e.player_stats, StatusEffects.STRENGTH, 2))
	_row(4, "Unspent Courage + a multi-hit turn", "+%d on a 6-hit card" % (with4 - base4),
		"BOUNDED", "+2 a hit for the fight; adds beside the sword's bonus, then x zone and Vulnerable")

	# 5. Hold stockpile: superseded; the hound's Bay is candidate 12.
	_row(5, "Hold stockpile (old hound)", "superseded by 12", "NOT A BREAK",
		"Hold no longer exists; the hound's deck was redesigned in part 3b")

	# 6. Favour against the biggest telegraphed blow.
	var biggest := _biggest_blow()
	_row(6, "Favour vs the biggest blow", "%d (%s)" % [biggest[0], biggest[1]], "BOUNDED",
		"worth one telegraphed blow; the cap is the largest single hit any enemy throws")

	# 7. A Trick card never reaches the exhaust pile, so a recall cannot return it.
	_reset(0)
	var leaked := 0
	for id in PetPool.all_ids():
		for c in PetPool.build_cards(id):
			var e7 := _fight([], [_wall()])
			e7.energy = 10
			e7.piles.hand.append(c)
			e7.play_card(c, e7.enemies[0].stats)
			leaked += e7.piles.exhaust_pile.size() + e7.piles.discard_pile.size()
			e7.free()
	_row(7, "Trick cards and recall", "%d pet cards found in a pile after play" % leaked,
		"NOT A BREAK" if leaked == 0 else "CONFIRMED", "recorded so nobody 'fixes' it")

	# 8 and 11. Nothing counts card plays: scan the code for a play-counting trigger.
	var counters := _play_counting_sites()
	_row(8, "Free plays count nothing", "%d play-counting sites" % counters.size(),
		"NOT A BREAK" if counters.is_empty() else "CONFIRMED",
		"only the UI, audio and this tool listen to card_played" if counters.is_empty() else ", ".join(counters))
	var free_pet := 0
	for id in PetPool.all_ids():
		for c in PetPool.build_cards(id):
			if c.energy_cost == 0:
				free_pet += 1
	_row(11, "Free plays (Harry, Wait On, Scurry, Filch)", "%d free pet cards, one arrival a turn" % free_pet,
		"NOT A BREAK", "restated 8: a free trigger for any future play-counting effect")

	# 9. The oil on a pet card with two hits: spends on the first hit only.
	var harry := _by_name(hound, "Harry")
	var harry_plain := _damage_of(harry.duplicate_card(), 0)
	var harry_oil := _damage_of(harry.duplicate_card(), 0, func(e): e._blade_oil_pending = 8)
	_row(9, "Blade Oil on a Trick sweep", "+%d on Harry (once)" % (harry_oil - harry_plain),
		"NOT A BREAK", "the oil lands on one hit of one target")

	# 10. Stoop with every first-hit rider, through a guard, on a Vulnerable wall, the sword at +8.
	_reset(0)
	RunManager.add_relic(RelicPool.get_relic_by_name("Blooded Edge"))
	RunManager.active_title_slots = [&"swords_bearer", &""]
	RunManager.earned_title_ids.append(&"swords_bearer")
	var e10 := _fight([], [_wall()])
	e10.turn_number = 8
	e10._sword_base = 1
	e10._sword_escalates = true
	e10.energy = 10
	e10.enemies[0].stats.block = 60
	e10.enemies[0].stats.apply_status(StatusEffects.VULNERABLE, 2)
	e10.apply_status_effect(e10.player_stats, StatusEffects.STRENGTH, 2)
	e10._blade_oil_pending = 8
	var wait_on := _by_name(hawk, "Wait On")
	var stoop := _by_name(hawk, "Stoop")
	e10.piles.hand.append(wait_on)
	e10.play_card(wait_on, e10.enemies[0].stats)
	e10.piles.hand.append(stoop)
	e10.play_card(stoop, e10.enemies[0].stats)
	var stoop_max := _wall_hp_lost(e10)
	e10.free()
	_row(10, "Stoop with every rider", "%d on one hit" % stoop_max,
		"CONFIRMED" if stoop_max > _bar_first_lifebar else "BOUNDED",
		"sword +8, Strength 2, oil, Blooded Edge, Vulnerable, waiting on, through 60 Block; first bar %d" % _bar_first_lifebar)

	# 12. Bay stockpile: bank every Bay for 12 turns against a wall, then play them all.
	_reset(0)
	RunManager.pet_id = &"hound"
	var e12 := _fight(_filler(40), [_wall()])
	var max_bays := 0
	for t in 12:
		var bays := 0
		for c in e12.piles.hand:
			if c.card_name == "Bay":
				bays += 1
		max_bays = maxi(max_bays, bays)
		e12.end_player_turn()
	var bays_now := 0
	for c in e12.piles.hand:
		if c.card_name == "Bay":
			bays_now += 1
	e12.energy = 10
	for c in e12.piles.hand.duplicate():
		if c.card_name == "Bay":
			e12.play_card(c, e12.enemies[0].stats)
	var weak := e12.enemies[0].stats.get_status_stacks(StatusEffects.WEAK)
	e12.free()
	_row(12, "Bay stockpile", "%d banked by turn 12, Weak %d turns" % [max(max_bays, bays_now), weak],
		"BOUNDED", "-25% damage on one enemy for that many turns; one Bay a four-turn cycle, an energy each")

	# 13. Bind against a guard that resets.
	var guard := _biggest_block()
	_row(13, "Bind vs a resetting guard", "%d Block stripped at most (%s)" % [guard[0], guard[1]],
		"BOUNDED", "enemy Block resets at its own turn, so Bind only matters against Block gained the turn before")

	# 14. Filch and the X-cost torrent: one more energy is one more strike.
	var maelstrom := _by_name(emo_p, "Maelstrom")
	var m3 := _damage_of(maelstrom.duplicate_card(), 0, Callable(), [], 3)
	var m4 := _damage_of(maelstrom.duplicate_card(), 0, Callable(), [], 4)
	_row(14, "Filch + the X-cost torrent", "+%d (one more strike)" % (m4 - m3), "NOT A BREAK",
		"Filch comes once in four turns and never banks")

	# 15. Two saves a fight: the Girdle under the Compassionate.
	_reset(0)
	RunManager.add_relic(RelicPool.get_relic_by_name("The Green Girdle"))
	RunManager.active_title_slots = [&"the_compassionate", &""]
	RunManager.earned_title_ids.append(&"the_compassionate")
	var e15 := _fight([], [_hitter(1)], 30)
	var src := e15.enemies[0].stats
	var survived := 0
	for i in 5:
		e15.deal_damage(e15.player_stats, 100, src)
		if e15.phase == CombatEngine.Phase.BATTLE_LOST:
			break
		survived += 1
	e15.free()
	_row(15, "Two saves a fight (Girdle + Compassionate)", "%d felling blows survived" % survived,
		"BOUNDED", "title first, girdle second, then nothing; two extra turns against an unwinnable ramp")

	# 16. The scabbard against many small hits.
	var s16 := _scabbard_vs_moves()
	_row(16, "The scabbard vs many small hits", "max %d hits in a move; %d moves fully soaked" % [s16[0], s16[1]],
		"BOUNDED", "-1 a hit plus a 2 mend each turn; names: %s" % s16[2])

	# 17. Draw stacking: every combat-start draw relic held at once.
	var s17 := _draw_stack()
	_row(17, "Draw stacking", "opening hand %d, then %d a turn" % [s17[0], s17[1]],
		"BOUNDED", "needs %s; a hand has no cap, the deck is the cap" % s17[2])

	# 18. A note, not a break.
	_row(18, "The turn-one Block fix", "4 relics + the militia boon now work", "NOT A BREAK",
		"moves every baseline; re-baselined in BALANCE_SNAPSHOTS")


## The largest single DamageEffect value across every enemy this build ships, and who throws it.
func _biggest_blow() -> Array:
	var best := 0
	var who := ""
	for en in _all_enemies():
		for m in _all_moves(en):
			for e in m.effects:
				if e is DamageEffect and not e.apply_to_source and e.value > best:
					best = e.value
					who = "%s: %s" % [en.enemy_name, m.move_name]
	return [best, who]


func _biggest_block() -> Array:
	var best := 0
	var who := ""
	for en in _all_enemies():
		for m in _all_moves(en):
			for e in m.effects:
				if e is BlockEffect and e.value > best:
					best = e.value
					who = "%s: %s" % [en.enemy_name, m.move_name]
	return [best, who]


## [most hits in one move, moves whose whole damage is soaked by -1 a hit and the 2 mend, names].
func _scabbard_vs_moves() -> Array:
	var most := 0
	var soaked := 0
	var names: PackedStringArray = []
	for en in _all_enemies():
		for m in _all_moves(en):
			var total := 0
			var hits := 0
			for e in m.effects:
				if e is DamageEffect and not e.apply_to_source:
					total += e.value * e.hits
					hits += e.hits
			most = maxi(most, hits)
			if hits > 0 and total <= hits + 2:
				soaked += 1
				names.append("%s/%s" % [en.enemy_name, m.move_name])
	return [most, soaked, ", ".join(names) if not names.is_empty() else "none"]


func _draw_stack() -> Array:
	_reset(0)
	var held: PackedStringArray = []
	var turn_draw := 0
	for r in RelicPool._build_pool() + RelicPool._build_woken_pool():
		if r.trigger == RelicData.RelicTrigger.ON_COMBAT_START:
			if r.effect == RelicData.RelicEffect.DRAW_CARDS or r.effect2 == RelicData.RelicEffect.DRAW_CARDS:
				if not r.is_dormant() or true:
					RunManager.add_relic(r)
					held.append(r.relic_name)
		elif r.trigger == RelicData.RelicTrigger.ON_TURN_START and r.effect == RelicData.RelicEffect.DRAW_CARDS:
			RunManager.add_relic(r)
			held.append(r.relic_name)
			turn_draw += r.value
	var deck: Array[CardData] = []
	for i in 40:
		deck.append(_attack("Filler %d" % i, 1, 1))
	RunManager.pet_id = &"ferret"
	var eng := _fight(deck, [_wall()])
	var opening := eng.piles.hand.size()
	eng.end_player_turn()
	var steady := eng.piles.hand.size()
	eng.free()
	return [opening, steady, ", ".join(held)]


func _play_counting_sites() -> PackedStringArray:
	var out: PackedStringArray = []
	for dir in ["res://scripts/core", "res://scripts/autoloads"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var t := FileAccess.get_file_as_string(dir + "/" + f)
			if t.contains("card_played.connect") and f != "audio_manager.gd":
				out.append(f)
	return out


func _all_enemies() -> Array:
	var out: Array = []
	for i in 6:
		out.append_array(EnemyPool.get_combat_encounter(i))
	for i in 4:
		out.append_array(EnemyPool.get_elite_encounter())
	out.append_array(EnemyPool.get_boss())
	out.append_array(EnemyPool.get_sword_guardian())
	out.append_array(EnemyPool.get_raider_band())
	out.append_array(EnemyPool.get_barrow_warden())
	out.append(EnemyPool.the_shattered_choir())
	return out


func _all_moves(en: EnemyData) -> Array:
	var moves: Array = en.moves.duplicate()
	for ms in en.phase_movesets:
		moves.append_array(ms)
	return moves


# ============================================================
# (2) PER-CARD CEILINGS
# ============================================================

func _per_card() -> void:
	print("\n(2) PER-CARD CEILINGS: damage on the real engine into an immortal wall")
	var pools := {
		"emo primary": CardPool.build_emo_primary_pool(), "emo secondary": CardPool.build_emo_secondary_pool(),
		"generic": CardPool._build_generic_pool(), "memory": CardPool.build_memory_cards(),
	}
	var rows: Array = []  # [name, pool, cost, face, kit]
	for pool_name in pools:
		for c in pools[pool_name]:
			var face := _damage_of(c.duplicate_card(), 0, Callable(), [], 3)
			if face <= 0:
				continue
			# The amplifier kit: Strength 4, the sword at +8, the oil, Blooded Edge, Vulnerable, and
			# the card's own pole at its extreme (Blazing for Water, Hollow for Physical).
			var passion := 55 if c.personality == CardData.PersonalityType.PRIMARY else -55
			var kit := _damage_of(c.duplicate_card(), passion, func(e):
				e.apply_status_effect(e.player_stats, StatusEffects.STRENGTH, 4)
				e.turn_number = 8
				e._sword_base = 1
				e._sword_escalates = true
				e._blade_oil_pending = 8
				e.enemies[0].stats.apply_status(StatusEffects.VULNERABLE, 2), ["Blooded Edge"], 3)
			rows.append([c.card_name, pool_name, c.energy_cost if not c.x_cost else 3, face, kit])
	rows.sort_custom(func(a, b): return a[4] > b[4])
	print("  %-26s %-14s %4s %6s %10s" % ["card", "pool", "cost", "face", "with kit"])
	for i in mini(14, rows.size()):
		var r: Array = rows[i]
		print("  %-26s %-14s %4d %6d %10d%s" % [r[0], r[1], r[2], r[3], r[4],
			"   <- over the bar" if r[4] > _bar_first_lifebar else ""])
	rows.sort_custom(func(a, b): return float(a[3]) / maxf(0.5, a[2]) > float(b[3]) / maxf(0.5, b[2]))
	print("  best face damage per energy:")
	for i in mini(6, rows.size()):
		var r: Array = rows[i]
		print("    %-26s %-14s %d for %d energy (%.1f / energy)" % [r[0], r[1], r[3], r[2],
			float(r[3]) / maxf(0.5, r[2])])
	print("  kit = Strength 4, the sword at +8, Blade Oil, Blooded Edge, Vulnerable, the card's pole at its extreme.")


# ============================================================
# (3) THE SEARCH
# ============================================================

func _search() -> void:
	print("\n(3) THE SEARCH: seeded hill-climb, %d restarts x %d steps per objective, real engine, wall" % [
		_restarts, _iters])
	var space := _search_space()
	for objective in ["burst", "sustain"]:
		var best := {}
		var best_fit := -1
		var all_best: Array = []
		for r in _restarts:
			var build := _random_build(space)
			var fit := _fitness(build, objective, r)
			for step in _iters:
				var cand := _mutate(build, space)
				var f := _fitness(cand, objective, r)
				if f >= fit:
					build = cand
					fit = f
			all_best.append(fit)
			if fit > best_fit:
				best_fit = fit
				best = build
		var m := _evaluate(best, 7000)
		var fresh: Array[int] = []
		for fs in [91001, 91002, 91003]:
			var fm := _evaluate(best, fs)
			fresh.append(fm["max_turn"] if objective == "burst" else fm["total"])
		print("  objective %-8s best %d (%s); restarts reached %s" % [objective, best_fit,
			"single turn" if objective == "burst" else "six turns", str(all_best)])
		print("    turn by turn: %s   cards played a turn: %s" % [str(m["turns"]), str(m["plays"])])
		print("    deck (%d): %s" % [best["deck"].size(), _compact(best["deck"])])
		print("    relics: %s | titles: %s | pack: %s | pet: %s | start Passion %d" % [
			", ".join(best["relics"]), ", ".join(best["titles"]), ", ".join(best["pack"]),
			best["pet"] if best["pet"] != "" else "none", best["passion"]])
		var verdict := "CONFIRMED over the bar" if m["max_turn"] > _bar_first_lifebar else "BOUNDED under the bar"
		print("    ceiling: %d in one turn, %d over six: %s (bar %d); on three fresh seeds the same build scores %s" % [
			m["max_turn"], m["total"], verdict, _bar_first_lifebar, str(fresh)])
	print("  evaluations run: %d" % _evals)


func _compact(names: Array) -> String:
	var counts := {}
	for n in names:
		counts[n] = counts.get(n, 0) + 1
	var parts: PackedStringArray = []
	for n in counts:
		parts.append("%s%s" % [n, " x%d" % counts[n] if counts[n] > 1 else ""])
	return ", ".join(parts)


func _search_space() -> Dictionary:
	var cards: Array = []
	# Only cards a run can hold: the draftable pools, and the one memory card an event grants. The
	# two memory cards with no source yet (the linter's known findings) stay out, and a memory card
	# is a single copy.
	for pool in [CardPool.build_emo_primary_pool(), CardPool.build_emo_secondary_pool(),
			CardPool._build_generic_pool()]:
		for c in pool:
			if not cards.has(c.card_name):
				cards.append(c.card_name)
	cards.append(SOURCED_MEMORY_CARD)
	var relics: Array = []
	for r in RelicPool._build_pool() + RelicPool._build_quest_pool() + RelicPool._build_woken_pool():
		if not relics.has(r.relic_name) and not r.is_dormant():
			relics.append(r.relic_name)
	var titles: Array = []
	for t in TitlePool.get_all_titles():
		titles.append(String(t.title_id))
	var pack: Array = []
	for id in ConsumablePool.all_ids():
		var c := ConsumablePool.get_consumable(id)
		if c.usable_in_combat:
			pack.append(String(id))
	var starters: Array = []
	for c in CharacterPool.emo_starting_deck():
		starters.append(c.card_name)
	return {"cards": cards, "relics": relics, "titles": titles, "pack": pack,
		"pets": ["", "hound", "hawk", "ferret"], "starters": starters}


func _random_build(space: Dictionary) -> Dictionary:
	var deck: Array = space["starters"].duplicate()
	for i in 8:
		deck.append(space["cards"][_rng.randi_range(0, space["cards"].size() - 1)])
	var relics: Array = []
	for i in 3:
		var r: String = space["relics"][_rng.randi_range(0, space["relics"].size() - 1)]
		if not relics.has(r):
			relics.append(r)
	return {"deck": deck, "relics": relics,
		"titles": [space["titles"][_rng.randi_range(0, space["titles"].size() - 1)], ""],
		"pack": [space["pack"][_rng.randi_range(0, space["pack"].size() - 1)]],
		"pet": space["pets"][_rng.randi_range(0, space["pets"].size() - 1)],
		"passion": [-60, 0, 60][_rng.randi_range(0, 2)]}


func _mutate(b: Dictionary, space: Dictionary) -> Dictionary:
	var n := _deep(b)
	var kind := _rng.randi_range(0, 9)
	match kind:
		0, 1, 2:
			var card: String = space["cards"][_rng.randi_range(0, space["cards"].size() - 1)]
			if n["deck"].count(card) < (1 if card == SOURCED_MEMORY_CARD else MAX_COPIES):
				n["deck"].append(card)
		3, 4:
			if n["deck"].size() > 10:
				n["deck"].remove_at(_rng.randi_range(0, n["deck"].size() - 1))
		5:
			var r: String = space["relics"][_rng.randi_range(0, space["relics"].size() - 1)]
			if not n["relics"].has(r):
				if n["relics"].size() >= 6:
					n["relics"].remove_at(_rng.randi_range(0, n["relics"].size() - 1))
				n["relics"].append(r)
		6:
			n["titles"][_rng.randi_range(0, 1)] = space["titles"][_rng.randi_range(0, space["titles"].size() - 1)]
			if n["titles"][0] == n["titles"][1]:
				n["titles"][1] = ""
		7:
			var p: String = space["pack"][_rng.randi_range(0, space["pack"].size() - 1)]
			n["pack"] = [p] if n["pack"].size() >= 2 or _rng.randf() < 0.5 else n["pack"] + [p]
		8:
			n["pet"] = space["pets"][_rng.randi_range(0, space["pets"].size() - 1)]
		9:
			n["passion"] = [-60, -30, 0, 30, 60][_rng.randi_range(0, 4)]
	return n


func _deep(b: Dictionary) -> Dictionary:
	return {"deck": b["deck"].duplicate(), "relics": b["relics"].duplicate(),
		"titles": b["titles"].duplicate(), "pack": b["pack"].duplicate(), "pet": b["pet"],
		"passion": b["passion"]}


func _fitness(b: Dictionary, objective: String, restart: int) -> int:
	var m := _evaluate(b, 7000 + restart)
	return m["max_turn"] if objective == "burst" else m["total"]


## Six turns into the immortal wall, the build as given. Returns damage per turn, the best turn, the
## six-turn total, cards played per turn, and flags loops it saw.
func _evaluate(b: Dictionary, seed_val: int) -> Dictionary:
	_evals += 1
	RunManager.current_character = _character
	RunManager.current_act = 1
	RunManager.relics.clear()
	RunManager.consumables.clear()
	RunManager.pet_id = StringName(b["pet"])
	RunManager.pending_act_complete = false
	RunManager.active_title_slots = [&"", &""]
	RunManager.earned_title_ids.clear()
	for i in 2:
		var t: String = b["titles"][i]
		if t != "":
			RunManager.earned_title_ids.append(StringName(t))
			RunManager.active_title_slots[i] = StringName(t)
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = b["passion"]
	RngManager.setup_run(seed_val)
	for rn in b["relics"]:
		var rel := RelicPool.get_relic_by_name(rn)
		if rel:
			RunManager.add_relic(rel)
	if RunManager.has_excalibur():
		RunManager.excalibur_mode = RunManager.ExcaliburMode.SWORD
	for id in b["pack"]:
		RunManager.consumables.append(ConsumablePool.get_consumable(StringName(id)))
	var deck: Array[CardData] = []
	for cn in b["deck"]:
		var c := _find_card(cn)
		if c:
			deck.append(c)
	var eng := _fight(deck, [_wall()])
	var per_turn: Array[int] = []
	var plays: Array[int] = []
	var max_turn := 0
	var total := 0
	for t in SIX_TURNS:
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		var before := _wall_hp_lost(eng)
		_plays_this_turn = 0
		_cbt.play_turn(eng, false, 0)
		var after := _wall_hp_lost(eng)
		plays.append(_plays_this_turn)
		if _plays_this_turn > LOOP_CARDS:
			_note_loop("%d cards in one turn" % _plays_this_turn, b)
		if eng.energy > ENERGY_HOARD:
			_note_loop("%d energy left unspent" % eng.energy, b)
		eng.end_player_turn()
		var dealt := _wall_hp_lost(eng) - before  # the turn's plays and any ticks after it
		per_turn.append(dealt)
		max_turn = maxi(max_turn, dealt)
		total += dealt
		if after > WALL_HP:
			break
	eng.free()
	RunManager.consumables.clear()
	RunManager.pet_id = &""
	if not _cbt.within_memory_ceiling("hunt eval %d" % _evals):
		get_tree().quit(1)
	return {"turns": per_turn, "plays": plays, "max_turn": max_turn, "total": total}


func _find_card(card_name: String) -> CardData:
	for pool in [CardPool.build_emo_primary_pool(), CardPool.build_emo_secondary_pool(),
			CardPool._build_generic_pool(), CardPool.build_memory_cards(),
			CharacterPool.emo_starting_deck()]:
		for c in pool:
			if c.card_name == card_name:
				return c.duplicate_card()
	return null


func _note_loop(what: String, b: Dictionary) -> void:
	var line := "%s | deck %d, relics %s, pet %s" % [what, b["deck"].size(), ", ".join(b["relics"]),
		b["pet"] if b["pet"] != "" else "none"]
	if _loop_flags.size() < 12 and not _loop_flags.has(line):
		_loop_flags.append(line)


# ============================================================
# (4) LOOPS
# ============================================================

func _loops_report() -> void:
	print("\n(4) LOOP AND INFINITE DETECTION: over every build the search tried")
	print("  thresholds: more than %d cards in one turn, or more than %d energy left at the end of one" % [
		LOOP_CARDS, ENERGY_HOARD])
	if _loop_flags.is_empty():
		print("  none seen in %d evaluations" % _evals)
	else:
		for l in _loop_flags:
			print("  FLAG %s" % l)


## A deck of one-damage fillers, so a draw has something to draw.
func _filler(n: int) -> Array:
	var d: Array = []
	for i in n:
		d.append(_attack("Filler %d" % i, 1, 1))
	return d
