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
	_test_elite_rotation()
	_test_conspirator_rally()
	_test_caedmon_phase_gate()
	_test_caedmon_transition()
	_test_passion_pull()
	_test_cooldown()
	_test_curse()
	_test_water_rework()
	_test_multihit_wave()
	_test_control_heal()
	_test_new_regulars()
	_test_xcost_maelstrom()
	_test_swing_relics()
	_test_prophet_escalation()
	_test_starter_deck()
	_test_map_planarity()
	_test_realm_config()
	_test_vn_data()
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
	var elite_names := ["Champion of the Usurper", "The False Prophet", "The Iron Verdict"]
	var elite := EnemyPool.get_elite_encounter()
	_check("elite is one of the three Camelot elites",
		elite.size() == 1 and elite[0].enemy_name in elite_names)
	var boss := EnemyPool.get_boss()
	_check("act-1 boss is Sir Caedmon",
		boss.size() == 1 and boss[0].enemy_name == "Sir Caedmon")


## The shuffle-bag guarantees a run sees all three elites once before any repeat (a path
## can hold up to 3 elite nodes). Iron Verdict is armed with Enraged from turn 1.
func _test_elite_rotation() -> void:
	EnemyPool.reset_encounter_state()
	var seen := {}
	for i in 3:
		var e := EnemyPool.get_elite_encounter()
		seen[e[0].enemy_name] = seen.get(e[0].enemy_name, 0) + 1
	_check("3 elite draws are all distinct (no same-run repeat)", seen.size() == 3)

	var verdict := EnemyPool.iron_verdict()
	var armed := false
	for pair in verdict.starting_statuses:
		if pair[0] == StatusEffects.ENRAGED and pair[1] >= 1:
			armed = true
	_check("Iron Verdict starts armed with Enraged", armed)

	# End-to-end: start_combat applies starting_statuses, so the elite retaliates from
	# the first hit rather than needing a setup turn.
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 60, 60, [EnemyPool.iron_verdict()])
	var live_enraged: int = eng.enemies[0].stats.get_status_stacks(StatusEffects.ENRAGED)
	var hp_before := eng.player_stats.current_hp
	eng.deal_damage(eng.enemies[0].stats, 5, eng.player_stats)
	_check("Iron Verdict is Enraged in combat and lashes back on the first hit",
		live_enraged >= 1 and eng.player_stats.current_hp == hp_before - live_enraged)
	eng.free()


func _test_caedmon_phase_gate() -> void:
	var caedmon := EnemyPool.sir_caedmon()
	var phase1 := ["Vanguard Strike", "Oathbound Guard", "Rallying Blow"]
	var phase2 := ["Compelled Onslaught", "Hollowing Gaze", "Puppet's Fervor"]
	_check("Caedmon is multi-phase (2 bars)",
		caedmon.is_multiphase() and caedmon.phase_hps.size() == 2)
	_check("Caedmon has a death-beat line", caedmon.death_line != "")

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


