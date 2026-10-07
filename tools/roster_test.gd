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
	_test_content_enemies()
	_test_xcost_maelstrom()
	_test_swing_relics()
	_test_prophet_escalation()
	_test_starter_deck()
	_test_map_planarity()
	_test_realm_config()
	_test_event_scheduling()
	_test_scheduled_room()
	_test_memory_cards()
	_test_new_events()
	_test_reliquary()
	_test_vn_data()
	_test_profile_intro()
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
	var elite_names := ["Champion of the Usurper", "The False Prophet", "The Iron Verdict",
		"The Hollow Prelate"]
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


## The Oct-2026 content-furnishing enemies: the ranged-pierce Crossbowman, the escalation
## Hollow Herald, the Poison-stacking Rotting Knight, and the self-healing Hollow Prelate
## elite. Each is checked for its signature mechanic end-to-end through the real engine.
func _test_content_enemies() -> void:
	# Crossbowman: the Heavy Bolt carries pierce, and a piercing hit bypasses part of block.
	var cross := EnemyPool.corrupted_crossbowman()
	var bolt := _move_by_name(cross, "Heavy Bolt")
	var bolt_pierce := 0
	if bolt:
		for e in bolt.effects:
			if e is DamageEffect:
				bolt_pierce = e.pierce
	_check("Crossbowman's Heavy Bolt pierces block", bolt != null and bolt_pierce > 0)

	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [EnemyPool.corrupted_crossbowman()])
	eng.player_stats.gain_block(10)
	# 11 dmg, pierce 5: 5 bypasses block straight to HP, the other 6 soaks block (10 -> 4).
	bolt.effects[0].apply(eng.enemies[0].stats, eng.player_stats, eng)
	_check("a piercing bolt bypasses part of block (HP -5, block 10 -> 4)",
		eng.player_stats.current_hp == 45 and eng.player_stats.block == 4)
	# Pierce can't deal more than the hit: 4 dmg / pierce 10 into no block = 4 HP, not 10.
	eng.player_stats.current_hp = 50
	eng.player_stats.reset_block()
	eng.deal_damage(eng.player_stats, 4, eng.enemies[0].stats, 10)
	_check("pierce is capped at the hit (4 dmg / pierce 10 -> HP -4)",
		eng.player_stats.current_hp == 46)
	eng.free()

	# Hollow Herald: the banner buffs ALL allies' Strength and compounds each turn it fires.
	var herald := EnemyPool.hollow_herald()
	var standard := _move_by_name(herald, "Corrupt Standard")
	var is_banner := false
	if standard:
		for e in standard.effects:
			if e is StatusApplyEffect and e.apply_to_allies \
					and e.status_effect == StatusEffects.STRENGTH:
				is_banner = true
	_check("Herald's Corrupt Standard buffs all allies' Strength", standard != null and is_banner)

	var heng := CombatEngine.new()
	add_child(heng)
	heng.start_combat([], 50, 50, [EnemyPool.hollow_herald(), _dummy_attacker()])
	standard.effects[0].apply(heng.enemies[0].stats, heng.player_stats, heng)
	standard.effects[0].apply(heng.enemies[0].stats, heng.player_stats, heng)
	_check("the banner ramps the group's Strength each turn (+1 -> +2 on the ally)",
		heng.enemies[1].stats.get_status_stacks(StatusEffects.STRENGTH) == 2
		and heng.enemies[0].stats.get_status_stacks(StatusEffects.STRENGTH) == 2)
	heng.free()

	# Rotting Knight: Miasma stacks Poison on the player, which then bleeds through on tick.
	var rot := EnemyPool.rotting_knight()
	_check("Rotting Knight exists with Festering Cut + Miasma",
		rot.enemy_name == "Rotting Knight"
		and _has_move(rot, "Festering Cut") and _has_move(rot, "Miasma"))
	var reng := CombatEngine.new()
	add_child(reng)
	reng.start_combat([], 50, 50, [EnemyPool.rotting_knight()])
	_move_by_name(rot, "Miasma").effects[0].apply(
		reng.enemies[0].stats, reng.player_stats, reng)
	_check("Miasma puts 3 Poison on the player",
		reng.player_stats.get_status_stacks(StatusEffects.POISON) == 3)
	reng.tick_start_of_turn(reng.player_stats)
	_check("Poison bleeds through on tick (HP -3, Poison 3 -> 2)",
		reng.player_stats.current_hp == 47
		and reng.player_stats.get_status_stacks(StatusEffects.POISON) == 2)
	reng.free()

	# Hollow Prelate: the self-heal mends it (clamped to max) and fires enemy_healed; a heal
	# at full HP does nothing (so it only bites once you've chipped it).
	var prelate := EnemyPool.the_hollow_prelate()
	var font := _move_by_name(prelate, "Draw on the Font")
	var self_heals := false
	if font:
		for e in font.effects:
			if e is HealEffect and e.apply_to_source:
				self_heals = true
	_check("Prelate's Draw on the Font is a self-heal", font != null and self_heals)

	var peng := CombatEngine.new()
	add_child(peng)
	peng.start_combat([], 50, 50, [EnemyPool.the_hollow_prelate()])
	var healed_fired := [false]
	var on_heal := func(_en, _amt, _hp): healed_fired[0] = true
	Events.enemy_healed.connect(on_heal)
	var pstats: CombatantStats = peng.enemies[0].stats
	pstats.current_hp = pstats.max_hp - 15  # wounded, so a 14 heal has room
	font.effects[0].apply(pstats, peng.player_stats, peng)
	_check("the Prelate self-heal mends it and fires enemy_healed",
		pstats.current_hp == pstats.max_hp - 1 and healed_fired[0])
	pstats.current_hp = pstats.max_hp
	font.effects[0].apply(pstats, peng.player_stats, peng)
	_check("a self-heal at full HP does nothing", pstats.current_hp == pstats.max_hp)
	Events.enemy_healed.disconnect(on_heal)
	peng.free()


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

	# Pledge transform: Court (elite_frequency > 1) upgrades combats to NEW elites + records
	# them; Folk (weaken) flags the existing elites weakened. Both go on map.pledge_changes;
	# a neutral map records nothing.
	var ptrng := RandomNumberGenerator.new()
	ptrng.seed = 11
	var court_map := MapGenerator.generate(ptrng, &"camelot", 1, 1.4, false)
	var added := 0
	var added_are_elites := true
	for cid in court_map.pledge_changes:
		if court_map.pledge_changes[cid] == &"elite_added":
			added += 1
			if court_map.nodes[cid].node_type != MapNode.NodeType.ELITE:
				added_are_elites = false
	_check("Court pledge adds recorded new elites", added > 0 and added_are_elites)

	ptrng.seed = 11
	var folk_map := MapGenerator.generate(ptrng, &"camelot", 1, 1.0, true)
	var elite_ct := 0
	for fid in folk_map.nodes:
		if folk_map.nodes[fid].node_type == MapNode.NodeType.ELITE:
			elite_ct += 1
	var weak_records := 0
	var weak_flagged := true
	for fid in folk_map.pledge_changes:
		if folk_map.pledge_changes[fid] == &"weakened":
			weak_records += 1
			if not folk_map.nodes[fid].weakened:
				weak_flagged = false
	_check("Folk pledge weakens all existing elites (flagged + recorded)",
		elite_ct > 0 and weak_records == elite_ct and weak_flagged)

	_check("a neutral map records no pledge changes",
		MapGenerator.generate(RandomNumberGenerator.new(), &"camelot", 1, 1.0, false).pledge_changes.is_empty())

	# Raider questline placement: a camelot act-1 map seats a giver (an event node) and a
	# payoff that is DOWNSTREAM of and FORWARD-REACHABLE FROM it, so an accepted quest can
	# never be stranded. Checked across seeds; placement should essentially always succeed.
	var q_placed := 0
	var q_payoff_ok := true
	var q_giver_is_event := true
	for s in range(40):
		var qrng := RandomNumberGenerator.new()
		qrng.seed = 200 + s
		var qmap := MapGenerator.generate(qrng, &"camelot", 1, 1.0, false)
		var giver_id := -1
		var payoff_id := -1
		for id in qmap.nodes:
			if qmap.nodes[id].quest_giver_id == &"raiders":
				giver_id = id
			if qmap.nodes[id].quest_payoff_id == &"raiders":
				payoff_id = id
		if giver_id == -1 or payoff_id == -1:
			continue
		q_placed += 1
		if qmap.nodes[giver_id].node_type != MapNode.NodeType.EVENT:
			q_giver_is_event = false
		var reach := _forward_reachable(qmap, giver_id)
		if not reach.has(payoff_id) \
				or qmap.nodes[payoff_id].floor_num <= qmap.nodes[giver_id].floor_num:
			q_payoff_ok = false
	_check("raider questline places a giver + payoff on most seeds", q_placed >= 36)
	_check("quest giver is an event node", q_giver_is_event)
	_check("quest payoff is downstream + forward-reachable from the giver", q_payoff_ok)

	# The payoff fight composes The Boar + two Weald Raiders (pledge-agnostic by construction).
	var band := EnemyPool.get_raider_band()
	var band_names := PackedStringArray()
	for e in band:
		band_names.append(e.enemy_name)
	_check("raider band is The Boar + two Weald Raiders",
		band.size() == 3 and band_names.count("The Boar") == 1
		and band_names.count("Weald Raider") == 2)

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

	# The liaison + boon + quest relics exist (quest pool) and never leak into reward rolls.
	_check("liaison + boon + quest relics exist in the quest pool",
		RelicPool.get_relic_by_name("Bram's Briefing") != null
		and RelicPool.get_relic_by_name("Neve's Kit") != null
		and RelicPool.get_relic_by_name("Peasant Militia") != null
		and RelicPool.get_relic_by_name("Blooded Edge") != null)
	var reward_names := PackedStringArray()
	var boon_rng := RandomNumberGenerator.new()
	boon_rng.seed = 5
	for i in 30:
		for r in RelicPool.get_reward_choices(boon_rng, 3):
			reward_names.append(r.relic_name)
	_check("boon + quest relics stay out of reward rolls",
		"Bram's Briefing" not in reward_names
		and "Neve's Kit" not in reward_names
		and "Peasant Militia" not in reward_names
		and "Blooded Edge" not in reward_names)

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


