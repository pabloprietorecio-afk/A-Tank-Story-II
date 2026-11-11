class_name CloudDome
extends MeshInstance3D
## Techo de nubes de la partida (ver shaders/cloud_dome.gdshader): sigue a la cámara, se mueve
## con el viento y se enciende con los destellos de la batalla. Sustituye a la textura fija de
## nubes del cielo, que no podía moverse ni reflejar nada.

const RADIUS: float = 470.0
const FLASHES: int = 6

var _material: ShaderMaterial
var _at := PackedVector4Array()
var _light := PackedVector4Array()
var _from: Array[Color] = []
var _time := PackedFloat32Array()
var _left := PackedFloat32Array()
var _dirty: bool = false
var _cheap: bool = false


func _init() -> void:
	var dome := SphereMesh.new()
	dome.radius = RADIUS
	dome.height = RADIUS
	dome.is_hemisphere = true
	dome.radial_segments = 32
	dome.rings = 12
	mesh = dome
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/cloud_dome.gdshader")
	_material.set_shader_parameter("fx_noise", Fx.noise())
	# Se pinta antes que el humo y el resto de transparencias: va detrás de todo.
	_material.render_priority = -20
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_at.resize(FLASHES)
	_light.resize(FLASHES)
	_from.resize(FLASHES)
	_time.resize(FLASHES)
	_left.resize(FLASHES)
	_push()


## Aspecto del cielo: colores (en lineal) de la nube al sol y en sombra y de la bruma del
## horizonte; cuánto cubren (0..1), su opacidad y la deriva del viento.
func setup(lit: Color, shade: Color, haze: Color, coverage: float, density: float, wind: Vector3) -> void:
	_material.set_shader_parameter("lit_color", Vector3(lit.r, lit.g, lit.b))
	_material.set_shader_parameter("shade_color", Vector3(shade.r, shade.g, shade.b))
	_material.set_shader_parameter("haze_color", Vector3(haze.r, haze.g, haze.b))
	_material.set_shader_parameter("coverage", coverage)
	_material.set_shader_parameter("density", density)
	_material.set_shader_parameter("drift", Vector2(wind.x, wind.z) * 0.0015 + Vector2(0.002, 0.001))


## Destello que alumbra las nubes: dónde, de qué color, con qué fuerza, hasta dónde llega (m)
## y cuánto dura. Solo caben seis a la vez: uno nuevo sustituye al más flojo.
func flash(point: Vector3, color: Color, energy: float, reach: float, time: float) -> void:
	var slot: int = 0
	var weakest: float = INF
	for i in FLASHES:
		var strength: float = Vector3(_light[i].x, _light[i].y, _light[i].z).length() if _left[i] > 0.0 else 0.0
		if strength < weakest:
			weakest = strength
			slot = i
	if weakest > energy:
		return
	_at[slot] = Vector4(point.x, point.y, point.z, reach)
	_from[slot] = Color(color.r * energy, color.g * energy, color.b * energy)
	_light[slot] = Vector4(_from[slot].r, _from[slot].g, _from[slot].b, 1.0)
	_time[slot] = time
	_left[slot] = time
	_dirty = true


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	var cheap: bool = Fx.on(self).level() == 0
	if cheap != _cheap:
		_cheap = cheap
		_material.set_shader_parameter("cheap", cheap)
	if not _dirty:
		return
	_dirty = false
	for i in FLASHES:
		if _left[i] <= 0.0:
			continue
		_left[i] -= delta
		var t: float = maxf(_left[i] / _time[i], 0.0)
		var light: Color = _from[i] * (t * t)
		_light[i] = Vector4(light.r, light.g, light.b, t)
		_dirty = true
	_push()


func _push() -> void:
	_material.set_shader_parameter("flash_at", _at)
	_material.set_shader_parameter("flash_light", _light)
