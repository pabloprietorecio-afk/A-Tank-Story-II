shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Trazo de luz alargado en la dirección en que vuela: chispas, esquirlas al rojo y lenguas de
// fuego del cañón. El motor orienta el cuadrado (eje Y = velocidad, de cara a la cámara) y la
// física le da el largo según la velocidad.
//   COLOR = color (lineal) e intensidad;
//   INSTANCE_CUSTOM = (semilla, edad, cuánto se enfría [0 no, 1 del blanco al rojo], vida).

#include "res://shaders/fx_common.gdshaderinc"

global uniform float fx_fog_density;

varying vec4 pdata;
varying vec3 tint;

void vertex() {
	float age = INSTANCE_CUSTOM.y;
	float k = clamp(age, 0.0, 1.0);
	// La cabeza va en la posición de la partícula y la cola queda detrás; se afina al apagarse.
	VERTEX.y -= 0.5;
	VERTEX.x *= 1.0 - k * 0.6;
	VERTEX *= step(0.0, age);
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pdata = vec4(fract(INSTANCE_CUSTOM.x), k, INSTANCE_CUSTOM.z, COLOR.a * exp(-length(view_pos) * fx_fog_density));
	tint = COLOR.rgb;
}

void fragment() {
	float tail = UV.y;
	float across = abs(UV.x * 2.0 - 1.0);
	// Forma de cometa: cabeza redonda y cola que se estrecha.
	float width = mix(1.0, 0.25, tail);
	float core = max(1.0 - across / width, 0.0);
	float head = smoothstep(0.0, 0.08, tail);
	float i = core * core * head * (1.0 - tail * tail);
	float heat = 1.0 - pdata.y * pdata.z;
	vec3 color = mix(vec3(1.0, 0.16, 0.015), tint, heat * heat);
	float fade = 1.0 - smoothstep(0.7, 1.0, pdata.y);
	ALBEDO = fx_out(color * i * pdata.w * fade * (0.5 + heat));
}
