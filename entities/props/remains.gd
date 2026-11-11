class_name Remains
extends Node3D
## Lo que queda de un objeto del escenario al destruirlo. Los edificios se vienen abajo entre
## polvo y dejan un montón de escombros (que arde un rato si había qué quemar); los árboles,
## postes y mástiles se tumban hacia donde los empujan; las vallas y setos quedan aplastados.
## Es solo decorado: no estorba el paso ni detiene disparos, y si un tanque le pasa por encima
## lo aplasta contra el suelo y sofoca el fuego.

enum Style { CRUMBLE, TOPPLE, FLATTEN }

## Restos que se conservan a la vez; al pasar de ahí, los más viejos se hunden y desaparecen.
const MAX_KEPT: int = 40
const SINK_TIME: float = 3.0
const CHARRED_LEAF := Color(0.07, 0.06, 0.05)
const CHARRED_WOOD := Color(0.06, 0.055, 0.05)

static var _kept: Array[Remains] = []
static var _chunk: BoxMesh

var _style: int = Style.CRUMBLE
var _pivot: Node3D
var _heap: MultiMeshInstance3D
var _heap_material: ShaderMaterial
var _blaze: Blaze
var _area: Area3D
var _box: AABB
var _matter: Color
var _fall_time: float = 1.0
var _time: float = 0.0
var _settled: bool = false
var _crushed: bool = false
var _leaving: float = -1.0
var _axis := Vector3.RIGHT
var _dir := Vector3.FORWARD
var _lean := Vector3.ZERO
var _rest: float = 1.4
var _dust_due: float = 0.0
var _burn: float = 0.0
var _charred: bool = false
var _foliage: Array[Node3D] = []
var _foliage_scale: Array[Vector3] = []
var _fx: Fx


## Deja los restos de `prop` (que se va a liberar) en su sitio. `push` es hacia dónde lo empuja
## el golpe (para los que se tumban) y `burn` los segundos que arderán (0 = no arden).
static func leave(prop: Destructible, style: int, push: Vector3, burn: float) -> Remains:
	var remains := Remains.new()
	remains._style = style
	remains._burn = burn
	remains._matter = prop.debris_color.srgb_to_linear()
	remains.add_to_group(&"remains")
	prop.get_parent().add_child(remains)
	remains.global_transform = prop.global_transform
	remains._adopt(prop)
	remains._begin(push)
	_kept.append(remains)
	if _kept.size() > MAX_KEPT:
		var oldest: Remains = _kept[0]
		_kept.remove_at(0)
		oldest.fade_away()
	return remains


## Fuego suelto donde estaba `prop` (combustible derramado, paja): arde `fuel` segundos.
static func fire_at(prop: Node3D, extent: Vector3, power: float, fuel: float) -> Blaze:
	var blaze := Blaze.new()
	blaze.extent = extent
	blaze.power = power
	blaze.fuel = fuel
	blaze.smoulder = 20.0
	blaze.add_to_group(&"remains")
	prop.get_parent().add_child(blaze)
	blaze.global_position = prop.global_position + Vector3.UP * extent.y
	return blaze


## Piezas sueltas (cascotes, vigas, tiznones) que se pintan todas de una vez. `items` es una
## lista de [transformación, color en lineal]; cada pieza es un cubo deformado.
static func pile(items: Array) -> MultiMeshInstance3D:
	if _chunk == null:
		_chunk = BoxMesh.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _chunk
	multimesh.instance_count = items.size()
	for i in items.size():
		multimesh.set_instance_transform(i, items[i][0])
		multimesh.set_instance_color(i, items[i][1])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/rubble.gdshader")
	material.set_shader_parameter("fx_noise", Fx.noise())
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _exit_tree() -> void:
	_kept.erase(self)


## Se queda con las piezas visibles del objeto (el objeto en sí desaparece).
func _adopt(prop: Node3D) -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	var found: bool = false
	for child in prop.get_children():
		if child is CollisionShape3D or not child is Node3D:
			continue
		prop.remove_child(child)
		# Lo que está clavado al suelo (la caseta junto al mástil) no se cae con lo demás.
		if _style == Style.TOPPLE and child.has_meta(&"rooted"):
			add_child(child)
			continue
		_pivot.add_child(child)
		if child is VisualInstance3D:
			var local: AABB = (child as Node3D).transform * (child as VisualInstance3D).get_aabb()
			_box = _box.merge(local) if found else local
			found = true
			if child.has_meta(&"foliage"):
				_foliage.append(child)
				_foliage_scale.append((child as Node3D).scale)
	if not found:
		_box = AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


