extends Control
## Narrative event scene. Shows story text, player choices, consequences,
## and optional card reward / card removal follow-ups.

var event: EventData
var main_vbox: VBoxContainer
var info_label: Label
var desc_label: RichTextLabel
var choice_container: VBoxContainer
var follow_up_container: VBoxContainer
## Whether the consumable the last choice offered went into the pack. False when the player
## met a full pack and left the new thing behind. Read by the effect summary.
var _consumable_taken := true
## The capture rig sets this: a staged hold plays itself instead of waiting for a player.
var set_piece_camera_holds := false


func _ready() -> void:
	# Realm-signature events are hand-authored and route through this same scene
	# via RunManager.pending_special_event. The flag is consumed here so that
	# subsequent regular event nodes pull from the normal pool again.
	if RunManager.pending_special_event != &"":
		event = _build_special_event(RunManager.pending_special_event)
		RunManager.pending_special_event = &""
	else:
		# Ordinary event node. A scripted beat may be pinned to this visit's ordinal (e.g.
		# Cass's intro as the guaranteed 2nd event); otherwise draw from the random pool.
		var scripted := RunManager.next_ordinary_event_script()
		if scripted != &"":
			event = _build_special_event(scripted)
		else:
			# Gate out the Campfire's cache-reveal when there's nowhere downstream to seat it
			# (see EventData.requires_treasure_payoff) so "follow the map" is never a dead choice.
			var map = RunManager.current_map
			var treasure_ok := map != null \
				and MapGenerator.has_treasure_payoff(map, map.current_node_id)
			event = EventPool.get_random_event_filtered(RngManager.event_rng, treasure_ok)
	_build_ui()
	_show_choices()
	AudioManager.play_music("rest")


## Build a hand-authored event by id. New ids should be added here, not to EventPool
## (the pool is for randomly-drawn narrative events; signature quests have unique
## map placement and shouldn't be in the random rotation).
func _build_special_event(id: StringName) -> EventData:
	match id:
		&"sword_in_stone":
			return _build_sword_in_stone_event()
		&"sword_guardian_won":
			return _build_sword_guardian_won_event()
		&"raider_plea":
			return _build_raider_plea_event()
		&"raider_ambush":
			return _build_raider_ambush_event()
		&"raider_victory":
			return _build_raider_victory_event()
		&"campfire_ambush":
			return _build_campfire_ambush_event()
		&"campfire_victory":
			return _build_campfire_victory_event()
		&"room_that_isnt":
			return _build_room_that_isnt_event()
		&"reliquary_struck":
			return _build_reliquary_struck_event()
		&"reliquary_won":
			return _build_reliquary_won_event()
		&"master_of_game":
			return _build_master_of_game_event()
		# The record site seated late in every act (MapGenerator._place_record_site): one of the
		# three pool events that can wake a forgotten relic, shown on the map so a run can route
		# to it. The pool keeps drawing them too.
		&"scriptorium":
			return EventPool._scriptorium()
		&"tourney":
			return EventPool._the_tourney()
		&"reliquary":
			return EventPool._reliquary()
		_:
			push_warning("Unknown special event id: %s" % id)
			return EventPool.get_random_event(RngManager.event_rng)


func _build_sword_in_stone_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Sword in the Stone"
	e.description = ("A blade stands in a block of worn granite, sunk to the hilt. Something is hunched "
		+ "over it, and it lifts its head as you come near. A champion, once. The surcoat is plain cloth "
		+ "now. Whatever was on it has gone, and the cloth has not faded so much as been let go of."
		+ "\n\nThere is nothing in his face. His eyes are open and no one is looking out of them. He "
		+ "does not so much stand as brace, like a man holding a door shut from the inside who has "
		+ "forgotten which side of it he is on. When you move, he moves. The snarl comes up out of him "
		+ "from a long way down.\n\nThe sword's hilt catches the light, then goes dull. The metal settles deeper "
		+ "into the stone, the way a hand draws back from a thing it will not touch. The blade has "
		+ "not chosen him. It has been waiting.")

	var fight = EventData.EventChoice.new()
	fight.text = "Face the beast."
	fight.starts_combat = &"sword_guardian"
	e.choices.append(fight)

	var walk = EventData.EventChoice.new()
	walk.text = "Leave it to its vigil. The blade is not worth dying for."
	walk.result_text = ("You step back into the trees. Behind you the beast settles over its stone "
		+ "again, guarding a thing that will never answer to it. The choice not to reach is also a "
		+ "kind of weight, and you find you can carry it.")
	walk.passion_change = 3
	# Leaving the sword is the one refusal that rules out the crown (it needs Excalibur), so
	# this is where Outlander is earned: mid-act, with the fights left to pay it.
	walk.awarded_title_id = &"outlander_of_camelot"
	walk.set_piece = &"excalibur_leave"
	e.choices.append(walk)

	return e


## The follow-up beat after the guardian falls. The corruption lifts, he names the
## boss's nature (a hint at Sir Caedmon's compelled will, pointing at the Act-2 Puppeteer),
## and Excalibur frees itself from the stone.
func _build_sword_guardian_won_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Beast Unmade"
	e.description = ("As the last blow lands, something comes back into the cloth of his surcoat, faint, "
		+ "a shape you could almost read. His eyes find you. For one borrowed breath a man is left where "
		+ "the beast was, clear-eyed and frightened.\n\n\"Caedmon.\" He gets the name out like it costs "
		+ "him. \"I went to face Sir Caedmon. I had put down better men than him. I thought it would "
		+ "be quick.\" A wet laugh. \"But he does not fight like a man. Halfway through, something "
		+ "took the reins of him. His guard just dropped. He came at me like a thing with no fear "
		+ "left, and no one behind the eyes. Whatever has hold of him, it does not care if the body "
		+ "breaks getting to you.\"\n\nHis hand finds your arm. \"That is how it took me. Through "
		+ "him. Through every wound he opened. Do not stand there trading blows with the puppet. Wear "
		+ "his own will down first, until the thing moving him has to show itself. Then you put the "
		+ "sword in that.\"\n\nHe sags back against the stone. \"The blade would not have me. Maybe it "
		+ "will have you.\" He goes still. Behind you the granite gives, with a sound like a long-held "
		+ "breath let go, and the sword shifts in its seat. It sits loose in the stone now, waiting to "
		+ "be taken.")

	var take = EventData.EventChoice.new()
	take.text = "Take up Excalibur."
	take.result_text = ("You close your hand on the grip and pull. Excalibur comes free surprisingly "
		+ "easily, sliding out of the stone. It settles into your hand, impossibly light. Already you "
		+ "can feel it will answer to how you hold it: as an edge, or as an eye.")
	take.granted_relic_id = &"Excalibur"
	take.awarded_title_id = &"swords_bearer"
	take.set_piece = &"excalibur_take"
	take.passion_change = 3
	e.choices.append(take)

	return e


