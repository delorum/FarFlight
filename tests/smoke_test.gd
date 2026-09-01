extends SceneTree

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")

func _init() -> void:
	for seed_value in range(10001, 10031):
		var world = FlightWorldScript.new(seed_value)
		assert(world.airports.size() == 2)
		assert(world.beacons.size() == 6)
		assert(world.beacons[0].range_km == 15.0)
		assert(world.beacons[2].range_km == 30.0)
		var distance: float = world.airports[0].position.distance_to(world.airports[1].position)
		assert(distance >= 45.0 and distance <= 58.0, "Airport distance %.2f for seed %d" % [distance, seed_value])
		for airport in world.airports:
			var direction: Vector2 = world.heading_vector(airport.heading)
			assert(world.height_at(airport.position) < 1.0)
			assert(world.height_at(airport.position + direction * 4.0) < 50.0)
			assert(world.height_at(airport.position - direction * 4.0) < 50.0)
			var approach_point: Vector2 = airport.position - direction * 5.0
			var approach_right := Vector2(direction.y, -direction.x)
			assert(world.height_at(approach_point) < 1.0)
			assert(world.height_at(approach_point + approach_right * 0.8) < 250.0)
			assert(world.height_at(approach_point - approach_right * 0.8) < 250.0)
	var test_world = FlightWorldScript.new(424242)
	var out_of_range := test_world.beacon_signal(test_world.beacons[0], test_world.beacons[0].position + Vector2(16.0, 0.0), 5000.0)
	assert(not out_of_range.available)
	assert(out_of_range.reason == "ВНЕ ДАЛЬНОСТИ")
	var flight = FlightModelScript.new(test_world)
	assert(flight.message.begins_with("Готов к взлёту"))
	flight.refuel()
	assert(flight.message.begins_with("Самолёт заправлен"))
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.10))
	flight.throttle = 1.0
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.72))
	flight.altitude_m = 2500.0
	assert(is_equal_approx(flight.altitude_fuel_factor(), 0.82))
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.5904))
	assert(is_equal_approx(flight.altitude_power_factor(), 1.0))
	flight.altitude_m = 5000.0
	assert(is_equal_approx(flight.altitude_fuel_factor(), 1.08))
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.7776))
	assert(is_equal_approx(flight.altitude_power_factor(), 0.82))
	assert(is_equal_approx(flight.max_available_climb_mps(), 0.0))
	flight.altitude_m = 0.0
	flight.throttle = 0.0
	flight.update(3.1)
	assert(flight.message.begins_with("Готов к взлёту"))
	flight.throttle = 1.0
	flight.yoke = Vector2(0, 0.55)
	for frame in 900:
		flight.update(1.0 / 60.0)
	print("Takeoff state=%d altitude=%.1f speed=%.1f message=%s" % [flight.state, flight.altitude_m, flight.speed_kmh, flight.message])
	assert(flight.state == FlightModelScript.State.FLYING)
	assert(flight.altitude_m > 20.0)
	assert(not flight.stalled)

	# A sharp pull exceeds the critical angle of attack. The stall persists
	# until the nose is lowered and sufficient airspeed is restored.
	var stall_test = FlightModelScript.new(test_world)
	stall_test.state = FlightModelScript.State.FLYING
	stall_test.position_km = Vector2(50, 50)
	stall_test.altitude_m = 3000.0
	stall_test.speed_kmh = 110.0
	stall_test.yoke.y = 1.0
	for frame in 120:
		stall_test.update(1.0 / 60.0)
		if stall_test.stalled:
			break
	assert(stall_test.stalled)
	assert(stall_test.angle_of_attack_deg >= FlightModelScript.STALL_WARNING_AOA_DEG)
	stall_test.yoke.y = -1.0
	stall_test.throttle = 1.0
	for frame in 600:
		stall_test.update(1.0 / 60.0)
		if not stall_test.stalled:
			break
	assert(not stall_test.stalled)

	# At the practical ceiling full power no longer provides excess climb
	# power. Continuing to pull trades speed for AoA and causes a stall.
	var ceiling_test = FlightModelScript.new(test_world)
	ceiling_test.state = FlightModelScript.State.FLYING
	ceiling_test.position_km = Vector2(50, 50)
	ceiling_test.altitude_m = 4950.0
	ceiling_test.speed_kmh = 190.0
	ceiling_test.throttle = 1.0
	ceiling_test.yoke.y = 1.0
	var ceiling_start_speed: float = ceiling_test.speed_kmh
	var ceiling_min_speed: float = ceiling_test.speed_kmh
	var ceiling_stalled := false
	for frame in 300:
		ceiling_test.update(1.0 / 60.0)
		if ceiling_test.stalled:
			ceiling_stalled = true
		ceiling_min_speed = minf(ceiling_min_speed, ceiling_test.speed_kmh)
	assert(ceiling_stalled)
	assert(ceiling_min_speed < ceiling_start_speed - 10.0)
	assert(ceiling_test.altitude_m < 5000.0)
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

	# Complete north-up runway approach: 6 km to the far-end beacon means
	# 4 km to the threshold. Neutral pitch and 30% power should follow an
	# approximately three-degree glide path, followed by a short power cut.
	var approach = FlightModelScript.new(test_world)
	var approach_airport: Dictionary = test_world.airports[1]
	var approach_direction: Vector2 = test_world.heading_vector(approach_airport.heading)
	approach.position_km = approach_airport.position - approach_direction * 5.0
	approach.heading_deg = approach_airport.heading
	approach.altitude_m = 230.0
	approach.speed_kmh = 100.0
	approach.vertical_speed_mps = 0.0
	approach.throttle = 0.30
	approach.yoke = Vector2.ZERO
	approach.state = FlightModelScript.State.FLYING
	var initial_guidance: Dictionary = approach.landing_guidance(1)
	assert(initial_guidance.in_localizer)
	assert(initial_guidance.in_glide)
	assert(absf(initial_guidance.desired_altitude_m - 230.6) < 1.0)
	var landing_beacon: Dictionary = test_world.beacons[1]
	for frame in 30000:
		if approach.position_km.distance_to(landing_beacon.position) <= 2.05:
			approach.throttle = 0.10
		approach.update(1.0 / 60.0)
		if approach.state != FlightModelScript.State.FLYING:
			break
	var final_coords: Vector2 = test_world.runway_coordinates(approach.position_km, approach_airport)
	print("Approach result: state=%d along=%.3f cross=%.3f alt=%.1f speed=%.1f vs=%.2f beacon=%.3f" % [approach.state, final_coords.x, final_coords.y, approach.altitude_m, approach.speed_kmh, approach.vertical_speed_mps, approach.position_km.distance_to(landing_beacon.position)])
	assert(approach.state == FlightModelScript.State.LANDED, approach.message)
	print("Smoke test: 30 worlds, takeoff and landing simulation OK")
	quit()
