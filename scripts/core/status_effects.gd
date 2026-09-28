class_name StatusEffects
## Static registry of all known status effects.
## Access via StatusEffects.VULNERABLE, StatusEffects.WEAK, etc.

static var VULNERABLE: StatusEffectData
static var WEAK: StatusEffectData
static var STRENGTH: StatusEffectData
static var POISON: StatusEffectData
static var DEXTERITY: StatusEffectData
static var INTANGIBLE: StatusEffectData
static var STUN: StatusEffectData
static var ENRAGED: StatusEffectData
static var ZEALOTRY: StatusEffectData


static func _static_init() -> void:
	VULNERABLE = _make("Vulnerable", "Take 50% more attack damage.", false,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.TURN_TICK)
	WEAK = _make("Weak", "Deal 25% less attack damage.", false,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.TURN_TICK)
	STRENGTH = _make("Strength", "Deal additional damage equal to stacks.", true,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.PERSISTS)
	POISON = _make("Poison", "At start of turn, lose HP equal to stacks. Reduce by 1.", false,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.TURN_TICK)
	# Displayed as "Poise" — a temporary composure that grants bonus block and fades
	# by 1 each turn (see tick_end_of_turn). The internal var stays DEXTERITY so the
	# block-boost plumbing (apply_block) and every card/relic that grants it are unchanged.
	DEXTERITY = _make("Poise", "Gain additional block equal to stacks. Loses 1 each turn.", true,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.TURN_TICK)
	INTANGIBLE = _make("Intangible", "All damage and HP loss reduced to 1 per source.", true,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.TURN_TICK)
	# Frozen: forfeits the next turn's action. DURATION so a second Freeze in the
	# same turn refreshes rather than stacking into a multi-turn lock.
	STUN = _make("Frozen", "Skips their next turn.", false,
		StatusEffectData.StackType.DURATION, StatusEffectData.Decay.TEMPORARY)
	# Enraged: a retaliation buff. When the owner takes attack damage, it strikes the
	# attacker back for `stacks`. Pace-independent, so it makes even a burst-kill cost HP.
	ENRAGED = _make("Enraged", "Strikes back at attackers for damage equal to stacks.", true,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.PERSISTS)
	# Zealotry: the False Prophet's escalating fervor. Persists + stacks each turn it preaches;
	# its center-pull grows with the stacks (see PassionCenterEffect), so the longer it lives
	# the harder it strips your Passion — a race to silence it.
	ZEALOTRY = _make("Zealotry", "Each stack strengthens this enemy's Passion pull toward center.", true,
		StatusEffectData.StackType.INTENSITY, StatusEffectData.Decay.PERSISTS)


static func _make(n: String, desc: String, buff: bool,
		stack: StatusEffectData.StackType,
		decay: StatusEffectData.Decay = StatusEffectData.Decay.PERSISTS) -> StatusEffectData:
	var s = StatusEffectData.new()
	s.effect_name = n
	s.description = desc
	s.is_buff = buff
	s.stack_type = stack
	s.decay = decay
	return s
