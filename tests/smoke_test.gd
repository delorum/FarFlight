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
	assert(out_of_range.reason == "НЕТ СИГНАЛА")
	var flight = FlightModelScript.new(test_world)
	assert(flight.message.is_empty())
	flight.refuel()
	assert(flight.message.begins_with("Самолёт заправлен"))
	assert(not flight.engine_running)
	flight.toggle_engine()
	assert(flight.engine_running)
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.10))
	flight.throttle = 1.0
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.84))
	flight.speed_kmh = 200.0
	assert(absf(flight.estimated_range_km() - 158.730) < 0.01)
	flight.altitude_m = 2500.0
	assert(is_equal_approx(flight.altitude_fuel_factor(), 0.82))
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.6888))
	assert(absf(flight.estimated_range_km() - 193.573) < 0.01)
	assert(is_equal_approx(flight.altitude_power_factor(), 1.0))
	flight.altitude_m = 5000.0
	assert(is_equal_approx(flight.altitude_fuel_factor(), 1.08))
	assert(is_equal_approx(flight.fuel_flow_lpm(), 0.9072))
	assert(is_equal_approx(flight.altitude_power_factor(), 0.82))
	assert(is_equal_approx(flight.max_available_climb_mps(), 0.0))
	flight.altitude_m = 0.0
	flight.throttle = 0.0
	flight.update(3.1)
	assert(flight.message.is_empty())
	var taxi_coast = FlightModelScript.new(test_world)
	taxi_coast.speed_kmh = 50.0
	taxi_coast.throttle = 0.0
	var taxi_brake = FlightModelScript.new(test_world)
	taxi_brake.speed_kmh = 50.0
	taxi_brake.throttle = 0.0
	taxi_brake.wheel_brakes_applied = true
	taxi_coast.update(0.5)
	taxi_brake.update(0.5)
	assert(taxi_brake.speed_kmh < taxi_coast.speed_kmh - 4.0)
	var taxi_out = FlightModelScript.new(test_world)
	var taxi_airport: Dictionary = test_world.airports[0]
	var taxi_forward: Vector2 = test_world.heading_vector(taxi_airport.heading)
	var taxi_right := Vector2(taxi_forward.y, -taxi_forward.x)
	taxi_out.position_km = taxi_airport.position + taxi_right * 0.026
	taxi_out.update(0.1)
	assert(taxi_out.state == FlightModelScript.State.CRASHED)
	assert(taxi_out.message.begins_with("Выехали за пределы ВПП"))
	flight.throttle = 1.0
	flight.yoke = Vector2(0, 0.55)
	for frame in 900:
		flight.update(1.0 / 60.0)
	print("Takeoff state=%d altitude=%.1f speed=%.1f message=%s" % [flight.state, flight.altitude_m, flight.speed_kmh, flight.message])
	assert(flight.state == FlightModelScript.State.FLYING)
	assert(flight.altitude_m > 20.0)
	assert(not flight.stalled)

	var climbing_over_runway = FlightModelScript.new(test_world)
	climbing_over_runway.engine_running = true
	climbing_over_runway.state = FlightModelScript.State.FLYING
	climbing_over_runway.altitude_m = 1.0
	climbing_over_runway.speed_kmh = 90.0
	climbing_over_runway.vertical_speed_mps = 1.0
	climbing_over_runway.throttle = 1.0
	climbing_over_runway.yoke.y = 0.5
	climbing_over_runway.update(0.1)
	assert(climbing_over_runway.state == FlightModelScript.State.FLYING)
	var takeoff_grace_test = FlightModelScript.new(test_world)
	takeoff_grace_test.state = FlightModelScript.State.FLYING
	takeoff_grace_test.altitude_m = 1.0
	takeoff_grace_test.speed_kmh = 75.0
	takeoff_grace_test.vertical_speed_mps = -0.5
	takeoff_grace_test.takeoff_grace_remaining = 2.0
	takeoff_grace_test.update(0.1)
	assert(takeoff_grace_test.state == FlightModelScript.State.FLYING)
	assert(takeoff_grace_test.takeoff_grace_remaining < 2.0)
	var full_yoke_takeoff = FlightModelScript.new(test_world)
	full_yoke_takeoff.engine_running = true
	full_yoke_takeoff.throttle = 1.0
	full_yoke_takeoff.yoke.y = 1.0
	var full_yoke_stalled := false
	for frame in 1200:
		full_yoke_takeoff.update(1.0 / 60.0)
		full_yoke_stalled = full_yoke_stalled or full_yoke_takeoff.stalled
		if full_yoke_takeoff.state == FlightModelScript.State.CRASHED:
			break
	# Holding full aft yoke throughout the takeoff is no longer a guaranteed
	# safe technique: the aircraft may stall after rotation, especially in
	# disturbed air.
	assert(full_yoke_stalled or full_yoke_takeoff.state == FlightModelScript.State.CRASHED)

	# A sharp pull exceeds the critical angle of attack. The stall persists
	# until the nose is lowered and sufficient airspeed is restored.
	var stall_test = FlightModelScript.new(test_world)
	stall_test.engine_running = true
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
	# Keeping the yoke fully aft must no longer overpower the automatic nose
	# drop. Observe at least one negative-pitch recovery phase before release.
	var minimum_stall_pitch: float = stall_test.pitch_deg
	for frame in 180:
		stall_test.update(1.0 / 60.0)
		minimum_stall_pitch = minf(minimum_stall_pitch, stall_test.pitch_deg)
	assert(minimum_stall_pitch < -1.0)
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
	ceiling_test.engine_running = true
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
	# Allow 0.1 km/h around the expected 10 km/h loss: the automatic nose
	# drop can begin accelerating the aircraft just before that exact threshold.
	var ceiling_speed_loss_tolerance_kmh := 0.1
	assert(ceiling_start_speed - ceiling_min_speed >= 10.0 - ceiling_speed_loss_tolerance_kmh)
	assert(ceiling_test.altitude_m < 5000.0)

	# At equal power a descending aircraft gains speed from gravity, unlike an
	# otherwise identical aircraft in level flight.
	var level_test = FlightModelScript.new(test_world)
	level_test.engine_running = true
	level_test.state = FlightModelScript.State.FLYING
	level_test.position_km = Vector2(45, 45)
	level_test.altitude_m = 2500.0
	level_test.speed_kmh = 120.0
	level_test.throttle = 0.45
	var dive_test = FlightModelScript.new(test_world)
	dive_test.engine_running = true
	dive_test.state = FlightModelScript.State.FLYING
	dive_test.position_km = Vector2(45, 45)
	dive_test.altitude_m = 2500.0
	dive_test.speed_kmh = 120.0
	dive_test.throttle = 0.45
	dive_test.yoke.y = -0.75
	for frame in 300:
		level_test.update(1.0 / 60.0)
		dive_test.update(1.0 / 60.0)
	assert(dive_test.vertical_speed_mps < -2.0)
	assert(dive_test.speed_kmh > level_test.speed_kmh + 5.0)
	var airport: Dictionary = test_world.airports[1]
	flight.position_km = airport.position
	flight.heading_deg = airport.heading
	flight.altitude_m = 1.0
	flight.speed_kmh = 90.0
	flight.vertical_speed_mps = -2.0
	flight.throttle = 0.0
	flight.yoke = Vector2.ZERO
	for frame in 120:
		flight.update(1.0 / 60.0)
		if flight.state != FlightModelScript.State.FLYING:
			break
	assert(flight.state == FlightModelScript.State.ROLLING)
	var coasting_speed: float = flight.speed_kmh
	flight.update(1.0)
	assert(flight.state == FlightModelScript.State.ROLLING)
	assert(flight.speed_kmh > coasting_speed - 0.5)
	flight.wheel_brakes_applied = true
	for frame in 1200:
		flight.update(1.0 / 60.0)
		if flight.state != FlightModelScript.State.ROLLING:
			break
	assert(flight.state == FlightModelScript.State.LANDED)
	assert(flight.speed_kmh == 0.0)
	assert(is_equal_approx(FlightWorldScript.RUNWAY_WIDTH_KM, 0.05))
	flight.wheel_brakes_applied = false
	flight.throttle = 1.0
	flight.yoke.y = 0.55
	for frame in 900:
		flight.update(1.0 / 60.0)
		if flight.state == FlightModelScript.State.FLYING:
			break
	assert(flight.state == FlightModelScript.State.FLYING)

	var rollout_failure = FlightModelScript.new(test_world)
	rollout_failure.engine_running = true
	rollout_failure.state = FlightModelScript.State.ROLLING
	rollout_failure.position_km = airport.position + test_world.heading_vector(airport.heading) * 0.85
	rollout_failure.heading_deg = airport.heading
	rollout_failure.airport_index = 1
	rollout_failure.altitude_m = 0.0
	rollout_failure.speed_kmh = 90.0
	rollout_failure.vertical_speed_mps = 0.0
	rollout_failure.throttle = 1.0
	for frame in 600:
		rollout_failure.update(1.0 / 60.0)
		if rollout_failure.state != FlightModelScript.State.ROLLING:
			break
	assert(rollout_failure.state == FlightModelScript.State.CRASHED)
	assert(rollout_failure.message.begins_with("Выкатились за пределы ВПП"))

	var short_landing = FlightModelScript.new(test_world)
	var short_airport: Dictionary = test_world.airports[1]
	var short_direction: Vector2 = test_world.heading_vector(short_airport.heading)
	short_landing.state = FlightModelScript.State.FLYING
	short_landing.position_km = short_airport.position - short_direction * 1.2
	short_landing.heading_deg = short_airport.heading
	short_landing.altitude_m = 1.0
	short_landing.speed_kmh = 90.0
	short_landing.vertical_speed_mps = -2.0
	short_landing.throttle = 0.0
	for frame in 120:
		short_landing.update(1.0 / 60.0)
		if short_landing.state != FlightModelScript.State.FLYING:
			break
	assert(short_landing.state == FlightModelScript.State.CRASHED)
	assert(short_landing.message.begins_with("Касание до ВПП"))

	# Isolate repeatable landing checks from moving weather and earlier flights.
	for airport_index in 2:
		for reverse_direction in [false,true]:
			assert(_test_approach(airport_index,reverse_direction))
			assert(_test_wind_guidance(airport_index,reverse_direction))
	print("Smoke test: 30 worlds, takeoff, four runway approaches and wind guidance OK")
	quit()

