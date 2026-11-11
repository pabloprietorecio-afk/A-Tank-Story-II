class_name State
extends Node
## Estado base. La máquina de estados llama a enter/exit/update.

var machine: StateMachine


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass
