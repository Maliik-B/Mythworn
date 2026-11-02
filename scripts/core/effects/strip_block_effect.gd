class_name StripBlockEffect
extends CardEffect
## Removes every point of the target's Block (CombatEngine.strip_block). The hawk's Bind: it takes
## the quarry in the air and the guard comes down with it. Put it before a damage effect on the
## same card so the hit that follows lands on HP.


func apply(_source, target, battle_state) -> void:
	if battle_state and target:
		battle_state.strip_block(target)


func get_description() -> String:
	return "Remove all of its Block."
