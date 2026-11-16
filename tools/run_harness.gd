extends Node
## Run-layer balance harness: the whole-run companion to combat_harness.
##
## Walks a representative Act-1 node sequence with the REAL systems: EnemyPool encounters, the
## shared HarnessCombat policy over the real CombatEngine, CardPool reward drafting, EventPool and
## the event scene's own builders, ConsumablePool shop stock, and RunManager state (HP / gold /
## Passion / deck / pack / companion / titles) PERSISTING across nodes exactly as in a real run.
## Non-combat nodes are resolved by decision policies operating on the real pools, not by clicking UI.
##
## The layout carries the two seated nodes of the shipped Camelot act-1 map: the huntsman mid-act
## (the Master of Game, a companion at 75 gold) and a record site late (the Scriptorium, the Tourney
## or the Reliquary, drawn per run), so a forgotten relic found early is woken before the boss.
##
## It answers the questions the playtest raised: does a demo run traverse the Passion tiers, arrive
## at the boss committed and at a sane HP, and actually spend its gold? And now: what does a pet, a
## forgotten relic or a title add to a run, measured as the difference against the SAME seeds.
##
## Run headless (arguments after `--`):
##   godot --headless --path . res://tools/run_harness.tscn --quit-after 100000
##   --daily            seeds from today's UTC date (YYYYMMDD x 1000): the same for everyone that day
##   --seed=N           base seed by hand (default 0, comparable with the snapshots)
##   --runs=N           runs per batch (default 100)
##   --pet=PET          none | auto (default, buys at the huntsman) | hound | hawk | ferret (from floor 1)
##   --prefer=a,b,c     the order `auto` reaches for at the huntsman (default hound,hawk,ferret)
##   --relic=NAME       carry this relic from floor 1 (a dormant or a woken form)
##   --title=ID         wear this title from floor 1
##   --sweep=pets|forgotten|titles   a paired batch per variant on the same seeds, as differences
##
## MODEL of a Water-committing player (the shared planning policy); sets bands; playtest finalizes.

const MAX_TURNS := 60
const COMMIT_TARGET := 50
const EVENT_SCENE := "res://scenes/event/event_scene.gd"

## A plausible Act-1 layout (StS-shaped): hallway fights, 2 elites, 2 events, 2 rests, 1 shop, the
## Sword-in-the-Stone guardian at centre, the huntsman mid-act, a record site late, 1 boss.
## Floor = index + 1 (drives encounter scaling + the curated lone-Knight opener on floor 1).
const LAYOUT := [
	"combat", "combat", "event", "combat", "elite",
	"rest", "sword", "shop", "huntsman", "event", "combat",
	"elite", "record", "rest", "combat", "boss",
]

## Which special event follows a scripted event fight (event_scene._start_event_combat).
const FIGHT_FOLLOW_UP := {
	&"sword_guardian": &"sword_guardian_won", &"raider_band": &"raider_victory",
	&"raider_band_poisoned": &"raider_victory", &"chapel_beast": &"reliquary_won",
	&"barrow_warden": &"campfire_victory",
}

## Titles, best first, for the two slots: the harness wears the best it has earned.
const TITLE_PREFERENCE: Array[StringName] = [
	&"swords_bearer", &"the_unfading", &"the_compassionate", &"the_merciful", &"camelots_champion",
	&"king_of_camelot", &"peoples_champion", &"the_gracious", &"the_calculating",
	&"outlander_of_camelot",
]

var _cbt := HarnessCombat.new()
var _character: CharacterData
var _aborted := false  # set when a combat passes the memory ceiling
var _scene  # an event_scene script instance, used only for its special-event builders

var _runs := 100
var _seed_base := 0
var _daily_seed := 0
var _pet_mode := "auto"
var _prefer: Array = ["hound", "hawk", "ferret"]
var _force_relic := ""
var _force_title: StringName = &""
var _sweep := ""

# Per-run scratch, reset in _walk_run.
var _hp_lost_total := 0
var _consumables_used := 0
var _fights: Array = []   # per combat: {node, won, turns, lost, passion}
var _run_log: Array = []


