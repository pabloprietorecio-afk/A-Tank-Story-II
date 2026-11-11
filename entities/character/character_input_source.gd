class_name CharacterInputSource
extends Node
## Traduce los controles táctiles en órdenes para el personaje y mueve la cámara.
## Reutiliza TouchControls: joystick flotante a la izquierda, arrastre de cámara a la derecha.

@export var character: Character
@export var camera_rig: CharacterCamera
@export var touch: TouchControls
## Radianes de giro de cámara por píxel arrastrado.
@export var look_sensitivity: float = 0.005


func _process(_delta: float) -> void:
	if character == null or touch == null:
		return
	character.move_input = touch.move_vector
	var look: Vector2 = touch.consume_look_delta()
	if camera_rig != null:
		camera_rig.add_look(-look.x * look_sensitivity, -look.y * look_sensitivity)
		character.look_yaw = camera_rig.yaw
	_keyboard_fallback()


## Teclado para probar en ordenador (WASD, flechas, Ctrl = agacharse).
func _keyboard_fallback() -> void:
	if touch.move_vector != Vector2.ZERO:
		return
	var key := Vector2(
		Input.get_axis(&"ui_left", &"ui_right"),
		Input.get_axis(&"ui_down", &"ui_up"))
	if Input.is_physical_key_pressed(KEY_A):
		key.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		key.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		key.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		key.y -= 1.0
	if key != Vector2.ZERO:
		character.move_input = key.limit_length(1.0)
	if Input.is_physical_key_pressed(KEY_Q):
		camera_rig.add_look(0.03, 0.0)
	if Input.is_physical_key_pressed(KEY_E):
		camera_rig.add_look(-0.03, 0.0)


func toggle_crouch() -> void:
	if character != null:
		character.crouching = not character.crouching
