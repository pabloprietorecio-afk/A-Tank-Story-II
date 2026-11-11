class_name VoiceManager
extends Node
## Voces de la tripulación y de la radio (Kokoro TTS, pregeneradas).
## API: say(evento, prioridad). Las críticas interrumpen; el resto hace cola.
## Cada evento tiene un tiempo mínimo entre repeticiones para no saturar.
## Desacoplado: el juego llama con get_tree().call_group("voice", "say", ...).

enum Priority { LOW, NORMAL, HIGH, CRITICAL }

## Evento → variantes de audio.
const EVENTS: Dictionary = {
	"raid": ["raid_1", "raid_2"],
	"strike": ["strike_1", "strike_2"],
	"strike_denied": ["strike_denied"],
	"reinforcements": ["reinforcements"],
	"mission_start": ["mission_start"],
	"missile": ["missile"],
	"radar": ["radar_1", "radar_2"],
	"kill": ["kill_1", "kill_2", "kill_3"],
	"objective": ["objective"],
	"mission_win": ["mission_win"],
	"mission_fail": ["mission_fail"],
	"wave_start": ["wave_start"],
	"wave_clear": ["wave_clear"],
	"armor_low": ["armor_low"],
	"hit": ["hit_1", "hit_2"],
	"locked": ["locked"],
	"pickup": ["pickup"],
	"bonus": ["bonus"],
	"flag_taken": ["flag_taken"],
	"flag_lost": ["flag_lost"],
	"flag_capture": ["flag_capture"],
	"liberation": ["liberation"],
	"cease_fire": ["cease_fire"],
	"commander": ["commander"],
	"air_phase": ["air_phase"],
	"shot_down": ["shot_down_1", "shot_down_2"],
	"air_clear": ["air_clear"],
	# Órdenes del jugador a sus aliados.
	"follow_on": ["follow_on"],
	"follow_off": ["follow_off"],
	"focus_fire": ["focus_fire"],
	"focus_none": ["focus_none"],
}
## Segundos mínimos entre dos veces el mismo evento.
const COOLDOWNS: Dictionary = {
	"kill": 3.0, "hit": 6.0, "radar": 25.0, "locked": 8.0, "pickup": 4.0, "bonus": 4.0,
	"reinforcements": 40.0, "shot_down": 1.5, "armor_low": 20.0, "cease_fire": 4.0, "objective": 2.0,
	"follow_on": 1.0, "follow_off": 1.0, "focus_fire": 1.0, "focus_none": 4.0,
}
const MAX_QUEUE: int = 3
const RADAR_RANGE: float = 200.0

var player: Tank

var _player: AudioStreamPlayer
var _current_priority: int = -1
var _queue: Array = []
var _last_time: Dictionary = {}
var _streams: Dictionary = {}
var _radar_timer: float = 1.0
var _had_contacts: bool = false
var _armor_warned: bool = false


func _ready() -> void:
	add_to_group(&"voice")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = AudioSetup.VOICE
	_player.volume_db = 2.0
	_player.finished.connect(_play_next)
	add_child(_player)
	for event in EVENTS:
		for id in EVENTS[event]:
			# Voces del idioma activo; si falta alguna, la española antes que ninguna.
			var path: String = "%s/%s.ogg" % [Loc.voice_dir(), id]
			if not ResourceLoader.exists(path):
				path = "res://assets/voice/%s.ogg" % id
			_streams[id] = load(path)
	if player != null:
		player.damaged.connect(_on_player_damaged)


func say(event: String, priority: int = Priority.NORMAL) -> void:
	if not EVENTS.has(event):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_time.get(event, -999.0) < COOLDOWNS.get(event, 0.0):
		return
	_last_time[event] = now
	var stream: AudioStream = _streams[EVENTS[event].pick_random()]
	if not _player.playing:
		_start(stream, priority)
	elif priority == Priority.CRITICAL and _current_priority < Priority.CRITICAL:
		_queue.clear()
		_start(stream, priority)
	elif priority > Priority.LOW and _queue.size() < MAX_QUEUE:
		_queue.append([stream, priority])
		_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])


## Locución que no es un evento fijo (instrucciones del tutorial). Corta lo que suene de
## menor prioridad y descarta lo que hubiera en cola.
func say_stream(stream: AudioStream, priority: int = Priority.HIGH) -> void:
	if stream == null:
		return
	if not _player.playing or priority >= _current_priority:
		_queue.clear()
		_start(stream, priority)
	elif _queue.size() < MAX_QUEUE:
		_queue.append([stream, priority])


func _start(stream: AudioStream, priority: int) -> void:
	_player.stream = stream
	_current_priority = priority
	_player.play()


func _play_next() -> void:
	_current_priority = -1
	if not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_start(next[0], next[1])


func _process(delta: float) -> void:
	if player == null or player.is_destroyed or get_tree().paused:
		return
	_radar_timer -= delta
	if _radar_timer > 0.0:
		return
	_radar_timer = 1.0
	# "Tanques en el radar" cuando aparecen enemigos tras un rato sin ninguno.
	var contacts: bool = false
	for node in get_tree().get_nodes_in_group(&"tanks"):
		var tank := node as Tank
		if tank != null and not tank.is_destroyed and player.is_hostile_to(tank) and tank.global_position.distance_to(player.global_position) <= RADAR_RANGE:
			contacts = true
			break
	if contacts and not _had_contacts:
		say("radar", Priority.NORMAL)
	_had_contacts = contacts
	if player.health.fraction() > 0.5:
		_armor_warned = false


func _on_player_damaged(_amount: float, _source: Node) -> void:
	if player.health.is_dead:
		return
	if player.health.fraction() < 0.3 and not _armor_warned:
		_armor_warned = true
		say("armor_low", Priority.HIGH)
	else:
		say("hit", Priority.LOW)
