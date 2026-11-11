class_name VolumeSliders
## Deslizadores de volumen (general, música, efectos, radio) que se guardan al soltarlos.


static func create() -> VBoxContainer:
	GameSettings.ensure_loaded()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_row(box, Loc.t("GENERAL"), GameSettings.master_volume, func(v: float) -> void: GameSettings.master_volume = v)
	_row(box, Loc.t("MÚSICA"), GameSettings.music_volume, func(v: float) -> void: GameSettings.music_volume = v)
	_row(box, Loc.t("EFECTOS"), GameSettings.sfx_volume, func(v: float) -> void: GameSettings.sfx_volume = v)
	_row(box, Loc.t("RADIO"), GameSettings.voice_volume, func(v: float) -> void: GameSettings.voice_volume = v)
	return box


static func _row(box: VBoxContainer, title: String, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(150.0, 0.0)
	label.add_theme_font_size_override("font_size", 24)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(360.0, 48.0)
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		AudioSetup.apply_volumes())
	slider.drag_ended.connect(func(_changed: bool) -> void: GameSettings.save())
	row.add_child(slider)
	box.add_child(row)
