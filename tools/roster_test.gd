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
	# No sound: every play() here would be kept until the test ends (see AudioManager.enabled).
	AudioManager.enabled = false
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
	_test_sword_guardian()
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
	_test_title_relic_reworks()
	_test_swords_bearer_curve()
	_test_thurible()
	_test_event_reworks()
	_test_consumables()
	_test_consumable_ui()
	_test_hover_note()
	await _test_one_card_look()
	_test_pets()
	_test_master_of_game()
	_test_map_node_looks()
	_test_card_face_words()
	_test_forgotten_relics()
	_test_relic_names()
	_test_liaison_relics()
	_test_refusals()
	_test_title_split()
	_test_the_unfading()
	_test_outlander_home()
	await _test_set_pieces()
	_test_king_abroad()
	_test_vn_data()
	_test_profile_intro()
	await _test_vn_setting_lines()
	await _test_entry_trade()
	_test_boss_reward()
	await _test_frozen_skips()
	await _test_chilled_freeze()
	_test_inner_fire_copies_itself()
	_test_combat_retains_nothing()
	_test_whole_and_hollow()
	_test_every_sheet_is_baked()
	_test_rewards_follow_the_run_seed()
	_test_harness_copy_matches_engine()
	_test_harness_copy_card_rules()
	_test_harness_copy_new_rules()
	_test_harness_policy_decides()
	await _test_map_flourish()
	await _test_map_key()
	await _test_crossing_stage()
	await _test_event_page()
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
	_check("combat opener is a lone Unmarked Knight",
		enc.size() == 1 and enc[0].enemy_name == "Unmarked Knight")


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
	_check("Unwritten is unplayable + NEGATIVE",
		curse.unplayable and curse.personality == CardData.PersonalityType.NEGATIVE)
	_check("duplicate_card preserves unplayable", curse.duplicate_card().unplayable)
	var shade := EnemyPool.realm_shade()
	var has_corrupt := false
	for m in shade.moves:
		if m.move_name == "Unwrite":
			has_corrupt = true
	_check("Realm Shade has an Unwrite move", has_corrupt)
	# The full chain: AddCardEffect -> engine.add_card_to_pile -> draw pile.
	var eng := CombatEngine.new()
	eng.piles = PileManager.new()
	eng.piles.setup([])
	var eff = EnemyPool._add_curse()
	eff.apply(null, null, eng)
	_check("Unwrite shuffles one unplayable card into the draw pile",
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
	_check("Masterless Squire exists with Expose Weakness",
		squire.enemy_name == "Masterless Squire" and _has_move(squire, "Expose Weakness"))

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


## The Oct-2026 content-furnishing enemies: the reach-pierce Pikeman, the escalation
## Hollow Herald, the Poison-stacking Wasting Knight, and the self-healing Hollow Prelate
## elite. Each is checked for its signature mechanic end-to-end through the real engine.
func _test_content_enemies() -> void:
	# Pikeman: the Pike Thrust carries pierce, and a piercing hit bypasses part of block.
	var cross := EnemyPool.corrupted_pikeman()
	var bolt := _move_by_name(cross, "Pike Thrust")
	var bolt_pierce := 0
	if bolt:
		for e in bolt.effects:
			if e is DamageEffect:
				bolt_pierce = e.pierce
	_check("Pikeman's Pike Thrust pierces block", bolt != null and bolt_pierce > 0)

	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [EnemyPool.corrupted_pikeman()])
	eng.player_stats.gain_block(10)
	# 11 dmg, pierce 5: 5 bypasses block straight to HP, the other 6 soaks block (10 -> 4).
	bolt.effects[0].apply(eng.enemies[0].stats, eng.player_stats, eng)
	_check("a piercing thrust bypasses part of block (HP -5, block 10 -> 4)",
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
	var standard := _move_by_name(herald, "Blank Standard")
	var is_banner := false
	if standard:
		for e in standard.effects:
			if e is StatusApplyEffect and e.apply_to_allies \
					and e.status_effect == StatusEffects.STRENGTH:
				is_banner = true
	_check("Herald's Blank Standard buffs all allies' Strength", standard != null and is_banner)

	var heng := CombatEngine.new()
	add_child(heng)
	heng.start_combat([], 50, 50, [EnemyPool.hollow_herald(), _dummy_attacker()])
	standard.effects[0].apply(heng.enemies[0].stats, heng.player_stats, heng)
	standard.effects[0].apply(heng.enemies[0].stats, heng.player_stats, heng)
	_check("the banner ramps the group's Strength each turn (+1 -> +2 on the ally)",
		heng.enemies[1].stats.get_status_stacks(StatusEffects.STRENGTH) == 2
		and heng.enemies[0].stats.get_status_stacks(StatusEffects.STRENGTH) == 2)
	heng.free()

	# Wasting Knight: the Waste stacks Poison on the player, which then bleeds through on tick.
	var rot := EnemyPool.rotting_knight()
	_check("Wasting Knight exists with Wasting Cut + The Waste",
		rot.enemy_name == "Wasting Knight"
		and _has_move(rot, "Wasting Cut") and _has_move(rot, "The Waste"))
	var reng := CombatEngine.new()
	add_child(reng)
	reng.start_combat([], 50, 50, [EnemyPool.rotting_knight()])
	_move_by_name(rot, "The Waste").effects[0].apply(
		reng.enemies[0].stats, reng.player_stats, reng)
	_check("The Waste puts 5 Poison on the player (front-loaded rework)",
		reng.player_stats.get_status_stacks(StatusEffects.POISON) == 5)
	reng.tick_start_of_turn(reng.player_stats)
	_check("Poison bleeds through on tick (HP -5, Poison 5 -> 4)",
		reng.player_stats.current_hp == 45
		and reng.player_stats.get_status_stacks(StatusEffects.POISON) == 4)
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

	# Campfire treasure: a random fire exposes a cache node downstream of the player. Over
	# seeds, standing at an early-interior node finds a valid payoff (so the selection gate
	# rarely has to swap the Campfire out), and any picked payoff is a COMBAT node strictly
	# downstream, forward-reachable, and not already reserved (never the raider payoff).
	var t_available := 0
	var t_pick_ok := true
	for s in range(40):
		var trng := RandomNumberGenerator.new()
		trng.seed = 500 + s
		var tmap := MapGenerator.generate(trng, &"camelot", 1, 1.0, false)
		var from_id := -1
		for id in tmap.nodes:
			if tmap.nodes[id].floor_num == 3:
				from_id = id
				break
		if from_id == -1:
			continue
		if not MapGenerator.has_treasure_payoff(tmap, from_id):
			continue
		t_available += 1
		var pid := MapGenerator.pick_treasure_payoff(tmap, from_id, trng)
		if pid == -1:
			t_pick_ok = false
			continue
		var pn: MapNode = tmap.nodes[pid]
		if pn.node_type != MapNode.NodeType.COMBAT \
				or pn.floor_num <= tmap.nodes[from_id].floor_num \
				or pn.quest_payoff_id != &"" \
				or not _forward_reachable(tmap, from_id).has(pid):
			t_pick_ok = false
	_check("campfire treasure finds a downstream payoff from an early node on most seeds",
		t_available >= 30)
	_check("campfire treasure pick is a downstream, forward-reachable, unreserved combat node",
		t_pick_ok)

	# The barrow-warden treasure fight is a solo, elite-weight body; its relic is quest-only.
	var warden := EnemyPool.get_barrow_warden()
	_check("barrow-warden is a solo fight (The Barrow-Warden)",
		warden.size() == 1 and warden[0].enemy_name == "The Barrow-Warden")
	_check("Barrow-Warden's Mail exists in the quest pool",
		RelicPool.get_relic_by_name("Barrow-Warden's Mail") != null)

	# The selection gate: treasure-reveal events are dropped when no payoff is allowed, and
	# reachable when it is. (The Campfire is the only such event.)
	var gate_rng := RandomNumberGenerator.new()
	gate_rng.seed = 77
	var saw_campfire_when_blocked := false
	for i in 200:
		if EventPool.get_random_event_filtered(gate_rng, false).requires_treasure_payoff:
			saw_campfire_when_blocked = true
			break
	_check("treasure-reveal events are excluded when no payoff is available",
		not saw_campfire_when_blocked)
	var saw_campfire_when_allowed := false
	for i in 400:
		if EventPool.get_random_event_filtered(gate_rng, true).requires_treasure_payoff:
			saw_campfire_when_allowed = true
			break
	_check("treasure-reveal events can appear when a payoff is available",
		saw_campfire_when_allowed)

	# The Campfire event carries the cache-reveal option (arms_quest = campfire) + the gate flag.
	var campfire_ev: EventData = null
	for ev in EventPool._build_pool():
		if ev.requires_treasure_payoff:
			campfire_ev = ev
			break
	var campfire_has_arm := false
	if campfire_ev:
		for ch in campfire_ev.choices:
			if ch.arms_quest == &"campfire":
				campfire_has_arm = true
	_check("the Campfire event gates on a payoff and offers the cache-reveal option",
		campfire_ev != null and campfire_has_arm)

	# Multi-quest state: two questlines can be armed + tracked independently.
	RunManager.active_quests = {}
	RunManager.arm_quest(&"raiders")
	RunManager.arm_quest(&"campfire")
	_check("two questlines can be armed at once",
		RunManager.is_quest_active(&"raiders") and RunManager.is_quest_active(&"campfire"))
	RunManager.complete_quest(&"raiders")
	_check("completing one questline leaves the other active + incomplete",
		RunManager.is_quest_completed(&"raiders")
		and not RunManager.is_quest_completed(&"campfire")
		and RunManager.is_quest_active(&"campfire"))
	RunManager.mark_quest_revealed(&"raiders")
	_check("first_unrevealed_quest returns the still-unrevealed questline",
		RunManager.first_unrevealed_quest() == &"campfire")
	RunManager.active_quests = {}  # restore

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
		and RelicPool.get_relic_by_name("The People's Line") != null
		and RelicPool.get_relic_by_name("Blooded Edge") != null
		and RelicPool.get_relic_by_name("Barrow-Warden's Mail") != null)
	var reward_names := PackedStringArray()
	var boon_rng := RandomNumberGenerator.new()
	boon_rng.seed = 5
	for i in 30:
		for r in RelicPool.get_reward_choices(boon_rng, 3):
			reward_names.append(r.relic_name)
	_check("boon + quest relics stay out of reward rolls",
		"Bram's Briefing" not in reward_names
		and "Neve's Kit" not in reward_names
		and "The People's Line" not in reward_names
		and "Blooded Edge" not in reward_names
		and "Barrow-Warden's Mail" not in reward_names)

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
	_check("consume_map_boon grants the militia relic", RunManager.has_relic("The People's Line"))
	RunManager.consume_map_boon()
	var militia_count := 0
	for r in RunManager.relics:
		if r.relic_name == "The People's Line":
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
## the struck beat with an HP cost; the chapel-beast mini-boss builds; and The Compassionate
## title is distinct from The Merciful. The payoff relic (now The Thurible, which retired the
## old Vigil Candle) is covered in _test_thurible. The struck/won prose beats live in
## event_scene (verified by compile + live).
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

	# The Compassionate: a clutch-heal personality title (value 8), mechanically distinct from
	# The Merciful's post-combat heal.
	var comp := TitlePool.get_title(&"the_compassionate")
	var merc := TitlePool.get_title(&"the_merciful")
	_check("The Compassionate is a CLUTCH_HEAL personality title (8), distinct from The Merciful",
		comp != null and comp.category == TitleData.Category.PERSONALITY
		and comp.passive_effect == TitleData.EffectType.CLUTCH_HEAL and comp.original_value == 8
		and merc != null and merc.passive_effect != comp.passive_effect)
	_check("The Merciful heals per enemy death (3), off the post-combat lane",
		merc != null and merc.passive_effect == TitleData.EffectType.HEAL_ON_ENEMY_DEATH
		and merc.original_value == 3)

	# End-to-end: two bodies, two deaths, two mends, while the fight is still running.
	RunManager.award_title(&"the_merciful")
	RunManager.equip_title(0, &"the_merciful")
	var keng := CombatEngine.new()
	add_child(keng)
	keng.start_combat([], 50, 50, [_dummy_attacker(), _dummy_attacker()])
	keng.player_stats.current_hp = 20
	keng.deal_damage(keng.enemies[0].stats, 999, keng.player_stats)
	var after_one := keng.player_stats.current_hp
	keng.deal_damage(keng.enemies[1].stats, 999, keng.player_stats)
	var after_two := keng.player_stats.current_hp
	_check("The Merciful mends on each death during the fight (20 -> 23 -> 26)",
		after_one == 23 and after_two == 26)
	keng.free()
	# Freeing the engine must leave none of ITS handlers on the global death signal. The
	# signal itself keeps listeners for the life of the game (AudioManager is an autoload),
	# so the check is for the engine's own callable rather than for an empty list.
	var mercy_dangling := false
	for conn in Events.enemy_died.get_connections():
		var cb: Callable = conn["callable"]
		if cb.get_method() == &"_on_enemy_died_mercy":
			mercy_dangling = true
	_check("a freed engine leaves no dangling enemy_died connection", not mercy_dangling)
	RunManager.equip_title(0, &"")
	RunManager.earned_title_ids.erase(&"the_merciful")


## The Oct-2026 title/relic reworks, end-to-end through the real engine:
##  - The Compassionate (CLUTCH_HEAL): the first hit that drops the player below half HP mends
##    them once; it resolves before the lethal check, so a killing blow leaves them standing at
##    8 HP (death-save), and a second drop that combat does not re-trigger it.
##  - Momentum (relic): each player hit on an enemy raises attack damage by 1 for the rest of
##    the turn (first hit +0, second +1), and the ramp resets at the start of the next turn.
func _test_title_relic_reworks() -> void:
	# --- The Compassionate clutch heal ---
	RunManager.award_title(&"the_compassionate")
	RunManager.equip_title(0, &"the_compassionate")
	var ceng := CombatEngine.new()
	add_child(ceng)
	ceng.start_combat([], 50, 50, [_dummy_attacker()])  # full 50/50, half = 25
	# Drop below half: 50 -> 20, which is under 25, so the clutch mend fires once (+8 -> 28).
	ceng.deal_damage(ceng.player_stats, 30, ceng.enemies[0].stats)
	_check("The Compassionate mends once on the first drop below half HP (20 -> 28)",
		ceng.player_stats.current_hp == 28)
	# A second drop below half the same combat does NOT re-trigger (28 -> 23, no heal).
	ceng.deal_damage(ceng.player_stats, 5, ceng.enemies[0].stats)
	_check("the clutch heal fires only once per combat (28 -> 23, no re-heal)",
		ceng.player_stats.current_hp == 23)
	ceng.free()

	# Death-save: resolved before the lethal check, an otherwise-killing first blow (HP floors
	# at 0) leaves the player alive at the heal value (8) rather than dead.
	var deng := CombatEngine.new()
	add_child(deng)
	deng.start_combat([], 50, 50, [_dummy_attacker()])
	deng.deal_damage(deng.player_stats, 80, deng.enemies[0].stats)  # lethal: 50 -> 0 -> mend to 8
	_check("The Compassionate catches a killing blow (survives at 8, not dead)",
		deng.player_stats.current_hp == 8 and deng.phase != CombatEngine.Phase.BATTLE_LOST)
	deng.free()
	RunManager.equip_title(0, &"")
	RunManager.earned_title_ids.erase(&"the_compassionate")

	# --- Momentum relic ramp ---
	var mom := RelicPool.get_relic_by_name("Momentum")
	_check("Momentum is a RARE relic (value 1)",
		mom != null and mom.rarity == RelicData.RelicRarity.RARE and mom.value == 1)
	RunManager.relics.clear()
	RunManager.add_relic(mom)
	var meng := CombatEngine.new()
	add_child(meng)
	meng.start_combat([], 50, 50, [_dummy_attacker()])  # 100-HP dummy, 0 block
	var dummy := meng.enemies[0].stats
	var hp_before := dummy.current_hp
	meng.deal_damage(dummy, 5, meng.player_stats)  # 1st hit: +0 momentum -> 5
	var after_first := dummy.current_hp
	meng.deal_damage(dummy, 5, meng.player_stats)  # 2nd hit: +1 momentum -> 6
	var after_second := dummy.current_hp
	_check("Momentum's 2nd hit deals 1 more than the 1st (5 then 6)",
		hp_before - after_first == 5 and after_first - after_second == 6)
	# The ramp resets at the start of the next player turn (back to a 5-damage first hit).
	meng.start_player_turn()
	var hp_turn2 := dummy.current_hp
	meng.deal_damage(dummy, 5, meng.player_stats)
	_check("Momentum resets each turn (first hit of the new turn deals 5 again)",
		hp_turn2 - dummy.current_hp == 5)
	meng.free()
	RunManager.relics.clear()


## The Thurible (the Reliquary censer toggle relic): it exists as a quest-only RARE read
## directly by the engine (NONE effect, swing 3 at turn-start); never leaks into reward rolls;
## the old Vigil Candle it replaced is retired; the mode toggles both ways and defaults Blazing;
## and end-to-end the turn-start swing pushes Passion +3 in Blazing mode / -3 in Hollow mode.
func _test_thurible() -> void:
	var thur := RelicPool.get_relic_by_name("The Thurible")
	_check("The Thurible exists (quest-only RARE, NONE effect read directly, swing 3 at turn start)",
		thur != null and thur.rarity == RelicData.RelicRarity.RARE
		and thur.effect == RelicData.RelicEffect.NONE and thur.value == 3
		and thur.trigger == RelicData.RelicTrigger.ON_TURN_START)
	# Quest-only: never leaks into post-combat reward rolls (like Excalibur / the other quest relics).
	var names := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 30:
		for r in RelicPool.get_reward_choices(rng, 3):
			names.append(r.relic_name)
	_check("The Thurible stays out of reward rolls", "The Thurible" not in names)
	# The old Vigil Candle it replaced is fully retired from both relic pools.
	_check("Vigil Candle is retired (superseded by The Thurible)",
		RelicPool.get_relic_by_name("Vigil Candle") == null)

	# The per-fight mode toggles both directions; a fresh run defaults it to Blazing.
	RunManager.thurible_mode = RunManager.ThuribleMode.BLAZING
	RunManager.toggle_thurible_mode()
	_check("toggle_thurible_mode swings Blazing -> Hollow",
		RunManager.thurible_mode == RunManager.ThuribleMode.HOLLOW)
	RunManager.toggle_thurible_mode()
	_check("toggle_thurible_mode swings back Hollow -> Blazing",
		RunManager.thurible_mode == RunManager.ThuribleMode.BLAZING)

	# End-to-end through the real engine: with The Thurible held, each player turn-start swings
	# Passion by the mode's sign (test character volatility is 1.0, so +/-3 exactly).
	RunManager.relics.clear()
	RunManager.add_relic(thur)
	RunManager.thurible_mode = RunManager.ThuribleMode.BLAZING
	RunManager.passion.current_value = 0
	var beng := CombatEngine.new()
	add_child(beng)
	beng.start_combat([], 50, 50, [_dummy_attacker()])  # turn 1 start swings +3
	_check("The Thurible (Blazing) swings Passion +3 on turn 1",
		RunManager.passion.current_value == 3)
	beng.start_player_turn()  # next turn swings +3 again
	_check("The Thurible (Blazing) swings +3 again next turn (3 -> 6)",
		RunManager.passion.current_value == 6)
	beng.free()
	# Hollow mode pushes the other way.
	RunManager.thurible_mode = RunManager.ThuribleMode.HOLLOW
	RunManager.passion.current_value = 0
	var heng := CombatEngine.new()
	add_child(heng)
	heng.start_combat([], 50, 50, [_dummy_attacker()])  # turn 1 start swings -3
	_check("The Thurible (Hollow) swings Passion -3 on turn 1",
		RunManager.passion.current_value == -3)
	heng.free()
	RunManager.relics.clear()
	RunManager.thurible_mode = RunManager.ThuribleMode.BLAZING


