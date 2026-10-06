class_name HealEffect
extends CardEffect
## Heals the player for the given value — or, when apply_to_source is set, the
## combatant performing the effect (an enemy mending itself).

## True = heal the source combatant through the engine (the Hollow Prelate's self-
## heal). False = heal the run's player HP (the default, for player cards/relics).
@export var apply_to_source: bool = false


func apply(source, _target, battle_state) -> void:
	if apply_to_source:
		if battle_state:
			battle_state.heal_combatant(source, value)
		return
	RunManager.heal(value)


func get_description() -> String:
	return "Heal %d HP." % value
