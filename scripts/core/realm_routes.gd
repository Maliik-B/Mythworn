class_name RealmRoutes
## How a realm's content is looked up: by (realm_id, config_id). EnemyPool and EventPool each hold a
## table keyed that way, so another config of any kind costs a row in each, not a system.
##
## config_id lives on RealmConfig.route_id and says which content a config draws from, nothing else.
## Camelot's two pledges change knobs and share the one route. A realm with a row and nothing in it
## is a realm whose content has not landed: asking it for an encounter or an event is a loud error
## and an empty answer, never another realm's content.

## A realm's first config.
const BASE := &"base"

## STAND-IN, so the crossing runs end to end while the real picks land: Yggdrasil's far side, served
## with Camelot's own enemies and no events. Only RunManager.cross_to installs it. When the first
## config lands, point CROSSING_CONFIGS at it and delete this row from both pools.
const STANDIN_EDGE := &"standin_edge"

## The realm a crossing opens on -> the config its far side runs on.
const CROSSING_CONFIGS := {
	&"yggdrasil": STANDIN_EDGE,
}


## The key both pools match on.
static func key(realm_id: StringName, config_id: StringName) -> String:
	return "%s/%s" % [realm_id, config_id]


## The route the run is standing on right now.
static func current_key() -> String:
	return key(RunManager.current_realm_id, RunManager.realm_config.route_id)