## Event restructures (Oct 2026): the Tourney wager is a real win/lose gamble; its court ride
## costs HP; and the Shade at the Cross's power option is a one-shot next-combat boon that opens the
## next fight with +2 Strength and then clears.
func _test_event_reworks() -> void:
	var tourney: EventData = null
	var spirit: EventData = null
	for ev in EventPool._build_pool():
		if ev.event_name == "The Tourney":
			tourney = ev
		elif ev.event_name == "The Shade at the Cross":
			spirit = ev
	# The wager is a bet now (win/lose gold, both outcomes written), not a flat payout.
	var wager: EventData.EventChoice = tourney.choices[0] if tourney else null
	_check("The Tourney wager is a gamble (win > 0, lose < 0, both outcomes written, no flat gold)",
		wager != null and wager.gamble_win_gold > 0 and wager.gamble_lose_gold < 0
		and wager.gamble_win_text != "" and wager.gamble_lose_text != "" and wager.gold_change == 0)
	# The court ride now costs HP (jousting hurts) and stays court-gated with a card reward.
	var ride: EventData.EventChoice = null
	if tourney:
		for ch in tourney.choices:
			if ch.requires_favor == &"court":
				ride = ch
	_check("The Tourney court ride costs HP and is court-gated with a card reward",
		ride != null and ride.hp_change < 0 and ride.card_reward)
	# The Shade at the Cross's power option used to spend its courage for the player at the start of
	# the next fight (a queued boon). Part 3 made it a HELD consumable, Unspent Courage, that the
	# player spends: the same +2 Strength, with the moment chosen. See _test_consumables.
	var lend: EventData.EventChoice = null
	if spirit:
		for ch in spirit.choices:
			if ch.grants_consumable != &"":
				lend = ch
	_check("The Shade at the Cross grants the held Unspent Courage, not a queued boon",
		lend != null and lend.grants_consumable == &"unspent_courage"
		and lend.grants_combat_boon == &"" and lend.max_hp_change == 0)

	# The queued-boon primitive itself stays (no shipped event uses it now, but the mechanism and
	# its one-shot contract are still covered): a queued boon opens the next fight with +2 Strength,
	# then clears.
	RunManager.pending_combat_boon = &"wandering_vigor"
	var beng := CombatEngine.new()
	add_child(beng)
	beng.start_combat([], 50, 50, [_dummy_attacker()])
	_check("wandering_vigor opens the next combat with +2 Strength",
		beng.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 2)
	_check("the next-combat boon is one-shot (cleared once it applies)",
		RunManager.pending_combat_boon == &"")
	beng.free()
	# A second combat with nothing queued does not re-grant it.
	var beng2 := CombatEngine.new()
	add_child(beng2)
	beng2.start_combat([], 50, 50, [_dummy_attacker()])
	_check("no boon carries into a later fight (0 Strength when none queued)",
		beng2.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 0)
	beng2.free()

	# --- Forgotten Library: school-biased tomes + a relic find; Tourney walk-on skip ---
	var lib: EventData = null
	var tourney2: EventData = null
	for ev in EventPool._build_pool():
		if ev.event_name == "Forgotten Library":
			lib = ev
		elif ev.event_name == "The Tourney":
			tourney2 = ev
	var has_primary := false
	var has_secondary := false
	var has_relic_find := false
	if lib:
		for ch in lib.choices:
			if ch.card_reward and ch.card_reward_school == &"primary":
				has_primary = true
			if ch.card_reward and ch.card_reward_school == &"secondary":
				has_secondary = true
			# The search now pulls from Bram's Records pool (retro-upgraded off the old generic
			# grants_random_relic), so the ruined archive pays a scholarly relic, not a stat-stick.
			if ch.grants_liaison_relic == &"bram" and ch.hp_change < 0:
				has_relic_find = true
	# Down to four after the untitled book was cut: it offered an unschooled card beside two
	# schooled ones, so it was strictly less informative than either neighbour.
	_check("Forgotten Library offers 4 options incl. Water/Physical tomes + a costed Bram Records relic find",
		lib != null and lib.choices.size() == 4 and has_primary and has_secondary and has_relic_find)
	var lib_unschooled := false
	if lib:
		for ch in lib.choices:
			if ch.card_reward and ch.card_reward_school == &"":
				lib_unschooled = true
	_check("Forgotten Library no longer offers an unschooled card", not lib_unschooled)
	var skip_found := false
	if tourney2:
		for ch in tourney2.choices:
			if ch.skips_next_node:
				skip_found = true
	_check("The Tourney walk-on skips the next map node", skip_found)

	# A tome's reward draws from the matching school pool (needs real character card pools).
	var saved_char = RunManager.current_character
	RunManager.current_character = CharacterPool.build_emo_hybrid()
	var prim := CardPool.get_school_reward_choices(
		RngManager.loot_rng, CardData.PersonalityType.PRIMARY, 3)
	var sec := CardPool.get_school_reward_choices(
		RngManager.loot_rng, CardData.PersonalityType.SECONDARY, 3)
	var prim_ok := prim.size() == 3
	for c in prim:
		if c.personality != CardData.PersonalityType.PRIMARY:
			prim_ok = false
	var sec_ok := sec.size() == 3
	for c in sec:
		if c.personality != CardData.PersonalityType.SECONDARY:
			sec_ok = false
	_check("school-biased tome reward draws from the matching pool (Water=PRIMARY, Physical=SECONDARY)",
		prim_ok and sec_ok)
	RunManager.current_character = saved_char


## Per-liaison relic pools (Oct 2026): Bram's Records set + Neve's Dispatch set. Each is a
## dedicated quest-only pool (never in shops/reward rolls), resolvable by name so a grant lands,
## and the roller excludes owned relics. The folk liaison events + the Forgotten Library route
## their rewards through these pools (folk events pay in relics, per the §D faction principle).
func _test_liaison_relics() -> void:
	var bram := RelicPool._build_bram_pool()
	var neve := RelicPool._build_neve_pool()
	_check("Bram (Records) + Neve (Dispatch) pools build with 4+ relics each",
		bram.size() >= 4 and neve.size() >= 4)

	# Neve's pool is the reworked survival kit: Iron Rations is now per-turn regen (not a flat
	# Max-HP sponge), Hobnails (once Marching Tonic) is a Poise burst (not a Strength clone), and the duplicate
	# Broken-In Boots is cut so one Poise relic owns the lane.
	var neve_by := {}
	for r in neve:
		neve_by[r.relic_name] = r
	var rations: RelicData = neve_by.get("Iron Rations")
	var tonic: RelicData = neve_by.get("Hobnails")
	_check("Iron Rations is per-turn regen (HEAL 2 at turn start, not Max HP)",
		rations != null and rations.effect == RelicData.RelicEffect.HEAL
		and rations.trigger == RelicData.RelicTrigger.ON_TURN_START and rations.value == 2)
	_check("Hobnails is a Poise burst (+2 Dexterity/Poise at combat start, not Strength)",
		tonic != null and tonic.effect == RelicData.RelicEffect.GAIN_DEXTERITY and tonic.value == 2)
	_check("Broken-In Boots is cut (one Poise relic owns the lane)",
		not neve_by.has("Broken-In Boots"))

	# A granted liaison relic routes through granted_relic_id, so get_relic_by_name MUST resolve
	# every relic in both pools (else the grant + summary would silently find nothing).
	var all_resolve := true
	for r in bram + neve:
		if RelicPool.get_relic_by_name(r.relic_name) == null:
			all_resolve = false
	_check("every liaison relic resolves via get_relic_by_name", all_resolve)

	# Quest-only: none of the liaison relics may leak into post-combat reward rolls.
	var reward_names := PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 40:
		for r in RelicPool.get_reward_choices(rng, 3):
			reward_names.append(r.relic_name)
	var leaked := false
	for r in bram + neve:
		if r.relic_name in reward_names:
			leaked = true
	_check("liaison relics stay out of reward rolls", not leaked)

	# The roller draws only from the named pool and honors the owned-exclusion list.
	var lrng := RandomNumberGenerator.new()
	lrng.seed = 3
	var bram_names := PackedStringArray()
	for r in bram:
		bram_names.append(r.relic_name)
	var picks := RelicPool.get_liaison_relic_choices(&"bram", lrng, 1)
	_check("get_liaison_relic_choices(bram) returns a Bram-pool relic",
		picks.size() == 1 and picks[0].relic_name in bram_names)
	# Exclude all but one -- the roll must return exactly the remaining unowned relic.
	var owned := PackedStringArray()
	for i in range(bram.size() - 1):
		owned.append(bram[i].relic_name)
	var last := RelicPool.get_liaison_relic_choices(&"bram", lrng, 1, owned)
	_check("the roller skips owned relics (returns only the unowned one)",
		last.size() == 1 and last[0].relic_name == bram[bram.size() - 1].relic_name)
	# Owning the whole pool yields nothing (the grant simply no-ops).
	var all_owned := PackedStringArray()
	for r in bram:
		all_owned.append(r.relic_name)
	_check("a fully-owned pool rolls nothing",
		RelicPool.get_liaison_relic_choices(&"bram", lrng, 1, all_owned).is_empty())
	# An unknown liaison id is empty, not a crash.
	_check("unknown liaison id rolls nothing",
		RelicPool.get_liaison_relic_choices(&"nobody", lrng, 1).is_empty())

	# End-to-end grant: rolling a liaison relic and running it through the normal grant path
	# (resolve by name -> add_relic) actually equips it, the way event_scene does on selection.
	var saved_max := RunManager.max_hp
	var saved_cur := RunManager.current_hp
	RunManager.relics.clear()
	var grant := RelicPool.get_liaison_relic_choices(
		&"neve", lrng, 1, RunManager.get_owned_relic_names())
	var granted_name := grant[0].relic_name if grant.size() > 0 else ""
	var resolved := RelicPool.get_relic_by_name(granted_name)
	if resolved:
		RunManager.add_relic(resolved)
	_check("a rolled Neve relic resolves by name and equips via the normal grant path",
		granted_name != "" and RunManager.has_relic(granted_name))
	RunManager.relics.clear()
	RunManager.max_hp = saved_max  # restore HP in case a pickup-effect relic bumped it
	RunManager.current_hp = saved_cur

	# Event wiring: the folk liaison rewards + the library find route to the right pools.
	var by_name := {}
	for ev in EventPool._build_pool():
		by_name[ev.event_name] = ev
	var lib_bram := false
	for ch in by_name["Forgotten Library"].choices:
		if ch.grants_liaison_relic == &"bram":
			lib_bram = true
	var scriptorium_bram := false
	for ch in by_name["The Scriptorium"].choices:
		if ch.requires_favor == &"folk" and ch.grants_liaison_relic == &"bram":
			scriptorium_bram = true
	var cart_neve := false
	for ch in by_name["The Last Cart Out"].choices:
		if ch.grants_liaison_relic == &"neve":
			cart_neve = true
	_check("Forgotten Library + Scriptorium folk option grant Bram relics; Last Cart Out grants a Neve relic",
		lib_bram and scriptorium_bram and cart_neve)


## Refusals with teeth (Oct 2026): walking away / refusing now carries a cost. Tier 1 -- the
## folk/liaison walk-aways lose standing (or Passion for the factionless Man Off the Field);
## Tier 2 -- scattering the Shade at the Cross wedges a permanent unplayable curse into the deck.
func _test_refusals() -> void:
	var by_name := {}
	for ev in EventPool._build_pool():
		by_name[ev.event_name] = ev

	# Tier 1: the pure walk-aways that used to cost nothing now bite.
	var wounded_walk := _choice_by_text(by_name["The Man Off the Field"], "Keep walking")
	_check("The Man Off the Field's keep-walking costs Passion",
		wounded_walk != null and wounded_walk.passion_change < 0)
	var plea_walk := _choice_by_text(by_name["The Peasant's Plea"], "Walk on")
	_check("Peasant's Plea walk-on costs the people's favor",
		plea_walk != null and plea_walk.standing_change < 0)
	var cart_walk := _choice_by_text(by_name["The Last Cart Out"], "Move on")
	_check("Last Cart Out's move-on costs the people's favor",
		cart_walk != null and cart_walk.standing_change < 0)
	var scrip_leave := _choice_by_text(by_name["The Scriptorium"], "Leave")
	_check("Scriptorium's leave costs the people's favor",
		scrip_leave != null and scrip_leave.standing_change < 0)

	# Tier 2: the banish is a lingering curse now.
	var banish := _choice_by_text(by_name["The Shade at the Cross"], "Scatter him")
	_check("The Shade at the Cross's scattering wedges a curse into the deck",
		banish != null and banish.grants_curse == &"clinging_grief")

	# The curse card builds unplayable + NEGATIVE; an unknown id is null.
	var curse := CardPool.get_curse_card(&"clinging_grief")
	_check("Clinging Grief is an unplayable NEGATIVE curse card",
		curse != null and curse.unplayable
		and curse.personality == CardData.PersonalityType.NEGATIVE)
	_check("get_curse_card returns null for an unknown id",
		CardPool.get_curse_card(&"nope") == null)

	# End-to-end: granting the curse adds a permanent unplayable card to the run deck.
	var saved_deck := RunManager.current_deck.duplicate()
	RunManager.current_deck.clear()
	RunManager.add_card_to_deck(curse)
	_check("granting the curse adds an unplayable card to the run deck",
		RunManager.current_deck.size() == 1 and RunManager.current_deck[0].unplayable)
	RunManager.current_deck = saved_deck


## The Merciful split (Oct 2026): a second kindness title, The Gracious, so a run's repeat
## good-acts aren't wasted on a title already held. Distinct passive from the mercy-heal lane,
## and the kindness grants are spread across both titles in the event pool.
func _test_title_split() -> void:
	var grace := TitlePool.get_title(&"the_gracious")
	var merc := TitlePool.get_title(&"the_merciful")
	_check("The Gracious widens card rewards by 1 (personality), distinct from The Merciful's heal",
		grace != null and grace.category == TitleData.Category.PERSONALITY
		and grace.passive_effect == TitleData.EffectType.CARD_REWARD_CHOICES
		and grace.original_value == 1
		and merc != null and grace.passive_effect != merc.passive_effect)
	# Equipped, it reads through the one accessor every reward site uses.
	var saved_slots := RunManager.active_title_slots.duplicate()
	var had_grace := RunManager.earned_title_ids.has(&"the_gracious")
	RunManager.award_title(&"the_gracious")
	RunManager.equip_title(0, &"the_gracious")
	var bonus_worn := RunManager.get_card_reward_bonus()
	RunManager.equip_title(0, &"")
	var bonus_bare := RunManager.get_card_reward_bonus()
	_check("The Gracious adds a reward option only while worn",
		bonus_worn == 1 and bonus_bare == 0)
	# A widened reward really does offer the extra card rather than silently capping at 3.
	var wide := CardPool.get_reward_choices(RngManager.loot_rng, 4)
	_check("a widened card reward offers 4 distinct cards", wide.size() == 4)
	RunManager.active_title_slots = saved_slots
	if not had_grace:
		RunManager.earned_title_ids.erase(&"the_gracious")
	# The Shade at the Cross must not pay max HP on the same option that grants the title.
	var shade_grant: EventData.EventChoice = null
	for ev in EventPool._build_pool():
		if ev.event_name != "The Shade at the Cross":
			continue
		for ch in ev.choices:
			if ch.awarded_title_id == &"the_gracious":
				shade_grant = ch
	_check("The Shade at the Cross no longer pays max HP alongside The Gracious",
		shade_grant != null and shade_grant.max_hp_change == 0)
	var grants_gracious := 0
	var grants_merciful := 0
	for ev in EventPool._build_pool():
		for ch in ev.choices:
			if ch.awarded_title_id == &"the_gracious":
				grants_gracious += 1
			elif ch.awarded_title_id == &"the_merciful":
				grants_merciful += 1
	_check("kindness grants are spread across events (both The Gracious and The Merciful appear)",
		grants_gracious >= 1 and grants_merciful >= 1)

	# The Compassionate's home moved out of the Reliquary and onto the route: the Last Cart
	# Out's wholehearted help, which was one of The Merciful's three redundant grant sites.
	var cart_grant: EventData.EventChoice = null
	for ev in EventPool._build_pool():
		if ev.event_name != "The Last Cart Out":
			continue
		for ch in ev.choices:
			if ch.awarded_title_id == &"the_compassionate":
				cart_grant = ch
	_check("The Last Cart Out's lift pays The Compassionate (re-homed off the Reliquary)",
		cart_grant != null and cart_grant.standing_change > 0)


## The Unfading (TITLE_DESIGN 5.7, title wave 2), through the real engine: the first card played
## each combat comes back to the hand with its energy still spent; only the first card echoes,
## and each combat arms it anew; a spent first card (it exhausts, it is a Power, it is a Trick
## card) does not come back and uses the echo up; unworn, nothing echoes. And the Reliquary's
## won beat grants it, which leaves The Compassionate to the Last Cart Out alone.
func _test_the_unfading() -> void:
	var unf := TitlePool.get_title(&"the_unfading")
	_check("The Unfading is a personality title on its own effect, and its text says Exhaust wins",
		unf != null and unf.category == TitleData.Category.PERSONALITY
		and unf.passive_effect == TitleData.EffectType.FIRST_CARD_RETURNS
		and unf.original_description.contains("exhausts"))
	var saved_slots := RunManager.active_title_slots.duplicate()
	var had_unfading := RunManager.earned_title_ids.has(&"the_unfading")
	# No relic bonus on the hits and no companion card arriving in the hand.
	var saved_relics := RunManager.relics.duplicate()
	var saved_pet := RunManager.pet_id
	RunManager.relics.clear()
	RunManager.pet_id = &""
	RunManager.award_title(&"the_unfading")
	RunManager.equip_title(0, &"the_unfading")

	# The return, and only the first card's.
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [_dummy_attacker()])
	var first := _neutral_attack("Echo Strike", 1, 6)
	var second := _neutral_attack("Plain Strike", 1, 6)
	eng.piles.hand.append(first)
	eng.piles.hand.append(second)
	eng.energy = 3
	var dummy := eng.enemies[0].stats
	var hp0 := dummy.current_hp
	eng.play_card(first, dummy)
	_check("the first card played comes back to the hand, its 6 dealt and its energy spent (3 -> 2)",
		first in eng.piles.hand and first not in eng.piles.discard_pile
		and dummy.current_hp == hp0 - 6 and eng.energy == 2)
	eng.play_card(second, dummy)
	eng.play_card(first, dummy)
	_check("only the first card echoes: the second, and the echoed card played again, are discarded",
		second in eng.piles.discard_pile and first in eng.piles.discard_pile
		and eng.piles.hand.is_empty() and eng.energy == 0)
	# A new combat arms it again.
	eng.start_combat([], 50, 50, [_dummy_attacker()])
	var next_fight := _neutral_attack("Next Fight", 1, 6)
	eng.piles.hand.append(next_fight)
	eng.energy = 3
	eng.play_card(next_fight, eng.enemies[0].stats)
	_check("each combat arms the echo anew", next_fight in eng.piles.hand)
	eng.free()

	# Spent things stay spent, and a spent first card still uses the echo up.
	var spent_cases: Array[CardData] = []
	var exhausting := _neutral_attack("Spent Strike", 1, 6)
	exhausting.exhaust = true
	spent_cases.append(exhausting)
	var power := CardData.new()
	power.card_name = "Test Power"
	power.energy_cost = 1
	power.card_type = CardData.CardType.POWER
	power.target_type = CardData.TargetType.SELF
	spent_cases.append(power)
	var trick := _neutral_attack("Test Trick", 0, 3)
	trick.trick = true
	spent_cases.append(trick)
	var spent_ok := true
	for spent in spent_cases:
		var seng := CombatEngine.new()
		add_child(seng)
		seng.start_combat([], 50, 50, [_dummy_attacker()])
		var after := _neutral_attack("After Strike", 1, 6)
		seng.piles.hand.append(spent)
		seng.piles.hand.append(after)
		seng.energy = 3
		var tgt := seng.enemies[0].stats
		seng.play_card(spent, tgt if spent.target_type == CardData.TargetType.SINGLE_ENEMY else seng.player_stats)
		seng.play_card(after, tgt)
		if spent in seng.piles.hand or after in seng.piles.hand or after not in seng.piles.discard_pile:
			spent_ok = false
		seng.free()
	_check("a first card that exhausts, a Power or a Trick card is spent, and the echo goes with it",
		spent_ok and exhausting.exhaust and power.card_type == CardData.CardType.POWER)

	# Unworn, the first card is discarded like any other.
	RunManager.equip_title(0, &"")
	var ueng := CombatEngine.new()
	add_child(ueng)
	ueng.start_combat([], 50, 50, [_dummy_attacker()])
	var plain := _neutral_attack("Unworn Strike", 1, 6)
	ueng.piles.hand.append(plain)
	ueng.energy = 3
	ueng.play_card(plain, ueng.enemies[0].stats)
	_check("unworn, the first card goes to the discard pile",
		plain in ueng.piles.discard_pile and plain not in ueng.piles.hand)
	ueng.free()
	RunManager.active_title_slots = saved_slots
	RunManager.relics = saved_relics
	RunManager.pet_id = saved_pet
	if not had_unfading:
		RunManager.earned_title_ids.erase(&"the_unfading")

	# The grant: the Reliquary's won beat pays The Unfading; The Compassionate has one site left.
	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var won: EventData = es._build_reliquary_won_event()
	es.free()
	var reliquary_pays := &""
	for ch in won.choices:
		if ch.awarded_title_id != &"":
			reliquary_pays = ch.awarded_title_id
	var compassion_sites := 0
	for ev in EventPool._build_pool():
		for ch in ev.choices:
			if ch.awarded_title_id == &"the_compassionate":
				compassion_sites += 1
	_check("the Reliquary's won beat grants The Unfading; The Compassionate is the Last Cart Out's alone",
		reliquary_pays == &"the_unfading" and compassion_sites == 1)


## The staged moments are presentation over the event's own words. Each answer at the stone names its
## stage, each stage's line is still a whole sentence of the prose it quotes (so a rewrite of the event
## fails here instead of leaving the stage quoting something the game no longer says), each stage
## runs to its end without a player, and a held toast waits and then shows.
func _test_set_pieces() -> void:
	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var stone: EventData = es._build_sword_in_stone_event()
	var won: EventData = es._build_sword_guardian_won_event()
	es.free()
	var walk: EventData.EventChoice = null
	for ch in stone.choices:
		if ch.set_piece == &"excalibur_leave":
			walk = ch
	var take: EventData.EventChoice = won.choices[0]
	_check("taking Excalibur and leaving it each name a stage; facing the beast does not",
		take.set_piece == &"excalibur_take" and walk != null
		and _stone_fight_is_unstaged(stone))
	var taken_line := ExcaliburPiece.take_line(take)
	var left_line := ExcaliburPiece.leave_line(walk)
	_check("the stage's lines are whole sentences of the event's own prose",
		taken_line.ends_with("impossibly light.") and take.result_text.contains(taken_line)
		and left_line.begins_with("The choice not to reach") and left_line.ends_with(".")
		and walk.result_text.contains(left_line))
	_check("the words the refusal stamps and the take names still resolve",
		TitlePool.get_title(walk.awarded_title_id) != null
		and RelicPool.get_relic_by_name(String(take.granted_relic_id)) != null)
	var altar_ready := true
	for dormant_name in RelicPool.dormant_names():
		var relic := RelicPool.get_relic_by_name(dormant_name)
		var woken := RelicPool.get_relic_by_name(String(relic.wakes_into))
		if woken == null or relic.wake_line == "":
			altar_ready = false
	_check("every forgotten relic gives the altar a woken name and a line", altar_ready)
	var slots_ready := AltarPiece.figures_for(AltarPiece.HERO_RELIC).size() == 2 \
		and AltarPiece.figures_for("A Bone Comb").is_empty() \
		and ResourceLoader.exists(ExcaliburPiece.SWORD["path"]) \
		and ResourceLoader.exists(ExcaliburPiece.CHAMPION["path"])
	for dormant_name in AltarPiece.FIGURES:
		if not RelicPool.dormant_names().has(dormant_name):
			slots_ready = false
	_check("every art slot on the stages resolves, and a slot names a real forgotten relic", slots_ready)

	var host := Node.new()
	add_child(host)
	var ran := 0
	var take_piece := ExcaliburPiece.play_take(host, take, true)
	take_piece.hurry()
	await take_piece.finished
	ran += 1
	var leave_piece := ExcaliburPiece.play_leave(host, stone.event_name, walk)
	leave_piece.hurry()
	await leave_piece.finished
	ran += 1
	var altar_piece := AltarPiece.play(host, AltarPiece.HERO_RELIC)
	altar_piece.hurry()
	await altar_piece.finished
	ran += 1
	# The figureless path: a relic with no drawing yet stands on its name alone.
	var bare_piece := AltarPiece.play(host, "A Bone Comb")
	bare_piece.hurry()
	await bare_piece.finished
	ran += 1
	_check("the take, the refusal and the altar with and without a figure all run to their end", ran == 4)
	host.queue_free()

	var waiting_before: int = TitleEarnedPopup._queue.size()
	var live_before = TitleEarnedPopup._live_card
	TitleEarnedPopup.hold()
	Events.title_earned.emit(&"outlander_of_camelot")
	_check("a held toast waits in the queue and shows nothing",
		TitleEarnedPopup._queue.size() == waiting_before + 1 and TitleEarnedPopup._live_card == live_before)
	TitleEarnedPopup.release()
	_check("letting it go leaves nothing held", not TitleEarnedPopup._held)


