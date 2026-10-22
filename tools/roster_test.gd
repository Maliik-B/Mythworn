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
	_test_liaison_relics()
	_test_refusals()
	_test_title_split()
	_test_vn_data()
	_test_profile_intro()
	_test_boss_reward()
	await _test_frozen_skips()
	await _test_chilled_freeze()
	_test_inner_fire_copies_itself()
	_test_combat_retains_nothing()
	_test_rewards_follow_the_run_seed()
	_test_harness_copy_matches_engine()
	_test_harness_copy_card_rules()
	_test_harness_policy_decides()
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
	# The Shade at the Cross's power option is now a one-shot next-combat boon.
	var lend: EventData.EventChoice = null
	if spirit:
		for ch in spirit.choices:
			if ch.grants_combat_boon != &"":
				lend = ch
	_check("The Shade at the Cross grants the wandering_vigor next-combat boon",
		lend != null and lend.grants_combat_boon == &"wandering_vigor"
		and lend.max_hp_change == 0)

	# End-to-end: a queued boon opens the next fight with +2 Strength, then clears (one-shot).
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
	# Max-HP sponge), Marching Tonic is a Poise burst (not a Strength clone), and the duplicate
	# Broken-In Boots is cut so one Poise relic owns the lane.
	var neve_by := {}
	for r in neve:
		neve_by[r.relic_name] = r
	var rations: RelicData = neve_by.get("Iron Rations")
	var tonic: RelicData = neve_by.get("Marching Tonic")
	_check("Iron Rations is per-turn regen (HEAL 2 at turn start, not Max HP)",
		rations != null and rations.effect == RelicData.RelicEffect.HEAL
		and rations.trigger == RelicData.RelicTrigger.ON_TURN_START and rations.value == 2)
	_check("Marching Tonic is a Poise burst (+2 Dexterity/Poise at combat start, not Strength)",
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
			"res://scenes/splash/splash_scene.gd"]:
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
