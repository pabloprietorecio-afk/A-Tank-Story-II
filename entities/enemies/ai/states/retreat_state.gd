class_name RetreatState
extends EnemyState
## Se aleja del enemigo cuando le queda poco blindaje, disparando si puede.

var _time: float = 0.0


func enter(_previous: StringName) -> void:
	_time = 0.0


func exit() -> void:
	brain.tank.trigger_held = false


func update(delta: float) -> void:
	_time += delta
	if not brain.has_target():
		machine.change_to(&"Patrol")
		return
	var away: Vector3 = brain.tank.global_position + (brain.tank.global_position - brain.target.global_position).normalized() * 40.0
	away.x = clampf(away.x, -170.0, 170.0)
	away.z = clampf(away.z, -170.0, 170.0)
	brain.drive_to(away, 1.0, 3.0)
	if brain.perception.can_see:
		brain.aim_with_error()
		brain.tank.trigger_held = brain.tank.turret_controller.is_aligned(deg_to_rad(brain.tank.stats.fire_cone_deg * 1.5))
	else:
		brain.tank.trigger_held = false
	if _time > 8.0 or brain.perception.distance > brain.tank.stats.detect_range:
		machine.change_to(&"Search")
