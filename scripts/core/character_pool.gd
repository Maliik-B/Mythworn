class_name CharacterPool
## Single source of truth for the playable characters and their starting decks.
## The game (character select), the standalone map test, and the balance harnesses
## all build the character from HERE so the starting deck can never drift between
## what ships, what's tested, and what a dev sees when poking the map scene.
## Mirrors the CardPool / RelicPool / EnemyPool static-registry pattern.


static func build_emo_hybrid() -> CharacterData:
	var c := CharacterData.new()
	c.character_name = "Emo Hybrid Caster"
	c.max_health = 80
	c.passion_volatility = 1.0
	c.passion_thresholds.assign([50, 18, -18, -50])
	c.primary_personality = "Water"
	c.secondary_personality = "Physical"
	c.starting_deck.assign(emo_starting_deck())
	c.primary_cards = CardPool.build_emo_primary_pool()
	c.secondary_cards = CardPool.build_emo_secondary_pool()
	return c


## Pole-defined starting deck (8 cards), fresh instances each call. A neutral
## backbone that never moves Passion, plus a couple of cards down EACH pole with a
## distinct playstyle, so from turn 1 the player can commit to Water (swing toward
## Blazing) or Physical (settle toward Hollow). See GAME_DESIGN — "Starting decks
## path both poles."
static func emo_starting_deck() -> Array[CardData]:
	var deck: Array[CardData] = []

	# Neutral backbone — safe filler, no Passion shift.
	for i in 2:
		deck.append(_card("Strike", 1, CardData.CardType.ATTACK,
			CardData.TargetType.SINGLE_ENEMY, [_dmg(6)]))
	for i in 2:
		deck.append(_card("Defend", 1, CardData.CardType.SKILL,
			CardData.TargetType.SELF, [_blk(5)]))

	# Water (Primary) — swingy offense; each play ramps Passion toward Blazing.
	var outpouring := _card("Outpouring", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(9), _pas(3)])
	outpouring.personality = CardData.PersonalityType.PRIMARY
	outpouring.flavor_text = "He lets it pour out of him. For a moment, the ache goes with it."
	deck.append(outpouring)

	var riptide := _card("Riptide", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(4, 2), _pas(3)])
	riptide.personality = CardData.PersonalityType.PRIMARY
	riptide.flavor_text = "It pulls once, then drags back for a second."
	deck.append(riptide)

	# Physical (Secondary) — steady block/damage; each play settles toward Hollow.
	var measured := _card("Measured Blow", 1, CardData.CardType.ATTACK,
		CardData.TargetType.SINGLE_ENEMY, [_dmg(8), _pas(-3)])
	measured.personality = CardData.PersonalityType.SECONDARY
	measured.flavor_text = "No flourish. He just makes it land."
	deck.append(measured)

	var guard := _card("Guard", 1, CardData.CardType.SKILL,
		CardData.TargetType.SELF, [_blk(8), _pas(-3)])
	guard.personality = CardData.PersonalityType.SECONDARY
	guard.flavor_text = "Feet set, weight low. Let it come."
	deck.append(guard)

	return deck


## The Water starter card names — used by tooling that needs to strip the Primary
## starters to model a committed Physical build, so it stays in sync with the deck.
static func emo_water_starters() -> PackedStringArray:
	return PackedStringArray(["Outpouring", "Riptide"])


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
