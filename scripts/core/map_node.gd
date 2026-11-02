class_name MapNode
extends RefCounted
## A single node on the act map. Holds type, position, and connections.

enum NodeType { COMBAT, ELITE, REST, SHOP, EVENT, MYSTERY, BOSS, SWORD_IN_STONE }

var id: int = 0
var floor_num: int = 0
var column: int = 0
var node_type: NodeType = NodeType.COMBAT
var next_nodes: Array[int] = [] # IDs of connected nodes on the next floor
var visited: bool = false
# ELITE-only: weakened by the Folk pledge (see RealmConfig.elite_weaken). The node stays an
# elite (keeps its reward), but the encounter starts the enemies with Weak + a power nerf,
# and the node shows a "weakened" badge. Set by MapGenerator's pledge transform.
var weakened: bool = false
# Cross-map questlines (the raider hunt; a Campfire-revealed treasure cache). A GIVER node
# looks like an ordinary event node but routes to the quest's plea when entered; accepting it
# ARMS the payoff. A PAYOFF node is INDISTINGUISHABLE from the ordinary node it sits on until
# armed -- on arm its glyph reveals and entering it routes to the quest's payoff instead of its
# original node type. Both hold the same quest id (&"" = not a quest node). The raider pair is
# seated at gen (MapGenerator._place_raider_questline); the Campfire cache tags its payoff at
# runtime (event_scene._arm_campfire_treasure picks a node downstream of the fire).
var quest_giver_id: StringName = &""
var quest_payoff_id: StringName = &""
# A scripted event node: an EVENT node that always shows one named hand-authored event
# (event_scene._build_special_event) instead of a draw from the pool, and shows the player what it
# is on the map, so a run can route to it. The Master of Game (the huntsman selling his lord's
# animals) is seated once a map by MapGenerator._place_master_of_game. &"" = an ordinary node.
var scripted_event_id: StringName = &""
# Purely-cosmetic sub-cell offsets (in fractions of a cell) so the rendered graph
# looks organically placed instead of a rigid lattice. Set by MapGenerator; the
# grid column/floor still drive connectivity, balance, and layout — jitter never
# changes which nodes exist or connect.
var x_jitter: float = 0.0
var y_jitter: float = 0.0


static func type_label(t: NodeType) -> String:
	match t:
		NodeType.COMBAT: return "⚔"
		NodeType.ELITE: return "☠"
		NodeType.REST: return "♨"
		NodeType.SHOP: return "$"
		NodeType.EVENT: return "!"
		NodeType.MYSTERY: return "?"
		NodeType.BOSS: return "★"
		NodeType.SWORD_IN_STONE: return "✦"
	return "?"


static func type_name(t: NodeType) -> String:
	match t:
		NodeType.COMBAT: return "Combat"
		NodeType.ELITE: return "Elite"
		NodeType.REST: return "Rest"
		NodeType.SHOP: return "Shop"
		NodeType.EVENT: return "Event"
		NodeType.MYSTERY: return "Mystery"
		NodeType.BOSS: return "Boss"
		NodeType.SWORD_IN_STONE: return "The Sword in the Stone"
	return "???"


static func type_color(t: NodeType) -> Color:
	match t:
		NodeType.COMBAT: return Color(0.9, 0.25, 0.2)
		NodeType.ELITE: return Color(0.95, 0.65, 0.1)
		NodeType.REST: return Color(0.3, 0.8, 0.4)
		NodeType.SHOP: return Color(0.3, 0.7, 0.9)
		NodeType.EVENT: return Color(0.8, 0.55, 0.9)
		NodeType.MYSTERY: return Color(0.55, 0.55, 0.55)
		NodeType.BOSS: return Color(0.95, 0.15, 0.15)
		NodeType.SWORD_IN_STONE: return Color(1.0, 0.85, 0.35)  # heraldic gold
	return Color.WHITE
