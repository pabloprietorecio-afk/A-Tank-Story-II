class_name SkyDome
extends Node3D
## Cielo retro: estrellas y una luna lejanas que siguen al jugador (nunca se alcanzan).
## Se dibujan sin niebla; con mal tiempo se ocultan.

const STAR_COUNT: int = 260
const DISTANCE: float = 520.0

var follow: Node3D


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/sky_dots.gdshader")
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in STAR_COUNT:
		var yaw: float = rng.randf() * TAU
		var pitch: float = asin(rng.randf_range(0.08, 0.95))
		var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
		var pos: Vector3 = dir * DISTANCE
		var basis := Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.5, 1.6)), pos))
		multimesh.set_instance_color(i, Color.WHITE * rng.randf_range(0.35, 1.0))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = multimesh
	stars.custom_aabb = AABB(Vector3.ONE * -DISTANCE, Vector3.ONE * DISTANCE * 2.0)
	add_child(stars)

	# Luna llena sobre el atardecer.
	var moon_dir := Vector3(-0.55, 0.32, -0.77).normalized()
	for part in [[Color(1.0, 0.97, 0.85), 16.0, Vector3.ZERO]]:
		var disc := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = part[1]
		mesh.height = part[1] * 2.0
		mesh.radial_segments = 24
		mesh.rings = 8
		disc.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = material.shader
		mat.set_shader_parameter("color", part[0])
		disc.material_override = mat
		var basis := Basis.looking_at(-moon_dir)
		disc.position = moon_dir * (DISTANCE - (0.0 if part[0] != Color.BLACK else 8.0)) + basis * part[2]
		disc.scale = Vector3(1.0, 1.0, 0.05)
		disc.basis = basis.scaled(Vector3(1.0, 1.0, 0.05))
		add_child(disc)


func _process(_delta: float) -> void:
	if follow != null and is_instance_valid(follow):
		global_position = Vector3(follow.global_position.x, 0.0, follow.global_position.z)
