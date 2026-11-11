shader_type spatial;
render_mode diffuse_lambert, specular_disabled, shadows_disabled;

// Cascote o esquirla que sale despedido: un trozo iluminado por el sol que da vueltas, rebota
// en el suelo, se queda un rato y se encoge hasta desaparecer.
//   COLOR = color (lineal); INSTANCE_CUSTOM = (semilla, edad, incandescencia 0..1, vida).

#include "res://shaders/fx_common.gdshaderinc"

varying vec3 base;
varying float glow;

void vertex() {
	float age = INSTANCE_CUSTOM.y;
	float k = clamp(age, 0.0, 1.0);
	VERTEX *= step(0.0, age) * (1.0 - smoothstep(0.85, 1.0, k));
	base = COLOR.rgb;
	float cool = 1.0 - smoothstep(0.0, 0.35, k);
	glow = INSTANCE_CUSTOM.z * cool * cool;
}

void fragment() {
	ALBEDO = fx_out(base);
	ROUGHNESS = 0.9;
	EMISSION = fx_out(vec3(1.0, 0.3, 0.04) * glow * 1.6);
}
