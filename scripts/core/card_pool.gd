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
	var roll = rng.randf()
	if roll < 0.6:
		return CardData.CardRarity.COMMON
	if roll < 0.9:
		return CardData.CardRarity.UNCOMMON
	return CardData.CardRarity.RARE


## Builds pool from character card templates (deep copies with rarity-weighted duplication).
static func _build_character_pool(templates: Array[CardData]) -> Array[CardData]:
	var pool: Array[CardData] = []
	for card in templates:
		pool.append(card.duplicate_card())
	return pool


## Generic card pool — personality-neutral cards available to all characters. These are
## the "Steady / generalist" draft: flexible, never zone-modified, no Passion cost. Their
## CEILINGS are deliberately trimmed (design pass Sep 2026 — "soften center") so a
## committed pole deck out-spikes the neutral pool. Staying Steady stays a valid,
## low-variance option; it is no longer the strictly-best line. See docs/GAME_DESIGN.md
## § Zone Rewards and docs/BALANCE_SNAPSHOTS.md.
static func _build_generic_pool() -> Array[CardData]:
	var pool: Array[CardData] = []

	# -- COMMON ATTACKS --
	pool.append(_card("Crushing Blow", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(13)]))

	# Paired Strikes: buffed 3x2 -> 4x2 (#9 — it was a dead pick at 6 for 1). The
	# neutral chip that fits any plan and scales cleanly with Vulnerable. (#16 card-tier:
	# this is the "flexible weak-1" common — see Bracing Blow for the dmg-OR-block twin.)
	pool.append(_card("Paired Strikes", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(4, 2)]))

	# Sweep is the dedicated crowd tool: pricier than the cheap Wide Arc starter, but
	# its Weak-to-all is a real multi-enemy advantage (blunts a whole group's damage)
	# rather than just out-damaging Wide Arc by a point. Its upgrade is the direct
	# high-damage clear that used to be Wildfire's job.
	pool.append(_card("Sweep", 2, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, CardData.CardRarity.COMMON,
		[_damage(9), _status(StatusEffects.WEAK, 1)]))

	pool.append(_card("Reckless Swing", 0, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(5)]))

	# -- COMMON SKILLS --
	# #16 card-intensity tiers: Bracing Blow and Shield Wall are the deliberate
	# "weak-1 / weak-2" pair. Bracing Blow is the FLEXIBLE one — 5 dmg + 5 block fits
	# either an offense or a defense turn, so it's never dead but never spikes. Shield
	# Wall is the COMMITTED one — pure 8 block, better for the plan it fits, worse
	# otherwise. Same rarity, different purpose: the draft has texture, not dominance.
	pool.append(_card("Bracing Blow", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		[_damage(5), _block(5)]))

	pool.append(_card("Shield Wall", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.COMMON,
		[_block(8)]))

	# Free to play: cycles itself (draw 1) for a little block, so it smooths a hand
	# without costing tempo. The draw keeps it card-neutral, not card-advantage.
	pool.append(_card("Battle Cry", 0, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.COMMON,
		[_block(3), _draw(1)]))

	# -- UNCOMMON ATTACKS --
	# Trimmed 18 -> 15 ("soften center"): an 18-for-2 neutral stat-stick out-classed the
	# pole rares and made staying Steady the default. Still a solid reliable hit, just no
	# longer the best card in the game for zero commitment.
	pool.append(_card("Havoc", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(15)]))

	pool.append(_card("Poison Fang", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(3), _status(StatusEffects.POISON, 4)]))

	pool.append(_card("Armor Break", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_damage(8), _status(StatusEffects.VULNERABLE, 1)]))

	# -- UNCOMMON SKILLS --
	# Nudged 12 -> 10 block so it isn't a strictly-better Defend-at-uncommon. Its
	# identity rider is a small -3 Passion: block/defense reads as the steadying
	# secondary (Hollow) side, so Bolster commits you toward it — the deliberate
	# tension of the passion system (off-type value has a passion cost), and the
	# clean separator from neutral Defend, which never touches Passion.
	pool.append(_card("Bolster", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		[_block(10), _passion(-3)]))

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

	pool.append(_card("Weaken", 1, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.UNCOMMON,
		[_status(StatusEffects.WEAK, 2)]))

	# -- RARE ATTACKS --
	# Whirlwind: the direct high-damage AoE, formerly "Wildfire" — same 2e/14-to-all,
	# just re-skinned off fire (a spinning strike, not flames) to fit the Water build.
	# Sweep owns the control-AoE niche (Weak); this is the raw-clear rare.
	pool.append(_card("Whirlwind", 2, CardData.CardType.ATTACK,
		CardData.TargetType.ALL_ENEMIES, CardData.CardRarity.RARE,
		[_damage(14)]))

	# Trimmed 8x3 -> 7x3 (21, "soften center"): still the neutral Vulnerable-synergy
	# finisher, but no longer a flat 24 that beats the committed pole nukes for free.
	pool.append(_card("Execute", 2, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		[_damage(7, 3)]))

	# -- RARE SKILLS --
	# Exhausts: a one-shot burst of tempo (net +2 energy, +2 cards) that leaves the
	# deck rather than recurring every reshuffle — so future 0-cost/curse cards can't
	# loop it into an engine.
	pool.append(_card("Second Wind", 0, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		[_energy(2), _draw(2)], true))

	pool.append(_card("Phantom Guard", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.RARE,
		[_block(16), _draw(1)], true))

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

	# Creeping Tide replaces the old Mistveil (a plain 9-Block card that lived on
	# Physical's turf). Water's answer to a skill slot is a damage-over-time seed, not a
	# wall: it rewards racing / stalling with control rather than turtling.
	var creeping := _pcard("Creeping Tide", 1, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.COMMON,
		CardData.PersonalityType.PRIMARY,
		[_status(StatusEffects.POISON, 4), _passion(3)])
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

	# Soulstep replaces the old Riverstep (which granted Poise — block-adjacent, i.e.
	# Physical's turf). Water's defensive answer is EVASION, not armor: one turn where
	# every hit is reduced to 1, then it's gone. Exhausts, so it's a one-shot panic read,
	# not a repeatable wall — the high-variance identity in a single card.
	var soulstep := _pcard("Soulstep", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, CardData.CardRarity.UNCOMMON,
		CardData.PersonalityType.PRIMARY,
		[_status_self(StatusEffects.INTANGIBLE, 2), _passion(4)], true)
	soulstep.flavor_text = "For a breath he isn't quite there. The blow passes through the ache."
	pool.append(soulstep)

	# -- RARE --
	var deep_freeze := _pcard("Deep Freeze", 2, CardData.CardType.SKILL,
		CardData.TargetType.SINGLE_ENEMY, CardData.CardRarity.RARE,
		CardData.PersonalityType.PRIMARY,
		[_status(StatusEffects.STUN, 1), _status(StatusEffects.VULNERABLE, 1), _passion(6)])
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
