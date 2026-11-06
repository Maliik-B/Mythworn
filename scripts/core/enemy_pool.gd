class_name EnemyPool
## Camelot's enemy roster and its encounter table.
##
## This mirrors the CardPool / RelicPool / EventPool pattern: a code registry that
## builds EnemyData at request time rather than a folder of inspector-wired .tres
## assets. That matches how Slay the Spire itself does it (monsters + weighted
## encounter lists live in code) and, for a solo developer, keeps the
## content diffable and reviewable instead of hidden in the editor.
##
## Organization is realm-first so the other realms can bolt on their own sections
## the same way RealmRegistry hangs realms off one place. Camelot is all that ships
## in the demo, so it is all that lives here for now.
##
## Regular enemies, the two elites, and the Act-1 boss (Sir Caedmon) all live here.
## map_scene delegates its combat / elite / boss nodes to the get_*_encounter calls.

# The Prophet's centering effect is preloaded (rather than referenced by class_name)
# so it resolves regardless of Godot's class-registration order at load, matching how
# CardPool preloads its newer effect.
const PassionCenterEffectScript = preload("res://scripts/core/effects/passion_center_effect.gd")
const AddCardEffectScript = preload("res://scripts/core/effects/add_card_effect.gd")

# ============================================================
# ENCOUNTER TABLE (the StS-style composition puzzle)
# ============================================================

## The last composition we handed out this session. Used to damp back-to-back
## repeats without hard-banning them (StS soft-avoids recent encounters rather
## than forbidding them outright). Persisting across runs is harmless: the curated
## opener re-anchors every run's first fight anyway.
static var _last_key: String = ""

## The regular-combat encounter pool. Each entry: [key, base_weight, comp_builder].
## Weight is what an encounter is drawn at once the curated opener is past; the
## builder returns the actual enemy list at the given difficulty multiplier.
const _COMBAT_POOL := [
	["knight_conspirator", 1.0],
	["two_shades", 1.0],
	["golem_solo", 0.9],
	["golem_conspirator", 0.8],
	["knight_shade", 1.0],
	["knight_solo", 0.5], # still possible later, just deliberately lighter
	# New Sep-2026 compositions (roster thickened, #18): a bruiser body + the two new
	# debuff threats (Weak-caster Acolyte, Vulnerable-setter Squire), so back-to-back
	# fights feel distinct and the pool isn't ~6 recycled pairings.
	["manatarms_acolyte", 1.0],   # sustained damage + your offense throttled by Weak
	["knight_squire", 0.9],       # Strength snowball + Vulnerable-on-you setup
	["acolyte_shade", 0.9],       # Weak + curse pollution (annoyance/attrition)
	["manatarms_solo", 0.6],      # a lone clean bruiser
	["two_squires", 0.7],         # double glass harasser — stacking Vulnerable, low HP
	# New Oct-2026 compositions (content-furnishing pass): the three new regulars give the
	# pool a ranged-pierce threat, an escalation engine, and the first Poison body.
	["pikeman_solo", 0.6],    # the pierce teacher, lone -- block isn't the whole answer
	["pikeman_knight", 1.0],  # pierce + a bruiser body: split your defense
	["herald_knight", 0.9],       # banner escalation + bruiser (gated out of the early act)
	["rotting_solo", 0.7],        # the poison teacher, lone
	["rotting_shade", 0.9],       # poison + curse pollution — layered attrition
]


