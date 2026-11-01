class_name PetPool
## Builds companions by id and hands out their card pools. A pet's cards are Trick cards: the
## keyword (CardData.trick) means the card comes from a companion, never enters the deck, and
## leaves play when it resolves. An unplayed Trick card vanishes at the end of the turn by
## default; a card that answers "if this can be held, what stops a five-turn stockpile?" may
## instead be bankable (CardData.retain), decided per card.
## Every number here is PROVISIONAL (part 3 of the demo road); the harness models pets in part 4.


## Returns the pet with this id, or null for an unknown id (and for &"", meaning none).
static func get_pet(id: StringName) -> PetData:
	match id:
		&"hound":
			return _hound()
	return null


## Every pet id, in a stable order (tests, tooling).
static func all_ids() -> Array[StringName]:
	return [&"hound"]


## A fresh copy of every card in this pet's pool. Fresh each call: an arriving card is an
## instance of its own, played or vanished without touching the others.
static func build_cards(id: StringName) -> Array[CardData]:
	match id:
		&"hound":
			return CardPool.build_hound_cards()
	return []


## The Camelot companion for the demo. A grey-muzzled hound that stayed at the Tiltyard gate
## for men who are not coming back: a realm-fitting pet, and a thing the rot subtracted around
## rather than took, since the men went and the dog did not.
static func _hound() -> PetData:
	var p := PetData.new()
	p.id = &"hound"
	p.display_name = "The Hound"
	p.description = ("A grey-muzzled hound that waited at the Tiltyard gate. On a chance each "
		+ "turn it brings you a card.")
	p.realm_id = &"camelot"
	p.arrival_chance = 0.4
	return p
