extends Node
## Instrumented combat balance harness, drift-proof because it runs the game's own rules.
##
## It drives the REAL CombatEngine over the REAL EnemyPool
## and CardPool with the shared "decent player" policy (tools/harness_combat.gd), so its
## numbers cannot drift from the shipped rules. The engine's instant flag skips the
## enemy-turn pacing timers so thousands of trials run in seconds instead of real minutes.
##
## Run headless:
##   godot --headless --path . res://tools/combat_harness.tscn
##
## Reports win%, turn counts, HP-lost bands, and Passion trajectory for calibration
## against its recorded baselines, with Slay the Spire's difficulty as the reference. It is a
## MODEL of a competent player (it plans each turn against the rest of the fight), so it sets
## bands; playtest finalizes.

const TRIALS := 300
const MAX_TURNS := 60
const COMMIT_TARGET := 50    # when "committing", hold Passion at/above Blazing (+50)
const FAILSAFE_QUIT_SECONDS := 1500.0  # hard self-destruct if a run errors + idles (see _ready)
const TRAJ_TURNS := 8        # the Passion trajectory is sampled after each of the first 8 turns
## The realm-config dimension. The shipped (hollow) Camelot is its only value until the Straining
## Court's design card lands; every report is tagged with it so a second value slots in beside.
const CONFIG := "shipped"

## Mismatches --verify reports and records here, in the content linter's shape. Key = "<card>:
## <field>" as printed, value = why it stands. They print and do not fail the run; a new one fails
## it, and so does one that stops occurring, so the list cannot rot.
const KNOWN_MISMATCHES := {}

## Trial seeds are _seed_base + 0..N-1. The default base 0 keeps every number comparable with the
## snapshots; --daily derives it from the UTC date (YYYYMMDD x 1000) so a day's run is the same
## for anyone running it that day. --seed=N sets the base by hand,
## --trials=N the count, --only=pets,relics,... the sections.
var _seed_base := 0
var _trials := TRIALS
var _only: PackedStringArray = []
var _daily_seed := 0
var _verify := false  # --verify: check the planner's copy against the engine instead of reporting

var _character: CharacterData
var _cbt := HarnessCombat.new()  # shared planning-player combat policy
var _aborted := false            # set when a trial passes the memory ceiling


func _ready() -> void:
	# No sound: every play() here would be kept until the run ends (see AudioManager.enabled).
	AudioManager.enabled = false
	# Failsafe self-destruct. If any report below errors out, _ready returns without reaching
	# the clean quit() and a headless process would otherwise idle forever: an orphan that
	# piles up across runs until it exhausts memory and takes the machine (and other sessions)
	# down with it. This timer fires once frames resume after such an early return and force-
	# quits. (Belt-and-suspenders with the recommended CLI --quit-after; the bounded trial loops
	# guard the only other hang path.)
	get_tree().create_timer(FAILSAFE_QUIT_SECONDS).timeout.connect(
		func() -> void:
			push_error("combat_harness failsafe timeout: forcing quit")
			get_tree().quit(1))

	_read_args()
	print("\n===============================================================")
	print(" Mythworn combat harness: REAL engine, %d trials/scenario" % _trials)
	print(" player %d HP / %d energy   Passion axis -60..+60 (Blazing >= +50)" % [
		80, CombatEngine.MAX_ENERGY])
	print(" realm config: %s   trial seeds: %d..%d%s" % [CONFIG, _seed_base, _seed_base + _trials - 1,
		"   (daily seed %d)" % _daily_seed if _daily_seed > 0 else ""])
	print("===============================================================")
	_character = _build_emo_hybrid()
	if _verify:
		_run_verify()
		return

	for report in [["regulars", _report_regulars], ["elite", _report_elite],
			["guardian", _report_guardian], ["barrow", _report_barrow_warden],
			["poles", _report_poles], ["prophet", _report_prophet], ["boss", _report_boss],
			["physical", _report_physical], ["regen", _report_regen_check],
			["sword", _report_swords_bearer], ["pets", _report_pets],
			["relics", _report_relics], ["titles", _report_titles],
			["pack", _report_consumables]]:
		if not _only.is_empty() and not _only.has(report[0]):
			continue
		report[1].call()
		if _aborted:
			print("\n== harness ABORTED at the memory ceiling; rows after the error are nan ==\n")
			return

	print("\n  %s" % _cbt.memory_summary())
	print("\n== harness done ==\n")
	get_tree().quit()


