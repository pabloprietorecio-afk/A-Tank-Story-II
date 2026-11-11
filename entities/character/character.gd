class_name Character
extends CharacterBody3D
## Personaje a pie. Lo gobierna una fuente de órdenes (CharacterInputSource para el jugador;
## más adelante, la IA de los compañeros): solo escribe `move_input`, `look_yaw` y `crouching`.

const LAYER_WORLD: int = 1
const LAYER_TANK: int = 2
const LAYER_BOUNDARY: int = 8
const LAYER_CHARACTER: int = 16

const MODEL_PATH: String = "res://assets/characters/player_base.glb"
## El modelo mira hacia +Z; en Godot «adelante» es -Z.
const MODEL_YAW_OFFSET: float = PI

const WALK_SPEED: float = 1.9
const RUN_SPEED: float = 4.4
const SPRINT_SPEED: float = 6.6
const CROUCH_SPEED: float = 1.3
const ACCELERATION: float = 20.0
const TURN_RATE: float = 11.0
const GRAVITY: float = 25.0

const RADIUS: float = 0.35
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.15
const CROUCH_BLEND_SPEED: float = 9.0
## Cuánto se inclina hacia delante el modelo al agacharse (grados). Provisional: no hay clip propio.
const CROUCH_LEAN_DEG: float = 14.0

## Umbrales de la palanca (0..1) para cada modo de marcha.
const WALK_STICK_MAX: float = 0.45
const RUN_STICK_MAX: float = 0.9

## Órdenes. `move_input`: x = derecha, y = adelante, longitud 0..1.
var move_input: Vector2 = Vector2.ZERO
## Rumbo de la cámara: el movimiento es relativo a él.
var look_yaw: float = 0.0
var crouching: bool = false

var model: Node3D
var animator: CharacterAnimator
## Marcha actual: 0 quieto, 1 caminar, 2 correr, 3 esprintar.
var gait: int = 0

var _shape: CapsuleShape3D
var _collision: CollisionShape3D
var _crouch_amount: float = 0.0
var _model_instance: Node3D


func _ready() -> void:
	add_to_group(&"characters")
	collision_layer = LAYER_CHARACTER
	collision_mask = LAYER_WORLD | LAYER_TANK | LAYER_BOUNDARY
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4
	_build_collision()
	_build_model()


func _build_collision() -> void:
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_collision = CollisionShape3D.new()
	_collision.shape = _shape
	_collision.position.y = STAND_HEIGHT * 0.5
	add_child(_collision)


func _build_model() -> void:
	var holder := Node3D.new()
	holder.name = "ModelHolder"
	add_child(holder)
	model = holder
	var scene: PackedScene = load(MODEL_PATH) as PackedScene
	if scene == null:
		push_warning("Character: no se pudo cargar %s" % MODEL_PATH)
		return
	var instance: Node3D = scene.instantiate() as Node3D
	instance.name = "Model"
	instance.rotation.y = MODEL_YAW_OFFSET
	_model_instance = instance
	holder.add_child(instance)
	animator = CharacterAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(instance)


func _physics_process(delta: float) -> void:
	var stick: Vector2 = move_input.limit_length(1.0)
	var strength: float = stick.length()
	var target_speed: float = 0.0
	gait = 0
	if strength > 0.01:
		if crouching:
			gait = 1
			target_speed = CROUCH_SPEED * minf(strength / WALK_STICK_MAX, 1.0)
		elif strength <= WALK_STICK_MAX:
			gait = 1
			target_speed = WALK_SPEED
		elif strength <= RUN_STICK_MAX:
			gait = 2
			target_speed = RUN_SPEED
		else:
			gait = 3
			target_speed = SPRINT_SPEED

	var forward := Vector3(-sin(look_yaw), 0.0, -cos(look_yaw))
	var right := Vector3(cos(look_yaw), 0.0, -sin(look_yaw))
	var wish: Vector3 = (right * stick.x + forward * stick.y)
	if wish.length() > 0.001:
		wish = wish.normalized()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(wish * target_speed, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if wish.length() > 0.001:
		var target_yaw: float = atan2(-wish.x, -wish.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, clampf(TURN_RATE * delta, 0.0, 1.0))
	_update_crouch(delta)
	if animator != null:
		animator.update(horizontal.length(), gait, crouching)


## Agacharse: baja la cápsula y el modelo. Provisional hasta tener un clip propio de agachado.
func _update_crouch(delta: float) -> void:
	_crouch_amount = move_toward(_crouch_amount, 1.0 if crouching else 0.0, CROUCH_BLEND_SPEED * delta)
	var height: float = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_amount)
	_shape.height = height
	_collision.position.y = height * 0.5
	var lowering: float = (STAND_HEIGHT - CROUCH_HEIGHT) * 0.45 * _crouch_amount
	model.position.y = -lowering
	if _model_instance != null:
		_model_instance.rotation.x = deg_to_rad(CROUCH_LEAN_DEG) * _crouch_amount


## Dirección en la que mira el modelo (plano XZ), útil para otras mecánicas.
func facing() -> Vector3:
	var yaw: float = model.rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))
