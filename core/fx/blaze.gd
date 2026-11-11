class_name Blaze
extends Node3D
## Incendio: llamas, humo negro que sube en columna, pavesas, chisporroteo y el resplandor que
## alumbra lo que tiene alrededor (y las nubes, si es grande). Arde en los edificios
## bombardeados, en los árboles alcanzados y en los escombros de lo que se destruye.
## De lejos solo se pintan la columna de humo y el resplandor; las llamas con detalle, cuando
## la cámara está cerca.

## Incendios que prenden durante la partida y pueden arder a la vez; al prender uno más se
## empieza a apagar el más viejo (los de ambiente, que no se apagan, no cuentan).
const MAX_LIVE: int = 6

static var _live: Array[Blaze] = []

## Media caja (m, en local) de la que salen las llamas.
var extent := Vector3(1.0, 0.4, 1.0)
## Tamaño de las llamas (m).
var power: float = 1.0
## Segundos que arde con fuerza; INF = fuego de ambiente, que no se apaga.
var fuel: float = INF
## Lo que tarda en apagarse cuando se queda sin qué quemar, y lo que humea después.
var die_down: float = 8.0
var smoulder: float = 45.0
## Cantidad de humo (1 = la normal para su tamaño).
var smoke: float = 1.0
## Nivel del fuego (0..1): lo baja quien lo sofoca (un tanque que aplasta los restos).
var level: float = 1.0
## Los incendios grandes tiñen las nubes que tienen encima.
var lights_sky: bool = false

var _age: float = 0.0
var _phase: float = randf() * TAU
var _flame_due: float = 0.0
var _smoke_due: float = 0.0
var _ember_due: float = 0.0
var _glow_timer: float = 0.0
var _light_timer: float = 0.0
var _sky_timer: float = 0.0
var _crackle_timer: float = 1.0
var _fx: Fx


func _ready() -> void:
	if fuel == INF:
		return
	_live.append(self)
	if _live.size() > MAX_LIVE:
		_live[0].put_out()
		_live.remove_at(0)


func _exit_tree() -> void:
	_live.erase(self)


## Deja de arder: las llamas bajan en unos segundos y queda humeando.
func put_out() -> void:
	fuel = minf(fuel, _age)


## Le quedan `seconds` de arder con fuerza (para los fuegos de ambiente que dejan de serlo).
func burn_for(seconds: float) -> void:
	fuel = _age + seconds


## Parte ya consumida de lo que tenía que quemar (0..1).
func spent() -> float:
	return 0.0 if fuel == INF else clampf(_age / maxf(fuel, 1.0), 0.0, 1.0)


## Cuánto arde ahora mismo (0 apagado, 1 a tope).
func fire() -> float:
	if fuel == INF:
		return level
	return level * clampf((fuel + die_down - _age) / die_down, 0.0, 1.0)