## The Court Conspirator rallies the group: a BUFF that hands Strength to every living
## enemy (self + allies) via the new StatusApplyEffect.apply_to_allies path.
func _test_conspirator_rally() -> void:
	var consp := EnemyPool.court_conspirator()
	var has_rally := false
	for m in consp.moves:
		if m.move_name == "Rally the Court":
			has_rally = true
	_check("Court Conspirator has a Rally the Court move", has_rally)

	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [EnemyPool.court_conspirator(), _dummy_attacker()])
	EnemyPool._ally_status(StatusEffects.STRENGTH, 1).apply(eng.enemies[0].stats, eng.player_stats, eng)
	_check("Rally buffs all allies (both enemies gain Strength)",
		eng.enemies[0].stats.get_status_stacks(StatusEffects.STRENGTH) == 1
		and eng.enemies[1].stats.get_status_stacks(StatusEffects.STRENGTH) == 1)
	eng.free()


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
	# Passion caps at ±60 now (tight band so mechanics can bite).
	RunManager.passion.current_value = 0
	RunManager.change_passion(200)
	_check("passion caps at +60", RunManager.passion.current_value == 60)
	RunManager.change_passion(-400)
	_check("passion caps at -60", RunManager.passion.current_value == -60)
	RunManager.passion.current_value = 0


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
	# Water pool = 9 attack/skill + the Overflow POWER (10 after content pass #2 added
	# Cascade). Every card still pushes Passion toward the primary pole and is tagged
	# PRIMARY (Overflow carries a +Passion nudge toward Blazing, where it pays off).
	var prim := CardPool.build_emo_primary_pool()
	var prim_ok := prim.size() == 10
	for c in prim:
		if _sum_passion(c) <= 0 or c.personality != CardData.PersonalityType.PRIMARY:
			prim_ok = false
	_check("all 10 Water cards push Passion + and are PRIMARY", prim_ok)

	# Physical pool = 10 + the Grounded POWER (11 after content pass #2 added Twin Strike
	# + Whetstone), all pushing Passion − and SECONDARY.
	var sec := CardPool.build_emo_secondary_pool()
	var sec_ok := sec.size() == 11
	for c in sec:
		if _sum_passion(c) >= 0 or c.personality != CardData.PersonalityType.SECONDARY:
			sec_ok = false
	_check("all 11 Physical cards push Passion - and are SECONDARY", sec_ok)

	_check("Frozen status is registered", StatusEffects.STUN != null)

	# Frozen uses DURATION stacking, so a second Freeze in one turn refreshes to 1
	# rather than compounding into a multi-turn lock.
	var dummy := CombatantStats.new(30, 30)
	dummy.apply_status(StatusEffects.STUN, 1)
	dummy.apply_status(StatusEffects.STUN, 1)
	_check("Frozen does not stack past 1 (DURATION)",
		dummy.get_status_stacks(StatusEffects.STUN) == 1)

	# Deep Freeze applies both Frozen and Weak (content pass #2 swapped its old Vulnerable
	# rider → Weak so Vulnerable stays Physical-only), and reads as a big + shift.
	var freeze: CardData = null
	for c in prim:
		if c.card_name == "Deep Freeze":
			freeze = c
	var freeze_ok := freeze != null
	if freeze_ok:
		var has_stun := false
		var has_weak := false
		for e in freeze.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.STUN:
				has_stun = true
			if e is StatusApplyEffect and e.status_effect == StatusEffects.WEAK:
				has_weak = true
		freeze_ok = has_stun and has_weak and _sum_passion(freeze) > 0
	_check("Deep Freeze applies Frozen + Weak and pushes Passion +", freeze_ok)

	# Orthogonality guard: Water is glass CONTROL, so NO Water card may apply Vulnerable
	# to an enemy (Vulnerable is exclusively Physical's big-hit enabler now). Buff-self
	# statuses don't count — this only bans debuffing the target with Vulnerable.
	var water_vuln := false
	for c in prim:
		for e in c.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.VULNERABLE \
					and not e.apply_to_source:
				water_vuln = true
	_check("no Water card applies Vulnerable (Vuln is Physical's alone)", not water_vuln)


