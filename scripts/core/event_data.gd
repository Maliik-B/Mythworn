class_name EventData
extends RefCounted
## Defines a narrative event with choices and consequences.

var event_name: String = ""
var description: String = ""
var choices: Array[EventChoice] = []


class EventChoice extends RefCounted:
	var text: String = ""
	var result_text: String = ""
	var hp_change: int = 0
	var max_hp_change: int = 0
	var gold_change: int = 0
	var passion_change: int = 0
	var card_reward: bool = false  # Offer 3 cards to pick from
	var remove_card: bool = false  # Offer to remove a card from deck
	## If non-empty, awards this title when the choice is taken. The TitleEarnedPopup
	## autoload renders the celebration card automatically via Events.title_earned.
	## Silently no-ops if the title is unknown or already earned.
	var awarded_title_id: StringName = &""
	## If non-empty, grants this relic via RunManager.acquire_relic when chosen.
	## Used for one-shot quest events (e.g. Camelot's Sword in the Stone grants Excalibur).
	var granted_relic_id: StringName = &""
	## If non-empty, this choice LAUNCHES A SCRIPTED FIGHT (by key) instead of resolving
	## normally: event_scene sets up the encounter and routes to combat, and combat
	## victory routes to the follow-up beat. Used by the Sword-in-the-Stone guardian.
	var starts_combat: StringName = &""
	## If non-empty, accepting this choice ARMS the cross-map questline with this id
	## (RunManager.active_quest_id): the payoff node elsewhere on the map reveals and becomes
	## the quest's payoff. Used by the raiders' plea. See MapNode quest fields + map_scene.
	var arms_quest: StringName = &""
