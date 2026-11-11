class_name MapGenerator
## Generates an STS-style branching node map for one act.
## Uses random path walks to create organic branching with guaranteed connectivity.

const FLOOR_COUNT := 15
const MAP_WIDTH := 7
const PATH_COUNT := 6


## Generate a map. `realm_id` and `act` are optional — when provided, realm-specific
## post-processing places signature nodes (e.g. Camelot's Sword in the Stone at the
## center of Act 1). Default behavior preserves the original generic map.
static func generate(rng: RandomNumberGenerator, realm_id: StringName = &"",
		act: int = 1, elite_frequency_mult: float = 1.0,
		weaken_elites: bool = false) -> MapData:
	var map = MapData.new()
	map.floor_count = FLOOR_COUNT

	# Phase 1: Generate random paths and collect positions + connections
	var positions: Dictionary = {} # Vector2i(floor, col) -> true
	var connections: Dictionary = {} # Vector2i -> Array of Vector2i

	for p in PATH_COUNT:
		# Spread the path starts across the full width (evenly + a little jitter) so
		# the map's base spans the whole board rather than clustering to one side;
		# each path then random-walks upward from there.
		var base_col := int(round(float(p) / float(PATH_COUNT - 1) * float(MAP_WIDTH - 1)))
		var col = clampi(base_col + rng.randi_range(-1, 1), 0, MAP_WIDTH - 1)

		for floor in FLOOR_COUNT:
			var pos = Vector2i(floor, col)
			positions[pos] = true

			if floor < FLOOR_COUNT - 1:
				var next_col = clampi(col + rng.randi_range(-1, 1), 0, MAP_WIDTH - 1)
				var next_pos = Vector2i(floor + 1, next_col)

				if pos not in connections:
					connections[pos] = []
				if next_pos not in connections[pos]:
					connections[pos].append(next_pos)

				col = next_col

	# Phase 1b: straighten any X-crossings so no two edges cross when drawn — the
	# independent path-walks routinely produce them, and crossed lines misread as
	# "which node does this connect to?" Purely a connection rewrite; connectivity holds.
	_remove_edge_crossings(connections)

	# Phase 2: Merge all top-floor nodes into a single boss node
	var boss_pos = Vector2i(FLOOR_COUNT - 1, MAP_WIDTH / 2)
	var top_positions: Array = []
	for pos in positions:
		if pos.x == FLOOR_COUNT - 1:
			top_positions.append(pos)
	for pos in top_positions:
		positions.erase(pos)
	positions[boss_pos] = true

	# Redirect all connections to top floor toward the boss node
	for pos in connections:
		if pos.x == FLOOR_COUNT - 2:
			var redirected: Array = []
			for target in connections[pos]:
				if target.x == FLOOR_COUNT - 1:
					if boss_pos not in redirected:
						redirected.append(boss_pos)
				else:
					redirected.append(target)
			connections[pos] = redirected

	# Phase 3: Assign stable IDs (sorted by floor then column)
	var sorted_positions = positions.keys()
	sorted_positions.sort_custom(func(a, b):
		if a.x != b.x: return a.x < b.x
		return a.y < b.y
	)

	var pos_to_id: Dictionary = {}
	var id_counter := 0
	for pos in sorted_positions:
		var node = MapNode.new()
		node.id = id_counter
		node.floor_num = pos.x
		node.column = pos.y
		map.nodes[id_counter] = node
		pos_to_id[pos] = id_counter
		id_counter += 1

	# Phase 4: Convert grid connections to node ID connections
	for pos in connections:
		if pos not in pos_to_id:
			continue
		var from_id: int = pos_to_id[pos]
		for target_pos in connections[pos]:
			if target_pos in pos_to_id:
				var to_id: int = pos_to_id[target_pos]
				if to_id not in map.nodes[from_id].next_nodes:
					map.nodes[from_id].next_nodes.append(to_id)

	# Phase 5: Record starting nodes
	for id in map.nodes:
		if map.nodes[id].floor_num == 0:
			map.starting_node_ids.append(id)

	# Phase 6: Assign node types — always NEUTRAL now. The realm-entry pledge shapes the
	# map via a recorded transform (Phase 7b) instead of an invisible generation weight, so
	# the map can show exactly which nodes the choice changed.
	_assign_types(map, rng, 1.0)

	# Phase 7: Realm-specific signature nodes
	_apply_realm_specifics(map, realm_id, act, rng)

	# Phase 7b: apply the pledge's node changes (Court adds elites; Folk weakens them) and
	# record them on map.pledge_changes for the "watch your choice reshape these" animation.
	_apply_pledge_transform(map, rng, elite_frequency_mult, weaken_elites)

	# Phase 8: cosmetic placement jitter — organic look, never touches connectivity
	_apply_jitter(map, rng)

	# Phase 9: the crossing. Last, and on a stream of its own, so seating it moves nothing: not the
	# pledge's picks, not any later draw on `rng`.
	if realm_id == &"camelot" and act == 1:
		_place_crossing(map, rng)

	return map


