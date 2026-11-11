extends Node
## Walks a crossing end to end, through the real scenes: the map scene's own click handler, real
## fights (won by force, since the walk is about the road and not the deck), real reward screens.
## Run: godot --headless --path . res://tools/crossing_walk.tscn --quit-after 90000
##
## It prints the run's floor, realm, route and quest state before, during and after, then checks the
## home realm came back as it was left and that an armed quest still pays off on the far side of the
## trip. It pays the mound's debt each of the three ways, on three runs. Exit code is the number of
## failed checks. Judge by the last line.

const MAP := "res://scenes/map/map_scene.tscn"
const COMBAT := "res://scenes/combat/combat_scene.tscn"
const REWARDS: Array[String] = ["res://scenes/reward/card_reward_scene.tscn",
	"res://scenes/reward/relic_reward_scene.tscn"]
## A seed whose raider payoff sits past the crossing, so the armed quest can be walked to afterward.
## The search below starts here and moves on if map generation changes.
const FIRST_SEED := 4259
const SEED_TRIES := 60
## The walk is about order, not feel, so the fades go by quickly.
const TIME_SCALE := 8.0
## Headless frames are otherwise unthrottled, which only heats the machine.
const MAX_FPS := 120
## How long a scene or a flourish gets, in real time, before the walk calls it stuck.
const PATIENCE_MS := 60000

var _fails := 0


func _ready() -> void:
	AudioManager.enabled = false
	Engine.time_scale = TIME_SCALE
	Engine.max_fps = MAX_FPS
	await get_tree().process_frame
	# Out from under change_scene, which would otherwise free this node with the first scene change.
	get_tree().current_scene = null
	print("\n== Crossing walk ==")
	await _walk()
	print("== %s ==\n" % ("WALK OK" if _fails == 0 else "%d FAILED" % _fails))
	Engine.time_scale = 1.0
	get_tree().quit(_fails)


func _walk() -> void:
	var found := _find_run()
	if found.is_empty():
		_check("a seed within %d tries has the raider payoff past the crossing" % SEED_TRIES, false)
		return
	var map: MapData = RunManager.current_map
	var seat: int = found["seat"]
	var payoff: int = found["payoff"]
	print("seed %d: crossing on node %d, raider payoff on node %d" % [RngManager.run_seed, seat, payoff])

	# What has to survive the trip: a realm title worn, a realm item carried, a hunt under way.
	RunManager.award_title(&"swords_bearer")
	RunManager.equip_title(0, &"swords_bearer")
	RunManager.add_consumable(ConsumablePool.get_consumable(&"relic_water"))
	RunManager.add_consumable(ConsumablePool.get_consumable(&"poisoned_chalice"))
	RunManager.arm_quest(MapGenerator.QUEST_ID)

	get_tree().change_scene_to_file(MAP)
	var scene := await _next_scene(null)
	await _settle(scene)
	_print_state("first map open")
	_print_legend(scene)

	print("-- walking to the crossing --")
	for id in _route_to(map, seat):
		if id == seat:
			break
		scene = await _step(scene, id)
	var before := _snapshot(seat)
	var home_config := RunManager.realm_config
	_print_state("BEFORE, one step short of the crossing")

	print("-- stepping through --")
	scene = await _click(scene, seat)
	scene = await _next_scene(scene)
	await _settle(scene)
	var far: MapData = RunManager.current_map
	_print_state("DURING, landed on the far side")
	_print_legend(scene)
	_check("the far map is another map, with about 5 nodes", far != map and far.nodes.size() == 5)
	_check("the far map is Yggdrasil's, on its first config", RunManager.current_realm_id == &"yggdrasil"
		and RunManager.realm_config.route_id == RealmRoutes.BASE)
	_check("the far map counts its depth from just past the crossing",
		far.floor_base == map.get_node(seat).floor_num + 1)
	_check("a hop is not a visit", RunManager.visited_realm_ids.size() == 1
		and RunManager.visited_realm_ids[0] == &"camelot" and not RunManager.has_visited_realm(&"yggdrasil"))
	_check("the title still reads at its full tier", RunManager.get_title_tier(&"swords_bearer") == TitleData.Tier.ORIGINAL)
	_check("the realm's item is still in the pack", RunManager.has_consumable(&"relic_water"))
	_check("the quest item still has somewhere to go", not RunManager.is_consumable_spent(
		RunManager.get_consumable_by_id(&"poisoned_chalice")))

	print("-- the edge, paying the debt by force --")
	scene = await _far_event(scene, 0, 0)
	_print_state("DURING, after the arrival")
	scene = await _far_event(scene, 1, 0)
	_print_state("DURING, after the door")
	scene = await _step(scene, 2)
	_print_state("DURING, after the gate")
	scene = await _mound_fight(scene, 3, 0)
	_print_state("DURING, after the mound")
	_check("no boss on the far map", not _has_type(far, MapNode.NodeType.BOSS))
	_check("by force, the ring came out", RunManager.has_relic("The Oath-Ring"))
	_check("the realm remembers it was by force", RunManager.realm_memory.get(&"yggdrasil") == &"oath_ring_force")

	print("-- the way back --")
	var way_back := _way_back(far)
	scene = await _click(scene, way_back)
	scene = await _next_scene(scene)
	await _settle(scene)
	_print_state("AFTER, back on the home map")
	_print_legend(scene)
	var after := _snapshot(seat)
	_check("the same map came back, not a copy", RunManager.current_map == map)
	_check("the same config came back", RunManager.realm_config == home_config)
	for key in before:
		if key == "current_node" or key == "next" or key == "gold" or key == "deck" or key == "hp":
			continue
		_check("%s is as it was left" % key, str(before[key]) == str(after[key]))
	_check("the player stands on the crossing, with its onward nodes open",
		map.current_node_id == seat and map.get_available_next_ids() == map.get_node(seat).next_nodes)
	_check("the crossing cannot be taken twice", seat not in map.get_available_next_ids())
	_check("the trip is on record for the beat to come", RunManager.last_crossing.get("from") == &"camelot"
		and RunManager.last_crossing.get("to") == &"yggdrasil" and RunManager.last_crossing.get("node_id") == seat
		and RunManager.last_crossing.get("nodes_walked") == 5)

	print("-- on to the armed quest --")
	var road: Array = _route_between(map, seat, payoff)
	for id: int in road:
		if id == payoff:
			break
		scene = await _step(scene, id)
	scene = await _click(scene, payoff)
	scene = await _next_scene(scene)
	var event_name: String = scene.event.event_name if "event" in scene and scene.event else "(no event)"
	print("the payoff node opened: %s" % event_name)
	_check("the hunt armed before the trip still pays off after it",
		scene.scene_file_path == "res://scenes/event/event_scene.tscn" and scene.event != null
		and scene.event.event_name == scene._build_raider_ambush_event().event_name)
	_print_state("END")
	await _by_gift()
	await _by_word()


