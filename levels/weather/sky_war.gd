class_name SkyWar
extends Node3D
## La guerra en el cielo, de ambiente: formaciones de aviones de la época que cruzan muy por
## encima del campo con su ruido de motores, la antiaérea del bando contrario que les dispara
## (trazadoras que suben, fogonazo, nubecilla negra y el estampido que llega con retraso),
## duelos de artillería más allá del horizonte que encienden las nubes y, de vez en cuando, un
## avión tocado que cae envuelto en humo y se estrella fuera del campo. No afecta a la partida:
## nada de esto hace daño ni da puntos.

## Tipos de aparato: envergadura y largo (m), motores, velocidad de paso (m/s) y altura (m).
const TYPES: Dictionary = {
	"fighter": {"span": 11.0, "length": 9.5, "engines": 1, "speed": 95.0, "height": Vector2(110.0, 150.0), "group": Vector2i(2, 4)},
	"attack": {"span": 14.0, "length": 11.5, "engines": 1, "speed": 78.0, "height": Vector2(100.0, 140.0), "group": Vector2i(3, 3)},
	"medium": {"span": 22.0, "length": 16.5, "engines": 2, "speed": 70.0, "height": Vector2(150.0, 190.0), "group": Vector2i(3, 3)},
	"heavy": {"span": 31.0, "length": 22.5, "engines": 4, "speed": 64.0, "height": Vector2(180.0, 220.0), "group": Vector2i(3, 5)},
}

## Qué volaba en cada frente: [modelo, tipo, peso]. En Normandía (1944) el cielo era aliado y
## la Luftwaffe apenas aparecía; en África y en Kursk volaban los dos bandos.
const AIRCRAFT: Dictionary = {
	Fronts.Id.NORMANDY: {
		Fronts.Faction.ALLIES: [["P-51 MUSTANG", "fighter", 3.0], ["P-47 THUNDERBOLT", "fighter", 2.0], ["HAWKER TYPHOON", "attack", 2.0], ["B-26 MARAUDER", "medium", 2.0], ["B-17", "heavy", 2.0]],
		Fronts.Faction.AXIS: [["BF 109", "fighter", 2.0], ["FW 190", "fighter", 2.0], ["FW 190 F", "attack", 1.0], ["JU 88", "medium", 0.5]],
	},
	Fronts.Id.AFRICA: {
		Fronts.Faction.ALLIES: [["HURRICANE", "fighter", 3.0], ["SPITFIRE", "fighter", 2.0], ["P-40 KITTYHAWK", "fighter", 2.0], ["HURRICANE IID", "attack", 1.0], ["BLENHEIM", "medium", 2.0]],
		Fronts.Faction.AXIS: [["BF 109", "fighter", 3.0], ["JU 87 STUKA", "attack", 3.0], ["JU 88", "medium", 2.0]],
	},
	Fronts.Id.KURSK: {
		Fronts.Faction.ALLIES: [["IL-2 SHTURMOVIK", "attack", 4.0], ["YAK-9", "fighter", 2.0], ["LA-5", "fighter", 2.0], ["PE-2", "medium", 2.0]],
		Fronts.Faction.AXIS: [["JU 87 STUKA", "attack", 3.0], ["HE 111", "medium", 2.0], ["BF 109", "fighter", 2.0], ["FW 190", "fighter", 2.0]],
	},
}
## Probabilidad de que la formación que pasa sea aliada, por frente.
const ALLIED_SHARE: Array[float] = [0.85, 0.5, 0.5]
## Pintura por bando y frente: [lomo, panza].
const PAINT: Dictionary = {
	Fronts.Faction.ALLIES: [[Color(0.32, 0.35, 0.22), Color(0.6, 0.63, 0.62)], [Color(0.62, 0.52, 0.36), Color(0.5, 0.6, 0.7)], [Color(0.25, 0.33, 0.2), Color(0.5, 0.62, 0.72)]],
	Fronts.Faction.AXIS: [[Color(0.36, 0.4, 0.42), Color(0.55, 0.65, 0.72)], [Color(0.7, 0.6, 0.4), Color(0.55, 0.65, 0.75)], [Color(0.3, 0.36, 0.3), Color(0.55, 0.65, 0.72)]],
}