func _ready() -> void:
	# No sound: every play() here would be kept until the run ends (see AudioManager.enabled).
	AudioManager.enabled = false
	_read_args()
	print("\n===============================================================")
	print(" Mythworn RUN harness: %d runs, real Act-1 walk (%d nodes)" % [_runs, LAYOUT.size()])
	print(" realm config: shipped   seeds: %d..%d%s   companion: %s%s%s" % [
		_seed_base, _seed_base + _runs - 1,
		"   (daily seed %d)" % _daily_seed if _daily_seed > 0 else "", _pet_mode,
		"   relic: %s" % _force_relic if _force_relic != "" else "",
		"   title: %s" % _force_title if _force_title != &"" else ""])
	print("===============================================================")
	_character = _build_emo_hybrid()
	var scene_script: GDScript = load(EVENT_SCENE)
	_scene = scene_script.new()

	if _sweep != "":
		_run_sweep()
	else:
		var agg := _batch(_pet_mode, _force_relic, _force_title)
		if not _aborted:
			_report(agg)
	_scene.free()
	if _aborted:
		print("\n== run harness ABORTED at the memory ceiling; no report ==\n")
		return
	print("\n  %s" % _cbt.memory_summary())
	print("\n== run harness done ==\n")
	get_tree().quit()


func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--daily":
			_daily_seed = HarnessCombat.daily_seed()
			_seed_base = _daily_seed * 1000
		elif a.begins_with("--seed="):
			_seed_base = int(a.substr(7))
		elif a.begins_with("--runs="):
			_runs = maxi(1, int(a.substr(7)))
		elif a.begins_with("--pet="):
			_pet_mode = a.substr(6)
		elif a.begins_with("--prefer="):
			_prefer = Array(a.substr(9).split(",", false))
		elif a.begins_with("--relic="):
			_force_relic = a.substr(8).replace("_", " ")
		elif a.begins_with("--title="):
			_force_title = StringName(a.substr(8))
		elif a.begins_with("--sweep="):
			_sweep = a.substr(8)


# ============================================================
# BATCHES AND SWEEPS
# ============================================================

## One batch of runs off the seed list with this setup. Returns the aggregate.
func _batch(pet_mode: String, relic: String, title: StringName) -> Dictionary:
	var agg := _fresh_agg()
	for r in _runs:
		_walk_run(_seed_base + r, agg, pet_mode, relic, title)
		if _aborted:
			return agg
	return agg


## A paired batch per variant, every one off the same seeds, shown as the difference from the
## variant-free batch. Pets are carried from floor 1; forgotten relics in both forms; titles worn
## from floor 1. A run that carried the thing all along, not one that happened to find it.
func _run_sweep() -> void:
	var variants: Array = []  # [label, pet_mode, relic, title]
	match _sweep:
		"pets":
			for id in PetPool.all_ids():
				variants.append([PetPool.get_pet(id).display_name, String(id), "", &""])
		"forgotten":
			for name in RelicPool.dormant_names():
				var d := RelicPool.get_relic_by_name(name)
				variants.append(["dormant: " + name, "none", name, &""])
				variants.append(["woken:   " + String(d.wakes_into), "none", String(d.wakes_into), &""])
		"titles":
			for t in TitlePool.get_all_titles():
				variants.append([String(t.title_id), "none", "", t.title_id])
		_:
			print("unknown sweep '%s' (pets | forgotten | titles)" % _sweep)
			return
	var base := _batch("none", "", &"")
	if _aborted:
		return
	print("\nSWEEP %s (same %d seeds; delta = with minus without; no companion in the baseline)" % [
		_sweep, _runs])
	print("  %-34s clear %5.1f%%  HP lost/run %5.1f  boss arrival HP %4.1f  end HP %4.1f  gold left %4.0f" % [
		"baseline (without)", _clear(base), _per(base, "hp_lost"), _boss_hp(base),
		_per(base, "end_hp"), _per(base, "gold_end")])
	for v in variants:
		var a := _batch(v[1], v[2], v[3])
		if _aborted:
			return
		print("  %-34s clear %+6.1f   HP lost/run %+6.1f  boss arrival HP %+5.1f  end HP %+5.1f  gold left %+5.0f" % [
			v[0], _clear(a) - _clear(base), _per(a, "hp_lost") - _per(base, "hp_lost"),
			_boss_hp(a) - _boss_hp(base), _per(a, "end_hp") - _per(base, "end_hp"),
			_per(a, "gold_end") - _per(base, "gold_end")])


func _clear(a: Dictionary) -> float:
	return 100.0 * a["wins"] / maxf(1.0, a["runs"])


func _per(a: Dictionary, key: String) -> float:
	return float(a[key]) / maxf(1.0, a["runs"])


func _boss_hp(a: Dictionary) -> float:
	return float(a["boss_hp_sum"]) / maxf(1.0, a["boss_hp_n"])


# ============================================================
# ONE RUN
# ============================================================

