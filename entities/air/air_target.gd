class_name AirTarget
extends Node3D
## Avión enemigo que cruza el cielo y se puede derribar a cañonazos: caza, avión de ataque al
## suelo (más lento y resistente, vuela haciendo eses) o bombardero (grande y lento, el blanco
## más fácil). Son modelos de la época del bando contrario en ese frente.
## Al derribarlo da un premio (blindaje, misil o bombardeo) a quien lo derriba.

enum Kind { FIGHTER, ATTACK, BOMBER }

const SPEEDS: Array[float] = [24.0, 15.0, 11.0]
const PLANE_SPEED: float = 24.0
const TYPE_NAMES: Array[String] = ["fighter", "attack", "medium"]
## Distancia a la que estalla un proyectil cerca del aparato.
const PROXIMITY: float = 7.0

var kind: Kind = Kind.FIGHTER
var model: String = ""
var health: HealthComponent
var hurtbox: Hurtbox
var is_destroyed: bool = false
var _velocity: Vector3
var _life: float = 40.0
var _falling: bool = false
var _wobble: float = randf() * TAU
var _sound: FlybySound


static func spawn(host: Node, aircraft_kind: Kind, center: Vector3) -> AirTarget:
	var target := AirTarget.new()
	target.kind = aircraft_kind
	host.add_child(target)
	var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var speed: float = SPEEDS[aircraft_kind]
	var height: float = [randf_range(28.0, 42.0), randf_range(22.0, 32.0), randf_range(40.0, 55.0)][aircraft_kind]
	var start_dist: float = [160.0, 110.0, 90.0][aircraft_kind]
	target.global_position = center - dir * start_dist + dir.cross(Vector3.UP) * randf_range(-40.0, 40.0) + Vector3.UP * height
	target._velocity = dir * speed
	target.look_at(target.global_position + dir, Vector3.UP)
	return target


func _ready() -> void:
	add_to_group(&"air_targets")
	add_to_group(&"radar_marks")
	set_meta("radar_color", Color(1.0, 0.4, 0.9))
	set_meta("radar_shape", "star")
	health = HealthComponent.new()
	health.max_health = [30.0, 45.0, 30.0][kind]
	add_child(health)
	health.died.connect(_on_died)
	hurtbox = Hurtbox.new()
	hurtbox.team = 1
	hurtbox.health = health
	hurtbox.collision_layer = 4
	hurtbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Caja de impacto algo generosa para que se pueda acertar.
	box.size = [Vector3(12.0, 4.0, 11.0), Vector3(15.0, 4.5, 12.5), Vector3(23.0, 5.0, 17.5)][kind]
	shape.shape = box
	hurtbox.add_child(shape)
	add_child(hurtbox)
	var faction: int = GameSession.enemy_faction()
	var choice: Array = SkyWar.pick_model(GameSession.front, faction, [TYPE_NAMES[kind]])
	model = choice[0]
	add_child(SkyWar.make_plane(GameSession.front, faction, choice))
	match kind:
		Kind.FIGHTER:
			_sound = FlybySound.attach(self, Sfx.PLANE_FIGHTER, 6.0, 32.0, 450.0)
		Kind.ATTACK:
			_sound = FlybySound.attach(self, Sfx.PLANE_FIGHTER, 6.0, 30.0, 420.0, 0.86)
		_:
			_sound = FlybySound.attach(self, Sfx.PLANE_BOMBER, 5.0, 32.0, 420.0)


func _process(delta: float) -> void:
	_life -= delta
	if _sound != null:
		_sound.source_velocity = _velocity
		if _falling:
			# Al caer derribado, el motor se embala.
			_sound.base_pitch = move_toward(_sound.base_pitch, 1.7, delta * 0.5)
	if _falling:
		_velocity += Vector3.DOWN * 18.0 * delta
		rotation.z += delta * 2.5
		global_position += _velocity * delta
		if global_position.y <= 0.5:
			Explosion.spawn(self, Vector3(global_position.x, 0.5, global_position.z), 2.0)
			queue_free()
		return
	if kind == Kind.ATTACK:
		# El avión de ataque no vuela recto: va haciendo eses para estorbar la puntería.
		_wobble += delta
		_velocity = _velocity.rotated(Vector3.UP, sin(_wobble * 0.7) * delta * 0.45)
		if _velocity.length_squared() > 0.01:
			look_at(global_position + _velocity, Vector3.UP)
	global_position += _velocity * delta
	if _life <= 0.0 or absf(global_position.x) > 320.0 or absf(global_position.z) > 320.0:
		queue_free()


## Se aleja sin más (al acabar la fase aérea).
func leave() -> void:
	_life = minf(_life, 4.0)
	_velocity = _velocity.normalized() * PLANE_SPEED * 2.0 + Vector3.UP * 6.0


func _on_died(source: Node) -> void:
	is_destroyed = true
	_falling = true
	remove_from_group(&"radar_marks")
	remove_from_group(&"air_targets")
	hurtbox.set_deferred("monitorable", false)
	hurtbox.collision_layer = 0
	Explosion.spawn(self, global_position, 1.2)
	if source is Tank and (source as Tank).is_player:
		get_tree().call_group(&"game_mode", &"air_reward", global_position)
