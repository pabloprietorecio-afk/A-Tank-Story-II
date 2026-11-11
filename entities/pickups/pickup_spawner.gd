class_name PickupSpawner
extends Node
## Reparte premios por el terreno cada cierto tiempo, a media distancia del jugador.

const MAX_ACTIVE: int = 4

var player: Tank
var is_free_point: Callable
var _timer: float = 12.0


func _ready() -> void:
	add_to_group(&"pickup_spawner")


func _process(delta: float) -> void:
	if player == null or player.is_destroyed:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = randf_range(14.0, 24.0)
	var active: int = 0
	for node in get_tree().get_nodes_in_group(&"radar_marks"):
		if node is Pickup:
			active += 1
	if active >= MAX_ACTIVE:
		return
	spawn(Pickup.random_kind(), _find_point())


func spawn(kind: String, point: Vector2) -> void:
	var pickup := Pickup.create(kind, player)
	pickup.position = Vector3(point.x, 0.0, point.y)
	get_parent().add_child(pickup)


func _find_point() -> Vector2:
	var origin := Vector2(player.global_position.x, player.global_position.z)
	var point := origin
	for attempt in 30:
		point = (origin + Vector2.from_angle(randf() * TAU) * randf_range(40.0, 130.0)).clampf(-185.0, 185.0)
		if is_free_point.call(point):
			break
	return point
