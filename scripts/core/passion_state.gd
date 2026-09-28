class_name PassionState
extends Resource
## Runtime state of the Passion meter for the current run.
## Signed axis: 0 = dispassionate center, +100 = fully primary pole, -100 = fully
## secondary pole. Tier boundaries are defined per-character in CharacterData.

enum Tier { HOLLOW, WAVERING, STEADY, INSPIRED, BLAZING }

# Capped at ±60 (design pass Sep 2026), not ±100: with tiers at ±50, "at your pole" is a
# tight 50–60 band you SIT at rather than an open slider, so every Passion mechanic (the
# Prophet's pull, swing relics, card costs) has a defined 0-to-max to work against — and a
# multiplicative center-pull from +60 can actually drop you a tier, which it couldn't from +100.
@export var current_value: int = 0
@export var min_value: int = -60
@export var max_value: int = 60
@export var starting_value: int = 0


static func tier_name(tier: Tier) -> String:
	match tier:
		Tier.BLAZING: return "Blazing"
		Tier.INSPIRED: return "Inspired"
		Tier.STEADY: return "Steady"
		Tier.WAVERING: return "Wavering"
		Tier.HOLLOW: return "Hollow"
	return "Unknown"
