class_name TutorialOverlay
extends Control
## Capa del tutorial sobre el HUD: instrucción, progreso, «SALTAR LECCIÓN», «✔ BIEN»,
## resaltado del control que se está enseñando y resumen final.
## No tiene controles propios de juego: solo señala los del HUD, el radar y la zona táctil.

signal skip_pressed
signal campaign_pressed
signal repeat_pressed
signal menu_pressed

const YELLOW := Color(1.0, 0.9, 0.25)

var hud: Hud
var touch: TouchControls
var radar: Radar
## Qué se resalta ahora: nombres de botones del HUD o zonas (stick, look, fire, reload,
## radar, armor, buffs, target_info).
var highlights: Array[String] = []
## Interruptor del menú de opciones que debe parpadear mientras el juego está en pausa.
var pulse_toggle: Control

var _panel: PanelContainer
var _text: Label
var _progress: Label
var _fraction: float = 0.0
var _skip: Button
var _flash: Label
var _flash_time: float = 0.0
var _end: PanelContainer
var _t: float = 0.0
var _shift: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	style.border_color = Color(YELLOW, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position.y = 150.0
	add_child(_panel)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_font_size_override("font_size", 23)
	_text.add_theme_color_override("font_color", Color.WHITE)
	_text.max_lines_visible = 2
	_panel.add_child(_text)

	_progress = Label.new()
	_progress.position = Vector2(24.0, 84.0)
	_progress.add_theme_font_size_override("font_size", 22)
	_progress.add_theme_color_override("font_color", YELLOW)
	add_child(_progress)

	_skip = Button.new()
	_skip.text = Loc.t("SALTAR LECCIÓN")
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.position = Vector2(24.0, 136.0)
	_skip.size = Vector2(230.0, 54.0)
	_skip.modulate.a = 0.85
	_skip.pressed.connect(func() -> void: skip_pressed.emit())
	add_child(_skip)

	_flash = Label.new()
	_flash.text = Loc.t("✔ BIEN")
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.add_theme_font_size_override("font_size", 64)
	_flash.add_theme_color_override("font_color", Color(0.35, 1.0, 0.45))
	_flash.add_theme_color_override("font_outline_color", Color.BLACK)
	_flash.add_theme_constant_override("outline_size", 10)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_flash.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_flash.position.y = 250.0
	_flash.modulate.a = 0.0
	add_child(_flash)
	if touch != null:
		touch.exclusions.append(_skip)


func set_instruction(text: String) -> void:
	_text.text = text
	_fit_panel()


## El cartel va centrado en el hueco entre «SALTAR LECCIÓN» y el radar; si el texto no cabe,
## se reduce la letra.
func _fit_panel() -> void:
	var left: float = 270.0
	var right: float = size.x - 226.0
	for font_size in [23, 22, 21, 20, 19, 18, 17, 16]:
		_text.add_theme_font_size_override("font_size", font_size)
		_panel.reset_size()
		if _panel.get_combined_minimum_size().x <= right - left:
			break
	_panel.size = _panel.get_combined_minimum_size()
	_panel.position.x = maxf(left, (left + right - _panel.size.x) * 0.5)


func set_progress(index: int, total: int) -> void:
	_progress.text = Loc.t("LECCIÓN %d / %d") % [index + 1, total]
	_fraction = float(index) / float(total)


## Baja el bloque de progreso y «SALTAR LECCIÓN» para dejar sitio a la lista de objetivos.
func shift_progress(down: float) -> void:
	_shift = down
	_progress.position.y = 84.0 + down
	_skip.position.y = 136.0 + down


func flash_ok() -> void:
	_flash_time = 1.3


## Resumen de controles y salida a la campaña.
func show_summary() -> void:
	_panel.visible = false
	_skip.visible = false
	_progress.visible = false
	highlights.clear()
	_end = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.07, 0.97)
	style.border_color = Color(0.6, 0.5, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	_end.add_theme_stylebox_override("panel", style)
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Por encima del HUD (la capa del tutorial queda por debajo de él).
	get_parent().add_child(_end)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_end.add_child(box)
	var title := Label.new()
	title.text = Loc.t("TUTORIAL COMPLETADO")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", VectorMaterials.GREEN)
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	var rows: Array = [
		[Loc.t("JOYSTICK IZQUIERDO"), Loc.t("AVANZAR, RETROCEDER Y GIRAR EL CASCO")],
		[Loc.t("ARRASTRAR A LA DERECHA"), Loc.t("MOVER LA TORRETA Y APUNTAR")],
		["FIRE", Loc.t("DISPARAR; LA BARRA BAJO LA MIRA ES LA RECARGA")],
		[Loc.t("CÁM"), Loc.t("CABINA, TRASERA Y TRASERA LEJANA")],
		["RADAR", Loc.t("PUNTO ENEMIGO · CUADRO ALIADO · ROMBO OBJETIVO · CRUZ PREMIO")],
		["ZOOM", Loc.t("PRISMÁTICOS; CON ELLOS APARECEN MISIL Y AVIÓN")],
		[Loc.t("MISIL"), Loc.t("PERSIGUE AL ENEMIGO FIJADO")],
		[Loc.t("AVIÓN"), Loc.t("BOMBARDEO ALIADO A MÁS DE 30 M DE TI")],
		[Loc.t("TRES FLECHAS"), Loc.t("TODOS CONMIGO: LOS ALIADOS TE SIGUEN (OTRA VEZ: LIBRES)")],
		[Loc.t("DIANA Y FLECHAS"), Loc.t("TODOS ATACAN EL OBJETIVO QUE APUNTAS")],
		[Loc.t("ZONA ROJA"), Loc.t("BOMBARDEO ENEMIGO: SAL ANTES DE QUE LLEGUE A CERO")],
		["⚙", Loc.t("MOVIMIENTO FÁCIL, APUNTADO AUTOMÁTICO, SONIDO Y ABANDONAR")],
	]
	for row in rows:
		for column in 2:
			var cell := Label.new()
			cell.text = row[column]
			cell.add_theme_font_size_override("font_size", 18)
			cell.add_theme_color_override("font_color", YELLOW if column == 0 else Color(0.9, 0.92, 0.9))
			grid.add_child(cell)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	var specs: Array = [[Loc.t("EMPEZAR LA CAMPAÑA"), campaign_pressed, 28], [Loc.t("REPETIR TUTORIAL"), repeat_pressed, 20], [Loc.t("MENÚ PRINCIPAL"), menu_pressed, 20]]
	for spec in specs:
		var button := Button.new()
		button.text = spec[0]
		button.add_theme_font_size_override("font_size", spec[2])
		button.custom_minimum_size = Vector2(330.0 if spec[2] > 20 else 220.0, 68.0)
		var sig: Signal = spec[1]
		button.pressed.connect(func() -> void: sig.emit())
		buttons.add_child(button)
	if touch != null:
		touch.exclusions.append(_end)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_fit_panel()


func _process(delta: float) -> void:
	_t += delta
	_flash_time = maxf(_flash_time - delta, 0.0)
	_flash.modulate.a = clampf(_flash_time * 2.0, 0.0, 1.0)
	var paused: bool = get_tree().paused
	_skip.disabled = paused
	if is_instance_valid(pulse_toggle):
		pulse_toggle.modulate = YELLOW.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 7.0)) if paused else Color.WHITE
	queue_redraw()


