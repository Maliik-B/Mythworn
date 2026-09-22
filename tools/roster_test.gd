extends Node
## Headless behavior check for the Camelot roster + Passion system.
## Run: godot --headless res://tools/roster_test.tscn
## Constructs the real EnemyPool enemies and asserts phase-gating, the encounter
## selectors, and the Passion pull actually behave. Prints PASS/FAIL and quits.

var _fails := 0


func _check(label: String, ok: bool) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok:
		_fails += 1


func _ready() -> void:
	print("\n== Camelot roster behavior check ==")
	_setup_run_state()
	_test_opener()
	_test_elite_and_boss_identity()
	_test_caedmon_phase_gate()
	_test_caedmon_transition()
	_test_passion_pull()
	_test_cooldown()
	_test_curse()
	_test_water_rework()
	_test_boss_reward()
	await _test_frozen_skips()
	_test_scene_scripts_compile()
	print("== %s ==\n" % ("ALL PASS" if _fails == 0 else "%d FAILURE(S)" % _fails))
	get_tree().quit(_fails)


func _setup_run_state() -> void:
	var ch := CharacterData.new()
	ch.character_name = "Test"
	ch.max_health = 80
	ch.passion_volatility = 1.0
	ch.passion_thresholds.assign([50, 18, -18, -50])
	ch.primary_personality = "Water"
	ch.secondary_personality = "Physical"
	RunManager.current_character = ch
	RunManager.current_act = 1
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = 0


func _names_over_rolls(data: EnemyData, hp: int, rolls: int) -> Dictionary:
	# Roll a fresh combat state many times at a fixed HP, tally the move names chosen.
	var seen := {}
	for i in rolls:
		var st := EnemyCombatState.new(data)
		st.stats.current_hp = hp
		st.select_intent()
		var n: String = st.current_intent.move_name
		seen[n] = seen.get(n, 0) + 1
	return seen


func _test_opener() -> void:
	var enc := EnemyPool.get_combat_encounter(0)
	_check("combat opener is a lone Corrupted Knight",
		enc.size() == 1 and enc[0].enemy_name == "Corrupted Knight")


func _test_elite_and_boss_identity() -> void:
	var elite := EnemyPool.get_elite_encounter()
	_check("elite is Champion or False Prophet",
		elite.size() == 1 and elite[0].enemy_name in ["Champion of the Usurper", "The False Prophet"])
	var boss := EnemyPool.get_boss()
	_check("act-1 boss is Sir Caedmon",
		boss.size() == 1 and boss[0].enemy_name == "Sir Caedmon")


func _test_caedmon_phase_gate() -> void:
	var caedmon := EnemyPool.sir_caedmon()
	var phase1 := ["Vanguard Strike", "Oathbound Guard", "Rallying Blow"]
	var phase2 := ["Compelled Onslaught", "Hollowing Gaze", "Puppet's Fervor"]
	_check("Caedmon is multi-phase (2 bars)",
		caedmon.is_multiphase() and caedmon.phase_hps.size() == 2)

	# Phase 1: only disciplined moves (phases are separate bars now, not HP gates).
	var st := EnemyCombatState.new(caedmon)
	var p1_ok := true
	for i in 300:
		st.select_intent()
		if st.current_intent.move_name not in phase1:
			p1_ok = false
	_check("Caedmon phase 1 uses only disciplined moves", p1_ok)

	# Transition: refills to the phase-2 bar, swaps moveset, speaks a line.
	var line := st.advance_phase()
	_check("advance_phase refills HP + swaps to phase 2 + speaks",
		st.phase_index == 1 and st.stats.current_hp == caedmon.phase_hps[1] and line != "")
	_check("Caedmon has no third phase", not st.can_advance_phase())
	var p2_ok := true
	for i in 300:
		st.select_intent()
		if st.current_intent.move_name not in phase2:
			p2_ok = false
	_check("Caedmon phase 2 uses only compelled moves", p2_ok)


## End-to-end: the engine transitions (not kills) when a non-final phase is depleted,
## and overkill does not carry into the next bar.
func _test_caedmon_transition() -> void:
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 80, 80, [EnemyPool.sir_caedmon()])
	var caed: EnemyCombatState = eng.enemies[0]
	var bar1: int = caed.stats.max_hp
	eng.deal_damage(caed.stats, bar1 + 999, eng.player_stats)  # massive overkill
	_check("depleting phase 1 transitions instead of killing",
		caed.phase_index == 1 and not caed.stats.is_dead())
	_check("overkill does not carry into phase 2 (refilled to full bar)",
		caed.stats.current_hp == caed.enemy_data.phase_hps[1])
	eng.deal_damage(caed.stats, caed.stats.current_hp, eng.player_stats)
	_check("depleting the final phase kills", caed.stats.is_dead())
	eng.free()


