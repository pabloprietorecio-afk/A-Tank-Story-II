shader_type canvas_item;

// Velo de pantalla de la partida: oscurece un poco las esquinas, como el objetivo de una
// cámara, y cuando el tanque encaja un impacto tiñe de rojo los bordes (más cuanto más
// fuerte), dejando el centro limpio para seguir viendo.

uniform float vignette = 0.3;
uniform float hurt = 0.0;

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = dot(q, q);
	float corners = smoothstep(0.45, 2.0, r) * vignette;
	float pain = hurt * 0.85 * smoothstep(0.35, 1.9, r);
	COLOR = vec4(mix(vec3(0.0), vec3(0.55, 0.02, 0.0), clamp(pain / max(pain + corners, 0.001), 0.0, 1.0)), clamp(corners + pain, 0.0, 0.92));
}
