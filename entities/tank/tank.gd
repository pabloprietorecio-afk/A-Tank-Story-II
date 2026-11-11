class_name Tank
extends CharacterBody3D
## Tanque. Jugador, aliados y enemigos usan esta misma clase; solo cambia quién da las órdenes.
## El modelo lo construye TankModel a partir de la ficha (TankStats) y de la pintura del frente.

const LAYER_WORLD: int = 1
const LAYER_TANK: int = 2
const LAYER_HURTBOX: int = 4
## Barrera del límite del mapa: solo la tocan los tanques.
const LAYER_BOUNDARY: int = 8
## Pendiente máxima que sube un tanque. Colinas y montañas son más empinadas: hacen de pared.
const MAX_SLOPE_DEG: float = 10.0
## Capa visual de las piezas del propio jugador (la cámara en primera persona no las ve).
const VISUAL_LAYER_OWN: int = 2
## Distancia hacia atrás y altura de las vistas exteriores [cerca, lejos].
const CHASE_OFFSETS: Array[Vector2] = [Vector2(10.0, 4.5), Vector2(20.0, 9.0)]
## Segundos que arden los restos de un tanque de la máquina antes de hundirse y desaparecer.
const WRECK_TIME: float = 25.0
const WRECK_SINK: float = 2.5
## Retroceso del cañón al disparar (m, por la escala del vehículo).
const RECOIL_TRAVEL: float = 0.3
## Probabilidad de que la munición reviente y la torreta salga despedida.
const TURRET_TOSS_CHANCE: float = 0.35

signal destroyed(tank: Tank, killer: Node)
signal damaged(amount: float, source: Node)

@export var stats: TankStats
@export var is_player: bool = false
## Equipo: 0 = el del jugador, 1 = el contrario.
@export var team: int = 0
## Pintura: {"base": Color, "mode": int, "a": Color, "b": Color} (ver TankModel).
var paint: Dictionary = {}

## Órdenes (las rellena PlayerInputSource o la IA).
var drive_input: Vector2 = Vector2.ZERO
var trigger_held: bool = false
## Factor sobre la velocidad máxima (quien lleva la bandera va más lento).
var speed_factor: float = 1.0

var turret: Node3D
var gun_pivot: Node3D
var muzzle: Marker3D
var camera: Camera3D
var hurtbox: Hurtbox
var health: HealthComponent
var weapon: TankWeapon
var turret_controller: TurretController
var is_destroyed: bool = false
## Enemigo fijado por la ayuda de apuntado (solo jugador).
var aim_lock: Tank = null

var _scale_factor: float = 1.0
var _shake: float = 0.0
var _view: int = 0
var _meshes: Array[MeshInstance3D] = []
## Mejoras temporales activas: nombre → segundos restantes.
var buffs: Dictionary = {}
## Efectos: puntos del casco de donde salen (en coordenadas del tanque) y cuentas de emisión.
var _fx: Fx
var _exhaust_at: Vector3
var _track_at: Vector3
var _deck_at: Vector3
var _exhaust_due: float = 0.0
var _dust_due: float = 0.0
var _smoke_due: float = 0.0
var _recoil: float = 0.0
var _gun_mesh: MeshInstance3D
## Restos: segundos desde que lo destruyeron (-1 = entero), viveza del incendio y torreta
## arrancada por la explosión de la munición.
var _wreck_age: float = -1.0
var _wreck_fire: float = 1.0
var _pop_timer: float = 0.0
var _light_timer: float = 0.0
var _turret_home: Vector3
var _turret_flying: bool = false
var _turret_velocity: Vector3
var _turret_spin: Vector3
var _materials: Array[Material] = []
## Material del modelo: con él se animan las orugas.
var _track_material: ShaderMaterial
var _track_scroll: Vector2 = Vector2.ZERO
var _last_yaw: float = 0.0
## Sonido: motor (sube de vueltas al acelerar) y golpeteo de las orugas al moverse.
var _engine_sound: AudioStreamPlayer3D
var _idle_sound: AudioStreamPlayer3D
var _engine_pitch: float = 1.0
var _engine_level: float = 0.0
## Borde amarillo que destaca a los enemigos (ajuste «Destacar enemigos»): el mismo modelo, un poco
## más gordo y dibujado solo por sus caras traseras, asoma alrededor de la silueta.
static var _outline: StandardMaterial3D