func _test_approach(airport_index: int, reverse_direction: bool) -> bool:
	# A centre-mounted beacon is 5 km away at 4 km before the threshold.
	# The 3.3-degree glide path aims 60 m beyond the threshold: 234.098 m.
	var landing_world = FlightWorldScript.new(424242)
	landing_world.storms.clear()
	for layer in landing_world.wind_layers:
		layer.speed_kmh = 0.0
	var approach = FlightModelScript.new(landing_world)
	approach.engine_running = true
	var approach_airport: Dictionary = landing_world.airports[airport_index]
	var approach_heading: float = fposmod(approach_airport.heading + (180.0 if reverse_direction else 0.0),360.0)
	var approach_direction: Vector2 = landing_world.heading_vector(approach_heading)
	approach.position_km = approach_airport.position - approach_direction * 5.0
	approach.heading_deg = approach_heading
	approach.altitude_m = 234.098
	approach.speed_kmh = 100.0
	approach.vertical_speed_mps = 0.0
	approach.throttle = 0.30
	approach.yoke = Vector2.ZERO
	approach.state = FlightModelScript.State.FLYING
	var initial_guidance: Dictionary = approach.landing_guidance(airport_index)
	assert(initial_guidance.signal_available)
	assert(not approach.landing_guidance(airport_index, false).signal_available)
	assert(initial_guidance.in_localizer)
	assert(initial_guidance.in_glide)
	assert(absf(initial_guidance.desired_altitude_m - 234.098) < 0.01)
	assert(absf(initial_guidance.beacon_distance_km - 5.0) < 0.001)
	assert(Vector2(landing_world.beacons[airport_index].position).is_equal_approx(approach_airport.position))
	assert(is_equal_approx(initial_guidance.approach_sign, -1.0 if reverse_direction else 1.0))
	assert(absf(initial_guidance.actual_distance_to_threshold_km - 4.0) < 0.001)
	assert(not approach.touchdown_prediction(airport_index).valid)
	approach.vertical_speed_mps = -1.5
	var predicted_touchdown: Dictionary = approach.touchdown_prediction(airport_index)
	assert(predicted_touchdown.valid)
	assert(predicted_touchdown.distance_from_threshold_km > 0.0)
	assert(predicted_touchdown.distance_from_threshold_km < FlightWorldScript.RUNWAY_LENGTH_KM)
	approach.vertical_speed_mps = 0.0
	var landing_beacon: Dictionary = landing_world.beacons[airport_index]
	approach.position_km = landing_beacon.position + Vector2(16.0, 0.0)
	var unavailable_guidance: Dictionary = approach.landing_guidance(airport_index)
	assert(not unavailable_guidance.signal_available)
	assert(not unavailable_guidance.in_localizer)
	assert(not unavailable_guidance.in_glide)
	approach.position_km = approach_airport.position - approach_direction * 5.0
	var touched_down := false
	for frame in 30000:
		if frame % 60 == 0:
			assert(landing_world.ils_signal(airport_index,approach.position_km,approach.altitude_m,approach.heading_deg).available)
		var distance_to_threshold: float = -(approach.position_km-Vector2(approach_airport.position)).dot(approach_direction) - FlightWorldScript.RUNWAY_LENGTH_KM*0.5
		if approach.state == FlightModelScript.State.FLYING and distance_to_threshold <= 0.05:
			approach.throttle = 0.10
		approach.update(1.0 / 60.0)
		if approach.state == FlightModelScript.State.ROLLING:
			touched_down = true
			assert(landing_world.ils_signal(airport_index,approach.position_km,approach.altitude_m,approach.heading_deg).available)
			approach.throttle = 0.0
			approach.wheel_brakes_applied = true
		if approach.state == FlightModelScript.State.LANDED or approach.state == FlightModelScript.State.CRASHED:
			break
	var final_coords: Vector2 = landing_world.runway_coordinates(approach.position_km, approach_airport)
	print("Approach airport=%d reverse=%s: state=%d along=%.3f cross=%.3f alt=%.1f speed=%.1f vs=%.2f beacon=%.3f" % [airport_index, reverse_direction, approach.state, final_coords.x, final_coords.y, approach.altitude_m, approach.speed_kmh, approach.vertical_speed_mps, approach.position_km.distance_to(landing_beacon.position)])
	assert(touched_down)
	assert(approach.state == FlightModelScript.State.LANDED, approach.message)
	assert(is_zero_approx(approach.speed_kmh))
	assert(absf(final_coords.x) < FlightWorldScript.RUNWAY_LENGTH_KM*0.5)
	assert(absf(final_coords.y) <= FlightWorldScript.RUNWAY_WIDTH_KM*0.5)
	assert(landing_world.ils_signal(airport_index,approach.position_km,approach.altitude_m,approach.heading_deg).available)
	var beyond_far_end: Vector2 = approach_airport.position + approach_direction * (FlightWorldScript.RUNWAY_LENGTH_KM*0.5+0.01)
	assert(not landing_world.ils_signal(airport_index,beyond_far_end,0.0,approach.heading_deg).available)
	return true

