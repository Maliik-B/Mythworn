class_name EventPool
## Builds and returns random narrative events.


static func get_random_event(rng: RandomNumberGenerator) -> EventData:
	var pool = _build_pool()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _build_pool() -> Array[EventData]:
	var pool: Array[EventData] = []

	pool.append(_wounded_traveler())
	pool.append(_ancient_shrine())
	pool.append(_forgotten_library())
	pool.append(_ominous_statue())
	pool.append(_wandering_spirit())
	pool.append(_training_grounds())
	pool.append(_suspicious_chest())
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

static func _wounded_traveler() -> EventData:
	var e = EventData.new()
	e.event_name = "Wounded Traveler"
	e.description = "A traveler lies wounded by the roadside, clutching a leather pouch. They look up at you with desperate eyes.\n\n\"Please... help me. I can pay.\""

	var c1 = EventData.EventChoice.new()
	c1.text = "Tend to their wounds (Lose 5 HP)"
	c1.result_text = "You bandage their injuries. Grateful, they press a handful of coins into your palm before limping away."
	c1.hp_change = -5
	c1.gold_change = 30
	c1.passion_change = 3
	c1.awarded_title_id = &"the_merciful"

	var c2 = EventData.EventChoice.new()
	c2.text = "Take their pouch and leave"
	c2.result_text = "You snatch the pouch. The traveler says nothing, but their eyes follow you as you walk away."
	c2.gold_change = 20
	c2.passion_change = -5

	var c3 = EventData.EventChoice.new()
	c3.text = "Walk away"
	c3.result_text = "You continue on your path. Some problems aren't yours to solve."

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


static func _ancient_shrine() -> EventData:
	var e = EventData.new()
	e.event_name = "Ancient Shrine"
	e.description = "A crumbling stone shrine stands among twisted roots. Faded runes pulse with faint light. The air hums with old power.\n\nYou sense it could still grant a boon... for a price."

	var c1 = EventData.EventChoice.new()
	c1.text = "Pray at the shrine"
	c1.result_text = "Warmth floods through you as the runes flare. Your spirit feels renewed."
	c1.hp_change = 10
	c1.passion_change = 5

	var c2 = EventData.EventChoice.new()
	c2.text = "Desecrate it for materials"
	c2.result_text = "You pry gems from the stonework. The light dies. Something in the air shifts, disappointed."
	c2.gold_change = 40
	c2.passion_change = -8

	var c3 = EventData.EventChoice.new()
	c3.text = "Study the runes carefully"
	c3.result_text = "The runes reveal forgotten knowledge. A new technique crystallizes in your mind."
	c3.card_reward = true
	c3.awarded_title_id = &"the_calculating"

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## A library is a choice of WHICH knowledge, so it carries more options than a normal event
## (five): two school-biased tomes, a strange untitled one, burning dead weight, and a search
## that turns up a relic rather than coin -- a ruined library wouldn't hold a purse worth taking.
## (Water/Physical label the Emo Hybrid's schools; the demo only runs the one character.)
static func _forgotten_library() -> EventData:
	var e = EventData.new()
	e.event_name = "Forgotten Library"
	e.description = ("Shelves of rotting books line a hidden alcove. Most are ruined, but a few tomes "
		+ "remain intact, and the spines you can still read fall into two hands -- the flowing script "
		+ "of the water-scholars and the blunt manuals of fighting men. One book has no title at all.")

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

	var cs = EventData.EventChoice.new()
	cs.text = "Open the book with no title. (Add a card)"
	cs.result_text = ("The pages are wrong somehow, and afterward you cannot say what you read. But "
		+ "something in it took.")
	cs.card_reward = true

	var cb = EventData.EventChoice.new()
	cb.text = "Burn a useless page. (Remove a card)"
	cb.result_text = "You focus on what matters, feeding what holds you back to the one honest flame here."
	cb.remove_card = true

	var cr = EventData.EventChoice.new()
	cr.text = "Search the shelves for anything of worth. (Lose 4 HP)"
	cr.result_text = ("A needle hidden in a cracked spine bites your thumb -- but behind the ruined "
		+ "rank you turn up the one tome the rot never reached, and it is worth far more than the coin "
		+ "you were hoping for.")
	cr.hp_change = -4
	cr.grants_random_relic = true

	e.choices.append(cw)
	e.choices.append(cp)
	e.choices.append(cs)
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
		+ "abbey. No habit, no tonsure. You know him — Bram, from Records, with his satchel of loose "
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
	# The aligned big outcome -- the entire archive saved, not just Bram's one page.
	var cf = EventData.EventChoice.new()
	cf.text = "Wake the town and carry the whole archive out before the torches come."
	cf.result_text = ("You go door to door, and the people who trust you come out into the cold "
		+ "without asking much why. By the time the crown's men arrive the shelves stand bare, the "
		+ "charters scattered into a dozen cellars down the valley. Bram looks at the empty room with "
		+ "open astonishment. \"I came for one page,\" he says. \"You saved the lot of it.\" He digs "
		+ "something out of a cellar box and presses it into your hands before he leaves.")
	cf.requires_favor = &"folk"
	cf.card_reward = true
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

	e.choices.append(c1)
	e.choices.append(cf)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


