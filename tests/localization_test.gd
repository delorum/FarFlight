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
	check(Localization.text("Посадка") == "Landing practice" and Localization.text("Начать заново") == "Restart", "Landing-practice menu labels must translate")
	check(Localization.text("Успешная посадка в аэропорту «Северный»") == "Successful landing at “Northern”", "Formatted messages and airport names must translate together")
	check(Localization.text("КУПИТЬ ЕДУ С СОБОЙ • 14 монет (дешево)") == "BUY TAKEAWAY FOOD • 14 coins (cheap)", "Completed dynamic economy labels must translate")
	check(Localization.text("Северный: почта, лётная служба, кафе (+)") == "Northern: post office, flight service, cafe (+)", "Map service summaries must translate")
	check(Localization.text("Грузовой отсек • самолёт продолжает полёт • колесо вниз: отдалить") == "Cargo hold • flight continues • wheel down: zoom out", "Composed cabin prompts must translate as one sentence")
	check(Localization.text("ПОЧТА — Северный") == "MAIL — Northern", "Flattened multiline cargo labels must translate")
	check(Localization.text("Самолёт подготовлен к вылету курсом 185° • оплачено 40 монет") == "Aircraft prepared for departure on heading 185° • paid 40 coins", "Composed operation notices must translate")
	check("%s • %s" % [Localization.text("СТВОР"), Localization.text("НИЗКО")] == "LOCALIZER • LOW", "Composed ILS status must not retain Russian fragments")
	check(Localization.text("VS -1.25 м/с • НУЖНО -1.40 м/с") == "VS -1.25 m/s • TARGET -1.40 m/s", "Large ILS target vertical speed must translate")

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
	var calculator_labels: Array[Node] = game.flight_calculator.find_children("*", "Label", true, false)
	check(calculator_labels.any(func(label): return label.text == "FLIGHT CALCULATOR  ⋮⋮"), "The flight calculator must refresh into English")

	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("English/Russian localization, persistence, menus and calculator: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
