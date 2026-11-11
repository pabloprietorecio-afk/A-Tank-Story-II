class_name Fx
extends Node3D
## Efectos visuales de todo el juego: explosiones, fogonazos, impactos, humo, polvo, chispas,
## cascotes, luces fugaces y marcas en el suelo.
##
## Cada familia de partículas es un único GPUParticles3D para todo el campo: una sola llamada de
## dibujo por familia, haya una explosión o veinte. Las partículas no salen solas; cada efecto
## las lanza una a una con emit_particle() —posición, velocidad, tamaño, color, retardo—, así
## que la forma de cada explosión se decide aquí, en código, y no en un emisor genérico.
## Las mueve shaders/fx_particles.gdshader y las dibujan fx_puff (humo, polvo y fuego con
## volumen e iluminación), fx_glow y fx_streak (luz que se suma) y fx_debris (cascotes).
##
## En teléfonos sin Vulkan el juego arranca con el renderizador de compatibilidad (OpenGL), que
## no admite lanzar partículas a mano en la GPU: ahí las mueve la CPU (FxCpuFamily), con menos
## partículas, pero con las mismas mallas y los mismos shaders de dibujo.
##
## Uso: `Fx.on(nodo).explosion(punto, fuerza)`.

## Clases de bocanada (cada una con su física y su aspecto; ver _build_cloud).
enum Puff { FIRE, SMOKE, DUST, JET, CLOD, HAZE, PLUME }
## Tipos de luz sumada (ver fx_glow.gdshader).
enum Glow { FLASH, HALO, EMBER, STAR }

const QUALITY_NAMES: Array[String] = ["BAJOS", "MEDIOS", "ALTOS"]
const _COUNT_SCALE: Array[float] = [0.4, 0.7, 1.0]
const _LIGHTS: Array[int] = [2, 3, 5]
const _EMIT_ALL: int = GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM
const _FIELD := AABB(Vector3(-700.0, -5.0, -700.0), Vector3(1400.0, 420.0, 1400.0))
const MAX_MARKS: int = 48
const MARK_TIME: float = 70.0

# Colores en espacio lineal (los shaders los usan tal cual).
## Humo negro de combustible y goma ardiendo.
const SOOT := Color(0.028, 0.025, 0.023)
const DARK_SMOKE := Color(0.075, 0.07, 0.066)
const GREY_SMOKE := Color(0.19, 0.18, 0.17)
## Humo de pólvora: gris claro algo pardo.
const GUN_SMOKE := Color(0.3, 0.29, 0.27)
const FLASH := Color(1.0, 0.85, 0.58)
const FIRE_GLOW := Color(1.0, 0.48, 0.15)
const SPARK := Color(1.0, 0.8, 0.46)
const WHITE_HOT := Color(1.0, 0.93, 0.8)
const EMBER := Color(1.0, 0.4, 0.07)
const CHARRED := Color(0.012, 0.011, 0.01)

## Nivel de efectos elegido en ⚙ (0 bajos, 1 medios, 2 altos).
static var quality: int = 2
## Bajar solo el nivel si el teléfono no puede (las herramientas de captura lo apagan).
static var governor: bool = true

static var _live: Fx
static var _noise: ImageTexture

## Tanque del jugador: recibe las sacudidas de cámara.
var player: Tank
## Techo de nubes de la partida, si lo hay: los destellos grandes lo alumbran.
var sky: CloudDome
## Color del polvo y de la tierra del frente (lineal) y cuánto polvo levanta el suelo
## (1 seco, casi nada con lluvia o nieve).
var dust := Color(0.12, 0.095, 0.07)
var soil := Color(0.055, 0.035, 0.02)
var dustiness: float = 1.0
var wind := Vector3(1.6, 0.0, 0.7)
## Número de partículas lanzadas (para pruebas y medidas).
var emitted: int = 0

## Las partículas las mueve la GPU (lo normal) o, sin Vulkan, la CPU.
var _gpu: bool = true
var _cloud: Node3D
var _glow: Node3D
var _spark: Node3D
var _debris: Node3D
var _marks: MultiMesh
var _mark_born: PackedFloat32Array = PackedFloat32Array()
var _mark_seed: PackedFloat32Array = PackedFloat32Array()
var _mark_next: int = 0
var _mark_count: int = 0
var _mark_tick: float = 0.0
var _lights: Array[OmniLight3D] = []
var _light_from: PackedFloat32Array = PackedFloat32Array()
var _light_time: PackedFloat32Array = PackedFloat32Array()
var _light_left: PackedFloat32Array = PackedFloat32Array()
var _camera_pos: Vector3 = Vector3.ZERO
var _clock: float = 0.0
## Nivel efectivo: el elegido, o menos si el regulador lo ha bajado.
var _level: int = 2
var _slow_time: float = 0.0


## Efectos de la escena en la que está `host` (se crean la primera vez que se piden).
static func on(host: Node) -> Fx:
	if is_instance_valid(_live) and _live.is_inside_tree():
		return _live
	var tree: SceneTree = host.get_tree()
	var top: Node = host
	while top.get_parent() != null and top.get_parent() != tree.root:
		top = top.get_parent()
	_live = Fx.new()
	_live.name = "Fx"
	top.add_child(_live)
	return _live


## Textura de ruido de los efectos: cuatro ruidos continuos y repetibles, uno por canal
## (R jirones, G borbotones, B grano fino, A crestas).
static func noise() -> ImageTexture:
	if _noise == null:
		const SIZE: int = 128
		var layers: Array[PackedByteArray] = []
		for i in 4:
			var source := FastNoiseLite.new()
			source.seed = 1944 + i * 11
			source.fractal_type = FastNoiseLite.FRACTAL_FBM
			source.fractal_gain = 0.55
			match i:
				0:
					source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
					source.frequency = 0.02
					source.fractal_octaves = 4
				1:
					source.noise_type = FastNoiseLite.TYPE_CELLULAR
					source.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
					source.frequency = 0.034
					source.fractal_octaves = 3
				2:
					source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
					source.frequency = 0.07
					source.fractal_octaves = 3
				_:
					source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
					source.fractal_type = FastNoiseLite.FRACTAL_RIDGED
					source.frequency = 0.025
					source.fractal_octaves = 3
			var layer: Image = source.get_seamless_image(SIZE, SIZE, i == 1)
			layer.convert(Image.FORMAT_L8)
			layers.append(layer.get_data())
		var data := PackedByteArray()
		data.resize(SIZE * SIZE * 4)
		for p in SIZE * SIZE:
			data[p * 4] = layers[0][p]
			data[p * 4 + 1] = layers[1][p]
			data[p * 4 + 2] = layers[2][p]
			data[p * 4 + 3] = layers[3][p]
		var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
		image.generate_mipmaps()
		_noise = ImageTexture.create_from_image(image)
	return _noise


