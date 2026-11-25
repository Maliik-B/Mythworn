extends Control
## STS-style branching node map. Displays the map, handles node selection,
## and transitions to combat/rest/etc based on node type.

# Layout
# 200 (was 130): the 7 grid columns now span ~1410px of the 1920 base width (~73%,
# centred by _map_x_offset) instead of ~990px (~52%), so the graph fills the board
# instead of clustering in a narrow centre band with the sides empty (backlog #2).
# Purely a render-spacing change; grid columns/connections/planarity are untouched,
# and it stays within the viewport so horizontal scroll (disabled) is never needed.
const NODE_SPACING_X := 200
const NODE_SPACING_Y := 90
const MAP_MARGIN_X := 80
const MAP_MARGIN_Y := 60
# Extra top margin so the top row (boss) never rides up under the realm sigil /
# act title, and stays out of the darkest top-of-map effects. The
# always-readable header text tolerates the effects; the node icons should not.
const MAP_MARGIN_TOP := 165
const NODE_SIZE := 50

# A sentence a line at this size is what fits a quest's toast in the phone crop.
const QUEST_TOAST_SIZE := 44
const QUEST_TOAST_OUTLINE := 12

# The node key: down the left margin under the shield, where no node goes. Pointing at an entry
# rings every node of that kind and steps the rest back.
const LEGEND_AT := Vector2(34, 178)
const LEGEND_PLATE := Color(0.05, 0.04, 0.08, 0.62)
const LEGEND_NAME := Color(0.82, 0.78, 0.70)
const LEGEND_RING_PAD := 7.0
const LEGEND_DIM := 0.25

# The deck grid draws each card's face at this fraction of its size, so a deck fits a few rows.
const DECK_FACE_SCALE := 0.8
const DECK_GRID_COLUMNS := 9

# UI references
var scroll_container: ScrollContainer
var map_canvas: Control
var node_buttons: Dictionary = {} # node_id -> Button
var hp_label: Label
var gold_label: Label
var passion_label: Label
var relic_btn: Button
var deck_btn: Button
var titles_btn: Button
var excalibur_btn: Button  # Only visible when player holds Excalibur (Camelot quest reward)
var thurible_btn: Button  # Only visible when player holds The Thurible (Reliquary censer relic)
var consumable_bar: ConsumableBar  # The pack: two consumable slots, usable from the map
var pet_label: Label  # The companion readout; only visible when one travels with the player
var timer_label: Label
var seed_label: Label
var info_label: Label
var _header: Control  # the realm header floating over the top of the map
var _legend_plate: PanelContainer
var _legend_key: VBoxContainer
var _legend_refresh_queued := false
var _legend_lit := ""  # the kind of node the key is pointing at, or ""
var _legend_rings: Array[Control] = []
var popup_overlay: PanelContainer
var card_detail_overlay: Control


var _timer_accum := 0.0
var _pulse_time := 0.0
var _available_nodes: Array = []
var _map_x_offset := 0.0  # horizontal centering shift for the node graph
var _pledge_anim_active := false  # true while a flourish plays: the rewrite or a quest mark
var _flourish: MapFlourish = null

func _ready() -> void:
	# A map opened before the splash and the title could measure its glyphs (a direct launch, a
	# capture) waits the two frames here, so no glyph is ever seen moving into its place.
	NodeFace.prime_for_map()
	if not NodeFace.is_settled():
		await NodeFace.settled()
	if not RunManager.run_active:
		var character = _create_test_character()
		RunManager.start_run(character)

	# A freshly-generated map (realm/act entry, just after the pledge) gets the reveal
	# flourish; returning to an existing map just re-centers on the player.
	var fresh_map := RunManager.current_map == null
	if fresh_map:
		RunManager.current_map = MapGenerator.generate(RngManager.map_rng,
			RunManager.current_realm_id, RunManager.current_act,
			RunManager.realm_config.elite_frequency_mult,
			RunManager.realm_config.elite_weaken)

	# Resolve a realm-entry map_boon the first time the map opens this realm.
	# consume_map_boon clears the pending slot, so the later node-return reloads no-op.
	RunManager.consume_map_boon()

	_build_ui()
	_create_map_display()
	_update_node_states()
	_update_bottom_bar()
	_scroll_to_player.call_deferred()
	# First map open after a pledge: animate only the nodes the pledge changed.
	if fresh_map and not RunManager.current_map.pledge_changes.is_empty():
		_prime_pledge_changes(true)
	# Returning to the map having just armed a questline: reveal the now-armed payoff node
	# once. (Mutually exclusive with the pledge flourish, which only plays on a fresh map.) At
	# most one questline is pending a reveal per return; arming always happens inside an event.
	elif RunManager.first_unrevealed_quest() != &"":
		_prime_quest_reveal(RunManager.first_unrevealed_quest())
	AudioManager.play_music("map")

	# Refresh the bottom bar's title counter when titles change while on the map.
	# (The popup that announces a new title fires from this scene, so we need
	# to react locally rather than waiting for a scene reload.)
	Events.title_earned.connect(_on_title_state_changed_locally)
	Events.title_equipped.connect(_on_title_state_changed_locally)


func _on_title_state_changed_locally(_a = null, _b = null, _c = null) -> void:
	# Variadic shim: the two signals have different signatures.
	_update_bottom_bar()


## Builds the realm header that floats above the map scroll area. Has a vertical
## fade-out gradient so map nodes scrolling underneath remain partially visible.
## Mouse input passes through so the player can still click nodes behind the
## header without scrolling them out from under it.
func _build_floating_header(realm_name: String, realm_tagline: String,
		accent: Color, sigil_path: String) -> void:
	const HEADER_HEIGHT := 160
	const SIGIL_SIZE := 140

	# Outer container: anchored to the top, no input capture.
	var header = Control.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = HEADER_HEIGHT
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_header = header

	# Gradient backdrop: opaque at top, transparent at bottom.
	var grad = ColorRect.new()
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 base : source_color = vec4(0.06, 0.05, 0.10, 1.0);
void fragment() {
	// Solid in the top ~50%, smooth fade to transparent across the bottom.
	float alpha = 1.0 - smoothstep(0.45, 1.0, UV.y);
	COLOR = vec4(base.rgb, alpha * 0.92);
}
"""
	mat.shader = shader
	grad.material = mat
	# Blend a touch of realm accent into the base so the header reads as part of the realm.
	var header_base := Color(0.06, 0.05, 0.10).lerp(accent, 0.18).darkened(0.35)
	mat.set_shader_parameter("base", Vector4(header_base.r, header_base.g, header_base.b, 1.0))
	header.add_child(grad)

	# Realm sigil: corner badge in the top-left. Only rendered if the realm
	# has authored sigil art; absent for stub realms.
	if sigil_path != "" and ResourceLoader.exists(sigil_path):
		var sigil_tex: Texture2D = load(sigil_path)
		if sigil_tex:
			var sigil = TextureRect.new()
			sigil.texture = sigil_tex
			sigil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sigil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sigil.custom_minimum_size = Vector2(SIGIL_SIZE, SIGIL_SIZE)
			sigil.size = Vector2(SIGIL_SIZE, SIGIL_SIZE)
			sigil.position = Vector2(28, 12)
			sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			header.add_child(sigil)

	# Content (text labels), positioned with a top inset.
	var inset = MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 20)
	inset.add_theme_constant_override("margin_right", 20)
	inset.add_theme_constant_override("margin_top", 10)
	inset.add_theme_constant_override("margin_bottom", 12)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(inset)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(vbox)

	if realm_name != "":
		var realm_lbl = Label.new()
		realm_lbl.text = realm_name
		realm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		realm_lbl.add_theme_font_size_override("font_size", 32)
		realm_lbl.add_theme_color_override("font_color", accent.lightened(0.15))
		realm_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(realm_lbl)

		if realm_tagline != "":
			var tagline_lbl = Label.new()
			tagline_lbl.text = realm_tagline
			tagline_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tagline_lbl.add_theme_font_size_override("font_size", 12)
			tagline_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
			tagline_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(tagline_lbl)

	# Act / boss line, paired with the hover info label. A route with no boss to name just says the act.
	var boss_name := EnemyPool.boss_name(RunManager.current_act)
	var title = Label.new()
	title.text = "Act %d" % RunManager.current_act if boss_name == "" \
		else "Act %d: %s" % [RunManager.current_act, boss_name]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	info_label = Label.new()
	info_label.text = "Choose your path"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(info_label)


## The key to the node glyphs, on a dark plate in the left margin. Filled by _refresh_legend from what
## the nodes are showing.
func _build_legend_key() -> void:
	_legend_plate = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = LEGEND_PLATE
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_legend_plate.add_theme_stylebox_override("panel", style)
	_legend_plate.position = LEGEND_AT
	_legend_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_legend_plate)
	_legend_key = VBoxContainer.new()
	_legend_key.add_theme_constant_override("separation", 3)
	_legend_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend_plate.add_child(_legend_key)


## Queued rather than run at once: a flourish paints several nodes in a beat.
func _queue_legend_refresh() -> void:
	if not _legend_refresh_queued:
		_legend_refresh_queued = true
		_refresh_legend.call_deferred()


## Rebuilds the legend from the looks the node buttons are wearing right now, not from the map's
## data. So it cannot give away what the map is hiding: a payoff that has not been armed, or one
## whose reveal has not landed yet, is painted as the ordinary node it sits on and adds nothing here.
func _refresh_legend() -> void:
	_legend_refresh_queued = false
	if not is_instance_valid(_legend_key):
		return
	_light_legend("")
	var shown := {}
	for id in node_buttons:
		var look: Dictionary = node_buttons[id].get_meta("look")
		shown[look["glyph"] + look["name"]] = look
	var looks: Array = shown.values()
	looks.sort_custom(func(a, b): return a["order"] < b["order"])
	# Out of the column before freeing, so a rebuild never leaves a row standing to the frame's end.
	for child in _legend_key.get_children():
		_legend_key.remove_child(child)
		child.queue_free()
	for look in looks:
		# A kind is its glyph and name together, so a nameless look (a crossing) is still a kind of
		# its own: a glyph with no word beside it.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_entered.connect(_light_legend.bind(look["glyph"] + look["name"]))
		row.mouse_exited.connect(_light_legend.bind(""))
		var glyph := Label.new()
		glyph.text = look["glyph"]
		glyph.custom_minimum_size = Vector2(20, 0)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 18)
		glyph.add_theme_color_override("font_color", look["color"])
		row.add_child(glyph)
		var kind := Label.new()
		kind.text = look["name"]
		kind.add_theme_font_size_override("font_size", 14)
		kind.add_theme_color_override("font_color", LEGEND_NAME)
		row.add_child(kind)
		_legend_key.add_child(row)
	_legend_plate.visible = not looks.is_empty()


## Points the map at one kind of node (its look's glyph and name): every node wearing that look gets
## a ring and full light, and the rest step back. "" gives the nodes back their states. Held off
## while a flourish repaints.
func _light_legend(look_key: String) -> void:
	if look_key == _legend_lit or (_pledge_anim_active and look_key != ""):
		return
	for ring in _legend_rings:
		if is_instance_valid(ring):
			ring.get_parent().remove_child(ring)
			ring.queue_free()
	_legend_rings.clear()
	_legend_lit = look_key
	if look_key == "":
		_update_node_states()
		return
	for id in node_buttons:
		var btn: Button = node_buttons[id]
		var look: Dictionary = btn.get_meta("look")
		if look["glyph"] + look["name"] != look_key:
			btn.modulate.a = LEGEND_DIM
			continue
		btn.modulate = Color.WHITE
		var ring := Panel.new()
		var side := NODE_SIZE + LEGEND_RING_PAD * 2.0
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.set_border_width_all(3)
		style.border_color = (look["color"] as Color).lightened(0.35)
		style.set_corner_radius_all(int(side / 2.0))
		ring.add_theme_stylebox_override("panel", style)
		ring.size = Vector2(side, side)
		ring.position = btn.position - Vector2(LEGEND_RING_PAD, LEGEND_RING_PAD)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_canvas.add_child(ring)
		_legend_rings.append(ring)


## Renders a sky body (moon, aurora) in the upper portion of the screen.
## Sits between the realm motif and the drift particles in the layer stack,
## visible behind the map nodes but in front of the base bg.
func _add_sky_body(kind: int, _accent: Color) -> void:
	if kind == RealmData.SkyBody.NONE:
		return

	var realm: RealmData = RunManager.get_current_realm()
	var act: int = RunManager.current_act

	# MOON uses a generated texture (guaranteed round disc, modulate for tint).
	# AURORA stays as an animated shader since the wave motion is its identity.
	if kind == RealmData.SkyBody.MOON:
		var moon_tint := Color(0.92, 0.95, 0.88, 1.0)
		if realm:
			moon_tint = realm.get_sky_body_color_for_act(act)
		var tex = _make_moon_texture(160)
		var moon = TextureRect.new()
		moon.texture = tex
		moon.modulate = moon_tint
		moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		moon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		moon.custom_minimum_size = Vector2(160, 160)
		moon.size = Vector2(160, 160)
		moon.position = Vector2(1500, 100)  # upper-right area
		moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(moon)
		return

	# AURORA: shader-driven animated bands
	var sky = ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sky.offset_bottom = 540
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var shader = Shader.new()

	match kind:
		RealmData.SkyBody.AURORA:
			# Wavy color bands across the upper sky, two bands of customizable
			# color so we can shift them per act (peaceful green/ice for
			# Act 1, deeper for Act 2, blood-red for Act 3).
			shader.code = """
