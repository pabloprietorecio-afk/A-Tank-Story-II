class_name TankModel
## Construye el modelo de un vehículo histórico a partir de su ficha (TankStats) y su pintura.
## Toda la geometría se genera por código con MeshKit y se funde en tres mallas (casco,
## torreta y cañón) que comparten un único material (armor.gdshader): mucho detalle con muy
## pocas llamadas de dibujo. Las mallas se guardan en caché por modelo.

const HULL_SIZE := Vector3(3.2, 0.9, 4.6)
const TURRET_SIZE := Vector3(1.8, 0.7, 2.0)
const BARREL_SIZE := Vector3(0.22, 0.22, 2.6)

const PAINT := Color(1.0, 1.0, 1.0)
const PAINT_DARK := Color(0.8, 0.8, 0.8)
const DARK_METAL := Color(0.17, 0.16, 0.15)
const TRACK_METAL := Color(0.23, 0.21, 0.2)
const RUST := Color(0.3, 0.17, 0.1)
const RUBBER := Color(0.07, 0.07, 0.07)
const WOOD := Color(0.45, 0.32, 0.19)
const CANVAS := Color(0.42, 0.4, 0.28)
const SKIN := Color(0.78, 0.6, 0.47)

static var _cache: Dictionary = {}

var tank: Node3D
var stats: TankStats
var paint: Dictionary
var k: float
var own: Array[MeshInstance3D] = []
## Material compartido por las tres mallas (el tanque anima con él las orugas).
var material: ShaderMaterial

var turret: Node3D
var gun_pivot: Node3D
var muzzle: Marker3D
var hull_size: Vector3
var hull_bottom: float
var deck: float

var _player: bool = false
var _tracked: bool = true
var _front: float
var _rear: float
var _hw: float
var _mid: float
var _out: float
var _top_half: float
var _nose_y: float
var _glacis_len: float
var _glacis_angle: float
var _turret_size: Vector3
var _turret_pos: Vector3
var _barrel: Vector3
## Radio relativo del costado de la torreta abajo y arriba (para apoyar distintivos y equipo).
var _side_r: Vector2 = Vector2(0.5, 0.5)
var _g: MeshKit


static func build(owner_tank: Node3D, tank_stats: TankStats, tank_paint: Dictionary, is_player: bool) -> TankModel:
	var model := TankModel.new()
	model.tank = owner_tank
	model.stats = tank_stats
	model.paint = tank_paint
	model.k = tank_stats.body_scale
	model._player = is_player
	model._build()
	return model


## Pintura por defecto (verde oliva liso).
static func plain_paint(base: Color) -> Dictionary:
	return {"base": base, "mode": 0, "a": base, "b": base}


func _build() -> void:
	_layout()
	turret = Node3D.new()
	turret.name = "Turret"
	turret.position = _turret_pos
	tank.add_child(turret)
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	gun_pivot.position = Vector3(0.0, 0.05 * k, -_turret_size.z * 0.5)
	turret.add_child(gun_pivot)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.0, -_barrel.z - 0.15 * k)
	gun_pivot.add_child(muzzle)
	if stats.traverse_limit_deg > 0.0:
		turret.set_meta("traverse_limit", deg_to_rad(stats.traverse_limit_deg))

	var key: String = "%s|%.3f|%s|%s|%.2f|%.2f|%.2f" % [stats.id, k, _player, stats.hull_proportions, stats.turret_scale, stats.barrel_length, stats.barrel_thickness]
	var meshes: Array = _cache.get(key, [])
	if meshes.is_empty():
		_g = MeshKit.new()
		_hull_geometry()
		var hull_mesh: ArrayMesh = _g.commit()
		_g = MeshKit.new()
		_turret_geometry()
		var turret_mesh: ArrayMesh = _g.commit()
		_g = MeshKit.new()
		_gun_geometry()
		var gun_mesh: ArrayMesh = _g.commit()
		_g = null
		meshes = [hull_mesh, turret_mesh, gun_mesh]
		if stats.id != "":
			_cache[key] = meshes

	material = VectorMaterials.armor(paint, k, Fronts.ground_colors(GameSession.front)[2])
	material.set_shader_parameter("paint_base", paint.get("base", Color(0.35, 0.38, 0.25)))
	var parents: Array[Node3D] = [tank, turret, gun_pivot]
	for i in 3:
		var mesh: ArrayMesh = meshes[i]
		if mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		parents[i].add_child(instance)
		own.append(instance)


func _layout() -> void:
	hull_size = HULL_SIZE * stats.hull_proportions * k
	_tracked = stats.wheels <= 0
	hull_bottom = (0.25 if _tracked else 0.55) * k
	deck = hull_bottom + hull_size.y
	_front = -hull_size.z * 0.5
	_rear = hull_size.z * 0.5
	_hw = hull_size.x * 0.5
	_turret_size = TURRET_SIZE * stats.turret_scale * k
	if stats.casemate:
		_turret_size = Vector3(hull_size.x * 0.95, hull_size.y * 0.8, hull_size.z * 0.55)
		_turret_pos = Vector3(0.0, deck + _turret_size.y * 0.5, -hull_size.z * 0.08)
	else:
		_turret_pos = Vector3(0.0, deck + _turret_size.y * 0.5, 0.15 * k)
	_barrel = Vector3(BARREL_SIZE.x * stats.barrel_thickness, BARREL_SIZE.y * stats.barrel_thickness, BARREL_SIZE.z * stats.barrel_length) * k
	if _tracked:
		_mid = minf(0.93 * k, deck - 0.1 * k)
		_out = _hw + 0.46 * k
		_nose_y = lerpf(hull_bottom + 0.12 * k, _mid, 0.45)
	else:
		_mid = hull_bottom + hull_size.y * 0.45
		_out = _hw
		_nose_y = lerpf(hull_bottom, _mid, 0.5)
	_top_half = _out - (deck - _mid) * (0.75 if stats.sloped else 0.12)
	_glacis_len = hull_size.z * (0.27 if stats.sloped else 0.13)
	_glacis_angle = atan2(deck - _nose_y, _glacis_len)


# ---------------------------------------------------------------- utilidades

func _p(color: Color, kind: int) -> MeshKit:
	return _g.paint(color, kind)


## Cilindro tumbado a lo largo del eje Z, centrado en `pos`.
func _tube_z(pos: Vector3, radius: float, length: float, segments: int = 8, radius_front: float = -1.0) -> void:
	_g.at(pos, Vector3(-PI * 0.5, 0.0, 0.0))
	_g.tube(radius, radius if radius_front < 0.0 else radius_front, length, segments)


## Cilindro tumbado a lo largo del eje X, centrado en `pos`.
func _tube_x(pos: Vector3, radius: float, length: float, segments: int = 8) -> void:
	_g.at(pos, Vector3(0.0, 0.0, -PI * 0.5))
	_g.tube(radius, radius, length, segments)


