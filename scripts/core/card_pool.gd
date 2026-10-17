class_name CardPool
## Generates reward card options. Returns random cards filtered by rarity weights.
## Supports tier-based reward splits: passion tier determines how many primary,
## secondary, and generic cards are offered.

# Preloaded so the new effect resolves even before Godot finishes scanning
# class_name registrations. Other effects use class_name directly because
# they've been in the project long enough for the global class cache to know them.
const ExhaustToHandEffectScript = preload("res://scripts/core/effects/exhaust_to_hand_effect.gd")


## Tier-based reward split: [primary_count, secondary_count, generic_count]
## Blazing 2P+1G, Inspired 1P+2G, Steady 3G, Wavering 1S+2G, Hollow 2S+1G
static func _get_tier_split(tier: int) -> Array[int]:
	match tier:
		PassionState.Tier.BLAZING:
			return [2, 0, 1]
		PassionState.Tier.INSPIRED:
			return [1, 0, 2]
		PassionState.Tier.STEADY:
			return [0, 0, 3]
		PassionState.Tier.WAVERING:
			return [0, 1, 2]
		PassionState.Tier.HOLLOW:
			return [0, 2, 1]
	return [0, 0, 3]


static func get_reward_choices(rng: RandomNumberGenerator, count: int = 3) -> Array[CardData]:
	var character = RunManager.current_character
	var tier = RunManager.get_passion_tier()

	# If character has personality pools, use tier-based split
	if character and (character.primary_cards.size() > 0 or character.secondary_cards.size() > 0):
		return _get_tier_reward_choices(rng, character, tier, count)

	# Fallback: all generic (original behavior)
	return _pick_from_pool(_build_generic_pool(), rng, count)


## School-biased reward (the Forgotten Library's tomes): draws the offered cards straight from
## the current character's PRIMARY or SECONDARY pool so a chosen tome themes the pick. Falls back
## to the normal mixed reward if the requested pool is empty.
static func get_school_reward_choices(rng: RandomNumberGenerator,
		school: CardData.PersonalityType, count: int = 3) -> Array[CardData]:
	var character = RunManager.current_character
	var source: Array[CardData] = []
	if character and school == CardData.PersonalityType.PRIMARY:
		source = character.primary_cards
	elif character and school == CardData.PersonalityType.SECONDARY:
		source = character.secondary_cards
	if source.is_empty():
		return get_reward_choices(rng, count)
	return _pick_from_pool(_build_character_pool(source), rng, count)


## Boss card reward: a real payoff for the act boss, not three commons. Guarantees at
## least one RARE and fills the rest with uncommon-or-better (a strong lean toward
## rare). Draws from the whole card space available to the current character (both
## personality pools + generics) so the offer isn't tier-gated at the climax.
static func get_boss_reward_choices(rng: RandomNumberGenerator, count: int = 3) -> Array[CardData]:
	var pool := _build_boss_pool()
	var picked: Array[CardData] = []

	# 1) A guaranteed rare — the headline reward.
	_pick_of_rarity(pool, picked, CardData.CardRarity.RARE, rng)

	# 2) The rest: uncommon-or-better, leaning rare. Fall back gracefully if a rarity
	#    is exhausted so a thin pool never returns fewer than `count`.
	while picked.size() < count:
		var want := CardData.CardRarity.RARE if rng.randf() < 0.45 else CardData.CardRarity.UNCOMMON
		if _pick_of_rarity(pool, picked, want, rng):
			continue
		if _pick_of_rarity(pool, picked, CardData.CardRarity.UNCOMMON, rng):
			continue
		if _pick_of_rarity(pool, picked, CardData.CardRarity.RARE, rng):
			continue
		if not _pick_any(pool, picked, rng):
			break  # pool fully exhausted
	return picked


## Union of the current character's card space (both personality pools + generics),
## as fresh duplicates. Used for boss rewards, which aren't tier-split.
static func _build_boss_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	var character = RunManager.current_character
	if character:
		for c in character.primary_cards:
			pool.append(c.duplicate_card())
		for c in character.secondary_cards:
			pool.append(c.duplicate_card())
	pool.append_array(_build_generic_pool())
	return pool


## Appends one random card of the given rarity that isn't already picked (by name).
## Returns false if none is available.
static func _pick_of_rarity(pool: Array[CardData], picked: Array[CardData],
		rarity: CardData.CardRarity, rng: RandomNumberGenerator) -> bool:
	var names := _picked_names(picked)
	var candidates: Array[CardData] = []
	for c in pool:
		if c.rarity == rarity and c.card_name not in names:
			candidates.append(c)
	if candidates.is_empty():
		return false
	picked.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return true


