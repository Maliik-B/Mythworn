class_name CardEffect
extends Resource
## Base class for all card (and enemy move) effects.
## Subclass this and override apply() to create new effect types.
## Cards and enemy moves compose arrays of these to define their behavior.

@export var value: int = 0


func apply(_source, _target, _battle_state) -> void:
	pass


func get_description() -> String:
	return ""


## `zone_mult` is the Passion zone damage multiplier for the owning card's personality
## (1.0 = no zone). Only damage effects use it; block/status effects ignore it, since the
## zone modifies attack damage only. Threaded from CardData.get_modified_description.
func get_modified_description(_source: CombatantStats, _target: CombatantStats = null,
		_zone_mult: float = 1.0) -> String:
	return get_description()
