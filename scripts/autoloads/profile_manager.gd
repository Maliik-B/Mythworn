extends Node
## Persistent player profile / preferences, stored outside any single run and
## backed by user://profile.cfg (ConfigFile). Holds small cross-session flags:
## the settings toggles the player expects to stick, and the set of one-time
## cutscenes already seen, so the run-start intro plays the full two-liaison
## greeting only the first time on a save, then a single liaison per run.
##
## Structured to extend: the future cutscene-replay system reads the same
## seen_cutscenes set, one StringName id per sequence. Adding a new one-time
## sequence is just a new id + has_seen/mark_seen calls.
##
## NOTE: this is a lightweight prefs file, NOT the run save/load system (out of
## demo scope). It only persists tiny cross-session flags, never run state.

const SAVE_PATH := "user://profile.cfg"
const SECTION_CUTSCENES := "cutscenes"
const SECTION_SETTINGS := "settings"

## The Fable send-off introduction (the two-liaison double greeting), the one
## one-time cutscene the demo tracks. Later sequences add more ids alongside it.
const CUTSCENE_INTRO: StringName = &"fable_intro"

## Ids of one-time cutscenes the player has already seen (id -> true).
var _seen_cutscenes: Dictionary = {}

## When true, the full intro plays every run regardless of _seen_cutscenes
## (the settings "toggle it back on" option). Persisted.
var always_show_intro: bool = false

## Persisted player settings. Music/SFX are linear 0-100 (applied to the audio buses);
## fullscreen + screen_shake are the display/gameplay toggles. Loaded + applied at launch so
## the player's choices survive a restart (previously they reset every session).
var music_volume: float = 100.0
var sfx_volume: float = 100.0
var fullscreen: bool = false
var screen_shake: bool = true


func _ready() -> void:
	load_profile()
	apply_audio_settings()
	apply_display_settings()


func load_profile() -> void:
	_seen_cutscenes.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no profile yet -> defaults (a fresh save)
	for id in cfg.get_value(SECTION_CUTSCENES, "seen", PackedStringArray()):
		_seen_cutscenes[StringName(id)] = true
	always_show_intro = bool(cfg.get_value(SECTION_SETTINGS, "always_show_intro", false))
	music_volume = float(cfg.get_value(SECTION_SETTINGS, "music_volume", 100.0))
	sfx_volume = float(cfg.get_value(SECTION_SETTINGS, "sfx_volume", 100.0))
	fullscreen = bool(cfg.get_value(SECTION_SETTINGS, "fullscreen", false))
	screen_shake = bool(cfg.get_value(SECTION_SETTINGS, "screen_shake", true))


func save_profile() -> void:
	var cfg := ConfigFile.new()
	var seen := PackedStringArray()
	for id in _seen_cutscenes:
		seen.append(String(id))
	cfg.set_value(SECTION_CUTSCENES, "seen", seen)
	cfg.set_value(SECTION_SETTINGS, "always_show_intro", always_show_intro)
	cfg.set_value(SECTION_SETTINGS, "music_volume", music_volume)
	cfg.set_value(SECTION_SETTINGS, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION_SETTINGS, "fullscreen", fullscreen)
	cfg.set_value(SECTION_SETTINGS, "screen_shake", screen_shake)
	cfg.save(SAVE_PATH)


# ============================================================
# Settings application + setters (apply live AND persist)
# ============================================================

## Applies the stored music/SFX volumes to the audio buses. Called at launch and whenever
## a volume changes, so the buses always match the persisted prefs.
func apply_audio_settings() -> void:
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)


## Applies the stored fullscreen choice to the window. Called at launch + on toggle.
func apply_display_settings() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_bus_volume(bus_name: String, linear_value: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	if linear_value <= 0.0:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear_value / 100.0))


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 100.0)
	_apply_bus_volume("Music", music_volume)
	save_profile()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 100.0)
	_apply_bus_volume("SFX", sfx_volume)
	save_profile()


func set_fullscreen(enabled: bool) -> void:
	if fullscreen == enabled:
		return
	fullscreen = enabled
	apply_display_settings()
	save_profile()


## Gameplay toggle read by combat before it shakes the screen. Persisted so "off" sticks.
func set_screen_shake(enabled: bool) -> void:
	if screen_shake == enabled:
		return
	screen_shake = enabled
	save_profile()


## True if the player has already seen the given one-time cutscene.
func has_seen(cutscene_id: StringName) -> bool:
	return _seen_cutscenes.get(cutscene_id, false)


## Record that a one-time cutscene has been seen; persists immediately.
func mark_seen(cutscene_id: StringName) -> void:
	if _seen_cutscenes.get(cutscene_id, false):
		return
	_seen_cutscenes[cutscene_id] = true
	save_profile()


## Whether the run-start should play the full two-liaison introduction: the
## first time on this save (intro unseen), or whenever the player has toggled
## "always show intro" back on. Otherwise a returning run shows one liaison.
func should_show_full_intro() -> bool:
	return always_show_intro or not has_seen(CUTSCENE_INTRO)


## Setter for the settings toggle; no-ops + skips the write if unchanged.
func set_always_show_intro(enabled: bool) -> void:
	if always_show_intro == enabled:
		return
	always_show_intro = enabled
	save_profile()


## Clear the seen-cutscene record (testing / a future "replay from the start").
func reset_seen_cutscenes() -> void:
	_seen_cutscenes.clear()
	save_profile()
