extends Control
## Narrative event scene. Shows story text, player choices, consequences,
## and optional card reward / card removal follow-ups.

var event: EventData
var main_vbox: VBoxContainer
var info_label: Label
var desc_label: RichTextLabel
var choice_container: VBoxContainer
var follow_up_container: VBoxContainer


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
			event = EventPool.get_random_event(RngManager.event_rng)
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
		&"room_that_isnt":
			return _build_room_that_isnt_event()
		&"reliquary_struck":
			return _build_reliquary_struck_event()
		&"reliquary_won":
			return _build_reliquary_won_event()
		_:
			push_warning("Unknown special event id: %s" % id)
			return EventPool.get_random_event(RngManager.event_rng)


func _build_sword_in_stone_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Sword in the Stone"
	e.description = ("A blade stands in a block of worn granite, sunk to the hilt. Something is hunched "
		+ "over it, and it raises its head as you come near. A champion, once. You can still read the "
		+ "heraldry on the ruined surcoat, under everything that has grown over it since.\n\nThe chaos "
		+ "has gone all through him. Black veins climb his throat. One arm has swollen to near twice "
		+ "the size of the other. His eyes have filmed over to a flat white, and he does not so much "
		+ "stand as brace, like a man holding a door shut from the inside. When he sees you, he "
		+ "snarls.\n\nThe sword's hilt catches the light, then goes dull. The metal settles deeper "
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
	e.choices.append(walk)

	return e


## The follow-up beat after the guardian falls. The corruption lifts, he names the
## boss's nature (a hint at Sir Caedmon's compelled will, pointing at the Act-2 Puppeteer),
## and Excalibur frees itself from the stone.
func _build_sword_guardian_won_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Beast Unmade"
	e.description = ("As the last blow lands, the chaos within him seems to ebb. The black veins fade "
		+ "back under his skin. His swollen arm eases. For one borrowed breath a man is left where the "
		+ "beast was, clear-eyed and frightened.\n\n\"Caedmon.\" He gets the name out like it costs "
		+ "him. \"I went to face Sir Caedmon. I had put down better men than him. I thought it would "
		+ "be quick.\" A wet laugh. \"But he does not fight like a man. Halfway through, something "
		+ "took the reins of him. His guard just dropped. He came at me like a thing with no fear "
		+ "left, and no one behind the eyes. Whatever has hold of him, it does not care if the body "
		+ "breaks getting to you.\"\n\nHis hand finds your arm. \"That is how it got into me. Through "
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
		+ "the dirt with the point of a stick, and marks where the trees close in. \"They'll hear you "
		+ "before you see them,\" he says. \"They always do.\"")
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

	return e


## The reward beat after the band falls. Pledge-agnostic: an immediate heal (the village binds
## your wounds) plus Blooded Edge (the one good thing they had left to give). Marking the quest
## complete here stops any re-trigger; the grant itself happens on the choice.
func _build_raider_victory_event() -> EventData:
	RunManager.quest_completed = true

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
		+ "by now, the black veins and the smell. This is clean, and quiet, and wrong the way a word "
		+ "repeated too many times stops being a word.\n\nA woman is already there, leaning in a "
		+ "doorway that opens onto a room you are fairly sure the corridor does not have space for. "
		+ "She doesn't look up from her notes. \"Cass. Anomalies.\" She says it the way you'd say a "
		+ "department, because it is one. \"You're the one they sent for the sword. This isn't your "
		+ "file. It's mine.\" She finally looks at you, and something in your face makes her put the "
		+ "notes down. \"...you feel it pulling, don't you. Of course you do. Don't.\"")

	# Proposal A: the deterministic trade, cost shown up front. The glimpse of home grants the
	# memory card; the seeing takes a cut of HP. Cass warns you off, and lets you choose anyway.
	var step = EventData.EventChoice.new()
	step.text = "Step through the door that shouldn't fit. (Lose 8 HP)"
	step.result_text = ("Cass says your name -- the one you gave yourself -- once, flatly, and "
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

	# The safe read: let her walk you out. Nothing gained, nothing lost -- she's plainly relieved.
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
## via the entry event's next_event_id. The colleague stays unnamed.
func _build_reliquary_struck_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Reliquary"
	e.description = ("The thing the chapel gives you is a memory, and it is not of home. It is the "
		+ "office. Fable, the ordinary grind of it, and a face you know the way you know a face "
		+ "you've worked beside a hundred times. You can see them clearly. The way they hold a cup. "
		+ "A thing they're always saying that you'd stopped hearing.\n\nThen it begins to go. Not "
		+ "torn away. Just thinning at the edges while you reach for it, the way your oldest memories "
		+ "go, the way a whole home once went. You know this exactly. You can feel how much of them "
		+ "is left, and how fast, and that if you do nothing there will shortly have been no one "
		+ "there at all.")

	# Hold and leave: keep the memory, abandon the chapel, apologize. No fight, no title -- a
	# quiet, dignified out. You keep what matters to you; you just don't fight for more.
	var hold = EventData.EventChoice.new()
	hold.text = "Hold the feeling. Let the chapel keep the rest, and go."
	hold.result_text = ("You stop reaching. You hold still and just have them, the whole shape of "
		+ "them, for as long as it lasts, and you don't fight the chapel for anything past that. "
		+ "The face stays. Worn at the edges, but yours. On the way out you put a hand flat on the "
		+ "grey door. \"I'm sorry,\" you tell it, and you're not sure for what. For leaving it like "
		+ "this, maybe. It doesn't answer. You take the road with one more face kept than you came "
		+ "with, and a chapel at your back that you did not save.")
	hold.passion_change = 5
	e.choices.append(hold)

	# Stay in contact: more damage (clamped to leave 1 HP), and the chapel's held memory tears
	# itself off the walls to make you stop. Launches the chapel-beast fight -> reliquary_won.
	var stay = EventData.EventChoice.new()
	stay.text = "Don't let it fade. Hold on, whatever it costs. (Lose 6 HP)"
	stay.hp_change = -6
	stay.starts_combat = &"chapel_beast"
	e.choices.append(stay)

	return e


## The Reliquary, stage 3: the beast is unmade and the memory held. Reached only by winning the
## chapel-beast fight (pending_special_event after victory). The payoff: a heal, a Passion lift,
## the Vigil Candle relic, and The Compassionate title (distinct from The Merciful -- +6 Max HP,
## a lasting capacity for having held on rather than another post-combat mend).
func _build_reliquary_won_event() -> EventData:
	var e = EventData.new()
	e.event_name = "The Reliquary"
	e.description = ("The shape comes apart the way glass finds its own cracks, all at once and "
		+ "then still. What tore off the walls is back to being walls: dim glass, grey gold, a "
		+ "saint worn faceless by weather and years. The chapel is only a chapel again.\n\nAnd the "
		+ "memory you would not let go of is still there. Whole. Clear. The cup, the saying, the "
		+ "face. You held on and it held. In the quiet the reliquary gives you one thing more, the "
		+ "way a place gives you something when you've paid it enough mind to be owed.")

	var take = EventData.EventChoice.new()
	take.text = "Take what the chapel leaves you, and go."
	take.result_text = ("It is a stub of candle, beeswax gone amber-hard, the kind kept burning in "
		+ "a side chapel for someone who isn't coming back. It should mean nothing. It steadies you "
		+ "to hold it, the way keeping a small light does. You go out through the lychgate lighter "
		+ "than you came, carrying a face, a flame, and the particular ache of having refused to let "
		+ "a thing be forgotten.")
	take.hp_change = maxi(1, int(round(RunManager.max_hp * 0.25)))
	take.passion_change = 5
	take.granted_relic_id = &"Vigil Candle"
	take.awarded_title_id = &"the_compassionate"
	e.choices.append(take)

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
		_start_event_combat(choice.starts_combat)
		return

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
		_show_card_reward()
	elif choice.remove_card:
		_show_card_removal()
	elif choice.next_event_id != &"":
		# A multi-stage event: advance to the next authored beat after the player reads
		# this outcome (The Reliquary's warned -> struck -> fight chain).
		_show_next_beat(choice.next_event_id)
	else:
		_show_done()


## Launches a scripted event fight. The Sword-in-the-Stone guardian is the Champion
## of the Usurper (thematically a champion who went to fight Caedmon and was corrupted).
## Combat victory routes back to the "beast unmade" beat via pending_event_combat +
## pending_special_event; the player gets no normal reward — Excalibur IS the reward.
func _start_event_combat(key: StringName) -> void:
	match key:
		&"sword_guardian":
			RunManager.pending_enemies.clear()
			RunManager.pending_enemies.append(EnemyPool.champion_of_the_usurper())
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
		&"chapel_beast":
			RunManager.pending_enemies.clear()
			RunManager.pending_enemies.append(EnemyPool.the_shattered_choir())
			RunManager.pending_gold_reward = 0
			RunManager.pending_relic_reward = false
			RunManager.pending_relic_is_boss = false
			RunManager.pending_event_combat = true
			RunManager.pending_special_event = &"reliquary_won"
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

	# Accepting a plea arms the cross-map questline: the payoff node reveals on the next
	# return to the map (map_scene plays the arm flourish + objective toast).
	if choice.arms_quest != &"":
		RunManager.active_quest_id = choice.arms_quest

	# Faction-aligned acts shift the realm's court<->folk standing.
	if choice.standing_change != 0:
		RunManager.change_realm_standing(RunManager.current_realm_id, choice.standing_change)


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

func _show_card_reward() -> void:
	follow_up_container.visible = true
	for child in follow_up_container.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Choose a card to add:"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	follow_up_container.add_child(header)

	var cards = CardPool.get_reward_choices(RngManager.loot_rng, 3)

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
