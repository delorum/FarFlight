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
	var removed_receiver_shortcut := InputEventKey.new()
	removed_receiver_shortcut.keycode = KEY_1
	removed_receiver_shortcut.ctrl_pressed = true
	removed_receiver_shortcut.pressed = true
	scene._input(removed_receiver_shortcut)
	check(scene.active_receiver == -1, "Removed Ctrl+1/2 shortcuts must not select a receiver")
	var frequency_before_digit: int = scene.receiver_frequencies[0]
	scene.active_receiver = 0
	var removed_frequency_digit := InputEventKey.new()
	removed_frequency_digit.keycode = KEY_3
	removed_frequency_digit.unicode = 51
	removed_frequency_digit.pressed = true
	scene._input(removed_frequency_digit)
	check(scene.receiver_frequencies[0] == frequency_before_digit, "Digit keys must no longer edit receiver frequency")
	scene.active_receiver = -1
	check(scene.navigation_map.weather_briefing_storms.size() == scene.world.storms.size(), "New game must start with a complete weather briefing")
	var briefing_storm: Dictionary = scene.navigation_map.weather_briefing_storms[0]
	var frozen_center := Vector2(briefing_storm.center)
	var live_storm: Dictionary = scene.world.storms[0]
	scene.world.update_weather(1800.0)
	check(Vector2(scene.navigation_map.weather_briefing_storms[0].center) == frozen_center and scene.world.storm_position(live_storm) != frozen_center, "Map storm marks must remain a static snapshot while real storms move")
	scene.economy.elapsed_seconds += 1800.0
	check(scene.navigation_map.weather_briefing_age_text() == "30 мин", "Briefing age must use elapsed game time")
	scene.navigation_map.refresh_weather_briefing()
	check(Vector2(scene.navigation_map.weather_briefing_storms[0].center).is_equal_approx(scene.world.storm_position(live_storm)), "Refreshing a briefing must capture current storm positions without moving them")
	scene.map_center = Vector2(scene.navigation_map.weather_briefing_storms[0].center)
	scene.map_zoom = 8.0
	var storm_screen: Vector2 = scene.world_to_screen(scene.navigation_map.weather_briefing_storms[0].center)
	check(scene.navigation_map.weather_briefing_storm_at(storm_screen) == 0, "Hovering a mapped storm must find its briefing entry")
	var motion_text: String = scene.navigation_map.weather_briefing_motion_text(scene.navigation_map.weather_briefing_storms[0])
	check(motion_text.begins_with("≈") and motion_text.contains("° • ≈") and motion_text.ends_with(" км/ч"), "Mapped storm hover must format an approximate motion label beside its arrow")
	scene.navigation_map.toggle_weather_briefing()
	check(scene.navigation_map.weather_briefing_storm_at(storm_screen) == -1, "Hidden map storms must not retain hover interaction")
	scene.navigation_map.toggle_weather_briefing()
	var airport: Dictionary = scene.world.airports[0]
	var capture_triangle: PackedVector2Array = scene.navigation_map.ils_capture_triangle(airport, 1.0)
	var capture_forward: Vector2 = scene.world.heading_vector(airport.heading)
	var capture_far_center := (capture_triangle[1] + capture_triangle[2]) * 0.5
	var expected_capture_apex: Vector2 = Vector2(airport.position) + capture_forward * scene.FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	check(capture_triangle[0].is_equal_approx(expected_capture_apex), "ILS capture cone must begin at the far runway threshold used by signal calculations")
	check(is_equal_approx(Vector2(airport.position).distance_to(capture_far_center), scene.FlightWorldScript.ILS_RANGE_KM), "ILS capture crossbar must be centred 15 km from the airport beacon")
	check(absf((capture_triangle[2] - capture_triangle[1]).dot(capture_forward)) < 0.0001, "ILS capture crossbar must be perpendicular to the glide path")
	var expected_half_width: float = capture_triangle[0].distance_to(capture_far_center) * tan(deg_to_rad(scene.FlightWorldScript.ILS_HALF_CONE_DEG))
	check(is_equal_approx(capture_triangle[1].distance_to(capture_far_center), expected_half_width), "ILS capture sides must use the actual localizer half-cone angle")
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
	scene.map_center = Vector2(96, 96)
	for layer in scene.world.wind_layers:
		layer.from_deg = 270.0
		layer.speed_kmh = 20.0
	scene.wind_overlay_index = 1
	check(scene._wind_arrow_description() == "от 270° • 20 км/ч • 250 м", "Wind description must show FROM direction, speed and selected altitude")
	for zoom in [1.0, 2.0, 4.0, 8.0, 12.0, 16.0, 20.0, 24.0]:
		scene.map_zoom = zoom
		var centers: PackedVector2Array = scene._wind_arrow_centers(scene.map_rect())
		check(centers.size() <= 30, "Every zoom must keep the wind grid sparse")
		if not centers.is_empty():
			var arrow_center: Vector2 = centers[0]
			check(scene._wind_arrow_hovered(arrow_center), "Visible wind arrows must be hoverable at every map scale")
			check(not scene._wind_arrow_hovered(arrow_center + Vector2(0, 24)), "Empty space must not trigger wind details")
		check(not scene._wind_arrow_hovered(scene.map_rect().get_center()), "The central exclusion area must not expose hidden arrow tooltips")
		for map_position in [Vector2.ZERO, Vector2(200, 200), Vector2(83.7, 121.3)]:
			scene.map_center = map_position
			var moved_centers: PackedVector2Array = scene._wind_arrow_centers(scene.map_rect())
			check(moved_centers.size() <= 30, "Panning must keep arrows sparse; central arrows may all be hidden")
			for center in moved_centers:
				check(scene.map_rect().grow(-19.0).has_point(center), "Wind arrows must stay inside the map")
				check(center.distance_to(scene.map_rect().get_center()) > minf(scene.map_rect().size.x, scene.map_rect().size.y) * 0.25, "Wind arrows inside the central circle must be hidden")
		scene.map_center = Vector2(96, 96)
	scene.wind_overlay_index = scene.WIND_OVERLAY_ALTITUDES.size()
	var radar_rect: Rect2 = scene.map_rect()
	var label_size := Vector2(94, 14)
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var origin := radar_rect.get_center()
		var tip: Vector2 = origin + Vector2(direction) * 34.0
		var motion_label: Rect2 = scene.WeatherRadarArt.storm_motion_label_rect(radar_rect, origin, tip, label_size)
		check(motion_label.has_area() and radar_rect.encloses(motion_label), "Storm-motion label must stay inside the radar")
		check(not motion_label.intersects(Rect2(origin.min(tip), (tip-origin).abs()).grow(6.0)), "Storm-motion label must never cover its arrow")
	scene.flight.altitude_m = 637.0
	check(scene._wind_arrow_description().ends_with("637 м"), "Current-altitude layer must show actual aircraft altitude")
	scene.large_weather_radar = true
	check(not scene._wind_arrow_hovered(scene.map_rect().get_center()), "Hidden map arrows must not be interactive on radar")
	print("Radar switching, wind hover, map preservation and 1 Hz echo cache: ","FAIL" if failed else "OK")
	quit(1 if failed else 0)