# ============================================================
# RAIDER QUESTLINE (cross-map: plea arms a payoff node elsewhere)
# ============================================================

## The quest-giver plea. Looks like any event node on the map; accepting ARMS the payoff
## node (see EventChoice.arms_quest). Beast-and-bandit coded: a reiver the countryside calls
## the Boar. Helping is the keeper's guard dropping, so it nudges Passion toward Water (+),
## matching the tithe plea and the 8 base events' mercy convention. Medieval flavor.
func _build_raider_plea_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Road Past the Ford"
	e.description = ("You push through a last snarl of hedge and briar where the track gives "
		+ "out, and the land opens onto a village in the hollow below. It backs against the "
		+ "treeline. Even from the rise it has the look of a place that keeps its doors barred by "
		+ "daylight. A barn has burned down to its blackened frame. The well is boarded over. The "
		+ "few people who come out to meet you move with the stiffness of the newly "
		+ "hurt.\n\nA man with his arm in a sling does the talking. \"You'll have heard of the Boar, "
		+ "if you came through the weald.\" He says the name like it tastes bad. \"Was a reiver once, "
		+ "with a reiver's sense. Now he just takes, and burns what he can't carry, and laughs doing "
		+ "it. They started calling him the Boar for how he fights. It stuck.\"\n\nHe nods at the "
		+ "trees. \"They lair up the old drovers' road, past the ford. We can't move him. You've got a "
		+ "sword, and you're going that way regardless.\"")

	var accept = EventData.EventChoice.new()
	accept.text = "Follow the drovers' road. Put an end to the Boar."
	accept.result_text = ("You tell him you'll take the road past the ford. He doesn't thank you. "
		+ "He's past thanking people for things that haven't happened yet. But he draws you a map in "
		+ "the dirt with the point of a stick, and marks where the trees close in. Then he sends a boy "
		+ "running to the house for a covered cup, the last of the village's wine gone cloudy, with "
		+ "the green smell of monkshood steeped in it. \"They drink anything,\" he says. \"Leave it "
		+ "where they'll find it.\" He looks at the trees again. \"They'll hear you before you see "
		+ "them. They always do.\"")
	accept.grants_consumable = &"poisoned_chalice"
	accept.arms_quest = &"raiders"
	accept.passion_change = 3
	accept.standing_change = 8  # taking up the people's fight earns their regard
	e.choices.append(accept)

	var decline = EventData.EventChoice.new()
	decline.text = "The Boar is not your fight. Take another road."
	decline.result_text = ("You tell him it isn't yours to settle, and his face doesn't change, "
		+ "because he expected nothing else. You take a road that bends away from the ford. For a "
		+ "while you can still smell the wet char of the barn on the wind. Then you can't.")
	decline.passion_change = -2
	decline.standing_change = -5  # refusing the raided village's plea costs you with the people
	e.choices.append(decline)

	return e


## The payoff node, armed. The keeper has tracked the band to its lair; the fight is the
## scripted raider band (The Boar + two Weald Raiders). Victory routes to the reward beat.
func _build_raider_ambush_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Lair Past the Ford"
	e.description = ("The drovers' road narrows until the trees meet overhead and the daylight goes "
		+ "green and thin. The man was right: you hear them first. A whistle, passed from one side of "
		+ "the track to the other, then the brush moving the way brush doesn't.\n\nThey come out onto "
		+ "the road ahead of you, unhurried, a handful of them with the wood at their backs. The big "
		+ "one in the middle doesn't carry himself like a man expecting trouble. He carries himself "
		+ "like he is the trouble. When he sees the sword, he grins, and it is not a nice thing to "
		+ "watch.")

	var fight = EventData.EventChoice.new()
	fight.text = "Draw, and make an end of it."
	fight.starts_combat = &"raider_band"
	e.choices.append(fight)

	# The chalice delivered: the cup the village sent with you is set where they will find it,
	# and every raider opens the fight with Poison. Disabled with "(Need: The Poisoned Chalice)"
	# for a keeper who dropped it, or never took it, so the road not carried is visible.
	var cup = EventData.EventChoice.new()
	cup.text = "Set the village's cup where they will find it, then draw."
	cup.requires_consumable = &"poisoned_chalice"
	cup.spends_consumable = &"poisoned_chalice"
	cup.starts_combat = &"raider_band_poisoned"
	e.choices.append(cup)

	return e


## The reward beat after the band falls. Pledge-agnostic: an immediate heal (the village binds
## your wounds) plus Blooded Edge (the one good thing they had left to give). Marking the quest
## complete here stops any re-trigger; the grant itself happens on the choice.
func _build_raider_victory_event() -> EventData:
	RunManager.complete_quest(&"raiders")

	var e = EventData.new()
	e.event_name = "What the Village Had Left"
	e.description = ("It ends the way these things end: all at once, and then quiet. The Boar is the "
		+ "last down, and he goes hard, swearing at you through the blood as though the insult is that "
		+ "it was you and not someone grander.\n\nBy the time you walk back, the smell of the burned "
		+ "barn has people out of their doors to meet you. The man with the sling comes out last, and "
		+ "slowest, and looks a long while at the road behind you before he looks at you. Whatever he "
		+ "sees there is enough. They feed you, and bind what needs binding, and press on you the one "
		+ "good thing they had left to give.")

	var take = EventData.EventChoice.new()
	take.text = "Take what the village offers."
	take.result_text = ("It is an old campaigner's knife, kept oiled through everything. \"First "
		+ "cut's the one that counts,\" the man says, closing your hand around it. \"He taught me "
		+ "that. Before the Boar got him.\" The edge of it seems to find the gap in a guard on its "
		+ "own.")
	take.hp_change = maxi(1, int(round(RunManager.max_hp * 0.28)))
	take.granted_relic_id = &"Blooded Edge"
	take.passion_change = 2
	e.choices.append(take)

	return e


# ============================================================
# CAMPFIRE TREASURE (a random fire exposes a cache down the road)
# ============================================================