func _stone_fight_is_unstaged(stone: EventData) -> bool:
	for ch in stone.choices:
		if ch.starts_combat != &"" and ch.set_piece != &"":
			return false
	return true


## Outlander had no award path at all (TITLE_DESIGN 5.9). Its home is the Sword in the Stone's
## walk-away (title wave 2): leaving the sword grants it, facing the beast does not, and worn
## it pays its 5 gold when a combat is won.
func _test_outlander_home() -> void:
	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var stone: EventData = es._build_sword_in_stone_event()
	es.free()
	var walk_grants := &""
	var fight_grants := &""
	for ch in stone.choices:
		if ch.starts_combat == &"sword_guardian":
			fight_grants = ch.awarded_title_id
		else:
			walk_grants = ch.awarded_title_id
	_check("leaving the sword in its stone grants Outlander; facing the beast does not",
		walk_grants == &"outlander_of_camelot" and fight_grants == &"")

	var saved_slots := RunManager.active_title_slots.duplicate()
	var had_outlander := RunManager.earned_title_ids.has(&"outlander_of_camelot")
	var saved_active := RunManager.run_active
	var gold0 := RunManager.gold
	RunManager.award_title(&"outlander_of_camelot")
	RunManager.equip_title(0, &"outlander_of_camelot")
	RunManager.equip_title(1, &"")
	RunManager.run_active = true
	RunManager._on_combat_won()
	_check("worn, Outlander pays 5 gold when a combat is won", RunManager.gold == gold0 + 5)
	RunManager.gold = gold0
	RunManager.run_active = saved_active
	RunManager.active_title_slots = saved_slots
	if not had_outlander:
		RunManager.earned_title_ids.erase(&"outlander_of_camelot")


## King of Camelot away from Camelot (title wave 2, sheet Q5): the degraded tier is A King
## Abroad, still a crown at a smaller discount, and pairs with the returning tier's Former King.
func _test_king_abroad() -> void:
	var king := TitlePool.get_title(&"king_of_camelot")
	_check("King of Camelot degrades to A King Abroad (-12%), returning as Former King (-20%)",
		king != null
		and king.get_name_for_tier(TitleData.Tier.DEGRADED) == "A King Abroad"
		and king.get_value_for_tier(TitleData.Tier.DEGRADED) == 12
		and king.get_name_for_tier(TitleData.Tier.RETURNING) == "Former King")


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
	var held_pc_before := RunManager.earned_title_ids.has(&"peoples_champion")
	RunManager.set_realm_standing(&"camelot", folk_init + 12)
	var champ_reached := RunManager.is_peoples_champion(&"camelot")
	RunManager.set_realm_standing(&"camelot", folk_init)
	var champ_not_from_pledge := not RunManager.is_peoples_champion(&"camelot")
	_check("pledge + one pro-folk act makes a people's champion; the pledge alone does not",
		champ_reached and champ_not_from_pledge)
	RunManager.realm_standing.clear()
	# Crossing the bar above now grants the title as a side effect; keep the fixture clean.
	if not held_pc_before:
		RunManager.earned_title_ids.erase(&"peoples_champion")

	# The People's Champion is a route title now (a rest grants both choices), not a third
	# post-combat heal, and it is handed over the moment standing crosses the bar rather than
	# after the boss -- in a one-act demo the post-boss award arrived with no nodes left.
	var pc := TitlePool.get_title(&"peoples_champion")
	_check("The People's Champion is a route title (a rest grants both choices)",
		pc != null and pc.category == TitleData.Category.PERSONALITY
		and pc.original_name == "The People's Champion"
		and pc.passive_effect == TitleData.EffectType.REST_TAKES_BOTH)
	var had_pc := RunManager.earned_title_ids.has(&"peoples_champion")
	RunManager.earned_title_ids.erase(&"peoples_champion")
	RunManager.realm_standing.clear()
	RunManager.change_realm_standing(&"camelot", RunManager.PEOPLES_CHAMPION_THRESHOLD - 1)
	var not_yet := not RunManager.earned_title_ids.has(&"peoples_champion")
	RunManager.change_realm_standing(&"camelot", 1)
	var awarded_on_cross := RunManager.earned_title_ids.has(&"peoples_champion")
	_check("The People's Champion is awarded on the standing crossing, not after the boss",
		not_yet and awarded_on_cross)
	RunManager.realm_standing.clear()
	if not had_pc:
		RunManager.earned_title_ids.erase(&"peoples_champion")

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
	# R2: the keeper's lines are labelled with their work-name, never "You".
	var speakers := {}
	var cairn := CharacterPool.build_emo_hybrid()
	for vn in [VNPool.build_sendoff(cairn), VNPool.build_sendoff_single(cairn, &"bram"),
			VNPool.build_sendoff_single(cairn, &"neve")]:
		for beat in vn.beats:
			speakers[beat.speaker] = true
	_check("the send-off labels the keeper's lines Cairn, and nothing says You",
		speakers.has("Cairn") and not speakers.has("You"))

	# Restore fresh defaults so running this suite doesn't consume the player's intro.
	ProfileManager.reset_seen_cutscenes()


## R1: a place-and-time line is a setting beat, set as the running head above the panel. It takes no
## click of its own and a later one replaces it; it carries no full stop, and the narration after it
## no longer repeats the place.
func _test_vn_setting_lines() -> void:
	var cairn := CharacterPool.build_emo_hybrid()
	var settings := []
	for vn in [VNPool.build_sendoff(cairn), VNPool.build_sendoff_single(cairn, &"bram"),
			VNPool.build_sendoff_single(cairn, &"neve")]:
		for beat in vn.beats:
			if beat.setting:
				settings.append(beat.text)
	_check("the send-offs name their places as setting beats",
		settings == ["The Fable office, before deployment", "Dispatch", "The Records desk", "Dispatch"])
	var stops := false
	for s in settings:
		stops = stops or s.ends_with(".")
	_check("a setting line carries no full stop", not stops)

	RunManager.pending_vn = VNPool.build_sendoff(cairn)
	var scene: Control = load("res://scenes/vn/vn_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	_check("the first setting is the head and costs no click",
		scene._head.visible and scene._head_label.text == "The Fable office, before deployment"
		and scene._beat_index == 1 and scene._text_label.text.begins_with("Two desks"))
	# Click through to Neve's part, stopping short of the last beat so nothing changes scene.
	while scene._head_label.text != "Dispatch" and scene._beat_index < scene._vn.beats.size() - 1:
		scene._advance()
	_check("a later setting replaces the head as the scene moves",
		scene._head_label.text == "Dispatch" and scene._text_label.text.begins_with("Neve holds the kit"))
	scene.queue_free()
	await get_tree().process_frame
	RunManager.pending_vn = null


## R4: each pledge says what it will change under its option, in the approved words, with
## the numbers read from its config: two more elites and 10% for the court; 8 Block, 5%, 20% and the
## tier it lands in for the common folk. The scene sets each trade under its option.
func _test_entry_trade() -> void:
	var saved := RunManager.passion.current_value
	RunManager.passion.current_value = 0
	var entry := VNPool.build_camelot_entry()
	var court: String = entry.choices[0].detail
	var folk: String = entry.choices[1].detail
	_check("the court's option says its trade",
		court == "A harder road that pays better. Two more elites wait on it, and every enemy gets 10% stronger. In return, the court is in your favor, and the cards and relics you find are more often rare.")
	_check("the common folk's option says its trade",
		folk == "A gentler road with a price. The people are in your favor, the road's elites are weakened, you start every fight with 8 Block, and every enemy gets 5% weaker. In return, the shops charge 20% more, and the cards and relics you find are more often common. Your Passion also falls to Wavering.")
	_check("the trades carry no em dash", not (court + folk).contains("—"))
	_check("the court's elite count is the map's own",
		MapGenerator.elites_added_for(entry.choices[0].config.elite_frequency_mult) == 2)
	RunManager.pending_vn = entry
	var scene: Control = load("res://scenes/vn/vn_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	scene._show_beat(scene._vn.beats.size() - 1)
	scene._show_choices()
	await get_tree().process_frame
	var shown := 0
	for btn in scene._choices_box.get_children():
		for label in btn.find_children("*", "Label", true, false):
			if label.text == court or label.text == folk:
				shown += 1
	_check("each option shows its trade under it", shown == 2)
	scene.queue_free()
	await get_tree().process_frame
	RunManager.pending_vn = null
	RunManager.passion.current_value = saved


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


## Chilled (Cairn's signature Water DoT): a freeze-gauge DoT that resolves at the afflicted's
## turn-END — flat chip + either a melt (below threshold) or a convert-to-Frozen (at threshold,
## spending all the chill). Enemy turns run with instant=true so the pacing timers are skipped.
func _test_chilled_freeze() -> void:
	_check("Chilled status is registered", StatusEffects.CHILLED != null)
	_check("Chilled and Poison are distinct effects (the two DoTs stay orthogonal)",
		StatusEffects.CHILLED != StatusEffects.POISON)

	# Creeping Tide is now the Chilled SEED (was Poison); Poisoned Fang stays the generic
	# Poison card so the two DoTs live on different cards.
	var prim := CardPool.build_emo_primary_pool()
	var creeping := _card_by_name(prim, "Creeping Tide")
	var creeping_chills := false
	if creeping:
		for e in creeping.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.CHILLED:
				creeping_chills = true
	_check("Creeping Tide seeds Chilled (no longer Poison)", creeping != null and creeping_chills)
	var gen := CardPool._build_generic_pool()
	var fang := _card_by_name(gen, "Poisoned Fang")
	var fang_poisons := false
	if fang:
		for e in fang.effects:
			if e is StatusApplyEffect and e.status_effect == StatusEffects.POISON:
				fang_poisons = true
	_check("Poisoned Fang still applies Poison (Chilled didn't swallow Poison)",
		fang != null and fang_poisons)

	# Below threshold: the chip lands flat and the gauge melts by 1.
	var meng := CombatEngine.new()
	add_child(meng)
	meng.instant = true
	meng.start_combat([], 50, 50, [_dummy_attacker()])
	var men := meng.enemies[0]
	meng.apply_status_effect(men.stats, StatusEffects.CHILLED, 5)
	var ehp := men.stats.current_hp
	await meng.start_enemy_turn()
	_check("below threshold: Chilled chips a flat %d and melts 1 (5 -> 4)" % CombatEngine.CHILL_CHIP,
		men.stats.current_hp == ehp - CombatEngine.CHILL_CHIP
		and men.stats.get_status_stacks(StatusEffects.CHILLED) == 4)
	meng.free()

	# At threshold: the chill converts to Frozen, clears to 0, and the enemy skips its NEXT turn.
	var feng := CombatEngine.new()
	add_child(feng)
	feng.instant = true
	feng.start_combat([], 50, 50, [_dummy_attacker()])
	var fen := feng.enemies[0]
	feng.apply_status_effect(fen.stats, StatusEffects.CHILLED, CombatEngine.CHILL_FREEZE_THRESHOLD)
	await feng.start_enemy_turn()  # enemy acts, then the chill converts at its turn-end
	_check("at threshold: Chilled converts to Frozen and clears the chill",
		fen.stats.has_status(StatusEffects.STUN)
		and not fen.stats.has_status(StatusEffects.CHILLED))
	var php := feng.player_stats.current_hp
	await feng.start_enemy_turn()  # now Frozen -> the enemy forfeits its action
	_check("the frozen-by-chill enemy skips its next turn (no player damage) then thaws",
		feng.player_stats.current_hp == php
		and not fen.stats.has_status(StatusEffects.STUN))
	feng.free()

	# Poison still ticks in its own lane (start-of-turn), independent of Chilled — a combatant
	# can carry both at once. (The HP-per-tick bleed itself is covered in _test_content_enemies.)
	var peng := CombatEngine.new()
	add_child(peng)
	peng.start_combat([], 50, 50, [_dummy_attacker()])
	peng.player_stats.apply_status(StatusEffects.POISON, 3)
	peng.player_stats.apply_status(StatusEffects.CHILLED, 2)
	peng.tick_start_of_turn(peng.player_stats)
	_check("Poison ticks at start-of-turn while Chilled (Poison 3 -> 2, Chilled untouched)",
		peng.player_stats.get_status_stacks(StatusEffects.POISON) == 2
		and peng.player_stats.get_status_stacks(StatusEffects.CHILLED) == 2)
	peng.free()


## A minimal enemy whose only move is a guaranteed 20-damage attack — so a skipped
## turn is unambiguous (any hit would show as lost player HP).
## The Beast at the Stone: two bars; the drill in phase 1; phase 2 converting down its own
## bar (the combo sheds a hit per band and is gone at the bottom); Breaking Blow costs him.
func _test_sword_guardian() -> void:
	var g := EnemyPool.sword_guardian()
	_check("the Beast at the Stone fights in two bars",
		g.is_multiphase() and g.phase_hps.size() == 2 and g.enemy_name == "The Beast at the Stone")
	var p1: Array = g.phase_movesets[0]
	var p2: Array = g.phase_movesets[1]
	var guard := false
	var combo := false
	for m in p1:
		if m.move_name == "Practiced Guard" and m.intent_type == EnemyMove.IntentType.DEFEND:
			guard = true
		if m.move_name == "Drilled Combo":
			combo = true
	_check("phase 1 keeps the drill (Practiced Guard + Drilled Combo)", guard and combo)
	# The combo loses its hits down the second bar: 3 above 66%, 2 in the middle, none under 33%.
	var combo_hits := {}
	for m in p2:
		for e in m.effects:
			if e is DamageEffect and e.hits > 1 and not e.apply_to_source:
				combo_hits[m.min_hp_percent] = e.hits
	_check("the combo sheds a hit per band (3 -> 2 -> gone)",
		combo_hits.get(0.66, 0) == 3 and combo_hits.get(0.33, 0) == 2 and not combo_hits.has(0.0))
	# Rolling at the bottom of the second bar never produces a combo, and does produce the blows.
	var seen := {}
	for i in 200:
		var st := EnemyCombatState.new(g)
		st.advance_phase()
		st.stats.current_hp = 10
		st.select_intent()
		seen[st.current_intent.move_name] = true
	_check("under a third of the second bar: Reckless Abandon and Breaking Blow, no combo",
		seen.has("Reckless Abandon") and seen.has("Breaking Blow")
		and not seen.has("Drilled Combo") and not seen.has("Unlearned Combo"))
	# Breaking Blow through the engine: 22 to the player, 8 off his own bar, flat.
	var blow: EnemyMove = null
	for m in p2:
		if m.move_name == "Breaking Blow":
			blow = m
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [EnemyPool.sword_guardian()])
	var gs: EnemyCombatState = eng.enemies[0]
	gs.advance_phase()
	var his_hp: int = gs.stats.current_hp
	var my_hp: int = eng.player_stats.current_hp
	for e in blow.effects:
		e.apply(gs.stats, eng.player_stats, eng)
	_check("Breaking Blow hits the player for 22 and costs him 8",
		eng.player_stats.current_hp == my_hp - 22 and gs.stats.current_hp == his_hp - 8)
	# The self-cost is flat: Vulnerable on him does not scale it, and his block does not soak it.
	eng.apply_status_effect(gs.stats, StatusEffects.VULNERABLE, 1)
	gs.stats.gain_block(20)
	his_hp = gs.stats.current_hp
	for e in blow.effects:
		if e is DamageEffect and e.apply_to_source:
			e.apply(gs.stats, eng.player_stats, eng)
	_check("the self-cost ignores his block and his Vulnerable (flat 8)",
		gs.stats.current_hp == his_hp - 8 and gs.stats.block == 20)
	# Emptying his last bar with his own blow kills him the normal way.
	gs.stats.current_hp = 5
	for e in blow.effects:
		if e is DamageEffect and e.apply_to_source:
			e.apply(gs.stats, eng.player_stats, eng)
	_check("a Breaking Blow that empties his last bar kills him", gs.stats.is_dead())
	eng.free()
	# The harness copy resolves the blow the way the engine does: 22 to me, 8 off him.
	var policy := HarnessCombat.new()
	var saved_relics := RunManager.relics.duplicate()
	var saved_titles := RunManager.active_title_slots.duplicate()
	RunManager.relics.clear()
	RunManager.active_title_slots.assign([&"", &""])
	var peng := _policy_fight([], 80, [EnemyPool.sword_guardian()])
	var pen: EnemyCombatState = peng.enemies[0]
	pen.advance_phase()
	pen.stats.current_hp = 12
	pen.current_intent = blow
	pen.next_intent = blow
	var pline := policy._line_copy(peng)
	policy._sim_enemy_turn(peng, policy._context(peng, false, 0), pline)
	peng.end_player_turn()
	var pf: Dictionary = pline["foes"][0]
	_check("copy vs engine: Breaking Blow (copy %d / his %d, engine %d / %d)" % [
			pline["php"], pf["hp"], peng.player_stats.current_hp, pen.stats.current_hp],
		pline["php"] == peng.player_stats.current_hp and pf["hp"] == pen.stats.current_hp)
	peng.free()
	RunManager.relics.assign(saved_relics)
	RunManager.active_title_slots.assign(saved_titles)


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


## First choice in an event whose text contains `needle` (a substring, so a full option
## sentence can be matched by its distinctive verb). Null if none / the event is missing.
func _choice_by_text(ev: EventData, needle: String) -> EventData.EventChoice:
	if ev == null:
		return null
	for ch in ev.choices:
		if ch.text.find(needle) != -1:
			return ch
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
	# load() alone is too lenient -- a cached GDScript resource still returns non-null even
	# when it has a parse error (this missed an event_scene.gd error once), so reload() the
	# script and require OK: that re-runs the compiler and reports parse failures as an Error.
	for path in ["res://scenes/combat/combat_scene.gd", "res://scenes/map/map_scene.gd",
			"res://scenes/reward/card_reward_scene.gd", "res://scenes/event/event_scene.gd",
			"res://scenes/character_select/character_select_scene.gd",
			"res://scenes/shop/shop_scene.gd",
			"res://scenes/act/act_transition_scene.gd",
			"res://scenes/settings/settings_scene.gd",
			"res://scenes/demo/demo_end_scene.gd",
			"res://scenes/vn/vn_scene.gd",
			"res://scenes/rest/rest_scene.gd",
			"res://scenes/camelot/crown_decision_scene.gd",
			"res://scenes/reward/relic_reward_scene.gd",
			"res://scenes/game_over/game_over_scene.gd",
			"res://scenes/title/title_screen.gd",
			"res://scenes/splash/splash_scene.gd",
			"res://scripts/ui/set_piece.gd", "res://scripts/ui/excalibur_piece.gd",
			"res://scripts/ui/altar_piece.gd"]:
		var scr = load(path)
		var compiled: bool = scr != null and scr is GDScript and scr.reload() == OK
		_check("compiles: %s" % path, compiled)



## The Sword's Bearer (Oct 2026): the flat +3 became a per-hit bonus that doubles on a doubling
## timer, capped at three doublings and reset per combat, so the title is weak in the first few
## turns where fights are decided and only reaches its ceiling in a long one. The escalation is
## Original tier only; a degraded sword keeps a flat bonus, since the one-integer tier schema
## can shrink a value but cannot reshape a curve.
func _test_swords_bearer_curve() -> void:
	var sb := TitlePool.get_title(&"swords_bearer")
	_check("The Sword's Bearer opens at +1 per hit (down from a flat +3)",
		sb != null and sb.original_value == 1
		and sb.passive_effect == TitleData.EffectType.DAMAGE_BONUS_FLAT)

	var had := RunManager.earned_title_ids.has(&"swords_bearer")
	RunManager.award_title(&"swords_bearer")
	RunManager.equip_title(0, &"swords_bearer")
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], 50, 50, [_dummy_attacker()])

	# turn -> expected bonus. The interval between steps doubles with the value, and the
	# fourth doubling never arrives: turn 16 pays the same +8 as turn 8.
	var schedule := {1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 7: 4, 8: 8, 12: 8, 16: 8, 40: 8}
	var curve_ok := true
	var reported := ""
	for t in schedule:
		eng.turn_number = t
		var got: int = eng.sword_bonus()
		if got != schedule[t]:
			curve_ok = false
			reported += " t%d=%d(want %d)" % [t, got, schedule[t]]
	_check("the sword doubles on turns 2, 4 and 8, then stops (+1/+2/+4/+8)%s" % reported,
		curve_ok)

	# Per HIT, not per card: the whole reason the curve opens at +1 instead of +3.
	eng.turn_number = 8
	var dummy := eng.enemies[0].stats
	var before := dummy.current_hp
	for _i in 4:
		eng.deal_damage(dummy, 3, eng.player_stats)
	_check("the bonus lands per hit (four hits of 3 at +8 take 44)",
		before - dummy.current_hp == 44)

	# A degraded sword (worn outside Camelot) keeps a flat bonus at its own tier value.
	var saved_realm := RunManager.current_realm_id
	RunManager.current_realm_id = &"yggdrasil"
	var flat_eng := CombatEngine.new()
	add_child(flat_eng)
	flat_eng.start_combat([], 50, 50, [_dummy_attacker()])
	flat_eng.turn_number = 8
	var degraded_bonus: int = flat_eng.sword_bonus()
	flat_eng.turn_number = 1
	var degraded_opening: int = flat_eng.sword_bonus()
	_check("a degraded sword stays flat (no doubling outside its realm)",
		degraded_bonus == sb.degraded_value and degraded_opening == sb.degraded_value)
	flat_eng.free()
	RunManager.current_realm_id = saved_realm

	eng.free()
	RunManager.equip_title(0, &"")
	if not had:
		RunManager.earned_title_ids.erase(&"swords_bearer")