## Content pass #2 — the pole multi-hit wave. Verifies the two new multi-hit identities
## stay ORTHOGONAL: Water's Cascade is a high-count (y≥3) multi that rides Overflow, never
## Strength; Physical's Twin Strike is a low-count (2-hit) multi that RIDES Strength; and
## Whetstone is the pool Strength engine that feeds it.
func _test_multihit_wave() -> void:
	var prim := CardPool.build_emo_primary_pool()
	var sec := CardPool.build_emo_secondary_pool()

	# Cascade: Water's y≥3 single-target multi (PRIMARY).
	var cascade := _card_by_name(prim, "Cascade")
	var cascade_hits := 0
	if cascade:
		for e in cascade.effects:
			if e is DamageEffect:
				cascade_hits = e.hits
	_check("Cascade is a Water y≥3 multi-hit (PRIMARY, hits >= 3)",
		cascade != null and cascade.personality == CardData.PersonalityType.PRIMARY
		and cascade_hits >= 3)

	# Twin Strike: Physical's 2-hit (SECONDARY).
	var twin := _card_by_name(sec, "Twin Strike")
	var twin_hits := 0
	if twin:
		for e in twin.effects:
			if e is DamageEffect:
				twin_hits = e.hits
	_check("Twin Strike is a Physical 2-hit (SECONDARY, hits == 2)",
		twin != null and twin.personality == CardData.PersonalityType.SECONDARY
		and twin_hits == 2)

	# Whetstone: the pool's Strength engine (self-Strength, SECONDARY).
	var whet := _card_by_name(sec, "Whetstone")
	var whet_str := false
	if whet:
		for e in whet.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.STRENGTH \
					and e.apply_to_source and e.value >= 2:
				whet_str = true
	_check("Whetstone builds Strength (self +2, SECONDARY)",
		whet != null and whet_str and whet.personality == CardData.PersonalityType.SECONDARY)

	# End-to-end: Twin Strike RIDES Strength. Strength is added per hit, so at +3 Strength a
	# 6×2 attack lands for 2×(6+3)=18. Passion pinned to Steady so the zone modifier is flat.
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [_dummy_attacker()])  # 100-HP dummy, 0 block
	RunManager.passion.current_value = 0
	eng.player_stats.apply_status(StatusEffects.STRENGTH, 3)
	var shot := twin.duplicate_card()
	eng.piles.hand.append(shot)
	eng.energy = 3
	var hp_before := eng.enemies[0].stats.current_hp
	eng.play_card(shot, eng.enemies[0].stats)
	_check("Twin Strike rides Strength (2×(6+3) = 18 at +3 Strength)",
		eng.enemies[0].stats.current_hp == hp_before - 18)
	eng.free()
	RunManager.passion.current_value = 0


## The Emo Hybrid's innate control-heal passive (the Water attrition answer): landing Weak
## or Frozen on an ENEMY mends the player by CharacterData.control_heal; enemy-applied CC
## and applications at full HP do not. Auto-gated to Water's control statuses so a Physical
## build never triggers it.
func _test_control_heal() -> void:
	var ch := CharacterPool.build_emo_hybrid()
	_check("Emo Hybrid has a control-heal passive", ch.control_heal > 0)
	RunManager.current_character = ch
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 80, [_dummy_attacker()])  # wounded (50/80) so there's room to heal
	var hp0 := eng.player_stats.current_hp
	eng.apply_status_effect(eng.enemies[0].stats, StatusEffects.WEAK, 1)
	_check("landing Weak on an enemy heals the player by control_heal",
		eng.player_stats.current_hp == hp0 + ch.control_heal)
	var hp1 := eng.player_stats.current_hp
	eng.apply_status_effect(eng.enemies[0].stats, StatusEffects.STUN, 1)
	_check("landing Frozen on an enemy also heals",
		eng.player_stats.current_hp == hp1 + ch.control_heal)
	# Enemy-applied Weak on the PLAYER must never heal (gated to enemy targets).
	var hp2 := eng.player_stats.current_hp
	eng.apply_status_effect(eng.player_stats, StatusEffects.WEAK, 1)
	_check("enemy CC on the player does NOT heal", eng.player_stats.current_hp == hp2)
	eng.free()
	_setup_run_state()  # restore the baseline test character + passion for later tests


## The three new Sep-2026 regulars (#18 roster thickening): each exists with its
## signature move, and the two debuff signatures actually apply to the PLAYER (Squire's
## Vulnerable, Acolyte's Weak) — the new "throttle you" threats.
func _test_new_regulars() -> void:
	var maa := EnemyPool.man_at_arms()
	_check("Man-at-Arms exists with Overhead Chop",
		maa.enemy_name == "Man-at-Arms" and _has_move(maa, "Overhead Chop"))

	var squire := EnemyPool.corrupted_squire()
	_check("Corrupted Squire exists with Expose Weakness",
		squire.enemy_name == "Corrupted Squire" and _has_move(squire, "Expose Weakness"))

	var acolyte := EnemyPool.prophets_acolyte()
	_check("Prophet's Acolyte exists with Sap Will",
		acolyte.enemy_name == "Prophet's Acolyte" and _has_move(acolyte, "Sap Will"))

	# End-to-end: the two debuffs land on the player (not self), via the real engine.
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [EnemyPool.corrupted_squire()])
	_move_by_name(squire, "Expose Weakness").effects[0].apply(
		eng.enemies[0].stats, eng.player_stats, eng)
	_check("Squire's Expose Weakness puts Vulnerable on the player",
		eng.player_stats.has_status(StatusEffects.VULNERABLE))
	_move_by_name(acolyte, "Sap Will").effects[0].apply(
		eng.enemies[0].stats, eng.player_stats, eng)
	_check("Acolyte's Sap Will puts Weak on the player",
		eng.player_stats.get_status_stacks(StatusEffects.WEAK) == 2)
	eng.free()


