class_name CombatFlagEffect
extends CardEffect
## Raises a named flag on the combat (CombatEngine.raise_flag) for another card to read and spend
## (DamageEffect.bonus_when FLAG). The hawk's Wait On and Throw Up raise &"waiting_on", which its
## Stoop spends for a doubled hit. A flag already up stays up and nothing else happens, which is
## what makes a banked second Wait On worthless: the stockpile answers itself. Cleared with the
## fight. `text` is how the raising reads on the card.

@export var flag: StringName = &""
@export var text: String = ""


func apply(_source, _target, battle_state) -> void:
	if battle_state and battle_state.has_method("raise_flag"):
		battle_state.raise_flag(flag)


func get_description() -> String:
	return text
