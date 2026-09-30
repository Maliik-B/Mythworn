class_name RelicPool
## Builds and returns relic choices filtered by rarity.


## Returns the relic with the given name from either the rewards pool or the
## quest-only pool. Used by events that grant a specific named relic
## (e.g. Camelot's Sword in the Stone grants Excalibur).
static func get_relic_by_name(name: String) -> RelicData:
	for relic in _build_pool():
		if relic.relic_name == name:
			return relic
	for relic in _build_quest_pool():
		if relic.relic_name == name:
			return relic
	return null


## Quest-only relics — granted by specific narrative events, NEVER appear in
## shop wares or post-combat rewards. Excalibur is the central example: it
## comes from the Sword in the Stone node and has dual-mode behavior managed
## by RunManager + CombatEngine + map UI rather than the generic relic effect
## system.
static func _build_quest_pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []
	pool.append(_relic("Excalibur",
		"A blade that adheres to its wielder. Toggle between Sword (adds a power card to each combat) and Sight (reveals enemy intent one turn ahead) between battles.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_PICKUP,
		RelicData.RelicEffect.NONE, 0))

	# -- Fable liaison send-off gifts (A2). Granted at run start by apply_liaison_gift;
	#    quest-only so they never appear in shops or reward rolls. Bram leans info, Neve
	#    leans supplies. Modest, permanent-run relics; tune magnitudes in balance work.
	pool.append(_relic("Bram's Briefing",
		"Bram's Records file on Camelot — you know where they're soft. At the start of each combat, apply 1 Vulnerable to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL, 1))
	pool.append(_relic("Neve's Kit",
		"Neve packed you properly, the way she always does. Heal 5 HP after each combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 5))

	# -- Realm map_boon relic (A2). Common folk's boon: the town musters a militia to
	#    shield you. Granted by RunManager.consume_map_boon when map_boon == &"militia".
	pool.append(_relic("Peasant Militia",
		"The common folk march at your side. Start each combat with 8 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 8))
	return pool


static func get_reward_choices(rng: RandomNumberGenerator, count: int = 3,
		exclude_names: PackedStringArray = []) -> Array[RelicData]:
	var pool = _build_pool()

	# Remove relics the player already owns
	var filtered: Array[RelicData] = []
	for relic in pool:
		var dominated = false
		for name in exclude_names:
			if relic.relic_name == name:
				dominated = true
				break
		if not dominated:
			filtered.append(relic)

	# Shuffle and pick with rarity weighting
	filtered.shuffle()
	var picked: Array[RelicData] = []
	var rarity = _roll_rarity(rng)

	for relic in filtered:
		if picked.size() >= count:
			break
		if relic.rarity == rarity:
			picked.append(relic)
			rarity = _roll_rarity(rng)

	# Fallback: fill remaining slots
	if picked.size() < count:
		for relic in filtered:
			if picked.size() >= count:
				break
			if relic not in picked:
				picked.append(relic)

	return picked


static func get_boss_reward_choices(rng: RandomNumberGenerator,
		exclude_names: PackedStringArray = []) -> Array[RelicData]:
	var pool = _build_pool()
	var boss_relics: Array[RelicData] = []
	for relic in pool:
		if relic.rarity == RelicData.RelicRarity.BOSS:
			var owned = false
			for name in exclude_names:
				if relic.relic_name == name:
					owned = true
					break
			if not owned:
				boss_relics.append(relic)

	boss_relics.shuffle()
	var result: Array[RelicData] = []
	for i in mini(3, boss_relics.size()):
		result.append(boss_relics[i])
	return result


static func _roll_rarity(rng: RandomNumberGenerator) -> RelicData.RelicRarity:
	# Base weights: common 0.5, uncommon 0.33, rare 0.17. The realm's reward_rarity_mult
	# (A2) scales the non-common weights; common soaks the remainder. Neutral (1.0)
	# reproduces the original 0.5 / 0.83 thresholds.
	var mult := 1.0
	if RunManager and RunManager.realm_config:
		mult = RunManager.realm_config.reward_rarity_mult
	var rare_w := 0.17 * mult
	var unc_w := 0.33 * mult
	var common_w := maxf(0.0, 1.0 - rare_w - unc_w)
	var roll := rng.randf() * (common_w + unc_w + rare_w)
	if roll < common_w:
		return RelicData.RelicRarity.COMMON
	if roll < common_w + unc_w:
		return RelicData.RelicRarity.UNCOMMON
	return RelicData.RelicRarity.RARE


static func _build_pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []

	# -- COMMON --
	pool.append(_relic("Crimson Ink", "Heal 6 HP after each combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 6))

	pool.append(_relic("Iron Quill", "Start each combat with 1 Strength.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1))

	pool.append(_relic("Steadfast Binding", "Start each combat with 10 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 10))

	pool.append(_relic("Scattered Pages", "At the start of combat, apply 1 Vulnerable to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL, 1))

	pool.append(_relic("Tattered Veil", "At the start of combat, apply 1 Weak to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_WEAK_ALL, 1))

	# -- UNCOMMON --
	pool.append(_relic("Worn Talisman", "Start each combat with 1 Dexterity.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_DEXTERITY, 1))

	pool.append(_relic("Gilded Bookmark", "Gain 15 bonus Gold after each combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.GAIN_GOLD, 15))

	pool.append(_relic("Heartfruit", "Upon pickup, gain 14 Max HP.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_PICKUP,
		RelicData.RelicEffect.GAIN_MAX_HP, 14))

	pool.append(_relic("Prologue Scroll", "Draw 2 additional cards at the start of combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.DRAW_CARDS, 2))

	pool.append(_relic("Spring Charm", "Gain 3 Passion at the start of combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_PASSION, 3))

	# -- Swing gear (design pass Sep 2026): dedicated relics that swing Passion HARDER,
	# so a build-around player commits to a pole in ~1 fight instead of the base ~2,
	# while the plain deck's ramp is unchanged. One per direction so BOTH poles get gear.
	# Wellspring also folds in #22: it was a Rare +1/turn that lost to Demon's Horn's
	# +1 Strength/turn — now Uncommon and +2/turn, a real Blazing accelerant.
	pool.append(_relic("Wellspring of Resolve", "Gain 2 Passion at the start of each turn (surges you toward Blazing).",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_PASSION, 2))

	pool.append(_relic("Leaden Vow", "Lose 2 Passion at the start of each turn (settles you toward Hollow).",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_PASSION, -2))

	# -- RARE --
	pool.append(_relic("Guardian's Sigil", "Gain 5 Block at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_BLOCK, 5))

	pool.append(_relic("Thread of Fate", "Draw 1 additional card at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.DRAW_CARDS, 1))

	pool.append(_relic("Demon's Horn", "Gain 1 Strength at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1))

	# -- BOSS --
	pool.append(_relic("Sanguine Tome", "Heal 12 HP after each combat.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 12))

	pool.append(_relic("Seer's Lens", "Draw 2 additional cards at the start of each turn.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.DRAW_CARDS, 2))

	pool.append(_relic("Brand of Fury", "Start each combat with 2 Strength. Apply 1 Vulnerable to yourself.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 2))

	pool.append(_relic("Diadem of Grace", "Start each combat with 3 Dexterity.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_DEXTERITY, 3))

	return pool


static func _relic(relic_name: String, desc: String, rarity: RelicData.RelicRarity,
		trigger: RelicData.RelicTrigger, effect: RelicData.RelicEffect,
		val: int) -> RelicData:
	var r = RelicData.new()
	r.relic_name = relic_name
	r.description = desc
	r.rarity = rarity
	r.trigger = trigger
	r.effect = effect
	r.value = val
	return r
