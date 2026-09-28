extends Node
## Instrumented combat balance harness — the drift-proof companion to combat_sim.py.
##
## Unlike the Python model, this drives the REAL CombatEngine over the REAL EnemyPool
## and CardPool with the shared "decent player" policy (tools/harness_combat.gd), so its
## numbers cannot drift from the shipped rules. The engine's instant flag skips the
## enemy-turn pacing timers so thousands of trials run in seconds instead of real minutes.
##
## Run headless:
##   godot --headless --path D:\Applications\Fable res://tools/combat_harness.tscn
##
## Reports win%, turn counts, HP-lost bands, and Passion trajectory for calibration
## against docs/BALANCE_SNAPSHOTS.md and the sts-balance-targets north star. It is a
## MODEL of a competent player (greedy policy), so it sets bands; playtest finalizes.

const TRIALS := 300
const MAX_TURNS := 60
const COMMIT_TARGET := 50    # when "committing", hold Passion at/above Blazing (+50)

var _character: CharacterData
var _cbt := HarnessCombat.new()  # shared greedy-player combat policy


func _ready() -> void:
	print("\n===============================================================")
	print(" Fable combat harness — REAL engine, %d trials/scenario" % TRIALS)
	print(" player %d HP / %d energy   Passion axis -100..+100 (Blazing >= +50)" % [
		80, CombatEngine.MAX_ENERGY])
	print("===============================================================")
	_character = _build_emo_hybrid()

	_report_regulars()
	_report_elite()
	_report_poles()
	_report_prophet()
	_report_boss()
	_report_physical()

	print("\n== harness done ==\n")
	get_tree().quit()


# ============================================================
# SCENARIOS
# ============================================================

func _report_regulars() -> void:
	print("\nREGULAR ENCOUNTERS (fresh starting deck, start Passion 0):")
	var deck := _fresh_deck()
	for row in [
		["Knight (solo opener)", ["knight"]],
		["Knight + Conspirator", ["knight", "conspirator"]],
		["2 Realm Shades", ["shade", "shade"]],
		["Siege Golem (solo)", ["golem"]],
		["Golem + Conspirator", ["golem", "conspirator"]],
		["Knight + Shade", ["knight", "shade"]],
	]:
		_bar(row[0], _run(deck, row[1], 0, false))


func _report_elite() -> void:
	print("\nELITE — Champion of the Usurper (mid deck):")
	_bar("Champion", _run(_mid_deck(), ["champion"], 0, true))


func _report_prophet() -> void:
	print("\nELITE — The False Prophet (mid deck) — the Passion-pull crucible:")
	print("  Does a Water build HOLD its pole against the multiplicative center-pull?")
	# Start already committed (Blazing). Compare a player who ignores Passion
	# vs one who spends a Water card each turn to hold the pole.
	var ignore := _run(_mid_deck(), ["prophet"], 50, false)
	var commit := _run(_mid_deck(), ["prophet"], 50, true)
	_prophet_bar("ignores Passion", ignore)
	_prophet_bar("holds pole (Water)", commit)
	# Ramp probe: start dispassionate (0), commit — how fast to Blazing, and does it stick?
	var ramp := _run(_mid_deck(), ["prophet"], 0, true)
	print("  ramp from 0 (commit): avg turns-to-Blazing %s, end-Passion %.1f (%s)" % [
		_ttb_str(ramp), ramp["passion_mean"], _tier_name(int(round(ramp["passion_mean"])))])


## Symmetry check: a Water build should climb to Blazing (+), a Physical build should
## sink to Hollow (-). Both start dispassionate (0) vs a durable Champion and commit.
func _report_poles() -> void:
	# vs a durable training wall (not the Champion) so the fight lasts long enough for
	# the ~10-turn ramp to actually reach the pole — otherwise a ~7-turn fight ends
	# mid-climb and under-reads reachability.
	print("\nPASSION POLES — can a committed build reach BOTH extremes? (vs a durable wall, from 0)")
	var water := _run(_mid_deck(), ["wall"], 0, true, 50)
	var phys := _run(_physical_deck(), ["wall"], 0, true, -50)
	_pole_bar("Water build  (target +50)", water)
	_pole_bar("Physical build (target -50)", phys)


