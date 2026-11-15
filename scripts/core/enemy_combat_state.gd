class_name EnemyCombatState
extends RefCounted
## Runtime state for a single enemy during combat.

var enemy_data: EnemyData
var stats: CombatantStats
var current_intent: EnemyMove
## The move the enemy will take NEXT turn, pre-rolled for Excalibur's Sight mode.
## Always populated alongside current_intent; visibility is gated in the UI.
var next_intent: EnemyMove
## Current phase for multi-phase bosses (0-based). Single-phase enemies stay at 0.
var phase_index: int = 0

## Counts up once per select_intent() call, i.e. once per enemy turn. Drives the
## per-move cooldown bookkeeping below.
var _turn: int = 0
## EnemyMove -> the _turn value on which it was last actually performed. Absent
## means never used. Only the move the enemy commits to (current_intent) is
## recorded; a pre-rolled prediction that never fires does not spend its cooldown.
var _last_used: Dictionary = {}


func _init(data: EnemyData) -> void:
	enemy_data = data
	var hp := data.max_health
	if data.phase_hps.size() > 0:
		hp = data.phase_hps[0]
	stats = CombatantStats.new(hp)


## The move list for the current phase, the per-phase set for a multi-phase boss,
## or the flat `moves` for a single-phase enemy.
func _active_moves() -> Array:
	if enemy_data.phase_movesets.size() > phase_index:
		return enemy_data.phase_movesets[phase_index]
	return enemy_data.moves


## True if there's another phase to transition into when this one's HP is depleted.
func can_advance_phase() -> bool:
	return enemy_data.phase_hps.size() > phase_index + 1


## Transition to the next phase: refill to its own lifebar, drop block, clear statuses
## (a fresh state: resets both player debuffs and the boss's own escalation), reset
## the move cadence, and reroll intent. Returns the line to speak on entering, if any.
func advance_phase() -> String:
	phase_index += 1
	var hp: int = enemy_data.phase_hps[phase_index]
	stats.current_hp = hp
	stats.max_hp = hp
	stats.block = 0
	stats.statuses.clear()
	_turn = 0
	_last_used.clear()
	next_intent = null
	select_intent()
	if enemy_data.phase_lines.size() > phase_index:
		return enemy_data.phase_lines[phase_index]
	return ""


## Advances intent by one turn. On the first call (next_intent is null) it rolls
## both current and next fresh. Afterwards it slides the pre-rolled next into
## current, but only if that prediction is still legal, since a boss can cross an
## HP phase threshold between turns and invalidate a move that was fine last turn.
## When the prediction no longer fits, we roll fresh (Sight mode's forecast can
## "miss" right at a phase break, which reads as the enemy changing tactics).
func select_intent() -> void:
	if _active_moves().is_empty():
		current_intent = null
		next_intent = null
		return

	_turn += 1

	if next_intent != null and _is_eligible(next_intent, _turn):
		current_intent = next_intent
	else:
		current_intent = _roll_move(_turn)

	if current_intent != null:
		_last_used[current_intent] = _turn

	# Pre-roll the following turn for Sight. We forecast against _turn + 1 so
	# cooldowns line up with when the move would actually be chosen.
	next_intent = _roll_move(_turn + 1)


## Whether a move is legal on a given turn: its HP band must contain the enemy's
## current HP fraction, and it must be off cooldown.
func _is_eligible(move: EnemyMove, for_turn: int) -> bool:
	var hp_frac := 1.0
	if stats.max_hp > 0:
		hp_frac = float(stats.current_hp) / float(stats.max_hp)
	# Small epsilon so a threshold written as exactly 0.5 includes 50% HP.
	if hp_frac < move.min_hp_percent - 0.0001:
		return false
	if hp_frac > move.max_hp_percent + 0.0001:
		return false
	if move.cooldown > 0 and _last_used.has(move):
		if for_turn - int(_last_used[move]) <= move.cooldown:
			return false
	return true


func _roll_move(for_turn: int) -> EnemyMove:
	var moves := _active_moves()
	if moves.is_empty():
		return null

	var eligible: Array[EnemyMove] = []
	for move in moves:
		if _is_eligible(move, for_turn):
			eligible.append(move)
	# Safety net: if gating rules out everything (e.g. every move is on cooldown),
	# fall back to the full list so the enemy never stalls into a null intent.
	if eligible.is_empty():
		eligible.assign(moves)

	var total_weight := 0.0
	for move in eligible:
		total_weight += move.weight
	var roll = RngManager.enemy_rng.randf() * total_weight
	var cumulative := 0.0
	for move in eligible:
		cumulative += move.weight
		if roll <= cumulative:
			return move
	return eligible[0]