func _test_cooldown() -> void:
	# Hollow Blow has cooldown 2: it must not fire on consecutive enemy turns.
	var golem := EnemyPool.siege_golem()
	var st := EnemyCombatState.new(golem)
	var last_was_slam := false
	var double_slam := false
	for i in 40:
		st.select_intent()
		var is_slam := st.current_intent.move_name == "Hollow Blow"
		if is_slam and last_was_slam:
			double_slam = true
		last_was_slam = is_slam
	_check("Hollow Blow (cd 2) never fires back-to-back", not double_slam)


## Inner Fire adds copies of itself. Its AddCardEffect used to point at the card carrying it,
## a card -> effect -> card cycle that refcounting never frees, so every build of the generic
## pool (each card reward, the boss reward, the shop) leaked one Inner Fire for the life of the
## process. The copy is built by id now. Checks that the copy is exactly what it was before (the
## base card, even off an upgraded one, and able to copy itself in turn) and that building the
## pool leaves nothing behind.
func _test_inner_fire_copies_itself() -> void:
	var fire := _card_by_name(CardPool._build_generic_pool(), "Inner Fire")
	var points_at_itself := false
	var add: AddCardEffect = null
	if fire:
		for e in fire.effects:
			if e is AddCardEffect:
				add = e
				points_at_itself = e.card_to_add == fire
	_check("Inner Fire carries a copy effect that does not point at the card itself",
		add != null and not points_at_itself)
	if add == null:
		return
	_check("Inner Fire's copy text is unchanged",
		add.get_description() == "Add a copy of Inner Fire to your discard pile.")

	var eng := CombatEngine.new()
	eng.piles = PileManager.new()
	eng.piles.setup([])
	add.apply(null, null, eng)
	var up := fire.duplicate_card()
	up.upgrade_card()
	for e in up.get_active_effects():
		if e is AddCardEffect:
			e.apply(null, null, eng)
	var copies := eng.piles.discard_pile
	var copies_copy := false
	if copies.size() == 2:
		for e in copies[0].effects:
			copies_copy = copies_copy or (e is AddCardEffect and e.card_id == &"inner_fire")
	_check("playing Inner Fire, or Inner Fire+, drops a base Inner Fire into discard",
		copies.size() == 2 and copies.all(func(c): return c.card_name == "Inner Fire" \
			and not c.upgraded and c.school == fire.school))
	_check("the copy can copy itself in turn", copies_copy)
	eng.free()

	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 5:
		CardPool._build_generic_pool()
	var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check("building the generic pool 5 times leaves no objects behind (%d -> %d)" % [
		before, after], after == before)


## The batch harnesses run every trial inside one synchronous _ready, so whatever a finished
## combat leaves behind piles up over thousands of them; sound did, and took combat_harness to
## 6.9 GB. Fights a few real instant combats the way the harness does and checks the object
## count comes back to where it started. The first fight is a warm-up, since a first combat can
## build things once (caches, registries) that are meant to stay.
## The page shows only baked sheets, so a sheet added without its bake fails here and not on the frame.
func _test_every_sheet_is_baked() -> void:
	var scene_script: GDScript = load("res://scenes/combat/combat_scene.gd")
	var missing: Array[String] = []
	for key in scene_script.SPRITE_SETS:
		var sset: Dictionary = scene_script.SPRITE_SETS[key]
		if not sset.has("baked"):
			missing.append(key)
			continue
		for state in sset["anims"]:
			if not ResourceLoader.exists(sset["baked"] + sset["anims"][state][0]):
				missing.append("%s/%s" % [key, state])
	_check("every sprite set has its bake for the page %s" % str(missing), missing.is_empty())


## The side-by-side fight is one man twice: same numbers, same sheet, only the colour differs.
func _test_whole_and_hollow() -> void:
	var pair := EnemyPool.whole_and_hollow()
	var plain := EnemyPool.man_at_arms()
	var whole := pair[0]
	var hollow := pair[1]
	_check("whole and hollow are the shipped Man-at-Arms", whole.enemy_name == plain.enemy_name
		and hollow.enemy_name == plain.enemy_name and whole.max_health == plain.max_health
		and hollow.max_health == plain.max_health and hollow.moves.size() == plain.moves.size())
	_check("whole and hollow stand on the same sheet, and only one is drained",
		whole.sprite_set == hollow.sprite_set and whole.drained == 0.0 and hollow.drained == 1.0)
	var scene_script: GDScript = load("res://scenes/combat/combat_scene.gd")
	_check("their sheet is in the sprite sets", scene_script.SPRITE_SETS.has(whole.sprite_set))
	_check("a plain Man-at-Arms keeps the shipped look", plain.sprite_set == "" and plain.drained == 0.0)


func _test_combat_retains_nothing() -> void:
	var policy := HarnessCombat.new()
	_fight_instant_combat(policy)
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in 5:
		_fight_instant_combat(policy)
	var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check("five finished instant combats leave no objects behind (%d -> %d)" % [before, after],
		after == before)


## One instant combat driven by the harness policy, in its own function so every local it
## made is gone when it returns and the caller's object count sees only what was kept.
func _fight_instant_combat(policy: HarnessCombat) -> void:
	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)
	var deck: Array[CardData] = []
	for c in CharacterPool.emo_starting_deck():
		deck.append(c.duplicate_card())
	eng.start_combat(deck, 80, 80, [EnemyPool.corrupted_knight(), EnemyPool.realm_shade()])
	var turns := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and turns < 60:
		turns += 1
		policy.play_turn(eng, false, 50)
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		eng.end_player_turn()
	eng.free()


## Rewards are a function of the run seed. Card and relic rewards used to shuffle their pool
## with Array.shuffle(), which draws from Godot's global RNG, seeded fresh in every process, so
## the same run seed offered different rewards in every session and run_harness gave different
## numbers on every run of the same code. Rolls every reward table twice off the same run seed
## with the global RNG set to two different states, and requires the same offer both times.
func _test_rewards_follow_the_run_seed() -> void:
	var owned := RunManager.get_owned_relic_names()
	var offers: Array[String] = []
	for global_seed in [1, 987654321]:
		seed(global_seed)
		RngManager.setup_run(42)
		var names: PackedStringArray = []
		for c in CardPool.get_reward_choices(RngManager.loot_rng, 3):
			names.append(c.card_name)
		for c in CardPool.get_boss_reward_choices(RngManager.loot_rng):
			names.append(c.card_name)
		for r in RelicPool.get_reward_choices(RngManager.loot_rng, 3, owned):
			names.append(r.relic_name)
		for r in RelicPool.get_boss_reward_choices(RngManager.loot_rng, owned):
			names.append(r.relic_name)
		offers.append(", ".join(names))
	randomize()
	_check("the same run seed offers the same card + relic rewards whatever the global RNG holds",
		offers[0] == offers[1] and offers[0] != "")


## The harness player's copy of the fight against the engine itself. Each case sets up a real
## combat, predicts the enemy turn on the policy's copy, lets the engine run it, and compares
## the player's HP and the enemy's HP, Frozen and fall. (The per-card copy is also checked
## against the engine on every attack of whole harness runs.)
func _test_harness_copy_matches_engine() -> void:
	var policy := HarnessCombat.new()
	var saved_relics := RunManager.relics.duplicate()
	var saved_titles := RunManager.active_title_slots.duplicate()
	RunManager.relics.clear()
	RunManager.active_title_slots.assign([&"", &""])
	for case in [
		# label, player status, stacks, player block, pierce, enemy status, stacks, enemy HP
		["player Vulnerable 1 has worn off before the hit", StatusEffects.VULNERABLE, 1, 0, 0, null, 0, 100],
		["player Vulnerable 2 still amplifies it", StatusEffects.VULNERABLE, 2, 0, 0, null, 0, 100],
		["player Intangible 1 has worn off before the hit", StatusEffects.INTANGIBLE, 1, 0, 0, null, 0, 100],
		["player Intangible 2 holds each hit to 1", StatusEffects.INTANGIBLE, 2, 0, 0, null, 0, 100],
		["a pierce goes through block", null, 0, 30, 5, null, 0, 100],
		["a Frozen enemy forfeits its action", null, 0, 0, 0, StatusEffects.STUN, 1, 100],
		["Poison fells an enemy before it can act", null, 0, 0, 0, StatusEffects.POISON, 25, 20],
		["Chilled at 10 bites after the action and freezes", null, 0, 0, 0, StatusEffects.CHILLED, 10, 100],
	]:
		var foe := _one_move_enemy("Striker", 100, 11, 2, case[4])
		var eng := _policy_fight([], 80, [foe])
		var en: EnemyCombatState = eng.enemies[0]
		en.stats.current_hp = case[7]
		if case[1] != null:
			eng.player_stats.apply_status(case[1], case[2])
		eng.player_stats.block = case[3]
		if case[5] != null:
			en.stats.apply_status(case[5], case[6])
		var line := policy._line_copy(eng)
		policy._sim_enemy_turn(eng, policy._context(eng, false, 0), line)
		eng.end_player_turn()
		var f: Dictionary = line["foes"][0]
		var ok: bool = line["php"] == eng.player_stats.current_hp \
			and f["hp"] == en.stats.current_hp and f["dead"] == en.stats.is_dead() \
			and f["stun"] == en.stats.get_status_stacks(StatusEffects.STUN)
		_check("copy vs engine: %s (copy HP %d, engine %d)" % [case[0], line["php"],
			eng.player_stats.current_hp], ok)
		eng.free()
	RunManager.relics.assign(saved_relics)
	RunManager.active_title_slots.assign(saved_titles)


## The per-card copy on hands with known numbers: the title bonus once per hit, the lean zone,
## the Passion-distance rider, Vulnerable and Intangible targets, area attacks, Enraged lash only
## through block, Momentum's climb, Blooded Edge once, and a boss's lifebar breaking mid-card.
func _test_harness_copy_card_rules() -> void:
	var policy := HarnessCombat.new()
	var saved_relics := RunManager.relics.duplicate()
	var saved_titles := RunManager.active_title_slots.duplicate()
	var saved_passion: int = RunManager.passion.current_value
	RunManager.relics.clear()
	RunManager.active_title_slots.assign([&"", &""])
	RunManager.passion.current_value = 0
	var eng := _policy_fight([], 80, [_one_move_enemy("Target", 100, 0)])
	var target: EnemyCombatState = eng.enemies[0]
	var triple := _neutral_attack("Triple", 1, 4)
	triple.effects[0].hits = 3
	var big := _neutral_attack("Big", 2, 14)
	eng._sword_base = 2
	_check("the title bonus lands once per hit: 3 x (4+2) = 18, 1 x (14+2) = 16",
		_copy_strike(policy, eng, triple)[0] == 18 and _copy_strike(policy, eng, big)[0] == 16)
	eng._sword_base = 0
	RunManager.passion.current_value = 30  # Inspired for the test character
	var water := _neutral_attack("Water Ten", 1, 10)
	water.personality = CardData.PersonalityType.PRIMARY
	_check("an on-type card at Inspired gets x1.12: 10 -> 11", _copy_strike(policy, eng, water)[0] == 11)
	var carried := _neutral_attack("Carried", 1, 4)
	carried.effects[0].passion_bonus_divisor = 10
	_check("the Passion-distance rider adds 30 / 10 = 3: 4 -> 7", _copy_strike(policy, eng, carried)[0] == 7)
	RunManager.passion.current_value = 0
	target.stats.apply_status(StatusEffects.INTANGIBLE, 1)
	_check("an Intangible target takes 1 per hit: Triple deals 3", _copy_strike(policy, eng, triple)[0] == 3)
	target.stats.remove_status(StatusEffects.INTANGIBLE)
	target.stats.apply_status(StatusEffects.ENRAGED, 3)
	target.stats.block = 5
	_check("Enraged 3 behind block 5: the first hit is absorbed, two lash for 6 HP",
		_copy_strike(policy, eng, triple)[1] == 6)
	target.stats.remove_status(StatusEffects.ENRAGED)
	target.stats.block = 0
	eng._momentum_per_hit = 1
	var line := policy._line_copy(eng)
	var ctx := policy._context(eng, false, 0)
	policy._sim_card(eng, ctx, triple, line)
	policy._sim_card(eng, ctx, big, line)
	_check("Momentum climbs every hit: 4+5+6 then 14+3 = 32", 100 - line["foes"][0]["hp"] == 32)
	eng._momentum_per_hit = 0
	eng._blooded_edge_pending = 6
	line = policy._line_copy(eng)
	policy._sim_card(eng, policy._context(eng, false, 0), triple, line)
	_check("Blooded Edge lands once, on the first hit: 4+6 then 4, 4 = 18", 100 - line["foes"][0]["hp"] == 18)
	eng.free()

	var pair := _policy_fight([], 80, [_one_move_enemy("Low", 40, 0), _one_move_enemy("High", 40, 0)])
	pair.enemies[0].stats.apply_status(StatusEffects.VULNERABLE, 1)
	var sweep := _neutral_attack("Sweep", 1, 5)
	sweep.target_type = CardData.TargetType.ALL_ENEMIES
	_check("an area attack lands on every enemy: 7 (Vulnerable) + 5 = 12", _copy_strike(policy, pair, sweep)[0] == 12)
	pair.free()

	var boss_data := _one_move_enemy("Bars", 10, 0)
	boss_data.phase_hps.assign([10, 50])
	boss_data.phase_enter_enraged.assign([0, 1])
	boss_data.phase_enter_damage.assign([0, 18])
	var beng := _policy_fight([], 80, [boss_data])
	var quad := _neutral_attack("Quad", 1, 4)
	quad.effects[0].hits = 4
	line = policy._line_copy(beng)
	policy._sim_card(beng, policy._context(beng, false, 0), quad, line)
	_check("a bar breaking mid-card: the third 4 breaks the 10-HP bar (2 past it lost), the fourth lands on the fresh 50; entry lash 18, and the breaking hit and the fourth each lash 1",
		line["foes"][0]["phase"] == 1 and line["foes"][0]["hp"] == 46 and line["php"] == 80 - 18 - 1 - 1)
	beng.free()
	RunManager.passion.current_value = saved_passion
	RunManager.relics.assign(saved_relics)
	RunManager.active_title_slots.assign(saved_titles)


## Part 4: what the engine gained since the planner was written, each locked to the engine. The
## companion's Stoop (ignores Block, a flag bonus spent once), Bind (strips Block), Wait On (raises
## the flag), the oil, the ward, the girdle, the clutch mend, the scabbard, the Merciful's mend and
## the Unfading's echo. Enemy-turn rules are compared against a real end_player_turn.
func _test_harness_copy_new_rules() -> void:
	var policy := HarnessCombat.new()
	var saved_relics := RunManager.relics.duplicate()
	var saved_titles := RunManager.active_title_slots.duplicate()
	var saved_passion: int = RunManager.passion.current_value
	RunManager.relics.clear()
	RunManager.active_title_slots.assign([&"", &""])
	RunManager.passion.current_value = 0
	var hawk := PetPool.build_cards(&"hawk")
	var stoop := _card_by_name(hawk, "Stoop")
	var bind := _card_by_name(hawk, "Bind")
	var wait_on := _card_by_name(hawk, "Wait On")

	var eng := _policy_fight([], 80, [_one_move_enemy("Target", 100, 0)])
	eng.enemies[0].stats.block = 10
	_check("Stoop ignores Block: 8 lands whole on a target holding 10 Block",
		_copy_strike(policy, eng, stoop)[0] == 8)
	var line := policy._line_copy(eng)
	var ctx := policy._context(eng, false, 0)
	policy._sim_card(eng, ctx, wait_on, line)
	_check("Wait On raises the flag on the copy and not on the engine",
		line["flags"].get(&"waiting_on", false) == true and eng.combat_flags.is_empty())
	var flag: StringName = line["flags"].keys()[0] if line["flags"].size() > 0 else &""
	policy._sim_card(eng, ctx, stoop, line)
	_check("with the flag up Stoop deals 16 and spends it (copy: %d lost, flag %s)" % [
			100 - line["foes"][0]["hp"], str(line["flags"].has(flag))],
		100 - line["foes"][0]["hp"] == 16 and not line["flags"].has(flag))
	line = policy._line_copy(eng)
	policy._sim_card(eng, ctx, bind, line)
	_check("Bind strips the 10 Block and deals 4: the copy's block is 0, HP 96",
		line["foes"][0]["block"] == 0 and line["foes"][0]["hp"] == 96)
	eng.enemies[0].stats.block = 0
	eng._blade_oil_pending = 8
	var triple := _neutral_attack("Triple", 1, 4)
	triple.effects[0].hits = 3
	_check("Blade Oil lands once, on the first hit: 4+8 then 4, 4 = 20", _copy_strike(policy, eng, triple)[0] == 20)
	eng._blade_oil_pending = 0
	var echo_line := policy._line_copy(eng)
	eng._unfading_pending = true
	echo_line = policy._line_copy(eng)
	var first_back := policy._sim_card(eng, ctx, triple, echo_line)
	var second_back := policy._sim_card(eng, ctx, triple, echo_line)
	_check("the Unfading's echo: the first card goes back, the second does not", first_back and not second_back)
	var exhausts := _neutral_attack("Burn", 1, 4)
	exhausts.exhaust = true
	echo_line = policy._line_copy(eng)
	echo_line["echo"] = true
	_check("an exhausting card is spent and does not come back", not policy._sim_card(eng, ctx, exhausts, echo_line))
	eng._unfading_pending = false
	eng.free()

	# Enemy-turn rules against the real engine: a 3 x 11 mover into a player on 40 HP.
	for case in [
		["the Scabbard takes 1 off every blow", "scabbard", 1],
		["a Favour turns the first blow", "ward", 1],
		["the Girdle leaves a felled player on 1 HP", "girdle", 6],
		["the Compassionate mends the first drop below half", "clutch", 8],
	]:
		var foe := _one_move_enemy("Striker", 100, 11, 1 if case[1] == "girdle" else 3)
		var fe := _policy_fight([], 40, [foe])
		match case[1]:
			"scabbard": fe._scabbard_guard = case[2]
			"ward": fe._favour_ward = true
			"girdle":
				fe.player_stats.current_hp = 9
				fe._girdle_hp = 1
				fe._girdle_ward = true
			"clutch":
				fe._clutch_heal = case[2]
				fe._clutch_used = false
		var l := policy._line_copy(fe)
		policy._sim_enemy_turn(fe, policy._context(fe, false, 0), l)
		fe.end_player_turn()
		_check("copy vs engine: %s (copy HP %d, engine %d)" % [case[0], l["php"],
			fe.player_stats.current_hp], l["php"] == fe.player_stats.current_hp)
		fe.free()

	# The Merciful: a kill mends, in the copy as in the engine.
	var mend_eng := _policy_fight([], 60, [_one_move_enemy("Frail", 3, 0)])
	mend_eng.player_stats.current_hp = 50
	mend_eng._mercy_heal = 5
	var ml := policy._line_copy(mend_eng)
	policy._sim_card(mend_eng, policy._context(mend_eng, false, 0), _neutral_attack("Jab", 1, 9), ml)
	_check("a kill mends 5 on the copy: 50 -> 55", ml["php"] == 55)
	mend_eng.free()
	RunManager.passion.current_value = saved_passion
	RunManager.relics.assign(saved_relics)
	RunManager.active_title_slots.assign(saved_titles)


