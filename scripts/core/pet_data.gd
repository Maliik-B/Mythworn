class_name PetData
extends RefCounted
## A companion: a source with its own card pool, selected by id. The pet does not play a card, it
## GIVES you one. On a chance each player turn a card from its pool arrives in hand, where it
## obeys every normal rule for a card: it costs energy, it competes with the hand, and the player
## decides whether it is worth the energy. That is why it cannot hand the player more than the
## turn lets them spend. Each pet card is priced on its own, and the chance is a second,
## independent lever, so the pet is variance a player plans around rather than a metronome.
##
## Built as a pool per pet, never one hard-coded pet, so a character whose main mechanic is a
## summon can be built on the same source later. See PetPool and CombatEngine._maybe_pet_arrival.

var id: StringName = &""
var display_name: String = ""
## What the pet is, one or two sentences, in the world's own register. Shown in the map readout.
var description: String = ""
## The realm this companion belongs to. Pets travel with the player by default; this is
## provenance and the hook for a realm-specific answer later, not an expiry.
var realm_id: StringName = &""
## Chance, per player turn, that a card from the pool arrives. PROVISIONAL (part 3).
var arrival_chance: float = 0.4
