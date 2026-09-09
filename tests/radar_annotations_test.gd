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

func drag_world(from: Vector2, to: Vector2) -> void:
	button(scene._measurement_to_screen(from), true)
	var motion := InputEventMouseMotion.new()
	motion.position = scene._measurement_to_screen(to)
	scene._handle_mouse_motion(motion)
	button(motion.position, false)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.flight.engine_running = true
	scene.flight.position_km = Vector2(50,50)
	scene.flight.heading_deg = 0.0
	scene.simulation_paused = true
	scene._toggle_weather_radar()
	var a := Vector2(45,40)
	var b := Vector2(52,35)
	var c := Vector2(60,40)
	click_world(a)
	check(scene.radar_pending_measure != null, "First radar click starts a line, even paused")
	click_world(b)
	check(scene.radar_measurement_lines.size() == 1 and scene.radar_pending_measure == null, "Second click completes the shared line")
	check(Vector2(scene.radar_measurement_lines[0].a).is_equal_approx(a), "Endpoints are stored in world coordinates")
	click_world(b + Vector2(0.05,0.05))
	click_world(c)
	check(Vector2(scene.radar_measurement_lines[1].a).is_equal_approx(b), "New line snaps to existing endpoint")
	var moved := Vector2(51,38)
	drag_world(b, moved)
	check(Vector2(scene.radar_measurement_lines[0].b).is_equal_approx(moved) and Vector2(scene.radar_measurement_lines[1].a).is_equal_approx(moved), "Connected lines must drag together")
	check(scene.radar_measurement_lines[0].max_height_m == -1.0, "Radar edits must not calculate terrain heights")
	# Release near an unrelated endpoint, then drag the resulting shared node.
	scene.radar_measurement_lines.append({"a":Vector2(42,45),"b":Vector2(40,40),"max_height_m":0.0})
	drag_world(a, Vector2(42.04,45))
	check(Vector2(scene.radar_measurement_lines[0].a).is_equal_approx(Vector2(42,45)), "Released endpoint must stick to another line")
	drag_world(Vector2(42,45), Vector2(43,43))
	check(Vector2(scene.radar_measurement_lines[0].a).is_equal_approx(scene.radar_measurement_lines[2].a), "Snapped lines remain connected on subsequent drag")
	click_world(Vector2(55,50))
	click_world(Vector2(56,50), MOUSE_BUTTON_RIGHT)
	check(scene.radar_pending_measure == null and scene.radar_measurement_lines.size() == 3, "Right click cancels preview without deleting existing lines")
	click_world((moved + c) * 0.5, MOUSE_BUTTON_RIGHT)
	check(scene.radar_measurement_lines.size() == 2, "Right click on segment deletes it")
	var saved: Array = scene.radar_measurement_lines.duplicate(true)
	var old_screen: Vector2 = scene._measurement_to_screen(moved)
	scene.flight.heading_deg = 90.0
	check(not old_screen.is_equal_approx(scene._measurement_to_screen(moved)), "Heading rotates display, not stored points")
	check(scene._measurement_from_screen(scene._measurement_to_screen(moved)).is_equal_approx(moved), "Projection round trip at nonzero heading")
	scene.flight.position_km += Vector2(1,0)
	check(scene.radar_measurement_lines == saved, "Aircraft motion must not move world annotations")
	scene._toggle_weather_radar()
	check(scene.measurement_lines.is_empty(), "Radar lines must not appear on navigation map")
	check(scene.radar_measurement_lines == saved, "Switching views must preserve separate radar lines")
	scene._handle_map_click(scene.world_to_screen(Vector2(20,20)))
	scene._handle_map_click(scene.world_to_screen(Vector2(30,20)))
	check(scene.measurement_lines.size() == 1 and scene.radar_measurement_lines == saved, "Map edits must not affect radar lines")
	scene._toggle_weather_radar()
	var clipped = scene.WeatherRadarArt.clip_segment(Vector2(-50,0),Vector2(50,0),Vector2.ZERO,30.0)
	check(clipped.size() == 2 and clipped[0].is_equal_approx(Vector2(-30,0)) and clipped[1].is_equal_approx(Vector2(30,0)), "Segment crossing scope must appear even with both endpoints outside")
	check(scene.WeatherRadarArt.clip_segment(Vector2(-50,40),Vector2(50,40),Vector2.ZERO,30.0).is_empty(), "Outside segment must remain invisible")
	var scope_center: Vector2 = scene.WeatherRadarArt.scope_center(scene.map_rect())
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
	print("Radar annotations and zoom: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