# Court elite_frequency 1.4 -> +2 elites; the multiplier drives the count so a stress value
# (e.g. 4x in tests) still adds more than neutral.
const ELITE_ADD_SCALE := 5.0
const MAX_ELITES_ADDED := 4


## How many combat nodes a pledge's elite frequency turns into new elites, before the map's own room
## runs out. The entry choice says this number under its option, so it is worked out in one place.
static func elites_added_for(elite_frequency_mult: float) -> int:
	return clampi(roundi((elite_frequency_mult - 1.0) * ELITE_ADD_SCALE), 0, MAX_ELITES_ADDED)


## The pledge's discrete, RECORDED effect on the map. Court (elite_frequency > 1) upgrades a
## few interior combat nodes to NEW elites; Folk (weaken_elites) flags the existing elites
## as weakened (they keep their rewards, the encounter starts them Weak + power-nerfed). Both
## record their touched nodes on map.pledge_changes so map_scene animates only those.
static func _apply_pledge_transform(map: MapData, rng: RandomNumberGenerator,
		elite_frequency_mult: float, weaken_elites: bool) -> void:
	map.pledge_changes = {}

	var extra := elites_added_for(elite_frequency_mult)
	if extra > 0:
		var candidates := _combat_nodes_for_upgrade(map)
		RngManager.shuffle(candidates, rng)
		var n := mini(extra, candidates.size())
		for i in n:
			var id: int = candidates[i]
			map.nodes[id].node_type = MapNode.NodeType.ELITE
			map.pledge_changes[id] = &"elite_added"

	if weaken_elites:
		for id in map.nodes:
			var node: MapNode = map.nodes[id]
			if node.node_type == MapNode.NodeType.ELITE and not map.pledge_changes.has(id):
				node.weakened = true
				map.pledge_changes[id] = &"weakened"


## Interior combat nodes in the mid/late act -- keep the opening gentle and never touch the
## boss / Sword / starting rows.
static func _combat_nodes_for_upgrade(map: MapData) -> Array[int]:
	var out: Array[int] = []
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		# Skip the questline's payoff node: it must keep its original look until the player
		# arms it, and its own reveal flourish shouldn't fight the pledge flourish.
		if node.quest_payoff_id != &"" or node.quest_giver_id != &"" or node.scripted_event_id != &"":
			continue
		if node.node_type == MapNode.NodeType.COMBAT \
				and node.floor_num >= 2 and node.floor_num <= map.floor_count - 3:
			out.append(id)
	return out


## Gives each node a small sub-cell offset so the rendered graph looks hand-placed
## instead of a rigid grid, and every seed looks distinct. Landmarks (boss, the
## Sword) stay exactly on their cell so they remain easy to find. Purely visual:
## the grid column/floor still drive connections, layout, and balance.
static func _apply_jitter(map: MapData, rng: RandomNumberGenerator) -> void:
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		if node.node_type == MapNode.NodeType.BOSS \
				or node.node_type == MapNode.NodeType.SWORD_IN_STONE:
			continue
		# Kept small enough that adjacent-column nodes never overlap (see the render
		# spacing in map_scene / map_preview_overlay).
		node.x_jitter = rng.randf_range(-0.22, 0.22)
		node.y_jitter = rng.randf_range(-0.12, 0.12)


