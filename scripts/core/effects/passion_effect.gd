class_name PassionEffect
extends CardEffect
## Modifies the player's Passion. Positive values increase, negative decrease.
## Passion changes are adjusted by the character's volatility in RunManager.


func apply(_source, _target, _battle_state) -> void:
	RunManager.change_passion(value)


func get_description() -> String:
	if value > 0:
		return "+%d Passion." % value
	return "%d Passion." % value


## The words on an all-enemies card: its Passion counts once for every enemy the card hits, and
## kills count, so the number printed is the amount for one enemy.
func get_per_enemy_description() -> String:
	return get_description().trim_suffix(".") + " per enemy."