func _ready() -> void:
	_gpu = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	_build_cloud()
	_build_glow()
	_build_spark()
	_build_debris()
	_build_marks()
	set_level(quality)
	set_wind(wind)


# ------------------------------------------------------------------ construcción

func _family(family_name: String, amount: int, lifetime: float, physics: Dictionary, mesh: Mesh, shape: int = FxCpuFamily.Shape.BILLBOARD) -> Node3D:
	if not _gpu:
		var cpu := FxCpuFamily.new()
		cpu.name = family_name
		cpu.shape = shape
		# La CPU mueve muchas menos partículas que la GPU.
		cpu.setup(amount / 2, physics, mesh, _FIELD)
		add_child(cpu)
		return cpu
	var process := ShaderMaterial.new()
	process.shader = load("res://shaders/fx_particles.gdshader")
	for key: String in ["gravity_y", "drag", "wind_pull", "swirl"]:
		var values := PackedFloat32Array()
		values.resize(8)
		var given: Array = physics.get(key, [])
		for i in given.size():
			values[i] = given[i]
		process.set_shader_parameter(key, values)
	var floors := PackedInt32Array()
	floors.resize(8)
	var given_floors: Array = physics.get("ground", [])
	for i in given_floors.size():
		floors[i] = given_floors[i]
	process.set_shader_parameter("ground", floors)
	for key: String in ["bounce", "ground_offset", "stretch", "stretch_range", "tumble"]:
		if physics.has(key):
			process.set_shader_parameter(key, physics[key])
	var particles := GPUParticles3D.new()
	particles.name = family_name
	particles.amount = amount
	# Nadie emite solo: `lifetime` solo fija cuánto tarda el sistema en dormirse tras la
	# última partícula lanzada, así que debe cubrir la partícula más longeva.
	particles.lifetime = lifetime
	particles.emitting = false
	particles.one_shot = false
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.local_coords = false
	particles.visibility_aabb = _FIELD
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = process
	particles.draw_pass_1 = mesh
	if shape == FxCpuFamily.Shape.STREAK:
		particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	add_child(particles)
	return particles


## Lanza una partícula en la familia que sea (GPU o CPU).
func _emit(family: Node3D, xform: Transform3D, velocity: Vector3, color: Color, custom: Color) -> void:
	emitted += 1
	if _gpu:
		(family as GPUParticles3D).emit_particle(xform, velocity, color, custom, _EMIT_ALL)
	else:
		(family as FxCpuFamily).emit(xform, velocity, color, custom)


func _quad(material: ShaderMaterial) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = material
	return quad


func _draw_material(path: String, priority: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path)
	material.render_priority = priority
	return material


func _build_cloud() -> void:
	var look := _draw_material("res://shaders/fx_puff.gdshader", 2)
	look.set_shader_parameter("fx_noise", noise())
	# La última clase es la columna de humo de un incendio: sube mucho más alto que el humo
	# de una explosión, que se frena enseguida.
	#                      FUEGO  HUMO  POLVO CHORRO TERRÓN BRUMA COLUMNA
	var table: Dictionary = {
		"grow": [2.0, 2.6, 3.2, 3.0, 0.5, 1.5, 2.3, 0.0],
		"grow_ease": [3.0, 2.0, 2.5, 2.5, 1.5, 1.5, 1.5, 1.0],
		"spin": [0.5, 0.35, 0.3, 0.5, 0.8, 0.2, 0.3, 0.0],
		"detail": [0.6, 0.55, 0.5, 0.55, 0.9, 0.5, 0.5, 0.5],
		"scroll": [0.6, 0.3, 0.25, 0.4, 0.1, 0.15, 0.25, 0.0],
		"lumps": [0.75, 0.85, 0.95, 0.9, 0.9, 0.8, 0.9, 0.5],
		"erode_from": [0.3, 0.4, 0.2, 0.12, 0.7, 0.5, 0.35, 0.5],
		"thickness": [0.95, 0.9, 0.42, 0.5, 1.0, 0.7, 0.86, 1.0],
		"ground_fade": [0.4, 0.5, 0.6, 0.3, 0.15, 0.5, 0.5, 0.5],
		"softness": [0.32, 0.42, 0.6, 0.6, 0.3, 0.5, 0.46, 0.5],
	}
	for key: String in table:
		look.set_shader_parameter(key, PackedFloat32Array(table[key]))
	_cloud = _family("Cloud", 1024, 9.0, {
		"gravity_y": [3.0, 1.3, 0.12, 0.7, -12.0, 0.05, 1.5],
		"drag": [2.4, 0.9, 2.6, 3.2, 0.5, 1.5, 0.34],
		"wind_pull": [0.25, 0.5, 0.6, 0.9, 0.0, 0.9, 0.3],
		"swirl": [2.2, 1.0, 0.7, 1.4, 0.0, 0.3, 0.9],
		"ground": [0, 0, 4, 4, 1, 0, 0],
	}, _quad(look))


func _build_glow() -> void:
	var look := _draw_material("res://shaders/fx_glow.gdshader", 4)
	look.set_shader_parameter("fx_noise", noise())
	# Clase 0: quietas (destellos, halos). Clase 1: brasas que flotan y revolotean.
	_glow = _family("Glow", 192, 4.0, {
		"gravity_y": [0.0, 0.9],
		"drag": [0.0, 0.9],
		"wind_pull": [0.0, 0.5],
		"swirl": [0.0, 3.2],
	}, _quad(look))