## Punto del frontal del casco a la fracción `t` de su altura (0 = morro, 1 = cubierta).
func _glacis_point(t: float, lift: float = 0.0) -> Vector3:
	var z: float = _front + _glacis_len * t
	var y: float = lerpf(_nose_y, deck, t)
	var normal := Vector3(0.0, cos(_glacis_angle), -sin(_glacis_angle))
	return Vector3(0.0, y, z) + normal * lift


# ---------------------------------------------------------------- casco

func _hull_geometry() -> void:
	var g: MeshKit = _g
	var b: float = hull_bottom + (0.12 * k if _tracked else 0.0)
	var f: float = _front
	var r: float = _rear
	# Punto donde el frontal inclinado alcanza la altura de los guardabarros.
	var zm: float = f + _glacis_len * (_mid - _nose_y) / maxf(deck - _nose_y, 0.01)
	var tub_w: float = (hull_size.x - 0.16 * k) if _tracked else hull_size.x * 0.8

	# Barcaza inferior (entre las orugas o los ejes).
	g.at(Vector3.ZERO)
	_p(PAINT_DARK, MeshKit.ARMOR)
	g.prism(PackedVector2Array([
		Vector2(r - 0.35 * k, b), Vector2(f + 0.65 * k, b), Vector2(f, _nose_y),
		Vector2(zm, _mid), Vector2(r - 0.05 * k, _mid), Vector2(r, lerpf(b, _mid, 0.5)),
	]), tub_w)

	# Casco superior: sobresale por encima de las orugas; frontal, costados y zaga inclinados.
	_p(PAINT, MeshKit.ARMOR)
	var rear_top: float = r - (0.5 * k if stats.sloped else 0.15 * k)
	var front_top: float = f + _glacis_len
	g.hexa([
		Vector3(-_out, _mid, zm), Vector3(_out, _mid, zm), Vector3(_out, _mid, r - 0.05 * k), Vector3(-_out, _mid, r - 0.05 * k),
		Vector3(-_top_half, deck, front_top), Vector3(_top_half, deck, front_top), Vector3(_top_half, deck, rear_top), Vector3(-_top_half, deck, rear_top),
	])

	if _tracked:
		for side in [-1.0, 1.0]:
			_running_gear(side)
	else:
		_wheels()

	if stats.casemate:
		_casemate()
	else:
		# Anillo de la torreta.
		g.at(Vector3(_turret_pos.x, deck + 0.02 * k, _turret_pos.z))
		_p(DARK_METAL, MeshKit.STEEL)
		g.tube(minf(_turret_size.x, _turret_size.z) * 0.4, minf(_turret_size.x, _turret_size.z) * 0.4, 0.06 * k, 14)

	_hull_details(zm, front_top, rear_top)
	_hull_markings()


## Orugas, ruedas de rodaje, rueda motriz, tensora y rodillos de un lado.
func _running_gear(side: float) -> void:
	var g: MeshKit = _g
	var th: float = 0.06 * k
	var track_w: float = 0.6 * k
	var track_x: float = side * (_hw + 0.2 * k)
	var track_h: float = 0.85 * k
	var half_len: float = hull_size.z * 0.51
	var rf: float = 0.3 * k
	var ri: float = 0.27 * k
	var sprocket := Vector2(-half_len + rf + th, track_h - rf - th)
	var idler := Vector2(half_len - ri - th, track_h - ri - th - 0.02 * k)

	# Estilo del tren de rodaje según nación y tamaño.
	var count: int = 6
	var rw: float = 0.24 * k
	var rollers: int = 3
	var interleaved: bool = false
	match stats.nation:
		"SU":
			count = 5 if k < 1.4 else 6
			rw = 0.36 * k if k < 1.2 else 0.3 * k
			rollers = 0 if k < 1.2 else 3
		"DE":
			if k >= 1.05 or stats.sloped:
				count = 8
				rw = 0.36 * k
				rollers = 0
				interleaved = true
			elif stats.id == "panzer4":
				count = 8
				rw = 0.2 * k
				rollers = 4
			else:
				count = 6
				rw = 0.26 * k
				rollers = 3
		"UK":
			if k >= 1.2:
				count = 11
				rw = 0.14 * k
				rollers = 0
			else:
				count = 5
				rw = 0.36 * k
				rollers = 0
		_:
			if k >= 1.3:
				count = 6
				rw = 0.33 * k
				rollers = 5

	var z_first: float = -half_len + rf + 0.6 * k
	var z_last: float = half_len - ri - 0.55 * k
	var path := PackedVector2Array()
	path.append(Vector2(z_first - rw * 0.3, 0.0))
	path.append(Vector2(z_last + rw * 0.3, 0.0))
	for i in 8:
		var a: float = deg_to_rad(-50.0 + 20.0 * i)
		path.append(idler + Vector2(cos(a), sin(a)) * (ri + th))
	for i in 8:
		var a: float = deg_to_rad(90.0 + 20.0 * i)
		path.append(sprocket + Vector2(cos(a), sin(a)) * (rf + th))
	_p(TRACK_METAL, MeshKit.TRACK)
	g.at(Vector3.ZERO)
	g.belt(path, track_w, track_x, th)

	# Ruedas de rodaje.
	var wheel_x: float = track_x + side * (track_w * 0.5 - 0.11 * k)
	for i in count:
		var z: float = lerpf(z_first, z_last, float(i) / float(count - 1))
		var x: float = wheel_x
		if interleaved and i % 2 == 1:
			x -= side * 0.13 * k
		_wheel(Vector3(x, rw + th, z), rw, 0.16 * k, side, not (stats.nation == "SU" and k >= 1.2))
	# Bogies de los carros americanos y británicos pequeños: soporte entre cada par de ruedas.
	if stats.nation == "US" and k < 1.3:
		_p(PAINT_DARK, MeshKit.CAST)
		for i in count / 2:
			var z: float = lerpf(z_first, z_last, (i * 2 + 0.5) / float(count - 1))
			g.at(Vector3(wheel_x + side * 0.02 * k, rw + th + 0.2 * k, z))
			g.taper(Vector2(0.12 * k, 0.75 * k), Vector2(0.12 * k, 0.3 * k), 0.22 * k)
	# Rodillos de retorno.
	for i in rollers:
		var z: float = lerpf(z_first, z_last, (i + 0.5) / float(rollers))
		_wheel(Vector3(wheel_x, track_h - th - 0.1 * k, z), 0.1 * k, 0.12 * k, side, true)
	# Rueda motriz dentada delante y tensora detrás.
	_sprocket(Vector3(wheel_x, sprocket.y, sprocket.x), rf, side, true)
	_sprocket(Vector3(wheel_x, idler.y, idler.x), ri, side, false)

	# Guardabarros delantero y trasero.
	_p(PAINT_DARK, MeshKit.ARMOR)
	var fender_x: float = side * (_hw + 0.24 * k)
	g.at(Vector3(fender_x, _mid - 0.02 * k, -half_len + 0.6 * k))
	g.box(Vector3(0.66 * k, 0.03 * k, 1.3 * k))
	g.at(Vector3(fender_x, _mid - 0.13 * k, -half_len - 0.1 * k), Vector3(deg_to_rad(-50.0), 0.0, 0.0))
	g.box(Vector3(0.66 * k, 0.03 * k, 0.32 * k))
	g.at(Vector3(fender_x, _mid - 0.11 * k, half_len + 0.02 * k), Vector3(deg_to_rad(40.0), 0.0, 0.0))
	g.box(Vector3(0.66 * k, 0.03 * k, 0.3 * k))

	# Faldones laterales (Schürzen): planchas colgadas con pequeñas separaciones.
	if stats.skirts:
		_p(PAINT, MeshKit.ARMOR)
		var plates: int = 5
		var plate_len: float = hull_size.z * 0.86 / plates
		for i in plates:
			g.at(Vector3(side * (_hw + 0.56 * k), _mid - 0.2 * k + (0.015 * k if i % 2 == 0 else 0.0), -hull_size.z * 0.43 + plate_len * (i + 0.5)))
			g.box(Vector3(0.03 * k, 0.5 * k, plate_len * 0.95))
		# Soportes de los faldones.
		_p(DARK_METAL, MeshKit.STEEL)
		for i in plates + 1:
			g.at(Vector3(side * (_hw + 0.51 * k), _mid + 0.04 * k, -hull_size.z * 0.43 + plate_len * i))
			g.box(Vector3(0.1 * k, 0.03 * k, 0.04 * k))