func _walk_run(seed_val: int, agg: Dictionary, pet_mode: String, relic: String, title: StringName) -> void:
	RunManager.start_run(_character, seed_val)
	_hp_lost_total = 0
	_consumables_used = 0
	_fights = []
	if pet_mode in ["hound", "hawk", "ferret"]:
		RunManager.set_pet(StringName(pet_mode))
	if relic != "":
		var forced := RelicPool.get_relic_by_name(relic)
		if forced:
			RunManager.add_relic(forced)
	if title != &"":
		RunManager.award_title(title)
		RunManager.equip_title(0, title)

	var tiers_seen := {}
	var min_p := 0
	var max_p := 0
	var died_floor := -1
	var boss_start_hp := -1
	var gold_spent := 0
	var passion_by_node: Array[int] = []
	var pet_at_boss := ""
	var forgotten_at_boss := 0
	var woken_at_boss := 0

	for i in LAYOUT.size():
		var node: String = LAYOUT[i]
		var floor_num := i + 1
		match node:
			"combat", "elite", "boss":
				if node == "boss":
					boss_start_hp = RunManager.current_hp
					pet_at_boss = String(RunManager.pet_id)
					for rel in RunManager.relics:
						if rel.is_dormant():
							forgotten_at_boss += 1
						elif rel.is_woken():
							woken_at_boss += 1
				var enemies := _encounter(node, floor_num)
				var res := _run_combat(enemies, i)
				if not res["won"]:
					died_floor = floor_num
				else:
					_award_gold(node, floor_num)
					if node == "elite" or node == "boss":
						_award_relic(node == "boss")  # StS: a relic per elite + boss
					if node != "boss":
						_draft_reward()
			"sword":
				# Sword-in-the-Stone: the event itself, through its own builder, taking the fight
				# (the guardian, then Excalibur and The Sword's Bearer in the follow-up beat).
				if not _resolve_event(_scene._build_special_event(&"sword_in_stone"), i, true):
					died_floor = floor_num
			"rest":
				_rest_action()
			"shop":
				gold_spent += _shop_action()
			"event":
				if not _resolve_event(EventPool.get_random_event(RngManager.event_rng), i, false):
					died_floor = floor_num
			"huntsman":
				if not _resolve_event(_scene._build_special_event(&"master_of_game"), i, false):
					died_floor = floor_num
			"record":
				var ids := MapGenerator.RECORD_SITE_IDS
				var site: StringName = ids[RngManager.event_rng.randi_range(0, ids.size() - 1)]
				if not _resolve_event(_scene._build_special_event(site), i, false):
					died_floor = floor_num
		_equip_best_titles()
		_use_map_heals()

		# Sample Passion after every node.
		var p := RunManager.passion.current_value
		passion_by_node.append(p)
		min_p = mini(min_p, p)
		max_p = maxi(max_p, p)
		tiers_seen[RunManager.get_passion_tier()] = true
		if died_floor >= 0 or _aborted:
			break

	# Fold this run into the aggregate.
	var reached_boss := died_floor < 0
	agg["runs"] += 1
	agg["wins"] += 1 if reached_boss else 0
	if died_floor >= 0:
		agg["deaths"].append(died_floor)
	agg["end_hp"] += RunManager.current_hp
	agg["hp_lost"] += _hp_lost_total
	agg["min_p"] += min_p
	agg["max_p"] += max_p
	agg["tiers"] += tiers_seen.size()
	agg["end_tier"][RunManager.get_passion_tier()] += 1
	if boss_start_hp >= 0:
		agg["boss_hp_sum"] += boss_start_hp
		agg["boss_hp_n"] += 1
		agg["boss_passion_sum"] += RunManager.passion.current_value
		if pet_at_boss != "":
			agg["pet_at_boss"][pet_at_boss] = agg["pet_at_boss"].get(pet_at_boss, 0) + 1
		agg["forgotten_at_boss"] += forgotten_at_boss
		agg["woken_at_boss"] += woken_at_boss
	agg["gold_earned"] += RunManager.run_stats.get("gold_earned", 0)
	agg["gold_spent"] += gold_spent
	agg["gold_end"] += RunManager.gold
	agg["deck_size"] += RunManager.current_deck.size()
	agg["consumables_used"] += _consumables_used
	for i in passion_by_node.size():
		if agg["passion_node"].size() <= i:
			agg["passion_node"].append(0.0)
			agg["passion_node_n"].append(0)
		agg["passion_node"][i] += passion_by_node[i]
		agg["passion_node_n"][i] += 1
	for f in _fights:
		var key: int = f["index"]
		if not agg["fights"].has(key):
			agg["fights"][key] = {"n": 0, "wins": 0, "turns": 0, "lost": [], "passion": 0}
		var fs: Dictionary = agg["fights"][key]
		fs["n"] += 1
		fs["wins"] += 1 if f["won"] else 0
		fs["turns"] += f["turns"]
		fs["lost"].append(f["lost"])
		fs["passion"] += f["passion"]


