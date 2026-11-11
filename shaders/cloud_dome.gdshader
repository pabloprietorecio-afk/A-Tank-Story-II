shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_front, fog_disabled, shadows_disabled;

#include "res://shaders/fx_common.gdshaderinc"

// Techo de nubes: una cúpula alrededor de la cámara en la que se proyecta una capa plana de
// nubes que se mueve con el viento. El sol las alumbra por su lado y, lo que más importa, los
// destellos de la batalla (artillería, antiaérea, explosiones grandes, relámpagos) las
// encienden desde abajo: el resplandor sale del punto del destello y se apaga con la distancia
// (a la distancia `alcance` queda en un tercio).

global uniform vec3 fx_sun_dir;

uniform sampler2D fx_noise : filter_linear_mipmap, repeat_enable;
// Color de la nube por el lado del sol, en sombra, y bruma del horizonte en la que se funde.
uniform vec3 lit_color = vec3(1.0, 0.5, 0.28);
uniform vec3 shade_color = vec3(0.2, 0.12, 0.17);
uniform vec3 haze_color = vec3(0.6, 0.2, 0.08);
// Cuánto cielo tapan (0 despejado, 1 cubierto), lo deshilachado del borde y su opacidad.
uniform float coverage = 0.5;
uniform float softness = 0.3;
uniform float density = 0.85;
// Altura de la base de las nubes (m) y deriva por el viento (km/s en x y z).
uniform float base_height = 320.0;
uniform vec2 drift = vec2(0.004, 0.0015);
// Destellos: posición en el mundo y alcance (m); color por intensidad.
uniform vec4 flash_at[6];
uniform vec4 flash_light[6];
// Con los efectos bajos: una sola capa de ruido y sin destellos.
uniform bool cheap = false;

varying vec3 ray;
varying vec3 eye;

void vertex() {
	ray = VERTEX;
	eye = MODEL_MATRIX[3].xyz;
}

void fragment() {
	vec3 d = normalize(ray);
	float up = max(d.y, 0.0);
	// Distancia a la capa de nubes siguiendo el rayo (acotada cerca del horizonte).
	float reach = base_height / (up + 0.06);
	vec3 point = eye + d * reach;
	vec2 p = point.xz * 0.001 + drift * TIME;
	vec4 wide = texture(fx_noise, p * 0.23);
	vec4 fine = cheap ? wide.gbar : texture(fx_noise, p * 0.71 + vec2(0.31, 0.17) + drift * TIME * 0.6);
	float n = wide.r * 0.55 + fine.g * 0.3 + wide.a * 0.15;
	float edge = 1.0 - coverage;
	float cloud = smoothstep(edge - softness * 0.5, edge + softness * 0.5, n);
	float thick = smoothstep(edge, edge + 0.45, n);
	// El lado que mira al sol brilla; el corazón de la nube y el lado contrario se oscurecen.
	float toward = dot(d, fx_sun_dir) * 0.5 + 0.5;
	vec3 color = mix(shade_color, lit_color, clamp(toward * 0.95 - thick * 0.6 + 0.05, 0.0, 1.0));
	color = mix(haze_color, color, smoothstep(0.0, 0.3, up));
	float alpha = cloud * density * smoothstep(0.0, 0.1, up);
	// Destellos de la batalla.
	vec3 glow = vec3(0.0);
	for (int i = 0; i < (cheap ? 0 : 6); i++) {
		if (flash_light[i].w > 0.0) {
			float span = max(flash_at[i].w, 1.0);
			glow += flash_light[i].rgb * exp(-distance(flash_at[i].xyz, point) / span);
		}
	}
	// La luz dibuja el relieve de la panza de las nubes: los bultos que cuelgan se encienden
	// más que los huecos.
	color += glow * (0.25 + 0.75 * cloud) * (0.5 + 0.9 * fine.b);
	// El resplandor se ve también en el aire limpio, más flojo.
	alpha = max(alpha, clamp(dot(glow, vec3(0.34)) * 0.5, 0.0, 0.6));
	ALBEDO = fx_out(color);
	ALPHA = alpha;
}
