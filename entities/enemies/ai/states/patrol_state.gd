class_name PatrolState
extends EnemyState
## Va hacia su orden (objetivo de la misión) o hacia el enemigo lejano si caza; si no, deambula.

var _waypoint: Vector3
var _stuck: float = 0.0


func enter(_previous: StringName) -> void:
	_pick()
	_stuck = 0.0


func _pick() -> void:
	if brain.objective == Vector3.INF and brain.hunt and brain.has_target():
		_waypoint = brain.target.global_position
	else:
		_waypoint = brain.patrol_point()


func exit() -> void:
	brain.tank.trigger_held = false


func update(delta: float) -> void:
	if brain.focus_objective and brain.objective != Vector3.INF:
		# La orden es lo primero: a toda marcha hasta el punto exacto, disparando sobre la marcha.
		_stuck += delta
		if fmod(_stuck, 1.0) < delta:
			_waypoint = brain.patrol_point()
		brain.drive_to(_waypoint, 1.0, 1.5)
		if not brain.fire_on_the_move(delta):
			brain.tank.turret_controller.aim_yaw(brain.tank.global_rotation.y)
		return
	if brain.perception.can_see:
		machine.change_to(&"Chase")
		return
	_stuck += delta
	if fmod(_stuck, 3.0) < delta:
		_pick()
	var arrived: bool = brain.drive_to(_waypoint, 0.7, 6.0)
	brain.tank.turret_controller.aim_yaw(brain.tank.global_rotation.y)
	if arrived or _stuck > 20.0:
		machine.change_to(&"Idle")