## Rueda con llanta de goma (o de acero) y plato con buje.
func _wheel(center: Vector3, radius: float, width: float, side: float, rubber: bool) -> void:
	var g: MeshKit = _g
	var w: float = width * 0.5
	g.at(center, Vector3(0.0, 0.0, -side * PI * 0.5))
	_p(RUBBER if rubber else DARK_METAL, MeshKit.RUBBER if rubber else MeshKit.STEEL)
	g.lathe(PackedVector2Array([Vector2(0.0, -w), Vector2(radius, -w), Vector2(radius, w), Vector2(radius * 0.84, w)]), 12)
	_p(PAINT_DARK, MeshKit.CAST)
	g.lathe(PackedVector2Array([
		Vector2(radius * 0.84, w), Vector2(radius * 0.76, w * 0.55), Vector2(radius * 0.36, w * 0.45),
		Vector2(radius * 0.3, w * 1.1), Vector2(radius * 0.14, w * 1.25), Vector2(0.0, w * 1.25),
	]), 12)


func _sprocket(center: Vector3, radius: float, side: float, toothed: bool) -> void:
	var g: MeshKit = _g
	var w: float = 0.11 * k
	g.at(center, Vector3(0.0, 0.0, -side * PI * 0.5))
	_p(DARK_METAL if toothed else PAINT_DARK, MeshKit.STEEL if toothed else MeshKit.CAST)
	if toothed:
		# Corona dentada: polígono con dientes alternos.
		var teeth: int = 16
		for i in teeth:
			var a0: float = TAU * i / teeth
			var a1: float = TAU * (i + 1) / teeth
			var r0: float = radius * (1.0 if i % 2 == 0 else 0.88)
			g.face([Vector3(cos(a0) * r0, w, sin(a0) * r0), Vector3(cos(a1) * r0, w, sin(a1) * r0), Vector3(cos(a1) * radius * 0.5, w, sin(a1) * radius * 0.5), Vector3(cos(a0) * radius * 0.5, w, sin(a0) * radius * 0.5)], Vector3.UP)
		g.lathe(PackedVector2Array([Vector2(0.0, -w), Vector2(radius * 0.88, -w), Vector2(radius * 0.88, w)]), 16)
		_p(PAINT_DARK, MeshKit.CAST)
		g.lathe(PackedVector2Array([Vector2(radius * 0.5, w), Vector2(radius * 0.42, w * 1.6), Vector2(radius * 0.2, w * 1.9), Vector2(0.0, w * 1.9)]), 10)
	else:
		g.lathe(PackedVector2Array([
			Vector2(0.0, -w), Vector2(radius, -w), Vector2(radius, w), Vector2(radius * 0.85, w),
			Vector2(radius * 0.7, w * 0.4), Vector2(radius * 0.3, w * 0.4), Vector2(radius * 0.22, w * 1.3), Vector2(0.0, w * 1.3),
		]), 12)


## Vehículos de ruedas: neumáticos grandes con dibujo, bujes y guardabarros.
func _wheels() -> void:
	var g: MeshKit = _g
	var per_side: int = stats.wheels / 2
	var radius: float = 0.48 * k
	for side in [-1.0, 1.0]:
		for i in per_side:
			var z: float = lerpf(_front * 0.7, _rear * 0.7, float(i) / maxf(per_side - 1, 1))
			var center := Vector3(side * (_hw + 0.2 * k), radius, z)
			g.at(center, Vector3(0.0, 0.0, -side * PI * 0.5))
			var w: float = 0.17 * k
			_p(RUBBER, MeshKit.RUBBER)
			g.lathe(PackedVector2Array([
				Vector2(0.0, -w), Vector2(radius * 0.9, -w), Vector2(radius, -w * 0.6), Vector2(radius, w * 0.6),
				Vector2(radius * 0.9, w), Vector2(radius * 0.6, w),
			]), 14, 1.0, 1.0, true)
			_p(PAINT_DARK, MeshKit.CAST)
			g.lathe(PackedVector2Array([
				Vector2(radius * 0.6, w), Vector2(radius * 0.52, w * 0.4), Vector2(radius * 0.25, w * 0.4),
				Vector2(radius * 0.2, w * 1.2), Vector2(0.0, w * 1.2),
			]), 12)
			# Guardabarros.
			_p(PAINT_DARK, MeshKit.ARMOR)
			g.at(Vector3(side * (_hw + 0.22 * k), radius * 2.0 + 0.08 * k, z))
			g.box(Vector3(0.42 * k, 0.035 * k, 0.8 * k))
			for end in [-1.0, 1.0]:
				g.at(Vector3(side * (_hw + 0.22 * k), radius * 2.0 - 0.04 * k, z + end * 0.52 * k), Vector3(end * deg_to_rad(40.0), 0.0, 0.0))
				g.box(Vector3(0.42 * k, 0.035 * k, 0.34 * k))
	# Ejes.
	_p(DARK_METAL, MeshKit.STEEL)
	for i in per_side:
		var z: float = lerpf(_front * 0.7, _rear * 0.7, float(i) / maxf(per_side - 1, 1))
		_tube_x(Vector3(0.0, radius, z), 0.07 * k, hull_size.x + 0.3 * k, 6)


