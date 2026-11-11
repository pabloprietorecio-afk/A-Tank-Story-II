shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Montón de escombros: cascotes del color del material de lo que se ha venido abajo. Lo que
// arde se va tiznando de hollín y, mientras dura el fuego, brillan brasas en los huecos.
//   COLOR = color de cada cascote (lineal).

#include "res://shaders/fx_common.gdshaderinc"

uniform sampler2D fx_noise : filter_linear_mipmap, repeat_enable;
uniform float soot = 0.0;
uniform float embers = 0.0;

varying vec3 base;
varying vec3 world;

void vertex() {
	base = COLOR.rgb;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wide = texture(fx_noise, world.xz * 0.31 + world.y * 0.17).b;
	float fine = texture(fx_noise, world.xz * 1.3 + world.yy * 0.9).r;
	vec3 color = base * (0.62 + 0.7 * wide) * (0.85 + 0.3 * fine);
	color = mix(color, vec3(0.012, 0.011, 0.01) + color * 0.1, soot * smoothstep(0.2, 0.7, wide + 0.25));
	ALBEDO = fx_out(color);
	ROUGHNESS = 0.95;
	float hot = embers * smoothstep(0.6, 0.85, fine) * (0.65 + 0.35 * sin(TIME * 3.0 + world.x * 5.0 + world.z * 3.0));
	EMISSION = fx_out(vec3(1.0, 0.28, 0.04) * hot * 1.6);
}
