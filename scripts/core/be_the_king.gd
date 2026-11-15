class_name BeTheKing
extends RefCounted
## Be the King: Camelot's post-boss performance dial.
##
## Scores a crown-stakes boss fight on a 0-1 scale, then quantizes to one of
## four tiers. The tier sets the magnitude of the governing philosophy's
## modifiers if the player takes the crown (Act 1), or feeds into King's
## Reputation if the player is already crowned (Act 2+).
##
## Design rules (see docs/REALM_CAMELOT.md "Be the King"):
##   - Any win gives a decent baseline. The lowest tier still grants 0.6x
##     modifier strength; the meter decides leverage, not whether you rule.
##   - Score is normalized to the boss fight itself, not the run. The throne
##     room sees how the fight ended, not how the player arrived.
##   - Two scoring tracks (HP retention vs. speed) are combined with max(),
##     so block-tank and burst archetypes both have a path to Triumphant.
##
## Pure logic: no engine references. CombatEngine snapshots the inputs and
## calls score_fight() on combat_won when the fight is crown-stakes.

enum Tier { BATTERED, SCRAPPY, DECISIVE, TRIUMPHANT }

const TIER_MULTIPLIERS := {
	Tier.BATTERED: 0.6,
	Tier.SCRAPPY: 0.7,
	Tier.DECISIVE: 0.85,
	Tier.TRIUMPHANT: 1.0,
}

const TIER_NAMES := {
	Tier.BATTERED: "Battered",
	Tier.SCRAPPY: "Scrappy",
	Tier.DECISIVE: "Decisive",
	Tier.TRIUMPHANT: "Triumphant",
}

# Skul-style narrative reveals shown on the post-fight scene. The player never
# sees a numeric score; they see how the realm talks about the fight.
const TIER_PHRASES := {
	Tier.BATTERED: "You barely survived, but you survived. The court does not yet know what to make of you.",
	Tier.SCRAPPY: "The court remembers a close battle. Whispers travel of how near the end came.",
	Tier.DECISIVE: "Whispers of a decisive victory ripple through the kingdom. The realm leans toward you.",
	Tier.TRIUMPHANT: "Ballads are already being written of your triumph. The realm exhales in awe.",
}

# Speed scoring: a fight ending at or under SPEED_FLOOR turns is a max-speed
# win; SPEED_CEILING turns or more bottoms out at SPEED_MIN. Linear between.
const SPEED_FLOOR := 4
const SPEED_CEILING := 12
const SPEED_MIN := 0.4
# Bonus added to the better of (HP score, speed score) when no passion tier
# change occurred during the fight: rewards holding identity under pressure.
const PASSION_STABILITY_BONUS := 0.1

# Score thresholds for tier quantization. Read top-down: first match wins.
const TIER_THRESHOLDS := [
	[0.85, Tier.TRIUMPHANT],
	[0.65, Tier.DECISIVE],
	[0.4, Tier.SCRAPPY],
]


## Score a crown-stakes boss fight.
##
## start_hp: player HP at the moment the boss combat began
## end_hp: player HP after the killing blow
## max_hp: player max HP (sanity bound, doesn't affect score)
## turns: number of player turns taken (CombatEngine.turn_number on win)
## passion_tier_changed: true if the player's passion crossed a tier boundary
##                      at any point during the fight
##
## Returns: { score: float, tier: int, multiplier: float, phrase: String,
##            tier_name: String }
static func score_fight(start_hp: int, end_hp: int, max_hp: int, turns: int,
		passion_tier_changed: bool) -> Dictionary:
	var hp_score := _hp_score(start_hp, end_hp, max_hp)
	var speed_score := _speed_score(turns)
	# max() of the two tracks: reward whichever the player optimized for.
	var base_score: float = maxf(hp_score, speed_score)
	if not passion_tier_changed:
		base_score += PASSION_STABILITY_BONUS
	var final_score := clampf(base_score, 0.0, 1.0)
	var tier := _tier_for_score(final_score)
	return {
		"score": final_score,
		"tier": tier,
		"multiplier": TIER_MULTIPLIERS[tier],
		"phrase": TIER_PHRASES[tier],
		"tier_name": TIER_NAMES[tier],
	}


## Convert a tier back to its multiplier. Used by RunManager helpers when the
## tier is already locked (e.g. philosophy_strength_tier) and only the scaling
## factor is needed.
static func multiplier_for_tier(tier: int) -> float:
	return TIER_MULTIPLIERS.get(tier, 1.0)


static func tier_name(tier: int) -> String:
	return TIER_NAMES.get(tier, "Unknown")


static func phrase_for_tier(tier: int) -> String:
	return TIER_PHRASES.get(tier, "")


# --- Internal scoring tracks ---

static func _hp_score(start_hp: int, end_hp: int, max_hp: int) -> float:
	# Normalize against starting HP, not max: a player who entered the boss
	# at 30% shouldn't be penalized for arriving wounded. The fight is scored
	# on its own terms.
	if start_hp <= 0:
		return 0.0
	var ratio := float(end_hp) / float(start_hp)
	return clampf(ratio, 0.0, 1.0)


static func _speed_score(turns: int) -> float:
	if turns <= SPEED_FLOOR:
		return 1.0
	if turns >= SPEED_CEILING:
		return SPEED_MIN
	# Linear interpolation from 1.0 at SPEED_FLOOR down to SPEED_MIN at SPEED_CEILING.
	var t := float(turns - SPEED_FLOOR) / float(SPEED_CEILING - SPEED_FLOOR)
	return lerpf(1.0, SPEED_MIN, t)


static func _tier_for_score(score: float) -> int:
	for entry in TIER_THRESHOLDS:
		if score >= entry[0]:
			return entry[1]
	return Tier.BATTERED
