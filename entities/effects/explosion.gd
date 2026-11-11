class_name Explosion
extends RefCounted
## Explosión «a secas»: quien solo sabe dónde y cómo de grande la pide aquí, y Fx decide el
## efecto. Un `color` anaranjado es una explosión con fuego; cualquier otro, una nube de polvo
## y cascotes de ese color (derrumbes, golpes en piedra).
## Los efectos con forma propia (fogonazos, impactos, tanques que estallan) se piden a Fx.


static func spawn(host: Node, point: Vector3, strength: float = 1.0, color: Color = VectorMaterials.ORANGE, silent: bool = false) -> void:
	var fx: Fx = Fx.on(host)
	if color.r <= color.b + 0.25:
		fx.rubble(point, strength * 1.6, color)
	elif strength < 0.6:
		if point.y < 0.8:
			fx.shell_ground(point, strength / 0.4)
		else:
			fx.pop(point, strength / 0.4)
	else:
		fx.explosion(point, strength)
	if not silent:
		if strength < 0.8:
			Sfx.play_at(host, Sfx.HIT, point, 2.0)
		else:
			Sfx.play_at(host, Sfx.EXPLOSION, point, 6.0, 1.1 / clampf(strength, 0.8, 2.0))
