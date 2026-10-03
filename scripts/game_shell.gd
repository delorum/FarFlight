extends Control

const SaveGame = preload("res://scripts/save_game.gd")
const GameVersion = preload("res://scripts/game_version.gd")
const SessionMode = preload("res://scripts/session_mode.gd")
const Localization = preload("res://scripts/localization.gd")
const GAME_SCENE = preload("res://scenes/main.tscn")
const INK := Color("513e2c")
const README_URL_EN := "https://github.com/delorum/FarFlight/blob/main/README.md"
const README_URL_RU := "https://github.com/delorum/FarFlight/blob/main/README_RU.md"
const ABOUT := "Вы — почтальон-пилот. Между затерянными аэродромами почтовая авиация связывает людей: посылки, письма и вести издалека должны добраться до адресата. Выбирайте заказы на почте, загружайте самолёт и составляйте выгодные маршруты для нескольких доставок. Дальние заказы оплачиваются лучше.\n\nНо здесь небо почти никогда не бывает ясным. Уже в ста метрах над землёй начинается сплошная облачность. Дальше — полёт по приборам: курс, высота, скорость, сигналы радиомаяков и ваши пометки на карте. Положение самолёта на ней не отмечено — его предстоит определить самому.\n\nУчитывайте ветер, обходите грозы и планируйте остановки: топливо, еда, гостиницы и ремонтные ангары есть не на каждом аэродроме. Канистры и грузы занимают место, пилоту нужно есть и отдыхать, а самолёт постепенно изнашивается — особенно в грозах и при превышении безопасной скорости. Летайте между аэродромами, доставляйте почту и зарабатывайте деньги на новые рейсы."

var game: Control
var menu_root: Control
var content: VBoxContainer
var version_label: Label
var about_open := false
var authors_open := false
var language_open := false
var new_game_setup_open := false
var menu_open := true
var error_text := ""
var save_path := SaveGame.PATH
var settings_path := Localization.DEFAULT_SETTINGS_PATH
var new_game_seed_text := ""
var new_game_seed_field: LineEdit

