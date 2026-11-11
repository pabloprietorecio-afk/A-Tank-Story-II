shader_type spatial;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// El renderizador de compatibilidad (teléfonos sin Vulkan) no deja ajustar el premultiplicado
// en materiales sin iluminar: allí el color se entrega ya multiplicado y la niebla se aplica
// a mano, apagando la bocanada con la distancia.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#else
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
#endif

// Bocanada de humo, polvo o fuego: un cuadrado que mira a la cámara y que el ruido convierte
// en una nube con volumen. La ilumina el sol de la partida (por el lado que le da) y la luz
// ambiente; con calor es una llamarada que se enfría hasta volverse hollín; nace, crece y se
// deshace en jirones. El fuego suma luz y el humo tapa: por eso la mezcla es premultiplicada.
//   COLOR = color del humo (lineal) y opacidad;
//   INSTANCE_CUSTOM = (clase + semilla, edad, calor [> 0] o resplandor del fuego cercano
//   [< 0], vida).

#include "res://shaders/fx_common.gdshaderinc"

global uniform vec3 fx_sun_dir;
global uniform vec3 fx_sun_color;
global uniform vec3 fx_ambient;
global uniform float fx_fog_density;

uniform sampler2D fx_noise : filter_linear_mipmap, repeat_enable;
// Cada clase de bocanada (fuego, humo, polvo, chorro, terrón...) tiene su aspecto: cuánto crece
// (tamaño final = inicial × (1 + grow)) y con qué prisa, cuánto gira, a qué escala y con qué
// deriva se lee el ruido, cuánto abulta el contorno, a qué edad empieza a deshacerse, su
// opacidad y en cuántos metros se difumina contra el suelo.
uniform float grow[8];
uniform float grow_ease[8];
uniform float spin[8];
uniform float detail[8];
uniform float scroll[8];
uniform float lumps[8];
uniform float erode_from[8];
uniform float thickness[8];
uniform float ground_fade[8];
// Ancho del borde: fino = bola compacta, ancho = nube deshilachada.
uniform float softness[8];
uniform float fade_in = 0.06;
uniform float glow_gain = 1.0;

varying vec4 pdata;
varying vec3 tint;
varying vec2 quad;
varying vec3 sun_local;
varying float world_y;
// Aspecto de la clase, ya elegido en el vértice: (deriva, abultado, edad de deshacerse, escala).
varying vec4 look;
// (difuminado cerca de la cámara × opacidad de la clase, metros de difuminado con el suelo,
// segundos que lleva viva, ancho del borde).
varying vec4 fades;