## Builds one regular-combat encounter for a map node.
## floor_num drives a gentle within-act difficulty ramp and gates the curated
## opener; difficulty_mult is the injection point for the A2 realm-config knob
## (court-vs-common-folk), defaulting to neutral so A1 works standalone.
static func get_combat_encounter(floor_num: int, difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var mult := _encounter_mult(floor_num, difficulty_mult)

	# Curated easy opener: a lone Unmarked Knight. The clean teacher, solo, so a
	# first-timer meets attack/guard/rally with nothing else going on.
	if floor_num <= 1:
		_last_key = "knight_solo"
		return _compose("knight_solo", mult)

	var key := _pick_encounter_key(floor_num)
	_last_key = key
	return _compose(key, mult)


## Overall stat multiplier for an encounter: act scaling (kept for the acts 2-3
## code paths that still exist even though the demo locks to Act 1) times the A2
## config knob, times a slow per-floor ramp within the act.
static func _encounter_mult(floor_num: int, difficulty_mult: float) -> float:
	var floor_ramp := 1.0 + floor_num * 0.02
	return _act_mult() * difficulty_mult * floor_ramp


## Act-based stat scaling, shared by every encounter type. Demo (Act 1) = 1.0.
static func _act_mult() -> float:
	return 1.0 + (RunManager.current_act - 1) * 0.35


static func _pick_encounter_key(floor_num: int) -> String:
	# Gate the attrition pairing (Golem + Conspirator) out of the early act — the
	# sim showed it costs ~half your HP on a fresh deck. It appears once decks ramp.
	var pool := []
	for entry in _COMBAT_POOL:
		if entry[0] == "golem_conspirator" and floor_num < 5:
			continue
		# The Herald's banner snowballs a paired bruiser fast; keep it out of the early act
		# where a fresh deck can't race it down, same as the Golem+Conspirator attrition gate.
		if entry[0] == "herald_knight" and floor_num < 3:
			continue
		pool.append(entry)
	var total := 0.0
	for entry in pool:
		total += _effective_weight(entry[0], entry[1])
	var roll := RngManager.enemy_rng.randf() * total
	var cumulative := 0.0
	for entry in pool:
		cumulative += _effective_weight(entry[0], entry[1])
		if roll <= cumulative:
			return entry[0]
	return pool[0][0]


## Soft anti-repeat: the composition we just used is heavily discounted (not
## banned) so consecutive-identical fights are rare but not impossible.
static func _effective_weight(key: String, base: float) -> float:
	if key == _last_key:
		return base * 0.15
	return base


static func _compose(key: String, mult: float) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	match key:
		"knight_solo":
			result.append(corrupted_knight(mult))
		"knight_conspirator":
			result.append(corrupted_knight(mult))
			result.append(court_conspirator(mult))
		"two_shades":
			result.append(realm_shade(mult))
			result.append(realm_shade(mult))
		"golem_solo":
			result.append(siege_golem(mult))
		"golem_conspirator":
			result.append(siege_golem(mult))
			result.append(court_conspirator(mult))
		"knight_shade":
			result.append(corrupted_knight(mult))
			result.append(realm_shade(mult))
		"manatarms_acolyte":
			result.append(man_at_arms(mult))
			result.append(prophets_acolyte(mult))
		"knight_squire":
			result.append(corrupted_knight(mult))
			result.append(corrupted_squire(mult))
		"acolyte_shade":
			result.append(prophets_acolyte(mult))
			result.append(realm_shade(mult))
		"manatarms_solo":
			result.append(man_at_arms(mult))
		"two_squires":
			result.append(corrupted_squire(mult))
			result.append(corrupted_squire(mult))
		"pikeman_solo":
			result.append(corrupted_pikeman(mult))
		"pikeman_knight":
			result.append(corrupted_pikeman(mult))
			result.append(corrupted_knight(mult))
		"herald_knight":
			result.append(hollow_herald(mult))
			result.append(corrupted_knight(mult))
		"rotting_solo":
			result.append(rotting_knight(mult))
		"rotting_shade":
			result.append(rotting_knight(mult))
			result.append(realm_shade(mult))
		_:
			result.append(corrupted_knight(mult))
	return result


## Shuffle-bag of the four elites, drawn without replacement so a run meets distinct elites
## before any repeat. A path holds up to MAX_ELITES_PER_PATH=3 elite nodes, so a run samples
## 3 of the 4 (which one sits out varies). Reset per run by reset_encounter_state().
static var _elite_bag: Array[String] = []


## One elite for an elite node. The four test different axes: Champion (adaptability /
## HP-band phases), False Prophet (the Passion crucible), Iron Verdict (retaliation —
## punishes chip/multi-hit, rewards big single hits), Hollow Prelate (a throughput / DPS
## check — out-damage its heal+shield). difficulty_mult is the A2 hook.
static func get_elite_encounter(difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var mult := _act_mult() * difficulty_mult
	if _elite_bag.is_empty():
		_elite_bag = ["champion", "prophet", "verdict", "prelate"]
		RngManager.shuffle(_elite_bag, RngManager.enemy_rng)
	var pick: String = _elite_bag.pop_back()
	var result: Array[EnemyData] = []
	match pick:
		"prophet":
			result.append(false_prophet(mult))
		"verdict":
			result.append(iron_verdict(mult))
		"prelate":
			result.append(the_hollow_prelate(mult))
		_:
			result.append(champion_of_the_usurper(mult))
	return result


## Clears per-run encounter memory — the elite shuffle-bag and the last-combat key — so
## a fresh run's elites don't repeat and it doesn't inherit the prior run's anti-repeat
## state. Called from RunManager.start_run.
static func reset_encounter_state() -> void:
	_elite_bag.clear()
	_last_key = ""


## The raider questline payoff fight: The Boar (a bandit war-chief the countryside calls a
## beast) and his Weald Raiders. Deliberately scaled by ACT ONLY -- no realm difficulty_mult
## -- so the quest reward fight plays the same under either pledge (it is pledge-agnostic by
## design; the pledge shapes the rest of the map, not this).
static func get_raider_band() -> Array[EnemyData]:
	var mult := _act_mult()
	var result: Array[EnemyData] = []
	result.append(the_boar(mult))
	result.append(weald_raider(mult))
	result.append(weald_raider(mult))
	return result


## The raider band, as it meets a keeper who left the village's poisoned cup for it: the same
## three fighters, each opening the fight with `dose` Poison. The dose is the Poisoned Chalice's
## own value (ConsumablePool), passed in so the number lives in one place.
static func get_raider_band_poisoned(dose: int) -> Array[EnemyData]:
	var band := get_raider_band()
	for enemy in band:
		enemy.starting_statuses.append([StatusEffects.POISON, dose])
	return band


## The Campfire treasure guardian: a solo, elite-weight fight (the barrow-warden denning on
## the cache the campers dug up and fled). A chosen, optional detour with a strong reward, so
## it's meatier than a regular but a notch under the Shattered Choir mini-boss.
static func get_barrow_warden() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	result.append(the_barrow_warden(_act_mult()))
	return result


## The Act-1 boss: Sir Caedmon. (Acts 2-3 are out of demo scope; map_scene still
## routes those to its legacy boss builders.)
static func get_boss(difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	result.append(sir_caedmon(_act_mult() * difficulty_mult))
	return result


# ============================================================
# CAMELOT REGULAR ENEMIES
# ============================================================

## Unmarked Knight (Med HP). A knight whose shield has gone plain: whatever he swore to is
## gone and the drill remains. The clean teacher: attack, guard (block + a little
## Strength), and an occasional Rally that stacks more Strength. No Passion play.
## Left alone it snowballs, which is the lesson: this is the enemy that punishes
## you for not closing fights out.
static func corrupted_knight(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Vanguard Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(7, mult))], 2.0),
		_move("Oathbound Guard", EnemyMove.IntentType.DEFEND,
			[_block(_scale(6, mult)), _self_status(StatusEffects.STRENGTH, 1)], 1.2),
		# Rally is the snowball. Cooldown keeps it from chaining Strength turn after
		# turn, so the threat ramps but stays fair.
		_move("Rally", EnemyMove.IntentType.BUFF,
			[_self_status(StatusEffects.STRENGTH, 2)], 0.7, 2),
	]
	return _enemy("Unmarked Knight", _scale(46, mult), moves)


