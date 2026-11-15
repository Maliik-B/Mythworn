class_name ExhaustToHandEffect
extends CardEffect
## Returns N random cards from the exhaust pile back to the player's hand.
## Used by Emo Hybrid's "Recall", magic that surfaces fragments of what was lost.
##
## If the exhaust pile is empty or has fewer cards than `value`, returns as
## many as are available. Selection is deterministic via RngManager.deck_rng
## so seeded runs replay identically.


func apply(_source, _target, battle_state) -> void:
	if not battle_state.has_method("recall_from_exhaust"):
		# Engine doesn't support this op; fall through silently.
		# (Unreachable in production but keeps the effect safe to test in
		# isolation against a mock engine.)
		return
	battle_state.recall_from_exhaust(value)


func get_description() -> String:
	if value == 1:
		return "Return a random card from your exhaust pile to your hand."
	return "Return %d random cards from your exhaust pile to your hand." % value