func _build_spark() -> void:
	var look := _draw_material("res://shaders/fx_streak.gdshader", 5)
	# Clase 0: chispas que caen y rebotan. Clase 1: lenguas de fuego que se frenan en seco.
	# Clase 2: trazadoras antiaéreas, que casi no se frenan ni caen.
	_spark = _family("Spark", 384, 2.0, {
		"gravity_y": [-11.0, 0.0, -4.0],
		"drag": [0.7, 11.0, 0.04],
		"ground": [2, 0, 1],
		"bounce": 0.35,
		"stretch": 0.03,
		"stretch_range": Vector2(0.05, 2.4),
	}, _quad(look), FxCpuFamily.Shape.STREAK)


func _build_debris() -> void:
	var look := _draw_material("res://shaders/fx_debris.gdshader", 0)
	var mesh: ArrayMesh = _shard_mesh()
	mesh.surface_set_material(0, look)
	_debris = _family("Debris", 160, 7.0, {
		"gravity_y": [-18.0],
		"drag": [0.2],
		"ground": [2],
		"bounce": 0.3,
		"ground_offset": 0.35,
		"tumble": 10.0,
	}, mesh, FxCpuFamily.Shape.MESH)


## Esquirla: un octaedro irregular de caras planas.
func _shard_mesh() -> ArrayMesh:
	var top := Vector3(0.1, 0.5, 0.05)
	var bottom := Vector3(-0.08, -0.42, 0.0)
	var ring: Array[Vector3] = [Vector3(0.5, 0.05, 0.1), Vector3(0.05, -0.05, 0.42), Vector3(-0.46, 0.1, -0.05), Vector3(0.0, 0.0, -0.36)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		for face: Array in [[top, b, a], [bottom, a, b]]:
			var normal: Vector3 = (face[2] - face[0]).cross(face[1] - face[0]).normalized()
			for vertex: Vector3 in face:
				tool.set_normal(normal)
				tool.add_vertex(vertex)
	return tool.commit()


func _build_marks() -> void:
	var material: ShaderMaterial = _draw_material("res://shaders/fx_mark.gdshader", -5)
	material.set_shader_parameter("fx_noise", noise())
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = material
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	_marks.use_custom_data = true
	_marks.mesh = quad
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	_mark_born.resize(MAX_MARKS)
	_mark_seed.resize(MAX_MARKS)
	var node := MultiMeshInstance3D.new()
	node.name = "Marks"
	node.multimesh = _marks
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = _FIELD
	add_child(node)


func _build_lights() -> void:
	while _lights.size() > _LIGHTS[_level]:
		_lights.pop_back().queue_free()
	while _lights.size() < _LIGHTS[_level]:
		var lamp := OmniLight3D.new()
		lamp.visible = false
		lamp.shadow_enabled = false
		lamp.light_specular = 0.3
		add_child(lamp)
		_lights.append(lamp)
	_light_from.resize(_lights.size())
	_light_time.resize(_lights.size())
	_light_left.resize(_lights.size())


## Cambia el nivel de efectos sobre la marcha (0 bajos, 1 medios, 2 altos).
func set_level(value: int) -> void:
	# Moviendo la CPU las partículas, nunca más que el nivel medio.
	_level = clampi(value, 0, 2 if _gpu else 1)
	_slow_time = 0.0
	if _gpu:
		# Con detalle alto las bocanadas se pintan de lejos a cerca, como debe ser; en los
		# demás niveles se ahorra esa ordenación.
		(_cloud as GPUParticles3D).draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if _level >= 2 else GPUParticles3D.DRAW_ORDER_INDEX
	_build_lights()


# ------------------------------------------------------------------ entorno

## Luz de la partida para las bocanadas: hacia dónde está el sol, su color por su energía, la
## luz ambiente y la densidad de la niebla (todo en lineal).
static func set_lighting(to_sun: Vector3, sun: Color, ambient: Color, fog_density: float) -> void:
	RenderingServer.global_shader_parameter_set(&"fx_sun_dir", to_sun.normalized())
	RenderingServer.global_shader_parameter_set(&"fx_sun_color", Vector3(sun.r, sun.g, sun.b))
	RenderingServer.global_shader_parameter_set(&"fx_ambient", Vector3(ambient.r, ambient.g, ambient.b))
	RenderingServer.global_shader_parameter_set(&"fx_fog_density", fog_density)


func set_wind(value: Vector3) -> void:
	wind = value
	for family: Node3D in [_cloud, _glow]:
		if _gpu:
			((family as GPUParticles3D).process_material as ShaderMaterial).set_shader_parameter("wind", wind)
		else:
			(family as FxCpuFamily).wind = wind


# ------------------------------------------------------------------ piezas

func _n(count: float) -> int:
	return maxi(roundi(count * _COUNT_SCALE[_level]), 1)


## Menos partículas cuanto más lejos de la cámara (1 cerca … 0,3 al fondo del campo).
func _lod(pos: Vector3) -> float:
	return clampf(1.3 - _camera_pos.distance_to(pos) / 180.0, 0.3, 1.0)


## Cuánto detalle merece lo que pasa en `pos` según lo lejos que quede de la cámara y el nivel
## de efectos: 1 al lado, 0 a partir de unos 200 m. Lo usan los efectos continuos (escapes,
## polvo, incendios) para no gastar partículas en lo que apenas se ve.
func nearness(pos: Vector3) -> float:
	return clampf(1.4 - _camera_pos.distance_to(pos) / 150.0, 0.0, 1.0) * _COUNT_SCALE[_level]


## Dirección al azar hacia arriba (`lift` = inclinación mínima) y dirección al azar cualquiera.
static func dome(lift: float = 0.0) -> Vector3:
	return Vector3(randf_range(-1.0, 1.0), randf_range(lift, 1.0), randf_range(-1.0, 1.0)).normalized()


static func ball() -> Vector3:
	var v := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.UP


## Bocanada de humo, polvo o fuego. `data` > 0 es calor (llamarada que se enfría); < 0, el
## resplandor del fuego cercano sobre el humo. `delay` la hace esperar su turno.
func puff(kind: int, pos: Vector3, velocity: Vector3, size: float, life: float, color: Color, data: float = 0.0, delay: float = 0.0) -> void:
	_emit(_cloud, Transform3D(Basis.from_scale(Vector3(size, size, size)), pos), velocity, color, Color(kind + randf() * 0.999, -delay / life, data, life))


## Luz sumada: destello, halo, brasa o estrella de fogonazo. `drift` = 1 la deja flotar.
func glow(kind: int, pos: Vector3, velocity: Vector3, size: float, life: float, color: Color, intensity: float = 1.0, delay: float = 0.0, drift: int = 0) -> void:
	_emit(_glow, Transform3D(Basis.from_scale(Vector3(size, size, size)), pos), velocity, Color(color.r, color.g, color.b, intensity), Color(drift + randf() * 0.999, -delay / life, kind, life))


## Chispa (clase 0: cae y rebota) o lengua de fuego (clase 1). `cooling` 1 = se enfría al rojo.
func spark(pos: Vector3, velocity: Vector3, width: float, life: float, color: Color, cooling: float = 1.0, delay: float = 0.0, kind: int = 0) -> void:
	_emit(_spark, Transform3D(Basis.from_scale(Vector3(width, width, 1.0)), pos), velocity, color, Color(kind + randf() * 0.999, -delay / life, cooling, life))


## Cascote que vuela, rebota y se queda un rato. `heat` 1 = sale al rojo.
func chunk(pos: Vector3, velocity: Vector3, size: float, life: float, color: Color, heat: float = 0.0, delay: float = 0.0) -> void:
	var shape := Basis(ball(), randf() * TAU) * Basis.from_scale(Vector3(size, size * randf_range(0.4, 0.9), size * randf_range(0.6, 1.2)))
	_emit(_debris, Transform3D(shape, pos), velocity, color, Color(randf() * 0.999, -delay / life, heat, life))


## Luz fugaz (fogonazo, explosión). Hay pocas a la vez: gana la más fuerte.
func light(pos: Vector3, color: Color, energy: float, radius: float, time: float) -> void:
	if _lights.is_empty():
		return
	var slot: int = 0
	var weakest: float = INF
	for i in _lights.size():
		var strength: float = _lights[i].light_energy if _light_left[i] > 0.0 else 0.0
		if strength < weakest:
			weakest = strength
			slot = i
	if weakest > energy:
		return
	var lamp: OmniLight3D = _lights[slot]
	lamp.global_position = pos
	lamp.light_color = color
	lamp.omni_range = radius
	lamp.light_energy = energy
	lamp.visible = true
	_light_from[slot] = energy
	_light_time[slot] = time
	_light_left[slot] = time


## Marca en el suelo: quemadura o cráter de `radius` metros.
func mark(pos: Vector3, radius: float, crater: bool) -> void:
	var slot: int = _mark_next
	_mark_next = (_mark_next + 1) % MAX_MARKS
	_mark_count = mini(_mark_count + 1, MAX_MARKS)
	_marks.visible_instance_count = _mark_count
	var turn := Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3(radius * 2.0, 1.0, radius * 2.0))
	# Cada marca un pelo más alta que la anterior: las que se pisan no parpadean.
	_marks.set_instance_transform(slot, Transform3D(turn, Vector3(pos.x, 0.03 + slot * 0.0006, pos.z)))
	_marks.set_instance_color(slot, soil)
	_mark_seed[slot] = randf() + (1.0 if crater else 0.0)
	_mark_born[slot] = _clock
	_marks.set_instance_custom_data(slot, Color(fposmod(_mark_seed[slot], 1.0), 1.0 if crater else 0.0, 0.0, 1.0))


