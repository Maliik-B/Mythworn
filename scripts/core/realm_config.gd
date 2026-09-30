class_name RealmConfig
extends RefCounted
## Per-run realm-shape knobs, set by the realm-entry VN choice (Camelot Act 1: court vs
## common folk) and read at the consumption points before/during map navigation. Neutral
## by default, so a run with no realm config plays exactly as before. This is the A2
## "realm configuration" system: the VN determines the STATE of the realm before you
## navigate it. See docs/GAME_DESIGN.md § Realms and docs/REALM_CAMELOT.md.
##
## NOTE: the Fable liaison "gift" (Bram's briefing / Neve's supplies) is a SEPARATE
## run-start boon, not one of these knobs — see RunManager's pending-gift handling.

## Enemy stat multiplier applied to every encounter this run
## (threaded into EnemyPool.get_*_encounter's difficulty_mult).
var enemy_difficulty_mult: float = 1.0

## Multiplier on shop card + relic base prices (shop_scene).
var shop_price_mult: float = 1.0

## Multiplier on the map's ELITE node weight during generation
## (MapGenerator.generate → _region_weights), so a "dangerous" realm carries more elites.
var elite_frequency_mult: float = 1.0

## Reward rarity bias: > 1 shifts card/relic reward rolls toward higher rarities.
## FIELDED — wired at the reward-draft consumption point in a later A2 increment.
var reward_rarity_mult: float = 1.0

## A one-time run-start realm boon keyed by id (empty = none), resolved when the realm
## map first opens. Applied via RunManager.consume_map_boon (queued from apply_realm_config).
var map_boon: StringName = &""

## A one-shot Passion delta applied the moment this config is installed
## (RunManager.apply_realm_config). Zero for the neutral + Court/Folk entry configs;
## the mid-run Peasant's Plea event uses it to move Passion when it retunes the realm.
var passion_shift: int = 0


## One-line summary for logs / a future config-readout UI.
func describe() -> String:
	return "RealmConfig(diff x%.2f, shop x%.2f, elites x%.2f, rarity x%.2f, boon '%s', passion %+d)" % [
		enemy_difficulty_mult, shop_price_mult, elite_frequency_mult,
		reward_rarity_mult, map_boon, passion_shift]