func _begin(push: Vector3) -> void:
	_fx = Fx.on(self)
	var height: float = maxf(_box.end.y, 0.5)
	var center: Vector3 = _box.get_center()
	var reach := Vector3(maxf(_box.size.x, 1.2), 2.5, maxf(_box.size.z, 1.2))
	var spot := Vector3(center.x, 1.0, center.z)
	var turn := Basis.IDENTITY
	match _style:
		Style.CRUMBLE:
			_fall_time = clampf(0.5 + height * 0.1, 0.7, 2.2)
			_lean = Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1))
			_build_heap()
		Style.TOPPLE:
			_fall_time = clampf(0.45 + sqrt(height) * 0.3, 0.7, 2.0)
			var dir: Vector3 = global_basis.inverse() * Vector3(push.x, 0.0, push.z)
			dir.y = 0.0
			if dir.length_squared() < 0.0001:
				dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) + Vector3(0.001, 0.0, 0.0)
			_dir = dir.normalized()
			_axis = Vector3.UP.cross(_dir).normalized()
			# La copa lo deja algo levantado; un poste queda tendido del todo.
			var crown: float = maxf(_box.size.x, _box.size.z) * 0.5
			_rest = PI * 0.5 - clampf(0.5 * asin(clampf(crown / (0.7 * height), 0.0, 0.9)), 0.03, 0.3)
			# Lo aplasta el tanque que pise el tronco caído (no el que está parado al pie).
			reach = Vector3(maxf(crown * 1.6, 1.6), 2.5, height * 0.75)
			spot = _dir * height * 0.62 + Vector3.UP
			turn = Basis.looking_at(_dir, Vector3.UP)
		Style.FLATTEN:
			_fall_time = 0.3
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = Tank.LAYER_TANK
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = reach
	shape.shape = box
	_area.add_child(shape)
	_area.transform = Transform3D(turn, spot)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)


## Montón de cascotes del color del material, más alto en el centro; si arde, con vigas
## carbonizadas asomando.
func _build_heap() -> void:
	var half := Vector2(maxf(_box.size.x, 1.0), maxf(_box.size.z, 1.0)) * 0.5
	var center: Vector3 = _box.get_center()
	var area: float = half.x * half.y * 4.0
	var count: int = clampi(int(6.0 + area * 0.45), 8, 30)
	var beams: int = clampi(int(area * 0.12), 2, 6) if _burn > 0.0 else 0
	var tall: float = clampf(_box.end.y * 0.2, 0.35, 1.5)
	var grain: float = clampf(sqrt(area) * 0.11, 0.3, 0.95)
	var items: Array = []
	for i in count:
		var p := Vector2(clampf(randfn(0.0, 0.42), -1.0, 1.0), clampf(randfn(0.0, 0.42), -1.0, 1.0))
		var size := Vector3(randf_range(0.5, 1.5), randf_range(0.35, 0.9), randf_range(0.5, 1.4)) * grain
		var y: float = tall * (1.0 - minf(p.length(), 1.0)) * randf_range(0.2, 1.0) + size.y * 0.3
		var turn := Basis.from_euler(Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))) * Basis.from_scale(size)
		items.append([Transform3D(turn, Vector3(center.x + p.x * half.x * 1.1, y, center.z + p.y * half.y * 1.1)), _matter * randf_range(0.55, 1.05)])
	for i in beams:
		var length: float = minf(half.x, half.y) * randf_range(1.0, 1.9)
		var turn := Basis.from_euler(Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.25, 0.25))) * Basis.from_scale(Vector3(0.2, 0.2, length))
		items.append([Transform3D(turn, Vector3(center.x + randf_range(-0.5, 0.5) * half.x, tall * randf_range(0.5, 1.0), center.z + randf_range(-0.5, 0.5) * half.y)), Fx.CHARRED * randf_range(1.0, 2.5)])
	_heap = pile(items)
	_heap_material = _heap.material_override
	_heap.scale.y = 0.12
	add_child(_heap)


