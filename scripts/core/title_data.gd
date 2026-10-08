class_name TitleData
extends Resource
## Defines a title: the player's reputation and identity layer.
## Earned through major narrative moments, worn in one of two title slots.
## See docs/GAME_DESIGN.md § Titles for the design framework.

## Where a title came from determines whether and how it degrades.
enum Category {
	REALM,        # Tied to a specific realm; degrades when in foreign realms
	PERSONALITY,  # Tied to character actions; travels with you, never degrades
}

## A title's current power tier. Realm titles can cycle through all three.
## Personality titles always use ORIGINAL.
enum Tier {
	ORIGINAL,    # Full power; in the realm of origin, or right after earning
	DEGRADED,    # Reduced power; when in foreign realms
	RETURNING,   # Intermediate power; earned by returning to origin without reclaiming
}

## Mechanical effect types titles can grant.
## Start small; extend as new title designs require new effect types.
enum EffectType {
	NONE,
	SHOP_DISCOUNT_PERCENT,  # value = % discount on shop prices (0-100)
	BLOCK_ON_TURN_START,    # value = block granted at start of each player turn
	DAMAGE_BONUS_FLAT,      # value = flat damage added to player attacks
	MAX_HP_BONUS,           # value = bonus max HP while equipped
	GOLD_ON_COMBAT_END,     # value = bonus gold awarded after each combat
	HEAL_ON_COMBAT_END,     # value = HP healed after each combat
	CLUTCH_HEAL,            # value = HP healed the first time you drop below half HP in a combat
}

@export var title_id: StringName = &""
@export var category: Category = Category.PERSONALITY
@export var origin_realm_id: StringName = &""  # Empty for personality titles
@export var visual_style: RealmData.VisualStyle = RealmData.VisualStyle.NEUTRAL
@export var accent_color: Color = Color(0.85, 0.78, 0.55)

# --- Tier-specific data ---
# For personality titles, only the Original fields are used and the title
# always uses Tier.ORIGINAL. The Degraded/Returning fields below are ignored.

@export_group("Original (full power)")
@export var original_name: String = ""
@export_multiline var original_description: String = ""
@export var original_value: int = 0

@export_group("Degraded (foreign realm)")
@export var degraded_name: String = ""
@export_multiline var degraded_description: String = ""
@export var degraded_value: int = 0

@export_group("Returning (returned without reclamation)")
@export var returning_name: String = ""
@export_multiline var returning_description: String = ""
@export var returning_value: int = 0

# --- Mechanical effect ---

@export_group("Passive Effect")
@export var passive_effect: EffectType = EffectType.NONE
## When true, the passive's value scales with the current tier
## (original_value / degraded_value / returning_value). When false the
## passive uses original_value at all tiers (rare; mostly for narrative titles).
@export var passive_scales_with_tier: bool = true

@export_group("Active Effect")
## Titles may grant a usable active ability in addition to (or instead of) a passive.
@export var has_active: bool = false
@export var active_effect: EffectType = EffectType.NONE
@export var active_value: int = 0
@export var active_uses_per_combat: int = 1
@export_multiline var active_description: String = ""


# --- Convenience accessors ---

## Returns the display name for the given tier.
func get_name_for_tier(tier: Tier) -> String:
	match tier:
		Tier.ORIGINAL:
			return original_name
		Tier.DEGRADED:
			return degraded_name if degraded_name != "" else original_name
		Tier.RETURNING:
			return returning_name if returning_name != "" else original_name
		_:
			return original_name


## Returns the description for the given tier.
func get_description_for_tier(tier: Tier) -> String:
	match tier:
		Tier.ORIGINAL:
			return original_description
		Tier.DEGRADED:
			return degraded_description if degraded_description != "" else original_description
		Tier.RETURNING:
			return returning_description if returning_description != "" else original_description
		_:
			return original_description


## Returns the effect value for the given tier.
## For personality titles or titles that don't scale, always returns original_value.
func get_value_for_tier(tier: Tier) -> int:
	if category == Category.PERSONALITY or not passive_scales_with_tier:
		return original_value
	match tier:
		Tier.ORIGINAL:
			return original_value
		Tier.DEGRADED:
			return degraded_value
		Tier.RETURNING:
			return returning_value
		_:
			return original_value


## True if this is a realm title (can degrade) versus a personality title (cannot).
func is_realm_title() -> bool:
	return category == Category.REALM
