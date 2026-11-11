class_name AIBrain
extends Node
## Cerebro de un tanque controlado por la máquina (enemigo o aliado).
## Elige como objetivo al tanque hostil más cercano que pueda ver; si no hay ninguno,
## sigue su orden (`objective`) o, si `hunt` está activo, va a por el hostil más cercano.
## Da órdenes al Tank (drive_input, torreta, gatillo) igual que lo haría el jugador.

const WORLD_MASK: int = 1
const ARENA_LIMIT: float = 180.0
const RETARGET_INTERVAL: float = 0.6

var tank: Tank
var target: Tank
var perception: Perception
var machine: StateMachine
## Punto al que dirigirse cuando no hay combate (bandera, zona a defender...). Vector3.INF = ninguno.
var objective: Vector3 = Vector3.INF
## Si no ve a nadie, persigue al hostil más cercano aunque esté lejos (supervivencia).
var hunt: bool = true
## Distancia a la que se queda del objetivo al llegar (defensores: patrullan alrededor).
var objective_radius: float = 6.0
## La orden es lo primero: va a su objetivo sin desviarse a perseguir a nadie, disparando sobre
## la marcha a quien tenga a tiro (ir a por la bandera, llevarla a casa).
var focus_objective: bool = false
## Enemigo al que debe ir a por él antes que a cualquier otro (quien lleva nuestra bandera).
var priority_target: Tank = null
## Segundos entre correcciones de puntería: los reflejos del tirador (lo ajusta la dificultad).
var aim_interval: float = 0.6

## Orden «todos conmigo»: acompaña a este tanque (el del jugador) y solo pelea con quien tenga
## cerca de él; si se queda lejos, corre a reunirse con él disparando sobre la marcha.
var follow: Tank = null
const FOLLOW_RADIUS: float = 14.0
const FOLLOW_CATCHUP: float = 38.0
## Los enemigos más lejos que esto del tanque al que sigue se ignoran.
const FOLLOW_LEASH: float = 60.0
## Siguiendo al jugador se retira antes (para sobrevivir): a partir de esta fracción de blindaje.
const FOLLOW_RETREAT: float = 0.4
## Enemigo al que debe atacar sin distraerse (lo marca el jugador para todo su bando).
var forced_target: Tank = null

## Navegación con rodeo de obstáculos (la usan los tanques del bando del jugador). Dos capas:
## una ruta sobre el mapa de celdas (NavGrid), que evita edificios, setos, colinas y callejones
## sin salida; y, para seguirla, un abanico de rayos que esquiva lo que el mapa no ve (otros
## tanques, restos, esquinas). Si aun así se queda clavado, da marcha atrás y recalcula.
var smart_nav: bool = false

const NAV_INTERVAL: float = 0.12
const NAV_REACH: float = 14.0
## Desvíos que se prueban respecto al rumbo deseado (radianes; positivo = izquierda).
const NAV_ANGLES: Array[float] = [0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.65, -1.65, 2.2, -2.2]
const NAV_SIDE_PENALTY: float = 1.5
const PATH_INTERVAL: float = 2.5
const STUCK_CHECK: float = 1.2
const STUCK_DISTANCE: float = 0.7

## En alerta: le han disparado (o a un compañero cercano). Mientras dura no suelta a su atacante
## aunque no lo vea, ve más lejos y va a buscarlo.
const ALERT_TIME: float = 16.0
const ALERT_RANGE_BOOST: float = 1.6
## Los compañeros a esta distancia se enteran cuando a uno le aciertan.
const ALERT_RADIUS: float = 75.0
var _alert: float = 0.0
var _move_aim: float = 0.0

var _avoid_sign: float = 1.0
var _avoid_timer: float = 0.0
var _retarget_timer: float = 0.0
var _grid: NavGrid
var _path := PackedVector3Array()
var _path_index: int = 0
var _path_goal: Vector3 = Vector3.INF
var _path_timer: float = 0.0
var _nav_timer: float = 0.0
var _nav_heading: Vector3 = Vector3.ZERO
var _nav_blocked: bool = false
## Lado por el que está esquivando: +1 izquierda, -1 derecha, 0 ninguno.
var _nav_side: float = 0.0
var _nav_side_time: float = 0.0
var _nav_driving: bool = false
var _nav_aligned: bool = false
var _stuck_time: float = 0.0
var _stuck_origin: Vector3 = Vector3.ZERO
var _stuck_count: int = 0
var _stuck_calm: float = 0.0
var _reverse_time: float = 0.0
var _reverse_turn: float = 0.0
## Veces que ha tenido que desatascarse (para pruebas).
var unstuck_total: int = 0


