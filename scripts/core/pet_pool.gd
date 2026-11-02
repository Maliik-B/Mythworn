class_name PetPool
## Builds companions by id and hands out their decks. A pet's cards are Trick cards: the keyword
## (CardData.trick) means the card comes from a companion, never enters the deck, and leaves play
## when it resolves. An unplayed Trick card vanishes at the end of the turn by default; one card
## per pet may instead be bankable (CardData.retain), and its answer to "if this can be held, what
## stops a five-turn stockpile?" is that it wants a moment and the deck cycle hands over one every
## four turns. Each pet's deck comes from one reliable identity, the way the animal hunts, not
## from a verb list: the hound is the pack, the hawk is the stoop, the ferret is the warren.
## Every number here is PROVISIONAL (part 3b of the demo road); the harness models pets in part 4.


## Returns the pet with this id, or null for an unknown id (and for &"", meaning none).
static func get_pet(id: StringName) -> PetData:
	match id:
		&"hound":
			return _hound()
		&"hawk":
			return _hawk()
		&"ferret":
			return _ferret()
	return null


## Every pet id, in a stable order (tests, tooling, the huntsman's stock).
static func all_ids() -> Array[StringName]:
	return [&"hound", &"hawk", &"ferret"]


## A fresh copy of every card in this pet's deck. Fresh each call: an arriving card is an
## instance of its own, played or vanished without touching the others.
static func build_cards(id: StringName) -> Array[CardData]:
	match id:
		&"hound":
			return CardPool.build_hound_cards()
		&"hawk":
			return CardPool.build_hawk_cards()
		&"ferret":
			return CardPool.build_ferret_cards()
	return []


## The hunting hound: the pack. It holds a quarry at bay, harries it, wears it down and pulls it
## down once it is tired. The one that waited at the Tiltyard gate is grey in the muzzle; the
## huntsman's are his lord's. A thing the rot subtracted around rather than took, since the men
## went and the dogs did not.
static func _hound() -> PetData:
	var p := PetData.new()
	p.id = &"hound"
	p.display_name = "The Hound"
	p.description = ("A hunting hound, lean and working, grey in the muzzle. Every turn it brings "
		+ "you a card. The pack's way is to hold a quarry, wear it down and pull it down tired.")
	p.realm_id = &"camelot"
	return p


## The peregrine: the stoop. A longwing flown high, it waits on until it is a speck and comes
## straight down through whatever guard there is. An earl's bird in the Boke of St Albans; the
## huntsman's lord would have flown one.
static func _hawk() -> PetData:
	var p := PetData.new()
	p.id = &"hawk"
	p.display_name = "The Hawk"
	p.description = ("A peregrine, carried on the fist in jesses. Every turn it brings you a card. "
		+ "It waits on high and comes down through the guard.")
	p.realm_id = &"camelot"
	return p


## The warrener's ferret: the warren. It goes in where nothing else fits and bolts the quarry
## into the open, where the net is already waiting. Quick, long and a little absurd.
static func _ferret() -> PetData:
	var p := PetData.new()
	p.id = &"ferret"
	p.display_name = "The Ferret"
	p.description = ("A warrener's ferret, long and quick and a little absurd. Every turn it "
		+ "brings you a card. It goes in where nothing else fits and bolts the quarry into the open.")
	p.realm_id = &"camelot"
	return p
