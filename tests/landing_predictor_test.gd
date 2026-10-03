extends SceneTree

const FlightModel = preload("res://scripts/flight_model.gd")
const FlightWorld = preload("res://scripts/world.gd")
const LandingPredictor = preload("res://scripts/landing_predictor.gd")
const Scheduler = preload("res://scripts/ils_prediction_scheduler.gd")

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
	var job := LandingPredictor.start_prediction(flight, 0)
	job.advance(1)
	check(not job.finished and is_equal_approx(job.elapsed, LandingPredictor.STEP_SECONDS), "Incremental prediction must obey its step budget")
	while not job.finished:
		job.advance(17)
	check(job.result == prediction, "Incremental and synchronous forecasts must produce exactly the same result")
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
	_test_short_trajectory(flight, world)

	print("Forward landing prediction: OK (%.2f ms, %.1f s horizon, along %.4f km, cross %.4f km)" % [elapsed_msec, float(prediction.prediction_seconds), float(prediction.distance_from_threshold_km), float(prediction.cross_track_km)])
	quit(1 if failed else 0)

func _test_short_trajectory(flight, world) -> void:
	world.storms.clear()
	world.wind_layers.assign([
		{"altitude_m": 0.0, "from_deg": 90.0, "speed_kmh": 0.0},
		{"altitude_m": 150.0, "from_deg": 90.0, "speed_kmh": 0.0},
		{"altitude_m": 400.0, "from_deg": 90.0, "speed_kmh": 0.0},
	])
	var original: Dictionary = flight.snapshot()
	var rng_state: int = flight.turbulence_rng.state
	var job := LandingPredictor.start_prediction(flight, 0, LandingPredictor.Mode.SHORT_TRAJECTORY)
	while not job.finished:
		job.advance(3)
	check(is_equal_approx(job.elapsed, 4.0), "Short forecast must simulate only four seconds")
	check(bool(job.result.valid), "Descending short trajectory must produce an aiming estimate")
	var terminal = job.simulated
	var seconds: float = (terminal.altitude_m - world.height_at(world.airports[0].position)) / -terminal.vertical_speed_mps
	var velocity: Vector2 = world.heading_vector(terminal.heading_deg) * terminal.speed_kmh + terminal.current_wind_kmh
	var expected: Vector2 = terminal.position_km + velocity * seconds / 3600.0
	check(Vector2(job.result.predicted_position).distance_to(expected) < 0.00001, "Short forecast must extrapolate terminal velocity, not the entire future approach")
	var full_before: Dictionary = LandingPredictor.predict(flight, 0)
	world.wind_layers[0].speed_kmh = 100.0
	var short_after: Dictionary = LandingPredictor.predict(flight, 0, LandingPredictor.Mode.SHORT_TRAJECTORY)
	var full_after: Dictionary = LandingPredictor.predict(flight, 0)
	check(short_after == job.result, "Wind changes below the short horizon must not be anticipated")
	check(full_before != full_after, "Original full simulation must still anticipate future wind layers")
	check(flight.snapshot() == original and flight.turbulence_rng.state == rng_state, "Both forecast modes must leave the source untouched")
	var scheduler := Scheduler.new()
	check(is_equal_approx(Scheduler.REFRESH_INTERVAL, 0.5), "Forecast must refresh twice per real second")
	check(scheduler.prediction_mode == LandingPredictor.Mode.SHORT_TRAJECTORY, "Game instruments must default to the short forecast")
	scheduler.refresh_immediately(flight, 0)
	check(scheduler.result == short_after, "Immediate forecast must use the selected short mode")
	scheduler.prediction_mode = LandingPredictor.Mode.FULL_SIMULATION
	scheduler.refresh_immediately(flight, 0)
	check(scheduler.result == full_after, "One mode switch must restore the original full forecast")
	scheduler.prediction_mode = LandingPredictor.Mode.SHORT_TRAJECTORY
	scheduler.refresh_immediately(flight, 0)
	flight.heading_deg += 2.0
	var raw := LandingPredictor.predict(flight, 0, LandingPredictor.Mode.SHORT_TRAJECTORY)
	scheduler.update(flight, 0, true, Scheduler.REFRESH_INTERVAL)
	while scheduler.job != null:
		scheduler.update(flight, 0, true, 0.0)
	var smoothed: Vector2 = Vector2(short_after.predicted_position).lerp(Vector2(raw.predicted_position), 0.8)
	check(Vector2(scheduler.result.predicted_position).distance_to(smoothed) < 0.00001, "Both ILS sizes must share a lightly smoothed estimate")
	scheduler.update(flight, 0, false, 0.1)
	check(not bool(scheduler.result.valid), "Signal loss must clear the estimate immediately")
	flight.restore_snapshot(original, rng_state)
