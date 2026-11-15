class_name RealmConfig
extends RefCounted
## Per-run realm-shape knobs, set by the realm-entry VN choice (Camelot Act 1: court vs
## common folk) and read at the consumption points before/during map navigation. Neutral
## by default, so a run with no realm config plays exactly as before. This is the A2
## "realm configuration" system: the VN determines the STATE of the realm before you
## navigate it. See docs/GAME_DESIGN.md § Realms and docs/REALM_CAMELOT.md.
##
## NOTE: the Fable liaison "gift" (Bram's briefing / Neve's supplies) is a SEPARATE
## run-start boon, not one of these knobs; see RunManager's pending-gift handling.

## The config half of the (realm, config) key the content pools look up (RealmRoutes). It picks the
## content; every knob below only tunes it, which is why Camelot's two pledges share one route.
var route_id: StringName = RealmRoutes.BASE

## Enemy stat multiplier applied to every encounter this run
## (threaded into EnemyPool.get_*_encounter's difficulty_mult).
var enemy_difficulty_mult: float = 1.0

## Multiplier on shop card + relic base prices (shop_scene).
var shop_price_mult: float = 1.0

## Drives the pledge's ELITE-node transform in MapGenerator: > 1 converts a few combat
## nodes into NEW elites (Court = more risk + more reward), recorded so the map can show
## exactly which nodes changed. 1.0 = no added elites.
var elite_frequency_mult: float = 1.0

## Folk pledge: weaken the realm's existing elites in place rather than removing them, so
## the player keeps their rewards but the fights are easier (a Weak + power nerf, applied at
## the encounter). MapGenerator flags the elite nodes; the node shows a "weakened" badge.
var elite_weaken: bool = false

## Reward rarity bias: > 1 shifts card/relic reward rolls toward higher rarities.
## FIELDED: wired at the reward-draft consumption point in a later A2 increment.
var reward_rarity_mult: float = 1.0

## A one-time run-start realm boon keyed by id (empty = none), resolved when the realm
## map first opens. Applied via RunManager.consume_map_boon (queued from apply_realm_config).
var map_boon: StringName = &""

## A one-shot Passion delta applied the moment this config is installed
## (RunManager.apply_realm_config). Zero for the neutral + Court/Folk entry configs;
## the mid-run Peasant's Plea event uses it to move Passion when it retunes the realm.
var passion_shift: int = 0

## The realm's court<->folk standing the pledge plants you at (RunManager.realm_standing):
## positive = the people's favor, negative = the court's favor. The Court pledge sets this
## negative and the Folk pledge positive, enough to clear RunManager.FAVOR_THRESHOLD so the
## pledged side's favor-gated event options unlock from the start. Zero = no change (neutral
## configs + mid-run retunes leave standing alone). Applied in RunManager.apply_realm_config.
var standing_init: int = 0


## One-line summary for logs / a future config-readout UI.
func describe() -> String:
	return "RealmConfig(diff x%.2f, shop x%.2f, elites x%.2f%s, rarity x%.2f, boon '%s', passion %+d, standing %+d)" % [
		enemy_difficulty_mult, shop_price_mult, elite_frequency_mult,
		" weakened" if elite_weaken else "", reward_rarity_mult, map_boon, passion_shift, standing_init]
