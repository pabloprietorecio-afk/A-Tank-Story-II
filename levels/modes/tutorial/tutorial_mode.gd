class_name TutorialMode
extends GameMode
## Tutorial jugable: un campo de prácticas pequeño y despejado, sin refuerzos ni bombardeos
## por sorpresa, que enseña los controles lección a lección. Cada lección pide una acción real
## con los controles de siempre (Hud, TouchControls, Radar): aquí solo se colocan los blancos,
## se comprueba que el jugador lo ha hecho y se pasa a la siguiente.

signal lesson_completed(index: int, skipped: bool)

## Medio lado del campo de prácticas (la arena normal mide 200).
const FIELD: float = 100.0
## Segundos sin lograrlo antes de dar la pista detallada.
const HINT_TIME: float = 20.0

const LESSONS: Array[String] = [
	"move", "turn", "turret", "fire", "easy", "camera", "radar", "enemy",
	"assist", "zoom", "missile", "strike", "raid", "damage", "follow", "focus", "final",
]

## Pasos de cada lección: locución (id), instrucción, pista detallada y qué se resalta.
const STEPS: Dictionary = {
	"move": [
		{"id": "move_a", "show": ["stick"],
			"text": "JOYSTICK: TOCA EL LADO IZQUIERDO Y EMPUJA HACIA ARRIBA.\nAVANZA HASTA LA BALIZA AMARILLA",
			"hint": "PON EL PULGAR EN LA MITAD IZQUIERDA DE LA PANTALLA\nY DESLÍZALO HACIA ARRIBA SIN SOLTAR"},
		{"id": "move_b", "show": ["stick"],
			"text": "AHORA MARCHA ATRÁS: TIRA DEL JOYSTICK HACIA ABAJO\nY RETROCEDE UNOS METROS",
			"hint": "DESLIZA EL PULGAR IZQUIERDO HACIA ABAJO Y MANTENLO\nHASTA QUE EL TANQUE RETROCEDA"},
	],
	"turn": [
		{"id": "turn", "show": ["stick"],
			"text": "GIRA EL CASCO MOVIENDO EL JOYSTICK A IZQUIERDA O DERECHA.\nPASA POR LAS TRES BALIZAS EN ZIGZAG",
			"hint": "EMPUJA ARRIBA Y UN POCO HACIA UN LADO PARA AVANZAR GIRANDO.\nVE A LA BALIZA AMARILLA; LAS GRISES VIENEN DESPUÉS"},
	],
	"turret": [
		{"id": "turret", "show": ["look"],
			"text": "TORRETA: ARRASTRA EL DEDO POR LA MITAD DERECHA.\nPON LA MIRA SOBRE LAS TRES DIANAS",
			"hint": "DESLIZA EL PULGAR DERECHO A LOS LADOS: EL CAÑÓN GIRA.\nMANTÉN LA MIRA UN MOMENTO SOBRE CADA DIANA"},
	],
	"fire": [
		{"id": "fire_a", "show": ["fire"],
			"text": "APUNTA A UNA DIANA Y PULSA FIRE PARA DISPARAR",
			"hint": "FIRE ES EL CÍRCULO NARANJA DE ABAJO A LA DERECHA.\nPON ANTES LA MIRA SOBRE LA DIANA"},
		{"id": "fire_b", "show": ["reload"],
			"text": "RECARGANDO: LA BARRA BAJO LA MIRA SE LLENA.\nCUANDO ESTÉ VERDE, DISPARA HASTA DESTRUIR UNA DIANA",
			"hint": "NO SE PUEDE DISPARAR HASTA QUE LA BARRA SE LLENE.\nAPUNTA AL CENTRO DE LA DIANA Y PULSA FIRE"},
	],
	"easy": [
		{"id": "easy_a", "show": ["look"],
			"text": "MOVIMIENTO FÁCIL: AL AVANZAR, EL CASCO SIGUE AL CAÑÓN.\nAPUNTA A LA BALIZA Y EMPUJA SOLO HACIA DELANTE",
			"hint": "GIRA LA TORRETA HACIA LA BALIZA CON EL PULGAR DERECHO\nY EMPUJA EL JOYSTICK RECTO HACIA ARRIBA"},
		{"id": "easy_b", "show": ["gear"],
			"text": "SE DESACTIVA EN ⚙ → MOVIMIENTO FÁCIL.\nVE DEL MISMO MODO HASTA LA SEGUNDA BALIZA",
			"hint": "APUNTA EL CAÑÓN A LA BALIZA Y EMPUJA HACIA ARRIBA:\nEL TANQUE GIRA SOLO HACIA DONDE APUNTAS"},
	],
	"camera": [
		{"id": "camera", "show": ["cam"],
			"text": "PULSA CÁM PARA CAMBIAR DE VISTA:\nCABINA, TRASERA Y TRASERA LEJANA",
			"hint": "CÁM ESTÁ ARRIBA A LA DERECHA.\nPÚLSALO TRES VECES PARA VER LAS TRES VISTAS"},
	],
	"radar": [
		{"id": "radar", "show": ["radar"],
			"text": "RADAR. PUNTO: ENEMIGO · CUADRO AZUL: ALIADO · ROMBO: OBJETIVO\nANILLO: EDIFICIO CON PREMIO · CRUZ: PREMIO. VE HASTA EL ROMBO",
			"hint": "ARRIBA EN EL RADAR ES HACIA DONDE APUNTA TU CAÑÓN.\nGIRA HASTA TENER EL ROMBO ARRIBA Y AVANZA"},
	],
	"enemy": [
		{"id": "enemy_a", "show": [],
			"text": "TANQUE ENEMIGO DE PRÁCTICAS, PARADO.\nDESTRÚYELO: HARÁN FALTA VARIOS DISPAROS",
			"hint": "APUNTA AL CASCO, DISPARA Y ESPERA LA RECARGA.\nREPITE HASTA DESTRUIRLO"},
		{"id": "enemy_b", "show": [],
			"text": "AHORA UNO EN MOVIMIENTO.\nAPUNTA UN POCO POR DELANTE Y DESTRÚYELO",
			"hint": "EL PROYECTIL TARDA EN LLEGAR:\nDISPARA HACIA DONDE VA A ESTAR EL TANQUE"},
	],
	"assist": [
		{"id": "assist_a", "show": ["gear"],
			"text": "APUNTADO AUTOMÁTICO: PULSA ⚙, ACTÍVALO\nY PULSA CONTINUAR",
			"hint": "⚙ ESTÁ ARRIBA A LA DERECHA. EN LA LISTA, ACTIVA\n«APUNTADO AUTOMÁTICO» Y PULSA CONTINUAR"},
		{"id": "assist_b", "show": ["look"],
			"text": "PASA LA MIRA SOBRE EL ENEMIGO:\nSE FIJA SOLO Y LA MIRA SE VUELVE NARANJA",
			"hint": "ACERCA LA MIRA AL TANQUE ENEMIGO.\nSE FIJA A MENOS DE 150 METROS"},
		{"id": "assist_c", "show": ["target_info", "release"],
			"text": "FIJADO: SOBRE LA MIRA VES SU BLINDAJE Y SU ATAQUE.\nPULSA LIBERAR OBJETIVO PARA SOLTARLO",
			"hint": "LIBERAR OBJETIVO ESTÁ ABAJO,\nA LA IZQUIERDA DE FIRE"},
	],
	"zoom": [
		{"id": "zoom_a", "show": ["zoom"],
			"text": "PULSA ZOOM PARA USAR LOS PRISMÁTICOS",
			"hint": "ZOOM ESTÁ ARRIBA, A LA IZQUIERDA DE CÁM"},
		{"id": "zoom_b", "show": ["missile", "strike"],
			"text": "SOLO CON ZOOM APARECEN MISIL Y AVIÓN.\nACIERTA A LA DIANA LEJANA",
			"hint": "CON ZOOM EL DEDO MUEVE LA MIRA MÁS FINO.\nCENTRA LA DIANA Y PULSA FIRE"},
	],
	"missile": [
		{"id": "missile", "show": ["zoom", "missile"],
			"text": "MISIL GUIADO: FIJA AL ENEMIGO CON LA MIRA\nY, CON ZOOM, PULSA MISIL",
			"hint": "PRIMERO PASA LA MIRA SOBRE EL TANQUE HASTA FIJARLO.\nDESPUÉS ZOOM Y EL BOTÓN MISIL, SOBRE FIRE"},
	],
	"strike": [
		{"id": "strike_a", "show": ["zoom", "strike"],
			"text": "BOMBARDEO ALIADO: CON ZOOM, APUNTA AL DEPÓSITO CERCANO\nY PULSA AVIÓN",
			"hint": "EL DEPÓSITO CERCANO ESTÁ JUSTO DELANTE.\nPON LA MIRA SOBRE ÉL, ZOOM Y BOTÓN AVIÓN"},
		{"id": "strike_b", "show": ["strike"],
			"text": "DENEGADO: A MENOS DE 30 M LAS BOMBAS TE ALCANZARÍAN.\nPÍDELO SOBRE EL DEPÓSITO LEJANO",
			"hint": "GIRA HASTA EL DEPÓSITO LEJANO (ROMBO EN EL RADAR),\nAPUNTA A ÉL Y PULSA AVIÓN"},
		{"id": "strike_c", "show": ["strike"],
			"text": "AHORA PÍDELO SOBRE EL DEPÓSITO CERCANO\nY ESCUCHA QUÉ RESPONDE LA BASE",
			"hint": "APUNTA AL DEPÓSITO QUE TIENES AL LADO Y PULSA AVIÓN:\nA MENOS DE 30 M NO LO PERMITEN"},
	],
	"raid": [
		{"id": "raid", "show": [],
			"text": "BOMBARDEO ENEMIGO: CUANDO VEAS LA ZONA ROJA,\nSAL DE ELLA ANTES DE QUE LA CUENTA LLEGUE A CERO",
			"hint": "EMPUJA EL JOYSTICK A FONDO Y NO PARES\nHASTA ESTAR FUERA DEL CÍRCULO ROJO"},
	],
	"damage": [
		{"id": "damage_a", "show": ["armor"],
			"text": "DAÑO: UN ENEMIGO TE VA A DISPARAR.\nMIRA TU BARRA DE BLINDAJE, ABAJO",
			"hint": "ESPERA EL IMPACTO: LA PANTALLA PARPADEA EN ROJO\nY LA BARRA DE BLINDAJE BAJA"},
		{"id": "damage_b", "show": ["armor", "radar"],
			"text": "RECOGE LA CAJA VERDE PASANDO POR ENCIMA:\nREPARA TU BLINDAJE",
			"hint": "LA CAJA ES LA CRUZ VERDE DEL RADAR.\nCONDUCE HASTA TOCARLA"},
		{"id": "damage_c", "show": ["buffs", "radar"],
			"text": "RECOGE LA CAJA AZUL: RECARGA RÁPIDA DURANTE 20 SEGUNDOS.\nEL AVISO SALE SOBRE TU BLINDAJE",
			"hint": "LA CAJA ES LA CRUZ AZUL DEL RADAR.\nCONDUCE HASTA TOCARLA"},
	],
	"follow": [
		{"id": "follow_a", "show": ["follow"],
			"text": "TODOS CONMIGO: PULSA EL ICONO DE LAS TRES FLECHAS\nY TUS ALIADOS TE SEGUIRÁN",
			"hint": "ESTÁ A LA IZQUIERDA DE LA PANTALLA, EL DE ARRIBA.\nPÚLSALO UNA VEZ"},
		{"id": "follow_b", "show": ["radar"],
			"text": "AHORA CONDUCE HASTA LA BALIZA AMARILLA:\nTUS ALIADOS VENDRÁN CONTIGO Y TE ACOMPAÑARÁN",
			"hint": "AVANZA SIN PRISA HASTA LA BALIZA.\nLOS ALIADOS SE QUEDAN CERCA DE TI, VAYAS DONDE VAYAS"},
	],
	"focus": [
		{"id": "focus_a", "show": ["focus"],
			"text": "TODOS AL OBJETIVO: APUNTA AL TANQUE ENEMIGO\nY PULSA EL ICONO DE LA DIANA CON DOS FLECHAS",
			"hint": "PON LA MIRA SOBRE EL TANQUE ENEMIGO. EL ICONO ESTÁ\nA LA IZQUIERDA, DEBAJO DEL DE LAS TRES FLECHAS"},
		{"id": "focus_b", "show": [],
			"text": "TODOS TUS ALIADOS ATACAN LO QUE HAS SEÑALADO.\nESPERA A QUE LO DESTRUYAN",
			"hint": "NO HACE FALTA QUE DISPARES TÚ:\nTUS ALIADOS SE ENCARGAN DEL OBJETIVO"},
	],
	"final": [
		{"id": "final", "show": ["radar"],
			"text": "COMBATE FINAL: CON TUS DOS ALIADOS, DESTRUYE LOS TRES\nTANQUES ENEMIGOS Y EL DEPÓSITO (ROMBO DEL RADAR)",
			"hint": "USA EL RADAR PARA ENCONTRARLOS.\nTIENES CAÑÓN, MISILES Y UN BOMBARDEO ALIADO"},
	],
}