## The harness player's choices on hands with a known best play under the one currency (HP
## lost over the fight): energy spent on the most damage, block against a light hitter and
## attack against a heavy one, the enemy whose death saves most hit first, a kill credited with
## the blow it prevents, lash weighed at the fight's own rate, Strength bought for a long fight
## and not for a short one, no plan that dies when one survives, the Passion pole, overkill,
## and Sight using the move it shows.
func _test_harness_policy_decides() -> void:
	var policy := HarnessCombat.new()
	var saved_relics := RunManager.relics.duplicate()
	var saved_titles := RunManager.active_title_slots.duplicate()
	var saved_passion: int = RunManager.passion.current_value
	RunManager.relics.clear()
	RunManager.active_title_slots.assign([&"", &""])
	RunManager.passion.current_value = 0

	var big := _neutral_attack("Big", 2, 14)
	var nines: Array = [_neutral_attack("Nine A", 1, 9), _neutral_attack("Nine B", 1, 9),
		_neutral_attack("Nine C", 1, 9)]
	var eng := _policy_fight([big] + nines, 80, [_one_move_enemy("Dummy", 100, 5)])
	var plan: Array = policy._plan_turn(eng, policy._context(eng, false, 0), eng.piles.hand.duplicate())
	_check("3 energy buys three 1-cost 9s (27), not the 2-cost 14 and a 9 (23)",
		plan.size() == 3 and not plan.has(big))
	eng.free()

	for case in [["a heavy hitter (20 a turn): the 6 shortens the fight by more than 8 block saves", 20, "Strike"],
			["a light hitter (5 a turn): 8 block saves more than the 6 shortens the fight", 5, "Guard"]]:
		var duel := _policy_fight([_block_card("Guard", 1, 8), _neutral_attack("Strike", 1, 6)], 80,
			[_one_move_enemy("Hitter", 100, case[1])])
		duel.energy = 1
		var pick := policy.choose_card(duel, false, 0)
		_check("against %s" % case[0], pick != null and pick.card_name == case[2])
		duel.free()

	var two := _policy_fight([_neutral_attack("Strike", 1, 6)], 80,
		[_one_move_enemy("Pest", 10, 4), _one_move_enemy("Brute", 30, 20)])
	_check("the Brute (20 a turn, 30 HP) is hit before the Pest (4 a turn, 10 HP): most damage per HP first",
		policy._focus_index(policy._line_copy(two)) == 1)
	two.free()

	var finish := _policy_fight([_block_card("Guard", 1, 8), _neutral_attack("Strike", 1, 6)], 80,
		[_one_move_enemy("Wounded", 6, 15)])
	finish.energy = 1
	var kill := policy.choose_card(finish, false, 0)
	_check("finishing a 6-HP enemy about to hit 15 beats blocking 8 of it", kill != null and kill.card_name == "Strike")
	finish.free()

	for case in [["a target hitting 2 a turn: 12 damage saves under 1 HP, the lash costs 9", 2, false],
			["a target hitting 40 a turn: 12 damage saves about 13 HP, more than the 9 lash", 40, true]]:
		var triple := _neutral_attack("Triple", 1, 4)
		triple.effects[0].hits = 3
		var raged := _policy_fight([triple], 80, [_one_move_enemy("Enraged", 100, case[1])])
		raged.enemies[0].stats.apply_status(StatusEffects.ENRAGED, 3)
		raged.energy = 1
		var p := policy.choose_card(raged, false, 0)
		_check("Enraged 3, %s" % case[0], (p != null) == case[2])
		raged.free()

	for case in [["a long fight (200 HP)", 200, "Whet"], ["a 6-HP enemy", 6, "Strike"]]:
		var deck: Array = [_self_buff("Whet", StatusEffects.STRENGTH, 2)]
		for i in 4:
			deck.append(_neutral_attack("Strike", 1, 6))
		var invest := _policy_fight(deck, 80, [_one_move_enemy("Wall", case[1], 10)])
		invest.energy = 1
		var p := policy.choose_card(invest, false, 0)
		_check("+2 Strength or a 6 against %s: %s" % [case[0], case[2]], p != null and p.card_name == case[2])
		invest.free()

	var brink := _policy_fight([_block_card("Guard", 1, 8), _neutral_attack("Strike", 1, 6)], 25,
		[_one_move_enemy("Killer", 100, 30)])
	brink.energy = 1
	var save := policy.choose_card(brink, false, 0)
	_check("at 25 HP facing 30, the block that survives is played over the attack that dies",
		save != null and save.card_name == "Guard")
	brink.free()

	var tide := _neutral_attack("Tide", 1, 6)
	var push := PassionEffect.new()
	push.value = 4
	tide.effects.append(push)
	var pole := _policy_fight([_neutral_attack("Strike", 1, 7), tide], 80, [_one_move_enemy("Dummy", 100, 5)])
	pole.energy = 1
	var free_pick := policy.choose_card(pole, false, 0)
	var committed := policy.choose_card(pole, true, 50)
	_check("uncommitted plays the bigger Strike; committed to +50 plays the Passion card",
		free_pick != null and free_pick.card_name == "Strike" and committed != null and committed.card_name == "Tide")
	pole.free()

	var small := _neutral_attack("Small", 1, 6)
	var over := _policy_fight([big, small], 80, [_one_move_enemy("Weak", 5, 10), _one_move_enemy("Tough", 30, 10)])
	plan = policy._plan_turn(over, policy._context(over, false, 0), over.piles.hand.duplicate())
	_check("the 6 finishes the 5-HP enemy and the 14 goes to the next, not 14 into 5 HP",
		plan == [small, big])
	over.free()

	var seer := _one_move_enemy("Seer", 100, 20)
	var rest := EnemyMove.new()
	rest.move_name = "Rest"
	seer.moves.append(rest)
	var sight := _policy_fight([_neutral_attack("Strike", 1, 6)], 80, [seer])
	sight.enemies[0].next_intent = rest
	var line := policy._line_copy(sight)
	var ctx := policy._context(sight, false, 0)
	var blind := policy._future_loss(sight, ctx, line)
	ctx["sight"] = true
	_check("Sight shows the next move is a rest, so the next turn costs less than the average says",
		policy._future_loss(sight, ctx, line) < blind)
	sight.free()

	RunManager.passion.current_value = saved_passion
	RunManager.relics.assign(saved_relics)
	RunManager.active_title_slots.assign(saved_titles)


## A real combat for the policy checks: the given cards as the whole deck (five or fewer are all
## in hand), each enemy telegraphing its first move and no next move rolled.
func _policy_fight(cards: Array, hp: int, foes: Array) -> CombatEngine:
	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)
	var deck: Array[CardData] = []
	for c in cards:
		deck.append(c)
	var datas: Array[EnemyData] = []
	for f in foes:
		datas.append(f)
	eng.start_combat(deck, hp, 80, datas)
	for i in eng.enemies.size():
		eng.enemies[i].current_intent = datas[i].moves[0]
		eng.enemies[i].next_intent = null
	return eng


## [damage landed, HP the player lost] for one card played on the policy's copy.
func _copy_strike(policy: HarnessCombat, eng: CombatEngine, card: CardData) -> Array:
	var line := policy._line_copy(eng)
	var before := policy._pool_total(line)
	policy._sim_card(eng, policy._context(eng, false, 0), card, line)
	return [int(before - policy._pool_total(line)), eng.player_stats.current_hp - line["php"]]


## An enemy with a single move: an attack of `dmg` x `hits` (with `pierce`), or a do-nothing
## move when dmg is 0.
func _one_move_enemy(enemy_name: String, hp: int, dmg: int, hits: int = 1, pierce: int = 0) -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = enemy_name
	e.max_health = hp
	var m := EnemyMove.new()
	m.move_name = "Hit"
	m.intent_type = EnemyMove.IntentType.ATTACK
	if dmg > 0:
		var d := DamageEffect.new()
		d.value = dmg
		d.hits = hits
		d.pierce = pierce
		m.effects.append(d)
	e.moves.append(m)
	return e


func _block_card(card_name: String, cost: int, block: int) -> CardData:
	var c := CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = CardData.CardType.SKILL
	c.target_type = CardData.TargetType.SELF
	var e := BlockEffect.new()
	e.value = block
	c.effects.append(e)
	return c


func _self_buff(card_name: String, status: StatusEffectData, stacks: int) -> CardData:
	var c := CardData.new()
	c.card_name = card_name
	c.energy_cost = 1
	c.card_type = CardData.CardType.SKILL
	c.target_type = CardData.TargetType.SELF
	var e := StatusApplyEffect.new()
	e.status_effect = status
	e.value = stacks
	e.apply_to_source = true
	c.effects.append(e)
	return c


func _neutral_attack(card_name: String, cost: int, dmg: int) -> CardData:
	var c := CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = CardData.CardType.ATTACK
	c.target_type = CardData.TargetType.SINGLE_ENEMY
	var e := DamageEffect.new()
	e.value = dmg
	c.effects.append(e)
	return c


# ============================================================
# CONSUMABLES AND PETS (part 3 of the demo road)
# ============================================================

## Clears the pack and the standing/passion state the consumable tests touch, so each block
## starts from the same place and leaves nothing behind for the next one.
func _reset_consumable_state() -> void:
	RunManager.consumables.clear()
	RunManager.pet_id = &""
	RunManager.realm_standing.clear()
	RunManager.active_quests = {}
	RunManager.current_map = null
	RunManager.current_realm_id = &"camelot"
	RunManager.max_hp = 80
	RunManager.current_hp = 80
	_setup_run_state()


## A fresh engine over the test dummy (a 20-damage attacker with 100 HP), the player at `hp`/50.
func _consumable_engine(hp: int = 50) -> CombatEngine:
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat([], hp, 50, [_dummy_attacker()])
	return eng