## --verify: plays the loadout x fight matrix with the planner's copy checked against the engine
## before every card and every enemy turn. Prints the counts and every mismatch by card and field.
## A clean run says the copy knows everything these loadouts do; a mismatch is a model gap. The
## ones in KNOWN_MISMATCHES do not fail the run; a new one does, and exits 1.
func _run_verify() -> void:
	_cbt.verify_on = true
	var loadouts: Array = [
		["bare", {}, "", &""],
		["hound", {"pet": &"hound"}, "", &""],
		["hawk", {"pet": &"hawk"}, "", &""],
		["ferret", {"pet": &"ferret"}, "", &""],
		["Green Girdle + Compassionate", {"relics": ["The Green Girdle"]}, "", &"the_compassionate"],
		["Scabbard + Merciful", {"relics": ["Excalibur's Scabbard"]}, "", &"the_merciful"],
		["Unfading + Sword's Bearer", {"title2": &"the_unfading"}, "", &"swords_bearer"],
		["Blooded Edge + Momentum + Oak Banner", {"relics": ["Blooded Edge", "Momentum", "The Oak Banner"]}, "", &""],
		["oil + Favour + hawk", {"pack": [&"blade_oil", &"champions_favour"], "pet": &"hawk"}, "", &""],
		["Blessing + Courage + ferret", {"pack": [&"bottled_blessing", &"unspent_courage"], "pet": &"ferret"}, "", &""],
		["Salve + Relic-Water + hound", {"pack": [&"traveller_salve", &"relic_water"], "pet": &"hound"}, "", &""],
	]
	var fights: Array = [
		["Knight + Shade", _fresh_deck(), ["knight", "shade"], 0, false],
		["Champion", _mid_deck(), ["champion"], 0, false],
		["Beast at the Stone", _mid_deck(), ["guardian"], 0, true],
		["Caedmon realistic", _boss_deck(), ["caedmon"], 50, true],
		["Wasting Knight + Shade", _mid_deck(), ["rotting", "shade"], 0, false],
	]
	var saved_trials := _trials
	_trials = mini(_trials, 25)
	for lo in loadouts:
		for f in fights:
			_run(f[1], f[2], f[3], true, COMMIT_TARGET, f[4], lo[2], lo[3], lo[1])
			if _aborted:
				return
	_trials = saved_trials
	print("\nVERIFY: the planner's copy against the engine (%d loadouts x %d fights x 25 trials)" % [
		loadouts.size(), fights.size()])
	print("  cards checked: %d   enemy turns checked: %d   distinct mismatches: %d" % [
		_cbt.verify_cards, _cbt.verify_enemy_turns, _cbt.verify_mismatches.size()])
	var keys: Array = _cbt.verify_mismatches.keys()
	keys.sort()
	var fresh := 0
	for k in keys:
		var m: Array = _cbt.verify_mismatches[k]
		var known := KNOWN_MISMATCHES.has(k)
		fresh += 0 if known else 1
		print("  %-44s x%-5d %s%s" % [k, m[0], m[1], "  KNOWN" if known else ""])
		if known:
			print("      (%s)" % KNOWN_MISMATCHES[k])
	var stale := 0
	for k in KNOWN_MISMATCHES:
		if not _cbt.verify_mismatches.has(k):
			print("  FAIL stale known mismatch, it no longer occurs: %s" % k)
			stale += 1
	var verdict := "%d new, %d stale" % [fresh, stale] if fresh + stale > 0 \
		else "%d known" % KNOWN_MISMATCHES.size()
	print("\n  %s\n\n== verify done: %s ==\n" % [_cbt.memory_summary(), verdict])
	get_tree().quit(1 if fresh + stale > 0 else 0)


