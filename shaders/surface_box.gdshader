shader_type spatial;
render_mode cull_back;

#include "res://shaders/surface_common.gdshaderinc"

// Caja iluminada con textura procedural en relieve.
// pattern: 0 hormigón, 1 fachada con ventanas, 2 ladrillo/sillares, 3 orugas, 4 placas de acero,
//          5 tablones, 6 chapa ondulada, 7 ventana, 8 puerta, 9 enlucido desconchado,
//          10 sacos terreros, 11 troncos.
uniform vec3 half_size = vec3(1.0);
uniform vec3 base_color : source_color = vec3(0.5);
uniform int pattern = 0;
uniform float pattern_scale = 2.0;
// Camuflaje: 0 liso, 1 manchas, 2 franjas, 3 encalado de invierno.
uniform int camo_mode = 0;
uniform vec3 camo_a : source_color = vec3(0.3, 0.35, 0.2);
uniform vec3 camo_b : source_color = vec3(0.35, 0.25, 0.15);
uniform float camo_scale = 1.0;
uniform float roughness_value = 0.85;
uniform float metallic_value = 0.0;
uniform float edge_light = 0.12;

varying vec3 local_pos;
varying vec3 local_normal;
varying float world_y;
varying float node_seed;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	node_seed = fract(sin(dot(NODE_POSITION_WORLD.xz, vec2(12.9898, 78.233))) * 43758.5453);
}

// Ladrillos o sillares: devuelve (junta, identificador de pieza).
vec2 bricks(vec2 uv, float row_h, float len, out vec2 f) {
	float row = floor(uv.y / row_h);
	float bx = (uv.x + mod(row, 2.0) * len * 0.5) / len;
	f = vec2(fract(bx), fract(uv.y / row_h));
	float lod = clamp(1.0 - fwidth(bx) * 2.0, 0.0, 1.0);
	float joint = max(1.0 - smoothstep(0.02, 0.05, min(f.x, 1.0 - f.x)), 1.0 - smoothstep(0.05, 0.11, min(f.y, 1.0 - f.y)));
	return vec2(joint * lod, hash(vec2(floor(bx), row)));
}

