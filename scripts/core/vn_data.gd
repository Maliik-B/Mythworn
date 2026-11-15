class_name VNData
extends RefCounted
## A visual-novel segment: a sequence of dialogue beats, optionally ending in a choice set
## whose consequences shape the run. The realm-entry VN uses a choice to set the realm
## STATE before map navigation (Camelot: court vs common folk → RunManager.realm_config);
## the Fable send-off uses beats only (the liaison gift is applied separately). Hand-
## authored and rendered by vn_scene. See docs/GAME_DESIGN.md § Realms and
## [[demo-liaisons-bram-neve]] for the demo content this plumbing will carry.

## One line of dialogue: who speaks, what they say, and an accent colour for the name. A setting
## beat names only the place and the time: vn_scene sets it as a running head above the panel, where
## it stays until the next setting beat, and it takes no click of its own.
class VNBeat:
	var speaker: String = ""
	var text: String = ""
	var speaker_color: Color = Color(0.85, 0.82, 0.70)  # warm parchment default
	var setting := false
	func _init(p_speaker: String = "", p_text: String = "",
			p_color: Color = Color(0.85, 0.82, 0.70)) -> void:
		speaker = p_speaker
		text = p_text
		speaker_color = p_color

## A terminal choice. `config` (if non-null) is applied to RunManager.realm_config when
## chosen: the realm-shape consequence. `result_text` is an optional closing beat shown
## after choosing, before the VN hands off to the next scene. `detail` says what the choice
## will change, set under its label so it can be read before it is taken.
class VNChoice:
	var label: String = ""
	var result_text: String = ""
	var config: RealmConfig = null
	var detail: String = ""
	func _init(p_label: String = "", p_config: RealmConfig = null,
			p_result: String = "", p_detail: String = "") -> void:
		label = p_label
		config = p_config
		result_text = p_result
		detail = p_detail

var title: String = ""
var beats: Array[VNBeat] = []
var choices: Array[VNChoice] = []   # empty = dialogue only; the VN just continues on finish


## Chainable authoring helpers, so a VN sequence reads top-to-bottom at its call site.
func add_beat(speaker: String, text: String,
		color: Color = Color(0.85, 0.82, 0.70)) -> VNData:
	beats.append(VNBeat.new(speaker, text, color))
	return self


## A place-and-time line ("Dispatch"), set as a heading rather than read as narration.
func add_setting(text: String) -> VNData:
	var beat := VNBeat.new("", text)
	beat.setting = true
	beats.append(beat)
	return self


func add_choice(label: String, config: RealmConfig = null, result: String = "",
		detail: String = "") -> VNData:
	choices.append(VNChoice.new(label, config, result, detail))
	return self
