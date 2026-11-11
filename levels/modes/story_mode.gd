class_name StoryMode
extends GameMode
## Modo historia: una misión de la campaña. Si destruyen al jugador, la misión fracasa.
## assault: destruir una fuerza enemiga · destroy: volar depósitos · sabotage: destruir un
## complejo (aeródromo, puerto, central, fábrica, cuartel general) · defend: resistir en la
## posición · boss: abatir al comandante · liberate: derribar las alambradas de un campo ·
## breakthrough: cruzar las líneas enemigas hasta la salida, en el extremo norte del mapa.

const ZONE_RADIUS: float = 22.0
const TARGET_CENTER := Vector3(0.0, 0.0, -110.0)
const PENALTY_ARMOR: float = 10.0
const PENALTY_POINTS: int = 200

var mission: Dictionary
var kind: String
var remaining: int = 0
var time_left: float = 0.0
var alive: int = 0

var _to_spawn: int = 0
var _spawn_timer: float = 3.0
var _commander: Tank
var _objectives: Array[Destructible] = []
var _objective_names: Array[String] = []
var _depot_points: Array[Vector2] = []
var _reinforce_timer: float = 40.0
var _penalty_cooldown: float = 0.0
## Objetivos secundarios repartidos lejos del complejo principal (alargan la misión).
var _outposts: Array[Vector2] = []
const MAX_ALIVE: int = 6
## Ruptura: salida al norte y líneas de defensa que hay que cruzar por el camino.
const EXIT_POINT := Vector3(0.0, 0.0, -165.0)
const EXIT_RADIUS: float = 14.0
const DEFENCE_LINES: Array[Vector2] = [Vector2(-55.0, 75.0), Vector2(60.0, 55.0), Vector2(0.0, -10.0), Vector2(-75.0, -70.0), Vector2(70.0, -85.0)]


func _init() -> void:
	super._init()
	mission = GameSession.current_mission()
	kind = mission["type"]


func player_spawn() -> Transform3D:
	if kind == "defend":
		return Transform3D(Basis(), Vector3(0.0, 0.2, 8.0))
	return Transform3D(Basis(), Vector3(0.0, 0.2, 150.0))


func reserved_zones() -> Array[Rect2]:
	var zones: Array[Rect2] = [Rect2(Vector2(-25.0, 125.0), Vector2(50.0, 50.0))]
	match kind:
		"defend":
			zones.append(Rect2(Vector2(-ZONE_RADIUS - 8.0, -ZONE_RADIUS - 8.0), Vector2.ONE * (ZONE_RADIUS + 8.0) * 2.0))
		"destroy":
			_depot_points = [Vector2(-140.0, -130.0), Vector2(0.0, -160.0), Vector2(140.0, -120.0), Vector2(-160.0, 20.0), Vector2(160.0, 40.0)]
			for p in _depot_points:
				zones.append(Rect2(p - Vector2(15.0, 15.0), Vector2(30.0, 30.0)))
		"breakthrough":
			zones.append(Rect2(Vector2(EXIT_POINT.x, EXIT_POINT.z) - Vector2.ONE * (EXIT_RADIUS + 8.0), Vector2.ONE * (EXIT_RADIUS + 8.0) * 2.0))
		"sabotage", "liberate":
			zones.append(Rect2(Vector2(TARGET_CENTER.x, TARGET_CENTER.z) - Vector2(55.0, 50.0), Vector2(110.0, 100.0)))
			# Tres puestos secundarios en otras zonas del mapa.
			var candidates: Array[Vector2] = [Vector2(-150.0, -10.0), Vector2(150.0, 20.0), Vector2(-120.0, 90.0), Vector2(130.0, 100.0), Vector2(-160.0, -150.0), Vector2(160.0, -150.0)]
			candidates.shuffle()
			for i in 3:
				var p: Vector2 = candidates[i] + Vector2(randf_range(-15.0, 15.0), randf_range(-15.0, 15.0))
				_outposts.append(p)
				zones.append(Rect2(p - Vector2(14.0, 14.0), Vector2(28.0, 28.0)))
	return zones


