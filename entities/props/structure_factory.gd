class_name StructureFactory
## Edificios especiales: objetos con premio repartidos por el mapa y complejos que son
## objetivo de las misiones de sabotaje (aeródromo, puerto, central, fábrica, cuartel general).

const CONCRETE := Color(0.52, 0.52, 0.5)
const STEEL := Color(0.3, 0.32, 0.33)
const BRICK := Color(0.5, 0.28, 0.2)
const OBJECTIVE_COLOR := Color(1.0, 0.85, 0.1)

const COMPLEX_NAMES: Dictionary = {
	"airfield": "AERÓDROMO",
	"port": "PUERTO",
	"power_plant": "CENTRAL ELÉCTRICA",
	"factory": "FÁBRICA",
	"hq": "CUARTEL GENERAL",
}


static func _part(health: float, size_hint: float, debris: Color = Color(0.5, 0.5, 0.48)) -> Destructible:
	var prop := Destructible.new()
	prop.max_health = health
	prop.size_hint = size_hint
	prop.debris_color = debris
	return prop


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, pattern: int = 0, scale: float = 1.5) -> MeshInstance3D:
	var mesh := VectorMaterials.make_box(size, color, pattern, scale)
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


static func _shape(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	parent.add_child(shape)


static func _cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, pattern: int = 4, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 12
	var instance := VectorMaterials.make_outlined(mesh, color, color.darkened(0.4), pattern, 0.6)
	instance.position = pos
	parent.add_child(instance)
	return instance


static func _smoke(parent: Node3D, pos: Vector3, dark: bool = true) -> void:
	var vent := FxVent.new()
	vent.position = pos
	vent.rate = 3.5
	vent.size = 1.3
	vent.rise = 2.6
	vent.color = Fx.DARK_SMOKE if dark else Color(0.5, 0.5, 0.5, 0.55)
	parent.add_child(vent)


static func _prize(prop: Destructible, name: String, points: int) -> Destructible:
	prop.prize_name = name
	prop.prize_points = points
	prop.add_to_group(&"radar_marks")
	prop.set_meta("radar_color", Color(0.4, 1.0, 0.5))
	prop.set_meta("radar_shape", "ring")
	return prop


## Marca una pieza como objetivo de misión (rombo amarillo en el radar).
static func _objective(prop: Destructible, name: String) -> Destructible:
	prop.objective_name = name
	prop.add_to_group(&"radar_marks")
	prop.set_meta("radar_color", OBJECTIVE_COLOR)
	prop.set_meta("radar_shape", "diamond")
	return prop


# ---------------------------------------------------------------- objetos con premio

static func radio_mast() -> Destructible:
	var prop := _prize(_part(60.0, 3.0, STEEL), Loc.t("MÁSTIL DE RADIO"), 300)
	prop.topples = true
	for i in 6:
		var section := _box(prop, Vector3(1.2 - i * 0.15, 4.0, 1.2 - i * 0.15), Vector3(0.0, 2.0 + i * 4.0, 0.0), Color(0.6, 0.15, 0.1) if i % 2 == 0 else Color(0.85, 0.85, 0.85), 6, 0.3)
		section.rotation.y = i * 0.3
	var hut := _box(prop, Vector3(3.0, 2.5, 3.0), Vector3(3.0, 1.25, 0.0), CONCRETE, 0)
	hut.rotation.y = 0.1
	# La caseta se queda donde está cuando el mástil cae.
	hut.set_meta(&"rooted", true)
	_shape(prop, Vector3(1.4, 24.0, 1.4), Vector3(0.0, 12.0, 0.0))
	_shape(prop, Vector3(3.0, 2.5, 3.0), Vector3(3.0, 1.25, 0.0))
	return prop


static func water_tower() -> Destructible:
	var prop := _prize(_part(80.0, 3.0, STEEL), Loc.t("TORRE DE AGUA"), 250)
	prop.topples = true
	for x in [-1.8, 1.8]:
		for z in [-1.8, 1.8]:
			_box(prop, Vector3(0.3, 9.0, 0.3), Vector3(x, 4.5, z), STEEL, 4, 0.8)
	_cylinder(prop, 2.8, 4.0, Vector3(0.0, 11.0, 0.0), Color(0.45, 0.4, 0.33))
	_cylinder(prop, 2.9, 1.2, Vector3(0.0, 13.6, 0.0), Color(0.3, 0.28, 0.25), 4, 0.3)
	_shape(prop, Vector3(4.5, 14.0, 4.5), Vector3(0.0, 7.0, 0.0))
	return prop


static func flak_gun() -> Destructible:
	var prop := _prize(_part(90.0, 2.0, Color(0.55, 0.5, 0.4)), Loc.t("ANTIAÉREO"), 350)
	for i in 8:
		var angle: float = TAU * i / 8.0
		var bag := _box(prop, Vector3(2.4, 1.2, 0.9), Vector3(cos(angle) * 3.4, 0.6, sin(angle) * 3.4), Color(0.6, 0.53, 0.38), 10, 0.8)
		bag.rotation.y = -angle + PI * 0.5
	_cylinder(prop, 1.0, 1.0, Vector3(0.0, 0.6, 0.0), STEEL)
	var barrel := _cylinder(prop, 0.12, 5.0, Vector3(0.0, 2.6, -1.4), STEEL)
	barrel.rotation.x = deg_to_rad(-55.0)
	_box(prop, Vector3(1.6, 1.2, 0.1), Vector3(0.0, 1.6, -0.6), STEEL, 4, 0.5)
	_shape(prop, Vector3(7.0, 1.3, 7.0), Vector3(0.0, 0.65, 0.0))
	return prop


static func command_tent() -> Destructible:
	var prop := _prize(_part(60.0, 2.0, Color(0.4, 0.38, 0.28)), Loc.t("PUESTO DE MANDO"), 500)
	prop.burns = 35.0
	var roof := PrismMesh.new()
	roof.size = Vector3(6.0, 3.0, 8.0)
	var tent := VectorMaterials.make_outlined(roof, Color(0.35, 0.36, 0.25), Color(0.25, 0.25, 0.18), 8, 0.6)
	tent.position.y = 1.5
	prop.add_child(tent)
	_box(prop, Vector3(1.6, 0.8, 1.0), Vector3(4.0, 0.4, 0.0), Color(0.3, 0.28, 0.2), 5, 0.5)
	_box(prop, Vector3(0.08, 6.0, 0.08), Vector3(-3.5, 3.0, 3.0), STEEL)
	_shape(prop, Vector3(6.0, 3.0, 8.0), Vector3(0.0, 1.5, 0.0))
	return prop


# ---------------------------------------------------------------- complejos de sabotaje

## Construye un complejo en `world` alrededor de `center` y devuelve sus piezas objetivo.
static func build(kind: String, world: Node3D, center: Vector3, yaw: float) -> Array[Destructible]:
	var root := Node3D.new()
	root.position = center
	root.rotation.y = yaw
	world.add_child(root)
	match kind:
		"airfield":
			return _airfield(root)
		"port":
			return _port(root)
		"power_plant":
			return _power_plant(root)
		"factory":
			return _factory(root)
		_:
			return _hq(root)


static func _add(root: Node3D, prop: Destructible, pos: Vector3, yaw: float = 0.0) -> Destructible:
	prop.position = pos
	prop.rotation.y = yaw
	root.add_child(prop)
	return prop


static func _airfield(root: Node3D) -> Array[Destructible]:
	var parts: Array[Destructible] = []
	var runway := MeshInstance3D.new()
	var strip := BoxMesh.new()
	strip.size = Vector3(14.0, 0.06, 90.0)
	runway.mesh = strip
	runway.material_override = VectorMaterials.box_edges(strip.size, Color(0.3, 0.3, 0.29), 0, 4.0)
	runway.position = Vector3(-18.0, 0.03, 0.0)
	root.add_child(runway)
	for i in 2:
		var hangar := _objective(_part(180.0, 5.0), "HANGAR %d" % (i + 1))
		hangar.burns = 30.0
		var shell := CylinderMesh.new()
		shell.top_radius = 7.0
		shell.bottom_radius = 7.0
		shell.height = 18.0
		shell.radial_segments = 16
		var vault := VectorMaterials.make_outlined(shell, Color(0.42, 0.44, 0.4), Color(0.25, 0.26, 0.24), 4, 0.8)
		vault.rotation.x = PI * 0.5
		vault.scale = Vector3(1.0, 1.0, 0.75)
		hangar.add_child(vault)
		_box(hangar, Vector3(13.0, 7.0, 0.3), Vector3(0.0, 2.6, -9.0), Color(0.15, 0.15, 0.15), 6, 0.6)
		_shape(hangar, Vector3(14.0, 7.0, 18.0), Vector3(0.0, 3.5, 0.0))
		parts.append(_add(root, hangar, Vector3(6.0 + i * 17.0, 0.0, -20.0)))
	var tower := _objective(_part(120.0, 4.0), Loc.t("TORRE DE CONTROL"))
	_box(tower, Vector3(4.0, 8.0, 4.0), Vector3(0.0, 4.0, 0.0), CONCRETE, 1, 2.0)
	_box(tower, Vector3(5.0, 2.0, 5.0), Vector3(0.0, 9.0, 0.0), Color(0.3, 0.4, 0.45), 1, 0.8)
	_shape(tower, Vector3(5.0, 10.0, 5.0), Vector3(0.0, 5.0, 0.0))
	parts.append(_add(root, tower, Vector3(10.0, 0.0, 12.0)))
	for i in 3:
		parts.append(_add(root, _plane(Loc.t("AVIÓN %d") % (i + 1)), Vector3(-18.0, 0.0, -25.0 + i * 22.0), PI * 0.5 * (1 if i % 2 == 0 else -1)))
	return parts


static func _plane(name: String) -> Destructible:
	var plane := _objective(_part(40.0, 2.5, Color(0.4, 0.42, 0.38)), name)
	plane.burns = 30.0
	var color := Color(0.35, 0.38, 0.3)
	var body := _cylinder(plane, 0.7, 9.0, Vector3(0.0, 1.8, 0.0), color, 4)
	body.rotation.x = PI * 0.5
	_box(plane, Vector3(12.0, 0.15, 2.0), Vector3(0.0, 1.6, -0.6), color, 4, 1.0)
	_box(plane, Vector3(4.0, 0.12, 1.2), Vector3(0.0, 2.0, 4.0), color, 4, 1.0)
	_box(plane, Vector3(0.12, 1.6, 1.2), Vector3(0.0, 2.8, 4.0), color, 4, 1.0)
	_box(plane, Vector3(0.15, 2.6, 0.2), Vector3(0.0, 1.8, -4.7), Color(0.15, 0.15, 0.15))
	_box(plane, Vector3(0.8, 0.5, 1.4), Vector3(0.0, 2.6, -1.0), Color(0.3, 0.45, 0.5), 1, 0.4)
	_shape(plane, Vector3(12.0, 2.5, 9.0), Vector3(0.0, 1.5, 0.0))
	return plane


static func _port(root: Node3D) -> Array[Destructible]:
	var parts: Array[Destructible] = []
	# Dársena: agua contenida por muelles de hormigón.
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 26.0)
	water.mesh = plane
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.1, 0.2, 0.25)
	water_mat.roughness = 0.1
	water_mat.metallic = 0.3
	water.material_override = water_mat
	water.position = Vector3(0.0, 0.05, -14.0)
	root.add_child(water)
	var basin := StaticBody3D.new()
	_shape(basin, Vector3(70.0, 3.0, 26.0), Vector3(0.0, 1.5, -14.0))
	root.add_child(basin)
	_box(root, Vector3(74.0, 1.2, 4.0), Vector3(0.0, 0.6, 1.0), CONCRETE, 4, 3.0)
	var ship := _objective(_part(260.0, 6.0, Color(0.3, 0.3, 0.3)), Loc.t("MERCANTE"))
	_box(ship, Vector3(40.0, 5.0, 9.0), Vector3(0.0, 1.0, 0.0), Color(0.22, 0.24, 0.26), 4, 2.0)
	_box(ship, Vector3(10.0, 5.0, 7.0), Vector3(6.0, 6.0, 0.0), Color(0.8, 0.8, 0.75), 1, 1.5)
	_cylinder(ship, 1.2, 5.0, Vector3(4.0, 10.0, 0.0), Color(0.2, 0.2, 0.2))
	_smoke(ship, Vector3(4.0, 12.5, 0.0))
	_shape(ship, Vector3(40.0, 10.0, 9.0), Vector3(0.0, 3.0, 0.0))
	parts.append(_add(root, ship, Vector3(0.0, 0.0, -12.0)))
	for i in 2:
		var crane := _objective(_part(110.0, 4.0, STEEL), Loc.t("GRÚA %d") % (i + 1))
		for x in [-1.5, 1.5]:
			_box(crane, Vector3(0.5, 14.0, 0.5), Vector3(x, 7.0, 0.0), Color(0.7, 0.45, 0.15), 6, 0.4)
		_box(crane, Vector3(4.0, 1.5, 3.0), Vector3(0.0, 14.5, 0.0), Color(0.7, 0.45, 0.15), 4, 0.8)
		_box(crane, Vector3(0.5, 0.6, 16.0), Vector3(0.0, 15.0, -6.0), Color(0.7, 0.45, 0.15), 6, 0.4)
		_shape(crane, Vector3(4.0, 16.0, 3.0), Vector3(0.0, 8.0, 0.0))
		parts.append(_add(root, crane, Vector3(-20.0 + i * 40.0, 0.0, 4.0)))
	var warehouse := _objective(_part(200.0, 5.0), Loc.t("ALMACÉN"))
	_box(warehouse, Vector3(24.0, 8.0, 12.0), Vector3(0.0, 4.0, 0.0), BRICK, 2, 1.5)
	_shape(warehouse, Vector3(24.0, 8.0, 12.0), Vector3(0.0, 4.0, 0.0))
	parts.append(_add(root, warehouse, Vector3(0.0, 0.0, 16.0)))
	return parts


