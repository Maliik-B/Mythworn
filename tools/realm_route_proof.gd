extends Node
## Same-seed proof that Camelot's content does not move when the realm code does.
## Run: godot --headless --path . res://tools/realm_route_proof.tscn --quit-after 60000 > out.txt
## Run it on two commits and diff the files, leaving out the SEAT lines, which only a tree with a
## crossing can print: `diff <(grep -v ^SEAT a.txt) <(grep -v ^SEAT b.txt)`.
##
## For each seed, under each pledge, it builds the map the way map_scene does and walks one route up
## it the way map_scene and event_scene resolve nodes, with the same calls in the same order. It
## prints every node of the map, every encounter and event the walk meets, and where the RNG streams
## end up. It takes a node's type at face value, so it is the run that does not step through.
## `-- --seeds=N` runs the first N seeds, whose output is a prefix of a longer run's.

const SEEDS := 40
const PLEDGES := [
	["neutral", 1.0, 1.0, false],
	["court", 1.15, 1.4, false],
	["folk", 0.9, 1.0, true],
]


func _ready() -> void:
	AudioManager.enabled = false
	print("== Realm route proof ==")
	var character := CharacterPool.build_emo_hybrid()
	var seeds := SEEDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seeds = int(arg.substr(8))
	for s in seeds:
		for pledge in PLEDGES:
			_prove(character, 7000 + s * 13, pledge)
	print("== done ==")
	get_tree().quit()


func _prove(character: CharacterData, run_seed: int, pledge: Array) -> void:
	RunManager.start_run(character, run_seed)
	var mult: float = pledge[1]
	RunManager.realm_config.enemy_difficulty_mult = mult
	RunManager.realm_config.elite_frequency_mult = pledge[2]
	RunManager.realm_config.elite_weaken = pledge[3]
	var map := MapGenerator.generate(RngManager.map_rng, RunManager.current_realm_id,
		RunManager.current_act, pledge[2], pledge[3])
	RunManager.current_map = map
	print("# seed %d pledge %s" % [run_seed, pledge[0]])

	var seat := -1
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		print("N %d f%d c%d %s next%s w%d g[%s] p[%s] s[%s] j%.4f,%.4f" % [id, n.floor_num, n.column,
			MapNode.NodeType.keys()[n.node_type], str(n.next_nodes), int(n.weakened), n.quest_giver_id,
			n.quest_payoff_id, n.scripted_event_id, n.x_jitter, n.y_jitter])
		if n.get("crossing_to") != null and n.get("crossing_to") != &"":
			seat = id
			print("SEAT seed %d %s node %d floor %d under %s" % [run_seed, pledge[0], id, n.floor_num,
				MapNode.NodeType.keys()[n.node_type]])
	for id in map.pledge_changes:
		print("P %d %s" % [id, map.pledge_changes[id]])

	var current: int = map.starting_node_ids[run_seed % map.starting_node_ids.size()]
	var walked_seat := false
	while true:
		map.move_to(current)
		var node: MapNode = map.get_node(current)
		walked_seat = walked_seat or current == seat
		_resolve(node, map, mult)
		if node.next_nodes.is_empty():
			break
		current = node.next_nodes[(run_seed + node.floor_num) % node.next_nodes.size()]
	print("SEAT walk seed %d %s stepped on the seat: %s" % [run_seed, pledge[0], walked_seat])
	print("R enemy %d event %d map %d loot %d deck %d" % [RngManager.enemy_rng.state,
		RngManager.event_rng.state, RngManager.map_rng.state, RngManager.loot_rng.state,
		RngManager.deck_rng.state])


func _resolve(node: MapNode, map: MapData, mult: float) -> void:
	var where := "f%d %s" % [node.floor_num, MapNode.NodeType.keys()[node.node_type]]
	match node.node_type:
		MapNode.NodeType.COMBAT:
			print("W %s %s" % [where, _names(EnemyPool.get_combat_encounter(node.floor_num, mult))])
		MapNode.NodeType.ELITE:
			print("W %s %s" % [where, _names(EnemyPool.get_elite_encounter(mult))])
		MapNode.NodeType.BOSS:
			print("W %s %s" % [where, _names(EnemyPool.get_boss(mult))])
		MapNode.NodeType.MYSTERY:
			print("W %s roll %.6f" % [where, RngManager.event_rng.randf()])
		MapNode.NodeType.EVENT:
			if node.quest_giver_id != &"" or node.scripted_event_id != &"":
				print("W %s seated %s%s" % [where, node.quest_giver_id, node.scripted_event_id])
				return
			var scripted := RunManager.next_ordinary_event_script()
			if scripted != &"":
				print("W %s scripted %s" % [where, scripted])
				return
			var treasure_ok := MapGenerator.has_treasure_payoff(map, map.current_node_id)
			var event := EventPool.get_random_event_filtered(RngManager.event_rng, treasure_ok)
			print("W %s event %s treasure_ok=%s" % [where, event.event_name, treasure_ok])
		_:
			print("W %s" % where)


func _names(enemies: Array[EnemyData]) -> String:
	var out: PackedStringArray = []
	for e in enemies:
		out.append("%s:%d" % [e.enemy_name, e.max_health])
	return ", ".join(out)
