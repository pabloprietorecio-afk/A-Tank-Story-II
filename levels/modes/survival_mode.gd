class_name SurvivalMode
extends GameMode
## Supervivencia: oleadas sin fin que crecen poco a poco. Termina cuando destruyen al jugador.

const MAX_ALIVE_LIMIT: int = 5
const WAVE_PAUSE: float = 4.0
const SPAWN_MIN: float = 80.0
const SPAWN_MAX: float = 150.0
const REPAIR_PER_WAVE: float = 40.0
const WAVE_BONUS: int = 250

var wave: int = 0
var alive: int = 0

var _pending: Array[TankStats] = []
var _pause: float = 2.0
var _wave_active: bool = false
var _seen_types: Dictionary = {}
var _intro_queue: Array[TankStats] = []
var _intro_timer: float = 0.0

## Fase aérea entre oleadas (desde la oleada 3): cámara lenta y zoom durante 20 s.
const AIR_PHASE_TIME: float = 20.0
const SLOW_MOTION: float = 0.45
var air_phase: bool = false
var _air_end_msec: int = 0
var _air_spawn_timer: float = 0.0
var _air_spawned: int = 0


func start(player_tank: Tank, world_root: Node3D) -> void:
	super.start(player_tank, world_root)
	message.emit(Loc.t("%s — PREPÁRATE") % Loc.t(Fronts.NAMES[front]), false)


func raids_active() -> bool:
	return wave >= 2 and not air_phase


func _status_normal() -> String:
	return Loc.t("PUNTOS %d   OLEADA %d   ENEMIGOS %d") % [score, wave, alive]


func _process(delta: float) -> void:
	if is_over:
		if air_phase:
			_end_air_phase()
		return
	if air_phase:
		_update_air_phase(delta)
		return
	if not _wave_active:
		_pause -= delta
		if _pause <= 0.0:
			_begin_wave()
		return
	_intro_timer -= delta
	if _intro_timer <= 0.0 and not _intro_queue.is_empty():
		var stats: TankStats = _intro_queue.pop_front()
		message.emit(Loc.t("NUEVO ENEMIGO: %s — %s") % [stats.display_name, Loc.t(stats.description)], true)
		_intro_timer = 4.0
	while alive < max_alive() and not _pending.is_empty():
		_spawn(_pending.pop_back())
	if alive == 0 and _pending.is_empty():
		_end_wave()


## Enemigos simultáneos: 2 al principio, sube de uno en uno cada 3 oleadas.
func max_alive() -> int:
	return mini(2 + (wave - 1) / 3, MAX_ALIVE_LIMIT)


## Presupuesto de amenaza que crece despacio: 2, 3, 3, 4, 4, 5...
func wave_budget(n: int) -> int:
	return 2 + n / 2


func wave_composition(n: int) -> Array[TankStats]:
	var list: Array[TankStats] = []
	var budget: int = wave_budget(n)
	var pool: Array[TankStats] = roster(ENEMY_TEAM)
	# El tipo recién desbloqueado aparece siempre en su primera oleada.
	for stats in pool:
		if stats.unlock_wave == n and stats.cost <= budget:
			list.append(stats)
			budget -= stats.cost
	while budget > 0:
		var options: Array[TankStats] = []
		var weights: Array[float] = []
		for stats in pool:
			if stats.unlock_wave <= n and stats.cost <= budget:
				options.append(stats)
				weights.append(1.0 + float(stats.unlock_wave) / 4.0)
		if options.is_empty():
			break
		var pick: TankStats = options[_weighted_index(weights)]
		list.append(pick)
		budget -= pick.cost
	# Dificultad: en fácil sale uno menos; en difícil e inferno, uno o dos más por oleada.
	var extra: int = GameSettings.batch_extra()
	if extra < 0 and list.size() > 1:
		list.pop_back()
	for i in maxi(extra, 0):
		var unlocked: Array[TankStats] = pool.filter(func(s: TankStats) -> bool: return s.unlock_wave <= n)
		if not unlocked.is_empty():
			list.append(unlocked.pick_random())
	list.shuffle()
	return list


func _weighted_index(weights: Array[float]) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