## The Oct-2026 faction/liaison events: Scriptorium (Bram, folk-gated), Tourney (court-
## gated), Last Cart Out (Neve). Each must be in the random pool, with its gated option
## wired to the right faction so the pledge opens one side and locks the other.
func _test_new_events() -> void:
	var by_name := {}
	for ev in EventPool._build_pool():
		by_name[ev.event_name] = ev
	_check("The Scriptorium, The Tourney, and The Last Cart Out are in the pool",
		by_name.has("The Scriptorium") and by_name.has("The Tourney")
		and by_name.has("The Last Cart Out"))

	var scriptorium: EventData = by_name.get("The Scriptorium")
	var has_folk_gate := false
	if scriptorium:
		for ch in scriptorium.choices:
			if ch.requires_favor == &"folk":
				has_folk_gate = true
	_check("The Scriptorium has a folk-gated option", has_folk_gate)

	var tourney: EventData = by_name.get("The Tourney")
	var has_court_gate := false
	if tourney:
		for ch in tourney.choices:
			if ch.requires_favor == &"court":
				has_court_gate = true
	_check("The Tourney has a court-gated option", has_court_gate)

	var cart: EventData = by_name.get("The Last Cart Out")
	_check("The Last Cart Out offers a spread of choices",
		cart != null and cart.choices.size() >= 3)


