class_name ChaseState
extends EnemyState
## Se acerca al enemigo hasta tener alcance de tiro.

var _lost: float = 0.0


func enter(_previous: StringName) -> void:
	_lost = 0.0


func update(delta: float) -> void:
	var perception: Perception = brain.perception
	var stats: TankStats = brain.tank.stats
	if not brain.has_target():
		machine.change_to(&"Patrol")
		return
	if brain.retreat_threshold() > 0.0 and brain.armor_fraction() <= brain.retreat_threshold():
		machine.change_to(&"Retreat")
		return
	_lost = 0.0 if perception.can_see else _lost + delta
	if _lost > 3.0 and brain.forced_target != brain.target:
		machine.change_to(&"Search")
		return
	var point: Vector3 = perception.last_known
	brain.drive_to(point, 1.0, 3.0)
	if perception.can_see:
		brain.aim_with_error()
		if perception.distance <= stats.attack_range * 0.85:
			machine.change_to(&"Attack")
	else:
		brain.tank.turret_controller.aim_at(point)
