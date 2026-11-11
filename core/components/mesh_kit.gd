class_name MeshKit
extends RefCounted
## Constructor de mallas: acumula piezas (cajas, cuñas, perfiles extruidos, piezas torneadas,
## bandas de oruga, distintivos) en una sola malla que se dibuja de una vez.
## Cada vértice guarda su color y su tipo de superficie (ver armor.gdshader), las coordenadas
## de su cara en metros (UV) y la mitad del tamaño de la cara (UV2), con las que el shader
## pinta soldaduras, tornillos y desgaste en los cantos.

enum { ARMOR, CAST, STEEL, TRACK, RUBBER, WOOD, CANVAS, LIGHT, DECAL, GLASS, MATTE }

## Transformación, color y tipo que se aplican a las piezas que se añadan a continuación.
var xf := Transform3D.IDENTITY
var color := Color.WHITE
var kind: int = ARMOR

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _uv := PackedVector2Array()
var _uv2 := PackedVector2Array()


func paint(new_color: Color, new_kind: int) -> MeshKit:
	color = new_color
	kind = new_kind
	return self


## Coloca las siguientes piezas en `pos` con el giro `rot` (ángulos de Euler, radianes).
func at(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshKit:
	xf = Transform3D(Basis.from_euler(rot), pos)
	return self


func is_empty() -> bool:
	return _v.is_empty()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _v.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------- piezas

## Caja centrada en `center`.
func box(size: Vector3, center: Vector3 = Vector3.ZERO) -> void:
	var h: Vector3 = size * 0.5
	hexa([
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z), center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	])


## Tronco de pirámide: base `bottom` (ancho x, largo z) en y = 0 y tapa `top` a la altura
## `height`, desplazada `shift` (x, z). Sirve para superestructuras y torretas de caras inclinadas.
func taper(bottom: Vector2, top: Vector2, height: float, base_center: Vector3 = Vector3.ZERO, shift: Vector2 = Vector2.ZERO) -> void:
	var b: Vector2 = bottom * 0.5
	var t: Vector2 = top * 0.5
	var c: Vector3 = base_center
	var u: Vector3 = base_center + Vector3(shift.x, height, shift.y)
	hexa([
		c + Vector3(-b.x, 0.0, -b.y), c + Vector3(b.x, 0.0, -b.y), c + Vector3(b.x, 0.0, b.y), c + Vector3(-b.x, 0.0, b.y),
		u + Vector3(-t.x, 0.0, -t.y), u + Vector3(t.x, 0.0, -t.y), u + Vector3(t.x, 0.0, t.y), u + Vector3(-t.x, 0.0, t.y),
	])


## Hexaedro convexo: 4 esquinas de abajo y las 4 de arriba en el mismo orden.
func hexa(c: Array) -> void:
	var center := Vector3.ZERO
	for p in c:
		center += p
	center /= 8.0
	var quads: Array = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for q in quads:
		var pts: Array = [c[q[0]], c[q[1]], c[q[2]], c[q[3]]]
		var mid: Vector3 = (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
		face(pts, mid - center)


## Perfil cerrado (z, y) extruido a lo ancho (eje x). Admite perfiles cóncavos.
func prism(profile: PackedVector2Array, width: float, x_center: float = 0.0) -> void:
	var count: int = profile.size()
	var area: float = 0.0
	for i in count:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	var orient: float = 1.0 if area > 0.0 else -1.0
	var x0: float = x_center - width * 0.5
	var x1: float = x_center + width * 0.5
	for i in count:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % count]
		var e: Vector2 = b - a
		if e.length_squared() < 0.0000001:
			continue
		face([Vector3(x0, a.y, a.x), Vector3(x1, a.y, a.x), Vector3(x1, b.y, b.x), Vector3(x0, b.y, b.x)], Vector3(0.0, -e.x, e.y) * orient)
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(profile)
	for x in [x0, x1]:
		var pts: Array = []
		for p in profile:
			pts.append(Vector3(x, p.y, p.x))
		face(pts, Vector3(-1.0 if x == x0 else 1.0, 0.0, 0.0), tris)