func _process(delta: float) -> void:
	_time += delta
	if _leaving >= 0.0:
		_leaving += delta
		position.y -= delta * 0.7
		if _leaving >= SINK_TIME:
			queue_free()
		return
	if not _settled:
		var t: float = minf(_time / _fall_time, 1.0)
		match _style:
			Style.CRUMBLE:
				# Se hunde cada vez más deprisa, temblando y algo ladeado, mientras crece el montón.
				var shiver: float = 0.08 * (1.0 - t)
				_pivot.position = Vector3(randf_range(-shiver, shiver), -(_box.end.y + 0.5) * t * t, randf_range(-shiver, shiver))
				_pivot.rotation = _lean * t
				_heap.scale.y = lerpf(0.12, 1.0, 1.0 - (1.0 - t) * (1.0 - t))
				_raise_dust(delta)
			Style.TOPPLE:
				_pivot.basis = Basis(_axis, _rest * t * t)
			Style.FLATTEN:
				_pivot.scale.y = lerpf(1.0, 0.07, t * t)
		if t >= 1.0:
			_settle()
	elif _style == Style.TOPPLE and _time < _fall_time + 0.4:
		# Rebote al dar contra el suelo.
		var u: float = (_time - _fall_time) / 0.4
		_pivot.basis = Basis(_axis, _rest - 0.07 * sin(u * PI) * (1.0 - u))
	if is_instance_valid(_blaze):
		_burn_down()


## Polvo que sale rodando por el pie del edificio mientras se viene abajo.
func _raise_dust(delta: float) -> void:
	var near: float = _fx.nearness(global_position)
	if near <= 0.0:
		return
	var half := Vector3(_box.size.x, 0.0, _box.size.z) * 0.5
	var cloud: Color = _matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	_dust_due += delta * near * clampf((half.x + half.z) * 5.0, 10.0, 46.0)
	while _dust_due >= 1.0:
		_dust_due -= 1.0
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		# Sale por el borde: se lleva al lado más cercano de la planta.
		if absf(side.x) > absf(side.z):
			side.x = signf(side.x)
		else:
			side.z = signf(side.z)
		var at: Vector3 = global_transform * (_box.get_center() * Vector3(1.0, 0.0, 1.0) + side * half + Vector3.UP * randf_range(0.2, 1.4))
		var out: Vector3 = (global_basis * side).normalized()
		_fx.puff(Fx.Puff.DUST, at, out * randf_range(2.0, 6.5) + Vector3.UP * randf_range(0.2, 1.6), randf_range(1.1, 2.0) * clampf(_box.end.y * 0.3, 0.8, 1.8), randf_range(2.5, 4.5), cloud)


func _settle() -> void:
	_settled = true
	var height: float = maxf(_box.end.y, 0.5)
	var cloud: Color = _matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	match _style:
		Style.CRUMBLE:
			_pivot.queue_free()
			_pivot = null
			_fx.shake(global_position, 0.1 * height)
			if height > 3.0:
				# El golpe sordo de la mole al asentarse.
				Sfx.play_at(self, Sfx.EXPLOSION, global_position + Vector3.UP, -7.0, 0.55)
			if _burn > 0.0:
				var half := Vector3(maxf(_box.size.x, 1.0), 0.0, maxf(_box.size.z, 1.0)) * 0.5
				_ignite(_box.get_center() * Vector3(1.0, 0.0, 1.0) + Vector3.UP * 0.5, Vector3(half.x * 0.7, 0.4, half.z * 0.7), clampf(height * 0.35, 0.9, 2.2), _burn)
				_blaze.lights_sky = half.x * half.z > 6.0
				_fx.mark(global_position, maxf(half.x, half.z) * 1.5, false)
		Style.TOPPLE:
			var top: Vector3 = global_transform * (_dir * height * 0.8)
			for i in 6:
				var along: Vector3 = global_transform * (_dir * height * randf_range(0.2, 1.0))
				_fx.puff(Fx.Puff.DUST, along + Vector3.UP * 0.3, Fx.dome(0.1) * randf_range(1.0, 3.0), randf_range(0.8, 1.4), randf_range(1.5, 2.6), _fx.dust)
			_fx.chips(top + Vector3.UP * 0.4, Vector3.UP, Color(0.3, 0.4, 0.16) if not _foliage.is_empty() else Color(0.5, 0.5, 0.5), 0.8)
			Sfx.play_at(self, Sfx.HIT, top, -5.0, 0.7)
			_fx.shake(top, 0.03 * height)
			# Si ya venía ardiendo (un árbol en llamas), sigue un rato en el suelo.
			if not _has_fire() and _burn > 0.0:
				var crown: float = maxf(_box.size.x, _box.size.z) * 0.5
				_ignite(_dir * height * 0.68 + Vector3.UP * 0.6, Vector3(crown * 0.55, 0.4, crown * 0.55), clampf(crown * 0.4, 0.7, 1.1), _burn)
				_blaze.smoke = 0.6
		Style.FLATTEN:
			for i in 4:
				_fx.puff(Fx.Puff.DUST, global_transform * (_box.get_center() * Vector3(randf_range(0.0, 2.0), 0.0, 1.0)) + Vector3.UP * 0.3, Fx.dome(0.1) * randf_range(1.0, 2.5), randf_range(0.7, 1.1), randf_range(1.4, 2.2), cloud)
	for body in _area.get_overlapping_bodies():
		_on_body_entered(body)