func start(player_tank: Tank, world_root: Node3D) -> void:
	super.start(player_tank, world_root)
	message.emit("%s — %s" % [Loc.t(mission["title"]), _objective_line()], true)
	get_tree().call_group(&"voice", &"say", "mission_start", VoiceManager.Priority.HIGH)
	for i in mission.get("allies", 0):
		var stats: TankStats = roster(PLAYER_TEAM).filter(func(s: TankStats) -> bool: return s.tier <= 2).pick_random()
		var spawn: Vector3 = player_spawn().origin
		spawn_tank(stats, PLAYER_TEAM, Vector2(spawn.x + (i + 1) * 9.0 * (1 if i % 2 == 0 else -1), spawn.z + 6.0))
	match kind:
		"assault":
			remaining = maxi(roundi(mission["count"] * 2 * GameSettings.total_factor()), 2)
			_to_spawn = remaining
		"destroy":
			for n in _depot_points.size():
				var point: Vector2 = _depot_points[n]
				var depot := PropFactory.supply_depot()
				depot.remove_from_group(&"radar_marks")
				StructureFactory._objective(depot, Loc.t("DEPÓSITO %d") % (n + 1))
				depot.position = Vector3(point.x, 0.0, point.y)
				world.add_child(depot)
				_track(depot)
				_guards(point, 2 if n < 3 else 1)
		"sabotage":
			for part in StructureFactory.build(mission["target"], world, TARGET_CENTER, 0.0):
				_track(part)
			_guards(Vector2(TARGET_CENTER.x, TARGET_CENTER.z), 6)
			_build_outposts()
		"liberate":
			for part in StructureFactory.camp(world, TARGET_CENTER, mission["count"]):
				_track(part)
			# La guardia vigila desde fuera de las alambradas, no encerrada en el campo.
			_guards(Vector2(TARGET_CENTER.x, TARGET_CENTER.z), 5, 52.0, 78.0)
			_build_outposts()
		"defend":
			time_left = mission["time"]
			_build_zone()
		"breakthrough":
			_build_exit()
			for point in DEFENCE_LINES:
				_guards(point, 2)
			_guards(Vector2(EXIT_POINT.x, EXIT_POINT.z), 2)
		"boss":
			var heaviest: TankStats = roster(ENEMY_TEAM)[0]
			for stats in roster(ENEMY_TEAM):
				if stats.max_armor > heaviest.max_armor:
					heaviest = stats
			var boss_stats: TankStats = heaviest.duplicate()
			boss_stats.max_armor *= 1.5
			boss_stats.display_name = Loc.t("COMANDANTE (%s)") % heaviest.display_name
			boss_stats.score_value *= 3
			_commander = spawn_tank(boss_stats, ENEMY_TEAM, Vector2(randf_range(-60.0, 60.0), -150.0), 0.0)
			_commander.add_to_group(&"radar_marks")
			_commander.set_meta("radar_color", Color(0.85, 0.3, 1.0))
			_commander.set_meta("radar_shape", "diamond")
			_to_spawn = maxi(roundi(mission["count"] * 2 * GameSettings.total_factor()), 1)
	remaining = _objectives.size() if not _objectives.is_empty() else remaining


## Puestos secundarios: antiaéreo, antena de radio y puesto de mando, cada uno con guardia.
func _build_outposts() -> void:
	var builders: Array = [[StructureFactory.flak_gun, Loc.t("ANTIAÉREO")], [StructureFactory.radio_mast, Loc.t("ANTENA")], [StructureFactory.command_tent, Loc.t("PUESTO AVANZADO")]]
	for i in _outposts.size():
		var point: Vector2 = _outposts[i]
		var prop: Destructible = builders[i % builders.size()][0].call()
		prop.prize_points = 0
		StructureFactory._objective(prop, Loc.t("%s (SECUNDARIO)") % builders[i % builders.size()][1])
		prop.position = Vector3(point.x, 0.0, point.y)
		world.add_child(prop)
		_track(prop)
		_guards(point, 2)


func _track(part: Destructible) -> void:
	_objectives.append(part)
	_objective_names.append(part.objective_name)
	part.destroyed.connect(_on_objective_destroyed)


func _guards(point: Vector2, count: int, min_radius: float = 15.0, max_radius: float = 45.0) -> void:
	for g in count:
		var guard: Tank = _spawn_enemy(free_point_near(point, min_radius, max_radius))
		var brain: AIBrain = guard.get_node("AIBrain")
		brain.hunt = false
		brain.objective = Vector3(point.x, 0.0, point.y)
		brain.objective_radius = 30.0 if max_radius <= 45.0 else max_radius


func _objective_line() -> String:
	match kind:
		"assault":
			return Loc.t("DESTRUYE %d BLINDADOS") % mission["count"]
		"destroy":
			return Loc.t("DESTRUYE LOS DEPÓSITOS (ROMBOS EN EL RADAR)")
		"sabotage":
			return Loc.t("DESTRUYE EL %s (ROMBOS EN EL RADAR)") % Loc.t(StructureFactory.COMPLEX_NAMES[mission["target"]])
		"liberate":
			return Loc.t("DERRIBA LAS ALAMBRADAS. NO DISPARES A LOS BARRACONES")
		"defend":
			return Loc.t("RESISTE EN LA POSICIÓN %d s") % int(mission["time"])
		"breakthrough":
			return Loc.t("CRUZA LAS LÍNEAS ENEMIGAS HASTA LA SALIDA (ROMBO AZUL EN EL RADAR)")
		_:
			return Loc.t("DESTRUYE AL COMANDANTE (ROMBO VIOLETA EN EL RADAR)")