shader_type canvas_item;
uniform float time_scale = 0.10;
uniform vec4 band_color_lower : source_color = vec4(0.30, 0.85, 0.55, 1.0);
uniform vec4 band_color_upper : source_color = vec4(0.45, 0.72, 0.80, 1.0);
uniform float intensity = 0.55;
void fragment() {
	vec2 uv = UV;
	float t = TIME * time_scale;
	float w1 = 0.55 + sin(uv.x * 6.0 + t * 0.8) * 0.06
	             + sin(uv.x * 13.0 + t * 1.6) * 0.025;
	float band1 = exp(-pow((uv.y - w1) * 12.0, 2.0));
	float w2 = 0.32 + sin(uv.x * 5.0 - t * 1.2) * 0.08
	             + sin(uv.x * 11.0 + t * 0.7) * 0.03;
	float band2 = exp(-pow((uv.y - w2) * 14.0, 2.0));
	vec3 col = band_color_lower.rgb * band1 + band_color_upper.rgb * band2;
	float a = (band1 + band2 * 0.85) * intensity;
	a *= smoothstep(0.0, 0.18, uv.y);
	COLOR = vec4(col, a);
}
"""
		_:
			return

	mat.shader = shader
	# AURORA: apply per-act color shift
	if kind == RealmData.SkyBody.AURORA and realm:
		var aurora_lower = realm.get_aurora_lower_for_act(act)
		var aurora_upper = realm.get_aurora_upper_for_act(act)
		mat.set_shader_parameter("band_color_lower",
				Vector4(aurora_lower.r, aurora_lower.g, aurora_lower.b, 1.0))
		mat.set_shader_parameter("band_color_upper",
				Vector4(aurora_upper.r, aurora_upper.g, aurora_upper.b, 1.0))
	sky.material = mat
	add_child(sky)


## Builds a soft circular moon texture (white + halo) at the given pixel radius.
## The TextureRect using it gets tinted via `modulate` for per-realm color.
func _make_moon_texture(radius_px: int) -> Texture2D:
	var s := radius_px * 2 + 80  # extra padding for halo
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := s / 2.0
	var cy := s / 2.0
	# Core radius in pixels
	var core_r := float(radius_px) * 0.42
	var halo_r := float(radius_px)
	for y in range(s):
		for x in range(s):
			var dx := x - cx
			var dy := y - cy
			var d := sqrt(dx * dx + dy * dy)
			# Core disc: soft round edge
			var disc_t := clampf((core_r * 1.15 - d) / (core_r * 0.30), 0.0, 1.0)
			# Halo: wide soft falloff
			var halo_t := clampf((halo_r - d) / (halo_r * 0.55), 0.0, 1.0)
			halo_t = halo_t * halo_t  # ease toward edge
			var a := maxf(disc_t * 0.95, halo_t * 0.22)
			if a > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## Adds ambient drift particles matching the realm's atmosphere.
## Two layered emitters per realm for depth, small fast "far" particles and
## larger slow "near" particles. Sits above the horizon, below the map nodes.
func _add_drift_particles(kind: int, _accent: Color) -> void:
	if kind == RealmData.DriftKind.NONE:
		return

	# Tunables per drift kind. (color, alpha, size_min, size_max, count_near,
	# count_far, vel_y_near, vel_y_far, vel_x_jitter, lifetime)
	# Counts and sizes increased after first pass: particles need to read as
	# ambient atmosphere, not isolated stars.
	var spec: Dictionary
	match kind:
		RealmData.DriftKind.DUST:
			# Warm dawn/dusk fireflies drifting slowly upward, sparse, glowing, and
			# twinkling, for that golden-hour-with-fireflies feeling. Fewer + bigger +
			# brighter than dust so each reads as a distinct point of light.
			spec = {
				"color": Color(0.99, 0.83, 0.42),
				"alpha": 0.62,
				"size_min": 3.5, "size_max": 8.5,
				"count_near": 42, "count_far": 66,
				"vel_y_near": -11.0, "vel_y_far": -5.0,
				"vel_x_jitter": 16.0,
				"lifetime": 16.0,
				"shape": "circle",
				"twinkle": true,
			}
		RealmData.DriftKind.SNOW:
			# Pale snowflakes falling slowly, cold mountain air
			# Smaller max size than v1 so they read as distant snowfall rather
			# than huge bokeh blobs.
			spec = {
				"color": Color(0.92, 0.95, 1.0),
				"alpha": 0.65,
				"size_min": 3.0, "size_max": 7.0,
				"count_near": 110, "count_far": 180,
				"vel_y_near": 32.0, "vel_y_far": 16.0,
				"vel_x_jitter": 18.0,
				"lifetime": 14.0,
				"shape": "circle",
			}
		RealmData.DriftKind.MIST:
			# Pale jade cloud wisps drifting horizontally, mountain mist
			spec = {
				"color": Color(0.82, 0.92, 0.85),
				"alpha": 0.35,
				"size_min": 24.0, "size_max": 60.0,
				"count_near": 18, "count_far": 32,
				"vel_y_near": 2.0, "vel_y_far": 1.0,
				"vel_x_jitter": 60.0,
				"lifetime": 28.0,
				"shape": "wisp",
			}
		RealmData.DriftKind.LANTERN:
			# Warm red-orange lantern lights drifting slowly upward, a sense
			# of nearby festival or pilgrims carrying lights. Pairs with MIST.
			spec = {
				"color": Color(0.95, 0.55, 0.30),
				"alpha": 0.70,
				"size_min": 4.0, "size_max": 9.0,
				"count_near": 18, "count_far": 25,
				"vel_y_near": -10.0, "vel_y_far": -5.0,
				"vel_x_jitter": 8.0,
				"lifetime": 16.0,
				"shape": "circle",
			}
		RealmData.DriftKind.SPIRIT_WISP:
			# Pale icy-blue spirit-wisps drifting slowly upward, Norse
			# will-o'-the-wisp / ancestor-light. Pairs with SNOW.
			spec = {
				"color": Color(0.75, 0.90, 1.0),
				"alpha": 0.55,
				"size_min": 5.0, "size_max": 11.0,
				"count_near": 14, "count_far": 22,
				"vel_y_near": -8.0, "vel_y_far": -4.0,
				"vel_x_jitter": 10.0,
				"lifetime": 18.0,
				"shape": "circle",
			}
		_:
			return

	# Two layers for parallax depth, far (small, faint, slower) then near (larger, brighter)
	add_child(_make_drift_emitter(spec, false))
	add_child(_make_drift_emitter(spec, true))


## Build a single GPUParticles2D emitter for one drift layer (near or far).
## Positioned at viewport center so the EMISSION_SHAPE_BOX covers the whole screen.
func _make_drift_emitter(spec: Dictionary, near: bool) -> GPUParticles2D:
	var emitter = GPUParticles2D.new()
	# GPUParticles2D is a Node2D, not a Control, use position, not anchors.
	# Place the emitter at the viewport center so the emission box (extents
	# 960x540) covers the full 1920x1080 viewport.
	emitter.position = Vector2(960, 540)
	emitter.amount = spec["count_near"] if near else spec["count_far"]
	emitter.lifetime = spec["lifetime"]
	emitter.preprocess = spec["lifetime"]  # spawn particles already aged so the screen isn't empty at scene-load
	emitter.visibility_rect = Rect2(-960, -540, 1920, 1080)  # local space; emitter is at viewport center

	var mat = ParticleProcessMaterial.new()
	# Emit randomly across the full viewport, emission box in LOCAL space,
	# centered on the emitter position.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(960, 540, 0)

	var vel_y: float = spec["vel_y_near"] if near else spec["vel_y_far"]
	var vx_jit: float = spec["vel_x_jitter"]
	mat.direction = Vector3(0, sign(vel_y), 0) if vel_y != 0.0 else Vector3(1, 0, 0)
	mat.initial_velocity_min = abs(vel_y) * 0.7
	mat.initial_velocity_max = abs(vel_y) * 1.3
	mat.spread = 25.0  # cone width around the direction
	mat.gravity = Vector3(0, 0, 0)
	mat.linear_accel_min = 0.0
	mat.linear_accel_max = 0.0
	# Horizontal jitter via tangential acceleration
	mat.tangential_accel_min = -vx_jit
	mat.tangential_accel_max = vx_jit

	# Particle scale (size in pixels)
	var size_min: float = spec["size_min"] * (1.0 if near else 0.55)
	var size_max: float = spec["size_max"] * (1.0 if near else 0.55)
	mat.scale_min = size_min / 8.0  # divided by texture base size
	mat.scale_max = size_max / 8.0

	# Color + alpha (with simple alpha curve so particles fade in/out)
	var col: Color = spec["color"]
	var alpha_mult := 0.6 if not near else 1.0
	col.a = spec["alpha"] * alpha_mult
	mat.color = col
	var alpha_curve := Curve.new()
	if spec.get("twinkle", false):
		# Firefly blink: fade in, pulse a few times over the life, fade out.
		alpha_curve.add_point(Vector2(0.0, 0.0))
		alpha_curve.add_point(Vector2(0.12, 1.0))
		alpha_curve.add_point(Vector2(0.28, 0.32))
		alpha_curve.add_point(Vector2(0.45, 1.0))
		alpha_curve.add_point(Vector2(0.62, 0.28))
		alpha_curve.add_point(Vector2(0.80, 1.0))
		alpha_curve.add_point(Vector2(1.0, 0.0))
	else:
		alpha_curve.add_point(Vector2(0.0, 0.0))
		alpha_curve.add_point(Vector2(0.15, 1.0))
		alpha_curve.add_point(Vector2(0.85, 1.0))
		alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_tex := CurveTexture.new()
	alpha_tex.curve = alpha_curve
	mat.alpha_curve = alpha_tex

	emitter.process_material = mat
	emitter.texture = _make_drift_texture(spec)
	# Don't capture mouse: ambient layer only
	# (GPUParticles2D doesn't take input by default, but if wrapped in CanvasItem this matters)
	return emitter


## Build a small white texture for the drift particle.
## - "circle": soft round dot
## - "wisp": elongated horizontal soft ellipse
func _make_drift_texture(spec: Dictionary) -> Texture2D:
	var w := 32
	var h := 32 if spec.get("shape", "circle") == "circle" else 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := w / 2.0
	var cy := h / 2.0
	var max_r := minf(cx, cy)
	for y in range(h):
		for x in range(w):
			var dx := (x - cx) / max_r
			var dy := (y - cy) / max_r
			if spec.get("shape", "circle") == "wisp":
				# Stretch horizontally: squash y in the distance calc
				dy *= 2.5
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var a := smoothstep(1.0, 0.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Adds a subtle full-screen motif overlay based on the realm's visual style.
## Each style uses a small shader fragment for the pattern; all sit at low alpha
## so the map's nodes and connections stay the visual focus.
func _add_realm_motif(style: int, accent: Color) -> void:
	var shader_code: String = ""
	match style:
		RealmData.VisualStyle.HERALDIC:
			# Faint diagonal chevron bands, knightly heraldry. Kept subtle and cleared
			# from the top so it never competes with the legend / act title, and tinted
			# gold (below) rather than the loud red act accent.
			shader_code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 uv = UV;
	float band = abs(fract((uv.x + uv.y) * 5.0) - 0.5);
	float chevron = smoothstep(0.44, 0.5, band);
	float top_clear = smoothstep(0.16, 0.36, uv.y);
	float depth = 0.55 + 0.45 * uv.y;
	COLOR = vec4(tint.rgb, chevron * 0.045 * top_clear * depth);
}
"""
		RealmData.VisualStyle.RUNIC:
			# Faint runic rings: much more subtle than v1 so they don't compete
			# with the actual map nodes (which are also circles). Larger cell
			# size = fewer rings overall, and lower alpha so they read as
			# subtle background texture rather than UI elements.
			shader_code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 uv = UV * vec2(5.0, 3.0);
	vec2 cell = fract(uv) - 0.5;
	float d = length(cell);
	float ring = smoothstep(0.38, 0.40, d) - smoothstep(0.42, 0.44, d);
	// Concentrate in the upper half so the bottom (horizon area) stays clean
	float fade = 0.6 * smoothstep(1.0, 0.0, UV.y);
	COLOR = vec4(tint.rgb, ring * 0.06 * fade);
}
"""
		RealmData.VisualStyle.SCROLL:
			# Horizontal scroll-paper striations.
			shader_code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	vec2 uv = UV;
	float wave = sin(uv.y * 40.0 + uv.x * 1.5) * 0.5 + 0.5;
	float stripe = smoothstep(0.7, 1.0, wave);
	float fade = 0.4 + 0.6 * (1.0 - abs(uv.y - 0.5) * 1.4);
	COLOR = vec4(tint.rgb, stripe * 0.06 * fade);
}
"""
		_:
			# NEUTRAL or unknown: no motif. Leaving the layer absent keeps
			# the cost at zero and the look clean.
			return

	var motif = ColorRect.new()
	motif.set_anchors_preset(Control.PRESET_FULL_RECT)
	motif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = shader_code
	mat.shader = shader
	# Motif follows the realm accent, which now ramps gold -> crimson -> blood per act,
	# so the faint heraldry warms in peace and reddens under strife on its own.
	mat.set_shader_parameter("tint", Vector4(accent.r, accent.g, accent.b, 1.0))
	motif.material = mat
	add_child(motif)