func _test_wind_guidance(airport_index: int, reverse_direction: bool) -> bool:
	# Snapshot tests isolate wind-aware instruments from piloting technique:
	# crab angle is not a localizer error; range prediction uses ground speed.
	var wind_world = FlightWorldScript.new(424242)
	wind_world.storms.clear()
	var airport: Dictionary = wind_world.airports[airport_index]
	var runway_heading: float = fposmod(airport.heading+(180.0 if reverse_direction else 0.0),360.0)
	var forward: Vector2 = wind_world.heading_vector(runway_heading)
	var right := Vector2(forward.y,-forward.x)
	var flight = FlightModelScript.new(wind_world)
	flight.engine_running = true
	flight.state = FlightModelScript.State.FLYING
	flight.position_km = Vector2(airport.position)-forward*5.0
	flight.altitude_m = 234.098
	flight.speed_kmh = 100.0
	flight.vertical_speed_mps = -1.5
	flight.heading_deg = runway_heading
	var calm_prediction: Dictionary = flight.touchdown_prediction(airport_index)
	var calm_guidance: Dictionary = flight.landing_guidance(airport_index)
	var seconds_to_touchdown: float = flight.altitude_m/-flight.vertical_speed_mps
	for along_wind in [-20.0,20.0]:
		_set_test_wind(wind_world,forward*along_wind)
		flight.current_wind_kmh = wind_world.wind_at(flight.altitude_m)
		var guidance: Dictionary = flight.landing_guidance(airport_index)
		var prediction: Dictionary = flight.touchdown_prediction(airport_index)
		assert(guidance.in_localizer and guidance.in_glide)
		var expected_shift_km: float = along_wind*seconds_to_touchdown/3600.0
		assert(absf(prediction.distance_from_threshold_km-calm_prediction.distance_from_threshold_km-expected_shift_km) < 0.001)
		assert(absf(guidance.desired_vertical_speed_mps-calm_guidance.desired_vertical_speed_mps*(100.0+along_wind)/100.0) < 0.001)
	for crosswind in [-30.0,30.0]:
		_set_test_wind(wind_world,right*crosswind)
		flight.current_wind_kmh = wind_world.wind_at(flight.altitude_m)
		# Cancel lateral wind with a 17.46-degree crab at 100 km/h airspeed.
		var along_speed := sqrt(100.0*100.0-crosswind*crosswind)
		flight.heading_deg = wind_world.vector_heading(forward*along_speed-right*crosswind)
		var signal_status: Dictionary = wind_world.ils_signal(airport_index,flight.position_km,flight.altitude_m,flight.heading_deg)
		var guidance: Dictionary = flight.landing_guidance(airport_index,signal_status.available)
		assert(signal_status.available and guidance.in_localizer and guidance.in_glide)
		assert(absf(guidance.heading_error_deg) > 14.0)
		assert(absf(guidance.course_error_deg) < 0.01)
		assert(absf(guidance.desired_vertical_speed_mps-calm_guidance.desired_vertical_speed_mps*along_speed/100.0) < 0.001)
		var prediction: Dictionary = flight.touchdown_prediction(airport_index)
		var expected_distance := -4.0+along_speed*seconds_to_touchdown/3600.0
		assert(absf(prediction.distance_from_threshold_km-expected_distance) < 0.001)
		# With no correction the localizer still describes position, but the
		# course readout must expose drift rather than falsely show runway track.
		flight.heading_deg = runway_heading
		guidance = flight.landing_guidance(airport_index,signal_status.available)
		assert(guidance.in_localizer)
		assert(absf(guidance.course_error_deg) > 14.0)
	return true

func _set_test_wind(world, velocity_kmh: Vector2) -> void:
	for layer in world.wind_layers:
		layer.from_deg = fposmod(world.vector_heading(velocity_kmh)+180.0,360.0)
		layer.speed_kmh = velocity_kmh.length()
