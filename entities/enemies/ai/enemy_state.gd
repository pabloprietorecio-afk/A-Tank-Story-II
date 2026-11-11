class_name EnemyState
extends State
## Base de los estados de enemigo: acceso cómodo al cerebro y al tanque.

var brain: AIBrain:
	get: return machine.get_parent() as AIBrain

var tank: Tank:
	get: return brain.tank
