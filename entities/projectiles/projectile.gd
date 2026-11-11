class_name Projectile
extends Node3D
## Proyectil recto. Cada tick lanza un rayo de la posición anterior a la nueva, así un
## proyectil rápido no atraviesa paredes finas. Solo conoce a `Hurtbox`.
## Se reutilizan mediante un pequeño pool para evitar crear y destruir nodos.
## Se ve como una trazadora: una estela de luz con la cabeza incandescente.

const MASK_WORLD: int = 1
const MASK_HURTBOX: int = 4
const LIFETIME: float = 3.0
const MAX_SKIPS: int = 4
## Color de la trazadora según el país de quien dispara. Es una simplificación: las aliadas
## occidentales eran casi siempre rojas; las alemanas y las soviéticas variaron según la munición.
const TRACER_COLORS: Dictionary = {
	"US": Color(1.0, 0.3, 0.14), "UK": Color(1.0, 0.3, 0.14),
	"DE": Color(1.0, 0.82, 0.5), "SU": Color(0.5, 1.0, 0.45),
}
## Segundos de vuelo que abarca la estela (su largo es velocidad × esto).
const TRAIL_TIME: float = 0.045
## Color del polvo que salta de los muros del campo.
const WALL_COLOR := Color(0.45, 0.43, 0.4)

static var _pool: Array[Projectile] = []
static var _tracer_mesh: ArrayMesh
static var _tracer_material: ShaderMaterial

var velocity: Vector3 = Vector3.ZERO
var damage: float = 0.0
var shooter: Node = null
var team: int = 0

var _ignore: Array[RID] = []
var _life: float = LIFETIME
var _released: bool = false
var _tracer: MeshInstance3D
var _travelled: float = 0.0
var _trail: float = 6.0


static func acquire(scene: PackedScene, parent: Node) -> Projectile:
	while not _pool.is_empty():
		var pooled: Projectile = _pool.pop_back()
		if is_instance_valid(pooled):
			parent.add_child(pooled)
			return pooled
	var fresh: Projectile = scene.instantiate() as Projectile
	parent.add_child(fresh)
	return fresh


func _ready() -> void:
	if _tracer_mesh == null:
		_tracer_mesh = _build_tracer_mesh()
		_tracer_material = ShaderMaterial.new()
		_tracer_material.shader = load("res://shaders/fx_tracer.gdshader")
		_tracer_material.render_priority = 6
	_tracer = MeshInstance3D.new()
	_tracer.mesh = _tracer_mesh
	_tracer.material_override = _tracer_material
	_tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La estela se coloca en el shader: la caja de visibilidad debe abarcarla entera.
	_tracer.custom_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3(4.0, 4.0, 16.0))
	add_child(_tracer)


## Dos cuadrados: la estela (color de vértice 0) y la cabeza (color de vértice 1).
static func _build_tracer_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in 2:
		var corners: Array[Vector2] = [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var corner: Vector2 = corners[index]
			tool.set_color(Color(part, 0.0, 0.0))
			tool.set_uv(Vector2(corner.x + 0.5, 0.5 - corner.y))
			tool.add_vertex(Vector3(corner.x, corner.y, 0.0))
	return tool.commit()


func launch(origin: Vector3, new_velocity: Vector3, new_damage: float, owner_node: Node, ignore: Array[RID], new_team: int) -> void:
	_released = false
	_life = LIFETIME
	visible = true
	set_physics_process(true)
	global_position = origin
	velocity = new_velocity
	damage = new_damage
	shooter = owner_node
	team = new_team
	_ignore = ignore.duplicate()
	look_at(origin + new_velocity, Vector3.UP)
	var nation: String = (owner_node as Tank).stats.nation if owner_node is Tank else "US"
	_travelled = 0.0
	_trail = clampf(new_velocity.length() * TRAIL_TIME, 3.0, 12.0)
	var tint: Color = (TRACER_COLORS.get(nation, TRACER_COLORS["US"]) as Color).srgb_to_linear()
	_tracer.set_instance_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_tracer.set_instance_shader_parameter("trail", 0.0)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_release()
		return
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	# Espoleta de proximidad contra aviones (como la artillería antiaérea real).
	if team == 0:
		for node in get_tree().get_nodes_in_group(&"air_targets"):
			var air := node as AirTarget
			if air == null or air.is_destroyed:
				continue
			var closest: Vector3 = Geometry3D.get_closest_point_to_segment(air.global_position, from, to)
			if closest.distance_to(air.global_position) <= AirTarget.PROXIMITY:
				air.hurtbox.take_hit(damage, shooter, closest)
				Fx.on(self).airburst(closest, 0.8)
				Sfx.play_at(self, Sfx.EXPLOSION, closest, 6.0, 1.1 / 0.8)
				_release()
				return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for attempt in MAX_SKIPS:
		var query := PhysicsRayQueryParameters3D.create(from, to, MASK_WORLD | MASK_HURTBOX)
		query.collide_with_areas = true
		query.exclude = _ignore
		var result: Dictionary = space.intersect_ray(query)
		if result.is_empty():
			_advance(to, delta)
			return
		var collider: Object = result["collider"]
		if collider is Hurtbox:
			var hurtbox: Hurtbox = collider
			if hurtbox.team == team:
				_ignore.append(hurtbox.get_rid())
				continue
		_impact(collider, result["position"], result.get("normal", Vector3.UP))
		_release()
		return
	_advance(to, delta)


func _advance(to: Vector3, delta: float) -> void:
	global_position = to
	# La estela crece desde la boca del cañón: no asoma por detrás del tanque que dispara.
	_travelled += velocity.length() * delta
	_tracer.set_instance_shader_parameter("trail", minf(_trail, _travelled))


## Golpe contra algo: reparte el daño y pide a Fx el efecto que toca según contra qué da.
func _impact(collider: Object, point: Vector3, normal: Vector3) -> void:
	var fx: Fx = Fx.on(self)
	var power: float = clampf(sqrt(damage / 25.0), 0.8, 1.6)
	if collider is Hurtbox:
		(collider as Hurtbox).take_hit(damage, shooter, point)
		# La zona de impacto envuelve al vehículo con holgura: las chispas saltan del blindaje.
		fx.shell_armor(point + velocity.normalized() * 0.3, normal, power)
	elif collider.has_method("take_hit"):
		# Árboles, casas, vallas...: el propio objeto pone su polvo y sus cascotes.
		collider.take_hit(damage, shooter, point)
		fx.pop(point + normal * 0.2, power * 0.6)
	elif normal.y > 0.6 and point.y < 1.0:
		fx.shell_ground(point, power)
	else:
		fx.shell_solid(point, normal, WALL_COLOR, power)
	Sfx.play_at(self, Sfx.HIT, point, 2.0)


func _release() -> void:
	if _released:
		return
	_released = true
	set_physics_process(false)
	visible = false
	_return_to_pool.call_deferred()


func _return_to_pool() -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	_pool.append(self)
