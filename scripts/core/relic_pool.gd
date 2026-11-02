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
	# The per-liaison pools are quest-only too, but live in their own builders so a
	# grant resolved into granted_relic_id (Bram's Records / Neve's Dispatch relics)
	# can still be looked up here by the apply + summary path.
	for relic in _build_bram_pool():
		if relic.relic_name == name:
			return relic
	for relic in _build_neve_pool():
		if relic.relic_name == name:
			return relic
	# The woken forms of the forgotten relics: never rolled, only reached by waking.
	for relic in _build_woken_pool():
		if relic.relic_name == name:
			return relic
	return null


# ============================================================
# FORGOTTEN RELICS
# ============================================================
# A relic that arrives with its name worn off and its power dormant, and gets both back at a
# place that keeps records (the Scriptorium, the Tourney's herald, the Reliquary): the rot's
# subtraction running backwards, once, on the player's side of the table. The dormant form rolls
# in rewards and shops at its own rarity, fair on its own; the woken form is the one it had, one
# rarity up, the same effect and one more, and lives here outside _build_pool so it is only ever
# reached by waking (RunManager.wake_relic). The tell is one line of absence in the dormant text
# and the overlay's dead gold. A relic only ever goes up, once, never by distance. Every value
# PROVISIONAL (part 3b); the harness models both states in part 4. The dormant names are plain and
# unearned; the hart, the oak and Sir Aldric are placeholder names, open to change.

