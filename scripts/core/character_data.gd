class_name CharacterData
extends Resource
## Defines a playable character: personalities, passion behavior, and card pools.

@export var character_name: String = ""
@export_multiline var description: String = ""
@export var max_health: int = 80

# Passion configuration
@export var passion_volatility: float = 1.0 # Multiplier for all passion changes
## Breakpoints between tiers on the signed axis: [blazing_min, inspired_min,
## steady_min, wavering_min]. Values below wavering_min are Hollow. Symmetric
## around 0 so the two poles mirror each other (+ = primary, - = secondary).
## Tightened from ±60/±20 to ±50/±18 in the Passion-amplification pass so a demo
## player actually reaches the committed extremes (where the zone modifier bites).
@export var passion_thresholds: Array[int] = [50, 18, -18, -50]

# Personality descriptions
@export var primary_personality: String = "" # e.g. "Magic"
@export var secondary_personality: String = "" # e.g. "Physical"

# -- Innate passive --
## HP restored whenever the player lands a crowd-control status (Weak or Frozen) on an
## enemy. The glass-Water pole's non-block answer to attrition: playing your control cards
## mends you, so you recover by STILLING the enemy rather than by armoring up. Auto-gates
## by pole — a Physical build applies Vulnerable/Strength, not Weak/Frozen, so it never
## triggers. 0 for characters without the trait.
@export var control_heal: int = 0

# Card pools
@export var starting_deck: Array[CardData] = []
@export var primary_cards: Array[CardData] = [] # Cards offered at high passion
@export var secondary_cards: Array[CardData] = [] # Cards offered at low passion

# Art
@export var portrait: Texture2D
@export var sprite: Texture2D
