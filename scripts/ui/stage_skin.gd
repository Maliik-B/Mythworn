class_name StageSkin
extends RefCounted
## The combat stage's look, in one place. `active` is the one switch: everything the stage draws
## on its ground (the ground itself, the washes behind it, names, bars, numbers, banners, pills)
## reads its colour here, so changing look is one assignment and no colour for it lives anywhere
## else. The desk under the stage, with the player bar on it, is dark in both. The hand follows the
## look: parchment leaves on the page, type-coloured cards in the dark.
## Neither look has purple in it, on purpose.

const DARK := &"dark"
const PAGE := &"page"

## The switch. A capture can set it before the combat scene loads.
static var active: StringName = PAGE

## How far Passion reaches on the page. It is the keeper's and not the world's, so by default the
## page and the ground stay as they are and only the keeper's own things (gauge, desk, hand) answer.
## The two wider reaches are kept so they can be compared. No effect in the dark, which has no page.
enum PassionReach { KEEPER, GROUND_TOO, WHOLE_PAGE }
static var passion_reach := PassionReach.KEEPER

static var _no_purple: ShaderMaterial = null
static var _icon_grey: ShaderMaterial = null

# The faces the stage's words are set in, so a swap is here and nowhere else. They follow the card
# face's picks.
const NAME_FONT_PATH := CardFace.TITLE_FONT_PATH
const LINE_FONT_PATH := CardFace.RULES_FONT_PATH
const NUMERAL_FONT_PATH := CardFace.NUMERAL_FONT_PATH

# How strongly Passion tints the whole stage, by look, where it does.
const MOOD_GAIN := {DARK: 1.0, PAGE: 0.55}

# What a Passion band does on the page, Steady leaving it all be. "ground" only if the reach allows.
# Blazing warms. Hollow goes to the deep blue and never to grey, which is why these are the colours
# to arrive at and not a blue laid over them: tan under a thin blue is grey. The hand warms and does
# not cool: a blue leaf turns the edges of its red initials and coins purple. So the cold end does
# not tint the hand as a whole ("hand" stays white): "leaf" is a tint for the leaf's own paper and its
# slab alone, set as the panel's self_modulate, which its children (initial, coin, rules) never see.
const PASSION_ON_PAGE := {
	PassionState.Tier.BLAZING: {"ground": Color("C98F56"), "desk": Color("2C170A"), "hand": Color(1.0, 0.9, 0.74), "leaf": Color.WHITE, "gauge": Color("D9681E")},
	PassionState.Tier.INSPIRED: {"ground": Color("C2A073"), "desk": Color("241A12"), "hand": Color(1.0, 0.95, 0.87), "leaf": Color.WHITE, "gauge": Color("C98F56")},
	PassionState.Tier.WAVERING: {"ground": Color("8FA0C4"), "desk": Color("18233F"), "hand": Color.WHITE, "leaf": Color(0.86, 0.92, 1.08), "gauge": Color("4A63A8")},
	PassionState.Tier.HOLLOW: {"ground": Color("6A84BC"), "desk": Color("122B64"), "hand": Color.WHITE, "leaf": Color(0.72, 0.82, 1.14), "gauge": Color("1F3C88")},
}