## A warm dawn glow rising from the horizon, "the coming of day." Sits behind the
## castle silhouette so the skyline is backlit, and warms toward the right where the
## light source sits. Gives the map a golden-hour dawn/dusk mood.
func _add_dawn_glow(accent: Color) -> void:
	var glow = ColorRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 warm : source_color = vec4(1.0);
void fragment() {
	float up = smoothstep(0.0, 0.9, UV.y);   // 0 at top -> 1 at the horizon (bottom)
	float side = mix(1.0, 0.5, UV.x);          // warmer toward the left (sun rising, opposite the moon)
	float g = pow(up, 1.7) * side;
	COLOR = vec4(warm.rgb, g * 0.30);
}
"""
	mat.shader = shader
	# Warm amber dawn light, nudged toward the realm accent so it stays "of this place."
	var dawn := Color(0.99, 0.66, 0.30).lerp(accent, 0.22)
	mat.set_shader_parameter("warm", Vector4(dawn.r, dawn.g, dawn.b, 1.0))
	glow.material = mat
	add_child(glow)


func _process(delta: float) -> void:
	_timer_accum += delta
	if _timer_accum >= 1.0:
		_timer_accum -= 1.0
		timer_label.text = RunManager.get_run_time_string()

	# Pulse available nodes (paused while a flourish climbs the map, and while the key
	# is pointing at a kind of node, which sets their light itself).
	_pulse_time += delta
	if not _pledge_anim_active and _legend_lit == "":
		for id in _available_nodes:
			var btn: Button = node_buttons.get(id)
			if btn:
				var pulse = 0.85 + sin(_pulse_time * 3.0) * 0.15
				btn.modulate = Color(pulse + 0.15, pulse + 0.15, pulse + 0.15)


func _input(event: InputEvent) -> void:
	# A click hurries a flourish to its end state, unless it is the pledge's reveal showing for the
	# first time, which plays out. The press is used up here either way, so it cannot also land on
	# a node. Clicks inside the grace are dropped, as they always were during a flourish.
	if _flourish == null or not (event is InputEventMouseButton and event.pressed):
		return
	# The flourish moves the view itself, so the wheel waits until it is done.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if _flourish.can_hurry():
			_flourish.finish_now()


func _unhandled_input(event: InputEvent) -> void:
	# Dev-only: press R to replay the pledge-change flourish on the current map (feel-tuning
	# without relaunching). Debug builds only; never fires in a shipped build.
	if not OS.is_debug_build() or _flourish != null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if RunManager.current_map and not RunManager.current_map.pledge_changes.is_empty():
			_prime_pledge_changes()


# ============================================================
# UI CONSTRUCTION
# ============================================================

func _build_ui() -> void:
	# Pull realm theming if available; fall back to neutral palette if not.
	# Accent is act-aware so the realm sky shifts as the run progresses (Act 1
	# warm dusk → Act 2 deeper night → Act 3 corrupted/dramatic).
	var realm: RealmData = RunManager.get_current_realm()
	var accent: Color = Color(0.55, 0.5, 0.4)
	var visual_style: int = RealmData.VisualStyle.NEUTRAL
	var realm_name: String = ""
	var realm_tagline: String = ""
	if realm:
		accent = realm.get_accent_for_act(RunManager.current_act)
		visual_style = realm.visual_style
		realm_name = realm.display_name
		realm_tagline = realm.theme_description

	# Base background: neutral dark mixed lightly with the realm accent.
	# Subtle enough that gameplay nodes stay readable, distinct enough that
	# you know which realm you're in at a glance.
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.06, 0.15).lerp(accent, 0.14).darkened(0.45)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Realm motif overlay: drawn by a shader so it scales cleanly and needs
	# no image assets. Patterns differ per visual style.
	_add_realm_motif(visual_style, accent)
	# Camelot leans into a dawn/dusk mood: a warm glow rising behind the skyline.
	if visual_style == RealmData.VisualStyle.HERALDIC:
		_add_dawn_glow(accent)

	# Horizon silhouette: wide painted-in-Cairo strip anchored to the bottom
	# of the screen. Gives the map real depth (castle skyline / mountain peaks
	# receding into haze) instead of just flat tinted color.
	# The horizon spans 500px from the bottom, so the silhouette occupies the
	# lower third of the viewport, enough to read as a landscape, low enough
	# that the map nodes mostly sit ABOVE it rather than overlapping.
	# Stretches to viewport width to avoid black bars.
	if realm and realm.horizon_path != "" and ResourceLoader.exists(realm.horizon_path):
		var horizon_tex: Texture2D = load(realm.horizon_path)
		if horizon_tex:
			var horizon = TextureRect.new()
			horizon.texture = horizon_tex
			horizon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			horizon.stretch_mode = TextureRect.STRETCH_SCALE
			horizon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			horizon.offset_top = -500
			horizon.offset_left = 0
			horizon.offset_right = 0
			horizon.offset_bottom = -50  # leave the bottom bar visible above the silhouette's foreground
			horizon.modulate = Color(1.0, 1.0, 1.0, 1.0)
			horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(horizon)

	# Sky body: moon, aurora, etc. Painted in the upper portion of the
	# screen, behind everything else atmospheric. Sits between the motif and
	# the drift particles for layered depth.
	if realm:
		_add_sky_body(realm.sky_body, accent)

	# Particle drift: ambient motion for the realm (dust, snow, mist, etc.).
	# Primary layer, then optional secondary (e.g., lanterns pairing with mist).
	# Sits above the horizon but below the map nodes, low opacity so it
	# doesn't compete for attention.
	if realm:
		_add_drift_particles(realm.drift_kind, accent)
		if realm.secondary_drift_kind != RealmData.DriftKind.NONE:
			_add_drift_particles(realm.secondary_drift_kind, accent)

	# Vignette: tinted with a darker version of the realm accent so the edges
	# read as "of this place" rather than generic black.
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.4;
	float vig = smoothstep(0.3, 1.0, dist);
	COLOR = vec4(tint.rgb, vig * 0.6);
}
"""
	mat.shader = shader
	vignette.material = mat
	var vignette_tint := accent.darkened(0.85)
	mat.set_shader_parameter("tint", Vector4(vignette_tint.r, vignette_tint.g, vignette_tint.b, 1.0))
	add_child(vignette)

	# Bottom bar: anchored to the bottom of the screen. Built first so we know
	# how much vertical space to reserve for the scroll area above it.
	const BOTTOM_BAR_HEIGHT := 50
	_build_bottom_bar_anchored(BOTTOM_BAR_HEIGHT)

	# Map scroll area: anchored to fill the whole screen except the bottom bar.
	# The header floats on TOP of this with a fade-out gradient so map nodes
	# can scroll all the way to the top of the screen, passing under the header
	# rather than being cut off by it.
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_container.offset_bottom = -BOTTOM_BAR_HEIGHT
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_container)

	var map = RunManager.current_map
	var graph_w = MAP_MARGIN_X * 2 + (MapGenerator.MAP_WIDTH - 1) * NODE_SPACING_X + NODE_SIZE
	var canvas_h = MAP_MARGIN_TOP + MAP_MARGIN_Y + (map.floor_count - 1) * NODE_SPACING_Y + NODE_SIZE
	# Centre the graph in the viewport instead of hugging the left: the stretch mode
	# keeps a fixed base-width coordinate space, so shift every node right by half the
	# slack. Fills the previously-empty right side and puts the boss on screen centre.
	var viewport_w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1920)
	_map_x_offset = maxf(0.0, (viewport_w - graph_w) / 2.0)
	# The canvas hangs from a plain holder, not from the scroll: a container re-fits its child on
	# every sort and resets its scale, so only this way can a flourish push in on the canvas.
	var canvas_size := Vector2(maxf(graph_w, viewport_w), canvas_h)
	var canvas_holder := Control.new()
	canvas_holder.custom_minimum_size = canvas_size
	scroll_container.add_child(canvas_holder)
	map_canvas = Control.new()
	map_canvas.size = canvas_size
	canvas_holder.add_child(map_canvas)

	# Floating header overlay: sits above the scroll area at the top of the
	# screen with a vertical fade-out gradient. Text is solid at the top, the
	# bottom edge of the header fades into transparency so map nodes scrolling
	# behind it remain partially visible. Mouse input passes through so the
	# player can still click nodes that pass behind the header.
	var sigil_path: String = realm.sigil_path if realm else ""
	_build_floating_header(realm_name, realm_tagline, accent, sigil_path)
	_build_legend_key()