func _pole_bar(label: String, r: Dictionary) -> void:
	print("  %-26s win %5.1f%%  end-Passion %6.1f (%s)  reaches extreme: %s" % [
		label, r["winrate"], r["passion_mean"], _tier_name(int(round(r["passion_mean"]))),
		_ttb_str(r)])


func _report_boss() -> void:
	print("\nBOSS — Sir Caedmon. 'realistic' = boss deck (2 upgrades) + Excalibur + 2 relics:")
	for row in [
		["Blazing, bare mid deck", _mid_deck(), 50, false],
		["Blazing, realistic", _boss_deck(), 50, true],
		["Inspired, realistic", _boss_deck(), 18, true],
		["Wavering, realistic", _boss_deck(), -30, true],
	]:
		var r := _run(row[1], ["caedmon"], row[2], true, COMMIT_TARGET, row[3])
		print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  end-Passion %.1f (%s)" % [
			row[0], r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"],
			r["passion_mean"], _tier_name(int(round(r["passion_mean"])))])


## Content-pass-#2 feel-test: the same fights measured against a committed PHYSICAL build
## (sinks to Hollow, commit_target -50), whose deck carries the new Whetstone (Strength
## engine) + Twin Strike (Strength-riding 2-hit) alongside Sunder's Vulnerable and block.
## The Water boss number (82.3%) was tuned against a Water build; this checks the pole we
## just beefed survives Caedmon's Enraged transition too. Physical has block (Guardian's
## Sigil helps) and Iron Quill's +1 Strength feeds the ride — a fair "realistic" loadout.
func _report_physical() -> void:
	print("\n=== PHYSICAL POLE — content pass #2 (committed Hollow build) ===")
	print("ELITE — Champion of the Usurper (physical mid deck):")
	_bar("Champion (Physical)", _run(_physical_mid_deck(), ["champion"], -50, true, -50))
	print("\nBOSS — Sir Caedmon vs a committed PHYSICAL build (Whetstone/Twin Strike/Sunder + block):")
	for row in [
		["Hollow, bare mid deck", _physical_mid_deck(), -50, false],
		["Hollow, realistic", _physical_boss_deck(), -50, true],
		["Wavering, realistic", _physical_boss_deck(), -30, true],
	]:
		var r := _run(row[1], ["caedmon"], row[2], true, -50, row[3])
		print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  end-Passion %.1f (%s)" % [
			row[0], r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"],
			r["passion_mean"], _tier_name(int(round(r["passion_mean"])))])


# ============================================================
# TRIAL RUNNER + AGGREGATION
# ============================================================

func _run(deck: Array[CardData], enemy_keys: Array, start_passion: int,
		commit: bool, commit_target: int = COMMIT_TARGET, grant_excalibur := false) -> Dictionary:
	var wins := 0
	var hp_lost: Array[int] = []
	var turns_sum := 0
	var passion_sum := 0
	var ttb_sum := 0
	var ttb_count := 0
	for s in TRIALS:
		var r := _simulate(deck, enemy_keys, s, start_passion, commit, commit_target, grant_excalibur)
		turns_sum += r["turns"]
		passion_sum += r["passion"]
		if r["ttb"] >= 0:
			ttb_sum += r["ttb"]
			ttb_count += 1
		if r["win"]:
			wins += 1
			hp_lost.append(80 - r["hp"])
	hp_lost.sort()
	var mean_lost := 0.0
	if hp_lost.size() > 0:
		var tot := 0
		for v in hp_lost:
			tot += v
		mean_lost = float(tot) / hp_lost.size()
	var p90 := 80
	if hp_lost.size() > 0:
		p90 = hp_lost[mini(hp_lost.size() - 1, int(0.9 * hp_lost.size()))]
	return {
		"winrate": 100.0 * wins / TRIALS,
		"turns_mean": float(turns_sum) / TRIALS,
		"hp_lost_mean": mean_lost,
		"hp_lost_p90": p90,
		"passion_mean": float(passion_sum) / TRIALS,
		"ttb_mean": (float(ttb_sum) / ttb_count) if ttb_count > 0 else -1.0,
		"ttb_frac": float(ttb_count) / TRIALS,
	}