static func _power_plant(root: Node3D) -> Array[Destructible]:
	var parts: Array[Destructible] = []
	var hall := _objective(_part(260.0, 6.0, BRICK), Loc.t("SALA DE TURBINAS"))
	_box(hall, Vector3(28.0, 12.0, 16.0), Vector3(0.0, 6.0, 0.0), BRICK, 1, 3.0)
	_shape(hall, Vector3(28.0, 12.0, 16.0), Vector3(0.0, 6.0, 0.0))
	parts.append(_add(root, hall, Vector3.ZERO))
	for i in 2:
		var stack := _objective(_part(150.0, 6.0, BRICK), Loc.t("CHIMENEA %d") % (i + 1))
		_cylinder(stack, 2.2, 30.0, Vector3(0.0, 15.0, 0.0), BRICK.darkened(0.1), 4, 1.5)
		_smoke(stack, Vector3(0.0, 30.5, 0.0))
		_shape(stack, Vector3(4.0, 30.0, 4.0), Vector3(0.0, 15.0, 0.0))
		parts.append(_add(root, stack, Vector3(-8.0 + i * 16.0, 0.0, -14.0)))
	for i in 2:
		var transformer := _objective(_part(90.0, 3.0, STEEL), Loc.t("TRANSFORMADOR %d") % (i + 1))
		_box(transformer, Vector3(4.0, 4.0, 3.0), Vector3(0.0, 2.0, 0.0), Color(0.35, 0.38, 0.35), 6, 0.3)
		for x in [-1.2, 0.0, 1.2]:
			_cylinder(transformer, 0.25, 1.6, Vector3(x, 4.8, 0.0), Color(0.6, 0.4, 0.3), 4)
		_shape(transformer, Vector3(4.0, 5.0, 3.0), Vector3(0.0, 2.5, 0.0))
		parts.append(_add(root, transformer, Vector3(-10.0 + i * 20.0, 0.0, 16.0)))
	return parts