## Anchored variant: attaches the bottom bar to the bottom edge of the screen
## directly rather than to a parent VBox. Used by the new floating-header layout.
func _build_bottom_bar_anchored(height: int) -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -height
	add_child(panel)
	_populate_bottom_bar(panel)


## Legacy entry point: kept for any callers that still hand in a VBox parent.
func _build_bottom_bar(parent: VBoxContainer) -> void:
	var panel = PanelContainer.new()
	parent.add_child(panel)
	_populate_bottom_bar(panel)


## Builds the bottom bar's contents into the given PanelContainer.
func _populate_bottom_bar(panel: PanelContainer) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 0.9)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var bar = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 30)
	panel.add_child(bar)

	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 22)
	hp_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	bar.add_child(hp_label)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 22)
	gold_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	bar.add_child(gold_label)

	passion_label = Label.new()
	passion_label.add_theme_font_size_override("font_size", 22)
	passion_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	bar.add_child(passion_label)

	relic_btn = Button.new()
	relic_btn.flat = true
	relic_btn.add_theme_font_size_override("font_size", 20)
	relic_btn.add_theme_color_override("font_color", Color(0.7, 0.6, 0.8))
	relic_btn.add_theme_color_override("font_hover_color", Color(0.85, 0.75, 0.95))
	relic_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	relic_btn.pressed.connect(_on_relics_clicked)
	bar.add_child(relic_btn)

	deck_btn = Button.new()
	deck_btn.flat = true
	deck_btn.add_theme_font_size_override("font_size", 20)
	deck_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	deck_btn.add_theme_color_override("font_hover_color", Color(0.65, 0.85, 1.0))
	deck_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	deck_btn.pressed.connect(_on_deck_clicked)
	bar.add_child(deck_btn)

	titles_btn = Button.new()
	titles_btn.flat = true
	titles_btn.add_theme_font_size_override("font_size", 20)
	titles_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.45))
	titles_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.6))
	titles_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	titles_btn.pressed.connect(_on_titles_clicked)
	bar.add_child(titles_btn)

	# The pack. Heals and standing items are usable here; combat-only items wait, visibly.
	consumable_bar = ConsumableBar.new()
	consumable_bar.setup(ConsumableBar.Mode.MAP)
	consumable_bar.item_used.connect(func(_item): _update_bottom_bar())
	bar.add_child(consumable_bar)

	# What a pack item does, in the page's panel. Only over the pack itself, so a view opened over
	# the map never shows one through it.
	var note := HoverNote.new()
	note.blocked = func() -> bool:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or consumable_bar.is_menu_open():
			return true
		# Over the pack, or over a relic in the relics view.
		var over_pack := hovered == consumable_bar or consumable_bar.is_ancestor_of(hovered)
		var over_relic: bool = is_instance_valid(popup_overlay) and popup_overlay.is_ancestor_of(hovered)
		return not (over_pack or over_relic)
	add_child(note)

	# The companion, if one travels with the player. Hidden until an event grants one.
	pet_label = Label.new()
	pet_label.add_theme_font_size_override("font_size", 18)
	pet_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.55))
	pet_label.mouse_filter = Control.MOUSE_FILTER_STOP
	pet_label.visible = false
	bar.add_child(pet_label)

	# Excalibur mode toggle: only shown when the player holds Excalibur.
	# Gold styling matches the Sword in the Stone node color so it reads as
	# "this is the Camelot quest reward you're managing."
	excalibur_btn = Button.new()
	excalibur_btn.flat = true
	excalibur_btn.add_theme_font_size_override("font_size", 20)
	excalibur_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	excalibur_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.55))
	excalibur_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	excalibur_btn.pressed.connect(_on_excalibur_toggle_clicked)
	excalibur_btn.visible = false
	bar.add_child(excalibur_btn)

	# The Thurible mode toggle, only shown when the player holds The Thurible (the Reliquary
	# censer). Smoky-violet styling (incense, not Excalibur's quest-gold) so the two per-fight
	# toggles read as distinct things to manage between fights.
	thurible_btn = Button.new()
	thurible_btn.flat = true
	thurible_btn.add_theme_font_size_override("font_size", 20)
	thurible_btn.add_theme_color_override("font_color", Color(0.74, 0.62, 0.92))
	thurible_btn.add_theme_color_override("font_hover_color", Color(0.86, 0.78, 1.0))
	thurible_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	thurible_btn.pressed.connect(_on_thurible_toggle_clicked)
	thurible_btn.visible = false
	bar.add_child(thurible_btn)

	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size", 18)
	timer_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	bar.add_child(timer_label)

	seed_label = Label.new()
	seed_label.add_theme_font_size_override("font_size", 14)
	seed_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	bar.add_child(seed_label)


func _update_bottom_bar() -> void:
	hp_label.text = "HP: %d / %d" % [RunManager.current_hp, RunManager.max_hp]
	gold_label.text = "Gold: %d" % RunManager.gold
	if RunManager.passion:
		var tier = RunManager.get_passion_tier()
		passion_label.text = "Passion: %d (%s)" % [
			RunManager.passion.current_value, PassionState.tier_name(tier)]

	relic_btn.text = "Relics: %d" % RunManager.relics.size()
	deck_btn.text = "Deck: %d" % RunManager.current_deck.size()
	# Filled/total title SLOTS (not equipped/earned, which read like a progress bar).
	# The click-through popup shows the full earned list + which are equipped.
	titles_btn.text = "Titles: %d/%d slots" % [
		_count_equipped_titles(), RunManager.active_title_slots.size()]

	var companion := RunManager.get_pet()
	if companion:
		pet_label.visible = true
		pet_label.text = "Companion: %s" % companion.display_name
		pet_label.tooltip_text = companion.description
	else:
		pet_label.visible = false

	if RunManager.has_excalibur():
		excalibur_btn.visible = true
		var mode_label := "⚔ Sword" if RunManager.excalibur_mode == RunManager.ExcaliburMode.SWORD else "◉ Sight"
		excalibur_btn.text = "Excalibur: %s" % mode_label
		excalibur_btn.tooltip_text = ("Click to toggle. Sword adds a power card to each combat;"
			+ " Sight reveals enemy intent one turn ahead.")
	else:
		excalibur_btn.visible = false

	if RunManager.has_thurible():
		thurible_btn.visible = true
		var pole := "▲ Blazing" if RunManager.thurible_mode == RunManager.ThuribleMode.BLAZING else "▼ Hollow"
		thurible_btn.text = "Thurible: %s" % pole
		thurible_btn.tooltip_text = ("Click to toggle. Each turn the censer swings your Passion"
			+ " +3 toward Blazing or -3 toward Hollow. Switch sides between fights.")
	else:
		thurible_btn.visible = false

	timer_label.text = RunManager.get_run_time_string()
	seed_label.text = "Seed: %d" % RngManager.run_seed