## A second run: the debt paid by a gift, with a queued skip in hand at the way back, which must not
## swallow it or the player would stand on a node with nothing after it.
func _by_gift() -> void:
	print("-- a second run: the debt paid by a gift, a skip queued at the way back --")
	var scene := await _land_on_the_edge()
	var map: MapData = RunManager.home_map()
	scene = await _far_event(scene, 0, 0)
	scene = await _far_event(scene, 1, 0)
	scene = await _step(scene, 2)
	var gold_then := RunManager.gold
	scene = await _mound_fight(scene, 3, 1)
	_print_state("DURING, after the mound")
	_check("the gift cost its gold", RunManager.gold == gold_then - _gift_gold())
	_check("by gift, the ring came out", RunManager.has_relic("The Oath-Ring"))
	_check("the realm remembers it was by gift", RunManager.realm_memory.get(&"yggdrasil") == &"oath_ring_gift")
	RunManager.pending_skip_node = true
	scene = await _click(scene, _way_back(RunManager.current_map))
	scene = await _next_scene(scene)
	await _settle(scene)
	_print_state("AFTER the gift")
	_check("the way back was taken, skip or no skip", not RunManager.is_abroad() and RunManager.current_map == map)
	_check("the skip is still in hand for the next node at home", RunManager.pending_skip_node)


## A third run: the debt paid by your own word, with no fight at the mound.
func _by_word() -> void:
	print("-- a third run: the debt paid by your own word --")
	var scene := await _land_on_the_edge()
	var map: MapData = RunManager.home_map()
	scene = await _far_event(scene, 0, 0)
	scene = await _far_event(scene, 1, 0)
	scene = await _step(scene, 2)
	scene = await _far_event(scene, 3, -1)
	_print_state("DURING, after the mound")
	_check("by your word, no ring and the title", not RunManager.has_relic("The Oath-Ring")
		and RunManager.earned_title_ids.has(&"guest_of_the_hall"))
	_check("the realm remembers it was by your word", RunManager.realm_memory.get(&"yggdrasil") == &"oath_ring_word")
	scene = await _click(scene, _way_back(RunManager.current_map))
	scene = await _next_scene(scene)
	await _settle(scene)
	_print_state("AFTER the word")
	_check("the way back was taken", not RunManager.is_abroad() and RunManager.current_map == map)


## What the gold gift costs, read from the event so the number lives in one place.
func _gift_gold() -> int:
	return load("res://scenes/event/event_scene.gd").YGG_GIFT_GOLD


