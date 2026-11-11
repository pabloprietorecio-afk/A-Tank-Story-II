class_name Perception
extends RefCounted
## Percepción: distancia, línea de visión y última posición conocida del objetivo actual.
## El objetivo puede cambiar (lo elige AIBrain); no depende de ningún tipo de tanque concreto.

const WORLD_MASK: int = 1
const INTERVAL: float = 0.2

var distance: float = INF
var can_see: bool = false
var last_known: Vector3 = Vector3.ZERO
var has_last_known: bool = false
var time_since_seen: float = INF
## Con el tanque en alerta (le acaban de disparar) alcanza a ver más lejos: busca a quien le tira.
var range_boost: float = 1.0

var _owner: Tank
var _target: Tank
var _timer: float = randf() * INTERVAL


func _init(owner_tank: Tank) -> void:
	_owner = owner_tank


func set_target(target: Tank) -> void:
	if target == _target:
		return
	_target = target
	can_see = false
	_timer = 0.0
	if target == null:
		distance = INF


func update(delta: float) -> void:
	time_since_seen += delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	if not is_instance_valid(_target) or _target.is_destroyed:
		can_see = false
		distance = INF
		return
	distance = _owner.global_position.distance_to(_target.global_position)
	can_see = distance <= _owner.stats.detect_range * range_boost and line_of_sight(_target)
	if can_see:
		time_since_seen = 0.0
		last_known = _target.global_position
		has_last_known = true


## Un golpe recibido revela la posición del atacante aunque no lo viéramos.
func reveal(point: Vector3) -> void:
	last_known = point
	has_last_known = true
	time_since_seen = minf(time_since_seen, 1.0)


func forget() -> void:
	has_last_known = false
	time_since_seen = INF


func line_of_sight(other: Tank) -> bool:
	var from: Vector3 = _owner.global_position + Vector3.UP * 1.6
	var to: Vector3 = other.global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return _owner.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
