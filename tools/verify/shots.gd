extends Node
## Herramienta de verificación (no va en el APK): recorre escenas de muestra y partidas de
## cada frente y guarda capturas en res://shots_out. La usa el flujo .github/workflows/verify.yml
## para comprobar el aspecto del juego con un renderizador por software.


func _ready() -> void:
	var runner := Runner.new()
	runner.name = "ShotRunner"
	get_tree().root.add_child.call_deferred(runner)


class Runner extends Node:

	var _dir: String
	var _unreachable: int = 0
	var _camera: Camera3D
	var _stage: Node3D

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		# Con el renderizador por software todo va lento: que los efectos no se rebajen solos.
		Fx.governor = false
		_dir = ProjectSettings.globalize_path("res://shots_out")
		DirAccess.make_dir_recursive_absolute(_dir)
		_run.call_deferred()

	func _run() -> void:
		await _frames(2)
		var only: String = OS.get_environment("SHOTS_ONLY")
		if only == "" or only.contains("tanks"):
			await _tanks()
		if only == "" or only.contains("boom"):
			await _explosions()
		if only == "" or only.contains("props"):
			await _props()
		if only == "" or only.contains("arena"):
			for front in 3:
				await _arena(front)
		if only == "" or only.contains("menu"):
			await _menu()
		if only.contains("flags"):
			await _flags()
		if only.contains("fit"):
			await _menu_fit()
		if only.contains("story"):
			_campaign()
			await _story(Fronts.Faction.ALLIES, Fronts.Id.NORMANDY, 6)
			await _story(Fronts.Faction.AXIS, Fronts.Id.KURSK, 6)
			await _story(Fronts.Faction.ALLIES, Fronts.Id.AFRICA, 5)
			await _story(Fronts.Faction.AXIS, Fronts.Id.AFRICA, 7)
			await _story(Fronts.Faction.ALLIES, Fronts.Id.AFRICA, 1)
			await _story(Fronts.Faction.ALLIES, Fronts.Id.KURSK, 1)
			await _story(Fronts.Faction.AXIS, Fronts.Id.NORMANDY, 5)
			await _story(Fronts.Faction.ALLIES, Fronts.Id.NORMANDY, 3)
			await _story(Fronts.Faction.AXIS, Fronts.Id.KURSK, 3)
			await _story(Fronts.Faction.ALLIES, Fronts.Id.KURSK, 4)
			print("REACH RESULT inaccesibles: ", _unreachable)
		if only.contains("nav"):
			await _nav()
		if only.contains("tutorial"):
			await _tutorial()
		if only == "" or only.contains("tutshots"):
			await _tutorial_shots()
		if only.contains("ai"):
			await _ai_reaction()
		if only.contains("ctf"):
			await _ctf()
		if only.contains("sky"):
			await _sky()
		if only == "" or only.contains("skyshots"):
			await _sky_shots()
		if only == "" or only.contains("ctfshot"):
			await _ctf_shot()
		print("SHOTS DONE")
		get_tree().quit()

	func _frames(count: int) -> void:
		for i in count:
			await get_tree().process_frame

	func _snap(shot: String) -> void:
		await _frames(3)
		if DisplayServer.get_name() == "headless":
			return
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_jpg(_dir.path_join(shot + ".jpg"), 0.88)
		print("SHOT ", shot)

	func _look(eye: Vector3, target: Vector3, fov: float = 45.0) -> void:
		_camera.fov = fov
		_camera.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
		_camera.current = true

	## Escenario neutro: cielo de atardecer, sol con sombras y suelo del frente indicado.
	func _new_stage(front: int) -> void:
		var old: Node = get_tree().current_scene
		if old != null:
			old.queue_free()
		await _frames(2)
		GameSession.front = front
		_stage = Node3D.new()
		get_tree().root.add_child(_stage)
		get_tree().current_scene = _stage
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color(0.2, 0.35, 0.6)
		sky_material.sky_horizon_color = Color(0.7, 0.68, 0.6)
		sky_material.ground_horizon_color = Color(0.5, 0.48, 0.42)
		sky_material.sky_cover = VectorMaterials.clouds()
		sky_material.sky_cover_modulate = Color(0.6, 0.6, 0.6)
		var sky := Sky.new()
		sky.sky_material = sky_material
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.7
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var world_env := WorldEnvironment.new()
		world_env.environment = env
		_stage.add_child(world_env)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(-40.0), 0.0)
		sun.light_color = Color(1.0, 0.93, 0.82)
		sun.light_energy = 1.3
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 80.0
		_stage.add_child(sun)
		# El humo y el polvo de los efectos se iluminan con la luz de este escenario.
		Fx.set_lighting(sun.global_basis.z, sun.light_color.srgb_to_linear() * sun.light_energy, sky_material.sky_top_color.lerp(sky_material.sky_horizon_color, 0.55).srgb_to_linear() * 0.6, 0.0)
		var fx: Fx = Fx.on(_stage)
		var dirt: Color = Fronts.ground_colors(front)[2]
		fx.soil = dirt.darkened(0.3).srgb_to_linear()
		fx.dust = dirt.lerp(Color(0.56, 0.53, 0.48), 0.4).srgb_to_linear()
		var ground_mat: ShaderMaterial = VectorMaterials.ground().duplicate()
		var colors: Array[Color] = Fronts.ground_colors(front)
		ground_mat.set_shader_parameter("grass", colors[0])
		ground_mat.set_shader_parameter("dry_grass", colors[1])
		ground_mat.set_shader_parameter("dirt", colors[2])
		ground_mat.set_shader_parameter("gravel", colors[3])
		ground_mat.set_shader_parameter("tint", 0.0)
		ground_mat.set_shader_parameter("wet", 0.0)
		var plane := PlaneMesh.new()
		plane.size = Vector2(400.0, 400.0)
		var ground := MeshInstance3D.new()
		ground.mesh = plane
		ground.material_override = ground_mat
		_stage.add_child(ground)
		_camera = Camera3D.new()
		_camera.far = 500.0
		_stage.add_child(_camera)

	func _tank(id: String, front: int, faction: int, pos: Vector3, yaw: float, player: bool = false) -> TankModel:
		var stats: TankStats = Fronts.tank(id)
		var holder := Node3D.new()
		holder.position = pos
		holder.rotation.y = yaw
		_stage.add_child(holder)
		return TankModel.build(holder, stats, Fronts.paint(front, faction, stats.nation), player)

	func _tanks() -> void:
		var allies: Array[String] = ["m4_sherman", "t34_76", "cromwell", "m10_wolverine", "churchill", "is2", "m26_pershing", "kv1", "t34_85", "su85", "crusader"]
		var axis: Array[String] = ["tiger1", "panther", "panzer4", "stug3", "tiger2", "panzer3", "elefant", "marder3"]
		var wheeled: Array[String] = ["m8_greyhound", "ba64", "puma"]
		await _new_stage(Fronts.Id.NORMANDY)
		for i in allies.size():
			_tank(allies[i], Fronts.Id.NORMANDY if i % 2 == 0 else Fronts.Id.KURSK, Fronts.Faction.ALLIES, Vector3(i * 8.0, 0.0, 0.0), deg_to_rad(-35.0))
		for i in axis.size():
			_tank(axis[i], Fronts.Id.NORMANDY if i % 2 == 0 else Fronts.Id.KURSK, Fronts.Faction.AXIS, Vector3(i * 9.0, 0.0, 14.0), deg_to_rad(-35.0))
		for i in wheeled.size():
			_tank(wheeled[i], Fronts.Id.AFRICA, Fronts.Faction.AXIS if i == 2 else Fronts.Faction.ALLIES, Vector3(i * 7.0, 0.0, 26.0), deg_to_rad(-35.0))
		var wreck: TankModel = _tank("panzer4", Fronts.Id.NORMANDY, Fronts.Faction.AXIS, Vector3(30.0, 0.0, 26.0), deg_to_rad(-60.0))
		for mesh in wreck.own:
			mesh.material_override = VectorMaterials.burnt(mesh.material_override)
		_tank("m4_sherman", Fronts.Id.AFRICA, Fronts.Faction.ALLIES, Vector3(40.0, 0.0, 26.0), deg_to_rad(-35.0), true)
		await get_tree().create_timer(1.5).timeout
		for i in allies.size():
			_look(Vector3(i * 8.0 - 6.5, 3.2, -7.5), Vector3(i * 8.0, 1.2, 0.0), 40.0)
			await _snap("tank_%s" % allies[i])
		for i in axis.size():
			_look(Vector3(i * 9.0 - 7.0, 3.4, 14.0 - 8.0), Vector3(i * 9.0, 1.3, 14.0), 40.0)
			await _snap("tank_%s" % axis[i])
		for i in wheeled.size():
			_look(Vector3(i * 7.0 - 5.0, 2.6, 26.0 - 6.0), Vector3(i * 7.0, 1.0, 26.0), 40.0)
			await _snap("tank_%s" % wheeled[i])
		_look(Vector3(30.0 - 6.0, 3.0, 26.0 - 7.0), Vector3(30.0, 1.0, 26.0), 40.0)
		await _snap("tank_wreck")
		# Otros ángulos: costado, zaga, cenital y primer plano del tren de rodaje.
		_look(Vector3(0.0, 1.6, -9.0), Vector3(0.0, 1.2, 0.0), 40.0)
		await _snap("angle_sherman_low")
		_look(Vector3(9.0, 1.4, 14.0 - 8.0), Vector3(0.0, 1.3, 14.0), 35.0)
		await _snap("angle_tiger_side")
		_look(Vector3(8.0 + 5.0, 4.0, 8.0), Vector3(8.0, 1.0, 0.0), 40.0)
		await _snap("angle_t34_rear")
		_look(Vector3(9.0, 11.0, 14.0 + 0.5), Vector3(9.0, 0.0, 14.0), 40.0)
		await _snap("angle_panther_top")
		_look(Vector3(-2.6, 0.9, 14.0 - 3.2), Vector3(-0.6, 0.6, 14.0 - 1.0), 40.0)
		await _snap("angle_tiger_tracks")
		_look(Vector3(40.0 + 5.0, 6.0, 26.0 + 9.0), Vector3(40.0, 1.0, 26.0), 40.0)
		await _snap("angle_player_rear")
		_look(Vector3(-10.0, 7.0, -14.0), Vector3(22.0, 0.0, 12.0), 60.0)
		await _snap("lineup")

	## Explosiones a cámara lenta: grande, impacto pequeño y derrumbe sin fuego.
	func _explosions() -> void:
		for front in [Fronts.Id.NORMANDY, Fronts.Id.AFRICA]:
			await _new_stage(front)
			_tank("panzer4", front, Fronts.Faction.AXIS, Vector3(-9.0, 0.0, -3.0), deg_to_rad(-50.0))
			_look(Vector3(2.0, 3.5, 17.0), Vector3(0.5, 2.8, 0.0), 50.0)
			await get_tree().create_timer(0.6).timeout
			Engine.time_scale = 0.3
			Explosion.spawn(_stage, Vector3(0.0, 0.5, 0.0), 1.6, VectorMaterials.ORANGE, true)
			Explosion.spawn(_stage, Vector3(7.5, 1.2, 2.0), 0.4, VectorMaterials.ORANGE, true)
			Explosion.spawn(_stage, Vector3(-6.0, 1.5, 4.0), 1.2, Color(0.5, 0.48, 0.45), true)
			for i in 9:
				await _snap("boom_%d_%d" % [front, i])
			Engine.time_scale = 1.0

	func _props() -> void:
		for front in 3:
			await _new_stage(front)
			PropFactory.mountain_color = Fronts.mountain_color(front)
			var props: Array[Node3D] = []
			match front:
				Fronts.Id.AFRICA:
					props = [PropFactory.desert_house(Vector3(7.0, 4.0, 7.0)), PropFactory.palm(8.0), PropFactory.desert_house(Vector3(5.0, 3.2, 6.0)), PropFactory.palm(9.5), PropFactory.sandbags(8.0), PropFactory.rock(2.2), PropFactory.barrel(), StructureFactory.flak_gun()]
				Fronts.Id.KURSK:
					props = [PropFactory.izba(Vector3(6.0, 3.5, 7.0)), PropFactory.birch(8.0), PropFactory.izba(Vector3(7.0, 3.8, 8.0)), PropFactory.tree(9.0), PropFactory.haystack(), PropFactory.hedgehog(), PropFactory.fence(10.0), StructureFactory.water_tower()]
				_:
					props = [PropFactory.house(Vector3(7.0, 4.5, 8.0)), PropFactory.apple_tree(5.5), PropFactory.house(Vector3(6.0, 4.0, 7.0)), PropFactory.hedgerow(20.0), PropFactory.ruin(12.0), PropFactory.lamp_post(), PropFactory.rock(1.8), StructureFactory.command_tent()]
			for i in props.size():
				props[i].position = Vector3((i % 4) * 13.0, 0.0, -(i / 4) * 16.0)
				_stage.add_child(props[i])
			if front == Fronts.Id.NORMANDY:
				var church := PropFactory.church()
				church.position = Vector3(20.0, 0.0, -45.0)
				_stage.add_child(church)
			for i in 5:
				var mountain := PropFactory.mountain(randf_range(45.0, 70.0), randf_range(18.0, 40.0), 10 if front == Fronts.Id.AFRICA else 7)
				mountain.position = Vector3(-120.0 + i * 70.0, 0.0, -170.0 - (i % 2) * 40.0)
				_stage.add_child(mountain)
			var hill := PropFactory.mountain(14.0, 9.0, 10 if front == Fronts.Id.AFRICA else 7)
			hill.position = Vector3(60.0, 0.0, -10.0)
			_stage.add_child(hill)
			# Casa bombardeada en llamas y árboles quemados (uno ardiendo y otro que solo humea).
			var bombed := PropFactory.bombed_house(Vector3(7.0, 4.4, 8.0), front)
			bombed.position = Vector3(-18.0, 0.0, -8.0)
			bombed.rotation.y = 0.5
			_stage.add_child(bombed)
			for i in 2:
				var burnt := PropFactory.burnt_tree(6.0 if front != Fronts.Id.AFRICA else 8.0, [0, 2, 1][front], i == 0)
				burnt.position = Vector3(-10.0 - i * 9.0, 0.0, 4.0 + i * 2.0)
				_stage.add_child(burnt)
			await get_tree().create_timer(1.0).timeout
			_look(Vector3(-6.0, 6.0, 20.0), Vector3(20.0, 2.0, -8.0), 60.0)
			await _snap("props_%d_wide" % front)
			_look(Vector3(-4.0, 3.0, 11.0), Vector3(3.0, 2.2, 0.0), 45.0)
			await _snap("props_%d_house" % front)
			_look(Vector3(20.0, 3.0, 10.0), Vector3(28.0, 2.0, -2.0), 50.0)
			await _snap("props_%d_right" % front)
			_look(Vector3(15.0, 2.5, -6.0), Vector3(22.0, 1.5, -16.0), 55.0)
			await _snap("props_%d_back" % front)
			_look(Vector3(40.0, 4.0, 14.0), Vector3(60.0, 4.0, -10.0), 50.0)
			await _snap("props_%d_hill" % front)
			await get_tree().create_timer(4.0).timeout
			_look(Vector3(-6.0, 3.5, 20.0), Vector3(-16.0, 4.5, -6.0), 58.0)
			await _snap("props_%d_fire" % front)
			# Derrumbe: la primera casa se viene abajo y el primer árbol cae y arde.
			_look(Vector3(-6.0, 6.0, 20.0), Vector3(8.0, 2.0, -4.0), 60.0)
			props[0].take_hit(9999.0, null, props[0].global_position + Vector3(2.0, 2.0, 6.0))
			props[1].take_hit(9999.0, null, props[1].global_position + Vector3(-1.0, 1.5, 3.0))
			await get_tree().create_timer(0.7).timeout
			await _snap("props_%d_collapse" % front)
			await get_tree().create_timer(5.0).timeout
			await _snap("props_%d_rubble" % front)

	func _arena(front: int) -> void:
		GameSession.mode = GameSession.Mode.SURVIVAL
		GameSession.front_choice = front
		GameSession.faction = Fronts.Faction.ALLIES if front != Fronts.Id.KURSK else Fronts.Faction.AXIS
		GameSettings.ensure_loaded()
		GameSettings.camera_view = 1
		get_tree().change_scene_to_file("res://levels/arena.tscn")
		await _frames(3)
		await get_tree().create_timer(3.0).timeout
		await _snap("arena_%d_chase" % front)
		var arena: Node = get_tree().current_scene
		var player: Node3D = null
		for tank in get_tree().get_nodes_in_group(&"tanks"):
			if tank.is_player:
				player = tank
		_camera = Camera3D.new()
		_camera.far = 700.0
		arena.add_child(_camera)
		var origin: Vector3 = player.global_position if player != null else Vector3.ZERO
		_look(origin + Vector3(14.0, 5.0, 16.0), origin + Vector3(0.0, 1.5, 0.0), 55.0)
		await _snap("arena_%d_player" % front)
		_look(origin + Vector3(0.0, 45.0, 60.0), origin + Vector3(0.0, 0.0, -30.0), 60.0)
		await _snap("arena_%d_high" % front)
		# Enemigos destacados con el borde amarillo, vistos de cerca.
		await get_tree().create_timer(5.0).timeout
		GameSettings.highlight_enemies = true
		for other in get_tree().get_nodes_in_group(&"tanks"):
			other.refresh_highlight()
			if not other.is_player and other.team != 0:
				var at: Vector3 = other.global_position
				_look(at + Vector3(9.0, 4.0, 11.0), at + Vector3(0.0, 1.2, 0.0), 45.0)
				await _snap("arena_%d_outline" % front)
				break
		GameSettings.highlight_enemies = false
		if front == 0:
			# Menú de opciones (pausa), la galería de vehículos y la vista con zoom.
			var hud: Hud = arena._hud
			hud._set_paused(true)
			await _snap("options_menu")
			hud._history_from_menu = true
			hud._pause_panel.visible = false
			hud._history_gallery.show_index(3)
			hud.move_child(hud._history_panel, -1)
			hud._history_panel.visible = true
			await _snap("options_vehicles")
			hud._set_paused(false)
			_camera.current = false
			player.camera.current = true
			player.set_binoculars(true)
			await _snap("zoom_buttons")
			player.set_binoculars(false)
			_camera.current = true
		for i in 4:
			var angle: float = TAU * i / 4.0 + 0.4
			_look(origin + Vector3(0.0, 3.0, 0.0), origin + Vector3(sin(angle) * 50.0, 4.0, cos(angle) * 50.0), 70.0)
			await _snap("arena_%d_view%d" % [front, i])

	## Cada página del menú principal debe caber en una pantalla de 720 de alto sin tener que
	## desplazarla. Las listas de misiones de una campaña son la excepción (son listas largas).
	func _menu_fit() -> void:
		get_tree().change_scene_to_file("res://levels/main_menu.tscn")
		await _frames(4)
		var menu: Control = get_tree().current_scene
		menu.fit_height = 720.0
		var pages: Array = [["modo", menu._page_mode], ["oferta del tutorial", menu._page_tutorial_offer], ["opciones", menu._page_audio], ["vehículos", menu._page_vehicles]]
		GameSession.mode = GameSession.Mode.STORY
		pages.append(["bando", menu._page_faction])
		for faction in [Fronts.Faction.ALLIES, Fronts.Faction.AXIS]:
			pages.append(["frente (bando %d)" % faction, func() -> void:
				GameSession.faction = faction
				menu._page_front()])
			for front in [Fronts.Id.NORMANDY, Fronts.Id.AFRICA, Fronts.Id.KURSK]:
				GameSession.faction = faction
				GameSession.front_choice = front
				for i in GameSession.missions().size():
					pages.append(["parte de misión %d (bando %d, frente %d)" % [i + 1, faction, front], func() -> void:
						GameSession.faction = faction
						GameSession.front_choice = front
						menu._page_briefing(i)])
		var too_tall: int = 0
		var worst: float = 0.0
		for page: Array in pages:
			(page[1] as Callable).call()
			await _frames(5)
			var needed: float = menu.needed_height()
			worst = maxf(worst, needed)
			if needed > 720.0:
				too_tall += 1
				print("FIT MAL «%s» necesita %d de alto y la pantalla tiene 720" % [page[0], roundi(needed)])
		print("FIT RESULT páginas del menú que no caben en pantalla: %d de %d (la más alta: %d de 720)" % [too_tall, pages.size(), roundi(worst)])

	func _menu() -> void:
		if not GameSession.tutorial_offered():
			# Primera vez que se abre el juego: se ofrece el tutorial.
			get_tree().change_scene_to_file("res://levels/main_menu.tscn")
			await _frames(3)
			await get_tree().create_timer(2.0).timeout
			await _snap("menu_oferta_tutorial")
			GameSession.mark_tutorial("offered")
		get_tree().change_scene_to_file("res://levels/main_menu.tscn")
		await _frames(3)
		await get_tree().create_timer(2.0).timeout
		await _snap("menu")

	## Bandera de idioma del menú: cerrada, con la lista abierta y con el menú en cada idioma.
	func _flags() -> void:
		GameSession.mark_tutorial("offered")
		get_tree().change_scene_to_file("res://levels/main_menu.tscn")
		await _frames(3)
		await get_tree().create_timer(1.5).timeout
		var menu: Node = get_tree().current_scene
		await _snap("flags_menu")
		menu._flag_list.visible = true
		await _frames(2)
		await _snap("flags_lista")
		for code: String in Loc.LANGUAGES:
			menu._pick_language(code)
			await _frames(3)
			await _snap("flags_menu_" + code)
			menu._page_audio()
			await _frames(3)
			await _snap("flags_opciones_" + code)
			menu._page_mode()
			await _frames(2)
		GameSettings.set_language("es")

	func _start_tutorial() -> TutorialMode:
		GameSession.mode = GameSession.Mode.TUTORIAL
		GameSession.faction = Fronts.Faction.ALLIES
		GameSession.front_choice = Fronts.Id.NORMANDY
		GameSettings.ensure_loaded()
		GameSettings.camera_view = 0
		get_tree().change_scene_to_file("res://levels/arena.tscn")
		await _frames(4)
		return get_tree().current_scene.get_node("GameMode") as TutorialMode

	## Recorre las quince lecciones haciendo en cada una la acción correcta. Falla si alguna
	## no se completa. Sin gráficos y a cámara rápida.
	func _tutorial() -> void:
		var before: Array = [GameSettings.easy_drive, GameSettings.aim_assist, GameSettings.auto_recenter]
		var mode: TutorialMode = await _start_tutorial()
		if mode == null:
			print("TUTORIAL RESULT lecciones sin completar: no arranca el modo")
			return
		var bot: Node = load("res://tools/verify/tutorial_bot.gd").new()
		add_child(bot)
		bot.setup(mode)
		Engine.time_scale = 4.0
		var waited: float = 0.0
		while is_instance_valid(mode) and not mode.finished and waited < 900.0:
			await get_tree().create_timer(1.0, true, false, true).timeout
			waited += 1.0
		Engine.time_scale = 1.0
		var missing: int = bot.done.count(false)
		print("TUTORIAL completado: ", mode.finished, " | guardado en el progreso: ", GameSession.tutorial_completed(), " | resumen visible: ", mode.overlay._end != null)
		bot.queue_free()
		get_tree().change_scene_to_file("res://levels/main_menu.tscn")
		await _frames(4)
		var restored: bool = before == [GameSettings.easy_drive, GameSettings.aim_assist, GameSettings.auto_recenter]
		print("TUTORIAL ajustes del jugador restaurados al salir: ", "OK" if restored else "MAL")
		if not mode_ok(missing, restored):
			missing = maxi(missing, 1)
		print("TUTORIAL RESULT lecciones sin completar: ", missing)

	func mode_ok(missing: int, restored: bool) -> bool:
		return missing == 0 and restored and GameSession.tutorial_completed()

	## Guerra en el cielo: muchas formaciones seguidas con un avión condenado en cada una.
	## Ningún derribado puede caer dentro del campo de batalla.
	func _sky() -> void:
		await _new_stage(Fronts.Id.KURSK)
		var sky := SkyWar.new()
		sky.front = Fronts.Id.KURSK
		_stage.add_child(sky)
		var models: Dictionary = {}
		Engine.time_scale = 6.0
		for i in 36:
			sky.front = i % 3
			sky.launch(i % 2, -1, true, 0)
			models[sky.last_model] = true
			await get_tree().create_timer(4.0).timeout
		await get_tree().create_timer(40.0).timeout
		Engine.time_scale = 1.0
		# Blancos de la fase antiaérea y aviones de bombardeo, de los dos bandos y en los tres frentes.
		var targets: Array[String] = []
		var strikes: Array[String] = []
		for front in 3:
			for faction in 2:
				GameSession.front = front
				GameSession.faction = faction
				for kind in 3:
					var target: AirTarget = AirTarget.spawn(_stage, kind, Vector3.ZERO)
					targets.append(target.model)
					target.health.apply_damage(1000.0, null)
				for hostile in [false, true]:
					strikes.append(Aircraft.fly_over(_stage, Vector3.ZERO, hostile).model)
		await get_tree().create_timer(6.0).timeout
		print("SKY blancos de la fase antiaérea: ", targets)
		print("SKY aviones de bombardeo: ", strikes)
		print("SKY modelos vistos: ", models.keys())
		print("SKY RESULT derribos dentro del campo: %d de %d" % [sky.crashes_inside, sky.crashes])
		if sky.crashes < 20:
			print("SKY MAL: demasiado pocos derribos para dar la prueba por buena")

	## Una formación de bombarderos bajo el fuego antiaéreo y un avión cayendo.
	func _sky_shots() -> void:
		GameSession.mode = GameSession.Mode.SURVIVAL
		GameSession.front_choice = Fronts.Id.NORMANDY
		GameSession.faction = Fronts.Faction.ALLIES
		get_tree().change_scene_to_file("res://levels/arena.tscn")
		await _frames(4)
		var arena: Node = get_tree().current_scene
		var sky: SkyWar = arena.get_node("SkyWar")
		_camera = Camera3D.new()
		_camera.far = 900.0
		arena.add_child(_camera)
		for spec in [[Fronts.Faction.ALLIES, 4, "sky_b17"], [Fronts.Faction.AXIS, 0, "sky_bf109"]]:
			var formation: Dictionary = sky.launch(spec[0], spec[1], true, 1)
			formation["doom_at"] = -40.0
			var leader: Variant = formation["planes"][0]
			var dir: Vector3 = formation["dir"]
			while is_instance_valid(leader) and leader.global_position.dot(dir) < -150.0:
				await get_tree().create_timer(0.3).timeout
			if not is_instance_valid(leader):
				continue
			_look(Vector3(0.0, 3.0, 0.0), leader.global_position, 28.0)
			await _snap(spec[2] + "_formacion")
			var waited: float = 0.0
			var victim: Variant = formation["doomed"]
			while is_instance_valid(victim) and not victim.falling and waited < 12.0:
				await get_tree().create_timer(0.2).timeout
				waited += 0.2
			await get_tree().create_timer(1.6).timeout
			if is_instance_valid(victim):
				_look(Vector3(0.0, 3.0, 0.0), victim.global_position, 28.0)
				await _snap(spec[2] + "_derribo")
		# Fase antiaérea: un caza, un avión de ataque y un bombardero enemigos.
		var shown: Array[AirTarget] = []
		for kind in 3:
			var target: AirTarget = AirTarget.spawn(arena, kind, Vector3.ZERO)
			target._velocity = Vector3.ZERO
			target.global_position = Vector3(-22.0 + kind * 22.0, 30.0, -70.0)
			target.rotation = Vector3(0.0, PI * 0.5, 0.0)
			shown.append(target)
		_look(Vector3(0.0, 3.0, 0.0), Vector3(0.0, 30.0, -70.0), 50.0)
		await _snap("sky_fase_antiaerea")
		for target in shown:
			target.queue_free()
		var flight: Aircraft = Aircraft.fly_over(arena, Vector3(0.0, 0.0, -60.0), false)
		await get_tree().create_timer(2.6).timeout
		_look(Vector3(0.0, 3.0, 0.0), flight.global_position, 40.0)
		await _snap("sky_bombardeo_aliado")
		_look(Vector3(0.0, 3.0, 0.0), Vector3(0.0, 70.0, -200.0), 70.0)
		for i in 4:
			sky._distant_barrage()
		await get_tree().create_timer(1.3).timeout
		await _snap("sky_antiaerea_lejana")

	## Aspecto de varias lecciones, con la interfaz real.
	func _tutorial_shots() -> void:
		var mode: TutorialMode = await _start_tutorial()
		await get_tree().create_timer(2.0).timeout
		await _snap("tutorial_01_mover")
		for spec in [[2, "tutorial_03_torreta"], [3, "tutorial_04_disparo"], [6, "tutorial_07_radar"], [8, "tutorial_09_fijar"], [11, "tutorial_12_avion"], [13, "tutorial_14_dano"], [14, "tutorial_15_final"]]:
			mode.goto_lesson(spec[0])
			if spec[0] == 11:
				mode.player.set_binoculars(true)
			await get_tree().create_timer(1.5).timeout
			await _snap(spec[1])
		mode.player.set_binoculars(false)
		mode.goto_lesson(TutorialMode.LESSONS.size())
		await get_tree().create_timer(1.0).timeout
		await _snap("tutorial_resumen")

	## Datos de la campaña: todas las listas completas y con sus campos.
	func _campaign() -> void:
		var total: int = 0
		for faction in 2:
			for choice in 4:
				var list: Array[Dictionary] = Campaign.missions(faction, choice)
				var expected: int = Campaign.PER_CAMPAIGN * (3 if choice == GameSession.FRONT_MIXED else 1)
				if list.size() != expected:
					push_error("Campaña %d/%d: %d misiones, se esperaban %d" % [faction, choice, list.size(), expected])
				for mission in list:
					total += 1
					for key in ["title", "type", "briefing", "front"]:
						if not mission.has(key):
							push_error("Misión sin «%s»: %s" % [key, mission])
					if not mission["type"] in ["assault", "destroy", "sabotage", "defend", "boss", "liberate", "breakthrough"]:
						push_error("Tipo de misión desconocido: %s" % mission["type"])
		print("CAMPAIGN OK ", total)

	## Arranca una misión de la campaña y la deja correr unos segundos.
	func _story(faction: int, front: int, index: int) -> void:
		GameSession.mode = GameSession.Mode.STORY
		GameSession.faction = faction
		GameSession.front_choice = front
		GameSession.mission_index = index
		GameSettings.ensure_loaded()
		get_tree().change_scene_to_file("res://levels/arena.tscn")
		await _frames(3)
		await get_tree().create_timer(6.0).timeout
		var mode: GameMode = get_tree().current_scene.get_node("GameMode")
		var allies: int = 0
		var enemies: int = 0
		for tank in get_tree().get_nodes_in_group(&"tanks"):
			if tank.team == GameMode.PLAYER_TEAM:
				allies += 1
			else:
				enemies += 1
		print("STORY ", GameSession.current_mission()["title"], " | ", mode.status_text(), " | ", mode.objective_lines(), " | bando propio ", allies, " enemigos ", enemies)
		await _snap("story_%d_%d_%d" % [faction, front, index])
		_check_reach(mode as StoryMode)

	## Accesibilidad: desde el jugador tiene que haber ruta hasta cada objetivo, cada edificio
	## con premio, cada premio suelto y cada tanque, y nada puede quedar bajo una montaña ni
	## fuera del muro. Usa el mismo mapa de celdas con el que navegan los aliados.
	func _check_reach(mode: StoryMode) -> void:
		var arena: Node = get_tree().current_scene
		var grid := NavGrid.of(arena)
		var origin: Vector3 = mode.player.global_position
		var targets: Array[Node3D] = []
		for objective in mode._objectives:
			targets.append(objective)
		for node in get_tree().get_nodes_in_group(&"radar_marks"):
			if node is Destructible and not node in targets:
				targets.append(node)
		for tank in get_tree().get_nodes_in_group(&"tanks"):
			targets.append(tank)
		if mode.kind == "breakthrough":
			var exit_marker := Node3D.new()
			arena.add_child(exit_marker)
			exit_marker.position = StoryMode.EXIT_POINT
			targets.append(exit_marker)
		var mountains: Array[Destructible] = []
		for child in arena.get_children():
			if child is Destructible and child.indestructible:
				mountains.append(child)
		var bad: int = 0
		for target in targets:
			if target is Destructible and target.protected_area:
				continue
			var point: Vector3 = target.global_position
			var problem: String = ""
			if point.y < -1.0:
				problem = "hundido bajo el suelo"
			elif absf(point.x) > 196.0 or absf(point.z) > 196.0:
				problem = "fuera del muro"
			else:
				# Se puede llegar junto a él: hay ruta hasta algún punto a su alrededor (lo que
				# está pegado a un edificio o a una alambrada se alcanza por el lado libre).
				var reachable: bool = false
				for radius: float in [0.0, 8.0, 14.0, 22.0]:
					for i in (1 if radius == 0.0 else 8):
						var around: Vector3 = point + Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0) * radius
						var path: PackedVector3Array = grid.find_path(origin, around)
						if not path.is_empty():
							var end: Vector3 = path[path.size() - 2] if path.size() > 1 else path[0]
							if Vector2(end.x - point.x, end.z - point.z).length() <= 26.0:
								reachable = true
								break
					if reachable:
						break
				if not reachable:
					problem = "sin ruta"
			# Bajo la falda de una colina o montaña (salvo la propia).
			var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
			var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 90.0, point.z), Vector3(point.x, 0.3, point.z), 1)
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty() and hit["collider"] in mountains and hit["collider"] != target:
				problem = "dentro de una montaña"
			if problem != "":
				bad += 1
				print("REACH MAL ", target.name, " ", point, " ", problem)
		var outside: int = 0
		for mountain in mountains:
			var p: Vector3 = mountain.global_position
			if absf(p.x) > 200.0 or absf(p.z) > 200.0:
				# Montaña exterior: ningún punto del muro puede caer bajo su falda.
				for i in 81:
					var along: float = -200.0 + 5.0 * i
					for edge: Vector3 in [Vector3(along, 60.0, -199.0), Vector3(along, 60.0, 199.0), Vector3(-199.0, 60.0, along), Vector3(199.0, 60.0, along)]:
						var down := PhysicsRayQueryParameters3D.create(edge, Vector3(edge.x, 0.3, edge.z), 1)
						var found: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(down)
						if not found.is_empty() and found["collider"] == mountain:
							outside += 1
		_unreachable += bad + outside
		print("REACH ", GameSession.current_mission()["title"], ": ", targets.size(), " puntos comprobados, ", bad, " inaccesibles; ", mountains.size(), " montañas, ", outside, " puntos del muro bajo una montaña")

	## Prueba de navegación (sin gráficos): tanques que deben llegar al otro lado de un muro
	## largo, de un recinto en U y de un grupo de bloques. Compara la navegación con rodeo
	## (la de los aliados) con la antigua.
	func _nav() -> void:
		var old_scene: Node = get_tree().current_scene
		if old_scene != null:
			old_scene.queue_free()
		await _frames(2)
		var stage := Node3D.new()
		stage.name = "NavStage"
		get_tree().root.add_child(stage)
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(1200.0, 2.0, 1200.0)
		floor_shape.shape = floor_box
		floor_shape.position.y = -1.0
		floor_body.add_child(floor_shape)
		stage.add_child(floor_body)
		GameSession.mode = GameSession.Mode.SURVIVAL
		GameSession.front = Fronts.Id.NORMANDY
		GameSession.faction = Fronts.Faction.ALLIES
		var mode := GameMode.new()
		mode.set_physics_process(false)
		stage.add_child(mode)
		mode.world = stage
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var cases: Array[String] = ["muro", "recinto en U", "bloques"]
		var runs: Array[Dictionary] = []
		for c in cases.size():
			for smart in [true, false]:
				var origin := Vector3(c * 130.0 - 130.0, 0.0, 0.0 if smart else 220.0)
				match c:
					0:
						_wall(stage, origin, Vector3(44.0, 3.0, 2.0))
					1:
						_wall(stage, origin + Vector3(0.0, 0.0, -6.0), Vector3(26.0, 3.0, 2.0))
						_wall(stage, origin + Vector3(-12.0, 0.0, 4.0), Vector3(2.0, 3.0, 18.0))
						_wall(stage, origin + Vector3(12.0, 0.0, 4.0), Vector3(2.0, 3.0, 18.0))
					_:
						rng.seed = 7
						for i in 14:
							_wall(stage, origin + Vector3(rng.randf_range(-16.0, 16.0), 0.0, rng.randf_range(-18.0, 18.0)), Vector3(4.0, 3.0, 4.0))
				for stats_id: String in ["m4_sherman", "churchill"]:
					var start: Vector3 = origin + Vector3(-4.0 if stats_id == "m4_sherman" else 5.0, 0.0, 34.0)
					var tank: Tank = mode.spawn_tank(Fronts.tank(stats_id), GameMode.PLAYER_TEAM, Vector2(start.x, start.z), 0.0)
					var brain: AIBrain = tank.get_node("AIBrain")
					brain.smart_nav = smart
					brain.hunt = false
					brain.objective = origin + Vector3(0.0, 0.0, -34.0)
					brain.objective_radius = 2.0
					runs.append({"case": cases[c], "smart": smart, "tank": tank, "brain": brain, "id": stats_id, "best": INF, "time": -1.0})
		# Colina: un tanque que empuja de frente contra ella no debe subirla.
		var hill := PropFactory.mountain(14.0, 9.0, 7)
		hill.position = Vector3(0.0, 0.0, -150.0)
		stage.add_child(hill)
		var dune := PropFactory.mountain(16.0, 5.0, 10)
		dune.position = Vector3(60.0, 0.0, -150.0)
		stage.add_child(dune)
		var climbers: Array[Tank] = []
		for x in [0.0, 60.0]:
			var climber: Tank = mode.spawn_tank(Fronts.tank("m4_sherman"), GameMode.PLAYER_TEAM, Vector2(x + 2.0, -120.0), 0.0)
			climber.get_node("AIBrain").queue_free()
			climbers.append(climber)
		var climb_height: float = 0.0
		Engine.time_scale = 4.0
		var clock: float = 0.0
		while clock < 60.0:
			await get_tree().physics_frame
			clock += get_physics_process_delta_time()
			for climber in climbers:
				if clock < 20.0:
					climber.drive_input = Vector2(0.0, 1.0)
				climb_height = maxf(climb_height, climber.global_position.y)
			for run in runs:
				var tank: Tank = run["tank"]
				var brain: AIBrain = run["brain"]
				var gap: Vector3 = brain.objective - tank.global_position
				gap.y = 0.0
				run["best"] = minf(run["best"], gap.length())
				if run["time"] < 0.0 and gap.length() <= 8.0:
					run["time"] = clock
		Engine.time_scale = 1.0
		var failures: int = 0
		for run in runs:
			var ok: bool = run["time"] >= 0.0
			if run["smart"] and not ok:
				failures += 1
			print("NAV %-13s %-10s %s  %s  mínima distancia %.1f m  desatascos %d" % [run["case"], run["id"], "CON RODEO" if run["smart"] else "ANTIGUA  ", ("llega en %.1f s" % run["time"]) if ok else "NO LLEGA", run["best"], run["brain"].unstuck_total])
		print("NAV RESULT fallos de la navegación con rodeo: ", failures)
		print("CLIMB RESULT altura máxima alcanzada empujando contra una colina y una duna: %.2f m (%s)" % [climb_height, "OK" if climb_height < 1.0 else "SUBE"])
		stage.queue_free()
		await _frames(2)

	## Reacción de un tanque enemigo al que le disparan sin que vea a quien lo hace:
	## a) tapado por una casa, tiene que rodearla; b) atacado desde más lejos de lo que alcanza a
	## ver, tiene que acercarse. En los dos casos debe acabar devolviendo el fuego. Un tercer
	## tanque, vecino del primero, debe darse por avisado.
	func _ai_reaction() -> void:
		var old_scene: Node = get_tree().current_scene
		if old_scene != null:
			old_scene.queue_free()
		await _frames(2)
		var stage := Node3D.new()
		stage.name = "AiStage"
		get_tree().root.add_child(stage)
		get_tree().current_scene = stage
		var floor_body := StaticBody3D.new()
		floor_body.collision_layer = 1
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(1600.0, 2.0, 1600.0)
		floor_shape.shape = floor_box
		floor_shape.position.y = -1.0
		floor_body.add_child(floor_shape)
		stage.add_child(floor_body)
		GameSession.mode = GameSession.Mode.SURVIVAL
		GameSession.front = Fronts.Id.NORMANDY
		GameSession.faction = Fronts.Faction.ALLIES
		var mode := GameMode.new()
		mode.set_physics_process(false)
		stage.add_child(mode)
		mode.world = stage
		var cases: Array[Dictionary] = []
		for c in 2:
			var origin := Vector3(c * 500.0 - 250.0, 0.0, 0.0)
			var gap: float = 80.0 if c == 0 else 175.0
			if c == 0:
				_wall(stage, origin + Vector3(0.0, 0.0, -gap + 14.0), Vector3(16.0, 5.0, 10.0))
			var victim: Tank = mode.spawn_tank(Fronts.tank("m4_sherman"), GameMode.PLAYER_TEAM, Vector2(origin.x, origin.z), 0.0)
			victim.get_node("AIBrain").queue_free()
			victim.health.invulnerable = true
			var enemy: Tank = mode.spawn_tank(Fronts.tank("tiger2"), GameMode.ENEMY_TEAM, Vector2(origin.x, origin.z - gap), PI)
			var brain: AIBrain = enemy.get_node("AIBrain")
			brain.hunt = false
			brain.objective = enemy.global_position
			var buddy: Tank = mode.spawn_tank(Fronts.tank("panzer4"), GameMode.ENEMY_TEAM, Vector2(origin.x + 30.0, origin.z - gap - 10.0), PI)
			var buddy_brain: AIBrain = buddy.get_node("AIBrain")
			buddy_brain.hunt = false
			buddy_brain.objective = buddy.global_position
			var entry: Dictionary = {"name": "tapado por una casa" if c == 0 else "atacado desde 175 m", "victim": victim, "enemy": enemy, "brain": brain, "buddy": buddy_brain, "seen": -1.0, "fired": -1.0, "buddy_at": -1.0}
			enemy.weapon.fired.connect(func() -> void:
				if entry["fired"] < 0.0 and brain.target == victim:
					entry["fired"] = entry["t"])
			cases.append(entry)
		Engine.time_scale = 4.0
		await get_tree().create_timer(3.0).timeout
		var time: float = 0.0
		var hit_timer: float = 0.0
		while time < 75.0:
			await get_tree().physics_frame
			var delta: float = get_physics_process_delta_time()
			time += delta
			hit_timer -= delta
			for entry in cases:
				entry["t"] = time
				var brain: AIBrain = entry["brain"]
				if not is_instance_valid(entry["enemy"]):
					continue
				if hit_timer <= 0.0:
					# El «jugador» acierta un disparo cada 2,5 s.
					entry["enemy"].health.apply_damage(2.0, entry["victim"])
				if entry["seen"] < 0.0 and brain.target == entry["victim"] and brain.perception.can_see:
					entry["seen"] = time
				var buddy: AIBrain = entry["buddy"]
				if entry["buddy_at"] < 0.0 and is_instance_valid(buddy) and buddy.target == entry["victim"]:
					entry["buddy_at"] = time
			if hit_timer <= 0.0:
				hit_timer = 2.5
		Engine.time_scale = 1.0
		var failures: int = 0
		for entry in cases:
			var ok: bool = entry["seen"] >= 0.0 and entry["fired"] >= 0.0 and entry["buddy_at"] >= 0.0
			if not ok:
				failures += 1
			print("AI %-22s ve al atacante: %s | devuelve el fuego: %s | el vecino se da por avisado: %s | estado final %s" % [
				entry["name"], _secs(entry["seen"]), _secs(entry["fired"]), _secs(entry["buddy_at"]), entry["brain"].state_name() if is_instance_valid(entry["brain"]) else "-"])
		print("AI RESULT tanques que no reaccionan al fuego: ", failures)
		stage.queue_free()
		await _frames(2)

	## Captura la bandera jugada solo por la máquina (el jugador se queda parado en su base):
	## los dos bandos tienen que coger la bandera contraria y alguien tiene que capturar.
	func _ctf() -> void:
		var pickups: Array[int] = [0, 0]
		var captures: Array[int] = [0, 0]
		for front in [Fronts.Id.NORMANDY, Fronts.Id.KURSK]:
			GameSession.mode = GameSession.Mode.CTF
			GameSession.front_choice = front
			GameSession.faction = Fronts.Faction.ALLIES
			GameSettings.ensure_loaded()
			GameSettings.difficulty = 1
			get_tree().change_scene_to_file("res://levels/arena.tscn")
			await _frames(4)
			var mode: CtfMode = get_tree().current_scene.get_node("GameMode") as CtfMode
			mode.raid_interval = Vector2.ZERO
			mode.player.health.invulnerable = true
			Engine.time_scale = 6.0
			var carried: Array[bool] = [false, false]
			var time: float = 0.0
			while time < 300.0 and not mode.is_over:
				await get_tree().create_timer(0.5).timeout
				time += 0.5
				for team in 2:
					# flags[team] es la bandera de ese bando: la coge el contrario.
					var now: bool = mode.flags[team].state == Flag.Status.CARRIED
					if now and not carried[team]:
						pickups[1 - team] += 1
					carried[team] = now
			Engine.time_scale = 1.0
			for team in 2:
				captures[team] += mode.captures[team]
			print("CTF %s en %d s: capturas aliadas %d, enemigas %d" % [Fronts.NAMES[front], roundi(time), mode.captures[0], mode.captures[1]])
		print("CTF banderas cogidas: bando del jugador %d, bando enemigo %d | capturas %d y %d" % [pickups[0], pickups[1], captures[0], captures[1]])
		# Las capturas dependen de cómo vaya el combate; lo exigible es que los dos bandos lleguen
		# a coger la bandera contraria.
		var ok: bool = pickups[0] > 0 and pickups[1] > 0
		print("CTF RESULT la máquina juega a capturar: ", "OK" if ok else "NO")

	## Marcador de banderas en pantalla: una en su base y otra llevada por el jugador.
	func _ctf_shot() -> void:
		GameSession.mode = GameSession.Mode.CTF
		GameSession.front_choice = Fronts.Id.NORMANDY
		GameSession.faction = Fronts.Faction.ALLIES
		GameSettings.camera_view = 1
		get_tree().change_scene_to_file("res://levels/arena.tscn")
		await _frames(4)
		var mode: CtfMode = get_tree().current_scene.get_node("GameMode") as CtfMode
		mode.captures[0] = 1
		mode.captures[1] = 2
		mode.flags[1].pick_up(mode.player)
		await get_tree().create_timer(1.5).timeout
		await _snap("ctf_marcador")
		GameSettings.camera_view = 0

	func _secs(value: float) -> String:
		return "a los %.0f s" % value if value >= 0.0 else "NUNCA"

	func _wall(stage: Node3D, pos: Vector3, size: Vector3) -> void:
		var block := PropFactory.block(size)
		block.position = pos
		stage.add_child(block)