## Cara plana. `hint` indica hacia dónde mira. Sin `tris` se triangula en abanico (convexa).
func face(pts: Array, hint: Vector3, tris: PackedInt32Array = PackedInt32Array()) -> void:
	var count: int = pts.size()
	var normal := Vector3.ZERO
	for i in count:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % count]
		normal += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	if normal.length_squared() < 0.0000000001:
		return
	normal = normal.normalized()
	if normal.dot(hint) < 0.0:
		normal = -normal
	# Ejes de la cara: el borde más largo marca la dirección u.
	var u := Vector3.ZERO
	var longest: float = 0.0
	for i in count:
		var e: Vector3 = pts[(i + 1) % count] - pts[i]
		if e.length_squared() > longest:
			longest = e.length_squared()
			u = e
	u = (u - normal * u.dot(normal)).normalized()
	var w: Vector3 = normal.cross(u)
	var coords: Array[Vector2] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := Vector2(u.dot(p), w.dot(p))
		coords.append(q)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var mid: Vector2 = (lo + hi) * 0.5
	var half: Vector2 = (hi - lo) * 0.5
	if tris.is_empty():
		for i in range(1, count - 1):
			_tri(pts[0], pts[i], pts[i + 1], normal, normal, normal, coords[0] - mid, coords[i] - mid, coords[i + 1] - mid, half)
	else:
		for i in range(0, tris.size(), 3):
			var a: int = tris[i]
			var b: int = tris[i + 1]
			var c: int = tris[i + 2]
			_tri(pts[a], pts[b], pts[c], normal, normal, normal, coords[a] - mid, coords[b] - mid, coords[c] - mid, half)


## Pieza torneada alrededor del eje Y. `profile` son puntos (radio, altura) recorridos desde
## el centro de abajo, hacia fuera, hacia arriba y de vuelta al centro. `sx` y `sz` la
## achatan (torretas ovaladas). Con `flat` cada cara es una plancha (torretas soldadas).
func lathe(profile: PackedVector2Array, segments: int, sx: float = 1.0, sz: float = 1.0, smooth: bool = false, flat: bool = false, turn: float = 0.0) -> void:
	var count: int = profile.size()
	var seg_normals: Array[Vector2] = []
	for k in count - 1:
		var e: Vector2 = profile[k + 1] - profile[k]
		seg_normals.append(Vector2(e.y, -e.x).normalized() if e.length_squared() > 0.0000001 else Vector2.ZERO)
	var run: float = 0.0
	for k in count - 1:
		var p0: Vector2 = profile[k]
		var p1: Vector2 = profile[k + 1]
		var length: float = p0.distance_to(p1)
		if length < 0.00001 or (p0.x <= 0.0 and p1.x <= 0.0):
			continue
		var n0: Vector2 = seg_normals[k]
		var n1: Vector2 = seg_normals[k]
		if smooth:
			if k > 0 and seg_normals[k - 1] != Vector2.ZERO and seg_normals[k - 1].dot(seg_normals[k]) > 0.3:
				n0 = (seg_normals[k - 1] + seg_normals[k]).normalized()
			if k < count - 2 and seg_normals[k + 1] != Vector2.ZERO and seg_normals[k + 1].dot(seg_normals[k]) > 0.3:
				n1 = (seg_normals[k + 1] + seg_normals[k]).normalized()
		var girth: float = maxf(p0.x, p1.x) * (sx + sz) * 0.5
		if flat and (p0.x <= 0.0 or p1.x <= 0.0) and absf(p0.y - p1.y) < 0.00001:
			# Tapa plana de una sola pieza.
			var rim: Vector2 = p0 if p0.x > 0.0 else p1
			var cap: Array = []
			for j in segments:
				cap.append(_ring(rim, turn + TAU * j / segments, sx, sz))
			face(cap, Vector3(0.0, seg_normals[k].y, 0.0))
			run += length
			continue
		for j in segments:
			var a0: float = turn + TAU * j / segments
			var a1: float = turn + TAU * (j + 1) / segments
			var pa: Vector3 = _ring(p0, a0, sx, sz)
			var pb: Vector3 = _ring(p0, a1, sx, sz)
			var pc: Vector3 = _ring(p1, a1, sx, sz)
			var pd: Vector3 = _ring(p1, a0, sx, sz)
			if flat:
				var am: float = (a0 + a1) * 0.5
				var pts: Array = [pa, pb, pc, pd] if p0.x > 0.0 else [pa, pc, pd]
				if p1.x <= 0.0:
					pts = [pa, pb, pc]
				face(pts, _ring_normal(seg_normals[k], am, sx, sz))
				continue
			var ua := Vector2(a0 * girth, run)
			var ub := Vector2(a1 * girth, run)
			var uc := Vector2(a1 * girth, run + length)
			var ud := Vector2(a0 * girth, run + length)
			var na: Vector3 = _ring_normal(n0, a0, sx, sz)
			var nb: Vector3 = _ring_normal(n0, a1, sx, sz)
			var nc: Vector3 = _ring_normal(n1, a1, sx, sz)
			var nd: Vector3 = _ring_normal(n1, a0, sx, sz)
			_tri(pa, pb, pc, na, nb, nc, ua, ub, uc, Vector2.ZERO)
			_tri(pa, pc, pd, na, nc, nd, ua, uc, ud, Vector2.ZERO)
		run += length