func setup(tank_ref: Tank, initial_target: Tank = null) -> void:
	tank = tank_ref
	perception = Perception.new(tank)
	machine = StateMachine.new()
	machine.name = "StateMachine"
	add_child(machine)
	for state_script: Script in [IdleState, PatrolState, SearchState, ChaseState, AttackState, RetreatState, DestroyedState]:
		var state: State = state_script.new()
		state.name = state_script.get_global_name().trim_suffix("State")
		machine.add_child(state)
	add_to_group(&"ai_brains")
	tank.damaged.connect(_on_tank_damaged)
	tank.destroyed.connect(_on_tank_destroyed)
	_set_target(initial_target)
	machine.start(&"Idle")


func _physics_process(delta: float) -> void:
	if tank == null or tank.is_destroyed:
		return
	_alert = maxf(_alert - delta, 0.0)
	perception.range_boost = ALERT_RANGE_BOOST if _alert > 0.0 else 1.0
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_choose_target()
	_follow_tick()
	perception.update(delta)
	_avoid_timer = maxf(_avoid_timer - delta, 0.0)
	if smart_nav:
		_nav_tick(delta)


## Pone o quita la orden de seguir a `leader`. Al quitarla se olvida del punto de reunión.
func set_follow(leader: Tank) -> void:
	if leader == follow:
		return
	var was_following: bool = follow != null
	follow = leader
	if leader == null and was_following:
		objective = Vector3.INF
		focus_objective = false


func _follow_tick() -> void:
	if follow == null:
		return
	if not is_instance_valid(follow) or follow.is_destroyed:
		set_follow(null)
		return
	var far: bool = tank.global_position.distance_to(follow.global_position) > FOLLOW_CATCHUP
	order(follow.global_position, 10.0 if far else FOLLOW_RADIUS, far)


## Fracción de blindaje a partir de la cual se retira (más alta si sigue al jugador).
func retreat_threshold() -> float:
	var base: float = tank.stats.retreat_fraction
	return maxf(base, FOLLOW_RETREAT) if follow != null else base


func has_target() -> bool:
	return is_instance_valid(target) and not target.is_destroyed


## Da una orden nueva. Con `focus` deja lo que esté haciendo y va directo a cumplirla.
func order(point: Vector3, radius: float, focus: bool = false, priority: Tank = null) -> void:
	objective = point
	objective_radius = radius
	priority_target = priority
	if focus and not focus_objective and machine.current_name != &"Destroyed" and machine.current_name != &"Patrol":
		focus_objective = true
		machine.change_to(&"Patrol")
	focus_objective = focus


## Dispara sobre la marcha al objetivo actual si lo ve y lo tiene a tiro. Devuelve si apunta a alguien.
func fire_on_the_move(delta: float) -> bool:
	if not has_target() or not perception.can_see:
		tank.trigger_held = false
		return false
	_move_aim -= delta
	if _move_aim <= 0.0:
		_move_aim = aim_interval
		aim_with_error()
	tank.trigger_held = perception.distance <= tank.stats.attack_range * 1.25 and tank.turret_controller.is_aligned(deg_to_rad(tank.stats.fire_cone_deg))
	return true


func _choose_target() -> void:
	if is_instance_valid(forced_target) and not forced_target.is_destroyed:
		# Ataque marcado por el jugador: sabe dónde está y va a por él aunque no lo vea.
		perception.reveal(forced_target.global_position)
		_set_target(forced_target)
		return
	if is_instance_valid(priority_target) and not priority_target.is_destroyed:
		var reach: float = tank.stats.detect_range * maxf(perception.range_boost, 1.3)
		if tank.global_position.distance_to(priority_target.global_position) <= reach and perception.line_of_sight(priority_target):
			_set_target(priority_target)
			return
	var best: Tank = null
	var best_dist: float = INF
	var nearest_any: Tank = null
	var nearest_any_dist: float = INF
	for node in get_tree().get_nodes_in_group(&"tanks"):
		var other: Tank = node as Tank
		if other == null or other.is_destroyed or not tank.is_hostile_to(other):
			continue
		var dist: float = tank.global_position.distance_to(other.global_position)
		if follow != null and is_instance_valid(follow) and other.global_position.distance_to(follow.global_position) > FOLLOW_LEASH:
			continue
		if dist < nearest_any_dist:
			nearest_any_dist = dist
			nearest_any = other
		# El objetivo actual tiene ventaja para no cambiar a cada momento.
		var score: float = dist * (0.7 if other == target else 1.0)
		if dist <= tank.stats.detect_range * perception.range_boost and score < best_dist and perception.line_of_sight(other):
			best_dist = score
			best = other
	if best == null and has_target() and (perception.time_since_seen < 6.0 or _alert > 0.0):
		return
	if best == null and hunt and follow == null:
		best = nearest_any
	_set_target(best)