## Removes X-crossings from the grid connections so the drawn graph is planar (no two
## edges cross). All edges span adjacent floors with |Δcol| ≤ 1, so the ONLY way two
## edges cross is the "X": (f,c)→(f+1,c+1) together with (f,c+1)→(f+1,c). We straighten
## both — swap their targets to go straight up — which deletes the crossing while keeping
## every source's exit and every target's feeder (connectivity preserved). Straightening
## can only remove crossings, never create them, so a few passes reach a crossing-free
## fixpoint. The cosmetic jitter (±0.22 col) is far too small to reorder columns, so a
## planar grid stays planar when rendered.
static func _remove_edge_crossings(connections: Dictionary) -> void:
	for _pass in FLOOR_COUNT:
		var changed := false
		for floor in FLOOR_COUNT - 1:
			for c in MAP_WIDTH - 1:
				var a := Vector2i(floor, c)
				var b := Vector2i(floor, c + 1)
				if not connections.has(a) or not connections.has(b):
					continue
				var a_right := Vector2i(floor + 1, c + 1)
				var b_left := Vector2i(floor + 1, c)
				if a_right in connections[a] and b_left in connections[b]:
					connections[a].erase(a_right)
					connections[b].erase(b_left)
					var a_straight := Vector2i(floor + 1, c)
					var b_straight := Vector2i(floor + 1, c + 1)
					if a_straight not in connections[a]:
						connections[a].append(a_straight)
					if b_straight not in connections[b]:
						connections[b].append(b_straight)
					changed = true
		if not changed:
			return


## Realm-specific central quest nodes. Currently: Camelot Act 1 gets the Sword in
## the Stone at the center floor's middle column. We replace the nearest existing
## node — paths that happen to go through the center hit it, others bypass it.
## This matches the design intent that pathing to the central quest is itself the
## decision, not a forced detour.
static func _apply_realm_specifics(map: MapData, realm_id: StringName, act: int,
		rng: RandomNumberGenerator) -> void:
	if realm_id == &"camelot" and act == 1:
		_place_sword_in_stone(map)
		_place_raider_questline(map, rng)
		_place_master_of_game(map, rng)
		_place_record_site(map, rng)


static func _place_sword_in_stone(map: MapData) -> void:
	var target_floor := FLOOR_COUNT / 2  # 7 for 15-floor maps
	var target_col := MAP_WIDTH / 2      # 3 for 7-wide
	var best_id := -1
	var best_distance := 9999
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		if node.floor_num != target_floor:
			continue
		var dist = abs(node.column - target_col)
		if dist < best_distance:
			best_distance = dist
			best_id = id
	if best_id != -1:
		map.nodes[best_id].node_type = MapNode.NodeType.SWORD_IN_STONE


# The beast/bandit cross-map questline. A giver and a payoff are placed with a known
# relationship: the giver is a plain-looking event node in the early act, and the payoff is
# an ordinary node DOWNSTREAM of and FORWARD-REACHABLE FROM the giver, so an accepted quest
# can never be stranded. The payoff keeps its original look (indistinguishable) until the
# player accepts the plea, which arms it. See MapNode quest fields + map_scene.
const QUEST_ID := &"raiders"
const QUEST_GIVER_MIN_FLOOR := 2
const QUEST_GIVER_MAX_FLOOR := 5
const QUEST_PAYOFF_MIN_GAP := 2  # payoff sits at least this many floors ahead of the giver


