extends SceneTree

const FlightModel = preload("res://scripts/flight_model.gd")
const FlightWorld = preload("res://scripts/world.gd")
const LandingPredictor = preload("res://scripts/landing_predictor.gd")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	var world = FlightWorld.new(424242)
	var flight = FlightModel.new(world)
	var airport: Dictionary = world.airports[0]
	var heading := float(airport.heading)
	var forward: Vector2 = world.heading_vector(heading)
	flight.position_km = Vector2(airport.position) - forward * 5.0
	flight.position_integration_error_km = Vector2.ZERO
	flight.heading_deg = heading
	flight.altitude_m = 234.098
	flight.speed_kmh = 100.0
	flight.vertical_speed_mps = -1.3
	flight.pitch_deg = 0.0
	flight.yoke = Vector2.ZERO
	flight.throttle = 0.30
	flight.engine_running = true
	flight.electrical_power = true
	flight.state = FlightModel.State.FLYING
	flight.current_wind_kmh = world.wind_at(flight.altitude_m)

	var source_snapshot: Dictionary = flight.snapshot()
	var source_rng_state: int = flight.turbulence_rng.state
	var weather_time_before: float = world.weather_time_seconds
	var started_usec := Time.get_ticks_usec()
	var prediction: Dictionary = LandingPredictor.predict(flight, 0)
	var elapsed_msec := (Time.get_ticks_usec() - started_usec) / 1000.0
	check(bool(prediction.valid), "A stable three-degree approach must produce a forward touchdown prediction")
	check(float(prediction.prediction_seconds) > 30.0, "The predictor must simulate the future rather than project one instant")
	check(flight.snapshot() == source_snapshot, "Prediction must not mutate the real aircraft")
	check(flight.turbulence_rng.state == source_rng_state, "Prediction must not consume the real turbulence RNG")
	check(is_equal_approx(world.weather_time_seconds, weather_time_before), "Prediction must not advance world weather")
	var advanced = FlightModel.new(world)
	check(advanced.restore_snapshot(source_snapshot, source_rng_state), "The forecast continuation must restore its source state")
	for step in 5:
		advanced.yoke.x = move_toward(advanced.yoke.x, 0.0, 0.2 * LandingPredictor.LATERAL_YOKE_CENTER_RATE)
		advanced.update_prediction(0.2)
	var continued_prediction: Dictionary = LandingPredictor.predict(advanced, 0)
	check(bool(continued_prediction.valid), "The same unchanged approach must remain predictable one second later")
	check(Vector2(continued_prediction.predicted_position).distance_to(Vector2(prediction.predicted_position)) < 0.015, "The diamond must remain stable while unchanged controls follow the simulated trajectory")

	# Storms must not influence the forecast even if the real aircraft is inside a
	# strong cell: the requested first version is intentionally wind-only.
	world.storms.clear()
	world.storms.append({
		"position": flight.position_km,
		"radius_km": 20.0,
		"intensity": 1.0,
		"velocity_kmh": Vector2.ZERO,
		"seed": 1,
	})
	flight.storm_intensity = 1.0
	flight.storm_vertical_flow_mps = 8.0
	flight.storm_wind_gust_kmh = Vector2(50.0, -40.0)
	var storm_ignored: Dictionary = LandingPredictor.predict(flight, 0)
	check(bool(storm_ignored.valid), "A storm at the aircraft must not suppress the wind-only forecast")
	check(Vector2(storm_ignored.predicted_position).distance_to(Vector2(prediction.predicted_position)) < 0.002, "Storm state must be excluded from the prediction")

	print("Forward landing prediction: OK (%.2f ms, %.1f s horizon, along %.4f km, cross %.4f km)" % [elapsed_msec, float(prediction.prediction_seconds), float(prediction.distance_from_threshold_km), float(prediction.cross_track_km)])
	quit(1 if failed else 0)
