class_name VehicleGallery
extends VBoxContainer
## Ficha histórica de un vehículo: modelo 3D girando, texto y datos. En modo galería permite
## pasar por todos los tanques, cazacarros y blindados de ruedas del juego.
## Funciona aunque el juego esté en pausa.

signal closed

var _viewer: TankViewer
var _text: Label
var _browse_row: HBoxContainer
var _counter: Label
var _index: int = 0

static var _entries: Array[Dictionary] = []


## Todos los vehículos, sin repetir, con el frente y bando en que aparecen (para su pintura).
static func entries() -> Array[Dictionary]:
	if _entries.is_empty():
		var seen: Dictionary = {}
		for faction in [Fronts.Faction.ALLIES, Fronts.Faction.AXIS]:
			for front in [Fronts.Id.NORMANDY, Fronts.Id.AFRICA, Fronts.Id.KURSK]:
				for id: String in Fronts.ROSTERS[front][faction]:
					if not seen.has(id):
						seen[id] = true
						_entries.append({"id": id, "front": front, "faction": faction})
	return _entries


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_theme_constant_override("separation", 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	_viewer = TankViewer.new()
	row.add_child(_viewer)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560.0, 0.0)
	_text.add_theme_font_size_override("font_size", 22)
	row.add_child(_text)
	_browse_row = HBoxContainer.new()
	_browse_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_browse_row.add_theme_constant_override("separation", 24)
	add_child(_browse_row)
	var previous := _make_button(Loc.t("◀ ANTERIOR"))
	previous.pressed.connect(func() -> void: show_index(_index - 1))
	_browse_row.add_child(previous)
	_counter = Label.new()
	_counter.add_theme_font_size_override("font_size", 24)
	_counter.custom_minimum_size = Vector2(110.0, 0.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_browse_row.add_child(_counter)
	var following := _make_button(Loc.t("SIGUIENTE ▶"))
	following.pressed.connect(func() -> void: show_index(_index + 1))
	_browse_row.add_child(following)
	var close := _make_button(Loc.t("CERRAR"))
	close.pressed.connect(func() -> void: closed.emit())
	add_child(close)


## Versión algo más baja (menú principal): cabe en la pantalla sin desplazarla.
func compact() -> void:
	add_theme_constant_override("separation", 8)
	for node in find_children("*", "Button", true, false):
		(node as Button).custom_minimum_size.y = 56.0


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 26)
	button.custom_minimum_size = Vector2(260.0, 64.0)
	return button


## Muestra un vehículo concreto (el objetivo fijado), sin botones de pasar.
func show_stats(stats: TankStats, paint: Dictionary, browsing: bool = false) -> void:
	_text.text = Loc.t("%s\n\n%s\n\nBLINDAJE %d   ATAQUE %d   VELOCIDAD %d km/h") % [stats.display_name, Loc.t(stats.history) if Loc.t(stats.history) != "" else Loc.t(stats.description), roundi(stats.max_armor), roundi(stats.damage), roundi(stats.max_speed * 3.6)]
	_viewer.show_tank(stats, paint)
	_browse_row.visible = browsing


## Galería: el vehículo número `index` (da la vuelta al llegar a los extremos).
func show_index(index: int) -> void:
	var list: Array[Dictionary] = entries()
	_index = wrapi(index, 0, list.size())
	var entry: Dictionary = list[_index]
	var stats: TankStats = Fronts.tank(entry["id"])
	show_stats(stats, Fronts.paint(entry["front"], entry["faction"], stats.nation), true)
	_counter.text = "%d / %d" % [_index + 1, list.size()]
