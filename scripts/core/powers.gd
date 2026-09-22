class_name Powers
## Static registry of character powers (mirrors StatusEffects). Access via
## Powers.DETACHMENT, etc. Per-turn behavior is applied by
## CombatEngine._process_powers; event-driven powers (Whiplash) and in-play powers
## (Overflow) are handled at their own hooks. All keyed off each power's id.

static var DETACHMENT: PowerData
static var CONVICTION: PowerData
static var GROUNDED: PowerData
static var OVERFLOW: PowerData
static var WHIPLASH: PowerData

## How far Detachment cools Passion toward center each turn (additive, volatility-scaled).
const DETACHMENT_DRIFT := 8
## Strength gained per Detachment stack each turn.
const DETACHMENT_STRENGTH := 1
## Energy Conviction grants per stack while at a committed extreme.
const CONVICTION_ENERGY := 1
## Block Grounded grants per stack while at Hollow.
const GROUNDED_BLOCK := 5
## Cards Whiplash draws per stack on each tier crossing.
const WHIPLASH_DRAW := 1


static func _static_init() -> void:
	DETACHMENT = _make(&"detachment", "Detachment",
		"Start of each turn: your Passion cools toward center, and you steel into +%d Strength (per stack)." % DETACHMENT_STRENGTH)
	CONVICTION = _make(&"conviction", "Conviction",
		"Start of each turn, while at a committed extreme (Blazing or Hollow): gain %d Energy (per stack)." % CONVICTION_ENERGY)
	GROUNDED = _make(&"grounded", "Grounded",
		"Start of each turn, while Hollow: gain %d Block (per stack)." % GROUNDED_BLOCK)
	OVERFLOW = _make(&"overflow", "Overflow",
		"While Blazing, your multi-hit attacks strike 1 extra time (per stack).")
	WHIPLASH = _make(&"whiplash", "Whiplash",
		"Whenever your Passion crosses into a new tier, draw %d card (per stack)." % WHIPLASH_DRAW)


static func _make(id: StringName, n: String, desc: String) -> PowerData:
	var p := PowerData.new()
	p.id = id
	p.power_name = n
	p.description = desc
	return p
