class_name TitleData
extends Resource
## Defines a title: the player's reputation and identity layer.
## Earned through major narrative moments, worn in one of two title slots.

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
	SKIP_NODE,              # value = map nodes one charge passes over (active only)
	CARD_REWARD_CHOICES,    # value = extra card options offered at a card reward
	HEAL_ON_ENEMY_DEATH,    # value = HP healed each time an enemy dies, resolved in combat
	REST_TAKES_BOTH,        # value > 0 = a rest site grants both its choices, not one
	FIRST_CARD_RETURNS,     # value > 0 = the first card played each combat returns to hand
	FIRST_BLOCK_KEPT,       # value = % of the first Block gained each fight a strip cannot take
}


## Where an active title's charge is spent: the unit of play one use covers.
## Scope and period are separate axes. "One shot, N uses, cooldown" conflates them,
## which is why the old active_uses_per_combat field could only express one cell of
## the grid (scope and period both per-combat) and could not express a node skip that
## comes back each act.
enum ActiveScope {
	COMBAT,  # spent inside a fight
	NODE,    # spent on the map, against a node
	ACT,     # spent once somewhere in the act
	RUN,     # spent once in the run
}

## How often an active title's charges come back.
enum ActivePeriod {
	NEVER,   # one-shot; what is spent is gone for the run
	COMBAT,  # refreshes at the start of each fight
	ACT,     # refreshes at the start of each act (the default; it is self-correcting,
	         # because an unspent charge walking into the act boss is visibly wasted)
	REALM,   # refreshes on entering a realm
	RUN,     # refreshes once per run, so effectively at run start
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
## Unlike the passive, the active block does NOT scale with tier: get_value_for_tier
## returns one integer, so a tier can only differ in magnitude, and the interesting
## degradation for a charge title is in its PERIOD (refreshes at home, does not refresh
## abroad, comes back on reclamation). The schema has no room for that yet, which is the
## second reason the first consumable is a personality title.
@export var has_active: bool = false
@export var active_effect: EffectType = EffectType.NONE
@export var active_value: int = 0
## Charges granted per period, and the two axes that say what a charge is for.
@export var active_charges: int = 1
@export var active_scope: ActiveScope = ActiveScope.COMBAT
@export var active_period: ActivePeriod = ActivePeriod.ACT
@export_multiline var active_description: String = ""
## The line shown when the charge is actually spent. Lives on the title so a new
## consumable ships its own voice instead of needing a branch in map_scene.
@export_multiline var use_flavor: String = ""


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


## True if this title carries a spendable active, as opposed to a polled passive.
func has_active_effect() -> bool:
	return has_active and active_effect != EffectType.NONE and active_charges > 0
