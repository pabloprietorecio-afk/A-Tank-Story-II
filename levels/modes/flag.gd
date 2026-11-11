class_name Flag
extends Node3D
## Bandera de captura. Estados: en su base, llevada por un tanque o caída en el suelo.

enum Status { HOME, CARRIED, DROPPED }

const RETURN_TIME: float = 25.0

var team: int = 0
var home: Vector3
var state: Status = Status.HOME
var carrier: Tank = null
var dropped_time: float = 0.0


static func create(flag_team: int, faction: int, home_pos: Vector3) -> Flag:
	var flag := Flag.new()
	flag.team = flag_team
	flag.home = home_pos
	flag.position = home_pos
	flag._build(faction)
	return flag


func _build(faction: int) -> void:
	var pole := VectorMaterials.make_box(Vector3(0.15, 6.0, 0.15), Color(0.6, 0.6, 0.6), 4, 0.5)
	pole.position.y = 3.0
	add_child(pole)
	var cloth_color: Color = Color(0.15, 0.25, 0.5) if faction == Fronts.Faction.ALLIES else Color(0.4, 0.42, 0.4)
	var cloth := MeshInstance3D.new()
	var cloth_mesh := BoxMesh.new()
	cloth_mesh.size = Vector3(0.05, 1.6, 2.4)
	cloth.mesh = cloth_mesh
	cloth.material_override = VectorMaterials.paint(cloth_color)
	cloth.position = Vector3(0.0, 5.1, 1.25)
	add_child(cloth)
	# Emblema: estrella blanca (Aliados) o cruz de hierro (Alemania).
	var emblem := MeshInstance3D.new()
	var emblem_mesh := BoxMesh.new()
	emblem.mesh = emblem_mesh
	if faction == Fronts.Faction.ALLIES:
		emblem_mesh.size = Vector3(0.07, 0.7, 0.7)
		emblem.material_override = VectorMaterials.paint(Color(0.95, 0.95, 0.95))
		emblem.rotation.x = PI * 0.25
	else:
		emblem_mesh.size = Vector3(0.07, 0.9, 0.25)
		emblem.material_override = VectorMaterials.paint(Color(0.05, 0.05, 0.05))
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.07, 0.25, 0.9)
		bar.mesh = bar_mesh
		bar.material_override = emblem.material_override
		emblem.add_child(bar)
	emblem.position = cloth.position
	add_child(emblem)
	var light := OmniLight3D.new()
	light.light_color = cloth_color.lightened(0.5)
	light.omni_range = 8.0
	light.light_energy = 1.5
	light.position.y = 5.0
	add_child(light)
	add_to_group(&"radar_marks")


func set_radar_color(color: Color) -> void:
	set_meta("radar_color", color)


func pick_up(tank: Tank) -> void:
	state = Status.CARRIED
	carrier = tank


func drop() -> void:
	state = Status.DROPPED
	carrier = null
	dropped_time = 0.0
	global_position = Vector3(global_position.x, 0.0, global_position.z)


func return_home() -> void:
	state = Status.HOME
	carrier = null
	global_position = home


func _process(delta: float) -> void:
	match state:
		Status.CARRIED:
			if is_instance_valid(carrier):
				global_position = carrier.global_position + Vector3.UP * 1.5
		Status.DROPPED:
			dropped_time += delta
			if dropped_time >= RETURN_TIME:
				return_home()
