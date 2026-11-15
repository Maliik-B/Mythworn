extends Node
## Content linter: walks every registry and every cross-reference and fails loudly.
## Run: godot --headless --path . res://tools/content_linter.tscn --quit-after 600
##
## It runs beside roster_test at the close of every part. It is two steps. GATHER reads the
## registries (and the source text, for references that only exist as literals) into one plain
## "world" dictionary. The RULES are pure functions of that world, each returning the findings it
## sees. Because a rule never touches the engine, the SELF-TEST can hand each one a copy of the
## world with one seeded bug and demand that it notices: a class of bug the linter has found gets
## a test here, and a rule that goes quiet is itself a failure.
##
## Exit code is the number of findings plus self-test failures, so a clean run is 0.

const SCAN_DIRS: Array[String] = ["res://scripts", "res://scenes"]
## Files whose literals are the definition of an id, not a use of it.
const DEFINITION_FILES: Array[String] = [
	"res://scripts/core/relic_pool.gd", "res://scripts/core/consumable_pool.gd",
	"res://scripts/core/pet_pool.gd", "res://scripts/core/title_pool.gd",
]
const EVENT_SCENE := "res://scenes/event/event_scene.gd"
const EVENT_POOL := "res://scripts/core/event_pool.gd"
const MAP_SEEDS := 60

## Findings the linter reports and the sheet records. Key = "<rule>: <finding>", value = why it
## stands. The two memory cards are authored (docs/CONTENT_AUDIT.md) but their sources, boss
## fights and a shop relic, are not built (memory-cards design: never the normal reward pool).
const KNOWN := {
	"memory cards have a source and card ids resolve: memory card 'everything_i_carried_out' is granted by no event choice":
		"authored, source not built yet; CONTENT_REVIEW_DECISIONS Part 4",
	"memory cards have a source and card ids resolve: memory card 'name_i_gave_myself' is granted by no event choice":
		"authored, source not built yet; CONTENT_REVIEW_DECISIONS Part 4",
}

var _findings: Array[String] = []
var _self_fails := 0


func _ready() -> void:
	AudioManager.enabled = false
	print("\n== Content linter ==")
	_setup_run_state()
	var world := _gather()
	var results := _run_rules(world)
	for rule in results:
		var found: Array = results[rule]
		print("  %s %s%s" % ["FAIL" if not found.is_empty() else "PASS", rule,
			"" if found.is_empty() else " (%d)" % found.size()])
		for f in found:
			print("      - %s" % f)
			_findings.append("%s: %s" % [rule, f])
	print("-- self-test: each rule must see its seeded bug --")
	_self_test(world)
	# Known findings: real, recorded in the sheet, and not this part's to fix. They print, they do
	# not fail the run, and one that stops occurring fails it as stale so the list cannot rot.
	var live: Array[String] = []
	var known_seen := {}
	for f in _findings:
		if KNOWN.has(f):
			known_seen[f] = true
			print("  KNOWN %s\n        (%s)" % [f, KNOWN[f]])
		else:
			live.append(f)
	var stale := 0
	for k in KNOWN:
		if not known_seen.has(k):
			print("  FAIL stale known finding, it no longer occurs: %s" % k)
			stale += 1
	var total := live.size() + stale + _self_fails
	print("== %s ==\n" % ("LINT CLEAN (%d known)" % known_seen.size() if total == 0 \
		else "%d FINDING(S)" % total))
	get_tree().quit(mini(total, 125))


func _setup_run_state() -> void:
	var ch := CharacterData.new()
	ch.character_name = "Lint"
	ch.max_health = 80
	ch.passion_volatility = 1.0
	ch.passion_thresholds.assign([50, 18, -18, -50])
	ch.primary_personality = "Water"
	ch.secondary_personality = "Physical"
	RunManager.current_character = ch
	RunManager.current_act = 1
	RunManager.passion = PassionState.new()
	RunManager.passion.current_value = 0
	RunManager.relics.clear()


# ============================================================
# GATHER
# ============================================================

