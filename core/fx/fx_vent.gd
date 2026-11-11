class_name FxVent
extends Node3D
## Fuente continua de humo (chimenea, tienda de mando, restos ardiendo): suelta bocanadas a su
## ritmo, y llamas si se le pide, mientras la cámara esté lo bastante cerca para verlas.

## Bocanadas de humo y llamaradas por segundo.
var rate: float = 4.0
var flames: float = 0.0
## Tamaño (m), velocidad de subida (m/s) y duración (s) de cada bocanada.
var size: float = 1.0
var rise: float = 2.5
var life: float = 5.0
## Color del humo, en lineal; la opacidad va en el alfa.
var color: Color = Fx.SOOT

var _due: float = 0.0
var _flame_due: float = 0.0
var _fx: Fx


func _process(delta: float) -> void:
	if not is_instance_valid(_fx):
		_fx = Fx.on(self)
	var near: float = _fx.nearness(global_position)
	if near <= 0.0:
		return
	_due += delta * rate * near
	while _due >= 1.0:
		_due -= 1.0
		var at: Vector3 = global_position + Fx.ball() * size * 0.3
		_fx.puff(Fx.Puff.SMOKE, at, Vector3(randf_range(-0.3, 0.3), rise * randf_range(0.8, 1.2), randf_range(-0.3, 0.3)), size * randf_range(0.8, 1.2), life * randf_range(0.8, 1.2), color, -0.6 if flames > 0.0 else 0.0)
	if flames > 0.0:
		_flame_due += delta * flames * near
		while _flame_due >= 1.0:
			_flame_due -= 1.0
			_fx.flame(global_position + Fx.ball() * size * 0.4, Vector3.ZERO, size * randf_range(0.7, 1.0))
