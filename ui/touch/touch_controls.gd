class_name TouchControls
extends Control
## Controles táctiles: joystick flotante a la izquierda, arrastre de torreta a la derecha
## y botón FIRE. Cada dedo se sigue por su índice, así que funcionan varios a la vez.

const STICK_RADIUS: float = 120.0
const STICK_DEADZONE: float = 0.12
const FIRE_RADIUS: float = 95.0
const FIRE_MARGIN: float = 150.0
const LEFT_ZONE_FRACTION: float = 0.45

var move_vector: Vector2 = Vector2.ZERO
var fire_held: bool = false

## El tutorial apaga FIRE hasta que toca enseñarlo (atenuado y sin responder).
var fire_enabled: bool = true:
	set(value):
		fire_enabled = value
		if not value:
			_fire_id = -1
			fire_held = false
		queue_redraw()

## Controles de la interfaz (botones, paneles) cuyos toques no se usan para conducir ni apuntar.
var exclusions: Array[Control] = []

var _look_delta: Vector2 = Vector2.ZERO
var _stick_id: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _look_id: int = -1
var _fire_id: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Devuelve el arrastre acumulado de la torreta (en píxeles) y lo pone a cero.
func consume_look_delta() -> Vector2:
	var value: Vector2 = _look_delta
	_look_delta = Vector2.ZERO
	return value


func _screen_size() -> Vector2:
	return get_viewport_rect().size


func _fire_center() -> Vector2:
	return _screen_size() - Vector2(FIRE_MARGIN, FIRE_MARGIN)


## Centro del botón FIRE en pantalla (para señalarlo desde fuera).
func fire_center() -> Vector2:
	return _fire_center()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_on_press(touch.index, touch.position)
		else:
			_on_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		_on_drag(drag.index, drag.position, drag.relative)


func _on_press(index: int, pos: Vector2) -> void:
	for control in exclusions:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return
	if _fire_id == -1 and pos.distance_to(_fire_center()) <= FIRE_RADIUS * 1.25:
		if not fire_enabled:
			return
		_fire_id = index
		fire_held = true
	elif pos.x < _screen_size().x * LEFT_ZONE_FRACTION:
		if _stick_id == -1:
			_stick_id = index
			_stick_origin = pos
			_stick_pos = pos
	elif _look_id == -1:
		_look_id = index
	queue_redraw()


func _on_release(index: int) -> void:
	if index == _fire_id:
		_fire_id = -1
		fire_held = false
	elif index == _stick_id:
		_stick_id = -1
		move_vector = Vector2.ZERO
	elif index == _look_id:
		_look_id = -1
	queue_redraw()


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_id:
		var offset: Vector2 = (pos - _stick_origin).limit_length(STICK_RADIUS)
		_stick_pos = _stick_origin + offset
		var normalized := Vector2(offset.x, -offset.y) / STICK_RADIUS
		move_vector = normalized if normalized.length() > STICK_DEADZONE else Vector2.ZERO
		queue_redraw()
	elif index == _look_id:
		_look_delta += relative


func _draw() -> void:
	var green := Color(0.2, 1.0, 0.33, 0.8)
	var dim := Color(0.2, 1.0, 0.33, 0.35)
	if _stick_id != -1:
		draw_arc(_stick_origin, STICK_RADIUS, 0.0, TAU, 48, dim, 3.0)
		draw_circle(_stick_pos, 38.0, green)
	var fire_color := Color(1.0, 0.5, 0.1, 0.95) if fire_held else Color(1.0, 0.5, 0.1, 0.5)
	if not fire_enabled:
		fire_color.a = 0.15
	draw_arc(_fire_center(), FIRE_RADIUS, 0.0, TAU, 48, fire_color, 5.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, _fire_center() + Vector2(-34.0, 12.0), "FIRE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 32, fire_color)
