extends SceneTree
const Localization = preload("res://scripts/localization.gd")
const VisualTheme = preload("res://scripts/visual_theme.gd")
const Palette = preload("res://scripts/ui_palette.gd")
var failed := false
var settings := "user://test_menu_settings_%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func buttons(shell) -> Array[String]:
	var result: Array[String] = []
	for child in shell.content.get_children():
		if child is Button:
			result.append(child.text)
	return result

func escape(shell) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	shell._input(event)

func preview(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + name + ".png")

func _run() -> void:
	var old_settings := Localization.settings_path
	var old_language := Localization.language
	var old_dark := VisualTheme.dark
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.settings_path = settings
	shell.save_path = settings + ".save"
	root.add_child(shell)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	check(shell.background.texture == shell.DAY_ART, "Light title menu must use the original art")
	check(buttons(shell).has("Настройки") and not buttons(shell).has("Язык"), "Language must move inside Settings")
	shell._open_settings()
	check(buttons(shell) == ["Язык", "Тема оформления", "Назад"], "Settings must expose language and theme")
	shell._open_language()
	shell._select_language(Localization.ENGLISH)
	check(buttons(shell) == ["Russian", "✓ English", "Back"], "Language choices must remain localized")
	escape(shell)
	check(shell.settings_open and not shell.language_open and buttons(shell) == ["Language", "Display theme", "Back"], "Escape from Language must return to Settings")
	shell._open_theme()
	check(buttons(shell) == ["✓ Light", "Dark", "Back"], "Theme choices must mark the current preference")
	shell._select_theme(true)
	check(shell.night_art != null, "The supplied night artwork must be installed and imported")
	check(shell.background.texture == shell.night_art and shell.night_art != shell.DAY_ART, "Dark title menu must use a separate night-time asset")
	check(buttons(shell) == ["Light", "✓ Dark", "Back"], "Dark must be marked as selected")
	check(shell.version_label.get_theme_color("font_color") == Palette.PAPER, "Version must remain readable in the dark menu")
	var gradient_colors: PackedColorArray = shell.background_gradient.colors
	shell._rebuild_menu()
	check(shell.background_gradient.colors == gradient_colors, "Rebuilding unchanged menus must preserve the cached background gradient")
	var config := ConfigFile.new()
	check(config.load(settings) == OK and config.get_value("interface", "language") == "en" and config.get_value("interface", "dark_landscape"), "Theme and language must persist without overwriting each other")
	escape(shell)
	check(shell.settings_open and not shell.theme_open, "Escape from Theme must return to Settings")
	escape(shell)
	check(not shell.settings_open and buttons(shell).has("Settings"), "Escape from Settings must return to the title menu")
	await preview("menu_night_preview")
	shell._open_about()
	var links: Array[Node] = shell.content.find_children("*", "LinkButton", true, false)
	check(links[0].get_theme_color("font_color") == Palette.PAPER, "About links must use the dark menu text colour")
	shell._close_about()
	shell._open_new_game_setup()
	check(shell.new_game_seed_field.get_theme_color("font_color") == Palette.PAPER, "Seed input must follow the dark menu palette")
	shell._close_new_game_setup()

	shell._new_game(424242)
	shell._pause_game()
	var game = shell.game
	game.set_process(false)
	game.time_scale_index = 3
	check(shell.background.texture == shell.night_art and buttons(shell).has("Settings"), "Pause menu must use the same night background and expose Settings")
	await preview("pause_night_preview")
	shell._open_settings()
	shell._open_theme()
	var calculation: Dictionary = game.flight_calculator.values.duplicate(true)
	shell._select_theme(false)
	check(shell.background.texture == shell.DAY_ART, "Light pause menu must restore the original day art")
	check(game.flight_calculator.get_theme_stylebox("panel").bg_color == Palette.PAPER, "Changing theme in pause must immediately update the game palette")
	check(game.time_scale_index == 3 and game.flight_calculator.values == calculation, "Appearance changes must not reset time or alter flight calculations")
	check(not game.instrument_panel.has_method("get_theme_button_rect"), "Theme switch must be removed from the cockpit panel")
	shell._close_theme()
	shell._close_settings()
	await preview("pause_day_preview")
	VisualTheme.initialize(settings)
	check(not VisualTheme.dark, "Reloading settings must restore the last chosen theme")
	Localization.initialize(settings)
	check(Localization.language == Localization.ENGLISH, "Choosing Light must preserve English")
	shell.free()
	Localization.initialize(old_settings)
	Localization.set_language(old_language, false)
	VisualTheme.initialize(old_settings)
	VisualTheme.set_dark(old_dark, false)
	if FileAccess.file_exists(settings):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings))
	if not failed:
		print("Main/pause menu themes, nested settings and persistence: OK")
	quit(1 if failed else 0)