## Drives one combat with the shared policy over the real engine. Persists the post-fight HP;
## Passion is mutated live on RunManager by the played cards. Returns the fight's numbers.
func _run_combat(enemies: Array[EnemyData], node_index: int = -1) -> Dictionary:
	var eng := CombatEngine.new()
	eng.instant = true
	add_child(eng)
	var deck: Array[CardData] = []
	for c in RunManager.current_deck:
		deck.append(c.duplicate_card())
	var hp_before := RunManager.current_hp
	var pack_before := RunManager.consumables.size()
	eng.start_combat(deck, RunManager.current_hp, RunManager.max_hp, enemies)

	var guard := 0
	while eng.phase == CombatEngine.Phase.PLAYER_TURN and eng.turn_number < MAX_TURNS:
		guard += 1
		if guard > 400:
			break
		_cbt.play_turn(eng, true, COMMIT_TARGET)  # commit=true: a Water-pole player
		if eng.phase != CombatEngine.Phase.PLAYER_TURN:
			break
		eng.end_player_turn()

	var won := eng.phase == CombatEngine.Phase.BATTLE_WON
	if not won:  # a win has already carried its HP and combat-end relics into the run
		RunManager.current_hp = maxi(0, eng.player_stats.current_hp)
	var turns := eng.turn_number
	eng.free()
	if not _cbt.within_memory_ceiling("run %d, after a combat" % RngManager.run_seed):
		_aborted = true
		get_tree().quit(1)
	var lost := maxi(0, hp_before - RunManager.current_hp)
	_hp_lost_total += lost
	_consumables_used += maxi(0, pack_before - RunManager.consumables.size())
	var res := {"won": won, "turns": turns, "lost": lost,
		"passion": RunManager.passion.current_value, "index": node_index}
	if node_index >= 0:
		_fights.append(res)
	return res


func _encounter(node: String, floor_num: int) -> Array[EnemyData]:
	match node:
		"elite":
			return EnemyPool.get_elite_encounter()
		"boss":
			return EnemyPool.get_boss()
		_:
			return EnemyPool.get_combat_encounter(floor_num)


## The scripted event fights, as event_scene._start_event_combat sets them up.
func _event_enemies(key: StringName) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	match key:
		&"sword_guardian":
			out.assign(EnemyPool.get_sword_guardian())
		&"raider_band":
			out.assign(EnemyPool.get_raider_band())
		&"raider_band_poisoned":
			var chalice := ConsumablePool.get_consumable(&"poisoned_chalice")
			out.assign(EnemyPool.get_raider_band_poisoned(chalice.value if chalice else 4))
		&"chapel_beast":
			out.append(EnemyPool.the_shattered_choir())
		&"barrow_warden":
			out.assign(EnemyPool.get_barrow_warden())
	return out


## A relic reward after an elite/boss (the real reward flow offers 3; we take the
## first offered = average luck, not best-case, so sustain isn't over-modelled),
## skipping only a relic that would fight the modeled build's pole (see below).
func _award_relic(is_boss: bool) -> void:
	var owned := RunManager.get_owned_relic_names()
	var choices: Array[RelicData]
	if is_boss:
		choices = RelicPool.get_boss_reward_choices(RngManager.loot_rng, owned)
	else:
		choices = RelicPool.get_reward_choices(RngManager.loot_rng, 3, owned)
	for c in choices:
		if not _relic_against_commit(c):
			RunManager.add_relic(c)
			return
	if choices.size() > 0:
		RunManager.add_relic(choices[0])


## True if a relic swings Passion the WRONG way for the modeled Water-commit build (an
## ON_TURN_START −Passion relic like Leaden Vow). A real Water player would never draft
## it, so the model shouldn't either; otherwise the swing gear pollutes the passion arc.
func _relic_against_commit(r: RelicData) -> bool:
	return r.trigger == RelicData.RelicTrigger.ON_TURN_START \
		and r.effect == RelicData.RelicEffect.GAIN_PASSION \
		and signi(r.value) != signi(COMMIT_TARGET)


## Post-combat gold, mirroring map_scene's scaling.
func _award_gold(node: String, floor_num: int) -> void:
	var g := 16 + floor_num * 2
	if node == "elite":
		g = 34 + floor_num * 2
	elif node == "boss":
		g = 50 + floor_num * 2
	RunManager.add_gold(g)


