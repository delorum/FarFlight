extends SceneTree
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Predictor = preload("res://scripts/landing_predictor.gd")
const State = preload("res://scripts/ils_display_state.gd")
const Camera = preload("res://scripts/ils_cockpit_projection.gd")
const Art = preload("res://scripts/ils_display_art.gd")
const Practice = preload("res://scripts/landing_practice.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var raised := 0
	var engineered := 0
	var started := Time.get_ticks_usec()
	for seed_value in [424242, 19, 1033, 2026]:
		var world := World.new(seed_value)
		var takeoff := Flight.new(world)
		takeoff.approach_gusts_enabled = false
		for field_index in world.airports.size():
			takeoff.prepare_at_airport(field_index)
			takeoff.electrical_power = true
			takeoff.engine_running = true
			takeoff.throttle = 1.0
			takeoff.speed_kmh = 90.0
			takeoff.yoke.y = 1.0
			for frame in 30:
				takeoff.update_prediction(1.0 / 30.0)
			check(takeoff.state == Flight.State.FLYING and takeoff.altitude_m > world.airport_elevation_m(world.airports[field_index]), "Aircraft must be able to take off from every elevated runway")
		for airport in world.airports:
			var height := world.airport_elevation_m(airport)
			check(height >= 0 and height <= 300 and is_equal_approx(world.height_at(airport.position), height), "Airports must have a consistent elevation datum in the 0–300 m range")
			raised += 1 if height > 0 else 0
			engineered += 1 if airport.get("engineered_approach", false) else 0
			for sign_value in [-1.0, 1.0]:
				var forward: Vector2 = world.heading_vector(airport.heading) * sign_value
				var lateral := forward.orthogonal()
				var threshold: Vector2 = Vector2(airport.position) - forward * World.RUNWAY_LENGTH_KM * 0.5
				for step in range(1, 25):
					var distance := step * 0.25
					for offset in [-1.0, 0.0, 1.0]:
						var point: Vector2 = threshold - forward * distance + lateral * offset * (0.1 + distance * 0.05)
						var path_height := minf(world.glide_altitude_m(airport, distance), height + 234.0)
						check(world.height_at(point) <= path_height - minf(15.0, distance * 15.0) + 0.1, "Both glide paths and the lower level practice entry must be clear with lateral and vertical margin")
	check(raised > 4, "Generated airports must actually vary in elevation")
	var flat := World.new(424242, false)
	for airport in flat.airports:
		check(flat.airport_elevation_m(airport) == 0.0 and flat.height_at(airport.position) == 0.0, "Rollback must restore sea-level runways")
	var world := World.new(424242)
	world.storms.clear()
	var index := 1
	for i in world.airports.size():
		if world.airport_elevation_m(world.airports[i]) > 0:
			index = i
			break
	var airport: Dictionary = world.airports[index]
	var height := world.airport_elevation_m(airport)
	var flight := Flight.new(world)
	flight.approach_gusts_enabled = false
	for reverse in [false, true]:
		flight.prepare_at_airport(index, reverse)
		flight.electrical_power = true
		check(flight.altitude_m == height and flight.radio_height_m() == 0.0, "Parked aircraft must sit on its runway, not sea level")
		flight.state = Flight.State.FLYING
		flight.electrical_power = true
		var forward: Vector2 = world.heading_vector(flight.heading_deg)
		flight.position_km = Vector2(airport.position) - forward * (4.0 + World.RUNWAY_LENGTH_KM * 0.5)
		flight.altitude_m = world.glide_altitude_m(airport, 4.0)
		flight.speed_kmh = 100
		flight.current_wind_kmh = Vector2.ZERO
		var state := State.build(flight, index, true, {}, 350)
		check(state.glide_capture.on_glide and absf(float(state.guidance.desired_altitude_m) - height - 212.78) < 0.1, "ILS glide height must add runway elevation for both directions")
		var elevated_point := Camera.camera_point(state.projection, 0.1, 0.0)
		var low_guidance: Dictionary = state.projection.duplicate()
		low_guidance.aircraft_altitude_m -= height
		low_guidance.runway_elevation_m = 0.0
		check(elevated_point.is_equal_approx(Camera.camera_point(low_guidance, 0.1, 0.0)), "Cockpit projection must use height above runway")
		var view := Rect2(0, 0, 500, 500)
		check(is_equal_approx(Art.projected_runway_geometry(view, state.projection).altitude_km, Art.projected_runway_geometry(view, low_guidance).altitude_km), "Legacy projection must use the same elevation datum")
		flight.position_km = airport.position
		flight.altitude_m = height + 0.05
		flight.vertical_speed_mps = -1.0
		flight.pitch_deg = 0.0
		for mode in [Predictor.Mode.FULL_SIMULATION, Predictor.Mode.SHORT_TRAJECTORY]:
			var prediction := Predictor.predict(flight, index, mode)
			check(prediction.valid and prediction.prediction_seconds <= Predictor.STEP_SECONDS + 0.001, "Both forecasts must detect elevated runway contact immediately, not descend to sea level")
		check(flight._try_land() and flight.altitude_m == height, "Touchdown must reset to runway elevation")
		flight._update_ground_roll(0.001)
		check(flight.altitude_m == height, "Rollout must retain runway elevation")
	Practice.configure(world, flight)
	check(is_equal_approx(flight.altitude_m - world.airport_elevation_m(world.airports[flight.airport_index]), 234.0), "Practice altitude must be relative to its selected runway")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world = world
	game.flight = flight
	game._build_approach_markers()
	for field in world.airports:
		for markers in field.approach_markers.values():
			check(markers.any(func(marker): return marker.distance_km == 4.0), "Every generated approach must publish its reachable four-kilometre marker")
			for marker in markers:
				check(is_equal_approx(marker.altitude_m, world.glide_altitude_m(field, marker.distance_km)) and marker.altitude_m <= Flight.PRACTICAL_CEILING_M, "Map markers must use absolute altitudes and omit unreachable heights")
	game.map_center = airport.position
	var footer: String = game.navigation_map.map_footer_text_at(game.world_to_screen(airport.position))
	check(footer.begins_with(String(airport.name) + ":") and footer.contains("%.0f м" % height), "Airport map information must include its elevation compactly")
	game.free()
	var restored_world := World.new(world.seed_value)
	restored_world.restore_snapshot(world.snapshot())
	check(is_equal_approx(restored_world.height_at(airport.position), height), "Loading must rebuild the cached airport terrain geometry")
	print("Elevated airports: %d raised, %d engineered fallback, %.1f ms; approach clearance, rollback, ILS and contact: %s" % [raised, engineered, (Time.get_ticks_usec() - started) / 1000.0, "FAIL" if failed else "OK"])
	quit(1 if failed else 0)