## Superestructura fija de los cazacarros (el cañón apenas gira dentro de ella).
func _casemate() -> void:
	var g: MeshKit = _g
	var ts: Vector3 = _turret_size
	var base := Vector3(0.0, deck, _turret_pos.z)
	_p(PAINT, MeshKit.ARMOR)
	if stats.open_top:
		# Escudo de tres caras, abierto por arriba y por detrás.
		var t: float = 0.05 * k
		g.at(base + Vector3(0.0, ts.y * 0.62, -ts.z * 0.36), Vector3(deg_to_rad(-18.0), 0.0, 0.0))
		g.box(Vector3(ts.x * 0.86, ts.y * 1.3, t))
		for side in [-1.0, 1.0]:
			g.at(base + Vector3(side * ts.x * 0.44, ts.y * 0.6, -ts.z * 0.05), Vector3(0.0, 0.0, side * deg_to_rad(8.0)))
			g.box(Vector3(t, ts.y * 1.2, ts.z * 0.62))
		# Recámara del cañón y cajas de munición a la vista.
		_p(DARK_METAL, MeshKit.STEEL)
		g.at(base + Vector3(0.0, ts.y * 0.6, -ts.z * 0.12))
		g.box(Vector3(0.3 * k, 0.3 * k, 0.8 * k))
		_p(Color(0.3, 0.3, 0.22), MeshKit.MATTE)
		for side in [-1.0, 1.0]:
			g.at(base + Vector3(side * ts.x * 0.28, 0.16 * k, ts.z * 0.05))
			g.box(Vector3(0.3 * k, 0.32 * k, 0.5 * k))
	else:
		var bottom := Vector2(minf(ts.x * 1.04, _top_half * 2.0), ts.z)
		var top := Vector2(ts.x * 0.8, ts.z * 0.72)
		g.at(base)
		g.taper(bottom, top, ts.y, Vector3.ZERO, Vector2(0.0, ts.z * 0.07))
		_side_r = Vector2(bottom.x * 0.5 / ts.x, top.x * 0.5 / ts.x)
		var roof: float = ts.y
		# Escotillas, periscopios y ventilador del techo.
		_p(PAINT_DARK, MeshKit.ARMOR)
		for side in [-1.0, 1.0]:
			g.at(base + Vector3(side * ts.x * 0.18, roof + 0.015 * k, ts.z * 0.2))
			g.box(Vector3(0.5 * k, 0.03 * k, 0.5 * k))
		_p(Color(0.08, 0.1, 0.12), MeshKit.GLASS)
		g.at(base + Vector3(-ts.x * 0.25, roof + 0.05 * k, -ts.z * 0.12))
		g.box(Vector3(0.18 * k, 0.1 * k, 0.1 * k))
		if stats.has_dome:
			_cupola(base + Vector3(ts.x * 0.2, roof, ts.z * 0.15))


# ---------------------------------------------------------------- detalles del casco

