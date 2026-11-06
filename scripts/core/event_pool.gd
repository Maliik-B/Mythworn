class_name EventPool
## Builds and returns random narrative events, from the pool of the route the run is standing on
## (RealmRoutes). A route with no events answers null, loudly: map_scene turns an event node on such
## a route into a fight before anything asks, so nothing else's event is ever served in its place.


static func get_random_event(rng: RandomNumberGenerator) -> EventData:
	var pool = _build_pool()
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## Like get_random_event, but drops events whose selection gate the caller can't satisfy.
## Currently that's only the treasure-reveal gate: the Campfire's cache needs a node downstream
## of the player to seat its fight, so when none exists the Campfire is excluded and a different
## event is drawn (rather than offering a "follow the map" choice that goes nowhere). Draws once
## from the filtered pool, so the rng advances exactly as the unfiltered draw would.
static func get_random_event_filtered(rng: RandomNumberGenerator, allow_treasure_reveal: bool) -> EventData:
	var pool := _build_pool()
	if pool.is_empty():
		return null
	if allow_treasure_reveal:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var filtered: Array[EventData] = []
	for e in pool:
		if not e.requires_treasure_payoff:
			filtered.append(e)
	if filtered.is_empty():
		filtered = pool
	return filtered[rng.randi_range(0, filtered.size() - 1)]


## The pool of the current route, refusing loudly if it has nothing to draw.
static func _build_pool() -> Array[EventData]:
	var pool := pool_for(RunManager.current_realm_id, RunManager.realm_config.route_id)
	if pool.is_empty():
		push_error("EventPool: route '%s' has no events. Its table is empty, so nothing was served."
			% RealmRoutes.current_key())
	return pool


## True if the route has random events to draw. Asking builds the pool and draws nothing.
static func has_events(realm_id: StringName, config_id: StringName) -> bool:
	return not pool_for(realm_id, config_id).is_empty()


## Every route's events. A route with a row and no events has not had its picks land.
static func pool_for(realm_id: StringName, config_id: StringName) -> Array[EventData]:
	var pool: Array[EventData] = []
	match RealmRoutes.key(realm_id, config_id):
		"camelot/base":
			pool = _camelot_pool()
		# Yggdrasil's first config, on the realm's affairs, and Journey to the West: empty until
		# their picks land. The stand-in edge has no events: its event slot is a fight.
		"yggdrasil/base", "yggdrasil/standin_edge", "journey_to_the_west/base":
			pass
		_:
			push_error("EventPool: no such route '%s'." % RealmRoutes.key(realm_id, config_id))
	return pool


static func _camelot_pool() -> Array[EventData]:
	var pool: Array[EventData] = []

	pool.append(_man_off_the_field())
	pool.append(_the_still_mere())
	pool.append(_forgotten_library())
	pool.append(_shade_at_the_cross())
	pool.append(_the_tiltyard())
	pool.append(_campfire_remnants())
	pool.append(_peasants_plea())
	pool.append(_scriptorium())
	pool.append(_the_tourney())
	pool.append(_last_cart_out())
	pool.append(_reliquary())

	return pool


# ============================================================
# EVENT DEFINITIONS
# ============================================================