void fragment() {
	vec3 d = half_size - abs(local_pos);
	float smallest = min(d.x, min(d.y, d.z));
	float largest = max(d.x, max(d.y, d.z));
	float second = d.x + d.y + d.z - smallest - largest;
	float edge = 1.0 - clamp(second / (fwidth(second) * 2.0 + 0.00001), 0.0, 1.0);

	vec3 n = abs(local_normal);
	bool top_face = n.y > 0.5;
	bool side_face = n.x > 0.5;
	vec2 uv = top_face ? local_pos.xz : (side_face ? local_pos.zy : local_pos.xy);
	vec2 face_half = top_face ? half_size.xz : (side_face ? half_size.zy : half_size.xy);
	float ps = pattern_scale;

	vec4 nz = noise4(uv * 0.9 / ps + local_pos.yx * 0.31);
	float grime = nz.r * 0.6 + noise4(uv * 2.7 / ps + 4.0).g * 0.4;
	vec4 fine = noise4(uv * 9.0 + 1.7);
	float h = 0.0;
	vec3 emission = vec3(0.0);
	float rough = roughness_value;
	float metal = metallic_value;
	vec3 painted = apply_camo(base_color, camo_mode, camo_a, camo_b, camo_scale, local_pos);
	vec3 color = painted * (0.8 + grime * 0.36);

	if (pattern == 0) {
		// Hormigón: juntas de encofrado, poros y chorretones.
		float joints = max(groove(uv.x / ps, 0.012), groove(uv.y / ps, 0.012)) * clamp(1.0 - fwidth(uv.x / ps) * 4.0, 0.0, 1.0);
		float pores = smoothstep(0.72, 0.8, fine.r);
		color *= 1.0 - joints * 0.3 - pores * 0.18;
		h = -joints * 0.01 - pores * 0.004 + fine.g * 0.003;
		if (!top_face) {
			float streak = smoothstep(0.55, 0.9, noise4(vec2(uv.x * 2.2, uv.y * 0.15 + 3.0)).b) * smoothstep(-face_half.y, face_half.y, uv.y);
			color *= 1.0 - streak * 0.3;
		}
		rough = 0.93;
	} else if (pattern == 1) {
		if (top_face) {
			color = painted * (0.45 + fine.r * 0.2);
		} else {
			vec2 cell = vec2(uv.x / (ps * 0.9), uv.y / ps);
			vec2 f = fract(cell);
			vec2 id = floor(cell);
			float aa = fwidth(cell.x) + fwidth(cell.y) + 0.004;
			float lod = clamp(1.3 - aa * 3.0, 0.0, 1.0);
			vec2 wd = abs(f - vec2(0.5, 0.54)) - vec2(0.21, 0.24);
			float wdist = max(wd.x, wd.y);
			float window = (1.0 - smoothstep(-aa, aa, wdist)) * lod;
			float frame = (1.0 - smoothstep(-aa, aa, wdist - 0.04)) * lod - window;
			float mullion = window * max(1.0 - smoothstep(0.012, 0.012 + aa, abs(f.x - 0.5)), 1.0 - smoothstep(0.012, 0.012 + aa, abs(f.y - 0.62)));
			float glass = window - mullion;
			float sill = (1.0 - smoothstep(-aa, aa, max(abs(f.x - 0.5) - 0.27, abs(f.y - 0.245) - 0.025))) * lod;
			float lit = step(0.72, hash(id + floor(half_size.xz * 3.0) + node_seed * 31.0));
			float band = groove(cell.y, 0.025) * lod;
			color *= 1.0 - band * 0.25;
			// Chorretones bajo los alféizares.
			float drip = smoothstep(0.3, 0.0, abs(f.x - 0.5) - 0.2) * smoothstep(0.24, 0.05, f.y) * noise4(vec2(uv.x * 6.0, uv.y * 0.4)).g;
			color *= 1.0 - drip * 0.3 * lod;
			color = mix(color, painted * 1.25 + 0.04, clamp(frame + mullion + sill, 0.0, 1.0));
			vec3 glass_color = mix(vec3(0.02, 0.03, 0.045), vec3(0.1, 0.14, 0.2), f.y);
			color = mix(color, glass_color, glass);
			emission = glass * lit * vec3(1.0, 0.72, 0.38) * (0.5 + 0.5 * hash(id + 7.0));
			rough = mix(0.9, 0.1, glass);
			h = -window * 0.06 + (frame + sill) * 0.025 - band * 0.01 + fine.g * 0.002 * (1.0 - window);
		}
	} else if (pattern == 2) {
		if (top_face) {
			color *= 0.8 + fine.r * 0.25;
		} else {
			vec2 f;
			vec2 b = bricks(uv, ps * 0.14, ps * 0.34, f);
			vec3 piece = painted * (0.72 + b.y * 0.5) * mix(vec3(1.0), vec3(1.12, 0.9, 0.82), fract(b.y * 7.3) * 0.5);
			piece *= 0.85 + fine.r * 0.3;
			vec3 mortar = mix(painted, vec3(0.5, 0.48, 0.44), 0.5) * (0.62 + fine.g * 0.25);
			color = mix(piece * (0.85 + grime * 0.3), mortar, b.x);
			h = (1.0 - b.x) * (0.012 + fine.r * 0.006 + b.y * 0.004);
			rough = 0.94;
		}
	} else if (pattern == 3) {
		float axis = top_face ? local_pos.z : (side_face ? local_pos.z : local_pos.y);
		float links = fract(axis / ps);
		float plate = smoothstep(0.0, 0.15, links) * smoothstep(0.5, 0.35, links);
		color *= 1.0 - plate * 0.4;
		h = -plate * 0.01;
	} else if (pattern == 4) {
		// Planchas de acero con juntas y remaches.
		float lod = clamp(1.0 - fwidth(uv.x / ps) * 3.0, 0.0, 1.0);
		float seams = max(groove(uv.x / ps, 0.015), groove(uv.y / ps, 0.015)) * lod;
		vec2 c = abs(fract(uv / ps) - 0.5);
		float near_seam = min(0.5 - c.x, 0.5 - c.y);
		float along = (0.5 - c.x) < (0.5 - c.y) ? uv.y : uv.x;
		float rivet = (1.0 - smoothstep(0.012, 0.02, length(vec2((fract(along / ps * 5.0) - 0.5) / 5.0, near_seam - 0.06)))) * lod;
		color *= 1.0 - seams * 0.35;
		color = mix(color, color * 1.35 + 0.02, rivet * 0.6);
		float rust = smoothstep(0.6, 0.85, noise4(vec2(uv.x * 3.0, uv.y * 0.6) / ps + 9.0).g) * (top_face ? 0.3 : 1.0);
		color = mix(color, color * vec3(0.7, 0.45, 0.32), rust * 0.5);
		h = -seams * 0.006 + rivet * 0.008 + (fine.g - 0.5) * 0.001;
		rough = mix(rough, 0.9, rust);
	} else if (pattern == 5) {
		// Tablones.
		float board_h = ps * 0.25;
		float row = floor(uv.y / board_h);
		float lod = clamp(1.0 - fwidth(uv.y / board_h) * 2.5, 0.0, 1.0);
		float gap = groove(uv.y / board_h, 0.04) * lod;
		float grain = noise4(vec2(uv.x * 2.0 / ps + row * 3.7, uv.y * 30.0 / ps)).r;
		float knot = smoothstep(0.82, 0.9, noise4(vec2(uv.x * 1.3 / ps + row * 9.1, row * 2.3)).g);
		color = painted * (0.72 + hash(vec2(row, 3.0)) * 0.3) * (0.75 + grain * 0.45);
		color *= 1.0 - gap * 0.6 - knot * 0.35;
		h = -gap * 0.012 + grain * 0.003;
		rough = 0.92;
	} else if (pattern == 6) {
		float wave = sin(uv.x / ps * 6.2831 * 4.0);
		float lod = clamp(1.0 - fwidth(uv.x / ps * 4.0) * 2.0, 0.0, 1.0);
		color *= 1.0 + wave * 0.12 * lod;
		float rust = smoothstep(0.55, 0.85, noise4(vec2(uv.x * 2.0, uv.y * 0.3) + 5.0).g);
		color = mix(color, color * vec3(0.75, 0.5, 0.35), rust * 0.45);
		h = wave * 0.012 * ps * lod;
		metal = max(metal, 0.3);
		rough = 0.6 + rust * 0.3;
	} else if (pattern == 7) {
		// Ventana: marco, cruceta y cristal.
		vec2 p = uv / face_half;
		float border = max(abs(p.x), abs(p.y));
		float frame = smoothstep(0.76, 0.8, border);
		float cross_bar = max(1.0 - smoothstep(0.04, 0.07, abs(p.x)), 1.0 - smoothstep(0.04, 0.07, abs(p.y - 0.15)));
		float wood = max(frame, cross_bar);
		float lit = step(0.66, node_seed);
		vec3 glass_color = mix(vec3(0.02, 0.03, 0.045), base_color * 0.6, p.y * 0.5 + 0.5);
		// Visillos tras el cristal de las ventanas iluminadas.
		glass_color = mix(glass_color, vec3(0.5, 0.36, 0.2) * (0.7 + 0.3 * sin(uv.x * 40.0)), lit * 0.8);
		color = mix(glass_color, vec3(0.78, 0.76, 0.7) * (0.8 + fine.r * 0.25), wood);
		emission = (1.0 - wood) * lit * vec3(1.0, 0.7, 0.35) * 0.3;
		rough = mix(0.1, 0.8, wood);
		h = wood * 0.03;
	} else if (pattern == 8) {
		// Puerta de tablas con marco y herrajes.
		vec2 p = uv / face_half;
		float frame = smoothstep(0.86, 0.9, max(abs(p.x), p.y));
		float boards = groove(uv.x / 0.24, 0.05);
		float grain = noise4(vec2(uv.x * 30.0, uv.y * 2.5)).r;
		float hinge = step(0.55, p.x) * step(p.x, 0.86) * max(1.0 - smoothstep(0.03, 0.05, abs(p.y - 0.6)), 1.0 - smoothstep(0.03, 0.05, abs(p.y + 0.6)));
		float handle = 1.0 - smoothstep(0.05, 0.07, length((p - vec2(-0.62, -0.05)) * face_half));
		color = painted * (0.7 + grain * 0.5) * (1.0 - boards * 0.5);
		color = mix(color, painted * 0.55, frame);
		color = mix(color, vec3(0.1, 0.1, 0.11), max(hinge, handle));
		metal = max(hinge, handle) * 0.7;
		h = -boards * 0.01 + frame * 0.02 + max(hinge, handle) * 0.015 + grain * 0.002;
		rough = 0.85;
	} else if (pattern == 9) {
		// Enlucido: yeso con grietas y desconchones que dejan ver el ladrillo o el adobe.
		if (top_face) {
			color *= 0.85 + fine.r * 0.2;
		} else {
			float patch_n = noise4(uv * 0.35 + node_seed * 20.0).r * 0.6 + noise4(uv * 1.1 + 3.0).g * 0.4;
			float low = 1.0 - smoothstep(-face_half.y, -face_half.y + 1.6, uv.y);
			float fallen = smoothstep(0.66, 0.71, patch_n + low * 0.16);
			vec2 f;
			vec2 b = bricks(uv, ps * 0.1, ps * 0.25, f);
			vec3 under_base = mix(vec3(0.42, 0.22, 0.15), painted * 0.5, 0.45);
			vec3 under = mix(under_base, vec3(0.42, 0.39, 0.34), b.x) * (0.75 + b.y * 0.4);
			float crack = (1.0 - smoothstep(0.0, 0.006, abs(noise4(uv * 0.6 + 11.0).b - 0.5))) * step(0.55, noise4(uv * 0.2 + 2.0).a);
			vec3 plaster = painted * (0.86 + grime * 0.24) * (1.0 - crack * 0.3);
			float streak = smoothstep(0.55, 0.9, noise4(vec2(uv.x * 2.0, uv.y * 0.12 + 1.0)).b) * smoothstep(-face_half.y, face_half.y, uv.y);
			plaster *= 1.0 - streak * 0.22;
			color = mix(plaster, under, fallen);
			h = (1.0 - fallen) * 0.02 + fallen * (1.0 - b.x) * 0.008 - crack * 0.006 + fine.g * 0.002;
			rough = 0.95;
		}
	} else if (pattern == 10) {
		// Sacos terreros apilados.
		vec2 f;
		vec2 b = bricks(uv, ps * 0.5, ps * 1.1, f);
		float bulge = sqrt(max(sin(f.x * 3.14159) * sin(f.y * 3.14159), 0.0));
		float weave = noise4(uv * 38.0).r;
		color = painted * (0.72 + b.y * 0.3) * (0.5 + bulge * 0.6) * (0.9 + weave * 0.2);
		h = bulge * 0.07 * ps;
		rough = 1.0;
	} else if (pattern == 11) {
		// Muro de troncos.
		if (top_face) {
			color *= 0.7;
		} else {
			float log_h = ps * 0.22;
			float row = floor(uv.y / log_h);
			float fy = fract(uv.y / log_h);
			float round_log = sin(fy * 3.14159);
			float grain = noise4(vec2(uv.x * 1.6 + row * 5.3, uv.y * 26.0)).r;
			float chk = smoothstep(0.75, 0.85, noise4(vec2(uv.x * 0.8 + row * 2.1, row * 1.7)).g);
			color = painted * (0.45 + round_log * 0.65) * (0.75 + grain * 0.4) * (0.85 + hash(vec2(row, 1.0)) * 0.3);
			color *= 1.0 - chk * 0.3;
			h = round_log * 0.07 * ps + grain * 0.004;
			rough = 0.92;
		}
	}

	// Suciedad al pie de los muros y polvo encima.
	if (!top_face && pattern != 7) {
		float foot = (1.0 - smoothstep(0.0, 1.1, world_y)) * (0.5 + nz.b * 0.5);
		color = mix(color, color * vec3(0.55, 0.48, 0.4), foot * 0.6);
	}
	color = mix(color, color * 1.4 + vec3(0.03), edge * edge_light);
	ALBEDO = color;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emission;
	NORMAL = bump_normal(NORMAL, VERTEX, h * detail_fade(VERTEX, 40.0, 110.0));
}