func _hull_details(zm: float, front_top: float, rear_top: float) -> void:
	var g: MeshKit = _g
	var f: float = _front
	var r: float = _rear
	var slope := Vector3(-_glacis_angle, 0.0, 0.0)

	for side in [-1.0, 1.0]:
		# Faros (delante) y pilotos rojos (detrás): dejan claro el frente y la cola.
		var lamp := Vector3(side * (_out - 0.2 * k), _mid + 0.14 * k, zm - 0.02 * k)
		if not _tracked:
			lamp = Vector3(side * _hw * 0.75, _mid + 0.1 * k, zm - 0.05 * k)
		_p(PAINT_DARK, MeshKit.CAST)
		_tube_z(lamp, 0.095 * k, 0.12 * k, 8)
		_p(DARK_METAL, MeshKit.STEEL)
		g.at(lamp + Vector3(0.0, -0.1 * k, 0.02 * k))
		g.box(Vector3(0.03 * k, 0.12 * k, 0.03 * k))
		_p(Color(1.0, 0.95, 0.75), MeshKit.LIGHT)
		g.at(lamp + Vector3(0.0, 0.0, -0.065 * k), Vector3(0.0, PI, 0.0))
		g.disc(0.075 * k, 10)
		_p(Color(1.0, 0.08, 0.05), MeshKit.LIGHT)
		g.at(Vector3(side * (_out - 0.22 * k), _mid + 0.06 * k, r - 0.03 * k))
		g.box(Vector3(0.16 * k, 0.08 * k, 0.04 * k))
		# Ganchos de remolque.
		_p(DARK_METAL, MeshKit.STEEL)
		g.at(Vector3(side * _hw * 0.55, _nose_y - 0.08 * k, f + 0.02 * k))
		g.box(Vector3(0.08 * k, 0.16 * k, 0.14 * k))
		g.at(Vector3(side * _hw * 0.55, lerpf(hull_bottom, _mid, 0.55), r + 0.02 * k))
		g.box(Vector3(0.08 * k, 0.16 * k, 0.12 * k))

	# Escapes.
	_p(RUST, MeshKit.STEEL)
	if stats.nation == "DE" and k >= 1.3:
		for side in [-1.0, 1.0]:
			g.at(Vector3(side * _hw * 0.42, _mid + 0.08 * k, r + 0.13 * k))
			g.tube(0.13 * k, 0.13 * k, 0.55 * k, 10)
			g.at(Vector3(side * _hw * 0.42, _mid + 0.4 * k, r + 0.13 * k))
			g.tube(0.07 * k, 0.07 * k, 0.12 * k, 8)
	else:
		for side in [-1.0, 1.0]:
			_tube_z(Vector3(side * _hw * 0.5, lerpf(hull_bottom, _mid, 0.75), r + 0.1 * k), 0.07 * k, 0.4 * k, 8)

	# Rejillas del motor: lamas a ambos lados de la cubierta trasera.
	var deck_len: float = rear_top - (_turret_pos.z + _turret_size.z * 0.55)
	if deck_len > 0.5 * k and not stats.casemate:
		var slats: int = clampi(int(deck_len / (0.13 * k)), 3, 7)
		for side in [-1.0, 1.0]:
			_p(DARK_METAL, MeshKit.STEEL)
			g.at(Vector3(side * _top_half * 0.66, deck + 0.012 * k, rear_top - slats * 0.065 * k - 0.1 * k))
			g.box(Vector3(_top_half * 0.5, 0.02 * k, slats * 0.13 * k + 0.06 * k))
			_p(PAINT_DARK, MeshKit.ARMOR)
			for i in slats:
				g.at(Vector3(side * _top_half * 0.66, deck + 0.04 * k, rear_top - 0.16 * k - i * 0.13 * k), Vector3(deg_to_rad(25.0), 0.0, 0.0))
				g.box(Vector3(_top_half * 0.46, 0.015 * k, 0.1 * k))

	# Escotillas de conductor y radio, visor y ametralladora de casco.
	_p(PAINT_DARK, MeshKit.ARMOR)
	if stats.sloped:
		for side in [-1.0, 1.0]:
			g.at(_glacis_point(0.7, 0.02 * k) + Vector3(side * _hw * 0.45, 0.0, 0.0), slope)
			g.box(Vector3(0.5 * k, 0.04 * k, 0.42 * k))
	else:
		var hatch_z: float = front_top + 0.32 * k
		if hatch_z < _turret_pos.z - _turret_size.z * 0.55:
			for side in [-1.0, 1.0]:
				g.at(Vector3(side * _top_half * 0.5, deck + 0.015 * k, hatch_z))
				g.box(Vector3(0.48 * k, 0.03 * k, 0.4 * k))
	_p(Color(0.08, 0.1, 0.12), MeshKit.GLASS)
	g.at(_glacis_point(0.82, 0.035 * k) + Vector3(-_hw * 0.45, 0.0, 0.0), slope)
	g.box(Vector3(0.3 * k, 0.03 * k, 0.07 * k))
	if stats.bow_mg:
		var mount: Vector3 = _glacis_point(0.62, 0.0) + Vector3(_hw * 0.45, 0.0, 0.0)
		_p(PAINT_DARK, MeshKit.CAST)
		g.at(mount)
		g.blob(Vector3.ONE * 0.12 * k, 8, 4)
		_p(DARK_METAL, MeshKit.STEEL)
		_tube_z(mount + Vector3(0.0, 0.0, -0.3 * k), 0.028 * k, 0.5 * k, 6)

	# Eslabones de repuesto sobre el frontal.
	_p(TRACK_METAL, MeshKit.STEEL)
	for i in 5:
		g.at(_glacis_point(0.32, 0.03 * k) + Vector3((i - 2) * 0.24 * k, 0.0, 0.0), slope)
		g.box(Vector3(0.2 * k, 0.05 * k, 0.16 * k))

	# Herramientas: pala y palanca sobre el costado derecho, taco de madera a la izquierda.
	var tool_y: float = deck + 0.035 * k
	var tool_x: float = _top_half - 0.14 * k
	_p(WOOD, MeshKit.WOOD)
	_tube_z(Vector3(tool_x, tool_y, 0.2 * k), 0.022 * k, 1.0 * k, 5)
	_p(DARK_METAL, MeshKit.STEEL)
	g.at(Vector3(tool_x, tool_y, -0.42 * k))
	g.box(Vector3(0.16 * k, 0.02 * k, 0.26 * k))
	_tube_z(Vector3(tool_x - 0.1 * k, tool_y, 0.3 * k), 0.016 * k, 1.3 * k, 5)
	_p(WOOD, MeshKit.WOOD)
	g.at(Vector3(-tool_x, deck + 0.07 * k, -0.5 * k))
	g.box(Vector3(0.22 * k, 0.14 * k, 0.4 * k))

	# Cable de remolque enrollado a lo largo del costado izquierdo.
	_p(DARK_METAL, MeshKit.STEEL)
	_tube_z(Vector3(-tool_x, deck + 0.025 * k, 0.5 * k), 0.02 * k, 1.5 * k, 5)

	# Equipo propio de cada ejército en la zaga.
	var rear_y: float = deck
	match stats.nation:
		"SU":
			# Depósitos exteriores de combustible y tronco para desatascar.
			_p(PAINT_DARK, MeshKit.CAST)
			for side in [-1.0, 1.0]:
				_tube_z(Vector3(side * (_top_half - 0.04 * k), rear_y + 0.12 * k, r - 0.85 * k), 0.17 * k, 0.75 * k, 10)
			_p(DARK_METAL, MeshKit.STEEL)
			for side in [-1.0, 1.0]:
				for band in [-0.25, 0.25]:
					_tube_z(Vector3(side * (_top_half - 0.04 * k), rear_y + 0.12 * k, r - 0.85 * k + band * k), 0.178 * k, 0.04 * k, 10)
			_p(WOOD, MeshKit.WOOD)
			_tube_z(Vector3(_top_half + 0.05 * k, rear_y - 0.03 * k, -0.2 * k), 0.1 * k, hull_size.z * 0.4, 8)
		"DE":
			# Bidones de combustible y gato.
			_p(Color(0.36, 0.34, 0.29), MeshKit.MATTE)
			for side in [-1.0, 1.0]:
				_jerrycan(Vector3(side * (_top_half - 0.14 * k), rear_y, rear_top - 0.2 * k))
			_p(DARK_METAL, MeshKit.STEEL)
			g.at(Vector3(0.0, rear_y + 0.07 * k, rear_top - 0.12 * k))
			g.box(Vector3(0.5 * k, 0.12 * k, 0.14 * k))
		"UK":
			# Cajones de estiba en los costados.
			_p(PAINT_DARK, MeshKit.ARMOR)
			for side in [-1.0, 1.0]:
				g.at(Vector3(side * (_top_half - 0.18 * k), rear_y + 0.13 * k, rear_top - 0.5 * k))
				g.box(Vector3(0.32 * k, 0.26 * k, 0.8 * k))
		_:
			# Petates y lonas atados en la zaga, y bidones.
			_p(CANVAS, MeshKit.CANVAS)
			g.at(Vector3(0.0, rear_y + 0.12 * k, rear_top - 0.2 * k))
			g.blob(Vector3(_top_half * 0.7, 0.14 * k, 0.2 * k), 8, 4)
			_p(Color(0.3, 0.33, 0.22), MeshKit.MATTE)
			for side in [-1.0, 1.0]:
				_jerrycan(Vector3(side * (_top_half - 0.14 * k), rear_y, rear_top - 0.55 * k))

	if _player:
		# Galones amarillos sobre el frontal: distinguen el carro propio en las vistas exteriores.
		_p(Color(1.0, 0.85, 0.1), MeshKit.DECAL)
		for side in [-1.0, 1.0]:
			g.at(Vector3(side * _top_half * 0.3, deck + 0.012 * k, front_top + 0.22 * k), Vector3(0.0, side * deg_to_rad(-38.0), 0.0))
			g.box(Vector3(0.14 * k, 0.02 * k, _top_half * 0.7))


func _jerrycan(base: Vector3) -> void:
	var g: MeshKit = _g
	g.at(base + Vector3(0.0, 0.2 * k, 0.0))
	g.box(Vector3(0.15 * k, 0.4 * k, 0.3 * k))
	g.at(base + Vector3(0.0, 0.43 * k, 0.0))
	g.box(Vector3(0.05 * k, 0.06 * k, 0.16 * k))


