class_name Weather
extends Node3D
## Clima de la partida: atardecer despejado, niebla, tormenta (lluvia y rayos) o nieve.
## Ajusta cielo, sol, niebla y lo que cae: lluvia con sus salpicaduras, nieve o arena, que se
## pintan solo alrededor de la cámara (más lejos las tapa la niebla).

enum Kind { CLEAR, FOG, RAIN, SNOW }

const NAMES: Array[String] = ["DESPEJADO", "NIEBLA", "LLUVIA", "NIEVE"]
## Parte de las gotas o copos que se pintan con efectos bajos, medios y altos.
const AMOUNT_SCALE: Array[float] = [0.4, 0.7, 1.0]

var kind: Kind = Kind.CLEAR
var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D
var follow: Node3D
var ground_material: ShaderMaterial
var sky: SkyDome
var clouds: CloudDome

var _particles: GPUParticles3D
var _splashes: GPUParticles3D
## Desde dónde se sueltan respecto a la cámara, para que la crucen a media caída.
var _emit_offset: Vector3
var _amount_timer: float = 0.0
var _rain_loop: AudioStreamPlayer
var _lightning_timer: float = 10.0
var _flash: float = 0.0
var _sun_energy: float = 1.0
var _front: int = 0
## Luz ambiente que reciben el humo y el polvo (lineal), para devolverla tras un relámpago.
var _fx_sun: Color
var _fx_ambient: Color
var _fx_fog: float = 0.0


func setup(env: Environment, sky_mat: ProceduralSkyMaterial, sun_light: DirectionalLight3D, target: Node3D, ground: ShaderMaterial, forced: int = -1, front: int = 0) -> void:
	environment = env
	_front = front
	sky_material = sky_mat
	sun = sun_light
	follow = target
	ground_material = ground
	kind = (randi() % 4) as Kind if forced < 0 else forced as Kind
	ground_material.set_shader_parameter("tint", 0.0)
	ground_material.set_shader_parameter("wet", 0.0)
	clouds = CloudDome.new()
	clouds.name = "CloudDome"
	add_child(clouds)
	sky = SkyDome.new()
	sky.follow = target
	add_child(sky)
	sky.visible = kind == Kind.CLEAR
	match kind:
		Kind.CLEAR:
			# Atardecer: cielo azul profundo, horizonte cálido, sol bajo.
			_apply(Color(0.05, 0.08, 0.2), Color(0.85, 0.45, 0.25), Color(1.0, 0.75, 0.5), 1.3, 0.004, Color(0.55, 0.4, 0.35))
		Kind.FOG:
			if front == Fronts.Id.AFRICA:
				# Tormenta de arena: niebla ocre y arena volando en horizontal.
				_apply(Color(0.55, 0.42, 0.25), Color(0.75, 0.58, 0.35), Color(1.0, 0.8, 0.55), 0.6, 0.02, Color(0.7, 0.55, 0.35))
				var gale: Vector3 = Fx.on(self).wind.normalized() * 24.0 + Vector3.DOWN * 1.5
				_make_drops(1000, Vector2(0.03, 0.8), Color(1.0, 0.9, 0.68), 0.5, gale, 1.3, Vector3(20.0, 3.0, 20.0), false)
			else:
				_apply(Color(0.35, 0.38, 0.4), Color(0.55, 0.58, 0.58), Color(0.85, 0.88, 0.9), 0.5, 0.025, Color(0.55, 0.58, 0.58))
		Kind.RAIN:
			_apply(Color(0.08, 0.09, 0.11), Color(0.22, 0.25, 0.28), Color(0.6, 0.7, 0.8), 0.35, 0.012, Color(0.2, 0.23, 0.26))
			_make_drops(2400, Vector2(0.018, 0.8), Color(0.75, 0.82, 0.95), 0.42, Fx.on(self).wind * 1.6 + Vector3.DOWN * 26.0, 0.7, Vector3(15.0, 0.5, 15.0), false)
			_make_splashes(240)
			ground_material.set_shader_parameter("wet", 1.0)
			_rain_loop = AudioStreamPlayer.new()
			_rain_loop.stream = load("res://assets/audio/rain.wav")
			_rain_loop.volume_db = -12.0
			_rain_loop.bus = AudioSetup.SFX
			add_child(_rain_loop)
			_rain_loop.play()
		Kind.SNOW:
			_apply(Color(0.45, 0.5, 0.58), Color(0.75, 0.78, 0.82), Color(0.9, 0.93, 1.0), 0.7, 0.014, Color(0.72, 0.75, 0.8))
			ground_material.set_shader_parameter("tint", 0.8)
			# Contra el cielo y la nieve, los copos se ven grises; contra lo oscuro, blancos.
			_make_drops(1800, Vector2(0.1, 0.1), Color(0.6, 0.62, 0.66), 0.9, Fx.on(self).wind + Vector3.DOWN * 1.9, 5.0, Vector3(14.0, 4.5, 14.0), true)


