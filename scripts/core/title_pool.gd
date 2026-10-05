class_name TitlePool
## Builds and returns the canonical TitleData instances for V1.
## Awarding logic (which title to grant after which event) lives elsewhere —
## this class is a content registry, not a decision system.

const HERALDIC_ACCENT: Color = Color(0.78, 0.18, 0.18)    # Camelot red
const NEUTRAL_ACCENT: Color = Color(0.85, 0.78, 0.55)     # Parchment
const PEOPLES_ACCENT: Color = Color(0.82, 0.68, 0.32)     # Harvest gold (the common folk)


# --- Public API ---

## Returns every title defined for V1. Cheap to call; no I/O.
static func get_all_titles() -> Array[TitleData]:
	var titles: Array[TitleData] = []
	titles.append(_build_king_of_camelot())
	titles.append(_build_camelots_champion())
	titles.append(_build_swords_bearer())
	titles.append(_build_outlander_of_camelot())
	titles.append(_build_the_merciful())
	titles.append(_build_the_calculating())
	titles.append(_build_peoples_champion())
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

	t.degraded_name = "Distant Royal Noble"
	t.degraded_description = "Your bearing gives the air of nobility. Merchants warm to you. (-12% shop prices)"
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


static func _build_swords_bearer() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"swords_bearer"
	t.category = TitleData.Category.REALM
	t.origin_realm_id = &"camelot"
	t.visual_style = RealmData.VisualStyle.HERALDIC
	t.accent_color = HERALDIC_ACCENT

	t.original_name = "The Sword's Bearer"
	t.original_description = "The blade answers to how you hold it — as edge, or as eye. (+3 damage to all attacks)"
	t.original_value = 3

	t.degraded_name = "Vagrant of Renown"
	t.degraded_description = "Even far from Camelot, the weight of the sword's memory lends your strikes purpose. (+1 damage)"
	t.degraded_value = 1

	t.returning_name = "Returned Bearer"
	t.returning_description = "You stand again where the stone once stood. (+2 damage)"
	t.returning_value = 2

	t.passive_effect = TitleData.EffectType.DAMAGE_BONUS_FLAT
	t.passive_scales_with_tier = true
	return t


# --- Personality Titles (no degradation) ---

static func _build_outlander_of_camelot() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"outlander_of_camelot"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""  # Personality titles aren't tied to a realm
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "Outlander"
	t.original_description = "You walked through a kingdom that wasn't yours and left no king behind. Gain 5 gold after each combat."
	t.original_value = 5

	t.passive_effect = TitleData.EffectType.GOLD_ON_COMBAT_END
	t.passive_scales_with_tier = false
	return t


static func _build_the_merciful() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"the_merciful"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = NEUTRAL_ACCENT

	t.original_name = "The Merciful"
	t.original_description = "You spared those you didn't have to. Heal 3 HP after each combat."
	t.original_value = 3

	t.passive_effect = TitleData.EffectType.HEAL_ON_COMBAT_END
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


## Earned at the run's end for holding the people's line (high folk standing) through the
## realm. A personality trait, not a realm office -- it doesn't fade when you leave Camelot,
## because it's who you are, not a post you held. The people tend their champion's hurts.
static func _build_peoples_champion() -> TitleData:
	var t := TitleData.new()
	t.title_id = &"peoples_champion"
	t.category = TitleData.Category.PERSONALITY
	t.origin_realm_id = &""
	t.visual_style = RealmData.VisualStyle.NEUTRAL
	t.accent_color = PEOPLES_ACCENT

	t.original_name = "The People's Champion"
	t.original_description = "You stood with the common folk and would not be made their king. Heal 4 HP after each combat."
	t.original_value = 4

	t.passive_effect = TitleData.EffectType.HEAL_ON_COMBAT_END
	t.passive_scales_with_tier = false
	return t