## Maelstrom is the X-cost torrent (#21): x_cost card carrying an x_scaled DamageEffect,
## and end-to-end it strikes once per energy spent (5 x 3 = 15 at full energy, zeroing it).
func _test_xcost_maelstrom() -> void:
	var mael: CardData = null
	for c in CardPool.build_emo_primary_pool():
		if c.card_name == "Maelstrom":
			mael = c
	var flagged := mael != null and mael.x_cost
	var x_eff := false
	if mael:
		for e in mael.effects:
			if e is DamageEffect and e.x_scaled:
				x_eff = true
	_check("Maelstrom is an x_cost card with an x_scaled DamageEffect", flagged and x_eff)

	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [_dummy_attacker()])  # 100-HP dummy, 0 block
	var shot := mael.duplicate_card()
	eng.piles.hand.append(shot)
	eng.energy = 3  # X = 3
	var hp_before := eng.enemies[0].stats.current_hp
	eng.play_card(shot, eng.enemies[0].stats)
	_check("Maelstrom spends all energy and strikes 5x3=15 at X=3",
		eng.enemies[0].stats.current_hp == hp_before - 15 and eng.energy == 0)
	eng.free()


## The swing gear (Q2): Wellspring surges Passion + each turn (uncommon after the #22
## rarity nerf), Leaden Vow settles it − each turn — one relic per pole so a build-around
## player can commit fast in either direction.
func _test_swing_relics() -> void:
	var well := RelicPool.get_relic_by_name("Wellspring of Resolve")
	_check("Wellspring is Uncommon and +2 Passion/turn (toward Blazing)",
		well != null and well.rarity == RelicData.RelicRarity.UNCOMMON
		and well.trigger == RelicData.RelicTrigger.ON_TURN_START
		and well.effect == RelicData.RelicEffect.GAIN_PASSION and well.value == 2)
	var vow := RelicPool.get_relic_by_name("Leaden Vow")
	_check("Leaden Vow is −2 Passion/turn (toward Hollow)",
		vow != null and vow.trigger == RelicData.RelicTrigger.ON_TURN_START
		and vow.effect == RelicData.RelicEffect.GAIN_PASSION and vow.value == -2)


## The False Prophet's escalating pull (design pass Sep 2026): it builds Zealotry each
## sermon, and PassionCenterEffect multiplies its pull by the source's Zealotry — so a
## longer fight strips your pole harder (race to silence it).
func _test_prophet_escalation() -> void:
	var prophet := EnemyPool.false_prophet()
	var builds := false
	for m in prophet.moves:
		for e in m.effects:
			if e is StatusApplyEffect and e.apply_to_source \
					and e.status_effect == StatusEffects.ZEALOTRY:
				builds = true
	_check("Prophet builds Zealotry each sermon", builds)

	# The pull escalates with the source's Zealotry: same base strength pulls HARDER with
	# stacks (leaves you closer to center).
	var eff = load("res://scripts/core/effects/passion_center_effect.gd").new()
	eff.strength = 0.2
	var src := CombatantStats.new(100, 100)
	RunManager.passion.current_value = 60
	eff.apply(src, null, null)                    # 0 Zealotry → mild pull
	var base_after: int = RunManager.passion.current_value
	RunManager.passion.current_value = 60
	src.apply_status(StatusEffects.ZEALOTRY, 5)
	eff.apply(src, null, null)                    # 5 Zealotry → stronger pull
	_check("Prophet pull escalates with Zealotry (stronger with stacks)",
		RunManager.passion.current_value < base_after)
	RunManager.passion.current_value = 0