## The six woken forms. Each names the dormant form it came from.
static func _build_woken_pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []
	pool.append(_woken("The Hart's Shield", &"A Plain Shield",
		"A hart lodged, argent, on a field of green, read back off the roll. Start each combat with 8 Block and 1 Poise.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 8, RelicData.RelicEffect.GAIN_DEXTERITY, 1))
	pool.append(_woken("The Oak Banner", &"An Unpicked Banner",
		"An oak with its roots showing, gold on red, and they rally to it again. Start each combat with 1 Strength and draw 1 additional card.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1, RelicData.RelicEffect.DRAW_CARDS, 1))
	pool.append(_woken("The Brass of Sir Aldric", &"A Rubbed Brass",
		"The inscription read back, and with it the rents of a dead man's lands. Gain 15 bonus Gold and heal 6 HP after each combat.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.GAIN_GOLD, 15, RelicData.RelicEffect.HEAL, 6))
	# The girdle's ward and the scabbard's guard are read by CombatEngine by name (effect2 NONE,
	# value2 the number), like Blooded Edge: once a combat a blow that would fell you leaves you at
	# value2 HP; every enemy hit on you deals value2 less.
	pool.append(_woken("The Green Girdle", &"A Faded Girdle",
		"Green again, and the gold bright in it, and whoever wears it cannot be slain, or so the lady said. Heal 8 HP after each combat. Once each combat, a blow that would fell you leaves you at 1 HP.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 8, RelicData.RelicEffect.NONE, 1))
	pool.append(_woken("Excalibur's Scabbard", &"A Bare Scabbard",
		"The sheath that was worth ten of the sword: whoever wears it loses no blood. Heal 2 HP at the start of each turn, and every enemy hit on you deals 1 less.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.HEAL, 2, RelicData.RelicEffect.NONE, 1))
	pool.append(_woken("Harja", &"A Bone Comb",
		"The word along the back is a name, or the word for a fighter, and nobody can say which. Draw 1 additional card and start each combat with 1 Poise.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.DRAW_CARDS, 1, RelicData.RelicEffect.GAIN_DEXTERITY, 1))
	return pool


## The names of every dormant form, in a stable order (tests, tooling).
static func dormant_names() -> PackedStringArray:
	var names := PackedStringArray()
	for relic in _build_pool():
		if relic.is_dormant():
			names.append(relic.relic_name)
	return names


## The offer: while the keeper carries no forgotten relic, dormant or woken, one of a reward's
## picks is a dormant one, so a run meets the mechanic by its first elite rather than by luck.
## Replaces the last pick with a seeded dormant choice when none was rolled; nothing to do when
## one was, when the keeper already carries one, or when none is left to offer.
static func _ensure_a_dormant_pick(picked: Array[RelicData], filtered: Array[RelicData],
		rng: RandomNumberGenerator) -> void:
	for relic in picked:
		if relic.is_dormant():
			return
	var dormant: Array[RelicData] = []
	for relic in filtered:
		if relic.is_dormant() and relic not in picked:
			dormant.append(relic)
	if dormant.is_empty():
		return
	var offer: RelicData = dormant[rng.randi_range(0, dormant.size() - 1)]
	if picked.is_empty():
		picked.append(offer)
	else:
		picked[picked.size() - 1] = offer


## A dormant forgotten relic: an ordinary reward relic that also names the woken form it wakes
## into, how prose calls it, and the sentence of its waking.
static func _forgotten(relic_name: String, short_name: String, desc: String,
		rarity: RelicData.RelicRarity, trigger: RelicData.RelicTrigger,
		effect: RelicData.RelicEffect, val: int, wakes_into: StringName,
		wake_line: String) -> RelicData:
	var r := _relic(relic_name, desc, rarity, trigger, effect, val)
	r.wakes_into = wakes_into
	r.short_name = short_name
	r.wake_line = wake_line
	return r


## A woken forgotten relic: the effect it always had and one more, naming the dormant form.
static func _woken(relic_name: String, woken_from: StringName, desc: String,
		rarity: RelicData.RelicRarity, trigger: RelicData.RelicTrigger,
		effect: RelicData.RelicEffect, val: int, effect2: RelicData.RelicEffect,
		val2: int) -> RelicData:
	var r := _relic(relic_name, desc, rarity, trigger, effect, val)
	r.woken_from = woken_from
	r.effect2 = effect2
	r.value2 = val2
	return r


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
		"Bram's Records file on Camelot: you know where they're soft. At the start of each combat, apply 1 Vulnerable to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL, 1))
	pool.append(_relic("Neve's Kit",
		"Neve packed you properly, the way she always does. Heal 5 HP after each combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 5))

	# -- Realm map_boon relic (A2). Common folk's boon: the town musters a militia to
	#    shield you. Granted by RunManager.consume_map_boon when map_boon == &"militia".
	pool.append(_relic("The People's Line",
		"The common folk hold the line at your side. Start each combat with 8 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 8))

	# -- Raider questline payoff relic. Granted by the "raider_victory" event beat after the
	#    cross-map hunt. Effect is NONE here (no generic trigger fits "first attack of the
	#    combat"); CombatEngine reads the relic directly and adds `value` to the first attack
	#    damage you land each combat, like Excalibur's externally-driven behavior. The value
	#    is the tunable first-hit bonus. Quest-only, so it never appears in shops or rewards.
	pool.append(_relic("Blooded Edge",
		"The first attack you land each combat deals 6 bonus damage.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.NONE, 6))

	# -- Reliquary event payoff relic. Granted by the "reliquary_won" beat after the chapel
	#    beast falls (you refused to let the memory fade). Quest-only, so it never appears in
	#    shops or reward rolls. A chapel censer that swings on its chain: before each of your
	#    turns it drifts your Passion toward the pole you set on the map (Blazing +, Hollow -).
	#    NONE effect read directly by CombatEngine (like Blooded Edge / Momentum) because a fixed
	#    GAIN_PASSION relic can't flip sign per-fight. Coexists with Wellspring of Resolve /
	#    Leaden Vow (the fixed one-directional +/-2 commons) as the premium, flexible version.
	#    (Supersedes the old Vigil Candle, which this reward replaced and which is now retired.)
	pool.append(_relic("The Thurible",
		"A chapel censer on its chain. Before each of your turns it swings your Passion toward the pole you choose: +3 toward Blazing, or -3 toward Hollow. Switch sides between fights.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.NONE, 3))

	# -- Campfire treasure payoff relic. Granted by the "campfire_victory" beat after the
	#    barrow-warden falls (you followed the dead campers' map to the cache). Quest-only, so
	#    it never appears in shops or reward rolls. The warden's own grave-mail, lifted off the
	#    hoard: a straight defensive opener, strong enough to justify the optional detour.
	pool.append(_relic("Barrow-Warden's Mail",
		"The grave-mail off the hoard's dead keeper. Start each combat with 15 Block.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 15))
	return pool


# ============================================================
# PER-LIAISON RELIC POOLS
# ============================================================
# Dedicated pools the Fable liaisons hand out at events. Folk events pay in relics (per the
# faction-reward principle: a folk run skips no fights but faces steeper shops, so it earns
# gear instead of cards). Each liaison gives from a themed set: Bram, from Records, deals in
# knowledge and foresight (undercut the enemy, draw ahead, call in debts); Neve, from
# Dispatch, deals in the well-packed kit (patch up, pack heavier, stand the blow). Like the
# quest pool these live outside _build_pool, so they can never surface in shops or post-combat
# reward rolls — only EventChoice.grants_liaison_relic draws from them, via
# get_liaison_relic_choices. get_relic_by_name scans them so a granted id still resolves.

## Bram's Records relics — scholarly foresight: you read up on the road and arrive knowing
## where it's soft, a step ahead, with the accounts in hand.
static func _build_bram_pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []
	pool.append(_relic("Annotated Bestiary",
		"Bram's notes on what walks this road. At the start of combat, apply 2 Vulnerable to ALL enemies.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL, 2))
	pool.append(_relic("Writ of Precedence",
		"The record shows they hold their ground on a lie, and some part of them knows it. At the start of combat, apply 1 Weak to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_WEAK_ALL, 1))
	pool.append(_relic("Marginalia",
		"A lifetime of notes crammed down the margins, and all of it comes back when you need it. Draw 1 additional card at the start of combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.DRAW_CARDS, 1))
	pool.append(_relic("The Long Ledger",
		"Records keeps every account, and sooner or later calls them in. Gain 20 bonus Gold after each combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.GAIN_GOLD, 20))
	return pool


## Neve's Dispatch relics — a pure survival kit: nothing to swing, everything to keep you
## standing (patch up between fights, bleed health back during them, stand the first blow,
## steady the hands). Keeping people alive in a trade that chews them up is the whole of her
## work, and it shows in what she packs.
static func _build_neve_pool() -> Array[RelicData]:
	var pool: Array[RelicData] = []
	pool.append(_relic("Linen Roll",
		"A roll of clean linen, packed the way Neve packs it, with a fresh length cut after every fight. Heal 8 HP after each combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 8))
	# Was a flat +12 Max HP (a bland bigger-sponge); reworked to in-fight regen so it uses HP as
	# a flowing resource, distinct from Linen Roll's between-fight top-up. HEAL on
	# ON_TURN_START is already handled by _apply_relic_effect, so this needs no engine work.
	pool.append(_relic("Iron Rations",
		"She overpacks the food and makes you eat on the march, whatever you say about it. Heal 2 HP at the start of each turn.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.HEAL, 2))
	pool.append(_relic("Packed Tight",
		"A kit stowed the way Neve stows it sits close and turns a blow. Start each combat with 10 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 10))
	# A flask whose kick fades: Poise (this game's Dexterity) grants bonus block and sheds 1 each
	# turn, so the steadiness is real early and gone by the long grind -- a defensive burst, not a
	# flat stat. (Replaced the old +1 Strength, a plain Iron Quill clone; and this absorbed the
	# cut Broken-In Boots, so one Poise relic owns the lane instead of two.)
	pool.append(_relic("Hobnails",
		"Hobnails she has you drive into your boots before the hard roads. The footing is sure at the start and wears smooth as the fight wears on. Start each combat with 2 Poise.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_DEXTERITY, 2))
	return pool


## Maps a liaison id to its pool. Unknown ids warn and return empty (a grant simply no-ops).
static func _build_liaison_pool(liaison: StringName) -> Array[RelicData]:
	match liaison:
		&"bram":
			return _build_bram_pool()
		&"neve":
			return _build_neve_pool()
		_:
			push_warning("Unknown liaison relic pool: %s" % liaison)
			return []


## Rolls up to `count` relics the player doesn't already own from a liaison's pool. Shuffled
## with the passed rng (Fisher-Yates) so the roll is reproducible from the run seed. Events
## resolve the first pick into granted_relic_id, so the grant reuses the normal relic path.
static func get_liaison_relic_choices(liaison: StringName, rng: RandomNumberGenerator,
		count: int = 1, exclude_names: PackedStringArray = []) -> Array[RelicData]:
	var filtered: Array[RelicData] = []
	for relic in _build_liaison_pool(liaison):
		if relic.relic_name not in exclude_names:
			filtered.append(relic)
	RngManager.shuffle(filtered, rng)
	return filtered.slice(0, mini(count, filtered.size()))


static func get_reward_choices(rng: RandomNumberGenerator, count: int = 3,
		exclude_names: PackedStringArray = []) -> Array[RelicData]:
	var pool = _build_pool()

	# Remove relics the player already owns, and the dormant form of a relic the player has
	# already woken (the woken form is the same thing with its name back).
	var filtered: Array[RelicData] = []
	for relic in pool:
		var dominated = false
		for name in exclude_names:
			if relic.relic_name == name or (relic.is_dormant() and String(relic.wakes_into) == name):
				dominated = true
				break
		if not dominated:
			filtered.append(relic)

	# Shuffle and pick with rarity weighting
	RngManager.shuffle(filtered, rng)
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

	# The offer (see _ensure_a_dormant_pick): a keeper carrying no forgotten relic is shown one.
	if RunManager and not RunManager.carries_forgotten_relic():
		_ensure_a_dormant_pick(picked, filtered, rng)

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

	RngManager.shuffle(boss_relics, rng)
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
	pool.append(_relic("Crimson Ink", "Red ink that works its way back into whatever it touched. Heal 6 HP after each combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 6))

	pool.append(_relic("Iron Quill", "A quill cut from iron. The hand behind it does not tire. Start each combat with 1 Strength.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1))

	pool.append(_relic("Steadfast Binding", "Cords pulled tight through the boards. The leaves hold under any blow. Start each combat with 10 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 10))

	pool.append(_relic("Scattered Pages", "Leaves shaken loose from their gathering. Nothing stays where it was put. At the start of combat, apply 1 Vulnerable to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_VULNERABLE_ALL, 1))

	pool.append(_relic("Tattered Veil", "A veil worn to threads, and it drags at whoever it is thrown over. At the start of combat, apply 1 Weak to ALL enemies.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.APPLY_WEAK_ALL, 1))

	# -- COMMON, FORGOTTEN (dormant; the woken forms are in _build_woken_pool) --
	# Two knightly objects with the device worn off, and the one from elsewhere: a comb cut with
	# a word no one here can read (LORE_SURFACE §5, the strange elite; nothing explains it).
	pool.append(_forgotten("A Plain Shield", "the plain shield",
		"A knight's shield with the paint gone down to the bare wood, the boss still bright. Something was painted here once. Start each combat with 8 Block.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_BLOCK, 8, &"The Hart's Shield",
		"The paint comes back up through the grain of the wood, white first: a hart, lying down, on a field of green."))
	pool.append(_forgotten("An Unpicked Banner", "the unpicked banner",
		"A banner with its device unpicked thread by thread, and the holes still show the shape of what was there. Start each combat with 1 Strength.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1, &"The Oak Banner",
		"The holes in the cloth fill with thread, gold on red: an oak with its roots showing."))
	pool.append(_forgotten("A Bone Comb", "the bone comb",
		"A comb of antler, five teeth gone, with a word cut along the back that no one here can read. Draw 1 additional card at the start of combat.",
		RelicData.RelicRarity.COMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.DRAW_CARDS, 1, &"Harja",
		"Red comes into the cuts along the back, then black, and the one long scratch comes apart into a word."))

	# -- UNCOMMON --
	pool.append(_relic("Ruled Margin", "The ruled lines that keep a scribe's hand straight, pricked down the margin. Start each combat with 1 Poise.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_DEXTERITY, 1))

	pool.append(_relic("Gilded Bookmark", "A gilt ribbon laid in at the page where something is owed. Gain 15 bonus Gold after each combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.GAIN_GOLD, 15))

	pool.append(_relic("Oak Boards", "Bound between boards of oak, a book outlasts the hand that wrote it. Upon pickup, gain 14 Max HP.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_PICKUP,
		RelicData.RelicEffect.GAIN_MAX_HP, 14))

	pool.append(_relic("Prologue Scroll", "The scroll a herald reads out before the lists open. Nobody is surprised by what follows. Draw 2 additional cards at the start of combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.DRAW_CARDS, 2))

	# (Spring Charm retired Oct 2026 — its flat +3 Passion at combat start was superseded by the
	# steerable per-turn pole relics. The Thurible is the flexible Passion-swing reward now.)

	# -- Swing gear (design pass Sep 2026): dedicated relics that swing Passion HARDER,
	# so a build-around player commits to a pole in ~1 fight instead of the base ~2,
	# while the plain deck's ramp is unchanged. One per direction so BOTH poles get gear.
	# Wellspring also folds in #22: it was a Rare +1/turn that lost to Gilt Spurs'
	# +1 Strength/turn — now Uncommon and +2/turn, a real Blazing accelerant.
	pool.append(_relic("Wellspring of Resolve", "Ink that wells up faster than the pen can use it. Gain 2 Passion at the start of each turn (surges you toward Blazing).",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_PASSION, 2))

	pool.append(_relic("Leaden Vow", "A vow sealed in lead, heavy enough to settle whatever it is hung on. Lose 2 Passion at the start of each turn (settles you toward Hollow).",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_PASSION, -2))

	# -- UNCOMMON, FORGOTTEN (dormant) --
	# A memorial brass with its inscription rubbed away, and two of the romances' own named
	# objects, the girdle and the scabbard, each with its colour or its tooling gone.
	pool.append(_forgotten("A Rubbed Brass", "the rubbed brass",
		"A small memorial brass off a tomb slab, the inscription rubbed to nothing by a century of hands. Something was written here once. Gain 10 bonus Gold after each combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.GAIN_GOLD, 10, &"The Brass of Sir Aldric",
		"The letters stand up out of the brass one at a time, and the last of them is a name."))
	pool.append(_forgotten("A Faded Girdle", "the faded girdle",
		"A lace of silk to go about the waist, the green gone to grey and the gold thread still in it. Something was worked into it once. Heal 8 HP after each combat.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 8, &"The Green Girdle",
		"The grey goes out of the silk the way cold goes out of a hand, and it is green."))
	pool.append(_forgotten("A Bare Scabbard", "the bare scabbard",
		"A scabbard tooled for a blade longer than yours, the leather worn smooth where a device was. Heal 2 HP at the start of each turn.",
		RelicData.RelicRarity.UNCOMMON, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.HEAL, 2, &"Excalibur's Scabbard",
		"The tooling comes back under your thumb, and you know the blade it was made for, whether or not you carry it."))

	# -- RARE --
	pool.append(_relic("Chained Folio", "A folio chained to its lectern so nothing could carry it off. Gain 5 Block at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_BLOCK, 5))

	pool.append(_relic("Catchword", "The word at the foot of a page that tells you the next one before you turn it. Draw 1 additional card at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.DRAW_CARDS, 1))

	pool.append(_relic("Gilt Spurs", "The spurs a knight is given the day he is made one. Gain 1 Strength at the start of each turn.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 1))

	# Momentum: a within-turn ramp. CombatEngine reads this relic directly (NONE effect, like
	# Blooded Edge) -- each hit you land on an enemy raises your attack damage by `value` for
	# the rest of the turn, reset at the start of your next turn. Rewards multi-hit chains.
	pool.append(_relic("Momentum",
		"A pen that runs faster with every stroke, until the line is finished. During your turn, each hit you land on an enemy gives your attacks +1 damage until your turn ends.",
		RelicData.RelicRarity.RARE, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.NONE, 1))

	# -- BOSS --
	pool.append(_relic("Sanguine Tome", "A book bound in oxblood and kept open at the one page that mends. Heal 12 HP after each combat.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_COMBAT_END,
		RelicData.RelicEffect.HEAL, 12))

	pool.append(_relic("The Index", "Every page cross-referenced, so what you need is already in your hand. Draw 2 additional cards at the start of each turn.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_TURN_START,
		RelicData.RelicEffect.DRAW_CARDS, 2))

	pool.append(_relic("Rubric", "Written in red, so that nothing in it can be missed. Start each combat with 2 Strength.",
		RelicData.RelicRarity.BOSS, RelicData.RelicTrigger.ON_COMBAT_START,
		RelicData.RelicEffect.GAIN_STRENGTH, 2))

	pool.append(_relic("Flourish", "The flourish a steady hand leaves at the end of a stroke. Start each combat with 3 Poise.",
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
