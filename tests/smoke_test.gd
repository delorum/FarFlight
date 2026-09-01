extends SceneTree

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")

func _init() -> void:
	for seed_value in range(10001, 10031):
		var world = FlightWorldScript.new(seed_value)
		assert(world.airports.size() == 2)
		assert(world.beacons.size() == 6)
		var distance: float = world.airports[0].position.distance_to(world.airports[1].position)
		assert(distance >= 45.0 and distance <= 58.0, "Airport distance %.2f for seed %d" % [distance, seed_value])
		for airport in world.airports:
			var direction: Vector2 = world.heading_vector(airport.heading)
			assert(world.height_at(airport.position) < 1.0)
			assert(world.height_at(airport.position + direction * 4.0) < 50.0)
			assert(world.height_at(airport.position - direction * 4.0) < 50.0)
	var test_world = FlightWorldScript.new(424242)
	var flight = FlightModelScript.new(test_world)
	assert(flight.message.begins_with("Готов к взлёту"))
	flight.refuel()
	assert(flight.message.begins_with("Самолёт заправлен"))
	flight.update(3.1)
	assert(flight.message.begins_with("Готов к взлёту"))
	flight.throttle = 1.0
	flight.yoke = Vector2(0, 1)
	for frame in 900:
		flight.update(1.0 / 60.0)
	print("Takeoff state=%d altitude=%.1f speed=%.1f message=%s" % [flight.state, flight.altitude_m, flight.speed_kmh, flight.message])
	assert(flight.state == FlightModelScript.State.FLYING)
	assert(flight.altitude_m > 20.0)
	var airport: Dictionary = test_world.airports[1]
	flight.position_km = airport.position
	flight.heading_deg = airport.heading
	flight.altitude_m = 1.0
	flight.speed_kmh = 90.0
	flight.vertical_speed_mps = -2.0
	flight.throttle = 0.0
	flight.yoke = Vector2.ZERO
	flight.update(0.2)
	assert(flight.state == FlightModelScript.State.LANDED)
	assert(flight.speed_kmh == 0.0)
	print("Smoke test: 30 worlds, takeoff and landing simulation OK")
	quit()