## Court Conspirator (Low HP). The Passion threat made legible early: debuffs, plus
## a "Whisper" on a ~3-turn cadence that drains Passion. Fragile, so the puzzle is
## whether you can afford to kill the drainer before it destabilizes you.
static func court_conspirator(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Jab", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(4, mult))], 1.3),
		_move("Undermine", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 1)], 1.2),
		_move("Slander", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.VULNERABLE, 1)], 1.0),
		# The signature. High weight + cooldown 3 == fires roughly every third turn.
		# Passion drain is a flat value, not scaled by difficulty (it is identity
		# pressure, not damage). Weak rides along so ignoring it also costs tempo.
		_move("Whisper", EnemyMove.IntentType.DEBUFF,
			[_passion(-4), _status(StatusEffects.WEAK, 1)], 2.2, 3),
		# The coordinator: he's usually fought alongside a bruiser (Knight/Golem), and
		# Rally the Court hands Strength to the whole group (himself included). Makes him
		# a priority kill — leave him up and the pairing snowballs. Cooldown paces it.
		_move("Rally the Court", EnemyMove.IntentType.BUFF,
			[_ally_status(StatusEffects.STRENGTH, 1)], 1.1, 2),
	]
	return _enemy("Court Conspirator", _scale(26, mult), moves)


## Empty Harness (High HP). A full suit of plate with no one inside, still walking the
## wall. Slow and almost defenseless, but telegraphs a heavy blow on a 2-3 turn rhythm.
## A block-timing / burst-window check: race it down or eat the blow when you can spare
## the block. (The builder keeps its old name; the shipped name changed in the naming pass.)
static func siege_golem(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Gauntlet", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(8, mult))], 2.0),
		_move("Crushing Step", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(12, mult))], 1.0),
		# The telegraph. Cooldown 2 spaces the big hits out so they read as a rhythm
		# to block around rather than a random spike.
		_move("Hollow Blow", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(18, mult))], 1.6, 2),
	]
	return _enemy("Empty Harness", _scale(72, mult), moves)


## Realm Shade (Med HP). Evasive: it self-blocks (Shroud) and chips with Weak. Its
## signature Unwrite move shuffles a blank Unwritten card into your draw pile,
## polluting your tempo. Often fought in pairs, which is the demo's multi-enemy intro.
static func realm_shade(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Fade Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(6, mult))], 1.5),
		_move("Shroud", EnemyMove.IntentType.DEFEND,
			[_block(_scale(7, mult))], 1.4),
		_move("Hex", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 1)], 1.0),
		# The signature: shuffle a blank Unwritten card into the draw pile. Cooldown keeps
		# a pair of Shades from burying you in blanks.
		_move("Unwrite", EnemyMove.IntentType.DEBUFF,
			[_add_curse()], 1.1, 2),
	]
	return _enemy("Realm Shade", _scale(34, mult), moves)


## Man-at-Arms (Med HP). A plain, honest bruiser — steady sustained damage, an
## occasional shield-up, and a telegraphed overhead on a 2-turn rhythm. No status
## gimmick: he's the clean new hallway BODY that pairs with the debuff/support enemies
## for fresh compositions (added Sep 2026 to thicken the thin roster, #18). The damage
## race — block his rhythm or out-pace him.
## The same man twice in one fight, whole and hollow: the shipped Man-at-Arms, same numbers and same
## sheet, one with the colour gone. Not in any encounter table, so no seed moves.
static func whole_and_hollow(mult := 1.0) -> Array[EnemyData]:
	var whole := man_at_arms(mult)
	whole.sprite_set = "man_at_arms_whole"
	var hollow := man_at_arms(mult)
	hollow.sprite_set = "man_at_arms_whole"
	hollow.drained = 1.0
	return [whole, hollow]


static func man_at_arms(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Halberd Swing", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(9, mult))], 2.0),
		_move("Raise Shield", EnemyMove.IntentType.DEFEND,
			[_block(_scale(8, mult))], 1.0),
		# The telegraphed heavy — the block-now beat. Cooldown paces it as a rhythm.
		_move("Overhead Chop", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(14, mult))], 1.4, 2),
	]
	return _enemy("Man-at-Arms", _scale(44, mult), moves)


## Masterless Squire (Low HP). A squire whose knight is gone, reckless because no one is
## holding him to anything. A fast, fragile harasser whose signature Expose Weakness
## puts VULNERABLE on the PLAYER — so his own follow-ups (and any bruiser he's paired
## with) hit much harder. The priority-kill puzzle made about damage instead of Passion:
## drop him before the Vulnerable stacks turn a partner's hit into a spike (added Sep 2026,
## #18). Glass — a couple of good hits end him, so the tension is whether you can spare them.
static func corrupted_squire(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Harry", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(5, mult))], 1.6),
		# Sets Vulnerable on YOU. Cooldown so it can't chain you into a permanent 1.5x.
		_move("Expose Weakness", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.VULNERABLE, 1)], 1.4, 2),
		# The payoff hit — bigger, and nastier if you let the Vulnerable land first.
		_move("Reckless Charge", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(11, mult))], 1.1, 2),
	]
	return _enemy("Masterless Squire", _scale(24, mult), moves)


