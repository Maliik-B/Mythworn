class_name StatusEffectData
extends Resource
## Defines a status effect (buff or debuff). Used in combat and realm modifiers.

enum DurationType { TURN_BASED, PERMANENT, COMBAT_ONLY, REALM }
enum StackType { INTENSITY, DURATION, NONE }
## How the effect leaves play — surfaced in the status chip's tooltip so the player
## knows whether it will fade on its own. PERSISTS: stays all combat (Strength).
## TURN_TICK: loses a stack each turn (Vulnerable, Poison, Poise). TEMPORARY: a
## one-shot duration that expires after firing (Frozen).
enum Decay { PERSISTS, TURN_TICK, TEMPORARY }
enum TriggerTiming {
	START_OF_TURN,
	END_OF_TURN,
	ON_DAMAGE_DEALT,
	ON_DAMAGE_TAKEN,
	ON_CARD_PLAYED,
	PASSIVE,
}

@export var effect_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var is_buff: bool = true
@export var duration_type: DurationType = DurationType.TURN_BASED
@export var stack_type: StackType = StackType.INTENSITY
@export var trigger_timing: TriggerTiming = TriggerTiming.PASSIVE
@export var decay: Decay = Decay.PERSISTS


## Short "buff"/"debuff" tag for the status chip.
func kind_label() -> String:
	return "buff" if is_buff else "debuff"


## One-line note on how the effect fades, for the chip tooltip.
func decay_note() -> String:
	match decay:
		Decay.TURN_TICK:
			return "Loses 1 each turn"
		Decay.TEMPORARY:
			return "Expires after it triggers"
		_:
			return "Persists for the rest of combat"