const FIELD: float = 215.0
const PASS_INTERVAL: Vector2 = Vector2(14.0, 32.0)
const DISTANT_INTERVAL: Vector2 = Vector2(4.0, 11.0)
const DOWN_CHANCE: float = 0.55
## Velocidad de las trazadoras antiaéreas (m/s) y color según quién dispara (lineal).
const TRACER_SPEED: float = 240.0
const TRACER_AXIS := Color(1.0, 0.62, 0.2)
const TRACER_ALLIES := Color(1.0, 0.2, 0.1)
const TRACER_SOVIET := Color(0.45, 1.0, 0.35)

var front: int = Fronts.Id.NORMANDY
## Aviones derribados que han caído dentro del campo (debe ser siempre 0; lo miran las pruebas).
var crashes_inside: int = 0
var crashes: int = 0
## Última formación lanzada (para pruebas y capturas).
var last_model: String = ""

var _pass_timer: float = 12.0
var _distant_timer: float = 6.0
var _formations: Array[Dictionary] = []


func _process(delta: float) -> void:
	# En la fase antiaérea de supervivencia (cámara lenta) el cielo ya tiene lo suyo.
	if Engine.time_scale < 0.99:
		return
	_pass_timer -= delta
	if _pass_timer <= 0.0:
		_pass_timer = randf_range(PASS_INTERVAL.x, PASS_INTERVAL.y)
		launch()
	_distant_timer -= delta
	if _distant_timer <= 0.0:
		_distant_timer = randf_range(DISTANT_INTERVAL.x, DISTANT_INTERVAL.y)
		if randf() < 0.6:
			distant_guns()
		else:
			_distant_barrage()
	for formation in _formations.duplicate():
		_update_formation(formation, delta)


## Lanza una formación. Sin argumentos se sortean bando y modelo según el frente.
func launch(faction: int = -1, choice: int = -1, flak: bool = true, doomed: int = -1) -> Dictionary:
	if faction < 0:
		faction = Fronts.Faction.ALLIES if randf() < ALLIED_SHARE[front] else Fronts.Faction.AXIS
	var options: Array = AIRCRAFT[front][faction]
	if choice < 0:
		var total: float = 0.0
		for option in options:
			total += option[2]
		var roll: float = randf() * total
		for i in options.size():
			roll -= options[i][2]
			if roll <= 0.0:
				choice = i
				break
	var model: Array = options[clampi(choice, 0, options.size() - 1)]
	var spec: Dictionary = TYPES[model[1]]
	last_model = model[0]
	var heading: float = randf() * TAU
	var dir := Vector3(sin(heading), 0.0, cos(heading))
	var right := Vector3(dir.z, 0.0, -dir.x)
	var height: float = randf_range(spec["height"].x, spec["height"].y)
	var lead_pos: Vector3 = -dir * 540.0 + right * randf_range(-140.0, 140.0) + Vector3.UP * height
	var count: int = randi_range(spec["group"].x, spec["group"].y)
	var planes: Array[SkyPlane] = []
	var paint: Array = PAINT[faction][front]
	for i in count:
		var plane := SkyPlane.new()
		add_child(plane)
		plane.build(model[0], spec, paint[0], paint[1], faction)
		# Formación en cuña: el jefe delante y los demás escalonados a los lados.
		var rank: int = (i + 1) / 2
		var side: float = -1.0 if i % 2 == 1 else 1.0
		var gap: float = spec["span"] * 1.6
		plane.global_position = lead_pos - dir * rank * gap * 0.9 + right * side * rank * gap + Vector3.UP * rank * 2.0
		plane.velocity = dir * spec["speed"]
		plane.look_at(plane.global_position + dir, Vector3.UP)
		planes.append(plane)
	var sound_stream: AudioStream = Sfx.PLANE_FIGHTER if spec["engines"] == 1 else Sfx.PLANE_BOMBER
	var sound := FlybySound.attach(planes[0], sound_stream, 7.0 + count, 60.0, 900.0, 1.0 if spec["engines"] < 4 else 0.85)
	sound.source_velocity = planes[0].velocity
	if doomed < 0:
		doomed = randi() % count if flak and randf() < DOWN_CHANCE else -1
	# Dos cañones antiaéreos ligeros, fuera del campo y a los lados de la ruta, le tiran trazadoras.
	var guns: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		guns.append(right * (lead_pos.dot(right) + side * randf_range(90.0, 180.0)) + dir * randf_range(-120.0, 120.0))
	for i in guns.size():
		var edge: float = maxf(absf(guns[i].x), absf(guns[i].z))
		if edge < FIELD + 30.0:
			guns[i] *= (FIELD + 30.0) / maxf(edge, 1.0)
	var formation: Dictionary = {
		"planes": Array(planes), "dir": dir, "flak": flak, "flak_timer": randf_range(0.5, 1.5), "sound": sound,
		"guns": guns, "burst_timer": randf_range(0.2, 1.0), "burst_left": 0, "burst_gun": 0, "burst_due": 0.0,
		"doomed": planes[doomed] if doomed >= 0 and doomed < count else null, "doom_at": randf_range(-120.0, 60.0), "faction": faction,
	}
	_formations.append(formation)
	return formation