# ============================================================
# NON-COMBAT NODE POLICIES
# ============================================================

## Draft the strongest offered card for a Water build (prefer the water pole,
## then rarity). A demo player almost always takes a card, so we never skip.
func _draft_reward() -> void:
	var choices := CardPool.get_reward_choices(RngManager.loot_rng)
	var best := _best_card(choices)
	if best != null:
		RunManager.add_card_to_deck(best)


## Rest: heal if wounded, otherwise upgrade the costliest un-upgraded card.
func _rest_action() -> void:
	if RunManager.current_hp < int(0.6 * RunManager.max_hp):
		RunManager.heal(int(0.3 * RunManager.max_hp))
		return
	var best: CardData = null
	for c in RunManager.current_deck:
		if c.upgraded:
			continue
		if best == null or c.energy_cost > best.energy_cost:
			best = c
	if best != null:
		best.upgrade_card()
	else:
		RunManager.heal(int(0.3 * RunManager.max_hp))


## A restorative from the pack when the player is hurt between nodes: a Cold Supper (map only)
## first, since it has no other use, then whatever else mends. Below half health, no more than
## the missing HP is wasted by a quarter.
func _use_map_heals() -> void:
	for item in RunManager.consumables.duplicate():
		if RunManager.current_hp >= int(0.5 * RunManager.max_hp):
			return
		if item.kind != ConsumableData.Kind.RESTORATIVE:
			continue
		if item.usable_on_map and not item.usable_in_combat \
				and RunManager.use_consumable_on_map(item):
			_consumables_used += 1
	for item in RunManager.consumables.duplicate():
		if RunManager.current_hp >= int(0.4 * RunManager.max_hp):
			return
		if item.kind == ConsumableData.Kind.RESTORATIVE and item.usable_on_map \
				and RunManager.use_consumable_on_map(item):
			_consumables_used += 1


## Wear the best two titles earned, in the order of TITLE_PREFERENCE.
func _equip_best_titles() -> void:
	var slot := 0
	for id in TITLE_PREFERENCE:
		if slot >= RunManager.TITLE_SLOT_COUNT:
			return
		if RunManager.earned_title_ids.has(id):
			if RunManager.active_title_slots[slot] != id:
				RunManager.equip_title(slot, id)
			slot += 1


## Shop: buy the best affordable relic first (the high-value purchase), then the pack's stock
## (two items at random from every priced one, as the shop shows), then up to two cards. Uses the
## REAL shop_scene prices: cards 40/60/90, relics 100/150/200 by rarity, consumables their own.
## Returns gold spent.
func _shop_action() -> int:
	var spent := 0
	var owned := RunManager.get_owned_relic_names()
	for r in RelicPool.get_reward_choices(RngManager.loot_rng, 2, owned):
		if _relic_against_commit(r):
			continue
		var rp := _relic_price(r)
		if RunManager.gold >= rp:
			RunManager.gold -= rp
			spent += rp
			RunManager.add_relic(r)
			break  # one relic per shop is plenty
	for item in ConsumablePool.get_shop_stock(RngManager.loot_rng, &"camelot", 2):
		if item.kind == ConsumableData.Kind.STANDING or item.kind == ConsumableData.Kind.QUEST:
			continue  # the standing swings and quest items serve a pledge this walk does not play
		if RunManager.has_consumable_room() and RunManager.gold >= item.price:
			RunManager.gold -= item.price
			spent += item.price
			RunManager.add_consumable(item)
	var wares := CardPool.get_reward_choices(RngManager.loot_rng, 5)
	wares.sort_custom(func(a, b): return _card_score(a) > _card_score(b))
	var bought := 0
	for w in wares:
		if bought >= 2:
			break
		var price := _card_price(w)
		if RunManager.gold >= price:
			RunManager.gold -= price
			spent += price
			RunManager.add_card_to_deck(w)
			bought += 1
	return spent


func _relic_price(r: RelicData) -> int:
	match r.rarity:
		RelicData.RelicRarity.RARE: return 200
		RelicData.RelicRarity.UNCOMMON: return 150
		_: return 100


# ============================================================
# EVENTS: the real builders, resolved by a value heuristic
# ============================================================