func _set_target(new_target: Tank) -> void:
	target = new_target
	perception.set_target(new_target)


func state_name() -> StringName:
	return machine.current_name


func armor_fraction() -> float:
	return tank.health.fraction()


func target_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.2 * target.stats.body_scale


## Punto de patrulla: la orden actual o un punto al azar.
func patrol_point() -> Vector3:
	if objective != Vector3.INF:
		var offset := Vector2.from_angle(randf() * TAU) * randf_range(0.0, objective_radius)
		return objective + Vector3(offset.x, 0.0, offset.y)
	return random_waypoint()


## Conduce hacia un punto. `speed` en 0..1. Devuelve true al llegar (radio `arrive`).
func drive_to(point: Vector3, speed: float = 1.0, arrive: float = 4.0) -> bool:
	var to: Vector3 = point - tank.global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist <= arrive:
		tank.drive_input = Vector2.ZERO
		return true
	if smart_nav:
		_drive_smart(point, speed)
		return false
	var forward: Vector3 = -tank.global_transform.basis.z
	var angle: float = forward.signed_angle_to(to, Vector3.UP)
	var turn: float = clampf(-angle * 2.0, -1.0, 1.0)
	var advance: float = speed * clampf(1.0 - absf(angle) / 1.2, 0.0, 1.0)
	var avoid: float = _avoidance()
	if avoid != 0.0:
		turn = clampf(turn + avoid, -1.0, 1.0)
		advance *= 0.5
	tank.drive_input = Vector2(turn, advance)
	return false


## Gira el casco en el sitio hacia un punto (cazacarros de casamata). True si ya está encarado.
func face(point: Vector3, tolerance: float = 0.08) -> bool:
	var to: Vector3 = point - tank.global_position
	to.y = 0.0
	var forward: Vector3 = -tank.global_transform.basis.z
	var angle: float = forward.signed_angle_to(to, Vector3.UP)
	if absf(angle) <= tolerance:
		tank.drive_input = Vector2.ZERO
		return true
	tank.drive_input = Vector2(clampf(-angle * 2.5, -1.0, 1.0), 0.0)
	return false


func stop() -> void:
	tank.drive_input = Vector2.ZERO


func strafe_point(around: Vector3, radius: float, side: float) -> Vector3:
	var from_target: Vector3 = tank.global_position - around
	from_target.y = 0.0
	var dir: Vector3 = from_target.normalized().rotated(Vector3.UP, side * 0.5)
	return around + dir * radius


func random_waypoint() -> Vector3:
	return Vector3(randf_range(-ARENA_LIMIT, ARENA_LIMIT), 0.0, randf_range(-ARENA_LIMIT, ARENA_LIMIT))


## Apunta con predicción y error según las estadísticas.
func aim_with_error() -> void:
	if not has_target():
		return
	var stats: TankStats = tank.stats
	var point: Vector3 = target_point()
	var dist: float = tank.global_position.distance_to(point)
	point += target.velocity * (dist / stats.projectile_speed) * stats.lead_factor
	var error: float = dist * tan(deg_to_rad(stats.aim_error_deg))
	point += Vector3(randf_range(-error, error), randf_range(-error, error) * 0.3, randf_range(-error, error))
	tank.turret_controller.aim_at(point)