## Cilindro (o cono truncado) centrado, a lo largo del eje Y, con sus tapas.
func tube(radius_bottom: float, radius_top: float, height: float, segments: int = 10) -> void:
	lathe(PackedVector2Array([Vector2(0.0, -height * 0.5), Vector2(radius_bottom, -height * 0.5), Vector2(radius_top, height * 0.5), Vector2(0.0, height * 0.5)]), segments)


## Elipsoide (cabezas, cúpulas, bultos) de radios `r`.
func blob(r: Vector3, segments: int = 10, rings: int = 5) -> void:
	var profile := PackedVector2Array()
	for i in rings + 1:
		var a: float = -PI * 0.5 + PI * i / rings
		profile.append(Vector2(maxf(cos(a), 0.0), sin(a) * r.y))
	lathe(profile, segments, r.x, r.z, true)


## Banda cerrada (oruga) que sigue el contorno `path` (z, y), de anchura `width` centrada en
## `x_center`. UV.y recorre la banda en metros. Los cantos se cierran con acero.
func belt(path: PackedVector2Array, width: float, x_center: float, thickness: float) -> void:
	var count: int = path.size()
	var area: float = 0.0
	for i in count:
		area += path[i].x * path[(i + 1) % count].y - path[(i + 1) % count].x * path[i].y
	var orient: float = 1.0 if area > 0.0 else -1.0
	var normals: Array[Vector2] = []
	for i in count:
		var prev: Vector2 = path[(i - 1 + count) % count]
		var next: Vector2 = path[(i + 1) % count]
		var e0: Vector2 = (path[i] - prev).normalized()
		var e1: Vector2 = (next - path[i]).normalized()
		normals.append((Vector2(e0.y, -e0.x) + Vector2(e1.y, -e1.x)).normalized() * orient)
	var x0: float = x_center - width * 0.5
	var x1: float = x_center + width * 0.5
	var half := Vector2(width * 0.5, 1000.0)
	var run: float = 0.0
	var base_kind: int = kind
	for i in count:
		var j: int = (i + 1) % count
		var a: Vector2 = path[i]
		var b: Vector2 = path[j]
		var length: float = a.distance_to(b)
		var na := Vector3(0.0, normals[i].y, normals[i].x)
		var nb := Vector3(0.0, normals[j].y, normals[j].x)
		var p0 := Vector3(x0, a.y, a.x)
		var p1 := Vector3(x1, a.y, a.x)
		var p2 := Vector3(x1, b.y, b.x)
		var p3 := Vector3(x0, b.y, b.x)
		kind = base_kind
		_tri(p0, p1, p2, na, na, nb, Vector2(-half.x, run), Vector2(half.x, run), Vector2(half.x, run + length), half)
		_tri(p0, p2, p3, na, nb, nb, Vector2(-half.x, run), Vector2(half.x, run + length), Vector2(-half.x, run + length), half)
		# Cantos de la banda.
		kind = STEEL
		var ia: Vector2 = a - normals[i] * thickness
		var ib: Vector2 = b - normals[j] * thickness
		for x in [x0, x1]:
			face([Vector3(x, a.y, a.x), Vector3(x, b.y, b.x), Vector3(x, ib.y, ib.x), Vector3(x, ia.y, ia.x)], Vector3(-1.0 if x == x0 else 1.0, 0.0, 0.0))
		run += length
	kind = base_kind