func _ready() -> void:
	if stats == null:
		stats = TankStats.new()
	if paint.is_empty():
		paint = TankModel.plain_paint(Color(0.33, 0.36, 0.22))
	_scale_factor = stats.body_scale
	add_to_group(&"tanks")
	collision_layer = LAYER_TANK
	collision_mask = LAYER_WORLD | LAYER_TANK | LAYER_BOUNDARY
	floor_max_angle = deg_to_rad(MAX_SLOPE_DEG)
	floor_block_on_wall = true
	_build_body()
	_build_components()
	_build_effects()
	_build_sound()
	refresh_highlight()
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


## ¿Es enemigo de este otro tanque?
func is_hostile_to(other: Tank) -> bool:
	return other != null and other.team != team


func _physics_process(delta: float) -> void:
	if trigger_held and not is_destroyed:
		weapon.fire()
	if not buffs.is_empty():
		for kind in buffs.keys():
			buffs[kind] -= delta
			if buffs[kind] <= 0.0:
				buffs.erase(kind)
		_apply_buffs()


## Mejora temporal: "reload" (recarga x2), "damage" (daño x2), "shield" (daño recibido /2).
func add_buff(kind: String, duration: float) -> void:
	buffs[kind] = maxf(buffs.get(kind, 0.0), duration)
	_apply_buffs()


func _apply_buffs() -> void:
	weapon.reload_mult = 0.5 if buffs.has("reload") else 1.0
	weapon.damage_mult = 2.0 if buffs.has("damage") else 1.0
	hurtbox.damage_multiplier = 0.5 if buffs.has("shield") else 1.0


const ZOOM_FOV: float = 16.0
const NORMAL_FOV: float = 75.0
var binoculars: bool = false
var _view_before_zoom: int = 0


const AIR_FOV: float = 45.0
var air_mode: bool = false


## Modo antiaéreo: vista de cabina con zoom moderado y el cañón puede alzarse 60º.
func set_air_mode(on: bool) -> void:
	if camera == null or on == air_mode:
		return
	air_mode = on
	set_binoculars(false)
	turret_controller.max_pitch = deg_to_rad(60.0) if on else TurretController.MAX_PITCH
	if on:
		_view_before_zoom = _view
		set_view(0)
		camera.fov = AIR_FOV
	else:
		camera.fov = NORMAL_FOV
		set_view(_view_before_zoom)


## Prismáticos: vista desde la cabina con mucho aumento.
func set_binoculars(on: bool) -> void:
	if camera == null or on == binoculars:
		return
	binoculars = on
	if on:
		_view_before_zoom = _view
		set_view(0)
	camera.fov = ZOOM_FOV if on else NORMAL_FOV
	if not on:
		set_view(_view_before_zoom)


## 0 = cabina, 1 = detrás cerca, 2 = detrás lejos.
func set_view(view: int) -> void:
	if camera == null:
		return
	_view = view
	if view == 0:
		camera.top_level = false
		camera.transform = Transform3D(Basis(), Vector3(0.0, 0.35, 0.2))
		camera.cull_mask = 1
	else:
		camera.top_level = true
		camera.cull_mask = 1 | VISUAL_LAYER_OWN
		camera.global_transform = _chase_transform()


func _chase_transform() -> Transform3D:
	var offset: Vector2 = CHASE_OFFSETS[clampi(_view - 1, 0, 1)]
	var yaw: float = turret_controller.world_yaw
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye: Vector3 = global_position - forward * offset.x + Vector3.UP * offset.y
	var look: Vector3 = global_position + forward * 25.0 + Vector3.UP * 1.5
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


func _process(delta: float) -> void:
	if _wreck_age >= 0.0 and _update_wreck(delta):
		return
	_update_effects(delta)
	_animate_tracks(delta)
	_update_sound(delta)
	if camera != null and _view > 0:
		var target: Transform3D = _chase_transform()
		var t: float = 1.0 - exp(-8.0 * delta)
		camera.global_transform = Transform3D(camera.global_basis.slerp(target.basis, t).orthonormalized(), camera.global_position.lerp(target.origin, t))
	if camera != null:
		_shake = maxf(_shake - delta * 2.5, 0.0)
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25


## Sacudida de la cámara (explosiones cercanas, impactos); solo la nota el tanque del jugador.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.5)