## Prophet's Acolyte (Med HP). A low-damage cultist — one of the False Prophet's
## followers — whose signature Sap Will lays WEAK on the player, blunting your offense.
## The "your damage is throttled" threat: it rewards decks that can still push through
## (Water trades its own control, Physical leans on its raw floor), and punishes a
## fragile all-in. Chips and shields itself otherwise (added Sep 2026, #18). Ties the
## regular roster to the False Prophet elite thematically.
static func prophets_acolyte(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Censure", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(6, mult))], 1.5),
		# The signature: 2 Weak on the player, on a cooldown so your offense recovers
		# between throttles. Weak is a flat identity pressure, unscaled by difficulty.
		_move("Sap Will", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 2)], 1.3, 2),
		_move("Wane", EnemyMove.IntentType.DEFEND,
			[_block(_scale(6, mult)), _dmg(_scale(4, mult))], 1.2),
	]
	return _enemy("Prophet's Acolyte", _scale(34, mult), moves)


## Bannerless Pikeman (Low-Med HP). The company's banner is gone; he holds the line of a
## line that no longer exists. The reach-pierce threat: a heavy Pike Thrust that punches
## through part of your block, so turtling behind a wall doesn't fully answer it. Its catch
## is the recovery -- the Thrust is on a cooldown, so the turn after it commits the pikeman
## can only Brace (a weak hunker) or jab. The punish window lands AFTER the lunge: eat the
## thrust, then burst it while it recovers its guard. Fragile, so that window usually closes
## the fight.
static func corrupted_pikeman(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# The signature: heavy + partially block-piercing. Cooldown 2 forces the recovery
		# rhythm, so it can't chain thrusts and the post-lunge punish window is reliable.
		_move("Pike Thrust", EnemyMove.IntentType.ATTACK,
			[_dmg_pierce(_scale(11, mult), 5)], 2.2, 2),
		# The recovery / punish window -- it levels the pike and braces, barely a threat.
		_move("Brace", EnemyMove.IntentType.DEFEND,
			[_block(_scale(5, mult))], 1.4),
		# A weak jab so a recovery turn isn't completely free for you.
		_move("Jab", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(5, mult))], 0.8),
	]
	return _enemy("Bannerless Pikeman", _scale(32, mult), moves)


## Hollow Herald (Low HP). The escalation engine: it raises a blank standard (nothing on
## it, and they rally to it anyway) that hands
## Strength to the WHOLE group every turn it stands, so a paired bruiser's damage climbs the
## longer the Herald lives. That makes it the priority kill — unlike the Court Conspirator's
## occasional one-shot rally, the Herald's banner compounds each turn. Fragile on its own;
## the threat is entirely what it does to its companions, so drop it first.
static func hollow_herald(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# The banner: +1 Strength to every living enemy (self included) each turn. High
		# weight + no cooldown so it fires most turns and the group's damage snowballs.
		_move("Blank Standard", EnemyMove.IntentType.BUFF,
			[_ally_status(StatusEffects.STRENGTH, 1)], 2.2),
		# A little chip so it isn't purely passive while it waves the banner.
		_move("Hollow Toll", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(5, mult))], 1.0),
	]
	return _enemy("Hollow Herald", _scale(30, mult), moves)


## Wasting Knight (Med HP). A knight the rot is still thinning, whose wound thins you: the
## attrition bruiser and the roster's only Poison source. Its wasting cut and the Waste stack
## Poison on you, so it threatens on a timer even through block. A body you can't just
## out-turtle: the longer it lives, the more the poison bleeds you, so it rewards closing the
## fight instead of grinding it. (The builder keeps its old name; the shipped name changed in
## the naming pass.)
static func rotting_knight(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Dull Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(8, mult))], 1.8),
		# Wasting cut: damage that also leaves Poison. Cooldown paces the stacking so
		# it climbs as a rhythm rather than spiking out of a fresh deck's reach.
		_move("Wasting Cut", EnemyMove.IntentType.ATTACK_DEBUFF,
			[_dmg(_scale(6, mult)), _status(StatusEffects.POISON, 3)], 1.4, 2),
		# Pure poison application: the Waste, front-loaded, bleeds hardest the turn it lands
		# (dmg = stacks, -1/turn) and bypasses block entirely. The timer you have to race.
		_move("The Waste", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.POISON, 5)], 1.1, 2),
	]
	return _enemy("Wasting Knight", _scale(44, mult), moves)


# ============================================================
# CAMELOT ELITES
# ============================================================

## Champion of the Usurper (High HP). The adaptability test: three HP-gated phases.
## Aggro while healthy, a defensive pivot in the mid band, and a desperate flurry
## when low. The HP gates make each band play differently with no per-turn scripting.
static func champion_of_the_usurper(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# Phase A (>66%): aggressive.
		_move("Usurper's Blade", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(11, mult))], 2.0, 0, 0.66, 1.0),
		_move("Challenge", EnemyMove.IntentType.BUFF,
			[_self_status(StatusEffects.STRENGTH, 2)], 1.0, 2, 0.66, 1.0),
		# Phase B (33-66%): defensive pivot.
		_move("Regroup", EnemyMove.IntentType.DEFEND,
			[_block(_scale(12, mult)), _self_status(StatusEffects.STRENGTH, 1)], 1.5, 0, 0.33, 0.66),
		_move("Measured Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(9, mult))], 1.5, 0, 0.33, 0.66),
		# Phase C (<33%): desperate.
		_move("Last Stand", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(16, mult))], 2.0, 0, 0.0, 0.33),
		_move("Reckless Fury", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(8, mult)), _self_status(StatusEffects.STRENGTH, 2)], 1.5, 0, 0.0, 0.33),
	]
	return _enemy("Champion of the Usurper", _scale(100, mult), moves)