## The 10-card self-scaling starter (design pass Sep 2026): leaned neutrals (Strike −1 /
## Defend +1, both NEUTRAL so no zone penalty), Water's Ebb applies Weak (its control/early
## defense), Physical's Tempered Strike gains Strength (the ramp / damage buff).
func _test_starter_deck() -> void:
	var deck := CharacterPool.emo_starting_deck()
	_check("starter deck is 11 cards", deck.size() == 11)
	var by_name := {}
	for c in deck:
		by_name[c.card_name] = c

	# The strongest single-target base attack must be Physical (big singles = Physical lane).
	var strongest: CardData = null
	var strongest_dmg := -1
	for c in deck:
		for e in c.effects:
			if e is DamageEffect and e.hits == 1 and e.value > strongest_dmg:
				strongest_dmg = e.value
				strongest = c
	_check("strongest single-target starter attack is Physical",
		strongest != null and strongest.personality == CardData.PersonalityType.SECONDARY)

	# Physical Vulnerable enabler (Sunder) — the big-hit setup.
	var sunder: CardData = by_name.get("Sunder")
	var sunder_vuln := false
	if sunder:
		for e in sunder.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.VULNERABLE \
					and not e.apply_to_source:
				sunder_vuln = true
	_check("Sunder is a Physical Vulnerable enabler (SECONDARY)",
		sunder != null and sunder_vuln and sunder.personality == CardData.PersonalityType.SECONDARY)
	var strike: CardData = by_name.get("Strike")
	var defend: CardData = by_name.get("Defend")
	_check("Strike is NEUTRAL with a −1 Passion lean (toward Physical)",
		strike != null and strike.personality == CardData.PersonalityType.NEUTRAL
		and _sum_passion(strike) == -1)
	_check("Defend is NEUTRAL with a +1 Passion lean (toward Water)",
		defend != null and defend.personality == CardData.PersonalityType.NEUTRAL
		and _sum_passion(defend) == 1)
	var ebb: CardData = by_name.get("Ebb")
	var ebb_weak := false
	if ebb:
		for e in ebb.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.WEAK \
					and not e.apply_to_source:
				ebb_weak = true
	_check("Ebb (Water seed) applies Weak and is PRIMARY",
		ebb != null and ebb_weak and ebb.personality == CardData.PersonalityType.PRIMARY)
	var temp: CardData = by_name.get("Tempered Strike")
	var temp_str := false
	if temp:
		for e in temp.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.STRENGTH \
					and e.apply_to_source:
				temp_str = true
	_check("Tempered Strike (Physical ramp) gains Strength and is SECONDARY",
		temp != null and temp_str and temp.personality == CardData.PersonalityType.SECONDARY)


## Map readability: the generated graph must be planar (no two edges cross) after the
## _remove_edge_crossings straightening pass. Checks grid columns over many seeds — the
## cosmetic jitter is too small to reorder columns, so grid-planarity == drawn-planarity.
func _test_map_planarity() -> void:
	var crossed := 0
	for s in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var map := MapGenerator.generate(rng, &"camelot", 1)
		if _map_has_crossing(map):
			crossed += 1
	_check("map is planar — no crossing edges over 30 seeds", crossed == 0)


## True if any two edges on a floor-pair cross. Edges (c1→c2) and (c3→c4) cross iff their
## column orders disagree at start vs end, i.e. (c1−c3)·(c2−c4) < 0. Shared endpoints
## (fan-in/out, incl. the boss merge) give a 0 product, correctly not a crossing.
func _map_has_crossing(map: MapData) -> bool:
	for f in range(0, map.floor_count - 1):
		var edges := []
		for node in map.get_nodes_on_floor(f):
			for nid in node.next_nodes:
				var t: MapNode = map.nodes[nid]
				if t.floor_num == f + 1:
					edges.append([node.column, t.column])
		for i in range(edges.size()):
			for j in range(i + 1, edges.size()):
				if (edges[i][0] - edges[j][0]) * (edges[i][1] - edges[j][1]) < 0:
					return true
	return false