func status_text() -> String:
	match kind:
		"assault":
			return Loc.t("%s   ENEMIGOS RESTANTES %d") % [Loc.t(mission["title"]), remaining]
		"destroy", "sabotage", "liberate":
			return Loc.t("%s   OBJETIVOS %d / %d") % [Loc.t(mission["title"]), _objectives.size() - remaining, _objectives.size()]
		"defend":
			return Loc.t("%s   RESISTE %d s") % [Loc.t(mission["title"]), ceili(time_left)]
		"breakthrough":
			return Loc.t("%s   SALIDA A %d m") % [Loc.t(mission["title"]), roundi(_exit_distance())]
		_:
			return Loc.t("%s   COMANDANTE %d%%") % [Loc.t(mission["title"]), roundi(_commander.health.fraction() * 100.0) if is_instance_valid(_commander) else 0]


## Lista de objetivos para el HUD: ✔ cumplido, ▢ pendiente.
func objective_lines() -> Array[String]:
	var lines: Array[String] = []
	for i in _objectives.size():
		var done: bool = not is_instance_valid(_objectives[i]) or _objectives[i].is_destroyed
		lines.append("%s %s" % ["✔" if done else "▢", _objective_names[i]])
	if kind == "breakthrough":
		lines.append(Loc.t("%s ALCANZAR LA SALIDA (NORTE)") % ("✔" if is_over and _exit_distance() <= EXIT_RADIUS else "▢"))
	if kind == "boss":
		lines.append("%s %s" % ["▢" if is_instance_valid(_commander) and not _commander.is_destroyed else "✔", Loc.t("COMANDANTE")])
	return lines


## Disparo contra zona protegida (barracones con prisioneros).
func penalize(_source: Node) -> void:
	if _penalty_cooldown > 0.0 or is_over:
		return
	_penalty_cooldown = 1.0
	player.health.apply_damage(PENALTY_ARMOR, null)
	score = maxi(score - PENALTY_POINTS, 0)
	message.emit(Loc.t("¡ALTO EL FUEGO! HAY PRISIONEROS EN LOS BARRACONES  −%d") % PENALTY_POINTS, true)
	get_tree().call_group(&"voice", &"say", "cease_fire", VoiceManager.Priority.CRITICAL)


func _process(delta: float) -> void:
	if is_over:
		return
	_penalty_cooldown = maxf(_penalty_cooldown - delta, 0.0)
	_spawn_timer -= delta
	match kind:
		"assault", "boss":
			if _to_spawn > 0 and alive < 5 + GameSettings.batch_extra() and _spawn_timer <= 0.0:
				_spawn_timer = 3.0
				_to_spawn -= 1
				_spawn_enemy(edge_point())
		"destroy", "sabotage", "liberate":
			_reinforce_timer -= delta
			if _reinforce_timer <= 0.0 and alive < MAX_ALIVE + 2:
				_reinforce_timer = 25.0 / minf(GameSettings.total_factor(), 1.0)
				# Los refuerzos entran por los límites del mapa y van a por el jugador.
				get_tree().call_group(&"voice", &"say", "reinforcements", VoiceManager.Priority.NORMAL)
				for i in GameSettings.batch(2):
					_spawn_enemy(edge_point())
		"breakthrough":
			if _exit_distance() <= EXIT_RADIUS:
				_win(Loc.t("LÍNEAS ENEMIGAS ATRAVESADAS"))
				return
			_reinforce_timer -= delta
			if _reinforce_timer <= 0.0 and alive < MAX_ALIVE + 6:
				_reinforce_timer = 35.0 / minf(GameSettings.total_factor(), 1.0)
				# Perseguidores que entran por los límites del mapa.
				get_tree().call_group(&"voice", &"say", "reinforcements", VoiceManager.Priority.NORMAL)
				for i in GameSettings.batch(1):
					_spawn_enemy(edge_point())
		"defend":
			time_left -= delta
			if time_left <= 0.0:
				_win(Loc.t("POSICIÓN DEFENDIDA"))
				return
			var elapsed: float = mission["time"] - time_left
			if alive < 4 + GameSettings.batch_extra() + int(elapsed / 40.0) and _spawn_timer <= 0.0:
				_spawn_timer = 4.0
				var tank: Tank = _spawn_enemy(edge_point(110.0, true))
				var brain: AIBrain = tank.get_node("AIBrain")
				brain.hunt = false
				brain.objective = Vector3.ZERO
				brain.objective_radius = ZONE_RADIUS