## Appends any not-yet-picked card. Returns false if the pool is exhausted.
static func _pick_any(pool: Array[CardData], picked: Array[CardData],
		rng: RandomNumberGenerator) -> bool:
	var names := _picked_names(picked)
	var candidates: Array[CardData] = []
	for c in pool:
		if c.card_name not in names:
			candidates.append(c)
	if candidates.is_empty():
		return false
	picked.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	return true


static func _picked_names(picked: Array[CardData]) -> PackedStringArray:
	var names: PackedStringArray = []
	for c in picked:
		names.append(c.card_name)
	return names


static func _get_tier_reward_choices(rng: RandomNumberGenerator,
		character: CharacterData, tier: int, _count: int) -> Array[CardData]:
	var split = _get_tier_split(tier)
	var primary_needed: int = split[0]
	var secondary_needed: int = split[1]
	var generic_needed: int = split[2]

	var picked: Array[CardData] = []

	# Pick from primary pool
	if primary_needed > 0 and character.primary_cards.size() > 0:
		var primary_pool = _build_character_pool(character.primary_cards)
		var primary_picks = _pick_from_pool(primary_pool, rng, primary_needed)
		picked.append_array(primary_picks)
		generic_needed += primary_needed - primary_picks.size()

	# Pick from secondary pool
	if secondary_needed > 0 and character.secondary_cards.size() > 0:
		var secondary_pool = _build_character_pool(character.secondary_cards)
		var secondary_picks = _pick_from_pool(secondary_pool, rng, secondary_needed)
		picked.append_array(secondary_picks)
		generic_needed += secondary_needed - secondary_picks.size()

	# Fill remaining with generic
	if generic_needed > 0:
		var generic_pool = _build_generic_pool()
		# Exclude already picked names
		var picked_names: PackedStringArray = []
		for card in picked:
			picked_names.append(card.card_name)
		var filtered: Array[CardData] = []
		for card in generic_pool:
			if card.card_name not in picked_names:
				filtered.append(card)
		var generic_picks = _pick_from_pool(filtered, rng, generic_needed)
		picked.append_array(generic_picks)

	return picked


## Picks unique cards from a pool with rarity weighting.
static func _pick_from_pool(pool: Array[CardData], rng: RandomNumberGenerator,
		count: int) -> Array[CardData]:
	pool.shuffle()

	var picked: Array[CardData] = []
	var rarity = _roll_rarity(rng)
	for card in pool:
		if picked.size() >= count:
			break
		if card.rarity == rarity or picked.size() < count - (pool.size() - pool.find(card)):
			var dupe = false
			for p in picked:
				if p.card_name == card.card_name:
					dupe = true
					break
			if not dupe:
				picked.append(card)
				rarity = _roll_rarity(rng)

	# Fallback: just grab unique cards if weighting didn't fill
	if picked.size() < count:
		for card in pool:
			if picked.size() >= count:
				break
			var dupe = false
			for p in picked:
				if p.card_name == card.card_name:
					dupe = true
					break
			if not dupe:
				picked.append(card)

	return picked


static func _roll_rarity(rng: RandomNumberGenerator) -> CardData.CardRarity:
	# Base weights: common 0.6, uncommon 0.3, rare 0.1. The realm's reward_rarity_mult
	# (A2: Court biases loot up, folk down) scales the two non-common weights; common
	# soaks the remainder. Neutral (1.0) reproduces the original 0.6 / 0.9 thresholds.
	var mult := 1.0
	if RunManager and RunManager.realm_config:
		mult = RunManager.realm_config.reward_rarity_mult
	var rare_w := 0.1 * mult
	var unc_w := 0.3 * mult
	var common_w := maxf(0.0, 1.0 - rare_w - unc_w)
	var roll := rng.randf() * (common_w + unc_w + rare_w)
	if roll < common_w:
		return CardData.CardRarity.COMMON
	if roll < common_w + unc_w:
		return CardData.CardRarity.UNCOMMON
	return CardData.CardRarity.RARE


## Builds pool from character card templates (deep copies with rarity-weighted duplication).
static func _build_character_pool(templates: Array[CardData]) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in templates:
		pool.append(card.duplicate_card())
	return pool


