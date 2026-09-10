extends Control

const SaveGame = preload("res://scripts/save_game.gd")
const GAME_SCENE = preload("res://scenes/main.tscn")
const INK := Color("513e2c")
const ABOUT := "Вы — почтальон-пилот. Между затерянными аэродромами почтовая авиация связывает людей: письма, вести издалека и небольшие грузы должны добраться до адресата.\n\nНо здесь небо почти никогда не бывает ясным. Уже в ста метрах над землёй начинается сплошная облачность. Дальше — полёт по приборам: курс, высота, скорость, сигналы радиомаяков и ваши пометки на карте. Положение самолёта на ней не отмечено — его предстоит определить самому.\n\nУчитывайте ветер, обходите грозы, берегите топливо и ищите дорогу к огням следующей полосы. За каждым удачным заходом — ещё один доставленный шанс услышать близких.\n\nСейчас это техническая демоверсия: доступны полёты, навигация, погода и прогулки по самолёту и аэропорту. Задания на перевозку почты, грузы и экономика ещё в разработке."

var game: Control
var menu_root: Control
var content: VBoxContainer
var about_open := false
var menu_open := true
var error_text := ""
var save_path := SaveGame.PATH

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_background()
	resized.connect(_layout_menu)
	_rebuild_menu()

func _build_background() -> void:
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu_root)
	var background := TextureRect.new()
	background.texture = load("res://assets/title_screen.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(background)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(0.90,0.85,0.72,0.91),Color(0.90,0.85,0.72,0.66),Color(0.90,0.85,0.72,0.06),Color(0.90,0.85,0.72,0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	var veil := TextureRect.new()
	veil.texture = texture
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(veil)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, action: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 49
	button.disabled = disabled
	button.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.93,0.89,0.79,0.52 if state in ["hover","focus"] else 0.12)
		style.border_color = Color(0.40,0.29,0.18,0.5 if state == "focus" else 0.22)
		style.border_width_bottom = 1
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + state + "_color", Color(0.36,0.30,0.24,0.4) if state == "disabled" else INK)
	button.add_theme_color_override("font_color", INK)
	button.pressed.connect(action)
	content.add_child(button)
	return button

func _rebuild_menu() -> void:
	if content != null:
		content.hide()
		content.queue_free()
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	menu_root.add_child(content)
	content.add_child(_label("Far Flight", 64))
	content.add_child(_label("ПОЧТОВАЯ АВИАЦИЯ", 22))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	content.add_child(spacer)
	if about_open:
		content.add_child(_label("Об игре", 22))
		var scroll := ScrollContainer.new()
		scroll.name = "AboutScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = clampf(size.y - 365.0, 160.0, 480.0)
		content.add_child(scroll)
		var description := _label(ABOUT, 18)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(description)
		_button("Назад", _close_about)
	elif game != null:
		content.add_child(_label("ПАУЗА", 14))
		_button("Продолжить", _resume_game)
		_button("Сохранить и выйти", _save_and_exit)
	else:
		_button("Новая игра", _new_game)
		var slot := SaveGame.read_slot(save_path)
		_button("Продолжить", _continue_game, slot.is_empty())
		_button("Об игре", _open_about)
		_button("Выход", _exit_game)
		if SaveGame.slot_exists(save_path) and slot.is_empty():
			error_text = "Сохранение повреждено или несовместимо с этой версией."
	if not error_text.is_empty():
		var error_label := _label(error_text, 15)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error_label.add_theme_color_override("font_color", Color("893f2f"))
		content.add_child(error_label)
	_layout_menu()
	for child in content.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func _layout_menu() -> void:
	if content == null:
		return
	content.position = Vector2(maxf(28, size.x * 0.065), maxf(24, size.y * (0.07 if about_open else 0.19)))
	content.size.x = minf(660.0 if about_open else 385.0, size.x - content.position.x * 2.0)
	var scroll := content.get_node_or_null("AboutScroll")
	if scroll != null:
		scroll.custom_minimum_size.y = clampf(size.y - 365.0,160.0,480.0)

func _create_game() -> Control:
	var instance: Control = GAME_SCENE.instantiate()
	add_child(instance)
	move_child(instance, 0)
	instance.set_process(false)
	instance.set_process_input(false)
	return instance

func _new_game() -> void:
	game = _create_game()
	error_text = ""
	_resume_game()

func _continue_game() -> void:
	var data := SaveGame.read_slot(save_path)
	if data.is_empty():
		error_text = "Не удалось прочитать сохранение."
		_rebuild_menu()
		return
	var candidate := _create_game()
	if not SaveGame.restore(candidate, data):
		candidate.queue_free()
		error_text = "Не удалось восстановить сохранение. Файл не изменён."
		_rebuild_menu()
		return
	game = candidate
	_resume_game()

func _pause_game() -> void:
	if game == null:
		return
	menu_open = true
	about_open = false
	game.set_process(false)
	game.set_process_input(false)
	game.hide()
	# Release physical inputs, retaining throttle and elevator positions.
	game.throttle_up_held = false
	game.throttle_down_held = false
	game.flight.wheel_brakes_applied = false
	game.dragging_throttle = false
	game.dragging_yoke = false
	game.dragging_map = false
	game.map_drag_candidate = false
	game.point_drag_candidate = false
	game.dragging_measure_point = false
	game.dragged_measure_connections.clear()
	game.scene_is_walking = false
	menu_root.show()
	_rebuild_menu()

func _resume_game() -> void:
	if game == null:
		return
	menu_open = false
	menu_root.hide()
	game.show()
	game.set_process(true)
	game.set_process_input(true)
	game.weather_radar_cache.invalidate()
	game._queue_map_redraw()
	game.queue_redraw()

func _save_and_exit() -> void:
	var error := SaveGame.write_slot(game, save_path)
	if error == OK:
		_exit_game()
	else:
		error_text = "Сохранение не записано: %s. Игра не закрыта." % error_string(error)
		_rebuild_menu()

func _exit_game() -> void:
	if not OS.has_feature("web"):
		get_tree().quit()
		return
	# Browsers cannot close a normal tab. Return to a live title screen instead.
	if game != null:
		game.set_process(false)
		game.set_process_input(false)
		game.hide()
		game.queue_free()
		game = null
	menu_open = true
	about_open = false
	error_text = "Можно закрыть вкладку. Сохранения хранятся в этом браузере."
	menu_root.show()
	_rebuild_menu()

func _open_about() -> void:
	about_open = true
	error_text = ""
	_rebuild_menu()

func _close_about() -> void:
	about_open = false
	_rebuild_menu()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and (event.keycode == KEY_Q or event.physical_keycode == KEY_Q):
		get_viewport().set_input_as_handled()
		_exit_game()
	elif event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if about_open:
			_close_about()
		elif game != null:
			if menu_open:
				_resume_game()
			else:
				_pause_game()
