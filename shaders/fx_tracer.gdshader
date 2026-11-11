shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

// Proyectil trazador: una estela de luz que siempre da la cara a la cámara y, en la cabeza, un
// punto incandescente que se ve también de frente o desde atrás (que es como ve el jugador sus
// propios disparos). La malla son dos cuadrados: COLOR.r = 0 la estela, 1 la cabeza.

#include "res://shaders/fx_common.gdshaderinc"

global uniform float fx_fog_density;

// Color de la trazadora, en lineal.
instance uniform vec3 tint = vec3(1.0, 0.07, 0.015);
// Largo de la estela en metros (crece desde cero al salir del cañón).
instance uniform float trail = 6.0;
uniform float width = 0.26;
uniform float head = 0.7;

varying float part;
varying float fog;

void vertex() {
	vec3 origin = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	part = COLOR.r;
	// Recién salido del cañón aún no brilla del todo (y no deslumbra a quien dispara).
	fog = exp(-length(origin) * fx_fog_density) * clamp(trail / 5.0, 0.15, 1.0);
	if (part < 0.5) {
		vec3 side = cross(axis, normalize(-origin));
		float len = length(side);
		side = len > 0.0001 ? side / len : vec3(1.0, 0.0, 0.0);
		VERTEX = origin - axis * (0.5 - VERTEX.y) * trail + side * VERTEX.x * width;
	} else {
		VERTEX = origin + vec3(VERTEX.xy * head, 0.0);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (part < 0.5) {
		float across = 1.0 - abs(UV.x * 2.0 - 1.0);
		float along = 1.0 - UV.y;
		float i = across * across * along * along;
		ALBEDO = fx_out(mix(tint, vec3(1.0, 0.95, 0.85), across * along * 0.55) * i * 1.7 * fog);
	} else {
		vec2 q = UV * 2.0 - 1.0;
		float r2 = dot(q, q);
		float i = exp(-r2 * 7.0) * 1.3 + exp(-r2 * 45.0) * 1.2;
		ALBEDO = fx_out(mix(tint, vec3(1.0, 0.97, 0.9), exp(-r2 * 28.0)) * i * fog * (1.0 - smoothstep(0.7, 1.0, r2)));
	}
}
