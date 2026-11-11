shader_type spatial;
render_mode unshaded;

uniform vec3 color : source_color = vec3(1.0, 0.5, 0.1);

void fragment() {
	ALBEDO = color;
}
