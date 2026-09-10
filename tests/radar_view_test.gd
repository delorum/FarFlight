extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var map_size: Vector2 = scene.map_rect().size
	var world_span_px: float = scene.FlightWorldScript.SIZE_KM * scene.pixels_per_km()
	check(world_span_px + 0.01 >= maxf(map_size.x, map_size.y), "Maximum zoom-out must cover the whole map viewport without side gaps")
	check(scene.map_center.is_equal_approx(Vector2(scene.world.airports[scene.flight.airport_index].position)), "New game map must be centred on the departure airport")
	var initial_radius: float = maxf(map_size.x, map_size.y) / (scene.pixels_per_km() * 2.0)
	check(initial_radius <= scene.INITIAL_MAP_RADIUS_KM + 0.01, "Initial map view must show about a 40 km radius")
	scene.map_zoom = 4.0
	scene.map_center = Vector2(45,55)
	scene.measurement_lines.append({"a":Vector2(20,30),"b":Vector2(40,60),"max_height_m":500.0})
	var original_lines: Array = scene.measurement_lines.duplicate(true)
	scene.pending_measure = Vector2(25,35)
	scene.map_drag_candidate = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = scene.get_weather_radar_rect().get_center()
	scene._handle_mouse_button(click)
	check(scene.large_weather_radar,"Click must open large radar even with engine off")
	check(not scene.map_drag_candidate,"Switch must cancel map drag gesture")
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		click.button_index = button
		click.position = scene.map_rect().get_center()
		scene._handle_mouse_button(click)
	check(scene.map_zoom == 4.0 and scene.map_center == Vector2(45,55),"Radar clicks/wheel must not change hidden map camera")
	check(scene.measurement_lines == original_lines and scene.pending_measure == Vector2(25,35),"Radar must preserve map annotations including unfinished line")
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.pressed = true
	scene.simulation_paused = true
	scene._input(key)
	check(not scene.large_weather_radar,"Hotkey must restore map while paused")
	scene._input(key)
	check(scene.large_weather_radar,"Hotkey must open radar while paused")
	key.echo = true
	scene._input(key)
	check(scene.large_weather_radar,"Key repeat must not repeatedly toggle views")
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = scene.get_weather_radar_rect().get_center()
	scene._handle_mouse_button(click)
	check(not scene.large_weather_radar,"Click miniature must restore map")
	key.echo = false
	key.keycode = KEY_NONE
	key.physical_keycode = KEY_B
	scene._input(key)
	check(scene.large_weather_radar,"Physical B must work with alternate keyboard layout")
	scene._enter_cabin()
	scene._input(key)
	check(scene.large_weather_radar,"Radar hotkey must not change state in side scenes")
	scene._set_view_mode(scene.ViewMode.COCKPIT)
	check(scene.map_render_layer.visible and scene.large_weather_radar,"Returning to cockpit must retain selected display")
	scene._toggle_weather_radar()
	check(scene.measurement_lines == original_lines and scene.pending_measure == Vector2(25,35),"Round trip through radar/cabin must preserve annotations")
	var cache = scene.weather_radar_cache
	cache.invalidate()
	var count_before: int = cache.refresh_count
	cache.update_cache(scene.world, scene.flight, 10.0)
	for frame in range(1, 60):
		scene.flight.heading_deg = fposmod(359.0 + frame, 360.0)
		cache.update_cache(scene.world, scene.flight, 10.0 + frame / 60.0)
	check(cache.refresh_count == count_before + 1, "Turning at 60 fps must only rasterize echoes once per second")
	check(cache.snapshot.heading_deg == 0.0, "Echo texture must stay north-up for independent smooth rotation")
	cache.update_cache(scene.world, scene.flight, 11.0)
	check(cache.refresh_count == count_before + 2, "Next simulation second must refresh echoes")
	for frame in 60:
		cache.update_cache(scene.world, scene.flight, 11.0)
	check(cache.refresh_count == count_before + 2, "Paused simulation must not refresh cached weather")
	cache.invalidate()
	cache.update_cache(scene.world, scene.flight, 11.0)
	check(cache.refresh_count == count_before + 3, "Reopening scope must allow an immediate refresh")
	print("Radar switching, pause, map preservation and 1 Hz echo cache: ","FAIL" if failed else "OK")
	quit(1 if failed else 0)
