extends Node
## Manages all game audio: SFX and music playback.
## Connects to Events signals and plays appropriate sounds.
## Audio files go in res://audio/sfx/ and res://audio/music/; any that are missing play nothing.

# -- Music player --
var music_player: AudioStreamPlayer

# -- SFX pool (multiple players for overlapping sounds) --
const SFX_POOL_SIZE := 8
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_index: int = 0

# -- Preloaded sound streams --
# Populated in _ready() from whichever audio files exist.
# Keys are sound names, values are AudioStream resources.
var sounds: Dictionary = {}

# -- Music tracks --
var music_tracks: Dictionary = {}
var current_music: String = ""

## False makes play_sfx and play_music do nothing. The headless batch tools (combat_harness,
## run_harness, roster_test) turn it off before they start. They run thousands of combats
## inside one synchronous _ready, and every play() creates an AudioStreamPlayback, holding
## a ~20 KB QOA decode buffer, that the AudioServer only lets go of once the main loop runs
## again. No frame runs until the tool is finished, so every sound of every trial was kept:
## about 6.9 GB resident on a full combat_harness run.
var enabled := true


func _ready() -> void:
	# Create music player
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	add_child(music_player)

	# Create SFX player pool
	for i in SFX_POOL_SIZE:
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		sfx_players.append(player)

	music_player.finished.connect(_on_music_finished)

	_load_sounds()
	_connect_signals()


## The sound effects, by name. A name with no file in res://audio/sfx/ simply plays nothing, and a
## file of that name added later plays with no code change.
const SOUND_NAMES: Array[String] = [
	"card_play", "card_draw", "hit", "block", "enemy_die", "player_hurt", "combat_win",
	"combat_lose", "button_click", "gold_gain", "relic_acquire", "heal", "status_apply",
	"passion_shift", "tier_change", "card_exhaust", "card_upgrade", "shop_buy",
]

## The music tracks, by name, each looked up as res://audio/music/<name>_theme with one of the
## extensions below. There is no music yet, so none loads and every music call does nothing.
const MUSIC_NAMES: Array[String] = ["map", "combat", "boss", "shop", "rest", "victory"]
const MUSIC_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]


func _load_sounds() -> void:
	for sound_name in SOUND_NAMES:
		var stream := _load_stream("res://audio/sfx/%s.wav" % sound_name)
		if stream != null:
			sounds[sound_name] = stream

	for track_name in MUSIC_NAMES:
		for ext in MUSIC_EXTENSIONS:
			var stream := _load_stream("res://audio/music/%s_theme.%s" % [track_name, ext])
			if stream != null:
				music_tracks[track_name] = stream
				break


## Loads an audio file if it exists, else returns null without a word, so a missing file is
## not an error.
func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


func _connect_signals() -> void:
	# Card events
	Events.card_played.connect(_on_card_played)
	Events.card_drawn.connect(_on_card_drawn)
	Events.card_exhausted.connect(_on_card_exhausted)

	# Combat events
	Events.combat_started.connect(_on_combat_started)
	Events.combat_won.connect(_on_combat_won)
	Events.combat_lost.connect(_on_combat_lost)

	# Damage / defense
	Events.player_damaged.connect(_on_player_damaged)
	Events.enemy_damaged.connect(_on_enemy_damaged)
	Events.enemy_died.connect(_on_enemy_died)
	Events.block_gained.connect(_on_block_gained)

	# Status
	Events.status_applied.connect(_on_status_applied)

	# Passion
	Events.passion_changed.connect(_on_passion_changed)
	Events.passion_tier_changed.connect(_on_passion_tier_changed)

	# Items
	Events.relic_acquired.connect(_on_relic_acquired)


# ============================================================
# SFX PLAYBACK
# ============================================================

## Play a named sound effect. Silently skips if sound not loaded.
func play_sfx(sound_name: String, volume_db: float = 0.0) -> void:
	if not enabled or sound_name not in sounds:
		return
	var player = sfx_players[sfx_index]
	player.stream = sounds[sound_name]
	player.volume_db = volume_db
	player.play()
	sfx_index = (sfx_index + 1) % SFX_POOL_SIZE


# ============================================================
# MUSIC PLAYBACK
# ============================================================

## Play a named music track. Does nothing if already playing that track.
func play_music(track_name: String, volume_db: float = -6.0) -> void:
	if not enabled or track_name == current_music:
		return
	if track_name not in music_tracks:
		return
	current_music = track_name
	music_player.stream = music_tracks[track_name]
	music_player.volume_db = volume_db
	music_player.play()


func _on_music_finished() -> void:
	if current_music != "":
		music_player.play()


func stop_music() -> void:
	music_player.stop()
	current_music = ""


# ============================================================
# SIGNAL HANDLERS
# ============================================================

func _on_card_played(_card: CardData, _target) -> void:
	play_sfx("card_play")

func _on_card_drawn(_card: CardData) -> void:
	play_sfx("card_draw", -4.0)

func _on_card_exhausted(_card: CardData) -> void:
	play_sfx("card_exhaust")

func _on_combat_started() -> void:
	if RunManager.pending_act_complete:
		play_music("boss", -9.0)  # the boss WAV is mastered hotter; pull it down to ~match combat
	else:
		play_music("combat")

func _on_combat_won() -> void:
	play_sfx("combat_win")

func _on_combat_lost() -> void:
	play_sfx("combat_lose")
	stop_music()

func _on_player_damaged(_amount: int, _new_hp: int) -> void:
	play_sfx("player_hurt")

func _on_enemy_damaged(_enemy, _amount: int, _new_hp: int) -> void:
	play_sfx("hit")

func _on_enemy_died(_enemy) -> void:
	play_sfx("enemy_die")

func _on_block_gained(_target, amount: int) -> void:
	# A negative amount is Block being taken away, which is not a gain.
	if amount <= 0:
		return
	play_sfx("block")

func _on_status_applied(_target, _effect: StatusEffectData, _stacks: int) -> void:
	play_sfx("status_apply", -3.0)

func _on_passion_changed(_old_value: int, _new_value: int) -> void:
	play_sfx("passion_shift", -3.0)

func _on_passion_tier_changed(_old_tier: int, _new_tier: int) -> void:
	play_sfx("tier_change")

func _on_relic_acquired(_relic: RelicData) -> void:
	play_sfx("relic_acquire")
