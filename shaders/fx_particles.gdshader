shader_type particles;
render_mode disable_velocity, disable_force;

// Física de todas las partículas de efectos (fuego, humo, polvo, chispas, cascotes).
// Ninguna sale sola: Fx las lanza una a una con GPUParticles3D.emit_particle(), que da a cada
// partícula su posición y tamaño (la transformación), su velocidad, su color y
//   CUSTOM = (clase + semilla 0..1, edad 0..1 —negativa: todavía espera su turno—, dato libre,
//   vida en segundos).
// El mismo shader mueve a todas las familias; solo cambian estos parámetros.

// Cada familia reparte sus partículas en clases (la parte entera de la semilla) con su propia
// física: gravedad vertical (positiva = flota), freno del aire, arrastre del viento, remolino.
uniform float gravity_y[8];
uniform float drag[8];
uniform float wind_pull[8];
uniform float swirl[8];
// Suelo (el campo es llano, y = 0): 0 no existe, 1 la partícula se apaga al tocarlo, 2 rebota
// y acaba posándose, 3 se queda donde cae, 4 resbala sin hundirse.
uniform int ground[8];
uniform vec3 wind = vec3(0.0);
uniform float bounce = 0.35;
// Altura del centro al posarse, como fracción del tamaño.
uniform float ground_offset = 0.0;
// Chispas: el largo del trazo es velocidad × stretch, entre los dos límites (m).
uniform float stretch = 0.0;
uniform vec2 stretch_range = vec2(0.1, 2.0);
// Cascotes: giro en rad/s mientras vuelan.
uniform float tumble = 0.0;

void start() {
	if (RESTART_CUSTOM) {
		// Solo existen las partículas lanzadas a mano.
		ACTIVE = false;
	}
}

void process() {
	float life = max(CUSTOM.w, 0.02);
	float age = CUSTOM.y + DELTA / life;
	CUSTOM.y = age;
	if (age >= 1.0) {
		ACTIVE = false;
	}
	if (age > 0.0) {
		int cls = clamp(int(CUSTOM.x), 0, 7);
		float seed = fract(CUSTOM.x);
		int floor_mode = ground[cls];
		vec3 v = VELOCITY;
		vec3 p = TRANSFORM[3].xyz;
		float floor_y = length(TRANSFORM[0].xyz) * ground_offset;
		bool resting = floor_mode >= 2 && floor_mode <= 3 && p.y <= floor_y + 0.002 && dot(v, v) < 0.04;
		if (!resting) {
			v.y += gravity_y[cls] * DELTA;
			v *= exp(-drag[cls] * DELTA);
			if (wind_pull[cls] > 0.0) {
				v.xz += (wind.xz - v.xz) * (1.0 - exp(-wind_pull[cls] * DELTA));
			}
			if (swirl[cls] > 0.0) {
				float s = seed * 61.7;
				float t = age * life;
				v += vec3(sin(s + t * 2.3), sin(s * 1.7 + t * 1.9) * 0.4, cos(s * 2.3 + t * 2.1)) * swirl[cls] * DELTA;
			}
			p += v * DELTA;
			if (floor_mode > 0 && p.y < floor_y) {
				if (floor_mode == 1) {
					ACTIVE = false;
				} else if (floor_mode == 2) {
					p.y = floor_y;
					v = vec3(v.x * 0.55, -v.y * bounce, v.z * 0.55);
					if (v.y < 1.2) {
						v = vec3(0.0);
					}
				} else if (floor_mode == 3) {
					p.y = floor_y;
					v = vec3(0.0);
				} else {
					p.y = floor_y;
					v.y = max(v.y, 0.0);
				}
			}
			if (tumble > 0.0) {
				float s = seed * 97.3;
				vec3 axis = normalize(vec3(sin(s), cos(s * 1.3), sin(s * 2.1) + 0.2));
				float angle = tumble * (0.5 + fract(s)) * DELTA;
				float c = cos(angle);
				float si = sin(angle);
				float oc = 1.0 - c;
				mat3 turn = mat3(
						vec3(oc * axis.x * axis.x + c, oc * axis.x * axis.y + axis.z * si, oc * axis.z * axis.x - axis.y * si),
						vec3(oc * axis.x * axis.y - axis.z * si, oc * axis.y * axis.y + c, oc * axis.y * axis.z + axis.x * si),
						vec3(oc * axis.z * axis.x + axis.y * si, oc * axis.y * axis.z - axis.x * si, oc * axis.z * axis.z + c));
				mat3 turned = turn * mat3(TRANSFORM);
				TRANSFORM[0].xyz = turned[0];
				TRANSFORM[1].xyz = turned[1];
				TRANSFORM[2].xyz = turned[2];
			}
		}
		if (stretch > 0.0) {
			// El motor orienta el eje Y según la velocidad; aquí solo importa su longitud.
			// Las trazadoras (clase 2) dejan un trazo más largo que las chispas.
			float longest = stretch_range.y * (cls == 2 ? 3.5 : 1.0);
			TRANSFORM[1].xyz = vec3(0.0, clamp(length(v) * stretch, stretch_range.x, longest), 0.0);
		}
		TRANSFORM[3].xyz = p;
		VELOCITY = v;
	}
}
