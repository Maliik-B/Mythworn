class_name DrawEffect
extends CardEffect
## Draws cards from the draw pile into the hand.

## Run-persistent decay: each time this effect resolves, its draw count drops by this
## much (floored at 0). The memory card "The Name I Gave Myself" forgets itself across a
## run: `value` mutates on the deck's own card instance, so the decay persists between
## combats and resets only on a fresh run (a new grant builds a fresh instance). 0 = a
## normal, non-decaying draw.
@export var decay_per_play: int = 0


func apply(_source, _target, battle_state) -> void:
	if battle_state.has_method("draw_cards"):
		battle_state.draw_cards(value)
	# Draw first, then forget: this play used the current count; the next draws one fewer.
	if decay_per_play > 0 and value > 0:
		value = maxi(0, value - decay_per_play)


func get_description() -> String:
	var note := " Each time I play it, it draws 1 fewer." if decay_per_play > 0 else ""
	if value <= 0:
		# Only reachable on a decaying draw that has run dry.
		return "Draw no cards. The memory has faded."
	if value == 1:
		return "Draw a card.%s" % note
	return "Draw %d cards.%s" % [value, note]