## Dice a los efectos cómo es la luz de esta partida (para que el humo y el polvo se iluminen
## como el resto de la escena), de qué color es el polvo del frente, cuánto se levanta con
## este tiempo y hacia dónde sopla el viento.
func _setup_effects(top: Color, horizon: Color, light: Color, energy: float, fog: float) -> void:
	_fx_sun = light.srgb_to_linear() * energy
	_fx_ambient = top.lerp(horizon, 0.55).srgb_to_linear() * 0.6 + Color(0.015, 0.015, 0.015)
	_fx_fog = fog
	Fx.set_lighting(sun.global_basis.z, _fx_sun, _fx_ambient, fog)
	var fx: Fx = Fx.on(self)
	var dirt: Color = Fronts.ground_colors(_front)[2]
	var desert: bool = _front == Fronts.Id.AFRICA
	fx.soil = dirt.darkened(0.3).srgb_to_linear()
	fx.dust = dirt.lerp(Color(0.56, 0.53, 0.48), 0.4).srgb_to_linear()
	fx.dustiness = 1.4 if desert else 1.0
	var gust: float = 2.0
	match kind:
		Kind.FOG:
			fx.dustiness = 1.6 if desert else 0.8
			gust = 6.0 if desert else 0.8
		Kind.RAIN:
			# Suelo mojado: apenas hay polvo, y el poco que salta es barro oscuro.
			fx.dust = dirt.darkened(0.35).srgb_to_linear()
			fx.dustiness = 0.15
			gust = 3.5
		Kind.SNOW:
			fx.dust = Color(0.78, 0.81, 0.86).srgb_to_linear()
			fx.dustiness = 0.7
			gust = 1.5
	var heading: float = randf() * TAU
	fx.set_wind(Vector3(cos(heading), 0.0, sin(heading)) * gust * randf_range(0.7, 1.2))
	# Nubes: encendidas por el sol poniente si está despejado; un techo plomizo con mal tiempo.
	var haze: Color = horizon.srgb_to_linear()
	match kind:
		Kind.CLEAR:
			clouds.setup(Color(0.85, 0.34, 0.17), Color(0.1, 0.055, 0.1), haze, 0.42, 0.8, fx.wind)
		Kind.FOG:
			clouds.setup(haze * 1.1, haze * 0.7, haze, 0.8, 0.45, fx.wind)
		Kind.RAIN:
			clouds.setup(Color(0.1, 0.115, 0.14), Color(0.022, 0.026, 0.034), haze, 0.97, 0.96, fx.wind)
		Kind.SNOW:
			clouds.setup(Color(0.62, 0.66, 0.72), Color(0.3, 0.33, 0.38), haze, 0.92, 0.85, fx.wind)
	fx.sky = clouds


func display_name() -> String:
	if kind == Kind.FOG and _front == Fronts.Id.AFRICA:
		return Loc.t("TORMENTA DE ARENA")
	return Loc.t(NAMES[kind])


func _apply(top: Color, horizon: Color, light: Color, energy: float, fog: float, fog_color: Color) -> void:
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon.darkened(0.3)
	sky_material.ground_bottom_color = top.darkened(0.5)
	sky_material.sun_angle_max = 20.0
	sun.light_color = light
	sun.light_energy = energy
	_sun_energy = energy
	environment.fog_density = fog
	environment.fog_light_color = fog_color
	_setup_effects(top, horizon, light, energy, fog)


## Lo que cae cerca de la cámara: `amount` gotas, granos o copos de `size` metros (ancho y
## largo del trazo) que se mueven a `velocity` durante `lifetime` segundos y se sueltan dentro
## de una caja de medio lado `extents`. Con `flake` son copos redondos que revolotean.
func _make_drops(amount: int, size: Vector2, tint: Color, opacity: float, velocity: Vector3, lifetime: float, extents: Vector3, flake: bool) -> void:
	_particles = GPUParticles3D.new()
	_particles.amount = amount
	_particles.lifetime = lifetime
	_particles.preprocess = lifetime
	_particles.local_coords = false
	_particles.visibility_aabb = AABB(Vector3(-70.0, -50.0, -70.0), Vector3(140.0, 100.0, 140.0))
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = velocity.normalized()
	process.spread = 10.0 if flake else 0.0
	process.initial_velocity_min = velocity.length() * 0.85
	process.initial_velocity_max = velocity.length() * 1.15
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.35
	_particles.process_material = process
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/weather_drop.gdshader")
	var linear: Color = tint.srgb_to_linear()
	material.set_shader_parameter("tint", Vector3(linear.r, linear.g, linear.b))
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("size", size)
	material.set_shader_parameter("fall_dir", velocity.normalized())
	material.set_shader_parameter("flake", flake)
	# Por delante del humo lejano y por detrás de los fogonazos.
	material.render_priority = 3
	var quad := QuadMesh.new()
	quad.material = material
	_particles.draw_pass_1 = quad
	_emit_offset = -velocity * lifetime * 0.5
	add_child(_particles)


