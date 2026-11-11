shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

uniform vec3 color : source_color = vec3(0.8, 1.0, 0.85);

void fragment() {
	ALBEDO = color * COLOR.rgb;
}
