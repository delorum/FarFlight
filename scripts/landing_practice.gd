extends RefCounted
## Builds one reproducible approach from a random world seed.

const FlightWorld = preload("res://scripts/world.gd")
const FlightModel = preload("res://scripts/flight_model.gd")

static func clear_storms(world) -> void:
	world.storms.clear()

static func configure(world, flight) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.seed_value) * 7919 + 104729
	var airport_index := rng.randi_range(0, world.airports.size() - 1)
	var reverse_direction := rng.randf() < 0.5
	var airport: Dictionary = world.airports[airport_index]
	var approach_heading := fposmod(float(airport.heading) + (180.0 if reverse_direction else 0.0), 360.0)
	var approach_forward: Vector2 = world.heading_vector(approach_heading)
	var near_threshold := Vector2(airport.position) - approach_forward * (FlightWorld.RUNWAY_LENGTH_KM * 0.5)
	clear_storms(world)
	flight.airport_index = airport_index
	flight.prepared_airport_index = airport_index
	flight.prepared_reverse_direction = reverse_direction
	flight.position_km = near_threshold - approach_forward * 6.0
	flight.position_integration_error_km = Vector2.ZERO
	flight.heading_deg = approach_heading
	flight.altitude_m = 234.0
	flight.speed_kmh = 150.0
	flight.vertical_speed_mps = 0.0
	flight.pitch_deg = 0.0
	flight.bank_deg = 0.0
	flight.yoke = Vector2.ZERO
	flight.throttle = 0.70
	flight.fuel_l = 40.0
	flight.electrical_power = true
	flight.engine_running = true
	flight.departure_authorized = true
	flight.state = FlightModel.State.FLYING
	flight.current_wind_kmh = world.wind_at(flight.altitude_m)
	flight._show_message("ТРЕНИРОВКА ПОСАДКИ", 4.0, "")