static func _place_raider_questline(map: MapData, rng: RandomNumberGenerator) -> void:
	# Candidate givers: interior nodes in the early act that aren't a landmark, the start,
	# or the pre-boss rest. Shuffle so the pick is seeded but varied per run.
	var givers: Array[int] = []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.floor_num < QUEST_GIVER_MIN_FLOOR or n.floor_num > QUEST_GIVER_MAX_FLOOR:
			continue
		if _is_reserved_node(map, n):
			continue
		# Only overwrite a combat or event node -- never clobber a scarce, path-planned
		# service (shop/rest) or an elite to seat the plea.
		if n.node_type != MapNode.NodeType.COMBAT and n.node_type != MapNode.NodeType.EVENT:
			continue
		givers.append(id)
	RngManager.shuffle(givers, rng)

	# For the first giver that has a valid downstream payoff, place both and stop.
	for giver_id in givers:
		var giver: MapNode = map.nodes[giver_id]
		var payoff_id := _pick_quest_payoff(map, giver, rng)
		if payoff_id == -1:
			continue
		giver.node_type = MapNode.NodeType.EVENT  # looks like any event node
		giver.quest_giver_id = QUEST_ID
		map.nodes[payoff_id].quest_payoff_id = QUEST_ID
		return


## A COMBAT node forward-reachable from `giver`, far enough ahead to read as "elsewhere on
## the map," and not a reserved node. -1 if none fits.
static func _pick_quest_payoff(map: MapData, giver: MapNode, rng: RandomNumberGenerator) -> int:
	var reachable := _reachable_from(map, giver.id)
	var cands: Array[int] = []
	for id in reachable:
		var n: MapNode = map.nodes[id]
		if n.node_type != MapNode.NodeType.COMBAT:
			continue
		if n.floor_num < giver.floor_num + QUEST_PAYOFF_MIN_GAP:
			continue
		if _is_reserved_node(map, n):
			continue
		cands.append(id)
	if cands.is_empty():
		return -1
	RngManager.shuffle(cands, rng)
	return cands[0]


# The Master of Game: the huntsman whose lord rode out and did not come back, selling the lord's
# animals to someone who will feed them. Seated once on every map in the mid-act, far enough in
# that a bought companion has fights left to pay for itself and early enough that it is not the
# last thing before the boss, on an ordinary combat or event node that nothing else has claimed.
# Unlike the raider giver it is meant to be seen: the map shows what it is, so a run that wants a
# companion can route to it. One a map; a Tiltyard hound is the other way to one.
const MASTER_OF_GAME_ID := &"master_of_game"
const HUNTSMAN_MIN_FLOOR := 6
const HUNTSMAN_MAX_FLOOR := 10


static func _place_master_of_game(map: MapData, rng: RandomNumberGenerator) -> void:
	var cands: Array[int] = []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.floor_num < HUNTSMAN_MIN_FLOOR or n.floor_num > HUNTSMAN_MAX_FLOOR:
			continue
		if _is_reserved_node(map, n):
			continue
		if n.node_type != MapNode.NodeType.COMBAT and n.node_type != MapNode.NodeType.EVENT:
			continue
		cands.append(id)
	if cands.is_empty():
		return
	RngManager.shuffle(cands, rng)
	var node: MapNode = map.nodes[cands[0]]
	node.node_type = MapNode.NodeType.EVENT
	node.scripted_event_id = MASTER_OF_GAME_ID


# A record site: one of the three pool events that can wake a forgotten relic (the Scriptorium,
# the Tourney's herald, the Reliquary), seated once on every map late in the act, after the
# elites and shops that hand out dormant relics and before the pre-boss rest, so a run that holds
# one can count on a place to wake it and route there. Which of the three is drawn on the map
# rng; the pool keeps drawing all three at random as well. Shown on the map like the huntsman.
const RECORD_SITE_IDS: Array[StringName] = [&"scriptorium", &"tourney", &"reliquary"]
const RECORD_SITE_MIN_FLOOR := 9
const RECORD_SITE_MAX_FLOOR := 12


static func _place_record_site(map: MapData, rng: RandomNumberGenerator) -> void:
	var cands: Array[int] = []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.floor_num < RECORD_SITE_MIN_FLOOR or n.floor_num > RECORD_SITE_MAX_FLOOR:
			continue
		if _is_reserved_node(map, n):
			continue
		if n.node_type != MapNode.NodeType.COMBAT and n.node_type != MapNode.NodeType.EVENT:
			continue
		cands.append(id)
	if cands.is_empty():
		return
	RngManager.shuffle(cands, rng)
	var node: MapNode = map.nodes[cands[0]]
	node.node_type = MapNode.NodeType.EVENT
	node.scripted_event_id = RECORD_SITE_IDS[rng.randi_range(0, RECORD_SITE_IDS.size() - 1)]


