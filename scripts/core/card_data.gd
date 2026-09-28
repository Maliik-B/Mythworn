class_name CardData
extends Resource
## Defines a single card's properties. Cards are composed of CardEffect arrays.
## Create .tres files from this resource to define individual cards.

enum CardType { ATTACK, SKILL, POWER }
enum CardRarity { STARTER, COMMON, UNCOMMON, RARE }
enum TargetType { SINGLE_ENEMY, ALL_ENEMIES, SELF, NONE }
enum PersonalityType { PRIMARY, SECONDARY, NEUTRAL, NEGATIVE }

@export var card_name: String = ""
@export var energy_cost: int = 1
@export_multiline var description: String = ""
@export_multiline var flavor_text: String = ""  # Italicized lore beneath the description; optional
@export var card_type: CardType = CardType.ATTACK
@export var rarity: CardRarity = CardRarity.COMMON
@export var target_type: TargetType = TargetType.SINGLE_ENEMY
@export var personality: PersonalityType = PersonalityType.NEUTRAL
## The card's SCHOOL — which pole's SYMBOL it wears (≈ Water / ⚔ Physical), independent of
## `personality` (which drives the zone). For a committed pole card this equals its
## personality. For a NEUTRAL card that fits a pole's style but is passion-neutral for zone
## purposes, set this to the fitting pole so it still wears a symbol. NEUTRAL here = no symbol.
@export var school: PersonalityType = PersonalityType.NEUTRAL
@export var effects: Array[CardEffect] = []
@export var exhaust: bool = false
## X-cost card (StS "X"): on play it spends ALL remaining energy, and its x_scaled
## effects repeat once per energy spent (X = energy on cast). energy_cost stays 0 so
## can_play_card always admits it; the engine reads the live energy as X. UI shows "X".
@export var x_cost: bool = false
## Unplayable cards (curses / status) sit dead in hand: they can't be played, they
## just clog your options. Enemies like Realm Shade inject these mid-combat, and the
## Act-3 mirror-curses will reuse the same flag.
@export var unplayable: bool = false
## Retained cards stay in hand at end of turn instead of being discarded (StS-style
## "Retain"). The end-turn discard + its fly-to-pile animation both skip these.
@export var retain: bool = false
@export var card_art: Texture2D

# Upgrade tracking
@export var upgraded: bool = false
@export var upgrade_effects: Array[CardEffect] = [] # Effects when upgraded (replaces base effects)


## Deep copy this card for mutable per-instance state (deck building, upgrades).
## Required because Resource.duplicate(true) has bugs with Array sub-resources.
func duplicate_card() -> CardData:
	var copy = CardData.new()
	copy.card_name = card_name
	copy.energy_cost = energy_cost
	copy.description = description
	copy.flavor_text = flavor_text
	copy.card_type = card_type
	copy.rarity = rarity
	copy.target_type = target_type
	copy.personality = personality
	copy.school = school
	copy.exhaust = exhaust
	copy.x_cost = x_cost
	copy.unplayable = unplayable
	copy.retain = retain
	copy.card_art = card_art
	copy.upgraded = upgraded

	for effect in effects:
		copy.effects.append(effect.duplicate())

	for effect in upgrade_effects:
		copy.upgrade_effects.append(effect.duplicate())

	return copy


## Which pole's SYMBOL this card wears: its explicit `school` if set, else its `personality`
## if that's a pole, else NEUTRAL (no symbol). One place so the card face and any preview
## agree on the glyph. `school` lets a passion-neutral card still wear a pole's symbol.
func symbol_pole() -> PersonalityType:
	if school == PersonalityType.PRIMARY or school == PersonalityType.SECONDARY:
		return school
	if personality == PersonalityType.PRIMARY or personality == PersonalityType.SECONDARY:
		return personality
	return PersonalityType.NEUTRAL


## Upgrades this card. Uses upgrade_effects if defined, otherwise boosts base effect values.
func upgrade_card() -> void:
	if upgraded:
		return
	upgraded = true
	card_name = card_name + "+"

	if upgrade_effects.size() > 0:
		return # Will use upgrade_effects via get_active_effects()

	# Generic upgrade: boost base effect values
	for effect in effects:
		if effect is DamageEffect or effect is BlockEffect:
			effect.value += 3
		elif effect is DrawEffect or effect is EnergyEffect:
			effect.value += 1
		elif effect is StatusApplyEffect:
			effect.value += 1
		elif effect is HealEffect:
			effect.value += 3
		elif effect is PassionEffect:
			if effect.value > 0:
				effect.value += 1
			else:
				effect.value -= 1


## The energy cost to display: "X" for X-cost cards (which spend all energy on cast),
## otherwise the numeric cost. Single source so every cost ornament reads the same.
func cost_label() -> String:
	return "X" if x_cost else str(energy_cost)


## Returns the currently active effects (base or upgraded).
func get_active_effects() -> Array[CardEffect]:
	if upgraded and upgrade_effects.size() > 0:
		return upgrade_effects
	return effects


## Generates a description string from the card's effects.
func get_generated_description() -> String:
	var parts: PackedStringArray = []
	for effect in get_active_effects():
		var desc = effect.get_description()
		if desc != "":
			parts.append(desc)
	var text = " ".join(parts)
	# Cards with no effect text (e.g. an unplayable curse) fall back to their
	# authored description so the panel isn't blank.
	if text == "" and description != "":
		text = description
	if target_type == TargetType.ALL_ENEMIES:
		text += " Hits all enemies."
	return text


## Generates description with combat modifiers applied. When `target` is supplied
## (e.g. an enemy the card is being dragged onto), target-side modifiers like
## Vulnerable are folded into the damage brackets too.
func get_modified_description(source: CombatantStats, target: CombatantStats = null) -> String:
	var parts: PackedStringArray = []
	for effect in get_active_effects():
		var desc = effect.get_modified_description(source, target)
		if desc != "":
			parts.append(desc)
	var text = " ".join(parts)
	# Cards with no effect text (e.g. an unplayable curse) fall back to their
	# authored description so the panel isn't blank.
	if text == "" and description != "":
		text = description
	if target_type == TargetType.ALL_ENEMIES:
		text += " Hits all enemies."
	var zm := CombatEngine.zone_multiplier(personality)
	if zm < 1.0:
		text += " [Zone Penalty: -%d%% dmg]" % roundi((1.0 - zm) * 100.0)
	elif zm > 1.0:
		text += " [Zone Bonus: +%d%% dmg]" % roundi((zm - 1.0) * 100.0)
	return text
