extends SceneTree

var failed := false
var scene

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func button(point: Vector2, pressed: bool, which := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = which
	event.pressed = pressed
	scene._handle_mouse_button(event)

func click_world(point: Vector2, which := MOUSE_BUTTON_LEFT) -> void:
	var pixel: Vector2 = scene._measurement_to_screen(point)
	button(pixel, true, which)
	button(pixel, false, which)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	check(scene._trajectory_overlay_visible(), "A new game must show the known aircraft position at the departure airfield")
	scene.flight.state = scene.FlightModelScript.State.FLYING
	check(not scene._trajectory_overlay_visible(), "Live aircraft position must remain hidden after departure")
	scene.trajectory_finished = true
	check(not scene._trajectory_overlay_visible(), "A final trajectory must remain hidden while the aircraft is in flight")
	scene.flight.state = scene.FlightModelScript.State.LANDED
	check(scene._trajectory_overlay_visible(), "A finished flight must show its trajectory and final aircraft position on the ground")
	check(scene._map_aircraft_visible(), "A finished flight must show its final aircraft position")
	button(scene.get_trajectory_button_rect().get_center(), true)
	check(not scene._trajectory_overlay_visible(), "The final trajectory button must hide the completed route")
	check(scene._map_aircraft_visible(), "Hiding the completed route must keep the final aircraft position visible")
	button(scene.get_trajectory_button_rect().get_center(), true)
	check(scene._trajectory_overlay_visible(), "The final trajectory button must show the completed route again")
	scene.trajectory_finished = false
	scene.flight.state = scene.FlightModelScript.State.PARKED
	scene.flight.electrical_power = true
	scene.flight.engine_running = true
	scene.flight.position_km = Vector2(50,50)
	scene.flight.heading_deg = 0.0
	scene.flight.speed_kmh = 180.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	scene.simulation_paused = true
	scene._toggle_weather_radar()
	var scope_center: Vector2 = scene.WeatherRadarArt.scope_center(scene.map_rect())
	click_world(scene.flight.position_km + Vector2(5, 0))
	check(scene.radar_measurement_lines.is_empty(), "A radar course line must start only from a click on the aircraft")
	click_world(scene.flight.position_km)
	check(scene.radar_measurement_lines.size() == 1 and scene.radar_pending_measure == null, "Clicking the radar aircraft must create one complete course line")
	var course_line: Dictionary = scene.radar_measurement_lines[0]
	check(Vector2(course_line.a).is_equal_approx(scene.flight.position_km), "The course line must start at the aircraft position")
	check(is_equal_approx(Vector2(course_line.a).distance_to(course_line.b), 30.0), "The course line must extend exactly 30 km")
	check(Vector2(course_line.b).is_equal_approx(scene.flight.position_km + scene.world.heading_vector(0.0) * 30.0), "Without wind the course line must follow the aircraft heading")
	var original_course_line: Dictionary = course_line.duplicate(true)
	click_world(scene.flight.position_km)
	check(scene.radar_measurement_lines.size() == 1 and scene.radar_measurement_lines[0] == original_course_line, "A second radar line must not be created while the first exists")
	var guidance: Dictionary = scene.navigation_map.radar_course_guidance()
	check(is_zero_approx(guidance.lateral_km) and is_zero_approx(guidance.course_error_deg), "A newly created course line must start with centred guidance")
	scene.flight.position_km += Vector2(2, 0)
	scene.flight.heading_deg = 10.0
	guidance = scene.navigation_map.radar_course_guidance()
	check(is_equal_approx(guidance.lateral_km, 2.0), "Guidance must report the aircraft to the right of a northbound line")
	check(is_equal_approx(guidance.course_error_deg, 10.0), "Guidance must report the signed difference between current and reference courses")
	click_world((Vector2(course_line.a) + Vector2(course_line.b)) * 0.5, MOUSE_BUTTON_RIGHT)
	check(scene.radar_measurement_lines.is_empty(), "Right click on the course line must delete it")
	scene.flight.heading_deg = 90.0
	scene.flight.current_wind_kmh = Vector2(0, -45)
	click_world(scene.flight.position_km)
	check(scene.radar_measurement_lines.size() == 1, "Deleting the old course line must permit creating a new one")
	var expected_ground_direction: Vector2 = (scene.world.heading_vector(90.0) * scene.flight.speed_kmh + scene.flight.current_wind_kmh).normalized()
	var regenerated_direction: Vector2 = (Vector2(scene.radar_measurement_lines[0].b) - Vector2(scene.radar_measurement_lines[0].a)).normalized()
	check(regenerated_direction.is_equal_approx(expected_ground_direction), "The course line must use the current wind-aware ground track")
	var saved: Array = scene.radar_measurement_lines.duplicate(true)
	var saved_endpoint: Vector2 = saved[0].b
	var old_screen: Vector2 = scene._measurement_to_screen(saved_endpoint)
	scene.flight.heading_deg = 120.0
	check(not old_screen.is_equal_approx(scene._measurement_to_screen(saved_endpoint)), "Heading rotates display, not stored points")
	check(scene._measurement_from_screen(scene._measurement_to_screen(saved_endpoint)).is_equal_approx(saved_endpoint), "Projection round trip at nonzero heading")
	scene.flight.position_km += Vector2(1,0)
	check(scene.radar_measurement_lines == saved, "Aircraft motion must not move world annotations")
	scene._toggle_weather_radar()
	check(scene.measurement_lines.is_empty(), "Radar lines must not appear on navigation map")
	check(scene.radar_measurement_lines == saved, "Switching views must preserve the separate radar course line")
	scene._handle_map_click(scene.world_to_screen(Vector2(20,20)))
	scene._handle_map_click(scene.world_to_screen(Vector2(30,20)))
	check(scene.measurement_lines.size() == 1 and scene.radar_measurement_lines == saved, "Map edits must not affect radar lines")
	scene._toggle_weather_radar()
	var clipped = scene.WeatherRadarArt.clip_segment(Vector2(-50,0),Vector2(50,0),Vector2.ZERO,30.0)
	check(clipped.size() == 2 and clipped[0].is_equal_approx(Vector2(-30,0)) and clipped[1].is_equal_approx(Vector2(30,0)), "Segment crossing scope must appear even with both endpoints outside")
	check(scene.WeatherRadarArt.clip_segment(Vector2(-50,40),Vector2(50,40),Vector2.ZERO,30.0).is_empty(), "Outside segment must remain invisible")
	var probe: Vector2 = scene.flight.position_km + Vector2(1,0)
	var distance_at_30: float = scene._measurement_to_screen(probe).distance_to(scope_center)
	for i in 5:
		button(scope_center, true, MOUSE_BUTTON_WHEEL_UP)
	check(scene.radar_range_index == 3, "Zoom in must stop at 5 km")
	check(is_equal_approx(scene._measurement_to_screen(probe).distance_to(scope_center), distance_at_30 * 6.0), "5 km scope must magnify world geometry sixfold")
	check(scene._measurement_from_screen(scene._measurement_to_screen(probe)).is_equal_approx(probe), "Zoomed coordinate transform must remain invertible")
	check(scene.radar_measurement_lines == saved, "Zoom must not alter annotations")
	for i in 5:
		button(scope_center, true, MOUSE_BUTTON_WHEEL_DOWN)
	check(scene.radar_range_index == 0, "Zoom out must stop at default 30 km")
	var retained_line: Dictionary = scene.radar_measurement_lines[0]
	var retained_direction: Vector2 = (Vector2(retained_line.b) - Vector2(retained_line.a)).normalized()
	scene.flight.position_km = Vector2(retained_line.b) + retained_direction * 10.0
	scene.navigation_map.update_dynamic_annotations(0.0)
	check(retained_line in scene.radar_measurement_lines, "A radar line must remain while either endpoint is within 30 km")
	scene.flight.position_km = Vector2(retained_line.b) + retained_direction * 31.0
	scene.navigation_map.update_dynamic_annotations(0.0)
	check(scene.radar_measurement_lines.is_empty(), "A radar line must be removed after both endpoints leave the 30 km retention radius")
	print("Radar annotations and zoom: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