## Distintivos nacionales en los costados y en la cubierta trasera (identificación aérea).
func _hull_markings() -> void:
	var g: MeshKit = _g
	var side_height: float = deck - _mid
	# En los costados del casco cuando son altos (Sherman) o cuando es una casamata.
	if stats.casemate and not stats.open_top:
		var ts: Vector3 = _turret_size
		var tilt: float = atan2((_side_r.x - _side_r.y) * ts.x, ts.y)
		for side in [-1.0, 1.0]:
			var x: float = side * ((_side_r.x + _side_r.y) * 0.5 * ts.x + 0.012 * k)
			g.at(Vector3(x, deck + ts.y * 0.5, _turret_pos.z + ts.z * 0.07), Vector3(-tilt, side * PI * 0.5, 0.0))
			_marking(minf(0.7 * k, ts.y * 0.8))
	elif side_height >= 0.36 * k and not stats.skirts:
		var tilt: float = atan2(_out - _top_half, side_height)
		for side in [-1.0, 1.0]:
			g.at(Vector3(side * ((_out + _top_half) * 0.5 + 0.012 * k), (_mid + deck) * 0.5, hull_size.z * 0.12), Vector3(-tilt, side * PI * 0.5, 0.0))
			_marking(side_height * 0.8)
	# Sobre la cubierta trasera, entre las rejillas.
	var rear_top: float = _rear - (0.5 * k if stats.sloped else 0.15 * k)
	var free: float = rear_top - (_turret_pos.z + _turret_size.z * 0.5 + (0.42 * k if stats.nation == "DE" else 0.2 * k))
	if free > 0.5 * k and not stats.casemate:
		g.at(Vector3(0.0, deck + 0.012 * k, rear_top - free * 0.5), Vector3(-PI * 0.5, 0.0, 0.0))
		_marking(minf(minf(free * 0.85, _top_half * 0.6), 0.9 * k))


## Dibuja el distintivo de la nación en el plano XY local (mirando a +Z).
func _marking(size: float) -> void:
	var g: MeshKit = _g
	var lift: float = 0.004 * k
	match stats.nation:
		"DE":
			# Balkenkreuz: cruz negra con bordes blancos.
			_p(Color(0.93, 0.93, 0.9), MeshKit.DECAL)
			g.rect(Vector2(size * 0.4, size))
			g.rect(Vector2(size, size * 0.4))
			_p(Color(0.04, 0.04, 0.04), MeshKit.DECAL)
			g.rect(Vector2(size * 0.24, size * 0.94), Vector3(0.0, 0.0, lift))
			g.rect(Vector2(size * 0.94, size * 0.24), Vector3(0.0, 0.0, lift))
		"SU":
			_p(Color(0.8, 0.07, 0.05), MeshKit.DECAL)
			g.star(size * 0.55)
		"UK":
			_p(Color(0.1, 0.2, 0.55), MeshKit.DECAL)
			g.disc(size * 0.5, 18)
			_p(Color(0.93, 0.93, 0.9), MeshKit.DECAL)
			g.disc(size * 0.34, 16, lift)
			_p(Color(0.75, 0.08, 0.06), MeshKit.DECAL)
			g.disc(size * 0.18, 14, lift * 2.0)
		_:
			_p(Color(0.93, 0.93, 0.9), MeshKit.DECAL)
			g.star(size * 0.55)


# ---------------------------------------------------------------- torreta

