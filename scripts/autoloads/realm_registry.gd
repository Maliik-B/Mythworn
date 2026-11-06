extends Node
## Autoload registry of all realms.
## Owns the canonical RealmData instances and provides lookup by id.

var _realms: Dictionary[StringName, RealmData] = {}


func _ready() -> void:
	_register_realms()


func _register_realms() -> void:
	var camelot := RealmData.new()
	camelot.realm_id = &"camelot"
	camelot.display_name = "Camelot"
	camelot.theme_description = "Nobility, political agency, knightly combat, the weight of rule."
	camelot.core_question = "What kind of ruler are you?"
	camelot.max_act_depth = 3
	camelot.visual_style = RealmData.VisualStyle.HERALDIC
	camelot.accent_color = Color(0.80, 0.60, 0.28)  # Heraldic gold (peaceful base)
	camelot.tags = PackedStringArray(["urban", "courtly", "player-driven", "power"])
	camelot.implemented = true
	camelot.sigil_path = "res://assets/sprites/realms/sigil_camelot.png"
	camelot.horizon_path = "res://assets/sprites/realms/horizon_camelot.png"
	camelot.drift_kind = RealmData.DriftKind.DUST
	camelot.sky_body = RealmData.SkyBody.MOON
	# Warm dusk moon — pale gold with a touch of pink, fitting Camelot's
	# heraldic dusk vibe rather than a cold night-sky moon.
	camelot.sky_body_color = Color(0.96, 0.78, 0.55, 1.0)
	# Per-act mood shift: peaceful noble Camelot slides into strife. Red is earned by
	# Act 3, matching the narrative descent (and how the other realms open peaceful).
	# Accent drives bg tint, vignette, motif, and header color.
	camelot.accent_by_act = [
		Color(0.80, 0.60, 0.28),  # Act 1: warm gold dusk — peaceful, noble Camelot
		Color(0.62, 0.28, 0.18),  # Act 2: amber into crimson — rising strife
		Color(0.70, 0.14, 0.16),  # Act 3: blood-red — corruption/strife earned
	]
	camelot.sky_body_color_by_act = [
		Color(0.96, 0.78, 0.55, 1.0),  # Act 1: warm gold dusk moon
		Color(0.78, 0.74, 0.68, 1.0),  # Act 2: pale silver moon (night)
		Color(0.92, 0.32, 0.28, 1.0),  # Act 3: blood-tinged moon
	]
	_realms[camelot.realm_id] = camelot

	var yggdrasil := RealmData.new()
	yggdrasil.realm_id = &"yggdrasil"
	yggdrasil.display_name = "Yggdrasil"
	yggdrasil.theme_description = "The fallout of divine conflicts. Fate, primal nature, survival."
	yggdrasil.core_question = "Do you accept your fate?"
	yggdrasil.max_act_depth = 3
	yggdrasil.visual_style = RealmData.VisualStyle.RUNIC
	yggdrasil.accent_color = Color(0.42, 0.55, 0.78)  # Cold runic blue
	yggdrasil.tags = PackedStringArray(["wilderness", "primal", "destiny", "creatures"])
	yggdrasil.implemented = false  # Design doc pending
	yggdrasil.sigil_path = "res://assets/sprites/realms/sigil_yggdrasil.png"
	yggdrasil.horizon_path = "res://assets/sprites/realms/horizon_yggdrasil.png"
	yggdrasil.drift_kind = RealmData.DriftKind.SNOW
	yggdrasil.secondary_drift_kind = RealmData.DriftKind.SPIRIT_WISP
	yggdrasil.sky_body = RealmData.SkyBody.AURORA
	# Per-act shift: peaceful aurora → stormy → blood aurora.
	yggdrasil.accent_by_act = [
		Color(0.42, 0.55, 0.78),  # Act 1: cold runic blue
		Color(0.32, 0.42, 0.60),  # Act 2: deeper cobalt
		Color(0.62, 0.30, 0.42),  # Act 3: bruised red-purple (corrupted)
	]
	yggdrasil.aurora_lower_by_act = [
		Color(0.30, 0.85, 0.55, 1.0),  # Act 1: peaceful green
		Color(0.30, 0.78, 0.85, 1.0),  # Act 2: stormy cyan
		Color(0.85, 0.32, 0.32, 1.0),  # Act 3: blood red
	]
	yggdrasil.aurora_upper_by_act = [
		Color(0.45, 0.72, 0.80, 1.0),  # Act 1: pale ice
		Color(0.34, 0.52, 0.72, 1.0),  # Act 2: storm blue
		Color(0.72, 0.30, 0.22, 1.0),  # Act 3: ember
	]
	_realms[yggdrasil.realm_id] = yggdrasil

	var jttw := RealmData.new()
	jttw.realm_id = &"journey_to_the_west"
	jttw.display_name = "Journey to the West"
	jttw.theme_description = "Pilgrimage, spiritual growth, demons that test the wild spirit."
	jttw.core_question = "Can you master yourself?"
	jttw.max_act_depth = 3
	jttw.visual_style = RealmData.VisualStyle.SCROLL
	jttw.accent_color = Color(0.32, 0.62, 0.42)  # Jade green
	jttw.tags = PackedStringArray(["journey", "demons", "transformation", "hierarchy"])
	jttw.implemented = false  # Design doc pending
	jttw.sigil_path = "res://assets/sprites/realms/sigil_journey_to_the_west.png"
	jttw.horizon_path = "res://assets/sprites/realms/horizon_journey_to_the_west.png"
	jttw.drift_kind = RealmData.DriftKind.MIST
	jttw.secondary_drift_kind = RealmData.DriftKind.LANTERN
	jttw.sky_body = RealmData.SkyBody.MOON
	# Per-act shift: moonrise → full moon → blood moon.
	jttw.accent_by_act = [
		Color(0.32, 0.62, 0.42),  # Act 1: peaceful jade
		Color(0.20, 0.45, 0.38),  # Act 2: deeper teal-jade (night settles)
		Color(0.55, 0.30, 0.32),  # Act 3: corrupted red-jade
	]
	jttw.sky_body_color_by_act = [
		Color(0.95, 0.90, 0.78, 1.0),  # Act 1: pale warm moonrise
		Color(0.96, 0.96, 0.92, 1.0),  # Act 2: bright full moon
		Color(0.92, 0.32, 0.28, 1.0),  # Act 3: blood moon
	]
	_realms[jttw.realm_id] = jttw


# --- Public API ---

func get_realm(id: StringName) -> RealmData:
	return _realms.get(id)


func has_realm(id: StringName) -> bool:
	return _realms.has(id)


func get_all_realms() -> Array[RealmData]:
	var result: Array[RealmData] = []
	for realm in _realms.values():
		result.append(realm)
	return result


func get_implemented_realms() -> Array[RealmData]:
	var result: Array[RealmData] = []
	for realm in _realms.values():
		if realm.implemented:
			result.append(realm)
	return result
