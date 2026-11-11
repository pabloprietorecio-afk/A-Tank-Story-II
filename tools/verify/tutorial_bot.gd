extends Node
## Jugador automático para probar el tutorial sin gráficos (no va en el APK). En cada lección
## hace la acción correcta por los mismos caminos que un jugador: mueve el joystick y la mira
## de TouchControls, mantiene FIRE y pulsa los botones del HUD. Si una lección no se completa
## en su tiempo, la anota como fallo y la salta para seguir con las demás.

const LIMIT: float = 120.0
const LIMIT_FINAL: float = 300.0

var mode: TutorialMode
var player: Tank
var touch: TouchControls
var hud: Hud
var input: PlayerInputSource
var failures: int = 0
var done: Array[bool] = []

var _lesson: int = -1
var _time: float = 0.0
var _press_timer: float = 0.0
var _final_pause: float = 0.0


func setup(tutorial: TutorialMode) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mode = tutorial
	player = tutorial.player
	touch = tutorial.touch
	hud = tutorial.hud
	input = tutorial.input_source
	done.resize(TutorialMode.LESSONS.size())
	done.fill(false)
	mode.lesson_completed.connect(_on_completed)
	mode.message.connect(func(text: String, _urgent: bool) -> void: print("TUTORIAL   aviso (lección %d, %.1f s): %s" % [_lesson + 1, _time, text]))


func _on_completed(index: int, skipped: bool) -> void:
	if skipped:
		return
	done[index] = true
	print("TUTORIAL lección %2d %-8s OK en %5.1f s" % [index + 1, TutorialMode.LESSONS[index], _time])


func _process(delta: float) -> void:
	if not is_instance_valid(mode) or mode.finished or get_tree().paused:
		return
	touch.move_vector = Vector2.ZERO
	touch.fire_held = false
	_press_timer -= delta
	if mode.lesson_index != _lesson:
		_lesson = mode.lesson_index
		_time = 0.0
	if mode._transition > 0.0:
		return
	_time += delta
	var id: String = mode.lesson_id()
	if _time > (LIMIT_FINAL if id == "final" else LIMIT):
		failures += 1
		print("TUTORIAL lección %2d %-8s NO COMPLETADA (paso %d)" % [_lesson + 1, id, mode.step])
		mode.skip_lesson()
		return
	call("_do_" + id)


func _do_move() -> void:
	if mode.step == 0:
		_drive_to(mode.beacons[0].point())
	else:
		touch.move_vector = Vector2(0.0, -1.0)


func _do_turn() -> void:
	var beacon: PracticeProps.Beacon = mode.beacons[mode.beacon_index]
	if is_instance_valid(beacon):
		_drive_to(beacon.point())


func _do_turret() -> void:
	for target in mode.targets:
		if is_instance_valid(target) and not target.acquired:
			_aim(target.center())
			return


func _do_fire() -> void:
	for target in mode.targets:
		if is_instance_valid(target) and not target.is_destroyed:
			_aim(target.center())
			touch.fire_held = mode._aim_error(target.center()) < 0.02
			return


func _do_easy() -> void:
	var beacon: PracticeProps.Beacon = mode.beacons[mode.step]
	if is_instance_valid(beacon):
		_drive_to(beacon.point())


func _do_camera() -> void:
	_press("cam")


func _do_radar() -> void:
	_drive_to(mode.beacons[0].point())


func _do_enemy() -> void:
	_shoot_tank(mode.enemy)


func _do_assist() -> void:
	match mode.step:
		0:
			# Abre ⚙, activa el interruptor y continúa, como haría el jugador.
			hud._set_paused(true)
			(hud.toggles["aim_assist"] as CheckButton).button_pressed = true
			hud._set_paused(false)
		1:
			if is_instance_valid(mode.enemy):
				_aim(mode.enemy.global_position + Vector3.UP * 1.2)
		2:
			_press("release")


func _do_zoom() -> void:
	if mode.step == 0:
		_press("zoom")
		return
	var target: PracticeProps.Target = mode.targets[0]
	if is_instance_valid(target):
		_aim(target.center())
		touch.fire_held = mode._aim_error(target.center()) < 0.008


func _do_missile() -> void:
	if mode._dead(mode.enemy):
		return
	if not is_instance_valid(player.aim_lock):
		_aim(mode.enemy.global_position + Vector3.UP * 1.2)
	elif not player.binoculars:
		_press("zoom")
	elif not mode._missile_ok:
		_press("missile")


func _do_strike() -> void:
	if not player.binoculars:
		_press("zoom")
		return
	var depot: Destructible = mode.depot_far if mode.step == 1 else mode.depot_near
	if not is_instance_valid(depot):
		return
	var point: Vector3 = depot.global_position + Vector3.UP * 1.2
	_aim(point)
	if mode._aim_error(point) < 0.03 and _press_timer <= 0.0:
		_press("strike")
		_press_timer = 1.0 if mode.step != 1 else 8.0


