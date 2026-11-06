class_name MapData
extends RefCounted
## Holds all nodes for one act's map and tracks the player's position.

var nodes: Dictionary = {} # int (id) -> MapNode
var floor_count: int = 15
var current_node_id: int = -1 # -1 = haven't entered the map yet
var starting_node_ids: Array[int] = []
# Nodes the realm-entry pledge changed, for the "watch your choice reshape these" animation:
# node id -> change kind (&"elite_added" = a combat node the Court pledge upgraded to elite;
# &"weakened" = an elite the Folk pledge weakened). Empty on a neutral / no-pledge map.
var pledge_changes: Dictionary = {}


func get_node(id: int) -> MapNode:
	return nodes.get(id)


## Returns node IDs the player can move to right now.
func get_available_next_ids() -> Array[int]:
	if current_node_id == -1:
		return starting_node_ids
	var current = get_node(current_node_id)
	if current:
		return current.next_nodes
	return []


## The node ids along one forward road from `from_id` to `to_id`, both included, or empty if none
## reaches it. -1 starts from the opening row, as a player who has not entered the map would.
func road_between(from_id: int, to_id: int) -> Array[int]:
	var frontier: Array[int] = []
	if from_id == -1:
		frontier.assign(starting_node_ids)
	else:
		frontier.append(from_id)
	var came_from := {}
	for id in frontier:
		came_from[id] = -1
	while not frontier.is_empty():
		var id: int = frontier.pop_front()
		if id == to_id:
			var road: Array[int] = []
			while id != -1:
				road.push_front(id)
				id = came_from[id]
			return road
		var node := get_node(id)
		if node == null:
			continue
		for next_id in node.next_nodes:
			if not came_from.has(next_id):
				came_from[next_id] = id
				frontier.append(next_id)
	return []


func move_to(node_id: int) -> void:
	current_node_id = node_id
	var node = get_node(node_id)
	if node:
		node.visited = true


func get_nodes_on_floor(floor_num: int) -> Array[MapNode]:
	var result: Array[MapNode] = []
	for id in nodes:
		if nodes[id].floor_num == floor_num:
			result.append(nodes[id])
	return result