func _process(delta: float) -> void:
	_age += delta
	var burning: float = fire()
	var smoking: float = 1.0
	if fuel != INF:
		var left: float = fuel + die_down + smoulder - _age
		if left <= 0.0:
			queue_free()
			return
		smoking = clampf(left / 12.0, 0.0, 1.0)
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	var origin: Vector3 = global_position
	var frame: Basis = global_basis.orthonormalized()
	var near: float = _fx.nearness(origin)
	# Las llamas respiran: suben y bajan despacio, nunca iguales.
	var breath: float = 0.78 + 0.22 * sin(_age * 1.9 + _phase) * sin(_age * 0.7 + _phase * 1.7)
	var area: float = maxf(extent.x * extent.z * 4.0, 0.5)
	var top: Vector3 = origin + Vector3.UP * (extent.y + power * 0.6)
	if burning > 0.02:
		if near > 0.0:
			_flame_due += delta * near * burning * breath * clampf(5.0 + area * 1.6, 6.0, 24.0)
			while _flame_due >= 1.0:
				_flame_due -= 1.0
				var at: Vector3 = origin + frame * Vector3(randf_range(-1.0, 1.0) * extent.x, randf_range(-0.3, 1.0) * extent.y, randf_range(-1.0, 1.0) * extent.z)
				_fx.flame(at, Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)), power * randf_range(0.8, 1.3) * (0.6 + 0.4 * burning))
			_ember_due += delta * near * burning * clampf(0.8 + area * 0.25, 1.0, 5.0)
			while _ember_due >= 1.0:
				_ember_due -= 1.0
				_fx.ember(top + frame * Vector3(randf_range(-1.0, 1.0) * extent.x, 0.0, randf_range(-1.0, 1.0) * extent.z), Vector3(randf_range(-1.2, 1.2), randf_range(2.0, 5.0) + power, randf_range(-1.2, 1.2)))
			# Chisporroteo: de vez en cuando salta un puñado de chispas.
			_crackle_timer -= delta
			if _crackle_timer <= 0.0 and near > 0.35:
				_crackle_timer = randf_range(0.5, 2.2) / maxf(burning, 0.3)
				var at: Vector3 = origin + frame * Vector3(randf_range(-1.0, 1.0) * extent.x, extent.y, randf_range(-1.0, 1.0) * extent.z)
				for i in randi_range(3, 7):
					_fx.spark(at, Vector3(randf_range(-2.5, 2.5), randf_range(4.0, 9.0), randf_range(-2.5, 2.5)), 0.05, randf_range(0.5, 1.1), Fx.SPARK)
		# El resplandor se ve desde lejos aunque no se pinten las llamas.
		_glow_timer -= delta
		if _glow_timer <= 0.0:
			_glow_timer = 0.11
			# (Con OpenGL la suma de luz deslumbra mucho más: allí va atenuado.)
			_fx.glow(Fx.Glow.HALO, top, Vector3.ZERO, (extent.x + extent.z) * 1.4 + power * 2.4, 0.3, Fx.FIRE_GLOW, (0.3 if _fx.on_gpu() else 0.08) * burning * breath * randf_range(0.7, 1.15))
		_light_timer -= delta
		if _light_timer <= 0.0 and near > 0.5:
			_light_timer = 0.1
			_fx.light(top + Vector3.UP * 0.5, Color(1.0, 0.5, 0.18), randf_range(1.2, 2.4) * burning * (0.6 + 0.4 * power), 7.0 + (extent.x + extent.z) * 2.0 + power * 3.0, 0.22)
		if lights_sky:
			_sky_timer -= delta
			if _sky_timer <= 0.0:
				_sky_timer = 0.6
				_fx.sky_flash(origin, Color(1.0, 0.45, 0.16), 0.1 * burning * power, 260.0, 1.3)
	# El humo: negro y rápido mientras hay llama, gris y perezoso cuando solo quedan rescoldos.
	# De lejos se pintan menos bocanadas, pero más grandes, para que la columna se siga viendo.
	_smoke_due += delta * maxf(near, 0.22) * smoking * smoke * maxf(burning, 0.3) * clampf(1.6 + area * 0.2, 2.0, 4.0)
	while _smoke_due >= 1.0:
		_smoke_due -= 1.0
		var at: Vector3 = origin + frame * Vector3(randf_range(-0.7, 0.7) * extent.x, extent.y + randf_range(0.3, 1.2) * power, randf_range(-0.7, 0.7) * extent.z)
		var size: float = power * randf_range(1.15, 1.8) * (1.9 - 0.9 * near)
		var drift := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		if burning > 0.12 and power >= 1.3:
			# Un incendio grande levanta una columna alta que el viento va tumbando.
			_fx.puff(Fx.Puff.PLUME, at, drift + Vector3.UP * (2.6 + power * 1.6) * randf_range(0.8, 1.2), size, randf_range(6.5, 8.8), Fx.SOOT.lerp(Fx.DARK_SMOKE, randf()), -0.9)
		elif burning > 0.12:
			_fx.black_smoke(at, drift + Vector3.UP * (2.0 + power * 2.0) * randf_range(0.8, 1.2), size, randf_range(4.5, 6.5))
		else:
			_fx.puff(Fx.Puff.SMOKE, at, drift + Vector3.UP * randf_range(1.4, 2.4), size * 0.8, randf_range(5.0, 7.5), Color(Fx.GREY_SMOKE.r, Fx.GREY_SMOKE.g, Fx.GREY_SMOKE.b, 0.55))
