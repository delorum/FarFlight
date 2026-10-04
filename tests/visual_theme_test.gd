extends SceneTree
const VisualTheme = preload("res://scripts/visual_theme.gd")
const Palette = preload("res://scripts/ui_palette.gd")
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
	check(not scene.instrument_panel.has_method("get_theme_button_rect"), "Theme switch must no longer be part of aircraft controls")
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.settings_path = TEST_SETTINGS
	shell.save_path = TEST_SETTINGS + ".save"
	root.add_child(shell)
	shell.hide()
	shell.game = scene
	scene.flight_calculator._apply_validation_style("")
	var calculation: Dictionary = scene.flight_calculator.values.duplicate(true)
	var distance_text: String = scene.flight_calculator.fields.distance.text
	scene.time_scale_index = 2
	shell._open_settings()
	shell._open_theme()
	shell._select_theme(true)
	check(VisualTheme.dark, "Menu settings must enable dark landscape theme")
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
	check(scene.map_render_layer.material.get_shader_parameter("source_paper") == Vector3(Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b), "Landscape shader must use the central paper colour")
	check(scene.map_render_layer.material.get_shader_parameter("source_route") == Vector3(Palette.ROUTE.r, Palette.ROUTE.g, Palette.ROUTE.b), "Landscape shader must preserve the central route colour")
	check(scene.map_render_layer.material.get_shader_parameter("dark_background") == Vector3(Palette.DARK_BACKGROUND.r, Palette.DARK_BACKGROUND.g, Palette.DARK_BACKGROUND.b), "Landscape shader must use the central dark background")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/theme_preview_map.png")
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64, 64)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var swatch := ColorRect.new()
		swatch.size = Vector2(64, 64)
		swatch.color = Palette.ROUTE
		swatch.material = scene.map_render_layer.material
		viewport.add_child(swatch)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(32, 32)
		check(absf(pixel.r - Palette.ROUTE.r) < 0.02 and absf(pixel.g - Palette.ROUTE.g) < 0.02 and absf(pixel.b - Palette.ROUTE.b) < 0.02, "Dark map must render user-drawn lines in their original blue, not beige")
		viewport.queue_free()
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
	shell._select_theme(false)
	check(not VisualTheme.dark, "Selecting Light must restore the light palette")
	check(scene.flight_calculator.get_theme_stylebox("panel").bg_color == Color("d7d0ad"), "Calculator must return to the light theme with the map")
	shell.game = null
	shell.queue_free()
	scene.queue_free()
	await process_frame
	Localization.initialize(previous_settings)
	Localization.set_language(previous_language, false)
	VisualTheme.initialize(previous_settings)
	VisualTheme.set_dark(previous_dark, false)
	DirAccess.remove_absolute(TEST_SETTINGS)
	print("Landscape theme and menu settings: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
