class_name StatusApplyEffect
extends CardEffect
## Applies a status effect to the target with the given number of stacks.

@export var status_effect: StatusEffectData
@export var apply_to_source: bool = false # True = buff self, false = debuff target


func apply(source, target, battle_state) -> void:
	var recipient = source if apply_to_source else target
	battle_state.apply_status_effect(recipient, status_effect, value)


func get_description() -> String:
	if not status_effect:
		return ""
	# Negative stacks read as a reduction ("Reduce 2 Strength") rather than the
	# awkward "Apply -2 Strength" — used by debuffs that soak enemy Strength.
	if value < 0:
		return "Reduce %d %s." % [-value, status_effect.effect_name]
	var target_text = "Gain" if apply_to_source else "Apply"
	return "%s %d %s." % [target_text, value, status_effect.effect_name]
