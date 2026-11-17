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
# armed: on arm its glyph reveals and entering it routes to the quest's payoff instead of its
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
# A crossing: stepping on this node leaves the map for the realm named here or, on a far map, goes
# back to it. Seated by MapGenerator._place_crossing on top of an ordinary node whose node_type stays
# as it was, so anything that reads the map's shape sees the same map. &"" = not a crossing.
var crossing_to: StringName = &""
# Purely-cosmetic sub-cell offsets (in fractions of a cell) so the rendered graph
# looks organically placed instead of a rigid lattice. Set by MapGenerator; the
# grid column/floor still drive connectivity, balance, and layout; jitter never
# changes which nodes exist or connect.
var x_jitter: float = 0.0
var y_jitter: float = 0.0


# What the map shows for a node: its glyph, colour and name, in one place. The node painter, the map
# peek and the legend all go through look(), so a kind added here is painted and joins the legend by
# itself; the content linter fails a kind with no name. `order` is its place in the legend. A
# `landmark` stays bright while locked. `lit` only keeps it bright on the map, for a kind worth seeing
# from far off when choosing a route; it is not a landmark anywhere else. `loud` is a bigger ring:
# [fill darkened, ring lightened, hover fill darkened, hover ring lightened]. `font` is the glyph's
# size, 20 when it has none: DejaVu Sans draws most of these marks finer than a letter, so the
# fighting kinds and the Master of Game are drawn larger to read at a glance. `bold` thickens a mark
# drawn in fine lines.
const EVENT_COLOR := Color(0.8, 0.55, 0.9)
const TYPE_LOOKS := {
	NodeType.COMBAT: {"glyph": "⚔", "name": "Combat", "color": Color(0.9, 0.25, 0.2), "order": 10, "font": 26,
		"bold": true},
	NodeType.ELITE: {"glyph": "☠", "name": "Elite", "color": Color(0.95, 0.65, 0.1), "order": 20, "font": 30,
		"lit": true},
	NodeType.REST: {"glyph": "♨", "name": "Rest", "color": Color(0.3, 0.8, 0.4), "order": 30, "font": 28,
		"bold": true},
	NodeType.SHOP: {"glyph": "$", "name": "Shop", "color": Color(0.3, 0.7, 0.9), "order": 40},
	NodeType.EVENT: {"glyph": "!", "name": "Event", "color": EVENT_COLOR, "order": 50},
	NodeType.MYSTERY: {"glyph": "?", "name": "Mystery", "color": Color(0.55, 0.55, 0.55), "order": 60},
	# The signature quest node, in heraldic gold.
	NodeType.SWORD_IN_STONE: {"glyph": "✦", "name": "The Sword in the Stone", "color": Color(1.0, 0.85, 0.35),
		"order": 70, "font": 30, "landmark": true, "loud": [0.35, 0.25, 0.15, 0.4]},
	# The act's threat: bold, vivid, resilient to the map's darkening.
	NodeType.BOSS: {"glyph": "★", "name": "Boss", "color": Color(0.95, 0.15, 0.15),
		"order": 100, "font": 32, "landmark": true, "loud": [0.15, 0.35, 0.0, 0.5]},
}
# A crossing has no name in the game, so it is flagged `unnamed`: the legend shows its glyph alone and
# the linter lets it off. It wears the weather of the realm it opens on, never one look across realms.
# Keyed by that realm. Placeholder glyphs until the crossing's presentation lands.
const CROSSING_LOOKS := {
	&"yggdrasil": {"glyph": "❄", "name": "", "unnamed": true, "color": Color(0.8, 0.9, 1.0),
		"order": 95, "font": 26, "landmark": true},
	&"camelot": {"glyph": "☀", "name": "", "unnamed": true, "color": Color(0.99, 0.83, 0.42),
		"order": 95, "font": 26, "landmark": true},
}
# Drained: the elite is still there, with the fight gone out of it.
const WEAKENED_ELITE_LOOK := {"glyph": "☠", "name": "Weakened Elite", "color": Color(0.5, 0.56, 0.62), "order": 25,
	"font": 30}
# Seated scripted events, meant to be found and routed to, so each shows what it is.
const SCRIPTED_LOOKS := {
	&"master_of_game": {"glyph": "♞", "name": "The Master of Game", "color": EVENT_COLOR, "order": 80, "font": 30,
		"lit": true},
	&"scriptorium": {"glyph": "✎", "name": "The Scriptorium", "color": EVENT_COLOR, "order": 85, "font": 24, "bold": true},
	&"tourney": {"glyph": "✎", "name": "The Tourney", "color": EVENT_COLOR, "order": 85, "font": 24, "bold": true},
	&"reliquary": {"glyph": "✎", "name": "The Reliquary", "color": EVENT_COLOR, "order": 85, "font": 24, "bold": true},
}
# An armed questline payoff, in hunt gold. It overrides the ordinary look of the node it sits on,
# and only once armed: before that the node must read as whatever it was.
const QUEST_MARK_LOOK := {"glyph": "◎", "name": "Quest", "color": Color(1.0, 0.8, 0.3),
	"order": 90, "font": 28, "landmark": true, "loud": [0.4, 0.2, 0.2, 0.4]}


## What this node shows. `quest_armed` is the caller's, since arming lives in RunManager.
func look(quest_armed: bool = false) -> Dictionary:
	if CROSSING_LOOKS.has(crossing_to):
		return CROSSING_LOOKS[crossing_to]
	if quest_armed and quest_payoff_id != &"":
		return QUEST_MARK_LOOK
	if SCRIPTED_LOOKS.has(scripted_event_id):
		return SCRIPTED_LOOKS[scripted_event_id]
	if node_type == NodeType.ELITE and weakened:
		return WEAKENED_ELITE_LOOK
	return TYPE_LOOKS[node_type]


static func type_name(t: NodeType) -> String:
	return TYPE_LOOKS[t]["name"]