## Generic card pool — personality-neutral cards available to all characters. NEUTRAL
## personality (never zone-modified), but each carries a small Passion LEAN toward the pole
## whose lane it fits (card-rewards "passion treatment", Sep 2026), so drafting/playing a
## generic commits you instead of pinning you to dead-center — the same rule as the starter
## backbone, just a bit heavier (±2) since these are deliberate draft picks:
##   • big single hits / aggressive chip / Vulnerable setup → −Passion (Physical's lane)
##   • AoE / multi≥3 / DoT / Weak-control / block-utility → +Passion (Water's lane)
##   • genuinely flexible cards (Bracing Blow, Second Wind) stay 0.
## CEILINGS are also trimmed ("soften center") so a committed pole out-spikes the neutral
## pool. Steady stays a valid low-variance option, not the strictly-best line. See
## docs/GAME_DESIGN.md § Zone Rewards and docs/BALANCE_SNAPSHOTS.md.
static func _build_generic_pool() -> Array[CardData]:
	var pool: Array[CardData] = []

	# -- COMMON ATTACKS --
	# Paired Strikes: buffed 3x2 -> 4x2 (#9 — it was a dead pick at 6 for 1). The
	# single-target 2-hit chip that scales cleanly with Vulnerable. (#16 card-tier: the
	# "flexible weak-1" common — see Bracing Blow for the dmg-OR-block twin.) Leans −2
	# (single-target multi is Physical's lane, and Strength rewards the 2 hits).
	pool.append(_card("Paired Strikes", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(4, 2), _passion(-2)]))

	# Sweep is the dedicated crowd tool: its Weak-to-all blunts a whole group's damage.
	# Leans +2 (AoE + Weak control is Water's lane).
	pool.append(_card("Sweep", 2, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, CardData.CardRarity.COMMON,
		[_damage(9), _status(StatusEffects.WEAK, 1), _passion(2)]))

	# -- COMMON SKILLS --
	# #16 card-intensity tiers: Bracing Blow and Shield Wall are the deliberate
	# "weak-1 / weak-2" pair. Bracing Blow is the FLEXIBLE one — 5 dmg + 5 block fits
	# either an offense or a defense turn, so it's never dead but never spikes. It stays
	# Passion-NEUTRAL (0) on purpose: it's the one true generalist, the flat-center pick.
	# Shield Wall is the COMMITTED block → leans +2 (block-utility is glass-Water's floor).
	pool.append(_card("Bracing Blow", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(5), _block(5)]))

	pool.append(_card("Shield Wall", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.COMMON,
		[_block(8), _passion(2)]))

	# -- UNCOMMON ATTACKS --
	# Havoc: the biggest neutral single hit → −2 (squarely Physical's big-single lane).
	# Trimmed 18 -> 15 ("soften center") so it doesn't out-class the committed pole rares.
	pool.append(_card("Havoc", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(15), _passion(-2)]))

	# Poisoned Fang: the generic damage-DoT. Poison is now Chilled's clear opposite — raw
	# front-loaded bleed that fades (dmg = stacks, −1/turn), not Water's freeze gauge. A big
	# 6-stack hit bites hardest the turn it lands and tapers, rewarding racing the fight. NEUTRAL
	# Passion lean (no push): the old +2 came from the dead "poison = Water" rationale; poison no
	# longer ties to a pole, so playing it doesn't move your Passion either way.
	pool.append(_card("Poisoned Fang", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(3), _status(StatusEffects.POISON, 6)]))

	# Armor Break: applies Vulnerable → −2 (Vuln is Physical's big-hit enabler now).
	pool.append(_card("Armor Break", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(8), _status(StatusEffects.VULNERABLE, 1), _passion(-2)]))

	# -- UNCOMMON SKILLS --
	pool.append(_card("Dark Pact", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		[_draw(2), _passion(-5)]))

	# Inner Fire — StS "Anger"-style passion engine: free to play, stokes Passion,
	# and drops a fresh copy of itself into the discard pile. The self-replication
	# is the cost — it clogs the deck as it ramps you toward your zone. The copy's
	# AddCardEffect points back at this prototype, so every clone re-clones on play.
	# NOTE: that back-pointer is an intentional prototype self-reference cycle. It
	# never frees (one card, app-lifetime pool) → accounts for a small bump in the
	# harness's "resources still in use at exit" count. Per-combat clones don't
	# cycle (their AddCardEffect just shares this prototype), so they free normally.
	var inner_fire = _card("Inner Fire", 0, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		[_block(5), _passion(5)])
	var inner_fire_copy = AddCardEffect.new()
	inner_fire_copy.card_to_add = inner_fire
	inner_fire_copy.to_discard = true
	inner_fire.effects.append(inner_fire_copy)
	pool.append(inner_fire)

	# Weaken: pure Weak control → +2 (Water's lane).
	pool.append(_card("Weaken", 1, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_status(StatusEffects.WEAK, 2), _passion(2)]))

	# -- RARE ATTACKS --
	# Whirlwind: the direct high-damage AoE. Leans +2 (AoE spread is Water's lane).
	pool.append(_card("Whirlwind", 2, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, CardData.CardRarity.RARE,
		[_damage(14), _passion(2)]))

	# Execute: a 3-hit finisher (y=3) → +2 (high-coefficient multi is Water's lane).
	# Trimmed 8x3 -> 7x3 (21, "soften center") so it doesn't beat the pole nukes for free.
	pool.append(_card("Execute", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		[_damage(7, 3), _passion(2)]))

	# -- RARE SKILLS --
	# Exhausts: a one-shot burst of tempo (net +2 energy, +2 cards) that leaves the
	# deck rather than recurring every reshuffle — so future 0-cost/curse cards can't
	# loop it into an engine.
	pool.append(_card("Second Wind", 0, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		[_energy(2), _draw(2)], true))

	# Phantom Guard: big block + draw → +2 (block-utility, Water's floor).
	pool.append(_card("Phantom Guard", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		[_block(16), _draw(1), _passion(2)], true))

	# -- POWERS (universal; pole-specific powers live in the character pools) --
	# StS-style: play → persistent effect in the powers slot for the rest of combat.
	# Detachment: the center-as-a-build line (cool toward Steady, gain stacking Strength).
	pool.append(_power_card("Detachment", 1, CardData.CardRarity.UNCOMMON,
		Powers.DETACHMENT, "The quieter he gets, the harder he lands."))
	# Conviction: rewards holding a pole with tempo (energy at the extremes).
	pool.append(_power_card("Conviction", 1, CardData.CardRarity.UNCOMMON,
		Powers.CONVICTION, "Certainty, once found, pays for itself."))
	# Whiplash: rewards swinging the meter — cross a tier, draw a card.
	pool.append(_power_card("Whiplash", 1, CardData.CardRarity.UNCOMMON,
		Powers.WHIPLASH, "Every lurch of feeling hands him something new."))

	# School (which pole SYMBOL each card wears) follows its Passion lean, since the generic
	# pool's lane == lean: a Water-lane card leans + (→ PRIMARY / ≈), a Physical-lane card leans
	# − (→ SECONDARY / ⚔). The flat-center picks (0 lean: Bracing Blow, Second Wind, the powers)
	# stay school-less = no symbol. These cards are personality-NEUTRAL, so the symbol renders
	# FLAT (identity only, no zone glow/coin) — see combat_scene._make_resonance_sigil.
	for c in pool:
		var lean := 0
		for e in c.effects:
			if e is PassionEffect:
				lean += e.value
		if lean > 0:
			c.school = CardData.PersonalityType.PRIMARY
		elif lean < 0:
			c.school = CardData.PersonalityType.SECONDARY

	return pool