## The Room That Isn't (Cass's intro) is scheduled as the guaranteed 2nd event of a Camelot
## run, and its step-in grants the "house_that_was" memory card. Verifies the end-to-end
## wiring: start_run registration -> the scheduling ordinal -> a resolvable grant id.
func _test_scheduled_room() -> void:
	RunManager.start_run(CharacterPool.build_emo_hybrid())  # defaults to camelot
	_check("a Camelot run schedules The Room as the 2nd event",
		RunManager.scripted_event_schedule.get(2, &"") == &"room_that_isnt")
	RunManager.ordinary_event_count = 0
	RunManager.next_ordinary_event_script()                 # 1st event: random
	_check("the 2nd ordinary event resolves to The Room",
		RunManager.next_ordinary_event_script() == &"room_that_isnt")
	_check("The Room's granted memory card resolves",
		CardPool.get_memory_card(&"house_that_was") != null)
	# start_run reset the run; restore the suite's baseline character + passion + encounter bag.
	_setup_run_state()
	EnemyPool.reset_encounter_state()


## Memory ("Remembrance") cards (Oct 2026): the three Emo/Cairn memory cards and their
## new mechanics -- a player heal that shows in combat, Passion-distance-scaled damage with
## an on-kill energy refund, and a run-persistent decaying draw. Each is flagged is_memory,
## RARE, and kept out of the normal reward pools by construction.
func _test_memory_cards() -> void:
	var house := CardPool.get_memory_card(&"house_that_was")
	var carried := CardPool.get_memory_card(&"everything_i_carried_out")
	var name_card := CardPool.get_memory_card(&"name_i_gave_myself")
	_check("all three memory cards build by id",
		house != null and carried != null and name_card != null)
	_check("memory cards are flagged is_memory + RARE",
		house.is_memory and carried.is_memory and name_card.is_memory
		and house.rarity == CardData.CardRarity.RARE)
	_check("get_memory_card returns null for an unknown id",
		CardPool.get_memory_card(&"nope") == null)
	_check("build_memory_cards returns all three", CardPool.build_memory_cards().size() == 3)
	_check("duplicate_card preserves is_memory", house.duplicate_card().is_memory)

	# Memory cards never leak into the normal card pools (gated by construction).
	var leaked := false
	for c in CardPool.build_emo_primary_pool() + CardPool.build_emo_secondary_pool():
		if c.is_memory:
			leaked = true
	_check("no memory card appears in the normal Emo pools", not leaked)

	# Card 1 (The House That Was): its heal routes through the live player_stats so it
	# actually shows in combat (not RunManager, which would be clobbered on win). Play it
	# wounded and the combat HP goes up, block lands, and Intangible is applied.
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 80, [_dummy_attacker()])  # wounded 50/80
	RunManager.passion.current_value = 0
	var healed_fired := [false]
	var on_heal := func(_amt, _hp): healed_fired[0] = true
	Events.player_healed.connect(on_heal)
	var h := house.duplicate_card()
	eng.piles.hand.append(h)
	eng.energy = 3
	eng.play_card(h, eng.player_stats)
	_check("House That Was heals the live combat HP (+6) and fires player_healed",
		eng.player_stats.current_hp == 56 and healed_fired[0])
	_check("House That Was lands block + Intangible",
		eng.player_stats.block == 15 and eng.player_stats.has_status(StatusEffects.INTANGIBLE))
	Events.player_healed.disconnect(on_heal)
	eng.free()

	# Card 2 (Everything I Carried Out): damage scales with Passion distance from center,
	# and felling the target refunds energy. At Passion 12 (Steady, zone flat), distance 12
	# / divisor 4 = +3, so 8 -> 11 before the self-Strength (which applies after the hit).
	var eng2 := CombatEngine.new()
	add_child(eng2)
	eng2.start_combat([], 50, 50, [_dummy_attacker()])  # 100-HP dummy, 0 block
	RunManager.passion.current_value = 12
	var carried_hit := carried.duplicate_card()
	eng2.piles.hand.append(carried_hit)
	eng2.energy = 3
	var hp_before := eng2.enemies[0].stats.current_hp
	eng2.play_card(carried_hit, eng2.enemies[0].stats)
	_check("Everything I Carried Out scales with Passion distance (8 +12/4 = 11 at dist 12)",
		eng2.enemies[0].stats.current_hp == hp_before - 11)
	_check("Everything I Carried Out grants self-Strength",
		eng2.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 3)
	eng2.free()

	# On-kill energy refund: a low-HP target felled by the burst gives 2 energy back.
	var eng3 := CombatEngine.new()
	add_child(eng3)
	eng3.start_combat([], 50, 50, [_dummy_attacker()])
	RunManager.passion.current_value = 0
	eng3.enemies[0].stats.current_hp = 5  # the 8 base will fell it
	var finisher := carried.duplicate_card()
	eng3.piles.hand.append(finisher)
	eng3.energy = 3  # pays 2 -> 1, then +2 on kill -> 3
	eng3.play_card(finisher, eng3.enemies[0].stats)
	_check("Everything I Carried Out refunds 2 energy on a kill",
		eng3.enemies[0].stats.is_dead() and eng3.energy == 3)
	eng3.free()
	RunManager.passion.current_value = 0

	# Card 3 (The Name I Gave Myself): the draw decays by 1 each play and persists on the
	# instance (run-persistent). A fresh instance starts at 4.
	var nc := name_card.duplicate_card()
	var draw_eff: DrawEffect = null
	for e in nc.effects:
		if e is DrawEffect:
			draw_eff = e
	_check("Name I Gave Myself has a decaying draw starting at 4",
		draw_eff != null and draw_eff.value == 4 and draw_eff.decay_per_play == 1)
	var deng := CombatEngine.new()
	add_child(deng)
	deng.start_combat([], 50, 50, [_dummy_attacker()])
	draw_eff.apply(null, null, deng)
	var after1 := draw_eff.value
	draw_eff.apply(null, null, deng)
	var after2 := draw_eff.value
	_check("the draw forgets itself across plays (4 -> 3 -> 2)", after1 == 3 and after2 == 2)
	_check("duplicate_card preserves the decay state (a copy keeps the current count)",
		nc.duplicate_card().effects.any(func(e): return e is DrawEffect and e.value == 2))
	deng.free()


