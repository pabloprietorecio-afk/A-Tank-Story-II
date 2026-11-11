shader_type canvas_item;

// Máscara de prismáticos: dos círculos solapados, el resto oscuro.
uniform vec2 screen_size = vec2(1280.0, 720.0);

void fragment() {
	vec2 p = UV * screen_size;
	vec2 c = screen_size * 0.5;
	float r = screen_size.y * 0.46;
	float d1 = length(p - (c - vec2(r * 0.55, 0.0)));
	float d2 = length(p - (c + vec2(r * 0.55, 0.0)));
	float d = min(d1, d2) - r;
	float mask = smoothstep(-12.0, 4.0, d);
	COLOR = vec4(0.0, 0.0, 0.0, mask * 0.96);
}
