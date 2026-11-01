class_name ConsumablePool
## Builds consumables by id, the way RelicPool builds relics by name. Every value here is
## PROVISIONAL (part 3 of the demo road): the harness models these in part 4 and the numbers
## are balanced in part 5. They sit inside the EVENT_GUIDE section 8 bands.
##
## Two boxes. GENERIC items travel. REALM items belong to a realm, and by default leave the
## pack at that realm's border (a chapel's water means nothing under the world-tree); an item
## that has an answer for what it means out there sets expires_at_border to false.
## Consumables are sourced from events first and shops second, never from combat drops.


## Returns a fresh instance of the consumable with this id, or null for an unknown id. Fresh
## each call, because the run holds the instance it was handed.
static func get_consumable(id: StringName) -> ConsumableData:
	match id:
		&"traveller_salve":
			return _traveller_salve()
		&"cold_supper":
			return _cold_supper()
		&"blade_oil":
			return _blade_oil()
		&"bottled_blessing":
			return _bottled_blessing()
		&"unspent_courage":
			return _unspent_courage()
		&"relic_water":
			return _relic_water()
		&"champions_favour":
			return _champions_favour()
		&"indulgence":
			return _indulgence()
		&"writ":
			return _writ()
		&"loaf":
			return _loaf()
		&"poisoned_chalice":
			return _poisoned_chalice()
	return null


## Every consumable id, in a stable order (tests, tooling, the codex later).
static func all_ids() -> Array[StringName]:
	return [&"traveller_salve", &"cold_supper", &"blade_oil", &"bottled_blessing",
		&"unspent_courage", &"relic_water", &"champions_favour", &"indulgence",
		&"writ", &"loaf", &"poisoned_chalice"]