## The False Prophet (High HP, tanky on purpose). The Passion crucible: it pulls you
## toward the dispassionate center on nearly every turn (Sermon on cooldown, Doubt
## filling the gaps), stripping whichever pole you committed to. Counterplay is your
## own Passion cards. This is the reference enemy for tuning card Passion values.
static func false_prophet(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# ESCALATING PULL (design pass Sep 2026): both preaching moves build a stack of
		# Zealotry, and PassionCenterEffect multiplies its pull by the Prophet's Zealotry —
		# so the longer it lives, the harder it strips your pole (a race to silence it),
		# rather than a flat tanky pull. Base pull also bumped (0.22/0.14 → 0.26/0.18) to bite
		# against the tighter ±60 cap. Harness-calibration target (tools/combat_harness).
		_move("False Sermon", EnemyMove.IntentType.DEBUFF,
			[_passion_center(0.26), _status(StatusEffects.WEAK, 1),
			_self_status(StatusEffects.ZEALOTRY, 1)], 2.6, 2),
		_move("Doubt", EnemyMove.IntentType.DEBUFF,
			[_passion_center(0.18), _self_status(StatusEffects.ZEALOTRY, 1)], 2.4),
		_move("Condemn", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(10, mult)), _status(StatusEffects.VULNERABLE, 1)], 1.1),
		_move("Zealot's Ward", EnemyMove.IntentType.DEFEND,
			[_block(_scale(14, mult))], 1.1),
	]
	return _enemy("The False Prophet", _scale(110, mult), moves)


## The Iron Verdict (High effective HP via block). The retaliation test: a corrupt
## executioner-knight who begins ARMED with Enraged (strikes back per hit) and escalates
## it with Retribution, while turtling behind heavy block. Chip / multi-hit decks bleed
## themselves out on him; the counterplay is fewer, bigger hits landed when his guard is
## down — so he pulls toward the Physical/secondary pole the way the Prophet pulls toward
## center. Enraged ignores block and fires per hit (see combat_engine.deal_damage), so it
## specifically punishes the multi-hit Water build. Numbers are a harness-calibration target.
static func iron_verdict(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# Filler pressure so stalling him out isn't free — you have to engage, and
		# engaging is what the retaliation punishes.
		_move("Backhand", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(9, mult))], 1.6),
		# Heavy block windows. Hitting into this wastes hits AND (fully blocked) denies
		# your own tempo; the read is to burst when the guard is down instead.
		_move("Iron Bulwark", EnemyMove.IntentType.DEFEND,
			[_block(_scale(14, mult))], 1.2),
		# Escalating retaliation: the longer the fight drags, the more each hit costs you.
		# Cooldown so it ramps as a rhythm (2 -> 3 -> 4 ...) rather than spiking.
		_move("Retribution", EnemyMove.IntentType.BUFF,
			[_self_status(StatusEffects.ENRAGED, 1)], 1.0, 2),
		# The telegraphed heavy — the strike-around / block-now moment.
		_move("Cleaving Sentence", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(17, mult))], 1.3, 2),
	]
	var e := _enemy("The Iron Verdict", _scale(92, mult), moves)
	# Armed from turn 1 so the retaliation puzzle is live before he can be rushed.
	e.starting_statuses = [[StatusEffects.ENRAGED, 2]]
	return e


## The Hollow Prelate (High HP). The throughput / DPS-check elite: a corrupted high cleric
## who mends himself and turtles behind heavy shields, so chip and slow control bleed out
## against his sustain. The counterplay is raw throughput — out-damage the heal+block or the
## fight drags forever. A fresh axis vs the other three (Champion = adaptability, False
## Prophet = Passion, Iron Verdict = retaliation); no new combat tech, just heal + block +
## a Weak so stalling him isn't free. Ties the roster's rotting faith (Acolyte / False
## Prophet) to its elite.
static func the_hollow_prelate(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Chastening Blow", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(12, mult))], 1.8),
		# The shield wall — hitting into this wastes throughput you need for the heal race.
		_move("Sanctuary", EnemyMove.IntentType.DEFEND,
			[_block(_scale(16, mult))], 1.3),
		# The sustain that makes it a DPS check. Cooldown paces it so the heal undoes a
		# round of chip rather than every hit. Self-heal does nothing at full HP, so it
		# only bites once you've wounded him — the race is whether your damage outpaces it.
		_move("Draw on the Font", EnemyMove.IntentType.BUFF,
			[_self_heal(_scale(14, mult))], 1.4, 2),
		# Throttles your offense so stalling the heal race isn't free (echoes the Acolyte's
		# Sap Will). Weak is flat identity pressure, unscaled by difficulty.
		_move("Sap Faith", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 2)], 1.0, 2),
	]
	return _enemy("The Hollow Prelate", _scale(115, mult), moves)


# ============================================================
# CAMELOT QUESTLINE — THE RAIDERS (beast/bandit payoff fight)
# ============================================================

## The Boar (High HP, the anchor). A bandit war-chief the countryside nicknamed for the way
## he fights: he gores, he charges, and he will not go down. Gore is the telegraphed beast-
## charge to block around; Blood-Howl hands Strength to his whole pack, which makes HIM the
## priority kill -- leave him up and the raiders' chip turns into real damage.
static func the_boar(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Trample", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(9, mult))], 1.8),
		# The beast-charge telegraph. Cooldown paces it as a rhythm to guard against.
		_move("Gore", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(16, mult))], 1.4, 2),
		# Rallies the pack (self included), so ignoring him snowballs the raiders.
		_move("Blood-Howl", EnemyMove.IntentType.BUFF,
			[_ally_status(StatusEffects.STRENGTH, 1)], 1.0, 2),
	]
	return _enemy("The Boar", _scale(60, mult), moves)