## Camelot court event: a tourney still bright in a rotting realm. The open option (wager on
## the commoner) is the populist reward; entering the lists for the real prize is COURT-GATED
## (the marshal only lifts the rope for a keeper the crown backs). Mirror of the Scriptorium's
## folk gate on the court side. Surface Arthurian spectacle with the rot showing underneath.
static func _the_tourney() -> EventData:
	var e = EventData.new()
	e.event_name = "The Tourney"
	e.description = ("The tourney field is loud and bright in a realm gone quiet and gray everywhere "
		+ "else, and that is the first wrong thing about it. The grandstand is full. Pennants snap in "
		+ "a stiff wind. Down the lists two knights couch their lances and ride, and the crowd makes "
		+ "the noise crowds make.\n\nLook closer and you see how many of the cheering faces hold too "
		+ "still, and how the black creeps up under one champion's gorget where his squire keeps "
		+ "worrying the strap to hide it. A herald takes wagers at the rail. A marshal takes names for "
		+ "the open challenge, and looks hard at who he lets past the rope.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Wager a purse on the commoner in the plain harness."
	# An actual bet, not a payout: the underdog usually has it, but not always. Backing him
	# openly is the pro-folk gesture win or lose, so passion and standing land either way --
	# only the gold rolls (gamble_win_gold / gamble_lose_gold).
	c1.gamble_chance = 0.55
	c1.gamble_win_gold = 40
	c1.gamble_lose_gold = -25
	c1.gamble_win_text = ("You back the man with no device on his shield, and the stands laugh at you "
		+ "for it, until he puts the rotting noble in the dirt and stands over him breathing clean "
		+ "and hard. The herald counts out your winnings with a sour face. Across the field the "
		+ "commoner catches your eye and touches two fingers to his brow.")
	c1.gamble_lose_text = ("You back the man with no device on his shield, and for three passes he "
		+ "rides like he will shame the lot of them -- then the rotting noble's lance catches him "
		+ "under the arm and he goes down and is slow to rise. The herald rakes in your stake without "
		+ "meeting your eye. Across the field they get the commoner back to his knees; he finds you in "
		+ "the crowd anyway, and touches two fingers to his brow.")
	c1.passion_change = 2
	c1.standing_change = 5

	# Court-gated: the marshal only lifts the rope for a name the crown stands behind. The real
	# reward (a technique from a master-at-arms) sits behind court favor; a folk-pledged keeper
	# is turned away at the rope, the way the Scriptorium turns a court keeper away from the folk.
	var cc = EventData.EventChoice.new()
	cc.text = "Give the marshal your name and ride in the open challenge. (Lose 8 HP)"
	cc.result_text = ("The marshal weighs your name, or the weight behind it, and lifts the rope. "
		+ "They find you a horse and a lance. The ride is short and it hurts -- a lance on the shield "
		+ "is a hammer-blow even when you keep your seat -- but you put your man in the dirt and the "
		+ "stand roars for you. Afterward an old master-at-arms who liked your seat shows you a way of "
		+ "closing the distance you will not forget.")
	cc.requires_favor = &"court"
	cc.hp_change = -8  # jousting hurts, even when you win the pass
	cc.card_reward = true
	cc.passion_change = 4
	cc.standing_change = -4

	var c3 = EventData.EventChoice.new()
	c3.text = "Watch a single pass, then slip out and take the drovers' road. (Skip the next node)"
	c3.result_text = ("You stay for one ride and leave while the crowd is still on its feet. Behind the "
		+ "grandstand a drovers' track cuts the long bend off the king's road, and you take it at a hard "
		+ "walk. You have seen enough of this place -- the shortcut puts the next trouble on the road "
		+ "well behind you.")
	c3.passion_change = 3
	c3.skips_next_node = true

	e.choices.append(c1)
	e.choices.append(cc)
	e.choices.append(c3)
	return e


## Camelot liaison event: Neve (Dispatch) on-site running a village evacuation ahead of the
## corruption. Help wholeheartedly, help while covering your own escape, or walk on. Her warm,
## worried-veteran voice (and a touch of old-coworker familiarity with the keeper) per the
## brief. The notebook is flavor and is never explained. Folk-leaning standing.
static func _last_cart_out() -> EventData:
	var e = EventData.new()
	e.event_name = "The Last Cart Out"
	e.description = ("The village is emptying the way water leaves a cracked basin, quick at first "
		+ "and then a slow hopeless trickle of the people who had least to pack. The corruption is "
		+ "two valleys off and coming. You can see it as a grayness in the far tree line that does "
		+ "not move the way weather moves. In the square too few carts are being loaded by too many "
		+ "hands.\n\nNeve is in the thick of it with a battered notebook, sending each cart off in "
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
		+ "until the square stands empty and the gray is close enough to smell. \"There,\" she says, "
		+ "breathless. \"Now you look how you ought to.\" She marks one last line in the notebook and "
		+ "does not let you see it.")
	c1.hp_change = -4
	c1.passion_change = 5
	c1.standing_change = 7
	c1.awarded_title_id = &"the_merciful"

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

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


static func _ominous_statue() -> EventData:
	var e = EventData.new()
	e.event_name = "Ominous Statue"
	e.description = "A towering obsidian statue looms before you. Its hollow eyes seem to peer into your soul. A basin at its feet is stained dark.\n\nCarved text reads: \"Offer of the flesh, reward of the spirit.\""

	var c1 = EventData.EventChoice.new()
	c1.text = "Offer your blood (Lose 8 HP)"
	c1.result_text = "Pain lances through you as the statue drinks. In return, power surges into your body."
	c1.hp_change = -8
	c1.max_hp_change = 5
	c1.card_reward = true

	var c2 = EventData.EventChoice.new()
	c2.text = "Offer gold (Lose 15 gold)"
	c2.result_text = "The coins dissolve in the basin. The statue's gaze softens, and you feel lighter."
	c2.gold_change = -15
	c2.hp_change = 15

	var c3 = EventData.EventChoice.new()
	c3.text = "Smash it"
	c3.result_text = "The statue shatters. Shards of obsidian rain down, and dark energy crackles across your skin."
	c3.gold_change = 20
	c3.passion_change = -6
	c3.hp_change = -3

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


static func _wandering_spirit() -> EventData:
	var e = EventData.new()
	e.event_name = "Wandering Spirit"
	e.description = "A translucent figure drifts between the trees, humming a melancholy tune. It notices you and pauses.\n\n\"Traveler... will you hear my story? I have been alone so long.\""

	var c1 = EventData.EventChoice.new()
	c1.text = "Listen to their story"
	c1.result_text = "The spirit shares a tale of love and loss. As it fades, you feel your resolve harden."
	c1.max_hp_change = 3
	c1.passion_change = 4
	c1.awarded_title_id = &"the_gracious"  # hearing out the lonely dead -- grace, not mercy

	var c2 = EventData.EventChoice.new()
	c2.text = "Ask it to lend you its strength for the road ahead."
	c2.result_text = ("The spirit hesitates, then lays a cold hand against your sword-arm. The chill "
		+ "sinks in and settles there, patient, waiting for the next time you draw steel. It will "
		+ "carry you through one hard fight, the spirit says, and then it will be spent, the way it is "
		+ "spent itself.")
	c2.grants_combat_boon = &"wandering_vigor"

	var c3 = EventData.EventChoice.new()
	c3.text = "Banish the spirit"
	c3.result_text = "You dispel the spirit with a wave. Its essence scatters into glittering motes you collect."
	c3.gold_change = 25
	c3.passion_change = -4

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


static func _training_grounds() -> EventData:
	var e = EventData.new()
	e.event_name = "Training Grounds"
	e.description = "An abandoned training yard. Wooden dummies, rusted weights, and a weapon rack still stand. You could hone your skills here."

	var c1 = EventData.EventChoice.new()
	c1.text = "Train intensely (Lose 3 HP)"
	c1.result_text = "Sweat and effort pay off. You feel sharper, more capable."
	c1.hp_change = -3
	c1.card_reward = true

	var c2 = EventData.EventChoice.new()
	c2.text = "Scavenge the equipment"
	c2.result_text = "You find some serviceable gear and a few coins among the debris."
	c2.gold_change = 20

	var c3 = EventData.EventChoice.new()
	c3.text = "Rest in the shade"
	c3.result_text = "You take a moment to breathe. Sometimes that's enough."
	c3.hp_change = 8

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e


static func _suspicious_chest() -> EventData:
	var e = EventData.new()
	e.event_name = "Suspicious Chest"
	e.description = "A gilded chest sits in the middle of an empty clearing. No traps visible. No guards. Just a chest, gleaming in the light.\n\nToo good to be true?"

	var c1 = EventData.EventChoice.new()
	c1.text = "Open it carefully"
	c1.result_text = "A hidden needle pricks your finger, but the chest's contents are worth it."
	c1.hp_change = -4
	c1.gold_change = 35
	c1.card_reward = true

	var c2 = EventData.EventChoice.new()
	c2.text = "Smash it open"
	c2.result_text = "The chest explodes with force! Coins scatter everywhere."
	c2.hp_change = -8
	c2.gold_change = 50

	var c3 = EventData.EventChoice.new()
	c3.text = "Leave it alone"
	c3.result_text = "Wisdom is knowing when not to act. You walk on, unscathed."
	c3.passion_change = 2
	c3.awarded_title_id = &"the_calculating"

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
		+ "cart. Grain sacks, a crate of thin hens, a strongbox. \"The collector rides in at dawn "
		+ "for the crown's share. He took the seed-corn last winter. He'll take it again, and we'll "
		+ "be chewing the thatch by spring.\"\n\nA child watches from a doorway. Nobody tells them to "
		+ "go inside.")

	var c1 = EventData.EventChoice.new()
	c1.text = "Pay the crown's share yourself. (Lose 50 Gold)"
	c1.result_text = ("You count the coin into the old woman's hands. It is more than the collector "
		+ "will expect, and he will not think to ask where it came from. That night the village "
		+ "feeds you at its own thin table. An old campaigner who soldiered for the last king sits "
		+ "with you late, showing you a trick of his he says the young ones never have the patience "
		+ "to learn.")
	c1.gold_change = -50
	c1.passion_change = 5
	c1.card_reward = true
	c1.awarded_title_id = &"the_gracious"  # paying their debt from your own purse -- open-handed
	c1.standing_change = 8  # sparing the folk, the way anyone could

	var c2 = EventData.EventChoice.new()
	c2.text = "Take the crown's share yourself, and your own cut with it."
	c2.result_text = ("You tell them you will see the king's due collected. They are almost grateful, "
		+ "until they understand you mean to carry it off tonight, ahead of the collector. You take "
		+ "the strongbox and a measure of the grain. Nobody tries to stop a sword. By the time you "
		+ "reach the trees, the quiet behind you has a different weight to it.")
	c2.gold_change = 45
	c2.passion_change = -6
	c2.awarded_title_id = &"the_calculating"
	c2.standing_change = -12  # robbing them like a collector turns the people against you

	var c3 = EventData.EventChoice.new()
	c3.text = "This is not your realm to set right. Walk on."
	c3.result_text = ("You tell her it isn't yours to mend, which is true, and you take the road out "
		+ "before the sun is up. It is an easy enough thing to say, a mile of walking hasn't made "
		+ "you feel much better though.")
	c3.passion_change = -3

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
		+ "turns his cart around. The village will never learn how close it came. You will.")
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


static func _campfire_remnants() -> EventData:
	var e = EventData.new()
	e.event_name = "Campfire Remnants"
	e.description = "Embers still glow in a recently abandoned campsite. Bedrolls, supplies, and a journal lie scattered. Whoever was here left in a hurry."

	var c1 = EventData.EventChoice.new()
	c1.text = "Rest by the fire"
	c1.result_text = "The warmth soothes your aches. You drift off briefly and wake feeling restored."
	c1.hp_change = 12

	var c2 = EventData.EventChoice.new()
	c2.text = "Read the journal"
	c2.result_text = "The journal details combat techniques you haven't considered. You feel sharper."
	c2.remove_card = true
	c2.passion_change = 2

	var c3 = EventData.EventChoice.new()
	c3.text = "Loot the supplies"
	c3.result_text = "You stuff your pockets with everything useful. Better you than the wilderness."
	c3.gold_change = 18
	c3.passion_change = -2

	e.choices.append(c1)
	e.choices.append(c2)
	e.choices.append(c3)
	return e