func _spawn_enemy(point: Vector2) -> Tank:
	var pool: Array[TankStats] = roster(ENEMY_TEAM)
	var index: int = GameSession.mission_index
	# Cuanto más avanzada la misión, más pesados pueden salir.
	var max_tier: int = 2 if index < 2 else 3
	var options: Array[TankStats] = pool.filter(func(s: TankStats) -> bool: return s.tier <= max_tier)
	alive += 1
	var yaw: float = PI
	if is_instance_valid(player):
		yaw = yaw_towards(point, Vector2(player.global_position.x, player.global_position.z))
	return spawn_tank(options.pick_random(), ENEMY_TEAM, point, yaw)


## Distancia del jugador a la salida (misiones de ruptura).
func _exit_distance() -> float:
	if not is_instance_valid(player):
		return INF
	return Vector2(player.global_position.x - EXIT_POINT.x, player.global_position.z - EXIT_POINT.z).length()


## Salida de las misiones de ruptura: un círculo de postes azules y un rombo en el radar.
func _build_exit() -> void:
	for i in 16:
		var angle: float = TAU * i / 16.0
		var post := VectorMaterials.make_box(Vector3(0.3, 2.2, 0.3), Color(0.3, 0.9, 1.0), 0, 1.0)
		post.position = EXIT_POINT + Vector3(cos(angle) * EXIT_RADIUS, 1.1, sin(angle) * EXIT_RADIUS)
		world.add_child(post)
	var marker := Node3D.new()
	marker.add_to_group(&"radar_marks")
	marker.set_meta("radar_color", Color(0.3, 0.9, 1.0))
	marker.set_meta("radar_shape", "diamond")
	world.add_child(marker)
	marker.position = EXIT_POINT


func _build_zone() -> void:
	for i in 16:
		var angle: float = TAU * i / 16.0
		var post := VectorMaterials.make_box(Vector3(0.3, 1.5, 0.3), Color(0.9, 0.75, 0.2), 0, 1.0)
		post.position = Vector3(cos(angle) * ZONE_RADIUS, 0.75, sin(angle) * ZONE_RADIUS)
		world.add_child(post)
	var marker := Node3D.new()
	marker.add_to_group(&"radar_marks")
	marker.set_meta("radar_color", Color(0.3, 0.9, 1.0))
	marker.set_meta("radar_shape", "diamond")
	world.add_child(marker)
	for side in [-1.0, 1.0]:
		var bags := PropFactory.sandbags(10.0)
		bags.position = Vector3(side * 12.0, 0.0, -10.0)
		bags.rotation.y = side * 0.4
		world.add_child(bags)


func _on_objective_destroyed(prop: Destructible) -> void:
	remaining -= 1
	score += 300
	message.emit(Loc.t("%s DESTRUIDO — QUEDAN %d") % [prop.objective_name, remaining], true)
	if remaining > 0:
		get_tree().call_group(&"voice", &"say", "objective", VoiceManager.Priority.HIGH)
	if remaining <= 0:
		_win(Loc.t("LAS ALAMBRADAS HAN CAÍDO. LOS PRISIONEROS SON LIBRES") if kind == "liberate" else Loc.t("OBJETIVOS CUMPLIDOS"))


func _on_tank_destroyed(tank: Tank, killer: Node) -> void:
	super._on_tank_destroyed(tank, killer)
	if tank.team != ENEMY_TEAM:
		return
	alive -= 1
	if tank == _commander:
		_commander.remove_from_group(&"radar_marks")
		get_tree().call_group(&"voice", &"say", "commander", VoiceManager.Priority.HIGH)
		_win(Loc.t("COMANDANTE ABATIDO"))
	elif kind == "assault":
		remaining -= 1
		if remaining <= 0:
			_win(Loc.t("ZONA DESPEJADA"))


func _win(detail: String) -> void:
	if kind == "liberate":
		get_tree().call_group(&"voice", &"say", "liberation", VoiceManager.Priority.CRITICAL)
	finish(true, Loc.t("¡MISIÓN CUMPLIDA!"), "%s — %s" % [Loc.t(mission["title"]), detail])
	GameSession.mark_mission_completed(GameSession.mission_index)


func _on_player_destroyed(_tank: Tank, _killer: Node) -> void:
	finish(false, Loc.t("MISIÓN FRACASADA"), Loc.t("%s — TU TANQUE HA SIDO DESTRUIDO") % Loc.t(mission["title"]))


func has_next_mission() -> bool:
	return GameSession.mission_index + 1 < GameSession.missions().size()
