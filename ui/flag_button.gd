class_name FlagButton
extends Button
## Bandera vieja y maltrecha, dibujada por código, que hace de botón de idioma: desteñida,
## con manchas, agujeros de metralla y el borde de la tela deshilachado, ondeando en su asta.
## Son las banderas lisas, sin escudos ni emblemas: España (rojigualda), Reino Unido (Union
## Jack, para el inglés), Francia, Italia y Japón (el disco solar).

const COLS: int = 40
const ROWS: int = 26
const FLAG_W: float = 96.0
const FLAG_H: float = 62.0
const POLE_W: float = 5.0
const MARGIN: float = 6.0

var code: String = "es"
## Marca la bandera del idioma activo (barra dorada debajo).
var current: bool = false:
	set(value):
		current = value
		queue_redraw()
## Si ondea (la del menú) o se queda quieta (las del selector, que no se mueven nunca).
var waving: bool = false

var _colors: Array[Color] = []
var _alive: Array[bool] = []
var _t: float = 0.0
var _phase: float = 0.0
var _redraw_timer: float = 0.0


static func create(language_code: String, wave: bool) -> FlagButton:
	var flag := FlagButton.new()
	flag.code = language_code
	flag.waving = wave
	return flag


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(FLAG_W + POLE_W + MARGIN * 2.0, FLAG_H + 22.0)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _ready() -> void:
	_phase = float(code.hash() % 100) * 0.1
	_weather()
	set_process(waving)


## Cambia la bandera que muestra (vuelve a calcular su desgaste).
func set_code(new_code: String) -> void:
	code = new_code
	_phase = float(code.hash() % 100) * 0.1
	_weather()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_redraw_timer += delta
	# 20 imágenes por segundo bastan para un ondeo lento.
	if _redraw_timer >= 0.05 and is_visible_in_tree():
		_redraw_timer = 0.0
		queue_redraw()


## Color de la bandera sin desgastar en el punto (u, v) de la tela (0..1).
func _pure_color(u: float, v: float) -> Color:
	match code:
		"es":
			return Color(0.78, 0.1, 0.12) if (v < 0.25 or v > 0.75) else Color(0.99, 0.76, 0.05)
		"fr":
			if u < 1.0 / 3.0:
				return Color(0.05, 0.16, 0.58)
			return Color(0.96, 0.96, 0.94) if u < 2.0 / 3.0 else Color(0.85, 0.12, 0.17)
		"it":
			if u < 1.0 / 3.0:
				return Color(0.0, 0.57, 0.27)
			return Color(0.96, 0.96, 0.94) if u < 2.0 / 3.0 else Color(0.8, 0.1, 0.14)
		"ja":
			var d: float = Vector2((u - 0.5) * 3.0, (v - 0.5) * 2.0).length()
			return Color(0.74, 0.0, 0.18) if d < 0.6 else Color(0.97, 0.97, 0.95)
		"en":
			return _union_jack(u, v)
		"pt":
			return _brazil(u, v)
		"id":
			return Color(0.84, 0.09, 0.16) if v < 0.5 else Color(0.97, 0.97, 0.95)
		"hi":
			return _india(u, v)
		"de":
			if v < 1.0 / 3.0:
				return Color(0.05, 0.05, 0.05)
			return Color(0.87, 0.0, 0.0) if v < 2.0 / 3.0 else Color(1.0, 0.81, 0.0)
		"ru":
			if v < 1.0 / 3.0:
				return Color(0.97, 0.97, 0.95)
			return Color(0.0, 0.22, 0.65) if v < 2.0 / 3.0 else Color(0.84, 0.17, 0.13)
	return Color(0.5, 0.5, 0.5)


## Brasil: campo verde, rombo amarillo y disco azul (sin la banda con el lema).
func _brazil(u: float, v: float) -> Color:
	var x: float = (u - 0.5) * 3.0
	var y: float = (v - 0.5) * 2.0
	if Vector2(x, y).length() < 0.5:
		return Color(0.0, 0.16, 0.56)
	if absf(x) / 1.2 + absf(y) / 0.8 < 1.0:
		return Color(1.0, 0.85, 0.0)
	return Color(0.0, 0.6, 0.25)