func _on_excalibur_toggle_clicked() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.toggle_excalibur_mode()
	_update_bottom_bar()


func _on_thurible_toggle_clicked() -> void:
	AudioManager.play_sfx("button_click")
	RunManager.toggle_thurible_mode()
	_update_bottom_bar()


# ============================================================
# RELIC & DECK POPUPS
# ============================================================

func _on_relics_clicked() -> void:
	if popup_overlay:
		popup_overlay.queue_free()
		popup_overlay = null
		return
	_show_relic_popup()


func _on_deck_clicked() -> void:
	if popup_overlay:
		popup_overlay.queue_free()
		popup_overlay = null
		return
	_show_deck_popup()


func _on_titles_clicked() -> void:
	if popup_overlay:
		popup_overlay.queue_free()
		popup_overlay = null
		return
	_show_titles_popup()


## Counts how many of the two title slots have a title equipped (0-2).
func _count_equipped_titles() -> int:
	var n := 0
	for slot_id in RunManager.active_title_slots:
		if slot_id != &"":
			n += 1
	return n


## Build the titles popup: a header summarizing slots + per-slot card showing
## the equipped title (or "empty slot" placeholder) with its current tier and effect.
func _show_titles_popup() -> void:
	var earned_count: int = RunManager.earned_title_ids.size()
	popup_overlay = _create_popup_panel("Titles (%d/%d slots filled, %d earned)" % [
		_count_equipped_titles(), RunManager.TITLE_SLOT_COUNT, earned_count])
	var content: VBoxContainer = popup_overlay.get_meta("content")

	if earned_count == 0:
		var empty = Label.new()
		empty.text = "No titles yet. Major decisions in each realm grant titles\nthat shape your reputation and identity."
		empty.add_theme_font_size_override("font_size", 16)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(empty)
		add_child(popup_overlay)
		return

	# Active slots row
	var slots_label = Label.new()
	slots_label.text = "─── Equipped ───"
	slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slots_label.add_theme_font_size_override("font_size", 14)
	slots_label.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
	content.add_child(slots_label)

	var slot_row = HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 16)
	content.add_child(slot_row)

	for slot in range(RunManager.TITLE_SLOT_COUNT):
		slot_row.add_child(_build_title_card_for_slot(slot))

	# Earned-but-unequipped section
	var unequipped: Array = []
	for id in RunManager.earned_title_ids:
		if not (id in RunManager.active_title_slots):
			unequipped.append(id)
	if unequipped.size() > 0:
		var divider = Label.new()
		divider.text = "─── Earned (not equipped) ───"
		divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		divider.add_theme_font_size_override("font_size", 14)
		divider.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
		content.add_child(divider)

		var bench_row = HBoxContainer.new()
		bench_row.alignment = BoxContainer.ALIGNMENT_CENTER
		bench_row.add_theme_constant_override("separation", 12)
		content.add_child(bench_row)

		for id in unequipped:
			bench_row.add_child(_build_title_card_for_id(id, false))

	add_child(popup_overlay)


## Build a slot display card. Empty slots show a placeholder; filled slots show
## the equipped title's current tier, description, and an unequip hint.
func _build_title_card_for_slot(slot: int) -> PanelContainer:
	var id: StringName = RunManager.active_title_slots[slot]
	if id == &"":
		return _build_empty_slot_card(slot)
	return _build_title_card_for_id(id, true)


func _build_empty_slot_card(slot: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 130)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.09, 0.14)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = Color(0.25, 0.22, 0.3)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var slot_label = Label.new()
	slot_label.text = "Slot %d" % (slot + 1)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 14)
	slot_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	vbox.add_child(slot_label)

	var empty = Label.new()
	empty.text = "(empty)"
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_theme_font_size_override("font_size", 18)
	empty.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	vbox.add_child(empty)

	return panel


## Build a card showing a title's current tier name, description, and effect value.
## When `equipped` is true, uses the equipped styling (brighter border, full opacity).
func _build_title_card_for_id(id: StringName, equipped: bool) -> PanelContainer:
	var data: TitleData = TitlePool.get_title(id)
	var tier: TitleData.Tier = RunManager.get_title_tier(id)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(240, 130)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.1, 0.18, 1.0 if equipped else 0.7)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2 if equipped else 1)
	style.border_color = data.accent_color if equipped else data.accent_color.darkened(0.4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Name (uses tier-appropriate name)
	var name_lbl = Label.new()
	name_lbl.text = data.get_name_for_tier(tier)
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", data.accent_color if equipped else data.accent_color.darkened(0.3))
	vbox.add_child(name_lbl)

	# Tier label (only show for realm titles where tier matters)
	if data.is_realm_title():
		var tier_str := ""
		match tier:
			TitleData.Tier.ORIGINAL:
				tier_str = "● ORIGINAL"
			TitleData.Tier.DEGRADED:
				tier_str = "○ DEGRADED"
			TitleData.Tier.RETURNING:
				tier_str = "◐ RETURNING"
		var tier_lbl = Label.new()
		tier_lbl.text = tier_str
		tier_lbl.add_theme_font_size_override("font_size", 11)
		tier_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
		vbox.add_child(tier_lbl)

	# Description (tier-appropriate)
	var desc_lbl = Label.new()
	desc_lbl.text = data.get_description_for_tier(tier)
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68) if equipped else Color(0.5, 0.48, 0.45))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	return panel


func _show_relic_popup() -> void:
	popup_overlay = _create_popup_panel("Relics (%d)" % RunManager.relics.size())
	var content: VBoxContainer = popup_overlay.get_meta("content")

	if RunManager.relics.size() == 0:
		var empty = Label.new()
		empty.text = "No relics yet"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		content.add_child(empty)
	else:
		var flow = HBoxContainer.new()
		flow.add_theme_constant_override("separation", 12)
		content.add_child(flow)
		var col_count := 0
		var current_row: HBoxContainer = flow

		for relic in RunManager.relics:
			if col_count >= 3:
				current_row = HBoxContainer.new()
				current_row.add_theme_constant_override("separation", 12)
				content.add_child(current_row)
				col_count = 0

			var rarity_colors = {
				RelicData.RelicRarity.COMMON: Color(0.6, 0.6, 0.6),
				RelicData.RelicRarity.UNCOMMON: Color(0.3, 0.7, 0.9),
				RelicData.RelicRarity.RARE: Color(0.95, 0.8, 0.2),
				RelicData.RelicRarity.BOSS: Color(0.9, 0.3, 0.3),
			}
			var color = rarity_colors.get(relic.rarity, Color(0.6, 0.6, 0.6))

			var relic_panel = PanelContainer.new()
			relic_panel.custom_minimum_size = Vector2(200, 80)
			var rs = StyleBoxFlat.new()
			rs.bg_color = Color(0.14, 0.11, 0.2)
			rs.set_corner_radius_all(6)
			rs.set_border_width_all(2)
			rs.border_color = color
			rs.content_margin_left = 10
			rs.content_margin_right = 10
			rs.content_margin_top = 8
			rs.content_margin_bottom = 8
			relic_panel.add_theme_stylebox_override("panel", rs)

			var rvbox = VBoxContainer.new()
			relic_panel.add_child(rvbox)
			var rname = Label.new()
			rname.text = relic.relic_name
			rname.add_theme_font_size_override("font_size", 16)
			rname.add_theme_color_override("font_color", color)
			rvbox.add_child(rname)
			var rdesc = Label.new()
			rdesc.text = relic.description
			rdesc.add_theme_font_size_override("font_size", 13)
			rdesc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			rdesc.autowrap_mode = TextServer.AUTOWRAP_WORD
			rvbox.add_child(rdesc)

			RelicKeywords.mark(relic_panel, relic)
			current_row.add_child(relic_panel)
			col_count += 1

	add_child(popup_overlay)


func _show_deck_popup() -> void:
	popup_overlay = _create_popup_panel("Deck (%d cards)" % RunManager.current_deck.size())
	var content: VBoxContainer = popup_overlay.get_meta("content")

	# Deck stats by card type
	var type_counts := {CardData.CardType.ATTACK: 0, CardData.CardType.SKILL: 0, CardData.CardType.POWER: 0}
	for card in RunManager.current_deck:
		type_counts[card.card_type] = type_counts.get(card.card_type, 0) + 1
	var stats_lbl = Label.new()
	stats_lbl.text = "%d Attack / %d Skill / %d Power" % [
		type_counts[CardData.CardType.ATTACK],
		type_counts[CardData.CardType.SKILL],
		type_counts[CardData.CardType.POWER]]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.add_theme_font_size_override("font_size", 16)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content.add_child(stats_lbl)

	# Passion zones: see which of these cards your current Passion is buffing.
	var passion_btn = Button.new()
	passion_btn.text = "⚡ Passion Zones"
	passion_btn.custom_minimum_size = Vector2(220, 40)
	passion_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	passion_btn.add_theme_font_size_override("font_size", 16)
	passion_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	passion_btn.pressed.connect(func(): PassionInfographic.open_modal(self))
	content.add_child(passion_btn)

	# Sort cards by type then name
	var sorted_deck = RunManager.current_deck.duplicate()
	sorted_deck.sort_custom(func(a, b):
		if a.card_type != b.card_type:
			return a.card_type < b.card_type
		return a.card_name < b.card_name
	)

	var grid = GridContainer.new()
	grid.columns = DECK_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	for card in sorted_deck:
		# The face is drawn at its own size and scaled, in a holder that has the room it will fill
		# (a container ignores a child's scale).
		var holder := Control.new()
		holder.custom_minimum_size = CardFace.SIZE * DECK_FACE_SCALE
		var face := CardFace.build(card, null, CardSigil.build(card))
		face.pivot_offset = Vector2.ZERO
		face.scale = Vector2(DECK_FACE_SCALE, DECK_FACE_SCALE)
		face.position = Vector2.ZERO
		_ignore_mouse_recursive(face)
		holder.add_child(face)

		# Click a card to blow it up to full size with an upgrade toggle.
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		holder.gui_input.connect(_on_deck_card_clicked.bind(card))

		grid.add_child(holder)

	add_child(popup_overlay)