## The treasure payoff, armed. The dead campers' map led here: the barrow the warden came out
## of, and the cache they hid before they ran. Reaching for the gold rouses him. Victory routes
## to the reward beat. Fight-only, like the raider ambush -- the player armed this knowingly and
## pathed to it, so there's no back-out at the cache.
func _build_campfire_ambush_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Cache on the Road"
	e.description = ("The map runs out at a fork where a cairn of grave-stones has been pulled "
		+ "half apart. The cache is where the journal promised: oilcloth bundles wedged under the "
		+ "stones, heavy with a lord's buried wealth. You have a hand on the first of them when the "
		+ "cold comes up out of the ground.\n\nHe was a knight once, laid here with his hoard the "
		+ "old way, and he has not stayed laid. The name that was cut on the barrow stone is gone, "
		+ "and so is whatever was on his shield; the gilt on his grave-mail has gone the dull of "
		+ "brass. He does not speak. He simply stands between you and a hoard he could not tell you "
		+ "whose it was, the way he has stood since before the road had a name.")

	var fight = EventData.EventChoice.new()
	fight.text = "Take the hoard. Put him back in the ground."
	fight.starts_combat = &"barrow_warden"
	e.choices.append(fight)

	return e


## The reward beat after the warden falls. The cache is the payoff: a purse of the lord's buried
## wealth (extra gold) and the warden's own grave-mail (Barrow-Warden's Mail). Marking the quest
## complete here stops any re-trigger; the grants happen on the choice.
func _build_campfire_victory_event() -> EventData:
	RunManager.complete_quest(&"campfire")

	var e = EventData.new()
	e.event_name = "What the Barrow Kept"
	e.description = ("He comes apart the way old things do, all at once, the cold going out of "
		+ "him, the grave-mail folding empty to the road. For a breath the barrow is only a barrow "
		+ "again, and the quiet is enormous.\n\nThe cache is where the dead men left it. The lord's "
		+ "wealth is real, and heavier than it looks. And the mail the warden wore has come away "
		+ "from him whole, the grave-cold still in it, fitted for a body about your size.")

	var take = EventData.EventChoice.new()
	take.text = "Take the hoard and the mail."
	take.result_text = ("You load the coin into your pack until the seams complain, and work "
		+ "yourself into the grave-mail. It settles cold against you and never warms, but little "
		+ "gets through it, and it is yours now, not his.")
	take.gold_change = 55
	take.granted_relic_id = &"Barrow-Warden's Mail"
	e.choices.append(take)

	return e


## Seats the Campfire treasure at a node downstream of the player, then arms the quest so the
## payoff reveals on the next return to the map. The event-selection gate already confirmed a
## candidate exists, so the pick normally succeeds; if it fails anyway the quest is left unarmed
## rather than marking a node that can't be reached. event_rng keeps the pick run-seed-stable.
func _arm_campfire_treasure() -> void:
	var map = RunManager.current_map
	if map == null:
		return
	var payoff_id := MapGenerator.pick_treasure_payoff(map, map.current_node_id, RngManager.event_rng)
	if payoff_id == -1:
		return
	map.nodes[payoff_id].quest_payoff_id = &"campfire"
	RunManager.arm_quest(&"campfire")


## The Room That Isn't -- introduces Cass (Anomalies). Scheduled as the player's 2nd event
## (RunManager.scripted_event_schedule, set in start_run). A space that's wrong in a way that
## ISN'T the usual rot: a corridor longer inside than out, a window on a sky that isn't
## Camelot's. Stepping through is Proposal A -- a deterministic trade, seen going in: a glimpse
## of a lost home (the memory card "The House That Was") for a cut of HP that the seeing takes.
## Cass names Anomalies and Fable without explaining what an anomaly is, and the lost home is
## only glimpsed. Her voice: flat, unimpressed, already tired of you being here.
func _build_room_that_isnt_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Room That Isn't"
	e.description = ("The corridor runs longer than the building it's in. You counted the windows "
		+ "from the yard, and there were four. In here there are seven, and the light coming through "
		+ "the last one is the wrong color for the hour, the wrong color for the season, maybe the "
		+ "wrong color for anywhere you've stood under a sky.\n\nThis isn't the rot. You know the rot "
		+ "by now, the shields gone plain, the faces with no one behind them, the grey. This is "
		+ "something else. Clean, and quiet, and wrong the way a word repeated too many times stops "
		+ "being a word.\n\nA woman is already there, leaning in a doorway that opens onto a room you "
		+ "are fairly sure the corridor does not have space for. She doesn't look up from her notes. "
		+ "\"Cass. Anomalies.\" She says it the way you'd say a department, because it is one. \"You're "
		+ "the one they sent for the sword. This isn't your file. It's mine.\" She finally looks at "
		+ "you, and something in your face makes her put the notes down. \"...you feel it pulling, "
		+ "don't you. Of course you do. Don't.\"")

	# Proposal A: the deterministic trade, cost shown up front. The glimpse of home grants the
	# memory card; the seeing takes a cut of HP. Cass warns you off, and lets you choose anyway.
	var step = EventData.EventChoice.new()
	step.text = "Step through the door that shouldn't fit. (Lose 8 HP)"
	step.result_text = ("Cass says your name once, flatly. The one you gave yourself. She "
		+ "doesn't try to stop you with her hands. You step through, and for a moment you are "
		+ "somewhere with a low roof and a particular light and the sense of a room you knew the "
		+ "shape of without looking. You can't keep it. It goes the way they all go. But your hands "
		+ "remember the shape of a door, and you come back carrying that much. It costs you. The "
		+ "seeing always costs something. Cass watches you sway and says, not unkindly, \"I told "
		+ "you.\" She writes something down. \"They never listen. I don't know why I still say it.\"")
	step.hp_change = -8
	step.granted_card_id = &"house_that_was"
	e.choices.append(step)

	# Look, don't cross: a smaller taste -- the longing without the wound. A Passion nudge, no card.
	var look = EventData.EventChoice.new()
	look.text = "Stand at the threshold and only look."
	look.result_text = ("You stop at the edge of it and let yourself look and no further. It's "
		+ "enough to ache and not enough to keep. After a while the wrongness of the light stops "
		+ "feeling like an invitation and starts feeling like weather, and you can turn away from "
		+ "weather. Cass nods, once, like you passed something she doesn't bother grading out loud.")
	look.passion_change = 5
	e.choices.append(look)

	# The safe read: let her walk you out. Nothing gained, nothing lost; she's plainly relieved.
	var leave = EventData.EventChoice.new()
	leave.text = "Let Cass walk you back out."
	leave.result_text = ("\"Smart,\" she says, and means it, and walks you back down a corridor "
		+ "that takes fewer steps to leave than it did to enter. At the door she almost says "
		+ "something else, decides against it, and goes back to her notes. Behind you the room does "
		+ "whatever the room does when no one is looking at it.")
	e.choices.append(leave)

	return e


