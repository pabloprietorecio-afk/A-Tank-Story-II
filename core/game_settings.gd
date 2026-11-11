class_name GameSettings
extends RefCounted
## Ajustes del jugador, guardados en user://settings.cfg.

const PATH: String = "user://settings.cfg"

## Fija la torreta sobre el enemigo una vez que la mira lo ha encontrado.
static var aim_assist: bool = false
## La torreta gira 360º siempre. Si está activo, vuelve sola al frente al dejar de moverla.
static var auto_recenter: bool = false

## Movimiento fácil: el cañón se apunta libre en el mundo y el casco se alinea con él al avanzar.
static var easy_drive: bool = true

## Vista: 0 = cabina, 1 = detrás cerca, 2 = detrás lejos.
static var camera_view: int = 0

## Sombras en tiempo real (desactivar en móviles lentos).
static var shadows: bool = true

## Detalle de los efectos (explosiones, humo, polvo, fuego): 0 bajos, 1 medios, 2 altos.
const EFFECTS_NAMES: Array[String] = ["BAJOS", "MEDIOS", "ALTOS"]
static var effects: int = 2

## Volúmenes (0..1). La música va bajita por defecto.
static var music_volume: float = 0.3
static var sfx_volume: float = 1.0
static var voice_volume: float = 0.9
## Volumen general: sube o baja todo a la vez.
static var master_volume: float = 1.0

## Dificultad: 0 fácil, 1 normal, 2 difícil, 3 inferno.
const DIFFICULTY_NAMES: Array[String] = ["FÁCIL", "NORMAL", "DIFÍCIL", "INFERNO"]
const DIFFICULTY_HINTS: Array[String] = [
	"Pocos enemigos; apuntan mal y tardan en reaccionar",
	"Los enemigos de siempre",
	"Un enemigo más por tanda; apuntan y recargan mejor",
	"Dos enemigos más por tanda; puntería y reflejos de veterano",
]
## Pericia de las tripulaciones enemigas por dificultad: error de puntería, tiempo de recarga,
## alcance de visión y segundos entre correcciones de puntería (reflejos).
const SKILL_AIM_ERROR: Array[float] = [1.7, 1.0, 0.7, 0.45]
const SKILL_RELOAD: Array[float] = [1.3, 1.0, 0.9, 0.8]
const SKILL_SIGHT: Array[float] = [0.85, 1.0, 1.1, 1.2]
const SKILL_AIM_INTERVAL: Array[float] = [1.0, 0.6, 0.45, 0.3]
static var difficulty: int = 1

## Dibuja un borde amarillo alrededor de los tanques enemigos para verlos mejor.
static var highlight_enemies: bool = false

## Idioma del juego: "es" (por defecto) o "en".
static var language: String = "es"

static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		aim_assist = cfg.get_value("controls", "aim_assist", aim_assist)
		camera_view = cfg.get_value("controls", "camera_view", camera_view)
		shadows = cfg.get_value("graphics", "shadows", shadows)
		effects = clampi(cfg.get_value("graphics", "effects", effects), 0, 2)
		music_volume = cfg.get_value("audio", "music", music_volume)
		sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
		voice_volume = cfg.get_value("audio", "voice", voice_volume)
		master_volume = cfg.get_value("audio", "master", master_volume)
		difficulty = clampi(cfg.get_value("game", "difficulty", difficulty), 0, 3)
		highlight_enemies = cfg.get_value("game", "highlight_enemies", highlight_enemies)
		easy_drive = cfg.get_value("controls", "easy_drive", easy_drive)
		auto_recenter = cfg.get_value("controls", "auto_recenter", auto_recenter)
		language = str(cfg.get_value("game", "language", language))
	Loc.apply(language)
	Fx.quality = effects


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "aim_assist", aim_assist)
	cfg.set_value("controls", "camera_view", camera_view)
	cfg.set_value("graphics", "shadows", shadows)
	cfg.set_value("graphics", "effects", effects)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "voice", voice_volume)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "highlight_enemies", highlight_enemies)
	cfg.set_value("controls", "easy_drive", easy_drive)
	cfg.set_value("controls", "auto_recenter", auto_recenter)
	cfg.set_value("game", "language", language)
	cfg.save(PATH)


## Cambia el idioma y lo guarda.
static func set_language(code: String) -> void:
	ensure_loaded()
	language = code if code in Loc.LANGUAGES else "es"
	Loc.apply(language)
	save()


## Enemigos de más (o de menos) en cada tanda de refuerzos: -1, 0, +1 o +2.
static func batch_extra() -> int:
	ensure_loaded()
	return difficulty - 1


## Tamaño de una tanda de `base` enemigos con la dificultad actual (nunca menos de uno).
static func batch(base: int) -> int:
	return maxi(base + batch_extra(), 1)


## Factor para el total de enemigos de una misión y, en fácil, para espaciar los refuerzos.
static func total_factor() -> float:
	ensure_loaded()
	return [0.6, 1.0, 1.25, 1.5][difficulty]