## Weald Raider (Low HP, fast + fragile). A bandit out of the wild wood. Cutthroat chips;
## Hamstring lays VULNERABLE on you so the Boar's Gore (and the other raider) spike. Glass:
## a couple of hits end one, so the puzzle is whether you can spare them before the Vulnerable
## stacks line up a charge.
static func weald_raider(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Cutthroat", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(6, mult))], 1.6),
		# Sets Vulnerable on YOU. Cooldown so two raiders can't chain you into a lock.
		_move("Hamstring", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.VULNERABLE, 1)], 1.2, 2),
	]
	return _enemy("Weald Raider", _scale(22, mult), moves)


# ============================================================
# CAMELOT EVENT FIGHT — The Reliquary's chapel beast
# ============================================================

## The Shattered Choir (mini-boss). What reforms off the reliquary's walls when you refuse to
## let the memory fade: broken stained glass and relic-bone pulling together into a thing that
## moves like a beast. A chosen, optional fight (The Reliquary event) with a strong reward, so
## it's meatier than a regular. No new combat tech -- it layers a block-punishing shard torrent
## (Raining Glass), a memory-eating drain (The Fade = Passion + Weak), and a reform that mends +
## shields it (so you must out-throughput the sustain, echoing the Hollow Prelate on a smaller
## scale). The reform does nothing at full HP, so it only bites once you've chipped it.
static func the_shattered_choir(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		# The signature: a torrent of glass shards (multi-hit, so block is a partial answer).
		_move("Raining Glass", EnemyMove.IntentType.ATTACK,
			[_dmg_x(_scale(4, mult), 3)], 1.8),
		# The memory-eater: drains Passion and lays Weak. Flat identity pressure, unscaled.
		_move("The Fade", EnemyMove.IntentType.DEBUFF,
			[_passion(-5), _status(StatusEffects.WEAK, 1)], 1.3, 2),
		# Pulls itself back off the walls: mends + shields. Cooldown paces the sustain so you
		# can out-race it with throughput rather than it healing every turn.
		_move("Reform", EnemyMove.IntentType.BUFF,
			[_self_heal(_scale(8, mult)), _block(_scale(6, mult))], 1.0, 2),
	]
	return _enemy("The Shattered Choir", _scale(70, mult), moves)


# ============================================================
# CAMELOT EVENT FIGHT — The Campfire cache's barrow-warden
# ============================================================

## The Barrow-Warden (solo, elite-weight). A knight laid in an old grave-mound with his hoard,
## risen under the realm's corruption to keep it. The campers who dug for the cache woke him
## and ran, leaving their gear by the dead fire. Optional (the Campfire's "follow the map"
## reveal), with a strong reward, so he hits harder than a regular: a heavy telegraphed smash
## he guards the gold with (Hoarder's Wrath), grave-cold that saps you (Barrow Chill = Weak +
## Vulnerable, so the next smash spikes), and a steady maul between. No new combat tech.
static func the_barrow_warden(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Grave Maul", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(11, mult))], 1.8),
		# Grave-cold: Weak throttles your offense while Vulnerable sets up the heavy. Cooldown
		# so it can't chain you into a lock.
		_move("Barrow Chill", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 1), _status(StatusEffects.VULNERABLE, 1)], 1.1, 2),
		# The telegraphed heavy he guards the hoard with. Cooldown paces it as a rhythm to block.
		_move("Hoarder's Wrath", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(21, mult))], 1.3, 2),
	]
	# HP sits high enough (above a regular, under the Shattered Choir mini-boss) that the fight
	# lasts long enough for Barrow Chill -> Hoarder's Wrath to actually cycle -- otherwise a
	# burst deck ends it before the heavy lands and the "strong, earned treasure" read is lost.
	return _enemy("The Barrow-Warden", _scale(82, mult), moves)


# ============================================================
# CAMELOT QUEST FIGHT — The Beast at the Stone (the Sword in the Stone's guardian)
# ============================================================

## The guardian in the run's act scaling, for the Sword in the Stone event's fight.
static func get_sword_guardian() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	result.append(sword_guardian(_act_mult()))
	return result


