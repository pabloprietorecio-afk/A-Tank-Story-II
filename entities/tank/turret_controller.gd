class_name TurretController
extends Node
## Torreta independiente: gira solo cuando el jugador la mueve (o la IA / ayuda de apuntado
## le ordena apuntar a un punto). Si nadie la mueve, queda fija respecto al casco y
## acompaña al tanque cuando éste gira.

const MAX_LEAD: float = 1.0
const MIN_PITCH: float = deg_to_rad(-6.0)
const MAX_PITCH: float = deg_to_rad(18.0)
## Elevación máxima actual (sube en la fase antiaérea).
var max_pitch: float = MAX_PITCH
## Suavizado: cuanto mayor, más rápido alcanza la torreta su objetivo.
const SMOOTHING: float = 9.0

## Rumbo de la torreta respecto al casco (0 = alineada con el casco).
var local_yaw: float = 0.0
var pitch: float = 0.0

## Rumbo de la torreta en el mundo.
var world_yaw: float:
	get: return _tank.global_rotation.y + local_yaw if _tank != null else local_yaw

var _tank: Tank
var _target_local: float = 0.0
var _target_world: float = 0.0
var _world_mode: bool = false
var _target_pitch: float = 0.0
var _prev_hull_yaw: float = 0.0
## Giro máximo respecto al casco (casamatas). 0 = sin límite.
var traverse_limit: float = 0.0


func setup(tank: Tank) -> void:
	_tank = tank
	_prev_hull_yaw = tank.global_rotation.y
	traverse_limit = tank.turret.get_meta("traverse_limit", 0.0)


## Desplazamiento deseado en radianes (jugador). La torreta se queda donde la dejes,
## relativa al casco.
func add_aim(delta_yaw: float, delta_pitch: float) -> void:
	hold_relative()
	var lead: float = clampf(angle_difference(local_yaw, _target_local + delta_yaw), -MAX_LEAD, MAX_LEAD)
	_target_local = wrapf(local_yaw + lead, -PI, PI)
	_target_pitch = clampf(_target_pitch + delta_pitch, MIN_PITCH, max_pitch)


## Fija el rumbo de la torreta respecto al casco (modo clásico: ajuste fino alrededor de 0).
func aim_local(yaw: float, delta_pitch: float = 0.0) -> void:
	_world_mode = false
	_target_local = wrapf(yaw, -PI, PI)
	_target_pitch = clampf(_target_pitch + delta_pitch, MIN_PITCH, max_pitch)


## Deja de seguir un punto del mundo y mantiene la orientación actual respecto al casco.
func hold_relative() -> void:
	if _world_mode:
		_world_mode = false
		_target_local = local_yaw


## Apunta a un punto del mundo (IA, ayuda de apuntado).
func aim_at(point: Vector3) -> void:
	var to: Vector3 = point - _tank.turret.global_position
	_target_world = atan2(-to.x, -to.z)
	_world_mode = true
	var horizontal: float = Vector2(to.x, to.z).length()
	_target_pitch = clampf(atan2(to.y, horizontal), MIN_PITCH, max_pitch)


## Mantiene la torreta en un rumbo fijo del mundo (no gira con el casco) y ajusta la elevación.
func aim_world_yaw(yaw: float, delta_pitch: float = 0.0) -> void:
	_target_world = yaw
	_world_mode = true
	_target_pitch = clampf(_target_pitch + delta_pitch, MIN_PITCH, max_pitch)


## Apunta hacia un rumbo del mundo sin cambiar la elevación (para escanear).
func aim_yaw(yaw: float) -> void:
	_target_world = yaw
	_world_mode = true
	_target_pitch = 0.0


## ¿Puede la torreta llegar a ese rumbo sin girar el casco?
func can_reach(yaw: float) -> bool:
	return traverse_limit <= 0.0 or absf(angle_difference(_tank.global_rotation.y, yaw)) <= traverse_limit


func is_aligned(cone: float) -> bool:
	return absf(angle_difference(world_yaw, _desired_world())) <= cone and absf(pitch - _target_pitch) <= cone


## Ángulo del casco respecto a hacia donde mira la torreta (positivo = casco girado a la izquierda).
func hull_relative_angle() -> float:
	return wrapf(-local_yaw, -PI, PI)


func _desired_world() -> float:
	return _target_world if _world_mode else _tank.global_rotation.y + _target_local


func _process(delta: float) -> void:
	if _tank == null:
		return
	# Al seguir un rumbo del mundo, el giro del casco se compensa al instante.
	var hull_yaw: float = _tank.global_rotation.y
	if _world_mode:
		local_yaw = wrapf(local_yaw - angle_difference(_prev_hull_yaw, hull_yaw), -PI, PI)
	_prev_hull_yaw = hull_yaw
	var max_step: float = _tank.stats.turret_turn_speed * delta
	var ease: float = 1.0 - exp(-SMOOTHING * delta)
	var diff: float = angle_difference(world_yaw, _desired_world())
	local_yaw = wrapf(local_yaw + clampf(diff * ease, -max_step, max_step), -PI, PI)
	pitch += clampf((_target_pitch - pitch) * ease, -max_step, max_step)
	if traverse_limit > 0.0:
		local_yaw = clampf(local_yaw, -traverse_limit, traverse_limit)
	_tank.turret.rotation.y = local_yaw
	_tank.gun_pivot.rotation.x = pitch
