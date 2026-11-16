class_name TitlePool
## Builds and returns the canonical TitleData instances.
## Awarding logic (which title to grant after which event) lives elsewhere;
## this class is a content registry, not a decision system.

const HERALDIC_ACCENT: Color = Color(0.78, 0.18, 0.18)    # Camelot red
const NEUTRAL_ACCENT: Color = Color(0.85, 0.78, 0.55)     # Parchment
const PEOPLES_ACCENT: Color = Color(0.82, 0.68, 0.32)     # Harvest gold (the common folk)
const RUNIC_ACCENT: Color = Color(0.42, 0.55, 0.78)       # Yggdrasil's cold blue, as its sky has it


# --- Public API ---

## Returns every title defined. Cheap to call; no I/O.
static func get_all_titles() -> Array[TitleData]:
	var titles: Array[TitleData] = []
	titles.append(_build_king_of_camelot())
	titles.append(_build_camelots_champion())
	titles.append(_build_swords_bearer())
	titles.append(_build_outlander_of_camelot())
	titles.append(_build_the_merciful())
	titles.append(_build_the_gracious())
	titles.append(_build_the_calculating())
	titles.append(_build_the_compassionate())
	titles.append(_build_the_unfading())
	titles.append(_build_peoples_champion())
	titles.append(_build_guest_of_the_hall())
	return titles


## Look up a single title by id, or null if not found.
static func get_title(id: StringName) -> TitleData:
	for title in get_all_titles():
		if title.title_id == id:
			return title
	return null


## All realm titles tied to a specific realm.
static func get_realm_titles_for(realm_id: StringName) -> Array[TitleData]:
	var result: Array[TitleData] = []
	for title in get_all_titles():
		if title.category == TitleData.Category.REALM and title.origin_realm_id == realm_id:
			result.append(title)
	return result


## All personality titles (cross-realm character traits).
static func get_personality_titles() -> Array[TitleData]:
	var result: Array[TitleData] = []
	for title in get_all_titles():
		if title.category == TitleData.Category.PERSONALITY:
			result.append(title)
	return result


# --- Camelot Realm Titles ---

static func _build_king_of_camelot() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"king_of_camelot"
	t.category = TitleData.Category.REALM
	t.origin_realm_id = &"camelot"
	t.visual_style = RealmData.VisualStyle.HERALDIC
	t.accent_color = HERALDIC_ACCENT

	t.original_name = "King of Camelot"
	t.original_description = "The crown is yours. Shops in Camelot bow to their ruler. (-30% prices)"
	t.original_value = 30

	t.degraded_name = "A King Abroad"
	t.degraded_description = "Your crown is another realm's, and merchants here still warm to it. (-12% shop prices)"
	t.degraded_value = 12

	t.returning_name = "Former King"
	t.returning_description = "Camelot remembers what you were. Some doors still open for you. (-20% shop prices)"
	t.returning_value = 20

	t.passive_effect = TitleData.EffectType.SHOP_DISCOUNT_PERCENT
	t.passive_scales_with_tier = true
	return t


static func _build_camelots_champion() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"camelots_champion"
	t.category = TitleData.Category.REALM
	t.origin_realm_id = &"camelot"
	t.visual_style = RealmData.VisualStyle.HERALDIC
	t.accent_color = HERALDIC_ACCENT

	t.original_name = "Camelot's Champion"
	t.original_description = "Sworn to serve, not to rule. The realm fortifies its protector. (+15 max HP)"
	t.original_value = 15

	t.degraded_name = "Wandering Advisor"
	t.degraded_description = "A scholar of strange courts. Your counsel is worth something even here. (+6 max HP)"
	t.degraded_value = 6

	t.returning_name = "Returned Champion"
	t.returning_description = "Camelot welcomes back its sword. (+10 max HP)"
	t.returning_value = 10

	t.passive_effect = TitleData.EffectType.MAX_HP_BONUS
	t.passive_scales_with_tier = true
	return t


