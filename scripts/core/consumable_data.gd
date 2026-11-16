class_name ConsumableData
extends RefCounted
## A held, spent item: the fourth power layer after cards, relics and titles. The thing that
## sets it apart is that the player picks the moment. It is NOT a title with charges: that is a passive worn in a slot, this is an object you carry and
## use up. The inventory is two slots with no relic that widens it (RunManager.CONSUMABLE_SLOTS).

## What kind of item it is, for the UI grouping and the shop. QUEST items are carried to a
## payoff node and spent there by an event choice, never by the use button.
enum Kind { RESTORATIVE, COMBAT_BOON, STANDING, QUEST }

## Realm-exclusive items carry a realm id and (by default) expire at the border; generic items
## travel. The behaviours are case by case, the cap is the hard rule.
enum Box { GENERIC, REALM }

## What using it does. Resolved in CombatEngine.use_consumable (combat) and
## RunManager.use_consumable_on_map (map); an effect only runs where its usable_* flag is set.
enum Effect {
	HEAL,                  # restore `value` HP
	HEAL_DRIFT_HOLLOW,     # restore `value` HP, then pull Passion `value2` toward Hollow
	NEXT_ATTACK_BONUS,     # the first hit of the next card you play deals +`value`
	PASSION_TOWARD_POLE,   # push Passion `value` toward the pole you already lean to
	STRENGTH_THIS_FIGHT,   # +`value` Strength until the fight ends
	WARD_NEXT_BLOW,        # the next blow against you after it is used does not land
	STANDING_SHIFT,        # add `value` to the realm's court/folk standing (+ folk, - court)
	NONE,                  # quest items: spent by an event choice, not by the use button
}

var id: StringName = &""
var display_name: String = ""
var description: String = ""
## One line of the object's own voice, shown beneath the description.
var flavor: String = ""
var kind: Kind = Kind.RESTORATIVE
var box: Box = Box.GENERIC
var realm_id: StringName = &""
var effect: Effect = Effect.NONE
var value: int = 0
var value2: int = 0
var usable_in_combat: bool = false
var usable_on_map: bool = false
## Realm-exclusive items leave the pack when the player crosses a realm border unless they have
## an answer for what they mean out there. Case by case; the default for a REALM item is true.
var expires_at_border: bool = false
## Quest items name the questline they ride (RunManager.active_quests). Once the quest is
## completed, or its payoff node is behind the player, the item is spent: the UI says so and
## the player is meant to drop it to free the slot.
var quest_id: StringName = &""
## Gold price in a shop that stocks it. 0 = never sold.
var price: int = 0


func is_quest_item() -> bool:
	return kind == Kind.QUEST


## Where the item can be used right now, as a short phrase for the tooltip.
func use_context_label() -> String:
	if usable_in_combat and usable_on_map:
		return "Use: in combat or on the map"
	if usable_in_combat:
		return "Use: in combat"
	if usable_on_map:
		return "Use: on the map"
	return "Carried to its payoff"
