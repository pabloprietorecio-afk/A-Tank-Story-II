extends Node3D
## Zona de pruebas a pie (Etapa 1 de la secuela): suelo, un tanque como referencia de escala,
## unos obstáculos y el personaje con cámara en tercera persona. Se abre desde el menú (PRUEBA A PIE).

const SPAWN := Vector3(0.0, 0.2, 14.0)

var character: Character
var camera_rig: CharacterCamera


func _ready() -> void:
	GameSettings.ensure_loaded()
	_build_environment()
	_build_ground()
	_build_obstacles()
	_build_reference_tank()
	_build_character()
	_build_ui()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.45, 0.65)
	sky_material.sky_horizon_color = Color(0.75, 0.72, 0.65)
	sky_material.ground_horizon_color = Color(0.55, 0.5, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Character.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	mesh_instance.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.33, 0.24)
	material.roughness = 1.0
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)


func _build_obstacles() -> void:
	# Muro bajo, cajas y una rampa para probar colisiones, cámara y pendientes.
	_add_box(Vector3(6.0, 0.6, 0.5), Vector3(-6.0, 0.3, 6.0))
	_add_box(Vector3(1.2, 1.2, 1.2), Vector3(4.0, 0.6, 4.0))
	_add_box(Vector3(1.2, 2.4, 1.2), Vector3(7.0, 1.2, 4.0))
	_add_box(Vector3(10.0, 3.0, 0.6), Vector3(0.0, 1.5, -14.0))
	var ramp := _add_box(Vector3(4.0, 0.3, 8.0), Vector3(-10.0, 0.7, -4.0))
	ramp.rotation_degrees.x = -15.0


func _add_box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Character.LAYER_WORLD
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.45, 0.4)
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)
	return body


## Un tanque quieto: sirve para ver la escala del personaje respecto al vehículo.
func _build_reference_tank() -> void:
	var tank := Tank.new()
	tank.name = "ReferenceTank"
	tank.stats = Fronts.player_stats(Fronts.Id.NORMANDY, Fronts.Faction.ALLIES)
	tank.team = GameMode.PLAYER_TEAM
	tank.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(0.0, 0.2, -2.0))
	add_child(tank)


func _build_character() -> void:
	character = Character.new()
	character.name = "Character"
	character.transform = Transform3D(Basis(), SPAWN)
	add_child(character)
	camera_rig = CharacterCamera.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = character
	add_child(camera_rig)
	camera_rig.camera.current = true
	camera_rig.yaw = 0.0


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var touch := TouchControls.new()
	touch.fire_enabled = false
	layer.add_child(touch)
	var source := CharacterInputSource.new()
	source.name = "CharacterInputSource"
	source.character = character
	source.camera_rig = camera_rig
	source.touch = touch
	add_child(source)

	var crouch := Button.new()
	crouch.text = Loc.t("AGACHARSE")
	crouch.custom_minimum_size = Vector2(210.0, 90.0)
	crouch.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crouch.offset_left = -240.0
	crouch.offset_top = -130.0
	crouch.offset_right = -30.0
	crouch.offset_bottom = -40.0
	crouch.pressed.connect(source.toggle_crouch)
	layer.add_child(crouch)
	touch.exclusions.append(crouch)

	var back := Button.new()
	back.text = Loc.t("VOLVER")
	back.custom_minimum_size = Vector2(170.0, 70.0)
	back.position = Vector2(24.0, 24.0)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://levels/main_menu.tscn"))
	layer.add_child(back)
	touch.exclusions.append(back)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_CTRL:
		get_node("CharacterInputSource").toggle_crouch()