var hud: Hud
var touch: TouchControls
var radar: Radar
var input_source: PlayerInputSource
var overlay: TutorialOverlay

var lesson_index: int = -1
var step: int = 0
var finished: bool = false

## Lo que hay ahora en el campo (lo leen también las pruebas automáticas).
var beacons: Array[PracticeProps.Beacon] = []
var beacon_index: int = 0
var targets: Array[PracticeProps.Target] = []
var enemy: Tank
var depot_near: Destructible
var depot_far: Destructible
var pickup: Pickup
var raid: AirStrike
var allies: Array[Tank] = []
var final_enemies: Array[Tank] = []
var final_objective: Destructible

var _props: Array[Node] = []
var _hint_timer: float = 0.0
var _hint_on: bool = false
var _hint_spoken: bool = false
var _transition: float = 0.0
var _aim_time: Dictionary = {}
var _reverse_distance: float = 0.0
var _shots: int = 0
var _reloaded: bool = false
var _targets_destroyed: int = 0
var _cam_presses: int = 0
var _release_presses: int = 0
var _mover_time: float = 0.0
var _missile_ok: bool = false
var _strike_launched: bool = false
var _denied: bool = false
var _bombed: bool = false
var _raid_delay: float = 0.0
var _raid_judged: bool = false
var _hit: bool = false
var _shoot_delay: float = 0.0
var _picked: int = 0
var _follow_wait: float = 0.0