## The Beast at the Stone (two bars, elite weight). A champion who went to face Caedmon,
## came back with nothing behind the eyes, and has crouched over the sword since. Phase 1
## is what his training still does on its own: a measured strike, a practiced guard, a
## drilled three-hit combo, a feint that leaves you Weak, a moment to set his feet. Phase 2
## is the same body with the fighter gone, and it runs down as his bar does: the guard is
## the first thing lost, then the combo sheds a hit per band (4x3, then 6x2, then nothing)
## while the single swing grows, until under a third of the bar all that is left is a
## reckless blow and a Breaking Blow that costs him 8 of his own HP every time he throws
## it. Brace survives in every band as a thin reflex, the one thing left in him. No
## transition lash, no Strength, no Enraged: he is not Caedmon, nothing is pushing him.
## Loses to burst less than Caedmon by design (a mid-run optional fight), and the cost of
## the fight is the hits you take reading the conversion. Harness-calibration target.
static func sword_guardian(mult := 1.0) -> EnemyData:
	var phase1: Array[EnemyMove] = [
		_move("Measured Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(9, mult))], 1.8),
		_move("Practiced Guard", EnemyMove.IntentType.DEFEND,
			[_block(_scale(10, mult))], 1.2),
		_move("Drilled Combo", EnemyMove.IntentType.ATTACK,
			[_dmg_x(_scale(4, mult), 3)], 1.5, 2),
		# The craft: a light hit that leaves you Weak for the combo behind it.
		_move("Feint", EnemyMove.IntentType.ATTACK_DEBUFF,
			[_dmg(_scale(5, mult)), _status(StatusEffects.WEAK, 1)], 1.0, 2),
		_move("Set His Feet", EnemyMove.IntentType.BUFF,
			[_self_status(StatusEffects.STRENGTH, 1)], 0.6, 3),
	]
	# Phase 2 is gated by HP band on its own bar: the conversion is read off his health.
	var phase2: Array[EnemyMove] = [
		# Above two thirds: the combo is intact, the guard is gone.
		_move("Drilled Combo", EnemyMove.IntentType.ATTACK,
			[_dmg_x(_scale(4, mult), 3)], 2.0, 1, 0.66, 1.0),
		_move("Wild Swing", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(12, mult))], 0.8, 0, 0.66, 1.0),
		_move("Grasp", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.VULNERABLE, 1)], 0.9, 2, 0.66, 1.0),
		_move("Brace", EnemyMove.IntentType.DEFEND,
			[_block(_scale(5, mult))], 0.5, 0, 0.66, 1.0),
		# The middle band: the combo has lost a hit, the swing has grown.
		_move("Unlearned Combo", EnemyMove.IntentType.ATTACK,
			[_dmg_x(_scale(6, mult), 2)], 1.6, 1, 0.33, 0.66),
		_move("Wild Swing", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(14, mult))], 1.4, 0, 0.33, 0.66),
		_move("Grasp", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.VULNERABLE, 1)], 0.7, 2, 0.33, 0.66),
		_move("Brace", EnemyMove.IntentType.DEFEND,
			[_block(_scale(5, mult))], 0.4, 0, 0.33, 0.66),
		# Under a third: no technique left. Each blow is the whole of him, and the
		# Breaking Blow costs him 8 HP of his own, flat (CombatEngine.self_damage).
		_move("Reckless Abandon", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(18, mult))], 1.8, 1, 0.0, 0.33),
		_move("Breaking Blow", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(22, mult)), _self_dmg(8)], 1.4, 2, 0.0, 0.33),
		_move("Brace", EnemyMove.IntentType.DEFEND,
			[_block(_scale(4, mult))], 0.3, 0, 0.0, 0.33),
	]
	var e := _enemy("The Beast at the Stone", _scale(44, mult), phase1)
	e.phase_hps.assign([_scale(44, mult), _scale(44, mult)])
	e.phase_movesets = [phase1, phase2]
	# No line on the transition: he has nothing to say, and the event's prose carries the
	# sound he makes. The follow-up beat (The Beast Unmade) is where words come back.
	e.phase_lines.assign(["", ""])
	return e


# ============================================================
# CAMELOT ACT-1 BOSS — Sir Caedmon, the Hollow Champion
# ============================================================

## Camelot's greatest champion, returned from the great evil as its weapon: a mirror
## for the player about to pull Excalibur. TWO SEPARATE-BAR phases (not HP-gating): you
## must fully deplete his disciplined phase before the Puppeteer compels him, at which
## point he refills to a fresh bar, drops his guard, goes reckless, and drains your
## Passion. Depleting-to-transition (rather than an HP threshold he can be burst past)
## stops the old degenerate loop where a burst deck skipped him straight into his
## self-debuffing phase-2 moves. The transition line's "who moves my hand?" tease points
## at the Act-2 Puppeteer.
static func sir_caedmon(mult := 1.0) -> EnemyData:
	# Phase 1: his own disciplined will. Rallying Blow is the telegraphed heavy; the
	# guard's stacking Strength makes it escalate if the fight drags.
	var phase1: Array[EnemyMove] = [
		_move("Vanguard Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(10, mult))], 2.0),
		_move("Oathbound Guard", EnemyMove.IntentType.DEFEND,
			[_block(_scale(12, mult)), _self_status(StatusEffects.STRENGTH, 1)], 1.3),
		_move("Rallying Blow", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(20, mult))], 1.4, 3),
	]
	# Phase 2: Compelled. Guard dropped entirely. Onslaught is multi-hit (punishes
	# block); Hollowing Gaze is the Passion-drain climax; Fervor is the soft enrage.
	var phase2: Array[EnemyMove] = [
		_move("Compelled Onslaught", EnemyMove.IntentType.ATTACK,
			[_dmg_x(_scale(6, mult), 3)], 2.0),
		_move("Hollowing Gaze", EnemyMove.IntentType.DEBUFF,
			[_passion(-6), _status(StatusEffects.WEAK, 2)], 1.6, 2),
		_move("Puppet's Fervor", EnemyMove.IntentType.BUFF,
			[_self_status(StatusEffects.STRENGTH, 3)], 1.2, 1),
	]
	# Two 72-HP bars (144 total, ~the original 140). #24 lesson (harness-driven): the old
	# fight was 2-round burst for ~no damage taken, but inflating his HP/damage just turned
	# him into a 9-turn attrition meatgrinder (~67 HP-lost at 170) that also wiped the
	# low-HP run-arrival decks — WRONG fix. The RIGHT fix is purely the guaranteed
	# transition cost below: you literally cannot reach + fell bar 2 without eating the
	# lash + Enraged retaliation, no matter how fast you burst. So his raw stats stay ~as
	# they were (a fair boss for a normal deck) and only the burst gets taxed.
	# phase-0 HP + moves seed the base fields so single-phase code paths still read sane.
	# Harness-calibration target (docs/BALANCE_SNAPSHOTS.md).
	var e := _enemy("Sir Caedmon", _scale(78, mult), phase1)
	# .assign() (not `=`) for the typed Array[int]/Array[String] exports — a raw literal
	# is an untyped Array and debug builds break on the assignment (see docs pitfalls).
	e.phase_hps.assign([_scale(78, mult), _scale(78, mult)])
	e.phase_movesets = [phase1, phase2]
	e.phase_lines.assign(["",
		"No... please, not again. I'll do whatever you ask. Just... don't make me..."])
	# Phase-2 anti-burst (#24): the compulsion seizes him. On transition he deals an
	# unavoidable LASH, jumps in Strength, AND gains Enraged. All three are pace-
	# independent, so reaching + felling his second bar costs HP no matter how fast you
	# burst. Enraged (per-hit retaliation) is now the RIGHT tool, not the wrong one: the
	# redesigned Water pole wins through multi-hit torrents (Maelstrom / Riptide / Ripple /
	# Overflow), so per-hit retaliation punishes exactly the burst that used to trivialize
	# him — thematically, the puppet flailing at everything within reach.
	# Lash 16→18 (content pass #3): the recenter lever alongside Onslaught 7×3→6×3. The
	# Onslaught softening alone overshot (harness 76%→86%); this pace-independent +2 trims
	# it back to the ~82% target midpoint without touching the per-turn phase-2 numbers.
	e.phase_enter_damage.assign([0, _scale(18, mult)])
	e.phase_enter_self_strength.assign([0, 2])
	e.phase_enter_enraged.assign([0, 1])
	# Death beat: in death the compulsion finally lets go, the "…free" moment that closes
	# his arc (phase 2 begged "don't make me…"). A light tease of the Act-2 Puppeteer ("who
	# held the strings", "it will reach for another").
	# Ellipses, to match his prose voice (playtest #23).
	e.death_line = "...oh. It's quiet. Find who held the strings, keeper. It will reach for another. ...thank you."
	return e