func _test_passion_pull() -> void:
	_check("passion_center is 0 for [50,18,-18,-50]", RunManager.passion_center() == 0)
	# Multiplicative pull toward 0 keeps (1 - strength) of the value.
	RunManager.passion.current_value = 80
	RunManager.pull_passion_to_center(0.25)
	_check("pull-to-center 0.25 from 80 -> 60", RunManager.passion.current_value == 60)
	# Symmetric from the secondary pole.
	RunManager.passion.current_value = -80
	RunManager.pull_passion_to_center(0.25)
	_check("pull-to-center 0.25 from -80 -> -60 (symmetric)", RunManager.passion.current_value == -60)
	# Can never overshoot 0.
	RunManager.passion.current_value = 4
	RunManager.pull_passion_to_center(0.9)
	_check("pull-to-center never overshoots 0", RunManager.passion.current_value == 0)
	# Additive change_passion is directional: + toward primary, - toward secondary.
	RunManager.passion.current_value = 0
	RunManager.change_passion(10)
	_check("change_passion +10 from 0 -> +10", RunManager.passion.current_value == 10)
	RunManager.change_passion(-30)
	_check("change_passion -30 -> -20", RunManager.passion.current_value == -20)
	# Tier mapping on the signed axis.
	RunManager.passion.current_value = 60
	_check("+60 is Blazing", RunManager.get_passion_tier() == PassionState.Tier.BLAZING)
	RunManager.passion.current_value = -80
	_check("-80 is Hollow", RunManager.get_passion_tier() == PassionState.Tier.HOLLOW)
	RunManager.passion.current_value = 0
	_check("0 is Steady", RunManager.get_passion_tier() == PassionState.Tier.STEADY)


func _test_curse() -> void:
	var curse := EnemyPool._corruption_curse()
	_check("Corruption is unplayable + NEGATIVE",
		curse.unplayable and curse.personality == CardData.PersonalityType.NEGATIVE)
	_check("duplicate_card preserves unplayable", curse.duplicate_card().unplayable)
	var shade := EnemyPool.realm_shade()
	var has_corrupt := false
	for m in shade.moves:
		if m.move_name == "Corrupt":
			has_corrupt = true
	_check("Realm Shade has a Corrupt move", has_corrupt)
	# The full chain: AddCardEffect -> engine.add_card_to_pile -> draw pile.
	var eng := CombatEngine.new()
	eng.piles = PileManager.new()
	eng.piles.setup([])
	var eff = EnemyPool._add_curse()
	eff.apply(null, null, eng)
	_check("Corrupt shuffles one unplayable card into the draw pile",
		eng.piles.draw_pile.size() == 1 and eng.piles.draw_pile[0].unplayable)
	eng.free()


## Sum a card's Passion shift across its effects (direction check for the rework).
func _sum_passion(card: CardData) -> int:
	var total := 0
	for e in card.effects:
		if e is PassionEffect:
			total += e.value
	return total


## The Water rework's affinity discipline: every primary (Water) card pushes Passion
## toward the primary pole (+); every secondary (Physical) card pushes toward the
## secondary pole (−). Also checks the new Frozen status wiring on Deep Freeze.
func _test_water_rework() -> void:
	# Water pool = 8 attack/skill + the Overflow POWER (9). Every card still pushes
	# Passion toward the primary pole and is tagged PRIMARY (Overflow carries a
	# +Passion nudge toward Blazing, where it pays off).
	var prim := CardPool.build_emo_primary_pool()
	var prim_ok := prim.size() == 9
	for c in prim:
		if _sum_passion(c) <= 0 or c.personality != CardData.PersonalityType.PRIMARY:
			prim_ok = false
	_check("all 9 Water cards push Passion + and are PRIMARY", prim_ok)

	# Physical pool = 8 + the Grounded POWER (9), all pushing Passion − and SECONDARY.
	var sec := CardPool.build_emo_secondary_pool()
	var sec_ok := sec.size() == 9
	for c in sec:
		if _sum_passion(c) >= 0 or c.personality != CardData.PersonalityType.SECONDARY:
			sec_ok = false
	_check("all 9 Physical cards push Passion - and are SECONDARY", sec_ok)

	_check("Frozen status is registered", StatusEffects.STUN != null)

	# Frozen uses DURATION stacking, so a second Freeze in one turn refreshes to 1
	# rather than compounding into a multi-turn lock.
	var dummy := CombatantStats.new(30, 30)
	dummy.apply_status(StatusEffects.STUN, 1)
	dummy.apply_status(StatusEffects.STUN, 1)
	_check("Frozen does not stack past 1 (DURATION)",
		dummy.get_status_stacks(StatusEffects.STUN) == 1)

	# Deep Freeze applies both Frozen and Vulnerable, and reads as a big + shift.
	var freeze: CardData = null
	for c in prim:
		if c.card_name == "Deep Freeze":
			freeze = c
	var freeze_ok := freeze != null
	if freeze_ok:
		var has_stun := false
		var has_vuln := false
		for e in freeze.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.STUN:
				has_stun = true
			if e is StatusApplyEffect and e.status_effect == StatusEffects.VULNERABLE:
				has_vuln = true
		freeze_ok = has_stun and has_vuln and _sum_passion(freeze) > 0
	_check("Deep Freeze applies Frozen + Vulnerable and pushes Passion +", freeze_ok)


