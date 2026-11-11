class_name Loc
extends RefCounted
## Idiomas del juego. El texto del código está en español y es la clave: en español se muestra
## tal cual; en los demás idiomas se busca en su tabla (EnglishTable, FrenchTable, ItalianTable,
## JapaneseTable, PortugueseTable, IndonesianTable, HindiTable, GermanTable, RussianTable) y, si no
## está, también se muestra tal cual.
## Uso: Loc.t("TEXTO") o Loc.t("PUNTOS %d") % valor. Cambiar de idioma: GameSettings.set_language().

const LANGUAGES: Array[String] = ["es", "en", "fr", "it", "ja", "pt", "id", "hi", "de", "ru"]
const LANGUAGE_NAMES: Dictionary = {"es": "ESPAÑOL", "en": "ENGLISH", "fr": "FRANÇAIS", "it": "ITALIANO", "ja": "日本語",
		"pt": "PORTUGUÊS", "id": "INDONESIA", "hi": "हिन्दी", "de": "DEUTSCH", "ru": "РУССКИЙ"}
## Subconjunto de Noto Sans JP (licencia OFL) con los caracteres japoneses del juego: se añade a
## la fuente por defecto como respaldo, así el japonés se ve igual en todos los móviles.
const JAPANESE_FONT: String = "res://assets/fonts/NotoSansJP-Subset.otf"
## Noto Sans Devanagari (licencia OFL), para el hindi.
const DEVANAGARI_FONT: String = "res://assets/fonts/NotoSansDevanagari-Medium.ttf"

static var language: String = "es"
static var _registered: bool = false
static var _tight_fonts: Dictionary = {}
## Píxeles que se recortan arriba y abajo de cada línea con las fuentes de respaldo.
const TIGHT_SPACING: int = 5


## Activa un idioma (registra las tablas la primera vez).
static func apply(code: String) -> void:
	language = code if code in LANGUAGES else "es"
	if not _registered:
		_registered = true
		_register("en", EnglishTable.TABLE, EnglishTable.CONTEXT)
		_register("fr", FrenchTable.TABLE, FrenchTable.CONTEXT)
		_register("it", ItalianTable.TABLE, ItalianTable.CONTEXT)
		_register("ja", JapaneseTable.TABLE, JapaneseTable.CONTEXT)
		_register("pt", PortugueseTable.TABLE, PortugueseTable.CONTEXT)
		_register("id", IndonesianTable.TABLE, IndonesianTable.CONTEXT)
		_register("hi", HindiTable.TABLE, HindiTable.CONTEXT)
		_register("de", GermanTable.TABLE, GermanTable.CONTEXT)
		_register("ru", RussianTable.TABLE, RussianTable.CONTEXT)
	_update_font_fallbacks()
	TranslationServer.set_locale(language)


static func _register(locale: String, table: Dictionary, contexts: Dictionary) -> void:
	var catalog := Translation.new()
	catalog.locale = locale
	for key in table:
		catalog.add_message(StringName(key), StringName(table[key]))
	for context in contexts:
		var entries: Dictionary = contexts[context]
		for key in entries:
			catalog.add_message(StringName(key), StringName(entries[key]), StringName(context))
	TranslationServer.add_translation(catalog)


## La fuente por defecto no trae kanji, kana ni devanagari: se le añade la fuente del idioma activo
## como respaldo. Solo en esos idiomas: en los demás, esas fuentes (más altas) cambiarían la
## altura de línea de símbolos como «◀» y «▶» y las páginas de los menús dejarían de caber.
## (El cirílico, el latín ampliado y el resto ya vienen en la fuente por defecto.)
static func _update_font_fallbacks() -> void:
	var wanted_path: String = ""
	if language == "ja":
		wanted_path = JAPANESE_FONT
	elif language == "hi":
		wanted_path = DEVANAGARI_FONT
	var wanted: Font = null
	if wanted_path != "" and ResourceLoader.exists(wanted_path):
		wanted = _tight_font(wanted_path)
	var fonts: Array[Font] = [ThemeDB.fallback_font]
	var default_font: Font = ThemeDB.get_default_theme().default_font
	if default_font != null and default_font != ThemeDB.fallback_font:
		fonts.append(default_font)
	for font in fonts:
		var chain: Array[Font] = []
		for existing in font.fallbacks:
			if not _tight_fonts.values().has(existing):
				chain.append(existing)
		if wanted != null:
			chain.append(wanted)
		font.fallbacks = chain


## La fuente de respaldo con el interlineado recortado: las de japonés y hindi son más altas que la
## fuente por defecto y, sin esto, las páginas de los menús dejarían de caber en la pantalla.
static func _tight_font(path: String) -> Font:
	if not _tight_fonts.has(path):
		var variation := FontVariation.new()
		variation.base_font = load(path)
		variation.spacing_top = -TIGHT_SPACING
		variation.spacing_bottom = -TIGHT_SPACING
		_tight_fonts[path] = variation
	return _tight_fonts[path]


## Traduce `message` al idioma activo.
static func t(message: String) -> String:
	if language == "es" or message.is_empty():
		return message
	return String(TranslationServer.translate(StringName(message)))


## Igual, para un texto que en español se repite con otro sentido (ver EnglishTable.CONTEXT).
static func tc(message: String, context: String) -> String:
	if language == "es" or message.is_empty():
		return message
	return String(TranslationServer.translate(StringName(message), StringName(context)))


## Carpeta de las voces del idioma activo (las de español están en assets/voice).
static func voice_dir() -> String:
	return "res://assets/voice" if language == "es" else "res://assets/voice_%s" % language
