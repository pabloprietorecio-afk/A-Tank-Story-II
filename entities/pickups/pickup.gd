class_name Pickup
extends Node3D
## Premio sobre el terreno. Lo recoge el jugador pasando por encima.
## Cuanto más vale, menos tiempo dura antes de desaparecer. Se ve en el radar.

const KINDS: Dictionary = {
	"points": {"name": "PUNTOS +150", "color": Color(1.0, 0.9, 0.3), "life": 60.0, "weight": 5.0},
	"repair": {"name": "REPARACIÓN +35", "color": Color(0.3, 1.0, 0.4), "life": 45.0, "weight": 4.0},
	"reload": {"name": "RECARGA RÁPIDA 20 s", "color": Color(0.3, 0.9, 1.0), "life": 35.0, "weight": 2.5},
	"shield": {"name": "BLINDAJE EXTRA 20 s", "color": Color(0.4, 0.5, 1.0), "life": 30.0, "weight": 2.0},
	"damage": {"name": "CAÑÓN PESADO 20 s", "color": Color(1.0, 0.3, 0.2), "life": 25.0, "weight": 1.5},
	"missile": {"name": "MISIL +1", "color": Color(1.0, 0.55, 0.15), "life": 40.0, "weight": 1.6},
	"strike": {"name": "BOMBARDEO +1", "color": Color(0.85, 0.45, 1.0), "life": 40.0, "weight": 1.4},
	"medal": {"name": "MEDALLA +1000", "color": Color(1.0, 0.75, 0.2), "life": 15.0, "weight": 0.6},
}
const PICK_RADIUS: float = 4.5
const BUFF_TIME: float = 20.0

var kind: String = "points"
var time_left: float = 60.0
var player: Tank
var _visual: Node3D
var _beam: MeshInstance3D
var _t: float = 0.0


static func create(pickup_kind: String, target: Tank) -> Pickup:
	var pickup := Pickup.new()
	pickup.kind = pickup_kind
	pickup.player = target
	pickup.time_left = KINDS[pickup_kind]["life"]
	return pickup


static func random_kind() -> String:
	var total: float = 0.0
	for k in KINDS:
		total += KINDS[k]["weight"]
	var roll: float = randf() * total
	for k in KINDS:
		roll -= KINDS[k]["weight"]
		if roll <= 0.0:
			return k
	return "points"


func _ready() -> void:
	var color: Color = KINDS[kind]["color"]
	_visual = Node3D.new()
	add_child(_visual)
	var crate := VectorMaterials.make_box(Vector3(1.4, 1.4, 1.4), color.darkened(0.3), 5, 0.7)
	_visual.add_child(crate)
	for axis in [Vector3(1.5, 0.3, 0.3), Vector3(0.3, 1.5, 0.3), Vector3(0.3, 0.3, 1.5)]:
		var band := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = axis
		band.mesh = mesh
		band.material_override = VectorMaterials.flat(color)
		_visual.add_child(band)
	# Columna de luz para verlo de lejos.
	_beam = MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.25
	beam_mesh.bottom_radius = 0.6
	beam_mesh.height = 30.0
	beam_mesh.radial_segments = 8
	_beam.mesh = beam_mesh
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(color, 0.25)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position.y = 15.0
	add_child(_beam)
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 7.0
	light.light_energy = 2.0
	light.position.y = 2.0
	add_child(light)
	add_to_group(&"radar_marks")
	set_meta("radar_color", color)
	set_meta("radar_shape", "star")


func _process(delta: float) -> void:
	_t += delta
	time_left -= delta
	_visual.rotation.y = _t * 1.5
	_visual.position.y = 1.4 + sin(_t * 2.5) * 0.3
	# Parpadea los últimos 5 segundos.
	var expiring: bool = time_left < 5.0
	visible = not expiring or fmod(_t, 0.4) < 0.25
	set_meta("radar_blink", expiring)
	if time_left <= 0.0:
		queue_free()
		return
	if is_instance_valid(player) and not player.is_destroyed and player.global_position.distance_to(global_position) <= PICK_RADIUS:
		_collect()


func _collect() -> void:
	match kind:
		"points":
			_award(150)
		"medal":
			_award(1000)
		"repair":
			player.health.heal(35.0)
		"missile":
			get_tree().call_group(&"game_mode", &"grant_missiles", 1)
		"strike":
			get_tree().call_group(&"game_mode", &"grant_strikes", 1)
		_:
			player.add_buff(kind, BUFF_TIME)
	get_tree().call_group(&"game_mode", &"announce", Loc.t("PREMIO: %s") % Loc.t(KINDS[kind]["name"]), false)
	Sfx.play_2d(self, Sfx.PICKUP, 0.0)
	get_tree().call_group(&"voice", &"say", "pickup", VoiceManager.Priority.LOW)
	queue_free()


func _award(points: int) -> void:
	get_tree().call_group(&"game_mode", &"add_score", points)