## Relojes de la navegación y vigilancia de atascos. Se considera atascado si lleva un rato
## queriendo avanzar, ya encarado a su rumbo, y apenas se ha movido del sitio.
func _nav_tick(delta: float) -> void:
	_nav_timer -= delta
	_path_timer -= delta
	_nav_side_time = maxf(_nav_side_time - delta, 0.0)
	if _nav_side_time <= 0.0 and not _nav_blocked:
		_nav_side = 0.0
	_stuck_calm += delta
	if _stuck_calm > 8.0:
		_stuck_count = 0
	if _reverse_time > 0.0:
		_reverse_time -= delta
		_stuck_time = 0.0
		_stuck_origin = tank.global_position
		return
	if not _nav_driving or not _nav_aligned:
		# Parado a propósito, o girando sobre sí mismo hacia su rumbo: normal que no se desplace.
		_nav_driving = false
		_stuck_time = 0.0
		_stuck_origin = tank.global_position
		return
	_nav_driving = false
	_stuck_time += delta
	if _stuck_time < STUCK_CHECK:
		return
	var moved: float = tank.global_position.distance_to(_stuck_origin)
	_stuck_time = 0.0
	_stuck_origin = tank.global_position
	if moved < STUCK_DISTANCE:
		_unstick()


## Atascado: marcha atrás girando el morro hacia un lado (alterna cada dos intentos) y ruta nueva.
func _unstick() -> void:
	unstuck_total += 1
	_stuck_count += 1
	_stuck_calm = 0.0
	if _nav_side == 0.0:
		_nav_side = 1.0 if randf() < 0.5 else -1.0
	elif _stuck_count % 2 == 0:
		_nav_side = -_nav_side
	_nav_side_time = 5.0
	_reverse_time = randf_range(1.0, 1.6)
	# drive_input.x > 0 gira a la derecha; para llevar el morro a la izquierda (+1), negativo.
	_reverse_turn = -_nav_side * 0.9
	_nav_timer = 0.0
	_path_timer = 0.0


func _drive_smart(point: Vector3, speed: float) -> void:
	_nav_driving = true
	if _reverse_time > 0.0:
		tank.drive_input = Vector2(_reverse_turn, -0.8)
		return
	if _nav_timer <= 0.0 or _nav_heading == Vector3.ZERO:
		_nav_timer = NAV_INTERVAL
		if _path_timer <= 0.0 or _path_goal == Vector3.INF or _path_goal.distance_to(point) > 8.0:
			_plan_path(point)
		var to: Vector3 = _path_target(point) - tank.global_position
		to.y = 0.0
		var dist: float = to.length()
		if dist < 0.5:
			tank.drive_input = Vector2.ZERO
			return
		_choose_heading(to / dist, dist)
	var forward: Vector3 = -tank.global_transform.basis.z
	var angle: float = forward.signed_angle_to(_nav_heading, Vector3.UP)
	var turn: float = clampf(-angle * 2.5, -1.0, 1.0)
	var advance: float = speed * clampf(1.0 - absf(angle) / 0.9, 0.0, 1.0)
	if _nav_blocked and absf(angle) > 0.45:
		# Esquivando: primero gira en el sitio hacia el hueco y luego avanza.
		advance = 0.0
	_nav_aligned = absf(angle) < 0.5
	tank.drive_input = Vector2(turn, advance)


## Calcula la ruta hasta el destino sobre el mapa de celdas (vacía si aún no está listo o no
## hay paso: entonces va en línea recta, esquivando con los rayos).
func _plan_path(point: Vector3) -> void:
	_path_timer = PATH_INTERVAL + randf() * 0.5
	_path_goal = point
	_path_index = 0
	if _grid == null:
		_grid = NavGrid.of(tank.get_parent())
	_path = _grid.find_path(tank.global_position, point) if _grid.ready_once else PackedVector3Array()


## Punto de la ruta hacia el que conducir ahora: deja atrás los ya alcanzados y ataja hasta el
## más lejano de los siguientes que tenga a la vista, para no ir haciendo eses de celda en celda.
func _path_target(point: Vector3) -> Vector3:
	if _path.is_empty():
		return point
	var pos: Vector3 = tank.global_position
	var last: int = _path.size() - 1
	while _path_index < last and Vector2(_path[_path_index].x - pos.x, _path[_path_index].z - pos.z).length() < 5.0:
		_path_index += 1
	for i in range(mini(_path_index + 5, last), _path_index, -1):
		var leg: Vector3 = _path[i] - pos
		leg.y = 0.0
		var length: float = leg.length()
		if length < 0.5 or _clearance(leg / length, length) >= length - 0.3:
			_path_index = i
			break
	return _path[_path_index]


