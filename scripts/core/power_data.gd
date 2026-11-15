class_name PowerData
extends Resource
## A character POWER: a persistent, character-defining effect granted by playing a
## POWER card (StS-style). Its per-turn behavior lives in CombatEngine (hardcoded per
## power, keyed off `id`, exactly like status ticks). Powers get their own slot on the
## battle bar, apart from transient statuses.

var id: StringName = &""
var power_name: String = ""
var description: String = ""
var icon: Texture2D