## The Reliquary (multi-stage memory event): the entry is in the random pool and chains into
## the struck beat with an HP cost; the chapel-beast mini-boss builds; the Vigil Candle payoff
## relic exists and stays out of reward rolls; and The Compassionate title is distinct from
## The Merciful. The struck/won prose beats live in event_scene (verified by compile + live).
func _test_reliquary() -> void:
	var reliq: EventData = null
	for ev in EventPool._build_pool():
		if ev.event_name == "The Reliquary":
			reliq = ev
	var chains := false
	var costs_hp := false
	if reliq:
		for ch in reliq.choices:
			if ch.next_event_id == &"reliquary_struck":
				chains = true
				if ch.hp_change < 0:
					costs_hp = true
	_check("The Reliquary entry is in the pool and chains to the struck beat with an HP cost",
		reliq != null and chains and costs_hp)

	# The chapel beast mini-boss: a multi-hit torrent + a self-heal reform (the "off the walls").
	var choir := EnemyPool.the_shattered_choir()
	var has_glass := false
	var has_reform_heal := false
	for m in choir.moves:
		if m.move_name == "Raining Glass":
			for e in m.effects:
				if e is DamageEffect and e.hits >= 3:
					has_glass = true
		if m.move_name == "Reform":
			for e in m.effects:
				if e is HealEffect and e.apply_to_source:
					has_reform_heal = true
	_check("The Shattered Choir has a multi-hit torrent + a self-heal reform",
		choir.enemy_name == "The Shattered Choir" and has_glass and has_reform_heal)

	# The Vigil Candle payoff relic (quest pool), and it never leaks into reward rolls.
	var candle := RelicPool.get_relic_by_name("Vigil Candle")
	_check("Vigil Candle draws an extra card at combat start",
		candle != null and candle.trigger == RelicData.RelicTrigger.ON_COMBAT_START
		and candle.effect == RelicData.RelicEffect.DRAW_CARDS)
	var names := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 30:
		for r in RelicPool.get_reward_choices(rng, 3):
			names.append(r.relic_name)
	_check("Vigil Candle stays out of reward rolls", "Vigil Candle" not in names)

	# The Compassionate: a +6 Max HP personality title, mechanically distinct from The Merciful.
	var comp := TitlePool.get_title(&"the_compassionate")
	var merc := TitlePool.get_title(&"the_merciful")
	_check("The Compassionate is a +6 Max HP personality title, distinct from The Merciful",
		comp != null and comp.category == TitleData.Category.PERSONALITY
		and comp.passive_effect == TitleData.EffectType.MAX_HP_BONUS and comp.original_value == 6
		and merc != null and merc.passive_effect != comp.passive_effect)