## Las orugas corren según el avance y el giro del casco (una gira más que la otra al virar).
func _animate_tracks(delta: float) -> void:
	if _track_material == null or is_destroyed or delta <= 0.0:
		return
	var yaw: float = global_rotation.y
	var turn: float = angle_difference(_last_yaw, yaw) / delta
	_last_yaw = yaw
	var forward: float = velocity.dot(-global_basis.z)
	if absf(forward) < 0.01 and absf(turn) < 0.001:
		return
	var half_width: float = 1.7 * _scale_factor
	var link: float = 0.17 * _scale_factor
	_track_scroll.x = fposmod(_track_scroll.x - (forward - turn * half_width) * delta / link, 1.0)
	_track_scroll.y = fposmod(_track_scroll.y - (forward + turn * half_width) * delta / link, 1.0)
	_track_material.set_shader_parameter("track_offset", _track_scroll)


## Pone o quita el borde amarillo según el ajuste. Solo en tanques enemigos enteros.
func refresh_highlight() -> void:
	var on: bool = GameSettings.highlight_enemies and team != 0 and not is_player and not is_destroyed
	if on and _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.albedo_color = Color(1.0, 0.9, 0.1)
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.03
		_outline.disable_fog = true
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _outline if on else null


## Motor: grabaciones de tanques de verdad. En el tanque propio suenan dos bucles que se funden
## según el acelerador: el ralentí (un Sherman parado) y el motor en marcha grabado a bordo
## (con su ruido de orugas y transmisión). Los demás tanques usan una grabación desde fuera y se
## oyen según la distancia, así que se les oye llegar. El tono solo se mueve un poco: una
## grabación real muy estirada deja de sonar real.
func _build_sound() -> void:
	var heavy: bool = _scale_factor >= 1.2 or stats.tier >= 3
	_engine_pitch = clampf(1.0 / sqrt(maxf(_scale_factor, 0.5)), 0.88, 1.1) * randf_range(0.97, 1.03)
	if stats.wheels > 0:
		_engine_pitch *= 1.12
	var reach: float = 60.0 if is_player else 170.0
	if is_player:
		_engine_sound = Sfx.loop_player(Sfx.ENGINE_DRIVE, 40.0, reach)
		_idle_sound = Sfx.loop_player(Sfx.ENGINE_IDLE, 40.0, reach)
		_idle_sound.position.y = 1.2 * _scale_factor
		add_child(_idle_sound)
	else:
		_engine_sound = Sfx.loop_player(Sfx.ENGINE_HEAVY if heavy else Sfx.ENGINE_TANK, 9.0, reach)
	_engine_sound.position.y = 1.2 * _scale_factor
	add_child(_engine_sound)
	_update_sound(0.0)


func _update_sound(delta: float) -> void:
	if _engine_sound == null or is_destroyed:
		return
	var speed: float = clampf(velocity.length() / maxf(stats.max_speed, 1.0), 0.0, 1.0)
	var turning: float = clampf(absf(drive_input.x), 0.0, 1.0)
	# El motor sube de vueltas en cuanto se pisa el acelerador, antes de ganar velocidad.
	var throttle: float = clampf(maxf(absf(drive_input.y), turning * 0.6), 0.0, 1.0)
	_engine_level = move_toward(_engine_level, maxf(speed, throttle * 0.75), delta * 1.3)
	if _idle_sound == null:
		_engine_sound.pitch_scale = _engine_pitch * (0.88 + 0.24 * _engine_level)
		_engine_sound.volume_db = lerpf(-7.0, 3.0, _engine_level)
		return
	var drive: float = smoothstep(0.02, 0.45, _engine_level)
	_engine_sound.pitch_scale = _engine_pitch * (0.9 + 0.2 * _engine_level)
	_engine_sound.volume_db = lerpf(-45.0, -7.0, sqrt(drive))
	_idle_sound.pitch_scale = _engine_pitch * (1.0 + 0.12 * _engine_level)
	_idle_sound.volume_db = lerpf(-9.0, -32.0, drive)


func _set_sound_running(running: bool) -> void:
	for sound: AudioStreamPlayer3D in [_engine_sound, _idle_sound]:
		if sound == null:
			continue
		if running and not sound.playing:
			sound.play(randf() * 1.5)
		elif not running:
			sound.stop()
	_engine_level = 0.0


