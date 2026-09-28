class_name PassionCenterEffect
extends CardEffect
## Multiplicatively pulls the player's Passion toward 0 (the dispassionate center)
## by `strength` (a 0..1 fraction: 0.3 = pull 30% of the way to center this hit).
##
## The False Prophet's signature. On the signed axis this is self-scaling: it yanks
## hard when you're committed to a pole and eases off near center, and it can never
## overshoot 0. Counterplay is your own Passion cards pushing back toward your pole.


## Strength of the pull (0..1). Stored separately from the int `value` since it's a
## fraction, not an amount.
@export var strength: float = 0.3

## Each stack of the SOURCE's Zealotry multiplies the pull by this much — the Prophet's
## escalation. Capped below 1.0 so a single pull can never fully wipe your pole.
const ZEAL_SCALE := 0.12
const MAX_PULL := 0.85


func apply(source, _target, _battle_state) -> void:
	var s := strength
	if source and source.has_status(StatusEffects.ZEALOTRY):
		s *= 1.0 + source.get_status_stacks(StatusEffects.ZEALOTRY) * ZEAL_SCALE
	RunManager.pull_passion_to_center(minf(s, MAX_PULL))


func get_description() -> String:
	return "Pull Passion %d%% toward center." % int(round(strength * 100.0))