## Reads the command-line arguments after `--`: --daily, --seed=N, --trials=N, --only=a,b.
func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--daily":
			_daily_seed = HarnessCombat.daily_seed()
			_seed_base = _daily_seed * 1000
		elif a.begins_with("--seed="):
			_seed_base = int(a.substr(7))
		elif a.begins_with("--trials="):
			_trials = maxi(1, int(a.substr(9)))
		elif a.begins_with("--only="):
			_only = a.substr(7).split(",", false)
		elif a == "--verify":
			_verify = true


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
		["Empty Harness (solo)", ["golem"]],
		["Harness + Conspirator", ["golem", "conspirator"]],
		["Knight + Shade", ["knight", "shade"]],
		["Wasting Knight (solo)", ["rotting"]],
		["Wasting Knight + Shade", ["rotting", "shade"]],
	]:
		_bar(row[0], _run(deck, row[1], 0, false))


func _report_elite() -> void:
	print("\nELITE: Champion of the Usurper (mid deck):")
	_bar("Champion", _run(_mid_deck(), ["champion"], 0, true))


func _report_guardian() -> void:
	print("\nQUEST FIGHT: The Beast at the Stone (the Sword in the Stone, mid deck):")
	_bar("Beast at the Stone", _run(_mid_deck(), ["guardian"], 0, true))


func _report_barrow_warden() -> void:
	print("\nEVENT FIGHT: The Barrow-Warden (Campfire treasure, optional):")
	_bar("fresh deck", _run(_fresh_deck(), ["barrow"], 0, false))
	_bar("mid deck", _run(_mid_deck(), ["barrow"], 0, false))


func _report_prophet() -> void:
	print("\nELITE: The False Prophet (mid deck), the Passion-pull crucible:")
	print("  Does a Water build HOLD its pole against the multiplicative center-pull?")
	# Start already committed (Blazing). Compare a player who ignores Passion
	# vs one who spends a Water card each turn to hold the pole.
	var ignore := _run(_mid_deck(), ["prophet"], 50, false)
	var commit := _run(_mid_deck(), ["prophet"], 50, true)
	_prophet_bar("ignores Passion", ignore)
	_prophet_bar("holds pole (Water)", commit)
	# Ramp probe: start dispassionate (0), commit: how fast to Blazing, and does it stick?
	var ramp := _run(_mid_deck(), ["prophet"], 0, true)
	print("  ramp from 0 (commit): avg turns-to-Blazing %s, end-Passion %.1f (%s)" % [
		_ttb_str(ramp), ramp["passion_mean"], _tier_name(ramp["passion_mean"])])


## Symmetry check: a Water build should climb to Blazing (+), a Physical build should
## sink to Hollow (-). Both start dispassionate (0) vs a durable Champion and commit.
func _report_poles() -> void:
	# vs a durable training wall (not the Champion) so the fight lasts long enough for
	# the ~10-turn ramp to actually reach the pole; otherwise a ~7-turn fight ends
	# mid-climb and under-reads reachability.
	print("\nPASSION POLES: can a committed build reach BOTH extremes? (vs a durable wall, from 0)")
	var water := _run(_mid_deck(), ["wall"], 0, true, 50)
	var phys := _run(_physical_deck(), ["wall"], 0, true, -50)
	_pole_bar("Water build  (target +50)", water)
	_pole_bar("Physical build (target -50)", phys)


func _pole_bar(label: String, r: Dictionary) -> void:
	print("  %-26s win %5.1f%%  end-Passion %6.1f (%s)  reaches extreme: %s" % [
		label, r["winrate"], r["passion_mean"], _tier_name(r["passion_mean"]),
		_ttb_str(r)])


