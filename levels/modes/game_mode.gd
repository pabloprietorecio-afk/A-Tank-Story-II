class_name GameMode
extends Node
## Base de los modos de juego. Crea tanques de cada bando, lleva la puntuación y decide
## cuándo termina la partida. El HUD solo conoce esta interfaz.

signal message(text: String, urgent: bool)
signal ended(victory: bool, title: String, detail: String)

const PLAYER_TEAM: int = 0
const ENEMY_TEAM: int = 1

var player: Tank
var world: Node3D
var front: int
var is_over: bool = false
var score: int = 0
## Callable(Vector2) -> bool: punto libre de obstáculos.
var is_free_point: Callable = func(_p: Vector2) -> bool: return true

## Arsenal especial por misión/partida.
var missiles: int = 2
var strikes: int = 1
## Bombardeos enemigos sobre la posición del jugador (0 = desactivados).
var raid_interval: Vector2 = Vector2(55.0, 85.0)
var raid_first: float = 45.0

## Órdenes al bando del jugador: «todos conmigo» (siguen al jugador) y ataque al objetivo marcado.
var follow_me: bool = false
var focus_target: Tank = null
## Aliados con vida (se cuentan cada medio segundo; el HUD solo ofrece las órdenes si hay).
var allies_alive: int = 0
const FOCUS_CONE: float = 0.35
const FOCUS_RANGE: float = 420.0

var _command_timer: float = 0.0
var _rosters: Dictionary = {}
var _raid_timer: float = 45.0
## Caja de cada forma de colisión ya medida (ver _solid_shapes).
var _shape_bounds: Dictionary = {}


func _init() -> void:
	front = GameSession.front
	_rosters[PLAYER_TEAM] = Fronts.roster(front, GameSession.faction)
	_rosters[ENEMY_TEAM] = Fronts.roster(front, GameSession.enemy_faction())


func roster(team: int) -> Array[TankStats]:
	return _rosters[team]


func faction_of(team: int) -> int:
	return GameSession.faction if team == PLAYER_TEAM else GameSession.enemy_faction()


## Dónde aparece el jugador.
func player_spawn() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, 0.2, 0.0))


## ¿Monta la arena el decorado del frente (pueblos, colinas, edificios con premio)?
func wants_scenery() -> bool:
	return true


## ¿Reparte la arena premios al azar por el terreno?
func wants_pickups() -> bool:
	return true


## Clima obligado (Weather.Kind) o -1 para sortearlo entre los del frente.
func forced_weather() -> int:
	return -1


## La arena entrega aquí la interfaz ya montada, antes de start().
func bind_ui(_hud: Hud, _touch: TouchControls, _radar: Radar, _input: PlayerInputSource) -> void:
	pass


## Zonas que el escenario debe dejar libres (bases, posiciones a defender).
func reserved_zones() -> Array[Rect2]:
	return []


func start(player_tank: Tank, world_root: Node3D) -> void:
	player = player_tank
	world = world_root
	add_to_group(&"game_mode")
	player.destroyed.connect(_on_player_destroyed)
	_raid_timer = raid_first


func _physics_process(delta: float) -> void:
	_update_commands(delta)
	if is_over or raid_interval == Vector2.ZERO or not raids_active():
		return
	_raid_timer -= delta
	if _raid_timer <= 0.0:
		_raid_timer = randf_range(raid_interval.x, raid_interval.y)
		enemy_air_raid()


## ¿Ofrece el HUD las órdenes a los aliados? (El tutorial no.)
func wants_commands() -> bool:
	return true


## ¿Puede este aliado seguir al jugador? (Captura la bandera reserva al que lleva o rescata una bandera.)
func can_follow(_tank: Tank) -> bool:
	return true


## Cada medio segundo pone al día las órdenes de los aliados (también las de los que acaban de aparecer).
func _update_commands(delta: float) -> void:
	_command_timer -= delta
	if _command_timer > 0.0 or player == null:
		return
	_command_timer = 0.5
	if not is_instance_valid(focus_target) or focus_target.is_destroyed:
		focus_target = null
	allies_alive = 0
	for node in get_tree().get_nodes_in_group(&"ai_brains"):
		var brain := node as AIBrain
		if brain == null or brain.tank == null or brain.tank.is_destroyed or brain.tank.team != player.team:
			continue
		allies_alive += 1
		brain.set_follow(player if follow_me and not player.is_destroyed and can_follow(brain.tank) else null)
		brain.forced_target = focus_target


