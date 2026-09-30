extends RefCounted
## Select a playable chart before changing any campaign state.
const World = preload("res://scripts/world.gd")
const MAX_CANDIDATES := 128
const EMERGENCY_SEED := 424242

static func _candidate_seed(base_seed: int, level: int, attempt: int) -> int:
	if level == 0 and attempt == 0:
		return base_seed
	return posmod(base_seed + level * 1000003 + attempt * 7919, 2147483646) + 1

static func initial_world(requested_seed: int):
	var first = World.new(requested_seed)
	var base_seed: int = first.seed_value
	for attempt in MAX_CANDIDATES:
		var candidate = first if attempt == 0 else World.new(_candidate_seed(base_seed, 0, attempt))
		if not candidate.all_airports_route_connected() or not candidate.ensure_exit_portal():
			continue
		# The route is checked now, but the marker remains hidden until delivery 16.
		candidate.exit_portal.clear()
		return candidate
	# A playable chart is preferable to starting an unwinnable campaign if an
	# unusually restrictive seed exhausts the deterministic search.
	var fallback = World.new(EMERGENCY_SEED)
	if fallback.all_airports_route_connected() and fallback.ensure_exit_portal():
		fallback.exit_portal.clear()
		return fallback
	return null

static func next_world(previous_world) -> Dictionary:
	if previous_world.exit_portal.is_empty():
		return {}
	var entry_side: String = World.opposite_edge(String(previous_world.exit_portal.side))
	var coordinate: float = float(previous_world.exit_portal.coordinate)
	var next_level: int = previous_world.level_index + 1
	for attempt in MAX_CANDIDATES:
		var candidate = World.new(_candidate_seed(previous_world.seed_value, next_level, attempt))
		if not candidate.all_airports_route_connected():
			continue
		var entry: Vector2 = candidate.find_entry_position(entry_side, coordinate)
		if entry.x < 0.0 or not candidate.ensure_exit_portal():
			continue
		candidate.exit_portal.clear()
		candidate.level_index = next_level
		return {"world": candidate, "entry_position": entry}
	return {}

static func transition(previous_world, flight, economy, simulation) -> Dictionary:
	var destination := next_world(previous_world)
	if destination.is_empty():
		return {}
	var next_chart = destination.world
	var entry: Vector2 = destination.entry_position
	var abandoned: int = economy.advance_to_world(next_chart)
	flight.world = next_chart
	flight.position_km = entry
	flight.position_integration_error_km = Vector2.ZERO
	flight.altitude_m = maxf(flight.altitude_m, next_chart.height_at(entry) + World.ROUTE_CLEARANCE_M)
	flight.world_exit_reached = false
	flight.current_wind_kmh = next_chart.wind_at(flight.altitude_m)
	flight.storm_intensity = 0.0
	flight.storm_vertical_flow_mps = 0.0
	flight.storm_roll_bias_deg = 0.0
	flight.storm_pitch_bias_deg = 0.0
	flight.storm_wind_gust_kmh = Vector2.ZERO
	flight.turbulence_rng.seed = next_chart.seed_value + 918273
	var nearest_airport := 0
	var nearest_distance := INF
	for airport_index in next_chart.airports.size():
		var distance: float = entry.distance_squared_to(Vector2(next_chart.airports[airport_index].position))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_airport = airport_index
	flight.airport_index = nearest_airport
	flight.prepared_airport_index = nearest_airport
	flight.departure_authorized = false
	simulation.flight_history.active = false
	simulation.flight_history.active_origin = -1
	simulation.flight_history.active_level = next_chart.level_index
	simulation.flight_history.active_distance_km = 0.0
	simulation.trip_air_distance_km = 0.0
	simulation.trip_elapsed_seconds = 0.0
	simulation.last_economy_flight_state = flight.state
	simulation.time_scale_index = 0
	return {"world": next_chart, "entry_position": entry, "nearest_airport": nearest_airport, "abandoned": abandoned}
