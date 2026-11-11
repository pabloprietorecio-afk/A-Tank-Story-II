class_name Hurtbox
extends Area3D
## Zona que recibe golpes. Los proyectiles solo conocen esta clase, nunca al enemigo concreto.

signal hit(amount: float, source: Node)

@export var health: HealthComponent
@export var damage_multiplier: float = 1.0
## Los proyectiles no dañan hurtboxes de su propio equipo.
@export var team: int = 0


func take_hit(amount: float, source: Node = null, _point: Vector3 = Vector3.ZERO) -> void:
	var final_amount: float = amount * damage_multiplier
	hit.emit(final_amount, source)
	if health != null:
		health.apply_damage(final_amount, source)