## The Reliquary, stage 2: struck at the lychgate (the HP cost rode the entry choice), a
## memory of a Fable colleague surfaces and starts to fade. The hold-or-stay choice. Reached
## via the entry event's next_event_id. The colleague is Neve (Dispatch, the run-start send-off
## liaison), remembered plainly as a coworker.
func _build_reliquary_struck_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Reliquary"
	e.description = ("The thing the chapel gives you is a memory, and it is not of home. It is the "
		+ "office. Fable, the ordinary grind of it, and Neve. Dispatch. The kit she always packs "
		+ "too carefully, the way she holds it a second longer than she needs to before she lets "
		+ "you take it. You can see her clearly. The line she gets between her eyes. The thing she "
		+ "is always saying that you'd stopped hearing. Come back in one piece. You're bad at that."
		+ "\n\nThen she begins to go. Not torn away. Just thinning at the edges while you reach for "
		+ "her, the way your oldest memories go, the way a whole home once went. You know this "
		+ "exactly. You can feel how much of her is left, and how fast, and that if you do nothing "
		+ "there will shortly have been no one there at all.")

	# Hold and leave: keep the memory, abandon the chapel, apologize. No fight, no title -- a
	# quiet, dignified out. You keep what matters to you; you just don't fight for more.
	var hold = EventData.EventChoice.new()
	hold.text = "Hold the feeling. Let the chapel keep the rest, and go."
	hold.result_text = ("You stop reaching. You hold still and just have her, the whole shape of "
		+ "her, for as long as it lasts, and you don't fight the chapel for anything past that. "
		+ "Her face stays. Worn at the edges, but yours. On the way out you put a hand flat on the "
		+ "grey door. \"I'm sorry,\" you tell it, and you're not sure for what. For leaving it like "
		+ "this, maybe. It doesn't answer. The stoup in the porch has a little holy water standing in "
		+ "it, and you fill a flask from it on the way past, because it is there and because "
		+ "something ought to be taken out of a place that has taken that much. It is colder than "
		+ "it should be. You take the road with one more face kept than you came with, and a "
		+ "chapel at your back that you did not save.")
	hold.grants_consumable = &"relic_water"
	hold.passion_change = 5
	e.choices.append(hold)

	# Stay in contact: more damage (clamped to leave 1 HP), and the chapel's held memory tears
	# itself off the walls to make you stop. Launches the chapel-beast fight -> reliquary_won.
	var stay = EventData.EventChoice.new()
	stay.text = "Don't let her fade. Hold on, whatever it costs. (Lose 6 HP)"
	stay.hp_change = -6
	stay.starts_combat = &"chapel_beast"
	e.choices.append(stay)

	# A keeper carrying a forgotten relic can give the chapel the memory it wants for the one the
	# thing has lost: one option per dormant relic held, none when none is carried. The cost is
	# the hold and the fight, which is to say her. The chapel's trade, taken at its word.
	for relic in RunManager.get_forgotten_relics():
		var trade = EventData.EventChoice.new()
		trade.text = "Let her go. Hold up %s instead, and let the chapel have its trade." % relic.short_name
		trade.result_text = ("You stop reaching for her and hold the thing up instead, and the chapel "
			+ "takes what it takes. She goes the way the oldest things go, without a sound, and "
			+ "you will not be able to say afterward what the line between her eyes looked like. "
			+ "In your hands the thing you carried comes back to itself. " + relic.wake_line
			+ " You go out past the stoup without filling anything. The chapel is at your back "
			+ "with its memory, and the thing in your hand has its own, and you are short one.")
		trade.wakes_relic = StringName(relic.relic_name)
		e.choices.append(trade)

	return e


## The Reliquary, stage 3: the beast is unmade and the memory held. Reached only by winning the
## chapel-beast fight (pending_special_event after victory). The payoff: a heal, a Passion lift,
## The Thurible relic (the censer toggle, replacing the old Vigil Candle), and The Unfading title
## (the first card you play each combat returns to your hand: a thing you spend that refuses to
## be spent, for having refused to let a memory go). The Compassionate is the Last Cart Out's.
func _build_reliquary_won_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Reliquary"
	e.description = ("The shape comes apart the way glass finds its own cracks, all at once and "
		+ "then still. What tore off the walls is back to being walls: dim glass, grey gold, a "
		+ "saint worn faceless by weather and years. The chapel is only a chapel again.\n\nAnd the "
		+ "memory you would not let go of is still there. Whole. Clear. The kit, the saying, her "
		+ "face. You held on and it held. In the quiet the reliquary gives you one thing more, the "
		+ "way a place gives you something when you've paid it enough mind to be owed.")

	var take = EventData.EventChoice.new()
	take.text = "Take what the chapel leaves you, and go."
	take.result_text = ("It is a censer, a small chapel thurible of brass gone dark, its chain "
		+ "kinked from a lifetime of being swung, a coal still sleeping in its throat. When you "
		+ "lift it the thing swings on its own, and a thread of old incense lets go, and something "
		+ "in you tips with it, toward heat or toward quiet, depending on how you hold your hand. "
		+ "It steadies you to carry it, the way a kept rhythm steadies you. You go out through the "
		+ "lychgate lighter than you came, carrying a face, a slow-swinging weight, and the "
		+ "particular ache of having refused to let a thing be forgotten.")
	take.hp_change = maxi(1, int(round(RunManager.max_hp * 0.25)))
	take.passion_change = 5
	take.granted_relic_id = &"The Thurible"
	take.awarded_title_id = &"the_unfading"
	e.choices.append(take)

	return e


