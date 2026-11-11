class_name Aircraft
extends Node3D
## Aviones de un bombardeo (solo visual): una cuña de tres aparatos de la época, del bando que
## lo pide, cruza el cielo en línea recta sobre la zona y desaparece.

const SPEED: float = 70.0

var direction: Vector3 = Vector3.FORWARD
var model: String = ""
var _life: float = 9.0
var _sound: FlybySound


## `hostile`: bombardeo enemigo (aviones del bando contrario) o aliado (del nuestro).
static func fly_over(host: Node, target: Vector3, hostile: bool, height: float = 55.0) -> Aircraft:
	var flight := Aircraft.new()
	var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	flight.direction = dir
	host.add_child(flight)
	flight.global_position = target - dir * SPEED * 3.0 + Vector3.UP * height
	flight.look_at(flight.global_position + dir, Vector3.UP)
	var faction: int = GameSession.enemy_faction() if hostile else GameSession.faction
	# Bombarderos medios o aviones de ataque al suelo: lo que de verdad apoyaba a los tanques.
	var choice: Array = SkyWar.pick_model(GameSession.front, faction, ["medium", "attack"])
	var spec: Dictionary = SkyWar.TYPES[choice[1]]
	flight.model = choice[0]
	var gap: float = spec["span"] * 1.3
	for offset in [Vector3.ZERO, Vector3(-gap, 1.5, gap * 0.9), Vector3(gap, 1.5, gap * 0.9)]:
		var plane: SkyWar.SkyPlane = SkyWar.make_plane(GameSession.front, faction, choice)
		plane.position = offset
		flight.add_child(plane)
	# Zumbido de los motores que se acerca, pasa por encima y se aleja.
	var sound := FlybySound.attach(flight, Sfx.PLANE_BOMBER if spec["engines"] > 1 else Sfx.PLANE_FIGHTER, 9.0, 45.0, 700.0, 1.0 if spec["engines"] > 1 else 0.88)
	sound.source_velocity = dir * SPEED
	flight._sound = sound
	return flight


func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_life -= delta
	if _sound != null and _life < 1.5:
		_sound.fade_out()
	if _life <= 0.0:
		queue_free()
