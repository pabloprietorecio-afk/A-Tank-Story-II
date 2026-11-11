class_name DestroyedState
extends EnemyState
## Estado final: el enemigo ya no actúa.


func enter(_previous: StringName) -> void:
	brain.tank.drive_input = Vector2.ZERO
	brain.tank.trigger_held = false