## «Todos conmigo»: los aliados siguen al jugador a donde vaya (otra pulsación, y vuelven a lo suyo).
func toggle_follow() -> void:
	if is_over or player == null or player.is_destroyed:
		return
	follow_me = not follow_me
	_command_timer = 0.0
	_update_commands(0.0)
	get_tree().call_group(&"voice", &"say", "follow_on" if follow_me else "follow_off", VoiceManager.Priority.HIGH)
	message.emit(Loc.t("TODOS CONMIGO: TUS ALIADOS TE SIGUEN") if follow_me else Loc.t("TODOS LIBRES: TUS ALIADOS ACTÚAN POR SU CUENTA"), false)


## Todo el bando ataca al objetivo fijado del jugador o, si no hay, al enemigo que tiene bajo la mira.
func focus_fire() -> void:
	if is_over or player == null or player.is_destroyed:
		return
	var enemy: Tank = player.aim_lock if is_instance_valid(player.aim_lock) and not player.aim_lock.is_destroyed else _enemy_under_crosshair()
	if enemy == null:
		get_tree().call_group(&"voice", &"say", "focus_none", VoiceManager.Priority.NORMAL)
		message.emit(Loc.t("SIN OBJETIVO: APUNTA A UN ENEMIGO"), false)
		return
	focus_target = enemy
	_command_timer = 0.0
	_update_commands(0.0)
	get_tree().call_group(&"voice", &"say", "focus_fire", VoiceManager.Priority.HIGH)
	message.emit(Loc.t("TODOS CONTRA %s") % enemy.stats.display_name, false)


## El enemigo más cercano a la dirección en la que apunta el cañón (dentro de un cono amplio).
func _enemy_under_crosshair() -> Tank:
	var origin: Vector3 = player.muzzle.global_position
	var aim: Vector3 = -player.muzzle.global_transform.basis.z
	var best: Tank = null
	var best_angle: float = FOCUS_CONE
	for node in get_tree().get_nodes_in_group(&"tanks"):
		var other := node as Tank
		if other == null or other.is_destroyed or not player.is_hostile_to(other):
			continue
		var to: Vector3 = other.global_position + Vector3.UP * 1.2 - origin
		if to.length() > FOCUS_RANGE:
			continue
		var angle: float = aim.angle_to(to)
		if angle < best_angle:
			best_angle = angle
			best = other
	return best


## Premios de la aviación y de misiles recogidos del suelo (vía grupo "game_mode").
func grant_missiles(count: int) -> void:
	missiles += count


func grant_strikes(count: int) -> void:
	strikes += count


## ¿Hay bombardeos enemigos ahora? (Supervivencia los activa a partir de la oleada 2.)
func raids_active() -> bool:
	return true


## Bombardeo enemigo sobre la posición actual del jugador: hay 4 s para salir de la zona.
func enemy_air_raid() -> void:
	if player == null or player.is_destroyed:
		return
	AirStrike.launch(world, player.global_position, true)
	get_tree().call_group(&"voice", &"say", "raid", VoiceManager.Priority.CRITICAL)
	message.emit(Loc.t("¡BOMBARDEO ENEMIGO! SAL DE LA ZONA ROJA"), true)


## Premio por derribar un avión enemigo: blindaje, misil o bombardeo.
func air_reward(_where: Vector3) -> void:
	score += 200
	get_tree().call_group(&"voice", &"say", "shot_down", VoiceManager.Priority.HIGH)
	match randi() % 3:
		0:
			player.health.heal(40.0)
			message.emit(Loc.t("¡DERRIBADO! +40 DE BLINDAJE"), false)
		1:
			missiles += 1
			message.emit(Loc.t("¡DERRIBADO! +1 MISIL"), false)
		_:
			strikes += 1
			message.emit(Loc.t("¡DERRIBADO! +1 BOMBARDEO"), false)


## Misil guiado: va a por el objetivo fijado (si lo hay).
func fire_missile() -> bool:
	if missiles <= 0 or is_over or player.is_destroyed:
		return false
	missiles -= 1
	Missile.fire(player, player.aim_lock)
	get_tree().call_group(&"voice", &"say", "missile", VoiceManager.Priority.NORMAL)
	message.emit(Loc.t("MISIL LANZADO — QUEDAN %d") % missiles, false)
	return true


