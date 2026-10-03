extends SceneTree

const Localization = preload("res://scripts/localization.gd")

var failed := false
var settings_path := "user://test_localization_%d.cfg" % Time.get_ticks_usec()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func button_texts(shell) -> Array[String]:
	var result: Array[String] = []
	for child in shell.content.get_children():
		if child is Button:
			result.append(child.text)
	return result

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Localization.initialize(settings_path)
	check(Localization.language == Localization.RUSSIAN, "A missing settings file must default to Russian")
	Localization.set_language(Localization.ENGLISH)
	check(Localization.text("Далекий полет") == "Far Flight", "The Russian title must retain the Far Flight name in English")
	check(Localization.text("Далекий полет — Почтовая авиация") == "Far Flight — Airmail", "The localized window title must include the translated subtitle")
	check(Localization.text("Новая игра") == "New game", "Static interface labels must translate")
	check(Localization.text("75.0 км • 00:30:00 • СР. 150.0 км/ч • день 1 00:00:00 → день 1 00:30:00") == "75.0 km • 00:30:00 • AVG 150.0 km/h • day 1 00:00:00 → day 1 00:30:00", "Flight-history average speed and timestamps must translate together")
	check(Localization.text("ЛЁТНАЯ СЛУЖБА • МИР 2") == "FLIGHT SERVICE • WORLD 2", "Flight service must localize its current world number")
	check(Localization.text("СТАТИСТИКА ПОЛЁТОВ • МИР 2") == "FLIGHT HISTORY • WORLD 2", "History must localize its current world number")
	check(Localization.text("ПЕРЕХОД: МИР 1 → МИР 2") == "TRANSITION: WORLD 1 → WORLD 2", "World crossing rows must translate")
	check(Localization.text("Мир 1 → 2") == "World 1 → 2", "Cross-world flight labels must translate")
	check(Localization.text("Посадка") == "Landing practice" and Localization.text("Начать заново") == "Restart", "Landing-practice menu labels must translate")
	check(Localization.text("Успешная посадка в аэропорту «Северный»") == "Successful landing at “Northern”", "Formatted messages and airport names must translate together")
	check(Localization.text("Жёсткое касание • планер −2.0% ВПП «Северный» на 100.0 км/ч — газ 0%, удерживайте S для торможения") == "Hard touchdown • airframe −2.0% RWY “Northern” at 100.0 km/h — throttle 0%, hold S to brake", "Hard touchdown damage must translate inside the complete landing message")
	check(Localization.text("КУПИТЬ ЕДУ С СОБОЙ • 14 монет (дешево)") == "BUY TAKEAWAY FOOD • 14 coins (cheap)", "Completed dynamic economy labels must translate")
	check(Localization.text("Северный: почта, лётная служба, кафе (+)") == "Northern: post office, flight service, cafe (+)", "Map service summaries must translate")
	check(Localization.text("Грузовой отсек • самолёт продолжает полёт • колесо вниз: отдалить") == "Cargo hold • flight continues • wheel down: zoom out", "Composed cabin prompts must translate as one sentence")
	check(Localization.text("ПОЧТА — Северный") == "MAIL — Northern", "Flattened multiline cargo labels must translate")
	check(Localization.text("Самолёт подготовлен к вылету курсом 185° • оплачено 40 монет") == "Aircraft prepared for departure on heading 185° • paid 40 coins", "Composed operation notices must translate")
	check("%s • %s" % [Localization.text("СТВОР"), Localization.text("НИЗКО")] == "LOCALIZER • LOW", "Composed ILS status must not retain Russian fragments")
	check(Localization.text("VS -1.25 м/с • НУЖНО -1.40 м/с") == "VS -1.25 m/s • TARGET -1.40 m/s", "Large ILS target vertical speed must translate")
	check(Localization.text("ОСЬ +200 м") == "AXIS +200 m" and Localization.text("НОС -16.5°") == "NOSE -16.5°", "Off-scale ILS arrows must translate their numeric labels")
	check(Localization.text("почта (7)") == "post office (7)" and Localization.text("Карта 2") == "Map 2", "Mail stock and level indicators must translate")
	check(Localization.text("КАРТА 2 • Северный → Озёрный • ВСЕГО ПОЛЁТОВ: 3 • РЕКОРД СВЕРХУ").contains("MAP 2") and Localization.text("КАРТА 2 • Северный → Озёрный • ВСЕГО ПОЛЁТОВ: 3 • РЕКОРД СВЕРХУ").contains("TOTAL FLIGHTS: 3"), "Per-map flight records must translate")
	check(Localization.text("Переход на новую карту • недоставленная почта останется здесь") == "Next map • undelivered mail stays behind", "The one-way exit warning must translate")
	check(Localization.text("КАС. +0.09 км") == "TD +0.09 km" and Localization.text("БОК -1 м") == "LAT -1 m", "Compact touchdown and lateral forecast labels must translate")

	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.settings_path = settings_path
	shell.save_path = settings_path + ".save"
	root.add_child(shell)
	await process_frame
	check(button_texts(shell) == ["New game", "Landing practice", "About", "Language", "Credits", "Quit"], "The title menu must restore and display English: %s" % [button_texts(shell)])
	shell._open_about()
	var about_links: Array[Node] = shell.content.find_children("*", "LinkButton", true, false)
	check(about_links.size() == 1 and about_links[0].uri == shell.README_URL_EN, "English About must link to the English README")
	shell._close_about()
	shell._open_language()
	check(button_texts(shell) == ["Russian", "✓ English", "Back"], "Language menu must offer Russian and English and mark the active choice")
	shell._select_language(Localization.RUSSIAN)
	check(button_texts(shell) == ["✓ Русский", "Английский", "Назад"], "Russian must become the marked active language")
	Localization.set_language(Localization.ENGLISH)
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.localization_changed()
	var airport_screen: Vector2 = game.navigation_map.world_to_screen(Vector2(game.world.airports[0].position))
	var airport_hover := Localization.text(game.navigation_map.map_footer_text_at(airport_screen))
	check(airport_hover.contains("Northern") and airport_hover.contains("post office (7), flight service"), "The map's inline finite-mail count must translate in context")
	var calculator_labels: Array[Node] = game.flight_calculator.find_children("*", "Label", true, false)
	check(calculator_labels.any(func(label): return label.text == "FLIGHT CALCULATOR  ⋮⋮"), "The flight calculator must refresh into English")

	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("English/Russian localization, persistence, menus and calculator: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