## Destello que se refleja en las nubes (ver CloudDome.flash).
func sky_flash(point: Vector3, color: Color, energy: float, reach: float, time: float) -> void:
	if is_instance_valid(sky):
		sky.flash(point, color, energy, reach, time)


## Sacudida de la cámara del jugador según lo cerca que le pille.
func shake(pos: Vector3, power: float) -> void:
	if not is_instance_valid(player) or player.is_destroyed:
		return
	var distance: float = player.global_position.distance_to(pos)
	var amount: float = power / (1.0 + pow(distance / 14.0, 2.0))
	if amount > 0.02:
		player.add_shake(amount)


func _process(delta: float) -> void:
	_clock += delta
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		_camera_pos = camera.global_position
	if not _gpu:
		for family: FxCpuFamily in [_cloud, _glow, _spark, _debris]:
			family.step(delta, _camera_pos)
	for i in _lights.size():
		if _light_left[i] <= 0.0:
			continue
		_light_left[i] -= delta
		var t: float = maxf(_light_left[i] / _light_time[i], 0.0)
		_lights[i].light_energy = _light_from[i] * t * t
		if _light_left[i] <= 0.0:
			_lights[i].visible = false
	_mark_tick -= delta
	if _mark_tick <= 0.0:
		_mark_tick = 0.5
		for i in _mark_count:
			var age: float = _clock - _mark_born[i]
			if age > MARK_TIME - 12.0:
				var fade: float = clampf((MARK_TIME - age) / 12.0, 0.0, 1.0)
				_marks.set_instance_custom_data(i, Color(fposmod(_mark_seed[i], 1.0), 1.0 if _mark_seed[i] >= 1.0 else 0.0, 0.0, fade))
	_govern(delta)


## Si el teléfono no llega a 24 imágenes por segundo durante un rato, baja un nivel los efectos
## (solo en esta partida; el ajuste guardado no cambia).
func _govern(delta: float) -> void:
	if not governor or _level <= 0 or Engine.time_scale < 0.99:
		return
	if Engine.get_frames_per_second() < 24.0 and _clock > 6.0:
		_slow_time += delta
	else:
		_slow_time = maxf(_slow_time - delta * 0.5, 0.0)
	if _slow_time > 4.0:
		set_level(_level - 1)