func _ignore_mouse_recursive(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_ignore_mouse_recursive(child)


func _on_deck_card_clicked(event: InputEvent, card: CardData) -> void:
	if not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_show_card_detail(card)


## Blows a deck card up to a readable full-size render on a dim backdrop. For an
## un-upgraded card a toggle previews what upgrading would do (green-tinted);
## an already-upgraded card shows as upgraded with a badge. Rebuilds itself on
## toggle (show_upgrade), which is simplest and cheap for a single card.
func _show_card_detail(card: CardData, show_upgrade: bool = false) -> void:
	if card_detail_overlay:
		card_detail_overlay.queue_free()
		card_detail_overlay = null

	var overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	card_detail_overlay = overlay

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_card_detail())
	overlay.add_child(dim)

	# CenterContainer is transparent to picking so clicks off the card hit the dim;
	# its interactive children (toggle / close) still receive input.
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var is_upgraded := card.upgraded
	var display_card := card
	if not is_upgraded and show_upgrade:
		display_card = card.duplicate_card()
		display_card.upgrade_card()

	vbox.add_child(_render_full_card(display_card))

	# State caption under the card.
	var state = Label.new()
	if is_upgraded:
		state.text = "✦ Upgraded"
		state.add_theme_color_override("font_color", Color(0.4, 0.9, 0.45))
	elif show_upgrade:
		state.text = "Upgrade preview"
		state.add_theme_color_override("font_color", Color(0.4, 0.9, 0.45))
	else:
		state.text = "Current"
		state.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 16)
	vbox.add_child(state)

	# Only un-upgraded cards have a meaningful "other" side to compare against.
	if not is_upgraded:
		var toggle = Button.new()
		toggle.text = "◂ Show Current" if show_upgrade else "Preview Upgrade ▸"
		toggle.custom_minimum_size = Vector2(220, 42)
		toggle.add_theme_font_size_override("font_size", 16)
		toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggle.pressed.connect(func(): _show_card_detail(card, not show_upgrade))
		vbox.add_child(toggle)

	var close = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 40)
	close.add_theme_font_size_override("font_size", 16)
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(_close_card_detail)
	vbox.add_child(close)


func _close_card_detail() -> void:
	if card_detail_overlay:
		card_detail_overlay.queue_free()
		card_detail_overlay = null


## The deck detail view's card: the face enlarged, with the inspect notes beside it (rarity, flavor
## and a reminder for each keyword), the way a right-click shows it elsewhere. An upgraded or
## upgrade-previewed card carries its green edge from the face itself.
func _render_full_card(card: CardData) -> Control:
	var card_size: Vector2 = CardFace.SIZE * CardInspect.SCALE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(CardInspect.GAP))
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var holder := Control.new()
	holder.custom_minimum_size = card_size
	var face := CardFace.build(card, null, CardSigil.build(card))
	face.pivot_offset = Vector2.ZERO
	face.scale = Vector2(CardInspect.SCALE, CardInspect.SCALE)
	face.position = Vector2.ZERO
	holder.add_child(face)
	row.add_child(holder)

	# The notes hang from the card's top edge, in a column the card's height.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(CardInspect.NOTES_W, card_size.y)
	side.add_child(CardInspect.notes(card))
	row.add_child(side)
	return row


func _create_popup_panel(title: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.14, 0.96)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 30
	style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func():
		if popup_overlay:
			popup_overlay.queue_free()
			popup_overlay = null)
	header.add_child(close_btn)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	scroll.add_child(content)

	panel.set_meta("content", content)
	return panel


# ============================================================
# MAP DISPLAY
# ============================================================

func _get_node_center(node: MapNode) -> Vector2:
	# Floor 0 at bottom, boss at top. x_jitter/y_jitter are cosmetic sub-cell
	# offsets from the generator so the graph reads as organic, not a lattice.
	var map = RunManager.current_map
	var x = _map_x_offset + MAP_MARGIN_X + (node.column + node.x_jitter) * NODE_SPACING_X + NODE_SIZE / 2.0
	var y = MAP_MARGIN_TOP + (map.floor_count - 1 - node.floor_num + node.y_jitter) * NODE_SPACING_Y + NODE_SIZE / 2.0
	return Vector2(x, y)


func _create_map_display() -> void:
	var map = RunManager.current_map

	# Draw connection lines first (behind nodes)
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		var from_pos = _get_node_center(node)
		for next_id in node.next_nodes:
			var next_node = map.get_node(next_id)
			if next_node:
				var to_pos = _get_node_center(next_node)
				var line = Line2D.new()
				line.add_point(from_pos)
				line.add_point(to_pos)
				line.width = 2.0
				line.default_color = Color(0.35, 0.3, 0.55, 0.7)
				map_canvas.add_child(line)

	# Create node buttons
	for id in map.nodes:
		var node: MapNode = map.nodes[id]
		var btn = _create_node_button(node)
		var center = _get_node_center(node)
		btn.position = center - Vector2(NODE_SIZE / 2.0, NODE_SIZE / 2.0)
		map_canvas.add_child(btn)
		node_buttons[id] = btn


## What the map says of each seated record site (MapGenerator.RECORD_SITE_IDS).
const RECORD_SITE_TOOLTIPS := {
	&"scriptorium": "The Scriptorium: an abbey's records, and Bram at the long table",
	&"tourney": "The Tourney: the lists, and the herald's roll of arms",
	&"reliquary": "The Reliquary: a wayside chapel that keeps memory",
}


func _create_node_button(node: MapNode) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.size = Vector2(NODE_SIZE, NODE_SIZE)
	# An armed payoff shows the quest glyph (the arm-reveal flourish briefly resets it to its
	# pre-arm look, then swaps the glyph back in). Before the plea is accepted it's ordinary.
	_paint_node(btn, node.look(_is_quest_payoff_armed(node)))

	# Tooltip descriptions by node type
	var tooltip_map = {
		MapNode.NodeType.COMBAT: "Battle enemies for card rewards and gold",
		MapNode.NodeType.ELITE: "Tough enemy: higher rewards + relic",
		MapNode.NodeType.REST: "Rest to heal or upgrade a card",
		MapNode.NodeType.SHOP: "Spend gold on cards, relics, and card removal",
		MapNode.NodeType.EVENT: "A narrative encounter with choices",
		MapNode.NodeType.MYSTERY: "Unknown: could be anything",
		MapNode.NodeType.BOSS: "Defeat the act boss to advance",
		MapNode.NodeType.SWORD_IN_STONE: "An ancient blade waits in stone…",
	}
	btn.tooltip_text = tooltip_map.get(node.node_type, "")
	if node.node_type == MapNode.NodeType.ELITE and node.weakened:
		btn.tooltip_text = "Weakened elite: the people sabotaged it. Easier fight, same rewards."
	if _is_quest_payoff_armed(node):
		btn.tooltip_text = _quest_payoff_tooltip(node.quest_payoff_id)
	# The Master of Game is meant to be found: the tooltip says what is sold there, so a run that
	# wants a companion can route to it.
	if node.scripted_event_id == MapGenerator.MASTER_OF_GAME_ID:
		btn.tooltip_text = "The Master of Game: a huntsman selling his lord's animals. A companion, 75 gold."
	# The record site seated late in the act: a place that keeps records, where a forgotten relic
	# can be given its name back. Named, so a keeper carrying one can route to it.
	elif node.scripted_event_id in MapGenerator.RECORD_SITE_IDS:
		btn.tooltip_text = RECORD_SITE_TOOLTIPS.get(node.scripted_event_id, "A place that keeps records")
	# A crossing has no name, so it has nothing to say either.
	if node.crossing_to != &"":
		btn.tooltip_text = ""

	btn.pressed.connect(_on_node_clicked.bind(node))
	btn.mouse_entered.connect(_on_node_hover.bind(node))
	btn.mouse_exited.connect(_on_node_unhover)

	return btn


## Dresses a node button in a look from MapNode: glyph, styleboxes, and its entry in the legend.
## Separate from the node so the pledge and quest flourishes can show a node's pre-change look,
## then swap to its real one.
func _paint_node(btn: Button, look: Dictionary) -> void:
	btn.set_meta("look", look)
	btn.text = look["glyph"]
	btn.add_theme_font_size_override("font_size", look.get("font", 20))

	var base_col: Color = look["color"]
	# The glyph near white with a hint of its kind's colour, edged dark so it reads against the
	# circle's colour and the dimming of a node out of reach. A look marked `bold` is edged in its own
	# ink instead, which thickens a mark DejaVu Sans draws in fine lines (the swords, the steam).
	var ink := Color.WHITE.lerp(base_col, 0.2)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ink)
	btn.add_theme_color_override("font_outline_color", ink if look.get("bold", false) else base_col.darkened(0.8))
	btn.add_theme_constant_override("outline_size", 2)

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(NODE_SIZE / 2)
	style.set_border_width_all(3)
	style.bg_color = base_col.darkened(0.5)
	style.border_color = base_col

	var hover_style := style.duplicate()
	hover_style.bg_color = base_col.darkened(0.3)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = base_col.darkened(0.6)

	var loud: Array = look.get("loud", [])
	if not loud.is_empty():
		style.bg_color = base_col.darkened(loud[0])
		style.set_border_width_all(5)
		style.border_color = base_col.lightened(loud[1])
		hover_style.bg_color = base_col.darkened(loud[2])
		hover_style.set_border_width_all(5)
		hover_style.border_color = base_col.lightened(loud[3])
		pressed_style.set_border_width_all(5)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("disabled", style.duplicate())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	NodeFace.centre(btn)
	_queue_legend_refresh()


# ============================================================
# NODE STATES & INTERACTION
# ============================================================

func _update_node_states() -> void:
	var map = RunManager.current_map
	var available = map.get_available_next_ids()
	_available_nodes = available

	for id in node_buttons:
		var btn: Button = node_buttons[id]
		var node: MapNode = map.get_node(id)

		if id in available:
			btn.modulate = Color.WHITE
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		elif node.visited:
			# Dimmed but mostly opaque so the icon reads against the warm bg (was too
			# transparent and clashed with the background colour).
			btn.modulate = Color(0.55, 0.55, 0.55, 0.92)
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		else:
			# Landmark nodes (boss, the Sword, an armed quest payoff) stay bright even when
			# locked so they survive the map's darkening effects and always read; ordinary
			# future nodes dim to show they're out of reach.
			var far_look: Dictionary = node.look(_is_quest_payoff_armed(node))
			if far_look.get("landmark", false) or far_look.get("lit", false):
				btn.modulate = Color(0.9, 0.9, 0.9, 1.0)
			else:
				btn.modulate = Color(0.42, 0.42, 0.42, 0.85)
			btn.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _on_node_clicked(node: MapNode) -> void:
	if _pledge_anim_active:
		return
	var available = RunManager.current_map.get_available_next_ids()
	if node.id not in available:
		return
	AudioManager.play_sfx("button_click")
	_enter_node(node)