func _gather() -> Dictionary:
	var w := {}
	var texts := _read_sources()
	w["texts"] = texts

	# --- titles ---
	var title_ids: Array = []
	for t in TitlePool.get_all_titles():
		title_ids.append(String(t.title_id))
	w["titles"] = title_ids

	# --- events: the pool, the special builders, and the record sites with a relic carried ---
	var events: Array = []
	for e in EventPool._build_pool():
		events.append(_event_record("pool:" + e.event_name, e))
	var special_ids := _special_event_ids(texts.get(EVENT_SCENE, ""))
	w["special_ids"] = special_ids
	var scene_script: GDScript = load(EVENT_SCENE)
	var scene = scene_script.new()
	for id in special_ids:
		var ev: EventData = scene._build_special_event(StringName(id))
		events.append(_event_record("special:" + id, ev))
	scene.free()
	# Record sites build one waking option per dormant relic CARRIED, so carry each in turn.
	var wake_options: Dictionary = {}  # dormant name -> [site names that offered a wake option]
	for name in RelicPool.dormant_names():
		RunManager.relics.clear()
		var dormant := RelicPool.get_relic_by_name(name)
		RunManager.relics.append(dormant)
		var sites: Array = []
		# The Reliquary wakes at its close: the chapel stage, reached by the chain.
		scene = scene_script.new()
		var chapel: EventData = scene._build_special_event(&"reliquary_struck")
		scene.free()
		for pair in [["scriptorium", EventPool._scriptorium()], ["tourney", EventPool._the_tourney()],
				["reliquary", chapel]]:
			for c in pair[1].choices:
				if String(c.wakes_relic) == name:
					sites.append(pair[0])
		wake_options[name] = sites
		var woke := RunManager.wake_relic_by_name(name)
		wake_options[name + "|woke"] = woke.relic_name if woke else ""
	RunManager.relics.clear()
	w["events"] = events
	w["wake_options"] = wake_options
	w["pool_event_funcs"] = _regex_all(texts.get(EVENT_POOL, ""),
		"static func (_\\w+)\\(\\) -> EventData", 1)
	w["pool_event_appended"] = _regex_all(texts.get(EVENT_POOL, ""), "pool\\.append\\((_\\w+)\\(\\)\\)", 1)
	var scene_text: String = texts.get(EVENT_SCENE, "")
	w["pool_event_scene_calls"] = _regex_all(scene_text, "EventPool\\.(_\\w+)\\(", 1)

	# --- references to special event ids written as literals ---
	var refs: Array = []  # [kind, id, where]
	for path in texts:
		var t: String = texts[path]
		for kind in ["pending_special_event = ", "next_event_id = ", "scripted_event_id = ",
				"MASTER_OF_GAME_ID := "]:
			for id in _regex_all(t, kind.replace("(", "\\(") + "&\"(\\w+)\"", 1):
				refs.append([kind.strip_edges(), id, path])
		for id in _regex_all(t, "scripted_event_schedule\\[\\w+\\] = &\"(\\w+)\"", 1):
			refs.append(["scripted_event_schedule", id, path])
		for id in _regex_all(t, "RECORD_SITE_IDS[^=]*= \\[([^\\]]*)\\]", 1):
			for m in _regex_all(id, "&\"(\\w+)\"", 1):
				refs.append(["RECORD_SITE_IDS", m, path])
	w["special_refs"] = refs
	# Every special id's literal uses outside the match arm that builds it.
	var uses: Dictionary = {}
	for id in special_ids:
		uses[id] = 0
	for path in texts:
		var t2: String = texts[path]
		if path == EVENT_SCENE:
			t2 = _without_span(t2, "func _build_special_event(", "\nfunc ", "\n\nfunc ")
		for id in special_ids:
			uses[id] += t2.count("&\"%s\"" % id)
	w["special_uses"] = uses

	# --- combat keys and boons ---
	w["combat_keys_known"] = _match_arms(scene_text, "func _start_event_combat(")
	w["boons_known"] = _match_arms(texts.get("res://scripts/core/combat_engine.gd", ""),
		"func _apply_pending_combat_boon(")

	# --- relics ---
	var relics: Array = []
	for r in RelicPool._build_pool():
		relics.append(_relic_record(r, "reward"))
	for r in RelicPool._build_quest_pool():
		relics.append(_relic_record(r, "quest"))
	for r in RelicPool._build_bram_pool():
		relics.append(_relic_record(r, "bram"))
	for r in RelicPool._build_neve_pool():
		relics.append(_relic_record(r, "neve"))
	for r in RelicPool._build_woken_pool():
		relics.append(_relic_record(r, "woken"))
	w["relics"] = relics

	# --- consumables ---
	var cons: Dictionary = {}
	for id in ConsumablePool.all_ids():
		var c := ConsumablePool.get_consumable(id)
		if c != null:
			cons[String(id)] = {"price": c.price, "quest_id": String(c.quest_id),
				"id_matches": c.id == id, "text": [c.display_name, c.description, c.flavor]}
		else:
			cons[String(id)] = {"missing": true}
	w["consumables"] = cons
	w["consumable_arms"] = _match_arms(texts.get("res://scripts/core/consumable_pool.gd", ""),
		"static func get_consumable(")
	w["consumable_literals"] = _consumable_literals(texts)
	var shop_ids: Array = []
	for realm in [&"camelot", &"yggdrasil", &"journey_to_the_west"]:
		for id in ConsumablePool.shop_candidates(realm):
			if not shop_ids.has(String(id)):
				shop_ids.append(String(id))
	w["shop_consumables"] = shop_ids

	# --- pets ---
	var pets: Dictionary = {}
	for id in PetPool.all_ids():
		var p := PetPool.get_pet(id)
		var deck := PetPool.build_cards(id)
		var all_trick := true
		for c in deck:
			if not c.trick:
				all_trick = false
		pets[String(id)] = {"found": p != null, "deck": deck.size(), "all_trick": all_trick}
	w["pets"] = pets

	# --- cards ---
	var pools: Dictionary = {
		"generic": CardPool._build_generic_pool(),
		"emo_primary": CardPool.build_emo_primary_pool(),
		"emo_secondary": CardPool.build_emo_secondary_pool(),
		"memory": CardPool.build_memory_cards(),
		"hound": CardPool.build_hound_cards(),
		"hawk": CardPool.build_hawk_cards(),
		"ferret": CardPool.build_ferret_cards(),
	}
	var card_names: Dictionary = {}
	for pool_name in pools:
		var names: Array = []
		for c in pools[pool_name]:
			names.append(c.card_name)
		card_names[pool_name] = names
	w["card_names"] = card_names
	var memory_ids: Array = []
	for id in [&"house_that_was", &"everything_i_carried_out", &"name_i_gave_myself"]:
		memory_ids.append(String(id))
	w["memory_ids"] = memory_ids
	w["memory_arms"] = _match_arms(texts.get("res://scripts/core/card_pool.gd", ""),
		"static func get_memory_card(")
	w["curse_arms"] = _match_arms(texts.get("res://scripts/core/card_pool.gd", ""),
		"static func get_curse_card(")
	w["card_build_arms"] = _match_arms(texts.get("res://scripts/core/card_pool.gd", ""),
		"static func build_card(")
	# Every AddCardEffect on every card and every enemy move must name a card that exists.
	var add_effects: Array = []
	for pool_name in pools:
		for c in pools[pool_name]:
			for e in c.get_active_effects():
				if e is AddCardEffect:
					add_effects.append(_add_effect_record("card:" + c.card_name, e))
	for en in _all_enemies():
		var moves: Array = en.moves.duplicate()
		for ms in en.phase_movesets:
			moves.append_array(ms)
		for m in moves:
			for e in m.effects:
				if e is AddCardEffect:
					add_effects.append(_add_effect_record("enemy:%s/%s" % [en.enemy_name, m.move_name], e))
	w["add_effects"] = add_effects

	# --- quests ---
	w["quests_completed"] = _regex_all_texts(texts, "complete_quest\\(&\"(\\w+)\"\\)")
	w["quests_armed_literal"] = _regex_all_texts(texts, "arm_quest\\(&\"(\\w+)\"\\)")
	w["title_awards_literal"] = _regex_all_texts(texts, "award_title\\(&\"(\\w+)\"\\)")

	# --- maps ---
	w["maps"] = _map_survey()
	w["node_looks"] = _node_looks(w["maps"])

	# --- authored text (em dashes) ---
	w["strings"] = _authored_strings(events, relics, cons, pets)
	return w