## The realm's signature title, off the Excalibur quest at the centre of the map. Its bonus is
## applied inside deal_damage on the same line as Strength, so it is per HIT and not per card:
## a multi-hit card adds it once per hit. That is intended, and it is the only per-hit damage
## source in the game, which is what earns it the top tier.
##
## The flat +3 was never measured (the harness excluded it by comment), and its real problem was
## not its ceiling but its floor: it made the EARLY turns easier, and fights are decided in the
## first three or four. So the bonus now doubles on a doubling timer, +1 on turn 1, +2 from turn
## 2, +4 from turn 4, +8 from turn 8, capped at three doublings and reset every combat. A
## four-turn regular averages about +2.25 a hit, which is weaker than the flat version; a
## twelve-turn boss averages about +5 with the tail at +8, which is stronger, and only there.
## Weak where the game is decided, legendary where a legendary sword should feel it.
##
## The escalation is ORIGINAL tier only, gated in code, because the one-integer tier schema can
## express a smaller number but not a different SHAPE. Degraded and Returning keep a flat bonus
## at their own values.
static func _build_swords_bearer() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"swords_bearer"
	t.category = TitleData.Category.REALM
	t.origin_realm_id = &"camelot"
	t.visual_style = RealmData.VisualStyle.HERALDIC
	t.accent_color = HERALDIC_ACCENT

	t.original_name = "The Sword's Bearer"
	t.original_description = ("The blade answers to how you hold it, as edge, or as eye. It wakes "
		+ "as a fight runs long: +1 damage per hit, doubling on turns 2, 4 and 8.")
	t.original_value = 1

	t.degraded_name = "Vagrant of Renown"
	t.degraded_description = "Even far from Camelot, the weight of the sword's memory lends your strikes purpose. (+1 damage)"
	t.degraded_value = 1

	t.returning_name = "Returned Bearer"
	t.returning_description = "You stand again where the stone once stood. (+2 damage)"
	t.returning_value = 2

	t.passive_effect = TitleData.EffectType.DAMAGE_BONUS_FLAT
	t.passive_scales_with_tier = true
	return t


# --- Yggdrasil Realm Titles ---

## Earned at the mound on Yggdrasil's edge by paying the debt with your own word: a lighter version of
## what the ring does. Its text is a draft for review, and its values are placeholders.
static func _build_guest_of_the_hall() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"guest_of_the_hall"
	t.category = TitleData.Category.REALM
	t.origin_realm_id = &"yggdrasil"
	t.visual_style = RealmData.VisualStyle.RUNIC
	t.accent_color = RUNIC_ACCENT

	t.original_name = "Guest of the Hall"
	t.original_description = ("You swore the guest's oath at the empty seat. Half of the first Block you "
		+ "gain each fight cannot be stripped.")
	t.original_value = 50

	t.degraded_name = "A Guest Abroad"
	t.degraded_description = "The hall is a long way off. A quarter of the first Block you gain each fight cannot be stripped."
	t.degraded_value = 25

	t.returning_name = "A Guest Returned"
	t.returning_description = "You stand again under the root. Half of the first Block you gain each fight cannot be stripped."
	t.returning_value = 50

	t.passive_effect = TitleData.EffectType.FIRST_BLOCK_KEPT
	t.passive_scales_with_tier = true
	return t


# --- Personality Titles (no degradation) ---

## Earned by walking away from the Sword in the Stone. The starter concept was clearing Camelot
## without engaging the central quest, which would only be known at the end of the act, and a
## title handed over after the last fight is a line of text. Leaving the sword is the moment
## that concept becomes true: the crown needs Excalibur, so a keeper who walks past the stone
## leaves no king behind, and the stone sits on every map, so every run can earn it. One refusal
## in one choice pays a +2, and the pay is a sellsword's: gold for each fight.
static func _build_outlander_of_camelot() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"outlander_of_camelot"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""  # Personality titles aren't tied to a realm
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "Outlander"
	t.original_description = ("You left the sword in its stone and took nothing from Camelot but "
		+ "what the fighting paid. Gain 5 gold after each combat.")
	t.original_value = 5

	t.passive_effect = TitleData.EffectType.GOLD_ON_COMBAT_END
	t.passive_scales_with_tier = false
	return t


## Mercy pays out on the dying rather than on the aftermath. It was heal 3 after each combat,
## a flat always-on with nothing to play around; per-death it pays 3 on a solo elite and 9 on a
## three-body fight, so its value depends on what is in front of you. It resolves IN combat, on
## the death, which makes kill order a real decision: focusing a weak body down early starts
## the healing sooner, and that decision is the whole reason to prefer this to a lump at the
## end. It pays least where healing matters most, since bosses are single bodies, and that is
## deliberate: it keeps the cheapest title from becoming a universal sustain crutch.
static func _build_the_merciful() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_merciful"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Merciful"
	t.original_description = "You spared those you didn't have to. Heal 3 HP each time an enemy dies."
	t.original_value = 3

	t.passive_effect = TitleData.EffectType.HEAL_ON_ENEMY_DEATH
	t.passive_scales_with_tier = false
	return t


