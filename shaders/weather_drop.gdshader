shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

// Lo que cae del cielo, visto de cerca: gotas de lluvia y granos de arena como trazos finos en
// la dirección en que caen (lo que deja ver el ojo de algo tan rápido), o copos de nieve
// redondos y blandos. Reciben la luz del ambiente: se oscurecen bajo la tormenta y se
// encienden con el relámpago.

#include "res://shaders/fx_common.gdshaderinc"

global uniform vec3 fx_sun_color;
global uniform vec3 fx_ambient;

// Color propio (lineal) y opacidad.
uniform vec3 tint = vec3(0.75, 0.82, 0.95);
uniform float opacity = 0.4;
// Ancho y largo del trazo (m) y dirección en la que cae; con `flake` son copos redondos.
uniform vec2 size = vec2(0.02, 0.8);
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);
uniform bool flake = false;

varying float strength;

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	float k = length(MODEL_MATRIX[0].xyz);
	if (flake) {
		// Los copos no caen rectos: revolotean.
		float id = float(INSTANCE_ID);
		center += vec3(sin(TIME * 1.3 + id * 12.9898), sin(TIME * 0.9 + id * 4.1) * 0.4, cos(TIME * 1.1 + id * 78.233)) * 0.14;
	}
	vec3 along = flake ? INV_VIEW_MATRIX[1].xyz : normalize(fall_dir);
	vec3 side = flake ? INV_VIEW_MATRIX[0].xyz : normalize(cross(along, CAMERA_POSITION_WORLD - center));
	vec3 world = center + side * VERTEX.x * size.x * k + along * VERTEX.y * size.y * k;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	// Cada gota brilla distinto, y las que rozan la cámara se desvanecen en vez de cruzarla.
	float near = smoothstep(0.4, 1.6, length(VERTEX));
	strength = (0.45 + 0.55 * fract(float(INSTANCE_ID) * 0.6180339)) * near;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float shape;
	if (flake) {
		shape = 1.0 - smoothstep(0.25, 1.0, length(q));
	} else {
		float across = 1.0 - abs(q.x);
		shape = across * across * (1.0 - q.y * q.y);
	}
	vec3 light = fx_ambient * 2.4 + fx_sun_color * 0.22 + vec3(0.05);
	ALBEDO = fx_out(tint * min(light, vec3(1.6)));
	ALPHA = shape * opacity * strength;
}
