// Funciones comunes de las texturas procedurales.
// El ruido sale de una textura pequeña compartida (VectorMaterials.noise()): una sola lectura
// por muestra, mucho más barato en móvil que calcularlo con senos.
uniform sampler2D noise_tex : filter_linear, repeat_enable;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Cuatro ruidos independientes (uno por canal) con interpolación suave.
vec4 noise4(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return textureLod(noise_tex, (i + f + 0.5) / 64.0, 0.0);
}

float noise(vec2 p) {
	return noise4(p).r;
}

float fbm(vec2 p) {
	return noise4(p).r * 0.5 + noise4(p * 2.03 + 7.1).g * 0.3 + noise4(p * 4.1 + 3.7).b * 0.2;
}

float line(float coord, float width) {
	float f = abs(fract(coord - 0.5) - 0.5);
	return 1.0 - clamp(f / (fwidth(coord) * width + 0.00001), 0.0, 1.0);
}

// Surco de anchura fija (en unidades de `coord`), suavizado según la distancia.
float groove(float coord, float width) {
	float f = abs(fract(coord - 0.5) - 0.5);
	float aa = fwidth(coord) + 0.0001;
	return 1.0 - smoothstep(width - aa, width + aa, f);
}

// Relieve: inclina la normal según la altura `h` (en metros) de una textura procedural.
// `view_pos` y `n` van en espacio de vista (VERTEX y NORMAL del fragmento).
vec3 bump_normal(vec3 n, vec3 view_pos, float h) {
	vec3 dpx = dFdx(view_pos);
	vec3 dpy = dFdy(view_pos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 result = abs(det) * n - grad;
	float len = length(result);
	return len > 0.000001 ? result / len : n;
}

// El relieve se desvanece a lo lejos para que no centellee.
float detail_fade(vec3 view_pos, float near, float far) {
	return clamp(1.0 - (-view_pos.z - near) / (far - near), 0.0, 1.0);
}

vec3 apply_camo(vec3 base, int mode, vec3 a, vec3 b, float scale, vec3 pos) {
	if (mode == 0) {
		return base;
	}
	vec2 p = (pos.xz + vec2(pos.y * 0.7, -pos.y * 0.5)) / scale;
	if (mode == 1) {
		float n1 = fbm(p * 0.9);
		float n2 = fbm(p * 0.9 + 17.3);
		vec3 c = mix(base, a, smoothstep(0.5, 0.56, n1));
		return mix(c, b, smoothstep(0.58, 0.64, n2));
	} else if (mode == 2) {
		float band = sin((p.x + p.y * 0.6) * 2.2 + fbm(p) * 3.0);
		vec3 c = mix(base, a, smoothstep(0.3, 0.45, band));
		return mix(c, b, smoothstep(0.3, 0.45, -band) * step(0.5, fbm(p * 1.3)));
	}
	// Encalado de invierno: blanco con desconchones del color base.
	float worn = fbm(p * 2.0);
	return mix(vec3(0.82, 0.84, 0.86), base, smoothstep(0.6, 0.7, worn));
}