func _update_formation(formation: Dictionary, delta: float) -> void:
	# Los aviones se liberan solos al estrellarse: primero se quitan de la lista los que ya no existen.
	var planes: Array = formation["planes"]
	for i in range(planes.size() - 1, -1, -1):
		if not is_instance_valid(planes[i]):
			planes.remove_at(i)
	var dir: Vector3 = formation["dir"]
	var alive: int = planes.size()
	var lead: SkyPlane = null
	for plane: SkyPlane in planes:
		if not plane.falling:
			lead = plane
			break
	if alive == 0:
		_formations.erase(formation)
		return
	if lead == null:
		return
	# Distancia recorrida respecto al punto más cercano al centro del campo.
	var along: float = lead.global_position.dot(dir)
	if along > 560.0:
		for plane: SkyPlane in planes:
			if not plane.falling:
				plane.queue_free()
		return
	if along > 430.0 and is_instance_valid(formation["sound"]):
		(formation["sound"] as FlybySound).fade_out()
	if not formation["flak"] or absf(along) > 330.0:
		return
	_fire_tracers(formation, planes, delta)
	formation["flak_timer"] -= delta
	if formation["flak_timer"] <= 0.0:
		formation["flak_timer"] = randf_range(0.25, 0.9)
		var target: SkyPlane = planes.pick_random()
		if not target.falling:
			var miss := Vector3(randf_range(-28.0, 28.0), randf_range(-16.0, 16.0), randf_range(-28.0, 28.0))
			FlakBurst.spawn(self, target.global_position + target.velocity * 0.4 + miss, 1.0)
	var doomed: Variant = formation["doomed"]
	if doomed != null and is_instance_valid(doomed) and along >= formation["doom_at"] and not doomed.falling:
		var plane: SkyPlane = doomed
		# Solo se le derriba cuando ya va a caer fuera del campo: nunca sobre los tanques.
		var impact: Vector3 = plane.impact_point()
		if absf(impact.x) > FIELD + 25.0 or absf(impact.z) > FIELD + 25.0:
			FlakBurst.spawn(self, plane.global_position, 1.6)
			plane.shoot_down(self)
			formation["doomed"] = null


## Modelo [nombre, tipo] de un bando para los tipos pedidos, por orden de preferencia. Si en
## ese frente el bando no tiene ninguno de ese tipo, se toma el de otro frente.
static func pick_model(battle_front: int, faction: int, wanted: Array[String]) -> Array:
	for type in wanted:
		var found: Array = []
		for option in AIRCRAFT[battle_front][faction]:
			if option[1] == type:
				found.append(option)
		if found.is_empty():
			for other in AIRCRAFT:
				for option in AIRCRAFT[other][faction]:
					if option[1] == type:
						found.append(option)
		if not found.is_empty():
			return found.pick_random()
	return AIRCRAFT[battle_front][faction][0]


## Avión ya construido con la pintura de su bando en ese frente (sin añadir al árbol).
static func make_plane(battle_front: int, faction: int, model: Array) -> SkyPlane:
	var plane := SkyPlane.new()
	var paint: Array = PAINT[faction][battle_front]
	plane.build(model[0], TYPES[model[1]], paint[0], paint[1], faction)
	return plane


