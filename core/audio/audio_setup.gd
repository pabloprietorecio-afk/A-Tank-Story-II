class_name AudioSetup
## Buses de audio: Music, SFX y Voice (radio), con volúmenes de los ajustes.
## La música baja automáticamente mientras suena la radio (compresor con cadena lateral).

const MUSIC: StringName = &"Music"
const SFX: StringName = &"SFX"
const VOICE: StringName = &"Voice"

static var _ready_done: bool = false


static func ensure() -> void:
	if not _ready_done:
		_ready_done = true
		for bus_name in [MUSIC, SFX, VOICE]:
			if AudioServer.get_bus_index(bus_name) == -1:
				AudioServer.add_bus()
				var index: int = AudioServer.bus_count - 1
				AudioServer.set_bus_name(index, bus_name)
				AudioServer.set_bus_send(index, &"Master")
		var ducking := AudioEffectCompressor.new()
		ducking.threshold = -30.0
		ducking.ratio = 8.0
		ducking.attack_us = 20000.0
		ducking.release_ms = 600.0
		ducking.sidechain = VOICE
		AudioServer.add_bus_effect(AudioServer.get_bus_index(MUSIC), ducking)
	apply_volumes()


static func apply_volumes() -> void:
	GameSettings.ensure_loaded()
	_set_bus(&"Master", GameSettings.master_volume)
	_set_bus(MUSIC, GameSettings.music_volume)
	_set_bus(SFX, GameSettings.sfx_volume)
	_set_bus(VOICE, GameSettings.voice_volume)


static func _set_bus(bus_name: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))


## Reproductor de música en bucle.
static func music_player(path: String) -> AudioStreamPlayer:
	var stream: AudioStreamOggVorbis = load(path)
	stream.loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = MUSIC
	player.autoplay = true
	return player