# ============================================================
# EMO HYBRID CASTER — PRIMARY (WATER) POOL
# High-risk / high-reward SWING: DoT, chill-control, evasion, X-cost torrents
# ============================================================

## Emo Hybrid's Water pool — the high-variance SWING pole (design pass Sep 2026,
## "full re-identity split"). Water is glass: it NEVER grants plain Block or Poise
## (that is the Physical pole's home now) — its survival tools are evasion (Intangible),
## control (Weak / Freeze / Vulnerable), and racing the enemy down with poison and
## scaling torrents. So committing to Water is a real choice with a real ceiling and a
## real floor, not a re-skin of the Physical toolkit. Per the affinity rubric every card
## pushes Passion + toward Blazing (the pole's payoff). Magnitudes are the combat
## harness's calibration baseline. See docs/WATER_REWORK.md, docs/GAME_DESIGN.md
## § Characters, and docs/BALANCE_SNAPSHOTS.md.
static func build_emo_primary_pool() -> Array[CardData]:
	var pool: Array[CardData] = []

	# -- COMMON --
	# The clean on-ramp attack: pure offense, no defensive rider (the Water tell — a
	# Physical attack of this size would carry Block).
	var tidal := _pcard("Tidal Strike", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		CardData.PersonalityType.PRIMARY,
		[_damage(9), _passion(4)])
	tidal.flavor_text = "The water answers before he asks. It always did."
	pool.append(tidal)

	var ripple := _pcard("Ripple", 1, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, CardData.CardRarity.COMMON,
		CardData.PersonalityType.PRIMARY,
		[_damage(5), _passion(3)])
	ripple.flavor_text = "One motion outward, and the whole room feels it."
	pool.append(ripple)

	# Creeping Tide is the Chilled SEED — the common that opens Cairn's signature freeze line.
	# Water's skill slot isn't a wall; it lays Chilled, the freeze-gauge DoT that chips a little
	# each turn and locks the enemy out once it builds. Distinct from Poison (raw ramp damage):
	# this is the control lane. Reaching the freeze wants more than one application a turn, so it
	# stacks across Creeping Tide + the Cascade/Deep Freeze riders rather than solo.
	var creeping := _pcard("Creeping Tide", 1, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		CardData.PersonalityType.PRIMARY,
		[_status(StatusEffects.CHILLED, 5), _passion(3)])
	creeping.flavor_text = "It gets into everything. You only notice once it's everywhere."
	pool.append(creeping)

	# -- UNCOMMON --
	var chillbrand := _pcard("Chillbrand", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.PRIMARY,
		[_damage(6), _status(StatusEffects.WEAK, 2), _passion(4)])
	chillbrand.flavor_text = "Cold enough to slow the blood, not stop the heart."
	pool.append(chillbrand)

	var undertow := _pcard("Undertow", 1, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.PRIMARY,
		[_status(StatusEffects.WEAK, 2), _status(StatusEffects.STRENGTH, -2), _passion(4)])
	undertow.flavor_text = "The pull is quiet. By the time they feel it, they're already tired."
	pool.append(undertow)

	# Slip the Tide (was Soulstep — no "soul" angle fits Cairn) replaces the old Riverstep
	# (which granted Poise — block-adjacent, i.e. Physical's turf). Water's defensive answer is
	# EVASION, not armor: one turn where every hit is reduced to 1, then it's gone. Exhausts, so
	# it's a one-shot panic read, not a repeatable wall — the high-variance identity in a card.
	var slip := _pcard("Slip the Tide", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.PRIMARY,
		[_status_self(StatusEffects.INTANGIBLE, 2), _passion(4)], true)
	slip.flavor_text = "For a breath I'm not quite there. The blow passes through the ache."
	pool.append(slip)

	# Cascade — Water's signature y≥3 multi-hit (content pass #2). Strikes three times, so
	# it's the natural home for the Overflow power (Blazing → an extra strike per stack) and
	# scales with per-hit reach rather than one big number. Distinct from Physical's 2-hit:
	# Water's multi is higher-count and rides Overflow, never Strength (Water has no Strength).
	# Also lays a small chunk of Chilled, so a damage turn still feeds the freeze gauge.
	var cascade := _pcard("Cascade", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.PRIMARY,
		[_damage(4, 3), _status(StatusEffects.CHILLED, 3), _passion(4)])
	cascade.flavor_text = "It falls in stages — each wave a little heavier than the last."
	pool.append(cascade)

	# -- RARE --
	# Deep Freeze is Water's control climax: skip their turn (Frozen) now + soften the turn
	# after (Weak), and lay a chunk of Chilled so the freeze-gauge is already well along when
	# the instant Frozen thaws — the chill can re-lock them. Its old Vulnerable rider was the
	# ONE Vulnerable leak on the Water pole — swapped to Weak (content pass #2) so Vulnerable is
	# exclusively Physical's enabler and the poles' debuff kits stay orthogonal (Water controls,
	# Physical exposes).
	var deep_freeze := _pcard("Deep Freeze", 2, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		CardData.PersonalityType.PRIMARY,
		[_status(StatusEffects.STUN, 1), _status(StatusEffects.WEAK, 2),
			_status(StatusEffects.CHILLED, 4), _passion(6)])
	deep_freeze.flavor_text = "For one long breath, the world stops moving. So does the enemy."
	pool.append(deep_freeze)

	# Maelstrom is now the X-cost torrent (#21): dump all your energy, strike once per
	# point. The all-in Water finisher — scales with tempo, snowballs with Vulnerable, and
	# gains an extra strike per stack of Overflow while Blazing.
	var maelstrom := _pcard("Maelstrom", 0, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		CardData.PersonalityType.PRIMARY,
		[_xdamage(5), _passion(6)])
	maelstrom.x_cost = true
	maelstrom.flavor_text = "He opens his hands and does not close them until it's over."
	pool.append(maelstrom)

	# -- POWER (Water) --
	# Overflow: the Blazing payoff for a multi-hit torrent build — while Blazing, every
	# multi-hit attack strikes an extra time.
	pool.append(_power_card("Overflow", 1, CardData.CardRarity.UNCOMMON,
		Powers.OVERFLOW, "The water doesn't stop at once. It never did.",
		CardData.PersonalityType.PRIMARY, 3))

	return pool


