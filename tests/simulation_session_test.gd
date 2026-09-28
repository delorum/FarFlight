extends SceneTree
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Economy = preload("res://scripts/economy.gd")
const Session = preload("res://scripts/simulation_session.gd")
const Recorder = preload("res://scripts/flight_recorder.gd")

# Inject a disturbance at a known integration boundary, not a rendered frame.
class StormFlight extends "res://scripts/flight_model.gd":
	func update(delta: float) -> void:
		super.update(delta)
		storm_intensity = 1.0
		storm_roll_bias_deg = 2.0

func _initialize() -> void:
	var world := World.new(424242)
	world.storms.clear()
	var flight := Flight.new(world)
	var economy := Economy.new(world)
	var session := Session.new()
	assert(is_zero_approx(Session.time_of_day(economy.elapsed_seconds)), "Game time starts at day 1 midnight")
	assert(is_equal_approx(Session.time_of_day(86401.0), 1.0), "The single time source must wrap at midnight without losing the elapsed day")
	var recorder := Recorder.new()
	recorder.reset(flight)
	session.time_scale_index = 4
	var weather_before: float = world.weather_time_seconds
	var clock_before: float = Session.time_of_day(economy.elapsed_seconds)
	var result := session.advance(1.0, flight, economy, recorder, false)
	assert(is_equal_approx(result.elapsed, 16.0))
	assert(is_equal_approx(Session.time_of_day(economy.elapsed_seconds) - clock_before, result.elapsed))
	assert(is_equal_approx(economy.elapsed_seconds, result.elapsed))
	assert(is_equal_approx(world.weather_time_seconds - weather_before, result.elapsed))

	var takeoff_flight := Flight.new(world)
	takeoff_flight.state = Flight.State.LANDED
	takeoff_flight.engine_running = true
	takeoff_flight.departure_authorized = true
	takeoff_flight.throttle = 1.0
	takeoff_flight.speed_kmh = 80.0
	takeoff_flight.pitch_deg = 10.0
	takeoff_flight.yoke.y = 1.0
	var takeoff_session := Session.new()
	takeoff_session.trip_air_distance_km = 12.0
	takeoff_session.trip_elapsed_seconds = 345.0
	var takeoff_recorder := Recorder.new()
	takeoff_recorder.reset(takeoff_flight)
	takeoff_session.advance(Session.MAX_STEP, takeoff_flight, economy, takeoff_recorder, false)
	assert(takeoff_flight.state == Flight.State.FLYING, "Takeoff fixture must reach the airborne state")
	assert(is_zero_approx(takeoff_session.trip_air_distance_km) and is_zero_approx(takeoff_session.trip_elapsed_seconds), "Panel trip distance and time must start at zero on actual liftoff")

	var touch_and_go := Flight.new(world)
	touch_and_go.state = Flight.State.ROLLING
	touch_and_go.engine_running = true
	touch_and_go.departure_authorized = true
	touch_and_go.throttle = 1.0
	touch_and_go.speed_kmh = 80.0
	touch_and_go.pitch_deg = 10.0
	touch_and_go.yoke.y = 1.0
	var touch_and_go_session := Session.new()
	touch_and_go_session.trip_air_distance_km = 12.0
	touch_and_go_session.trip_elapsed_seconds = 345.0
	var touch_and_go_recorder := Recorder.new()
	touch_and_go_recorder.reset(touch_and_go)
	touch_and_go_session.advance(Session.MAX_STEP, touch_and_go, economy, touch_and_go_recorder, false)
	assert(touch_and_go.state == Flight.State.FLYING, "Touch-and-go fixture must return airborne")
	assert(is_equal_approx(touch_and_go_session.trip_air_distance_km, 12.0) and is_equal_approx(touch_and_go_session.trip_elapsed_seconds, 345.0), "Touch-and-go must preserve the current leg counter")

	var storm_flight := StormFlight.new(world)
	storm_flight.state = Flight.State.FLYING
	storm_flight.altitude_m = Flight.ABSOLUTE_CEILING_M - 50.0
	storm_flight.speed_kmh = 180.0
	recorder.reset(storm_flight)
	result = session.advance(1.0, storm_flight, economy, recorder, false)
	assert(session.time_scale_index == 0)
	assert(result.elapsed > 1.0 and result.elapsed < 1.04, "Only the first substep may use 16x before a storm cancels it")

	session.time_scale_index = 4
	economy.hunger = 1
	economy.need_accumulator_seconds = 3599.99
	storm_flight.storm_roll_bias_deg = 0.0
	weather_before = world.weather_time_seconds
	clock_before = Session.time_of_day(economy.elapsed_seconds)
	result = session.advance(1.0, storm_flight, economy, recorder, false)
	assert(result.crashed and result.elapsed <= Session.MAX_STEP + 0.000001)
	assert(recorder.trajectory_finished, "Fatal needs must finish the flight log, not bypass recording")
	assert(is_equal_approx(Session.time_of_day(economy.elapsed_seconds) - clock_before, world.weather_time_seconds - weather_before))
	assert(is_equal_approx(recorder.trajectory_elapsed_seconds, session.trip_elapsed_seconds))

	var hotel_world := World.new(424242)
	var hotel_flight := Flight.new(hotel_world)
	var hotel_economy := Economy.new(hotel_world)
	var hotel_session := Session.new()
	hotel_economy.fatigue = 2
	clock_before = Session.time_of_day(hotel_economy.elapsed_seconds)
	weather_before = hotel_world.weather_time_seconds
	assert(hotel_session.rest_at_hotel(hotel_flight, hotel_economy))
	assert(hotel_economy.fatigue == 3)
	assert(is_equal_approx(Session.time_of_day(hotel_economy.elapsed_seconds) - clock_before, Economy.HOTEL_REST_SECONDS))
	assert(is_equal_approx(hotel_world.weather_time_seconds - weather_before, Economy.HOTEL_REST_SECONDS))
	assert(is_equal_approx(hotel_economy.elapsed_seconds, Economy.HOTEL_REST_SECONDS))
	hotel_economy.fatigue = Economy.NEED_SEGMENTS
	var full_rest_time: float = hotel_economy.elapsed_seconds
	var full_rest_weather: float = hotel_world.weather_time_seconds
	var full_rest_money: int = hotel_economy.money
	assert(hotel_session.rest_at_hotel(hotel_flight, hotel_economy), "A full-rest hotel visit must still advance the session")
	assert(is_equal_approx(hotel_economy.elapsed_seconds - full_rest_time, Economy.HOTEL_REST_SECONDS))
	assert(is_equal_approx(hotel_world.weather_time_seconds - full_rest_weather, Economy.HOTEL_REST_SECONDS))
	assert(hotel_economy.fatigue == Economy.NEED_SEGMENTS and hotel_economy.money == full_rest_money - hotel_economy.hotel_rest_price(hotel_flight.airport_index))

	var arrival_world := World.new(99117)
	var arrival_flight := Flight.new(arrival_world)
	var arrival_economy := Economy.new(arrival_world)
	var arrival_session := Session.new()
	var arrival_recorder := Recorder.new()
	arrival_recorder.reset(arrival_flight)
	var arrival_wind := arrival_world.wind_layers.duplicate(true)
	var arrival_storms := arrival_world.storms.duplicate(true)
	arrival_flight.state = Flight.State.LANDED
	arrival_flight.speed_kmh = 0.0
	arrival_session.last_economy_flight_state = Flight.State.FLYING
	var arrival_result := arrival_session.advance(0.1, arrival_flight, arrival_economy, arrival_recorder, false)
	assert(arrival_result.landed and arrival_world.wind_layers != arrival_wind and arrival_world.storms != arrival_storms, "Every completed landing must generate wind and storms for the next flight")

	# Preparation is an explicit reservation, not inferred from current heading.
	hotel_flight.prepare_at_airport(2, true)
	hotel_flight.heading_deg += 1.0
	assert(hotel_flight.is_prepared_for(2, true) and not hotel_flight.is_prepared_for(2, false))
	var snapshot := hotel_flight.snapshot()
	var loaded := Flight.new(hotel_world)
	assert(loaded.restore_snapshot(snapshot, hotel_flight.turbulence_rng.state))
	assert(loaded.is_prepared_for(2, true))
	snapshot.erase("prepared_airport_index")
	snapshot.erase("prepared_reverse_direction")
	assert(loaded.restore_snapshot(snapshot, hotel_flight.turbulence_rng.state))
	assert(loaded.is_prepared_for(2, true), "Old saves must migrate the reservation from airport and heading")
	print("Unified simulation clock, storm reset, fatal needs, hotel and preparation snapshots: OK")
	quit()
