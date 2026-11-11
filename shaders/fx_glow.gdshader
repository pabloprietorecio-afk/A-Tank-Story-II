shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

// Luz que se suma a la imagen: destellos de explosión, fogonazos, halos y brasas.
//   COLOR = color (lineal) e intensidad; INSTANCE_CUSTOM = (clase + semilla, edad, tipo, vida).
// Tipos: 0 destello con rayos, 1 halo redondo, 2 brasa que parpadea, 3 estrella de fogonazo.

#include "res://shaders/fx_common.gdshaderinc"

global uniform float fx_fog_density;

uniform sampler2D fx_noise : filter_linear_mipmap, repeat_enable;

varying vec4 pdata;
varying vec3 tint;
varying vec2 quad;
// Altura sobre el suelo (los destellos se difuminan al llegar a él en vez de cortarse).
varying float world_y;

void vertex() {
	float seed = fract(INSTANCE_CUSTOM.x);
	float age = INSTANCE_CUSTOM.y;
	float kind = INSTANCE_CUSTOM.z;
	float k = clamp(age, 0.0, 1.0);
	float size = length(MODEL_MATRIX[0].xyz) * step(0.0, age);
	if (kind < 0.5) {
		size *= 0.5 + 0.5 * sqrt(k);
	} else if (kind > 1.5 && kind < 2.5) {
		size *= 1.0 - k * 0.6;
	}
	float angle = seed * 43.0;
	float c = cos(angle);
	float s = sin(angle);
	quad = VERTEX.xy * 2.0;
	vec2 offset = vec2(quad.x * c - quad.y * s, quad.x * s + quad.y * c) * size * 0.5;
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	if (kind < 1.5 || kind > 2.5) {
		// Un destello deslumbra: se dibuja algo más cerca de la cámara para que el suelo o lo
		// que alumbra no lo corten por la mitad.
		float distance = length(center);
		center *= 1.0 - min(size * 0.3, distance * 0.5) / max(distance, 0.001);
	}
	VERTEX = center + vec3(offset, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	world_y = (kind > 1.5 && kind < 2.5) ? 10.0 : (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	// La niebla apaga la luz lejana (el motor no sabe hacerlo con mezclas aditivas).
	pdata = vec4(seed, age, kind, COLOR.a * exp(-length(center) * fx_fog_density));
	tint = COLOR.rgb;
}

void fragment() {
	float r = length(quad);
	float age = clamp(pdata.y, 0.0, 1.0);
	float kind = pdata.z;
	float falloff = max(1.0 - r, 0.0);
	float soft = falloff * falloff;
	float i;
	if (kind < 0.5) {
		// Destello: núcleo deslumbrante y rayos irregulares que se apagan enseguida.
		float turn = atan(quad.y, quad.x) / 6.2832;
		float rays = texture(fx_noise, vec2(turn * 3.0, pdata.x * 7.0)).r;
		float fade = 1.0 - age;
		i = (exp(-r * r * 9.0) * 1.9 + soft * smoothstep(0.42, 0.8, rays) * 0.9 + soft * falloff * 0.5) * fade * sqrt(fade);
	} else if (kind < 1.5) {
		i = soft * (1.0 - age);
	} else if (kind < 2.5) {
		float flicker = 0.62 + 0.38 * sin(age * 70.0 + pdata.x * 40.0);
		i = exp(-r * r * 6.0) * flicker * (1.0 - smoothstep(0.55, 1.0, age)) * 1.7;
	} else {
		// Fogonazo visto de frente: lengua de fuego con puntas.
		float turn = atan(quad.y, quad.x);
		float points = pow(abs(cos(turn * 2.5 + pdata.x * 6.0)), 6.0);
		float fade = 1.0 - age;
		i = (exp(-r * r * 7.0) * 1.8 + soft * points * 1.1 + soft * 0.35) * fade * fade;
	}
	ALBEDO = fx_out(tint * i * pdata.w * smoothstep(-0.3, 0.7, world_y));
}