## Ráfagas de trazadoras de los cañones antiaéreos ligeros: suben hacia la formación, apuntando
## por delante de un avión y casi siempre fallando.
func _fire_tracers(formation: Dictionary, planes: Array, delta: float) -> void:
	if formation["burst_left"] <= 0:
		formation["burst_timer"] -= delta
		if formation["burst_timer"] > 0.0:
			return
		formation["burst_timer"] = randf_range(0.5, 1.6)
		formation["burst_left"] = randi_range(4, 9)
		formation["burst_gun"] = randi() % 2
		formation["burst_due"] = 0.0
	formation["burst_due"] -= delta
	if formation["burst_due"] > 0.0:
		return
	formation["burst_due"] = 0.11
	formation["burst_left"] -= 1
	var target: SkyPlane = planes.pick_random()
	var gun: Vector3 = formation["guns"][formation["burst_gun"]]
	# Punto futuro del avión, con el error del artillero.
	var lead: float = gun.distance_to(target.global_position) / TRACER_SPEED
	var aim: Vector3 = target.global_position + target.velocity * lead * randf_range(0.7, 1.25) + Vector3(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0), randf_range(-14.0, 14.0))
	var color: Color = TRACER_AXIS
	if formation["faction"] == Fronts.Faction.AXIS:
		color = TRACER_SOVIET if front == Fronts.Id.KURSK else TRACER_ALLIES
	var from: Vector3 = gun + Vector3.UP * 2.0
	Fx.on(self).tracer(from, (aim - from).normalized() * TRACER_SPEED, color)


## Duelo de artillería más allá del horizonte: una salva de fogonazos que encienden desde abajo
## las nubes de esa parte del cielo y, segundos después, el retumbar sordo de los cañones.
func distant_guns() -> void:
	var heading: float = randf() * TAU
	var away := Vector3(sin(heading), 0.0, cos(heading))
	var distance: float = randf_range(1700.0, 3000.0)
	var at: float = 0.0
	for i in randi_range(3, 8):
		at += randf_range(0.1, 0.7)
		var point: Vector3 = away * distance + Vector3(randf_range(-400.0, 400.0), 0.0, randf_range(-400.0, 400.0))
		get_tree().create_timer(at).timeout.connect(func() -> void:
			if is_inside_tree():
				Fx.on(self).sky_flash(point, Color(1.0, 0.62, 0.32), randf_range(1.2, 2.0), randf_range(300.0, 420.0), randf_range(0.22, 0.42)))
		# El sonido viaja a 343 m/s: de tan lejos llega tarde y ya solo es un golpe grave.
		get_tree().create_timer(at + distance / 343.0).timeout.connect(func() -> void:
			if not is_inside_tree():
				return
			var camera: Camera3D = get_viewport().get_camera_3d()
			var ear: Vector3 = camera.global_position if camera != null else Vector3.ZERO
			Sfx.play_at(self, Sfx.EXPLOSION, ear + away * 260.0, 8.0, randf_range(0.42, 0.55)))


## Fogonazos de baterías antiaéreas lejanas, cerca del horizonte.
func _distant_barrage() -> void:
	var heading: float = randf() * TAU
	var centre := Vector3(sin(heading), 0.0, cos(heading)) * randf_range(400.0, 470.0)
	for i in randi_range(3, 7):
		var point: Vector3 = centre + Vector3(randf_range(-70.0, 70.0), randf_range(70.0, 170.0), randf_range(-70.0, 70.0))
		get_tree().create_timer(randf_range(0.0, 2.4)).timeout.connect(func() -> void:
			if is_inside_tree():
				FlakBurst.spawn(self, point, 5.0))


func _on_crash(point: Vector3) -> void:
	crashes += 1
	if absf(point.x) < FIELD and absf(point.z) < FIELD:
		crashes_inside += 1