## Elige el rumbo: el deseado si está libre; si no, el desvío más pequeño con paso, con
## preferencia por seguir esquivando por el mismo lado (para no dudar entre los dos).
func _choose_heading(goal_dir: Vector3, dist: float) -> void:
	var reach: float = NAV_REACH * maxf(tank.stats.body_scale, 1.0)
	var need: float = minf(reach, dist)
	if _clearance(goal_dir, need) >= need - 0.3:
		_nav_heading = goal_dir
		_nav_blocked = false
		return
	_nav_blocked = true
	var open: float = minf(reach, 10.0)
	var best_score: float = -INF
	var best_angle: float = 0.0
	for offset in NAV_ANGLES:
		var free: float = _clearance(goal_dir.rotated(Vector3.UP, offset), reach)
		var score: float = minf(free / open, 1.0) * 3.0 - absf(offset) * 0.8
		if free < 3.0:
			score -= 3.0
		if _nav_side != 0.0 and signf(offset) != _nav_side:
			score -= NAV_SIDE_PENALTY
		if score > best_score:
			best_score = score
			best_angle = offset
	_nav_heading = goal_dir.rotated(Vector3.UP, best_angle)
	_nav_side = signf(best_angle)
	_nav_side_time = 2.5


## Metros libres en una dirección: tres rayos a media altura (centro y los dos bordes del
## casco) y uno más alto. No cuentan lo que el tanque puede aplastar ni su propio objetivo.
func _clearance(dir: Vector3, reach: float) -> float:
	var k: float = tank.stats.body_scale
	var half_width: float = (TankModel.HULL_SIZE.x * tank.stats.hull_proportions.x + 1.0) * k * 0.5 + 0.35
	var right: Vector3 = dir.cross(Vector3.UP) * half_width
	var base: Vector3 = tank.global_position
	var space: PhysicsDirectSpaceState3D = tank.get_world_3d().direct_space_state
	var exclude: Array[RID] = [tank.get_rid()]
	if has_target():
		exclude.append(target.get_rid())
	var free: float = reach
	for probe: Vector2 in [Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(-1.0, 0.5), Vector2(0.0, 1.2)]:
		var from: Vector3 = base + right * probe.x + Vector3.UP * probe.y * k
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, WORLD_MASK | Tank.LAYER_TANK)
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		if collider is Destructible and (collider as Destructible).crushable:
			continue
		free = minf(free, from.distance_to(hit["position"]))
	return free


func _avoidance() -> float:
	var forward: Vector3 = -tank.global_transform.basis.z
	var from: Vector3 = tank.global_position + Vector3.UP * 1.0
	var reach: float = 9.0 * tank.stats.body_scale
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * reach, WORLD_MASK | Tank.LAYER_TANK)
	query.exclude = [tank.get_rid()]
	if tank.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return 0.0
	if _avoid_timer <= 0.0:
		_avoid_sign = 1.0 if randf() < 0.5 else -1.0
		_avoid_timer = 1.5
	return _avoid_sign


func is_alert() -> bool:
	return _alert > 0.0


## Le han acertado: va a por quien le dispara y avisa a los compañeros que tenga cerca.
func _on_tank_damaged(_amount: float, source: Node) -> void:
	var attacker: Tank = source as Tank
	if attacker == null or not tank.is_hostile_to(attacker) or attacker.is_destroyed:
		var current: StringName = machine.current_name
		if current == &"Idle" or current == &"Patrol":
			machine.change_to(&"Search")
		return
	alert(attacker, true)
	for node in get_tree().get_nodes_in_group(&"ai_brains"):
		var other: AIBrain = node as AIBrain
		if other == null or other == self or other.tank == null or other.tank.is_destroyed or other.tank.team != tank.team:
			continue
		if other.tank.global_position.distance_to(tank.global_position) <= ALERT_RADIUS:
			other.alert(attacker, false)


## Pone el tanque en alerta contra `attacker`. Con `direct` (el golpe lo ha recibido él) cambia
## siempre de objetivo; si solo se lo avisa un compañero, únicamente cuando no está ya
## combatiendo con alguien a quien ve.
func alert(attacker: Tank, direct: bool) -> void:
	if tank == null or tank.is_destroyed or not is_instance_valid(attacker):
		return
	if direct or not (has_target() and perception.can_see):
		_set_target(attacker)
		perception.reveal(attacker.global_position)
	_alert = ALERT_TIME
	perception.range_boost = ALERT_RANGE_BOOST
	if focus_objective:
		# Con una orden que cumplir no se desvía: devuelve el fuego sobre la marcha.
		return
	var current: StringName = machine.current_name
	if current == &"Idle" or current == &"Patrol":
		machine.change_to(&"Search")


func _on_tank_destroyed(_tank: Tank, _killer: Node) -> void:
	machine.change_to(&"Destroyed")