## Bombardeo aliado sobre el punto al que apunta el cañón (o el objetivo fijado).
func call_air_strike() -> bool:
	if strikes <= 0 or is_over or player.is_destroyed:
		return false
	var point: Vector3
	if is_instance_valid(player.aim_lock):
		point = player.aim_lock.global_position
	else:
		var from: Vector3 = player.muzzle.global_position
		var to: Vector3 = from - player.muzzle.global_transform.basis.z * 300.0
		to.y = minf(to.y, 0.0)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		point = hit["position"] if not hit.is_empty() else from - player.muzzle.global_transform.basis.z * 150.0
	if Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length() < 30.0:
		message.emit(Loc.t("DEMASIADO CERCA PARA BOMBARDEAR: APUNTA MÁS LEJOS"), true)
		get_tree().call_group(&"voice", &"say", "strike_denied", VoiceManager.Priority.HIGH)
		return false
	strikes -= 1
	AirStrike.launch(world, point, false, player)
	get_tree().call_group(&"voice", &"say", "strike", VoiceManager.Priority.HIGH)
	message.emit(Loc.t("BOMBARDEO ALIADO EN CAMINO"), false)
	return true


## Llamado por premios y edificios destruidos (vía grupo "game_mode").
func add_score(points: int) -> void:
	if not is_over:
		score += points


func announce(text: String, urgent: bool) -> void:
	message.emit(text, urgent)


## Marcador de banderas para el HUD (solo captura la bandera): {"score": texto, "flags": [
## {"color": Color, "title": texto, "state": texto, "alert": bool}, ...]}. Vacío = no se dibuja.
func flag_board() -> Dictionary:
	return {}


## Líneas de objetivos para el HUD (vacío si el modo no tiene objetivos concretos).
func objective_lines() -> Array[String]:
	return []


func status_text() -> String:
	return Loc.t("PUNTOS %d") % score


## Crea un tanque controlado por la máquina.
func spawn_tank(stats: TankStats, team: int, pos: Vector2, yaw: float = 0.0) -> Tank:
	var level: int = GameSettings.difficulty
	if team == ENEMY_TEAM and level != 1:
		# La dificultad cambia la pericia de las tripulaciones enemigas (en NORMAL, la de siempre).
		stats = stats.duplicate()
		stats.aim_error_deg *= GameSettings.SKILL_AIM_ERROR[level]
		stats.reload_time *= GameSettings.SKILL_RELOAD[level]
		stats.detect_range *= GameSettings.SKILL_SIGHT[level]
		stats.lead_factor = minf(stats.lead_factor * (0.6 if level == 0 else 1.25), 1.0)
	# Nunca dentro de un edificio, una colina u otro tanque: se corre al hueco más cercano.
	if not fits(pos):
		pos = free_point_near(pos, 0.0, 12.0)
	var tank := Tank.new()
	tank.name = "Tank"
	tank.stats = stats
	tank.team = team
	tank.paint = Fronts.paint(front, faction_of(team), stats.nation)
	tank.position = Vector3(pos.x, 0.2, pos.y)
	tank.rotation.y = yaw
	world.add_child(tank)
	var brain := AIBrain.new()
	brain.name = "AIBrain"
	tank.add_child(brain)
	brain.setup(tank)
	if team == ENEMY_TEAM:
		brain.aim_interval = GameSettings.SKILL_AIM_INTERVAL[level]
	# Todos los tanques, de los dos bandos, rodean los obstáculos y se desatascan solos.
	brain.smart_nav = true
	# El mapa de rutas empieza a rellenarse ya, antes de que haga falta.
	NavGrid.of(world)
	tank.destroyed.connect(_on_tank_destroyed)
	return tank


## Punto libre cerca de `center` (radio entre min y max) en el que cabe un tanque. Primero se
## busca fuera de las zonas ocupadas o reservadas; si no hay (la guardia de un complejo va
## dentro de su zona), vale cualquier hueco entre lo construido, cada vez un poco más lejos.
func free_point_near(center: Vector2, min_radius: float, max_radius: float) -> Vector2:
	var solids: Array = _solid_shapes()
	var point := center
	for attempt in 90:
		var reach: float = max_radius + maxf(attempt - 30.0, 0.0) * 1.5
		point = (center + Vector2.from_angle(randf() * TAU) * randf_range(min_radius, reach)).clampf(-180.0, 180.0)
		if (attempt >= 30 or is_free_point.call(point)) and _fits_among(point, solids, 4.5):
			return point
	return point


## ¿Cabe un tanque en `point` sin quedar metido dentro de nada ni encima de otro tanque?
func fits(point: Vector2, margin: float = 4.0) -> bool:
	return _fits_among(point, _solid_shapes(), margin)