func _ready() -> void:
	Localization.initialize(settings_path)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DisplayServer.window_set_title(Localization.text("Далекий полет — Почтовая авиация"))
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
	version_label = _label(GameVersion.display_version(), 16)
	version_label.name = "GameVersion"
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version_label.position = Vector2(-224, -48)
	version_label.size = Vector2(200, 28)
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(version_label)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = Localization.text(text)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _button(text: String, action: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = Localization.text(text)
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

func _link(text: String, url: String, parent: Node = null) -> LinkButton:
	var link := LinkButton.new()
	link.text = Localization.text(text)
	link.uri = url
	link.add_theme_color_override("font_color", INK)
	link.add_theme_color_override("font_hover_color", Color("8a552f"))
	link.add_theme_font_size_override("font_size", 20)
	(parent if parent != null else content).add_child(link)
	return link

func _rebuild_menu() -> void:
	if content != null:
		content.hide()
		content.queue_free()
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	menu_root.add_child(content)
	content.add_child(_label("Далекий полет", 64))
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
		var about_body := VBoxContainer.new()
		about_body.add_theme_constant_override("separation", 12)
		about_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(about_body)
		var description := _label(ABOUT, 18)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		about_body.add_child(description)
		about_body.add_child(_label("Подробнее обо всех приборах, механиках и управлении:", 16))
		_link("README — подробная справка", README_URL_EN if Localization.is_english() else README_URL_RU, about_body)
		_button("Назад", _close_about)
	elif authors_open:
		content.add_child(_label("Авторы", 22))
		_link("github.com/delorum", "https://github.com/delorum")
		_button("Назад", _close_authors)
	elif language_open:
		content.add_child(_label("ЯЗЫК", 22))
		_button(("✓ " if Localization.language == Localization.RUSSIAN else "") + Localization.text("Русский"), _select_language.bind(Localization.RUSSIAN))
		_button(("✓ " if Localization.language == Localization.ENGLISH else "") + Localization.text("Английский"), _select_language.bind(Localization.ENGLISH))
		_button("Назад", _close_language)
	elif new_game_setup_open:
		content.add_child(_label("НОВАЯ ИГРА", 22))
		var seed_help := _label("Введите seed от 1 до 2147483647, чтобы воспроизвести тот же мир. Оставьте поле пустым для случайного seed.", 16)
		seed_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(seed_help)
		new_game_seed_field = LineEdit.new()
		new_game_seed_field.name = "WorldSeed"
		new_game_seed_field.placeholder_text = Localization.text("Seed мира — пусто: случайный")
		new_game_seed_field.text = new_game_seed_text
		new_game_seed_field.max_length = 10
		new_game_seed_field.custom_minimum_size.y = 48
		new_game_seed_field.add_theme_font_size_override("font_size", 19)
		new_game_seed_field.add_theme_color_override("font_color", INK)
		new_game_seed_field.add_theme_color_override("font_placeholder_color", Color(0.32, 0.25, 0.18, 0.55))
		new_game_seed_field.add_theme_color_override("caret_color", INK)
		for state in ["normal", "focus", "read_only"]:
			var field_style := StyleBoxFlat.new()
			field_style.bg_color = Color(0.93, 0.89, 0.79, 0.66)
			field_style.border_color = Color(0.40, 0.29, 0.18, 0.55 if state == "focus" else 0.28)
			field_style.set_border_width_all(1)
			field_style.content_margin_left = 12
			field_style.content_margin_right = 12
			new_game_seed_field.add_theme_stylebox_override(state, field_style)
		new_game_seed_field.text_changed.connect(func(value: String): new_game_seed_text = value)
		new_game_seed_field.text_submitted.connect(func(_value: String): _start_configured_new_game())
		content.add_child(new_game_seed_field)
		_button("Начать игру", _start_configured_new_game)
		_button("Назад", _close_new_game_setup)
	elif game != null:
		if SessionMode.is_landing_practice(game.session_mode):
			content.add_child(_label("ПОСАДКА", 14))
			_button("Начать заново", _restart_landing_training)
			_button("В главное меню", _leave_landing_training)
		else:
			var run_finished: bool = game.flight.state == game.FlightModelScript.State.CRASHED
			content.add_child(_label("ИТОГИ ПРОХОЖДЕНИЯ" if run_finished else "ПАУЗА", 14))
			_button(("Вернуться к итогам" if run_finished else "Продолжить") + " • seed %d" % game.world.seed_value, _resume_game)
			_button("Статистика полётов", _open_pause_flight_history)
			_button("Об игре", _open_about)
			_button("Язык", _open_language)
			_button("Новая игра", _open_new_game_setup)
			if run_finished:
				_button("Выйти", _exit_game)
			else:
				_button("Сохранить и выйти", _save_and_exit)
	else:
		var slot := SaveGame.read_slot(save_path)
		if not slot.is_empty():
			var saved_action: String = "Итоги" if SaveGame.is_finished_run(slot) else "Продолжить"
			_button("%s • seed %d" % [saved_action, int(slot.world.seed)], _continue_game)
		_button("Новая игра", _open_new_game_setup)
		_button("Посадка", _start_landing_training)
		_button("Об игре", _open_about)
		_button("Язык", _open_language)
		_button("Авторы", _open_authors)
		_button("Выход", _exit_game)
		if SaveGame.slot_exists(save_path) and slot.is_empty():
			error_text = "Сохранение повреждено или несовместимо с этой версией."
	if not error_text.is_empty():
		var error_label := _label(error_text, 15)
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error_label.add_theme_color_override("font_color", Color("893f2f"))
		content.add_child(error_label)
	_layout_menu()
	if new_game_setup_open and new_game_seed_field != null:
		new_game_seed_field.grab_focus()
		new_game_seed_field.caret_column = new_game_seed_field.text.length()
	else:
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

func _create_game(requested_seed: int = 0, mode: int = SessionMode.Mode.CAMPAIGN) -> Control:
	var instance: Control = GAME_SCENE.instantiate()
	instance.requested_world_seed = requested_seed
	instance.session_mode = mode
	add_child(instance)
	move_child(instance, 0)
	instance.set_process(false)
	instance.set_process_input(false)
	return instance

func _open_new_game_setup() -> void:
	new_game_setup_open = true
	about_open = false
	authors_open = false
	language_open = false
	error_text = ""
	new_game_seed_text = ""
	_rebuild_menu()

func _close_new_game_setup() -> void:
	new_game_setup_open = false
	error_text = ""
	_rebuild_menu()

func _start_configured_new_game() -> void:
	if new_game_seed_field != null:
		new_game_seed_text = new_game_seed_field.text
	var text_value := new_game_seed_text.strip_edges()
	var requested_seed := 0
	if not text_value.is_empty():
		if not text_value.is_valid_int():
			error_text = "Seed должен быть целым числом."
			_rebuild_menu()
			return
		requested_seed = int(text_value)
		if requested_seed < 1 or requested_seed > 2147483647:
			error_text = "Seed должен находиться в диапазоне от 1 до 2147483647."
			_rebuild_menu()
			return
	_new_game(requested_seed)

func _new_game(requested_seed: int = 0) -> void:
	if game != null:
		game.set_process(false)
		game.set_process_input(false)
		game.hide()
		game.queue_free()
	game = _create_game(requested_seed)
	error_text = ""
	new_game_setup_open = false
	_resume_game()

func _start_landing_training() -> void:
	var previous_seed := int(game.world.seed_value) if game != null and SessionMode.is_landing_practice(game.session_mode) else 0
	_discard_current_game()
	var training_seed := randi_range(10000, 99999999)
	if training_seed == previous_seed:
		training_seed = 10000 if training_seed == 99999999 else training_seed + 1
	game = _create_game(training_seed, SessionMode.Mode.LANDING_PRACTICE)
	error_text = ""
	new_game_setup_open = false
	_resume_game()

func _restart_landing_training() -> void:
	if game == null or not SessionMode.is_landing_practice(game.session_mode):
		return
	_start_landing_training()

func _leave_landing_training() -> void:
	if game == null or not SessionMode.is_landing_practice(game.session_mode):
		return
	_discard_current_game()
	menu_open = true
	menu_root.show()
	error_text = ""
	_rebuild_menu()

func _discard_current_game() -> void:
	if game == null:
		return
	game.set_process(false)
	game.set_process_input(false)
	game.hide()
	game.queue_free()
	game = null

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
	game._prepare_return_from_pause_history()
	menu_open = true
	about_open = false
	authors_open = false
	language_open = false
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
	game.dragging_fuel_slider = false
	game.dragged_measure_connections.clear()
	game.scene_is_walking = false
	menu_root.show()
	_rebuild_menu()

func _open_pause_flight_history() -> void:
	if game == null:
		return
	game.open_flight_history_from_pause()
	_resume_game()

func _on_run_finished(finished_game: Control) -> void:
	if finished_game != game:
		return
	if not SessionMode.allows_save(game.session_mode):
		return
	var error := SaveGame.write_slot(game, save_path)
	if error == OK:
		error_text = ""
	else:
		var details := " (%s)" % SaveGame.last_validation_error if not SaveGame.last_validation_error.is_empty() else ""
		error_text = "Итоги прохождения не сохранены: %s%s." % [error_string(error), details]

func _resume_game() -> void:
	if game == null:
		return
	menu_open = false
	menu_root.hide()
	game.show()
	game.set_process(true)
	game.set_process_input(true)
	game.invalidate_weather_radar_caches()
	game._queue_map_redraw()
	game.queue_redraw()

func _save_and_exit() -> void:
	if game != null and not SessionMode.allows_save(game.session_mode):
		_leave_landing_training()
		return
	var error := SaveGame.write_slot(game, save_path)
	if error == OK:
		_exit_game()
	else:
		var details := " (%s)" % SaveGame.last_validation_error if not SaveGame.last_validation_error.is_empty() else ""
		error_text = "Сохранение не записано: %s%s. Игра не закрыта." % [error_string(error), details]
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
	authors_open = false
	language_open = false
	error_text = "Можно закрыть вкладку. Сохранения хранятся в этом браузере."
	menu_root.show()
	_rebuild_menu()

func _open_about() -> void:
	about_open = true
	authors_open = false
	language_open = false
	new_game_setup_open = false
	error_text = ""
	_rebuild_menu()

func _close_about() -> void:
	about_open = false
	_rebuild_menu()

func _open_authors() -> void:
	authors_open = true
	about_open = false
	language_open = false
	new_game_setup_open = false
	error_text = ""
	_rebuild_menu()

func _close_authors() -> void:
	authors_open = false
	_rebuild_menu()

func _open_language() -> void:
	language_open = true
	about_open = false
	authors_open = false
	new_game_setup_open = false
	error_text = ""
	_rebuild_menu()

func _close_language() -> void:
	language_open = false
	_rebuild_menu()

func _select_language(selected: String) -> void:
	Localization.set_language(selected)
	DisplayServer.window_set_title(Localization.text("Далекий полет — Почтовая авиация"))
	if game != null and game.has_method("localization_changed"):
		game.localization_changed()
	_rebuild_menu()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if about_open:
			_close_about()
		elif authors_open:
			_close_authors()
		elif language_open:
			_close_language()
		elif new_game_setup_open:
			_close_new_game_setup()
		elif game != null:
			if menu_open:
				_resume_game()
			else:
				_pause_game()