static func _factory(root: Node3D) -> Array[Destructible]:
	var parts: Array[Destructible] = []
	for i in 2:
		var hall := _objective(_part(230.0, 6.0, BRICK), Loc.t("NAVE %d") % (i + 1))
		_box(hall, Vector3(16.0, 9.0, 26.0), Vector3(0.0, 4.5, 0.0), BRICK, 1, 2.5)
		# Tejado en diente de sierra.
		for r in 4:
			var tooth := PrismMesh.new()
			tooth.left_to_right = 0.0
			tooth.size = Vector3(16.0, 2.5, 6.5)
			var roof := VectorMaterials.make_outlined(tooth, Color(0.3, 0.32, 0.33), Color(0.2, 0.22, 0.24), 6, 0.5)
			roof.rotation.y = PI * 0.5
			roof.scale = Vector3(6.5 / 16.0, 1.0, 16.0 / 6.5)
			roof.position = Vector3(0.0, 10.25, -9.75 + r * 6.5)
			hall.add_child(roof)
		_shape(hall, Vector3(16.0, 11.0, 26.0), Vector3(0.0, 5.5, 0.0))
		parts.append(_add(root, hall, Vector3(-10.0 + i * 20.0, 0.0, 0.0)))
	var stack := _objective(_part(150.0, 6.0, BRICK), Loc.t("CHIMENEA"))
	_cylinder(stack, 1.8, 26.0, Vector3(0.0, 13.0, 0.0), BRICK.darkened(0.1), 4, 1.2)
	_smoke(stack, Vector3(0.0, 26.5, 0.0))
	_shape(stack, Vector3(3.6, 26.0, 3.6), Vector3(0.0, 13.0, 0.0))
	parts.append(_add(root, stack, Vector3(0.0, 0.0, -18.0)))
	var tower := water_tower()
	tower.prize_points = 0
	tower.remove_from_group(&"radar_marks")
	parts.append(_add(root, _objective(tower, Loc.t("DEPÓSITO DE AGUA")), Vector3(16.0, 0.0, -18.0)))
	return parts


