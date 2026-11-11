class_name FxCpuFamily
extends MultiMeshInstance3D
## Familia de partículas movida por la CPU. Solo se usa cuando el teléfono no tiene Vulkan y el
## juego arranca con el renderizador de compatibilidad (OpenGL), que no admite lanzar
## partículas a mano en la GPU. Usa las mismas mallas y los mismos shaders de dibujo que la
## versión de GPU y la misma física que shaders/fx_particles.gdshader (sin remolinos ni giro de
## cascotes, para no gastar): lo único que cambia es quién mueve las partículas.

enum Shape { BILLBOARD, STREAK, MESH }

const STRIDE: int = 20

var shape: int = Shape.BILLBOARD
var wind := Vector3.ZERO

var _cap: int = 0
var _next: int = 0
var _active: int = 0
var _alive := PackedByteArray()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _size := PackedVector3Array()
var _custom := PackedColorArray()
var _basis: Array[Basis] = []
var _buffer := PackedFloat32Array()
var _dirty: bool = false
# Física por clase (ver fx_particles.gdshader).
var _gravity := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _wind_pull := PackedFloat32Array()
var _ground := PackedInt32Array()
var _bounce: float = 0.35
var _ground_offset: float = 0.0
var _stretch: float = 0.0
var _stretch_range := Vector2(0.1, 2.0)


func setup(amount: int, physics: Dictionary, mesh: Mesh, field: AABB) -> void:
	_cap = amount
	_alive.resize(amount)
	_pos.resize(amount)
	_vel.resize(amount)
	_size.resize(amount)
	_custom.resize(amount)
	_basis.resize(amount)
	_buffer.resize(amount * STRIDE)
	for key: String in ["gravity_y", "drag", "wind_pull"]:
		var values := PackedFloat32Array()
		values.resize(8)
		var given: Array = physics.get(key, [])
		for i in given.size():
			values[i] = given[i]
		match key:
			"gravity_y": _gravity = values
			"drag": _drag = values
			_: _wind_pull = values
	_ground.resize(8)
	var floors: Array = physics.get("ground", [])
	for i in floors.size():
		_ground[i] = floors[i]
	_bounce = physics.get("bounce", _bounce)
	_ground_offset = physics.get("ground_offset", _ground_offset)
	_stretch = physics.get("stretch", 0.0)
	_stretch_range = physics.get("stretch_range", _stretch_range)
	var data := MultiMesh.new()
	data.transform_format = MultiMesh.TRANSFORM_3D
	data.use_colors = true
	data.use_custom_data = true
	data.mesh = mesh
	data.instance_count = amount
	data.buffer = _buffer
	multimesh = data
	custom_aabb = field
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Misma firma que GPUParticles3D.emit_particle (sin las banderas).
func emit(xform: Transform3D, velocity: Vector3, color: Color, custom: Color) -> void:
	var slot: int = _next
	# Busca un hueco libre; si no lo hay, pisa la partícula más antigua de la rueda.
	for attempt in 8:
		if _alive[slot] == 0:
			break
		slot = (slot + 1) % _cap
	_next = (slot + 1) % _cap
	if _alive[slot] == 0:
		_active += 1
	_alive[slot] = 1
	_pos[slot] = xform.origin
	_vel[slot] = velocity
	_size[slot] = xform.basis.get_scale()
	_basis[slot] = xform.basis
	_custom[slot] = custom
	var o: int = slot * STRIDE
	_buffer[o + 12] = color.r
	_buffer[o + 13] = color.g
	_buffer[o + 14] = color.b
	_buffer[o + 15] = color.a


## Avanza la simulación y entrega las partículas vivas a la tarjeta gráfica. `eye` es la
## posición de la cámara (los trazos de las chispas se orientan hacia ella).
func step(delta: float, eye: Vector3) -> void:
	if _active == 0 and not _dirty:
		return
	_dirty = _active > 0
	for i in _cap:
		if _alive[i] == 0:
			continue
		var o: int = i * STRIDE
		var custom: Color = _custom[i]
		var life: float = maxf(custom.a, 0.02)
		var age: float = custom.g + delta / life
		if age >= 1.0:
			_kill(i, o)
			continue
		custom.g = age
		_custom[i] = custom
		var p: Vector3 = _pos[i]
		var size: Vector3 = _size[i]
		if age > 0.0:
			var kind: int = clampi(int(custom.r), 0, 7)
			var floor_mode: int = _ground[kind]
			var v: Vector3 = _vel[i]
			var floor_y: float = size.x * _ground_offset
			var resting: bool = floor_mode >= 2 and floor_mode <= 3 and p.y <= floor_y + 0.002 and v.length_squared() < 0.04
			if not resting:
				v.y += _gravity[kind] * delta
				v *= exp(-_drag[kind] * delta)
				var pull: float = _wind_pull[kind]
				if pull > 0.0:
					var blend: float = 1.0 - exp(-pull * delta)
					v.x += (wind.x - v.x) * blend
					v.z += (wind.z - v.z) * blend
				p += v * delta
				if floor_mode > 0 and p.y < floor_y:
					if floor_mode == 1:
						_kill(i, o)
						continue
					p.y = floor_y
					if floor_mode == 2:
						v = Vector3(v.x * 0.55, -v.y * _bounce, v.z * 0.55)
						if v.y < 1.2:
							v = Vector3.ZERO
					elif floor_mode == 3:
						v = Vector3.ZERO
					else:
						v.y = maxf(v.y, 0.0)
				_pos[i] = p
				_vel[i] = v
		match shape:
			Shape.BILLBOARD:
				_buffer[o] = size.x
				_buffer[o + 5] = size.x
				_buffer[o + 10] = size.x
			Shape.STREAK:
				# Eje Y a lo largo de la velocidad y de cara a la cámara.
				var v: Vector3 = _vel[i]
				var speed: float = v.length()
				var along: Vector3 = v / speed if speed > 0.001 else Vector3.UP
				var side: Vector3 = along.cross(eye - p)
				side = side.normalized() if side.length_squared() > 0.000001 else Vector3.RIGHT
				# Las trazadoras (clase 2) dejan un trazo más largo que las chispas.
				var longest: float = _stretch_range.y * (3.5 if int(custom.r) == 2 else 1.0)
				var length: float = clampf(speed * _stretch, _stretch_range.x, longest)
				_write_basis(o, Basis(side * size.x, along * length, side.cross(along)))
			_:
				_write_basis(o, _basis[i])
		_buffer[o + 3] = p.x
		_buffer[o + 7] = p.y
		_buffer[o + 11] = p.z
		_buffer[o + 16] = custom.r
		_buffer[o + 17] = custom.g
		_buffer[o + 18] = custom.b
		_buffer[o + 19] = custom.a
	multimesh.buffer = _buffer


func _kill(index: int, o: int) -> void:
	_alive[index] = 0
	_active -= 1
	# Transformación nula: la partícula deja de verse.
	for k in 12:
		_buffer[o + k] = 0.0


func _write_basis(o: int, basis: Basis) -> void:
	_buffer[o] = basis.x.x
	_buffer[o + 1] = basis.y.x
	_buffer[o + 2] = basis.z.x
	_buffer[o + 4] = basis.x.y
	_buffer[o + 5] = basis.y.y
	_buffer[o + 6] = basis.z.y
	_buffer[o + 8] = basis.x.z
	_buffer[o + 9] = basis.y.z
	_buffer[o + 10] = basis.z.z