# The crossing: a node that leads out of the realm and back. Seated once on the first map of a run,
# late enough that the player has a deck to take with them, and shown from the start, so it is there
# to be planned around. One jump and back only for now. It takes an ordinary node nothing else has
# claimed, never the only node on its floor, so stepping through is always a choice of route.
const CROSSING_REALM := &"yggdrasil"
const CROSSING_MIN_FLOOR := 8
const CROSSING_MAX_FLOOR := 10


static func _place_crossing(map: MapData, rng: RandomNumberGenerator) -> void:
	var cands: Array[int] = []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.floor_num < CROSSING_MIN_FLOOR or n.floor_num > CROSSING_MAX_FLOOR:
			continue
		if _is_reserved_node(map, n):
			continue
		if n.node_type != MapNode.NodeType.COMBAT and n.node_type != MapNode.NodeType.EVENT:
			continue
		if map.get_nodes_on_floor(n.floor_num).size() < 2:
			continue
		cands.append(id)
	if cands.is_empty():
		return
	var fork := RandomNumberGenerator.new()
	fork.seed = hash(str(rng.seed) + "crossing")
	RngManager.shuffle(cands, fork)
	map.nodes[cands[0]].crossing_to = CROSSING_REALM


# A crossing's far side: the edge of another realm, with no boss and one way back. One table, so it
# can be reshaped without touching anything else. A slot's optional `scripted` names the authored
# event it opens (event_scene._build_special_event), and an event slot with neither that nor a pool
# to draw from is a fight. Yggdrasil's edge is a line: under the root, the door, the fight at the
# gate, the mound (where the guardian is met, or not), and home.
const _EDGE_LAYOUT := [
	{"floor": 0, "column": 3, "type": MapNode.NodeType.EVENT, "next": [1], "scripted": &"ygg_arrival"},
	{"floor": 1, "column": 3, "type": MapNode.NodeType.EVENT, "next": [2], "scripted": &"ygg_door"},
	{"floor": 2, "column": 3, "type": MapNode.NodeType.COMBAT, "next": [3]},
	{"floor": 3, "column": 3, "type": MapNode.NodeType.EVENT, "next": [4], "scripted": &"ygg_mound"},
	{"floor": 4, "column": 3, "type": MapNode.NodeType.EVENT, "next": [], "way_back": true},
]


## Builds the far map. `home_realm` is where its way back leads; `floor_base` is the depth the player
## came from, which the far map's fights scale to; `has_events` is whether the route has a pool.
static func generate_edge(rng: RandomNumberGenerator, home_realm: StringName, floor_base: int,
		has_events: bool, layout: Array = _EDGE_LAYOUT) -> MapData:
	var map := MapData.new()
	map.floor_base = floor_base
	var top := 0
	for i in layout.size():
		var slot: Dictionary = layout[i]
		var node := MapNode.new()
		node.id = i
		node.floor_num = slot["floor"]
		node.column = slot["column"]
		node.node_type = slot["type"]
		node.next_nodes.assign(slot["next"])
		node.scripted_event_id = slot.get("scripted", &"")
		if slot.get("way_back", false):
			node.crossing_to = home_realm
		elif node.node_type == MapNode.NodeType.EVENT and node.scripted_event_id == &"" and not has_events:
			node.node_type = MapNode.NodeType.COMBAT
		map.nodes[i] = node
		top = maxi(top, node.floor_num)
	map.floor_count = top + 1
	map.starting_node_ids.append(0)
	_apply_jitter(map, rng)
	return map


# A treasure cache a random Campfire exposes mid-run. Unlike the raider payoff (seated at
# gen with a known giver), the Campfire can fire anywhere, so its payoff is chosen at the
# moment of investigation from the nodes still AHEAD of where the player is standing. This
# only re-targets an existing COMBAT node's routing -- it never adds a node or edge -- so the
# map's planarity and reachability guarantees are untouched. _is_reserved_node already skips
# nodes tagged for another questline, so a Campfire cache never lands on the raider payoff.