func _turret_geometry() -> void:
	if stats.casemate:
		return
	var g: MeshKit = _g
	var ts: Vector3 = _turret_size
	var h: float = ts.y * 0.5
	var octagon: float = PI / 8.0
	var facet: float = cos(octagon)
	# Radio relativo de la parte plana del techo.
	var roof_r: float = 0.44
	g.at(Vector3.ZERO)
	if stats.open_top:
		# Torreta abierta: paredes inclinadas, interior con suelo y recámara.
		_side_r = Vector2(0.56, 0.5) * facet
		_p(PAINT, MeshKit.ARMOR)
		g.lathe(PackedVector2Array([
			Vector2(0.56, -h), Vector2(0.5, h), Vector2(0.45, h), Vector2(0.49, -h + 0.06 * k), Vector2(0.0, -h + 0.06 * k),
		]), 8, ts.x, ts.z, false, true, octagon)
		_p(DARK_METAL, MeshKit.STEEL)
		g.at(Vector3(0.0, 0.0, -ts.z * 0.2))
		g.box(Vector3(0.26 * k, 0.26 * k, ts.z * 0.5))
		if not _player:
			_crewman(Vector3(ts.x * 0.2, -h + 0.06 * k - 0.05 * k, ts.z * 0.1))
			_crewman(Vector3(-ts.x * 0.22, -h + 0.06 * k - 0.12 * k, ts.z * 0.18))
	elif stats.round_turret:
		# Torreta de fundición: redondeada, con nuca.
		_side_r = Vector2(0.52, 0.5)
		roof_r = 0.3
		_p(PAINT, MeshKit.CAST)
		g.lathe(PackedVector2Array([
			Vector2(0.0, -h), Vector2(0.49, -h), Vector2(0.535, -h * 0.35), Vector2(0.52, h * 0.3),
			Vector2(0.44, h * 0.8), Vector2(0.3, h), Vector2(0.0, h),
		]), 18, ts.x, ts.z * 0.95, true)
		g.at(Vector3(0.0, -h * 0.05, ts.z * 0.4))
		g.blob(Vector3(ts.x * 0.36, h * 0.8, ts.z * 0.28), 12, 5)
	elif stats.nation == "UK" or stats.nation == "US":
		# Torreta de planchas atornilladas, casi vertical.
		_side_r = Vector2(0.5, 0.47)
		_p(PAINT, MeshKit.ARMOR)
		g.taper(Vector2(ts.x, ts.z), Vector2(ts.x * 0.94, ts.z * 0.92), ts.y, Vector3(0.0, -h, 0.0))
		g.at(Vector3(0.0, -h * 0.1, -ts.z * 0.5))
		g.taper(Vector2(ts.x * 0.8, 0.3 * k), Vector2(ts.x * 0.7, 0.16 * k), ts.y * 0.8, Vector3(0.0, -h * 0.8, 0.0))
	else:
		# Torreta soldada de ocho caras.
		var top: float = 0.5 if (stats.nation == "DE" and k >= 1.3 and not stats.sloped) else 0.42
		_side_r = Vector2(0.52, top) * facet
		roof_r = top * 0.95
		_p(PAINT, MeshKit.ARMOR)
		g.lathe(PackedVector2Array([Vector2(0.0, -h), Vector2(0.52, -h), Vector2(top, h), Vector2(0.0, h)]), 8, ts.x, ts.z, false, true, octagon)

	var roof: float = h
	if not stats.open_top:
		# Cajón o lona en la nuca de la torreta.
		if stats.nation == "DE":
			_p(PAINT_DARK, MeshKit.ARMOR)
			g.at(Vector3(0.0, -h * 0.1, ts.z * 0.5 + 0.17 * k))
			g.box(Vector3(ts.x * 0.55, ts.y * 0.6, 0.4 * k))
		elif stats.nation != "SU":
			_p(CANVAS, MeshKit.CANVAS)
			_g.at(Vector3(0.0, h * 0.2, ts.z * (0.66 if stats.round_turret else 0.5) + 0.12 * k), Vector3(0.0, 0.0, -PI * 0.5))
			_g.tube(0.14 * k, 0.14 * k, ts.x * 0.6, 8)
		# Escotilla del cargador con bisagras, periscopios y ventilador.
		_p(PAINT_DARK, MeshKit.ARMOR)
		g.at(Vector3(-ts.x * roof_r * 0.5, roof + 0.015 * k, ts.z * 0.12))
		g.box(Vector3(0.46 * k, 0.03 * k, 0.42 * k))
		_p(DARK_METAL, MeshKit.STEEL)
		g.at(Vector3(-ts.x * roof_r * 0.5, roof + 0.04 * k, ts.z * 0.12 + 0.22 * k))
		g.box(Vector3(0.3 * k, 0.03 * k, 0.04 * k))
		_p(Color(0.08, 0.1, 0.12), MeshKit.GLASS)
		for i in 2:
			g.at(Vector3((0.5 - i) * ts.x * roof_r * 0.9, roof + 0.05 * k, -ts.z * roof_r * 0.55))
			g.box(Vector3(0.16 * k, 0.1 * k, 0.1 * k))
		_p(PAINT_DARK, MeshKit.CAST)
		g.at(Vector3(0.0, roof, ts.z * roof_r * 0.75))
		g.blob(Vector3(0.14 * k, 0.07 * k, 0.14 * k), 8, 3)
		var hatch := Vector3(ts.x * roof_r * 0.5, roof, ts.z * 0.14)
		if stats.has_dome:
			_cupola(hatch)
		else:
			_p(PAINT_DARK, MeshKit.ARMOR)
			g.at(hatch + Vector3(0.0, 0.02 * k, 0.0))
			g.tube(0.25 * k, 0.25 * k, 0.04 * k, 10)
		if not _player:
			# Comandante asomado, con la tapa de la escotilla abierta detrás.
			_crewman(hatch + Vector3(0.0, (0.26 if stats.has_dome else 0.02) * k - 0.28 * k, 0.0))
			_p(PAINT_DARK, MeshKit.ARMOR)
			g.at(hatch + Vector3(0.0, (0.5 if stats.has_dome else 0.26) * k, 0.27 * k), Vector3(deg_to_rad(80.0), 0.0, 0.0))
			g.tube(0.24 * k, 0.24 * k, 0.03 * k, 10)
		# Asideros para la infantería que viajaba sobre los carros soviéticos.
		var side_mid: float = (_side_r.x + _side_r.y) * 0.5 * ts.x
		if stats.nation == "SU":
			_p(DARK_METAL, MeshKit.STEEL)
			for side in [-1.0, 1.0]:
				_tube_z(Vector3(side * (side_mid + 0.06 * k), 0.0, ts.z * 0.05), 0.014 * k, ts.z * 0.4, 4)
				for end in [-1.0, 1.0]:
					_tube_x(Vector3(side * (side_mid + 0.02 * k), 0.0, ts.z * 0.05 + end * ts.z * 0.2), 0.014 * k, 0.1 * k, 4)
		if stats.nation == "US":
			_roof_mg(Vector3(-ts.x * roof_r * 0.2, roof, ts.z * roof_r * 0.5))
		_turret_markings()
	if stats.has_antenna:
		_p(DARK_METAL, MeshKit.STEEL)
		var foot := Vector3(-ts.x * _side_r.y * 0.75, roof, ts.z * 0.3)
		g.at(foot + Vector3(0.0, 0.06 * k, 0.0))
		g.tube(0.04 * k, 0.03 * k, 0.12 * k, 6)
		g.at(foot + Vector3(0.0, 1.4 * k, 0.0))
		g.tube(0.014 * k, 0.005 * k, 2.6 * k, 4)


func _turret_markings() -> void:
	var ts: Vector3 = _turret_size
	var side_height: float = deck - _mid
	if stats.round_turret and side_height >= 0.36 * k and not stats.skirts:
		return
	var tilt: float = atan2((_side_r.x - _side_r.y) * ts.x, ts.y)
	var size: float = minf(0.72 * k, ts.y * 0.82) * (0.8 if stats.round_turret else 1.0)
	var bulge: float = 0.03 * k if stats.round_turret else 0.012 * k
	for side in [-1.0, 1.0]:
		_g.at(Vector3(side * ((_side_r.x + _side_r.y) * 0.5 * ts.x + bulge), -ts.y * 0.04, ts.z * 0.02), Vector3(-tilt, side * PI * 0.5, 0.0))
		_marking(size)


## Cúpula del comandante con mirillas.
func _cupola(base: Vector3) -> void:
	var g: MeshKit = _g
	_p(PAINT_DARK, MeshKit.CAST)
	g.at(base)
	g.lathe(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.31 * k, 0.0), Vector2(0.31 * k, 0.2 * k), Vector2(0.27 * k, 0.26 * k), Vector2(0.2 * k, 0.26 * k),
		Vector2(0.2 * k, 0.2 * k), Vector2(0.0, 0.2 * k),
	]), 12)
	_p(Color(0.08, 0.1, 0.12), MeshKit.GLASS)
	for i in 6:
		var a: float = TAU * i / 6.0
		g.at(base + Vector3(sin(a) * 0.3 * k, 0.14 * k, cos(a) * 0.3 * k), Vector3(0.0, a, 0.0))
		g.box(Vector3(0.13 * k, 0.04 * k, 0.04 * k))


