class_name Sfx
## Efectos de sonido de un solo disparo. Cada sonido crea un reproductor que se borra al terminar.

const CANNON := preload("res://assets/audio/cannon.ogg")
const EXPLOSION := preload("res://assets/audio/explosion.ogg")
const HIT := preload("res://assets/audio/hit.ogg")
const HIT_TANK := preload("res://assets/audio/hit_tank.ogg")
const PICKUP := preload("res://assets/audio/pickup.ogg")
const BELL := preload("res://assets/audio/bell.ogg")
## Bucles de motor (sintetizados con tools/sound_gen): tanque medio, tanque pesado, orugas,
## bombardero, caza y helicóptero.
const ENGINE_TANK := preload("res://assets/audio/engine_tank.wav")
const ENGINE_HEAVY := preload("res://assets/audio/engine_heavy.wav")
## Tanque del jugador: ralentí y motor en marcha (grabados a bordo de tanques reales).
const ENGINE_IDLE := preload("res://assets/audio/engine_idle.wav")
const ENGINE_DRIVE := preload("res://assets/audio/engine_drive.wav")
const PLANE_BOMBER := preload("res://assets/audio/plane_bomber.wav")
const PLANE_FIGHTER := preload("res://assets/audio/plane_fighter.wav")
const MISSILE := preload("res://assets/audio/missile.ogg")
const THUNDER := preload("res://assets/audio/thunder.wav")
## Estampido de la antiaérea: disparo real de un cañón de 25 libras.
const FLAK := preload("res://assets/audio/flak.ogg")


static func play_at(host: Node, stream: AudioStream, point: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = AudioSetup.SFX
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.92, 1.08)
	# Atenuación suave: las explosiones cercanas suenan fuertes y las lejanas aún se oyen.
	player.unit_size = 22.0
	player.max_distance = 500.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_root(host).add_child(player)
	player.global_position = point
	player.finished.connect(player.queue_free)
	player.play()


static func play_2d(host: Node, stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = AudioSetup.SFX
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.95, 1.05)
	_root(host).add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Reproductor de un bucle de motor que suena en el lugar del nodo al que se añada y se
## apaga con la distancia. Empieza en un punto al azar del bucle para que dos motores iguales
## no suenen acompasados.
static func loop_player(stream: AudioStream, unit_size: float = 10.0, max_distance: float = 180.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = AudioSetup.SFX
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# Los archivos ya se importan en bucle; esto lo garantiza si alguno no lo estuviera.
	player.finished.connect(player.play)
	player.ready.connect(func() -> void: player.play(randf() * maxf(stream.get_length() - 0.1, 0.0)))
	return player


static func _root(host: Node) -> Node:
	var tree: SceneTree = host.get_tree()
	return tree.current_scene if tree.current_scene != null else tree.root