## COMBAT nodes forward-reachable from `from_id`, far enough ahead to read as "elsewhere on
## the road," unvisited, not reserved, and not already a quest node. The candidate set behind
## both the reachability gate and the pick.
static func _treasure_candidates(map: MapData, from_id: int) -> Array[int]:
	var cands: Array[int] = []
	var from_node: MapNode = map.get_node(from_id)
	if from_node == null:
		return cands
	var reachable := _reachable_from(map, from_id)
	for id in reachable:
		var n: MapNode = map.nodes[id]
		if n.node_type != MapNode.NodeType.COMBAT:
			continue
		if n.floor_num < from_node.floor_num + QUEST_PAYOFF_MIN_GAP:
			continue
		if n.visited or _is_reserved_node(map, n):
			continue
		cands.append(id)
	return cands


## True if a Campfire standing on `from_id` has somewhere downstream to seat a treasure. rng-
## free so the event-selection gate can consult it without perturbing the run seed (a Campfire
## with no valid payoff is swapped for a different event rather than offering a dead choice).
static func has_treasure_payoff(map: MapData, from_id: int) -> bool:
	return not _treasure_candidates(map, from_id).is_empty()


## Picks one treasure-payoff node (seeded), or -1 if none fits (the fire fired too late in the
## act). The caller tags the node with quest_payoff_id and arms the quest.
static func pick_treasure_payoff(map: MapData, from_id: int, rng: RandomNumberGenerator) -> int:
	var cands := _treasure_candidates(map, from_id)
	if cands.is_empty():
		return -1
	RngManager.shuffle(cands, rng)
	return cands[0]


## True while the payoff node of a questline is still ahead of the player: tagged on this map,
## not yet visited, and forward-reachable from where the player stands. A quest item whose
## payoff fails this is spent (the lair is behind you, or the route to it is gone). rng-free, so
## the pack UI can ask on every redraw.
static func quest_payoff_ahead(map: MapData, quest_id: StringName) -> bool:
	if map == null or quest_id == &"":
		return false
	var payoff: MapNode = null
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.quest_payoff_id == quest_id:
			payoff = n
			break
	if payoff == null or payoff.visited:
		return false
	if map.current_node_id == -1:
		return true  # the player has not entered the map yet; every node is ahead
	return _reachable_from(map, map.current_node_id).has(payoff.id)


## Nodes that signature placement must never overwrite: the boss, the Sword, the opening
## row, the guaranteed pre-boss rest, and anything already tagged for the questline.
static func _is_reserved_node(map: MapData, n: MapNode) -> bool:
	if n.node_type == MapNode.NodeType.BOSS or n.node_type == MapNode.NodeType.SWORD_IN_STONE:
		return true
	if n.floor_num == 0 or n.floor_num >= map.floor_count - 2:
		return true
	if n.quest_giver_id != &"" or n.quest_payoff_id != &"" or n.scripted_event_id != &"":
		return true
	if n.crossing_to != &"":
		return true
	return false


## Set of node ids reachable by walking FORWARD (next_nodes) from `start_id`, excluding the
## start itself. Used to guarantee the payoff is reachable once the player stands on the giver.
static func _reachable_from(map: MapData, start_id: int) -> Dictionary:
	var seen: Dictionary = {}
	var stack: Array[int] = [start_id]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		for nxt in map.nodes[id].next_nodes:
			if not seen.has(nxt):
				seen[nxt] = true
				stack.append(nxt)
	return seen


# Path-aware type-assignment rules. The point is that which BRANCH you take is a
# real decision: services and elites are NOT floor-locked, so different paths carry
# different risk/reward (a shop-bearing route, an elite-heavy route, a safe route).
const MIN_ELITE_FLOOR := 4      # no elites in the opening stretch (deck too thin)
const MIN_REST_FLOOR := 3
const MIN_SHOP_FLOOR := 3
const MAX_ELITES_PER_PATH := 3  # cap the risk any single route can pile on
const MIN_SHOPS_TOTAL := 2      # at least this many shops exist somewhere on the map


