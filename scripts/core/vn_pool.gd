class_name VNPool
## Authored VN content for the demo run-start flow. Two segments, chained by the
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


## The full Fable send-off, the FIRST-run introduction, both liaisons in one scene.
## Dialogue only (no choice); the liaison gifts are granted separately by
## apply_liaison_gift. Shown only the first time on a save (or when the player toggles
## "always show intro" back on); returning runs use build_sendoff_single. The demo ships
## the Emo-Hybrid-reactive banter; Hotheaded-Mage reactivity is 1.0+ content.
static func build_sendoff(character: CharacterData) -> VNData:
	var vn := VNData.new()
	vn.title = "Before Deployment"
	vn.add_setting("The Fable office, before deployment")
	vn.add_beat("", "Two desks, two coworkers, the same tired morning.", C_NARRATION)
	_add_bram_beats(vn, _keeper(character))
	_add_neve_beats(vn, _keeper(character))
	return vn


## A returning-run send-off: one liaison only (the two-liaison version is the first-run
## introduction). On a return the liaison KNOWS they've sent you out before, so these beats
## skip the Camelot briefing and the introductions and play as a regular morning dispatching
## chaos: a quick, familiar handover and a little understated encouragement. The caller picks
## the liaison (random per run) and grants that liaison's gift.
static func build_sendoff_single(character: CharacterData, liaison: StringName) -> VNData:
	var vn := VNData.new()
	vn.title = "Before Deployment"
	if liaison == &"neve":
		_add_neve_return_beats(vn, _keeper(character))
	else:
		_add_bram_return_beats(vn, _keeper(character))
	return vn


## The speaker label for the played keeper: their work-name, so a line reads as theirs.
static func _keeper(character: CharacterData) -> String:
	if character != null and character.work_name != "":
		return character.work_name
	return "You"


## Bram: Records. Dry, tired; hands over the Camelot briefing.
static func _add_bram_beats(vn: VNData, keeper: String) -> void:
	vn.add_beat("", "Bram slides a folder across the Records desk without looking up.", C_NARRATION)
	vn.add_beat("Bram", "Filled it with everything we still have on Camelot. There's a 'weapon of heroes' in there, some reference out of the realm's old stories. We think. Lore never sticks around more than a couple days.", C_BRAM)
	vn.add_beat(keeper, "I know the feeling.", C_KEEPER)
	vn.add_beat("", "Bram looks up then. Not unkindly.", C_NARRATION)
	vn.add_beat("Bram", "Right. You would.", C_BRAM)
	vn.add_beat("Bram", "At least yours is only the once. Mine does it on a schedule.", C_BRAM)


## Neve: Dispatch. Warm veteran; hands over the kit.
static func _add_neve_beats(vn: VNData, keeper: String) -> void:
	vn.add_setting("Dispatch")
	vn.add_beat("", "Neve holds the kit a second longer than she needs to.", C_NARRATION)
	vn.add_beat("Neve", "Camelot. Political realm. Everyone smiles while they take something off you.", C_NEVE)
	vn.add_beat(keeper, "You say that about every realm.", C_KEEPER)
	vn.add_beat("Neve", "I mean it about every realm.", C_NEVE)
	vn.add_beat("", "She almost leaves it there.", C_NARRATION)
	vn.add_beat("Neve", "You slept badly. You get a line between your eyes when you don't.", C_NEVE)
	vn.add_beat(keeper, "It's nothing. A dream I couldn't hold onto.", C_KEEPER)
	vn.add_beat("Neve", "Those are the worst kind.", C_NEVE)
	vn.add_beat("", "She writes something small in the back of a battered notebook, the way other people check a watch, and hands you the rest of your supplies.", C_NARRATION)
	vn.add_beat("Neve", "Go on. Come back in one piece. You're bad at that.", C_NEVE)


## Bram, returning run: no re-briefing (you know the file), the lore-decay running gag, and a
## dry vote of confidence that passes for warmth out of Records.
static func _add_bram_return_beats(vn: VNData, keeper: String) -> void:
	vn.add_setting("The Records desk")
	vn.add_beat("", "The Camelot folder is already on the corner, squared to the edge. Bram saw you coming.", C_NARRATION)
	vn.add_beat("Bram", "You know the file. Same realm, same weapon-of-heroes footnote, same half of it gone stale since you last read it.", C_BRAM)
	vn.add_beat(keeper, "Comforting.", C_KEEPER)
	vn.add_beat("Bram", "It's the work. Nothing out there holds still long enough to be worth learning properly.", C_BRAM)
	vn.add_beat("Bram", "You keep walking back in here, though. I've started counting on it. Don't make a liar of me.", C_BRAM)


## Neve, returning run: she skips the speech you've both heard, reads you over the way she
## always does, and sends you off with the blunt affection of a veteran who's done this before.
static func _add_neve_return_beats(vn: VNData, keeper: String) -> void:
	vn.add_setting("Dispatch")
	vn.add_beat("", "Neve has the kit packed already. Probably had it packed since the last time.", C_NARRATION)
	vn.add_beat("Neve", "Camelot again. I won't do the speech. You've heard the speech.", C_NEVE)
	vn.add_beat(keeper, "Everyone smiles while they take something off me.", C_KEEPER)
	vn.add_beat("Neve", "See. You listen.", C_NEVE)
	vn.add_beat("", "She looks you over, taking an inventory only she can read.", C_NARRATION)
	vn.add_beat("Neve", "Still not sleeping. I'm not going to keep saying it.", C_NEVE)
	vn.add_beat("Neve", "Go on, you know the way out. Come back the same number of pieces you left in.", C_NEVE)


