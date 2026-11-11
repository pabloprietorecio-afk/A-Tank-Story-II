class_name PracticeProps
## Piezas del campo de prácticas del tutorial: dianas, balizas y la valla que lo delimita.


## Diana de tiro: un tablero redondo sobre dos postes. Cuenta los impactos que recibe.
class Target extends Destructible:
	signal was_hit

	var hits: int = 0
	## El jugador ya ha puesto la mira sobre ella (lección de la torreta).
	var acquired: bool = false
	var _rings: Array[MeshInstance3D] = []

	func _init() -> void:
		max_health = 50.0
		debris_color = Color(0.85, 0.8, 0.7)
		size_hint = 2.0
		# Al destruirla se tumba hacia atrás.
		topples = true
		var colors: Array[Color] = [Color(0.95, 0.95, 0.9), Color(0.85, 0.12, 0.1), Color(0.95, 0.95, 0.9), Color(0.85, 0.12, 0.1)]
		var radii: Array[float] = [1.7, 1.25, 0.8, 0.35]
		for i in 4:
			var mesh := CylinderMesh.new()
			mesh.top_radius = radii[i]
			mesh.bottom_radius = radii[i]
			mesh.height = 0.12 + i * 0.04
			mesh.radial_segments = 28
			var ring := MeshInstance3D.new()
			ring.mesh = mesh
			ring.material_override = VectorMaterials.flat(colors[i])
			ring.rotation.x = PI * 0.5
			ring.position.y = 2.3
			add_child(ring)
			_rings.append(ring)
		for x in [-1.2, 1.2]:
			var post := VectorMaterials.make_box(Vector3(0.18, 2.3, 0.18), Color(0.4, 0.3, 0.2))
			post.position = Vector3(x, 1.15, 0.12)
			add_child(post)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.4, 3.6, 0.5)
		shape.shape = box
		shape.position.y = 2.2
		add_child(shape)

	## Centro del tablero, donde hay que apuntar.
	func center() -> Vector3:
		return global_position + Vector3.UP * 2.3

	## La diana se pone verde cuando la mira ya ha pasado por ella.
	func mark_acquired() -> void:
		if acquired:
			return
		acquired = true
		_rings[1].material_override = VectorMaterials.flat(Color(0.2, 0.8, 0.3))
		_rings[3].material_override = VectorMaterials.flat(Color(0.2, 0.8, 0.3))

	func take_hit(amount: float, source: Node = null, point: Vector3 = Vector3.ZERO) -> void:
		if is_destroyed:
			return
		hits += 1
		was_hit.emit()
		super.take_hit(amount, source, point)


## Baliza: columna de luz y aro en el suelo. Se ve en el radar (cuadrado, o rombo si es objetivo).
class Beacon extends Node3D:
	const ACTIVE := Color(1.0, 0.85, 0.15)
	const WAITING := Color(0.55, 0.55, 0.5)

	var _beam_mat: StandardMaterial3D
	var _ring_mat: StandardMaterial3D
	var _light: OmniLight3D
	var _t: float = 0.0

	func _init() -> void:
		var beam := MeshInstance3D.new()
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = 0.5
		beam_mesh.bottom_radius = 1.1
		beam_mesh.height = 26.0
		beam_mesh.radial_segments = 10
		beam.mesh = beam_mesh
		_beam_mat = _glow()
		beam.material_override = _beam_mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position.y = 13.0
		add_child(beam)
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 4.3
		ring_mesh.outer_radius = 5.0
		ring_mesh.rings = 32
		ring_mesh.ring_segments = 6
		ring.mesh = ring_mesh
		_ring_mat = _glow()
		ring.material_override = _ring_mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.15
		ring.scale.y = 0.2
		add_child(ring)
		_light = OmniLight3D.new()
		_light.omni_range = 9.0
		_light.light_energy = 1.5
		_light.position.y = 2.5
		add_child(_light)
		add_to_group(&"radar_marks")
		set_active(true)

	func _glow() -> StandardMaterial3D:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat

	## La baliza activa es amarilla; las que vienen después, grises.
	func set_active(on: bool) -> void:
		var color: Color = ACTIVE if on else WAITING
		_beam_mat.albedo_color = Color(color, 0.4 if on else 0.15)
		_ring_mat.albedo_color = Color(color, 0.95 if on else 0.4)
		_light.light_color = color
		_light.visible = on
		set_meta("radar_color", color)

	func set_diamond() -> void:
		set_meta("radar_shape", "diamond")

	func _process(delta: float) -> void:
		_t += delta
		_light.light_energy = 1.5 + sin(_t * 5.0) * 0.6

	func point() -> Vector2:
		return Vector2(global_position.x, global_position.z)


## Valla de postes y travesaños alrededor del campo, con una barrera que solo paran los tanques.
static func build_fence(world: Node3D, half: float) -> void:
	var rail_color := Color(0.5, 0.4, 0.28)
	for side in [-1.0, 1.0]:
		for horizontal in [true, false]:
			var body := StaticBody3D.new()
			body.collision_layer = Tank.LAYER_BOUNDARY
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(half * 2.0 + 8.0, 60.0, 4.0) if horizontal else Vector3(4.0, 60.0, half * 2.0 + 8.0)
			shape.shape = box
			body.add_child(shape)
			body.position = Vector3(0.0, 30.0, side * (half + 2.0)) if horizontal else Vector3(side * (half + 2.0), 30.0, 0.0)
			world.add_child(body)
			for height in [0.7, 1.4]:
				var rail_size := Vector3(half * 2.0, 0.14, 0.14) if horizontal else Vector3(0.14, 0.14, half * 2.0)
				var rail := VectorMaterials.make_box(rail_size, rail_color)
				rail.position = Vector3(0.0, height, side * half) if horizontal else Vector3(side * half, height, 0.0)
				world.add_child(rail)
	var count: int = int(half * 2.0 / 10.0)
	for i in count + 1:
		var along: float = -half + i * 10.0
		for side in [-1.0, 1.0]:
			for horizontal in [true, false]:
				var post := VectorMaterials.make_box(Vector3(0.25, 1.8, 0.25), Color(0.85, 0.85, 0.8) if i % 2 == 0 else Color(0.75, 0.15, 0.1))
				post.position = Vector3(along, 0.9, side * half) if horizontal else Vector3(side * half, 0.9, along)
				world.add_child(post)
