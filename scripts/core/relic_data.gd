class_name RelicData
extends Resource
## Defines a relic: a passive stacking bonus acquired during a run.
## Each relic has a trigger (when it fires) and an effect (what it does).

enum RelicRarity { COMMON, UNCOMMON, RARE, BOSS }

enum RelicTrigger {
	ON_PICKUP,        # One-time when acquired
	ON_COMBAT_START,  # Start of each combat
	ON_COMBAT_END,    # After combat victory
	ON_TURN_START,    # Start of each player turn
}

enum RelicEffect {
	GAIN_MAX_HP,
	HEAL,
	GAIN_GOLD,
	GAIN_BLOCK,
	GAIN_STRENGTH,
	GAIN_DEXTERITY,
	APPLY_VULNERABLE_ALL,
	APPLY_WEAK_ALL,
	DRAW_CARDS,
	GAIN_PASSION,
	NONE,  # No automatic effect. Used by relics whose behavior is driven externally
	       # (e.g. Excalibur — Sword/Sight modes handled by CombatEngine + map UI).
}

@export var relic_name: String = ""
@export_multiline var description: String = ""
@export var rarity: RelicRarity = RelicRarity.COMMON
@export var trigger: RelicTrigger = RelicTrigger.ON_COMBAT_START
@export var effect: RelicEffect = RelicEffect.HEAL
@export var value: int = 0
## A second effect on the same trigger, for a woken forgotten relic (the one it had is the effect
## it always had and one more). NONE for every other relic.
@export var effect2: RelicEffect = RelicEffect.NONE
@export var value2: int = 0
## Forgotten relics (ROADMAP Phase 1): a dormant form names the woken form it `wakes_into`, and the
## woken form names the dormant one it was `woken_from`; both empty on an ordinary relic. The
## dormant form rolls in rewards and shops at its own rarity; the woken form sits one rarity up and
## is reached only by waking at a record site (RunManager.wake_relic). `short_name` is how prose
## refers to the dormant thing ("the plain shield"); `wake_line` is the sentence of its waking.
@export var wakes_into: StringName = &""
@export var woken_from: StringName = &""
@export var short_name: String = ""
@export var wake_line: String = ""
@export var icon: Texture2D


## True for a forgotten relic still asleep: a name worn off, a power dormant.
func is_dormant() -> bool:
	return wakes_into != &""


## True for a forgotten relic that has been given its name back.
func is_woken() -> bool:
	return woken_from != &""