## The Master of Game: the huntsman's node, seated once a map by MapGenerator. His lord rode out
## with the rest and did not come back, and he sells the lord's animals to someone who will feed
## them. Every animal the keeper does not already have is a priced option (75 gold, flat: the
## choice is identity, not value; gold_change disables what you cannot afford), a new one replaces
## the old, which stays with him and is fed, and leaving them with him costs nothing. One
## companion a run; the Tiltyard's hound is the other way to one. Stage-free: a lord who rode out
## in the spring is any stage of the fall.
func _build_master_of_game_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Master of Game"
	e.description = ("The lodge sits where the forest road leaves the fields, and the kennels behind "
		+ "it are still full. A man is feeding them. He is the lord's master of game, by the coat and "
		+ "the horn at his hip, and his lord went up the king's road in the spring with the rest and "
		+ "has not come back down it. So he feeds the hounds and the mews and the warren out of what "
		+ "the lord left, and that will not see the winter out, and he knows it.\n\nHe does not ask "
		+ "who you are. He looks at your hands and your boots. \"They want working,\" he says, of the "
		+ "animals, \"and I am one man, and he is not coming back.\" He will sell to anyone who will "
		+ "feed them. Seventy-five, each, and he does not haggle, because the price was never the "
		+ "point of it.")

	var held := RunManager.get_pet()
	var stays := ""
	if held != null:
		stays = (" %s you came with goes to him, and he takes it without a word, and that is "
			+ "settled. He will see it fed.") % held.display_name

	if held == null or held.id != &"hound":
		var hound = EventData.EventChoice.new()
		hound.text = "Take the hound. (75 gold)"
		hound.result_text = ("He whistles one out of the kennel, a lean hound grey in the muzzle, "
			+ "and it comes to your hand as though it has been waiting for exactly this. \"That one "
			+ "knows the work,\" he says. He does not say goodbye to it. He goes back to the "
			+ "feeding. At the gate the hound looks back once, and then does not again." + stays)
		hound.gold_change = -75
		hound.grants_pet = &"hound"
		e.choices.append(hound)

	if held == null or held.id != &"hawk":
		var hawk = EventData.EventChoice.new()
		hawk.text = "Take the hawk. (75 gold)"
		hawk.result_text = ("He brings the peregrine out of the mews hooded and sets her on your "
			+ "fist, and shows you the jesses, and unhoods her. She looks at you the way they look "
			+ "at everything, as though you were a long way down. \"She'll wait on for a man who "
			+ "stands still,\" he says. \"Stand still.\"" + stays)
		hawk.gold_change = -75
		hawk.grants_pet = &"hawk"
		e.choices.append(hawk)

	if held == null or held.id != &"ferret":
		var ferret = EventData.EventChoice.new()
		ferret.text = "Take the ferret. (75 gold)"
		ferret.result_text = ("He reaches into a box by the door and comes out with a ferret, long "
			+ "and pale and already trying to go down his sleeve, and puts it in your hands, where "
			+ "it tries to go down yours. \"Keep it fed and it will keep you fed,\" he says, \"and "
			+ "keep your fingers out of the way of it.\" It is a smaller thing than the others, and "
			+ "he charges you the same, and does not explain." + stays)
		ferret.gold_change = -75
		ferret.grants_pet = &"ferret"
		e.choices.append(ferret)

	var leave = EventData.EventChoice.new()
	leave.text = "Leave them with him. They are fed."
	leave.result_text = ("You leave him to it. He does not argue, and he does not thank you for the "
		+ "consideration, because it was not for him. Behind you the kennel sets up a noise, and "
		+ "stops, and then the only sound is a man working through a stack of feeding in the order "
		+ "he has always done it in.")
	e.choices.append(leave)
	return e


