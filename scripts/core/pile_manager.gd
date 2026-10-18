class_name PileManager
extends RefCounted
## Manages the four card piles during combat: draw, hand, discard, exhaust.
## Pure data operations — no signals. The CombatEngine handles events.

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []


## Copy the run's deck into the draw pile and shuffle.
func setup(deck: Array[CardData]) -> void:
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	for card in deck:
		draw_pile.append(card)
	shuffle_draw_pile()


func shuffle_draw_pile() -> void:
	RngManager.shuffle(draw_pile, RngManager.deck_rng)


## Draw a single card. Reshuffles discard into draw if empty.
func draw_card() -> CardData:
	if draw_pile.is_empty():
		reshuffle_discard_into_draw()
	if draw_pile.is_empty():
		return null
	var card = draw_pile.pop_back()
	hand.append(card)
	return card


func draw_cards(count: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	for i in count:
		var card = draw_card()
		if card:
			drawn.append(card)
	return drawn


func discard_card(card: CardData) -> void:
	hand.erase(card)
	discard_pile.append(card)


func discard_hand() -> void:
	# Retained cards persist into the next turn; everything else goes to discard.
	var kept: Array[CardData] = []
	for card in hand:
		if card.retain:
			kept.append(card)
		else:
			discard_pile.append(card)
	hand.assign(kept)


func exhaust_card(card: CardData) -> void:
	hand.erase(card)
	exhaust_pile.append(card)


func reshuffle_discard_into_draw() -> void:
	draw_pile.append_array(discard_pile)
	discard_pile.clear()
	shuffle_draw_pile()


## Shuffles a card into the draw pile at a random position (deterministic via
## deck_rng). Used by enemies that pollute your deck mid-combat (Realm Shade's
## Corruption). The card is per-combat only; it never touches the run deck.
func add_card_to_draw(card: CardData) -> void:
	var pos = RngManager.deck_rng.randi_range(0, draw_pile.size())
	draw_pile.insert(pos, card)


## Drops a card onto the discard pile. Used by Anger-style self-replication
## (Inner Fire): the fresh copy waits in discard until the next reshuffle rather
## than immediately re-entering the draw pile.
func add_card_to_discard(card: CardData) -> void:
	discard_pile.append(card)