## Ajustes del jugador antes del tutorial: se restauran al salir.
static var _saved: Dictionary = {}


func _init() -> void:
	super()
	missiles = 0
	strikes = 0
	# Sin bombardeos enemigos por sorpresa: solo el de su lección.
	raid_interval = Vector2.ZERO


func wants_commands() -> bool:
	return lesson_id() in ["follow", "focus", "final"]


func wants_scenery() -> bool:
	return false


func wants_pickups() -> bool:
	return false


func forced_weather() -> int:
	return Weather.Kind.CLEAR


func bind_ui(new_hud: Hud, new_touch: TouchControls, new_radar: Radar, new_input: PlayerInputSource) -> void:
	hud = new_hud
	touch = new_touch
	radar = new_radar
	input_source = new_input


func status_text() -> String:
	return Loc.t("CAMPO DE PRÁCTICAS")


func start(player_tank: Tank, world_root: Node3D) -> void:
	super(player_tank, world_root)
	if _saved.is_empty():
		_saved = {
			"easy_drive": GameSettings.easy_drive, "aim_assist": GameSettings.aim_assist,
			"auto_recenter": GameSettings.auto_recenter, "camera_view": GameSettings.camera_view,
		}
	GameSettings.auto_recenter = false
	PracticeProps.build_fence(world, FIELD)
	player.health.invulnerable = true
	player.health.min_health = 1.0
	player.weapon.fired.connect(func() -> void: _shots += 1)
	player.damaged.connect(func(_amount: float, _source: Node) -> void: _hit = true)
	overlay = TutorialOverlay.new()
	overlay.hud = hud
	overlay.touch = touch
	overlay.radar = radar
	if hud != null:
		var layer: Node = hud.get_parent()
		layer.add_child(overlay)
		# Por debajo del HUD: el menú de opciones y las fichas quedan por encima.
		layer.move_child(overlay, hud.get_index())
		hud.focus_active = true
		(hud.controls["cam"] as Button).pressed.connect(func() -> void: _cam_presses += 1)
		(hud.controls["release"] as Button).pressed.connect(func() -> void: _release_presses += 1)
	else:
		add_child(overlay)
	overlay.skip_pressed.connect(skip_lesson)
	overlay.campaign_pressed.connect(func() -> void:
		GameSession.menu_page = "story"
		_leave("res://levels/main_menu.tscn"))
	overlay.repeat_pressed.connect(func() -> void: _leave(""))
	overlay.menu_pressed.connect(func() -> void: _leave("res://levels/main_menu.tscn"))
	goto_lesson(0)