## The A2 realm-config system: neutral by default, and the wired knobs flow through —
## enemy difficulty scales encounter HP, and elite frequency biases the map's elite count
## (without breaking planarity). reward_rarity / map_boon are fielded but not yet wired.
func _test_realm_config() -> void:
	var cfg := RealmConfig.new()
	_check("RealmConfig defaults are neutral",
		cfg.enemy_difficulty_mult == 1.0 and cfg.shop_price_mult == 1.0
		and cfg.elite_frequency_mult == 1.0 and cfg.reward_rarity_mult == 1.0
		and cfg.map_boon == &"")

	# Difficulty knob: a 2x multiplier scales the opener enemy's HP.
	var base_hp: int = EnemyPool.get_combat_encounter(0, 1.0)[0].max_health
	var hard_hp: int = EnemyPool.get_combat_encounter(0, 2.0)[0].max_health
	_check("difficulty knob scales encounter HP (2x > 1x)", hard_hp > base_hp)

	# Elite-frequency knob: over many seeds, a high multiplier yields more elite nodes than
	# the neutral map (the min-floor gate + no-two-in-a-row + elite cap still bound it).
	var elites_neutral := 0
	var elites_dense := 0
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		elites_neutral += _count_elites(MapGenerator.generate(rng, &"camelot", 1, 1.0))
		rng.seed = s
		elites_dense += _count_elites(MapGenerator.generate(rng, &"camelot", 1, 4.0))
	_check("elite-frequency knob raises the elite count (4x > 1x over 40 seeds)",
		elites_dense > elites_neutral)

	# A raised elite frequency must not break map planarity.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	_check("map stays planar with a raised elite frequency",
		not _map_has_crossing(MapGenerator.generate(rng2, &"camelot", 1, 4.0)))

	# Reward-rarity knob: a > 1 mult biases card rarity rolls toward RARE.
	RunManager.realm_config = RealmConfig.new()
	var rr_rng := RandomNumberGenerator.new()
	rr_rng.seed = 123
	var rare_neutral := 0
	for i in 3000:
		if CardPool._roll_rarity(rr_rng) == CardData.CardRarity.RARE:
			rare_neutral += 1
	RunManager.realm_config.reward_rarity_mult = 1.8
	rr_rng.seed = 123
	var rare_rich := 0
	for i in 3000:
		if CardPool._roll_rarity(rr_rng) == CardData.CardRarity.RARE:
			rare_rich += 1
	_check("reward_rarity_mult biases card rolls toward RARE", rare_rich > rare_neutral)
	RunManager.realm_config = RealmConfig.new()  # restore neutral

	# The liaison + boon relics exist (quest pool) and never leak into reward rolls.
	_check("liaison + boon relics exist in the quest pool",
		RelicPool.get_relic_by_name("Bram's Briefing") != null
		and RelicPool.get_relic_by_name("Neve's Kit") != null
		and RelicPool.get_relic_by_name("Peasant Militia") != null)
	var reward_names := PackedStringArray()
	var boon_rng := RandomNumberGenerator.new()
	boon_rng.seed = 5
	for i in 30:
		for r in RelicPool.get_reward_choices(boon_rng, 3):
			reward_names.append(r.relic_name)
	_check("boon relics stay out of reward rolls",
		"Bram's Briefing" not in reward_names
		and "Neve's Kit" not in reward_names
		and "Peasant Militia" not in reward_names)

	# Liaison gifts grant the two send-off relics.
	RunManager.relics.clear()
	RunManager.apply_liaison_gift(&"bram")
	RunManager.apply_liaison_gift(&"neve")
	_check("liaison gifts grant Bram's Briefing + Neve's Kit",
		RunManager.has_relic("Bram's Briefing") and RunManager.has_relic("Neve's Kit"))
	RunManager.relics.clear()

	# apply_realm_config is the single install path: sets config, applies passion_shift
	# once, queues the map_boon, and emits realm_configured.
	RunManager.passion.current_value = 0
	var pcfg := RealmConfig.new()
	pcfg.passion_shift = 6
	pcfg.map_boon = &"militia"
	var emitted := [false]
	var on_cfg := func(_r): emitted[0] = true
	Events.realm_configured.connect(on_cfg)
	RunManager.apply_realm_config(pcfg)
	_check("apply_realm_config installs the config", RunManager.realm_config == pcfg)
	_check("apply_realm_config applies passion_shift once", RunManager.passion.current_value == 6)
	_check("apply_realm_config queues the map_boon", RunManager.pending_map_boon == &"militia")
	_check("apply_realm_config emits realm_configured", emitted[0])
	Events.realm_configured.disconnect(on_cfg)

	# consume_map_boon grants the militia relic exactly once (map reloads re-run _ready).
	RunManager.relics.clear()
	RunManager.consume_map_boon()
	_check("consume_map_boon grants the militia relic", RunManager.has_relic("Peasant Militia"))
	RunManager.consume_map_boon()
	var militia_count := 0
	for r in RunManager.relics:
		if r.relic_name == "Peasant Militia":
			militia_count += 1
	_check("consume_map_boon is one-shot", militia_count == 1)

	# Restore neutral state for the tests that follow.
	RunManager.relics.clear()
	RunManager.realm_config = RealmConfig.new()
	RunManager.pending_map_boon = &""
	RunManager.passion.current_value = 0


