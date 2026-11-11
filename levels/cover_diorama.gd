class_name CoverDiorama
extends Node3D
## Portada del menú: un Sherman y un Tiger frente a frente en un campo normando al atardecer,
## con humo, fuego, explosiones lejanas y la cámara girando despacio.

var _camera: Camera3D
var _time: float = 0.0
var _fire_light: OmniLight3D
var _boom_timer: float = 2.0
var _guns_timer: float = 5.0
## Mallas del último tanque creado (para calcinar el que hace de resto).
var _wreck_meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.08, 0.1, 0.22)
	sky_material.sky_horizon_color = Color(0.95, 0.5, 0.25)
	sky_material.ground_horizon_color = Color(0.6, 0.35, 0.2)
	sky_material.ground_bottom_color = Color(0.05, 0.05, 0.05)
	sky_material.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.6, 0.38, 0.25)
	env.fog_sky_affect = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(-70.0), 0.0)
	sun.light_color = Color(1.0, 0.7, 0.45)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	# El humo y el polvo de los efectos se iluminan con esta misma luz.
	Fx.set_lighting(sun.global_basis.z, sun.light_color.srgb_to_linear() * sun.light_energy, sky_material.sky_top_color.lerp(sky_material.sky_horizon_color, 0.55).srgb_to_linear() * 0.6, env.fog_density)
	var fx: Fx = Fx.on(self)
	var dirt: Color = Fronts.ground_colors(Fronts.Id.NORMANDY)[2]
	fx.soil = dirt.darkened(0.3).srgb_to_linear()
	fx.dust = dirt.lerp(Color(0.56, 0.53, 0.48), 0.4).srgb_to_linear()
	# Nubes del atardecer, que se encienden con las explosiones y la artillería lejana.
	var clouds := CloudDome.new()
	add_child(clouds)
	clouds.setup(Color(0.85, 0.34, 0.17), Color(0.1, 0.055, 0.1), sky_material.sky_horizon_color.srgb_to_linear(), 0.45, 0.8, fx.wind)
	fx.sky = clouds

	var ground_mat: ShaderMaterial = VectorMaterials.ground().duplicate()
	var colors: Array[Color] = Fronts.ground_colors(Fronts.Id.NORMANDY)
	ground_mat.set_shader_parameter("grass", colors[0])
	ground_mat.set_shader_parameter("dry_grass", colors[1])
	ground_mat.set_shader_parameter("dirt", colors[2])
	ground_mat.set_shader_parameter("gravel", colors[3])
	ground_mat.set_shader_parameter("grid_strength", 0.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = ground_mat
	add_child(ground)

	_tank("m4_sherman", Fronts.Faction.ALLIES, Vector3(5.0, 0.0, 6.0), deg_to_rad(-65.0), deg_to_rad(5.0))
	_tank("tiger1", Fronts.Faction.AXIS, Vector3(17.0, 0.0, -6.0), deg_to_rad(125.0), deg_to_rad(-12.0))
	var wreck := _tank("panzer4", Fronts.Faction.AXIS, Vector3(-14.0, 0.0, -38.0), deg_to_rad(30.0), 0.6)
	for mesh in _wreck_meshes:
		mesh.material_override = VectorMaterials.burnt(mesh.material_override)
	_smoke(Vector3(-14.0, 2.0, -38.0))
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.5, 0.15)
	_fire_light.omni_range = 16.0
	_fire_light.position = Vector3(-14.0, 2.5, -38.0)
	add_child(_fire_light)

	var church := PropFactory.church()
	church.position = Vector3(30.0, 0.0, -60.0)
	church.rotation.y = 0.4
	add_child(church)
	for i in 3:
		# La del centro está bombardeada y sigue ardiendo.
		var house: Destructible = PropFactory.bombed_house(Vector3(6.5, 4.2, 7.5)) if i == 1 else PropFactory.house(Vector3(6.0, 4.0, 7.0))
		house.position = Vector3(-35.0 + i * 11.0, 0.0, -55.0 - i * 4.0)
		house.rotation.y = 0.2 * i
		add_child(house)
	var hedge := PropFactory.hedgerow(40.0)
	hedge.position = Vector3(-5.0, 0.0, -35.0)
	add_child(hedge)
	for i in 8:
		var tree: Destructible = PropFactory.burnt_tree(randf_range(4.0, 6.0), 0, i == 0) if i < 2 else PropFactory.apple_tree(randf_range(4.0, 6.0))
		tree.position = Vector3(randf_range(-40.0, 40.0), 0.0, randf_range(-50.0, -30.0))
		add_child(tree)
	var ruin := PropFactory.ruin(10.0)
	ruin.position = Vector3(30.0, 0.0, -15.0)
	ruin.rotation.y = -0.6
	add_child(ruin)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 500.0
	add_child(_camera)
	_camera.current = true


func _tank(id: String, faction: int, pos: Vector3, yaw: float, turret_yaw: float) -> Node3D:
	var stats: TankStats = Fronts.tank(id)
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	add_child(holder)
	var model: TankModel = TankModel.build(holder, stats, Fronts.paint(Fronts.Id.NORMANDY, faction, stats.nation), false)
	model.turret.rotation.y = turret_yaw
	_wreck_meshes = model.own
	return holder


## Los restos del Panzer IV arden: llamas y una columna de humo negro.
func _smoke(at: Vector3) -> void:
	var vent := FxVent.new()
	vent.position = at
	vent.rate = 6.0
	vent.flames = 9.0
	vent.size = 1.5
	vent.rise = 3.0
	vent.life = 6.0
	add_child(vent)


func _process(delta: float) -> void:
	_time += delta
	var sway: float = sin(_time * 0.06)
	_camera.position = Vector3(-4.0 + sway * 3.0, 4.2, 20.0)
	_camera.look_at(Vector3(-3.0 + sway * 2.0, 2.2, -4.0))
	_fire_light.light_energy = 3.0 + sin(_time * 13.0) * 0.8 + sin(_time * 7.3) * 0.6
	_boom_timer -= delta
	if _boom_timer <= 0.0:
		_boom_timer = randf_range(3.0, 7.0)
		Explosion.spawn(self, Vector3(randf_range(-60.0, 60.0), 1.0, randf_range(-90.0, -60.0)), 1.6, VectorMaterials.ORANGE, true)
	# Artillería tras el horizonte: una salva de fogonazos en las nubes del fondo.
	_guns_timer -= delta
	if _guns_timer <= 0.0:
		_guns_timer = randf_range(6.0, 14.0)
		var centre := Vector3(randf_range(-1500.0, 1500.0), 0.0, randf_range(-3000.0, -1800.0))
		var at: float = 0.0
		for i in randi_range(3, 7):
			at += randf_range(0.1, 0.6)
			var point: Vector3 = centre + Vector3(randf_range(-400.0, 400.0), 0.0, randf_range(-300.0, 300.0))
			get_tree().create_timer(at).timeout.connect(func() -> void:
				if is_inside_tree():
					Fx.on(self).sky_flash(point, Color(1.0, 0.62, 0.32), randf_range(1.2, 2.0), randf_range(300.0, 420.0), randf_range(0.22, 0.42)))
