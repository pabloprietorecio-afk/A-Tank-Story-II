shader_type spatial;
render_mode cull_back;

#include "res://shaders/surface_common.gdshaderinc"

// Material único de los vehículos. Cada vértice trae su color base (COLOR.rgb) y su tipo de
// superficie (COLOR.a * 20), así todo un casco se dibuja de una vez:
//  0 blindaje pintado (soldaduras, tornillos)   1 pintado liso (piezas fundidas)
//  2 acero desnudo      3 oruga                 4 goma
//  5 madera             6 lona                  7 luz (emisiva)
//  8 distintivo pintado 9 cristal               10 mate liso (tripulación)
// UV = coordenadas de la cara en metros (centradas), UV2 = mitad del tamaño de la cara.
uniform vec3 paint_base : source_color = vec3(0.35, 0.38, 0.25);
uniform int camo_mode = 0;
uniform vec3 camo_a : source_color = vec3(0.3, 0.35, 0.2);
uniform vec3 camo_b : source_color = vec3(0.35, 0.25, 0.15);
uniform float camo_scale = 1.0;
uniform vec3 dust_color : source_color = vec3(0.34, 0.29, 0.2);
uniform float wear = 0.6;
uniform float burnt = 0.0;
uniform vec2 track_offset = vec2(0.0);
uniform float detail_scale = 1.0;