## Rectángulo plano en el plano XY local, mirando a +Z (distintivos).
func rect(size: Vector2, center: Vector3 = Vector3.ZERO) -> void:
	var h: Vector2 = size * 0.5
	face([center + Vector3(-h.x, -h.y, 0.0), center + Vector3(h.x, -h.y, 0.0), center + Vector3(h.x, h.y, 0.0), center + Vector3(-h.x, h.y, 0.0)], Vector3(0.0, 0.0, 1.0))


## Disco plano en el plano XY local, mirando a +Z.
func disc(radius: float, segments: int = 16, z: float = 0.0) -> void:
	var pts: Array = []
	for i in segments:
		var a: float = TAU * i / segments
		pts.append(Vector3(cos(a) * radius, sin(a) * radius, z))
	face(pts, Vector3(0.0, 0.0, 1.0))


## Estrella de cinco puntas en el plano XY local, mirando a +Z.
func star(radius: float, z: float = 0.0) -> void:
	var inner: float = radius * 0.4
	var center := Vector3(0.0, 0.0, z)
	for i in 10:
		var a0: float = PI * 0.5 + TAU * i / 10.0
		var a1: float = PI * 0.5 + TAU * (i + 1) / 10.0
		var r0: float = radius if i % 2 == 0 else inner
		var r1: float = inner if i % 2 == 0 else radius
		face([center, Vector3(cos(a0) * r0, sin(a0) * r0, z), Vector3(cos(a1) * r1, sin(a1) * r1, z)], Vector3(0.0, 0.0, 1.0))


# ---------------------------------------------------------------- interno

func _ring(p: Vector2, angle: float, sx: float, sz: float) -> Vector3:
	return Vector3(cos(angle) * p.x * sx, p.y, sin(angle) * p.x * sz)


func _ring_normal(n: Vector2, angle: float, sx: float, sz: float) -> Vector3:
	var result := Vector3(cos(angle) * n.x / sx, n.y, sin(angle) * n.x / sz)
	return result.normalized() if result.length_squared() > 0.0000001 else Vector3.UP


## Añade un triángulo. El orden de los vértices se ajusta solo para que mire hacia sus normales.
func _tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, half: Vector2) -> void:
	var geometric: Vector3 = (b - a).cross(c - a)
	if geometric.length_squared() < 0.0000000001:
		return
	var tint := Color(color.r, color.g, color.b, kind / 20.0)
	var flip: bool = geometric.dot(na + nb + nc) > 0.0
	var order: Array = [[a, na, ua], [c, nc, uc], [b, nb, ub]] if flip else [[a, na, ua], [b, nb, ub], [c, nc, uc]]
	for item in order:
		_v.append(xf * (item[0] as Vector3))
		_n.append((xf.basis * (item[1] as Vector3)).normalized())
		_c.append(tint)
		_uv.append(item[2])
		_uv2.append(half)
