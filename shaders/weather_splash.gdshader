shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Salpicadura de una gota en el suelo mojado: un anillo que se abre y se borra en un instante.
// El cuadrado va tumbado sobre el suelo; INSTANCE_CUSTOM.y trae la edad (0..1).

#include "res://shaders/fx_common.gdshaderinc"

global uniform vec3 fx_sun_color;
global uniform vec3 fx_ambient;

uniform vec3 tint = vec3(0.8, 0.86, 0.95);
uniform float opacity = 0.42;

varying float age;

void vertex() {
	age = clamp(INSTANCE_CUSTOM.y / max(INSTANCE_CUSTOM.w, 0.01), 0.0, 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float edge = 0.25 + 0.7 * sqrt(age);
	float ring = smoothstep(edge - 0.3, edge, r) * (1.0 - smoothstep(edge, edge + 0.08, r));
	vec3 light = fx_ambient * 2.4 + fx_sun_color * 0.22;
	ALBEDO = fx_out(tint * min(light, vec3(1.6)));
	ALPHA = ring * (1.0 - age) * opacity;
}