# ============================================================
# EMO HYBRID CASTER — SECONDARY (PHYSICAL) POOL
# The steady FLOOR: block, reliable single-hit damage, Strength
# ============================================================

## Physical pole — the low-variance FLOOR, and now the SOLE home of Block/defense and
## reliable single-hit damage (design pass Sep 2026, "full re-identity split"). It is
## deliberately ORTHOGONAL to Water: no control statuses (Weak/Vulnerable/Freeze), no
## poison, no multi-hit torrents — just armor, dependable strikes, and self-Strength.
## You are never naked and never spiky; you trade Water's ceiling for a floor. Every
## card pushes Passion − toward Hollow (its payoff tier). Magnitudes mirror the Water
## pool's scale and are the harness's calibration baseline.
static func build_emo_secondary_pool() -> Array[CardData]:
	var pool: Array[CardData] = []

	# -- COMMON --
	pool.append(_pcard("Power Slash", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		CardData.PersonalityType.SECONDARY,
		[_damage(7), _block(3), _passion(-3)]))

	pool.append(_pcard("Brace", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.COMMON,
		CardData.PersonalityType.SECONDARY,
		[_block(9), _passion(-3)]))

	pool.append(_pcard("Quick Jab", 0, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		CardData.PersonalityType.SECONDARY,
		[_damage(4), _passion(-3)]))

	# -- UNCOMMON --
	# Rampage is now a single reliable heavy (was a 7x2 multi-hit — multi-hit is Water's
	# torrent identity now). Physical's mid-cost attack is just a dependable big number.
	var rampage := _pcard("Rampage", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.SECONDARY,
		[_damage(14), _passion(-4)])
	rampage.flavor_text = "No trick to it. He winds up, and it lands where he means it to."
	pool.append(rampage)

	pool.append(_pcard("Iron Curtain", 2, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.SECONDARY,
		[_block(16), _passion(-4)]))

	pool.append(_pcard("Riposte", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.SECONDARY,
		[_block(6), _status_self(StatusEffects.STRENGTH, 1), _passion(-3)]))

	# Twin Strike — Physical's Strength-riding 2-hit (content pass #2). Two hits means every
	# stack of Strength is counted TWICE, so the pole's Strength ramp (Whetstone / Riposte /
	# the starter's Tempered Strike) pays off harder here than on a single big hit. This is
	# the deliberate ORTHOGONAL counterpart to Water's Cascade: Physical's multi is low-count
	# and rides Strength; Water's is high-count and rides Overflow.
	var twin := _pcard("Twin Strike", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.SECONDARY,
		[_damage(6, 2), _passion(-3)])
	twin.flavor_text = "First opens the wound. The next deepens it."
	pool.append(twin)

	# Whetstone — the Physical pool's dedicated Strength engine (content pass #2). Before this
	# pass only Riposte built Strength in the pool; the pole needed a clean source so "big
	# singles + a 2-hit that RIDES Strength" actually has Strength to ride. Persists for the
	# combat (Strength doesn't decay), so it's the setup that makes Twin Strike and the heavy
	# singles snowball over a fight — the Physical ramp fantasy.
	var whetstone := _pcard("Whetstone", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.SECONDARY,
		[_status_self(StatusEffects.STRENGTH, 2), _passion(-3)])
	whetstone.flavor_text = "He works the edge back into it, slow and certain, before it's needed."
	pool.append(whetstone)

	# -- RARE --
	pool.append(_pcard("Devastating Blow", 3, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		CardData.PersonalityType.SECONDARY,
		[_damage(28), _passion(-5)]))

	pool.append(_pcard("Bulwark", 2, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		CardData.PersonalityType.SECONDARY,
		[_block(20), _draw(1), _passion(-4)]))

	# -- POWER (Physical) --
	# Grounded: the Hollow payoff for a defensive wall build — while Hollow, gain block
	# at the start of each turn.
	pool.append(_power_card("Grounded", 1, CardData.CardRarity.UNCOMMON,
		Powers.GROUNDED, "He plants himself where the blow will fall, and waits.",
		CardData.PersonalityType.SECONDARY, -3))

	return pool


