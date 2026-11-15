class_name DamageEffect
extends CardEffect
## Deals damage to the target. Respects block and damage modifiers (Vulnerable, Weak).

@export var hits: int = 1 # For multi-hit attacks
## X-scaled: the hit count is X (the energy an X-cost card spent this cast) instead of
## `hits`. The engine supplies X via current_x(); pairs with CardData.x_cost. A torrent
## that strikes once per energy, synergises with Overflow and Vulnerable.
@export var x_scaled: bool = false
## Piercing: this many points of the hit bypass the target's block and land straight
## on HP; the rest soaks block normally. Per hit, so a multi-hit pierce is rare by
## design. The Bannerless Pikeman's thrust is the canonical user -- a guard-breaking
## lunge whose punish window is the recovery that follows.
@export var pierce: int = 0
## Passion-scaled bonus: when > 0, every this-many points of Passion distance from center
## adds +1 damage (per hit). The memory card "Everything I Carried Out" scales with how far
## committed I am to either pole. 0 = no scaling.
@export var passion_bonus_divisor: int = 0
## On-kill energy refund (StS "Feed"-style): when > 0, felling the target with this attack
## gives back this much energy. Used by the memory burst "Everything I Carried Out".
@export var energy_on_kill: int = 0
## Self-inflicted: the hit lands on the combatant performing the effect, not the target.
## The Beast at the Stone's Breaking Blow uses it: a blow that costs the body that throws
## it. Resolved as a flat loss through CombatEngine.self_damage (no Strength, no Weak, no
## block, no lash), so the number on the intent is the number he pays. Player cards never
## set this.
@export var apply_to_source: bool = false
## Ignores Block outright: the whole hit, after every modifier, lands on HP. Distinct from
## `pierce`, which is a fixed number of points. The hawk's Stoop uses it: there is no guard
## against a thing that comes straight down.
@export var ignores_block: bool = false
## A flag-read bonus: while the combat flag `bonus_flag` is up (raised by a CombatFlagEffect),
## every hit deals `bonus_value` more, and the card spends the flag after its hits. The hawk's
## Stoop lands double while the hawk is waiting on. The flag lives on the engine, so the dragged
## preview never shows the raised number; `bonus_flag_text` is how it reads on the card ("the
## hawk is waiting on").
@export var bonus_value: int = 0
@export var bonus_flag: StringName = &""
@export var bonus_flag_text: String = ""


## The base hit before combat modifiers, folding in the Passion-distance bonus so both
## apply() and the dragged-preview description read the same number.
func _effective_value() -> int:
	if passion_bonus_divisor > 0:
		return value + RunManager.passion_distance_from_center() / passion_bonus_divisor
	return value


## Whether the flag bonus applies right now: there is one, and the engine has the flag up.
func _bonus_applies(battle_state) -> bool:
	return bonus_value != 0 and bonus_flag != &"" and battle_state != null \
		and battle_state.has_method("has_flag") and battle_state.has_flag(bonus_flag)


func apply(source, target, battle_state) -> void:
	if apply_to_source:
		if battle_state and source:
			battle_state.self_damage(source, value)
		return
	var total_hits := hits
	if x_scaled and battle_state:
		total_hits = battle_state.current_x()
	# Overflow power: at Blazing, the player's multi-hit attacks strike extra times.
	# (Enemies never hold powers, so this is a no-op for their attacks.) Applies to
	# X-scaled torrents too once they're already striking more than once.
	if total_hits > 1 and source and source.has_power(Powers.OVERFLOW) \
			and RunManager.get_passion_tier() == PassionState.Tier.BLAZING:
		total_hits += source.get_power_stacks(Powers.OVERFLOW)
	var dmg := _effective_value()
	var bonus_on := _bonus_applies(battle_state)
	if bonus_on:
		dmg += bonus_value
	# A hit that ignores Block pierces for more than it could ever deal, and the engine clamps
	# the pierce to the modified hit, so every point lands on HP whatever Strength added.
	var pierce_points := 9999 if ignores_block else pierce
	for i in total_hits:
		battle_state.deal_damage(target, dmg, source, pierce_points)
	# The flag is spent by the card that cashed it, once, after all its hits.
	if bonus_on:
		battle_state.spend_flag(bonus_flag)
	# On-kill energy refund: checked once after all hits so a multi-hit doesn't
	# double-count. The heavy blow that fells a foe gives its tempo back.
	if energy_on_kill > 0 and target and target.is_dead() \
			and battle_state and battle_state.has_method("change_energy"):
		battle_state.change_energy(energy_on_kill)


func _riders() -> String:
	var s := ""
	if passion_bonus_divisor > 0:
		s += " +1 damage per %d Passion from center." % passion_bonus_divisor
	if ignores_block:
		s += " Ignores Block."
	elif pierce > 0:
		s += " Ignores %d block." % pierce
	if bonus_value != 0 and bonus_flag != &"":
		s += " %d instead while %s." % [value + bonus_value, bonus_flag_text]
	if energy_on_kill > 0:
		s += " On kill, gain %d energy." % energy_on_kill
	return s


func get_description() -> String:
	var riders := _riders()
	if apply_to_source:
		return "Lose %d HP." % value
	if x_scaled:
		return "Deal %d damage X times (X = energy spent).%s" % [value, riders]
	if hits > 1:
		return "Deal %d damage %d times (%d total).%s" % [value, hits, value * hits, riders]
	return "Deal %d damage.%s" % [value, riders]


## Returns description with combat modifiers shown as base [modified]. Includes the
## target's Vulnerable (×1.5) when a target is supplied, e.g. while dragging the card
## onto an enemy, so the bracket shows the real number, composing with Strength/Weak.
func get_modified_description(source: CombatantStats, target: CombatantStats = null,
		zone_mult: float = 1.0) -> String:
	var modified := modified_value(source, target, zone_mult)
	if modified != value:
		var riders := _riders()
		if x_scaled:
			return "Deal %d [%d] damage X times (X = energy spent).%s" % [value, modified, riders]
		if hits > 1:
			return "Deal %d [%d] damage %d times (%d total).%s" % [value, modified, hits, modified * hits, riders]
		return "Deal %d [%d] damage.%s" % [value, modified, riders]
	return get_description()


## The number one hit will land for: the rules' bracket and the card's big numeral both read this.
func modified_value(source: CombatantStats, target: CombatantStats = null, zone_mult: float = 1.0) -> int:
	# Start from the effective base so the Passion-distance bonus is already in the bracket.
	var modified = _effective_value()
	if source:
		modified += source.get_status_stacks(StatusEffects.STRENGTH)
		if source.has_status(StatusEffects.WEAK):
			modified = int(modified * 0.75)
	# Passion zone multiplier, folded in at the SAME point CombatEngine.deal_damage applies
	# it (after Strength/Weak, before Vulnerable) so the bracket equals the real hit. Without
	# this the preview showed the pre-zone number while a "[Zone Bonus]" tag claimed +25%,
	# under-reporting damage at a committed extreme.
	if zone_mult != 1.0:
		modified = int(modified * zone_mult)
	if target and target.has_status(StatusEffects.VULNERABLE):
		modified = int(modified * 1.5)
	return maxi(0, modified)