## The ids a shop in `realm_id` may stock: every priced generic, plus that realm's own priced
## items. Quest items and event-only items carry no price and never appear.
static func shop_candidates(realm_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all_ids():
		var c := get_consumable(id)
		if c == null or c.price <= 0:
			continue
		if c.box == ConsumableData.Box.GENERIC or c.realm_id == realm_id:
			out.append(id)
	return out


## Rolls up to `count` distinct consumables for a shop, shuffled with the passed rng so the
## stock follows the run seed. `exclude_ids` keeps a shop from offering what the player holds.
static func get_shop_stock(rng: RandomNumberGenerator, realm_id: StringName, count: int = 2,
		exclude_ids: Array[StringName] = []) -> Array[ConsumableData]:
	var ids := shop_candidates(realm_id)
	var filtered: Array[StringName] = []
	for id in ids:
		if id not in exclude_ids:
			filtered.append(id)
	RngManager.shuffle(filtered, rng)
	var out: Array[ConsumableData] = []
	for id in filtered.slice(0, mini(count, filtered.size())):
		out.append(get_consumable(id))
	return out


# ============================================================
# GENERIC BOX
# ============================================================

## The baseline: a heal that works anywhere. Smaller than the supper, but flexible. The Man
## Off the Field pays with what he has, and this is what he has.
static func _traveller_salve() -> ConsumableData:
	var c := _make(&"traveller_salve", "Traveller's Salve",
		"Heal 12 HP.",
		"A tin of grease and herbs, given by someone who had little else.",
		ConsumableData.Kind.RESTORATIVE, ConsumableData.Effect.HEAL, 12)
	c.usable_in_combat = true
	c.usable_on_map = true
	c.price = 30
	return c


## The restricted-but-bigger half of a clean trade against the salve: you eat at a fire, not
## mid-swing. Gives the layer a second axis, when rather than only what. Map only.
static func _cold_supper() -> ConsumableData:
	var c := _make(&"cold_supper", "Cold Supper",
		"Heal 20 HP. Map only: you eat at a fire, not mid-swing.",
		"Bread and cold meat in a dead man's cloth. It is still food.",
		ConsumableData.Kind.RESTORATIVE, ConsumableData.Effect.HEAL, 20)
	c.usable_on_map = true
	c.price = 45
	return c


## The next attack hits harder. Deliberately not per hit: per hit is The Sword's Bearer's own
## kind, and those stay unique. It spends on the first hit of the next card you play.
static func _blade_oil() -> ConsumableData:
	var c := _make(&"blade_oil", "Blade Oil",
		"The first hit of your next attack card deals 8 more damage.",
		"Armourer's oil, thick as honey. A drill yard keeps it by the whetstones.",
		ConsumableData.Kind.COMBAT_BOON, ConsumableData.Effect.NEXT_ATTACK_BONUS, 8)
	c.usable_in_combat = true
	c.price = 40
	return c


## Nothing else in the game lets the player time a Passion move. Distinct from The Thurible,
## which drifts a fixed amount every turn: here the moment is the decision.
static func _bottled_blessing() -> ConsumableData:
	var c := _make(&"bottled_blessing", "A Bottled Blessing",
		"Push Passion 12 toward the pole you already lean to.",
		"Shrine water in a stoppered vial. Whoever blessed it was there that morning.",
		ConsumableData.Kind.COMBAT_BOON, ConsumableData.Effect.PASSION_TOWARD_POLE, 12)
	c.usable_in_combat = true
	c.price = 50
	return c


## The proof of the system: the Shade at the Cross's lent courage used to be spent for you at
## the start of the next fight (a queued boon). Held instead, it is the same effect with the
## moment chosen. Event-only, never sold.
static func _unspent_courage() -> ConsumableData:
	var c := _make(&"unspent_courage", "Unspent Courage",
		"Gain 2 Strength until the fight ends.",
		"What a man could not spend on himself, lent.",
		ConsumableData.Kind.COMBAT_BOON, ConsumableData.Effect.STRENGTH_THIS_FIGHT, 2)
	c.usable_in_combat = true
	return c


# ============================================================
# CAMELOT BOX
# ============================================================

## The exemplar of a buffed generic: it heals more than the salve, with a price that says
## something about the realm. The chapel never did learn to trade fair.
static func _relic_water() -> ConsumableData:
	var c := _make(&"relic_water", "Relic-Water",
		"Heal 16 HP, then drift Passion 8 toward Hollow.",
		"Water that stood on a saint's relic. The chapel never did learn to trade fair.",
		ConsumableData.Kind.RESTORATIVE, ConsumableData.Effect.HEAL_DRIFT_HOLLOW, 16)
	c.value2 = 8
	c.usable_in_combat = true
	c.usable_on_map = true
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.price = 55
	return c


## The token a lady gives a knight to carry into the lists. A favour is worn into a fight
## rather than used during one, so it is meant to be spent on the first turn.
static func _champions_favour() -> ConsumableData:
	var c := _make(&"champions_favour", "A Champion's Favour",
		"The first blow against you this fight does not land.",
		"A lady's ribbon. It is worn into the lists, not used in them.",
		ConsumableData.Kind.COMBAT_BOON, ConsumableData.Effect.WARD_FIRST_BLOW, 1)
	c.usable_in_combat = true
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.price = 55
	return c


## A pardon bought off a pardoner's tray: the only way a consumable reaches the court/folk
## axis in a big way. It swings standing toward the court by more than a writ does, and it is
## sold, not found. An indulgence from Camelot's church means nothing in another realm, so it
## expires at the border.
static func _indulgence() -> ConsumableData:
	var c := _make(&"indulgence", "An Indulgence",
		"Swing standing 15 toward the court.",
		"A pardon off a pardoner's tray. It forgives whatever you did against the crown.",
		ConsumableData.Kind.STANDING, ConsumableData.Effect.STANDING_SHIFT, -15)
	c.usable_on_map = true
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.price = 60
	return c


## The Peasant's Plea gates its options on court and folk favour. A writ lets the player carry
## the court's answer instead of spending it on the spot.
static func _writ() -> ConsumableData:
	var c := _make(&"writ", "A Writ",
		"Swing standing 8 toward the court.",
		"A sealed leaf with the crown's name on it. Carried far enough, it opens a door.",
		ConsumableData.Kind.STANDING, ConsumableData.Effect.STANDING_SHIFT, -8)
	c.usable_on_map = true
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.price = 35
	return c


## The folk's half of the pair. A village's own bread, passed hand to hand.
static func _loaf() -> ConsumableData:
	var c := _make(&"loaf", "A Loaf",
		"Swing standing 8 toward the folk.",
		"A village's own bread, the kind passed hand to hand when someone wants a door opened.",
		ConsumableData.Kind.STANDING, ConsumableData.Effect.STANDING_SHIFT, 8)
	c.usable_on_map = true
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.price = 35
	return c


## A quest item: granted at the raider plea, spent at the lair past the ford, where leaving it
## for the band to find opens the fight with them poisoned. It costs one of the two slots for
## the stretch of the run between, which is what gives the quest its teeth; once the lair is
## behind the player it has no further use and the pack says so.
static func _poisoned_chalice() -> ConsumableData:
	var c := _make(&"poisoned_chalice", "The Poisoned Chalice",
		"Carried to the lair past the ford. Leave it there and every raider opens the fight with 4 Poison.",
		"The village's last wine, steeped with monkshood. It is not for drinking.",
		ConsumableData.Kind.QUEST, ConsumableData.Effect.NONE, 4)
	c.box = ConsumableData.Box.REALM
	c.realm_id = &"camelot"
	c.expires_at_border = true
	c.quest_id = &"raiders"
	return c


static func _make(id: StringName, display_name: String, description: String, flavor: String,
		kind: ConsumableData.Kind, effect: ConsumableData.Effect, value: int) -> ConsumableData:
	var c := ConsumableData.new()
	c.id = id
	c.display_name = display_name
	c.description = description
	c.flavor = flavor
	c.kind = kind
	c.effect = effect
	c.value = value
	return c
