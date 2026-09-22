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
		act: int = 1) -> MapData:
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

	# Phase 6: Assign node types
	_assign_types(map, rng)

	# Phase 7: Realm-specific signature nodes
	_apply_realm_specifics(map, realm_id, act)

	# Phase 8: cosmetic placement jitter — organic look, never touches connectivity
	_apply_jitter(map, rng)

	return map


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


## Realm-specific central quest nodes. Currently: Camelot Act 1 gets the Sword in
## the Stone at the center floor's middle column. We replace the nearest existing
## node — paths that happen to go through the center hit it, others bypass it.
## This matches the design intent that pathing to the central quest is itself the
## decision, not a forced detour.
static func _apply_realm_specifics(map: MapData, realm_id: StringName, act: int) -> void:
	if realm_id == &"camelot" and act == 1:
		_place_sword_in_stone(map)


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
static func _assign_types(map: MapData, rng: RandomNumberGenerator) -> void:
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
			node.node_type = _pick_interior_type(node, floor, last, preds, map, rng)

	# Path-aware guarantees.
	_enforce_elite_cap(map)
	_ensure_shop_access(map, rng)


## Weighted, constrained type roll for one interior node.
static func _pick_interior_type(node: MapNode, floor: int, last: int,
		preds: Dictionary, map: MapData, rng: RandomNumberGenerator) -> MapNode.NodeType:
	var weights := _region_weights(floor, last)

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
static func _region_weights(floor: int, last: int) -> Dictionary:
	if floor <= 4:
		return {
			MapNode.NodeType.COMBAT: 60.0,
			MapNode.NodeType.EVENT: 24.0,
			MapNode.NodeType.MYSTERY: 12.0,
			MapNode.NodeType.ELITE: 6.0,
		}
	elif floor <= 8:
		return {
			MapNode.NodeType.COMBAT: 30.0,
			MapNode.NodeType.ELITE: 17.0,
			MapNode.NodeType.EVENT: 18.0,
			MapNode.NodeType.MYSTERY: 12.0,
			MapNode.NodeType.REST: 11.0,
			MapNode.NodeType.SHOP: 12.0,
		}
	else:
		return {
			MapNode.NodeType.COMBAT: 26.0,
			MapNode.NodeType.ELITE: 20.0,
			MapNode.NodeType.EVENT: 16.0,
			MapNode.NodeType.MYSTERY: 14.0,
			MapNode.NodeType.REST: 10.0,
			MapNode.NodeType.SHOP: 14.0,
		}


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