static func _hq(root: Node3D) -> Array[Destructible]:
	var parts: Array[Destructible] = []
	var bunker := _objective(_part(300.0, 5.0, CONCRETE), Loc.t("BÚNKER DE MANDO"))
	_box(bunker, Vector3(14.0, 4.5, 12.0), Vector3(0.0, 2.25, 0.0), CONCRETE, 0, 2.0)
	_box(bunker, Vector3(15.0, 0.8, 13.0), Vector3(0.0, 4.9, 0.0), CONCRETE.darkened(0.15), 0, 2.0)
	_box(bunker, Vector3(5.0, 0.6, 0.2), Vector3(0.0, 3.0, 6.05), Color(0.08, 0.08, 0.08))
	_shape(bunker, Vector3(15.0, 5.3, 13.0), Vector3(0.0, 2.65, 0.0))
	parts.append(_add(root, bunker, Vector3.ZERO))
	var mast := radio_mast()
	mast.prize_points = 0
	mast.remove_from_group(&"radar_marks")
	parts.append(_add(root, _objective(mast, Loc.t("ANTENA DE RADIO")), Vector3(14.0, 0.0, -8.0)))
	for i in 2:
		var barracks := _objective(_part(140.0, 4.0, Color(0.4, 0.3, 0.2)), Loc.t("BARRACÓN %d") % (i + 1))
		_box(barracks, Vector3(8.0, 4.0, 18.0), Vector3(0.0, 2.0, 0.0), Color(0.38, 0.3, 0.2), 5, 1.2)
		var roof := PrismMesh.new()
		roof.size = Vector3(8.6, 2.0, 18.4)
		var top := VectorMaterials.make_outlined(roof, Color(0.25, 0.25, 0.22), Color(0.18, 0.18, 0.15), 6, 0.6)
		top.position.y = 5.0
		barracks.add_child(top)
		_shape(barracks, Vector3(8.0, 6.0, 18.0), Vector3(0.0, 3.0, 0.0))
		parts.append(_add(root, barracks, Vector3(-16.0 + i * 32.0, 0.0, 14.0)))
	var fuel := PropFactory.supply_depot()
	fuel.remove_from_group(&"radar_marks")
	parts.append(_add(root, _objective(fuel, Loc.t("DEPÓSITO DE COMBUSTIBLE")), Vector3(-14.0, 0.0, -10.0)))
	return parts


