class_name AttackState
extends EnemyState
## Dispara al enemigo moviéndose en círculo para no ser un blanco fácil.
## Los cazacarros de casamata se quedan quietos y giran el casco para apuntar.

var _aim_timer: float = 0.0
var _side: float = 1.0
var _blind: float = 0.0


func enter(_previous: StringName) -> void:
	_side = 1.0 if randf() < 0.5 else -1.0
	_aim_timer = 0.0
	_blind = 0.0


func exit() -> void:
	brain.tank.trigger_held = false


func update(delta: float) -> void:
	var perception: Perception = brain.perception
	var stats: TankStats = brain.tank.stats
	if not brain.has_target():
		machine.change_to(&"Patrol")
		return
	if brain.retreat_threshold() > 0.0 and brain.armor_fraction() <= brain.retreat_threshold():
		machine.change_to(&"Retreat")
		return
	# Los de largo alcance se retiran si el enemigo se les echa encima.
	if stats.preferred_range > 80.0 and perception.distance < stats.preferred_range * 0.4:
		machine.change_to(&"Retreat")
		return
	_blind = 0.0 if perception.can_see else _blind + delta
	if _blind > 1.5 or perception.distance > stats.attack_range * 1.25:
		machine.change_to(&"Chase")
		return
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		_aim_timer = brain.aim_interval
		brain.aim_with_error()
		if randf() < 0.3:
			_side = -_side
	var turret: TurretController = brain.tank.turret_controller
	if stats.traverse_limit_deg > 0.0:
		brain.face(brain.target.global_position)
	else:
		var radius: float = perception.distance if stats.preferred_range <= 0.0 else lerpf(perception.distance, stats.preferred_range, 0.6)
		brain.drive_to(brain.strafe_point(brain.target.global_position, radius, _side), 0.5, 2.0)
	var cone: float = deg_to_rad(stats.fire_cone_deg)
	brain.tank.trigger_held = perception.can_see and turret.is_aligned(cone)
