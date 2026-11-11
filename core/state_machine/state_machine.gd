class_name StateMachine
extends Node
## Máquina de estados: los estados son nodos hijos y se identifican por su nombre.

signal state_changed(from: StringName, to: StringName)

var current: State
var current_name: StringName = &""

var _states: Dictionary = {}


func start(initial: StringName) -> void:
	for child in get_children():
		if child is State:
			var state: State = child
			state.machine = self
			_states[state.name] = state
	change_to(initial)


func change_to(state_name: StringName) -> void:
	if not _states.has(state_name):
		push_error("StateMachine: estado desconocido '%s'" % state_name)
		return
	var previous: StringName = current_name
	if current != null:
		current.exit()
	current = _states[state_name]
	current_name = state_name
	current.enter(previous)
	state_changed.emit(previous, state_name)


func _physics_process(delta: float) -> void:
	if current != null:
		current.update(delta)