## Salpicaduras de la lluvia en el suelo, alrededor de la cámara.
func _make_splashes(amount: int) -> void:
	_splashes = GPUParticles3D.new()
	_splashes.amount = amount
	_splashes.lifetime = 0.3
	_splashes.preprocess = 0.3
	_splashes.local_coords = false
	_splashes.visibility_aabb = AABB(Vector3(-40.0, -2.0, -40.0), Vector3(80.0, 4.0, 80.0))
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(13.0, 0.0, 13.0)
	process.gravity = Vector3.ZERO
	process.scale_min = 0.7
	process.scale_max = 1.3
	_splashes.process_material = process
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/weather_splash.gdshader")
	material.render_priority = 1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = material
	_splashes.draw_pass_1 = quad
	add_child(_splashes)


func _process(delta: float) -> void:
	if _particles != null:
		_follow_camera(delta)
	if kind != Kind.RAIN:
		return
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = randf_range(8.0, 20.0)
		strike()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 4.0, 0.0)
		var strength: float = _flash * (0.6 + 0.4 * sin(_flash * 40.0))
		sun.light_energy = _sun_energy + strength * 3.0
		environment.ambient_light_energy = 0.6 + strength * 2.0
		# El relámpago alumbra también el humo, el polvo y la propia lluvia.
		Fx.set_lighting(sun.global_basis.z, _fx_sun, _fx_ambient + Color(0.5, 0.55, 0.65) * strength, _fx_fog)


## La lluvia, la nieve y la arena solo existen alrededor de la cámara, algo adelantadas hacia
## donde mira, que es donde se ven.
func _follow_camera(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var center: Vector3 = Vector3.ZERO
	if camera != null:
		var ahead: Vector3 = -camera.global_basis.z
		ahead.y = 0.0
		center = camera.global_position + ahead.normalized() * 6.0 if ahead.length_squared() > 0.01 else camera.global_position
	elif follow != null and is_instance_valid(follow):
		center = follow.global_position + Vector3.UP * 3.0
	_particles.global_position = center + _emit_offset
	if _splashes != null:
		_splashes.global_position = Vector3(center.x, 0.04, center.z)
	# Menos gotas con los efectos bajos (o si el juego los ha bajado por ir justo).
	_amount_timer -= delta
	if _amount_timer <= 0.0:
		_amount_timer = 1.0
		var ratio: float = AMOUNT_SCALE[Fx.on(self).level()]
		_particles.amount_ratio = ratio
		if _splashes != null:
			_splashes.amount_ratio = ratio


## Cae un rayo: el trazo, el fogonazo que enciende las nubes y el paisaje y, al rato (el
## sonido va a 343 m/s), el trueno. `aside` es el ángulo respecto a donde mira la cámara.
func strike(aside: float = NAN) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var eye: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	var heading: float = randf() * TAU
	if camera != null and (not is_nan(aside) or randf() < 0.7):
		# Casi siempre hacia donde se mira, para que se vea caer.
		var forward: Vector3 = -camera.global_basis.z
		heading = atan2(forward.x, forward.z) + (aside if not is_nan(aside) else randf_range(-0.8, 0.8))
	var distance: float = randf_range(180.0, 420.0)
	var foot := Vector3(eye.x + sin(heading) * distance, 0.0, eye.z + cos(heading) * distance)
	var top: Vector3 = foot + Vector3(randf_range(-70.0, 70.0), 300.0, randf_range(-70.0, 70.0))
	LightningBolt.strike(self, top, foot)
	if clouds != null:
		clouds.flash(top, Color(0.72, 0.8, 1.0), 2.4, 480.0, 0.5)
	_flash = 1.0
	get_tree().create_timer(distance / 343.0).timeout.connect(func() -> void:
		if is_inside_tree():
			Sfx.play_2d(self, Sfx.THUNDER, lerpf(-3.0, -9.0, (distance - 180.0) / 240.0)))
