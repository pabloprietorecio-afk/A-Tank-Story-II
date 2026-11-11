shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Zona de un bombardeo aéreo marcada en el suelo: un cerco de trazos que gira, un velo tenue
// dentro y un anillo que se cierra hacia el centro como cuenta atrás.

uniform vec3 color : source_color = vec3(1.0, 0.1, 0.05);
// Cuenta atrás (0 acaba de marcarse, 1 caen las bombas) y parpadeo de aviso (0..1).
uniform float progress = 0.0;
uniform float alert = 1.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float w = fwidth(r);
	float turn = atan(q.y, q.x) / 6.2832;
	float dashes = step(0.45, fract(turn * 28.0 + TIME * 0.35));
	float rim = (1.0 - smoothstep(0.012, 0.022 + w, abs(r - 0.965))) * dashes;
	float closing = 1.0 - smoothstep(0.008, 0.016 + w, abs(r - (1.0 - progress * 0.95) * 0.965));
	float inside = 1.0 - smoothstep(0.955, 0.965, r);
	float veil = inside * (0.07 + 0.11 * alert) * (0.35 + 0.65 * r);
	ALBEDO = color;
	ALPHA = clamp(max(max(rim * 0.9, closing * inside * 0.85), veil), 0.0, 1.0);
}
