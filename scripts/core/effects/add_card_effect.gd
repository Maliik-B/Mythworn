class_name AddCardEffect
extends CardEffect
## Injects a copy of `card_to_add` into the player's draw pile. Used by enemies that
## pollute your deck mid-combat (Realm Shade's Corruption). Foreshadows the Act-3
## mirror-curse mechanic, which reuses this + CardData.unplayable.
##
## A fresh duplicate is inserted so piles never share a mutable card instance
## (Godot #74918). The injected card lives only for this combat.

@export var card_to_add: CardData
## When true the copy drops into the discard pile (StS "Anger" self-replication,
## e.g. Inner Fire) instead of shuffling into the draw pile (the Corruption curse).
@export var to_discard: bool = false


func apply(_source, _target, battle_state) -> void:
	if card_to_add and battle_state.has_method("add_card_to_pile"):
		battle_state.add_card_to_pile(card_to_add.duplicate_card(), to_discard)


func get_description() -> String:
	if not card_to_add:
		return "Shuffle a Corruption into your draw pile."
	if to_discard:
		return "Add a copy of %s to your discard pile." % card_to_add.card_name
	return "Shuffle a %s into your draw pile." % card_to_add.card_name
