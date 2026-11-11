class_name HealthComponent
extends Node
## Blindaje de una entidad. No sabe quién es su dueño: solo emite señales.

signal damaged(amount: float, source: Node)
signal died(source: Node)

@export var max_health: float = 100.0

var current: float
var is_dead: bool = false
## No recibe daño alguno (campo de prácticas).
var invulnerable: bool = false
## El blindaje nunca baja de aquí (0 = puede morir).
var min_health: float = 0.0


func _ready() -> void:
	current = max_health


func apply_damage(amount: float, source: Node = null) -> void:
	if is_dead or invulnerable:
		return
	current = maxf(current - amount, min_health)
	damaged.emit(amount, source)
	if current <= 0.0:
		is_dead = true
		died.emit(source)


func fraction() -> float:
	return current / max_health if max_health > 0.0 else 0.0


func heal(amount: float) -> void:
	if is_dead:
		return
	current = minf(current + amount, max_health)


func revive() -> void:
	is_dead = false
	current = max_health