## Assigns node types with path-awareness (StS-style) so branch choice matters.
## Structural floors are fixed (opening combat, pre-boss rest, boss); the interior
## is filled by region-weighted rolls constrained so no two of the same special
## (Elite/Rest/Shop) sit back-to-back on a path and min-floor rules hold. A pair of
## guarantee passes then cap elites-per-path and ensure a reachable shop (incl. a
## back-half gold sink) exists — without forcing one onto every route.
static func _assign_types(map: MapData, rng: RandomNumberGenerator,
		elite_frequency_mult: float = 1.0) -> void:
	var last := map.floor_count - 1

	# Fixed structural floors: the opening fight, a guaranteed pre-boss rest so
	# every route can heal/upgrade before the boss, and the boss itself.
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		if node.floor_num == 0:
			node.node_type = MapNode.NodeType.COMBAT
		elif node.floor_num == last:
			node.node_type = MapNode.NodeType.BOSS
		elif node.floor_num == last - 1:
			node.node_type = MapNode.NodeType.REST

	# Predecessor lookup: the floor-below nodes feeding into each node, used for
	# the no-same-special-in-a-row rule.
	var preds := {}
	for id in map.nodes:
		for nxt in map.nodes[id].next_nodes:
			if not preds.has(nxt):
				preds[nxt] = []
			preds[nxt].append(id)

	# Fill the interior bottom-up so each node can see its parents' assigned types.
	for floor in range(1, last - 1):
		for node in map.get_nodes_on_floor(floor):
			node.node_type = _pick_interior_type(node, floor, last, preds, map, rng, elite_frequency_mult)

	# Path-aware guarantees.
	_enforce_elite_cap(map)
	_ensure_shop_access(map, rng)


## Weighted, constrained type roll for one interior node.
static func _pick_interior_type(node: MapNode, floor: int, last: int,
		preds: Dictionary, map: MapData, rng: RandomNumberGenerator,
		elite_frequency_mult: float = 1.0) -> MapNode.NodeType:
	var weights := _region_weights(floor, last, elite_frequency_mult)

	# Min-floor gates.
	if floor < MIN_ELITE_FLOOR:
		weights.erase(MapNode.NodeType.ELITE)
	if floor < MIN_REST_FLOOR:
		weights.erase(MapNode.NodeType.REST)
	if floor < MIN_SHOP_FLOOR:
		weights.erase(MapNode.NodeType.SHOP)
	# The floor directly under the guaranteed pre-boss rest can't also be a rest,
	# or every route would stack rest-on-rest into the boss.
	if floor == last - 2:
		weights.erase(MapNode.NodeType.REST)

	# No two of the same special (Elite/Rest/Shop) adjacent along any path: if a
	# parent already holds that special, drop it from this node's options.
	for pid in preds.get(node.id, []):
		var pt: MapNode.NodeType = map.nodes[pid].node_type
		if pt == MapNode.NodeType.ELITE or pt == MapNode.NodeType.REST \
				or pt == MapNode.NodeType.SHOP:
			weights.erase(pt)

	return _weighted_pick(weights, rng)


## Region-weighted base distribution (before constraints). Early floors are mostly
## fights to build the deck; the mid/late board opens up to elites, services, and
## more events/mysteries.
static func _region_weights(floor: int, last: int, elite_frequency_mult: float = 1.0) -> Dictionary:
	var w: Dictionary
	if floor <= 4:
		w = {
			MapNode.NodeType.COMBAT: 60.0,
			MapNode.NodeType.EVENT: 24.0,
			MapNode.NodeType.MYSTERY: 12.0,
			MapNode.NodeType.ELITE: 6.0,
		}
	elif floor <= 8:
		w = {
			MapNode.NodeType.COMBAT: 30.0,
			MapNode.NodeType.ELITE: 17.0,
			MapNode.NodeType.EVENT: 18.0,
			MapNode.NodeType.MYSTERY: 12.0,
			MapNode.NodeType.REST: 11.0,
			MapNode.NodeType.SHOP: 12.0,
		}
	else:
		w = {
			MapNode.NodeType.COMBAT: 26.0,
			MapNode.NodeType.ELITE: 20.0,
			MapNode.NodeType.EVENT: 16.0,
			MapNode.NodeType.MYSTERY: 14.0,
			MapNode.NodeType.REST: 10.0,
			MapNode.NodeType.SHOP: 14.0,
		}
	# Realm-config elite-frequency knob: scale the ELITE weight so a "dangerous" realm
	# carries more elites (and a "safe" one fewer). The min-floor gate + no-two-in-a-row
	# + elite cap constraints in _pick_interior_type / _enforce_elite_cap still apply.
	if w.has(MapNode.NodeType.ELITE):
		w[MapNode.NodeType.ELITE] *= elite_frequency_mult
	return w