# ============================================================
# UI
# ============================================================

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.05, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Moody vignette for events
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.5;
	float vig = smoothstep(0.2, 1.0, dist);
	COLOR = vec4(0.02, 0.0, 0.04, vig * 0.6);
}
"""
	mat.shader = shader
	vignette.material = mat
	add_child(vignette)

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)

	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = event.event_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.8, 0.55, 0.9))
	main_vbox.add_child(title)

	# Description
	desc_label = RichTextLabel.new()
	desc_label.text = event.description
	desc_label.bbcode_enabled = false
	desc_label.fit_content = true
	desc_label.scroll_active = false
	desc_label.custom_minimum_size.y = 80
	desc_label.add_theme_font_size_override("normal_font_size", 18)
	desc_label.add_theme_color_override("default_color", Color(0.8, 0.78, 0.7))
	main_vbox.add_child(desc_label)

	# HP / Gold bar
	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	main_vbox.add_child(info_label)
	_update_info()

	# Unobtrusive read-only map peek — stays available through the whole event and
	# never consumes it.
	var map_row = HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(map_row)
	var map_btn = Button.new()
	map_btn.text = "View Map"
	map_btn.custom_minimum_size = Vector2(150, 34)
	map_btn.add_theme_font_size_override("font_size", 14)
	map_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	map_btn.pressed.connect(_on_view_map)
	map_row.add_child(map_btn)

	# Choice buttons container
	choice_container = VBoxContainer.new()
	choice_container.add_theme_constant_override("separation", 12)
	main_vbox.add_child(choice_container)

	# Follow-up area (card reward / removal)
	follow_up_container = VBoxContainer.new()
	follow_up_container.add_theme_constant_override("separation", 14)
	follow_up_container.visible = false
	main_vbox.add_child(follow_up_container)


func _update_info() -> void:
	info_label.text = "HP: %d / %d    Gold: %d" % [
		RunManager.current_hp, RunManager.max_hp, RunManager.gold]


func _on_view_map() -> void:
	MapPreviewOverlay.open(self)


# ============================================================
# CHOICES
# ============================================================

func _show_choices() -> void:
	for i in event.choices.size():
		var choice = event.choices[i]
		var btn = _make_choice_button(choice, i)
		# Disable choices the player can't afford
		if choice.gold_change < 0 and RunManager.gold < -choice.gold_change:
			btn.disabled = true
			btn.text += " (Not enough gold)"
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		# Favor gate: a faction-aligned option the opposed/neutral player can see but not take.
		# Same option styling as any other, just disabled with the requirement appended.
		elif choice.requires_favor == &"folk" and not RunManager.has_folk_favor():
			btn.disabled = true
			btn.text += " (Need: Favor of the People)"
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		elif choice.requires_favor == &"court" and not RunManager.has_court_favor():
			btn.disabled = true
			btn.text += " (Need: Favor of the Court)"
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		# Pack gate: an option that wants an item the player is not carrying (the raider lair's
		# chalice) shows what it would have taken, the way a favor gate shows its faction.
		elif choice.requires_consumable != &"" and not RunManager.has_consumable(choice.requires_consumable):
			var needed := ConsumablePool.get_consumable(choice.requires_consumable)
			btn.disabled = true
			btn.text += " (Need: %s)" % (needed.display_name if needed else "an item")
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		# Relic gate: the relic is the key and the site is the lock, shown the same way.
		elif choice.requires_relic != &"" and not RunManager.has_relic(String(choice.requires_relic)):
			btn.disabled = true
			btn.text += " (Need: %s)" % choice.requires_relic
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		choice_container.add_child(btn)


func _make_choice_button(choice: EventData.EventChoice, index: int) -> Button:
	var btn = Button.new()
	btn.text = "[%d] %s" % [index + 1, choice.text]
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_font_size_override("font_size", 17)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.bg_color = Color(0.14, 0.11, 0.2)
	style.border_color = Color(0.55, 0.4, 0.7)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.22, 0.16, 0.3)
	hover_style.border_color = Color(0.8, 0.55, 0.9)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.07, 0.14)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.14, 0.11, 0.2)
	disabled_style.border_color = Color(0.3, 0.3, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.pressed.connect(_on_choice_selected.bind(index))
	return btn


func _on_choice_selected(index: int) -> void:
	AudioManager.play_sfx("button_click")
	var choice = event.choices[index]

	# A choice can launch a scripted fight instead of resolving in-scene (the
	# Sword-in-the-Stone guardian). Combat victory routes to the follow-up beat.
	if choice.starts_combat != &"":
		# A pre-fight HP cost (The Reliquary: staying in contact wounds you before the
		# beast reforms). Applied here since the combat launch skips _apply_effects, and
		# clamped to leave 1 HP -- the fight is the real threat, not the reach.
		if choice.hp_change < 0:
			RunManager.current_hp = maxi(1, RunManager.current_hp + choice.hp_change)
		# A quest item delivered at the fight (the chalice left for the raiders) is spent
		# here for the same reason: the launch skips _apply_effects.
		if choice.spends_consumable != &"":
			RunManager.spend_consumable_by_id(choice.spends_consumable)
		_start_event_combat(choice.starts_combat)
		return

	# A wager rolls once on selection: the win/loss overrides the gold and the result text
	# before anything is applied or shown. Other effects on the choice still land either way.
	if choice.gamble_win_gold != 0 or choice.gamble_lose_gold != 0:
		var won: bool = RngManager.loot_rng.randf() < choice.gamble_chance
		choice.gold_change = choice.gamble_win_gold if won else choice.gamble_lose_gold
		choice.result_text = choice.gamble_win_text if won else choice.gamble_lose_text

	# A relic find rolls one random reward-pool relic the player doesn't own and routes it
	# through granted_relic_id, so the grant and the summary reuse the normal relic path.
	if choice.grants_random_relic and choice.granted_relic_id == &"":
		var picks := RelicPool.get_reward_choices(
			RngManager.loot_rng, 1, RunManager.get_owned_relic_names())
		if picks.size() > 0:
			choice.granted_relic_id = picks[0].relic_name

	# A liaison relic grant rolls one unowned relic from the named liaison's dedicated pool
	# (Bram = Records, Neve = Dispatch) and routes it through granted_relic_id, the same way
	# the generic find does -- so the grant and the summary reuse the normal relic path.
	if choice.grants_liaison_relic != &"" and choice.granted_relic_id == &"":
		var liaison_picks := RelicPool.get_liaison_relic_choices(
			choice.grants_liaison_relic, RngManager.loot_rng, 1,
			RunManager.get_owned_relic_names())
		if liaison_picks.size() > 0:
			choice.granted_relic_id = liaison_picks[0].relic_name

	# A consumable grant resolves BEFORE the result shows: with both pack slots full the player
	# must leave something behind, and the summary below has to say what actually happened.
	_consumable_taken = true
	if choice.grants_consumable != &"":
		_consumable_taken = await _grant_consumable(choice.grants_consumable)

	# A staged moment covers the scene while everything below lands under it, so when the stage
	# lifts the result is already standing there. Its toast waits for the map.
	_open_set_piece(choice)

	_apply_effects(choice)
	choice_container.visible = false

	# Show result text
	desc_label.text = choice.result_text
	_update_info()
	_show_effect_summary(choice)

	# Check if player died from event effects
	if RunManager.current_hp <= 0:
		_show_game_over()
		return

	# Handle follow-ups
	if choice.card_reward:
		_show_card_reward(choice.card_reward_school)
	elif choice.remove_card:
		_show_card_removal()
	elif choice.next_event_id != &"":
		# A multi-stage event: advance to the next authored beat after the player reads
		# this outcome (The Reliquary's warned -> struck -> fight chain).
		_show_next_beat(choice.next_event_id)
	else:
		_show_done()


## Opens the stage this choice calls for, if any. Fire and forget: the stage shields the scene from
## input and frees itself.
func _open_set_piece(choice: EventData.EventChoice) -> void:
	match choice.set_piece:
		&"excalibur_take":
			TitleEarnedPopup.hold()
			ExcaliburPiece.play_take(self, choice, set_piece_camera_holds)
		&"excalibur_leave":
			TitleEarnedPopup.hold()
			ExcaliburPiece.play_leave(self, event.event_name, choice)


func _exit_tree() -> void:
	TitleEarnedPopup.release()


## Player-facing label for a queued next-combat boon (RunManager.pending_combat_boon). Mirror
## of the effect catalogue in CombatEngine._apply_pending_combat_boon -- keep the ids in sync.
func _combat_boon_label(boon: StringName) -> String:
	match boon:
		&"wandering_vigor":
			return "Next combat: +2 Strength"
		_:
			return "Next combat: a boon"


## Hands the player a consumable, or raises the swap prompt when both slots are full. Returns
## whether the new item ended up in the pack. A coroutine: with a full pack it waits for the
## player's decision, so the caller can show an honest result afterward.
func _grant_consumable(id: StringName) -> bool:
	var item := ConsumablePool.get_consumable(id)
	if item == null:
		push_warning("Unknown consumable id on an event choice: %s" % id)
		return false
	if RunManager.add_consumable(item):
		return true
	var swap := ConsumableSwap.open(self, item)
	var taken: bool = await swap.resolved
	return taken


## Launches a scripted event fight. The Sword-in-the-Stone guardian is the Beast at the
## Stone (a champion who went to face Caedmon and came back hollowed).
## Combat victory routes back to the "beast unmade" beat via pending_event_combat +
## pending_special_event; the player gets no normal reward — Excalibur IS the reward.
func _start_event_combat(key: StringName) -> void:
	match key:
		&"sword_guardian":
			RunManager.pending_enemies.clear()
			for guardian in EnemyPool.get_sword_guardian():
				RunManager.pending_enemies.append(guardian)
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"sword_guardian_won"
			SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")
		&"raider_band":
			RunManager.pending_enemies.clear()
			for enemy in EnemyPool.get_raider_band():
				RunManager.pending_enemies.append(enemy)
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"raider_victory"
			SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")
		&"raider_band_poisoned":
			# The chalice was left where the band would find it: every raider opens the fight
			# with the chalice's Poison (its value, read from the consumable's own data so the
			# number lives in one place).
			var chalice := ConsumablePool.get_consumable(&"poisoned_chalice")
			RunManager.pending_enemies.clear()
			for enemy in EnemyPool.get_raider_band_poisoned(chalice.value if chalice else 4):
				RunManager.pending_enemies.append(enemy)
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"raider_victory"
			SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")
		&"chapel_beast":
			RunManager.pending_enemies.clear()
			RunManager.pending_enemies.append(EnemyPool.the_shattered_choir())
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"reliquary_won"
			SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")
		&"barrow_warden":
			RunManager.pending_enemies.clear()
			for enemy in EnemyPool.get_barrow_warden():
				RunManager.pending_enemies.append(enemy)
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"campfire_victory"
			SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")
		_:
			push_warning("Unknown event combat key: %s" % key)
			_show_done()


# ============================================================
# APPLY EFFECTS
# ============================================================

func _apply_effects(choice: EventData.EventChoice) -> void:
	if choice.hp_change != 0:
		if choice.hp_change > 0:
			RunManager.heal(choice.hp_change)
		else:
			# Apply damage directly without triggering run end — we handle death in the UI
			RunManager.current_hp = max(0, RunManager.current_hp - (-choice.hp_change))

	if choice.max_hp_change != 0:
		RunManager.max_hp += choice.max_hp_change
		if choice.max_hp_change > 0:
			RunManager.current_hp += choice.max_hp_change

	if choice.gold_change != 0:
		RunManager.gold = max(0, RunManager.gold + choice.gold_change)

	if choice.passion_change != 0:
		RunManager.change_passion(choice.passion_change)

	if choice.awarded_title_id != &"":
		RunManager.award_title(choice.awarded_title_id)

	if choice.granted_relic_id != &"":
		var relic = RelicPool.get_relic_by_name(String(choice.granted_relic_id))
		if relic and not RunManager.has_relic(relic.relic_name):
			RunManager.add_relic(relic)

	# A memory ("remembrance") card granted straight to the deck -- the one-off reward from
	# a memory event. add_card_to_deck duplicates it, so the deck owns a fresh instance.
	if choice.granted_card_id != &"":
		var mem = CardPool.get_memory_card(choice.granted_card_id)
		if mem:
			RunManager.add_card_to_deck(mem)

	# Accepting a plea arms a cross-map questline: the payoff node reveals on the next return
	# to the map (map_scene plays the arm flourish + objective toast). The raider payoff is
	# already seated at gen; the Campfire cache has no pre-placed node, so arming it first
	# picks + tags a node downstream of where the player stands (the event-selection gate
	# guaranteed one exists). A failed pick (shouldn't happen) just leaves the quest unarmed.
	if choice.arms_quest != &"":
		if choice.arms_quest == &"campfire":
			_arm_campfire_treasure()
		else:
			RunManager.arm_quest(choice.arms_quest)

	# Faction-aligned acts shift the realm's court<->folk standing.
	if choice.standing_change != 0:
		RunManager.change_realm_standing(RunManager.current_realm_id, choice.standing_change)

	# Queue a one-shot boon for the next combat (the Shade at the Cross's lent courage).
	if choice.grants_combat_boon != &"":
		RunManager.pending_combat_boon = choice.grants_combat_boon

	# Queue a skip of the next map node (the Tourney's walk-on shortcut).
	if choice.skips_next_node:
		RunManager.pending_skip_node = true

	# A quest item delivered by this choice leaves the pack; a companion joins it.
	if choice.spends_consumable != &"":
		RunManager.spend_consumable_by_id(choice.spends_consumable)
	if choice.grants_pet != &"":
		RunManager.set_pet(choice.grants_pet)

	# A forgotten relic woken at a record site: the one it had takes the dormant form's place.
	if choice.wakes_relic != &"":
		RunManager.wake_relic_by_name(String(choice.wakes_relic))

	# A refusal's curse (the higher tier of consequence): a permanent unplayable card wedged
	# into the run deck -- the spurned party's parting gift, dead weight for the rest of the run.
	if choice.grants_curse != &"":
		var curse = CardPool.get_curse_card(choice.grants_curse)
		if curse:
			RunManager.add_card_to_deck(curse)


func _show_effect_summary(choice: EventData.EventChoice) -> void:
	var parts: PackedStringArray = []
	if choice.hp_change > 0:
		parts.append("+%d HP" % choice.hp_change)
	elif choice.hp_change < 0:
		parts.append("%d HP" % choice.hp_change)
	if choice.max_hp_change > 0:
		parts.append("+%d Max HP" % choice.max_hp_change)
	elif choice.max_hp_change < 0:
		parts.append("%d Max HP" % choice.max_hp_change)
	if choice.gold_change > 0:
		parts.append("+%d Gold" % choice.gold_change)
	elif choice.gold_change < 0:
		parts.append("%d Gold" % choice.gold_change)
	if choice.passion_change > 0:
		parts.append("+%d Passion" % choice.passion_change)
	elif choice.passion_change < 0:
		parts.append("%d Passion" % choice.passion_change)
	if choice.standing_change > 0:
		parts.append("People's Favor +%d" % choice.standing_change)
	elif choice.standing_change < 0:
		parts.append("Court's Favor +%d" % -choice.standing_change)
	if choice.awarded_title_id != &"":
		var title_data := TitlePool.get_title(choice.awarded_title_id)
		if title_data:
			parts.append("Earned title: %s" % title_data.original_name)

	if choice.granted_relic_id != &"":
		var rel = RelicPool.get_relic_by_name(String(choice.granted_relic_id))
		if rel:
			parts.append("Acquired: %s" % rel.relic_name)

	if choice.granted_card_id != &"":
		var mem = CardPool.get_memory_card(choice.granted_card_id)
		if mem:
			parts.append("Remembered: %s" % mem.card_name)

	if choice.grants_combat_boon != &"":
		parts.append(_combat_boon_label(choice.grants_combat_boon))

	if choice.grants_consumable != &"":
		var offered := ConsumablePool.get_consumable(choice.grants_consumable)
		if offered:
			parts.append(("Acquired: %s" if _consumable_taken else "Left behind: %s") % offered.display_name)

	if choice.grants_pet != &"":
		var companion := PetPool.get_pet(choice.grants_pet)
		if companion:
			parts.append("%s joins you" % companion.display_name)

	if choice.wakes_relic != &"":
		var dormant := RelicPool.get_relic_by_name(String(choice.wakes_relic))
		if dormant and dormant.is_dormant():
			parts.append("Woken: %s" % dormant.wakes_into)

	if choice.skips_next_node:
		parts.append("Skip your next node")

	if choice.grants_curse != &"":
		var curse = CardPool.get_curse_card(choice.grants_curse)
		if curse:
			parts.append("Cursed: %s" % curse.card_name)

	if parts.size() > 0:
		var summary = Label.new()
		summary.text = ", ".join(parts)
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary.add_theme_font_size_override("font_size", 20)
		summary.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		main_vbox.add_child(summary)
		main_vbox.move_child(summary, main_vbox.get_child_count() - 2)


# ============================================================
# CARD REWARD (pick 1 of 3)
# ============================================================

func _show_card_reward(school: StringName = &"") -> void:
	follow_up_container.visible = true
	for child in follow_up_container.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Choose a card to add:"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	follow_up_container.add_child(header)

	# A tome choice biases the cards toward one school; otherwise a normal mixed reward.
	# The Gracious adds one more option to whichever offer this is.
	var pick_count := 3 + RunManager.get_card_reward_bonus()
	var cards: Array[CardData]
	if school == &"primary":
		cards = CardPool.get_school_reward_choices(
			RngManager.loot_rng, CardData.PersonalityType.PRIMARY, pick_count)
	elif school == &"secondary":
		cards = CardPool.get_school_reward_choices(
			RngManager.loot_rng, CardData.PersonalityType.SECONDARY, pick_count)
	else:
		cards = CardPool.get_reward_choices(RngManager.loot_rng, pick_count)

	# The 3 reward cards always fit, so center them across the full width. (A
	# ScrollContainer here pinned the row to the left, since it sizes its child to
	# content rather than stretching it — a CenterContainer that fills the width
	# centers the row to match the header above.)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	follow_up_container.add_child(center)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	center.add_child(row)

	for card in cards:
		var panel = _create_card_panel(card)
		row.add_child(panel)

	var skip_btn = Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(140, 40)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_on_skip_reward)
	follow_up_container.add_child(skip_btn)


func _create_card_panel(card: CardData) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 180)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	match card.card_type:
		CardData.CardType.ATTACK:
			style.bg_color = Color(0.3, 0.12, 0.1)
			style.border_color = Color(0.9, 0.25, 0.2)
		CardData.CardType.SKILL:
			style.bg_color = Color(0.1, 0.14, 0.3)
			style.border_color = Color(0.25, 0.45, 0.9)
		CardData.CardType.POWER:
			style.bg_color = Color(0.28, 0.24, 0.08)
			style.border_color = Color(0.9, 0.75, 0.15)

	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var cost_lbl = Label.new()
	cost_lbl.text = card.cost_label()
	cost_lbl.add_theme_font_size_override("font_size", 22)
	cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.3))
	vbox.add_child(cost_lbl)

	var name_lbl = Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = card.get_generated_description()
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	_ignore_mouse_recursive(vbox)

	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			RunManager.add_card_to_deck(card)
			follow_up_container.visible = false
			info_label.text += "  (Added %s)" % card.card_name
			_show_done()
	)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel


func _on_skip_reward() -> void:
	follow_up_container.visible = false
	_show_done()


# ============================================================
# CARD REMOVAL (pick 1 from deck)
# ============================================================

func _show_card_removal() -> void:
	if RunManager.current_deck.size() == 0:
		_show_done()
		return

	follow_up_container.visible = true
	for child in follow_up_container.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Choose a card to remove:"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	follow_up_container.add_child(header)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 200
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_up_container.add_child(scroll)

	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	scroll.add_child(row)

	for i in RunManager.current_deck.size():
		var card = RunManager.current_deck[i]
		var panel = _create_removal_panel(card, i)
		row.add_child(panel)

	var skip_btn = Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(140, 40)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	skip_btn.pressed.connect(_on_skip_removal)
	follow_up_container.add_child(skip_btn)


func _create_removal_panel(card: CardData, index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 140)

	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_border_width_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	match card.card_type:
		CardData.CardType.ATTACK:
			style.bg_color = Color(0.3, 0.12, 0.1)
			style.border_color = Color(0.9, 0.25, 0.2)
		CardData.CardType.SKILL:
			style.bg_color = Color(0.1, 0.14, 0.3)
			style.border_color = Color(0.25, 0.45, 0.9)
		CardData.CardType.POWER:
			style.bg_color = Color(0.28, 0.24, 0.08)
			style.border_color = Color(0.9, 0.75, 0.15)

	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var cost_lbl = Label.new()
	cost_lbl.text = card.cost_label()
	cost_lbl.add_theme_font_size_override("font_size", 20)
	cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.3))
	vbox.add_child(cost_lbl)

	var name_lbl = Label.new()
	name_lbl.text = card.card_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = card.get_generated_description()
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	_ignore_mouse_recursive(vbox)

	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var removed_name = card.card_name
			RunManager.remove_card_from_deck(index)
			follow_up_container.visible = false
			info_label.text += "  (Removed %s)" % removed_name
			_show_done()
	)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	return panel


func _on_skip_removal() -> void:
	follow_up_container.visible = false
	_show_done()


# ============================================================
# DONE
# ============================================================

func _show_done() -> void:
	var leave_btn = Button.new()
	leave_btn.text = "Continue"
	leave_btn.custom_minimum_size = Vector2(200, 55)
	leave_btn.add_theme_font_size_override("font_size", 20)
	leave_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_btn.pressed.connect(_on_leave)
	main_vbox.add_child(leave_btn)


## A Continue that advances to the next authored beat of a multi-stage event: stashes the
## next special-event id and reloads the event scene, which builds that beat.
func _show_next_beat(next_id: StringName) -> void:
	var btn = Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(200, 55)
	btn.add_theme_font_size_override("font_size", 20)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		RunManager.pending_special_event = next_id
		SceneTransition.change_scene("res://scenes/event/event_scene.tscn"))
	main_vbox.add_child(btn)


func _show_game_over() -> void:
	follow_up_container.visible = false
	info_label.text = "HP: 0 / %d" % RunManager.max_hp
	info_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

	var death_label = Label.new()
	death_label.text = "You have perished."
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 28)
	death_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	main_vbox.add_child(death_label)

	var game_over_btn = Button.new()
	game_over_btn.text = "Game Over"
	game_over_btn.custom_minimum_size = Vector2(200, 55)
	game_over_btn.add_theme_font_size_override("font_size", 20)
	game_over_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	game_over_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	game_over_btn.pressed.connect(_on_game_over)
	main_vbox.add_child(game_over_btn)


func _on_game_over() -> void:
	RunManager.end_run(false)
	SceneTransition.change_scene("res://scenes/game_over/game_over_scene.tscn")


func _on_leave() -> void:
	SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)