## A reflavor of the generic Wounded Traveler. He is a man-at-arms off the field where Caedmon's
## own champion broke, so the Act-1 boss gets seeded by what a witness actually saw rather than by
## narration. Option 1 keeps The Merciful, the earliest and plainest of its grant sites. Option 3's
## self-deception is the one lie the man personally disproved two lines earlier, which makes the
## refusal specific and checkable instead of a vague shrug.
static func _man_off_the_field() -> EventData:
	var e = EventData.new()
	e.event_name = "The Man Off the Field"
	e.description = ("A man drags himself along the roadside ditch with one leg bound up in a "
		+ "surcoat he has torn for the purpose. You half-know the device on it, one of the lesser "
		+ "Camelot houses. He was a man-at-arms by the look of him, and he went where men-at-arms "
		+ "have been going.\n\n\"You're walking the wrong way,\" he says, when he gets a look at "
		+ "your face. \"Everyone with any sense is walking the way I came.\" He works a ring off a "
		+ "finger swollen fat around it and holds it up between two knuckles. \"I can pay. I just "
		+ "can't do the next mile on my own, and there's nobody else on this road. I've been "
		+ "counting.\"")

	var c1 = EventData.EventChoice.new()
	c1.text = "Splint it, and ask him what he ran from. (Lose 5 HP)"
	c1.result_text = ("You set the leg with his own scabbard for a splint and get his arm over your "
		+ "shoulder, and he pays you in talk the whole mile as well as in the ring. At the last stile "
		+ "he digs a horn box of salve out of his coat, something a barber-surgeon pressed on him "
		+ "that he never got round to opening. He was in the "
		+ "line when their own champion broke. Not broke and ran. Broke and kept fighting, badly, "
		+ "wrong, the way a hand works a puppet it has never watched a man use. \"His guard went "
		+ "first,\" he says. \"Then his face went. He was still winning.\" He does not know he is "
		+ "describing the thing you are walking toward, and you decide not to tell him.")
	c1.hp_change = -5
	c1.gold_change = 20  # was 30 before the salve: the tin is part of what he pays with
	c1.grants_consumable = &"traveller_salve"
	c1.passion_change = 3
	c1.awarded_title_id = &"the_merciful"

	var c2 = EventData.EventChoice.new()
	c2.text = "Take the ring. Tell him the road is busier than he thinks."
	c2.result_text = ("You take the ring and you tell him the road is busier than he thinks, and he "
		+ "thanks you for it, which is the worst part of the whole transaction. He has no leg to "
		+ "chase you with. He does have eyes, and they are on your back the entire length of the "
		+ "rise, and you can still feel the exact spot they were resting for a good while after the "
		+ "hedgerow takes him out of sight.")
	c2.gold_change = 20
	c2.passion_change = -5

	# Refusal with teeth: the lie is the one he disproved himself, two lines earlier, with "I've
	# been counting." So the self-deception is specific and checkable rather than a vague shrug.
	var c3 = EventData.EventChoice.new()
	c3.text = "Keep walking. Leave him even the ring."
	c3.result_text = ("You keep your legs moving and you do not take his ring, and you tell yourself "
		+ "somebody will be along for him shortly. He told you how long he had been counting. You "
		+ "heard him say it. The arithmetic walks up the rise with you and is still there at the top, "
		+ "and it is not the kind of sum that gets easier for being carried.")
	c3.passion_change = -3

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## A rework of the generic Ancient Shrine into water-country: the Lady under a still mere, and
## the pool's one carrier of wonder and beauty. The whole event turns on whether you let the
## water offer or take it yourself, so the Water-school card is gated behind waiting rather than
## behind a cost. No corruption beat; this is a place the rot has not been told about yet.
static func _the_still_mere() -> EventData:
	var e = EventData.new()
	e.event_name = "The Still Mere"
	e.description = ("The road drops into a green hollow you had no idea was there, and at the "
		+ "bottom of it lies a mere so still it has swallowed the whole sky and kept it. Reeds. "
		+ "Dragonflies stitching the warm air. After the grey miles behind you it is nearly too much "
		+ "to look at, a place the rot has simply not been told about yet.\n\nSomething pales under "
		+ "the surface, out where the water goes deep. Not a fish. It rises the way a held breath "
		+ "rises, unhurried, until an arm breaks the mere without putting a ripple on it and holds "
		+ "there, open-handed, waiting, with something just under the light.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Don't reach. Wait, and see what the water offers."
	c1.result_text = ("You do not reach. You wait, which is what the place seems to be asking for, "
		+ "and the hand comes to you. What it presses into your palm is cool and certain and gone to "
		+ "water the instant you look straight at it, but your hands keep the knowing of it: a way "
		+ "of moving you did not have this morning. When you look up, the mere is only a mere. You "
		+ "could nearly believe you dreamed the entire green hollow, except for what your hands now "
		+ "know how to do without being told.")
	c1.card_reward = true
	c1.card_reward_school = &"primary"
	c1.passion_change = 4

	var c2 = EventData.EventChoice.new()
	c2.text = "Kneel, drink, and leave something behind for it. (Lose 10 Gold)"
	c2.result_text = ("You cup the water and drink, and it is the cold of deep springs and it goes "
		+ "all the way down to your heels. You leave a coin in the shallows afterwards, because it "
		+ "feels wrong to take from a place like this one and leave nothing, a small courtesy for one "
		+ "you have been shown. When you stand there is a stoppered vial on the flat stone by the "
		+ "shallows, full of the mere and still cold, that was not there when you knelt. You walk up "
		+ "out of the hollow steadier than you walked into it, and you do not look back, in case it "
		+ "is gone.")
	c2.gold_change = -10
	c2.hp_change = 6  # was 12 before the blessing: the vial is part of what the water gives back
	c2.grants_consumable = &"bottled_blessing"
	c2.passion_change = 3

	var c3 = EventData.EventChoice.new()
	c3.text = "Wade out and take it yourself. (Lose 4 HP)"
	c3.result_text = ("You wade out and close your hand on the thing before it is offered. The water "
		+ "goes cold, and then dark, fast, the way a face closes. It is yours. It is. But the cold "
		+ "stays up in your arm long after the hollow is behind you, and the green place does not "
		+ "feel like a gift when you think back on it. It feels like somewhere you stole from.")
	c3.card_reward = true
	c3.hp_change = -4
	c3.passion_change = -6

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## A library is a choice of WHICH knowledge, so it carries more options than a normal event
## (four): two school-biased tomes, burning dead weight, and a search that turns up a surviving
## document rather than coin. A ruined library wouldn't hold a purse worth taking, but it might
## hold a relic from Bram's Records pool (the archive is his kind of place, even when he isn't
## standing in it). Four distinct acts: specialise toward your pole, specialise away from it,
## prune the deck, gamble HP for a find.
## (Water/Physical label the Emo Hybrid's schools; the demo only runs the one character.)
static func _forgotten_library() -> EventData:
	var e = EventData.new()
	e.event_name = "Forgotten Library"
	e.description = ("It was a manor's library once, before the crown's men or the rot or plain "
		+ "neglect took the roof off half of it. Rain has had years with most of the shelves. The "
		+ "deep rank under the surviving span is dry, though, and the spines you can still read fall "
		+ "into two hands: the flowing script of the water-scholars, and the blunt manuals of "
		+ "fighting men.")

	var cw = EventData.EventChoice.new()
	cw.text = "Study the water-scholar's tome. (Add a Water card)"
	cw.result_text = "The flowing script pulls you under. A current of technique settles into your hands."
	cw.card_reward = true
	cw.card_reward_school = &"primary"

	var cp = EventData.EventChoice.new()
	cp.text = "Study the soldier's manual. (Add a Physical card)"
	cp.result_text = ("Blunt diagrams and a dead man's notes down the margins. Your body remembers it "
		+ "before your mind does.")
	cp.card_reward = true
	cp.card_reward_school = &"secondary"

	var cb = EventData.EventChoice.new()
	cb.text = "Burn a useless page. (Remove a card)"
	cb.result_text = "You focus on what matters, feeding what holds you back to the one honest flame here."
	cb.remove_card = true

	var cr = EventData.EventChoice.new()
	cr.text = "Search the shelves for anything of worth. (Lose 4 HP)"
	cr.result_text = ("A needle hidden in a cracked spine bites your thumb. Then, behind the ruined "
		+ "rank, you turn up the one tome the rot never reached, the kind of surviving record Bram "
		+ "would have crossed a realm for, and it is worth far more than the coin you were hoping for.")
	cr.hp_change = -4
	cr.grants_liaison_relic = &"bram"

	e.choices.append(cw)
	e.choices.append(cp)
	e.choices.append(cb)
	e.choices.append(cr)
	return e


## Camelot liaison event: Bram (Records) turns up at an abbey scriptorium the crown has
## ordered burned, after one specific charter before it's ash -- institutional interest, not
## a personal file. FOLK-GATED option: a people-trusted keeper can have the town carry the
## whole archive out. Bram names Records without explaining Fable. His dry,
## tired voice per the liaison brief. (Camelot-flavored; the demo only runs this pool here.)
static func _scriptorium() -> EventData:
	var e = EventData.new()
	e.event_name = "The Scriptorium"
	e.description = ("The abbey's scriptorium has one lamp still burning. A copyist works under it "
		+ "fast and without hope, because the word came down the king's road at noon: the archive is "
		+ "to be ash by morning. Too many charters in these drawers say the wrong families held the "
		+ "wrong lands, and a king rewriting his claim would rather no older version survived to "
		+ "argue with him.\n\nA figure waits at the end of the long table who does not belong to the "
		+ "abbey. No habit, no tonsure. You know him. Bram, from Records, with his satchel of loose "
		+ "paper and the patience of a man who has watched a great many things get lost and stopped "
		+ "being surprised by it. \"There you are,\" he says, and taps the satchel. \"I'll be straight "
		+ "with you, I'm not here for the abbey. "
		+ "There's one charter in that stack I need copied before the torches come. A king who burns "
		+ "the old deeds means to write new ones, and somebody ought to keep the version that was "
		+ "true.\"")

	var c1 = EventData.EventChoice.new()
	c1.text = "Sit down and copy with him until dawn."
	c1.result_text = ("You take up a second pen. Bram writes in a fast, ugly, legible hand, and "
		+ "between the two of you the charter is copied twice before the gray light comes. He blots "
		+ "the last line and tucks both copies into the satchel. \"Good. Two of them now. Harder to "
		+ "lose two.\" He leaves a folded page on the table as he goes, a copyist's old marginal "
		+ "notes on a technique you hadn't considered. \"For your trouble.\"")
	c1.card_reward = true
	c1.passion_change = 3

	# Folk-gated: only a keeper the people already trust can raise the whole town in a night.
	# The aligned big outcome -- the entire archive saved, not just Bram's one page. Per the
	# faction-reward principle (folk events pay in relics), Bram's thanks is a Records relic from
	# his dedicated pool, not a card -- and the prose already reads like an object pressed on you.
	var cf = EventData.EventChoice.new()
	cf.text = "Wake the town and carry the whole archive out before the torches come."
	cf.result_text = ("You go door to door, and the people who trust you come out into the cold "
		+ "without asking much why. By the time the crown's men arrive the shelves stand bare, the "
		+ "charters scattered into a dozen cellars down the valley. Bram looks at the empty room with "
		+ "open astonishment. \"I came for one page,\" he says. \"You saved the lot of it.\" He digs "
		+ "something out of a cellar box and presses it into your hands before he leaves.")
	cf.requires_favor = &"folk"
	cf.grants_liaison_relic = &"bram"
	cf.gold_change = 20
	cf.passion_change = 4
	cf.standing_change = 10

	var c2 = EventData.EventChoice.new()
	c2.text = "Strip the gilt and gemwork from the bindings. They burn either way."
	c2.result_text = ("You pry the stones and gold leaf from the old covers while the copyist "
		+ "pretends not to watch. The words are ash by morning and the gilt is in your purse. Bram "
		+ "says nothing to you. He only writes something short to himself, and does not offer to show "
		+ "you what.")
	c2.gold_change = 40
	c2.passion_change = -6

	var c3 = EventData.EventChoice.new()
	c3.text = "There is nothing here worth losing sleep over. Leave."
	c3.result_text = ("You take the road before the smoke starts. Bram does not try to stop you. He "
		+ "has watched people walk away from burning rooms before. \"Safe travels,\" he says, and "
		+ "means about half of it.")
	c3.passion_change = -2
	c3.standing_change = -4  # leaving the archive to burn is a small mark against you with the folk

	e.choices.append(c1)
	e.choices.append(cf)
	e.choices.append(c2)
	e.choices.append(c3)
	# A keeper carrying a forgotten relic may ask the record for it: one option per dormant relic
	# held, none shown otherwise, so the site does the telling. It costs nothing but the event's
	# other options (ROADMAP Phase 1, "Forgotten relics").
	for relic in RunManager.get_forgotten_relics():
		var wake = EventData.EventChoice.new()
		wake.text = "Put %s on the table under the lamp, and ask Bram what the record says of it." % relic.short_name
		wake.result_text = ("Bram turns it to the light and does not hurry. He goes through the "
			+ "satchel twice and the drawers once, and comes back with a page he does not let you "
			+ "read. \"There,\" he says. \"That one was written down.\" " + relic.wake_line
			+ " He watches you put it away. \"Keep it out of the fire,\" he says, which is the "
			+ "nearest he comes to a blessing.")
		wake.wakes_relic = StringName(relic.relic_name)
		e.choices.append(wake)
	return e


## Camelot court event: a tourney still bright in a rotting realm. The open option (wager on
## the commoner) is the populist reward; entering the lists for the real prize is COURT-GATED
## (the marshal only lifts the rope for a keeper the crown backs). Mirror of the Scriptorium's
## folk gate on the court side. Surface Arthurian spectacle with the rot showing underneath.
static func _the_tourney() -> EventData:
	var e = EventData.new()
	e.event_name = "The Tourney"
	e.description = ("The tourney field is loud and bright, and that is the first wrong thing about "
		+ "it. You have walked three days through a realm that has forgotten how to make noise, and "
		+ "here is a whole field of it: pennants, trumpets, a crowd in its colours, as though nobody "
		+ "has told them. Down the lists two knights couch their lances and ride, and the crowd makes "
		+ "the noise crowds make.\n\nLook closer and you see how many of the cheering faces hold too "
		+ "still, and how one champion's shield has gone plain to the rim, and how his squire keeps "
		+ "turning it from the stands as if that would hide it. Wagers pass hand to hand at the rail. "
		+ "A marshal takes names for the open challenge, and looks hard at who he lets past the rope.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Wager a purse on the commoner in the plain harness."
	# An actual bet, not a payout: the underdog usually has it, but not always. Backing him
	# openly is the pro-folk gesture win or lose, so passion and standing land either way --
	# only the gold rolls (gamble_win_gold / gamble_lose_gold).
	c1.gamble_chance = 0.55
	c1.gamble_win_gold = 30  # was 40 before the favour: the ribbon is part of the winnings
	c1.gamble_lose_gold = -25
	c1.gamble_win_text = ("You back the man with no device on his shield, and the stands laugh at you "
		+ "for it, until he puts the noble gone grey in the dirt and stands over him breathing clean "
		+ "and hard. The man at the rail counts out your winnings with a sour face. Across the field the "
		+ "commoner catches your eye and touches two fingers to his brow. A woman who put her own purse on "
		+ "him leans over the rail and ties a length of blue ribbon to your sleeve, and says nothing "
		+ "about it.")
	c1.gamble_lose_text = ("You back the man with no device on his shield, and for three passes he "
		+ "rides like he will shame the lot of them. Then the grey noble's lance catches him "
		+ "under the arm and he goes down and is slow to rise. The man at the rail rakes in your stake without "
		+ "meeting your eye. Across the field they get the commoner back to his knees; he finds you in "
		+ "the crowd anyway, and touches two fingers to his brow. The woman beside you, who lost on him "
		+ "too, unties the ribbon she meant for his lance and ties it on your sleeve instead, and does "
		+ "not explain.")
	c1.grants_consumable = &"champions_favour"
	c1.passion_change = 2
	c1.standing_change = 5

	# Court-gated: the marshal only lifts the rope for a name the crown stands behind. The real
	# reward (a technique from a master-at-arms) sits behind court favor; a folk-pledged keeper
	# is turned away at the rope, the way the Scriptorium turns a court keeper away from the folk.
	var cc = EventData.EventChoice.new()
	cc.text = "Give the marshal your name and ride in the open challenge. (Lose 8 HP)"
	cc.result_text = ("The marshal weighs your name, or the weight behind it, and lifts the rope. "
		+ "They find you a horse and a lance. The ride is short and it hurts, because a lance on the "
		+ "shield is a hammer-blow even when you keep your seat. You put your man in the dirt anyway, "
		+ "and the stand roars for you. Afterward an old master-at-arms who liked your seat shows you "
		+ "a way of closing the distance you will not forget.")
	cc.requires_favor = &"court"
	cc.hp_change = -8  # jousting hurts, even when you win the pass
	cc.card_reward = true
	cc.passion_change = 4
	cc.standing_change = -4

	var c3 = EventData.EventChoice.new()
	c3.text = "Watch a single pass, then slip out and take the drovers' road. (Skip the next node)"
	c3.result_text = ("You stay for one ride and leave while the crowd is still on its feet. Behind the "
		+ "stands a drovers' track cuts the long bend off the king's road, and you take it at a hard "
		+ "walk. You have seen enough of this place. The shortcut puts the next trouble on the road "
		+ "well behind you.")
	c3.passion_change = 3
	c3.skips_next_node = true

	e.choices.append(c1)
	e.choices.append(cc)
	e.choices.append(c3)
	# The herald's roll of arms reads a device back: one waking option per dormant forgotten relic
	# the keeper carries, none otherwise. It costs nothing but the event's other options.
	for relic in RunManager.get_forgotten_relics():
		var wake = EventData.EventChoice.new()
		wake.text = "Take %s to the herald's tent and ask him to read it." % relic.short_name
		wake.result_text = ("The herald is an old man with a roll of arms longer than he is, and the "
			+ "eyes for it still. He unrolls it along the trestle a hand's width at a time, and "
			+ "stops, and puts a finger on the vellum. \"I know that,\" he says. \"I know whose "
			+ "that was.\" " + relic.wake_line + " He says a name, and the noise of the field "
			+ "takes most of it, and you keep the rest. Then he rolls the roll back up and goes "
			+ "to call the next pass.")
		wake.wakes_relic = StringName(relic.relic_name)
		e.choices.append(wake)
	return e


## Camelot liaison event: Neve (Dispatch) on-site running a village evacuation ahead of the
## corruption. Help wholeheartedly, help while covering your own escape, or walk on. Her warm,
## worried-veteran voice (and a touch of old-coworker familiarity with the keeper) per the
## brief. The notebook is flavor and is never explained. Folk-leaning standing, and the
## wholehearted help earns a Dispatch relic from her pool (folk events pay in relics, per §D).
static func _last_cart_out() -> EventData:
	var e = EventData.new()
	e.event_name = "The Last Cart Out"
	e.description = ("The village is emptying the way water leaves a cracked basin, quick at first "
		+ "and then a slow hopeless trickle of the people who had least to pack. The chaos is "
		+ "two valleys off and coming. You cannot see it yet. You can tell exactly where it is "
		+ "anyway, by the quiet: no birds over that stretch of wood, not one, and the cattle have "
		+ "all drifted to the far fences and stand there with their heads low and their backs to "
		+ "the trees, refusing to look at what is behind them. In the square too few carts are "
		+ "being loaded by too many hands.\n\nNeve is in the thick of it with a battered notebook, sending each cart off in "
		+ "its turn and marking something down as it rolls. She is not dressed for the field and does "
		+ "not seem to care. When she sees you her face does something complicated. \"Of course it's "
		+ "you. It's always you where it's worst.\" She jerks her chin at a stalled wagon. \"Don't "
		+ "stand there looking noble. There's a wheel off the miller's cart, and he's got six "
		+ "children and a grandmother.\"")

	var c1 = EventData.EventChoice.new()
	c1.text = "Get under the axle and lift."
	c1.result_text = ("You set your shoulder under the axle while the miller seats the wheel, and "
		+ "you leave some skin behind doing it, but the cart rolls and the children and the "
		+ "grandmother roll with it. Neve works you like a draft animal after that, cart to cart, "
		+ "until the square stands empty and the quiet is close enough to hear. \"There,\" she says, "
		+ "breathless. \"Now you look how you ought to.\" She digs in her own pack and presses a piece "
		+ "of her kit into your hands before you can wave it off. \"You'll want this worse than I "
		+ "will, where you're going.\" Then she marks one last line in the notebook and does not let "
		+ "you see it.")
	c1.hp_change = -4
	c1.passion_change = 5
	c1.standing_change = 7
	c1.awarded_title_id = &"the_compassionate"
	c1.grants_liaison_relic = &"neve"

	var c2 = EventData.EventChoice.new()
	c2.text = "Help, but keep yourself a place on the last cart out."
	c2.result_text = ("You help, and you are good at it, but you keep one eye on the last wagon and a "
		+ "hand near its rail the whole while. Nobody is left behind that you could have carried, and "
		+ "you are not on foot when the gray comes over the ridge. Neve notices, because Neve notices "
		+ "everything, and says nothing, which is worse. She presses coin into your hand for the road "
		+ "regardless. \"Go on. Careful is a kindness too. Mostly to yourself.\"")
	c2.gold_change = 18
	c2.passion_change = 2
	c2.standing_change = 3

	var c3 = EventData.EventChoice.new()
	c3.text = "They have their own people for this. Move on."
	c3.result_text = ("You tell her it is not your evacuation to run. She looks at you a moment the "
		+ "way she does when she is deciding not to argue. \"No,\" she agrees. \"It isn't.\" She turns "
		+ "back to her carts. You feel her not-arguing for a mile down the road.")
	c3.passion_change = -3
	c3.standing_change = -6  # walking out on the evacuation costs you with the people

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## A reflavor of the generic Wandering Spirit: a knight who knelt at a wayside cross rather than
## meet what came up the valley, and never got up again. Carries the realm's chivalric-honour
## register with no corruption beat. The sword in the grass is a specific object with a reason it
## is still lying there (nobody uses this track), and option 2 points at it so the image pays off
## instead of just decorating. Locale is a crossroads, not a chapel.
static func _shade_at_the_cross() -> EventData:
	var e = EventData.new()
	e.event_name = "The Shade at the Cross"
	e.description = ("A wayside cross stands where two tracks meet, and a man kneels at the foot of "
		+ "it who is not all the way there. You can see the grain of the wood through his shoulders. "
		+ "The sword he knelt down beside is still lying in the grass where he let go of it, and "
		+ "nobody has come along this track in long enough for the weather to have had the whole "
		+ "thing: pitted black, the edge gone to crumbs, the grip rotted off the tang and only the "
		+ "wire left. He does not look up.\n\n\"I put it down there,\" he says, as though you had "
		+ "asked. \"The thing came up the valley and I found I had nothing in me to meet it with, so "
		+ "I knelt here to pray instead, and the praying never finished. Will you hear how a man gets "
		+ "to this? I have had nobody to tell. The ones who come past don't stop, and I don't blame "
		+ "them, and I would like very much to be blamed by somebody.\"")

	var c1 = EventData.EventChoice.new()
	c1.text = "Kneel with him and hear it out."
	c1.result_text = ("You kneel in the wet grass and let him tell it: the whole shabby, human shape "
		+ "of the thing, the courage that was simply not there when it was called for. When it is "
		+ "told, something in him comes unclenched that has been clenched a long time, and he thins "
		+ "out into the evening noticeably lighter than he was. What he leaves behind settles into "
		+ "you as a kind of steadiness. You will not kneel here. Not you, not at a crossroads, not "
		+ "for years.")
	c1.passion_change = 4
	c1.awarded_title_id = &"the_gracious"  # hearing out the lonely dead: grace, not mercy

	var c2 = EventData.EventChoice.new()
	c2.text = "Ask him to lend you the courage he never spent."
	c2.result_text = ("He looks at the sword in the grass, then at the one on your hip. \"Let me "
		+ "spend on you what I couldn't spend on myself,\" he says, and closes your fist around "
		+ "something that is not quite there. It sits in your palm as cold as a coin kept in a well, "
		+ "and it does not fade. It waits for you to ask. One hard fight it will carry you. Then it "
		+ "will be spent, the way he was spent, and you will be on your own with it again.")
	# Held, not spent for you: the same courage the Shade used to lend at the start of the next
	# fight, now carried until the player picks the fight. The part 3 migration that proves the layer.
	c2.grants_consumable = &"unspent_courage"

	# Refusal with teeth (higher tier): scattering him for the gilt leaves a lingering curse, a
	# permanent unplayable card. The gold is real, but so is the price.
	var c3 = EventData.EventChoice.new()
	c3.text = "Scatter him, and get the gilt off the cross."
	c3.result_text = ("You wave him apart and he goes like breath off a window, and you work the old "
		+ "gold leaf off the cross with your knife while the going is good. Not all of him scatters. "
		+ "Some of whatever kept him kneeling catches in you the way a burr catches, cold and "
		+ "unfinished and unspent, and it is still there in the morning, and it is still there the "
		+ "week after that.")
	c3.gold_change = 25
	c3.passion_change = -4
	c3.grants_curse = &"clinging_grief"

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## A rework of the generic Training Grounds, kept in Camelot because a tiltyard is not generic
## furniture: the pell, the quintain and the butts are the apparatus of chivalric training, which
## is this realm's own subject matter. Empty is better still, since the men who drilled here went
## where the player is going. It carries resolve and quiet hope, the register nothing else in the
## pool covers, and option 3 is a genuinely warm mundane beat. Mechanics are unchanged from the
## original, so the rework carries no balance risk.
static func _the_tiltyard() -> EventData:
	var e = EventData.new()
	e.event_name = "The Tiltyard"
	e.description = ("The yard behind the manor wall still has its gate standing open. The pell is "
		+ "there, the man-high oak post squires beat at until the arm learns a stroke without being "
		+ "asked, scarred white on every face and splintered down one side. The quintain still stands "
		+ "at the far end with its arm swung round and stopped, the sandbag counterweight long since "
		+ "split and bled out into the grass. The archery butts have gone to seed. And somebody has "
		+ "stacked the practice harness against the wall in its proper order, every piece where it "
		+ "belongs, the way men leave a place they fully intend to come back to.\n\nNobody is "
		+ "coming back to this one. You know where the men who trained here went. You are walking "
		+ "the road they took.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Strip to your shirt and work the pell. (Lose 3 HP)"
	c1.result_text = ("You go at the post the way you were taught, or the way somebody was taught, "
		+ "and after a while it stops being effort and starts being rhythm. The oak gives you nothing "
		+ "back, which is the entire point of oak. By the time your arms are shaking there is a "
		+ "stroke in them that was not in them this morning. Somebody's stroke, worked into this post "
		+ "across years of afternoons, and yours now, because there is nobody else left to come and "
		+ "have it.")
	c1.hp_change = -3
	c1.card_reward = true
	c1.passion_change = 2

	var c2 = EventData.EventChoice.new()
	c2.text = "Take the harness. It's good kit and it's going to rot."
	c2.result_text = ("It is good harness, better than yours in places, and in a month it will be "
		+ "rust and mould and mouse-nest. So you take what fits and bundle the rest to sell on down "
		+ "the road, and the flask of armourer's oil from the shelf behind it, which will not keep "
		+ "either. You do have to unstack it to do that. Putting a dead man's kit out of the order "
		+ "he left it in is a smaller thing than it feels like, and it feels like something.")
	c2.gold_change = 12  # was 20 before the oil: the flask is part of what the yard gives up
	c2.grants_consumable = &"blade_oil"
	c2.passion_change = -2

	var c3 = EventData.EventChoice.new()
	c3.text = "Put your back to the wall and do nothing at all."
	c3.result_text = ("You sit against the south wall, where the stone has been holding the sun all "
		+ "afternoon, and you do not train and you do not take anything. For a quarter of an hour the "
		+ "only thing happening anywhere in the world is a blackbird working the seeded butts for "
		+ "grubs. Somewhere in it a hound comes out of the kennel by the gate, grey in the muzzle, "
		+ "and lies down against your boot as though that were what the afternoon was for. Then you "
		+ "get up and go on. It was enough. The hound goes with you and does not ask whose yard this "
		+ "was. You will think about that quarter of an hour again later, at a considerably worse "
		+ "time, and it will still be enough.")
	c3.hp_change = 5  # was 8 before the hound: the dog is part of what the quiet gives back
	c3.grants_pet = &"hound"

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## Camelot within-realm lore event (the "good-feeling pass" step 2). A village bled
## dry by the crown's tithe begs relief — leaning into the court-vs-folk axis the "A
## Realm Divided" pledge sets up. Helping is the keeper letting his guard down, so it
## moves Passion toward Water (+); the cold, crown-serving choice hardens him (-).
## Arthurian flavor. (Flavor is medieval/Camelot; the demo
## only ever runs this pool in Camelot. Multi-realm pools will need realm-filtering.)
static func _peasants_plea() -> EventData:
	var e = EventData.new()
	e.event_name = "The Peasant's Plea"
	e.description = ("The village sits where the king's road bends, and it is too quiet for the hour. "
		+ "No smoke off the bake-ovens. A cart stands half-loaded in the square with nobody minding "
		+ "it. The people who come out to meet you come slow, the way you'd approach a strange "
		+ "dog.\n\nAn old woman speaks for them. \"You came down the king's road with a sword on "
		+ "you, so you're his or you're not. Either way, you'll want to hear it.\" She nods at the "
		+ "cart. Grain sacks, a crate of thin hens, a coffer. \"The collector rides in at dawn "
		+ "for the crown's share. He took the seed-corn last winter. He'll take it again, and we'll "
		+ "be chewing the thatch by spring.\"\n\nA child watches from a doorway. Nobody tells them to "
		+ "go inside.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Pay the crown's share yourself. (Lose 50 Gold)"
	c1.result_text = ("You count the coin into the old woman's hands. It is more than the collector "
		+ "will expect, and he will not think to ask where it came from. That night the village "
		+ "feeds you at its own thin table. An old campaigner who soldiered for the last king sits "
		+ "with you late, showing you a trick of his he says the young ones never have the patience "
		+ "to learn. In the morning the old woman puts a loaf in your hands, still warm in its cloth, "
		+ "because it is the one thing they have left to give.")
	c1.grants_consumable = &"loaf"
	c1.gold_change = -50
	c1.passion_change = 5
	c1.card_reward = true
	c1.awarded_title_id = &"the_gracious"  # paying their debt from your own purse -- open-handed
	c1.standing_change = 8  # sparing the folk, the way anyone could

	var c2 = EventData.EventChoice.new()
	c2.text = "Take the crown's share yourself, and your own cut with it."
	c2.result_text = ("You tell them you will see the king's due collected. They are almost grateful, "
		+ "until they understand you mean to carry it off tonight, ahead of the collector. You take "
		+ "the coffer and a measure of the grain. Nobody tries to stop a sword. By the time you "
		+ "reach the trees, the quiet behind you has a different weight to it.")
	c2.gold_change = 45
	c2.passion_change = -6
	c2.awarded_title_id = &"the_calculating"
	c2.standing_change = -12  # robbing them like a collector turns the people against you

	var c3 = EventData.EventChoice.new()
	c3.text = "This is not your realm to set right. Walk on."
	c3.result_text = ("You tell her it isn't yours to mend, which is true, and you take the road out "
		+ "before the sun is up. It is an easy enough thing to say. A mile of walking hasn't made "
		+ "it sit any easier.")
	c3.passion_change = -3
	c3.standing_change = -6  # turning your back on the folk costs you their regard

	# Folk-gated: only a keeper the people already trust can ask them to conspire. Opens for
	# a Folk-pledged hero (and anyone who has earned the people's favor); locked otherwise with
	# "Need: Favor of the People". The aligned boon -- Pay's outcome without the gold cost.
	var cf = EventData.EventChoice.new()
	cf.text = "Have the village hide its stores before the collector rides in."
	cf.result_text = ("They don't argue. People who trust you move fast. By the time the gray "
		+ "light comes up the grain and the seed-corn are gone, into cellars and hollow logs and "
		+ "the thatch itself. The village wears the face of a place with nothing left worth taking, "
		+ "and the collector will believe it. He has seen enough real famine to know the look. The "
		+ "old campaigner who stayed to help you work shows you a trick with a blade while you wait "
		+ "out the dark.")
	cf.requires_favor = &"folk"
	cf.passion_change = 6
	cf.card_reward = true
	cf.awarded_title_id = &"the_merciful"
	cf.standing_change = 12

	# Court-gated: only a keeper the crown already backs can wave its own levy aside. Opens for
	# a Court-pledged hero (and anyone who has earned the court's favor); locked otherwise with
	# "Need: Favor of the Court". Effortless authority -- no gold, no risk, but no growth either.
	var cc = EventData.EventChoice.new()
	cc.text = "Ride ahead and tell the collector the crown forgives this village's share."
	cc.result_text = ("You find the collector on the road at first light and tell him, in the "
		+ "crown's name, that this village is forgiven its share this season. He doesn't like it. "
		+ "But he knows whose voice you carry, and it is not one he can afford to argue with, so he "
		+ "turns his cart around. He hands you the writ he was meant to serve, the seal unbroken. If "
		+ "anyone asks why this village paid nothing this season, he would rather the answer was in "
		+ "your hand than his. The village will never learn how close it came. You will.")
	cc.grants_consumable = &"writ"
	cc.requires_favor = &"court"
	cc.passion_change = 3
	cc.awarded_title_id = &"the_gracious"  # a gracious pardon in the crown's name
	cc.standing_change = -4

	e.choices.append(c1)
	e.choices.append(cf)
	e.choices.append(cc)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## The Reliquary (entry beat) -- the multi-stage memory event. Appears in the random rotation
## like any event, but it unfolds: approaching is struck (the HP cost) and chains to the
## fading-memory choice (reliquary_struck), which can launch the chapel-beast fight and pay off
## in reliquary_won. Here the player is only warned: the chapel "takes a memory for every one
## it gives". Camelot-flavored.
static func _reliquary() -> EventData:
	var e = EventData.new()
	e.event_name = "The Reliquary"
	e.description = ("A wayside chapel, small and old, the kind that holds one saint's relic and the "
		+ "worn-smooth prayers of everyone who ever passed. The gold leaf on its door has gone the "
		+ "grey of everything the chaos has touched. Someone has driven a stake into the ground at "
		+ "the edge of the yard and tied a rag to it. You have learned what that means on a road "
		+ "like this. No closer.\n\nAn old man working the hedge watches you weigh the door. \"They "
		+ "go in to remember someone,\" he says, not stopping his shears. \"Comes of the chapel "
		+ "being what it was. And they come out having lost something else for it, the ones that "
		+ "come out. Takes a memory for every one it gives. Never did learn to trade fair.\"")

	var approach = EventData.EventChoice.new()
	approach.text = "Cross the yard to the door anyway. (Lose 6 HP)"
	approach.result_text = ("You step past the stake and its rag, and the air at the lychgate goes "
		+ "thick and close, like the pause before a church bell. Something strikes through you "
		+ "before you reach the step. Not a blow you could have blocked. More like a hand closing "
		+ "somewhere behind your ribs. You get a palm flat against the cold grey door and hold "
		+ "there, and the chapel opens its one memory to you.")
	approach.hp_change = -6
	approach.next_event_id = &"reliquary_struck"
	e.choices.append(approach)

	var heed = EventData.EventChoice.new()
	heed.text = "Heed the warning. Keep to the road."
	heed.result_text = ("You leave the stake and its rag where they stand and walk on. The old man "
		+ "nods to himself and goes back to his hedge, having said his piece to one more traveler "
		+ "who had the sense to hear it. Whatever the chapel keeps, it keeps without you.")
	heed.passion_change = 2
	e.choices.append(heed)

	return e


## The fire is days cold, but the camp tells a story: these were diggers who broke open an old
## barrow, got the grave-goods out, and fled whatever was laid in with them -- leaving a journal
## whose last page maps where they cached the haul. Reading it ARMS a treasure node down the
## road (arms_quest = &"campfire"), which reveals on the next map return and pays off a strong
## fight (the barrow-warden) for extra gold + a relic. requires_treasure_payoff gates the whole
## event out when the fire would fire too late to seat that node, so the map-choice is never dead.
static func _campfire_remnants() -> EventData:
	var e = EventData.new()
	e.event_name = "Campfire Remnants"
	e.requires_treasure_payoff = true
	e.description = ("The fire is days cold, but the camp is barely a week abandoned: bedrolls "
		+ "still laid out, a cook-pot tipped where someone kicked it rising. These were diggers, "
		+ "not travellers: mattocks, a coil of rope, and in the rise behind the camp an old barrow "
		+ "stands open, its capstone levered aside. Whatever they pulled out of it, they left in "
		+ "too much of a hurry to take their own gear. A journal lies open in the ashes, a map "
		+ "sketched across its last page.")

	var investigate = EventData.EventChoice.new()
	investigate.text = "Read the journal, and follow its map."
	investigate.result_text = ("The last pages are one man's hand going ragged. They broke the "
		+ "barrow for a lord's grave-goods and got them clear, and then the thing laid in with the "
		+ "gold stood up. They cached the haul further down the road, somewhere they prayed it "
		+ "couldn't follow, and ran, and the writing stops mid-word. The map is clear enough. The "
		+ "mark sits further along your way.")
	investigate.arms_quest = &"campfire"
	investigate.passion_change = 2  # the pull of the hunt
	e.choices.append(investigate)

	var rest = EventData.EventChoice.new()
	rest.text = "Use their wood, and sleep in their camp."
	rest.result_text = ("Their firewood is still dry under a scrap of canvas, which is the only "
		+ "reason you get a fire at all, and it occurs to you while you are laying it that "
		+ "somebody's small foresight is keeping you warm a week after it stopped doing him the "
		+ "least bit of good. You right the cook-pot, scrape out what has dried hard in the bottom "
		+ "of it, and boil your own supper in a dead man's pot.

You sleep in the bedroll "
		+ "furthest from the barrow. Not for any reason you would say out loud. In the morning you "
		+ "are warm and whole and slower to get up than you ought to be, and you fold the bedroll "
		+ "back the way you found it before you go, which helps nobody at all.")
	rest.hp_change = 12
	e.choices.append(rest)

	var loot = EventData.EventChoice.new()
	loot.text = "Strip the camp and move on."
	loot.result_text = ("You take what's worth carrying: the rope, a whetstone, a little coin sewn "
		+ "into a bedroll against exactly this, and a supper of bread and hard meat wrapped in a dead "
		+ "man's cloth that will keep. Better your pack than the crows'. You leave the "
		+ "journal where it lies.")
	loot.gold_change = 10  # was 18 before the supper: the cloth is part of what the camp leaves
	loot.grants_consumable = &"cold_supper"
	loot.passion_change = -2
	e.choices.append(loot)

	return e