## Resolves an event the way a decent player would: pick the best-scoring choice that can be taken,
## apply it through RunManager, run the fight it starts and its follow-up beat, follow a chain.
## `take_fight` forces the choice that starts a fight (the Sword in the Stone). Returns false only
## if the player died in a fight the event started.
func _resolve_event(ev: EventData, node_index: int, take_fight: bool, depth: int = 0) -> bool:
	if ev == null or depth > 6:
		return true
	var best: EventData.EventChoice = null
	var best_score := -999999
	for choice in ev.choices:
		var s := _event_score(choice)
		if take_fight and choice.starts_combat != &"":
			s += 100000
		if s > best_score:
			best_score = s
			best = choice
	if best == null or best_score <= -99999:
		return true
	_apply_choice(best)
	if best.starts_combat != &"":
		var enemies := _event_enemies(best.starts_combat)
		if enemies.is_empty():
			return true
		var res := _run_combat(enemies, node_index)
		if not res["won"]:
			return false
		var follow: StringName = FIGHT_FOLLOW_UP.get(best.starts_combat, &"")
		if follow != &"":
			return _resolve_event(_scene._build_special_event(follow), node_index, false, depth + 1)
		return true
	if best.next_event_id != &"":
		return _resolve_event(_scene._build_special_event(best.next_event_id), node_index, false,
			depth + 1)
	return true


## The effects of a taken choice, in event_scene._apply_effects' order where it matters. HP is
## applied directly (events bypass block), clamped; gold, Passion, standing and the grants go
## through the normal paths. Quest arming is not modelled (the walk has no map to place a payoff).
func _apply_choice(c: EventData.EventChoice) -> void:
	if c.max_hp_change != 0:
		RunManager.max_hp += c.max_hp_change
	RunManager.current_hp = clampi(RunManager.current_hp + c.hp_change, 0, RunManager.max_hp)
	var gold := c.gold_change
	if c.gamble_win_gold != 0 or c.gamble_lose_gold != 0:
		gold = c.gamble_win_gold if RngManager.event_rng.randf() < c.gamble_chance else c.gamble_lose_gold
	if gold > 0:
		RunManager.add_gold(gold)
	elif gold < 0:
		RunManager.gold = maxi(0, RunManager.gold + gold)
	if c.passion_change != 0:
		RunManager.change_passion(c.passion_change)
	if c.standing_change != 0:
		RunManager.change_realm_standing(RunManager.current_realm_id, c.standing_change)
	if c.card_reward:
		_draft_reward()
	if c.remove_card and RunManager.current_deck.size() > 1:
		RunManager.remove_card_from_deck(_worst_card_index())
	if c.awarded_title_id != &"":
		RunManager.award_title(c.awarded_title_id)
	if c.granted_relic_id != &"":
		var rel := RelicPool.get_relic_by_name(String(c.granted_relic_id))
		if rel and not RunManager.has_relic(rel.relic_name):
			RunManager.add_relic(rel)
	if c.grants_random_relic:
		var picks := RelicPool.get_reward_choices(RngManager.loot_rng, 3,
			RunManager.get_owned_relic_names())
		if not picks.is_empty():
			RunManager.add_relic(picks[0])
	if c.grants_liaison_relic != &"":
		var lp := RelicPool.get_liaison_relic_choices(c.grants_liaison_relic, RngManager.loot_rng, 1,
			RunManager.get_owned_relic_names())
		if not lp.is_empty():
			RunManager.add_relic(lp[0])
	if c.granted_card_id != &"":
		var mem := CardPool.get_memory_card(c.granted_card_id)
		if mem:
			RunManager.add_card_to_deck(mem)
	if c.grants_curse != &"":
		var curse := CardPool.get_curse_card(c.grants_curse)
		if curse:
			RunManager.add_card_to_deck(curse)
	if c.grants_consumable != &"":
		var item := ConsumablePool.get_consumable(c.grants_consumable)
		if item and item.kind != ConsumableData.Kind.STANDING and item.kind != ConsumableData.Kind.QUEST:
			RunManager.add_consumable(item)  # a full pack leaves it behind
	if c.grants_pet != &"":
		RunManager.set_pet(c.grants_pet)
	if c.wakes_relic != &"":
		RunManager.wake_relic_by_name(String(c.wakes_relic))
	if c.grants_combat_boon != &"":
		RunManager.pending_combat_boon = c.grants_combat_boon