func _build_effects() -> void:
	var k: float = _scale_factor
	var rear: float = TankModel.HULL_SIZE.z * stats.hull_proportions.z * k * 0.5
	var half_width: float = TankModel.HULL_SIZE.x * stats.hull_proportions.x * k * 0.5
	_exhaust_at = Vector3(half_width * 0.45, 1.15 * k, rear * 0.98)
	_track_at = Vector3(half_width + 0.2 * k, 0.3 * k, rear * 0.85)
	_deck_at = Vector3(0.0, 1.3 * k, rear * 0.5)
	_turret_home = turret.position
	for mesh in _meshes:
		if mesh.get_parent() == gun_pivot:
			_gun_mesh = mesh


## Efectos que acompañan al tanque: el cañón que vuelve del retroceso, el humo del escape (más
## y más negro al acelerar), el polvo que levantan las orugas y el humo de las averías.
## A los tanques lejanos no se les pinta nada de esto.
func _update_effects(delta: float) -> void:
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	if _recoil > 0.0 and _gun_mesh != null:
		_recoil = maxf(_recoil - delta * 2.2, 0.0)
		_gun_mesh.position.z = _recoil * _recoil * RECOIL_TRAVEL * _scale_factor
	var near: float = _fx.nearness(global_position)
	if near <= 0.0 or is_destroyed:
		return
	var k: float = _scale_factor
	var speed: float = velocity.length()
	var throttle: float = clampf(maxf(absf(drive_input.y), absf(drive_input.x) * 0.6), 0.0, 1.0)
	_exhaust_due += delta * lerpf(4.0, 14.0, throttle) * near
	while _exhaust_due >= 1.0:
		_exhaust_due -= 1.0
		_fx.exhaust(global_transform * _exhaust_at, global_basis.z * randf_range(1.0, 2.5) + Vector3.UP * randf_range(0.5, 1.2) + velocity * 0.4, k, throttle * randf_range(0.6, 1.0))
	if speed > 2.0 and _fx.dustiness > 0.05:
		_dust_due += delta * minf(speed, 14.0) * 1.0 * near * minf(_fx.dustiness, 1.5)
		while _dust_due >= 1.0:
			_dust_due -= 1.0
			var side: float = -1.0 if randf() < 0.5 else 1.0
			var at: Vector3 = global_transform * Vector3(_track_at.x * side, _track_at.y, _track_at.z)
			_fx.track_dust(at, -velocity * 0.12 + Vector3(randf_range(-0.6, 0.6), randf_range(0.5, 1.4), randf_range(-0.6, 0.6)), k, clampf(speed / 9.0, 0.3, 0.85))
	var armor: float = health.fraction()
	if armor < 0.5:
		var level: float = 1.0 - armor / 0.5
		_smoke_due += delta * lerpf(2.5, 7.0, level) * near
		while _smoke_due >= 1.0:
			_smoke_due -= 1.0
			_fx.damage_smoke(global_transform * _deck_at, velocity * 0.3, k, level)


## Restos ardiendo: llamas en la cubierta del motor y en el anillo de la torreta, columna de
## humo negro, resplandor que parpadea y munición que va estallando. Los restos de un tanque
## de la máquina se apagan, se hunden y desaparecen. Devuelve `true` si el tanque se ha borrado.
func _update_wreck(delta: float) -> bool:
	_wreck_age += delta
	if _turret_flying:
		_fly_turret(delta)
	var fire: float = _wreck_fire
	if not is_player:
		if _wreck_age >= WRECK_TIME:
			queue_free()
			return true
		if _wreck_age > WRECK_TIME - WRECK_SINK:
			if collision_layer != 0:
				collision_layer = 0
				collision_mask = 0
				get_node("TankMovement").set_physics_process(false)
			global_position.y -= delta * 1.1
		fire *= clampf((WRECK_TIME - WRECK_SINK - 3.0 - _wreck_age) / 6.0, 0.0, 1.0)
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	var near: float = _fx.nearness(global_position)
	if near <= 0.0:
		return false
	var k: float = _scale_factor
	var ring: Vector3 = global_transform * Vector3(_turret_home.x, _turret_home.y - 0.2 * k, _turret_home.z)
	var deck: Vector3 = global_transform * _deck_at
	if fire > 0.02:
		_exhaust_due += delta * 20.0 * fire * near
		while _exhaust_due >= 1.0:
			_exhaust_due -= 1.0
			var source: Vector3 = ring if randf() < 0.55 else deck
			_fx.flame(source + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)) * k, Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)), randf_range(0.6, 1.0) * k * (0.6 + 0.4 * fire))
			if randf() < 0.14:
				_fx.ember(source + Vector3.UP * 0.5, Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 5.0), randf_range(-1.0, 1.0)))
		_light_timer -= delta
		if _light_timer <= 0.0 and near > 0.55:
			_light_timer = 0.1
			_fx.light(ring + Vector3.UP * 0.8, Color(1.0, 0.5, 0.18), randf_range(1.2, 2.4) * fire, 9.0 * k, 0.22)
		_pop_timer -= delta
		if _pop_timer <= 0.0 and _wreck_age < 14.0:
			_pop_timer = randf_range(1.8, 4.5)
			_fx.cook_off(ring, k)
			Sfx.play_at(self, Sfx.HIT, ring, -4.0, randf_range(1.2, 1.6))
	# El humo sigue saliendo cuando el fuego ya se apaga, cada vez más ralo.
	var smoke: float = maxf(fire, 0.25) if _wreck_age < WRECK_TIME - WRECK_SINK else 0.0
	_smoke_due += delta * 5.5 * smoke * near
	while _smoke_due >= 1.0:
		_smoke_due -= 1.0
		_fx.black_smoke(ring + Vector3(randf_range(-0.4, 0.4), randf_range(0.6, 1.4), randf_range(-0.4, 0.4)) * k, Vector3(randf_range(-0.3, 0.3), randf_range(2.2, 3.6), randf_range(-0.3, 0.3)), randf_range(1.1, 1.7) * k, randf_range(4.0, 6.5))
	return false


