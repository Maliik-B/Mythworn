class_name StatusApplyEffect
extends CardEffect
## Applies a status effect to the target with the given number of stacks.

@export var status_effect: StatusEffectData
@export var apply_to_source: bool = false # True = buff self, false = debuff target
## True = apply to every living enemy combatant (self + allies). For support enemies
## that empower the group (e.g. the Court Conspirator rallying his companions). Takes
## precedence over apply_to_source. Player cards never set this.
@export var apply_to_allies: bool = false


func apply(source, target, battle_state) -> void:
	if apply_to_allies:
		for e in battle_state.enemies:
			if not e.stats.is_dead():
				battle_state.apply_status_effect(e.stats, status_effect, value)
		return
	var recipient = source if apply_to_source else target
	battle_state.apply_status_effect(recipient, status_effect, value)


func get_description() -> String:
	if not status_effect:
		return ""
	# Negative stacks read as a reduction ("Reduce 2 Strength") rather than the
	# awkward "Apply -2 Strength" — used by debuffs that soak enemy Strength.
	if value < 0:
		return "Reduce %d %s." % [-value, status_effect.effect_name]
	if apply_to_allies:
		return "Allies gain %d %s." % [value, status_effect.effect_name]
	var target_text = "Gain" if apply_to_source else "Apply"
	return "%s %d %s." % [target_text, value, status_effect.effect_name]