func _report_boss() -> void:
	print("\nBOSS: Sir Caedmon. 'realistic' = boss deck (2 upgrades) + Excalibur + 2 relics:")
	for row in [
		["Blazing, bare mid deck", _mid_deck(), 50, false],
		["Blazing, realistic", _boss_deck(), 50, true],
		["Inspired, realistic", _boss_deck(), 18, true],
		["Wavering, realistic", _boss_deck(), -30, true],
	]:
		var r := _run(row[1], ["caedmon"], row[2], true, COMMIT_TARGET, row[3])
		print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  end-Passion %.1f (%s)" % [
			row[0], r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"],
			r["passion_mean"], _tier_name(r["passion_mean"])])


## Content-pass-#2 feel-test: the same fights measured against a committed PHYSICAL build
## (sinks to Hollow, commit_target -50), whose deck carries the new Whetstone (Strength
## engine) + Twin Strike (Strength-riding 2-hit) alongside Sunder's Vulnerable and block.
## The Water boss number (82.3%) was tuned against a Water build; this checks the pole we
## just beefed survives Caedmon's Enraged transition too. Physical has block (Guardian's
## Sigil helps) and Iron Quill's +1 Strength feeds the ride, a fair "realistic" loadout.
func _report_physical() -> void:
	print("\n=== PHYSICAL POLE: content pass #2 (committed Hollow build) ===")
	print("ELITE: Champion of the Usurper (physical mid deck):")
	_bar("Champion (Physical)", _run(_physical_mid_deck(), ["champion"], -50, true, -50))
	print("\nBOSS: Sir Caedmon vs a committed PHYSICAL build (Whetstone/Twin Strike/Sunder + block):")
	for row in [
		["Hollow, bare mid deck", _physical_mid_deck(), -50, false],
		["Hollow, realistic", _physical_boss_deck(), -50, true],
		["Wavering, realistic", _physical_boss_deck(), -30, true],
	]:
		var r := _run(row[1], ["caedmon"], row[2], true, -50, row[3])
		print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  end-Passion %.1f (%s)" % [
			row[0], r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"],
			r["passion_mean"], _tier_name(r["passion_mean"])])


## Iron Rations balance probe: the relic reworked to +2 HP at the start of each turn. Run on a
## Water build (so the innate control-heal is firing too) with and without the relic, on both a
## boss attrition fight and a long regular timer, so we can see whether regen + control-heal
## blunts attrition too hard. "Too high" would look like HP-lost collapsing toward zero or the
## win-rate jumping from a real risk to a near-certainty; a healthy sustain relic just shaves a
## chunk off the damage taken.
func _report_regen_check() -> void:
	print("\n=== IRON RATIONS REGEN CHECK: does +2 HP/turn stack too high with the control-heal? ===")
	print("  Water build (control-heal active). Identical fights, with vs without Iron Rations held.")
	# Boss, realistic loadout (already has Excalibur + 2 relics); Iron Rations is the 3rd.
	var boss_base := _run(_boss_deck(), ["caedmon"], 50, true, COMMIT_TARGET, true)
	var boss_reg := _run(_boss_deck(), ["caedmon"], 50, true, COMMIT_TARGET, true, "Iron Rations")
	# A long regular attrition timer (no Excalibur), so the regen is read in isolation.
	var reg_base := _run(_mid_deck(), ["rotting", "shade"], 0, false)
	var reg_reg := _run(_mid_deck(), ["rotting", "shade"], 0, false, COMMIT_TARGET, false, "Iron Rations")
	_regen_bar("Caedmon, realistic   (no Rations)", boss_base)
	_regen_bar("Caedmon, realistic   (+Iron Rations)", boss_reg)
	_regen_bar("Wasting+Shade        (no Rations)", reg_base)
	_regen_bar("Wasting+Shade        (+Iron Rations)", reg_reg)
	print("  read: healthy if +Rations shaves HP-lost modestly and nudges win%, not if HP-lost")
	print("        collapses toward 0 or win% jumps from a real risk to a near-certainty.")


