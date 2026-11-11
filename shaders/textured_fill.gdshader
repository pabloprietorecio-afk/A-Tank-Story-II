shader_type spatial;
render_mode cull_back;

#include "res://shaders/surface_common.gdshaderinc"

// Superficie iluminada con textura procedural en relieve para mallas no cúbicas.
// pattern: 0 liso, 1 corteza, 2 follaje, 3 roca, 4 metal con aros, 5 tejas, 6 madera/paja,
//          7 ladera (hierba en lo llano, roca en lo escarpado), 8 lona.
uniform vec3 base_color : source_color = vec3(0.5);
uniform vec3 detail_color : source_color = vec3(0.2);
uniform int pattern = 0;
uniform float scale = 1.0;
// Camuflaje: 0 liso, 1 manchas, 2 franjas, 3 encalado de invierno.
uniform int camo_mode = 0;
uniform vec3 camo_a : source_color = vec3(0.3, 0.35, 0.2);
uniform vec3 camo_b : source_color = vec3(0.35, 0.25, 0.15);
uniform float camo_scale = 1.0;
uniform float roughness_value = 0.9;
uniform float metallic_value = 0.0;
// Deforma la malla con ruido (copas de árbol y rocas irregulares). 0 = sin deformar.
uniform float lumpiness = 0.0;
uniform float sway = 0.0;

varying vec3 lp;
varying vec3 ln;
varying float node_seed;

