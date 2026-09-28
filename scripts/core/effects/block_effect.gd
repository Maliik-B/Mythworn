class_name BlockEffect
extends CardEffect
## Grants block to the source (the card player).


func apply(source, _target, battle_state) -> void:
	battle_state.apply_block(source, value)


func get_description() -> String:
	return "Gain %d Block." % value


## Returns description with Dexterity modifier shown as base [modified]. Block is NOT
## zone-modified (the Passion zone only scales attack damage), so `_zone_mult` is ignored.
func get_modified_description(source: CombatantStats, _target: CombatantStats = null,
		_zone_mult: float = 1.0) -> String:
	var modified = value + source.get_status_stacks(StatusEffects.DEXTERITY)
	if modified != value:
		return "Gain %d [%d] Block." % [value, modified]
	return get_description()