# ---------------------------------------------------------------- campo de prisioneros

## Campo de prisioneros: el objetivo es derribar las alambradas (piezas objetivo).
## Los barracones son zona protegida: dispararles quita vida y puntos.
static func camp(world: Node3D, center: Vector3, segments: int) -> Array[Destructible]:
	var root := Node3D.new()
	root.position = center
	world.add_child(root)
	var half := Vector2(34.0, 26.0)
	var corners: Array[Vector2] = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	var parts: Array[Destructible] = []
	var per_side: int = int(ceil(segments / 4.0))
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var count: int = per_side
		var length: float = a.distance_to(b) / count
		for i in count:
			var p: Vector2 = a.lerp(b, (i + 0.5) / count)
			var fence := _objective(_wire(length), Loc.t("ALAMBRADA %d") % (parts.size() + 1))
			fence.position = Vector3(p.x, 0.0, p.y)
			fence.rotation.y = -(b - a).angle()
			root.add_child(fence)
			parts.append(fence)
	for corner in corners:
		var tower := Node3D.new()
		tower.position = Vector3(corner.x, 0.0, corner.y)
		for x in [-1.2, 1.2]:
			for z in [-1.2, 1.2]:
				_box(tower, Vector3(0.25, 7.0, 0.25), Vector3(x, 3.5, z), Color(0.35, 0.27, 0.18), 5, 0.4)
		_box(tower, Vector3(3.4, 2.0, 3.4), Vector3(0.0, 8.0, 0.0), Color(0.33, 0.26, 0.18), 5, 0.8)
		root.add_child(tower)
	for i in 3:
		var barracks := _part(1.0, 3.0, Color(0.4, 0.33, 0.24))
		barracks.indestructible = true
		barracks.protected_area = true
		_box(barracks, Vector3(7.0, 3.2, 16.0), Vector3(0.0, 1.6, 0.0), Color(0.36, 0.3, 0.22), 5, 1.2)
		var roof := PrismMesh.new()
		roof.size = Vector3(7.6, 1.8, 16.4)
		var top := VectorMaterials.make_outlined(roof, Color(0.22, 0.22, 0.2), Color(0.15, 0.15, 0.14), 6, 0.6)
		top.position.y = 4.1
		barracks.add_child(top)
		_shape(barracks, Vector3(7.0, 5.0, 16.0), Vector3(0.0, 2.5, 0.0))
		barracks.position = Vector3(-14.0 + i * 14.0, 0.0, 0.0)
		barracks.add_to_group(&"radar_marks")
		barracks.set_meta("radar_color", Color(0.4, 0.7, 1.0))
		root.add_child(barracks)
	return parts


