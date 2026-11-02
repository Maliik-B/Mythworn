class_name EventData
extends RefCounted
## Defines a narrative event with choices and consequences.

var event_name: String = ""
var description: String = ""
var choices: Array[EventChoice] = []
## Selection gate: if true, this event may only be served when a treasure-payoff node exists
## downstream of the player (MapGenerator.has_treasure_payoff). The Campfire's cache-reveal
## needs somewhere ahead to seat the fight; if the fire would fire too late in the act,
## event_scene swaps in a different event rather than offer a dead "follow the map" choice.
var requires_treasure_payoff: bool = false


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
	## If non-empty, grants this specific MEMORY card (CardPool.get_memory_card) to the deck
	## when chosen -- the one-off "remembrance" from a memory event (e.g. The Room That Isn't).
	## Distinct from card_reward, which offers a pick-1-of-3 from the normal pool.
	var granted_card_id: StringName = &""
	## If non-empty, this choice LAUNCHES A SCRIPTED FIGHT (by key) instead of resolving
	## normally: event_scene sets up the encounter and routes to combat, and combat
	## victory routes to the follow-up beat. Used by the Sword-in-the-Stone guardian.
	var starts_combat: StringName = &""
	## If non-empty, taking this choice CHAINS to another authored beat (a special event id)
	## after its result text: the player reads the outcome, then a Continue advances to that
	## next beat in the same scene flow. Lets one event unfold in stages (The Reliquary:
	## warned -> struck -> the chapel beast). The choice's own effects still apply first.
	var next_event_id: StringName = &""
	## If non-empty, accepting this choice ARMS the cross-map questline with this id
	## (RunManager.arm_quest): the payoff node elsewhere on the map reveals and becomes the
	## quest's payoff on the next map return. Used by the raiders' plea (&"raiders") and the
	## Campfire's cache-reveal (&"campfire", which also runtime-picks + tags its payoff node in
	## event_scene._arm_campfire_treasure). See MapNode quest fields + map_scene.
	var arms_quest: StringName = &""
	## Favor gate: if &"folk" / &"court", this choice is only selectable while the player
	## holds that faction's favor (RunManager.has_folk_favor / has_court_favor). Otherwise it
	## renders like any option but disabled, with "Need: Favor of the People/Court" appended --
	## so the pledge visibly opens one door and locks the other. &"" = ungated.
	var requires_favor: StringName = &""
	## Signed nudge to the realm's court<->folk standing when taken: positive toward the
	## people, negative toward the court (RunManager.change_realm_standing). 0 = no change.
	var standing_change: int = 0
	## Wager: if either gamble gold value is non-zero, selecting this choice ROLLS once
	## (gamble_chance to win, default 0.5). A win applies gamble_win_gold and shows
	## gamble_win_text; a loss applies gamble_lose_gold and shows gamble_lose_text --
	## overriding gold_change and result_text. Every other effect (passion, standing, ...)
	## still applies regardless of the roll. Used by the Tourney wager.
	var gamble_win_gold: int = 0
	var gamble_lose_gold: int = 0
	var gamble_chance: float = 0.5
	var gamble_win_text: String = ""
	var gamble_lose_text: String = ""
	## If non-empty, taking this choice queues a ONE-SHOT boon applied at the start of the
	## player's NEXT combat, then cleared (RunManager.pending_combat_boon). The id's effect
	## lives in CombatEngine._apply_pending_combat_boon; its player-facing label lives in
	## event_scene._combat_boon_label (keep the two in sync). Used by the Shade at the Cross
	## (wandering_vigor = start your next fight with +2 Strength).
	var grants_combat_boon: StringName = &""
	## When card_reward is true, biases the pick-1-of-3 toward a school: &"primary" or
	## &"secondary" draws only from that pool (the Forgotten Library's tomes); &"" = the
	## normal mixed reward. Resolved via CardPool.get_school_reward_choices.
	var card_reward_school: StringName = &""
	## If true, selecting this choice rolls ONE random reward-pool relic the player doesn't
	## own and grants it (resolved into granted_relic_id on selection, so the grant + summary
	## reuse the normal relic path). A generic find; grants_liaison_relic is the themed version.
	var grants_random_relic: bool = false
	## If non-empty (&"bram" / &"neve"), selecting this choice rolls ONE relic the player
	## doesn't own from that liaison's DEDICATED pool and grants it (resolved into
	## granted_relic_id on selection, so the grant + summary reuse the normal relic path).
	## The per-liaison reward: Bram hands out Records relics, Neve hands out Dispatch kit --
	## quest-only pools that never appear in shops or reward rolls. Mirrors grants_random_relic
	## but draws from a themed pool (RelicPool.get_liaison_relic_choices). Used by the folk
	## liaison events (Scriptorium = Bram, Last Cart Out = Neve) and the Records-flavored
	## Forgotten Library find.
	var grants_liaison_relic: StringName = &""
	## If true, taking this choice lets the player skip the next map node: the next node they
	## step onto is entered (position advances, it counts as visited) but its content is passed
	## over (RunManager.pending_skip_node). The Tourney's "watch a pass and move on" shortcut.
	var skips_next_node: bool = false
	## If non-empty, taking this choice wedges a permanent unplayable CURSE card
	## (CardPool.get_curse_card) into the run deck -- a refusal's "teeth" at the higher tier
	## (the spurned/dismissed party's parting gift). Distinct from granted_card_id (a boon):
	## this is a dead card that clogs the deck for the rest of the run. Used by the Wandering
	## Spirit's banish option.
	var grants_curse: StringName = &""
	## If non-empty, taking this choice hands the player this consumable (ConsumablePool id). When
	## both pack slots are full the event scene raises the swap prompt first: leave one behind, or
	## leave the new thing. Sourced from events first and shops second, never from combat drops.
	## The Shade at the Cross's lent courage is the first (&"unspent_courage"), held rather than
	## spent for the player.
	var grants_consumable: StringName = &""
	## Pack gate: if non-empty, this choice is only selectable while the player holds this
	## consumable. Rendered like a favor-gated option, disabled with "(Need: <name>)" so the
	## player sees the road they were not carrying the means for (the raider lair's chalice).
	var requires_consumable: StringName = &""
	## If non-empty, taking this choice spends this held consumable (a quest item delivered where
	## it was meant to go). Spent before the grant, so a swap never has to ask.
	var spends_consumable: StringName = &""
	## If non-empty, taking this choice hands the player this companion (PetPool id): a source
	## with its own card pool, one per run. See CombatEngine pet arrivals.
	var grants_pet: StringName = &""
	## Relic gate: if non-empty, this choice is only selectable while the player carries the relic
	## of this name. Rendered like a favor gate, disabled with "(Need: <name>)". The home of the
	## parked requires_item idea: the relic is the key and the site is the lock.
	var requires_relic: StringName = &""
	## If non-empty, taking this choice wakes the carried dormant forgotten relic of this name
	## (RunManager.wake_relic_by_name): the one it had takes its place. A record site builds one
	## such option per dormant relic the keeper carries, and none when none is carried, so the site
	## does the telling. It costs nothing but the event's other options.
	var wakes_relic: StringName = &""