# -- Factory helpers --

## POWER card factory: a SELF card that grants a persistent power. `pers` groups it
## with a pole (Overflow=Water, Grounded=Physical); leave NEUTRAL for universal powers
## (Detachment, Conviction, Whiplash). Pole powers also carry a `passion` push toward
## the tier where they pay off, so playing one commits you in its direction.
static func _power_card(card_name: String, cost: int, rarity: CardData.CardRarity,
		power: PowerData, flavor: String = "",
		pers: CardData.PersonalityType = CardData.PersonalityType.NEUTRAL,
		passion: int = 0) -> CardData:
	var c := _card(card_name, cost, CardData.CardType.POWER,
		CardData.TargetType.SELF, rarity, [])
	var gain := GainPowerEffect.new()
	gain.power = power
	c.effects.append(gain)
	if passion != 0:
		c.effects.append(_passion(passion))
	c.personality = pers
	c.flavor_text = flavor
	return c


static func _card(card_name: String, cost: int, type: CardData.CardType,
		target: CardData.TargetType, rarity: CardData.CardRarity,
		card_effects: Array, exhaust: bool = false) -> CardData:
	var c = CardData.new()
	c.card_name = card_name
	c.energy_cost = cost
	c.card_type = type
	c.target_type = target
	c.rarity = rarity
	c.exhaust = exhaust
	for e in card_effects:
		c.effects.append(e)
	return c