## Nivel de efectos en uso (puede ser menor que el elegido si el regulador lo ha bajado).
func level() -> int:
	return _level


## Falso en los teléfonos sin Vulkan, donde las partículas las mueve la CPU (ver FxCpuFamily).
func on_gpu() -> bool:
	return _gpu


# ------------------------------------------------------------------ efectos

## Explosión de alto explosivo. `s` 1 ≈ granada de cañón; 1,5-2,5 bomba, cohete o un tanque que
## estalla. En el suelo levanta tierra y polvo y deja marca; en el aire, no.
func explosion(pos: Vector3, s: float) -> void:
	var lod: float = _lod(pos)
	var grounded: bool = pos.y < 1.5 + s
	var root: float = sqrt(s)
	var slow: float = clampf(root, 0.75, 1.7)
	var up := Vector3.UP
	var c: Vector3 = Vector3(pos.x, maxf(pos.y, 0.35 * s), pos.z) if grounded else pos
	glow(Glow.FLASH, c + up * 0.3 * s, Vector3.ZERO, 9.0 * s, 0.14, FLASH, 1.0)
	glow(Glow.HALO, c + up * 0.5 * s, Vector3.ZERO, 7.0 * s, 0.5 * slow, FIRE_GLOW, 0.6)
	light(c + up * (0.8 + s), Color(1.0, 0.62, 0.3), 4.0 + 2.5 * s, 10.0 + 12.0 * s, 0.4 + 0.15 * s)
	if s >= 1.0:
		sky_flash(c, Color(1.0, 0.55, 0.25), 0.4 * s, 90.0 + 40.0 * s, 0.5 + 0.2 * s)
	# Bola de fuego: llamaradas que salen del centro, suben y se enfrían hasta ser hollín.
	for i in _n((7.0 + 2.5 * s) * lod):
		var dir: Vector3 = dome(0.1) if grounded else ball()
		puff(Puff.FIRE, c + dir * 0.45 * s, dir * randf_range(2.5, 7.0) * s + up * 1.2 * s, randf_range(1.0, 1.6) * s, randf_range(0.8, 1.3) * slow, SOOT, randf_range(1.05, 1.5), randf() * 0.05)
	# Humo negro: lo primero sale con la bola de fuego y sube deprisa; el resto sigue manando
	# del suelo unos segundos, así queda una columna y no una nube suelta.
	var plumes: int = _n((7.0 + 3.0 * s) * lod)
	for i in plumes:
		var late: float = float(i) / plumes
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.8 * s
		puff(Puff.SMOKE, c + side * (1.0 - late * 0.5) + up * randf_range(0.3, 2.2) * s * (1.0 - late), side * 0.4 + up * randf_range(1.6, 3.6) * root * (1.0 - late * 0.45), randf_range(1.3, 2.2) * s * (1.0 - late * 0.3), randf_range(3.5, 6.0) * slow, SOOT.lerp(DARK_SMOKE, randf()), -randf_range(0.5, 1.0) * (1.0 - late), 0.1 + late * 2.2 * slow)
	if grounded:
		var g := Vector3(pos.x, 0.0, pos.z)
		# Corona de polvo que barre el suelo.
		var ring: int = _n(10.0 * lod * dustiness)
		for i in ring:
			var angle: float = TAU * (i + randf()) / ring
			var out := Vector3(cos(angle), 0.0, sin(angle))
			puff(Puff.DUST, g + out * 0.7 * s + up * 0.35 * s, out * randf_range(6.0, 11.0) * s + up * randf_range(0.2, 1.0), randf_range(0.9, 1.5) * s, randf_range(1.8, 3.2), dust, 0.0, 0.02)
		# Surtidor de tierra: una rociada de terrones pequeños que sube en abanico y cae.
		for i in _n(26.0 * lod):
			var dir := Vector3(randf_range(-0.55, 0.55), 1.0, randf_range(-0.55, 0.55)).normalized()
			puff(Puff.CLOD, g + dir * 0.4 * s, dir * randf_range(5.0, 21.0) * root, randf_range(0.07, 0.3) * s, randf_range(1.0, 2.0), soil, 0.0, randf() * 0.04)
		for i in _n(10.0 * lod):
			chunk(g + up * 0.3, dome(0.45) * randf_range(6.0, 16.0) * root, randf_range(0.08, 0.22) * root, randf_range(2.0, 4.0), soil * 1.6)
		mark(g, 3.2 * s, s >= 1.2)
	for i in _n(20.0 * lod):
		spark(c, dome(0.05) * randf_range(9.0, 30.0) * root, randf_range(0.09, 0.16) * root, randf_range(0.6, 1.4), SPARK)
	for i in _n(7.0 * lod):
		glow(Glow.EMBER, c + ball() * s, dome(0.3) * randf_range(1.5, 5.0) * root, randf_range(0.12, 0.22) * root, randf_range(1.2, 2.8), EMBER, 1.0, randf() * 0.2, 1)
	for i in _n(7.0 * lod):
		chunk(c, dome(0.35) * randf_range(5.0, 13.0) * root, randf_range(0.12, 0.34) * root, randf_range(2.5, 5.0), CHARRED, 0.6)
	shake(pos, 0.9 * s)


## Trazadora antiaérea: un trazo de luz que sube hasta apagarse (unos 400 m).
func tracer(pos: Vector3, velocity: Vector3, color: Color) -> void:
	# Con el alfa por encima de 1 brilla más que una chispa: tiene que verse contra el cielo.
	spark(pos, velocity, 1.8, randf_range(1.5, 1.9), Color(color.r, color.g, color.b, 2.4), 0.0, 0.0, 2)
	glow(Glow.STAR, pos, Vector3.ZERO, 3.0, 0.07, FLASH, 0.6)