## Boss card reward: must offer a full 3, include at least one RARE, and never a
## common/starter (uncommon-or-better) — the "3 commons off a boss" fix.
func _test_boss_reward() -> void:
	var ch := RunManager.current_character
	ch.primary_cards = CardPool.build_emo_primary_pool()
	ch.secondary_cards = CardPool.build_emo_secondary_pool()
	var choices := CardPool.get_boss_reward_choices(RngManager.loot_rng)
	var has_rare := false
	var all_uncommon_plus := true
	var unique := {}
	for c in choices:
		unique[c.card_name] = true
		if c.rarity == CardData.CardRarity.RARE:
			has_rare = true
		if c.rarity == CardData.CardRarity.COMMON or c.rarity == CardData.CardRarity.STARTER:
			all_uncommon_plus = false
	_check("boss reward offers 3 distinct cards", choices.size() == 3 and unique.size() == 3)
	_check("boss reward guarantees a rare", has_rare)
	_check("boss reward is all uncommon-or-better", all_uncommon_plus)


## End-to-end: a Frozen enemy forfeits its action for one turn, then thaws. Drives
## the real CombatEngine enemy-turn coroutine rather than asserting on internals.
func _test_frozen_skips() -> void:
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [_dummy_attacker()])
	var enemy_state: EnemyCombatState = eng.enemies[0]
	eng.apply_status_effect(enemy_state.stats, StatusEffects.STUN, 1)
	var hp_before := eng.player_stats.current_hp
	await eng.start_enemy_turn()
	_check("Frozen enemy skips its turn (no player damage, then thaws)",
		eng.player_stats.current_hp == hp_before
		and not enemy_state.stats.has_status(StatusEffects.STUN))
	eng.free()


## A minimal enemy whose only move is a guaranteed 20-damage attack — so a skipped
## turn is unambiguous (any hit would show as lost player HP).
func _dummy_attacker() -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Test Dummy"
	e.max_health = 100
	var move := EnemyMove.new()
	move.move_name = "Smash"
	move.intent_type = EnemyMove.IntentType.ATTACK
	var dmg := DamageEffect.new()
	dmg.value = 20
	move.effects.append(dmg)
	e.moves.append(move)
	return e


func _test_scene_scripts_compile() -> void:
	# Scene scripts only compile when their scene runs, so the project-load check
	# never touches them. load() here (autoloads present) forces a full compile,
	# catching errors in the resonance-sigil edits and the encounter wiring.
	for path in ["res://scenes/combat/combat_scene.gd", "res://scenes/map/map_scene.gd",
			"res://scenes/reward/card_reward_scene.gd", "res://scenes/event/event_scene.gd"]:
		var scr = load(path)
		_check("compiles: %s" % path, scr != null and scr is GDScript)


func _test_cooldown() -> void:
	# Siege Slam has cooldown 2: it must not fire on consecutive enemy turns.
	var golem := EnemyPool.siege_golem()
	var st := EnemyCombatState.new(golem)
	var last_was_slam := false
	var double_slam := false
	for i in 40:
		st.select_intent()
		var is_slam := st.current_intent.move_name == "Siege Slam"
		if is_slam and last_was_slam:
			double_slam = true
		last_was_slam = is_slam
	_check("Siege Slam (cd 2) never fires back-to-back", not double_slam)