func _exit_tree() -> void:
	if _saved.is_empty():
		return
	GameSettings.easy_drive = _saved["easy_drive"]
	GameSettings.aim_assist = _saved["aim_assist"]
	GameSettings.auto_recenter = _saved["auto_recenter"]
	GameSettings.camera_view = _saved["camera_view"]
	GameSettings.save()
	_saved = {}


func _leave(scene: String) -> void:
	get_tree().paused = false
	if scene == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(scene)


func lesson_id() -> String:
	return LESSONS[lesson_index] if lesson_index >= 0 and lesson_index < LESSONS.size() else ""


## Empieza la lección indicada (también la usan las pruebas y las capturas).
func goto_lesson(index: int) -> void:
	var keep_targets: bool = index < LESSONS.size() and LESSONS[index] == "fire" and not targets.is_empty()
	_cleanup(keep_targets)
	lesson_index = index
	_transition = 0.0
	if index >= LESSONS.size():
		_finish()
		return
	_prepare(index)
	call("_setup_" + LESSONS[index])
	_enter_step(0)


func skip_lesson() -> void:
	if finished or _transition > 0.0 or lesson_index >= LESSONS.size():
		return
	_complete(true)


func objective_lines() -> Array[String]:
	if lesson_id() != "final":
		return []
	var kills: int = 0
	for tank: Variant in final_enemies:
		if _dead(tank):
			kills += 1
	var depot_done: bool = not is_instance_valid(final_objective) or final_objective.is_destroyed
	return [
		Loc.t("%sTANQUES ENEMIGOS %d / %d") % ["✔ " if kills == final_enemies.size() else "", kills, final_enemies.size()],
		Loc.t("%sDEPÓSITO ENEMIGO") % ("✔ " if depot_done else ""),
	]


func announce(text: String, urgent: bool) -> void:
	if text.begins_with(Loc.t("PREMIO")):
		_picked += 1
	super(text, urgent)


func fire_missile() -> bool:
	var locked: bool = is_instance_valid(player.aim_lock)
	var fired: bool = super()
	if fired and lesson_id() == "missile":
		if locked:
			_missile_ok = true
		else:
			missiles += 1
			message.emit(Loc.t("SIN OBJETIVO FIJADO EL MISIL VA RECTO: FÍJALO ANTES"), true)
	return fired


func call_air_strike() -> bool:
	var available: bool = strikes > 0
	var launched: bool = super()
	if lesson_id() == "strike":
		if launched:
			_strike_launched = true
		elif available:
			_denied = true
	return launched


func _physics_process(delta: float) -> void:
	super(delta)
	if finished or is_over or lesson_index < 0 or player == null:
		return
	if _transition > 0.0:
		_transition -= delta
		if _transition <= 0.0:
			goto_lesson(lesson_index + 1)
		return
	_hint_timer += delta
	if _hint_timer >= HINT_TIME:
		# Cada 20 s sin lograrlo alterna entre la instrucción y la pista detallada.
		_hint_timer = 0.0
		_hint_on = not _hint_on
		var data: Dictionary = STEPS[lesson_id()][step]
		overlay.set_instruction(Loc.t(data["hint"]) if _hint_on else Loc.t(data["text"]))
		# La locución se repite una sola vez, con la primera pista.
		if not _hint_spoken:
			_hint_spoken = true
			_speak(data["id"])
	if call("_check_" + lesson_id(), delta):
		_complete(false)