## Avión de ambiente. La silueta sale del tipo (caza, ataque, bimotor, cuatrimotor).
class SkyPlane extends Node3D:
	const FALL_ACCEL: float = 11.0

	var velocity: Vector3
	var falling: bool = false
	var model: String = ""
	var _props: Array[Node3D] = []
	var _fx: Fx
	var _trail_due: float = 0.0
	var _span: float = 11.0
	var _owner_sky: Node
	var _roll_rate: float = 0.0

	func build(model_name: String, spec: Dictionary, top: Color, belly: Color, faction: int) -> void:
		model = model_name
		var span: float = spec["span"]
		_span = span
		var length: float = spec["length"]
		var top_mat: ShaderMaterial = VectorMaterials.textured(top, top.darkened(0.35), 4, 0.5)
		var fuselage := MeshInstance3D.new()
		var body := CylinderMesh.new()
		body.top_radius = length * 0.035
		body.bottom_radius = length * 0.075
		body.height = length
		body.radial_segments = 10
		fuselage.mesh = body
		fuselage.material_override = top_mat
		fuselage.rotation.x = PI * 0.5
		add_child(fuselage)
		var chord: float = span * (0.2 if spec["engines"] == 1 else 0.16)
		# El Stuka se reconoce por su ala en gaviota invertida y su tren fijo carenado.
		var gull: bool = model_name.contains("STUKA")
		for side in [-1.0, 1.0]:
			var wing := VectorMaterials.make_box(Vector3(span * 0.5, length * 0.02, chord), top, 4, 1.2)
			wing.position = Vector3(side * span * 0.25, -length * 0.02, -length * 0.08)
			wing.rotation.z = side * (0.09 if not gull else 0.2)
			add_child(wing)
			var under := VectorMaterials.make_box(Vector3(span * 0.5, 0.05, chord * 0.98), belly, 0, 1.0)
			under.position = wing.position + Vector3(0.0, -length * 0.012, 0.0)
			under.rotation.z = wing.rotation.z
			add_child(under)
			if gull:
				var leg := VectorMaterials.make_box(Vector3(0.45, 1.5, 1.4), top.darkened(0.2), 4, 0.6)
				leg.position = Vector3(side * span * 0.16, -1.1, -length * 0.1)
				add_child(leg)
			# Insignia en el ala: estrella o escarapela aliada, cruz alemana (un simple distintivo).
			var mark := VectorMaterials.make_box(Vector3(chord * 0.45, 0.04, chord * 0.45), Color(0.9, 0.9, 0.88) if faction == Fronts.Faction.ALLIES else Color(0.08, 0.08, 0.08))
			mark.position = Vector3(side * span * 0.36, length * 0.02 + side * 0.0, -length * 0.08)
			mark.rotation.z = wing.rotation.z
			add_child(mark)
		var tail := VectorMaterials.make_box(Vector3(span * 0.32, length * 0.015, chord * 0.55), top, 4, 1.0)
		tail.position = Vector3(0.0, length * 0.03, length * 0.45)
		add_child(tail)
		var fin := VectorMaterials.make_box(Vector3(length * 0.015, length * 0.16, chord * 0.6), top, 4, 1.0)
		fin.position = Vector3(0.0, length * 0.1, length * 0.45)
		add_child(fin)
		var canopy := VectorMaterials.make_box(Vector3(length * 0.07, length * 0.05, length * 0.16), Color(0.3, 0.42, 0.5), 1, 0.5)
		canopy.position = Vector3(0.0, length * 0.07, -length * 0.12)
		add_child(canopy)
		var engine_x: Array[float] = [0.0]
		if spec["engines"] == 2:
			engine_x = [-span * 0.17, span * 0.17]
		elif spec["engines"] == 4:
			engine_x = [-span * 0.3, -span * 0.14, span * 0.14, span * 0.3]
		for x in engine_x:
			var nose_z: float = -length * 0.5 if spec["engines"] == 1 else -length * 0.22
			if spec["engines"] > 1:
				var nacelle := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = length * 0.03
				cyl.bottom_radius = length * 0.035
				cyl.height = length * 0.24
				cyl.radial_segments = 8
				nacelle.mesh = cyl
				nacelle.material_override = top_mat
				nacelle.rotation.x = PI * 0.5
				nacelle.position = Vector3(x, -length * 0.02, nose_z + length * 0.1)
				add_child(nacelle)
			var prop := Node3D.new()
			prop.position = Vector3(x, 0.0 if spec["engines"] == 1 else -length * 0.02, nose_z - 0.1)
			add_child(prop)
			prop.add_child(VectorMaterials.make_box(Vector3(length * 0.3, 0.14, 0.05), Color(0.12, 0.12, 0.12)))
			_props.append(prop)

	## Dónde tocaría el suelo si le dieran ahora mismo.
	func impact_point() -> Vector3:
		var fall_time: float = sqrt(2.0 * maxf(global_position.y, 1.0) / FALL_ACCEL)
		return global_position + Vector3(velocity.x, 0.0, velocity.z) * fall_time * 0.92

	func shoot_down(sky: Node) -> void:
		falling = true
		_owner_sky = sky
		_roll_rate = randf_range(0.6, 1.4) * (1.0 if randf() < 0.5 else -1.0)
		_fx = Fx.on(self)
		_fx.airburst(global_position, 1.3)
		Sfx.play_at(self, Sfx.EXPLOSION, global_position, 16.0, 0.9)

	func _process(delta: float) -> void:
		for prop in _props:
			prop.rotation.z += delta * 45.0
		if falling:
			velocity.y -= FALL_ACCEL * delta
			rotation.z += _roll_rate * delta
			if velocity.length() > 1.0:
				var heading: Vector3 = velocity.normalized()
				var roll: float = rotation.z
				look_at(global_position + heading, Vector3.UP)
				rotation.z = roll
		global_position += velocity * delta
		if falling and is_instance_valid(_fx):
			# Cae envuelto en llamas, dejando una estela de humo negro.
			var size: float = _span * 0.16
			_trail_due += delta * 26.0
			while _trail_due >= 1.0:
				_trail_due -= 1.0
				var at: Vector3 = global_position - velocity * delta * randf() + Fx.ball() * size * 0.4
				_fx.flame(at, velocity * 0.75, size * 1.3, 1.4)
				_fx.black_smoke(at, velocity * 0.25 + Vector3.UP * 1.5, size * 1.5, randf_range(4.0, 6.5))
		if falling and global_position.y <= 1.0:
			var point := Vector3(global_position.x, 0.5, global_position.z)
			Explosion.spawn(self, point, 3.0, VectorMaterials.ORANGE, true)
			Sfx.play_at(self, Sfx.EXPLOSION, point, 22.0, 0.7)
			if is_instance_valid(_owner_sky):
				_owner_sky._on_crash(point)
				SmokeColumn.spawn(_owner_sky, point)
			queue_free()


