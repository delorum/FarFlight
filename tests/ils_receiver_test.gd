extends SceneTree

const ILSDisplayArt = preload("res://scripts/ils_display_art.gd")
const ILSDisplayState = preload("res://scripts/ils_display_state.gd")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var airport: Dictionary = game.world.airports[0]
	var departure_frequency := int(game.world.beacons[0].frequency)
	check(game.receiver_frequencies == [departure_frequency, departure_frequency], "Both receivers must start tuned to the departure airport")
	var forward: Vector2 = game.world.heading_vector(airport.heading)
	game.flight.position_km = Vector2(airport.position) - forward * 6.0
	game.flight.altitude_m = 230.0
	game.flight.heading_deg = airport.heading
	game.receiver_frequencies[0] = int(game.world.beacons[0].frequency)
	game.receiver_frequencies[1] = int(game.world.beacons[3].frequency)
	game._update_receiver_signals()
	game._update_ils_touchdown_prediction()
	check(game.ils_airport_index == 0, "Receiver 1 runway frequency must select that airport")
	check(game.ils_signal_status.get("available", false), "ILS must work on receiver 1 runway frequency inside the approach cone")
	check(game._ils_title() == "ILS %03d кГц" % int(game.world.beacons[0].frequency), "ILS title must contain only its name and receiver 1 frequency")
	game.flight.electrical_power = true
	var display_state: Dictionary = game.ils_display_state()
	check(display_state.signal_available and display_state.title == game._ils_title(), "Both ILS sizes must use the same available signal and tuned frequency")
	check(display_state.course_text == "ОТКЛ. ПУТИ %+.1f°" % float(display_state.guidance.course_error_deg), "Both ILS sizes must use the same course readout")
	check(display_state.descent_angle_text == "УГОЛ —", "Descent angle must be unavailable while the aircraft is parked")
	var target_sink := -tan(deg_to_rad(FlightModel.GLIDE_SLOPE_DEG)) * 92.0 / 3.6
	var target_angle := ILSDisplayState.descent_angle_deg(target_sink, 92.0)
	check(is_equal_approx(target_angle, FlightModel.GLIDE_SLOPE_DEG), "The target descent angle must use along-runway ground speed")
	check(ILSDisplayState.descent_angle_deg(target_sink, 72.0) > target_angle, "Headwind must steepen the actual angle at the same vertical speed")
	check(ILSDisplayState.descent_angle_color(target_angle) == ILSDisplayState.GREEN, "A target-angle descent must be green")
	check(ILSDisplayState.descent_angle_color(4.0) == ILSDisplayState.YELLOW and ILSDisplayState.descent_angle_color(5.0) == ILSDisplayState.RED, "Steep descent angles must progress from yellow to red")
	check(ILSDisplayState.descent_angle_color(2.0) == ILSDisplayState.TEXT, "A shallow descent must not misleadingly appear correct")

	var before_click: int = game.ils_airport_index
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.get_ils_rect().get_center()
	game._handle_mouse_button(click)
	check(game.ils_airport_index == before_click, "Clicking ILS must not switch airports")
	check(game.large_ils, "Clicking the small ILS must open the large display")
	game._handle_mouse_button(click)
	check(not game.large_ils, "Clicking the small ILS again must return to the map")
	game._toggle_weather_radar()
	check(game.large_weather_radar and not game.large_ils, "Opening the weather radar must close large ILS")
	game._toggle_large_ils()
	check(game.large_ils and not game.large_weather_radar, "Opening large ILS must close the weather radar")
	await process_frame
	game._toggle_large_ils()

	game.flight.speed_kmh = 100.0
	game.flight.vertical_speed_mps = -1.5
	game.flight.current_wind_kmh = Vector2.ZERO
	var prediction: Dictionary = game.flight.touchdown_prediction(0)
	check(prediction.valid and prediction.has("cross_track_km"), "Touchdown prediction must include lateral FPM displacement")
	check(absf(float(prediction.cross_track_km)) < 0.001, "A centred no-wind approach must predict a centred touchdown")
	var projection := Rect2(0, 0, 400, 400)
	var large_display_rect := Rect2(18, 20, 1884, 664)
	var large_layout: Dictionary = ILSDisplayArt.display_layout(large_display_rect)
	check(Vector2(large_layout.scope.get_center()).is_equal_approx(large_display_rect.get_center()), "The large ILS projection window must be centred in the whole display")
	check(large_layout.left_info.end.x < large_layout.scope.position.x and large_layout.right_info.position.x > large_layout.scope.end.x, "Unframed ILS readouts must stay immediately beside the central projection window")
	var centred_guidance := {"actual_distance_to_threshold_km": 8.0, "localizer_error": 0.0, "glide_error": 0.0}
	var displaced_guidance := {"actual_distance_to_threshold_km": 8.0, "localizer_error": 1.0, "glide_error": -1.0}
	var centred_runway: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, centred_guidance)
	var displaced_runway: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, displaced_guidance)
	check(Vector2(centred_runway.near_left).is_equal_approx(Vector2(displaced_runway.near_left)), "Localizer and glide deviation must not move the fixed runway")
	var small_ils_view := Rect2(0, 0, 82, 35)
	var right_of_runway := {"localizer_error": -1.2, "glide_error": 0.0, "course_error_deg": -5.1}
	var small_aircraft_marker: Vector2 = ILSDisplayArt.localizer_marker_position(small_ils_view, right_of_runway)
	var large_aircraft_marker: Vector2 = ILSDisplayArt.localizer_marker_position(projection, right_of_runway)
	check(small_aircraft_marker.x > small_ils_view.get_center().x and large_aircraft_marker.x > projection.get_center().x, "The aircraft cross must be right of the runway in both ILS sizes even when tracking left")
	check(ILSDisplayArt.localizer_marker_position(projection, {"localizer_error": 1.2, "glide_error": 0.0}).x < projection.get_center().x, "Positive localizer error must place the aircraft cross left in both ILS sizes")
	var distant_runway: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, {"actual_distance_to_threshold_km": 5.5, "aircraft_altitude_m": 234.0})
	check(float(distant_runway.near_half) < projection.size.x * 0.05 and float(distant_runway.near_y) - float(distant_runway.far_y) < projection.size.y * 0.08, "A runway more than 5 km away must retain a small realistic angular size")
	var centred_nose: Vector2 = ILSDisplayArt.nose_marker_position(projection, {"heading_error_deg": 0.0, "aircraft_pitch_deg": -3.3})
	var right_nose: Vector2 = ILSDisplayArt.nose_marker_position(projection, {"heading_error_deg": 4.0, "aircraft_pitch_deg": -3.3})
	var raised_nose: Vector2 = ILSDisplayArt.nose_marker_position(projection, {"heading_error_deg": 0.0, "aircraft_pitch_deg": 1.0})
	check(centred_nose.is_equal_approx(projection.get_center()), "The nose marker must be centred when aligned with the runway and display sightline")
	check(right_nose.x > centred_nose.x, "A nose pointed right of runway heading must move the marker right")
	check(raised_nose.y < centred_nose.y, "Raising the nose must move its marker upward")
	var centred_flight_path: Vector2 = ILSDisplayArt.flight_path_marker_position(projection, {"course_error_deg": 0.0, "flight_path_angle_deg": -3.3})
	var right_climbing_flight_path: Vector2 = ILSDisplayArt.flight_path_marker_position(projection, {"course_error_deg": 4.0, "flight_path_angle_deg": 1.0})
	check(centred_flight_path.is_equal_approx(projection.get_center()), "The flight-path marker must be centred when moving along runway heading and glideslope")
	check(right_climbing_flight_path.x > centred_flight_path.x and right_climbing_flight_path.y < centred_flight_path.y, "The flight-path marker must follow the aircraft's actual horizontal and vertical movement")
	var centred_touchdown := {"valid": true, "distance_from_threshold_km": 0.5, "cross_track_km": 0.0}
	var lateral_touchdown := {"valid": true, "distance_from_threshold_km": 0.5, "cross_track_km": 0.01}
	var farther_touchdown := {"valid": true, "distance_from_threshold_km": 1.0, "cross_track_km": 0.0}
	var centred_marker: Vector2 = ILSDisplayArt.touchdown_cross_position(projection, centred_guidance, centred_touchdown)
	var same_marker_with_deviation: Vector2 = ILSDisplayArt.touchdown_cross_position(projection, displaced_guidance, centred_touchdown)
	check(centred_marker.is_equal_approx(same_marker_with_deviation), "The separate touchdown marker must follow the prediction rather than raw ILS needle errors")
	check(ILSDisplayArt.touchdown_cross_position(projection, centred_guidance, lateral_touchdown).x > centred_marker.x, "A right-of-centre touchdown must move the FPM right")
	check(ILSDisplayArt.touchdown_cross_position(projection, centred_guidance, farther_touchdown).y < centred_marker.y, "A touchdown farther along the runway must move the FPM toward the far end")
	var near_runway: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, {"actual_distance_to_threshold_km": 1.0, "localizer_error": 0.0, "glide_error": 0.0})
	check(float(near_runway.near_half) > float(centred_runway.near_half), "The fixed runway must grow as the aircraft approaches")
	var before_threshold: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": 0.40, "actual_distance_to_threshold_km": 0.40, "aircraft_altitude_m": 50.0})
	var crossing_threshold: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": 0.05, "actual_distance_to_threshold_km": 0.05, "aircraft_altitude_m": 50.0})
	var past_threshold: Dictionary = ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": -0.05, "actual_distance_to_threshold_km": 0.05, "aircraft_altitude_m": 50.0})
	check(not bool(before_threshold.near_clipped) and bool(crossing_threshold.near_clipped) and bool(past_threshold.near_clipped), "The near threshold must leave through the projection boundary instead of reappearing behind the aircraft")
	check(float(before_threshold.far_half) < float(crossing_threshold.far_half) and float(crossing_threshold.far_half) < float(past_threshold.far_half), "The far runway end must continue approaching across threshold passage")
	check(float(before_threshold.far_y) < float(crossing_threshold.far_y) and float(crossing_threshold.far_y) < float(past_threshold.far_y), "The far runway end must not reverse direction or flatten at threshold passage")
	var centreline_far: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(before_threshold)
	var centreline_near: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": 0.30, "aircraft_altitude_m": 50.0}))
	var distant_centreline: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(distant_runway)
	check(not distant_centreline.is_empty(), "The centreline must remain visible on a distant runway")
	if not distant_centreline.is_empty():
		check(distant_centreline.size() == centreline_far.size(), "Distant markings must keep every fixed runway dash instead of swapping a sparse selection")
		check(float(distant_centreline[-1].along_start_km) > FlightWorld.RUNWAY_LENGTH_KM - 0.25, "Distant centreline marks must cover the far end of the runway")
		check(Vector2(distant_centreline[-1].near_point).y - Vector2(distant_centreline[-1].far_point).y >= ILSDisplayArt.CENTERLINE_MIN_MARK_PX, "Subpixel distant marks must remain visible")
	check(not centreline_far.is_empty() and not centreline_near.is_empty(), "Approaching runway must show centreline dashes")
	if not centreline_far.is_empty() and not centreline_near.is_empty():
		check(centreline_far.size() == centreline_near.size(), "Every painted dash must persist during the approach")
		check(is_equal_approx(float(centreline_far[0].along_start_km), float(centreline_near[0].along_start_km)), "The same first dash must stay anchored to the runway")
		check(Vector2(centreline_near[0].near_point).y > Vector2(centreline_far[0].near_point).y, "A fixed dash must move down as the aircraft approaches")
		for index in mini(centreline_far.size(), centreline_near.size()):
			check(is_equal_approx(float(centreline_far[index].along_start_km), float(centreline_near[index].along_start_km)) and Vector2(centreline_near[index].near_point).y > Vector2(centreline_far[index].near_point).y, "Every fixed dash must scroll toward the pilot instead of vanishing or being replaced")
	var centreline_past: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": -0.30, "aircraft_altitude_m": 50.0}))
	check(not centreline_past.is_empty() and float(centreline_past[0].along_start_km) > ILSDisplayArt.CENTERLINE_FIRST_KM, "Dashes already behind the aircraft must disappear")
	var rollout_far: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": -0.30, "aircraft_altitude_m": 2.0}))
	var rollout_near: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": -0.40, "aircraft_altitude_m": 2.0}))
	var tracked_rollout_dash_start := ILSDisplayArt.CENTERLINE_FIRST_KM + 10 * ILSDisplayArt.CENTERLINE_PERIOD_KM
	var tracked_far_y := -INF
	var tracked_near_y := -INF
	for dash in rollout_far:
		if is_equal_approx(float(dash.along_start_km), tracked_rollout_dash_start):
			tracked_far_y = Vector2(dash.near_point).y
	for dash in rollout_near:
		if is_equal_approx(float(dash.along_start_km), tracked_rollout_dash_start):
			tracked_near_y = Vector2(dash.near_point).y
	check(tracked_far_y > -INF and tracked_near_y > tracked_far_y, "A painted dash must visibly move back toward the pilot during runway rollout")
	var centreline_after_runway: Array[Dictionary] = ILSDisplayArt.projected_centerline_dashes(ILSDisplayArt.projected_runway_geometry(projection, {"signed_distance_to_threshold_km": -2.10, "aircraft_altitude_m": 2.0}))
	check(centreline_after_runway.is_empty(), "No centreline dash may reappear after passing the runway")

	game.receiver_frequencies[0] = int(game.world.beacons[game.world.airports.size()].frequency)
	game._update_receiver_signals()
	check(game._selected_ils_airport_index() == -1, "Route NDB on receiver 1 must not select ILS")
	check(not game.ils_signal_status.get("available", false), "Route NDB on receiver 1 must disable ILS")

	game.receiver_frequencies[0] = int(game.world.beacons[0].frequency)
	game.receiver_frequencies[1] = int(game.world.beacons[1].frequency)
	game._update_receiver_signals()
	check(game.ils_airport_index == 0 and game.ils_signal_status.get("available", false), "Receiver 2 must not control ILS")

	game.receiver_frequencies = [300, 400]
	game._prepare_from_operations(true)
	check(game.receiver_frequencies == [departure_frequency, departure_frequency], "Preparing either runway direction must retune both receivers to its airport")
	game.ils_touchdown_prediction = {"valid": true, "distance_from_threshold_km": 0.5, "cross_track_km": 0.0}
	game._process(0.0)
	check(not bool(game.ils_touchdown_prediction.valid), "Touchdown prediction must disappear immediately outside the flying state")
	check(not bool(game.ils_display_state().show_forecast), "Both ILS sizes must hide forecast readouts outside flight")

	print("ILS receiver binding, flight-path/nose markers, touchdown prediction and automatic airport selection: OK")
	quit(1 if failed else 0)