func _regen_bar(label: String, r: Dictionary) -> void:
	print("  %-34s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f" % [
		label, r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"]])


## The Sword's Bearer, measured for the first time. Every published Caedmon win rate was
## taken WITHOUT this title, because the harness excluded it by comment, so the post-sword
## numbers were higher than anything we had ever tuned against by an unknown amount.
##
## The output is a CURVE rather than a number, because the title's value is now a function of
## fight length: the per-hit bonus opens at +1 and doubles on turns 2, 4 and 8. A short regular
## should come out WEAKER than the old flat +3, an elite about the same, and a long boss fight
## stronger. Each row is the same fight run twice off the same seeds, bare and then wearing the
## title, so the delta is the real size of the title at that duration.
func _report_swords_bearer() -> void:
	print("\nTHE SWORD'S BEARER - per-hit bonus +1/+2/+4/+8, doubling on turns 2/4/8:")
	print("  (same seeds bare vs worn; the delta IS the title at that fight length)")
	for row in [
		["Regular: Knight + Shade", _fresh_deck(), ["knight", "shade"], 0, false],
		["Elite: Champion", _mid_deck(), ["champion"], 0, false],
		["Boss: Caedmon, realistic", _boss_deck(), ["caedmon"], 50, true],
	]:
		var bare := _run(row[1], row[2], row[3], true, COMMIT_TARGET, row[4])
		var worn := _run(row[1], row[2], row[3], true, COMMIT_TARGET, row[4], "",
			&"swords_bearer")
		print("  %-26s turns %4.1f   win %5.1f%% -> %5.1f%%  (%+5.1f)   HP-lost %4.1f -> %4.1f  (%+5.1f)" % [
			row[0], bare["turns_mean"],
			bare["winrate"], worn["winrate"], worn["winrate"] - bare["winrate"],
			bare["hp_lost_mean"], worn["hp_lost_mean"],
			worn["hp_lost_mean"] - bare["hp_lost_mean"]])
	print("  Cap is 3 doublings (+8). If +8 reads too hot, the lever is the cap, not the")
	print("  schedule: the feel lives in the curve and the risk lives in the top step.")


# ============================================================
# CONTRIBUTIONS: one thing added, the same seeds, the difference
# ============================================================

## The three fights every contribution is read on: a regular on the fresh deck, an elite on the mid
## deck, the boss on the realistic loadout. Each is run twice off the same seeds, without the thing
## and with it, and the table is the difference.
func _fights() -> Array:
	return [
		["Regular", _fresh_deck(), ["knight", "shade"], 0, false],
		["Elite", _mid_deck(), ["champion"], 0, false],
		["Boss", _boss_deck(), ["caedmon"], 50, true],
	]


## Runs each variant against each fight and prints win rate, turns and HP lost as differences
## from the same fight without it. A variant is [label, opts, extra_relic, extra_title].
func _contribution_table(heading: String, variants: Array) -> void:
	print("\n%s   (config: %s; same seeds with and without; delta = with minus without)" % [
		heading, CONFIG])
	var fights := _fights()
	var bases: Array = []
	for f in fights:
		bases.append(_run(f[1], f[2], f[3], true, COMMIT_TARGET, f[4]))
	var head := "  %-30s" % "baseline (without)"
	for i in fights.size():
		head += " | %-7s win %5.1f%% turns %4.1f lost %4.1f p90 %3.0f" % [fights[i][0],
			bases[i]["winrate"], bases[i]["turns_mean"], bases[i]["hp_lost_mean"], bases[i]["hp_lost_p90"]]
	print(head)
	for v in variants:
		var row := "  %-30s" % v[0]
		for i in fights.size():
			var f: Array = fights[i]
			var r := _run(f[1], f[2], f[3], true, COMMIT_TARGET, f[4], v[2], v[3], v[1])
			if _aborted:
				return
			row += " | %-7s win %+6.1f  turns %+5.1f lost %+5.1f" % [f[0],
				r["winrate"] - bases[i]["winrate"], r["turns_mean"] - bases[i]["turns_mean"],
				r["hp_lost_mean"] - bases[i]["hp_lost_mean"]]
		print(row)


func _report_pets() -> void:
	var variants: Array = []
	for id in PetPool.all_ids():
		variants.append([PetPool.get_pet(id).display_name, {"pet": id}, "", &""])
	_contribution_table("COMPANIONS (a card every turn from its own deck)", variants)
	print("  Passion trajectory is unchanged by design: no pet card pushes Passion.")


## Every reward-pool relic, then the six forgotten relics in both states: the dormant form as
## rolled, and the woken form as a run that reached a record site.
func _report_relics() -> void:
	var variants: Array = []
	for r in RelicPool._build_pool():
		if r.is_dormant():
			continue
		variants.append([r.relic_name, {}, r.relic_name, &""])
	_contribution_table("RELICS (reward pool, the forgotten relics' dormant forms apart)", variants)
	var forgotten: Array = []
	for name in RelicPool.dormant_names():
		var dormant := RelicPool.get_relic_by_name(name)
		forgotten.append(["dormant: " + name, {}, name, &""])
		forgotten.append(["woken:   " + String(dormant.wakes_into), {}, String(dormant.wakes_into), &""])
	_contribution_table("FORGOTTEN RELICS (dormant as rolled, woken as a record site leaves them)",
		forgotten)


func _report_titles() -> void:
	var variants: Array = []
	for t in TitlePool.get_all_titles():
		variants.append([String(t.title_id), {}, "", t.title_id])
	_contribution_table("TITLES (equipped in slot one, Original tier in Camelot)", variants)


func _report_consumables() -> void:
	var variants: Array = []
	for id in ConsumablePool.all_ids():
		var c := ConsumablePool.get_consumable(id)
		if c.usable_in_combat:
			variants.append([c.display_name, {"pack": [id]}, "", &""])
	variants.append(["Blade Oil + A Champion's Favour", {"pack": [&"blade_oil", &"champions_favour"]}, "", &""])
	variants.append(["Salve + Relic-Water", {"pack": [&"traveller_salve", &"relic_water"]}, "", &""])
	_contribution_table("THE PACK (used by the policy: restoratives when hurt, boons on the opening turns)", variants)


# ============================================================
# TRIAL RUNNER + AGGREGATION
# ============================================================

func _run(deck: Array[CardData], enemy_keys: Array, start_passion: int,
		commit: bool, commit_target: int = COMMIT_TARGET, grant_excalibur := false,
		extra_relic: String = "", extra_title: StringName = &"", opts: Dictionary = {}) -> Dictionary:
	var wins := 0
	var hp_lost: Array[int] = []
	var turns_sum := 0
	var passion_sum := 0
	var ttb_sum := 0
	var ttb_count := 0
	var traj_sum: Array[float] = []
	var traj_n: Array[int] = []
	for s in _trials:
		if _aborted:
			return _aborted_result()
		var r := _simulate(deck, enemy_keys, _seed_base + s, start_passion, commit, commit_target,
			grant_excalibur, extra_relic, extra_title, opts)
		if not _cbt.within_memory_ceiling("%s trial %d" % [enemy_keys, s]):
			_aborted = true
			get_tree().quit(1)
			return _aborted_result()
		turns_sum += r["turns"]
		passion_sum += r["passion"]
		for ti in r["traj"].size():
			if traj_sum.size() <= ti:
				traj_sum.append(0.0)
				traj_n.append(0)
			traj_sum[ti] += r["traj"][ti]
			traj_n[ti] += 1
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
	var traj: Array[float] = []
	for ti in traj_sum.size():
		traj.append(traj_sum[ti] / maxf(1.0, traj_n[ti]))
	return {
		"winrate": 100.0 * wins / _trials,
		"turns_mean": float(turns_sum) / _trials,
		"hp_lost_mean": mean_lost,
		"hp_lost_p90": p90,
		"passion_mean": float(passion_sum) / _trials,
		"ttb_mean": (float(ttb_sum) / ttb_count) if ttb_count > 0 else -1.0,
		"ttb_frac": float(ttb_count) / _trials,
		"traj": traj,  # mean Passion after player turn 1, 2, ... (trials still fighting)
	}


## What _run hands back once the ceiling has tripped: every number nan, so a row printed after
## the abort cannot be mistaken for a measurement.
func _aborted_result() -> Dictionary:
	return {
		"winrate": NAN, "turns_mean": NAN, "hp_lost_mean": NAN, "hp_lost_p90": NAN,
		"passion_mean": NAN, "ttb_mean": NAN, "ttb_frac": NAN, "traj": [],
	}


## One combat against the real engine. Deterministic per seed. ttb tracks turns to
## reach the COMMITTED extreme tier (Blazing for a +target, Hollow for a -target).
func _simulate(deck: Array[CardData], enemy_keys: Array, seed_val: int,
		start_passion: int, commit: bool, commit_target: int = COMMIT_TARGET,
		grant_excalibur := false, extra_relic: String = "",
		extra_title: StringName = &"", opts: Dictionary = {}) -> Dictionary:
	# Minimal run-state reset (mirrors roster_test; avoids start_run's realm/title
	# machinery which is irrelevant to a single combat). Titles ARE cleared, because a
	# slot left set would carry a title into every later trial and quietly rewrite the
	# whole report.
	RunManager.current_character = _character
	RunManager.current_act = 1
	RunManager.relics.clear()
	RunManager.pending_act_complete = false
	RunManager.active_title_slots = [&"", &""]
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = start_passion
	RngManager.setup_run(seed_val)
	# A realistic end-of-Act-1 boss loadout: Excalibur (Sword mode, injects its 14-dmg
	# card) plus a couple of relics a player would have picked up by the boss. Titles are
	# NOT part of this loadout on purpose: pass extra_title to isolate one, which is how
	# the sword's curve is measured below. Every win rate printed without extra_title is a
	# bare-headed number.
	if grant_excalibur:
		RunManager.excalibur_mode = RunManager.ExcaliburMode.SWORD
		RunManager.add_relic(RelicPool.get_relic_by_name("Excalibur"))
		RunManager.add_relic(RelicPool.get_relic_by_name("Iron Quill"))       # +1 Strength/combat
		RunManager.add_relic(RelicPool.get_relic_by_name("Chained Folio"))  # +5 Block/turn
	# An optional extra relic by name (e.g. a liaison relic under test). Resolved via
	# get_relic_by_name so quest/liaison pools work too.
	if extra_relic != "":
		var er := RelicPool.get_relic_by_name(extra_relic)
		if er:
			RunManager.add_relic(er)
	# An optional equipped title, for single-variable isolation the same way extra_relic
	# works. The slot is set directly rather than through equip_title, which would require
	# the title to be in earned_title_ids and would drag in the max-HP recompute; no title
	# measured this way touches max HP. current_realm_id stays at its camelot default, so a
	# Camelot realm title resolves to its Original tier and escalates.
	if extra_title != &"":
		RunManager.active_title_slots[0] = extra_title
	# Extra options, a fresh pack and companion every trial so nothing carries over: more relics
	# by name (a dormant or a woken form), a companion by id, the pack by id, a second title.
	RunManager.pet_id = opts.get("pet", &"")
	RunManager.consumables.clear()
	for id in opts.get("pack", []):
		RunManager.consumables.append(ConsumablePool.get_consumable(id))
	for rn in opts.get("relics", []):
		var orel := RelicPool.get_relic_by_name(rn)
		if orel:
			RunManager.add_relic(orel)
	if opts.has("title2"):
		RunManager.active_title_slots[1] = opts["title2"]

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
	var traj: Array[int] = []
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and eng.turn_number < MAX_TURNS:
		guard += 1
		if guard > 400:
			break
		_cbt.play_turn(eng, commit, commit_target)
		if ttb < 0 and RunManager.get_passion_tier() == extreme_tier:
			ttb = eng.turn_number
		if traj.size() < TRAJ_TURNS:
			traj.append(RunManager.passion.current_value)
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		var predicted := {}
		if _cbt.verify_on:
			predicted = _cbt.verify_enemy_turn_before(eng, commit, commit_target)
		eng.end_player_turn()  # instant: resolves enemy turn + next player-turn setup
		if _cbt.verify_on:
			_cbt.verify_enemy_turn_after(eng, predicted)
		if ttb < 0 and RunManager.get_passion_tier() == extreme_tier:
			ttb = eng.turn_number

	var res := {
		"win": eng.phase == CombatEngine.Phase.BATTLE_WON,
		"turns": eng.turn_number,
		"hp": maxi(0, eng.player_stats.current_hp),
		"passion": RunManager.passion.current_value,
		"ttb": ttb,
		"traj": traj,
	}
	eng.free()
	RunManager.pet_id = &""
	RunManager.consumables.clear()
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
			"rotting": out.append(EnemyPool.rotting_knight())
			"champion": out.append(EnemyPool.champion_of_the_usurper())
			"guardian": out.append(EnemyPool.sword_guardian())
			"prophet": out.append(EnemyPool.false_prophet())
			"caedmon": out.append(EnemyPool.sir_caedmon())
			"barrow": out.append(EnemyPool.the_barrow_warden())
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


## The real Emo Hybrid starting deck: single source of truth in CharacterPool, so
## the harness always balances the deck the game actually ships.
func _fresh_deck() -> Array[CardData]:
	return CharacterPool.emo_starting_deck()


## A developed mid-act deck: the starter core plus a Water-leaning spread of pool
## cards, so the Passion-hold and zone-bonus behaviour actually exercises.
func _mid_deck() -> Array[CardData]:
	var d := _fresh_deck()
	var prim := CardPool.build_emo_primary_pool()
	var sec := CardPool.build_emo_secondary_pool()
	# Water-leaning spread post-redesign (Riverstep/Poise is gone: the pole no longer
	# borrows Physical's turf). Undertow exercises the debuff/soak lane; Maelstrom is now
	# the X-cost torrent so it also exercises the new X path; Cascade (content pass #2) is
	# the y≥3 multi a committed Water player would draft, so the boss is tuned against it.
	# Creeping Tide is the common Chilled SEED, included so the harness exercises the full
	# freeze line (Creeping Tide + the Cascade/Deep Freeze riders stacking toward a freeze).
	for name in ["Tidal Strike", "Chillbrand", "Maelstrom", "Undertow", "Deep Freeze", "Cascade",
			"Creeping Tide"]:
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


# -- effect factory --

func _dmg(v: int, hits: int = 1) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.hits = hits
	return e


# ============================================================
# REPORT FORMATTING
# ============================================================

func _bar(label: String, r: Dictionary) -> void:
	print("  %-24s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f p90 %3.0f  (of 80)" % [
		label, r["winrate"], r["turns_mean"], r["hp_lost_mean"], r["hp_lost_p90"]])


func _prophet_bar(label: String, r: Dictionary) -> void:
	var tier_txt := _tier_name(r["passion_mean"])
	var verdict := "HOLDS Blazing" if r["passion_mean"] >= COMMIT_TARGET else "gets centered"
	if is_nan(r["passion_mean"]):
		verdict = "nan"
	print("  %-20s win %5.1f%%  turns %4.1f  HP-lost avg %4.1f  end-Passion %5.1f (%s) -> %s" % [
		label, r["winrate"], r["turns_mean"], r["hp_lost_mean"],
		r["passion_mean"], tier_txt, verdict])


func _ttb_str(r: Dictionary) -> String:
	if is_nan(r["ttb_mean"]):
		return "nan"
	if r["ttb_mean"] < 0:
		return "never"
	return "%.1f (%d%% of runs reach it)" % [r["ttb_mean"], int(round(r["ttb_frac"] * 100))]


## Tier name for a mean Passion, rounded to the nearest whole point; nan after an abort.
func _tier_name(v: float) -> String:
	if is_nan(v):
		return "nan"
	return PassionState.tier_name(RunManager.get_passion_tier_for_value(int(round(v))))
