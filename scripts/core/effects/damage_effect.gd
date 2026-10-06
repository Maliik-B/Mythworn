class_name DamageEffect
extends CardEffect
## Deals damage to the target. Respects block and damage modifiers (Vulnerable, Weak).

@export var hits: int = 1 # For multi-hit attacks
## X-scaled: the hit count is X (the energy an X-cost card spent this cast) instead of
## `hits`. The engine supplies X via current_x(); pairs with CardData.x_cost. A torrent
## that strikes once per energy — synergises with Overflow and Vulnerable.
@export var x_scaled: bool = false
## Piercing: this many points of the hit bypass the target's block and land straight
## on HP; the rest soaks block normally. Per hit, so a multi-hit pierce is rare by
## design. The Corrupted Crossbowman's bolt is the canonical user — a guard-breaking
## shot whose punish window is the reload that follows.
@export var pierce: int = 0


func apply(source, target, battle_state) -> void:
	var total_hits := hits
	if x_scaled and battle_state:
		total_hits = battle_state.current_x()
	# Overflow power: at Blazing, the player's multi-hit attacks strike extra times.
	# (Enemies never hold powers, so this is a no-op for their attacks.) Applies to
	# X-scaled torrents too once they're already striking more than once.
	if total_hits > 1 and source and source.has_power(Powers.OVERFLOW) \
			and RunManager.get_passion_tier() == PassionState.Tier.BLAZING:
		total_hits += source.get_power_stacks(Powers.OVERFLOW)
	for i in total_hits:
		battle_state.deal_damage(target, value, source, pierce)


func get_description() -> String:
	var pierce_note := " Ignores %d block." % pierce if pierce > 0 else ""
	if x_scaled:
		return "Deal %d damage X times (X = energy spent).%s" % [value, pierce_note]
	if hits > 1:
		return "Deal %d damage %d times (%d total).%s" % [value, hits, value * hits, pierce_note]
	return "Deal %d damage.%s" % [value, pierce_note]


## Returns description with combat modifiers shown as base [modified]. Includes the
## target's Vulnerable (×1.5) when a target is supplied — e.g. while dragging the card
## onto an enemy — so the bracket shows the real number, composing with Strength/Weak.
func get_modified_description(source: CombatantStats, target: CombatantStats = null,
		zone_mult: float = 1.0) -> String:
	var modified = value
	if source:
		modified += source.get_status_stacks(StatusEffects.STRENGTH)
		if source.has_status(StatusEffects.WEAK):
			modified = int(modified * 0.75)
	# Passion zone multiplier, folded in at the SAME point CombatEngine.deal_damage applies
	# it (after Strength/Weak, before Vulnerable) so the bracket equals the real hit. Without
	# this the preview showed the pre-zone number while a "[Zone Bonus]" tag claimed +25% —
	# under-reporting damage at a committed extreme.
	if zone_mult != 1.0:
		modified = int(modified * zone_mult)
	if target and target.has_status(StatusEffects.VULNERABLE):
		modified = int(modified * 1.5)
	modified = maxi(0, modified)
	if modified != value:
		if x_scaled:
			return "Deal %d [%d] damage X times (X = energy spent)." % [value, modified]
		if hits > 1:
			return "Deal %d [%d] damage %d times (%d total)." % [value, modified, hits, modified * hits]
		return "Deal %d [%d] damage." % [value, modified]
	return get_description()
