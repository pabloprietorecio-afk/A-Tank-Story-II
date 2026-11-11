class_name CharacterAnimator
extends Node
## Elige la animación del personaje a partir de su velocidad y su postura.
## El modelo base solo trae reposo, trote y sprint: «caminar» es el trote a menos velocidad.
## Godot quita el sufijo «_Loop» al importar (Idle_Loop pasa a llamarse Idle), por eso se admiten ambos.
## Cuando haya clips propios (caminar, agacharse, subir al vehículo...) basta registrarlos en
## `_register_clips`; el resto del juego no cambia.

## Velocidad a la que se ve natural cada clip (m/s). Ajustar mirando el juego.
const JOG_NATURAL_SPEED: float = 4.4
const SPRINT_NATURAL_SPEED: float = 7.0
const MOVING_THRESHOLD: float = 0.25

var director: AnimationDirector


func setup(model_root: Node) -> void:
	director = AnimationDirector.new()
	director.name = "AnimationDirector"
	model_root.add_child(director)
	director.animation_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_register_clips()


func _register_clips() -> void:
	director.register_alias(&"idle", [&"Idle", &"Idle_Loop"])
	director.register_alias(&"walk", [&"Jog_Fwd", &"Jog_Fwd_Loop"])
	director.register_alias(&"run", [&"Jog_Fwd", &"Jog_Fwd_Loop"])
	director.register_alias(&"sprint", [&"Sprint", &"Sprint_Loop"])
	director.register_alias(&"crouch_idle", [&"Idle", &"Idle_Loop"])
	director.register_alias(&"crouch_walk", [&"Jog_Fwd", &"Jog_Fwd_Loop"])


## `gait`: 0 = quieto, 1 = caminar, 2 = correr, 3 = esprintar (lo decide Character).
func update(speed: float, gait: int, crouching: bool) -> void:
	if director == null:
		return
	if speed < MOVING_THRESHOLD or gait == 0:
		director.play_semantic(&"crouch_idle" if crouching else &"idle")
		return
	if crouching:
		director.play_semantic(&"crouch_walk", clampf(speed / JOG_NATURAL_SPEED, 0.3, 1.0))
		return
	match gait:
		1:
			director.play_semantic(&"walk", clampf(speed / JOG_NATURAL_SPEED, 0.35, 1.2))
		2:
			director.play_semantic(&"run", clampf(speed / JOG_NATURAL_SPEED, 0.7, 1.4))
		_:
			director.play_semantic(&"sprint", clampf(speed / SPRINT_NATURAL_SPEED, 0.8, 1.3))
