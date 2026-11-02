class_name DiscardToHandEffect
extends CardEffect
## Returns N random cards from the discard pile to the player's hand (CombatEngine
## recall_from_discard). The ferret's Dig: whatever you threw away was only ever underneath.
## Mirrors ExhaustToHandEffect, which digs in the exhaust pile instead. Fewer cards than `value`
## in the pile returns as many as there are; the pick is on RngManager.deck_rng so seeded runs
## replay identically.


func apply(_source, _target, battle_state) -> void:
	if not battle_state.has_method("recall_from_discard"):
		return
	battle_state.recall_from_discard(value)


func get_description() -> String:
	if value == 1:
		return "Return a random card from your discard pile to your hand."
	return "Return %d random cards from your discard pile to your hand." % value