func _begin_wave() -> void:
	wave += 1
	_pending = wave_composition(wave)
	for stats in _pending:
		if not _seen_types.has(stats.id):
			_seen_types[stats.id] = true
			_intro_queue.append(stats)
	_intro_timer = 3.0
	_wave_active = true
	message.emit(Loc.t("OLEADA %d — %d ENEMIGOS") % [wave, _pending.size()], true)
	get_tree().call_group(&"voice", &"say", "wave_start", VoiceManager.Priority.HIGH)


func _end_wave() -> void:
	_wave_active = false
	_pause = WAVE_PAUSE
	score += WAVE_BONUS
	player.health.heal(REPAIR_PER_WAVE)
	GameSession.record_wave(wave)
	message.emit(Loc.t("OLEADA %d SUPERADA  +%d  BLINDAJE REPARADO") % [wave, WAVE_BONUS], false)
	get_tree().call_group(&"voice", &"say", "wave_clear", VoiceManager.Priority.HIGH)
	if wave >= 3:
		_start_air_phase()
	# Cada 4 oleadas se repone el arsenal especial.
	if wave % 4 == 0:
		missiles = 2
		strikes = 1
		message.emit(Loc.t("ARSENAL REPUESTO: 2 MISILES Y 1 BOMBARDEO"), false)


func _start_air_phase() -> void:
	air_phase = true
	_air_end_msec = Time.get_ticks_msec() + int(AIR_PHASE_TIME * 1000.0)
	_air_spawn_timer = 0.0
	_air_spawned = 0
	Engine.time_scale = SLOW_MOTION
	player.set_air_mode(true)
	message.emit(Loc.t("¡ATAQUE AÉREO! DERRIBA CAZAS, AVIONES DE ATAQUE Y BOMBARDEROS"), true)
	get_tree().call_group(&"voice", &"say", "air_phase", VoiceManager.Priority.CRITICAL)


func _update_air_phase(delta: float) -> void:
	# El tiempo de la fase se mide en segundos reales (la cámara lenta no la alarga).
	if Time.get_ticks_msec() >= _air_end_msec:
		_end_air_phase()
		return
	_air_spawn_timer -= delta
	if _air_spawn_timer <= 0.0 and _air_spawned < 4 + wave / 2:
		_air_spawn_timer = 1.6
		_air_spawned += 1
		var kind: int = AirTarget.Kind.FIGHTER
		if _air_spawned % 3 == 0:
			kind = AirTarget.Kind.ATTACK
		elif _air_spawned == 2:
			kind = AirTarget.Kind.BOMBER
		AirTarget.spawn(world, kind, player.global_position)


func air_seconds_left() -> float:
	return maxf((_air_end_msec - Time.get_ticks_msec()) / 1000.0, 0.0)


func _end_air_phase() -> void:
	air_phase = false
	Engine.time_scale = 1.0
	player.set_air_mode(false)
	for node in get_tree().get_nodes_in_group(&"air_targets"):
		(node as AirTarget).leave()
	if not is_over:
		message.emit(Loc.t("CIELO DESPEJADO — PREPÁRATE"), false)
		get_tree().call_group(&"voice", &"say", "air_clear", VoiceManager.Priority.NORMAL)


func status_text() -> String:
	if air_phase:
		return Loc.t("PUNTOS %d   OLEADA %d   ATAQUE AÉREO %d s") % [score, wave, ceili(air_seconds_left())]
	return _status_normal()


func _spawn(stats: TankStats) -> void:
	# Entran por los límites del mapa, de cara al jugador.
	var origin := Vector2(player.global_position.x, player.global_position.z)
	var point: Vector2 = edge_point()
	spawn_tank(stats, ENEMY_TEAM, point, yaw_towards(point, origin))
	alive += 1


func _on_tank_destroyed(tank: Tank, killer: Node) -> void:
	super._on_tank_destroyed(tank, killer)
	if tank.team == ENEMY_TEAM:
		alive -= 1


func _on_player_destroyed(_tank: Tank, _killer: Node) -> void:
	GameSession.record_wave(wave)
	finish(false, Loc.t("TANQUE DESTRUIDO"), Loc.t("PUNTOS %d   OLEADA %d   (RÉCORD %d)") % [score, wave, GameSession.best_wave()])
