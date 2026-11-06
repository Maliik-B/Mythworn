class_name StageSkin
extends RefCounted
## The combat stage's look, in one place. `active` is the one switch: everything the stage draws
## on its ground (the ground itself, the washes behind it, names, bars, numbers, banners, pills)
## reads its colour here, so changing look is one assignment and no colour for it lives anywhere
## else. The desk under the stage, with the player bar and the hand on it, is dark in both.
## Neither look has purple in it, on purpose.

const DARK := &"dark"
const PAGE := &"page"

## The switch. A capture can set it before the combat scene loads.
static var active: StringName = DARK

static var _no_purple: ShaderMaterial = null

# The faces the stage's words are set in, so a swap is here and nowhere else. They follow the card
# face's picks.
const NAME_FONT_PATH := CardFace.TITLE_FONT_PATH
const LINE_FONT_PATH := CardFace.RULES_FONT_PATH

const LOOKS := {
	DARK: {
		"desk": Color(0.055, 0.05, 0.047),
		"wall": Color(0.075, 0.07, 0.065),
		"ruling": Color(0, 0, 0, 0),
		"wash_far": Color(0.115, 0.107, 0.098),
		"wash_near": Color(0.15, 0.138, 0.124),
		"ground": Color(0.098, 0.09, 0.082),
		"ground_line": Color(0.2, 0.185, 0.165),
		"shadow": Color(0, 0, 0, 0.55),
		"dim": Color(0, 0, 0, 0.5),
		"ember": Color(1.0, 0.6, 0.22),
		"frost": Color(0.72, 0.84, 1.0),
		"ink": Color(0.93, 0.9, 0.84),
		"ink_soft": Color(0.76, 0.72, 0.64),
		"bar_back": Color(0.14, 0.11, 0.1),
		"bar_trail": Color(0.62, 0.42, 0.2),
		"bar_high": Color(0.78, 0.2, 0.15),
		"bar_mid": Color(0.86, 0.48, 0.12),
		"bar_low": Color(0.5, 0.1, 0.1),
		"bar_text": Color(1, 1, 1),
		"bar_text_shadow": Color(0, 0, 0, 0.8),
		"number_hurt": Color(1.0, 0.32, 0.22),
		"number_heal": Color(0.42, 0.95, 0.45),
		"number_block": Color(0.35, 0.72, 1.0),
		"number_outline": Color(0, 0, 0),
		"block": Color(0.38, 0.68, 0.95),
		"banner_you": Color(0.85, 0.82, 0.72),
		"banner_enemy": Color(0.92, 0.42, 0.3),
		"banner_outline": Color(0, 0, 0),
		"callout": Color(1.0, 0.85, 0.42),
		"callout_outline": Color(0, 0, 0, 0.85),
		"intent_attack": Color(1.0, 0.4, 0.3),
		"intent_defend": Color(0.35, 0.72, 1.0),
		"intent_buff": Color(0.36, 0.86, 0.44),
		"intent_debuff": Color(0.86, 0.72, 0.32),
		"intent_passion": Color(1.0, 0.64, 0.3),
		"line": Color(0.97, 0.95, 0.9),
		"line_outline": Color(0, 0, 0, 0.9),
		"pile_map": Color(0.82, 0.72, 0.42),
		"pile_draw": Color(0.5, 0.7, 0.9),
		"pile_exhaust": Color(0.66, 0.62, 0.56),
		"pile_discard": Color(0.74, 0.54, 0.46),
		"pack_tint": Color(1, 1, 1),
		"glow_mid": Color(1.0, 0.62, 0.26, 0.3),
		"glow_core": Color(1.0, 0.72, 0.36, 0.8),
	},
	PAGE: {
		"desk": Color("1C1A18"),
		"wall": Color("D3C9B1"),
		"ruling": Color("CCC2AA"),
		"wash_far": Color("C7BCA3"),
		"wash_near": Color("BBAF96"),
		"ground": Color("B8AC93"),
		"ground_line": Color("8F846C"),
		"shadow": Color("9A8F76"),
		"dim": Color(0.2, 0.18, 0.15, 0.32),
		"ember": Color("A8531C"),
		"frost": Color("EEF2F8"),
		"ink": Color("1E1B18"),
		"ink_soft": Color("3D3A35"),
		"bar_back": Color("CFC8B8"),
		"bar_trail": Color("8C8676"),
		"bar_high": Color("1E1B18"),
		"bar_mid": Color("3D3A35"),
		"bar_low": Color("D7301F"),
		"bar_text": Color("E8DCBD"),
		"bar_text_shadow": Color(0, 0, 0, 0.6),
		"number_hurt": Color("D7301F"),
		"number_heal": Color("2F6B3A"),
		"number_block": Color("1F3C88"),
		"number_outline": Color("E8DCBD"),
		"block": Color("1F3C88"),
		"banner_you": Color("1E1B18"),
		"banner_enemy": Color("D7301F"),
		"banner_outline": Color("D3C9B1"),
		"callout": Color("1E1B18"),
		"callout_outline": Color("E8DCBD"),
		"intent_attack": Color("D7301F"),
		"intent_defend": Color("1F3C88"),
		"intent_buff": Color("2F6B3A"),
		"intent_debuff": Color("6B5A2E"),
		"intent_passion": Color("A8531C"),
		"line": Color("1E1B18"),
		"line_outline": Color("D3C9B1"),
		"pile_map": Color("3D3A35"),
		"pile_draw": Color("3D3A35"),
		"pile_exhaust": Color("3D3A35"),
		"pile_discard": Color("3D3A35"),
		"pack_tint": Color(0.32, 0.3, 0.28),
		"glow_mid": Color(0.93, 0.74, 0.42, 0.45),
		"glow_core": Color(1.0, 0.86, 0.55, 0.9),
	},
}


static func c(key: String) -> Color:
	return LOOKS[active][key]


## For a glyph or icon that may come out of a system emoji font: ⚔ is shaded purple there, and this
## is what takes it out. Shared, since it holds no state of its own.
static func no_purple() -> ShaderMaterial:
	if _no_purple == null:
		_no_purple = ShaderMaterial.new()
		_no_purple.shader = load("res://assets/ui/stage_body.gdshader")
	return _no_purple


static func is_page() -> bool:
	return active == PAGE