## A fresh run set down one step short of the crossing, then through it. The road there is the first
## run's to walk; here it is taken as read.
func _land_on_the_edge() -> Node:
	var found := _find_run()
	var map: MapData = RunManager.current_map
	var seat: int = found["seat"]
	RunManager.gold = 200
	for id in map.nodes:
		if map.nodes[id].next_nodes.has(seat):
			map.move_to(id)
			break
	get_tree().change_scene_to_file(MAP)
	var scene := await _next_scene(get_tree().current_scene)
	await _settle(scene)
	scene = await _click(scene, seat)
	scene = await _next_scene(scene)
	await _settle(scene)
	return scene


## Clicks a far map's event node, takes a choice (negative counts from the last) and goes back to the map.
func _far_event(scene: Node, id: int, choice: int) -> Node:
	await _click(scene, id)
	var event := await _next_scene(scene)
	return await _choose_and_leave(event, choice)


func _choose_and_leave(event: Node, choice: int) -> Node:
	var index: int = choice if choice >= 0 else event.event.choices.size() + choice
	print("    %s: %s" % [event.event.event_name, event.event.choices[index].text])
	event._on_choice_selected(index)
	await get_tree().process_frame
	event._on_leave()
	var map := await _next_scene(event)
	await _settle(map)
	return map


## The mound, by a way that starts the guardian: the choice, the fight, the beat after it, the ring.
func _mound_fight(scene: Node, id: int, choice: int) -> Node:
	await _click(scene, id)
	var event := await _next_scene(scene)
	print("    %s: %s" % [event.event.event_name, event.event.choices[choice].text])
	var opening: String = event.event.description
	var taken: String = event.event.choices[choice].text
	event._on_choice_selected(choice)
	var fight := await _next_scene(event)
	var after := await _leave(fight)
	var told: Array = after._parts.map(func(p): return p.get("text", ""))
	_check("the mound's page came across the fight, ending on the choice that started it",
		told.find(opening) >= 0 and told.find(taken) > told.find(opening))
	return await _choose_and_leave(after, 0)


## Starts a run and builds its map as map_scene would, trying seeds until the raider payoff is ahead
## of the crossing. Empty if none in range.
func _find_run() -> Dictionary:
	var character := CharacterPool.build_emo_hybrid()
	for offset in SEED_TRIES:
		RunManager.start_run(character, FIRST_SEED + offset)
		var map := MapGenerator.generate(RngManager.map_rng, RunManager.current_realm_id, RunManager.current_act)
		var seat := -1
		var payoff := -1
		for id in map.nodes:
			if map.nodes[id].crossing_to != &"":
				seat = id
			if map.nodes[id].quest_payoff_id == MapGenerator.QUEST_ID:
				payoff = id
		if seat >= 0 and payoff >= 0 and MapGenerator._reachable_from(map, seat).has(payoff):
			RunManager.current_map = map
			return {"seat": seat, "payoff": payoff}
	return {}


## The path from the first row to `target`, in order, found by walking back from it.
func _route_to(map: MapData, target: int) -> Array:
	for start in map.starting_node_ids:
		var road := _route_between(map, start, target)
		if not road.is_empty() or start == target:
			road.push_front(start)
			return road
	return []


## The nodes after `from` on a path up to and including `to`, or empty if there is none.
func _route_between(map: MapData, from: int, to: int) -> Array:
	if from == to:
		return []
	for nxt in map.get_node(from).next_nodes:
		if nxt == to:
			return [nxt]
		var rest := _route_between(map, nxt, to)
		if not rest.is_empty():
			rest.push_front(nxt)
			return rest
	return []


func _click(scene: Node, id: int) -> Node:
	var node: MapNode = RunManager.current_map.get_node(id)
	var kind: String = MapNode.NodeType.keys()[node.node_type]
	print("  click node %d (floor %d, %s%s)" % [id, node.floor_num, kind,
		", crossing to %s" % node.crossing_to if node.crossing_to != &"" else ""])
	await _settle(scene)
	scene._on_node_clicked(node)
	return scene


## Clicks a node and plays out whatever it opens until the map is back.
func _step(scene: Node, id: int) -> Node:
	await _click(scene, id)
	var current := await _next_scene(scene)
	while current.scene_file_path != MAP:
		current = await _leave(current)
	await _settle(current)
	return current


func _leave(scene: Node) -> Node:
	if scene.scene_file_path == COMBAT:
		var names: PackedStringArray = []
		for enemy in scene.combat_engine.enemies:
			names.append("%s:%d" % [enemy.enemy_data.enemy_name, enemy.enemy_data.max_health])
		print("    fight: %s" % ", ".join(names))
		for enemy in scene.combat_engine.enemies:
			enemy.stats.current_hp = 0
		scene.combat_engine.check_battle_end()
		await get_tree().process_frame
		scene._on_continue_pressed()
	elif scene.scene_file_path in REWARDS:
		scene._on_skip()
	else:
		print("    passing through %s" % scene.scene_file_path.get_file())
		SceneTransition.change_scene(MAP)
	return await _next_scene(scene)


