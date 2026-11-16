extends Node
## Headless analysis of map PATH variety (not just visual layout). For several
## seeds it enumerates every start→boss path and reports the per-path node-type
## composition, so we can see whether path CHOICE is meaningful (paths differ in
## enemy density / shop / rest / elite counts) or homogeneous (every path ~same).
## Run: godot --headless --path . res://tools/map_path_analysis.tscn --quit-after 200
## A scene rather than a --script tool because MapGenerator shuffles through the RngManager
## autoload, and --script mode loads no autoloads.

const TYPE_NAMES := ["Combat", "Elite", "Rest", "Shop", "Event", "Mystery", "Boss", "Sword"]


func _ready() -> void:
	for s in [101, 202, 303]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var map: MapData = MapGenerator.generate(rng, &"camelot", 1)
		_report(map, s)
	get_tree().quit()


func _report(map: MapData, s: int) -> void:
	print("\n=== SEED %d ===" % s)

	# Which node types are floor-locked (identical type across the whole floor)?
	var locked := []
	for f in map.floor_count:
		var nodes := map.get_nodes_on_floor(f)
		if nodes.is_empty():
			continue
		var t0 = nodes[0].node_type
		var uniform := true
		for n in nodes:
			if n.node_type != t0:
				uniform = false
				break
		if uniform and nodes.size() > 1:
			locked.append("f%d=%s" % [f, MapNode.type_name(t0)])
	print("Floor-locked (same type on ALL columns): ", ", ".join(locked))

	# Enumerate all start→boss paths.
	var paths: Array = []
	for sid in map.starting_node_ids:
		_walk(map, sid, [], paths)

	# Per-path type counts.
	var counts_by_type := {}  # type -> Array[int] across paths
	for t in TYPE_NAMES.size():
		counts_by_type[t] = []
	for path in paths:
		var c := {}
		for nid in path:
			var t = map.nodes[nid].node_type
			c[t] = c.get(t, 0) + 1
		for t in TYPE_NAMES.size():
			counts_by_type[t].append(c.get(t, 0))

	print("Distinct start→boss paths: %d" % paths.size())
	print("Per-path composition  [min..max] (spread = how much path CHOICE matters):")
	for t in [0, 1, 2, 3, 4, 5]:  # skip Boss/Sword
		var arr: Array = counts_by_type[t]
		if arr.is_empty():
			continue
		var lo = arr.min()
		var hi = arr.max()
		var avg := 0.0
		for v in arr:
			avg += v
		avg /= arr.size()
		print("  %-8s min %d  max %d  avg %.1f   %s" % [
			TYPE_NAMES[t], lo, hi, avg,
			("<-- varies" if hi - lo >= 2 else "(~same on every path)")])


func _walk(map: MapData, nid: int, acc: Array, out: Array) -> void:
	var path = acc.duplicate()
	path.append(nid)
	var node: MapNode = map.nodes[nid]
	if node.next_nodes.is_empty():
		out.append(path)
		return
	for nxt in node.next_nodes:
		_walk(map, nxt, path, out)