## India: azafrán, blanco y verde, con la rueda (chakra) azul marino de 24 radios.
func _india(u: float, v: float) -> Color:
	var x: float = (u - 0.5) * 3.0
	var y: float = (v - 0.5) * 2.0
	var d: float = Vector2(x, y).length()
	if d < 0.25:
		var spoke: bool = absf(sin(atan2(y, x) * 12.0)) > 0.85
		if d > 0.18 or d < 0.06 or spoke:
			return Color(0.0, 0.0, 0.5)
	if v < 1.0 / 3.0:
		return Color(1.0, 0.6, 0.2)
	return Color(0.97, 0.97, 0.95) if v < 2.0 / 3.0 else Color(0.07, 0.53, 0.03)


## Union Jack con los bordes blancos y la inversión de las franjas rojas de las diagonales.
func _union_jack(u: float, v: float) -> Color:
	var blue := Color(0.0, 0.14, 0.4)
	var white := Color(0.96, 0.96, 0.95)
	var red := Color(0.78, 0.07, 0.17)
	var x: float = (u - 0.5) * 60.0
	var y: float = (v - 0.5) * 40.0
	# Cruz de San Jorge (roja con borde blanco).
	if absf(x) < 3.2 or absf(y) < 3.2:
		return red if (absf(x) < 2.0 or absf(y) < 2.0) else white
	if absf(x) < 5.2 or absf(y) < 5.2:
		return white
	# Diagonales: la mitad superior se calcula tal cual y la inferior por simetría de media vuelta.
	var px: float = x
	var py: float = y
	if py > 0.0:
		px = -x
		py = -y
	var upper_left: bool = px < 0.0
	var s: float = (py * 30.0 - px * 20.0) / 36.06 if upper_left else (py * 30.0 + px * 20.0) / 36.06
	var shifted: float = s - (1.9 if upper_left else -1.9)
	if absf(shifted) < 1.2:
		return red
	if absf(s) < 4.0:
		return white
	return blue


func _hash(ix: int, iy: int, salt: int) -> float:
	var h: int = (ix * 374761393 + iy * 668265263 + salt * 144665) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## Ruido suave (valor interpolado) para las manchas y la suciedad.
func _noise(x: float, y: float, salt: int) -> float:
	var ix: int = floori(x)
	var iy: int = floori(y)
	var fx: float = x - float(ix)
	var fy: float = y - float(iy)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a: float = lerpf(_hash(ix, iy, salt), _hash(ix + 1, iy, salt), fx)
	var b: float = lerpf(_hash(ix, iy + 1, salt), _hash(ix + 1, iy + 1, salt), fx)
	return lerpf(a, b, fy)


## Calcula una sola vez el desgaste de cada trozo de tela: color pasado, manchas, quemaduras,
## agujeros y flecos. Es siempre igual para una misma bandera.
func _weather() -> void:
	var salt: int = absi(code.hash()) % 997
	var holes: Array[Vector3] = []
	var scale: float = float(COLS) / 26.0
	for i in 3:
		holes.append(Vector3(0.18 + _hash(i, 1, salt) * 0.66, 0.12 + _hash(i, 2, salt) * 0.76, (0.6 + _hash(i, 3, salt) * 0.7) * scale))
	# Un par de desgarros grandes en el borde libre: fila y profundidad (en columnas).
	var tears: Array[Vector2] = [
		Vector2(floorf(_hash(7, 7, salt) * float(ROWS - 6)) + 3.0, (3.0 + floorf(_hash(8, 8, salt) * 3.0)) * scale),
		Vector2(floorf(_hash(9, 9, salt) * float(ROWS - 6)) + 3.0, (2.0 + floorf(_hash(10, 10, salt) * 3.0)) * scale),
	]
	_colors.clear()
	_alive.clear()
	for col in COLS:
		for row in ROWS:
			var u: float = (float(col) + 0.5) / float(COLS)
			var v: float = (float(row) + 0.5) / float(ROWS)
			var c: Color = _pure_color(u, v)
			# Sol y lavados: desteñida hacia un sepia apagado.
			var gray: float = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			c = c.lerp(Color(gray * 1.08, gray * 0.96, gray * 0.78), 0.42)
			c = c.lerp(Color(0.86, 0.8, 0.66), 0.1 + 0.14 * _noise(u * 4.0, v * 3.0, salt + 5))
			# Manchas de humo, barro y óxido.
			var stain: float = smoothstep(0.55, 0.85, _noise(u * 5.0, v * 4.0, salt + 11))
			c = c.lerp(Color(0.24, 0.16, 0.09), stain * 0.5)
			var soot: float = smoothstep(0.6, 1.0, u) * _noise(u * 7.0, v * 6.0, salt + 17)
			c = c.lerp(Color(0.1, 0.08, 0.06), clampf(soot * 0.6, 0.0, 0.5))
			# Pliegues de la tela doblada.
			var crease: float = absf(sin((u * 2.6 + v * 1.4) * TAU))
			if crease < 0.07:
				c = c.darkened(0.16)
			var alive: bool = true
			# Agujeros de metralla con el borde quemado.
			for hole in holes:
				var d: float = (Vector2(u * float(COLS), v * float(ROWS)) - Vector2(hole.x * float(COLS), hole.y * float(ROWS))).length()
				if d < hole.z:
					alive = false
				elif d < hole.z + 1.4:
					c = c.darkened(0.5)
			# Flecos en el borde libre y desgarros.
			var fray: int = int(_hash(row, 4, salt) * 2.6 * scale)
			if col >= COLS - fray:
				alive = false
			elif col == COLS - fray - 1:
				c = c.darkened(0.3)
			for tear in tears:
				var depth: float = tear.y - absf(float(row) - tear.x) * 1.3 * scale * 0.9
				if depth > 0.0 and float(col) >= float(COLS) - depth:
					alive = false
			_colors.append(c)
			_alive.append(alive)


