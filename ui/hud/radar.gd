class_name Radar
extends Control
## Radar circular. Arriba = hacia donde mira la torreta (la vista del jugador).
## Dibuja tanques (enemigos por nivel de amenaza, aliados en azul) y marcas de misión.

const RADIUS: float = 90.0
const RANGE: float = 200.0
const SWEEP_PERIOD: float = 2.5

@export var player: Tank

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * RADIUS * 2.0 + Vector2(8.0, 8.0)
	size = custom_minimum_size


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(RADIUS + 4.0, RADIUS + 4.0)
	var green: Color = VectorMaterials.GREEN
	draw_circle(c, RADIUS, Color(0.0, 0.12, 0.03, 0.55))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(green, 0.7), 2.0)
	draw_arc(c, RADIUS * 0.5, 0.0, TAU, 32, Color(green, 0.25), 1.0)
	draw_line(c + Vector2(-RADIUS, 0.0), c + Vector2(RADIUS, 0.0), Color(green, 0.2), 1.0)
	draw_line(c + Vector2(0.0, -RADIUS), c + Vector2(0.0, RADIUS), Color(green, 0.2), 1.0)
	var sweep: float = fmod(_time / SWEEP_PERIOD, 1.0) * TAU
	draw_line(c, c + Vector2(sin(sweep), -cos(sweep)) * RADIUS, Color(green, 0.35), 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -9.0), c + Vector2(-6.0, 7.0), c + Vector2(6.0, 7.0)]), green)
	if player == null or player.is_destroyed:
		return
	var yaw: float = player.turret_controller.world_yaw
	var origin: Vector3 = player.global_position
	# Marcas de misión (banderas, objetivos): cuadrados.
	for node in get_tree().get_nodes_in_group(&"radar_marks"):
		var mark := node as Node3D
		if mark == null or not mark.is_visible_in_tree():
			continue
		var pos: Vector2 = _to_radar(c, mark.global_position - origin, yaw)
		var mark_color: Color = mark.get_meta("radar_color", Color.WHITE)
		if mark.get_meta("radar_blink", false) and fmod(_time, 0.4) > 0.2:
			continue
		match mark.get_meta("radar_shape", "square"):
			"star":
				# Premio: cruz brillante.
				draw_line(pos + Vector2(-6.0, 0.0), pos + Vector2(6.0, 0.0), mark_color, 3.0)
				draw_line(pos + Vector2(0.0, -6.0), pos + Vector2(0.0, 6.0), mark_color, 3.0)
				draw_circle(pos, 2.5, Color.WHITE)
			"diamond":
				# Objetivo de misión: rombo.
				var d := PackedVector2Array([pos + Vector2(0.0, -8.0), pos + Vector2(8.0, 0.0), pos + Vector2(0.0, 8.0), pos + Vector2(-8.0, 0.0)])
				draw_colored_polygon(d, Color(mark_color, 0.85))
				d.append(d[0])
				draw_polyline(d, Color.WHITE, 1.5)
			"zone":
				# Zona de bombardeo: círculo a escala.
				var r: float = mark.get_meta("radar_radius", 10.0) / RANGE * (RADIUS - 6.0)
				draw_circle(pos, r, Color(mark_color, 0.35))
				draw_arc(pos, r, 0.0, TAU, 24, mark_color, 2.0)
			"ring":
				# Edificio con premio: anillo.
				draw_arc(pos, 5.0, 0.0, TAU, 12, mark_color, 2.5)
			_:
				draw_rect(Rect2(pos - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), mark_color, true)
				draw_rect(Rect2(pos - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Color(mark_color, 0.6), false, 1.5)
	for node in get_tree().get_nodes_in_group(&"tanks"):
		var other := node as Tank
		if other == null or other == player or other.is_destroyed:
			continue
		var offset: Vector3 = other.global_position - origin
		var out_of_range: bool = Vector2(offset.x, offset.z).length() > RANGE
		var pos: Vector2 = _to_radar(c, offset, yaw)
		var hostile: bool = player.is_hostile_to(other)
		var base: Color = other.stats.color if hostile else Color(0.35, 0.65, 1.0)
		var color: Color = Color(base, 0.45 if out_of_range else 1.0)
		var dot: float = (4.0 if out_of_range else 5.0) * other.stats.body_scale
		if hostile:
			draw_circle(pos, dot, color)
		else:
			draw_rect(Rect2(pos - Vector2(dot, dot) * 0.8, Vector2(dot, dot) * 1.6), color, false, 2.0)
		if other == player.aim_lock:
			draw_arc(pos, dot + 4.0, 0.0, TAU, 16, VectorMaterials.ORANGE, 2.0)


## Pasa un desplazamiento del mundo al radar ("arriba" = rumbo de la torreta).
func _to_radar(c: Vector2, offset: Vector3, yaw: float) -> Vector2:
	var local := Vector2(offset.x, offset.z).rotated(yaw)
	return c + local.limit_length(RANGE) / RANGE * (RADIUS - 6.0)
