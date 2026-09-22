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
]


## Builds one regular-combat encounter for a map node.
## floor_num drives a gentle within-act difficulty ramp and gates the curated
## opener; difficulty_mult is the injection point for the A2 realm-config knob
## (court-vs-common-folk), defaulting to neutral so A1 works standalone.
static func get_combat_encounter(floor_num: int, difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var mult := _encounter_mult(floor_num, difficulty_mult)

	# Curated easy opener: a lone Corrupted Knight. The clean teacher, solo, so a
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
		_:
			result.append(corrupted_knight(mult))
	return result


## Shuffle-bag of the three elites, drawn without replacement so a run meets each once
## before any repeat (a path can hold up to MAX_ELITES_PER_PATH=3 elite nodes, so a full
## bag exactly covers the worst case). Reset per run by reset_encounter_state().
static var _elite_bag: Array[String] = []


## One elite for an elite node. The three test different axes: Champion (adaptability /
## HP-band phases), False Prophet (the Passion crucible), Iron Verdict (retaliation —
## punishes chip/multi-hit, rewards big single hits). difficulty_mult is the A2 hook.
static func get_elite_encounter(difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var mult := _act_mult() * difficulty_mult
	if _elite_bag.is_empty():
		_elite_bag = ["champion", "prophet", "verdict"]
		_shuffle_bag(_elite_bag)
	var pick: String = _elite_bag.pop_back()
	var result: Array[EnemyData] = []
	match pick:
		"prophet":
			result.append(false_prophet(mult))
		"verdict":
			result.append(iron_verdict(mult))
		_:
			result.append(champion_of_the_usurper(mult))
	return result


## Deterministic Fisher-Yates using the run-seeded enemy RNG (Array.shuffle() would use
## the global RNG and break run reproducibility).
static func _shuffle_bag(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := RngManager.enemy_rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Clears per-run encounter memory — the elite shuffle-bag and the last-combat key — so
## a fresh run's elites don't repeat and it doesn't inherit the prior run's anti-repeat
## state. Called from RunManager.start_run.
static func reset_encounter_state() -> void:
	_elite_bag.clear()
	_last_key = ""


## The Act-1 boss: Sir Caedmon. (Acts 2-3 are out of demo scope; map_scene still
## routes those to its legacy boss builders.)
static func get_boss(difficulty_mult: float = 1.0) -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	result.append(sir_caedmon(_act_mult() * difficulty_mult))
	return result


# ============================================================
# CAMELOT REGULAR ENEMIES
# ============================================================

## Corrupted Knight (Med HP). The clean teacher: attack, guard (block + a little
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
	return _enemy("Corrupted Knight", _scale(46, mult), moves)


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


## Siege Golem (High HP). Slow and almost defenseless, but telegraphs a heavy Slam
## on a 2-3 turn rhythm. A block-timing / burst-window check: race it down or eat
## the Slam when you can spare the block.
static func siege_golem(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Grind", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(8, mult))], 2.0),
		_move("Crushing Step", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(12, mult))], 1.0),
		# The telegraph. Cooldown 2 spaces the big hits out so they read as a rhythm
		# to block around rather than a random spike.
		_move("Siege Slam", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(18, mult))], 1.6, 2),
	]
	return _enemy("Siege Golem", _scale(72, mult), moves)


## Realm Shade (Med HP). Evasive: it self-blocks (Shroud) and chips with Weak. Its
## signature Corrupt move shuffles a dead Corruption card into your draw pile,
## polluting your tempo. Often fought in pairs, which is the demo's multi-enemy intro.
static func realm_shade(mult := 1.0) -> EnemyData:
	var moves: Array[EnemyMove] = [
		_move("Fade Strike", EnemyMove.IntentType.ATTACK,
			[_dmg(_scale(6, mult))], 1.5),
		_move("Shroud", EnemyMove.IntentType.DEFEND,
			[_block(_scale(7, mult))], 1.4),
		_move("Hex", EnemyMove.IntentType.DEBUFF,
			[_status(StatusEffects.WEAK, 1)], 1.0),
		# The signature: shuffle a dead Corruption into the draw pile. Cooldown keeps
		# a pair of Shades from burying you in curses.
		_move("Corrupt", EnemyMove.IntentType.DEBUFF,
			[_add_curse()], 1.1, 2),
	]
	return _enemy("Realm Shade", _scale(34, mult), moves)


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
		# Pull strengths are a harness-calibration target (tools/combat_harness). Tracks
		# the card-Passion scale: when the ~10-turns-to-pole re-tune roughly halved card
		# Passion, the pull halved too (0.42/0.26 → 0.22/0.14) so the crucible dynamic
		# holds — a passive player still gets centered, a committed one can still hold
		# Blazing. The Prophet is the only user of this effect, so no HP/damage band moves.
		_move("False Sermon", EnemyMove.IntentType.DEBUFF,
			[_passion_center(0.22), _status(StatusEffects.WEAK, 1)], 2.6, 2),
		_move("Doubt", EnemyMove.IntentType.DEBUFF,
			[_passion_center(0.14)], 2.4),
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
	# Two ~70-HP bars (≈ the old 130 total, split). phase-0 HP + moves seed the base
	# fields so single-phase code paths still read something sane.
	var e := _enemy("Sir Caedmon", _scale(70, mult), phase1)
	# .assign() (not `=`) for the typed Array[int]/Array[String] exports — a raw literal
	# is an untyped Array and debug builds break on the assignment (see docs pitfalls).
	e.phase_hps.assign([_scale(70, mult), _scale(70, mult)])
	e.phase_movesets = [phase1, phase2]
	e.phase_lines.assign(["",
		"No... please, not again. I'll do whatever you ask. Just... don't make me..."])
	# Phase-2 anti-burst: the compulsion seizes him. A one-time LASH at the player + a
	# Strength jump on transition — both pace-independent, so reaching his second bar
	# costs HP no matter how fast you burst it. (Enraged/retaliation is intentionally NOT
	# used here: it fires per hit, which punishes chip decks more than burst — wrong tool.
	# The engine keeps it for future "don't chip me" enemies.) Harness-calibration target.
	e.phase_enter_damage.assign([0, _scale(12, mult)])
	e.phase_enter_self_strength.assign([0, 2])
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


## A dead, unplayable Corruption card — the Realm Shade's deck pollution. It just
## clogs a hand slot for the rest of the combat (per-combat only; never persists).
static func _corruption_curse() -> CardData:
	var c := CardData.new()
	c.card_name = "Corruption"
	c.card_type = CardData.CardType.SKILL
	c.rarity = CardData.CardRarity.COMMON
	c.energy_cost = 0
	c.unplayable = true
	c.personality = CardData.PersonalityType.NEGATIVE
	c.target_type = CardData.TargetType.NONE
	c.description = "Unplayable. A shard of the realm's rot, clogging your hand."
	return c


## AddCardEffect that shuffles a fresh Corruption into the player's draw pile.
static func _add_curse() -> Resource:
	var e = AddCardEffectScript.new()
	e.card_to_add = _corruption_curse()
	return e
