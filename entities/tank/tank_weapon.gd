class_name TankWeapon
extends Node
## Arma del tanque: cadencia y disparo de proyectiles.

signal fired

@export var projectile_scene: PackedScene
@export var projectile_speed: float = 150.0
@export var damage: float = 25.0
@export var reload_time: float = 1.2
@export var muzzle: Node3D

## Hurtboxes que el proyectil debe ignorar (las del propio tanque).
var ignore_rids: Array[RID] = []
var team: int = 0
## Multiplicadores de las mejoras temporales (premios).
var damage_mult: float = 1.0
var reload_mult: float = 1.0

var _cooldown: float = 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func can_fire() -> bool:
	return _cooldown <= 0.0 and projectile_scene != null and muzzle != null


## 0 = recién disparado, 1 = listo.
func ready_fraction() -> float:
	var total: float = reload_time * reload_mult
	return 1.0 - clampf(_cooldown / total, 0.0, 1.0) if total > 0.0 else 1.0


func fire() -> bool:
	if not can_fire():
		return false
	var scene: Node = get_tree().current_scene
	var shell: Projectile = Projectile.acquire(projectile_scene, scene if scene != null else get_tree().root)
	var direction: Vector3 = -muzzle.global_transform.basis.z
	shell.launch(muzzle.global_position, direction * projectile_speed, damage * damage_mult, get_parent(), ignore_rids, team)
	_cooldown = reload_time * reload_mult
	fired.emit()
	return true
