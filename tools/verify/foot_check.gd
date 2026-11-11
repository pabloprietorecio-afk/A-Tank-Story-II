extends SceneTree
## Comprobación sin gráficos del personaje a pie (Etapa 1): cae al suelo, camina, corre, esprinta,
## se agacha, orienta el modelo y los clips existen. Uso:
##   godot --headless --path . --script res://tools/verify/foot_check.gd


func _init() -> void:
	var failures: Array[String] = []
	var root: Node = (load("res://levels/foot_test.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	await process_frame
	var ch: Character = root.character
	var touch: TouchControls = root.get_node("CharacterInputSource").touch
	var player: AnimationPlayer = ch.animator.director.animation_player if ch.animator != null else null
	if player == null:
		failures.append("sin AnimationPlayer")
	else:
		for action in [&"idle", &"walk", &"run", &"sprint"]:
			if not ch.animator.director.has_action(action):
				failures.append("falta clip para %s" % action)
	for i in 60:
		await physics_frame
	if not ch.is_on_floor():
		failures.append("no apoya en el suelo")

	touch.move_vector = Vector2(0.0, 1.0)
	var z0: float = ch.global_position.z
	for i in 60:
		await physics_frame
	if ch.gait != 3 or z0 - ch.global_position.z < 3.0:
		failures.append("no esprinta hacia delante (gait %d, avance %.1f)" % [ch.gait, z0 - ch.global_position.z])
	touch.move_vector = Vector2(0.0, 0.3)
	for i in 30:
		await physics_frame
	if ch.gait != 1 or ch.animator.director.current_action() != &"walk":
		failures.append("no camina con la palanca suave")
	touch.move_vector = Vector2.ZERO
	ch.crouching = true
	for i in 60:
		await physics_frame
	if ch._shape.height > Character.CROUCH_HEIGHT + 0.05:
		failures.append("no se agacha")
	ch.crouching = false

	print("FOOT RESULT fallos: %d" % failures.size())
	for f in failures:
		print("FOOT FAIL ", f)
	quit(0 if failures.is_empty() else 1)