func _on_node_hover(node: MapNode) -> void:
	var floor_str = "Floor %d" % (node.floor_num + 1)
	if node.crossing_to != &"":
		info_label.text = floor_str
		return
	match node.node_type:
		MapNode.NodeType.ELITE:
			info_label.text = "Elite Combat: %s (Relic reward)" % floor_str
		MapNode.NodeType.BOSS:
			info_label.text = "Boss: %s, %s" % [EnemyPool.boss_name(RunManager.current_act), floor_str]
		MapNode.NodeType.REST:
			info_label.text = "Rest Site: %s" % floor_str
		_:
			info_label.text = "%s: %s" % [node.look(_is_quest_payoff_armed(node))["name"], floor_str]


func _on_node_unhover() -> void:
	info_label.text = "Choose your path"


func _enter_node(node: MapNode) -> void:
	RunManager.current_map.move_to(node.id)
	RunManager.run_stats["floors_cleared"] = RunManager.run_stats.get("floors_cleared", 0) + 1
	_update_node_states()

	# A queued "skip the next node" (the Tourney's walk-on shortcut): step onto this node to
	# advance position, but pass over its content and leave its children available. Consumed
	# once, and never on the boss (the act still has to be finished) nor on a far map's way
	# back, which has no children to leave available.
	var way_back := RunManager.is_abroad() and node.crossing_to != &""
	if RunManager.pending_skip_node and node.node_type != MapNode.NodeType.BOSS and not way_back:
		RunManager.pending_skip_node = false
		info_label.text = "You took the shortcut, skipping ahead."
		return

	if node.crossing_to != &"":
		_take_crossing(node, way_back)
		return

	# Armed questline payoff: route to the quest's ambush instead of this node's normal type.
	# (The node looked ordinary until a plea/campfire armed it; now it pays off.)
	if _is_quest_payoff_armed(node) and not RunManager.is_quest_completed(node.quest_payoff_id):
		RunManager.pending_special_event = _quest_ambush_event(node.quest_payoff_id)
		SceneTransition.change_scene("res://scenes/event/event_scene.tscn")
		return

	# On a realm's own map this is the node's floor; on a far map, how deep into the act it counts.
	var act_floor: int = RunManager.current_map.act_floor(node)
	match node.node_type:
		MapNode.NodeType.COMBAT:
			_start_combat(_combat_encounter(act_floor), 16 + act_floor * 2)
		MapNode.NodeType.ELITE:
			_start_combat(_elite_encounter(node.weakened), 34 + act_floor * 2, true, false)
		MapNode.NodeType.BOSS:
			RunManager.pending_act_complete = true
			_start_combat(_boss_encounter(), 50 + act_floor * 2, true, true)
		MapNode.NodeType.REST:
			SceneTransition.change_scene("res://scenes/rest/rest_scene.tscn")
		MapNode.NodeType.MYSTERY:
			_handle_mystery(node)
		MapNode.NodeType.SHOP:
			SceneTransition.change_scene("res://scenes/shop/shop_scene.tscn")
		MapNode.NodeType.EVENT:
			# A quest-giver event node routes to its plea, a scripted node (the Master of Game) to
			# its own event; ordinary event nodes pull from the random pool.
			if node.quest_giver_id != &"":
				RunManager.pending_special_event = &"raider_plea"
			elif node.scripted_event_id != &"":
				RunManager.pending_special_event = node.scripted_event_id
			elif not EventPool.has_events(RunManager.current_realm_id, RunManager.realm_config.route_id):
				# A route with no events yet: the node is a fight instead of an empty scene.
				_start_combat(_combat_encounter(act_floor), 16 + act_floor * 2)
				return
			SceneTransition.change_scene("res://scenes/event/event_scene.tscn")
		MapNode.NodeType.SWORD_IN_STONE:
			# Reuse the event scene with a flag: Excalibur is a one-shot event
			# routed through a special path. event_scene reads the flag and renders
			# the Sword-in-the-Stone content instead of pulling from EventPool.
			RunManager.pending_special_event = &"sword_in_stone"
			SceneTransition.change_scene("res://scenes/event/event_scene.tscn")


## Steps through a crossing, or takes a far map's way back. The map scene reloads onto whichever map
## RunManager now holds, so the far side's skin, nodes and legend come from the same path as home's.
func _take_crossing(node: MapNode, way_back: bool) -> void:
	var crossed := RunManager.return_from_crossing() if way_back else RunManager.cross_to(node.crossing_to)
	if crossed:
		SceneTransition.change_scene("res://scenes/map/map_scene.tscn")


func _start_combat(enemies: Array[EnemyData], gold_reward: int = 0,
		relic_reward: bool = false, is_boss: bool = false) -> void:
	# An empty table has already said so loudly. Opening a fight against nobody would hide that.
	if enemies.is_empty():
		RunManager.pending_act_complete = false
		return
	RunManager.pending_enemies.clear()
	for e in enemies:
		RunManager.pending_enemies.append(e)
	RunManager.pending_gold_reward = gold_reward
	RunManager.pending_relic_reward = relic_reward
	RunManager.pending_relic_is_boss = is_boss
	SceneTransition.change_scene("res://scenes/combat/combat_scene.tscn")


func _handle_mystery(node: MapNode) -> void:
	var roll = RngManager.event_rng.randf()
	if roll < 0.4:
		node.node_type = MapNode.NodeType.COMBAT
	elif roll < 0.6:
		node.node_type = MapNode.NodeType.EVENT
	elif roll < 0.8:
		node.node_type = MapNode.NodeType.REST
	else:
		node.node_type = MapNode.NodeType.SHOP
	_update_node_visual(node)
	_enter_node(node)


func _update_node_visual(node: MapNode) -> void:
	var btn: Button = node_buttons.get(node.id)
	if btn:
		_paint_node(btn, node.look(_is_quest_payoff_armed(node)))


func _scroll_to_player() -> void:
	var map = RunManager.current_map
	var target_floor := 0
	if map.current_node_id >= 0:
		target_floor = map.get_node(map.current_node_id).floor_num

	var target_y = MAP_MARGIN_Y + (map.floor_count - 1 - target_floor) * NODE_SPACING_Y
	var scroll_target = target_y - scroll_container.size.y / 2.0 + NODE_SIZE / 2.0
	scroll_container.scroll_vertical = int(maxf(0, scroll_target))


# ============================================================
# PLEDGE CHANGES (the road rewrites itself: only the nodes the pledge changed)
# ============================================================

## Set each changed node to its PRE-change look synchronously, so there's no first-frame flash of the
## final state, then start the flourish after layout. Each stays visible and bright until the climb
## reaches it, since the change only reads if you saw what was there. Replays on an open map.
## `first_showing` is the reveal on the map's first open: the only time the player sees what their
## pledge did, so no click cuts it short. The debug replay can be hurried.
func _prime_pledge_changes(first_showing := false) -> void:
	_end_flourish()
	var map = RunManager.current_map
	for id in map.pledge_changes:
		var btn: Button = node_buttons.get(id)
		if btn == null:
			continue
		if map.pledge_changes[id] == &"elite_added":
			_paint_node(btn, MapNode.TYPE_LOOKS[MapNode.NodeType.COMBAT])  # was a combat node
		else:  # &"weakened": was a normal (un-weakened) elite
			_paint_node(btn, MapNode.TYPE_LOOKS[MapNode.NodeType.ELITE])
		btn.modulate = Color.WHITE
	_pledge_anim_active = true
	_play_pledge_changes.call_deferred(first_showing)


## The map climbs slowly from where you stand, and each changed node flips as it comes into view.
func _play_pledge_changes(first_showing: bool) -> void:
	await get_tree().process_frame  # the scroll has to have settled for the climb to start from it
	var map = RunManager.current_map
	if map == null or map.pledge_changes.is_empty():
		_finish_pledge_changes()
		return
	var flips: Array = []
	for id in map.pledge_changes:
		var btn: Button = node_buttons.get(id)
		var node: MapNode = map.get_node(id)
		if btn == null or node == null:
			continue
		flips.append({"btn": btn, "at": _get_node_center(node), "swap": _pledge_swap_cb(btn, node)})
	if flips.is_empty():
		_finish_pledge_changes()
		return
	var flourish := _start_flourish()
	flourish.hurriable = not first_showing
	flourish.play_rewrite(flips)


## Where the ink starts: your node, or before you have one, the opening node nearest the action.
func _ink_origin(toward: Vector2) -> Vector2:
	var map = RunManager.current_map
	if map.current_node_id >= 0:
		return _get_node_center(map.get_node(map.current_node_id))
	var best: Vector2 = toward
	var best_dist := INF
	for id in map.starting_node_ids:
		var at := _get_node_center(map.get_node(id))
		var dist := at.distance_squared_to(toward)
		if dist < best_dist:
			best_dist = dist
			best = at
	return best


func _start_flourish() -> MapFlourish:
	_flourish = MapFlourish.new()
	add_child(_flourish)
	_flourish.setup(map_canvas)
	_flourish.finished.connect(_finish_pledge_changes)
	return _flourish


## Ends whichever flourish is playing, at its end state. A no-op with none playing.
func _end_flourish() -> void:
	if _flourish != null:
		_flourish.finish_now()


func _finish_pledge_changes() -> void:
	_flourish = null
	_pledge_anim_active = false
	_update_node_states()  # restore availability dimming on the changed nodes
	_scroll_to_player()    # settle exactly at the start


## Flip-midpoint callback: swap the node into its real, post-change look.
func _pledge_swap_cb(btn: Button, node: MapNode) -> Callable:
	return func() -> void: _paint_node(btn, node.look())


# ============================================================
# QUESTLINE PAYOFF REVEAL (arm flourish, one node, mid-run)
# ============================================================

## True if `node` is the payoff for a questline the player has armed. Drives its glyph,
## landmark brightness, and routing. Independent of completion (a done payoff keeps its mark).
func _is_quest_payoff_armed(node: MapNode) -> bool:
	return node.quest_payoff_id != &"" and RunManager.is_quest_active(node.quest_payoff_id)


## The payoff node for the given questline on the current map, or null (none placed / unknown).
func _quest_payoff_node(quest_id: StringName) -> MapNode:
	var map = RunManager.current_map
	if map == null or quest_id == &"":
		return null
	for id in map.nodes:
		if map.nodes[id].quest_payoff_id == quest_id:
			return map.nodes[id]
	return null


