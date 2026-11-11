shader_type spatial;
render_mode unshaded, cull_back;

// Caja oscura con aristas luminosas y un patrón opcional en las caras.
// half_size = mitad de las dimensiones de la caja.
// pattern: 0 = liso, 1 = plantas/ventanas, 2 = ladrillo, 3 = orugas, 4 = paneles blindados.
uniform vec3 half_size = vec3(1.0);
uniform vec3 line_color : source_color = vec3(0.2, 1.0, 0.33);
uniform vec3 fill_color : source_color = vec3(0.0);
uniform float line_px = 1.5;
uniform int pattern = 0;
uniform float pattern_scale = 2.0;
uniform float pattern_strength = 0.35;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float grid_line(float coord) {
	float f = abs(fract(coord - 0.5) - 0.5);
	return 1.0 - clamp(f / (fwidth(coord) * 1.2 + 0.00001), 0.0, 1.0);
}

void fragment() {
	vec3 d = half_size - abs(local_pos);
	float smallest = min(d.x, min(d.y, d.z));
	float largest = max(d.x, max(d.y, d.z));
	float second = d.x + d.y + d.z - smallest - largest;
	float edge = 1.0 - clamp(second / (fwidth(second) * line_px + 0.00001), 0.0, 1.0);

	// Coordenada horizontal a lo largo de la cara (x en caras frontales, z en laterales).
	bool side_face = d.x < d.z;
	float along = side_face ? local_pos.z : local_pos.x;
	bool top_face = d.y < min(d.x, d.z);
	float detail = 0.0;
	if (pattern == 1 && !top_face) {
		float floors = grid_line(local_pos.y / pattern_scale);
		float cols = grid_line(along / (pattern_scale * 0.8));
		detail = max(floors, cols * 0.6);
	} else if (pattern == 2 && !top_face) {
		float row = floor(local_pos.y / (pattern_scale * 0.5));
		float joints = grid_line((along + mod(row, 2.0) * pattern_scale * 0.5) / pattern_scale);
		detail = max(grid_line(local_pos.y / (pattern_scale * 0.5)), joints);
	} else if (pattern == 3) {
		float axis = top_face ? local_pos.z : (side_face ? local_pos.z : local_pos.y);
		detail = grid_line(axis / pattern_scale);
	} else if (pattern == 4) {
		detail = max(grid_line(along / pattern_scale), grid_line(local_pos.y / pattern_scale)) * 0.7;
		if (top_face) {
			detail = grid_line(local_pos.z / pattern_scale) * 0.7;
		}
	}
	vec3 color = fill_color + line_color * max(edge, detail * pattern_strength);
	ALBEDO = color;
}
