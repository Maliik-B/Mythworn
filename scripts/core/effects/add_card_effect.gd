class_name AddCardEffect
extends CardEffect
## Injects a copy of `card_to_add` into the player's draw pile. Used by enemies that
## pollute your deck mid-combat (Realm Shade's Corruption). Foreshadows the Act-3
## mirror-curse mechanic, which reuses this + CardData.unplayable.
##
## A fresh duplicate is inserted so piles never share a mutable card instance
## (Godot #74918). The injected card lives only for this combat.

@export var card_to_add: CardData
## Names a card for CardPool.build_card to make fresh on every apply, used in place of
## card_to_add by a card that adds copies of itself (Inner Fire). card_to_add cannot do that
## job: pointing it at the card that carries this effect makes card -> effect -> card, a
## reference cycle, and refcounted resources in a cycle are never freed.
@export var card_id: StringName = &""
## When true the copy drops into the discard pile (StS "Anger" self-replication,
## e.g. Inner Fire) instead of shuffling into the draw pile (the Corruption curse).
@export var to_discard: bool = false


func apply(_source, _target, battle_state) -> void:
	var card: CardData = null
	if card_id != &"":
		card = CardPool.build_card(card_id)
	elif card_to_add:
		card = card_to_add.duplicate_card()
	if card and battle_state.has_method("add_card_to_pile"):
		battle_state.add_card_to_pile(card, to_discard)


func get_description() -> String:
	var source: CardData = CardPool.build_card(card_id) if card_id != &"" else card_to_add
	if not source:
		return "Shuffle a Corruption into your draw pile."
	if to_discard:
		return "Add a copy of %s to your discard pile." % source.card_name
	return "Shuffle a %s into your draw pile." % source.card_name
