class_name PetData
extends RefCounted
## A companion: a source with its own small deck of cards, selected by id. The pet does not play
## a card, it GIVES you one. On every player turn one card from its deck arrives in hand, where
## it obeys every normal rule for a card: it costs energy, it competes with the hand, and the
## player decides whether it is worth the energy. That is why it cannot hand the player more than
## the turn lets them spend. The deck is drawn like the player's, without replacement and
## reshuffled when spent (CombatEngine._pet_arrival), so each card shows once a cycle and the
## player can count on it; each card is priced on its own, and the budget for the whole deck is
## about an uncommon relic's worth over a fight.
##
## Built as a deck per pet, never one hard-coded pet, so a character whose main mechanic is a
## summon can be built on the same source later. See PetPool.

var id: StringName = &""
var display_name: String = ""
## What the pet is, one or two sentences, in the world's own register.
var description: String = ""
## The realm this companion belongs to. Pets travel with the player by default; this is
## provenance and the hook for a realm-specific answer later, not an expiry.
var realm_id: StringName = &""