## Estallido en el aire (antiaérea, avión tocado): fogonazo, metralla en todas direcciones y
## una nube negra que se queda flotando.
func airburst(pos: Vector3, s: float) -> void:
	var lod: float = _lod(pos)
	glow(Glow.FLASH, pos, Vector3.ZERO, 8.0 * s, 0.12, FLASH, 1.0)
	light(pos, Color(1.0, 0.8, 0.5), 3.0 + s, 18.0 * s, 0.2)
	sky_flash(pos, Color(1.0, 0.78, 0.5), 0.45 * sqrt(s), 70.0 + 30.0 * minf(s, 3.0), 0.35)
	for i in _n(4.0 * lod + s):
		var dir: Vector3 = ball()
		puff(Puff.FIRE, pos + dir * 0.3 * s, dir * randf_range(2.0, 5.0) * s, randf_range(0.8, 1.2) * s, randf_range(0.35, 0.6), SOOT, randf_range(0.9, 1.3))
	for i in _n(5.0 * lod + s):
		var dir: Vector3 = ball()
		puff(Puff.HAZE, pos + dir * 0.6 * s, dir * randf_range(1.0, 4.0) * s, randf_range(1.6, 2.4) * s, randf_range(5.0, 8.0), SOOT.lerp(DARK_SMOKE, randf()), -0.6, 0.05)
	for i in _n(14.0 * lod):
		spark(pos, ball() * randf_range(18.0, 40.0), 0.09 * sqrt(s), randf_range(0.3, 0.7), SPARK)


## Estallido pequeño en el aire o contra algo: fogonazo, una llamarada breve, humo y chispas.
func pop(pos: Vector3, s: float = 1.0) -> void:
	var lod: float = _lod(pos)
	glow(Glow.FLASH, pos, Vector3.ZERO, 4.0 * s, 0.1, FLASH, 0.9)
	light(pos, Color(1.0, 0.66, 0.34), 3.0, 8.0 * s, 0.16)
	for i in _n(3.0 * lod):
		puff(Puff.FIRE, pos + ball() * 0.2 * s, ball() * randf_range(1.5, 4.0) * s, 0.7 * s, randf_range(0.35, 0.55), SOOT, randf_range(0.9, 1.2))
	for i in _n(3.0 * lod):
		puff(Puff.SMOKE, pos, ball() + Vector3.UP * randf_range(0.5, 1.5), randf_range(0.4, 0.65) * s, randf_range(1.8, 2.8), DARK_SMOKE.lerp(GREY_SMOKE, randf() * 0.4), -0.4, 0.05 + randf() * 0.2)
	for i in _n(8.0 * lod):
		spark(pos, ball() * randf_range(8.0, 22.0), 0.07, randf_range(0.3, 0.8), SPARK)


## Granada que cae en tierra: fogonazo corto, surtidor de tierra, polvo, humo y una quemadura.
func shell_ground(pos: Vector3, s: float = 1.0) -> void:
	var lod: float = _lod(pos)
	var up := Vector3.UP
	var g := Vector3(pos.x, 0.0, pos.z)
	glow(Glow.FLASH, g + up * 0.4, Vector3.ZERO, 4.5 * s, 0.1, FLASH, 0.9)
	light(g + up, Color(1.0, 0.66, 0.34), 3.0, 9.0 * s, 0.18)
	for i in _n(3.0 * lod):
		puff(Puff.FIRE, g + up * 0.5, dome(0.3) * randf_range(1.5, 4.0) * s, 0.7 * s, randf_range(0.35, 0.55), SOOT, randf_range(0.9, 1.2))
	for i in _n(16.0 * lod):
		var dir := Vector3(randf_range(-0.5, 0.5), 1.0, randf_range(-0.5, 0.5)).normalized()
		puff(Puff.CLOD, g + dir * 0.2, dir * randf_range(4.0, 14.0), randf_range(0.06, 0.22) * s, randf_range(0.8, 1.6), soil, 0.0, randf() * 0.03)
	for i in _n(8.0 * lod):
		chunk(g + up * 0.2, dome(0.45) * randf_range(4.0, 11.0), randf_range(0.05, 0.14), randf_range(1.5, 3.0), soil * 1.6)
	var ring: int = _n(6.0 * lod * dustiness)
	for i in ring:
		var angle: float = TAU * (i + randf()) / ring
		var out := Vector3(cos(angle), 0.0, sin(angle))
		puff(Puff.DUST, g + out * 0.4 + up * 0.3, out * randf_range(2.5, 5.5) * s + up * randf_range(0.2, 1.2), randf_range(0.7, 1.1) * s, randf_range(1.6, 2.8), dust, 0.0, 0.02)
	for i in _n(3.0 * lod):
		puff(Puff.SMOKE, g + up * 0.8, up * randf_range(1.0, 2.2) + ball() * 0.5, randf_range(0.45, 0.7) * s, randf_range(2.0, 3.2), DARK_SMOKE.lerp(GREY_SMOKE, randf() * 0.4), -0.4, 0.05 + randf() * 0.25)
	for i in _n(6.0 * lod):
		spark(g + up * 0.3, dome(0.3) * randf_range(8.0, 20.0), 0.07, randf_range(0.3, 0.8), SPARK)
	mark(g, 1.5 * s, false)
	shake(pos, 0.25 * s)


## Proyectil contra blindaje: fogonazo blanco, lluvia de chispas que rebotan, esquirlas al rojo
## y una voluta de humo gris.
func shell_armor(pos: Vector3, normal: Vector3, s: float = 1.0) -> void:
	var lod: float = _lod(pos)
	glow(Glow.FLASH, pos + normal * 0.2, Vector3.ZERO, 3.6 * s, 0.1, WHITE_HOT, 1.0)
	glow(Glow.HALO, pos + normal * 0.2, Vector3.ZERO, 2.2 * s, 0.25, FIRE_GLOW, 0.7)
	light(pos + normal * 0.6, Color(1.0, 0.8, 0.52), 3.5, 8.0, 0.14)
	for i in _n(24.0 * lod):
		var dir: Vector3 = (normal * randf_range(0.15, 1.1) + ball() * 0.85).normalized()
		spark(pos + normal * 0.05, dir * randf_range(8.0, 34.0), randf_range(0.06, 0.11), randf_range(0.35, 1.1), WHITE_HOT if i % 3 == 0 else SPARK)
	for i in _n(3.0 * lod):
		puff(Puff.JET, pos + normal * 0.3, normal * randf_range(1.5, 4.0) + ball() * 0.8, randf_range(0.28, 0.42), randf_range(0.8, 1.4), Color(DARK_SMOKE.lerp(GREY_SMOKE, randf()), 0.8), -0.5, i * 0.03)
	for i in _n(3.0 * lod):
		chunk(pos + normal * 0.1, (normal + ball() * 0.7).normalized() * randf_range(4.0, 10.0), randf_range(0.05, 0.11), randf_range(1.5, 3.0), CHARRED, 1.0)