varying vec3 lp;
varying vec3 ln;
varying float world_y;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	int kind = int(COLOR.a * 20.0 + 0.5);
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float s = detail_scale;
	vec3 n = normalize(ln);
	vec3 an = abs(n);
	vec2 tp = an.y > 0.6 ? lp.xz : (an.x > an.z ? lp.zy : lp.xy);
	vec2 q = tp / s;

	vec2 ed = UV2 - abs(UV);
	float has_edge = step(0.0001, UV2.x + UV2.y);
	float edge_d = mix(10.0, min(ed.x, ed.y), has_edge) / s;
	float face_min = min(UV2.x, UV2.y) / s;

	vec4 nz = noise4(q * 1.3 + lp.y * 0.7);
	float n_large = nz.r * 0.6 + noise4(q * 3.1 + 5.0).g * 0.4;
	vec4 fine = noise4(q * 11.0 + 3.0);
	float low = 1.0 - smoothstep(0.15 * s, 1.15 * s, world_y);

	vec3 col = base;
	float h = 0.0;
	float rough = 0.8;
	float metal = 0.0;
	vec3 emission = vec3(0.0);
	float dust = 0.0;

	if (kind <= 1) {
		col = apply_camo(paint_base, camo_mode, camo_a, camo_b, camo_scale, lp) * base;
		col *= 0.8 + n_large * 0.4;
		rough = 0.62 + fine.g * 0.2;
		metal = 0.15;
		// Canto de las planchas: pintura gastada y cordón de soldadura.
		float rim = (1.0 - smoothstep(0.0, 0.03, edge_d)) * has_edge;
		float weld = smoothstep(0.02, 0.035, edge_d) * (1.0 - smoothstep(0.05, 0.065, edge_d)) * has_edge * step(0.2, face_min);
		h += weld * (0.004 + fine.b * 0.003) * s;
		col *= 1.0 - weld * 0.18;
		if (kind == 0 && face_min > 0.3) {
			// Tornillos a lo largo del borde de las planchas grandes.
			float along = ed.x < ed.y ? UV.y : UV.x;
			float pitch = 0.26 * s;
			vec2 bolt_p = vec2((fract(along / pitch) - 0.5) * pitch, min(ed.x, ed.y) - 0.11 * s) / s;
			float bolt = 1.0 - smoothstep(0.018, 0.03, length(bolt_p));
			h += bolt * 0.008 * s;
			col = mix(col, col * 0.7, bolt * 0.5);
		}
		// Desconchones: más cerca de los cantos.
		float chip_n = noise4(q * 24.0 + 7.0).r * 0.6 + fine.r * 0.4;
		float chip = smoothstep(0.74, 0.8, chip_n + rim * 0.22 * wear + (wear - 0.6) * 0.15);
		vec3 steel = mix(vec3(0.07, 0.06, 0.055), vec3(0.2, 0.1, 0.05), fine.a * 0.7);
		col = mix(col, steel, chip * 0.85);
		metal = mix(metal, 0.6, chip);
		h -= chip * 0.0015 * s;
		col = mix(col, col * 1.5 + 0.03, rim * 0.35);
		// Churretes de óxido y lluvia en las caras verticales.
		float vertical = 1.0 - smoothstep(0.3, 0.6, an.y);
		float streak = smoothstep(0.55, 0.85, noise4(vec2(tp.x * 5.0 / s, tp.y * 0.5 / s + 2.0)).g) * vertical;
		col = mix(col, col * vec3(0.62, 0.46, 0.36), streak * 0.55 * wear);
		dust = max(n.y, 0.0) * (0.25 + nz.b * 0.35) + low * (0.35 + n_large * 0.5);
		h += (fine.g - 0.5) * 0.0012 * s;
	} else if (kind == 2) {
		col = base * (0.75 + n_large * 0.5);
		float rim = (1.0 - smoothstep(0.0, 0.025, edge_d)) * has_edge;
		col = mix(col, vec3(0.45, 0.43, 0.4), rim * 0.4);
		col = mix(col, vec3(0.25, 0.12, 0.06), smoothstep(0.62, 0.8, fine.r) * 0.5 * wear);
		rough = 0.45 + fine.g * 0.25;
		metal = 0.7;
		dust = low * 0.4 * n_large;
		h += (fine.g - 0.5) * 0.001 * s;
	} else if (kind == 3) {
		// Oruga: UV.y recorre la banda, UV.x la cruza.
		float scroll = lp.x < 0.0 ? track_offset.x : track_offset.y;
		float t = UV.y / (0.17 * s) + scroll;
		float f = fract(t);
		float aa = fwidth(t) + 0.001;
		float plate = smoothstep(0.06, 0.06 + aa + 0.04, f) * (1.0 - smoothstep(0.94 - aa - 0.04, 0.94, f));
		float bar = smoothstep(0.34, 0.4, f) * (1.0 - smoothstep(0.6, 0.66, f));
		float across = abs(UV.x) / max(UV2.x, 0.001);
		float pin = smoothstep(0.78, 0.84, across);
		float guide = 1.0 - smoothstep(0.1, 0.16, across);
		float fade = clamp(1.0 - (aa - 0.25) * 2.0, 0.0, 1.0);
		h = (plate * 0.014 + bar * (0.012 - guide * 0.006)) * s * fade;
		col = base * (0.55 + plate * 0.35 + n_large * 0.3);
		col = mix(col, vec3(0.42, 0.41, 0.39), bar * (0.35 + fine.r * 0.3) * fade);
		col *= 1.0 - pin * 0.35;
		col = mix(col, vec3(0.28, 0.14, 0.07), smoothstep(0.55, 0.8, fine.g) * 0.35);
		rough = 0.5 + fine.b * 0.3;
		metal = 0.65;
		dust = 0.25 + n_large * 0.45;
	} else if (kind == 4) {
		col = base * (0.8 + fine.r * 0.4);
		rough = 0.95;
		dust = 0.2 + low * 0.3 * n_large;
	} else if (kind == 5) {
		float grain = noise4(vec2(tp.x * 3.0, tp.y * 40.0) / s).r;
		float grain2 = noise4(vec2(tp.x * 40.0, tp.y * 3.0) / s).r;
		float g = UV2.x >= UV2.y ? grain : grain2;
		col = base * (0.65 + g * 0.6);
		h = g * 0.003 * s;
		rough = 0.9;
		dust = low * 0.3;
	} else if (kind == 6) {
		float fold = sin(tp.x * 16.0 / s + n_large * 5.0) * 0.5 + 0.5;
		col = base * (0.78 + fold * 0.2 + fine.r * 0.14);
		h = fold * 0.012 * s;
		rough = 1.0;
		dust = max(n.y, 0.0) * 0.3;
	} else if (kind == 7) {
		col = base;
		emission = base * 1.6 * (1.0 - burnt);
		rough = 0.3;
	} else if (kind == 8) {
		col = base * (0.82 + n_large * 0.25);
		col = mix(col, col * 0.45, smoothstep(0.7, 0.8, fine.r) * wear);
		rough = 0.75;
		dust = low * 0.3 + max(n.y, 0.0) * 0.2;
	} else if (kind == 9) {
		col = base;
		rough = 0.12;
		metal = 0.4;
	} else {
		col = base * (0.9 + fine.r * 0.15);
		rough = 0.9;
	}

	dust = clamp(dust * (0.5 + wear), 0.0, 0.8);
	col = mix(col, dust_color * (0.8 + fine.a * 0.3), dust);
	rough = mix(rough, 0.97, dust);
	metal *= 1.0 - dust;

	if (burnt > 0.0) {
		vec3 char_col = mix(vec3(0.025, 0.023, 0.022), vec3(0.2, 0.09, 0.04), smoothstep(0.45, 0.75, n_large) * 0.8);
		char_col = mix(char_col, vec3(0.3, 0.29, 0.27), smoothstep(0.75, 0.9, fine.r) * 0.3);
		col = mix(col, char_col, burnt);
		rough = mix(rough, 0.95, burnt);
		metal = mix(metal, 0.1, burnt);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emission;
	NORMAL = bump_normal(NORMAL, VERTEX, h * detail_fade(VERTEX, 25.0, 70.0));
}
