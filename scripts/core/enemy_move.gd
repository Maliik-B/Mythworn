class_name EnemyMove
extends Resource
## A single move an enemy can perform. Uses the same CardEffect system as player cards.

enum IntentType { ATTACK, DEFEND, BUFF, DEBUFF, ATTACK_DEBUFF, UNKNOWN }

@export var move_name: String = ""
@export var intent_type: IntentType = IntentType.ATTACK
@export var effects: Array[CardEffect] = []
@export var intent_icon: Texture2D
## Weight for random move selection (higher = more likely to be chosen).
@export var weight: float = 1.0

## HP-band gate, as a fraction of max health. A move is only eligible when the
## enemy's current HP fraction sits within [min_hp_percent, max_hp_percent]. The
## defaults span the whole bar, so an ungated move behaves exactly as before.
## This is how boss phases are expressed: a "phase 2" move is gated to <= 0.5, a
## phase-1-only move to >= 0.5. Also handy for "desperate at low HP" flourishes.
@export var min_hp_percent: float = 0.0
@export var max_hp_percent: float = 1.0

## Turns this move must sit out before it can be chosen again (0 = no cooldown,
## the old behavior). Lets a heavy telegraphed hit land on a rhythm ("every ~3
## turns") instead of clumping at random. Cooldown is tracked per enemy in
## EnemyCombatState; it does not survive between separate combats.
@export var cooldown: int = 0
