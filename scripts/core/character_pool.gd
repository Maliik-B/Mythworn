class_name CharacterPool
## Single source of truth for the playable characters and their starting decks.
## The game (character select), the standalone map test, and the balance harnesses
## all build the character from HERE so the starting deck can never drift between
## what ships, what's tested, and what a dev sees when poking the map scene.
## Mirrors the CardPool / RelicPool / EnemyPool static-registry pattern.


static func build_emo_hybrid() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Emo Hybrid Caster"
	c.work_name = "Cairn"
	c.max_health = 80
	c.passion_volatility = 1.0
	c.passion_thresholds.assign([50, 18, -18, -50])
	c.primary_personality = "Water"
	c.secondary_personality = "Physical"
	# Innate Water attrition answer: mend when he stills an enemy (lands Weak/Frozen). The
	# glass pole's non-block sustain, auto-gated to the control build. Magnitude is the
	# harness's calibration baseline (see docs/BALANCE_SNAPSHOTS.md).
	c.control_heal = 2
	c.starting_deck.assign(emo_starting_deck())
	c.primary_cards = CardPool.build_emo_primary_pool()
	c.secondary_cards = CardPool.build_emo_secondary_pool()
	return c


## Pole-defined starting deck (11 cards), fresh instances each call. Design pass Sep 2026
## (self-scaling poles + probability-planned density): a leaned neutral backbone (4) plus
## a self-sufficient in-fight ENGINE per pole (Water 3 / Physical 4) so you can "forge your
## path" and win on one pole without splashing the other:
##   • Water (Primary) self-scales via multi-hit + control (Weak) + the +Passion climb to
##     Blazing. Glass — no block; Weak is its early defense; single hits stay MODEST.
##   • Physical (Secondary) self-scales via STRENGTH stacking (the damage buff) and OWNS
##     the big single hits + the Vulnerable enabler (Vuln ×1.5 pays off a big hit cheaply):
##     it starts under Water's flat numbers but out-scales them, and spikes off Vuln.
## The neutral backbone is LEANED (±1 Passion, opposite-pole rule) so tempo plays commit
## you instead of centering you, matched to natural usage (glass-Water leans on Defend →
## +Water; Physical attacks with Strike → −Physical). Density: 10 cards / 5-card hand fully
## cycles by turn 2, so copy counts (2 neutral, 1 per pole card) tune opening-hand odds —
## see GAME_DESIGN "Starting deck — iteration log" and docs/BALANCE_SNAPSHOTS.md.
static func emo_starting_deck() -> Array[CardData]:
	var deck: Array[CardData] = []

	# Neutral backbone — LEANED per the "a helps-both card carries an opposite-pole Passion
	# cost" rule. Personality stays NEUTRAL (no zone effect); each wears its fitting SCHOOL
	# symbol but leans toward the OTHER pole, so its pips read "away" from the symbol:
	#   • Strike (offense → Water school) leans −Passion → pips point AWAY from ≈ (toward Physical).
	#   • Defend (block → Physical school) leans +Passion → pips point AWAY from ⚔ (toward Water).
	for i in 2:
		var strike := _card("Strike", 1, CardData.CardType.ATTACK,
			CardData.TargetType.SINGLE_ENEMY, [_dmg(6), _pas(-1)])
		strike.school = CardData.PersonalityType.PRIMARY
		deck.append(strike)
	for i in 2:
		var defend := _card("Defend", 1, CardData.CardType.SKILL,
			CardData.TargetType.SELF, [_blk(5), _pas(1)])
		defend.school = CardData.PersonalityType.SECONDARY
		deck.append(defend)

	# Water (Primary) — self-scales via multi-hit × control + the +Passion climb. Its
	# single-target hit (Outpouring) is deliberately MODEST — big single hits are the
	# Physical pole's domain now; Water's ceiling is the multi-hit torrent, not the nuke.
	var outpouring := _card("Outpouring", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(7), _pas(3)])
	outpouring.personality = CardData.PersonalityType.PRIMARY
	outpouring.flavor_text = "I let it pour out of me. For a moment, the ache goes with it."
	deck.append(outpouring)

	var riptide := _card("Riptide", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(4, 2), _pas(3)])
	riptide.personality = CardData.PersonalityType.PRIMARY
	riptide.flavor_text = "It pulls once, then drags back for a second."
	deck.append(riptide)

	# Ebb — the Water control seed: chip + Weak. Weak softens the enemy's next hit, so it
	# doubles as Water's early defense (its answer to having no block) and sets up the
	# multi-hit lane.
	var ebb := _card("Ebb", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(5), _status(StatusEffects.WEAK, 1), _pas(3)])
	ebb.personality = CardData.PersonalityType.PRIMARY
	ebb.flavor_text = "The tide pulls back, and their strength goes with it."
	deck.append(ebb)

	# Physical (Secondary) — self-scales via STRENGTH stacking (the damage buff), and it
	# OWNS the big single hits: Measured Blow is the strongest single-target attack in the
	# starter, and the Vulnerable enabler below turns it into the pole's payoff swing.
	var measured := _card("Measured Blow", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(10), _pas(-3)])
	measured.personality = CardData.PersonalityType.SECONDARY
	measured.flavor_text = "No flourish. I just make it land."
	deck.append(measured)

	# Sunder — the Physical Vulnerable enabler (Vuln is Physical's setup now: a ×1.5
	# multiplier that pays off a big single hit without needing huge Strength/base). Chip +
	# Vulnerable so a same-turn Measured Blow lands at 15, or a Strength-stacked one lands
	# even harder. This is what makes the Physical core cohere from turn 1.
	var sunder := _card("Sunder", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(5), _status(StatusEffects.VULNERABLE, 1), _pas(-3)])
	sunder.personality = CardData.PersonalityType.SECONDARY
	sunder.flavor_text = "Find the seam in the plate. Everything after is easier."
	deck.append(sunder)

	# Tempered Strike — the Physical ramp seed: a modest hit + permanent Strength, so every
	# later attack (Strikes included) hits harder. It's why Physical starts under Water's
	# flat numbers but out-scales them over a fight.
	var tempered := _card("Tempered Strike", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY,
		[_dmg(5), _status_self(StatusEffects.STRENGTH, 1), _pas(-3)])
	tempered.personality = CardData.PersonalityType.SECONDARY
	tempered.flavor_text = "Each blow instructs the next."
	deck.append(tempered)

	var guard := _card("Guard", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, [_blk(8), _pas(-3)])
	guard.personality = CardData.PersonalityType.SECONDARY
	guard.flavor_text = "Feet set, weight low. Let it come."
	deck.append(guard)

	return deck


## The Water starter card names — used by tooling that needs to strip the Primary
## starters to model a committed Physical build, so it stays in sync with the deck.
static func emo_water_starters() -> PackedStringArray:
	return PackedStringArray(["Outpouring", "Riptide", "Ebb"])


# -- factory helpers --

static func _card(n: String, cost: int, type: CardData.CardType,
		target: CardData.TargetType, fx: Array) -> CardData:
	var c := CardData.new()
	c.card_name = n
	c.energy_cost = cost
	c.card_type = type
	c.target_type = target
	for e in fx:
		c.effects.append(e)
	return c


static func _dmg(v: int, hits: int = 1) -> DamageEffect:
	var e := DamageEffect.new()
	e.value = v
	e.hits = hits
	return e


static func _blk(v: int) -> BlockEffect:
	var e := BlockEffect.new()
	e.value = v
	return e


static func _pas(v: int) -> PassionEffect:
	var e := PassionEffect.new()
	e.value = v
	return e


static func _status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e


static func _status_self(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e := StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	e.apply_to_source = true
	return e
