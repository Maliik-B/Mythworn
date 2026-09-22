class_name RealmData
extends Resource
## Defines a realm: a mythological/historical world the player visits during a run.
## Realms own their bestiaries, events, bosses, and narrative arc.
## See docs/GAME_DESIGN.md § Realms for the design framework.

enum VisualStyle {
	HERALDIC,   # Camelot: gold/red, knight iconography
	RUNIC,      # Yggdrasil: silver/blue, Norse iconography
	SCROLL,     # Journey to the West: jade/red, Eastern iconography
	NEUTRAL,    # Realm-agnostic / parchment
}

@export var realm_id: StringName = &""
@export var display_name: String = ""
@export_multiline var theme_description: String = ""
@export var core_question: String = ""
@export var max_act_depth: int = 1            # 1, 2, or 3
@export var visual_style: VisualStyle = VisualStyle.NEUTRAL
@export var accent_color: Color = Color(0.85, 0.78, 0.55)  # Default parchment
@export var tags: PackedStringArray = []
@export var implemented: bool = false         # False = stub / not yet content-complete
## Path (res://...) to the realm's sigil/emblem PNG. Empty if not yet authored.
## Map header renders this as a corner badge when present.
@export var sigil_path: String = ""
## Path (res://...) to the realm's horizon-strip PNG (wide silhouette landscape).
## Map renders this as a parallax layer at the bottom of the screen, giving the
## background depth instead of a flat tinted color.
@export var horizon_path: String = ""
## Drift type for ambient particles on the map. Affects color, motion, and shape.
## NONE = no particles. DUST/SNOW/MIST are primary atmospheric drifts.
## LANTERN/SPIRIT_WISP are secondary "warm-light" drifts that pair with a primary.
enum DriftKind { NONE, DUST, SNOW, MIST, LANTERN, SPIRIT_WISP }
@export var drift_kind: DriftKind = DriftKind.NONE
## Optional second drift layer that runs alongside `drift_kind` for visual richness.
## (e.g., JttW pairs MIST + LANTERN, Yggdrasil pairs SNOW + SPIRIT_WISP.)
@export var secondary_drift_kind: DriftKind = DriftKind.NONE
## Sky body rendered in the upper portion of the map for atmospheric depth.
## Examples: moon for night realms, aurora for Norse realms.
enum SkyBody { NONE, MOON, AURORA }
@export var sky_body: SkyBody = SkyBody.NONE
## Color tint for sky bodies that accept one (MOON). Lets us have a warm dusk
## moon for Camelot vs a cool pale moon for JttW. Ignored for AURORA which
## uses its own bicolor scheme.
@export var sky_body_color: Color = Color(0.92, 0.95, 0.88, 1.0)

## Per-act overrides for atmospheric shifts as the run progresses. Each array
## is keyed by act index (0 = Act 1, 1 = Act 2, 2 = Act 3). Empty/short arrays
## fall back to the base color above. Use the get_*_for_act() helpers below.
@export var accent_by_act: Array[Color] = []
@export var sky_body_color_by_act: Array[Color] = []
## Aurora-specific bands. Lower (closer to horizon) and upper (closer to top).
## Used only by realms with sky_body == AURORA.
@export var aurora_lower_by_act: Array[Color] = []
@export var aurora_upper_by_act: Array[Color] = []


## Returns the accent color for the given 1-based act, falling back to the
## base accent if no per-act override is defined.
func get_accent_for_act(act: int) -> Color:
	var idx: int = act - 1
	if idx >= 0 and idx < accent_by_act.size():
		return accent_by_act[idx]
	return accent_color


## Returns the sky body color for the given 1-based act, falling back to the
## base sky_body_color if no per-act override is defined.
func get_sky_body_color_for_act(act: int) -> Color:
	var idx: int = act - 1
	if idx >= 0 and idx < sky_body_color_by_act.size():
		return sky_body_color_by_act[idx]
	return sky_body_color


## Returns the aurora lower band color for the given 1-based act.
## Defaults to peaceful green if no override defined.
func get_aurora_lower_for_act(act: int) -> Color:
	var idx: int = act - 1
	if idx >= 0 and idx < aurora_lower_by_act.size():
		return aurora_lower_by_act[idx]
	return Color(0.30, 0.85, 0.55, 1.0)


## Returns the aurora upper band color for the given 1-based act.
## Defaults to peaceful violet if no override defined.
func get_aurora_upper_for_act(act: int) -> Color:
	var idx: int = act - 1
	if idx >= 0 and idx < aurora_upper_by_act.size():
		return aurora_upper_by_act[idx]
	return Color(0.55, 0.40, 0.85, 1.0)


func is_three_act_capable() -> bool:
	return max_act_depth >= 3
