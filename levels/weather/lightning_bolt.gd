class_name LightningBolt
extends MeshInstance3D
## Rayo que cae de las nubes al suelo: un trazado quebrado con alguna rama, que parpadea un
## par de veces (las descargas de retorno) y se apaga en menos de medio segundo.

const TIME: float = 0.45

var _age: float = 0.0
var _material: ShaderMaterial


static func strike(host: Node, top: Vector3, foot: Vector3) -> LightningBolt:
	var bolt := LightningBolt.new()
	bolt._build(top, foot)
	host.add_child(bolt)
	bolt.global_transform = Transform3D.IDENTITY
	return bolt


func _build(top: Vector3, foot: Vector3) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var widths := PackedVector2Array()
	var indices := PackedInt32Array()
	var trunk: PackedVector3Array = _path(top, foot, 5, top.distance_to(foot) * 0.11)
	_ribbon(trunk, 1.0, vertices, normals, uvs, widths, indices)
	# Ramas: salen de la mitad alta del tronco y mueren en el aire, más finas.
	for b in randi_range(2, 4):
		var from: Vector3 = trunk[randi_range(3, trunk.size() / 2)]
		var reach: float = from.y * randf_range(0.25, 0.55)
		var heading: float = randf() * TAU
		var to: Vector3 = from + Vector3(cos(heading) * reach * 0.7, -reach, sin(heading) * reach * 0.7)
		_ribbon(_path(from, to, 3, reach * 0.14), randf_range(0.3, 0.5), vertices, normals, uvs, widths, indices)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = widths
	arrays[Mesh.ARRAY_INDEX] = indices
	var bolt_mesh := ArrayMesh.new()
	bolt_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = bolt_mesh
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/fx_bolt.gdshader")
	_material.render_priority = 6
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 8.0


## Trazado quebrado entre dos puntos: se parte por la mitad varias veces, desviando cada vez
## el punto medio (cada vez menos).
func _path(from: Vector3, to: Vector3, levels: int, wander: float) -> PackedVector3Array:
	var points := PackedVector3Array([from, to])
	for level in levels:
		var next := PackedVector3Array()
		for i in points.size() - 1:
			var middle: Vector3 = (points[i] + points[i + 1]) * 0.5
			middle += Vector3(randf_range(-1.0, 1.0), randf_range(-0.35, 0.35), randf_range(-1.0, 1.0)) * wander
			next.append(points[i])
			next.append(middle)
		next.append(points[points.size() - 1])
		points = next
		wander *= 0.52
	return points


func _ribbon(points: PackedVector3Array, thickness: float, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, widths: PackedVector2Array, indices: PackedInt32Array) -> void:
	var base: int = vertices.size()
	var last: int = points.size() - 1
	for i in points.size():
		var along: Vector3 = (points[mini(i + 1, last)] - points[maxi(i - 1, 0)]).normalized()
		# La rama se afina hacia la punta.
		var taper: float = thickness * (1.0 if thickness >= 1.0 else 1.0 - 0.7 * float(i) / last)
		for side in 2:
			vertices.append(points[i])
			normals.append(along)
			uvs.append(Vector2(side, float(i) / last))
			widths.append(Vector2(taper, 0.0))
		if i < last:
			var v: int = base + i * 2
			indices.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))


func _process(delta: float) -> void:
	_age += delta
	if _age >= TIME:
		queue_free()
		return
	# Primera descarga, un parpadeo y la segunda, que se apaga.
	var power: float = 1.0
	if _age > 0.07 and _age < 0.13:
		power = 0.2
	elif _age >= 0.13:
		power = 0.95 * (1.0 - (_age - 0.13) / (TIME - 0.13))
	_material.set_shader_parameter("power", power)