func _do_raid() -> void:
	if not is_instance_valid(mode.raid):
		return
	var center := Vector2(mode.raid.global_position.x, mode.raid.global_position.z)
	var away: Vector2 = -center.normalized() if center.length() > 20.0 else Vector2.RIGHT
	_drive_to(center + away * 60.0)


func _do_damage() -> void:
	if mode.step > 0 and is_instance_valid(mode.pickup):
		_drive_to(Vector2(mode.pickup.global_position.x, mode.pickup.global_position.z))


func _do_follow() -> void:
	if mode.step == 0:
		_press("follow")
	elif not mode.beacons.is_empty() and is_instance_valid(mode.beacons[0]):
		_drive_to(mode.beacons[0].point())


func _do_focus() -> void:
	if mode.step == 0 and is_instance_valid(mode.enemy):
		_aim(mode.enemy.global_position + Vector3.UP * 1.2)
		if mode._aim_error(mode.enemy.global_position + Vector3.UP * 1.2) < 0.05:
			_press("focus")


func _do_final() -> void:
	# Tras la primera baja espera a que el tanque destruido desaparezca del campo (los restos
	# se retiran a los 8 s): la lección tiene que seguir contando bien con tanques ya retirados.
	var dead: int = 0
	for tank: Variant in mode.final_enemies:
		if mode._dead(tank):
			dead += 1
	if dead > 0 and _final_pause < 11.0:
		_final_pause += get_process_delta_time()
		return
	var best: Tank = null
	for tank: Variant in mode.final_enemies:
		if mode._dead(tank):
			continue
		if best == null or tank.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position):
			best = tank
	if best != null:
		_shoot_tank(best)
		if best.global_position.distance_to(player.global_position) > 90.0:
			touch.move_vector = Vector2(0.0, 1.0)
		return
	var depot: Destructible = mode.final_objective
	if not is_instance_valid(depot) or depot.is_destroyed:
		return
	var point: Vector3 = depot.global_position + Vector3.UP * 1.2
	_aim(point)
	touch.fire_held = mode._aim_error(point) < 0.02
	if depot.global_position.distance_to(player.global_position) > 100.0:
		touch.move_vector = Vector2(0.0, 1.0)


# ------------------------------------------------------------------ manos del jugador

func _press(key: String) -> void:
	if _press_timer > 0.0:
		return
	var button: Button = hud.controls[key]
	if button.is_visible_in_tree() and not button.disabled:
		button.pressed.emit()
		_press_timer = 0.6


## Arrastra la mira (como el pulgar derecho) hasta apuntar a un punto del mundo.
func _aim(point: Vector3) -> void:
	var tc: TurretController = player.turret_controller
	var to: Vector3 = point - player.gun_pivot.global_position
	var desired_yaw: float = atan2(-to.x, -to.z)
	var desired_pitch: float = clampf(atan2(to.y, Vector2(to.x, to.z).length()), TurretController.MIN_PITCH, tc.max_pitch)
	var current_yaw: float = player.global_rotation.y + tc._target_local
	if GameSettings.easy_drive:
		current_yaw = tc.world_yaw if is_nan(input._aim_world) else input._aim_world
	var zoom: float = Tank.ZOOM_FOV / Tank.NORMAL_FOV if player.binoculars else 1.0
	var sens: float = input.look_sensitivity * zoom
	touch._look_delta = Vector2(-angle_difference(current_yaw, desired_yaw), -(desired_pitch - tc._target_pitch)) / sens


## Conduce hasta un punto: con movimiento fácil apunta el cañón y empuja hacia delante;
## sin él, gira el casco con el joystick.
func _drive_to(point: Vector2) -> void:
	if GameSettings.easy_drive:
		_aim(Vector3(point.x, 2.0, point.y))
		touch.move_vector = Vector2(0.0, 1.0)
		return
	var offset: Vector2 = point - Vector2(player.global_position.x, player.global_position.z)
	var diff: float = angle_difference(player.global_rotation.y, atan2(-offset.x, -offset.y))
	touch.move_vector = Vector2(clampf(-diff * 3.0, -1.0, 1.0), 1.0 if absf(diff) < 0.7 else 0.15)


func _shoot_tank(tank: Tank) -> void:
	if mode._dead(tank):
		return
	var point: Vector3 = tank.global_position + Vector3.UP * 1.2 * tank.stats.body_scale
	point += tank.velocity * (player.global_position.distance_to(point) / maxf(player.weapon.projectile_speed, 1.0))
	_aim(point)
	touch.fire_held = mode._aim_error(point) < 0.012