## Event scheduling (Step 2 tech): a scripted beat can be pinned to the player's Nth
## ordinary event while the rest stay random. The ordinal advances once per ordinary event,
## and only the scheduled ordinal returns an id (everything else draws from the pool).
func _test_event_scheduling() -> void:
	var saved_schedule = RunManager.scripted_event_schedule
	var saved_count := RunManager.ordinary_event_count
	RunManager.scripted_event_schedule = {2: &"test_beat"}
	RunManager.ordinary_event_count = 0
	var first := RunManager.next_ordinary_event_script()
	var second := RunManager.next_ordinary_event_script()
	var third := RunManager.next_ordinary_event_script()
	_check("1st ordinary event draws random (no scripted id)", first == &"")
	_check("2nd ordinary event serves the scheduled beat", second == &"test_beat")
	_check("3rd ordinary event draws random again", third == &"")
	_check("the ordinal advances once per ordinary event", RunManager.ordinary_event_count == 3)
	RunManager.scripted_event_schedule = saved_schedule
	RunManager.ordinary_event_count = saved_count


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
	_check("Court adds elites + richer loot; Folk weakens elites + carries the militia boon",
		entry.choices[0].config.elite_frequency_mult > 1.0
		and entry.choices[0].config.reward_rarity_mult > 1.0
		and entry.choices[1].config.elite_weaken
		and entry.choices[1].config.map_boon == &"militia")
	# The common-folk pledge shoves Passion to tier-1 Physical (Wavering) from the Steady
	# start; Court leaves it alone.
	var folk_cfg := entry.choices[1].config
	_check("folk pledge shifts Passion toward Physical, landing tier-1 (Wavering)",
		folk_cfg.passion_shift < 0
		and RunManager.get_passion_tier_for_value(folk_cfg.passion_shift) == PassionState.Tier.WAVERING)
	_check("court pledge leaves Passion unmoved", entry.choices[0].config.passion_shift == 0)

	# Favor axis: the pledge plants court<->folk standing past the favor threshold so the
	# aligned side's gated options unlock at once and the opposed side's do not.
	_check("Court pledge plants court favor; Folk pledge plants the people's favor",
		entry.choices[0].config.standing_init <= -RunManager.FAVOR_THRESHOLD
		and entry.choices[1].config.standing_init >= RunManager.FAVOR_THRESHOLD)
	RunManager.set_realm_standing(&"camelot", entry.choices[0].config.standing_init)
	var court_ok := RunManager.has_court_favor(&"camelot") and not RunManager.has_folk_favor(&"camelot")
	RunManager.set_realm_standing(&"camelot", entry.choices[1].config.standing_init)
	var folk_ok := RunManager.has_folk_favor(&"camelot") and not RunManager.has_court_favor(&"camelot")
	_check("standing resolves to the right faction's favor", court_ok and folk_ok)
	# A swing out of the pledged band drops that favor before the other side's is earned.
	RunManager.set_realm_standing(&"camelot", 25)
	RunManager.change_realm_standing(&"camelot", -30)  # 25 -> -5
	_check("a standing swing drops you out of the pledged favor",
		not RunManager.has_folk_favor(&"camelot") and not RunManager.has_court_favor(&"camelot"))
	RunManager.realm_standing.clear()

	# The tithe exposes both a folk-gated and a court-gated option (the pledge opens one,
	# locks the other) plus standing nudges on the plain choices.
	var tithe: EventData = null
	for ev in EventPool._build_pool():
		if ev.event_name == "The Peasant's Plea":
			tithe = ev
			break
	var has_folk_gate := false
	var has_court_gate := false
	var moves_standing := false
	if tithe:
		for ch in tithe.choices:
			if ch.requires_favor == &"folk":
				has_folk_gate = true
			if ch.requires_favor == &"court":
				has_court_gate = true
			if ch.standing_change != 0:
				moves_standing = true
	_check("the tithe gates a folk and a court option and moves standing",
		has_folk_gate and has_court_gate and moves_standing)

	# People's champion: the bar sits above the Folk pledge alone, so it takes the pledge
	# plus at least one pro-folk act (e.g. the tithe's folk option, +12) to clear it.
	var folk_init: int = entry.choices[1].config.standing_init
	_check("people's-champion bar sits above the folk pledge alone",
		RunManager.PEOPLES_CHAMPION_THRESHOLD > folk_init)
	RunManager.set_realm_standing(&"camelot", folk_init + 12)
	var champ_reached := RunManager.is_peoples_champion(&"camelot")
	RunManager.set_realm_standing(&"camelot", folk_init)
	var champ_not_from_pledge := not RunManager.is_peoples_champion(&"camelot")
	_check("pledge + one pro-folk act makes a people's champion; the pledge alone does not",
		champ_reached and champ_not_from_pledge)
	RunManager.realm_standing.clear()

	# The People's Champion ending title exists as a (non-degrading) personality trait.
	var pc := TitlePool.get_title(&"peoples_champion")
	_check("The People's Champion title exists (personality)",
		pc != null and pc.category == TitleData.Category.PERSONALITY
		and pc.original_name == "The People's Champion")

	# Run-start queue: send-off -> entry -> map (what vn_scene._finish walks).
	RunManager.pending_vn = sendoff
	RunManager.pending_vn_queue.clear()
	RunManager.pending_vn_queue.append(entry)
	_check("queue advances send-off -> realm-entry",
		RunManager.pending_vn_queue.pop_front() == entry
		and RunManager.pending_vn_queue.is_empty())
	RunManager.pending_vn = null


