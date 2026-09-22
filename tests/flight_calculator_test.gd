extends SceneTree

const Calculator = preload("res://scripts/flight_calculator.gd")
const FlightPlanSolver = preload("res://scripts/flight_plan_solver.gd")
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight = Flight.new(World.new(424242))
	flight.state = Flight.State.FLYING
	flight.heading_deg = 0.0
	flight.speed_kmh = 180.0
	flight.current_wind_kmh = Vector2(0, 30)
	assert(is_equal_approx(flight.ground_speed_kmh(), 150))
	flight.current_wind_kmh = Vector2(40, 0)
	assert(is_equal_approx(flight.ground_speed_kmh(), Vector2(180, 40).length()))
	flight.engine_running = true
	flight.throttle = 0.5
	flight.fuel_l = 10.0
	var expected_minutes: float = flight.fuel_l / flight.fuel_flow_lpm()
	assert(is_equal_approx(flight.estimated_range_km(), expected_minutes * flight.ground_speed_kmh() / 60.0), "Range must use ground speed, including wind")
	assert(Flight.ECONOMY_ALTITUDE_MIN_M < 425.0 and Flight.ECONOMY_ALTITUDE_MAX_M > 425.0)
	assert(ThemeDB.fallback_font.get_string_size("40.0/40 л • запас 999 км", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= 180.0, "Combined fuel and range caption must fit its extended text box")
	var parameters := {"distance": 50.0, "time": 10.0, "speed": 150.0, "vertical": -2.0, "altitude": 500.0}
	var complete_plan: Dictionary = parameters.duplicate(true)
	complete_plan.merge({"track": 0.0, "heading": 0.0, "wind_from": 0.0, "wind_speed": 0.0})
	var untouched_plan: Dictionary = complete_plan.duplicate(true)
	var fixed_plan := FlightPlanSolver.solve(complete_plan, 3000.0, false, true, false)
	assert(fixed_plan.valid and is_equal_approx(fixed_plan.values.distance, 50.0) and complete_plan == untouched_plan, "The pure planner must derive airspeed without mutating its input or route length")
	var path := Calculator.calculate(parameters, "distance", 3000)
	assert(path.valid and is_equal_approx(path.values.time, 20))
	assert(is_equal_approx(path.values.altitude, 600))
	var timed := Calculator.calculate(parameters, "time", 3000)
	assert(timed.valid and is_equal_approx(timed.values.distance, 25))
	var descent := Calculator.calculate(parameters, "altitude", 1500)
	assert(descent.valid and is_equal_approx(descent.values.time, 500.0 / 60.0))
	assert(is_equal_approx(descent.values.distance, 20.8333333))
	parameters.vertical = 2.0
	assert(not Calculator.calculate(parameters, "altitude", 1500).valid)
	parameters.vertical = 0.0
	assert(not Calculator.calculate(parameters, "altitude", 1500).valid)
	parameters.speed = 0.0
	assert(not Calculator.calculate(parameters, "distance", 1500).valid)
	assert(not Calculator.calculate(parameters, "time", 1500).valid, "A calculation that would erase distance must be rejected")
	# Reconstruct the ground vector to check sign conventions and drift removal.
	for track in [0.0, 90.0, 179.0, 270.0, 359.0]:
		for wind_from in [0.0, 60.0, 180.0, 270.0]:
			var triangle := Calculator.wind_triangle(150, track, wind_from, 30)
			assert(triangle.valid)
			var velocity: Vector2 = flight.world.heading_vector(triangle.heading) * 150.0 + flight.world.heading_vector(wind_from + 180) * 30.0
			var expected: Vector2 = flight.world.heading_vector(track) * float(triangle.speed)
			assert(velocity.distance_to(expected) < 0.001, "Calculated nose heading must cancel lateral wind")
	assert(is_equal_approx(Calculator.wind_triangle(150, 90, 90, 30).speed, 120))
	assert(is_equal_approx(Calculator.wind_triangle(150, 90, 270, 30).speed, 180))
	assert(not Calculator.wind_triangle(100, 0, 90, 120).valid)
	assert(not Calculator.wind_triangle(100, 0, 0, 100).valid)
	assert(not Calculator.wind_triangle(100, 0, 0, 120).valid)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var widget = scene.flight_calculator
	widget.toggle.pressed.emit()
	await process_frame
	assert(widget.expanded and widget.body.visible)
	assert(widget.profile_buttons.size() == 4 and widget.active_profile == 0, "Calculator must expose four planning profiles")
	for profile_button in widget.profile_buttons:
		assert(widget.get_global_rect().encloses(profile_button.get_global_rect()), "Profile buttons must remain inside the calculator panel")
	widget._set_value("distance", 111.0)
	widget._select_profile(1)
	assert(widget.active_profile == 1 and is_equal_approx(widget.values.distance, widget.DEFAULT_DISTANCE_KM), "A new profile must start with a nonzero independent route")
	widget._set_value("distance", 22.0)
	widget._set_value("wind_speed", 17.0)
	widget._select_profile(0)
	assert(is_equal_approx(widget.values.distance, 111.0) and not is_equal_approx(widget.values.wind_speed, 17.0), "Switching back must restore the first profile")
	widget._select_profile(1)
	assert(is_equal_approx(widget.values.distance, 22.0) and is_equal_approx(widget.values.wind_speed, 17.0), "Each profile must preserve its complete settings")
	widget._set_value("distance", 0.0)
	assert(not widget.valid and is_equal_approx(widget.values.distance, 22.0), "A zero distance must be rejected without replacing the existing route")
	widget._select_profile(0)
	var legacy_zero_distance_snapshot: Dictionary = widget.snapshot()
	legacy_zero_distance_snapshot.profiles[3].values.distance = 0.0
	assert(widget.restore_snapshot(legacy_zero_distance_snapshot), "A legacy calculator snapshot with zero distance must remain readable")
	widget._select_profile(3)
	assert(is_equal_approx(widget.values.distance, widget.DEFAULT_DISTANCE_KM), "Restoring an old zero-distance tab must replace it with a useful nonzero route")
	widget._select_profile(0)
	var original_wind_layers: Array = scene.world.wind_layers.duplicate(true)
	scene.flight.state = Flight.State.FLYING
	scene.flight.speed_kmh = 175.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	scene.flight.heading_deg = 0.0
	scene.world.wind_layers.assign([
		{"altitude_m":0.0,"from_deg":0.0,"speed_kmh":40.0},
		{"altitude_m":250.0,"from_deg":0.0,"speed_kmh":40.0},
		{"altitude_m":500.0,"from_deg":180.0,"speed_kmh":40.0},
		{"altitude_m":700.0,"from_deg":180.0,"speed_kmh":40.0},
	])
	var northbound_optimum: Vector2 = scene.instrument_panel.optimal_altitude_range(true)
	scene.flight.heading_deg = 180.0
	var southbound_optimum: Vector2 = scene.instrument_panel.optimal_altitude_range(true)
	assert((northbound_optimum.x + northbound_optimum.y) * 0.5 > (southbound_optimum.x + southbound_optimum.y) * 0.5 + 100.0, "Optimal-altitude band must move towards the layer with the favourable along-track wind")
	var position_before_terrain_test: Vector2 = scene.flight.position_km
	var power_before_terrain_test: bool = scene.flight.electrical_power
	var terrain_point := Vector2.ZERO
	var terrain_height := -1.0
	for y in range(0, 201, 2):
		for x in range(0, 201, 2):
			var candidate_height: float = scene.world.height_at(Vector2(x, y))
			if candidate_height >= 300.0 and candidate_height <= 600.0:
				terrain_point = Vector2(x, y)
				terrain_height = candidate_height
				break
		if terrain_height >= 0.0:
			break
	assert(terrain_height >= 0.0, "Test world must contain reachable elevated terrain")
	scene.flight.electrical_power = true
	scene.flight.position_km = terrain_point
	scene.flight.altitude_m = terrain_height + 40.0
	assert(is_equal_approx(scene.instrument_panel.radio_ground_altitude_m(), terrain_height), "Altimeter ground mark must convert radio height into absolute terrain altitude")
	var altitude_readouts: Dictionary = scene.instrument_panel.altimeter_readout_texts()
	assert(altitude_readouts.barometric == "%d м" % roundi(scene.flight.altitude_m), "The first altimeter line must show the uncluttered barometric altitude")
	assert(altitude_readouts.radio == "РВ %d м" % floori(scene.flight.radio_height_m()), "The second altimeter line must include the abbreviated radio height")
	assert(altitude_readouts.ground == "ЗЕМ %d м" % roundi(terrain_height), "The second altimeter line must include absolute terrain altitude")
	var terrain_safe_optimum: Vector2 = scene.instrument_panel.optimal_altitude_range(true)
	assert(terrain_safe_optimum.x > terrain_safe_optimum.y or terrain_safe_optimum.x >= terrain_height + 50.0, "Recommended altitude band must stay at least 50 m above the radio-altimeter ground mark")
	scene.flight.electrical_power = false
	assert(scene.instrument_panel.radio_ground_altitude_m() < 0.0 and is_zero_approx(scene.instrument_panel.recommended_altitude_floor_m()), "Unpowered radio altimeter must expose neither a ground mark nor a terrain floor")
	altitude_readouts = scene.instrument_panel.altimeter_readout_texts()
	assert(altitude_readouts.radio == "РВ —" and altitude_readouts.ground == "ЗЕМ —", "Unavailable radio data must not leave a stale height or terrain reading")
	scene.flight.position_km = position_before_terrain_test
	scene.flight.electrical_power = power_before_terrain_test
	scene.flight.heading_deg = 0.0
	scene.flight.altitude_m = 250.0
	for layer in scene.world.wind_layers:
		layer.from_deg = 0.0
		layer.speed_kmh = 40.0
	var headwind_speed_range: Vector2 = scene.instrument_panel.optimal_speed_range(true)
	for layer in scene.world.wind_layers:
		layer.from_deg = 180.0
	var tailwind_speed_range: Vector2 = scene.instrument_panel.optimal_speed_range(true)
	assert((headwind_speed_range.x + headwind_speed_range.y) * 0.5 > (tailwind_speed_range.x + tailwind_speed_range.y) * 0.5 + 5.0, "Best-range speed band must move up in a headwind and down in a tailwind")
	scene.world.wind_layers.assign(original_wind_layers)
	scene.flight.altitude_m = 3000
	for layer in scene.world.wind_layers:
		layer.speed_kmh = 0.0
	widget.current_buttons.initial_altitude.pressed.emit()
	widget._set_value("wind_speed", 0.0)
	widget._set_value("speed", 150.0)
	var distance_field: LineEdit = widget.fields.distance
	distance_field.grab_focus()
	distance_field.text = "50,5"
	distance_field.text_changed.emit(distance_field.text)
	assert(is_equal_approx(widget.values.time, 20.2), "Typed numbers must recalculate immediately without Enter, including decimal commas")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	distance_field.gui_input.emit(wheel)
	assert(is_equal_approx(widget.values.distance, 51.5), "Mouse wheel must edit the field")
	scene.flight.state = Flight.State.FLYING
	scene.flight.speed_kmh = 180.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	scene.flight.vertical_speed_mps = -2.0
	widget.current_buttons.speed.pressed.emit()
	widget.current_buttons.vertical.pressed.emit()
	assert(widget.values.speed == 180.0 and widget.values.vertical == -2.0)
	assert(scene.navigation_map.measurement_time_text(36.0) == "12.0 мин", "Map-line duration must use the current 180 km/h ground speed")
	var invariant_distance: float = widget.values.distance
	widget._set_value("altitude", 1800.0)
	assert(widget.valid and is_equal_approx(widget.values.distance, invariant_distance) and is_equal_approx(widget.values.altitude, 1800.0))
	widget.fields.vertical.text_changed.emit("0")
	assert(widget.valid and widget.last_changed == "distance", "Entering zero vertical speed must keep distance as the calculation anchor")
	assert(is_equal_approx(widget.values.altitude, 3000.0) and is_equal_approx(widget.values.distance, invariant_distance), "Levelling off must preserve the planned distance")
	widget._set_value("vertical", -2.0)
	widget._set_value("altitude", 1800.0)
	scene.flight.vertical_speed_mps = 0.0
	widget.current_buttons.vertical.pressed.emit()
	assert(widget.valid and is_equal_approx(widget.values.altitude, widget.initial_altitude) and is_equal_approx(widget.values.distance, invariant_distance), "Current vertical speed button must support level flight without changing distance")
	widget._set_value("vertical", -2.0)
	widget._set_value("altitude", 1800.0)
	widget._set_value("vertical", -1.0)
	assert(widget.values.altitude > 1800.0 and is_equal_approx(widget.values.distance, invariant_distance), "Changing descent rate must recalculate height over the fixed route")
	widget.fields.vertical.text_changed.emit("2")
	assert(widget.valid and widget.last_changed == "distance")
	assert(widget.values.altitude > widget.initial_altitude and is_equal_approx(widget.values.distance, invariant_distance), "Switching from descent to climb must raise destination altitude without changing distance")
	widget._set_value("altitude", 5400.0)
	scene.flight.vertical_speed_mps = -1.0
	widget.current_buttons.vertical.pressed.emit()
	assert(widget.valid and widget.values.altitude < widget.initial_altitude and is_equal_approx(widget.values.distance, invariant_distance), "Switching from climb to descent via current speed must lower destination altitude without changing distance")
	widget._set_value("time", 5.0)
	assert(is_equal_approx(widget.values.distance, invariant_distance) and is_equal_approx(widget.values.time, 5.0), "Editing time must derive speed instead of distance")
	widget._set_value("speed", 120.0)
	assert(is_equal_approx(widget.values.distance, invariant_distance) and widget.values.time > 5.0, "Changing speed must recalculate time while preserving distance")
	widget._set_value("vertical", 0.0)
	widget._set_value("altitude", 4000.0)
	assert(widget.valid and is_equal_approx(widget.values.altitude, 4000.0) and widget.values.vertical > 0.0, "Entering a new height must derive a compatible vertical speed instead of an error")
	widget._set_value("vertical", 2.0)
	assert(widget.valid and widget.values.altitude > widget.initial_altitude and is_equal_approx(widget.values.distance, invariant_distance), "A corrected climb rate must recalculate height without changing distance")
	var fixed_calculation: Dictionary = widget.values.duplicate()
	scene.flight.altitude_m = 3400.0
	await process_frame
	assert(widget.values == fixed_calculation and widget.initial_altitude == 3000.0, "Flying must not change the planned calculation")
	widget._set_value("speed", 120.0)
	assert(widget.values == fixed_calculation, "Editing other parameters must not silently sample the aircraft altitude")
	widget.current_buttons.initial_altitude.pressed.emit()
	assert(widget.initial_altitude == 3400.0 and widget.fields.initial_altitude.text == "3400")
	assert(is_equal_approx(widget.values.altitude, float(fixed_calculation.altitude)) and is_equal_approx(widget.values.distance, invariant_distance), "Explicit altitude sampling must preserve target height and route distance while recalculating the other values")
	widget._set_value("time", 10.0)
	scene.flight.altitude_m = 3200.0
	await process_frame
	assert(is_equal_approx(widget.values.altitude, float(fixed_calculation.altitude)) and is_equal_approx(widget.values.distance, invariant_distance), "Time-based plans must remain fixed while flying")
	widget.current_buttons.initial_altitude.pressed.emit()
	assert(is_equal_approx(widget.values.altitude, float(fixed_calculation.altitude)) and is_equal_approx(widget.values.distance, invariant_distance), "Explicit sampling must preserve target height and distance and derive compatible remaining values")
	var initial_field: LineEdit = widget.fields.initial_altitude
	initial_field.text = "2100,5"
	initial_field.text_changed.emit(initial_field.text)
	assert(is_equal_approx(widget.initial_altitude, 2100.5) and is_equal_approx(widget.values.altitude, float(fixed_calculation.altitude)) and is_equal_approx(widget.values.distance, invariant_distance), "Initial altitude must apply typed decimal values without changing route distance")
	initial_field.gui_input.emit(wheel)
	assert(is_equal_approx(widget.initial_altitude, 2200.5), "Initial altitude must support the mouse wheel")
	var saved_wind: Array = scene.world.wind_layers.duplicate(true)
	scene.world.wind_layers.assign([
		{"altitude_m": 0.0, "from_deg": 90.0, "speed_kmh": 10.0},
		{"altitude_m": 2000.0, "from_deg": 270.0, "speed_kmh": 30.0},
	])
	widget._set_value("initial_altitude", 2000.0)
	scene.flight.altitude_m = 0.0
	assert(not widget.current_buttons.has("wind"), "Wind no longer needs a separate sampling button")
	assert(is_equal_approx(widget.values.wind_from, 270.0) and is_equal_approx(widget.values.wind_speed, 30.0), "Initial altitude must automatically sample BOTH wind values")
	widget._set_value("initial_altitude", 0.0)
	assert(is_equal_approx(widget.values.wind_from, 90.0) and is_equal_approx(widget.values.wind_speed, 10.0))
	initial_field.text = "2000"
	initial_field.text_changed.emit(initial_field.text)
	assert(is_equal_approx(widget.values.wind_speed, 30.0), "Typing altitude must refresh wind")
	initial_field.gui_input.emit(wheel)
	var sampled_wind: Vector2 = scene.world.wind_at(widget.initial_altitude)
	assert(is_equal_approx(widget.values.wind_speed, sampled_wind.length()), "Wheeling altitude must refresh wind")
	widget.fields.wind_from.text_changed.emit("123")
	widget.fields.wind_speed.text_changed.emit("17,5")
	widget._set_value("time", 8.0)
	await process_frame
	assert(is_equal_approx(widget.values.wind_from, 123.0) and is_equal_approx(widget.values.wind_speed, 17.5), "Manual wind must survive unrelated edits and simulation frames")
	widget.current_buttons.initial_altitude.pressed.emit()
	assert(is_equal_approx(widget.values.wind_from, 90.0) and is_equal_approx(widget.values.wind_speed, 10.0), "Current altitude button must replace manual wind with wind at aircraft altitude")
	scene.world.wind_layers.assign(saved_wind)
	widget._set_value("wind_speed", 0.0)
	# A normal click near a finished segment starts a new annotation at the
	# actual pointer position. Only beacons and existing endpoints are snap
	# targets; selecting a whole line is reserved for explicit linking mode.
	scene.map_center = Vector2(100, 100)
	var a := Vector2(90, 100)
	var b := Vector2(110, 100)
	scene.measurement_lines.clear()
	scene.measurement_lines.append({"a": a, "b": b, "max_height_m": 0.0})
	var line_midpoint: Vector2 = scene.world_to_screen((a + b) * 0.5)
	var hover_text: String = scene.navigation_map.measurement_line_description_at(line_midpoint)
	assert(hover_text.contains("20.0 км") and hover_text.contains("мин") and hover_text.contains("090° / 270°") and hover_text.contains("0 м"), "Hovering a line must repeat its distance, time, bearings and terrain height")
	assert(scene.navigation_map.measurement_line_description_at(line_midpoint + Vector2(0, 24)).is_empty(), "The map footer must not describe a line after the pointer leaves it")
	var line_motion := InputEventMouseMotion.new()
	line_motion.position = line_midpoint
	scene._handle_mouse_motion(line_motion)
	assert(scene.navigation_map.hovered_measurement_line_index == 0, "Moving onto a line must request its hover footer")
	line_motion.position += Vector2(0, 24)
	scene._handle_mouse_motion(line_motion)
	assert(scene.navigation_map.hovered_measurement_line_index == -1, "Moving off a line must clear its hover footer")
	var short_midpoint: Vector2 = scene.map_rect().get_center()
	var short_text_size := ThemeDB.fallback_font.get_string_size(hover_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var vertical_label: Vector2 = scene.navigation_map._horizontal_measurement_label_baseline(short_midpoint, Vector2(0, 12), short_text_size, scene.map_rect())
	var horizontal_label: Vector2 = scene.navigation_map._horizontal_measurement_label_baseline(short_midpoint, Vector2(12, 0), short_text_size, scene.map_rect())
	assert(vertical_label.x > short_midpoint.x and horizontal_label.y < short_midpoint.y, "Short-line labels must sit right of steep lines and above flat lines")
	scene.pending_measure = null
	var selection := InputEventMouseButton.new()
	selection.button_index = MOUSE_BUTTON_LEFT
	selection.position = scene.world_to_screen((a + b) / 2) + Vector2(0, 6)
	var expected_free_point: Vector2 = scene.navigation_map.screen_to_world(selection.position)
	selection.pressed = true
	scene._handle_mouse_button(selection)
	selection.pressed = false
	scene._handle_mouse_button(selection)
	assert(scene.pending_measure != null and Vector2(scene.pending_measure).is_equal_approx(expected_free_point) and not Vector2(scene.pending_measure).is_equal_approx((a + b) * 0.5) and scene.measurement_lines.size() == 1, "Clicking near a line must keep the free pointer position instead of snapping onto the segment")
	scene.pending_measure = null
	widget._toggle_line_link()
	assert(widget.awaiting_line_binding())
	selection.pressed = true
	scene._handle_mouse_button(selection)
	selection.pressed = false
	scene._handle_mouse_button(selection)
	assert(not widget.awaiting_line_binding() and widget.bound_line_id > 0)
	assert(widget.values.distance == 20.0 and is_equal_approx(widget.values.track, 90.0))
	assert(scene.navigation_map.measurement_line_color(true, true) == scene.navigation_map.ACTIVE_LINKED_MEASUREMENT_COLOR, "The line linked to the open calculator tab must be red")
	assert(scene.navigation_map.measurement_line_color(true, false) == scene.navigation_map.LINKED_MEASUREMENT_COLOR, "Lines linked to other calculator tabs must be orange")
	assert(scene.navigation_map.measurement_line_color(false, false) == scene.navigation_map.MEASUREMENT_COLOR, "Unlinked measurement lines must retain their blue color")
	var line_before_rejected_length: Dictionary = scene.measurement_lines[0].duplicate(true)
	widget._set_value("distance", 150.0)
	assert(not widget.valid and is_equal_approx(widget.values.distance, 20.0), "An out-of-map linked distance must be rejected instead of shortening or desynchronizing the plan")
	assert(scene.measurement_lines[0].a == line_before_rejected_length.a and scene.measurement_lines[0].b == line_before_rejected_length.b, "A rejected linked edit must leave the line untouched")
	widget._set_value("speed", 120.0)
	assert(widget.valid and is_equal_approx(widget.values.distance, 20.0))
	widget._reverse_track()
	assert(Vector2(scene.measurement_lines[0].a) == b and Vector2(scene.measurement_lines[0].b) == a and is_equal_approx(widget.values.track, 270.0), "Reversing a linked vector must swap its start and end without moving the line")
	widget._reverse_track()
	assert(Vector2(scene.measurement_lines[0].a) == a and Vector2(scene.measurement_lines[0].b) == b and is_equal_approx(widget.values.track, 90.0))
	widget._set_value("vertical", 0.0)
	widget._set_value("speed", 120.0)
	widget._set_value("wind_from", 90.0)
	widget._set_value("wind_speed", 30.0)
	assert(is_equal_approx(widget.values.time, 20.0 / 90.0 * 60.0))
	assert(is_equal_approx(widget.line_time_minutes(widget.bound_line_id), widget.values.time), "Linked line labels must use their profile's wind-aware duration")
	assert(is_equal_approx(widget.values.heading, 90.0))
	widget._set_value("wind_speed", 0.0)
	widget._set_value("time", 10.0)
	assert(widget.valid and is_equal_approx(widget.values.speed, 120.0) and is_equal_approx(widget.values.distance, 20.0), "Changing time on a linked route must derive airspeed without moving the line")
	var distance_before_current_speed: float = widget.values.distance
	var linked_line_before_current_speed: Dictionary = scene.measurement_lines[0].duplicate(true)
	scene.flight.speed_kmh = 0.0
	widget.current_buttons.speed.pressed.emit()
	assert(is_equal_approx(widget.values.distance, distance_before_current_speed), "Current speed must preserve the planned distance even when the aircraft is stopped")
	assert(scene.measurement_lines[0].a == linked_line_before_current_speed.a and scene.measurement_lines[0].b == linked_line_before_current_speed.b, "Current speed must not collapse or move a linked line")
	widget._set_value("speed", 120.0)
	widget._set_value("distance", distance_before_current_speed)
	widget._set_value("wind_from", 90.0)
	widget._set_value("wind_speed", 30.0)
	widget._set_value("track", 270.0)
	assert(is_equal_approx(widget.values.time, 20.0 / 150.0 * 60.0))
	assert(not widget.fields.has("wind_altitude"))
	widget._set_value("wind_speed", 200.0)
	widget._set_value("wind_from", 0.0)
	widget._set_value("track", 90.0)
	assert(not widget.valid and widget.fields.heading.text == "—")
	widget._set_value("wind_speed", 0.0)
	assert(widget.valid)
	widget._set_value("wind_from", 0.0)
	widget._set_value("wind_speed", 30.0)
	var heading_field: LineEdit = widget.fields.heading
	heading_field.text = "90"
	heading_field.text_changed.emit(heading_field.text)
	assert(widget.heading_based and is_equal_approx(widget.values.heading, 90.0))
	var expected_track: float = scene.world.vector_heading(Vector2(120, 30))
	assert(absf(widget.values.track - expected_track) < 0.001, "Typing a nose heading must calculate wind drift immediately")
	assert(absf(widget.values.time - 20.0 / Vector2(120, 30).length() * 60.0) < 0.001)
	widget._set_value("wind_speed", 40.0)
	assert(is_equal_approx(widget.values.heading, 90.0), "Changing wind must preserve a manually chosen heading")
	heading_field.gui_input.emit(wheel)
	assert(is_equal_approx(widget.values.heading, 91.0), "Heading must support mouse wheel input")
	scene.flight.heading_deg = 359.0
	widget.current_buttons.heading.pressed.emit()
	assert(widget.heading_based and is_equal_approx(widget.values.heading, 359.0))
	heading_field.gui_input.emit(wheel)
	assert(is_equal_approx(widget.values.heading, 0.0), "Heading wraps at north")
	widget._set_value("track", 90.0)
	assert(not widget.heading_based and widget.values.heading < 90.0, "Editing track must restore inverse wind correction")
	widget._set_value("heading", 200.0)
	var linked_start: Vector2 = scene.measurement_lines[0].a
	widget._set_value("distance", 30.0)
	assert(Vector2(scene.measurement_lines[0].a) == linked_start and is_equal_approx(Vector2(scene.measurement_lines[0].a).distance_to(scene.measurement_lines[0].b), 30.0), "Calculator distance must move only the linked vector endpoint")
	widget._set_value("track", 180.0)
	assert(Vector2(scene.measurement_lines[0].a) == linked_start and Vector2(scene.measurement_lines[0].b).distance_to(linked_start + scene.world.heading_vector(180.0) * 30.0) < 0.001, "Changing track must rotate the endpoint around the fixed start")
	scene.measurement_lines[0].b = linked_start + Vector2(0, -12)
	widget.measurement_line_changed(scene.measurement_lines[0])
	assert(is_equal_approx(widget.values.distance, 12.0) and is_equal_approx(widget.values.track, 0.0), "Editing linked geometry must update its calculator profile")
	widget._toggle_line_link()
	assert(widget.bound_line_id < 0 and widget.line_link_button.text.contains("ПРИВЯЗАТЬ"))
	scene._handle_map_click(scene.world_to_screen(b))
	assert(scene.pending_measure != null, "Endpoint click must still start a connected segment")
	scene.pending_measure = null
	distance_field.grab_focus()
	scene.flight.engine_running = false
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_M
	scene._input(key)
	assert(not scene.flight.engine_running, "Editing the calculator must not operate the aircraft")
	scene.large_weather_radar = true
	widget._process(0)
	assert(not widget.visible)
	scene.large_weather_radar = false
	widget._process(0)
	assert(widget.visible and widget.expanded)
	scene.world.storms.clear()
	scene.flight.state = Flight.State.FLYING
	scene.flight.position_km = Vector2(100, 100)
	scene.flight.altitude_m = 5000
	scene.flight.heading_deg = 0
	scene.flight.speed_kmh = 180
	scene.flight.engine_running = true
	scene.flight.throttle = 0.5
	scene.trip_air_distance_km = 0
	scene.trip_elapsed_seconds = 0
	var trip_start: Vector2 = scene.flight.position_km
	scene._process(1.0)
	var actual_ground_path: float = trip_start.distance_to(scene.flight.position_km)
	assert(absf(scene.trip_air_distance_km - actual_ground_path) < 0.0001, "Clock trip counter must integrate actual ground displacement")
	assert(is_equal_approx(scene.trip_elapsed_seconds, 1.0), "Clock trip time must advance with the integrated ground path")
	# Every tab follows the same strict ownership rule: only its distance field or
	# linked geometry may replace route length; every other parameter derives.
	for profile_index in 4:
		widget._select_profile(profile_index)
		var owned_distance := 31.0 + float(profile_index)
		widget._set_value("wind_speed", 0.0)
		widget._set_value("track", 0.0)
		widget._set_value("speed", 150.0)
		widget._set_value("distance", owned_distance)
		widget._set_value("time", 12.0)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Editing time must preserve distance in every tab")
		widget._set_value("speed", 135.0)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Editing speed must preserve distance in every tab")
		widget._set_value("vertical", 1.5)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Editing vertical speed must preserve distance in every tab")
		widget._set_value("altitude", widget.initial_altitude + 250.0)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Editing target altitude must preserve distance in every tab")
		widget._set_value("initial_altitude", widget.initial_altitude + 10.0)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Editing initial altitude must preserve distance in every tab")
		widget._set_value("heading", 5.0)
		widget._set_value("wind_from", 180.0)
		widget._set_value("wind_speed", 12.0)
		assert(is_equal_approx(widget.values.distance, owned_distance), "Navigation and wind edits must preserve distance in every tab")
	print("Flight calculator, wind-aware range and clock ground-path counter: OK")
	quit()