func _seeded(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _test_consumables() -> void:
	_reset_consumable_state()

	# --- The pool: every id builds, shops stock priced items only (quest and event-only items
	# carry no price), and a realm's shop sells that realm's own items beside the generics.
	var all_built := true
	for id in ConsumablePool.all_ids():
		var c := ConsumablePool.get_consumable(id)
		if c == null or c.id != id or c.display_name == "" or c.description == "":
			all_built = false
	_check("every consumable id builds a named, described item", all_built)
	_check("an unknown consumable id builds nothing", ConsumablePool.get_consumable(&"nope") == null)
	_check("two fresh calls give two separate instances",
		ConsumablePool.get_consumable(&"traveller_salve") != ConsumablePool.get_consumable(&"traveller_salve"))
	var camelot_stock := ConsumablePool.shop_candidates(&"camelot")
	var other_stock := ConsumablePool.shop_candidates(&"yggdrasil")
	_check("a Camelot shop may sell Camelot's own items; another realm's shop may not",
		&"relic_water" in camelot_stock and &"indulgence" in camelot_stock
		and &"relic_water" not in other_stock and &"indulgence" not in other_stock)
	_check("shops never sell the quest item or the event-only courage",
		&"poisoned_chalice" not in camelot_stock and &"unspent_courage" not in camelot_stock)
	_check("gifts are never wares: no shop sells the favour, the writ or the loaf",
		&"champions_favour" not in camelot_stock and &"writ" not in camelot_stock
		and &"loaf" not in camelot_stock)
	var stock_a := ConsumablePool.get_shop_stock(_seeded(77), &"camelot", 2)
	var stock_b := ConsumablePool.get_shop_stock(_seeded(77), &"camelot", 2)
	_check("shop stock is two distinct items and follows the seed",
		stock_a.size() == 2 and stock_a[0].id != stock_a[1].id
		and stock_a[0].id == stock_b[0].id and stock_a[1].id == stock_b[1].id)
	var excluded := ConsumablePool.get_shop_stock(_seeded(77), &"camelot", 2, [stock_a[0].id])
	_check("a shop does not re-offer what the player already holds",
		excluded.size() == 2 and excluded[0].id != stock_a[0].id and excluded[1].id != stock_a[0].id)

	# --- The cap: two slots, no more, and a discard frees one.
	var first := ConsumablePool.get_consumable(&"traveller_salve")
	var second := ConsumablePool.get_consumable(&"cold_supper")
	var third := ConsumablePool.get_consumable(&"blade_oil")
	_check("the pack takes two consumables",
		RunManager.add_consumable(first) and RunManager.add_consumable(second))
	_check("a third is refused and the pack is unchanged",
		not RunManager.has_consumable_room() and not RunManager.add_consumable(third)
		and RunManager.consumables.size() == 2)
	_check("discarding frees the slot",
		RunManager.discard_consumable(first) and RunManager.has_consumable_room()
		and RunManager.add_consumable(third) and RunManager.consumables.size() == 2)
	_check("discarding something not held does nothing", not RunManager.discard_consumable(first))
	_check("a held item is found by id", RunManager.has_consumable(&"blade_oil")
		and not RunManager.has_consumable(&"traveller_salve"))
	RunManager.consumables.clear()

	# --- Map use: heals, the supper's map-only rule, standing swings, and the stray-click guard.
	var salve := ConsumablePool.get_consumable(&"traveller_salve")
	RunManager.add_consumable(salve)
	RunManager.current_hp = 80
	_check("a heal at full health is refused and the item is kept",
		not RunManager.use_consumable_on_map(salve) and RunManager.consumables.has(salve))
	RunManager.current_hp = 60
	_check("the salve heals 12 on the map and is spent",
		RunManager.use_consumable_on_map(salve) and RunManager.current_hp == 72
		and RunManager.consumables.is_empty())
	var supper := ConsumablePool.get_consumable(&"cold_supper")
	RunManager.add_consumable(supper)
	RunManager.current_hp = 50
	_check("the cold supper is map-only and heals 20",
		not supper.usable_in_combat and supper.usable_on_map
		and RunManager.use_consumable_on_map(supper) and RunManager.current_hp == 70)
	var oil := ConsumablePool.get_consumable(&"blade_oil")
	RunManager.add_consumable(oil)
	_check("a combat-only item cannot be used from the map",
		not RunManager.use_consumable_on_map(oil) and RunManager.consumables.has(oil))
	RunManager.consumables.clear()
	var water := ConsumablePool.get_consumable(&"relic_water")
	RunManager.add_consumable(water)
	RunManager.current_hp = 40
	RunManager.passion.current_value = 0
	RunManager.use_consumable_on_map(water)
	_check("relic-water heals 16 and drifts Passion 8 toward Hollow",
		RunManager.current_hp == 56 and RunManager.passion.current_value == -8)

	var writ := ConsumablePool.get_consumable(&"writ")
	var loaf := ConsumablePool.get_consumable(&"loaf")
	var pardon := ConsumablePool.get_consumable(&"indulgence")
	RunManager.consumables.clear()
	RunManager.add_consumable(writ)
	RunManager.add_consumable(loaf)
	RunManager.use_consumable_on_map(writ)
	_check("a writ swings standing 8 toward the court",
		RunManager.get_realm_standing(&"camelot") == -8)
	RunManager.use_consumable_on_map(loaf)
	_check("a loaf swings standing 8 toward the folk (back to even)",
		RunManager.get_realm_standing(&"camelot") == 0)
	RunManager.add_consumable(pardon)
	RunManager.use_consumable_on_map(pardon)
	_check("an indulgence swings standing 15 toward the court",
		RunManager.get_realm_standing(&"camelot") == -15 and RunManager.consumables.is_empty())
	_check("standing items are map-only",
		not writ.usable_in_combat and not loaf.usable_in_combat and not pardon.usable_in_combat)

	# --- Realm border: realm items leave the pack, generics stay.
	RunManager.consumables.clear()
	RunManager.add_consumable(ConsumablePool.get_consumable(&"relic_water"))
	RunManager.add_consumable(ConsumablePool.get_consumable(&"traveller_salve"))
	RunManager.set_current_realm(&"yggdrasil")
	_check("crossing a border expires Camelot's relic-water and keeps the generic salve",
		RunManager.consumables.size() == 1 and RunManager.consumables[0].id == &"traveller_salve")
	RunManager.set_current_realm(&"camelot")
	_check("re-entering the origin realm does not bring the expired item back",
		RunManager.consumables.size() == 1)
	RunManager.add_consumable(ConsumablePool.get_consumable(&"champions_favour"))
	RunManager.set_current_realm(&"camelot")
	_check("staying in the realm expires nothing", RunManager.consumables.size() == 2)

	# --- Combat use ---
	_reset_consumable_state()
	var eng := _consumable_engine(30)
	var csalve := ConsumablePool.get_consumable(&"traveller_salve")
	RunManager.add_consumable(csalve)
	_check("the salve heals 12 in combat, live, and is spent",
		eng.use_consumable(csalve) and eng.player_stats.current_hp == 42
		and RunManager.consumables.is_empty())
	var healthy := ConsumablePool.get_consumable(&"traveller_salve")
	RunManager.add_consumable(healthy)
	eng.player_stats.current_hp = 50
	_check("a combat heal at full health is refused",
		not eng.can_use_consumable(healthy) and not eng.use_consumable(healthy)
		and RunManager.consumables.has(healthy))
	RunManager.consumables.clear()
	var csupper := ConsumablePool.get_consumable(&"cold_supper")
	RunManager.add_consumable(csupper)
	eng.player_stats.current_hp = 10
	_check("a map-only item cannot be used in combat", not eng.use_consumable(csupper))
	RunManager.consumables.clear()

	# Blade Oil: the first hit of the next attack card deals +8, once.
	var coil := ConsumablePool.get_consumable(&"blade_oil")
	RunManager.add_consumable(coil)
	var strike := _neutral_attack("Test Strike", 1, 6)
	var strike2 := _neutral_attack("Test Strike B", 1, 6)
	eng.piles.hand.append(strike)
	eng.piles.hand.append(strike2)
	var dummy := eng.enemies[0].stats
	var hp0 := dummy.current_hp
	_check("blade oil is poured and spent",
		eng.use_consumable(coil) and RunManager.consumables.is_empty())
	eng.play_card(strike, dummy)
	var first_hit := hp0 - dummy.current_hp
	eng.play_card(strike2, dummy)
	var second_hit := (hp0 - first_hit) - dummy.current_hp
	_check("the next attack deals 6 + 8 = 14, then attacks return to 6 (one-shot)",
		first_hit == 14 and second_hit == 6)
	var oil2 := ConsumablePool.get_consumable(&"blade_oil")
	var oil3 := ConsumablePool.get_consumable(&"blade_oil")
	RunManager.add_consumable(oil2)
	RunManager.add_consumable(oil3)
	eng.use_consumable(oil2)
	_check("a second oil is refused while one is already waiting (no wasted click)",
		not eng.can_use_consumable(oil3))
	RunManager.consumables.clear()

	# Unspent Courage: the same fight-long Strength the Shade's queued boon gave, but held until
	# the player spends it. A fight with the item merely held starts at 0 Strength.
	_reset_consumable_state()
	var ceng := _consumable_engine()
	var courage := ConsumablePool.get_consumable(&"unspent_courage")
	RunManager.add_consumable(courage)
	_check("unspent courage gives +2 Strength for the fight when the player spends it",
		ceng.use_consumable(courage)
		and ceng.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 2)
	_check("it is not auto-applied: a fight with the item merely held starts at 0 Strength",
		_held_courage_fight_starts_flat())

	# A Bottled Blessing pushes toward the pole the player already leans to.
	_reset_consumable_state()
	var beng := _consumable_engine()
	var blessing := ConsumablePool.get_consumable(&"bottled_blessing")
	RunManager.add_consumable(blessing)
	RunManager.passion.current_value = 10
	beng.use_consumable(blessing)
	_check("a blessing at +10 pushes toward Blazing (+12 to 22)",
		RunManager.passion.current_value == 22)
	var blessing2 := ConsumablePool.get_consumable(&"bottled_blessing")
	RunManager.add_consumable(blessing2)
	RunManager.passion.current_value = -10
	beng.use_consumable(blessing2)
	_check("a blessing at -10 pushes toward Hollow (-12 to -22)",
		RunManager.passion.current_value == -22)
	var blessing3 := ConsumablePool.get_consumable(&"bottled_blessing")
	RunManager.add_consumable(blessing3)
	RunManager.passion.current_value = 0
	beng.use_consumable(blessing3)
	_check("dead center leans Blazing", RunManager.passion.current_value == 12)
	RunManager.passion.current_value = 0

	# Relic-water in combat heals and drifts Passion; the favour turns the next blow only.
	var weng := _consumable_engine(30)
	var cwater := ConsumablePool.get_consumable(&"relic_water")
	RunManager.add_consumable(cwater)
	weng.use_consumable(cwater)
	_check("relic-water in combat heals 16 and drifts Passion 8 toward Hollow",
		weng.player_stats.current_hp == 46 and RunManager.passion.current_value == -8)
	RunManager.passion.current_value = 0
	var feng := _consumable_engine()
	var favour := ConsumablePool.get_consumable(&"champions_favour")
	RunManager.add_consumable(favour)
	_check("the favour is armed and spent",
		feng.use_consumable(favour) and RunManager.consumables.is_empty())
	feng.execute_enemy_turn(feng.enemies[0])
	_check("the next blow against the player does not land", feng.player_stats.current_hp == 50)
	feng.execute_enemy_turn(feng.enemies[0])
	_check("the blow after it does (the favour is spent by the one it turned)",
		feng.player_stats.current_hp == 30)
	# Used after a blow has already landed, it still turns the next one: it is the next blow,
	# not the fight's first, which is what the item's text says.
	var feng_late := _consumable_engine()
	feng_late.execute_enemy_turn(feng_late.enemies[0])
	var favour_late := ConsumablePool.get_consumable(&"champions_favour")
	RunManager.add_consumable(favour_late)
	feng_late.use_consumable(favour_late)
	feng_late.execute_enemy_turn(feng_late.enemies[0])
	_check("a favour used mid-fight turns the next blow, not only the first",
		feng_late.player_stats.current_hp == 30)
	var feng2 := _consumable_engine()
	var favour2 := ConsumablePool.get_consumable(&"champions_favour")
	RunManager.add_consumable(favour2)
	feng2.use_consumable(favour2)
	feng2.self_damage(feng2.player_stats, 5)
	_check("the player's own HP costs do not spend the favour",
		feng2.player_stats.current_hp == 45)
	feng2.execute_enemy_turn(feng2.enemies[0])
	_check("...and the favour still turns the next enemy blow", feng2.player_stats.current_hp == 45)

	# Nothing armed carries into the next fight, and combat items wait for the player's turn.
	var feng3 := _consumable_engine()
	feng3.execute_enemy_turn(feng3.enemies[0])
	_check("a new fight starts with no favour armed", feng3.player_stats.current_hp == 30)
	feng3.phase = CombatEngine.Phase.ENEMY_TURN
	var late_salve := ConsumablePool.get_consumable(&"traveller_salve")
	RunManager.add_consumable(late_salve)
	_check("combat consumables cannot be used off the player's turn",
		not feng3.can_use_consumable(late_salve))
	RunManager.consumables.clear()
	for e in [eng, ceng, beng, weng, feng, feng2, feng3]:
		e.free()

	# --- The chalice: a quest item with a slot cost, spent at its payoff, dead once it is passed.
	_reset_consumable_state()
	var chalice := ConsumablePool.get_consumable(&"poisoned_chalice")
	_check("the chalice is a quest item with no use button",
		chalice.is_quest_item() and not chalice.usable_in_combat and not chalice.usable_on_map
		and chalice.quest_id == &"raiders")
	_check("an unarmed chalice is already spent", RunManager.is_consumable_spent(chalice))
	var qmap: MapData = null
	var payoff_id := -1
	for seed_value in range(200, 260):
		var qrng := RandomNumberGenerator.new()
		qrng.seed = seed_value
		qmap = MapGenerator.generate(qrng, &"camelot", 1, 1.0, false)
		for id in qmap.nodes:
			if qmap.nodes[id].quest_payoff_id == &"raiders":
				payoff_id = id
		if payoff_id != -1:
			break
	_check("a seeded Camelot map places the raider payoff the chalice rides", payoff_id != -1)
	RunManager.current_map = qmap
	RunManager.arm_quest(&"raiders")
	_check("an armed chalice with the lair still ahead is live",
		not RunManager.is_consumable_spent(chalice))
	var boss_id := -1
	for id in qmap.nodes:
		if qmap.nodes[id].node_type == MapNode.NodeType.BOSS:
			boss_id = id
	var saved_pos := qmap.current_node_id
	qmap.current_node_id = boss_id
	_check("once the player has walked past the lair, the chalice is spent",
		RunManager.is_consumable_spent(chalice))
	qmap.current_node_id = saved_pos
	qmap.nodes[payoff_id].visited = true
	_check("a visited lair leaves the chalice spent", RunManager.is_consumable_spent(chalice))
	qmap.nodes[payoff_id].visited = false
	RunManager.complete_quest(&"raiders")
	_check("a completed questline leaves the chalice spent", RunManager.is_consumable_spent(chalice))
	_check("a spent quest item can still be dropped to free the slot",
		RunManager.add_consumable(chalice) and RunManager.discard_consumable(chalice)
		and RunManager.consumables.is_empty())

	# Delivered at the lair: every raider opens the fight with the chalice's Poison.
	var band := EnemyPool.get_raider_band_poisoned(chalice.value)
	var normal_band := EnemyPool.get_raider_band()
	var all_dosed := band.size() == 3
	for member in band:
		var dosed := false
		for pair in member.starting_statuses:
			if pair[0] == StatusEffects.POISON and pair[1] == chalice.value:
				dosed = true
		if not dosed:
			all_dosed = false
	_check("the poisoned band is the same three fighters, each carrying the chalice's Poison",
		all_dosed and band.size() == normal_band.size())
	var peng := CombatEngine.new()
	add_child(peng)
	peng.start_combat([], 50, 50, band)
	var started_poisoned := true
	for member in peng.enemies:
		if member.stats.get_status_stacks(StatusEffects.POISON) != chalice.value:
			started_poisoned = false
	_check("they open the fight Poisoned", started_poisoned)
	peng.free()
	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var lair: EventData = es._build_raider_ambush_event()
	var plea: EventData = es._build_raider_plea_event()
	var cup: EventData.EventChoice = null
	for ch in lair.choices:
		if ch.requires_consumable == &"poisoned_chalice":
			cup = ch
	_check("the lair offers a chalice-gated option that spends it and launches the poisoned fight",
		cup != null and cup.spends_consumable == &"poisoned_chalice"
		and cup.starts_combat == &"raider_band_poisoned")
	_check("the plea hands over the chalice when the hunt is accepted",
		plea.choices[0].grants_consumable == &"poisoned_chalice"
		and plea.choices[0].arms_quest == &"raiders")

	# --- Every consumable has a grant site: an event choice, or the shop.
	var granted: Array[StringName] = []
	var events: Array[EventData] = EventPool._build_pool()
	events.append(es._build_reliquary_struck_event())
	events.append(plea)
	events.append(lair)
	for ev in events:
		for ch in ev.choices:
			if ch.grants_consumable != &"":
				granted.append(ch.grants_consumable)
	var orphans := PackedStringArray()
	for id in ConsumablePool.all_ids():
		var sold := id in camelot_stock
		if id not in granted and not sold:
			orphans.append(String(id))
	_check("every consumable is granted by an event or sold in a shop (orphans: %s)" % ", ".join(orphans),
		orphans.is_empty())
	var unknown_grant := false
	for id in granted:
		if ConsumablePool.get_consumable(id) == null:
			unknown_grant = true
	_check("no event grants a consumable id the pool does not know", not unknown_grant)
	es.free()

	# --- The shop's provisions follow the same rules.
	var shop: Control = load("res://scenes/shop/shop_scene.gd").new()
	shop._generate_shop()
	var priced: bool = shop.shop_consumables.size() == 2
	for item in shop.shop_consumables:
		priced = priced and shop.consumable_prices.get(item, 0) > 0
	_check("a shop rolls two priced provisions", priced)
	shop.free()

	_reset_consumable_state()


## Builds a fight with Unspent Courage merely HELD (not used) and reports whether the player starts
## at 0 Strength: the migration's point is that the held item never spends itself.
func _held_courage_fight_starts_flat() -> bool:
	RunManager.consumables.clear()
	RunManager.add_consumable(ConsumablePool.get_consumable(&"unspent_courage"))
	var held_eng := _consumable_engine()
	var flat: bool = held_eng.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 0 \
		and RunManager.consumables.size() == 1
	held_eng.free()
	RunManager.consumables.clear()
	return flat


## R6: one panel for what a thing is. Hover shows it, a click on a chip pins it until a click
## elsewhere, a click on a button never pins, and the engine tooltip is gone from marked controls.
func _test_hover_note() -> void:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var note := HoverNote.new()
	host.add_child(note)
	var chip := PanelContainer.new()
	chip.tooltip_text = "the old tooltip"
	chip.position = Vector2(100, 100)
	chip.size = Vector2(80, 30)
	host.add_child(chip)
	HoverNote.mark(chip, "Weak 2", "Deal 25% less attack damage.", "debuff", "Loses 1 each turn", true)
	var button := Button.new()
	button.position = Vector2(400, 100)
	button.size = Vector2(80, 30)
	host.add_child(button)
	HoverNote.mark(button, "Traveller's Salve", "Heal 12 HP.")
	_check("a marked control has no engine tooltip, so only one panel can show", chip.tooltip_text == "")
	_check("the panel finds what is under the mouse", note._source_at(Vector2(120, 110)) == chip)
	_check("and nothing where nothing is marked", note._source_at(Vector2(300, 300)) == null)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(120, 110)
	note._input(click)
	_check("a click on a chip pins its panel", note.is_pinned() and note.shown_title() == "Weak 2")
	chip.free()
	_check("a pinned panel stays when its chip is rebuilt away", note.shown_title() == "Weak 2")
	click.position = Vector2(300, 300)
	note._input(click)
	_check("a click elsewhere takes the pin down", not note.is_pinned() and note.shown_title() == "")
	click.position = Vector2(420, 110)
	note._input(click)
	_check("a click on a button does not pin, so the button still gets it", not note.is_pinned())
	host.free()


## R8 and R12: the reward screen, the shop and the deck draw CardFace with CardSigil's coin, the
## shop's actions sit outside its scroll, and the detail view carries the inspect notes.
func _test_one_card_look() -> void:
	var probe := _neutral_attack("Probe", 1, 6)
	_check("a card with no school has no coin", CardSigil.build(probe) == null)
	probe.school = CardData.PersonalityType.PRIMARY
	var coin := CardSigil.build(probe)
	_check("a card with a school wears a coin", coin != null)
	if coin:
		coin.free()
	var sigil_label := CardSigil.label(CardData.PersonalityType.NEGATIVE)
	_check("the coin names a curse's pole", sigil_label == "Curse")

	var reward: Control = load("res://scenes/reward/card_reward_scene.gd").new()
	var reward_card: Control = reward._create_card_panel(probe)
	_check("a reward card is CardFace's", reward_card.find_child("CardDesc", true, false) != null)
	_check("and CardFace's size", reward_card.custom_minimum_size == CardFace.SIZE)
	reward_card.free()
	reward.free()

	RunManager.gold = 500
	var shop: Control = load("res://scenes/shop/shop_scene.gd").new()
	var held: Control = shop._create_shop_card(probe, 40)
	_check("a shop card is CardFace's with its price above",
		held.find_child("CardDesc", true, false) != null
		and held.get_child(0) is Label and held.get_child(0).text == "40 gold")
	var affordable_dim: Color = held.get_child(1).modulate
	held.free()
	var poor: Control = shop._create_shop_card(probe, 900)
	_check("a card too dear dims its face, not the price",
		poor.get_child(1).modulate != affordable_dim and poor.get_child(0).modulate == Color.WHITE)
	poor.free()
	shop.free()

	# The footer: the four actions are not inside any scroll.
	var live: Control = load("res://scenes/shop/shop_scene.gd").new()
	add_child(live)
	await get_tree().process_frame
	var leave: Button = null
	var all: Array = live.find_children("*", "Button", true, false)
	for b in all:
		if b.text == "Leave Shop":
			leave = b
	var in_scroll := false
	var up: Node = leave
	while up and up != live:
		if up is ScrollContainer:
			in_scroll = true
		up = up.get_parent()
	_check("the shop's Leave button is found", leave != null)
	_check("and sits in a footer outside the scroll", leave != null and not in_scroll)
	live.queue_free()

	var map: Control = load("res://scenes/map/map_scene.gd").new()
	var detail: Control = map._render_full_card(probe)
	_check("the deck's detail view is the face with the inspect notes beside it",
		detail.find_child("CardDesc", true, false) != null and detail.get_child_count() == 2)
	detail.free()
	map.free()
	RunManager.gold = 0


## The pack's UI logic without rendering: the bar's reasons and uses, and the full-pack prompt.
func _test_consumable_ui() -> void:
	_reset_consumable_state()
	var bar := ConsumableBar.new()
	add_child(bar)
	bar.setup(ConsumableBar.Mode.MAP)
	var salve := ConsumablePool.get_consumable(&"traveller_salve")
	var oil := ConsumablePool.get_consumable(&"blade_oil")
	var supper := ConsumablePool.get_consumable(&"cold_supper")
	var chalice := ConsumablePool.get_consumable(&"poisoned_chalice")
	RunManager.current_hp = 80
	_check("on the map, a salve at full health says why it waits",
		bar._why_unusable(salve, false) == "Already at full health.")
	RunManager.current_hp = 60
	RunManager.add_consumable(salve)
	_check("on the map, a salve at 60/80 is usable", bar._why_unusable(salve, false) == "")
	RunManager.discard_consumable(salve)
	_check("on the map, an oil says it is combat only",
		bar._why_unusable(oil, false) == "Combat only.")
	_check("a quest item says it is carried to its payoff",
		bar._why_unusable(chalice, false).begins_with("Carried"))
	_check("a spent quest item says to drop it",
		bar._why_unusable(chalice, true).find("Drop it") != -1)
	var cbar := ConsumableBar.new()
	add_child(cbar)
	var eng := _consumable_engine(30)
	cbar.setup(ConsumableBar.Mode.COMBAT, eng)
	_check("in combat, a supper says it is map only", cbar._why_unusable(supper, false) == "Map only.")
	RunManager.add_consumable(salve)
	_check("in combat, a wounded player can use a salve", cbar._why_unusable(salve, false) == "")
	var used: Array = []
	cbar.item_used.connect(func(item): used.append(item))
	cbar._on_use_pressed(salve)
	_check("pressing a usable item in combat uses it, spends it and tells the host",
		used.size() == 1 and eng.player_stats.current_hp == 42 and RunManager.consumables.is_empty())
	RunManager.add_consumable(supper)
	var map_used: Array = []
	bar.item_used.connect(func(item): map_used.append(item))
	RunManager.current_hp = 40
	bar._on_use_pressed(supper)
	_check("pressing a usable item on the map uses it",
		map_used.size() == 1 and RunManager.current_hp == 60)
	# R15/R23: a host refreshes the pack many times a frame (a boss's hit, a phase change). The
	# slots are rebuilt only when what they show changes, and old ones never linger in the row.
	RunManager.add_consumable(salve)
	bar.refresh()
	var shown := bar.get_child_count()
	var first_slot := bar.get_child(bar.get_child_count() - 1)
	for i in 7:
		bar.refresh()
	_check("refreshing an unchanged pack seven times in a frame rebuilds nothing",
		bar.get_child_count() == shown and bar.get_child(bar.get_child_count() - 1) == first_slot)
	RunManager.current_hp = 80
	bar.refresh()
	_check("a change in what is usable rebuilds the pack, with no old slot left in the row",
		bar.get_child_count() == shown and bar.get_child(bar.get_child_count() - 1) != first_slot)
	RunManager.discard_consumable(salve)
	# R13: a click on an item opens its menu; Use waits with the reason, Drop empties the slot.
	RunManager.add_consumable(salve)
	var salve_btn: Button = null
	for child in bar.get_children():
		if child is Button and child.text.begins_with(salve.display_name):
			salve_btn = child
	_check("a waiting item is still a live button, so it can be dropped",
		salve_btn != null and not salve_btn.disabled)
	salve_btn.pressed.emit()
	_check("a click on an item opens its menu", bar.is_menu_open() and bar.menu_item() == salve)
	var menu_use: Button = bar._menu.get_child(0).get_child(0)
	_check("at full health the menu's Use waits", menu_use.disabled)
	salve_btn.pressed.emit()
	_check("a second click on the item closes its menu", not bar.is_menu_open())
	salve_btn.pressed.emit()
	bar._on_menu_drop()
	_check("Drop empties the slot and closes the menu",
		not RunManager.consumables.has(salve) and not bar.is_menu_open())
	eng.free()
	bar.free()
	cbar.free()

	# The full-pack prompt: drop a held one to take the new one, or leave the new one.
	_reset_consumable_state()
	var held_a := ConsumablePool.get_consumable(&"traveller_salve")
	var held_b := ConsumablePool.get_consumable(&"cold_supper")
	RunManager.add_consumable(held_a)
	RunManager.add_consumable(held_b)
	var newcomer := ConsumablePool.get_consumable(&"blade_oil")
	var swap := ConsumableSwap.open(self, newcomer)
	var results: Array = []
	swap.resolved.connect(func(taken): results.append(taken))
	swap._on_drop_held(held_a)
	_check("dropping a held item takes the new one: the pack is the supper and the oil",
		results == [true] and RunManager.consumables.size() == 2
		and RunManager.consumables.has(held_b) and RunManager.consumables.has(newcomer)
		and not RunManager.consumables.has(held_a))
	var newcomer2 := ConsumablePool.get_consumable(&"bottled_blessing")
	var swap2 := ConsumableSwap.open(self, newcomer2)
	var results2: Array = []
	swap2.resolved.connect(func(taken): results2.append(taken))
	swap2._on_leave_new()
	_check("leaving the new item behind changes nothing in the pack",
		results2 == [false] and RunManager.consumables.size() == 2
		and not RunManager.consumables.has(newcomer2))
	_reset_consumable_state()


func _test_pets() -> void:
	_reset_consumable_state()
	# --- The three companions, each a deck of four Tricks with exactly one bankable card.
	var all_trick := true
	var all_four := true
	for id in PetPool.all_ids():
		var pet := PetPool.get_pet(id)
		_check("%s is a Camelot companion with a description" % id,
			pet != null and pet.realm_id == &"camelot" and pet.description != "")
		var deck := PetPool.build_cards(id)
		if deck.size() != 4:
			all_four = false
		var banked := 0
		for c in deck:
			if not c.trick:
				all_trick = false
			if c.retain:
				banked += 1
		_check("%s banks exactly one of its four cards" % id, banked == 1)
	_check("every companion deck is four Trick cards", all_trick and all_four)
	_check("an unknown pet, and no pet, are null",
		PetPool.get_pet(&"nope") == null and PetPool.get_pet(&"") == null)
	var hound := PetPool.build_cards(&"hound")
	var hawk := PetPool.build_cards(&"hawk")
	var ferret := PetPool.build_cards(&"ferret")
	_check("the hound's deck is Harry, Bay, Worry and Relay, and Bay is the one it banks",
		_deck_names(hound) == PackedStringArray(["Harry", "Bay", "Worry", "Relay"])
		and _card_by_name(hound, "Bay").retain)
	_check("the hawk's deck is Wait On, Stoop, Bind and Throw Up, and Wait On is the one it banks",
		_deck_names(hawk) == PackedStringArray(["Wait On", "Stoop", "Bind", "Throw Up"])
		and _card_by_name(hawk, "Wait On").retain)
	_check("the ferret's deck is Scurry, Filch, Bolt and Dig, and Dig is the one it banks",
		_deck_names(ferret) == PackedStringArray(["Scurry", "Filch", "Bolt", "Dig"])
		and _card_by_name(ferret, "Dig").retain)
	_check("each pet card is priced on its own: the free ones are Harry, Wait On, Scurry and Filch",
		_card_by_name(hound, "Harry").energy_cost == 0 and _card_by_name(hound, "Bay").energy_cost == 1
		and _card_by_name(hound, "Worry").energy_cost == 1 and _card_by_name(hound, "Relay").energy_cost == 1
		and _card_by_name(hawk, "Wait On").energy_cost == 0 and _card_by_name(hawk, "Stoop").energy_cost == 1
		and _card_by_name(hawk, "Bind").energy_cost == 1 and _card_by_name(hawk, "Throw Up").energy_cost == 1
		and _card_by_name(ferret, "Scurry").energy_cost == 0 and _card_by_name(ferret, "Filch").energy_cost == 0
		and _card_by_name(ferret, "Bolt").energy_cost == 1 and _card_by_name(ferret, "Dig").energy_cost == 1)
	var harry: CardData = _card_by_name(hound, "Harry")
	var bay: CardData = _card_by_name(hound, "Bay")
	_check("the Trick keyword carries reminder text on the card, and the bankable one says it stays",
		harry.get_generated_description().find("Trick.") != -1
		and harry.trick_reminder().find("leaves at end of turn") != -1
		and bay.trick_reminder().find("Stays in hand") != -1)
	_check("an ordinary card carries no Trick reminder",
		_neutral_attack("Plain", 1, 6).trick_reminder() == "")
	_check("a pet card copies its Trick flag when duplicated", harry.duplicate_card().trick)
	_check("different calls give separate card instances", PetPool.build_cards(&"hound")[0] != hound[0])
	_check("the Tiltyard's warm option grants the hound", _tiltyard_grants_hound())
	_check("the hawk's Stoop says it ignores Block and lands 16 while the hawk is waiting on",
		_card_by_name(hawk, "Stoop").get_generated_description().find("Ignores Block.") != -1
		and _card_by_name(hawk, "Stoop").get_generated_description().find(
			"16 instead while the hawk is waiting on") != -1)
	_check("Bind says it strips the guard before the hit, and Wait On says what the hawk does",
		_card_by_name(hawk, "Bind").get_generated_description().begins_with("Remove all of its Block. Deal 4")
		and _card_by_name(hawk, "Wait On").get_generated_description().begins_with("The hawk is waiting on."))

	# --- Arrival: a card every turn, the deck drawn without replacement, on the deck rng; no pet,
	# no draw and no rng.
	var eng := _consumable_engine()
	eng.piles.hand.clear()
	var rng_before: int = RngManager.deck_rng.state
	eng._pet_arrival()
	_check("with no companion nothing arrives and the deck rng is untouched",
		eng.piles.hand.is_empty() and RngManager.deck_rng.state == rng_before)
	RunManager.set_pet(&"hound")
	RngManager.setup_run(9001)
	var seen := PackedStringArray()
	var from_deck := true
	for _i in 40:
		eng.piles.hand.clear()
		eng._pet_arrival()
		for c in eng.piles.hand:
			seen.append(c.card_name)
			if not c.trick or c.card_name not in _deck_names(hound):
				from_deck = false
	_check("the hound brings a card on every one of 40 turns (got %d)" % seen.size(), seen.size() == 40)
	_check("every arrival is a Trick card from the hound's own deck", from_deck)
	var cycles_whole := true
	var orders := {}
	for i in range(0, 40, 4):
		var cycle := seen.slice(i, i + 4)
		var sorted := Array(cycle)
		sorted.sort()
		if sorted != ["Bay", "Harry", "Relay", "Worry"]:
			cycles_whole = false
		orders[",".join(cycle)] = true
	_check("each cycle of four turns is the whole deck once: drawn without replacement", cycles_whole)
	_check("the deck is reshuffled between cycles (%d orders over 10 cycles)" % orders.size(),
		orders.size() > 1)
	RunManager.set_pet(&"nope")
	_check("an unknown pet id is refused and the hound stays", RunManager.pet_id == &"hound")
	eng.free()

	# --- Arrival is seeded: two runs of the same seed see the same cards, for every pet.
	var replays := true
	for id in PetPool.all_ids():
		RngManager.setup_run(4242)
		var run_a := _pet_arrivals(id, 12)
		RngManager.setup_run(4242)
		var run_b := _pet_arrivals(id, 12)
		if run_a != run_b or run_a == "":
			replays = false
	_check("every pet's arrivals replay identically from the same run seed", replays)

	# --- The hound: the grind. Two free bites, Poison, a fresh hand, and a banked Bay.
	var peng := _consumable_engine()
	var h := PetPool.build_cards(&"hound")
	var p_harry: CardData = _card_by_name(h, "Harry")
	var p_bay: CardData = _card_by_name(h, "Bay")
	var p_worry: CardData = _card_by_name(h, "Worry")
	var p_relay: CardData = _card_by_name(h, "Relay")
	peng.piles.hand.clear()
	for c in h:
		peng.piles.hand.append(c)
	peng.piles.draw_pile.append(_neutral_attack("Deep A", 1, 6))
	peng.piles.draw_pile.append(_neutral_attack("Deep B", 1, 6))
	var enemy_stats := peng.enemies[0].stats
	var e_hp := enemy_stats.current_hp
	_check("a pet card obeys energy: Harry is free", peng.can_play_card(p_harry) and peng.energy == 3)
	peng.play_card(p_harry, enemy_stats)
	_check("Harry bites twice for 2 and leaves play (no pile, not exhausted, not discarded)",
		e_hp - enemy_stats.current_hp == 4 and peng.energy == 3 and p_harry not in peng.piles.hand
		and p_harry not in peng.piles.discard_pile and p_harry not in peng.piles.exhaust_pile)
	peng.play_card(p_worry, enemy_stats)
	_check("Worry lays 4 Poison for an energy",
		peng.energy == 2 and enemy_stats.get_status_stacks(StatusEffects.POISON) == 4)
	var hand_before := peng.piles.hand.size()
	peng.play_card(p_relay, peng.player_stats)
	_check("Relay draws two for an energy and leaves play",
		peng.energy == 1 and peng.piles.hand.size() == hand_before + 1
		and p_relay not in peng.piles.discard_pile)
	# Bay is bankable: it survives the end of the turn; an unplayed Harry would not.
	var spare_harry: CardData = _card_by_name(PetPool.build_cards(&"hound"), "Harry")
	peng.piles.hand.append(spare_harry)
	var plain := _neutral_attack("Plain Strike", 1, 6)
	peng.piles.hand.append(plain)
	peng.instant = true
	peng.end_player_turn()
	_check("at end of turn an unplayed Trick vanishes (not into the discard pile)",
		spare_harry not in peng.piles.hand and spare_harry not in peng.piles.discard_pile
		and spare_harry not in peng.piles.exhaust_pile)
	_check("a bankable Trick stays in hand across the turn", p_bay in peng.piles.hand)
	# (The next turn's draw may already have reshuffled it into the draw pile or the hand; what
	# matters is that an ordinary card is never lost the way a Trick is.)
	_check("an ordinary unplayed card is not lost the way a Trick is",
		plain in peng.piles.discard_pile or plain in peng.piles.hand or plain in peng.piles.draw_pile)
	peng.play_card(p_bay, enemy_stats)
	_check("Bay puts 2 Weak on its target and leaves play",
		enemy_stats.get_status_stacks(StatusEffects.WEAK) == 2 and p_bay not in peng.piles.hand
		and p_bay not in peng.piles.discard_pile)
	peng.free()

	# --- The hawk: the strike. The stoop goes through a guard, double while the hawk waits on.
	var heng := _consumable_engine()
	heng.change_energy(3)
	var hk := PetPool.build_cards(&"hawk")
	var k_wait: CardData = _card_by_name(hk, "Wait On")
	var k_stoop: CardData = _card_by_name(hk, "Stoop")
	var k_bind: CardData = _card_by_name(hk, "Bind")
	var k_throw: CardData = _card_by_name(hk, "Throw Up")
	heng.piles.hand.clear()
	for c in hk:
		heng.piles.hand.append(c)
	var guard := heng.enemies[0].stats
	guard.gain_block(10)
	var g_hp := guard.current_hp
	heng.play_card(k_stoop, guard)
	_check("Stoop ignores Block: 8 lands on HP through a guard of 10, which stays",
		g_hp - guard.current_hp == 8 and guard.block == 10 and heng.energy == 5)
	heng.play_card(k_wait, heng.player_stats)
	_check("Wait On is free and the hawk is waiting on",
		heng.energy == 5 and heng.has_flag(CardPool.HAWK_WAITING_ON))
	var spare_wait: CardData = _card_by_name(PetPool.build_cards(&"hawk"), "Wait On")
	heng.piles.hand.append(spare_wait)
	heng.play_card(spare_wait, heng.player_stats)
	_check("a second Wait On while one is up changes nothing",
		heng.has_flag(CardPool.HAWK_WAITING_ON) and heng.energy == 5)
	var spare_stoop: CardData = _card_by_name(PetPool.build_cards(&"hawk"), "Stoop")
	heng.piles.hand.append(spare_stoop)
	g_hp = guard.current_hp
	heng.play_card(spare_stoop, guard)
	_check("a Stoop while the hawk is waiting on lands 16 through the guard and spends the wait",
		g_hp - guard.current_hp == 16 and guard.block == 10
		and not heng.has_flag(CardPool.HAWK_WAITING_ON) and heng.energy == 4)
	g_hp = guard.current_hp
	heng.play_card(k_bind, guard)
	_check("Bind strips the guard and its 4 lands on HP",
		guard.block == 0 and g_hp - guard.current_hp == 4 and heng.energy == 3)
	g_hp = guard.current_hp
	heng.play_card(k_throw, guard)
	_check("Throw Up lands 5 and the hawk is waiting on again",
		g_hp - guard.current_hp == 5 and heng.has_flag(CardPool.HAWK_WAITING_ON) and heng.energy == 2)
	var fresh := _consumable_engine()
	_check("the wait does not carry between fights", not fresh.has_flag(CardPool.HAWK_WAITING_ON))
	fresh.free()
	heng.free()

	# --- The ferret: speed. It hurts nothing; the hand moves.
	var feng := _consumable_engine()
	var fr := PetPool.build_cards(&"ferret")
	var f_scurry: CardData = _card_by_name(fr, "Scurry")
	var f_filch: CardData = _card_by_name(fr, "Filch")
	var f_bolt: CardData = _card_by_name(fr, "Bolt")
	var f_dig: CardData = _card_by_name(fr, "Dig")
	feng.piles.hand.clear()
	for c in fr:
		feng.piles.hand.append(c)
	feng.piles.draw_pile.append(_neutral_attack("Deep", 1, 6))
	var thrown := _neutral_attack("Thrown Away", 1, 6)
	feng.piles.discard_pile.append(thrown)
	var quarry := feng.enemies[0].stats
	var q_hp := quarry.current_hp
	feng.play_card(f_filch, feng.player_stats)
	_check("Filch is free and gives an energy", feng.energy == 4)
	var f_before := feng.piles.hand.size()
	feng.play_card(f_scurry, feng.player_stats)
	_check("Scurry draws one for nothing", feng.energy == 4 and feng.piles.hand.size() == f_before)
	feng.play_card(f_bolt, quarry)
	_check("Bolt lays 2 Vulnerable for an energy",
		feng.energy == 3 and quarry.get_status_stacks(StatusEffects.VULNERABLE) == 2)
	feng.play_card(f_dig, feng.player_stats)
	_check("Dig brings the thrown-away card back up to hand for an energy",
		thrown in feng.piles.hand and thrown not in feng.piles.discard_pile and feng.energy == 2)
	_check("the ferret's four hurt nothing themselves", quarry.current_hp == q_hp)
	feng.free()
	_reset_consumable_state()


## Part 3b: the huntsman's node. The Master of Game is seated once on every Camelot act-1 map in
## the mid-act, as a scripted event node on no reserved node; the event sells every animal the
## keeper does not have at 75, a new one replaces the old, and leaving costs nothing.
func _test_master_of_game() -> void:
	_reset_consumable_state()
	var placed := 0
	var mid := true
	var clean := true
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = 700 + s
		var map := MapGenerator.generate(rng, &"camelot", 1, 1.0, false)
		var found := 0
		for id in map.nodes:
			var n: MapNode = map.nodes[id]
			if n.scripted_event_id != MapGenerator.MASTER_OF_GAME_ID:
				continue
			found += 1
			if n.node_type != MapNode.NodeType.EVENT or n.quest_giver_id != &"" \
					or n.quest_payoff_id != &"":
				clean = false
			if n.floor_num < MapGenerator.HUNTSMAN_MIN_FLOOR \
					or n.floor_num > MapGenerator.HUNTSMAN_MAX_FLOOR:
				mid = false
		if found == 1:
			placed += 1
	_check("the Master of Game is seated exactly once on every seeded Camelot map (%d of 40)" % placed,
		placed == 40)
	_check("it sits mid-act, on an event node that is no quest node", mid and clean)

	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var ev: EventData = es._build_master_of_game_event()
	var animals := 0
	var priced := true
	var leave: EventData.EventChoice = null
	for ch in ev.choices:
		if ch.grants_pet != &"":
			animals += 1
			if ch.gold_change != -75 or PetPool.get_pet(ch.grants_pet) == null:
				priced = false
		else:
			leave = ch
	_check("with no companion he offers all three animals at 75 each, and a leave",
		animals == 3 and priced and ev.choices.size() == 4 and leave != null
		and leave.gold_change == 0 and leave.grants_pet == &"")
	RunManager.set_pet(&"hound")
	ev = es._build_master_of_game_event()
	var offered: Array[StringName] = []
	var hawk_choice: EventData.EventChoice = null
	for ch in ev.choices:
		if ch.grants_pet != &"":
			offered.append(ch.grants_pet)
		if ch.grants_pet == &"hawk":
			hawk_choice = ch
	_check("with the hound he offers only the hawk and the ferret, and says the hound stays fed",
		offered == [&"hawk", &"ferret"] and hawk_choice != null
		and hawk_choice.result_text.find("The Hound you came with") != -1
		and hawk_choice.result_text.find("see it fed") != -1)
	RunManager.gold = 100
	es._apply_effects(hawk_choice)
	_check("taking the hawk costs 75 and replaces the hound", RunManager.gold == 25
		and RunManager.pet_id == &"hawk")
	es._apply_effects(leave)
	_check("leaving them with him changes nothing", RunManager.gold == 25 and RunManager.pet_id == &"hawk")
	es.free()
	_reset_consumable_state()


## Part 3b: the forgotten relics. Six dormant forms roll in the reward pool, each naming a woken
## form one rarity up that never rolls; the offer is guaranteed while the keeper carries none; a
## record site builds one waking option per dormant relic carried and none otherwise; waking
## replaces the relic in place; the engine applies a woken relic's second effect, the girdle's
## ward and the scabbard's guard; and a record site is seated late in every act.
## The node painter, the map peek and the legend all read MapNode.look(), so what it returns is
## what the player can see. A payoff must be indistinguishable until armed.
func _test_map_node_looks() -> void:
	print("-- Map node looks --")
	var plain := MapNode.new()
	plain.node_type = MapNode.NodeType.COMBAT
	var payoff := MapNode.new()
	payoff.node_type = MapNode.NodeType.COMBAT
	payoff.quest_payoff_id = &"raiders"
	_check("an unarmed payoff reads as the ordinary node it sits on", payoff.look(false) == plain.look(false))
	_check("an armed payoff reads as the quest mark", payoff.look(true) == MapNode.QUEST_MARK_LOOK)
	_check("arming means nothing on a node with no payoff", plain.look(true) == plain.look(false))
	var giver := MapNode.new()
	giver.node_type = MapNode.NodeType.EVENT
	giver.quest_giver_id = &"raiders"
	_check("a quest giver reads as an ordinary event", giver.look() == MapNode.TYPE_LOOKS[MapNode.NodeType.EVENT])
	var huntsman := MapNode.new()
	huntsman.node_type = MapNode.NodeType.EVENT
	huntsman.scripted_event_id = MapGenerator.MASTER_OF_GAME_ID
	_check("the Master of Game shows as itself", huntsman.look()["glyph"] == "♘")
	var elite := MapNode.new()
	elite.node_type = MapNode.NodeType.ELITE
	elite.weakened = true
	_check("a weakened elite has its own drained look", elite.look() == MapNode.WEAKENED_ELITE_LOOK)
	for id in MapGenerator.RECORD_SITE_IDS:
		_check("record site %s has a look" % id, MapNode.SCRIPTED_LOOKS.has(id))


## The map's flourishes are presentation: however one ends, the map is left at rest, showing what the
## run says is true. A click carried over from the last screen cannot skip one, the pledge's reveal
## plays out the first time it is shown, and the click that does hurry one is used up, so it cannot
## also land on a node.
func _test_map_flourish() -> void:
	print("-- Map flourish --")
	RunManager.start_run(CharacterPool.build_emo_hybrid(), 424242)
	RunManager.realm_config.elite_frequency_mult = 1.4
	RunManager.current_map = null
	var scene = load("res://scenes/map/map_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	var map: MapData = RunManager.current_map
	var at_rest: int = scene.map_canvas.get_child_count()
	_check("a pledge changes nodes to show", not map.pledge_changes.is_empty())
	for id in map.pledge_changes:
		_check("a changed node keeps its old look until the ink reaches it",
			scene.node_buttons[id].get_meta("look") == MapNode.TYPE_LOOKS[MapNode.NodeType.COMBAT])
	_check("a flourish holds the map from its first frame", scene._pledge_anim_active)
	for i in 3:
		await get_tree().process_frame
	_check("the rewrite plays on a pledged map", scene._flourish != null)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	scene._input(click)
	_check("a click in the grace does not skip the flourish", scene._flourish != null)
	scene._flourish._age = MapFlourish.HURRY_AFTER
	scene._input(click)
	_check("a click after the grace does not skip the pledge's first showing", scene._flourish != null)
	# The replay has been seen, so it can be hurried, and the map is left at rest however it ends.
	scene._prime_pledge_changes()
	for i in 3:
		await get_tree().process_frame
	_check("the rewrite replays", scene._flourish != null)
	scene._flourish._age = MapFlourish.HURRY_AFTER
	scene._input(click)
	_check("a click after the grace hurries the replay", scene._flourish == null)
	_check("the hurrying click is used up", get_viewport().is_input_handled())
	await get_tree().process_frame
	_check_map_at_rest(scene, at_rest, "hurried rewrite")

	var giver := -1
	var payoff := -1
	for id in map.nodes:
		if map.nodes[id].quest_giver_id == &"raiders":
			giver = id
		if map.nodes[id].quest_payoff_id == &"raiders":
			payoff = id
	var road := map.road_between(giver, payoff)
	var walkable := road.size() >= 2 and road[0] == giver and road[road.size() - 1] == payoff
	for i in road.size() - 1:
		walkable = walkable and map.nodes[road[i]].next_nodes.has(road[i + 1])
	_check("the road to a quest is one the player can walk", walkable)
	_check("no road runs back down the map", map.road_between(payoff, giver).is_empty())
	var from_start := map.road_between(-1, payoff)
	_check("before entering the map, a road starts on the opening row",
		from_start.size() >= 2 and map.starting_node_ids.has(from_start[0]))

	scene.queue_free()
	await get_tree().process_frame
	map.move_to(giver)
	RunManager.arm_quest(&"raiders")
	scene = load("res://scenes/map/map_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	_check("an armed payoff keeps its ordinary look until the glyph lands",
		scene.node_buttons[payoff].get_meta("look") == map.nodes[payoff].look(false))
	for i in 3:
		await get_tree().process_frame
	_check("the mark plays on returning armed", scene._flourish != null)
	_check("the mark plays once", RunManager.first_unrevealed_quest() == &"")
	scene._flourish.finish_now()
	await get_tree().process_frame
	_check_map_at_rest(scene, at_rest, "hurried mark")
	_check("a hurried mark still shows its glyph", scene.node_buttons[payoff].get_meta("look") == MapNode.QUEST_MARK_LOOK)
	var shown := ""
	for child in scene.get_children():
		if child is CenterContainer and child.get_child(0) is Label:
			shown = child.get_child(0).text
	_check("a hurried mark still brings up the objective, in the toast's own words",
		shown.replace("\n", " ") == scene._quest_reveal_toast(&"raiders"))
	scene.queue_free()
	await get_tree().process_frame
	RunManager.current_map = null


func _check_map_at_rest(scene: Node, canvas_children: int, tag: String) -> void:
	_check("%s: the canvas is back at rest" % tag,
		scene.map_canvas.scale == Vector2.ONE and scene.map_canvas.position == Vector2.ZERO)
	_check("%s: the map takes clicks again" % tag, not scene._pledge_anim_active)
	_check("%s: nothing of the flourish is left on the canvas" % tag,
		scene.map_canvas.get_child_count() == canvas_children)
	var settled := true
	var map: MapData = RunManager.current_map
	for id in scene.node_buttons:
		var btn: Button = scene.node_buttons[id]
		var node: MapNode = map.nodes[id]
		settled = settled and btn.scale == Vector2.ONE and btn.z_index == 0 \
			and btn.get_meta("look") == node.look(scene._is_quest_payoff_armed(node))
	_check("%s: every node is its own size, on its layer, showing its real look" % tag, settled)


## The crossing is staged for the clip: it names nothing, changes no map data, and gives the map back
## as it found it. A word or a legend entry on it would be a name it has not been given.
func _test_crossing_stage() -> void:
	print("-- Crossing stage --")
	RunManager.start_run(CharacterPool.build_emo_hybrid(), 424242)
	RunManager.current_map = null
	var scene = load("res://scenes/map/map_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	for i in 3:
		await get_tree().process_frame
	var map: MapData = RunManager.current_map
	var at_rest: int = scene.map_canvas.get_child_count()
	var data_before := _map_fingerprint(map)
	var legend_before := _legend_words(scene)

	var crossing := CrossingStage.play(scene)
	var picked: MapNode = crossing._pick_node(map)
	_check("it stands on an ordinary node on floors 8 to 10",
		picked != null and picked.floor_num >= 8 and picked.floor_num <= 10 and picked.quest_payoff_id == &""
		and picked.quest_giver_id == &"" and picked.scripted_event_id == &"")
	_check("it holds the map while it plays", scene._pledge_anim_active)
	_check("the other map waits for the step", crossing._cold_mat.get_shader_parameter("reach") == 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("it adds nothing to the legend", _legend_words(scene) == legend_before)
	_check("it changes no map data", _map_fingerprint(map) == data_before)
	_check("the other map never reaches the run", RunManager.current_map == map)
	var cold_ids: Array = crossing._cold_nodes
	_check("the other map has nodes of its own", cold_ids.size() >= 10)
	var colours := {}
	var whole := true
	for destination in CrossingStage.CROSSING_LOOKS:
		var look: Dictionary = CrossingStage.CROSSING_LOOKS[destination]
		whole = whole and look.has("glyph") and look.has("color")
		colours[look.get("color")] = true
	_check("every destination has a look of its own colour",
		whole and colours.size() == CrossingStage.CROSSING_LOOKS.size())
	_check("the crossing shown wears its destination's colour",
		crossing._node_btn.get_theme_stylebox("normal").border_color
		== CrossingStage.CROSSING_LOOKS[CrossingStage.SWAP_REALM]["color"])
	var icon_look: Dictionary = crossing._node_btn.get_meta("look")
	_check("the icon's face leaves its look and legend entry alone", icon_look == picked.look())

	crossing.step_through()
	for i in 3:
		await get_tree().process_frame
	_check("the swap is one call", crossing._cold_mat.get_shader_parameter("reach") > 0.0)
	var worded := false
	for prop in crossing._props:
		worded = worded or prop is Label
	_check("nothing on the stage carries a word", not worded)
	_check("nothing is left to say where you were", crossing._header != null)
	for layer in CrossingStage.COLD_LAYERS:
		_check("the other map's layer exists: %s" % layer[0], ResourceLoader.exists(CrossingStage.COLD_DIR + layer[0]))

	crossing.close()
	await get_tree().process_frame
	_check_map_at_rest(scene, at_rest, "closed crossing")
	var all_back := true
	for id in scene.node_buttons:
		all_back = all_back and scene.node_buttons[id].modulate.a > 0.0
	_check("every node it hid is back", all_back)
	_check("the icon is an ordinary node again", crossing_node_text(scene, picked))
	_check("the header and the key are back",
		scene._header.modulate.a == 1.0 and scene._legend_plate.modulate.a == 1.0)
	_check("the map's data is still as it was", _map_fingerprint(map) == data_before)

	# Each look of the light, and the road the ink-fading one has to give back.
	for light in CrossingStage.Light.values():
		var look := CrossingStage.play(scene, -1, light)
		await get_tree().process_frame
		look.step_through()
		look.close()
		await get_tree().process_frame
		_check_map_at_rest(scene, at_rest, "closed crossing, light %d" % light)
		var inked := false
		var all_visible := true
		for child in scene.map_canvas.get_children():
			inked = inked or (child is Line2D and child.gradient != null)
		for id in scene.node_buttons:
			all_visible = all_visible and scene.node_buttons[id].modulate.a > 0.0
		_check("light %d gives the roads and nodes back" % light, not inked and all_visible)
	scene.queue_free()
	await get_tree().process_frame
	RunManager.current_map = null


## R9: an event's page keeps its story. The opening stays when a choice is taken, the choice stays as a
## marked line with its result and summary under it, and the Reliquary's next stage goes on below in
## the same scene. Across the chapel beast's fight the page is carried to the stage it returns to,
## taken once, and a page left for some other id is dropped.
func _test_event_page() -> void:
	print("-- Event page --")
	RunManager.start_run(CharacterPool.build_emo_hybrid(), 424242)
	var entry := EventPool._reliquary()
	RunManager.pending_special_event = &"reliquary"
	var scene: Control = load("res://scenes/event/event_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	_check("an event opens on its description with its choices under it",
		scene._told.size() == 1 and scene._told[0].text == entry.description
		and scene.choice_container.get_child_count() == entry.choices.size())
	scene._on_choice_selected(0)  # cross the yard: -6 HP, then the struck stage
	await get_tree().process_frame
	var kinds: Array = []
	for part in scene._parts:
		kinds.append(part["kind"])
	_check("the opening, the choice taken, its result and summary stay, then the next stage",
		kinds == ["text", "choice", "text", "summary", "rule", "text"]
		and scene._parts[1]["text"] == entry.choices[0].text
		and scene._parts[2]["text"] == entry.choices[0].result_text
		and scene._parts[3]["text"] == "-6 HP")
	_check("what has been read steps back, and the choice taken stays bright",
		scene._told[0].self_modulate == scene.STORY_PAST and scene._told[1].self_modulate == Color.WHITE)
	var struck: EventData = scene._build_special_event(&"reliquary_struck")
	_check("the struck stage plays in the same scene, with its own choices",
		scene.desc_label.text == struck.description and RunManager.pending_special_event == &""
		and scene.choice_container.get_child_count() == struck.choices.size())

	# Staying with her starts the chapel beast's fight. The fight is not launched here: the hand-off is
	# checked on its own, with the id the fight sets.
	var stay: EventData.EventChoice = scene.event.choices[1]
	scene._take_choice(stay)
	RunManager.pending_special_event = &"reliquary_won"
	scene._carry_story_into_fight()
	var carried_parts: int = scene._parts.size()
	_check("the page goes with the fight to the stage it returns to, ending on the choice that started it",
		RunManager.event_story.get("resume") == &"reliquary_won"
		and RunManager.event_story["parts"].size() == carried_parts
		and RunManager.event_story["parts"][-1]["text"] == stay.text)
	scene.queue_free()
	await get_tree().process_frame
	var won: Control = load("res://scenes/event/event_scene.tscn").instantiate()
	get_tree().root.add_child(won)
	await get_tree().process_frame
	_check("after the fight the page opens on the story so far, then the won stage under a rule",
		won._parts.size() == carried_parts + 2 and won._parts[carried_parts]["kind"] == "rule"
		and won._parts[0]["text"] == entry.description
		and won.desc_label.text == won.event.description and won._told[0].self_modulate == won.STORY_PAST)
	_check("the carried page is taken once", RunManager.event_story.is_empty())
	won.queue_free()
	await get_tree().process_frame

	# A page left for another id is dropped, never shown on the next event.
	RunManager.event_story = {"resume": &"raider_victory", "parts": [{"kind": "text", "text": "stale"}]}
	RunManager.pending_special_event = &"reliquary"
	var other: Control = load("res://scenes/event/event_scene.tscn").instantiate()
	get_tree().root.add_child(other)
	await get_tree().process_frame
	_check("a page left for another stage is dropped", other._parts.size() == 1 and RunManager.event_story.is_empty())
	# A one-stage outcome appends too: heed the warning, and the description stays above the result.
	other._on_choice_selected(1)
	await get_tree().process_frame
	var leave_found := false
	for c in other._story.get_children():
		if c is Button and c.text == "Continue":
			leave_found = true
	_check("a one-stage event keeps its description above the result, with Continue at the foot",
		other._parts.size() >= 3 and other._parts[0]["text"] == entry.description
		and other._parts[2]["text"] == entry.choices[1].result_text and leave_found)
	other.queue_free()
	await get_tree().process_frame
	RunManager.pending_special_event = &""


func crossing_node_text(scene: Node, node: MapNode) -> bool:
	return scene.node_buttons[node.id].text == node.look()["glyph"]


func _map_fingerprint(map: MapData) -> String:
	var parts: PackedStringArray = []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		parts.append("%d:%d:%s:%s:%s:%s:%s" % [id, n.node_type, n.weakened, n.quest_giver_id, n.quest_payoff_id,
			n.scripted_event_id, n.next_nodes])
	parts.append("at %d, %d changes" % [map.current_node_id, map.pledge_changes.size()])
	return "|".join(parts)


func _legend_words(scene: Node) -> PackedStringArray:
	var words: PackedStringArray = []
	for row in scene._legend_key.get_children():
		if not row.is_queued_for_deletion():
			words.append(row.get_child(1).text)
	return words


## R3: the node key sits in the left margin clear of every node and names what the map shows, once a
## kind. Pointing at an entry rings every node of that kind and steps the rest back, the pulse waits
## while it does, and leaving the entry gives every node its light back.
func _test_map_key() -> void:
	print("-- Map key --")
	RunManager.start_run(CharacterPool.build_emo_hybrid(), 424242)
	RunManager.realm_config = RealmConfig.new()
	RunManager.current_map = null
	var scene = load("res://scenes/map/map_scene.tscn").instantiate()
	get_tree().root.add_child(scene)
	for i in 3:
		await get_tree().process_frame
	var kinds := {}
	var leftmost := INF
	for id in scene.node_buttons:
		var btn: Button = scene.node_buttons[id]
		kinds[btn.get_meta("look")["name"]] = true
		leftmost = minf(leftmost, btn.global_position.x)
	var rows: Array = scene._legend_key.get_children()
	_check("the key sits in the left margin, clear of every node",
		scene._legend_plate.get_parent() == scene and scene._legend_plate.get_global_rect().end.x < leftmost)
	_check("the key names every kind the map shows, once", rows.size() == kinds.size() and rows.size() > 3)

	var kind: String = rows[0].get_child(1).text
	scene._update_node_states()
	var before := {}
	var matching := 0
	for id in scene.node_buttons:
		before[id] = scene.node_buttons[id].modulate
		if scene.node_buttons[id].get_meta("look")["name"] == kind:
			matching += 1
	var canvas_at_rest: int = scene.map_canvas.get_child_count()
	rows[0].mouse_entered.emit()
	var lit_right := true
	for id in scene.node_buttons:
		var btn: Button = scene.node_buttons[id]
		if btn.get_meta("look")["name"] == kind:
			lit_right = lit_right and btn.modulate == Color.WHITE
		else:
			lit_right = lit_right and is_equal_approx(btn.modulate.a, scene.LEGEND_DIM)
	_check("pointing at %s rings each of its %d nodes" % [kind, matching],
		scene._legend_rings.size() == matching and matching > 0)
	_check("and lights them while the rest step back", lit_right)
	await get_tree().process_frame
	var held := true
	for id in scene.node_buttons:
		if scene.node_buttons[id].get_meta("look")["name"] != kind:
			held = held and is_equal_approx(scene.node_buttons[id].modulate.a, scene.LEGEND_DIM)
	_check("the pulse waits while the key points", held)
	rows[0].mouse_exited.emit()
	var given_back := true
	for id in scene.node_buttons:
		given_back = given_back and scene.node_buttons[id].modulate == before[id]
	_check("leaving the entry gives every node its light back",
		given_back and scene._legend_rings.is_empty() and scene.map_canvas.get_child_count() == canvas_at_rest)
	scene.queue_free()
	await get_tree().process_frame
	RunManager.current_map = null


## The card face moves sentences between zones and must never lose or change one: for every shipped
## card, its zones hold exactly the words of its description, printed and in combat.
func _test_card_face_words() -> void:
	print("-- Card face words --")
	var sets: Array = [CharacterPool.emo_starting_deck(), CardPool._build_generic_pool(),
		CardPool.build_emo_primary_pool(), CardPool.build_emo_secondary_pool(),
		CardPool.build_memory_cards(), [CardPool.get_curse_card(&"clinging_grief")],
		[CardPool.build_excalibur_card()], CardPool.build_hound_cards(), CardPool.build_hawk_cards(),
		CardPool.build_ferret_cards()]
	var stats := CombatantStats.new(80, 80)
	stats.apply_status(StatusEffects.STRENGTH, 2)
	var total := 0
	var printed_ok := 0
	var modified_ok := 0
	for pile in sets:
		for card in pile:
			total += 1
			if _same_words(card.get_face_text(), card.get_generated_description()):
				printed_ok += 1
			else:
				print("   printed differs: %s" % card.card_name)
			if _same_words(card.get_face_text(stats), card.get_modified_description(stats)):
				modified_ok += 1
			else:
				print("   in combat differs: %s" % card.card_name)
	_check("all %d cards' zones hold their printed words" % total, printed_ok == total and total > 50)
	_check("all %d cards' zones hold their words in combat" % total, modified_ok == total and total > 50)
	# The slab's numeral is the bracket: the same function answers both.
	var hit := DamageEffect.new()
	hit.value = 5
	_check("the numeral is the bracket's number", hit.modified_value(stats) == 7 \
		and hit.get_modified_description(stats).begins_with("Deal 5 [7] damage"))


func _same_words(face: Dictionary, whole: String) -> bool:
	var a: PackedStringArray = (face["rules"] + " " + face["passion"] + " " + face["trick"]).split(" ", false)
	var b: PackedStringArray = whole.replace("\n", " ").split(" ", false)
	a.sort()
	b.sort()
	return a == b


func _test_forgotten_relics() -> void:
	_reset_consumable_state()
	RunManager.relics.clear()
	var dormant := ["A Plain Shield", "An Unpicked Banner", "A Rubbed Brass",
		"A Faded Girdle", "A Bare Scabbard", "A Bone Comb"]
	var woken := ["The Hart's Shield", "The Oak Banner", "The Brass of Sir Aldric",
		"The Green Girdle", "Excalibur's Scabbard", "Harja"]
	var pool_names := PackedStringArray()
	for r in RelicPool._build_pool():
		pool_names.append(r.relic_name)
	var pairs_ok := true
	var dormant_roll := true
	var woken_never := true
	var up_one := true
	var tells := true
	var lines := true
	var second := true
	for i in 6:
		var d := RelicPool.get_relic_by_name(dormant[i])
		var w := RelicPool.get_relic_by_name(woken[i])
		if d == null or w == null:
			pairs_ok = false
			continue
		if String(d.wakes_into) != woken[i] or String(w.woken_from) != dormant[i] \
				or not d.is_dormant() or d.is_woken() or not w.is_woken() or w.is_dormant():
			pairs_ok = false
		if dormant[i] not in pool_names:
			dormant_roll = false
		if woken[i] in pool_names:
			woken_never = false
		if int(w.rarity) != int(d.rarity) + 1 or w.trigger != d.trigger or w.effect != d.effect:
			up_one = false
		if d.description.find(" once.") == -1 and d.description.find("still show") == -1 \
				and d.description.find("worn smooth") == -1 \
				and d.description.find("no one here can read") == -1:
			tells = false
		if d.wake_line == "" or d.short_name == "" or d.wake_line.find("—") != -1:
			lines = false
		if w.effect2 == RelicData.RelicEffect.NONE and w.value2 <= 0:
			second = false
	_check("six dormant relics each name a woken form, and the woken form names it back", pairs_ok)
	_check("every dormant form rolls in the reward pool and no woken form ever does",
		dormant_roll and woken_never)
	_check("each woken form keeps its trigger and effect, one rarity up, with a second effect or an engine number",
		up_one and second)
	_check("each dormant text carries one line of absence, and each has a short name and a wake line",
		tells and lines)
	_check("the dormant names are known in a stable order", RelicPool.dormant_names().size() == 6)

	# --- Carrying and waking: in place, once, only the one named.
	var shield := RelicPool.get_relic_by_name("A Plain Shield")
	var comb := RelicPool.get_relic_by_name("A Bone Comb")
	var quill := RelicPool.get_relic_by_name("Iron Quill")
	_check("with no relics the keeper carries no forgotten relic",
		not RunManager.carries_forgotten_relic() and RunManager.get_forgotten_relics().is_empty())
	RunManager.add_relic(quill)
	RunManager.add_relic(shield)
	RunManager.add_relic(comb)
	_check("the dormant relics carried are listed in pickup order, and an ordinary one is not",
		RunManager.get_forgotten_relics().size() == 2 and RunManager.get_forgotten_relics()[0] == shield
		and RunManager.carries_forgotten_relic())
	var hart := RunManager.wake_relic_by_name("A Plain Shield")
	_check("waking the shield puts The Hart's Shield in its slot and leaves the comb asleep",
		hart != null and hart.relic_name == "The Hart's Shield" and RunManager.relics[1] == hart
		and RunManager.relics[2] == comb and RunManager.get_forgotten_relics().size() == 1
		and RunManager.has_relic("The Hart's Shield") and not RunManager.has_relic("A Plain Shield"))
	_check("a woken relic cannot be woken again, and a name not carried wakes nothing",
		RunManager.wake_relic_by_name("The Hart's Shield") == null
		and RunManager.wake_relic_by_name("A Faded Girdle") == null)
	_check("a keeper holding a woken relic still counts as carrying a forgotten one",
		RunManager.carries_forgotten_relic())

	# --- The offer: with none carried every pick holds a dormant relic; with one, the roll is
	# ordinary; the dormant form of a woken relic is never offered again.
	RunManager.relics.clear()
	var offered_each_time := true
	for s in 20:
		var picks := RelicPool.get_reward_choices(_seeded(900 + s), 3, [])
		var has_dormant := false
		for r in picks:
			if r.is_dormant():
				has_dormant = true
		if not has_dormant:
			offered_each_time = false
	_check("while the keeper carries no forgotten relic, every relic pick of three includes a dormant one",
		offered_each_time)
	RunManager.add_relic(hart)
	var never_again := true
	var ordinary_sometimes := false
	for s in 20:
		var picks := RelicPool.get_reward_choices(_seeded(900 + s), 3, RunManager.get_owned_relic_names())
		var has_dormant := false
		for r in picks:
			if r.relic_name == "A Plain Shield":
				never_again = false
			if r.is_dormant():
				has_dormant = true
		if not has_dormant:
			ordinary_sometimes = true
	_check("with The Hart's Shield carried A Plain Shield never rolls, and the roll is ordinary again",
		never_again and ordinary_sometimes)
	_check("a seeded roll with the offer is the same roll twice",
		_relic_names(RelicPool.get_reward_choices(_seeded(77), 3, []))
		== _relic_names(RelicPool.get_reward_choices(_seeded(77), 3, [])))

	# --- The engine: the second effect, the girdle's ward, the scabbard's guard.
	var deck: Array[CardData] = []
	for i in 10:
		deck.append(_neutral_attack("Card %d" % i, 1, 6))
	RunManager.relics.clear()
	RunManager.add_relic(hart)
	var eng := CombatEngine.new()
	add_child(eng)
	eng.start_combat(deck, 50, 50, [_dummy_attacker()])
	_check("The Hart's Shield opens a fight with 8 Block and 1 Poise, the Block landing first",
		eng.player_stats.block == 8 and eng.player_stats.get_status_stacks(StatusEffects.DEXTERITY) == 1)
	eng.free()
	RunManager.relics.clear()
	RunManager.add_relic(RelicPool.get_relic_by_name("The Oak Banner"))
	RunManager.add_relic(RelicPool.get_relic_by_name("Harja"))
	eng = CombatEngine.new()
	add_child(eng)
	eng.start_combat(deck, 50, 50, [_dummy_attacker()])
	_check("The Oak Banner and Harja: 1 Strength, 1 Poise and two extra cards in the opening hand",
		eng.player_stats.get_status_stacks(StatusEffects.STRENGTH) == 1
		and eng.player_stats.get_status_stacks(StatusEffects.DEXTERITY) == 1
		and eng.piles.hand.size() == 7)
	eng.free()
	RunManager.relics.clear()
	RunManager.add_relic(RelicPool.get_relic_by_name("The Brass of Sir Aldric"))
	RunManager.max_hp = 50
	RunManager.current_hp = 40
	RunManager.gold = 0
	eng = CombatEngine.new()
	add_child(eng)
	eng.start_combat(deck, 40, 50, [_dummy_attacker()])
	eng.process_combat_end_relics()
	_check("The Brass of Sir Aldric pays 15 gold and mends 6 when a fight ends",
		RunManager.gold == 15 and RunManager.current_hp == 46)
	eng.free()
	RunManager.relics.clear()
	RunManager.add_relic(RelicPool.get_relic_by_name("The Green Girdle"))
	eng = CombatEngine.new()
	add_child(eng)
	eng.start_combat(deck, 10, 50, [_dummy_attacker()])
	var foe := eng.enemies[0].stats
	eng.deal_damage(eng.player_stats, 30, foe)
	_check("The Green Girdle turns a felling blow into 1 HP, once, and the fight goes on",
		eng.player_stats.current_hp == 1 and eng.phase != CombatEngine.Phase.BATTLE_LOST)
	eng.deal_damage(eng.player_stats, 30, foe)
	_check("the second felling blow lands", eng.player_stats.current_hp == 0
		and eng.phase == CombatEngine.Phase.BATTLE_LOST)
	eng.free()
	RunManager.relics.clear()
	RunManager.add_relic(RelicPool.get_relic_by_name("Excalibur's Scabbard"))
	eng = CombatEngine.new()
	add_child(eng)
	eng.start_combat(deck, 50, 50, [_dummy_attacker()])
	foe = eng.enemies[0].stats
	var hp0 := eng.player_stats.current_hp
	eng.deal_damage(eng.player_stats, 20, foe)
	_check("Excalibur's Scabbard takes 1 off an enemy's 20 (after its turn-start mend of 2)",
		hp0 - eng.player_stats.current_hp == 19 and hp0 == 50)
	eng.self_damage(eng.player_stats, 5)
	_check("a cost the player pays themselves is not softened",
		hp0 - eng.player_stats.current_hp == 24)
	eng.free()
	var bare := CombatEngine.new()
	add_child(bare)
	RunManager.relics.clear()
	bare.start_combat(deck, 10, 50, [_dummy_attacker()])
	bare.deal_damage(bare.player_stats, 30, bare.enemies[0].stats)
	_check("without the girdle a felling blow fells", bare.phase == CombatEngine.Phase.BATTLE_LOST)
	bare.free()

	# --- The sites: one waking option per dormant relic carried, none otherwise, and the relic's
	# own wake line in the outcome.
	RunManager.relics.clear()
	var es: Control = load("res://scenes/event/event_scene.gd").new()
	var scrip_none: EventData = EventPool._scriptorium()
	var tourn_none: EventData = EventPool._the_tourney()
	var struck_none: EventData = es._build_reliquary_struck_event()
	_check("with no dormant relic the three sites show no waking (4, 3 and 2 options)",
		scrip_none.choices.size() == 4 and tourn_none.choices.size() == 3
		and struck_none.choices.size() == 2 and _wakings(scrip_none) == 0)
	RunManager.add_relic(RelicPool.get_relic_by_name("A Plain Shield"))
	RunManager.add_relic(RelicPool.get_relic_by_name("A Bone Comb"))
	var scrip: EventData = EventPool._scriptorium()
	var tourn: EventData = EventPool._the_tourney()
	var struck: EventData = es._build_reliquary_struck_event()
	_check("with two dormant relics each site shows two wakings, one per relic",
		_wakings(scrip) == 2 and _wakings(tourn) == 2 and _wakings(struck) == 2)
	var shield_wake: EventData.EventChoice = null
	for ch in scrip.choices:
		if ch.wakes_relic == &"A Plain Shield":
			shield_wake = ch
	_check("the Scriptorium names the thing and tells its waking in the outcome",
		shield_wake != null and shield_wake.text.find("the plain shield") != -1
		and shield_wake.result_text.find("a hart, lying down") != -1
		and shield_wake.gold_change == 0 and shield_wake.awarded_title_id == &"")
	es._apply_effects(shield_wake)
	_check("taking it wakes the shield in place and leaves the comb asleep",
		RunManager.has_relic("The Hart's Shield") and RunManager.get_forgotten_relics().size() == 1)
	_check("the sites resolve as scripted events by id",
		es._build_special_event(&"scriptorium").event_name == "The Scriptorium"
		and es._build_special_event(&"tourney").event_name == "The Tourney"
		and es._build_special_event(&"reliquary").event_name == "The Reliquary")
	es.free()

	# --- The seated record site: once a map, late, one of the three, beside the huntsman.
	var seated := 0
	var late := true
	var ids_ok := true
	var apart := true
	for s in range(40):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1100 + s
		var map := MapGenerator.generate(rng, &"camelot", 1, 1.0, false)
		var found := 0
		var huntsman := -1
		var site := -1
		for id in map.nodes:
			var n: MapNode = map.nodes[id]
			if n.scripted_event_id == MapGenerator.MASTER_OF_GAME_ID:
				huntsman = id
			if n.scripted_event_id in MapGenerator.RECORD_SITE_IDS:
				found += 1
				site = id
				if n.node_type != MapNode.NodeType.EVENT:
					ids_ok = false
				if n.floor_num < MapGenerator.RECORD_SITE_MIN_FLOOR \
						or n.floor_num > MapGenerator.RECORD_SITE_MAX_FLOOR:
					late = false
		if found == 1:
			seated += 1
		if site != -1 and site == huntsman:
			apart = false
	_check("a record site is seated exactly once on every seeded map (%d of 40), late, as an event, never on the huntsman"
		% seated, seated == 40 and late and ids_ok and apart)
	RunManager.relics.clear()
	_reset_consumable_state()


## The number of waking options an event offers.
func _wakings(ev: EventData) -> int:
	var n := 0
	for ch in ev.choices:
		if ch.wakes_relic != &"":
			n += 1
	return n


func _relic_names(relics: Array[RelicData]) -> PackedStringArray:
	var names := PackedStringArray()
	for r in relics:
		names.append(r.relic_name)
	return names


## The names of a companion deck, in its built order.
func _deck_names(deck: Array[CardData]) -> PackedStringArray:
	var names := PackedStringArray()
	for c in deck:
		names.append(c.card_name)
	return names


## True if the Tiltyard's quiet option (the warm mundane one) hands over the hound.
func _tiltyard_grants_hound() -> bool:
	for ev in EventPool._build_pool():
		if ev.event_name == "The Tiltyard":
			for ch in ev.choices:
				if ch.grants_pet == &"hound":
					return true
	return false


## The names of the cards a companion brings over `turns` consecutive player turns, as one string.
func _pet_arrivals(id: StringName, turns: int) -> String:
	RunManager.set_pet(id)
	var eng := _consumable_engine()
	var seen := PackedStringArray()
	for _i in turns:
		eng.piles.hand.clear()
		eng._pet_arrival()
		for c in eng.piles.hand:
			seen.append(c.card_name)
	eng.free()
	return ",".join(seen)


## Q4 and the Neve collisions (part 3): the six generic-fantasy relic names are gone, the pool reads as
## one family, every reward relic says what it is before it says what it does, and no description
## promises a drawback the engine does not apply.
func _test_relic_names() -> void:
	var retired := ["Heartfruit", "Worn Talisman", "Guardian's Sigil", "Seer's Lens",
		"Brand of Fury", "Diadem of Grace", "Field Dressing", "Marching Tonic"]
	var renamed := ["Oak Boards", "Ruled Margin", "Chained Folio", "The Index", "Rubric",
		"Flourish", "Linen Roll", "Hobnails"]
	var none_left := true
	for name in retired:
		if RelicPool.get_relic_by_name(name) != null:
			none_left = false
	var all_resolve := true
	for name in renamed:
		if RelicPool.get_relic_by_name(name) == null:
			all_resolve = false
	_check("the eight retired relic names resolve to nothing", none_left)
	_check("the eight new relic names resolve, in the reward pool and Neve's pool", all_resolve)

	# Every reward relic opens with a sentence about the thing, then the mechanic: the description
	# is longer than a bare mechanic line and ends on one (Catchword and Gilt Spurs set the pattern).
	var bare: PackedStringArray = []
	var uses_old_term: PackedStringArray = []
	for relic in RelicPool._build_pool():
		if relic.description.count(". ") < 1 and relic.description.count(".") < 2:
			bare.append(relic.relic_name)
		if relic.description.find("Dexterity") != -1:
			uses_old_term.append(relic.relic_name)
	_check("every reward relic has a leading line before its mechanic (bare: %s)" % ", ".join(bare),
		bare.is_empty())
	_check("no relic text says Dexterity where the game says Poise (%s)" % ", ".join(uses_old_term),
		uses_old_term.is_empty())

	# Rubric used to say it also made you Vulnerable, which was never applied. The text now says only
	# what the relic does, and the effect matches.
	var rubric := RelicPool.get_relic_by_name("Rubric")
	_check("Rubric gives 2 Strength and promises no drawback it does not apply",
		rubric != null and rubric.effect == RelicData.RelicEffect.GAIN_STRENGTH and rubric.value == 2
		and rubric.description.find("Vulnerable") == -1)
	var flourish := RelicPool.get_relic_by_name("Flourish")
	var margin := RelicPool.get_relic_by_name("Ruled Margin")
	_check("the two Poise relics say Poise and give it (1 and 3)",
		flourish != null and margin != null and flourish.effect == RelicData.RelicEffect.GAIN_DEXTERITY
		and flourish.value == 3 and flourish.description.find("Poise") != -1
		and margin.value == 1 and margin.description.find("Poise") != -1)
