class_name Missile
extends Node3D
## Cohete guiado de largo alcance: persigue al objetivo fijado (si lo hay) y hace daño de área.

const SPEED: float = 95.0
const TURN_RATE: float = 2.2
const LIFETIME: float = 6.0
const DAMAGE: float = 120.0
const SPLASH_RADIUS: float = 7.0
const MASK: int = 1 | 4

var target: Tank
var shooter: Tank
var velocity: Vector3
var _life: float = LIFETIME
var _ignore: Array[RID] = []
var _fx: Fx
var _trail_due: float = 0.0


static func fire(from: Tank, lock: Tank) -> Missile:
	var missile := Missile.new()
	missile.shooter = from
	missile.target = lock
	missile._ignore = [from.hurtbox.get_rid(), from.get_rid()]
	var root: Node = from.get_tree().current_scene if from.get_tree().current_scene != null else from.get_tree().root
	root.add_child(missile)
	var dir: Vector3 = -from.muzzle.global_transform.basis.z
	missile.global_position = from.muzzle.global_position + Vector3.UP * 0.4
	missile.velocity = dir * SPEED
	Sfx.play_2d(from, Sfx.MISSILE, 0.0)
	# Rebufo del lanzamiento: humo blanco y un fogonazo junto al tanque.
	var fx: Fx = Fx.on(from)
	fx.glow(Fx.Glow.FLASH, missile.global_position, Vector3.ZERO, 4.0, 0.12, Fx.FLASH, 0.9)
	for i in 8:
		fx.puff(Fx.Puff.JET, missile.global_position - dir * randf_range(0.5, 2.5), -dir * randf_range(4.0, 12.0) + Fx.ball() * 2.0, randf_range(0.6, 1.0), randf_range(1.2, 2.2), Color(0.55, 0.54, 0.52, 0.8), -0.8, i * 0.01)
	return missile


func _ready() -> void:
	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.18
	mesh.height = 1.6
	mesh.radial_segments = 8
	body.mesh = mesh
	body.material_override = VectorMaterials.flat(Color(0.8, 0.8, 0.75))
	body.rotation.x = -PI * 0.5
	add_child(body)
	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.6, 0.2)
	flame.omni_range = 7.0
	flame.light_energy = 3.0
	add_child(flame)


## Llama del motor y estela de humo blanco que se queda flotando detrás.
func _process(delta: float) -> void:
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	var dir: Vector3 = velocity.normalized()
	var tail: Vector3 = global_position - dir * 0.9
	_fx.glow(Fx.Glow.HALO, tail, velocity, randf_range(1.5, 2.0), 0.07, Fx.FLASH, 1.0)
	_fx.spark(tail, -dir * randf_range(18.0, 30.0) + velocity, 0.34, 0.07, Fx.FLASH, 0.0, 0.0, 1)
	# Una bocanada por metro recorrido, repartidas por el tramo de este fotograma: la estela
	# queda continua vaya el misil a la velocidad que vaya.
	var step: float = velocity.length() * delta
	_trail_due += step / 1.1
	var count: int = int(_trail_due)
	_trail_due -= count
	for i in count:
		_fx.puff(Fx.Puff.HAZE, tail - dir * step * (i + randf()) / count, -dir * randf_range(1.0, 4.0) + Fx.ball() * 0.8, randf_range(0.7, 1.0), randf_range(1.4, 2.2), Color(0.42, 0.41, 0.4, 0.8), -0.9)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_explode(global_position)
		return
	if is_instance_valid(target) and not target.is_destroyed:
		var desired: Vector3 = (target.global_position + Vector3.UP * 1.2 - global_position).normalized() * SPEED
		velocity = velocity.lerp(desired, clampf(TURN_RATE * delta, 0.0, 1.0)).normalized() * SPEED
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, MASK)
	query.collide_with_areas = true
	query.exclude = _ignore
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_explode(hit["position"])
		return
	global_position = to
	look_at(to + velocity, Vector3.UP)


func _explode(point: Vector3) -> void:
	Explosion.spawn(self, point, 1.8)
	var sphere := SphereShape3D.new()
	sphere.radius = SPLASH_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), point)
	query.collision_mask = MASK
	query.collide_with_areas = true
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 24):
		var collider: Object = hit["collider"]
		if collider is Hurtbox and (collider as Hurtbox).team == shooter.team:
			continue
		if collider.has_method("take_hit"):
			collider.take_hit(DAMAGE, shooter, (collider as Node3D).global_position + Vector3.UP)
	queue_free()
