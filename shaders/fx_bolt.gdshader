shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

// Rayo: una cinta que sigue el trazado quebrado de la descarga y se pone siempre de cara a la
// cámara. Cada vértice trae el punto del trazado, la dirección del tramo (NORMAL), a qué lado
// cae (UV.x) y lo gruesa que es esa rama (UV2.x).

#include "res://shaders/fx_common.gdshaderinc"

global uniform float fx_fog_density;

uniform float power = 1.0;
uniform float width = 1.8;

varying float fade;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 along = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 side = normalize(cross(along, CAMERA_POSITION_WORLD - world));
	world += side * (UV.x * 2.0 - 1.0) * width * UV2.x;
	// La lluvia lo vela con la distancia, pero un rayo se ve desde muy lejos.
	fade = exp(-distance(world, CAMERA_POSITION_WORLD) * fx_fog_density * 0.25) * UV2.x;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.0, 0.2, across);
	float halo = (1.0 - across) * (1.0 - across);
	vec3 color = vec3(0.55, 0.68, 1.0) * halo * 0.8 + vec3(1.0, 0.98, 0.95) * core * 2.2;
	ALBEDO = fx_out(color * power * fade);
}
