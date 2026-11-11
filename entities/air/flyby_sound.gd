class_name FlybySound
extends AudioStreamPlayer3D
## Motor de un aparato en vuelo: bucle que suena en su posición, entra y sale poco a poco, y
## cambia de tono con el efecto Doppler (más agudo al acercarse, más grave al alejarse),
## calculado a mano con la velocidad del aparato respecto a la cámara.

const SOUND_SPEED: float = 343.0
const FADE_IN: float = 0.8
const FADE_OUT: float = 1.4

## Velocidad del aparato (m/s). La actualiza quien lo mueve.
var source_velocity: Vector3 = Vector3.ZERO
var base_pitch: float = 1.0

var _level_db: float = 0.0
var _fade: float = 0.0
var _fading_out: bool = false


static func attach(host: Node3D, sound: AudioStream, level_db: float, unit: float, reach: float, pitch: float = 1.0) -> FlybySound:
	var player := FlybySound.new()
	player.stream = sound
	player.bus = AudioSetup.SFX
	player.unit_size = unit
	player.max_distance = reach
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.base_pitch = pitch
	player.pitch_scale = pitch
	player._level_db = level_db
	player.volume_db = level_db - 40.0
	host.add_child(player)
	player.finished.connect(player.play)
	player.play(randf() * maxf(sound.get_length() - 0.1, 0.0))
	return player


func fade_out() -> void:
	_fading_out = true


func _process(delta: float) -> void:
	if _fading_out:
		_fade = maxf(_fade - delta / FADE_OUT, 0.0)
	else:
		_fade = minf(_fade + delta / FADE_IN, 1.0)
	volume_db = _level_db - 40.0 * (1.0 - _fade) * (1.0 - _fade)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var offset: Vector3 = global_position - camera.global_position
	var distance: float = offset.length()
	if distance < 1.0:
		return
	# Velocidad con la que se aleja (positiva) o se acerca (negativa) al oyente.
	var radial: float = source_velocity.dot(offset / distance)
	pitch_scale = clampf(base_pitch * SOUND_SPEED / (SOUND_SPEED + radial), 0.4, 2.5)
