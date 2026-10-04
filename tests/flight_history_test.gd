extends SceneTree

const FlightWorld = preload("res://scripts/world.gd")
const FlightModel = preload("res://scripts/flight_model.gd")
const FlightHistory = preload("res://scripts/flight_history.gd")
const SaveGame = preload("res://scripts/save_game.gd")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := FlightWorld.new(7182)
	var flight := FlightModel.new(world)
	var history := FlightHistory.new()
	flight.airport_index = 0
	flight.position_km = Vector2(10, 10)
	flight.state = FlightModel.State.FLYING
	history.update(flight, FlightModel.State.ROLLING, flight.position_km, 101.0, 1.0)
	check(history.active and history.active_origin == 0 and is_equal_approx(history.active_start_seconds, 100.0), "Liftoff must begin one active flight at the departure airport")
	var previous := flight.position_km
	flight.position_km += Vector2(3, 4)
	history.update(flight, FlightModel.State.FLYING, previous, 111.0, 10.0)
	flight.state = FlightModel.State.ROLLING
	previous = flight.position_km
	flight.position_km += Vector2(0, 5)
	history.update(flight, FlightModel.State.FLYING, previous, 121.0, 10.0)
	check(history.active and history.records.is_empty() and is_equal_approx(history.active_distance_km, 10.0), "Touchdown and rollout must retain the active flight and airborne ground distance")
	flight.state = FlightModel.State.FLYING
	history.update(flight, FlightModel.State.ROLLING, flight.position_km, 126.0, 5.0)
	check(is_equal_approx(history.active_start_seconds, 100.0), "Touch-and-go must not start a second flight")
	previous = flight.position_km
	flight.position_km += Vector2(6, 8)
	history.update(flight, FlightModel.State.FLYING, previous, 146.0, 20.0)
	flight.airport_index = 1
	flight.state = FlightModel.State.LANDED
	history.update(flight, FlightModel.State.ROLLING, flight.position_km, 151.0, 5.0)
	check(not history.active and history.records.size() == 1, "A full stop at an airport must complete exactly one flight")
	var first: Dictionary = history.records[0]
	check(first.origin == 0 and first.destination == 1 and is_equal_approx(first.distance_km, 20.0), "Completed history row must store airports and flown distance")
	check(is_equal_approx(first.duration_seconds, 51.0) and first.start_seconds == 100.0 and first.end_seconds == 151.0, "Completed history row must store exact game timestamps and duration")
	history.records.append({"origin": 0, "destination": 1, "distance_km": 18.0, "duration_seconds": 42.0, "start_seconds": 500.0, "end_seconds": 542.0})
	var route := history.route_records(0, 1)
	check(history.route_count(0, 1) == 2 and route.size() == 2 and route[0].duration_seconds == 42.0 and route[1].duration_seconds == 51.0, "Repeated route flights must sort from the fastest record to the slowest")
	var index_builds := history.route_index_build_count
	for lookup in 1000:
		check(history.route_count(0, 1, 0) == 2, "Cached route counts must match journal records")
	check(history.route_index_build_count == index_builds, "Repeated UI queries must not rebuild the route index")
	history.active = true
	history.active_origin = 1
	history.active_start_seconds = 800.0
	history.active_distance_km = 12.5
	var snapshot := history.snapshot()
	var restored := FlightHistory.new()
	check(FlightHistory.valid_snapshot(snapshot, world.airports.size()) and restored.restore_snapshot(snapshot, world.airports.size()) and restored.snapshot() == snapshot, "Completed and airborne flight history must survive a save round trip")
	check(restored.route_count(0, 1, 0) == 2, "Loading must rebuild route counts from the restored journal")
	restored.reset()
	check(restored.route_count(0, 1, 0) == 0, "Resetting must invalidate cached route counts")
	var cross_world := FlightHistory.new()
	world.level_index = 0
	flight.state = FlightModel.State.FLYING
	flight.airport_index = 0
	cross_world.update(flight, FlightModel.State.ROLLING, flight.position_km, 201.0, 1.0)
	cross_world.active_distance_km = 12.0
	cross_world.add_world_transition(0, 1, 250.0)
	world.level_index = 1
	previous = flight.position_km
	flight.position_km += Vector2(3, 4)
	cross_world.update(flight, FlightModel.State.FLYING, previous, 290.0, 1.0)
	flight.airport_index = 2
	flight.state = FlightModel.State.LANDED
	cross_world.update(flight, FlightModel.State.ROLLING, flight.position_km, 300.0, 1.0)
	check(cross_world.records.size() == 1 and cross_world.records[0].level == 0 and cross_world.records[0].destination_level == 1 and cross_world.records[0].duration_seconds == 100.0 and cross_world.records[0].distance_km == 17.0, "A cross-world flight must remain one complete timed record including distance from both worlds")
	check(cross_world.route_count(0, 2, 0) == 0 and cross_world.route_count(0, 2, 0, 1) == 1, "Cross-world records must not mix with local route records")
	check(cross_world.journal_rows().size() == 2 and cross_world.journal_rows()[0].kind == "world_transition", "The chronological journal must include the transition before the later completed flight")
	var old_snapshot: Dictionary = snapshot.duplicate(true)
	old_snapshot.erase("transitions")
	old_snapshot.erase("active_origin_name")
	var legacy := FlightHistory.new()
	check(legacy.restore_snapshot(old_snapshot), "Older flight-history saves must remain compatible")
	legacy.recover_legacy_transitions(1, 900.0)
	check(legacy.transitions.size() == 1 and not legacy.transitions[0].time_known, "Old transition times must be marked unknown, not fabricated")
	var bad_snapshot: Dictionary = cross_world.snapshot()
	bad_snapshot.transitions[0].time_seconds = INF
	check(not FlightHistory.valid_snapshot(bad_snapshot), "Non-finite crossing timestamps must invalidate a history snapshot")

	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.side_scenes.history_selected = 3
	check(scene.side_scenes.history_view.history_selected == 3, "History selection must have one owner in the extracted view")
	scene.side_scenes.history_view.history_selected = 0
	check(scene.side_scenes.history_selected == 0, "Compatibility accessors must not keep a second selection")
	var sample := {"distance_km": 75.0, "duration_seconds": 1800.0, "start_seconds": 0.0, "end_seconds": 1800.0}
	check(scene.side_scenes._format_history_details(sample).contains("00:30:00 • СР. 150.0 км/ч"), "History must show distance divided by elapsed hours directly after duration")
	sample.duration_seconds = 0.0
	check(scene.side_scenes._format_history_details(sample).contains("СР. — км/ч"), "A zero-duration history record must not divide by zero")
	sample.distance_km = 1.0
	sample.duration_seconds = 5.4
	check(scene.side_scenes._format_history_details(sample).contains("СР. 666.7 км/ч"), "Average speed must use the stored duration, including fractional seconds")
	check(scene.side_scenes._format_history_timestamp(0.0) == "день 1 00:00:00", "The first history timestamp must match the initial midnight clock")
	check(scene.side_scenes._format_history_timestamp(86399.9) == "день 1 23:59:59", "History must not roll over before the visible clock")
	check(scene.side_scenes._format_history_timestamp(86400.0) == "день 2 00:00:00", "History day rollover must match the clock's day count")
	scene.simulation.flight_history.records.assign(history.records.duplicate(true))
	scene.simulation.flight_history.records.append({"origin": 1, "destination": 2, "distance_km": 31.0, "duration_seconds": 300.0, "start_seconds": 900.0, "end_seconds": 1200.0})
	scene._set_view_mode(scene.ViewMode.OPERATIONS)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = scene.get_operations_history_rect().get_center()
	scene._handle_mouse_button(click)
	check(scene.view_mode == scene.ViewMode.FLIGHT_HISTORY, "Every flight service must open the chronological history")
	check(scene.side_scenes._history_record_at(0).end_seconds == 1200.0 and scene.side_scenes._history_record_at(1).end_seconds == 542.0, "The general journal must display the most recently completed flight first without reversing storage")
	var history_list_rect: Rect2 = scene.side_scenes._history_list_rect()
	var history_back_rect: Rect2 = scene.side_scenes.get_history_back_rect()
	var clock_controls_right: float = scene.get_time_reset_button_rect(true).end.x
	var clock_controls_left: float = scene.get_time_scale_button_rect(true).position.x
	check(is_equal_approx(history_list_rect.position.x - clock_controls_right, clock_controls_left), "The journal gap after the clock column must match the clock's left screen margin")
	check(is_equal_approx(scene.size.x - history_list_rect.end.x, 40.0), "Flight history must use the free width up to the normal right scene margin")
	check(history_back_rect.position.y >= 108.0 and history_list_rect.position.y > history_back_rect.end.y, "History controls and list must remain below the top status indicators")
	scene._interact_in_scene()
	check(scene.view_mode == scene.ViewMode.FLIGHT_HISTORY, "The newest one-off route must not open another route's records")
	scene.side_scenes.history_selected = 1
	scene._interact_in_scene()
	check(scene.view_mode == scene.ViewMode.ROUTE_HISTORY and scene.side_scenes._active_history_records()[0].duration_seconds == 42.0, "Enter on an older repeated route must open its own record-sorted detail screen")
	check(SaveGame.capture(scene).ui.view_mode == scene.ViewMode.OPERATIONS, "Saving from a transient history screen must resume in flight service")
	click.position = scene.side_scenes.get_history_back_rect().get_center()
	scene._handle_mouse_button(click)
	check(scene.view_mode == scene.ViewMode.FLIGHT_HISTORY, "Route detail back button must return to the chronological list")
	scene._handle_mouse_button(click)
	check(scene.view_mode == scene.ViewMode.OPERATIONS, "History back button must return to flight service")
	scene.simulation.flight_history.add_world_transition(0, 1, 1300.0)
	scene._set_view_mode(scene.ViewMode.FLIGHT_HISTORY)
	scene.side_scenes.history_selected = 0
	check(scene.side_scenes._history_record_at(0).kind == "world_transition", "The latest crossing must appear above older flights")
	scene._interact_in_scene()
	check(scene.view_mode == scene.ViewMode.FLIGHT_HISTORY, "Enter on a transition must not attempt to open flight records")
	await process_frame

	print("Persistent chronological flight history, route records and navigation: OK")
	quit(1 if failed else 0)