## Set the payoff node to its PRE-arm look synchronously (no first-frame flash of the glyph), latch
## the one-shot flag, then start the flourish after layout. Replays on an open map.
func _prime_quest_reveal(quest_id: StringName) -> void:
	_end_flourish()
	var node := _quest_payoff_node(quest_id)
	if node == null:
		# Abroad, its payoff is on the map at home, so it waits for the way back. Otherwise there is
		# nothing to reveal; don't retry.
		if not RunManager.is_abroad():
			RunManager.mark_quest_revealed(quest_id)
		return
	var btn: Button = node_buttons.get(node.id)
	if btn == null:
		return
	RunManager.mark_quest_revealed(quest_id)
	_paint_node(btn, node.look(false))  # its ordinary pre-arm look
	_pledge_anim_active = true
	_play_quest_reveal.call_deferred(node)


## A gold line inks itself up the road from your node to the payoff as the map climbs with it, the
## glyph stamps at the end of it, and the objective comes up as it lands.
func _play_quest_reveal(node: MapNode) -> void:
	await get_tree().process_frame  # the scroll has to have settled for the climb to start from it
	var btn: Button = node_buttons.get(node.id)
	if btn == null:
		_finish_pledge_changes()
		return
	var map = RunManager.current_map
	var road_ids: Array[int] = map.road_between(map.current_node_id, node.id)
	var road := PackedVector2Array()
	var lit: Array = []
	for id in road_ids:
		road.append(_get_node_center(map.get_node(id)))
		if id != node.id and node_buttons.has(id):
			lit.append(node_buttons[id])
	if road.size() < 2:  # no road reaches it: a straight stroke still says where it is
		road = PackedVector2Array([_ink_origin(_get_node_center(node)), _get_node_center(node)])
	_start_flourish().play_mark(road, lit, btn, _quest_swap_cb(btn, node),
		_show_quest_toast.bind(_quest_reveal_toast(node.quest_payoff_id)))


## Flip-midpoint callback: swap the payoff node into its armed quest-glyph look.
func _quest_swap_cb(btn: Button, node: MapNode) -> Callable:
	return func() -> void: _paint_node(btn, node.look(true))


## The objective toast raised when a questline's payoff reveals, keyed by quest id.
func _quest_reveal_toast(quest_id: StringName) -> String:
	match quest_id:
		&"raiders":
			return "The hunt is marked. The Boar waits on the road past the ford."
		&"campfire":
			return "The dead men's map is marked. A barrow-cache waits down the road."
	return "A mark is set on your road."


## The hover tooltip an armed payoff node carries, keyed by quest id.
func _quest_payoff_tooltip(quest_id: StringName) -> String:
	match quest_id:
		&"raiders":
			return "The hunt leads here. The Boar's band waits on the road past the ford."
		&"campfire":
			return "The map leads here. A barrow-warden keeps the cache the campers left behind."
	return "Something waits here."


## The special-event id a questline's payoff node routes to when entered, keyed by quest id.
func _quest_ambush_event(quest_id: StringName) -> StringName:
	match quest_id:
		&"raiders":
			return &"raider_ambush"
		&"campfire":
			return &"campfire_ambush"
	return &""


## Where a transient toast sits. Objective reveals clear the floating header at the top;
## a title spending itself wants the bottom, clear of the map it has just changed.
enum ToastAnchor { TOP, BOTTOM }

const TOAST_TOP_OFFSET := 174.0     # clear of the floating header
const TOAST_BOTTOM_OFFSET := -132.0  # up off the bottom edge

## A brief centered line that fades in, holds 2.4s, and fades out. Pass dismissible to let
## a click clear it early, which an active title's flavor wants and an objective reveal
## does not. The band is full width but only the text itself takes mouse input, so a
## dismissible toast cannot swallow clicks meant for the map underneath it.
##
## The status line is deliberately not used for this surface: info_label is overwritten by
## the next hover or node-state refresh, which is why "You took the shortcut, skipping
## ahead." does not survive long enough to be read. Transient flavor wants the toast.
func _show_map_toast(text: String, anchor := ToastAnchor.TOP, dismissible := false) -> Label:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	if anchor == ToastAnchor.BOTTOM:
		holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		holder.offset_top = TOAST_BOTTOM_OFFSET
	else:
		holder.offset_top = TOAST_TOP_OFFSET
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	add_child(holder)

	var toast = Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", MapNode.QUEST_MARK_LOOK["color"])
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast.add_theme_constant_override("outline_size", 5)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(toast)

	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", 1.0, 0.45)
	tw.tween_interval(2.4)
	tw.tween_property(holder, "modulate:a", 0.0, 0.7)
	tw.tween_callback(holder.queue_free)

	if dismissible:
		# Only the text takes the click, so the rest of the band stays transparent to the map.
		toast.mouse_filter = Control.MOUSE_FILTER_STOP
		toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toast.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton and event.pressed):
				return
			if tw.is_valid():
				tw.kill()
			holder.queue_free()
		)
	return toast


## A quest's objective, large enough to read on a phone. The words are the toast's own: only the line
## break is new, a sentence to a line.
func _show_quest_toast(text: String) -> void:
	var toast := _show_map_toast(text.replace(". ", ".\n"))
	toast.add_theme_font_override("font", load(CardFace.RULES_FONT_PATH))
	toast.add_theme_font_size_override("font_size", QUEST_TOAST_SIZE)
	toast.add_theme_constant_override("outline_size", QUEST_TOAST_OUTLINE)
	toast.get_parent().z_index = MapFlourish.ABOVE_Z


# ============================================================
# ENCOUNTER GENERATION
# ============================================================

func _combat_encounter(floor_num: int) -> Array[EnemyData]:
	# Camelot's regular roster + encounter pairings live in EnemyPool; the realm-config
	# difficulty knob (set by the realm-entry VN: court vs common folk) scales every
	# encounter this run.
	return EnemyPool.get_combat_encounter(floor_num, RunManager.realm_config.enemy_difficulty_mult)


# Folk's weakened elites keep their rewards but fight at a power nerf (reduced stats via a
# lower difficulty mult) and start Weak: a real, felt debuff behind the "weakened" badge.
const WEAKENED_ELITE_POWER := 0.7
const WEAKENED_ELITE_WEAK := 2

func _elite_encounter(weakened := false) -> Array[EnemyData]:
	var mult := RunManager.realm_config.enemy_difficulty_mult
	if weakened:
		mult *= WEAKENED_ELITE_POWER
	var enc := EnemyPool.get_elite_encounter(mult)
	if weakened:
		for e in enc:
			e.starting_statuses.append([StatusEffects.WEAK, WEAKENED_ELITE_WEAK])
	return enc


func _boss_encounter() -> Array[EnemyData]:
	# The route's table answers for the boss (Act 1 of Camelot is Sir Caedmon) and refuses loudly if
	# it has none. Camelot's Acts 2-3 are out of demo scope and keep their legacy placeholder bosses
	# until those acts get built; no other realm falls through to them.
	if RunManager.current_act <= 1 or RunManager.current_realm_id != &"camelot":
		return EnemyPool.get_boss(RunManager.realm_config.enemy_difficulty_mult)
	var result: Array[EnemyData] = []
	result.append(_make_boss())
	return result


# ============================================================
# ENEMY TEMPLATES
# ============================================================

func _make_boss() -> EnemyData:
	# Placeholder bosses for Acts 2-3 (out of demo scope). Act 1 is Sir Caedmon,
	# built in EnemyPool and routed via _boss_encounter, so this is never called
	# for act <= 1.
	var act = RunManager.current_act
	var e = EnemyData.new()

	if act == 2:
		e.enemy_name = "Hollow Warden"
		e.max_health = 180
		var m1 = EnemyMove.new()
		m1.move_name = "Soul Rend"
		m1.intent_type = EnemyMove.IntentType.ATTACK
		m1.effects.assign([_fx_damage(12)])
		m1.weight = 2.0
		var m2 = EnemyMove.new()
		m2.move_name = "Dark Barrier"
		m2.intent_type = EnemyMove.IntentType.DEFEND
		m2.effects.assign([_fx_block(18), _fx_self_status(StatusEffects.STRENGTH, 2)])
		m2.weight = 1.0
		var m3 = EnemyMove.new()
		m3.move_name = "Annihilate"
		m3.intent_type = EnemyMove.IntentType.ATTACK
		m3.effects.assign([_fx_damage(30)])
		m3.weight = 0.3
		var m4 = EnemyMove.new()
		m4.move_name = "Wither"
		m4.intent_type = EnemyMove.IntentType.DEBUFF
		m4.effects.assign([_fx_status(StatusEffects.WEAK, 2), _fx_status(StatusEffects.POISON, 4)])
		m4.weight = 0.7
		e.moves.assign([m1, m2, m3, m4])
	else:
		e.enemy_name = "Fable's End"
		e.max_health = 250
		var m1 = EnemyMove.new()
		m1.move_name = "Unravel"
		m1.intent_type = EnemyMove.IntentType.ATTACK
		m1.effects.assign([_fx_damage(15)])
		m1.weight = 2.0
		var m2 = EnemyMove.new()
		m2.move_name = "Rewrite"
		m2.intent_type = EnemyMove.IntentType.DEFEND
		m2.effects.assign([_fx_block(25), _fx_self_status(StatusEffects.STRENGTH, 3)])
		m2.weight = 0.8
		var m3 = EnemyMove.new()
		m3.move_name = "Erase"
		m3.intent_type = EnemyMove.IntentType.ATTACK
		m3.effects.assign([_fx_damage(40)])
		m3.weight = 0.25
		var m4 = EnemyMove.new()
		m4.move_name = "Silence"
		m4.intent_type = EnemyMove.IntentType.DEBUFF
		m4.effects.assign([_fx_status(StatusEffects.WEAK, 3), _fx_status(StatusEffects.VULNERABLE, 2)])
		m4.weight = 0.6
		e.moves.assign([m1, m2, m3, m4])

	return e


# -- Effect factory helpers --

func _fx_damage(v: int) -> DamageEffect:
	var e = DamageEffect.new()
	e.value = v
	return e

func _fx_block(v: int) -> BlockEffect:
	var e = BlockEffect.new()
	e.value = v
	return e

func _fx_status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e = StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	return e

func _fx_self_status(effect: StatusEffectData, stacks: int) -> StatusApplyEffect:
	var e = StatusApplyEffect.new()
	e.status_effect = effect
	e.value = stacks
	e.apply_to_source = true
	return e


# ============================================================
# TEST CHARACTER (reused from combat scene)
# ============================================================

func _create_test_character() -> CharacterData:
	# Same character the real game builds, so poking the map scene standalone shows
	# the actual starting deck (single source of truth).
	return CharacterPool.build_emo_hybrid()