## Waits for the tree's current scene to stop being `old`, and for the new one to be up.
func _next_scene(old: Node) -> Node:
	var deadline := Time.get_ticks_msec() + PATIENCE_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var current := get_tree().current_scene
		if current != null and current != old and is_instance_valid(current) and current.is_node_ready():
			await get_tree().process_frame
			await get_tree().process_frame
			return current
	push_error("crossing_walk: the scene never changed")
	get_tree().quit(99)
	return old


## Lets a map's reveal flourish play out, since the map refuses clicks while it does.
func _settle(scene: Node) -> void:
	var deadline := Time.get_ticks_msec() + PATIENCE_MS
	while Time.get_ticks_msec() < deadline:
		if not ("_pledge_anim_active" in scene) or not scene._pledge_anim_active:
			return
		await get_tree().process_frame
	_check("the map's flourish finished", false)


func _way_back(map: MapData) -> int:
	for id in map.nodes:
		if map.nodes[id].crossing_to != &"":
			return id
	return -1


func _has_type(map: MapData, t: MapNode.NodeType) -> bool:
	for id in map.nodes:
		if map.nodes[id].node_type == t:
			return true
	return false


## The state that must come back as it was left, in plain values so it compares by value. The seat's
## own visited flag is left out: stepping onto it is the one thing the trip changes.
func _snapshot(seat: int) -> Dictionary:
	var map: MapData = RunManager.home_map()
	var nodes := {}
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		nodes[id] = [n.floor_num, n.column, n.node_type, n.next_nodes.duplicate(), n.visited and id != seat,
			n.quest_giver_id, n.quest_payoff_id, n.scripted_event_id, n.crossing_to, n.weakened]
	return {
		"home realm": RunManager.home_realm_id(),
		"route": RunManager.realm_config.route_id,
		"map nodes": nodes,
		"quests": RunManager.active_quests.duplicate(true),
		"visited realms": RunManager.visited_realm_ids.duplicate(),
		"title tier": RunManager.get_title_tier(&"swords_bearer"),
		"title left origin": RunManager._title_has_left_origin.get(&"swords_bearer", false),
		"title returned": RunManager._title_has_returned.get(&"swords_bearer", false),
		"pack": RunManager.consumables.map(func(c): return c.id),
		"standing": RunManager.realm_standing.duplicate(),
		"ordinary events": RunManager.ordinary_event_count,
		"current_node": map.current_node_id,
		"next": map.get_available_next_ids().duplicate(),
		"gold": RunManager.gold,
		"deck": RunManager.current_deck.size(),
		"hp": RunManager.current_hp,
	}


func _print_state(label: String) -> void:
	var map: MapData = RunManager.current_map
	var node := map.get_node(map.current_node_id)
	var floor_text := "not on a node yet" if node == null \
		else "node %d, floor %d of %d, counts as act floor %d" % [node.id, node.floor_num, map.floor_count, map.act_floor(node)]
	print("STATE %s" % label)
	print("  realm %s, route %s, abroad %s, home %s" % [RunManager.current_realm_id, RunManager.realm_config.route_id,
		RunManager.is_abroad(), RunManager.home_realm_id()])
	print("  map of %d nodes, %s, next %s" % [map.nodes.size(), floor_text, str(map.get_available_next_ids())])
	print("  quests %s" % str(RunManager.active_quests))
	print("  visited %s, titles %s, pack %s, standing %s, hp %d, gold %d" % [str(RunManager.visited_realm_ids),
		_title_words(), str(RunManager.consumables.map(func(c): return String(c.id))),
		str(RunManager.realm_standing), RunManager.current_hp, RunManager.gold])
	print("  relics %s, the realm remembers %s" % [str(RunManager.get_owned_relic_names()), str(RunManager.realm_memory)])


## Each earned title as it reads right now, with its tier.
func _title_words() -> String:
	var words: PackedStringArray = []
	for id in RunManager.earned_title_ids:
		var tier := RunManager.get_title_tier(id)
		words.append("%s (%s)" % [TitlePool.get_title(id).get_name_for_tier(tier), TitleData.Tier.keys()[tier]])
	return ", ".join(words)


## The margin key, an entry a row: its glyph, then its name (none for a crossing).
func _print_legend(scene: Node) -> void:
	var words: PackedStringArray = []
	for row in scene._legend_key.get_children():
		if not row.is_queued_for_deletion():
			words.append(("%s %s" % [row.get_child(0).text, row.get_child(1).text]).strip_edges())
	print("  legend: %s" % " | ".join(words))


func _check(label: String, ok: bool) -> void:
	print(("  PASS " if ok else "  FAIL ") + label)
	if not ok:
		_fails += 1