## La torreta arrancada sube dando vueltas y cae al suelo junto a los restos.
func _toss_turret() -> void:
	_turret_flying = true
	var side: float = -1.0 if randf() < 0.5 else 1.0
	_turret_velocity = Vector3(side * randf_range(2.8, 4.6), randf_range(8.0, 11.5), randf_range(-2.5, 2.5))
	_turret_spin = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), side * randf_range(1.5, 4.0))


func _fly_turret(delta: float) -> void:
	_turret_velocity.y -= 20.0 * delta
	turret.position += _turret_velocity * delta
	turret.rotation += _turret_spin * delta
	var rest: float = TankModel.TURRET_SIZE.y * stats.turret_scale * _scale_factor * 0.5 + 0.05
	if turret.position.y <= rest and _turret_velocity.y < 0.0:
		turret.position.y = rest
		_turret_flying = false
		# Queda tumbada, de lado o boca abajo.
		turret.rotation = Vector3(randf_range(-0.25, 0.25), turret.rotation.y, PI + randf_range(-0.5, 0.5) if randf() < 0.4 else randf_range(-0.6, 0.6))
		if is_instance_valid(_fx):
			var point: Vector3 = turret.global_position
			_fx.rubble(Vector3(point.x, 0.3, point.z), 1.2, Fronts.ground_colors(GameSession.front)[2])
			_fx.shake(point, 0.5)
		Sfx.play_at(self, Sfx.HIT_TANK, turret.global_position, 2.0, 0.7)


func _on_fired() -> void:
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	# El fogonazo crece con el calibre: el del Tiger no es el de un blindado de exploración.
	_fx.muzzle(muzzle.global_transform, clampf(_scale_factor * (0.65 + 0.35 * stats.barrel_thickness), 0.55, 1.7), velocity, stats.muzzle_brake)
	_recoil = 1.0
	if is_player:
		Sfx.play_2d(self, Sfx.CANNON, 2.0)
		_shake = maxf(_shake, 0.35)
	else:
		Sfx.play_at(self, Sfx.CANNON, muzzle.global_position, 0.0, 1.0 / maxf(_scale_factor, 0.7))


func _on_damaged(amount: float, source: Node) -> void:
	if is_player:
		_shake = minf(_shake + amount / 25.0, 1.5)
		# Impacto en nuestro propio blindaje: golpe metálico seco y fuerte.
		Sfx.play_2d(self, Sfx.HIT_TANK, 4.0, clampf(1.2 - amount / 60.0, 0.8, 1.2))
	damaged.emit(amount, source)