## Card factory with personality type.
static func _pcard(card_name: String, cost: int, type: CardData.CardType,
		target: CardData.TargetType, rarity: CardData.CardRarity,
		pers: CardData.PersonalityType,
		card_effects: Array, exhaust: bool = false) -> CardData:
	var c = _card(card_name, cost, type, target, rarity, card_effects, exhaust)
	c.personality = pers
	return c


static func _damage(amount: int, hit_count: int = 1) -> DamageEffect:
	var e = DamageEffect.new()
	e.value = amount
	e.hits = hit_count
	return e


## X-scaled damage: strikes once per energy the X-cost card spent. Pair with
## CardData.x_cost on the owning card (see Maelstrom).
static func _xdamage(amount: int) -> DamageEffect:
	var e = DamageEffect.new()
	e.value = amount
	e.x_scaled = true
	return e


static func _block(amount: int) -> BlockEffect:
	var e = BlockEffect.new()
	e.value = amount
	return e


static func _status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e = StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e


static func _status_self(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e = StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	e.apply_to_source = true
	return e


static func _draw(amount: int) -> DrawEffect:
	var e = DrawEffect.new()
	e.value = amount
	return e


static func _passion(amount: int) -> PassionEffect:
	var e = PassionEffect.new()
	e.value = amount
	return e


static func _energy(amount: int) -> EnergyEffect:
	var e = EnergyEffect.new()
	e.value = amount
	return e


static func _recall(amount: int) -> CardEffect:
	var e = ExhaustToHandEffectScript.new()
	e.value = amount
	return e


## Self-heal effect (routes through the combat engine so the heal shows live and isn't
## clobbered by the end-of-combat HP sync). apply_to_source = the card's player.
static func _heal(amount: int) -> HealEffect:
	var e = HealEffect.new()
	e.value = amount
	e.apply_to_source = true
	return e


## Passion-scaled attack with an optional on-kill energy refund (the memory burst).
static func _mdamage(amount: int, passion_divisor: int, kill_energy: int = 0) -> DamageEffect:
	var e = DamageEffect.new()
	e.value = amount
	e.passion_bonus_divisor = passion_divisor
	e.energy_on_kill = kill_energy
	return e


## Draw that forgets itself: draws `amount`, dropping by `decay` each play across the run.
static func _ddraw(amount: int, decay: int) -> DrawEffect:
	var e = DrawEffect.new()
	e.value = amount
	e.decay_per_play = decay
	return e


# ============================================================
# MEMORY ("REMEMBRANCE") CARDS — Emo Hybrid (Cairn)
# A league of their own: character-specific, overloaded, and sourced ONLY from memory
# events, boss fights, and a shop relic (never the normal reward pool). Each answers an
# enemy's intent a different way -- survive it, strike through it, or out-resource it.
# Flavor is first person (the character's own voice): a keeper who lost his home and gave
# himself a name.
# ============================================================

## Returns a fresh instance of a memory card by id (events/bosses grant a specific one).
## Unknown id returns null. New memory cards register here.
static func get_memory_card(id: StringName) -> CardData:
	match id:
		&"house_that_was":
			return _memory_house_that_was()
		&"everything_i_carried_out":
			return _memory_everything_carried_out()
		&"name_i_gave_myself":
			return _memory_name_i_gave_myself()
	return null


## Curse cards -- permanent, unplayable dead cards a run can pick up as a consequence (the
## higher tier of "refusals with teeth": a spurned party's parting gift). Built by id so events
## grant a specific, flavored curse. Distinct from the Realm Shade's per-combat Corruption
## (EnemyPool._corruption_curse), which never persists; these ride in the run deck for good.
static func get_curse_card(id: StringName) -> CardData:
	match id:
		&"clinging_grief":
			return _curse_clinging_grief()
	return null


## The Wandering Spirit's parting curse: you sent it off with its grief unspoken, and some of
## it stayed. An unplayable card that just crowds your hand -- the price of the cold dismissal.
static func _curse_clinging_grief() -> CardData:
	var c := CardData.new()
	c.card_name = "Clinging Grief"
	c.card_type = CardData.CardType.SKILL
	c.rarity = CardData.CardRarity.COMMON
	c.energy_cost = 0
	c.unplayable = true
	c.personality = CardData.PersonalityType.NEGATIVE
	c.target_type = CardData.TargetType.NONE
	c.description = "Unplayable. A grief that was not yours, clinging where you cannot set it down."
	c.flavor_text = "You sent it away with everything still unsaid. Some of it came with you."
	return c


## All memory cards (for the future shop relic that surfaces them, and for tests). Not
## wired into any reward roll -- the gating is by construction (nothing adds these to a pool).
static func build_memory_cards() -> Array[CardData]:
	return [
		_memory_house_that_was(),
		_memory_everything_carried_out(),
		_memory_name_i_gave_myself(),
	]


## Bypass the hit: a near-untouchable turn (block + a heal + draw + one turn of Intangible),
## then the memory is spent for the fight (Exhaust = forgetting). Always does SOMETHING, even
## if the block is redundant -- a hearth that takes you in.
static func _memory_house_that_was() -> CardData:
	var c := _pcard("The House That Was", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		CardData.PersonalityType.PRIMARY,
		[_block(15), _heal(6), _draw(2), _status_self(StatusEffects.INTANGIBLE, 1), _passion(10)],
		true)  # exhaust
	c.is_memory = true
	c.flavor_text = ("For a breath the walls are up again and the hearth is lit. I almost "
		+ "remember the room whole. For as long as it holds, I am present.")
	return c


## Strike through the hit: the whole weight I carry, set down at once -- so it scales with how
## far I've committed to either pole, hardens me (Strength), and gives tempo back on a kill.
static func _memory_everything_carried_out() -> CardData:
	var c := _pcard("Everything I Carried Out", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		CardData.PersonalityType.SECONDARY,
		[_mdamage(8, 4, 2), _status_self(StatusEffects.STRENGTH, 3), _passion(-12)])
	c.is_memory = true
	c.flavor_text = ("Everything I carried out of home, I am still carrying. Once in a while I "
		+ "set the whole of it down at once, on whoever is in front of me.")
	return c


## Out-resource the hit: free card advantage that forgets itself across the run -- it draws one
## fewer each time I lean on it, but never becomes dead (it still frees energy and steadies me).
static func _memory_name_i_gave_myself() -> CardData:
	var c := _pcard("The Name I Gave Myself", 0, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		CardData.PersonalityType.PRIMARY,
		[_ddraw(4, 1), _energy(1), _passion(8)])
	c.is_memory = true
	c.flavor_text = ("Choosing a name felt strange, especially after turning it over all through "
		+ "initiation. Nowadays, the word grants me strength.")
	return c


## The Excalibur signature card. Constructed fresh each combat by CombatEngine
## when the player holds Excalibur in Sword mode. Never enters the player's
## persistent deck and never appears in reward pools or shops — its existence
## is bound to the relic's mode toggle.
static func build_excalibur_card() -> CardData:
	var c = CardData.new()
	c.card_name = "Excalibur"
	c.energy_cost = 2
	c.card_type = CardData.CardType.ATTACK
	c.rarity = CardData.CardRarity.RARE
	c.target_type = CardData.TargetType.SINGLE_ENEMY
	c.personality = CardData.PersonalityType.NEUTRAL
	c.flavor_text = "The blade remembers older battles than yours."
	c.effects.append(_damage(14))
	return c
