extends Node
## Deterministic RNG with separate tracks per system.
## Ensures seeded runs produce identical results and save/load preserves randomness.

var run_seed: int = 0

var deck_rng := RandomNumberGenerator.new()
var enemy_rng := RandomNumberGenerator.new()
var loot_rng := RandomNumberGenerator.new()
var event_rng := RandomNumberGenerator.new()
var map_rng := RandomNumberGenerator.new()


func setup_run(seed_value: int) -> void:
	run_seed = seed_value
	deck_rng.seed = hash(str(seed_value) + "deck")
	enemy_rng.seed = hash(str(seed_value) + "enemy")
	loot_rng.seed = hash(str(seed_value) + "loot")
	event_rng.seed = hash(str(seed_value) + "event")
	map_rng.seed = hash(str(seed_value) + "map")


## In-place Fisher-Yates shuffle drawn from `rng`. Array.shuffle() draws from Godot's global
## RNG instead, which is seeded fresh in every process, so a shuffle that decides gameplay has
## to come through here or the same seed stops giving the same run.
func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func generate_seed() -> int:
	randomize()
	return randi()


func get_save_state() -> Dictionary:
	return {
		"run_seed": run_seed,
		"deck_state": deck_rng.state,
		"enemy_state": enemy_rng.state,
		"loot_state": loot_rng.state,
		"event_state": event_rng.state,
		"map_state": map_rng.state,
	}


func load_save_state(state: Dictionary) -> void:
	run_seed = state["run_seed"]
	setup_run(run_seed)
	deck_rng.state = state["deck_state"]
	enemy_rng.state = state["enemy_state"]
	loot_rng.state = state["loot_state"]
	event_rng.state = state["event_state"]
	map_rng.state = state["map_state"]