static func _wire(length: float) -> Destructible:
	var fence := _part(12.0, 1.0, Color(0.3, 0.3, 0.3))
	var posts: int = maxi(int(length / 3.0), 2)
	for i in posts + 1:
		_box(fence, Vector3(0.15, 3.0, 0.15), Vector3(-length * 0.5 + i * length / posts, 1.5, 0.0), Color(0.3, 0.24, 0.16), 5, 0.3)
	for y in [0.5, 1.1, 1.7, 2.3, 2.8]:
		_box(fence, Vector3(length, 0.04, 0.04), Vector3(0.0, y, 0.0), Color(0.25, 0.25, 0.25))
	for x in range(int(length / 2.0)):
		var coil := CylinderMesh.new()
		coil.top_radius = 0.45
		coil.bottom_radius = 0.45
		coil.height = 1.8
		coil.radial_segments = 8
		var mesh := VectorMaterials.make_outlined(coil, Color(0.28, 0.28, 0.28), Color(0.1, 0.1, 0.1), 4, 0.15)
		mesh.rotation.z = PI * 0.5
		mesh.position = Vector3(-length * 0.5 + 1.0 + x * 2.0, 3.2, 0.0)
		fence.add_child(mesh)
	_shape(fence, Vector3(length, 3.0, 0.4), Vector3(0.0, 1.5, 0.0))
	return fence
