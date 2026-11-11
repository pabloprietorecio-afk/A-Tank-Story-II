class_name CharacterCamera
extends Node3D
## Cámara en tercera persona: gira alrededor del personaje y se acerca si hay una pared detrás.

const MIN_PITCH: float = deg_to_rad(-65.0)
const MAX_PITCH: float = deg_to_rad(30.0)
const DISTANCE: float = 4.2
const HEIGHT: float = 1.55
const CROUCH_HEIGHT: float = 1.0
const FOLLOW_SMOOTHING: float = 14.0

@export var target: Character

var yaw: float = 0.0
var pitch: float = deg_to_rad(-12.0)
var camera: Camera3D

var _arm: SpringArm3D
var _height: float = HEIGHT


func _ready() -> void:
	top_level = true
	_arm = SpringArm3D.new()
	_arm.spring_length = DISTANCE
	_arm.margin = 0.25
	_arm.collision_mask = Character.LAYER_WORLD
	_arm.shape = SphereShape3D.new()
	(_arm.shape as SphereShape3D).radius = 0.2
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 1500.0
	_arm.add_child(camera)
	if target != null:
		global_position = target.global_position + Vector3.UP * HEIGHT
	_apply_rotation()


## Gira la cámara (radianes). Positivo en yaw = a la izquierda.
func add_look(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	pitch = clampf(pitch + delta_pitch, MIN_PITCH, MAX_PITCH)
	_apply_rotation()


func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	if target == null:
		return
	var wanted_height: float = CROUCH_HEIGHT if target.crouching else HEIGHT
	_height = lerpf(_height, wanted_height, clampf(8.0 * delta, 0.0, 1.0))
	var wanted: Vector3 = target.global_position + Vector3.UP * _height
	global_position = global_position.lerp(wanted, clampf(FOLLOW_SMOOTHING * delta, 0.0, 1.0))
	_arm.add_excluded_object(target.get_rid())
