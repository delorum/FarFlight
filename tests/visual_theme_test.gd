extends SceneTree
const VisualTheme = preload("res://scripts/visual_theme.gd")
const Localization = preload("res://scripts/localization.gd")
const TEST_SETTINGS := "/tmp/farflight_visual_theme_test.cfg"
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	var previous_settings := Localization.settings_path
	var previous_language := Localization.language
	var previous_dark := VisualTheme.dark
	var config := ConfigFile.new()
	config.set_value("interface", "language", "en")
	config.set_value("interface", "dark_landscape", false)
	config.save(TEST_SETTINGS)
	Localization.initialize(TEST_SETTINGS)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	await process_frame
	var button: Rect2 = scene.instrument_panel.get_theme_button_rect()
	check(button.position.y > scene.get_cabin_button_rect().end.y, "Theme switch must be on a separate second row")
	check(not button.intersects(scene.get_weather_radar_rect()) and not button.intersects(scene.get_ils_rect()), "Theme switch must not overlap radar or ILS")
	check(scene.instrument_panel.panel_rect().encloses(button), "Theme switch must fit inside the instrument panel")
	check(button.end.y < scene.instrument_panel.panel_rect().end.y - 25.0, "Theme switch must leave room for the flight-status line")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = button.get_center()
	scene.flight_calculator._apply_validation_style("")
	var calculation: Dictionary = scene.flight_calculator.values.duplicate(true)
	var distance_text: String = scene.flight_calculator.fields.distance.text
	scene.time_scale_index = 2
	scene._handle_mouse_button(click)
	check(VisualTheme.dark, "Click must enable dark landscape theme")
	check(scene.flight_calculator.get_theme_stylebox("panel").bg_color == Color("071012"), "Calculator panel must match the dark map background")
	check(scene.flight_calculator.fields.distance.get_theme_color("font_color") == Color("d7d0ad"), "Calculator values must be beige in dark mode")
	check(scene.flight_calculator.values == calculation and scene.flight_calculator.fields.distance.text == distance_text, "Theme change must not alter calculations or field contents")
	scene.flight_calculator._apply_validation_style("invalid test calculation")
	check(scene.flight_calculator.fields.distance.get_theme_color("font_color") == Color("ef645e"), "Calculator errors must remain clearly red")
	scene.flight_calculator.refresh_visual_theme()
	check(scene.flight_calculator.fields.distance.get_theme_color("font_color") == Color("ef645e"), "Refreshing palette must preserve the validation error")
	scene.flight_calculator._apply_validation_style("")
	check(scene.time_scale_index == 2, "Theme changes must not alter time acceleration")
	check(config.load(TEST_SETTINGS) == OK and config.get_value("interface", "language") == "en", "Saving theme must preserve language preference")
	VisualTheme.initialize(TEST_SETTINGS)
	check(VisualTheme.dark, "Theme preference must survive reloading settings")
	scene.map_render_layer.refresh()
	check(bool(scene.map_render_layer.material.get_shader_parameter("theme_enabled")), "Map layers must enable the selected palette")
	check(scene.map_render_layer.overlay.use_parent_material, "Overlay must use the same theme as map terrain")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/theme_preview_map.png")
	scene._enter_cabin()
	scene.queue_redraw()
	await process_frame
	await process_frame
	check(bool(scene.material.get_shader_parameter("theme_enabled")), "Cabin must use the dark landscape palette")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/theme_preview_cabin.png")
	scene._set_view_mode(scene.ViewMode.COCKPIT)
	scene.large_ils = true
	scene.map_render_layer.refresh()
	check(not bool(scene.map_render_layer.material.get_shader_parameter("theme_enabled")), "Large ILS must retain its existing instrument colours")
	scene.large_ils = false
	scene._handle_mouse_button(click)
	check(not VisualTheme.dark, "Second click must restore the light palette")
	check(scene.flight_calculator.get_theme_stylebox("panel").bg_color == Color("d7d0ad"), "Calculator must return to the light theme with the map")
	scene.queue_free()
	await process_frame
	Localization.initialize(previous_settings)
	Localization.set_language(previous_language, false)
	VisualTheme.initialize(previous_settings)
	VisualTheme.set_dark(previous_dark, false)
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("Landscape theme, button layout and settings: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