# ============================================================
# BUILDERS / EFFECT FACTORIES
# ============================================================

## Scales a base stat by the encounter multiplier and rounds to a whole number.
## roundi keeps low values from being floored away when the multiplier is > 1.
static func _scale(base: int, mult: float) -> int:
	return roundi(base * mult)


static func _enemy(enemy_name: String, hp: int, moves: Array[EnemyMove]) -> EnemyData:
	var e := EnemyData.new()
	e.enemy_name = enemy_name
	e.max_health = hp
	e.moves.assign(moves)
	return e


static func _move(move_name: String, intent: EnemyMove.IntentType,
		effects: Array, weight: float, cooldown: int = 0,
		min_hp: float = 0.0, max_hp: float = 1.0) -> EnemyMove:
	var m := EnemyMove.new()
	m.move_name = move_name
	m.intent_type = intent
	m.effects.assign(effects)
	m.weight = weight
	m.cooldown = cooldown
	m.min_hp_percent = min_hp
	m.max_hp_percent = max_hp
	return m


static func _dmg(v: int) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	return e


## Multi-hit attack (one intent, N hits, each checked against block separately).
static func _dmg_x(v: int, hits: int) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.hits = hits
	return e


## Piercing attack: `pierce` of the hit bypasses the player's block (the Corrupted
## Pikeman's thrust). The rest soaks block normally.
static func _dmg_pierce(v: int, pierce: int) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.pierce = pierce
	return e


## A flat HP cost the enemy pays for its own move (the Beast at the Stone's Breaking
## Blow). apply_to_source lands the hit on the mover; the engine skips modifiers and block.
static func _self_dmg(v: int) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.apply_to_source = true
	return e


## Enemy self-heal (the Hollow Prelate's sustain). apply_to_source routes the heal to
## the combatant performing the move instead of the player.
static func _self_heal(v: int) -> HealEffect:
	var e := HealEffect.new()
	e.value = v
	e.apply_to_source = true
	return e


static func _block(v: int) -> BlockEffect:
	var e := BlockEffect.new()
	e.value = v
	return e


static func _status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e


static func _self_status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	e.apply_to_source = true
	return e


## Buffs every living enemy (self + allies) — support moves like the Conspirator's rally.
static func _ally_status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	e.apply_to_allies = true
	return e


static func _passion(v: int) -> PassionEffect:
	var e := PassionEffect.new()
	e.value = v
	return e


## Multiplicative pull toward 0 by `strength` (0..1), the Prophet's tool. Exact
## values are a harness-calibration target.
static func _passion_center(strength: float) -> Resource:
	var e = PassionCenterEffectScript.new()
	e.strength = strength
	return e


## A blank, unplayable Unwritten card: the Realm Shade's deck pollution. It just
## clogs a hand slot for the rest of the combat (per-combat only; never persists).
## (The helper keeps its old name; the card's shipped name changed in the naming pass.)
static func _corruption_curse() -> CardData:
	var c := CardData.new()
	c.card_name = "Unwritten"
	c.card_type = CardData.CardType.SKILL
	c.rarity = CardData.CardRarity.COMMON
	c.energy_cost = 0
	c.unplayable = true
	c.personality = CardData.PersonalityType.NEGATIVE
	c.target_type = CardData.TargetType.NONE
	c.description = "Unplayable. Nothing is written on it. There was something, once."
	return c


## AddCardEffect that shuffles a fresh Unwritten card into the player's draw pile.
static func _add_curse() -> Resource:
	var e = AddCardEffectScript.new()
	e.card_to_add = _corruption_curse()
	return e