## Proyectil contra piedra, ladrillo, madera o chapa: nube de polvo del material y esquirlas.
## `color` es el color del material (sRGB, tal como lo define cada objeto).
func shell_solid(pos: Vector3, normal: Vector3, color: Color, s: float = 1.0) -> void:
	var lod: float = _lod(pos)
	var matter: Color = color.srgb_to_linear()
	var cloud: Color = matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	glow(Glow.FLASH, pos + normal * 0.2, Vector3.ZERO, 2.6 * s, 0.08, FLASH, 0.8)
	for i in _n(6.0 * lod):
		puff(Puff.DUST, pos + normal * 0.25, normal * randf_range(1.0, 4.0) + ball() * 1.5, randf_range(0.6, 0.9) * s, randf_range(1.4, 2.4), cloud, 0.0, i * 0.01)
	for i in _n(6.0 * lod):
		chunk(pos + normal * 0.15, (normal + ball() * 0.8).normalized() * randf_range(3.0, 9.0), randf_range(0.07, 0.18) * s, randf_range(2.0, 4.0), matter * 0.6)
	for i in _n(5.0 * lod):
		spark(pos + normal * 0.05, (normal + ball() * 0.9).normalized() * randf_range(6.0, 18.0), 0.06, randf_range(0.25, 0.6), SPARK)


## Disparo del cañón: fogonazo (estrella de frente, lengua de fuego hacia delante y, con freno
## de boca, dos chorros a los lados), humo de pólvora que sale y se frena, granos de pólvora
## encendidos y el polvo que la onda levanta del suelo bajo la boca.
## `at` es la transformación de la boca (−Z hacia delante), `k` la escala del cañón y `carry`
## la velocidad del tanque.
func muzzle(at: Transform3D, k: float, carry: Vector3, brake: bool) -> void:
	var p: Vector3 = at.origin
	var f: Vector3 = -at.basis.z.normalized()
	var r: Vector3 = at.basis.x.normalized()
	var lod: float = _lod(p)
	glow(Glow.STAR, p + f * 0.5 * k, Vector3.ZERO, 3.2 * k, 0.08, FLASH, 1.0)
	glow(Glow.HALO, p + f * 1.0 * k, Vector3.ZERO, 4.2 * k, 0.12, FIRE_GLOW, 0.35)
	light(p + f * 1.2, Color(1.0, 0.78, 0.46), 5.0, 12.0 * k, 0.1)
	var jets: Array[Vector3] = [f]
	if brake:
		jets.append((r + f * 0.35).normalized())
		jets.append((-r + f * 0.35).normalized())
	for j in jets.size():
		var jet: Vector3 = jets[j]
		var reach: float = 1.0 if j == 0 else 0.6
		for i in _n(5.0 * reach):
			spark(p, (jet + ball() * 0.13).normalized() * randf_range(40.0, 80.0) * k * reach + carry, randf_range(0.4, 0.7) * k * reach, randf_range(0.06, 0.1), FLASH, 0.0, 0.0, 1)
		var count: int = _n(11.0 * reach * lod)
		for i in count:
			var along: float = float(i) / count
			puff(Puff.JET, p + jet * randf_range(0.2, 1.0) * k, jet * lerpf(4.0, 30.0, along * along) * k * reach + ball() * 1.3 + carry, randf_range(0.28, 0.5) * k, randf_range(0.7, 1.5), Color(GUN_SMOKE, randf_range(0.5, 0.75)), -0.7, i * 0.006)
	for i in _n(6.0 * lod):
		spark(p, (f + ball() * 0.22).normalized() * randf_range(18.0, 42.0) + carry, 0.05, randf_range(0.2, 0.5), SPARK)
	if p.y < 3.6 and dustiness > 0.05:
		var g := Vector3(p.x + f.x * 1.6 * k, 0.0, p.z + f.z * 1.6 * k)
		var ring: int = _n(8.0 * lod * dustiness)
		for i in ring:
			var angle: float = TAU * (i + randf()) / ring
			var out: Vector3 = (Vector3(cos(angle), 0.0, sin(angle)) + f * 0.6).normalized()
			puff(Puff.DUST, g + out * 0.6 * k + Vector3.UP * 0.25, out * randf_range(3.0, 7.0) * k + Vector3.UP * randf_range(0.3, 1.0), randf_range(0.6, 1.0) * k, randf_range(1.4, 2.4), Color(dust, 0.8), 0.0, 0.03 + randf() * 0.04)


## Tanque que estalla: la explosión, el chorro de fuego de la munición que sale hacia arriba y
## planchas al rojo que salen despedidas.
func tank_blast(pos: Vector3, s: float) -> void:
	explosion(pos, s)
	var lod: float = _lod(pos)
	var root: float = sqrt(s)
	for i in _n(6.0 * lod):
		puff(Puff.FIRE, pos + Vector3.UP * (0.5 + i * 0.3), Vector3.UP * randf_range(6.0, 12.0) * root + ball() * 1.5, randf_range(0.8, 1.2) * s, randf_range(0.6, 1.0), SOOT, randf_range(1.3, 1.6), i * 0.03)
	for i in _n(8.0 * lod):
		chunk(pos + Vector3.UP * 0.5, dome(0.4) * randf_range(6.0, 15.0) * root, randf_range(0.15, 0.45), randf_range(3.0, 6.0), CHARRED, 1.0)
	for i in _n(14.0 * lod):
		spark(pos + Vector3.UP * 0.5, dome(0.2) * randf_range(12.0, 32.0), randf_range(0.08, 0.14), randf_range(0.6, 1.5), SPARK)


