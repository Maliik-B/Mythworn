class_name DamageEffect
extends CardEffect
## Deals damage to the target. Respects block and damage modifiers (Vulnerable, Weak).

@export var hits: int = 1 # For multi-hit attacks


func apply(source, target, battle_state) -> void:
	var total_hits := hits
	# Overflow power: at Blazing, the player's multi-hit attacks strike extra times.
	# (Enemies never hold powers, so this is a no-op for their attacks.)
	if hits > 1 and source and source.has_power(Powers.OVERFLOW) \
			and RunManager.get_passion_tier() == PassionState.Tier.BLAZING:
		total_hits += source.get_power_stacks(Powers.OVERFLOW)
	for i in total_hits:
		battle_state.deal_damage(target, value, source)


func get_description() -> String:
	if hits > 1:
		return "Deal %d damage %d times." % [value, hits]
	return "Deal %d damage." % value


## Returns description with combat modifiers shown as base [modified]. Includes the
## target's Vulnerable (×1.5) when a target is supplied — e.g. while dragging the card
## onto an enemy — so the bracket shows the real number, composing with Strength/Weak.
func get_modified_description(source: CombatantStats, target: CombatantStats = null) -> String:
	var modified = value
	if source:
		modified += source.get_status_stacks(StatusEffects.STRENGTH)
		if source.has_status(StatusEffects.WEAK):
			modified = int(modified * 0.75)
	if target and target.has_status(StatusEffects.VULNERABLE):
		modified = int(modified * 1.5)
	modified = maxi(0, modified)
	if modified != value:
		if hits > 1:
			return "Deal %d [%d] damage %d times." % [value, modified, hits]
		return "Deal %d [%d] damage." % [value, modified]
	return get_description()
