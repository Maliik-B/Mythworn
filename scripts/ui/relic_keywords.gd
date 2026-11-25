class_name RelicKeywords
extends RefCounted
## The game's keywords a relic's description names, each with what it means, so a relic's hover can
## say what "Poise" is the way a status chip does. A status keyword is the status's own name and
## description (the registry owns the words); Block is the one other term a relic leans on.
##
## `mark(control, relic)` puts the note on a relic's panel through HoverNote, wherever a relic is
## shown. A relic that names no keyword is left unmarked, since its panel already says everything.

const BLOCK_TEXT := "Absorbs damage before your HP does, and falls away when your next turn begins."


## Every keyword the game knows, as {name, text}, in the order a note lists them.
static func vocabulary() -> Array:
	var out: Array = []
	for status in [StatusEffects.VULNERABLE, StatusEffects.WEAK, StatusEffects.STRENGTH,
			StatusEffects.POISON, StatusEffects.DEXTERITY, StatusEffects.INTANGIBLE,
			StatusEffects.STUN, StatusEffects.CHILLED, StatusEffects.ENRAGED, StatusEffects.ZEALOTRY]:
		out.append({"name": status.effect_name, "text": status.description})
	out.append({"name": "Block", "text": BLOCK_TEXT})
	return out


## The keywords `text` names, once each, as {name, text}. A whole-word match, so "Weakness" is not
## "Weak".
static func in_text(text: String) -> Array:
	var out: Array = []
	for entry in vocabulary():
		var word := RegEx.new()
		word.compile("\\b" + String(entry["name"]) + "\\b")
		if word.search(text) != null:
			out.append(entry)
	return out


## The keywords in a relic's description.
static func for_relic(relic: RelicData) -> Array:
	return in_text(relic.description)


## The note's body for a relic: one line for each keyword, "Name: what it does". "" with none.
static func body_for(relic: RelicData) -> String:
	var lines: PackedStringArray = []
	for entry in for_relic(relic):
		lines.append("%s: %s" % [entry["name"], entry["text"]])
	return "\n".join(lines)


## Marks `control` so hovering it shows the relic's keywords. A host needs a HoverNote that is not
## blocked over the control.
static func mark(control: Control, relic: RelicData) -> void:
	var body := body_for(relic)
	if body == "":
		return
	HoverNote.mark(control, relic.relic_name, body, "Keywords", "", false, true)
