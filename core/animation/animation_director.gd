class_name AnimationDirector
extends Node
## Capa semántica de animación: los clips importados se asignan a acciones («idle», «run»...)
## para poder cambiar el material sin reescribir la lógica. Procede de Football Cards (mismo autor).

@export var animation_player: AnimationPlayer
@export var blend_time: float = 0.18

## Acción -> clips candidatos (se usa el primero que exista).
var aliases: Dictionary = {}

var _current: StringName = &""


func _ready() -> void:
	if animation_player == null:
		animation_player = get_parent().find_child("AnimationPlayer", true, false) as AnimationPlayer


func register_alias(action: StringName, clips: Array[StringName]) -> void:
	aliases[action] = clips


func has_action(action: StringName) -> bool:
	if animation_player == null:
		return false
	for clip in aliases.get(action, []):
		if animation_player.has_animation(clip):
			return true
	return false


## Reproduce la acción; devuelve false si no hay clip. Cambiar solo la velocidad no reinicia el clip.
func play_semantic(action: StringName, speed: float = 1.0) -> bool:
	if animation_player == null:
		return false
	for clip in aliases.get(action, []):
		if animation_player.has_animation(clip):
			animation_player.speed_scale = speed
			if _current != action:
				animation_player.play(clip, blend_time)
				_current = action
			return true
	return false


func current_action() -> StringName:
	return _current