## Tripulante de cintura para arriba; `base` es la altura de la cintura.
func _crewman(base: Vector3) -> void:
	var g: MeshKit = _g
	var uniform := Color(0.33, 0.33, 0.24)
	var headgear := Color(0.3, 0.32, 0.22)
	match stats.nation:
		"DE":
			uniform = Color(0.16, 0.16, 0.18)
			headgear = Color(0.12, 0.12, 0.13)
		"SU":
			uniform = Color(0.32, 0.3, 0.2)
			headgear = Color(0.1, 0.1, 0.1)
		"UK":
			uniform = Color(0.4, 0.36, 0.25)
			headgear = Color(0.1, 0.1, 0.12)
	_p(uniform, MeshKit.MATTE)
	g.at(base)
	g.taper(Vector2(0.34 * k, 0.22 * k), Vector2(0.46 * k, 0.24 * k), 0.4 * k)
	# Brazos apoyados en el borde de la escotilla.
	for side in [-1.0, 1.0]:
		g.at(base + Vector3(side * 0.26 * k, 0.27 * k, -0.08 * k), Vector3(deg_to_rad(35.0), 0.0, side * deg_to_rad(-12.0)))
		g.box(Vector3(0.1 * k, 0.32 * k, 0.1 * k))
	_p(SKIN, MeshKit.MATTE)
	g.at(base + Vector3(0.0, 0.45 * k, 0.0))
	g.tube(0.05 * k, 0.05 * k, 0.1 * k, 6)
	g.at(base + Vector3(0.0, 0.58 * k, 0.0))
	g.blob(Vector3(0.105 * k, 0.13 * k, 0.115 * k), 10, 5)
	_p(headgear, MeshKit.MATTE)
	if stats.nation == "DE" or stats.nation == "UK":
		# Gorra o boina.
		g.at(base + Vector3(0.0, 0.67 * k, 0.01 * k))
		g.blob(Vector3(0.125 * k, 0.05 * k, 0.14 * k), 10, 3)
	else:
		# Casco de tanquista.
		g.at(base + Vector3(0.0, 0.62 * k, 0.0))
		g.lathe(PackedVector2Array([Vector2(0.125 * k, -0.03 * k), Vector2(0.125 * k, 0.03 * k), Vector2(0.09 * k, 0.1 * k), Vector2(0.0, 0.12 * k)]), 10, 1.0, 1.1, true)
	# Auriculares.
	_p(Color(0.08, 0.08, 0.08), MeshKit.MATTE)
	for side in [-1.0, 1.0]:
		g.at(base + Vector3(side * 0.105 * k, 0.59 * k, 0.015 * k))
		g.box(Vector3(0.025 * k, 0.05 * k, 0.05 * k))


## Ametralladora pesada sobre afuste en el techo (carros americanos).
func _roof_mg(base: Vector3) -> void:
	var g: MeshKit = _g
	_p(DARK_METAL, MeshKit.STEEL)
	g.at(base + Vector3(0.0, 0.15 * k, 0.0))
	g.tube(0.03 * k, 0.025 * k, 0.3 * k, 6)
	g.at(base + Vector3(0.0, 0.33 * k, -0.05 * k))
	g.box(Vector3(0.07 * k, 0.09 * k, 0.4 * k))
	_tube_z(base + Vector3(0.0, 0.33 * k, -0.6 * k), 0.018 * k, 0.75 * k, 6)
	g.at(base + Vector3(0.0, 0.33 * k, 0.2 * k))
	g.box(Vector3(0.14 * k, 0.03 * k, 0.1 * k))
	_p(Color(0.28, 0.3, 0.2), MeshKit.MATTE)
	g.at(base + Vector3(-0.1 * k, 0.3 * k, -0.02 * k))
	g.box(Vector3(0.1 * k, 0.14 * k, 0.2 * k))


# ---------------------------------------------------------------- cañón

func _gun_geometry() -> void:
	var g: MeshKit = _g
	var ts: Vector3 = _turret_size
	# Mantelete.
	if stats.casemate:
		_p(PAINT_DARK, MeshKit.CAST)
		g.at(Vector3(0.0, 0.0, -0.02 * k))
		g.blob(Vector3(ts.x * 0.17, minf(ts.y * 0.45, 0.4 * k), 0.36 * k), 12, 5)
		g.at(Vector3(0.0, 0.0, 0.12 * k))
		_p(PAINT, MeshKit.ARMOR)
		g.box(Vector3(ts.x * 0.42, minf(ts.y * 0.7, 0.6 * k), 0.14 * k))
	elif stats.round_turret:
		_p(PAINT_DARK, MeshKit.CAST)
		g.at(Vector3(0.0, 0.0, 0.02 * k))
		g.blob(Vector3(ts.x * 0.34, ts.y * 0.4, 0.3 * k), 12, 5)
	elif stats.open_top:
		_p(PAINT_DARK, MeshKit.ARMOR)
		g.at(Vector3(0.0, 0.0, -0.06 * k), Vector3(deg_to_rad(-12.0), 0.0, 0.0))
		g.box(Vector3(ts.x * 0.55, ts.y * 0.7, 0.07 * k))
	else:
		_p(PAINT_DARK, MeshKit.ARMOR)
		g.at(Vector3(0.0, 0.0, -0.05 * k))
		g.taper(Vector2(ts.x * 0.62, 0.34 * k), Vector2(ts.x * 0.62, 0.22 * k), ts.y * 0.66, Vector3(0.0, -ts.y * 0.33, 0.0), Vector2(0.0, -0.03 * k))

	var radius: float = _barrel.x * 0.5
	var length: float = _barrel.z
	var barrels: int = maxi(stats.barrel_count, 1)
	for index in barrels:
		var x: float = 0.0 if barrels == 1 else (index - (barrels - 1) * 0.5) * _barrel.x * 2.2
		# El perfil se tornea sobre el eje Y y se tumba hacia delante (-Z).
		g.at(Vector3(x, 0.0, 0.0), Vector3(-PI * 0.5, 0.0, 0.0))
		_p(PAINT_DARK, MeshKit.CAST)
		var sleeve: float = minf(0.3 * k, length * 0.14)
		var profile := PackedVector2Array([
			Vector2(radius * 1.8, 0.03 * k), Vector2(radius * 1.8, sleeve), Vector2(radius * 1.4, sleeve + 0.04 * k),
			Vector2(radius * 1.4, maxf(length * 0.26, sleeve + 0.08 * k)), Vector2(radius * 1.15, maxf(length * 0.3, sleeve + 0.12 * k)),
		])
		if stats.muzzle_brake:
			var m: float = length
			profile.append_array(PackedVector2Array([
				Vector2(radius, m - 0.46 * k), Vector2(radius * 1.9, m - 0.43 * k), Vector2(radius * 1.9, m - 0.3 * k),
				Vector2(radius * 1.15, m - 0.28 * k), Vector2(radius * 1.15, m - 0.22 * k), Vector2(radius * 1.75, m - 0.2 * k),
				Vector2(radius * 1.75, m - 0.07 * k), Vector2(radius * 1.2, m), Vector2(radius * 0.6, m),
			]))
		else:
			profile.append_array(PackedVector2Array([
				Vector2(radius * 0.95, length - 0.08 * k), Vector2(radius * 1.12, length - 0.07 * k), Vector2(radius * 1.12, length), Vector2(radius * 0.6, length),
			]))
		g.lathe(profile, 10)
		# Ánima.
		_p(Color(0.02, 0.02, 0.02), MeshKit.MATTE)
		g.lathe(PackedVector2Array([Vector2(radius * 0.6, length), Vector2(radius * 0.6, length - 0.2 * k), Vector2(0.0, length - 0.2 * k)]), 8)
	# Ametralladora coaxial.
	if not stats.casemate and not stats.open_top:
		_p(DARK_METAL, MeshKit.STEEL)
		_tube_z(Vector3(ts.x * 0.16, 0.02 * k, -0.4 * k), 0.025 * k, 0.5 * k, 6)