func _on_died(source: Node) -> void:
	is_destroyed = true
	drive_input = Vector2.ZERO
	trigger_held = false
	remove_from_group(&"tanks")
	_set_sound_running(false)
	refresh_highlight()
	hurtbox.set_deferred("monitorable", false)
	hurtbox.collision_layer = 0
	var blast: float = 1.0 * _scale_factor + 0.5
	var center: Vector3 = global_position + Vector3.UP * 1.0
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	_fx.tank_blast(center, blast)
	Sfx.play_at(self, Sfx.EXPLOSION, center, 6.0, 1.1 / clampf(blast, 0.8, 2.0))
	destroyed.emit(self, source)
	if is_player:
		_shake = 1.5
	# Quedan los restos calcinados, ardiendo.
	for i in _meshes.size():
		if is_instance_valid(_meshes[i]):
			_meshes[i].material_override = VectorMaterials.burnt(_materials[i])
	_wreck_age = 0.0
	_wreck_fire = randf_range(0.65, 1.0)
	_pop_timer = randf_range(1.2, 3.0)
	_exhaust_due = 0.0
	_smoke_due = 0.0
	if _gun_mesh != null:
		_gun_mesh.position.z = 0.0
	if turret != null:
		if not is_player and not stats.casemate and randf() < TURRET_TOSS_CHANCE:
			_toss_turret()
		else:
			turret.rotation += Vector3(randf_range(-0.2, 0.2), randf_range(-0.6, 0.6), randf_range(-0.3, 0.3))


## Reaparece (solo el jugador: los tanques de la máquina se crean de nuevo).
func revive(spawn: Transform3D) -> void:
	health.revive()
	is_destroyed = false
	_set_sound_running(true)
	add_to_group(&"tanks")
	hurtbox.collision_layer = LAYER_HURTBOX
	hurtbox.set_deferred("monitorable", true)
	for i in _meshes.size():
		if is_instance_valid(_meshes[i]):
			_meshes[i].material_override = _materials[i]
	_wreck_age = -1.0
	_turret_flying = false
	turret.position = _turret_home
	turret.rotation = Vector3.ZERO
	turret_controller.setup(self)
	global_transform = spawn
	velocity = Vector3.ZERO
	aim_lock = null


func _build_body() -> void:
	var model: TankModel = TankModel.build(self, stats, paint, is_player)
	turret = model.turret
	gun_pivot = model.gun_pivot
	muzzle = model.muzzle
	_meshes = model.own
	_track_material = model.material
	_last_yaw = global_rotation.y
	for mesh in _meshes:
		_materials.append(mesh.material_override)
	var k: float = _scale_factor
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(model.hull_size.x + 1.0 * k, 1.4 * k, model.hull_size.z)
	shape.shape = box
	shape.position.y = 0.75 * k
	add_child(shape)

	if is_player:
		for mesh in _meshes:
			mesh.layers = VISUAL_LAYER_OWN
		camera = Camera3D.new()
		camera.name = "Camera"
		camera.fov = 75.0
		camera.near = 0.1
		camera.far = 600.0
		camera.cull_mask = 1
		camera.position = Vector3(0.0, 0.35, 0.2)
		gun_pivot.add_child(camera)
		camera.current = true


func _build_components() -> void:
	var k: float = _scale_factor
	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = stats.max_armor
	add_child(health)

	hurtbox = Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = LAYER_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.health = health
	hurtbox.team = team
	var hurt_shape := CollisionShape3D.new()
	var hurt_box := BoxShape3D.new()
	hurt_box.size = Vector3(TankModel.HULL_SIZE.x * stats.hull_proportions.x * k + 1.2 * k, 2.6 * k, TankModel.HULL_SIZE.z * stats.hull_proportions.z * k + 0.2)
	hurt_shape.shape = hurt_box
	hurt_shape.position.y = 1.3 * k
	hurtbox.add_child(hurt_shape)
	add_child(hurtbox)

	var movement := TankMovement.new()
	movement.name = "TankMovement"
	add_child(movement)
	movement.setup(self)

	turret_controller = TurretController.new()
	turret_controller.name = "TurretController"
	add_child(turret_controller)
	turret_controller.setup(self)

	weapon = TankWeapon.new()
	weapon.name = "TankWeapon"
	weapon.projectile_scene = load("res://entities/projectiles/shell.tscn")
	weapon.projectile_speed = stats.projectile_speed
	weapon.damage = stats.damage
	weapon.reload_time = stats.reload_time
	weapon.muzzle = muzzle
	weapon.ignore_rids = [hurtbox.get_rid()]
	weapon.team = team
	weapon.fired.connect(_on_fired)
	add_child(weapon)