func _complete(skipped: bool) -> void:
	if not skipped:
		Sfx.play_2d(self, Sfx.PICKUP, 2.0, 1.25)
		overlay.flash_ok()
	lesson_completed.emit(lesson_index, skipped)
	_transition = 0.3 if skipped else 1.5


func _enter_step(new_step: int) -> void:
	step = new_step
	_hint_timer = 0.0
	_hint_on = false
	_hint_spoken = false
	var data: Dictionary = STEPS[lesson_id()][step]
	overlay.set_instruction(Loc.t(data["text"]))
	var show: Array[String] = []
	show.assign(data["show"])
	overlay.highlights = show
	_speak(data["id"])


## Locución pregenerada de la instrucción; si no existe el audio, queda solo el texto.
func _speak(id: String) -> void:
	var path: String = "%s/tutorial/tut_%s.ogg" % [Loc.voice_dir(), id]
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream != null and is_inside_tree():
		get_tree().call_group(&"voice", &"say_stream", stream, VoiceManager.Priority.HIGH)


## Deja el tanque, los ajustes y los botones como los necesita la lección, también si se
## llega a ella saltando las anteriores.
func _prepare(index: int) -> void:
	GameSettings.easy_drive = index >= LESSONS.find("easy")
	var assist_lesson: int = LESSONS.find("assist")
	if index != assist_lesson:
		GameSettings.aim_assist = index > assist_lesson
	_sync_toggles()
	if is_instance_valid(player.aim_lock) and input_source != null:
		input_source.release_lock()
	player.aim_lock = null
	player.health.invulnerable = index < LESSONS.find("damage")
	missiles = 0
	strikes = 0
	# Las órdenes a los aliados empiezan de cero en cada lección.
	follow_me = false
	focus_target = null
	allies_alive = 0
	if LESSONS[index] in ["raid", "damage", "follow", "focus", "final"]:
		player.set_binoculars(false)
	if touch != null:
		touch.fire_enabled = index >= LESSONS.find("fire")
	if hud != null:
		var allowed: Array[String] = []
		var unlock: Dictionary = {
			"cam": "camera", "release": "assist", "zoom": "zoom", "missile": "missile", "strike": "strike",
			"follow": "follow", "focus": "focus",
		}
		for key in unlock:
			if index >= LESSONS.find(unlock[key]):
				allowed.append(key)
		hud.focus = allowed
	overlay.clear_pulse()
	overlay.set_progress(index, LESSONS.size())
	# En el combate final el HUD pinta la lista de objetivos donde va el progreso: se baja.
	overlay.shift_progress(84.0 if LESSONS[index] == "final" else 0.0)


func _sync_toggles() -> void:
	if hud == null:
		return
	(hud.toggles["easy_drive"] as CheckButton).set_pressed_no_signal(GameSettings.easy_drive)
	(hud.toggles["aim_assist"] as CheckButton).set_pressed_no_signal(GameSettings.aim_assist)


func _cleanup(keep_targets: bool) -> void:
	# Nada de lo que se retira puede quedar fijado por la ayuda de apuntado.
	if player != null:
		player.aim_lock = null
	for node in _props:
		if is_instance_valid(node) and not (keep_targets and node is PracticeProps.Target):
			node.queue_free()
	_props.clear()
	# Tampoco quedan los restos de lo destruido en la lección anterior.
	if is_inside_tree():
		get_tree().call_group(&"remains", &"queue_free")
	if keep_targets:
		for target in targets:
			if is_instance_valid(target):
				_props.append(target)
	else:
		targets.clear()
	beacons.clear()
	beacon_index = 0
	final_enemies.clear()
	allies.clear()
	enemy = null
	depot_near = null
	depot_far = null
	pickup = null
	raid = null
	final_objective = null
	_aim_time.clear()


func _finish() -> void:
	finished = true
	is_over = true
	player.health.invulnerable = true
	GameSession.mark_tutorial("completed")
	if touch != null:
		touch.fire_enabled = true
	overlay.show_summary()
	_speak("end")


# ------------------------------------------------------------------ utilidades del campo

func _player_xz() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


func _turret_dir() -> Vector2:
	var yaw: float = player.turret_controller.world_yaw
	return Vector2(-sin(yaw), -cos(yaw))


## Hacia dónde se colocan las cosas: delante del casco, o hacia el centro del campo si el
## jugador está cerca de la valla (así nada queda fuera).
func _base_dir() -> Vector2:
	var origin: Vector2 = _player_xz()
	if origin.length() > 40.0:
		return -origin.normalized()
	var forward: Vector3 = -player.global_basis.z
	return Vector2(forward.x, forward.z).normalized()


## Punto a `forward` metros en la dirección `dir` y `side` metros a su derecha.
func _spot(forward: float, side: float, dir: Vector2 = Vector2.ZERO) -> Vector2:
	if dir == Vector2.ZERO:
		dir = _base_dir()
	var right := Vector2(-dir.y, dir.x)
	return (_player_xz() + dir * forward + right * side).clampf(-FIELD + 12.0, FIELD - 12.0)