func _has_fire() -> bool:
	for child in _pivot.get_children():
		if child is Blaze:
			_blaze = child
			if _blaze.fuel == INF:
				_blaze.burn_for(randf_range(10.0, 22.0))
			return true
	return false


func _ignite(at: Vector3, extent: Vector3, power: float, fuel: float) -> void:
	_blaze = Blaze.new()
	_blaze.extent = extent
	_blaze.power = power
	_blaze.fuel = fuel * randf_range(0.8, 1.2)
	_blaze.position = at
	add_child(_blaze)


## Mientras arde: los escombros se tiznan y brillan sus brasas; a los árboles se les consume
## la copa y acaban carbonizados.
func _burn_down() -> void:
	var done: float = _blaze.spent()
	if _heap_material != null:
		_heap_material.set_shader_parameter("soot", done)
		_heap_material.set_shader_parameter("embers", _blaze.fire())
	for i in _foliage.size():
		if is_instance_valid(_foliage[i]):
			_foliage[i].scale = _foliage_scale[i] * lerpf(1.0, 0.6, done)
	if done > 0.55 and not _charred and _pivot != null:
		_charred = true
		scorch(_pivot)


## Deja carbonizadas las piezas de `root` (hojas y madera).
static func scorch(root: Node3D) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh: MeshInstance3D = child
			if mesh.has_meta(&"foliage"):
				mesh.material_override = VectorMaterials.organic(CHARRED_LEAF, Color(0.13, 0.09, 0.06), 2, 0.3, 0.45, 0.0)
			else:
				mesh.material_override = VectorMaterials.textured(CHARRED_WOOD, Color(0.02, 0.02, 0.02), 1, 0.5)


func _on_body_entered(body: Node) -> void:
	if body is Tank and _settled:
		crush()


## Un tanque le pasa por encima: queda aplastado y el fuego, casi sofocado.
func crush() -> void:
	if _crushed or _leaving >= 0.0:
		return
	_crushed = true
	if _style == Style.FLATTEN:
		return
	var tween := create_tween()
	if _heap != null:
		tween.tween_property(_heap, "scale:y", 0.4, 0.2)
	else:
		tween.tween_property(self, "scale:y", 0.3, 0.18)
	var cloud: Color = _matter.lerp(Color(0.2, 0.19, 0.17), 0.45)
	var center: Vector3 = _area.global_position
	for i in 7:
		_fx.puff(Fx.Puff.DUST, center + Vector3(randf_range(-1.0, 1.0), -0.6, randf_range(-1.0, 1.0)) * 1.5, Fx.dome(0.1) * randf_range(1.5, 4.0), randf_range(0.8, 1.4), randf_range(1.5, 2.8), cloud)
	Sfx.play_at(self, Sfx.HIT, center, -3.0, 0.6)
	if is_instance_valid(_blaze):
		_blaze.level *= 0.3
		_blaze.put_out()


## Se hunde en el suelo y desaparece (para no acumular restos sin fin).
func fade_away() -> void:
	if _leaving >= 0.0:
		return
	_leaving = 0.0
	_area.set_deferred("monitoring", false)
	if is_instance_valid(_blaze):
		_blaze.put_out()
