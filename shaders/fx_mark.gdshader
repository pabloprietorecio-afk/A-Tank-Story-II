shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

#include "res://shaders/surface_common.gdshaderinc"
#include "res://shaders/fx_common.gdshaderinc"

// Marcas que deja la batalla en el suelo: quemadura (hollín con lenguas radiales) o cráter
// (hoyo oscuro, reborde de tierra removida y tierra salpicada alrededor). Reciben la luz y las
// sombras como el propio suelo.
//   COLOR = color de la tierra del frente (lineal);
//   INSTANCE_CUSTOM = (semilla, tipo: 0 quemadura / 1 cráter, sin uso, opacidad).

uniform sampler2D fx_noise : filter_linear_mipmap, repeat_enable;

varying vec4 pdata;
varying vec3 soil;
varying float radius;

void vertex() {
	pdata = INSTANCE_CUSTOM;
	soil = COLOR.rgb;
	radius = length(MODEL_MATRIX[0].xyz) * 0.5;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float seed = pdata.x;
	float turn = atan(c.y, c.x) / 6.2832;
	vec4 n = texture(fx_noise, c * 0.9 + seed * 7.3);
	// Vetas que salen del centro (casi iguales a lo largo de cada radio).
	float streaks = texture(fx_noise, vec2(turn * 4.0, seed * 3.1 + r * 0.2)).r;
	float edge = r + (n.r - 0.5) * 0.42;
	vec3 color;
	float alpha;
	float height = 0.0;
	if (pdata.y < 0.5) {
		float burn = 1.0 - smoothstep(0.12, 0.72, edge);
		float rays = smoothstep(0.5, 0.78, streaks) * (1.0 - smoothstep(0.3, 0.95, r));
		color = mix(vec3(0.04, 0.035, 0.03), vec3(0.006), burn);
		alpha = clamp(burn * 0.9 + rays * 0.42, 0.0, 0.92);
	} else {
		float bowl = 1.0 - smoothstep(0.02, 0.42, edge);
		float rim = smoothstep(0.26, 0.44, edge) * (1.0 - smoothstep(0.48, 0.7, edge));
		float blanket = (1.0 - smoothstep(0.45, 1.0, r)) * smoothstep(0.36, 0.66, streaks * 0.75 + n.g * 0.45);
		vec3 fresh = soil * (0.7 + n.b * 0.55);
		color = mix(fresh * 1.1, vec3(0.018, 0.016, 0.014), bowl * 0.9);
		color = mix(color, fresh * 0.55, blanket * (1.0 - bowl) * (1.0 - rim) * 0.7);
		alpha = max(max(bowl, rim), blanket * 0.8);
		height = (rim * 0.16 - bowl * 0.32) * radius;
	}
	ALBEDO = fx_out(color);
	ROUGHNESS = 0.95;
	ALPHA = alpha * (1.0 - smoothstep(0.86, 1.0, r)) * pdata.w;
	NORMAL = bump_normal(NORMAL, VERTEX, height);
}
