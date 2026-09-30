extends Control
## DEV SANDBOX for the map-reveal node motion. A "Play Reveal" button replays the
## enlarge -> swap -> de-enlarge animation (the exact RevealAnim the real map uses) on a
## grid of map-styled nodes, staggered bottom-to-top like the real reveal. Tweak the motion
## in RevealAnim (or the PARAMS below) and re-click to feel it. Not shipped content.
## Run directly: godot --path . res://scenes/dev/reveal_test_scene.tscn

const ROWS := 4
const COLS := 6
const NODE_SIZE := 50
const ROW_STAGGER := 0.22   # bottom row reveals first, each row up delayed by this
const COL_STAGGER := 0.04

# Mirrors map_scene's per-node timings (currently slowed by half). Tune here to feel it,
# then copy into map_scene's REVEAL_* consts (or vice-versa).
const PARAMS := {
	"enlarge": 1.4,
	"enlarge_t": 0.28,
	"swap_t": 0.24,
	"deenlarge_t": 0.20,
}

# A representative spread of node types so the glyph "swap" is visible across kinds.
const TYPES := [
	MapNode.NodeType.COMBAT, MapNode.NodeType.ELITE, MapNode.NodeType.REST,
	MapNode.NodeType.SHOP, MapNode.NodeType.EVENT, MapNode.NodeType.MYSTERY,
	MapNode.NodeType.SWORD_IN_STONE, MapNode.NodeType.BOSS,
]

var _nodes: Array[Button] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 24)
	add_child(root)

	var title := Label.new()
	title.text = "Map-Reveal Node Motion — enlarge · swap · de-enlarge"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.4))
	root.add_child(title)

	var info := Label.new()
	info.text = "enlarge %.2fs · swap %.2fs · de-enlarge %.2fs · row stagger %.2fs" % [
		PARAMS["enlarge_t"], PARAMS["swap_t"], PARAMS["deenlarge_t"], ROW_STAGGER]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", Color(0.6, 0.58, 0.5))
	root.add_child(info)

	# Node grid (rows top-to-bottom; bottom row reveals first).
	var grid := VBoxContainer.new()
	grid.alignment = BoxContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("separation", 26)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(grid)

	var t := 0
	for r in ROWS:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 40)
		grid.add_child(row)
		for c in COLS:
			var node_type: int = TYPES[t % TYPES.size()]
			t += 1
			var btn := _make_node(node_type)
			row.add_child(btn)
			_nodes.append(btn)

	var play := Button.new()
	play.text = "▶  Play Reveal"
	play.custom_minimum_size = Vector2(220, 52)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.add_theme_font_size_override("font_size", 22)
	play.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	play.pressed.connect(_play)
	root.add_child(play)

	# Play once on open so it's not a blank grid.
	_play.call_deferred()


func _make_node(node_type: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.text = MapNode.type_label(node_type)
	btn.set_meta("glyph", btn.text)
	btn.add_theme_font_size_override("font_size", 20)

	var col := MapNode.type_color(node_type)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(NODE_SIZE / 2)
	style.set_border_width_all(3)
	style.bg_color = col.darkened(0.5)
	style.border_color = col
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


func _play() -> void:
	for i in _nodes.size():
		var btn := _nodes[i]
		var real: String = btn.get_meta("glyph", "")
		btn.text = ""  # glyph swaps in at the flip midpoint
		var row := i / COLS
		var col := i % COLS
		# Bottom row first (largest row index -> smallest delay).
		var delay := float(ROWS - 1 - row) * ROW_STAGGER + float(col) * COL_STAGGER
		var swap_cb := func() -> void: btn.text = real
		RevealAnim.play_node(self, btn, delay, PARAMS, swap_cb)