func _draw() -> void:
	var origin := Vector2(MARGIN, 8.0)
	var fx: float = origin.x + POLE_W
	# Asta de madera con su remate.
	var pole := Color(0.36, 0.24, 0.13)
	draw_line(Vector2(origin.x + POLE_W * 0.5, origin.y - 4.0), Vector2(origin.x + POLE_W * 0.5, origin.y + FLAG_H + 12.0), pole, POLE_W)
	draw_line(Vector2(origin.x + POLE_W * 0.5 - 1.0, origin.y - 4.0), Vector2(origin.x + POLE_W * 0.5 - 1.0, origin.y + FLAG_H + 12.0), Color(0.5, 0.36, 0.2), 1.5)
	draw_circle(Vector2(origin.x + POLE_W * 0.5, origin.y - 6.0), 3.4, Color(0.78, 0.62, 0.25))
	var cell_w: float = FLAG_W / float(COLS)
	var cell_h: float = FLAG_H / float(ROWS)
	# Ondeo: la tela sube y baja más cuanto más lejos del asta.
	var amplitude: float = 3.2 if waving else 2.2
	var points := PackedVector2Array()
	points.resize(4)
	for col in COLS:
		var x0: float = float(col) * cell_w
		var x1: float = x0 + cell_w
		var y_off0: float = _wave(x0)
		var y_off1: float = _wave(x1)
		var shade: float = 1.0 + (y_off1 - y_off0) * 0.12 / amplitude * 3.0
		for row in ROWS:
			var index: int = col * ROWS + row
			if not _alive[index]:
				continue
			var y0: float = float(row) * cell_h
			var y1: float = y0 + cell_h + 0.6
			points[0] = Vector2(fx + x0, origin.y + y0 + y_off0)
			points[1] = Vector2(fx + x1 + 0.5, origin.y + y0 + y_off1)
			points[2] = Vector2(fx + x1 + 0.5, origin.y + y1 + y_off1)
			points[3] = Vector2(fx + x0, origin.y + y1 + y_off0)
			var color: Color = _colors[index]
			color = Color(clampf(color.r * shade, 0.0, 1.0), clampf(color.g * shade, 0.0, 1.0), clampf(color.b * shade, 0.0, 1.0), 1.0)
			draw_colored_polygon(points, color)
	# Dos tiras con las que la tela cuelga del asta.
	for y in [origin.y + 6.0, origin.y + FLAG_H - 8.0]:
		draw_rect(Rect2(origin.x, y, POLE_W + 4.0, 3.0), Color(0.3, 0.2, 0.12))
	if current:
		draw_rect(Rect2(origin.x, origin.y + FLAG_H + 13.0, FLAG_W + POLE_W, 3.0), Color(0.96, 0.82, 0.5))


func _wave(x: float) -> float:
	var k: float = x / FLAG_W
	var amplitude: float = 3.2 if waving else 2.2
	return sin(x * 0.11 - _t * 3.2 + _phase) * amplitude * k