void vertex() {
	int cls = clamp(int(INSTANCE_CUSTOM.x), 0, 7);
	float seed = fract(INSTANCE_CUSTOM.x);
	float age = INSTANCE_CUSTOM.y;
	float k = clamp(age, 0.0, 1.0);
	float size = length(MODEL_MATRIX[0].xyz) * (1.0 + grow[cls] * (1.0 - pow(1.0 - k, grow_ease[cls])));
	size *= step(0.0, age);
	float angle = seed * 43.0 + (fract(seed * 7.31) - 0.5) * spin[cls] * k * 6.2832;
	float c = cos(angle);
	float s = sin(angle);
	quad = VERTEX.xy * 2.0;
	vec2 offset = vec2(quad.x * c - quad.y * s, quad.x * s + quad.y * c) * size * 0.5;
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	VERTEX = center + vec3(offset, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	// El sol, girado al plano de la bocanada, para que la luz no gire con ella.
	vec3 sun_view = (VIEW_MATRIX * vec4(fx_sun_dir, 0.0)).xyz;
	sun_local = vec3(sun_view.x * c + sun_view.y * s, -sun_view.x * s + sun_view.y * c, sun_view.z);
	world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	// Muy cerca de la cámara se desvanece: no tapa la vista ni cuesta pintarla entera.
	float near_fade = smoothstep(0.3, 2.2, -center.z - size * 0.15);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	near_fade *= exp(-length(center) * fx_fog_density);
#endif
	pdata = vec4(seed, age, INSTANCE_CUSTOM.z, COLOR.a);
	tint = COLOR.rgb;
	look = vec4(scroll[cls], lumps[cls], erode_from[cls], detail[cls]);
	fades = vec4(near_fade * thickness[cls], max(ground_fade[cls], 0.01), max(age, 0.0) * INSTANCE_CUSTOM.w, softness[cls]);
}

vec3 fire_ramp(float t) {
	vec3 c = vec3(0.5, 0.035, 0.0) * smoothstep(0.0, 0.22, t);
	c = mix(c, vec3(1.0, 0.26, 0.02), smoothstep(0.18, 0.48, t));
	c = mix(c, vec3(1.0, 0.6, 0.11), smoothstep(0.45, 0.8, t));
	c = mix(c, vec3(1.0, 0.9, 0.56), smoothstep(0.8, 1.3, t));
	return c * (0.55 + t);
}

void fragment() {
	float seed = pdata.x;
	float age = clamp(pdata.y, 0.0, 1.0);
	float r2 = dot(quad, quad);
	vec2 nuv = quad * 0.5 * look.w + vec2(seed * 3.17, seed * 5.71);
	vec4 na = texture(fx_noise, nuv + vec2(0.0, age * look.x));
	vec4 nb = texture(fx_noise, nuv * 2.3 + vec2(0.37 - age * look.x * 0.7, 0.11));
	float billow = na.g * 0.62 + nb.g * 0.38;
	float wisp = na.r * 0.6 + nb.r * 0.4;
	float shape = 1.0 - sqrt(r2);
	float body = shape + (billow - 0.5) * look.y;
	// Se deshace: el umbral sube con la edad y solo aguantan los jirones.
	float late = smoothstep(look.z, 1.0, age);
	float threshold = mix(0.05, 0.6, late);
	float a = smoothstep(threshold, threshold + fades.w * mix(1.0, 0.65, late), body + (wisp - 0.5) * 0.55 * late);
	a *= smoothstep(0.0, fade_in, age) * (1.0 - smoothstep(0.8, 1.0, age));
	a *= pdata.w * fades.x * smoothstep(0.0, fades.y, world_y);

	// Volumen: normal de una esfera arrugada por el ruido, iluminada por el lado del sol.
	vec3 n = normalize(vec3(quad + (vec2(na.r, nb.g) - 0.5) * 1.2, sqrt(max(1.0 - r2, 0.0)) + 0.35));
	float wrap = clamp(dot(n, normalize(sun_local)) * 0.55 + 0.45, 0.0, 1.0);
	vec3 light = fx_ambient + fx_sun_color * wrap * wrap;
	float core = smoothstep(0.25, 0.95, body);
	vec3 smoke = tint * light * mix(1.0, 0.7, core) * (0.78 + billow * 0.44);

	float heat = max(pdata.z, 0.0);
	float under = max(-pdata.z, 0.0);
	// Humo alumbrado desde abajo por el fuego que tiene al lado.
	smoke += under * exp(-fades.z * 2.6) * vec3(1.0, 0.4, 0.09) * clamp(0.55 - n.y * 0.6, 0.0, 1.0);
	// Fuego: la temperatura cae con la edad y el ruido deja vetas vivas entre el hollín.
	float cooling = 1.0 - smoothstep(0.0, 0.85, age);
	float temp = heat * cooling * cooling * (0.3 + 1.3 * smoothstep(0.3, 0.95, billow * 0.75 + shape * 0.6));
	float glow = smoothstep(0.1, 0.48, temp);
	vec3 rgb = mix(smoke, fire_ramp(temp) * glow_gain, glow);

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = fx_out(rgb * a);
#else
	ALBEDO = rgb;
	PREMUL_ALPHA_FACTOR = a;
#endif
	ALPHA = a * mix(1.0, 0.75, glow);
}