## A second kindness title, split off from The Merciful so a run's repeat good-acts aren't wasted
## on a title you already hold. Where mercy is sparing a life in peril, grace is generosity given
## freely: paying a stranger's debt, hearing out the lonely, pardoning a village.
##
## The world puts more in front of you because you put more in front of it. This is the only
## title that touches rewards, it carries no combat power at all, and its value depends on how
## specific the build is: a focused deck wants the wider net most, which is the latent axis
## doing real work. It was +5 max HP, which duplicated Camelot's Champion's lane and was pure
## immediate power, and worse, its own grant site paid max HP twice. Personality; never
## degrades.
static func _build_the_gracious() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_gracious"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Gracious"
	t.original_description = ("You met need with open hands when you didn't have to. "
		+ "Card rewards offer one more card to choose from.")
	t.original_value = 1

	t.passive_effect = TitleData.EffectType.CARD_REWARD_CHOICES
	t.passive_scales_with_tier = false
	return t


static func _build_the_calculating() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_calculating"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Calculating"
	t.original_description = "You took the long view when others reacted. Gain 2 block at the start of each turn."
	t.original_value = 2

	t.passive_effect = TitleData.EffectType.BLOCK_ON_TURN_START
	t.passive_scales_with_tier = false
	return t


## Earned at the Last Cart Out, for getting under the miller's axle and lifting until the square
## is empty, and only there: The Reliquary pays The Unfading now. It landed on one of the three
## sites that used to grant The Merciful, so the kindness lane got less repetitive in the same
## move. Deliberately distinct from mercy's per-death mend: compassion
## here is a CLUTCH heal, catching you the first time a fight drives you below half HP, which is
## what carrying other people through a bad day leaves you with. Personality; never degrades.
static func _build_the_compassionate() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_compassionate"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Compassionate"
	t.original_description = "The first time you would drop below half HP each combat, heal 8."
	t.original_value = 8

	t.passive_effect = TitleData.EffectType.CLUTCH_HEAL
	t.passive_scales_with_tier = false
	return t


## The Reliquary's grant, for holding on to a memory while the chapel tried to take it, through
## the fight the holding costs. The event's subject is a thing that refuses to fade, and the
## mechanical form of that is a card you spend that refuses to be spent: the first card you play
## each combat comes back to your hand. The card comes back and the energy does not, so the gain
## is one paid extra play a fight, which is why it is a +4 and not a +6.
##
## Spent things stay spent. A card that exhausts does not come back, which keeps the memory cards
## one-shot, and neither does a Power (it is used up into its lasting effect, and one played twice
## would be a doubled engine) or a companion's Trick card. The echo belongs to the FIRST card
## played, whatever it is, so leading with a spent card wastes it: the opening play is the
## decision, and that is the title's latent half. Personality; never degrades.
static func _build_the_unfading() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_unfading"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Unfading"
	t.original_description = ("You held on to what the chapel meant to take. The first card you "
		+ "play each combat returns to your hand. A card that exhausts, or a Power, is spent and "
		+ "does not come back.")
	t.original_value = 1

	t.passive_effect = TitleData.EffectType.FIRST_CARD_RETURNS
	t.passive_scales_with_tier = false
	return t


## Earned the moment folk standing crosses PEOPLES_CHAMPION_THRESHOLD, which the pledge plus
## one pro-folk act will do, so it arrives mid-act with nodes left to spend it on. It used to be
## granted after the boss, which in a one-act demo meant a route title handed over on the ending
## screen with no route left. Earning it before the crown scene also makes that scene a real
## trade: the crown is something you take INSTEAD of what you already are.
##
## A personality trait, not a realm office. It doesn't fade when you leave Camelot, because it
## is who you are and not a post you held. It was heal 4 after each combat, one point off The
## Merciful in the same lane and strictly dominating it, which wasted the rarest grant in the
## game on an upgrade to a common title. Now it lives where its fiction always was: the people
## tend their champion, so the villages host him, and a night under their roof is worth two.
## Mended AND seen to his gear, which means a player wearing it needs no sustain title and the
## other slot goes to a fighting title.
static func _build_peoples_champion() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"peoples_champion"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = PEOPLES_ACCENT

	t.original_name = "The People's Champion"
	t.original_description = ("You stood with the common folk and would not be made their king. "
		+ "The villages host you: a rest site grants both its choices.")
	t.original_value = 1

	t.passive_effect = TitleData.EffectType.REST_TAKES_BOTH
	t.passive_scales_with_tier = false
	return t