## Intro gating (ProfileManager): the full two-liaison introduction shows the first time
## on a save, then a single liaison per run, and the settings toggle forces it back on.
## Leaves the profile at fresh defaults so a later real play still gets the intro.
func _test_profile_intro() -> void:
	ProfileManager.set_always_show_intro(false)
	ProfileManager.reset_seen_cutscenes()
	_check("fresh profile shows the full intro", ProfileManager.should_show_full_intro())
	ProfileManager.mark_seen(ProfileManager.CUTSCENE_INTRO)
	_check("intro id is recorded as seen", ProfileManager.has_seen(ProfileManager.CUTSCENE_INTRO))
	_check("after seeing it, the full intro is suppressed",
		not ProfileManager.should_show_full_intro())
	ProfileManager.set_always_show_intro(true)
	_check("always-show toggle forces the full intro back on",
		ProfileManager.should_show_full_intro())
	ProfileManager.set_always_show_intro(false)

	# The single-liaison send-off builds for either liaison and is shorter than the full one.
	var full := VNPool.build_sendoff(RunManager.current_character)
	var bram := VNPool.build_sendoff_single(RunManager.current_character, &"bram")
	var neve := VNPool.build_sendoff_single(RunManager.current_character, &"neve")
	_check("single-liaison send-off builds for Bram + Neve, shorter than the full intro",
		bram.beats.size() > 0 and neve.beats.size() > 0
		and bram.beats.size() < full.beats.size() and neve.beats.size() < full.beats.size())

	# Restore fresh defaults so running this suite doesn't consume the player's intro.
	ProfileManager.reset_seen_cutscenes()


func _count_elites(map: MapData) -> int:
	var n := 0
	for id in map.nodes:
		if map.nodes[id].node_type == MapNode.NodeType.ELITE:
			n += 1
	return n


## Node ids reachable by walking forward (next_nodes) from start_id, excluding start.
## Mirrors MapGenerator._reachable_from so the questline reachability guarantee is tested.
func _forward_reachable(map: MapData, start_id: int) -> Dictionary:
	var seen := {}
	var stack: Array[int] = [start_id]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		for nxt in map.nodes[id].next_nodes:
			if not seen.has(nxt):
				seen[nxt] = true
				stack.append(nxt)
	return seen


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
			"res://scenes/settings/settings_scene.gd",
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