func _event_score(c: EventData.EventChoice) -> int:
	# Gates the player cannot meet, an unaffordable cost, a lethal HP hit: a hard no.
	if c.requires_favor == &"folk" and not RunManager.has_folk_favor():
		return -999999
	if c.requires_favor == &"court" and not RunManager.has_court_favor():
		return -999999
	if c.requires_consumable != &"" and not RunManager.has_consumable(c.requires_consumable):
		return -999999
	if c.requires_relic != &"" and not RunManager.has_relic(String(c.requires_relic)):
		return -999999
	if c.gold_change < 0 and RunManager.gold < -c.gold_change:
		return -999998
	if RunManager.current_hp + c.hp_change <= 0:
		return -999997
	# A quest is not played here (no map to place its payoff), and a standing swing serves a
	# pledge the walk does not take.
	if c.arms_quest != &"":
		return -99999
	var hp_frac := float(RunManager.current_hp) / maxf(1.0, RunManager.max_hp)
	var s := 0
	s += 50 if c.card_reward else 0
	s += 15 if c.remove_card else 0
	s += c.gold_change
	if c.gamble_win_gold != 0 or c.gamble_lose_gold != 0:
		s += int(c.gamble_chance * c.gamble_win_gold + (1.0 - c.gamble_chance) * c.gamble_lose_gold)
	s += c.max_hp_change * 3
	s += c.hp_change                 # negative HP hurts
	s += c.passion_change            # a Water build likes + Passion
	# Grants. A title is worth a slot; a relic a good share of a shop's price; an animal what it
	# brings if the player has none (and nothing to swap it for if they do); waking is the whole
	# point of carrying a forgotten relic; a fight is a cost unless the player is healthy.
	if c.awarded_title_id != &"" and not RunManager.earned_title_ids.has(c.awarded_title_id):
		s += 60
	if c.granted_relic_id != &"" or c.grants_random_relic or c.grants_liaison_relic != &"":
		s += 80
	if c.granted_card_id != &"":
		s += 40
	if c.grants_curse != &"":
		s -= 40
	if c.grants_consumable != &"":
		var item := ConsumablePool.get_consumable(c.grants_consumable)
		if item and item.kind in [ConsumableData.Kind.RESTORATIVE, ConsumableData.Kind.COMBAT_BOON] \
				and RunManager.has_consumable_room():
			s += 25
	if c.grants_pet != &"":
		if RunManager.pet_id == &"" and _pet_mode == "auto":
			s += 60 - 5 * maxi(0, _prefer.find(String(c.grants_pet)))
		else:
			s -= 100000  # already travelling with one, or the batch forbids it: leave them with him
	if c.wakes_relic != &"":
		s += 90
	if c.grants_combat_boon != &"":
		s += 20
	if c.starts_combat != &"":
		s += 70 if hp_frac >= 0.6 else -200
	return s


# ============================================================
# CARD SCORING (Water-build draft heuristic)
# ============================================================

func _best_card(choices: Array[CardData]) -> CardData:
	var best: CardData = null
	for c in choices:
		if best == null or _card_score(c) > _card_score(best):
			best = c
	return best


func _card_score(c: CardData) -> int:
	var s := int(c.rarity) * 10
	if c.personality == CardData.PersonalityType.PRIMARY:
		s += 100    # commit to Water
	elif c.personality == CardData.PersonalityType.SECONDARY:
		s -= 40     # off-pole
	elif _grants_block(c):
		s += 55     # glass Water still values a little neutral defense to survive
	return s


## True if a card grants any Block, the survival floor a committed Water drafter still
## reaches for (Shield Wall / Phantom Guard / Bracing Blow), since the Water pole itself
## no longer carries block.
func _grants_block(c: CardData) -> bool:
	for e in c.get_active_effects():
		if e is BlockEffect:
			return true
	return false


func _card_price(c: CardData) -> int:
	match c.rarity:
		CardData.CardRarity.RARE: return 90
		CardData.CardRarity.UNCOMMON: return 60
		_: return 40


## Index of the least-wanted deck card to remove (a basic Strike/Defend first).
func _worst_card_index() -> int:
	for i in RunManager.current_deck.size():
		var n: String = RunManager.current_deck[i].card_name
		if n == "Strike" or n == "Defend":
			return i
	return 0


# ============================================================
# AGGREGATION + REPORT
# ============================================================

func _fresh_agg() -> Dictionary:
	return {
		"runs": 0, "wins": 0, "deaths": [], "end_hp": 0, "hp_lost": 0, "min_p": 0, "max_p": 0,
		"tiers": 0,
		"end_tier": [0, 0, 0, 0, 0],  # HOLLOW..BLAZING
		"boss_hp_sum": 0, "boss_hp_n": 0, "boss_passion_sum": 0,
		"gold_earned": 0, "gold_spent": 0, "gold_end": 0, "deck_size": 0,
		"consumables_used": 0, "pet_at_boss": {}, "forgotten_at_boss": 0, "woken_at_boss": 0,
		"passion_node": [], "passion_node_n": [], "fights": {},
	}


