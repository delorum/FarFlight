extends SceneTree
const Gust = preload("res://scripts/approach_gust.gd")
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Predictor = preload("res://scripts/landing_predictor.gd")
const Save = preload("res://scripts/save_game.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state := Gust.initial(42)
	var prior: Vector2 = state.current
	var maximum := 0.0
	for frame in 2400:
		Gust.advance(state, 1.0 / 30.0, true, 32.0)
		check(Vector2(state.current).distance_to(prior) < 0.25, "Gusts must evolve smoothly, without per-frame jumps")
		check(Gust.valid(state), "Every simulation step must preserve valid bounded gust state")
		maximum = maxf(maximum, Vector2(state.current).length())
		prior = state.current
	check(maximum > 1.0 and maximum <= 12.0, "Gusts must actually vary and stay within twelve km/h")
	var one_step := Gust.initial(42)
	var split := Gust.initial(42)
	Gust.advance(one_step, 30.0, true, 32.0)
	for step in 120:
		Gust.advance(split, 0.25, true, 32.0)
	check(Vector2(one_step.current).distance_to(split.current) < 0.0001 and one_step.rng_state == split.rng_state, "Gust evolution must use simulation time, independent of frame size/time acceleration")
	var rng_state: int = state.rng_state
	Gust.advance(state, 20.0, false, 32.0)
	check(state.current == Vector2.ZERO and state.rng_state == rng_state, "Outside approaches there must be no gust or random draws")
	var world := World.new(424242)
	world.storms.clear()
	for layer in world.wind_layers:
		layer.speed_kmh = 0.0
	var airport: Dictionary = world.airports[0]
	var forward: Vector2 = world.heading_vector(airport.heading)
	var position: Vector2 = Vector2(airport.position) - forward * (1.0 + World.RUNWAY_LENGTH_KM * 0.5)
	var height: float = world.height_at(position)
	check(Gust.weight(world, position, height + 50, airport.heading, -1, true) > 0.99, "A low aligned approach must enable gusts")
	check(Gust.weight(world, position, height + 100, airport.heading, -1, true) == 0.0, "Gusts must stop at one hundred metres AGL")
	check(Gust.weight(world, position, height + 50, airport.heading, -1, false) == 0.0, "Grounded aircraft must have no approach gusts")
	check(Gust.weight(world, position, height + 50, airport.heading + 90, -1, true) == 0.0, "Passing an airport across its runway must not enable landing gusts")
	check(Gust.weight(world, position, height + 50, airport.heading, 2.0, true) == 0.0, "A climb/go-around must disable approach gusts")
	var distant: Vector2 = Vector2(airport.position) - forward * (6.0 + World.RUNWAY_LENGTH_KM * 0.5)
	check(Gust.weight(world, distant, world.height_at(distant) + 50, airport.heading, -1, true) == 0.0, "Low ordinary flight beyond five kilometres must remain calm")
	check(Gust.weight(world, position, height + 99.9, airport.heading, -1, true) < 0.001, "Height boundary must fade to zero rather than switch abruptly")
	for field in world.airports:
		var elevation: float = world.airport_elevation_m(field)
		if elevation > 100.0:
			check(Gust.weight(world, field.position, elevation + 50.0, field.heading, -1, true) > 0.99, "Elevated airports must use height above ground, not a one-hundred-metre sea-level cutoff")
	var plane := Flight.new(world)
	plane.state = Flight.State.FLYING
	plane.position_km = position
	plane.altitude_m = height + 50
	plane.heading_deg = airport.heading
	plane.speed_kmh = 100
	plane.pitch_deg = 0
	plane.vertical_speed_mps = -1.3
	plane.throttle = 0.3
	plane.engine_running = true
	plane.electrical_power = true
	plane.approach_gust_state = {"start": Vector2(8, 0), "target": Vector2(8, 0), "current": Vector2(8, 0), "elapsed": 5.0, "duration": 10.0, "rng_state": Gust.initial(42).rng_state}
	plane.approach_gust_kmh = Vector2(8, 0)
	var snapshot: Dictionary = plane.snapshot()
	var copied := Flight.new(world)
	check(copied.restore_snapshot(snapshot, plane.turbulence_rng.state), "Gust state must survive normal flight snapshots")
	copied.approach_gusts_enabled = false
	var before_prediction := plane.snapshot()
	for mode in [Predictor.Mode.FULL_SIMULATION, Predictor.Mode.SHORT_TRAJECTORY]:
		var job := Predictor.start_prediction(plane, 0, mode)
		job.advance(1)
		check(job.simulated.approach_gust_state == before_prediction.approach_gust_state and job.simulated.approach_gust_kmh == Vector2(8, 0), "Both forecasts must retain the known gust without sampling its future")
		check(plane.snapshot() == before_prediction, "Prediction must not mutate the live gust or random generator")
	var controls: Vector2 = plane.yoke
	plane.update(0.1)
	copied.update(0.1)
	check(plane.current_wind_kmh.length() > 7.9 and copied.current_wind_kmh == Vector2.ZERO, "The independent rollback flag must remove the gust vector")
	check(plane.heading_deg == copied.heading_deg and plane.pitch_deg == copied.pitch_deg and plane.yoke == controls and plane.speed_kmh == copied.speed_kmh and plane.vertical_speed_mps == copied.vertical_speed_mps, "Horizontal gusts must not directly move the yoke, nose, airspeed or vertical speed")
	check(plane.position_km.distance_to(copied.position_km) > 0.0001, "The gust must change actual ground displacement")
	check(snapshot.approach_gust_state == before_prediction.approach_gust_state, "Snapshot dictionaries must detach from live gust updates")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.approach_gust_state.current = Vector2(INF, 0)
	check(not copied.restore_snapshot(broken, plane.turbulence_rng.state), "Corrupt gust vectors must be rejected")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.flight = plane
	game.world = world
	game.simulation_paused = true
	var paused := plane.snapshot()
	game._process(1.0)
	check(plane.snapshot() == paused, "Pause must freeze gust evolution together with flight")
	var saved := Save.capture(game)
	check(Save.valid(saved) and Save.restore(game, saved), "Full game saves must preserve gust and airport elevation state")
	for invalid_height in [NAN, INF, -1.0, 301.0, "bad"]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid.world.airports[0].elevation_m = invalid_height
		check(not Save.valid(invalid), "Malformed runway elevation must be rejected before loading")
	saved.flight.approach_gust_state.duration = NAN
	check(not Save.valid(saved), "Full save validation must reject malformed gust state")
	game.free()
	print("Approach gust boundaries, smoothness, simulation clock, forecasts, rollback and saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