func _read_sources() -> Dictionary:
	var out := {}
	for dir in SCAN_DIRS:
		_read_dir(dir, out)
	return out


func _read_dir(dir: String, out: Dictionary) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out[dir + "/" + f] = FileAccess.get_file_as_string(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_read_dir(dir + "/" + d, out)


func _regex_all(text: String, pattern: String, group: int) -> Array:
	var re := RegEx.new()
	re.compile(pattern)
	var out: Array = []
	for m in re.search_all(text):
		out.append(m.get_string(group))
	return out


func _regex_all_texts(texts: Dictionary, pattern: String) -> Array:
	var out: Array = []
	for path in texts:
		for id in _regex_all(texts[path], pattern, 1):
			if not out.has(id):
				out.append(id)
	return out


## The text of source with the span from `start` to the next top-level func removed.
func _without_span(source: String, start: String, _end_a: String, _end_b: String) -> String:
	var i := source.find(start)
	if i < 0:
		return source
	var j := source.find("\nfunc ", i + start.length())
	if j < 0:
		j = source.length()
	return source.substr(0, i) + source.substr(j)


## The ids on the arms of the first match statement in the named function: `\t\t&"x":` lines.
func _match_arms(source: String, func_start: String) -> Array:
	var i := source.find(func_start)
	if i < 0:
		return []
	var j := source.find("\nfunc ", i + func_start.length())
	var k := source.find("\nstatic func ", i + func_start.length())
	if j < 0 or (k >= 0 and k < j):
		j = k
	if j < 0:
		j = source.length()
	var body := source.substr(i, j - i)
	var out: Array = []
	for id in _regex_all(body, "(?m)^\\t+&\"(\\w+)\":", 1):
		out.append(id)
	return out


func _special_event_ids(scene_text: String) -> Array:
	return _match_arms(scene_text, "func _build_special_event(")


func _consumable_literals(texts: Dictionary) -> Array:
	var out: Array = []
	for path in texts:
		if path in DEFINITION_FILES:
			continue
		for id in _regex_all(texts[path], "get_consumable\\(&\"(\\w+)\"\\)", 1):
			out.append(id)
		for id in _regex_all(texts[path], "(?:grants|requires|spends)_consumable = &\"(\\w+)\"", 1):
			out.append(id)
	return out


func _event_record(source: String, e: EventData) -> Dictionary:
	var choices: Array = []
	for c in e.choices:
		choices.append({
			"text": c.text, "result": c.result_text,
			"title": String(c.awarded_title_id), "relic": String(c.granted_relic_id),
			"card": String(c.granted_card_id), "curse": String(c.grants_curse),
			"cons_grant": String(c.grants_consumable), "cons_need": String(c.requires_consumable),
			"cons_spend": String(c.spends_consumable), "pet": String(c.grants_pet),
			"next": String(c.next_event_id), "quest": String(c.arms_quest),
			"combat": String(c.starts_combat), "boon": String(c.grants_combat_boon),
			"wakes": String(c.wakes_relic), "needs_relic": String(c.requires_relic),
			"favor": String(c.requires_favor), "school": String(c.card_reward_school),
			"liaison": String(c.grants_liaison_relic),
			"win": c.gamble_win_text, "lose": c.gamble_lose_text,
		})
	return {"source": source, "name": e.event_name, "description": e.description, "choices": choices}


func _relic_record(r: RelicData, pool: String) -> Dictionary:
	return {"name": r.relic_name, "pool": pool, "wakes_into": String(r.wakes_into),
		"woken_from": String(r.woken_from), "text": [r.description, r.wake_line]}


func _add_effect_record(where: String, e: AddCardEffect) -> Dictionary:
	var resolves := false
	if e.card_id != &"":
		resolves = CardPool.build_card(e.card_id) != null
	else:
		resolves = e.card_to_add != null
	return {"where": where, "resolves": resolves}


func _all_enemies() -> Array:
	var out: Array = []
	for i in 6:
		out.append_array(EnemyPool.get_combat_encounter(i))
	for i in 4:
		out.append_array(EnemyPool.get_elite_encounter())
	out.append_array(EnemyPool.get_boss())
	return out


## Generates act-1 Camelot maps and records where the seated nodes landed. The crossing is switched
## off in the game; the survey turns it on, so the seat is still held to its rule for when it is on.
func _map_survey() -> Dictionary:
	var survey := {"count": 0, "raider_pairs_ok": 0, "huntsman_ok": 0, "record_ok": 0, "crossing_ok": 0,
		"seated_ids": [], "doubled": 0, "bad": []}
	var switch_was: bool = MapGenerator.crossing_enabled
	MapGenerator.crossing_enabled = true
	for s in MAP_SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + s
		var map := MapGenerator.generate(rng, &"camelot", 1)
		survey["count"] += 1
		var giver := -1
		var payoff := -1
		var hunt := -1
		var rec := -1
		var crossings: Array[MapNode] = []
		for id in map.nodes:
			var n: MapNode = map.nodes[id]
			if n.crossing_to != &"":
				crossings.append(n)
			if n.quest_giver_id == MapGenerator.QUEST_ID:
				giver = id
			if n.quest_payoff_id == MapGenerator.QUEST_ID:
				payoff = id
			if n.scripted_event_id != &"":
				if not survey["seated_ids"].has(String(n.scripted_event_id)):
					survey["seated_ids"].append(String(n.scripted_event_id))
				if n.scripted_event_id == MapGenerator.MASTER_OF_GAME_ID:
					hunt = id
				elif n.scripted_event_id in MapGenerator.RECORD_SITE_IDS:
					rec = id
				var roles := 0
				if n.quest_giver_id != &"": roles += 1
				if n.quest_payoff_id != &"": roles += 1
				if roles > 0:
					survey["doubled"] += 1
		if giver >= 0 and payoff >= 0 and MapGenerator._reachable_from(map, giver).has(payoff):
			survey["raider_pairs_ok"] += 1
		else:
			survey["bad"].append("seed %d: no reachable raider giver and payoff" % (1000 + s))
		if hunt >= 0 and map.nodes[hunt].floor_num >= MapGenerator.HUNTSMAN_MIN_FLOOR \
				and map.nodes[hunt].floor_num <= MapGenerator.HUNTSMAN_MAX_FLOOR:
			survey["huntsman_ok"] += 1
		else:
			survey["bad"].append("seed %d: the huntsman is not seated mid-act" % (1000 + s))
		if rec >= 0 and map.nodes[rec].floor_num >= MapGenerator.RECORD_SITE_MIN_FLOOR \
				and map.nodes[rec].floor_num <= MapGenerator.RECORD_SITE_MAX_FLOOR:
			survey["record_ok"] += 1
		else:
			survey["bad"].append("seed %d: no record site seated late" % (1000 + s))
		if crossings.size() == 1 and crossings[0].floor_num >= MapGenerator.CROSSING_MIN_FLOOR \
				and crossings[0].floor_num <= MapGenerator.CROSSING_MAX_FLOOR \
				and crossings[0].quest_giver_id == &"" and crossings[0].quest_payoff_id == &"" \
				and crossings[0].scripted_event_id == &"":
			survey["crossing_ok"] += 1
		else:
			survey["bad"].append("seed %d: not exactly one crossing, on its floors, on a free node" % (1000 + s))
	MapGenerator.crossing_enabled = switch_was
	return survey


## What the map shows for every node kind: each type, and each scripted event a map can seat. A
## scripted id with no look of its own reads as nameless here, though the map would paint it as a
## plain event, because that is the failure this catches.
func _node_looks(survey: Dictionary) -> Array:
	var out: Array = []
	for t in MapNode.NodeType.values():
		out.append(_look_record("type %s" % MapNode.NodeType.keys()[t], MapNode.TYPE_LOOKS.get(t, {})))
	var scripted: Array = [String(MapGenerator.MASTER_OF_GAME_ID)]
	for id in MapGenerator.RECORD_SITE_IDS:
		scripted.append(String(id))
	for id in survey["seated_ids"]:
		if not scripted.has(id):
			scripted.append(id)
	for id in scripted:
		out.append(_look_record("scripted %s" % id, MapNode.SCRIPTED_LOOKS.get(StringName(id), {})))
	# Each realm a crossing opens on, and the realm its way back leads home to.
	var crossing_ends: Array = RealmRoutes.CROSSING_CONFIGS.keys()
	crossing_ends.append(&"camelot")
	for id in crossing_ends:
		out.append(_look_record("crossing to %s" % id, MapNode.CROSSING_LOOKS.get(id, {})))
	out.append(_look_record("weakened elite", MapNode.WEAKENED_ELITE_LOOK))
	out.append(_look_record("quest mark", MapNode.QUEST_MARK_LOOK))
	return out


func _look_record(key: String, look: Dictionary) -> Dictionary:
	return {"key": key, "name": String(look.get("name", "")), "glyph": String(look.get("glyph", "")),
		"has_order": look.has("order"), "has_color": look.has("color"), "unnamed": look.get("unnamed", false)}


func _authored_strings(events: Array, relics: Array, cons: Dictionary, pets: Dictionary) -> Array:
	var out: Array = []  # [where, text]
	for e in events:
		out.append([e["source"] + " description", e["description"]])
		for c in e["choices"]:
			out.append([e["source"] + " choice", c["text"]])
			out.append([e["source"] + " result", c["result"]])
			out.append([e["source"] + " gamble", c["win"] + c["lose"]])
	for r in relics:
		for t in r["text"]:
			out.append(["relic " + r["name"], t])
	for id in cons:
		if cons[id].has("text"):
			for t in cons[id]["text"]:
				out.append(["consumable " + id, t])
	for t in TitlePool.get_all_titles():
		out.append(["title " + String(t.title_id), "%s %s %s %s %s %s" % [t.original_name,
			t.original_description, t.degraded_name, t.degraded_description, t.returning_name,
			t.returning_description]])
	for id in pets:
		var p := PetPool.get_pet(StringName(id))
		if p:
			out.append(["pet " + id, p.display_name + " " + p.description])
	for pool in [CardPool._build_generic_pool(), CardPool.build_emo_primary_pool(),
			CardPool.build_emo_secondary_pool(), CardPool.build_memory_cards(),
			CardPool.build_hound_cards(), CardPool.build_hawk_cards(), CardPool.build_ferret_cards()]:
		for c in pool:
			out.append(["card " + c.card_name, c.card_name + " " + c.description + " " + c.flavor_text])
	return out


# ============================================================
# RULES (pure functions of the world)
# ============================================================

func _run_rules(w: Dictionary) -> Dictionary:
	var out := {}
	out["titles are awarded by some code path"] = _rule_titles_awarded(w)
	out["every title id an event names exists"] = _rule_title_ids_exist(w)
	out["every relic id an event names exists"] = _rule_event_relics_exist(w)
	out["quest-only relics have a grant"] = _rule_quest_relics_granted(w)
	out["liaison relic pools are reachable"] = _rule_liaison_pools(w)
	out["wakes_into and woken_from name each other"] = _rule_wake_links(w)
	out["every dormant relic can be woken at every record site"] = _rule_wake_sites(w)
	out["event choices name cards, curses, consumables, pets that exist"] = _rule_choice_ids(w)
	out["event choices name combats, boons, quests, gates that exist"] = _rule_choice_keys(w)
	out["every pool event is rollable"] = _rule_pool_events_rollable(w)
	out["every special event is reachable"] = _rule_special_reachable(w)
	out["special event references name a real event"] = _rule_special_refs_resolve(w)
	out["seated map nodes name a real event and stay in place"] = _rule_map_seating(w)
	out["every map node kind has a name, glyph and colour for the legend"] = _rule_node_looks(w)
	out["consumables resolve and have a grant site"] = _rule_consumables(w)
	out["quest ids have a payoff"] = _rule_quests(w)
	out["pets resolve, have a deck of tricks and a grant site"] = _rule_pets(w)
	out["memory cards have a source and card ids resolve"] = _rule_cards(w)
	out["card names are unique across the pools that share a name space"] = _rule_card_names(w)
	out["authored text has no em dash"] = _rule_em_dash(w)
	return out


func _granted_titles(w: Dictionary) -> Array:
	var got: Array = w["title_awards_literal"].duplicate()
	for e in w["events"]:
		for c in e["choices"]:
			if c["title"] != "" and not got.has(c["title"]):
				got.append(c["title"])
	return got


func _rule_titles_awarded(w: Dictionary) -> Array:
	var out: Array = []
	var got := _granted_titles(w)
	for id in w["titles"]:
		if not got.has(id):
			out.append("title '%s' is awarded by no event and no award_title call" % id)
	return out


func _rule_title_ids_exist(w: Dictionary) -> Array:
	var out: Array = []
	for id in _granted_titles(w):
		if not w["titles"].has(id):
			out.append("an event or award_title names the unknown title '%s'" % id)
	return out


func _relic_names(w: Dictionary) -> Array:
	var names: Array = []
	for r in w["relics"]:
		names.append(r["name"])
	return names


func _rule_event_relics_exist(w: Dictionary) -> Array:
	var out: Array = []
	var names := _relic_names(w)
	for e in w["events"]:
		for c in e["choices"]:
			for k in ["relic", "needs_relic", "wakes"]:
				if c[k] != "" and not names.has(c[k]):
					out.append("%s names the unknown relic '%s' (%s)" % [e["source"], c[k], k])
	return out


func _rule_quest_relics_granted(w: Dictionary) -> Array:
	var out: Array = []
	for r in w["relics"]:
		if r["pool"] != "quest":
			continue
		var found := false
		for e in w["events"]:
			for c in e["choices"]:
				if c["relic"] == r["name"]:
					found = true
		if not found:
			for path in w["texts"]:
				if path in DEFINITION_FILES:
					continue
				var t: String = w["texts"][path]
				if t.contains("\"%s\"" % r["name"]) or t.contains("&\"%s\"" % r["name"]):
					found = true
					break
		if not found:
			out.append("quest relic '%s' is granted by no event and named by no script" % r["name"])
	return out


func _rule_liaison_pools(w: Dictionary) -> Array:
	var out: Array = []
	for liaison in ["bram", "neve"]:
		var pooled := 0
		for r in w["relics"]:
			if r["pool"] == liaison:
				pooled += 1
		var granted := false
		for e in w["events"]:
			for c in e["choices"]:
				if c["liaison"] == liaison:
					granted = true
		if pooled > 0 and not granted:
			out.append("the %s relic pool has %d relics and no event grants from it" % [liaison, pooled])
		if pooled == 0 and granted:
			out.append("an event grants from the empty %s pool" % liaison)
	return out


func _rule_wake_links(w: Dictionary) -> Array:
	var out: Array = []
	var by_name := {}
	for r in w["relics"]:
		by_name[r["name"]] = r
	for r in w["relics"]:
		if r["wakes_into"] != "":
			var other = by_name.get(r["wakes_into"])
			if other == null:
				out.append("'%s' wakes into '%s', which does not exist" % [r["name"], r["wakes_into"]])
			elif other["woken_from"] != r["name"]:
				out.append("'%s' wakes into '%s', which says it came from '%s'" % [
					r["name"], r["wakes_into"], other["woken_from"]])
			elif other["pool"] != "woken":
				out.append("'%s' is the woken form of '%s' but sits in the %s pool" % [
					other["name"], r["name"], other["pool"]])
			if r["pool"] != "reward":
				out.append("dormant '%s' is not in the reward pool, so it cannot be offered" % r["name"])
		if r["woken_from"] != "":
			var dormant = by_name.get(r["woken_from"])
			if dormant == null:
				out.append("'%s' is woken from '%s', which does not exist" % [r["name"], r["woken_from"]])
			elif dormant["wakes_into"] != r["name"]:
				out.append("'%s' says it woke from '%s', which wakes into '%s'" % [
					r["name"], r["woken_from"], dormant["wakes_into"]])
	return out


func _rule_wake_sites(w: Dictionary) -> Array:
	var out: Array = []
	for name in w["wake_options"]:
		if name.ends_with("|woke"):
			continue
		var sites: Array = w["wake_options"][name]
		for site in ["scriptorium", "tourney", "reliquary"]:
			if not sites.has(site):
				out.append("carrying '%s' the %s offers no waking option" % [name, site])
		var woke: String = w["wake_options"].get(name + "|woke", "")
		if woke == "":
			out.append("RunManager.wake_relic_by_name('%s') returns nothing" % name)
	return out


func _rule_choice_ids(w: Dictionary) -> Array:
	var out: Array = []
	for e in w["events"]:
		for c in e["choices"]:
			if c["card"] != "" and not w["memory_arms"].has(c["card"]):
				out.append("%s grants the unknown memory card '%s'" % [e["source"], c["card"]])
			if c["curse"] != "" and not w["curse_arms"].has(c["curse"]):
				out.append("%s grants the unknown curse '%s'" % [e["source"], c["curse"]])
			for k in ["cons_grant", "cons_need", "cons_spend"]:
				if c[k] != "" and not w["consumables"].has(c[k]):
					out.append("%s names the unknown consumable '%s' (%s)" % [e["source"], c[k], k])
			if c["pet"] != "" and not w["pets"].has(c["pet"]):
				out.append("%s grants the unknown pet '%s'" % [e["source"], c["pet"]])
	return out


func _rule_choice_keys(w: Dictionary) -> Array:
	var out: Array = []
	for e in w["events"]:
		for c in e["choices"]:
			if c["combat"] != "" and not w["combat_keys_known"].has(c["combat"]):
				out.append("%s starts the unknown combat '%s'" % [e["source"], c["combat"]])
			if c["boon"] != "" and not w["boons_known"].has(c["boon"]):
				out.append("%s grants the combat boon '%s', which the engine does not apply" % [
					e["source"], c["boon"]])
			if c["next"] != "" and not w["special_ids"].has(c["next"]):
				out.append("%s chains to the unknown event '%s'" % [e["source"], c["next"]])
			if c["quest"] != "" and not w["quests_completed"].has(c["quest"]):
				out.append("%s arms the quest '%s', which nothing completes" % [e["source"], c["quest"]])
			if c["favor"] != "" and not (c["favor"] in ["folk", "court"]):
				out.append("%s gates on the unknown favor '%s'" % [e["source"], c["favor"]])
			if c["school"] != "" and not (c["school"] in ["primary", "secondary"]):
				out.append("%s rewards the unknown school '%s'" % [e["source"], c["school"]])
			if c["liaison"] != "" and not (c["liaison"] in ["bram", "neve"]):
				out.append("%s grants from the unknown liaison '%s'" % [e["source"], c["liaison"]])
		if e["choices"].is_empty():
			out.append("%s has no choices" % e["source"])
		for c in e["choices"]:
			if String(c["text"]).strip_edges() == "":
				out.append("%s has a choice with no text" % e["source"])
	return out


func _rule_pool_events_rollable(w: Dictionary) -> Array:
	var out: Array = []
	for f in w["pool_event_funcs"]:
		if not w["pool_event_appended"].has(f) and not w["pool_event_scene_calls"].has(f):
			out.append("%s builds an event that the pool never appends and no special event calls" % f)
	return out


func _rule_special_reachable(w: Dictionary) -> Array:
	var out: Array = []
	var seated: Array = w["maps"]["seated_ids"]
	for id in w["special_ids"]:
		if w["special_uses"].get(id, 0) <= 0 and not seated.has(id):
			out.append("special event '%s' is built but nothing routes to it" % id)
	return out


func _rule_special_refs_resolve(w: Dictionary) -> Array:
	var out: Array = []
	for ref in w["special_refs"]:
		if not w["special_ids"].has(ref[1]):
			out.append("%s names '%s' in %s, which _build_special_event does not build" % [
				ref[0], ref[1], String(ref[2]).get_file()])
	return out


func _rule_map_seating(w: Dictionary) -> Array:
	var out: Array = []
	var m: Dictionary = w["maps"]
	for b in m["bad"]:
		out.append(b)
	for id in m["seated_ids"]:
		if not w["special_ids"].has(id):
			out.append("a map seats '%s', which _build_special_event does not build" % id)
	if m["doubled"] > 0:
		out.append("%d seated scripted nodes also carry a quest role" % m["doubled"])
	if m["count"] == 0:
		out.append("no maps were generated")
	return out


func _rule_node_looks(w: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for r in w["node_looks"]:
		# Only a kind that says so may go without a name (a crossing); it still needs its glyph.
		if r["name"].strip_edges() == "":
			if not r.get("unnamed", false):
				out.append("%s has no name" % r["key"])
		elif seen.has(r["name"]):
			out.append("%s shares the name '%s' with %s, and the legend would merge them" % [r["key"], r["name"], seen[r["name"]]])
		else:
			seen[r["name"]] = r["key"]
		if r["glyph"].strip_edges() == "":
			out.append("%s has no glyph" % r["key"])
		if not r["has_color"] or not r["has_order"]:
			out.append("%s has no colour or legend order" % r["key"])
	return out


func _rule_consumables(w: Dictionary) -> Array:
	var out: Array = []
	var cons: Dictionary = w["consumables"]
	for id in cons:
		if cons[id].has("missing"):
			out.append("all_ids lists '%s' but get_consumable builds nothing for it" % id)
			continue
		if not cons[id]["id_matches"]:
			out.append("get_consumable('%s') builds an item with a different id" % id)
		if not w["consumable_arms"].has(id):
			out.append("'%s' has no arm in get_consumable" % id)
		var granted: bool = w["shop_consumables"].has(id) or w["consumable_literals"].has(id)
		for e in w["events"]:
			for c in e["choices"]:
				if c["cons_grant"] == id:
					granted = true
		if not granted:
			out.append("consumable '%s' is granted by no event, sold by no shop and named by no script" % id)
	for id in w["consumable_arms"]:
		if not cons.has(id):
			out.append("get_consumable builds '%s' but all_ids does not list it" % id)
	for id in w["consumable_literals"]:
		if not cons.has(id):
			out.append("a script names the unknown consumable '%s'" % id)
	return out


func _rule_quests(w: Dictionary) -> Array:
	var out: Array = []
	var armed: Array = w["quests_armed_literal"].duplicate()
	for e in w["events"]:
		for c in e["choices"]:
			if c["quest"] != "" and not armed.has(c["quest"]):
				armed.append(c["quest"])
	for q in armed:
		if not w["quests_completed"].has(q):
			out.append("quest '%s' is armed and nothing completes it" % q)
	for id in w["consumables"]:
		var qid: String = w["consumables"][id].get("quest_id", "")
		if qid != "" and not armed.has(qid):
			out.append("consumable '%s' belongs to the quest '%s', which no event arms" % [id, qid])
		if qid != "" and not w["quests_completed"].has(qid):
			out.append("consumable '%s' belongs to the quest '%s', which nothing completes" % [id, qid])
	return out


func _rule_pets(w: Dictionary) -> Array:
	var out: Array = []
	for id in w["pets"]:
		var p: Dictionary = w["pets"][id]
		if not p["found"]:
			out.append("pet '%s' is listed but get_pet builds nothing" % id)
		if p["deck"] == 0:
			out.append("pet '%s' has an empty deck" % id)
		if not p["all_trick"]:
			out.append("pet '%s' has a card that is not a Trick" % id)
		var granted := false
		for e in w["events"]:
			for c in e["choices"]:
				if c["pet"] == id:
					granted = true
		if not granted:
			out.append("pet '%s' is granted by no event choice" % id)
	return out


func _rule_cards(w: Dictionary) -> Array:
	var out: Array = []
	for id in w["memory_ids"]:
		if not w["memory_arms"].has(id):
			out.append("memory card '%s' has no arm in get_memory_card" % id)
		var granted := false
		for e in w["events"]:
			for c in e["choices"]:
				if c["card"] == id:
					granted = true
		if not granted:
			out.append("memory card '%s' is granted by no event choice" % id)
	for a in w["memory_arms"]:
		if not w["memory_ids"].has(a):
			out.append("get_memory_card builds '%s', which build_memory_cards does not list" % a)
	for fx in w["add_effects"]:
		if not fx["resolves"]:
			out.append("%s adds a card that does not exist" % fx["where"])
	return out


func _rule_card_names(w: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for pool_name in w["card_names"]:
		var names: Array = w["card_names"][pool_name]
		var within := {}
		for n in names:
			if within.has(n):
				out.append("'%s' appears twice in the %s pool" % [n, pool_name])
			within[n] = true
			# Pet decks are their own space; the shared one is the draftable pools plus memory.
			if pool_name in ["generic", "emo_primary", "emo_secondary", "memory"]:
				if seen.has(n) and seen[n] != pool_name:
					out.append("'%s' is in both the %s and %s pools" % [n, seen[n], pool_name])
				seen[n] = pool_name
	return out


func _rule_em_dash(w: Dictionary) -> Array:
	var out: Array = []
	for pair in w["strings"]:
		if String(pair[1]).contains(String.chr(0x2014)):
			out.append("%s carries an em dash" % pair[0])
	return out


# ============================================================
# SELF-TEST: one seeded bug per rule
# ============================================================

func _self_test(w: Dictionary) -> void:
	var baseline := _run_rules(w)
	var cases: Array = [
		["titles are awarded by some code path", func(x):
			x["titles"].append("never_awarded")],
		["every title id an event names exists", func(x):
			x["title_awards_literal"].append("no_such_title")],
		["every relic id an event names exists", func(x):
			x["events"].append({"source": "seed", "name": "s", "description": "", "choices": [
				_blank_choice({"relic": "No Such Relic"})]})],
		["quest-only relics have a grant", func(x):
			x["relics"].append({"name": "Zzz Unmentioned Relic", "pool": "quest",
				"wakes_into": "", "woken_from": "", "text": []})],
		["liaison relic pools are reachable", func(x):
			for e in x["events"]:
				for c in e["choices"]:
					if c["liaison"] == "bram":
						c["liaison"] = ""],
		["wakes_into and woken_from name each other", func(x):
			for r in x["relics"]:
				if r["woken_from"] != "":
					r["woken_from"] = "Somebody Else"
					break],
		["every dormant relic can be woken at every record site", func(x):
			for k in x["wake_options"]:
				if not k.ends_with("|woke"):
					x["wake_options"][k] = []
					break],
		["event choices name cards, curses, consumables, pets that exist", func(x):
			x["events"].append({"source": "seed", "name": "s", "description": "", "choices": [
				_blank_choice({"pet": "unicorn"})]})],
		["event choices name combats, boons, quests, gates that exist", func(x):
			x["events"].append({"source": "seed", "name": "s", "description": "", "choices": [
				_blank_choice({"combat": "no_such_fight"})]})],
		["every pool event is rollable", func(x):
			x["pool_event_funcs"].append("_orphan_event")],
		["every special event is reachable", func(x):
			x["special_ids"].append("orphan_beat")
			x["special_uses"]["orphan_beat"] = 0],
		["special event references name a real event", func(x):
			x["special_refs"].append(["pending_special_event", "typo_beat", "res://x.gd"])],
		["seated map nodes name a real event and stay in place", func(x):
			x["maps"]["bad"].append("seeded")],
		["every map node kind has a name, glyph and colour for the legend", func(x):
			x["node_looks"].append({"key": "seed", "name": "", "glyph": "?", "has_order": true, "has_color": true})],
		["consumables resolve and have a grant site", func(x):
			x["consumables"]["orphan_tonic"] = {"price": 0, "quest_id": "", "id_matches": true, "text": []}
			x["consumable_arms"].append("orphan_tonic")],
		["quest ids have a payoff", func(x):
			x["quests_armed_literal"].append("never_completed")],
		["pets resolve, have a deck of tricks and a grant site", func(x):
			x["pets"]["ghost"] = {"found": true, "deck": 3, "all_trick": true}],
		["memory cards have a source and card ids resolve", func(x):
			x["add_effects"].append({"where": "seed", "resolves": false})],
		["card names are unique across the pools that share a name space", func(x):
			x["card_names"]["generic"].append(x["card_names"]["emo_primary"][0])],
		["authored text has no em dash", func(x):
			x["strings"].append(["seed", "a line %s with a dash" % String.chr(0x2014)])],
	]
	for case in cases:
		var rule: String = case[0]
		if not baseline.has(rule):
			print("  FAIL self-test names no such rule: %s" % rule)
			_self_fails += 1
			continue
		var mutated := _deep(w)
		case[1].call(mutated)
		var found: Array = _run_rules(mutated)[rule]
		var base_count: int = baseline[rule].size()
		var ok: bool = found.size() > base_count
		print("  %s sees its seeded bug: %s" % ["PASS" if ok else "FAIL", rule])
		if not ok:
			_self_fails += 1


func _blank_choice(over: Dictionary) -> Dictionary:
	var c := {"text": "x", "result": "", "title": "", "relic": "", "card": "", "curse": "",
		"cons_grant": "", "cons_need": "", "cons_spend": "", "pet": "", "next": "", "quest": "",
		"combat": "", "boon": "", "wakes": "", "needs_relic": "", "favor": "", "school": "",
		"liaison": "", "win": "", "lose": ""}
	for k in over:
		c[k] = over[k]
	return c


## A deep copy of the world, minus the source texts (large, and no rule's seeded bug needs them
## copied: they are shared by reference).
func _deep(w: Dictionary) -> Dictionary:
	var texts = w["texts"]
	var c := {}
	for k in w:
		if k == "texts":
			continue
		c[k] = _deep_value(w[k])
	c["texts"] = texts
	return c


func _deep_value(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _deep_value(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_deep_value(x))
		return a
	return v
