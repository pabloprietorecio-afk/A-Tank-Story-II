shader_type spatial;
render_mode cull_back;

#include "res://shaders/surface_common.gdshaderinc"

// Terreno: hierba, pasto seco, tierra y grava mezclados con ruido, con relieve, rodadas de
// oruga, charcos cuando llueve y nieve. La retícula retro es opcional (grid_strength).
uniform vec3 grass : source_color = vec3(0.22, 0.27, 0.12);
uniform vec3 dry_grass : source_color = vec3(0.36, 0.33, 0.18);
uniform vec3 dirt : source_color = vec3(0.30, 0.23, 0.15);
uniform vec3 gravel : source_color = vec3(0.38, 0.37, 0.34);
uniform vec3 line_color : source_color = vec3(0.2, 1.0, 0.33);
uniform float grid_strength = 0.0;
uniform float cell_size = 20.0;
// Nieve (0..1) y suelo mojado (0..1).
uniform float tint = 0.0;
uniform float wet = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float near = detail_fade(VERTEX, 25.0, 90.0);
	float large = fbm(p * 0.012);
	float medium = fbm(p * 0.06 + 13.0);
	vec4 mid = noise4(p * 0.55 + 21.0);
	vec4 fine = noise4(p * 2.6);
	vec4 micro = noise4(p * 9.0 + 5.0);

	float dry_f = smoothstep(0.35, 0.7, medium);
	float dirt_f = smoothstep(0.52, 0.7, large + (mid.r - 0.5) * 0.25);
	float gravel_f = smoothstep(0.74, 0.86, fbm(p * 0.03 + 40.0) + (mid.g - 0.5) * 0.2) * 0.85;

	// Hierba: matas y briznas.
	float tuft = smoothstep(0.35, 0.75, mid.b * 0.6 + fine.r * 0.4);
	float blades = noise4(vec2(p.x * 7.0 + p.y * 2.0, p.y * 3.0)).g;
	vec3 turf = mix(grass, dry_grass, dry_f);
	turf *= 0.72 + tuft * 0.4 + (blades - 0.5) * 0.3 * near;
	turf = mix(turf, turf * vec3(1.15, 1.1, 0.75), smoothstep(0.7, 0.9, fine.b) * 0.5 * near);
	// Tierra: terrones y piedrecillas.
	vec3 soil = dirt * (0.7 + mid.a * 0.35 + (micro.r - 0.5) * 0.3 * near);
	float pebble = smoothstep(0.8, 0.92, noise4(p * 19.0 + 5.0).g) * near;
	soil = mix(soil, gravel * 0.95, pebble * 0.45);
	// Grava.
	vec3 stones = gravel * (0.65 + fine.g * 0.4 + micro.b * 0.3 * near);

	vec3 color = mix(turf, soil, dirt_f);
	color = mix(color, stones, gravel_f);
	float bare = max(dirt_f, gravel_f);
	float h = mix(tuft * 0.07 + blades * 0.03 * near, mid.a * 0.05 + micro.r * 0.02 * near + pebble * 0.02, dirt_f);
	h = mix(h, fine.g * 0.03 + micro.b * 0.03 * near, gravel_f);

	// Rodadas de oruga: pares de surcos sinuosos con las huellas de los eslabones.
	float lane = (p.x + sin(p.y * 0.02) * 30.0) / 70.0;
	float across = abs(fract(lane) - 0.5) * 70.0;
	float rut = (1.0 - smoothstep(0.35, 0.75, abs(across - 1.6))) * step(0.5, noise(p * 0.01 + 5.0));
	float tread = 0.6 + 0.4 * step(0.5, fract(p.y * 2.2)) * near;
	color = mix(color, dirt * 0.55, rut * 0.65 * tread);
	h -= rut * 0.06 * tread;
	bare = max(bare, rut);

	float rough = mix(0.96, 0.9, bare);
	// Lluvia: todo más oscuro y charcos brillantes en las zonas de tierra y en las rodadas.
	if (wet > 0.0) {
		float puddle = smoothstep(0.52, 0.6, noise4(p * 0.09 + 9.0).a * 0.7 + bare * 0.3 + rut * 0.2) * wet;
		color *= 1.0 - wet * 0.12;
		color = mix(color, color * 0.45 + vec3(0.02, 0.025, 0.03), puddle);
		rough = mix(mix(rough, 0.6, wet * 0.6), 0.06, puddle);
		h *= 1.0 - puddle;
	}
	// Nieve: cubre lo llano, deja asomar hierba y rodadas.
	if (tint > 0.0) {
		float snow = tint * smoothstep(0.2, 0.55, medium + 0.25 + (fine.r - 0.5) * 0.2) * (1.0 - rut * 0.7);
		vec3 snow_color = vec3(0.86, 0.89, 0.93) * (0.9 + mid.r * 0.1) + smoothstep(0.9, 0.97, micro.a) * 0.25 * near;
		color = mix(color, snow_color, snow);
		rough = mix(rough, 0.55, snow);
		h = mix(h, mid.b * 0.05, snow);
	}

	vec2 coord = p / cell_size;
	vec2 dist = abs(fract(coord - 0.5) - 0.5) / (fwidth(coord) + 0.00001);
	float grid = 1.0 - clamp(min(dist.x, dist.y) / 1.5, 0.0, 1.0);
	ALBEDO = color;
	EMISSION = line_color * grid * grid_strength;
	ROUGHNESS = rough;
	NORMAL = bump_normal(NORMAL, VERTEX, h * near);
}
