extends SceneTree

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

	var before_click: int = game.ils_airport_index
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.get_ils_rect().get_center()
	game._handle_mouse_button(click)
	check(game.ils_airport_index == before_click, "Clicking ILS must not switch airports")

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

	print("ILS receiver binding, automatic airport selection and inert click: OK")
	quit(1 if failed else 0)