## Depósito o bidón de combustible que revienta: la explosión y una bola de fuego anaranjada
## que sube rodando.
func fuel_blast(pos: Vector3, s: float) -> void:
	explosion(pos, s)
	var lod: float = _lod(pos)
	for i in _n(8.0 * lod):
		puff(Puff.FIRE, pos + dome(0.2) * s, dome(0.5) * randf_range(2.0, 5.0) * s + Vector3.UP * randf_range(3.0, 6.0), randf_range(1.2, 1.8) * s, randf_range(1.2, 1.9), SOOT, randf_range(1.2, 1.5), randf() * 0.45)


## Munición que estalla dentro de unos restos: chorro de chispas hacia arriba y un fogonazo.
func cook_off(pos: Vector3, k: float) -> void:
	var lod: float = _lod(pos)
	glow(Glow.FLASH, pos + Vector3.UP * 0.5, Vector3.ZERO, 3.0 * k, 0.1, FLASH, 0.9)
	for i in _n(12.0 * lod):
		spark(pos, (Vector3.UP + ball() * 0.45).normalized() * randf_range(10.0, 28.0), randf_range(0.06, 0.1), randf_range(0.4, 1.1), SPARK)
	for i in _n(2.0 * lod):
		puff(Puff.FIRE, pos, Vector3.UP * randf_range(4.0, 8.0) + ball(), 0.8 * k, randf_range(0.4, 0.7), SOOT, 1.4)


## Golpe sin explosión contra piedra, madera o chapa (o algo que se aplasta): polvo y astillas.
func chips(pos: Vector3, normal: Vector3, color: Color, s: float = 1.0) -> void:
	var lod: float = _lod(pos)
	var matter: Color = color.srgb_to_linear()
	var cloud: Color = matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	for i in _n(5.0 * lod):
		puff(Puff.DUST, pos + normal * 0.25, normal * randf_range(1.0, 3.5) + ball() * 1.4, randf_range(0.55, 0.9) * s, randf_range(1.4, 2.4), cloud, 0.0, i * 0.01)
	for i in _n(6.0 * lod):
		chunk(pos + normal * 0.15, (normal + ball() * 0.8).normalized() * randf_range(3.0, 9.0), randf_range(0.07, 0.18) * s, randf_range(2.0, 4.0), matter * 0.6)


## Derrumbe o destrozo sin fuego: nube de polvo del color del material y cascotes.
func rubble(pos: Vector3, size: float, color: Color) -> void:
	var lod: float = _lod(pos)
	var matter: Color = color.srgb_to_linear()
	var cloud: Color = matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	var root: float = sqrt(maxf(size, 0.2))
	for i in _n((4.0 + 4.0 * size) * lod):
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		puff(Puff.DUST, pos + side * 0.6 * size + Vector3.UP * randf_range(-0.6, 0.6) * size, side * randf_range(1.0, 4.0) * root + Vector3.UP * randf_range(0.4, 2.0), randf_range(0.9, 1.5) * root, randf_range(2.0, 4.0), cloud, 0.0, randf() * 0.15)
	for i in _n((4.0 + 3.0 * size) * lod):
		chunk(pos + ball() * 0.4 * size, dome(0.3) * randf_range(2.0, 7.0) * root, randf_range(0.1, 0.28) * root, randf_range(3.0, 5.0), matter * 0.6)
	shake(pos, 0.15 * size)


# ------------------------------------------------------------------ efectos continuos
# Quien los usa los llama a su ritmo (tantas bocanadas por segundo como quiera).

## Bocanada del tubo de escape. `load` 0 = al ralentí, 1 = acelerando a fondo (humo más negro).
func exhaust(pos: Vector3, velocity: Vector3, k: float, load: float) -> void:
	puff(Puff.JET, pos, velocity, randf_range(0.22, 0.34) * k, randf_range(0.8, 1.4), Color(GREY_SMOKE.lerp(SOOT, load), lerpf(0.5, 0.9, load)))


## Polvo (o barro, o nieve) que levantan las orugas.
func track_dust(pos: Vector3, velocity: Vector3, k: float, amount: float) -> void:
	puff(Puff.DUST, pos, velocity, randf_range(0.5, 0.85) * k, randf_range(1.2, 2.4), Color(dust, clampf(amount, 0.0, 1.0)))


## Humo de un vehículo tocado. `level` 0..1: de gris y ralo a negro y espeso.
func damage_smoke(pos: Vector3, velocity: Vector3, k: float, level: float) -> void:
	puff(Puff.SMOKE, pos, velocity + Vector3.UP * randf_range(1.2, 2.4), randf_range(0.45, 0.7) * k, randf_range(1.8, 3.2), Color(GREY_SMOKE.lerp(SOOT, level), lerpf(0.5, 0.95, level)))


## Llama de un incendio (restos de un tanque, avión tocado).
func flame(pos: Vector3, velocity: Vector3, size: float, heat: float = 0.85) -> void:
	puff(Puff.FIRE, pos, velocity + Vector3.UP * randf_range(1.6, 3.6), size * randf_range(0.5, 0.9), randf_range(0.45, 0.85), SOOT, heat * randf_range(0.8, 1.15))


## Humo negro de un incendio; `size` en metros, `life` en segundos.
func black_smoke(pos: Vector3, velocity: Vector3, size: float, life: float) -> void:
	puff(Puff.SMOKE, pos, velocity, size, life, SOOT.lerp(DARK_SMOKE, randf()), -0.9)


## Pavesa que sube revoloteando de un incendio.
func ember(pos: Vector3, velocity: Vector3) -> void:
	glow(Glow.EMBER, pos, velocity, randf_range(0.1, 0.2), randf_range(1.2, 2.6), EMBER, 1.0, 0.0, 1)