static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> MapNode.NodeType:
	var total := 0.0
	for w in weights.values():
		total += w
	if total <= 0.0:
		return MapNode.NodeType.COMBAT
	var r := rng.randf() * total
	var acc := 0.0
	for t in weights:
		acc += weights[t]
		if r <= acc:
			return t
	return MapNode.NodeType.COMBAT


## Converts down the highest excess elites on any route carrying more than the cap,
## so no single path is an unfair elite gauntlet.
static func _enforce_elite_cap(map: MapData) -> void:
	for _iter in range(64):
		var changed := false
		for path in _all_paths(map):
			var elites := []
			for nid in path:
				if map.nodes[nid].node_type == MapNode.NodeType.ELITE:
					elites.append(nid)
			if elites.size() > MAX_ELITES_PER_PATH:
				elites.sort_custom(func(a, b): return map.nodes[a].floor_num > map.nodes[b].floor_num)
				for i in range(elites.size() - MAX_ELITES_PER_PATH):
					map.nodes[elites[i]].node_type = MapNode.NodeType.COMBAT
				changed = true
		if not changed:
			return


## Ensures a shop is reachable (and a back-half one exists as a late gold sink),
## without forcing a shop onto every route — routing to one is the decision.
static func _ensure_shop_access(map: MapData, rng: RandomNumberGenerator) -> void:
	var shop_count := 0
	var back_half := false
	var mid_floor := map.floor_count / 2
	for id in map.nodes:
		if map.nodes[id].node_type == MapNode.NodeType.SHOP:
			shop_count += 1
			if map.nodes[id].floor_num >= mid_floor:
				back_half = true

	if not back_half:
		var late := _convertible_combat(map, mid_floor, map.floor_count - 3, rng)
		if late != -1:
			map.nodes[late].node_type = MapNode.NodeType.SHOP
			shop_count += 1

	while shop_count < MIN_SHOPS_TOTAL:
		var any := _convertible_combat(map, MIN_SHOP_FLOOR, map.floor_count - 3, rng)
		if any == -1:
			break
		map.nodes[any].node_type = MapNode.NodeType.SHOP
		shop_count += 1


## A random COMBAT node in the floor range, safe to convert to a service.
static func _convertible_combat(map: MapData, min_floor: int, max_floor: int,
		rng: RandomNumberGenerator) -> int:
	var cands := []
	for id in map.nodes:
		var n: MapNode = map.nodes[id]
		if n.node_type == MapNode.NodeType.COMBAT \
				and n.floor_num >= min_floor and n.floor_num <= max_floor:
			cands.append(id)
	if cands.is_empty():
		return -1
	return cands[rng.randi_range(0, cands.size() - 1)]


## Every start→boss path as an ordered array of node ids.
static func _all_paths(map: MapData) -> Array:
	var out := []
	for sid in map.starting_node_ids:
		_walk_paths(map, sid, [], out)
	return out


static func _walk_paths(map: MapData, nid: int, acc: Array, out: Array) -> void:
	var path: Array = acc.duplicate()
	path.append(nid)
	var node: MapNode = map.nodes[nid]
	if node.next_nodes.is_empty():
		out.append(path)
		return
	for nxt in node.next_nodes:
		_walk_paths(map, nxt, path, out)