func clear_pulse() -> void:
	if is_instance_valid(pulse_toggle):
		pulse_toggle.modulate = Color.WHITE
	pulse_toggle = null


## Rectángulo en pantalla de lo que se resalta (Rect2() si ahora no existe o no se ve).
func highlight_rect(key: String) -> Rect2:
	var center: Vector2 = size * 0.5
	match key:
		"stick":
			return Rect2(Vector2(20.0, size.y * 0.42), Vector2(size.x * TouchControls.LEFT_ZONE_FRACTION - 40.0, size.y * 0.58 - 20.0))
		"look":
			return Rect2(Vector2(size.x * 0.5, size.y * 0.42), Vector2(size.x * 0.5 - 300.0, size.y * 0.58 - 90.0))
		"fire":
			var r: float = TouchControls.FIRE_RADIUS + 14.0
			return Rect2(touch.fire_center() - Vector2(r, r), Vector2(r, r) * 2.0)
		"reload":
			return Rect2(center + Vector2(-42.0, 26.0), Vector2(84.0, 22.0))
		"armor":
			return Rect2(Vector2(center.x - 240.0, size.y - 74.0), Vector2(480.0, 46.0))
		"buffs":
			return Rect2(Vector2(center.x - 240.0, size.y - 104.0), Vector2(480.0, 32.0))
		"target_info":
			return Rect2(center + Vector2(-150.0, -80.0), Vector2(310.0, 56.0))
		"radar":
			return radar.get_global_rect() if radar != null else Rect2()
	var control: Control = hud.controls.get(key) if hud != null else null
	if control != null and control.is_visible_in_tree():
		return control.get_global_rect()
	return Rect2()