## Columna de humo negro donde ha caído un avión: arde un rato y se va apagando.
class SmokeColumn extends Node3D:
	const TIME: float = 30.0

	var _life: float = TIME
	var _due: float = 0.0
	var _fx: Fx

	static func spawn(host: Node, point: Vector3) -> void:
		var column := SmokeColumn.new()
		host.add_child(column)
		column.global_position = point

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		if not is_instance_valid(_fx):
			_fx = Fx.on(self)
		var burn: float = clampf(_life / (TIME * 0.5), 0.0, 1.0)
		_due += delta * 5.0 * maxf(burn, 0.3)
		while _due >= 1.0:
			_due -= 1.0
			var at: Vector3 = global_position + Vector3(randf_range(-3.0, 3.0), randf_range(1.0, 3.0), randf_range(-3.0, 3.0))
			_fx.black_smoke(at, Vector3(randf_range(-0.5, 0.5), randf_range(5.0, 8.0), randf_range(-0.5, 0.5)), randf_range(4.5, 7.5), randf_range(7.0, 9.0))
			if burn > 0.3:
				_fx.flame(at, Vector3.ZERO, randf_range(3.0, 5.0) * burn, 1.3)


## Estallido de un proyectil antiaéreo: fogonazo, metralla y nubecilla negra que se queda
## flotando (los pone Fx), y el estampido, que llega más tarde cuanto más lejos está (el sonido
## viaja a 343 m/s).
class FlakBurst extends Node3D:
	var _time: float = 0.0
	var _size: float = 1.0
	var _boom_at: float = 0.0

	static func spawn(host: Node, point: Vector3, size: float) -> void:
		var burst := FlakBurst.new()
		burst._size = size
		# Antes de entrar en el árbol: _ready ya necesita saber dónde estalla.
		burst.position = point
		host.add_child(burst)

	func _ready() -> void:
		Fx.on(self).airburst(global_position, _size)
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			_boom_at = camera.global_position.distance_to(global_position) / 343.0

	func _process(delta: float) -> void:
		_time += delta
		if _time >= _boom_at:
			var distance: float = _boom_at * 343.0
			# Estampido seco de cerca, sordo y grave de lejos.
			Sfx.play_at(self, Sfx.FLAK, global_position, 14.0 if distance < 320.0 else 20.0, 1.0 if distance < 320.0 else 0.7)
			queue_free()
