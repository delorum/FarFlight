extends SceneTree

const WorldScript = preload("res://scripts/world.gd")
const FlightScript = preload("res://scripts/flight_model.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = WorldScript.new(424242)
	var flight = FlightScript.new(world)
	check(flight.radio_height_m() < 0.0, "Radio altimeter must be off with engine stopped")
	flight.engine_running = true
	check(is_zero_approx(flight.radio_height_m()), "Runway reading must be zero")
	flight.position_km = Vector2(50, 50)
	var terrain: float = world.height_at(flight.position_km)
	for clearance in [0.0, 100.0, 749.9, 750.0]:
		flight.altitude_m = terrain + clearance
		check(is_equal_approx(flight.radio_height_m(), clearance), "Reading must be clearance above terrain, including 750 m")
	flight.altitude_m = terrain + 750.1
	check(flight.radio_height_m() < 0.0, "Above 750 m there must be no reading")
	flight.altitude_m = terrain - 1.0
	check(is_zero_approx(flight.radio_height_m()), "Ground penetration must not display negative height")
	# Move at constant absolute altitude: the reading must follow actual terrain.
	flight.altitude_m = 700.0
	for point in [Vector2(20, 30), Vector2(50, 50), Vector2(70, 60)]:
		flight.position_km = point
		var expected := maxf(0.0, 700.0 - world.height_at(point))
		check(is_equal_approx(flight.radio_height_m(), expected), "Moving must immediately update clearance without changing absolute altitude")
	flight.engine_running = false
	check(flight.radio_height_m() < 0.0, "Stopping engine must remove the reading")
	flight.engine_running = true
	check(flight.radio_height_m() >= 0.0, "Restarting engine must restore the reading")
	print("Radio altimeter range, terrain tracking and power: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
