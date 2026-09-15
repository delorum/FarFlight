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
	var recorder := Recorder.new()
	recorder.reset(flight)
	session.time_scale_index = 4
	var weather_before: float = world.weather_time_seconds
	var clock_before: float = session.clock_seconds
	var result := session.advance(1.0, flight, economy, recorder, false)
	assert(is_equal_approx(result.elapsed, 16.0))
	assert(is_equal_approx(session.clock_seconds - clock_before, result.elapsed))
	assert(is_equal_approx(economy.elapsed_seconds, result.elapsed))
	assert(is_equal_approx(world.weather_time_seconds - weather_before, result.elapsed))

	var storm_flight := StormFlight.new(world)
	storm_flight.state = Flight.State.FLYING
	storm_flight.altitude_m = 5000.0
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
	clock_before = session.clock_seconds
	result = session.advance(1.0, storm_flight, economy, recorder, false)
	assert(result.crashed and result.elapsed <= Session.MAX_STEP + 0.000001)
	assert(recorder.trajectory_finished, "Fatal needs must finish the flight log, not bypass recording")
	assert(is_equal_approx(session.clock_seconds - clock_before, world.weather_time_seconds - weather_before))
	assert(is_equal_approx(recorder.trajectory_elapsed_seconds, session.trip_elapsed_seconds))

	var hotel_world := World.new(424242)
	var hotel_flight := Flight.new(hotel_world)
	var hotel_economy := Economy.new(hotel_world)
	var hotel_session := Session.new()
	hotel_economy.fatigue = 2
	clock_before = hotel_session.clock_seconds
	weather_before = hotel_world.weather_time_seconds
	assert(hotel_session.rest_at_hotel(hotel_flight, hotel_economy))
	assert(hotel_economy.fatigue == 3)
	assert(is_equal_approx(hotel_session.clock_seconds - clock_before, Economy.HOTEL_REST_SECONDS))
	assert(is_equal_approx(hotel_world.weather_time_seconds - weather_before, Economy.HOTEL_REST_SECONDS))
	assert(is_equal_approx(hotel_economy.elapsed_seconds, Economy.HOTEL_REST_SECONDS))

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
