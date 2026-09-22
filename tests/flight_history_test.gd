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
	history.active = true
	history.active_origin = 1
	history.active_start_seconds = 800.0
	history.active_distance_km = 12.5
	var snapshot := history.snapshot()
	var restored := FlightHistory.new()
	check(FlightHistory.valid_snapshot(snapshot, world.airports.size()) and restored.restore_snapshot(snapshot, world.airports.size()) and restored.snapshot() == snapshot, "Completed and airborne flight history must survive a save round trip")

	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
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

	print("Persistent chronological flight history, route records and navigation: OK")
	quit(1 if failed else 0)