func _near(point: Vector2, radius: float) -> bool:
	return _player_xz().distance_to(point) <= radius


## ¿Destruido o ya retirado del campo? (Los restos de un tanque se liberan a los 8 s; por eso
## el argumento no lleva tipo: una referencia ya liberada no pasa por un parámetro `Tank`.)
func _dead(tank: Variant) -> bool:
	return not is_instance_valid(tank) or tank.is_destroyed


## Ángulo entre el cañón y un punto del mundo.
func _aim_error(point: Vector3) -> float:
	var from: Vector3 = player.muzzle.global_position
	return (-player.muzzle.global_transform.basis.z).angle_to(point - from)


func _add(node: Node3D, point: Vector2, yaw: float = 0.0) -> void:
	node.position = Vector3(point.x, 0.0, point.y)
	node.rotation.y = yaw
	world.add_child(node)
	_props.append(node)


func _beacon(point: Vector2, active: bool = true) -> PracticeProps.Beacon:
	var beacon := PracticeProps.Beacon.new()
	_add(beacon, point)
	beacon.set_active(active)
	beacons.append(beacon)
	return beacon


func _target(point: Vector2) -> PracticeProps.Target:
	var target := PracticeProps.Target.new()
	_add(target, point, yaw_towards(point, _player_xz()))
	target.destroyed.connect(func(_prop: Destructible) -> void: _targets_destroyed += 1)
	targets.append(target)
	return target


## Tanque sin tripulación (no se mueve ni dispara solo): blanco de prácticas o comparsa.
func _dummy(id: String, team: int, point: Vector2, yaw: float, armor: float) -> Tank:
	var stats: TankStats = Fronts.tank(id)
	var tank := Tank.new()
	tank.name = "PracticeTank"
	tank.stats = stats
	tank.team = team
	tank.paint = Fronts.paint(front, faction_of(team), stats.nation)
	tank.position = Vector3(point.x, 0.2, point.y)
	tank.rotation.y = yaw
	world.add_child(tank)
	tank.health.max_health = armor
	tank.health.current = armor
	tank.destroyed.connect(_on_tank_destroyed)
	_props.append(tank)
	return tank


func _pickup(kind: String, point: Vector2) -> Pickup:
	var prize := Pickup.create(kind, player)
	prize.time_left = 100000.0
	_add(prize, point)
	return prize


func _depot(point: Vector2, armor: float) -> Destructible:
	var depot: Destructible = PropFactory.supply_depot()
	depot.max_health = armor
	# En el campo de prácticas el depósito no revienta lo que tiene alrededor.
	depot.blast_radius = 0.0
	_add(depot, point, yaw_towards(point, _player_xz()))
	return depot


# ------------------------------------------------------------------ lecciones

func _setup_move() -> void:
	_reverse_distance = 0.0
	_beacon(_spot(30.0, 0.0))


func _check_move(delta: float) -> bool:
	if step == 0:
		if _near(beacons[0].point(), 5.5):
			beacons[0].set_active(false)
			_enter_step(1)
		return false
	var speed: float = player.velocity.dot(-player.global_basis.z)
	if speed < -0.5:
		_reverse_distance -= speed * delta
	return _reverse_distance >= 8.0


func _setup_turn() -> void:
	var dir: Vector2 = _base_dir()
	var origin: Vector2 = _player_xz()
	var right := Vector2(-dir.y, dir.x)
	var side: float = -14.0
	for i in 3:
		var point: Vector2 = (origin + dir * (24.0 + i * 22.0) + right * side).clampf(-FIELD + 12.0, FIELD - 12.0)
		_beacon(point, i == 0)
		side = -side


func _check_turn(_delta: float) -> bool:
	if _near(beacons[beacon_index].point(), 5.5):
		beacons[beacon_index].queue_free()
		beacon_index += 1
		if beacon_index >= beacons.size():
			return true
		beacons[beacon_index].set_active(true)
	return false


func _spawn_targets() -> void:
	var dir: Vector2 = _turret_dir()
	# Si la valla queda cerca, las dianas se abren alrededor del rumbo hacia el centro.
	if _player_xz().length() > 40.0:
		dir = -_player_xz().normalized()
	for angle in [-50.0, 35.0, 100.0]:
		var point: Vector2 = (_player_xz() + dir.rotated(deg_to_rad(angle)) * 42.0).clampf(-FIELD + 8.0, FIELD - 8.0)
		_target(point)


func _setup_turret() -> void:
	_spawn_targets()


func _check_turret(delta: float) -> bool:
	var pending: int = 0
	for target in targets:
		if not is_instance_valid(target) or target.acquired:
			continue
		pending += 1
		if _aim_error(target.center()) < deg_to_rad(3.5):
			_aim_time[target] = _aim_time.get(target, 0.0) + delta
			if _aim_time[target] >= 0.5:
				target.mark_acquired()
				Sfx.play_2d(self, Sfx.PICKUP, -4.0, 1.6)
		else:
			_aim_time[target] = 0.0
	return pending == 0


func _setup_fire() -> void:
	var alive: int = 0
	for target in targets:
		if is_instance_valid(target) and not target.is_destroyed:
			alive += 1
	if alive == 0:
		targets.clear()
		_spawn_targets()
	_shots = 0
	_reloaded = false
	_targets_destroyed = 0