func _draw() -> void:
	# Barra de progreso bajo «LECCIÓN n / N».
	if _progress.visible:
		var bar := Rect2(Vector2(24.0, 116.0 + _shift), Vector2(230.0, 10.0))
		draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _fraction, bar.size.y)), YELLOW, true)
		draw_rect(bar, Color(YELLOW, 0.8), false, 1.5)
	if get_tree().paused:
		return
	var pulse: float = 0.5 + 0.5 * sin(_t * 6.0)
	for key in highlights:
		var rect: Rect2 = highlight_rect(key)
		if rect.size == Vector2.ZERO:
			continue
		var grown: Rect2 = rect.grow(4.0 + pulse * 5.0)
		if key == "stick" or key == "look":
			draw_rect(grown, Color(YELLOW, 0.05 + 0.06 * pulse), true)
		draw_rect(grown, Color(YELLOW, 0.45 + 0.55 * pulse), false, 4.0)
		_draw_arrow(grown, pulse)
		if key == "stick":
			_draw_thumb(rect.get_center(), true)
		elif key == "look":
			_draw_thumb(rect.get_center(), false)


## Flecha que señala el rectángulo desde el lado del centro de la pantalla.
func _draw_arrow(rect: Rect2, pulse: float) -> void:
	if rect.size.x > 300.0 and rect.size.y > 200.0:
		return
	var target: Vector2 = rect.get_center()
	var from_center: Vector2 = size * 0.5 - target
	var tip: Vector2
	var dir: Vector2
	if rect.position.y < 100.0 or absf(from_center.y) * rect.size.x > absf(from_center.x) * rect.size.y or from_center.length() < 80.0:
		dir = Vector2(0.0, 1.0 if from_center.y >= 0.0 else -1.0)
		tip = target + dir * (rect.size.y * 0.5 + 6.0)
	else:
		dir = Vector2(1.0 if from_center.x >= 0.0 else -1.0, 0.0)
		tip = target + dir * (rect.size.x * 0.5 + 6.0)
	tip += dir * pulse * 10.0
	var side := Vector2(-dir.y, dir.x)
	var points := PackedVector2Array([tip, tip + dir * 26.0 + side * 16.0, tip + dir * 26.0 - side * 16.0])
	draw_colored_polygon(points, YELLOW)
	draw_line(tip + dir * 26.0, tip + dir * 52.0, YELLOW, 8.0)


## Dibujo de un pulgar deslizando: arriba/abajo (joystick) o a los lados (torreta).
func _draw_thumb(at: Vector2, vertical: bool) -> void:
	var swing: float = sin(_t * 2.2) * 60.0
	var offset := Vector2(0.0, -swing) if vertical else Vector2(swing, 0.0)
	var axis := Vector2(0.0, 80.0) if vertical else Vector2(80.0, 0.0)
	draw_line(at - axis, at + axis, Color(YELLOW, 0.5), 3.0)
	draw_circle(at + offset, 30.0, Color(YELLOW, 0.35))
	draw_arc(at + offset, 30.0, 0.0, TAU, 32, Color(YELLOW, 0.9), 3.0)
