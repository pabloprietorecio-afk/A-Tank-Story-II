class_name TankMovement
extends Node
## Avance, retroceso y giro del casco. Lee `drive_input` del tanque (x = giro, y = avance).

const GRAVITY: float = 25.0

var _tank: Tank


func setup(tank: Tank) -> void:
	_tank = tank


func _physics_process(delta: float) -> void:
	if _tank == null:
		return
	var stats: TankStats = _tank.stats
	_tank.rotate_y(-_tank.drive_input.x * stats.hull_turn_speed * delta)

	var forward: Vector3 = -_tank.global_transform.basis.z
	var current_speed: float = _tank.velocity.dot(forward)
	var target_speed: float = _tank.drive_input.y * stats.max_speed * _tank.speed_factor
	current_speed = move_toward(current_speed, target_speed, stats.acceleration * delta)

	_tank.velocity.x = forward.x * current_speed
	_tank.velocity.z = forward.z * current_speed
	if _tank.is_on_floor():
		_tank.velocity.y = 0.0
	else:
		_tank.velocity.y -= GRAVITY * delta
	_tank.move_and_slide()
	for i in _tank.get_slide_collision_count():
		var collider: Object = _tank.get_slide_collision(i).get_collider()
		if collider is Destructible and collider.crushable and absf(current_speed) > 2.0:
			collider.crush(_tank)