## One combat against the real engine. Deterministic per seed. ttb tracks turns to
## reach the COMMITTED extreme tier (Blazing for a +target, Hollow for a -target).
func _simulate(deck: Array[CardData], enemy_keys: Array, seed_val: int,
		start_passion: int, commit: bool, commit_target: int = COMMIT_TARGET,
		grant_excalibur := false) -> Dictionary:
	# Minimal run-state reset (mirrors roster_test; avoids start_run's realm/title
	# machinery which is irrelevant to a single combat).
	RunManager.current_character = _character
	RunManager.current_act = 1
	RunManager.relics.clear()
	RunManager.pending_act_complete = false
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = start_passion
	RngManager.setup_run(seed_val)
	# A realistic end-of-Act-1 boss loadout: Excalibur (Sword mode, injects its 14-dmg
	# card) plus a couple of relics a player would have picked up by the boss. Still does
	# NOT model the Sword's Bearer title (+3/attack), which would ease the fight further.
	if grant_excalibur:
		RunManager.excalibur_mode = RunManager.ExcaliburMode.SWORD
		RunManager.add_relic(RelicPool.get_relic_by_name("Excalibur"))
		RunManager.add_relic(RelicPool.get_relic_by_name("Iron Quill"))       # +1 Strength/combat
		RunManager.add_relic(RelicPool.get_relic_by_name("Guardian's Sigil"))  # +5 Block/turn

	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)

	var run_deck: Array[CardData] = []
	for c in deck:
		run_deck.append(c.duplicate_card())
	eng.start_combat(run_deck, 80, 80, _build_enemies(enemy_keys))

	var extreme_tier := (PassionState.Tier.BLAZING if commit_target >= 0
		else PassionState.Tier.HOLLOW)
	var ttb := -1
	var guard := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and eng.turn_number < MAX_TURNS:
		guard += 1
		if guard > 400:
			break
		_cbt.play_turn(eng, commit, commit_target)
		if ttb < 0 and RunManager.get_passion_tier() == extreme_tier:
			ttb = eng.turn_number
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		eng.end_player_turn()  # instant: resolves enemy turn + next player-turn setup
		if ttb < 0 and RunManager.get_passion_tier() == extreme_tier:
			ttb = eng.turn_number

	var res := {
		"win": eng.phase == CombatEngine.Phase.BATTLE_WON,
		"turns": eng.turn_number,
		"hp": maxi(0, eng.player_stats.current_hp),
		"passion": RunManager.passion.current_value,
		"ttb": ttb,
	}
	eng.free()
	return res


# ============================================================
# DECKS + ENEMIES + CHARACTER
# ============================================================

func _build_enemies(keys: Array) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for k in keys:
		match k:
			"knight": out.append(EnemyPool.corrupted_knight())
			"conspirator": out.append(EnemyPool.court_conspirator())
			"golem": out.append(EnemyPool.siege_golem())
			"shade": out.append(EnemyPool.realm_shade())
			"champion": out.append(EnemyPool.champion_of_the_usurper())
			"prophet": out.append(EnemyPool.false_prophet())
			"caedmon": out.append(EnemyPool.sir_caedmon())
			"wall": out.append(_wall())
	return out


## A high-HP, low-damage punching bag: lets the pole-ramp test run long enough
## (~15+ turns) for a committed build to actually reach its extreme.
func _wall() -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = "Training Wall"
	e.max_health = 300  # outlasts the ~10-turn ramp so both poles reach their extreme
	var m := EnemyMove.new()
	m.move_name = "Chip"
	m.intent_type = EnemyMove.IntentType.ATTACK
	m.effects.append(_dmg(4))
	e.moves.append(m)
	return e


## The real Emo Hybrid starting deck — single source of truth in CharacterPool, so
## the harness always balances the deck the game actually ships.
func _fresh_deck() -> Array[CardData]:
	return CharacterPool.emo_starting_deck()


