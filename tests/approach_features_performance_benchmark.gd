extends SceneTree
## Manual CPU comparison on a fixed seed; no writes to campaign saves.
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Gust = preload("res://scripts/approach_gust.gd")
const Predictor = preload("res://scripts/landing_predictor.gd")

func _initialize() -> void:
	for elevated in [false, true]:
		var start := Time.get_ticks_usec()
		var world := World.new(424242, elevated)
		var generation_ms := (Time.get_ticks_usec() - start) / 1000.0
		var checksum := 0.0
		start = Time.get_ticks_usec()
		for sample in 20000:
			checksum += world.height_at(Vector2(sample % 200, sample / 200))
		var terrain_usec := (Time.get_ticks_usec() - start) / 20000.0
		var airport: Dictionary = world.airports[0]
		var forward: Vector2 = world.heading_vector(airport.heading)
		var position: Vector2 = Vector2(airport.position) - forward * (1.0 + World.RUNWAY_LENGTH_KM * 0.5)
		var altitude := world.airport_elevation_m(airport) + 50.0
		start = Time.get_ticks_usec()
		for sample in 10000:
			Gust.weight(world, position, altitude, airport.heading, -1.3, true)
		var gust_usec := (Time.get_ticks_usec() - start) / 10000.0
		world.storms.clear()
		var flight := Flight.new(world)
		flight.position_km = position
		flight.heading_deg = airport.heading
		flight.altitude_m = altitude
		flight.state = Flight.State.FLYING
		flight.speed_kmh = 100.0
		flight.vertical_speed_mps = -1.3
		flight.throttle = 0.3
		flight.engine_running = true
		for enabled in [false, true]:
			flight.approach_gusts_enabled = enabled
			Predictor.predict(flight, 0, Predictor.Mode.SHORT_TRAJECTORY)
			start = Time.get_ticks_usec()
			for repeat in 20:
				Predictor.predict(flight, 0, Predictor.Mode.SHORT_TRAJECTORY)
			print("elevated=%s gusts=%s: short forecast %.3f ms" % [elevated, enabled, (Time.get_ticks_usec() - start) / 20000.0])
		print("elevated=%s: generation %.2f ms, terrain %.2f us/query, approach gate %.2f us/query, checksum %.0f" % [elevated, generation_ms, terrain_usec, gust_usec, checksum])
	quit()
