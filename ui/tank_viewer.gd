class_name TankViewer
extends SubViewportContainer
## Visor 3D de un tanque: el modelo gira despacio sobre un fondo neutro, con luz de estudio.
## Funciona aunque el juego esté en pausa.

var _holder: Node3D
var _viewport: SubViewport


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(500.0, 320.0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.5)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-30.0), 0.0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(150.0), 0.0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	_viewport.add_child(rim)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 7.0
	floor_mesh.bottom_radius = 7.0
	floor_mesh.height = 0.1
	floor_mesh.radial_segments = 32
	var floor := MeshInstance3D.new()
	floor.mesh = floor_mesh
	floor.material_override = VectorMaterials.paint(Color(0.2, 0.21, 0.19))
	floor.position.y = -0.05
	_viewport.add_child(floor)
	var camera := Camera3D.new()
	camera.fov = 40.0
	# Orientación calculada a mano: el visor aún no está en el árbol al crearse.
	var eye := Vector3(0.0, 4.0, 10.0)
	camera.transform = Transform3D(Basis.looking_at(Vector3(0.0, 1.2, 0.0) - eye, Vector3.UP), eye)
	_viewport.add_child(camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)


func show_tank(stats: TankStats, paint: Dictionary) -> void:
	for child in _holder.get_children():
		child.queue_free()
	var model_root := Node3D.new()
	_holder.add_child(model_root)
	# Ajusta la escala para que todos los modelos ocupen un tamaño parecido.
	model_root.scale = Vector3.ONE / maxf(stats.body_scale, 0.8)
	TankModel.build(model_root, stats, paint, false)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_holder.rotation.y += delta * 0.5
