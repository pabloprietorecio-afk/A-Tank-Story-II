class_name IdleState
extends EnemyState
## Parado, escaneando con la torreta. Pasa a patrullar o a perseguir si ve a un enemigo.

var _time: float = 0.0
var _duration: float = 2.0


func enter(_previous: StringName) -> void:
	brain.stop()
	_time = 0.0
	_duration = randf_range(1.0, 2.5)


func update(delta: float) -> void:
	_time += delta
	brain.tank.turret_controller.aim_yaw(brain.tank.global_rotation.y + sin(_time * 0.8) * 1.0)
	if brain.focus_objective:
		machine.change_to(&"Patrol")
	elif brain.perception.can_see:
		machine.change_to(&"Chase")
	elif _time >= _duration:
		machine.change_to(&"Patrol")