func _check_fire(_delta: float) -> bool:
	if step == 0:
		if _shots >= 1:
			_enter_step(1)
		return false
	if player.weapon.ready_fraction() >= 1.0:
		_reloaded = true
	return _reloaded and _targets_destroyed >= 1


func _setup_easy() -> void:
	_beacon(_spot(36.0, 30.0))


func _check_easy(_delta: float) -> bool:
	if not _near(beacons[step].point(), 5.5):
		return false
	beacons[step].queue_free()
	if step == 1:
		return true
	_beacon(_spot(36.0, -30.0))
	_enter_step(1)
	return false


func _setup_camera() -> void:
	_cam_presses = 0


func _check_camera(_delta: float) -> bool:
	return _cam_presses >= 3


func _setup_radar() -> void:
	var dir: Vector2 = _base_dir()
	var facing: float = yaw_towards(Vector2.ZERO, dir)
	_dummy("m4_sherman", PLAYER_TEAM, _spot(-12.0, -10.0, dir), facing, 50.0).health.invulnerable = true
	_dummy("m4_sherman", PLAYER_TEAM, _spot(-12.0, 10.0, dir), facing, 50.0).health.invulnerable = true
	enemy = _dummy("panzer3", ENEMY_TEAM, _spot(78.0, -28.0, dir), facing + PI, 30.0)
	_add(StructureFactory.radio_mast(), _spot(52.0, 46.0, dir))
	_pickup("points", _spot(28.0, -30.0, dir))
	_beacon(_spot(58.0, 8.0, dir)).set_diamond()


func _check_radar(_delta: float) -> bool:
	return _near(beacons[0].point(), 6.0)


func _setup_enemy() -> void:
	var point: Vector2 = _spot(60.0, 0.0)
	enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()) + 0.6, 75.0)


func _check_enemy(delta: float) -> bool:
	if step == 0:
		if _dead(enemy):
			var point: Vector2 = _spot(68.0, -20.0)
			# Cruza por delante del jugador, de un lado a otro.
			enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()) + PI * 0.5, 50.0)
			_mover_time = 0.0
			_enter_step(1)
		return false
	if _dead(enemy):
		return true
	_mover_time += delta
	enemy.drive_input = Vector2(0.0, 0.55 if fmod(_mover_time, 14.0) < 7.0 else -0.55)
	return false


func _setup_assist() -> void:
	var point: Vector2 = _spot(65.0, 18.0)
	enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()) + 0.5, 50.0)
	enemy.health.invulnerable = true
	_release_presses = 0
	if hud != null:
		overlay.pulse_toggle = hud.toggles["aim_assist"]


func _check_assist(_delta: float) -> bool:
	match step:
		0:
			if GameSettings.aim_assist:
				overlay.clear_pulse()
				_enter_step(1)
		1:
			if is_instance_valid(player.aim_lock):
				_release_presses = 0
				_enter_step(2)
		2:
			if not is_instance_valid(player.aim_lock):
				if _release_presses > 0:
					return true
				_enter_step(1)
	return false


func _setup_zoom() -> void:
	_target(_spot(108.0, 0.0))


func _check_zoom(_delta: float) -> bool:
	if step == 0:
		if player.binoculars:
			_enter_step(1)
		return false
	return not is_instance_valid(targets[0]) or targets[0].hits >= 1


func _spawn_missile_enemy() -> void:
	var point: Vector2 = _spot(95.0, -15.0)
	enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()) + 0.7, 100.0)


func _setup_missile() -> void:
	missiles = 3
	_missile_ok = false
	_spawn_missile_enemy()


func _check_missile(_delta: float) -> bool:
	if _dead(enemy):
		if _missile_ok:
			return true
		message.emit(Loc.t("ASÍ NO VALE: DESTRÚYELO CON UN MISIL"), true)
		_spawn_missile_enemy()
	if missiles <= 0 and not _missile_ok:
		missiles = 2
	return false


func _spawn_far_depot() -> void:
	depot_far = _depot(_spot(75.0, 28.0), 100.0)
	depot_far.set_meta("radar_shape", "diamond")
	depot_far.destroyed.connect(func(_prop: Destructible) -> void:
		if _strike_launched:
			_bombed = true)


func _setup_strike() -> void:
	strikes = 9
	_denied = false
	_bombed = false
	_strike_launched = false
	depot_near = _depot(_spot(17.0, -5.0), 100.0)
	depot_near.indestructible = true
	_spawn_far_depot()


func _check_strike(_delta: float) -> bool:
	if not _bombed and (not is_instance_valid(depot_far) or depot_far.is_destroyed):
		# Destruido a cañonazos: se repone, la lección es pedir el bombardeo.
		message.emit(Loc.t("ASÍ NO VALE: PIDE EL BOMBARDEO CON AVIÓN"), true)
		_spawn_far_depot()
	strikes = maxi(strikes, 3)
	match step:
		0:
			if _denied:
				_enter_step(1)
			elif _bombed:
				_enter_step(2)
		1:
			return _bombed
		2:
			return _denied
	return false