## A developed mid-act deck: the starter core plus a Water-leaning spread of pool
## cards, so the Passion-hold and zone-bonus behaviour actually exercises.
func _mid_deck() -> Array[CardData]:
	var d := _fresh_deck()
	var prim := CardPool.build_emo_primary_pool()
	var sec := CardPool.build_emo_secondary_pool()
	# Water-leaning spread post-redesign (Riverstep/Poise is gone — the pole no longer
	# borrows Physical's turf). Undertow exercises the debuff/soak lane; Maelstrom is now
	# the X-cost torrent so it also exercises the new X path; Cascade (content pass #2) is
	# the y≥3 multi a committed Water player would draft, so the boss is tuned against it.
	for name in ["Tidal Strike", "Chillbrand", "Maelstrom", "Undertow", "Deep Freeze", "Cascade"]:
		var c := _find(prim, name)
		if c != null:
			d.append(c)
	for name in ["Power Slash", "Rampage"]:
		var c := _find(sec, name)
		if c != null:
			d.append(c)
	return d


## A Physical build: the neutral starter core (a Physical player cuts the Water
## starters) plus the secondary pool's strikes/guards, so the negative pole (Hollow)
## actually gets exercised. Water-starter names come from CharacterPool so this
## stays in sync with the deck.
func _physical_deck() -> Array[CardData]:
	var water := CharacterPool.emo_water_starters()
	var d: Array[CardData] = []
	for c in _fresh_deck():
		if not (c.card_name in water):
			d.append(c)
	var sec := CardPool.build_emo_secondary_pool()
	for name in ["Power Slash", "Rampage", "Devastating Blow", "Brace", "Iron Curtain"]:
		var c := _find(sec, name)
		if c != null:
			d.append(c)
	return d


## A realistic end-of-Act-1 deck: the mid deck with a couple of rest-site upgrades on
## the heaviest hitters, as a player would have by the boss.
func _boss_deck() -> Array[CardData]:
	var d := _mid_deck()
	var upgraded := 0
	for c in d:
		if upgraded >= 2:
			break
		if c.card_name in ["Maelstrom", "Deep Freeze", "Chillbrand", "Tidal Strike"]:
			c.upgrade_card()
			upgraded += 1
	return d


## The Physical analog of _mid_deck: the block/heavy-single spread PLUS the content-pass-#2
## Strength kit (Whetstone engine + Twin Strike rider) and a second Strength source
## (Riposte), so the new cards actually get exercised. Sunder (Vulnerable) is already in the
## shared starter, so the Vuln->Strength-2-hit burst chain is present end-to-end.
func _physical_mid_deck() -> Array[CardData]:
	var d := _physical_deck()
	var sec := CardPool.build_emo_secondary_pool()
	for name in ["Whetstone", "Twin Strike", "Riposte"]:
		var c := _find(sec, name)
		if c != null:
			d.append(c)
	return d


## The Physical boss deck: the physical mid deck with a couple of rest-site upgrades on the
## heaviest hitters (mirrors _boss_deck's two-upgrade rule for the Water build).
func _physical_boss_deck() -> Array[CardData]:
	var d := _physical_mid_deck()
	var upgraded := 0
	for c in d:
		if upgraded >= 2:
			break
		if c.card_name in ["Devastating Blow", "Rampage", "Twin Strike"]:
			c.upgrade_card()
			upgraded += 1
	return d


func _find(pool: Array[CardData], name: String) -> CardData:
	for c in pool:
		if c.card_name == name:
			return c.duplicate_card()
	return null


func _build_emo_hybrid() -> CharacterData:
	return CharacterPool.build_emo_hybrid()


# -- card / effect factories --

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


# ============================================================
# REPORT FORMATTING
# ============================================================

func _bar(label: String, r: Dictionary) -> void:
	print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  (of 80)" % [
		label, r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"]])


func _prophet_bar(label: String, r: Dictionary) -> void:
	var tier_txt := _tier_name(int(round(r["passion_mean"])))
	var verdict := "HOLDS Blazing" if r["passion_mean"] >= COMMIT_TARGET else "gets centered"
	print("  %-20s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f  end-Passion %5.1f (%s) -> %s" % [
		label, r["winrate"], r["turns_mean"], r["hp_lost_mean"],
		r["passion_mean"], tier_txt, verdict])


func _ttb_str(r: Dictionary) -> String:
	if r["ttb_mean"] < 0:
		return "never"
	return "%.1f (%d%% of runs reach it)" % [r["ttb_mean"], int(round(r["ttb_frac"] * 100))]


func _tier_name(v: int) -> String:
	return PassionState.tier_name(RunManager.get_passion_tier_for_value(v))
