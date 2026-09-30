class_name VNPool
## Authored VN content for the demo run-start flow (A2). Two segments, chained by the
## run-start sequencer (character_select): the Fable send-off, then the Camelot realm-entry.
##
##   character_select -> build_sendoff() -> build_camelot_entry() -> map
##
## The liaisons name Fable, the office that sends keepers out, and talk about its daily grind;
## the Court/Folk premise is the dispatch work and the Excalibur legend.

# Speaker accent colours.
const C_NARRATION := Color(0.75, 0.78, 0.85)   # cool, un-speakered stage text
const C_KEEPER := Color(0.74, 0.60, 0.92)      # the Emo Hybrid's magic-purple
const C_BRAM := Color(0.68, 0.72, 0.64)        # dusty Records grey-green
const C_NEVE := Color(0.92, 0.72, 0.42)        # warm Dispatch amber
const C_COURT := Color(0.86, 0.74, 0.40)       # gilt
const C_FOLK := Color(0.72, 0.66, 0.52)        # homespun


## The full Fable send-off — the FIRST-run introduction, both liaisons in one scene.
## Dialogue only (no choice); the liaison gifts are granted separately by
## apply_liaison_gift. Shown only the first time on a save (or when the player toggles
## "always show intro" back on); returning runs use build_sendoff_single. The demo ships
## the Emo-Hybrid-reactive banter; Hotheaded-Mage reactivity is 1.0+ content.
static func build_sendoff(_character: CharacterData) -> VNData:
	var vn := VNData.new()
	vn.title = "Before Deployment"
	vn.add_beat("", "The Fable office, before deployment. Two desks, two coworkers, the same tired morning.", C_NARRATION)
	_add_bram_beats(vn)
	_add_neve_beats(vn)
	return vn


## A returning-run send-off: one liaison only, since the two-liaison version is the
## first-run introduction. Each liaison's beats self-frame (Records / Dispatch), so there
## is no shared opener. The caller picks the liaison (random per run) and grants that
## liaison's gift.
static func build_sendoff_single(_character: CharacterData, liaison: StringName) -> VNData:
	var vn := VNData.new()
	vn.title = "Before Deployment"
	if liaison == &"neve":
		_add_neve_beats(vn)
	else:
		_add_bram_beats(vn)
	return vn


## Bram — Records. Dry, tired; hands over the Camelot briefing.
static func _add_bram_beats(vn: VNData) -> void:
	vn.add_beat("", "Bram slides a folder across the Records desk without looking up.", C_NARRATION)
	vn.add_beat("Bram", "Filled it with everything we still have on Camelot. There's a 'weapon of heroes' in there — some reference out of Celtic lore. We think. Lore never sticks around more than a couple days.", C_BRAM)
	vn.add_beat("You", "I know the feeling.", C_KEEPER)
	vn.add_beat("", "Bram looks up then. Not unkindly.", C_NARRATION)
	vn.add_beat("Bram", "Right. You would.", C_BRAM)
	vn.add_beat("Bram", "At least yours is only the once. Mine does it on a schedule.", C_BRAM)


## Neve — Dispatch. Warm veteran; hands over the kit.
static func _add_neve_beats(vn: VNData) -> void:
	vn.add_beat("", "Dispatch. Neve holds the kit a second longer than she needs to.", C_NARRATION)
	vn.add_beat("Neve", "Camelot. Political realm. Everyone smiles while they take something off you.", C_NEVE)
	vn.add_beat("You", "You say that about every realm.", C_KEEPER)
	vn.add_beat("Neve", "I mean it about every realm.", C_NEVE)
	vn.add_beat("", "She almost leaves it there.", C_NARRATION)
	vn.add_beat("Neve", "You slept badly. You get a line between your eyes when you don't.", C_NEVE)
	vn.add_beat("You", "It's nothing. A dream I couldn't hold onto.", C_KEEPER)
	vn.add_beat("Neve", "Those are the worst kind.", C_NEVE)
	vn.add_beat("", "She writes something small in the back of a battered notebook, the way other people check a watch, and hands you the rest of your supplies.", C_NARRATION)
	vn.add_beat("Neve", "Go on. Come back in one piece. You're bad at that.", C_NEVE)


## The Camelot realm-entry — "A Realm Divided": arrival at a realm in crisis, then the
## court-vs-common-folk allegiance choice that SHAPES the run (each choice carries a
## RealmConfig applied via RunManager.apply_realm_config BEFORE the map generates, so it
## reshapes the map's composition, not just retunes it). ~3 scroll panels + the choice.
## This is the one big realm-shaping decision; the smaller within-act event layer (e.g. the
## standalone Peasant's Plea lore event) is separate. See docs/REALM_CAMELOT.md.
static func build_camelot_entry() -> VNData:
	var vn := VNData.new()
	vn.title = "A Realm Divided"

	vn.add_beat("", "Camelot rises ahead — banners at half-mast, the fields beyond the walls churned to mud and ash. Its champion, Sir Caedmon, rode out to meet the thing at the gates. What rode back was not him.", C_NARRATION)
	vn.add_beat("", "They have been waiting for you. Word runs ahead of a dispatched keeper the way the old promise runs ahead of the sword: a hero will come, and draw Excalibur, and set it right. By the time you reach the gate, two delegations are already crossing the yard.", C_NARRATION)
	vn.add_beat("", "From the keep, the court — velvet and guarded smiles, an offer of everything the crown can spare. From the town, the common folk — calloused hands, no smiles to spare, the same desperate plea. Both want the hero. Only one gets the first of you.", C_NARRATION)

	vn.add_choice("Stand with the court.", _court_config(),
		"The courtiers fold you into their warmth and their promises. The keep's doors open; the townsfolk's delegation melts back into the crowd. You will want for nothing here — and nothing here is free.")
	vn.add_choice("Stand with the common folk.", _folk_config(),
		"The townsfolk take you in among themselves, rough and grateful. Behind you, the court's smiles cool by a degree. The people will hold nothing back for you — and the crown will remember the slight.")
	return vn


## Court: side with power. A harder, richer realm -- more elites, tougher enemies, better
## loot; shops stay at their normal price. Starting values per the REALM_CAMELOT table;
## tune vs the combat harness.
static func _court_config() -> RealmConfig:
	var c := RealmConfig.new()
	c.enemy_difficulty_mult = 1.1
	c.elite_frequency_mult = 1.4
	c.shop_price_mult = 1.0
	c.reward_rarity_mult = 1.3
	c.map_boon = &""
	return c


## Common folk: side with the people. An easier realm -- fewer, weaker elites plus a
## militia map_boon -- but the slighted court raises shop prices all act, and loot is a
## touch plainer. Also shoves Passion into tier-1 Physical (the grounded, people's-champion
## stance pulls the keeper toward his physical self): from the Steady start (0) a -34 shift
## lands mid-Wavering, the first Physical tier below center (Emo Hybrid thresholds
## [50,18,-18,-50]; volatility 1.0). Starting values per the REALM_CAMELOT table; tune vs
## the combat harness.
static func _folk_config() -> RealmConfig:
	var c := RealmConfig.new()
	c.enemy_difficulty_mult = 0.95
	c.elite_frequency_mult = 0.7
	c.shop_price_mult = 1.2
	c.reward_rarity_mult = 0.9
	c.map_boon = &"militia"
	c.passion_shift = -34
	return c
