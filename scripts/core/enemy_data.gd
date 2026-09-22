class_name EnemyData
extends Resource
## Defines an enemy type: stats, available moves, and move selection behavior.

@export var enemy_name: String = ""
@export var max_health: int = 50
@export var moves: Array[EnemyMove] = []
@export var sprite: Texture2D

## Multi-phase bosses (separate HP bars). Leave empty for a normal single-phase
## enemy. When set, `phase_hps[i]` is phase i's own lifebar and `phase_movesets[i]`
## its move list; depleting a phase's HP transitions to the next phase (refill HP +
## swap moves + speak `phase_lines[i]`) instead of dying. Only the final phase's
## death ends the fight, so the boss can't be burst past a phase. Built in code by
## EnemyPool, not wired in the inspector, so the moveset array is left untyped.
@export var phase_hps: Array[int] = []
var phase_movesets: Array = []            # Array[Array[EnemyMove]], one per phase
@export var phase_lines: Array[String] = []  # spoken on ENTERING phase i (i>=1 = transitions)
## On ENTERING phase i, the engine applies these one-time transition effects (index by
## phase). They make reaching a phase a guaranteed, pace-independent cost — the boss's
## anti-burst pressure: an unavoidable lash at the player, a Strength gain, and Enraged
## (retaliation) so bursting the next bar down still hurts.
@export var phase_enter_damage: Array[int] = []        # unavoidable HP hit on the player
@export var phase_enter_self_strength: Array[int] = [] # Strength the enemy gains
@export var phase_enter_enraged: Array[int] = []       # Enraged (retaliation) the enemy gains


## True if this enemy fights in multiple separate-HP-bar phases.
func is_multiphase() -> bool:
	return phase_hps.size() > 1