## Formas de colisión de todo lo que hay en el campo, cada una como [transformación de mundo a
## su espacio, caja que la contiene]. Se miran así, y no preguntando a la física, porque la
## física no ve lo que se acaba de colocar en este mismo fotograma (los edificios de una misión
## y su guardia se ponen a la vez): un tanque que aparece dentro de algo sale despedido hacia
## abajo y se hunde.
func _solid_shapes() -> Array:
	var solids: Array = []
	if world != null:
		_collect_solids(world, solids)
	return solids


func _collect_solids(node: Node, solids: Array) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			var body: StaticBody3D = child
			if body.collision_layer & Tank.LAYER_WORLD == 0:
				continue
			for part in body.get_children():
				var holder := part as CollisionShape3D
				if holder == null or holder.shape == null or holder.disabled:
					continue
				var box: AABB = _bounds_of(holder.shape)
				if box.size != Vector3.ZERO:
					solids.append([(body.global_transform * holder.transform).affine_inverse(), box])
		elif child is Node3D and not child is Tank:
			_collect_solids(child, solids)


func _bounds_of(shape: Shape3D) -> AABB:
	var key: int = shape.get_instance_id()
	if _shape_bounds.has(key):
		return _shape_bounds[key]
	var box := AABB()
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		box = AABB(-size * 0.5, size)
	elif shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if not points.is_empty():
			box = AABB(points[0], Vector3.ZERO)
			for p in points:
				box = box.expand(p)
	elif shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		box = AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	elif shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		box = AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	_shape_bounds[key] = box
	return box


func _fits_among(point: Vector2, solids: Array, margin: float) -> bool:
	# A un metro del suelo: así no cuenta el propio suelo, que queda por debajo.
	var spot := Vector3(point.x, 1.0, point.y)
	for solid: Array in solids:
		var local: Vector3 = (solid[0] as Transform3D) * spot
		var box: AABB = solid[1]
		if local.y >= box.position.y and local.y <= box.end.y and local.x >= box.position.x - margin and local.x <= box.end.x + margin and local.z >= box.position.z - margin and local.z <= box.end.z + margin:
			return false
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(&"tanks"):
			var other := node as Node3D
			if other != null and Vector2(other.global_position.x - point.x, other.global_position.z - point.y).length() < 5.0:
				return false
	return true


## Distancia del centro a la línea por la que entran los refuerzos (el muro está a 200 m).
const EDGE: float = 186.0


## Punto libre en el límite del mapa, a `min_distance` o más del jugador: los enemigos entran
## desde fuera en vez de aparecer de la nada. Con `north_only` solo por el lado norte.
func edge_point(min_distance: float = 110.0, north_only: bool = false) -> Vector2:
	var origin := Vector2.ZERO
	if is_instance_valid(player):
		origin = Vector2(player.global_position.x, player.global_position.z)
	var best := Vector2(0.0, -EDGE)
	var best_distance: float = -1.0
	var solids: Array = _solid_shapes()
	for attempt in 40:
		var along: float = randf_range(-EDGE, EDGE)
		var point := Vector2(along, -EDGE)
		if not north_only:
			match randi() % 4:
				1:
					point = Vector2(along, EDGE)
				2:
					point = Vector2(-EDGE, along)
				3:
					point = Vector2(EDGE, along)
		if not is_free_point.call(point) or not _fits_among(point, solids, 4.0):
			continue
		var distance: float = point.distance_to(origin)
		if distance >= min_distance:
			return point
		if distance > best_distance:
			best_distance = distance
			best = point
	return best


## Giro con el que un tanque situado en `from` queda mirando hacia `to`.
func yaw_towards(from: Vector2, to: Vector2) -> float:
	var dir: Vector2 = to - from
	return atan2(-dir.x, -dir.y)


func finish(victory: bool, title: String, detail: String) -> void:
	if is_over:
		return
	is_over = true
	get_tree().call_group(&"voice", &"say", "mission_win" if victory else "mission_fail", VoiceManager.Priority.CRITICAL)
	ended.emit(victory, title, detail)


func _on_tank_destroyed(tank: Tank, killer: Node) -> void:
	if tank.team != PLAYER_TEAM and killer is Tank and (killer as Tank).team == PLAYER_TEAM:
		get_tree().call_group(&"voice", &"say", "kill", VoiceManager.Priority.NORMAL)
	if killer == player and tank.team != PLAYER_TEAM:
		score += tank.stats.score_value
		message.emit(Loc.t("%s DESTRUIDO  +%d") % [tank.stats.display_name, tank.stats.score_value], false)


func _on_player_destroyed(_tank: Tank, _killer: Node) -> void:
	finish(false, Loc.t("TANQUE DESTRUIDO"), Loc.t("PUNTOS %d") % score)