void vertex() {
	node_seed = fract(sin(dot(NODE_POSITION_WORLD.xz, vec2(12.9898, 78.233))) * 43758.5453);
	if (lumpiness > 0.0) {
		vec3 dir = normalize(VERTEX + vec3(0.0001));
		vec2 key = dir.xz * 2.3 + dir.y * 1.7 + node_seed * 37.0;
		float bulge = textureLod(noise_tex, (key + 0.5) / 64.0 * 3.0, 0.0).r;
		VERTEX *= 1.0 + (bulge - 0.5) * lumpiness;
	}
	if (sway > 0.0) {
		float phase = TIME * 1.1 + NODE_POSITION_WORLD.x * 0.3 + NODE_POSITION_WORLD.z * 0.2;
		VERTEX.x += sin(phase) * sway * (VERTEX.y + 0.5);
		VERTEX.z += cos(phase * 0.8) * sway * 0.6 * (VERTEX.y + 0.5);
	}
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	vec3 p = lp / scale;
	vec3 n = normalize(ln);
	float around = atan(p.z, p.x);
	float d = 0.0;
	float h = 0.0;
	float rough = roughness_value;
	float metal = metallic_value;
	// A lo lejos el grano fino se funde con su media para que no centellee.
	float lod = detail_fade(VERTEX, 60.0, 220.0);
	vec4 nz = mix(vec4(0.5), noise4(p.xz * 2.0 + p.y * 1.3), lod);
	vec4 fine = mix(vec4(0.5), noise4(p.xz * 9.0 + p.y * 7.0 + 2.0), detail_fade(VERTEX, 30.0, 100.0));
	float shade = 0.82 + nz.r * 0.2 + nz.g * 0.14;
	vec3 painted = apply_camo(base_color, camo_mode, camo_a, camo_b, camo_scale, lp);
	vec3 color = painted * shade;
	vec3 view_normal = NORMAL;

	if (pattern == 1) {
		// Corteza: surcos verticales irregulares.
		float ridges = noise4(vec2(around * 4.0, p.y * 1.2)).r;
		float furrow = smoothstep(0.35, 0.6, abs(ridges - 0.5) * 2.0 + fine.r * 0.3);
		float marks = smoothstep(0.7, 0.8, noise4(vec2(around * 1.5, p.y * 9.0)).g);
		d = max(1.0 - furrow, marks * 0.9) * 0.85;
		h = furrow * 0.02;
		color = mix(painted * shade, detail_color, clamp(d, 0.0, 1.0));
	} else if (pattern == 2) {
		// Follaje: racimos de hojas claros y huecos oscuros.
		vec2 leaf_uv = p.xz * 2.6 + vec2(p.y * 2.3, p.y * 3.1);
		vec4 clump = noise4(leaf_uv);
		vec2 turned = vec2(leaf_uv.x * 0.8 - leaf_uv.y * 0.6, leaf_uv.x * 0.6 + leaf_uv.y * 0.8);
		float leaves = noise4(turned * 2.7 + 5.0).g * 0.55 + noise4(leaf_uv * 4.3 + 9.0).b * 0.45;
		float depth = smoothstep(0.25, 0.7, clump.r * 0.6 + leaves * 0.4);
		float height_light = 0.6 + clamp(lp.y + 0.5, 0.0, 1.0) * 0.55;
		color = mix(painted * 0.55, mix(painted, detail_color, clump.b), depth) * height_light;
		color = mix(color, color * vec3(1.25, 1.2, 0.8), smoothstep(0.55, 0.85, leaves) * 0.4);
		// Tono distinto en cada árbol.
		color *= mix(vec3(0.9, 0.95, 0.9), vec3(1.12, 1.05, 0.9), node_seed);
		h = clump.r * 0.05;
		rough = 0.85;
	} else if (pattern == 3) {
		// Roca: facetas, estratos, grietas y liquen.
		vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(facet, view_normal) < 0.0) {
			facet = -facet;
		}
		view_normal = normalize(mix(view_normal, facet, 0.75));
		float strata = groove(p.y * 1.4 + nz.r * 0.9, 0.05);
		float cracks = (1.0 - smoothstep(0.0, 0.04, abs(noise4(vec2(around * 1.3, p.y * 0.8) + 3.0).b - 0.5))) * step(0.45, nz.a);
		float lichen = smoothstep(0.62, 0.72, noise4(p.xz * 0.9 + p.y + 9.0).g) * max(n.y, 0.0);
		color = painted * (0.72 + nz.r * 0.3 + fine.r * 0.18);
		color = mix(color, detail_color, clamp(strata * 0.45 + cracks * 0.7, 0.0, 1.0));
		color = mix(color, vec3(0.3, 0.33, 0.16), lichen * 0.5);
		h = fine.g * 0.02 - cracks * 0.03 - strata * 0.012;
		rough = 0.95;
	} else if (pattern == 4) {
		// Chapa cilíndrica: aros, remaches y óxido.
		float hoop = groove(p.y * 2.5, 0.07);
		float seam = step(0.93, sin(around * 6.0));
		float rivets = hoop * step(0.5, fract(around * 7.0));
		float rust = smoothstep(0.58, 0.85, noise4(vec2(around * 2.0, p.y * 0.7) + 4.0).g);
		color = painted * (0.8 + nz.r * 0.3);
		color = mix(color, detail_color, clamp(hoop * 0.55 + seam * 0.4, 0.0, 1.0));
		color = mix(color, color * vec3(0.75, 0.45, 0.3), rust * 0.5);
		h = hoop * 0.012 + rivets * 0.004 - seam * 0.004;
		metal = max(metal, 0.45) * (1.0 - rust * 0.6);
		rough = mix(0.5, 0.9, rust);
	} else if (pattern == 5) {
		if (abs(n.y) < 0.1) {
			// Hastial: tablas verticales oscuras.
			float boards = groove((abs(n.x) > abs(n.z) ? p.z : p.x) * 6.0, 0.06);
			color = mix(detail_color * 2.2, vec3(0.4, 0.32, 0.23), 0.6) * (0.8 + fine.r * 0.3) * (1.0 - boards * 0.5);
			h = -boards * 0.01;
		} else {
			// Tejas solapadas en hileras.
			float rows = p.y * 5.0;
			float row = floor(rows);
			float fy = fract(rows);
			float cols = (abs(n.x) > abs(n.z) ? p.z : p.x) * 9.0 + mod(row, 2.0) * 0.5;
			float fx = fract(cols);
			float tile_lod = clamp(1.2 - fwidth(cols) * 2.0, 0.0, 1.0);
			float id = hash(vec2(floor(cols), row));
			float curve = sin(fx * 3.14159);
			float lap = 1.0 - smoothstep(0.0, 0.2, fy);
			color = painted * (0.72 + id * 0.45) * (0.7 + curve * 0.35 * tile_lod) * (0.78 + fy * 0.3);
			color = mix(color, detail_color, lap * 0.7 * tile_lod);
			float moss = smoothstep(0.6, 0.75, noise4(p.zy * 1.5 + node_seed * 9.0).r);
			color = mix(color, vec3(0.2, 0.24, 0.1), moss * 0.35);
			h = (fy * 0.035 + curve * 0.02) * tile_lod;
		}
	} else if (pattern == 6) {
		float fibre = noise4(vec2(p.x * 1.5 + p.z * 1.1, p.y * 24.0)).r;
		float bands = groove(p.x * 1.5 + noise4(p.yz * 4.0).r * 0.4, 0.05);
		color = painted * (0.7 + fibre * 0.5);
		color = mix(color, detail_color, bands * 0.6);
		h = fibre * 0.012 - bands * 0.008;
	} else if (pattern == 7) {
		// Ladera: vegetación en lo llano, roca estratificada en lo escarpado.
		float broad = noise4(lp.xz * 0.045 + 3.0).r * 0.6 + noise4(lp.xz * 0.13 + 8.0).g * 0.4;
		float steep = 1.0 - smoothstep(0.76, 0.93, n.y + (nz.r - 0.5) * 0.14 + (broad - 0.5) * 0.16);
		float strata = groove(p.y * 2.2 + nz.g * 1.2, 0.08) * lod;
		vec3 rock = detail_color * 1.9 * (0.75 + nz.b * 0.4);
		rock = mix(rock, rock * 0.72, strata);
		vec3 veg = painted * (0.5 + broad * 0.7 + nz.r * 0.2 + fine.r * 0.1);
		veg = mix(veg, veg * vec3(1.15, 1.05, 0.7), smoothstep(0.55, 0.8, nz.a));
		color = mix(veg, rock, steep);
		h = steep * (nz.b * 0.6 - strata * 0.3) + fine.g * 0.08;
		rough = 0.96;
	} else if (pattern == 8) {
		float fold = sin(p.z * 9.0 + nz.r * 4.0) * 0.5 + 0.5;
		float weave = noise4(p.zy * 40.0).r;
		color = painted * (0.75 + fold * 0.22 + weave * 0.12);
		h = fold * 0.02;
		rough = 1.0;
	}

	ALBEDO = color;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL = bump_normal(view_normal, VERTEX, h * detail_fade(VERTEX, 40.0, 110.0));
}