const LOOKS := {
	DARK: {
		"desk": Color(0.055, 0.05, 0.047),
		"wear": Color(0, 0, 0, 0),
		"stat_hp": Color(0.9, 0.3, 0.3),
		"stat_outline": Color(0, 0, 0, 0),
		"stat_block": Color(0.3, 0.6, 0.9),
		"stat_energy": Color(0.9, 0.9, 0.3),
		"stat_passion": Color(0.9, 0.5, 0.2),
		"bar_frame": Color(0, 0, 0, 0),
		"bar_panel": Color(0.105, 0.098, 0.09, 0.95),
		"flake_a": Color(0.9, 0.3, 0.2, 0.8),
		"flake_b": Color(0.65, 0.25, 0.15, 0.8),
		"end_bg": Color(0.24, 0.17, 0.08),
		"end_edge": Color(0.8, 0.6, 0.2),
		"end_text": Color(0.9, 0.75, 0.35),
		"school_water": Color(0.9, 0.5, 0.2),
		"school_physical": Color(0.4, 0.6, 0.9),
		"card_ink": Color(0.94, 0.925, 0.886),
		"card_dim": Color(0.745, 0.714, 0.667),
		"card_number_up": Color(1.0, 0.77, 0.36),
		"card_number_down": Color(0.59, 0.557, 0.557),
		"card_passion_up": Color(1.0, 0.667, 0.353),
		"card_passion_down": Color(0.51, 0.667, 0.96),
		"card_bg_attack": Color(0.3, 0.12, 0.1),
		"card_edge_attack": Color(0.9, 0.25, 0.2),
		"card_bg_skill": Color(0.1, 0.14, 0.3),
		"card_edge_skill": Color(0.25, 0.45, 0.9),
		"card_bg_power": Color(0.28, 0.24, 0.08),
		"card_edge_power": Color(0.9, 0.75, 0.15),
		"card_bg_curse": Color(0.14, 0.13, 0.12),
		"card_edge_curse": Color(0.46, 0.42, 0.36),
		"card_rubric_attack": Color(0, 0, 0, 0),
		"card_rubric_skill": Color(0, 0, 0, 0),
		"card_rubric_power": Color(0, 0, 0, 0),
		"card_rubric_curse": Color(0, 0, 0, 0),
		"card_coin_attack": Color(0.18, 0.14, 0.06),
		"card_coin_skill": Color(0.18, 0.14, 0.06),
		"card_coin_power": Color(0.18, 0.14, 0.06),
		"card_coin_curse": Color(0.18, 0.14, 0.06),
		"card_coin_edge": Color(0.95, 0.8, 0.2),
		"card_coin_text": Color(0.95, 0.9, 0.3),
		"card_inset": Color(0, 0, 0, 0),
		"card_uncommon": Color(0.45, 0.78, 0.95),
		"card_rare": Color(0.95, 0.8, 0.3),
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
		"intent_outline": Color(0, 0, 0, 0),
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
		"note_bg": Color(0.09, 0.085, 0.078, 0.98),
		"note_edge": Color(0.55, 0.5, 0.42),
		"note_ink": Color(0.93, 0.9, 0.85),
		"note_dim": Color(0.7, 0.66, 0.6),
	},
	PAGE: {
		"desk": Color("1C1A18"),
		"wear": Color("1C1A18"),
		"stat_hp": Color("D7301F"),
		"stat_outline": Color("0F0E0C"),
		"stat_block": Color("8DA2D6"),
		"stat_energy": Color("E8DCBD"),
		"stat_passion": Color("D9A06A"),
		"bar_frame": Color("1E1B18"),
		"bar_panel": Color(0, 0, 0, 0),
		"flake_a": Color("3D3A35"),
		"flake_b": Color("6F7274"),
		"end_bg": Color("2A2622"),
		"end_edge": Color("8C7A4E"),
		"end_text": Color("E8DCBD"),
		"school_water": Color("A8531C"),
		"school_physical": Color("1F3C88"),
		"card_ink": Color("1E1B18"),
		"card_dim": Color("5A5750"),
		"card_number_up": Color("A8531C"),
		"card_number_down": Color("8C8676"),
		"card_passion_up": Color("A8531C"),
		"card_passion_down": Color("1F3C88"),
		"card_bg_attack": Color("E8DCBD"),
		"card_edge_attack": Color("0F0E0C"),
		"card_bg_skill": Color("E8DCBD"),
		"card_edge_skill": Color("0F0E0C"),
		"card_bg_power": Color("E8DCBD"),
		"card_edge_power": Color("0F0E0C"),
		"card_bg_curse": Color("B8AC93"),
		"card_edge_curse": Color("0F0E0C"),
		"card_rubric_attack": Color("D7301F"),
		"card_rubric_skill": Color("1F3C88"),
		"card_rubric_power": Color("8C7A4E"),
		"card_rubric_curse": Color("3D3A35"),
		"card_coin_attack": Color("D7301F"),
		"card_coin_skill": Color("1F3C88"),
		"card_coin_power": Color("8C7A4E"),
		"card_coin_curse": Color("5A5750"),
		"card_coin_edge": Color(0, 0, 0, 0),
		"card_coin_text": Color("E8DCBD"),
		"card_inset": Color("B8AC93"),
		"card_uncommon": Color("1F3C88"),
		"card_rare": Color("8C6A1E"),
		"wall": Color("D3C9B1"),
		"ruling": Color("CCC2AA"),
		"wash_far": Color("C7BCA3"),
		"wash_near": Color("BBAF96"),
		"ground": Color("B8AC93"),
		"ground_line": Color("B8AC93"),
		"shadow": Color("9A8F76"),
		"dim": Color(0.2, 0.18, 0.15, 0.2),
		"ember": Color(0, 0, 0, 0),
		"frost": Color(0, 0, 0, 0),
		"ink": Color("1E1B18"),
		"ink_soft": Color("3D3A35"),
		"bar_back": Color("8C8676"),
		"bar_trail": Color("5A5750"),
		"bar_high": Color("1E1B18"),
		"bar_mid": Color("2A2622"),
		"bar_low": Color("3D3A35"),
		"bar_text": Color("E8DCBD"),
		"bar_text_shadow": Color(0, 0, 0, 0.6),
		"number_hurt": Color("1E1B18"),
		"number_heal": Color("3D3A35"),
		"number_block": Color("3D3A35"),
		"number_outline": Color("E8DCBD"),
		"block": Color("3D3A35"),
		"banner_you": Color("1E1B18"),
		"banner_enemy": Color("D7301F"),
		"banner_outline": Color("D3C9B1"),
		"callout": Color("1E1B18"),
		"callout_outline": Color("E8DCBD"),
		"intent_outline": Color("E8DCBD"),
		"intent_attack": Color("D7301F"),
		"intent_defend": Color("3D3A35"),
		"intent_buff": Color("3D3A35"),
		"intent_debuff": Color("D7301F"),
		"intent_passion": Color("D7301F"),
		"line": Color("1E1B18"),
		"line_outline": Color(0, 0, 0, 0),
		"pile_map": Color("3D3A35"),
		"pile_draw": Color("3D3A35"),
		"pile_exhaust": Color("3D3A35"),
		"pile_discard": Color("3D3A35"),
		"pack_tint": Color(0.32, 0.3, 0.28),
		"glow_mid": Color(0.93, 0.74, 0.42, 0.45),
		"glow_core": Color(1.0, 0.86, 0.55, 0.9),
		"note_bg": Color("E8DCBD"),
		"note_edge": Color("0F0E0C"),
		"note_ink": Color("1E1B18"),
		"note_dim": Color("5A5750"),
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


## True when Passion colours the keeper's things, and not the whole stage.
static func passion_on_keeper() -> bool:
	return is_page() and passion_reach != PassionReach.WHOLE_PAGE


## The ground under a Passion band.
static func ground_tint(tier: int) -> Color:
	return keeper_tint(tier)["ground"] if passion_reach == PassionReach.GROUND_TOO else c("ground")


## The ground, desk and hand a Passion band asks for on the page.
static func keeper_tint(tier: int) -> Dictionary:
	if PASSION_ON_PAGE.has(tier):
		return PASSION_ON_PAGE[tier]
	return {"ground": c("ground"), "desk": c("desk"), "hand": Color.WHITE, "leaf": Color.WHITE}


## A Passion band's own colour on the gauge.
static func gauge_color(tier: int) -> Color:
	if is_page() and PASSION_ON_PAGE.has(tier):
		return PASSION_ON_PAGE[tier]["gauge"]
	return PassionInfographic._tier_color(tier)


## For a card's small art: on the page it goes to the ramp's greys with the figures. In the dark it
## only loses any purple.
static func icon_material() -> ShaderMaterial:
	if not is_page():
		return no_purple()
	if _icon_grey == null:
		_icon_grey = ShaderMaterial.new()
		_icon_grey.shader = load("res://assets/ui/stage_body.gdshader")
		_icon_grey.set_shader_parameter("drain", 1.0)
	return _icon_grey