func _report(a: Dictionary) -> void:
	var n := float(a["runs"])
	print("\nCLEAR RATE (reached + beat the Act-1 boss): %.0f%% (%d/%d)" % [
		100.0 * a["wins"] / n, a["wins"], a["runs"]])
	if a["deaths"].size() > 0:
		var hist := {}
		for f in a["deaths"]:
			hist[f] = hist.get(f, 0) + 1
		var floors: Array = hist.keys()
		floors.sort()
		var parts: PackedStringArray = []
		for f in floors:
			parts.append("f%d (%s): %d" % [f, LAYOUT[f - 1], hist[f]])
		print("  deaths by floor: %s" % ", ".join(parts))

	print("\nPER FIGHT (win rate, turns, HP lost average and p90, Passion at the end of the fight):")
	var keys: Array = a["fights"].keys()
	keys.sort()
	for k in keys:
		var fs: Dictionary = a["fights"][k]
		var lost: Array = fs["lost"]
		lost.sort()
		var tot := 0
		for v in lost:
			tot += v
		print("  f%-2d %-9s n %3d  win %5.1f%%  turns %4.1f  HP lost avg %4.1f p90 %3d  Passion %+5.1f" % [
			k + 1, LAYOUT[k], fs["n"], 100.0 * fs["wins"] / fs["n"], float(fs["turns"]) / fs["n"],
			float(tot) / maxf(1.0, lost.size()), lost[mini(lost.size() - 1, int(0.9 * lost.size()))],
			float(fs["passion"]) / fs["n"]])

	print("\nPASSION ARC (the playtest's main gripe: did it move?):")
	print("  distinct tiers visited / run: %.1f of 5" % (float(a["tiers"]) / n))
	print("  swing per run: avg low %.0f  ->  avg high %.0f" % [
		float(a["min_p"]) / n, float(a["max_p"]) / n])
	var traj: PackedStringArray = []
	for i in a["passion_node"].size():
		traj.append("%+.0f" % (a["passion_node"][i] / maxf(1.0, a["passion_node_n"][i])))
	print("  trajectory after each node: %s" % " ".join(traj))
	if a["boss_hp_n"] > 0:
		print("  Passion at the boss: avg %.0f (%s)" % [
			float(a["boss_passion_sum"]) / a["boss_hp_n"],
			_tier_name(int(round(float(a["boss_passion_sum"]) / a["boss_hp_n"])))])
	var tnames := ["Hollow", "Wavering", "Steady", "Inspired", "Blazing"]
	var parts: PackedStringArray = []
	for t in 5:
		parts.append("%s %d%%" % [tnames[t], int(round(100.0 * a["end_tier"][t] / n))])
	print("  end-of-run tier mix: %s" % ", ".join(parts))

	print("\nHP / SURVIVAL:")
	if a["boss_hp_n"] > 0:
		print("  HP arriving at the boss: avg %.0f / 80" % (float(a["boss_hp_sum"]) / a["boss_hp_n"]))
	print("  HP lost across a run's fights: avg %.1f" % (float(a["hp_lost"]) / n))
	print("  HP at run end (winners incl.): avg %.0f / 80" % (float(a["end_hp"]) / n))

	print("\nECONOMY (playtest: 'no gold spent'):")
	print("  gold earned/run %.0f  ·  spent %.0f  ·  leftover at end %.0f" % [
		float(a["gold_earned"]) / n, float(a["gold_spent"]) / n, float(a["gold_end"]) / n])
	print("  final deck size: avg %.1f cards (started 9)" % (float(a["deck_size"]) / n))
	print("  pack items used per run: avg %.2f" % (float(a["consumables_used"]) / n))

	print("\nTHE NEW LAYERS (at the boss, of the runs that reached it):")
	var reached := maxf(1.0, a["boss_hp_n"])
	var pets: PackedStringArray = []
	for id in a["pet_at_boss"]:
		pets.append("%s %d%%" % [id, int(round(100.0 * a["pet_at_boss"][id] / reached))])
	print("  companion held: %s" % (", ".join(pets) if not pets.is_empty() else "none"))
	print("  forgotten relics still dormant: avg %.2f   woken: avg %.2f" % [
		float(a["forgotten_at_boss"]) / reached, float(a["woken_at_boss"]) / reached])


func _tier_name(v: int) -> String:
	return PassionState.tier_name(RunManager.get_passion_tier_for_value(v))


# ============================================================
# CHARACTER (mirrors the real Emo Hybrid; shares CardPool pools)
# ============================================================

func _build_emo_hybrid() -> CharacterData:
	return CharacterPool.build_emo_hybrid()