## The VN plumbing (A2): VNData builds with chainable beats + choices, and a choice's
## RealmConfig is what vn_scene applies to the run — the realm-entry consequence.
func _test_vn_data() -> void:
	var cfg := RealmConfig.new()
	cfg.enemy_difficulty_mult = 1.3
	var vn := VNData.new()
	vn.add_beat("Bram", "test line").add_beat("Neve", "another").add_choice("Court", cfg, "outcome")
	_check("VNData builds beats + choices (chainable)",
		vn.beats.size() == 2 and vn.choices.size() == 1
		and vn.beats[0].speaker == "Bram" and vn.choices[0].config == cfg
		and vn.choices[0].result_text == "outcome")
	# The realm-entry consequence vn_scene performs on choose: choice.config → realm_config.
	RunManager.realm_config = vn.choices[0].config
	_check("a VN choice's config becomes the run's realm_config",
		RunManager.realm_config.enemy_difficulty_mult == 1.3)
	RunManager.realm_config = RealmConfig.new()  # restore neutral for later tests

	# Authored A2 content (VNPool): the send-off is dialogue-only; the Camelot entry
	# offers the Court/Folk choice with asymmetric configs.
	var sendoff := VNPool.build_sendoff(RunManager.current_character)
	_check("send-off VN has beats and no terminal choice",
		sendoff.beats.size() > 0 and sendoff.choices.is_empty())
	var entry := VNPool.build_camelot_entry()
	_check("Camelot entry offers Court + Folk choices with configs",
		entry.choices.size() == 2
		and entry.choices[0].config != null and entry.choices[1].config != null)
	_check("Court is harder + richer; Folk is easier + carries the militia boon",
		entry.choices[0].config.elite_frequency_mult > 1.0
		and entry.choices[0].config.reward_rarity_mult > 1.0
		and entry.choices[1].config.elite_frequency_mult < 1.0
		and entry.choices[1].config.map_boon == &"militia")

	# Run-start queue: send-off -> entry -> map (what vn_scene._finish walks).
	RunManager.pending_vn = sendoff
	RunManager.pending_vn_queue.clear()
	RunManager.pending_vn_queue.append(entry)
	_check("queue advances send-off -> realm-entry",
		RunManager.pending_vn_queue.pop_front() == entry
		and RunManager.pending_vn_queue.is_empty())
	RunManager.pending_vn = null


func _count_elites(map: MapData) -> int:
	var n := 0
	for id in map.nodes:
		if map.nodes[id].node_type == MapNode.NodeType.ELITE:
			n += 1
	return n


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


func _card_by_name(pool: Array[CardData], card_name: String) -> CardData:
	for c in pool:
		if c.card_name == card_name:
			return c
	return null


func _has_move(data: EnemyData, move_name: String) -> bool:
	return _move_by_name(data, move_name) != null


func _move_by_name(data: EnemyData, move_name: String) -> EnemyMove:
	for m in data.moves:
		if m.move_name == move_name:
			return m
	return null


func _test_scene_scripts_compile() -> void:
	# Scene scripts only compile when their scene runs, so the project-load check
	# never touches them. load() here (autoloads present) forces a full compile,
	# catching errors in the resonance-sigil edits and the encounter wiring.
	for path in ["res://scenes/combat/combat_scene.gd", "res://scenes/map/map_scene.gd",
			"res://scenes/reward/card_reward_scene.gd", "res://scenes/event/event_scene.gd",
			"res://scenes/character_select/character_select_scene.gd",
			"res://scenes/shop/shop_scene.gd",
			"res://scenes/act/act_transition_scene.gd",
			"res://scenes/vn/vn_scene.gd"]:
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