func _setup_raid() -> void:
	_raid_delay = 6.0
	_raid_judged = false


func _check_raid(delta: float) -> bool:
	if raid == null:
		_raid_delay -= delta
		if _raid_delay <= 0.0:
			raid = AirStrike.launch(world, player.global_position, true)
			_raid_judged = false
			get_tree().call_group(&"voice", &"say", "raid", VoiceManager.Priority.CRITICAL)
			message.emit(Loc.t("¡BOMBARDEO ENEMIGO! SAL DE LA ZONA ROJA"), true)
		return false
	if not is_instance_valid(raid):
		raid = null
		_raid_delay = 3.0
		return false
	if raid.time_left() <= 0.0 and not _raid_judged:
		_raid_judged = true
		if not raid.contains(player.global_position):
			return true
		message.emit(Loc.t("TE HABRÍA ALCANZADO. PRUEBA OTRA VEZ"), true)
	return false


func _setup_damage() -> void:
	player.health.heal(1000.0)
	_hit = false
	_picked = 0
	_shoot_delay = 4.0
	var point: Vector2 = _spot(38.0, 12.0)
	enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()), 50.0)
	enemy.health.invulnerable = true
	enemy.weapon.damage = 20.0


func _check_damage(delta: float) -> bool:
	match step:
		0:
			if _hit:
				if is_instance_valid(enemy):
					enemy.trigger_held = false
					Explosion.spawn(self, enemy.global_position + Vector3.UP, 1.2)
					if player.aim_lock == enemy:
						player.aim_lock = null
					enemy.queue_free()
				pickup = _pickup("repair", _spot(22.0, -10.0))
				_picked = 0
				_enter_step(1)
			elif is_instance_valid(enemy):
				_shoot_delay -= delta
				enemy.turret_controller.aim_at(player.global_position + Vector3.UP * 1.2)
				enemy.trigger_held = _shoot_delay <= 0.0 and enemy.turret_controller.is_aligned(0.03)
		1:
			if _picked >= 1:
				pickup = _pickup("reload", _spot(22.0, 10.0))
				_enter_step(2)
		2:
			return player.buffs.has("reload")
	return false


func _spawn_allies(forward: float) -> void:
	var dir: Vector2 = _base_dir()
	var facing: float = yaw_towards(Vector2.ZERO, dir)
	allies.clear()
	for side in [-14.0, 14.0]:
		var ally: Tank = spawn_tank(Fronts.tank("m4_sherman"), PLAYER_TEAM, _spot(forward, side, dir), facing)
		_props.append(ally)
		allies.append(ally)


func _setup_follow() -> void:
	player.health.heal(1000.0)
	_follow_wait = 0.0
	_spawn_allies(-6.0)
	_beacon(_spot(62.0, 0.0))


func _check_follow(delta: float) -> bool:
	match step:
		0:
			if follow_me:
				_enter_step(1)
		1:
			var beacon_point: Vector2 = Vector2(beacons[0].global_position.x, beacons[0].global_position.z)
			if not _near(beacon_point, 9.0):
				_follow_wait = 0.0
				return false
			# En la baliza, los aliados tienen que haber llegado junto al jugador.
			var close: int = 0
			for ally: Tank in allies:
				if is_instance_valid(ally) and not ally.is_destroyed and ally.global_position.distance_to(player.global_position) < 34.0:
					close += 1
			_follow_wait += delta
			return close >= 1 and _follow_wait > 3.0
	return false


func _setup_focus() -> void:
	player.health.heal(1000.0)
	_spawn_allies(-6.0)
	var dir: Vector2 = _base_dir()
	var point: Vector2 = _spot(75.0, 0.0, dir)
	enemy = _dummy("panzer3", ENEMY_TEAM, point, yaw_towards(point, _player_xz()), 90.0)
	enemy.health.invulnerable = false


func _check_focus(_delta: float) -> bool:
	match step:
		0:
			if focus_target != null and focus_target == enemy:
				_enter_step(1)
		1:
			return _dead(enemy)
	return false


func _setup_final() -> void:
	player.health.heal(1000.0)
	missiles = 2
	strikes = 1
	var dir: Vector2 = _base_dir()
	var facing: float = yaw_towards(Vector2.ZERO, dir)
	for side in [-12.0, 12.0]:
		_props.append(spawn_tank(Fronts.tank("m4_sherman"), PLAYER_TEAM, _spot(-6.0, side, dir), facing))
	var ids: Array[String] = ["panzer3", "puma", "panzer3"]
	var sides: Array[float] = [-42.0, 0.0, 42.0]
	for i in 3:
		var tank: Tank = spawn_tank(Fronts.tank(ids[i]), ENEMY_TEAM, _spot(105.0 if i == 1 else 92.0, sides[i], dir), facing + PI)
		_props.append(tank)
		final_enemies.append(tank)
	final_objective = _depot(_spot(70.0, 62.0, dir), 60.0)
	final_objective.set_meta("radar_shape", "diamond")


func _check_final(_delta: float) -> bool:
	for tank: Variant in final_enemies:
		if not _dead(tank):
			return false
	return not is_instance_valid(final_objective) or final_objective.is_destroyed