## The Camelot realm-entry, "A Realm Divided": arrival at a realm in crisis, then the
## court-vs-common-folk allegiance choice that SHAPES the run (each choice carries a
## RealmConfig applied via RunManager.apply_realm_config BEFORE the map generates, so it
## reshapes the map's composition, not just retunes it). ~3 scroll panels + the choice.
## This is the one big realm-shaping decision; the smaller within-act event layer (e.g. the
## standalone Peasant's Plea lore event) is separate.
static func build_camelot_entry() -> VNData:
	var vn := VNData.new()
	vn.title = "A Realm Divided"

	vn.add_beat("", "Camelot rises ahead, the banners on its walls gone plain, the fields beyond them churned to mud and ash. Its champion, Sir Caedmon, rode out to meet the thing at the gates. What rode back was not him.", C_NARRATION)
	vn.add_beat("", "They have been waiting for you. Word runs ahead of a dispatched keeper the way the old promise runs ahead of the sword: a hero will come, and draw Excalibur, and set it right. By the time you reach the gate, two delegations are already crossing the yard.", C_NARRATION)
	vn.add_beat("", "From the keep, the court: velvet and guarded smiles, an offer of everything the crown can spare. From the town, the common folk: calloused hands, no smiles to spare, the same desperate plea. Both want the hero. Only one gets the first of you.", C_NARRATION)

	var court := _court_config()
	var folk := _folk_config()
	vn.add_choice("Stand with the court.", court,
		"The courtiers fold you into their warmth and their promises. The keep's doors open; the townsfolk's delegation melts back into the crowd. You will want for nothing here, and nothing here is free.",
		_court_trade(court))
	vn.add_choice("Stand with the common folk.", folk,
		"The townsfolk take you in among themselves, rough and grateful. Behind you, the court's smiles cool by a degree. The people will hold nothing back for you, and the crown will remember the slight.",
		_folk_trade(folk))
	return vn


## What each pledge will change, said under its option before it is taken. The words were chosen on
## 10 Nov; the numbers are read from the config, so a balance change carries into the line.
static func _court_trade(c: RealmConfig) -> String:
	var added := MapGenerator.elites_added_for(c.elite_frequency_mult)
	return ("A harder road that pays better. %s on it, and every enemy gets %d%% stronger. In return, "
		+ "the court is in your favor, and the cards and relics you find are more often rare.") % [
		_more_elites(added), _percent(c.enemy_difficulty_mult)]


static func _folk_trade(c: RealmConfig) -> String:
	var people := RelicPool.get_relic_by_name("The People's Line")
	var start := RunManager.passion.current_value if RunManager.passion else 0
	var tier := PassionState.tier_name(RunManager.get_passion_tier_for_value(start + c.passion_shift))
	return ("A gentler road with a price. The people are in your favor, the road's elites are weakened, "
		+ "you start every fight with %d Block, and every enemy gets %d%% weaker. In return, the shops "
		+ "charge %d%% more, and the cards and relics you find are more often common. Your Passion also "
		+ "falls to %s.") % [people.value if people else 0, _percent(c.enemy_difficulty_mult),
		_percent(c.shop_price_mult), tier]


## "Two more elites wait", or "One more elite waits".
static func _more_elites(n: int) -> String:
	const WORDS := ["No", "One", "Two", "Three", "Four"]
	var count: String = WORDS[n] if n < WORDS.size() else str(n)
	return ("%s more elite waits" if n == 1 else "%s more elites wait") % count


## A multiplier as the whole percent it moves by: 1.1 and 0.9 are both 10.
static func _percent(mult: float) -> int:
	return absi(roundi((mult - 1.0) * 100.0))


## Court: side with power. A harder, richer realm: the pledge converts a couple of combat
## nodes into NEW elites (more risk, more reward), enemies hit a touch harder, loot is
## richer; shops stay at their normal price. Starting values are tuned against
## the combat harness.
static func _court_config() -> RealmConfig:
	var c := RealmConfig.new()
	c.enemy_difficulty_mult = 1.1
	c.elite_frequency_mult = 1.4  # > 1 -> the transform adds elites
	c.shop_price_mult = 1.0
	c.reward_rarity_mult = 1.3
	c.map_boon = &""
	c.standing_init = -25  # plant you in the court's favor (clears FAVOR_THRESHOLD)
	return c


## Common folk: side with the people. An easier realm: the people WEAKEN the realm's
## elites in place (you keep their rewards, but those fights start the enemies Weak + power-
## nerfed) plus a militia map_boon; but the slighted court raises shop prices all act, and
## loot is a touch plainer. Also shoves Passion into tier-1 Physical (the grounded, people's-
## champion stance pulls the keeper toward his physical self): from the Steady start (0) a
## -34 shift lands mid-Wavering, the first Physical tier below center (Emo Hybrid thresholds
## [50,18,-18,-50]; volatility 1.0). Starting values are tuned against
## the combat harness.
static func _folk_config() -> RealmConfig:
	var c := RealmConfig.new()
	c.enemy_difficulty_mult = 0.95
	c.elite_frequency_mult = 1.0  # elites stay (keep the rewards); they're weakened instead
	c.elite_weaken = true
	c.shop_price_mult = 1.2
	c.reward_rarity_mult = 0.9
	c.map_boon = &"militia"
	c.passion_shift = -34
	c.standing_init = 25  # plant you in the people's favor (clears FAVOR_THRESHOLD)
	return c
