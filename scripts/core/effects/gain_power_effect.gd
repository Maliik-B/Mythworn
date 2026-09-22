class_name GainPowerEffect
extends CardEffect
## Grants a persistent character POWER to the player (the payload of a POWER card).
## The power's per-turn behavior is handled by CombatEngine._process_powers.

@export var power: PowerData
@export var stacks: int = 1


func apply(source, _target, _battle_state) -> void:
	if power:
		source.add_power(power, stacks)


func get_description() -> String:
	if not power:
		return ""
	# StS "Power:" prefix so it reads as a persistent effect, not a one-shot.
	return "Power: %s" % power.description
