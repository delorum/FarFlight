extends RefCounted
## One clock and bounded step for physics, needs and flight recording.
## No drawing, input polling or scene objects; consumers handle returned events.
const Flight = preload("res://scripts/flight_model.gd")
const Economy = preload("res://scripts/economy.gd")
const FlightHistory = preload("res://scripts/flight_history.gd")
const Countdown = preload("res://scripts/clock_countdown.gd")
var countdown := Countdown.new()
const TIME_SCALES := [1.0, 2.0, 4.0, 8.0, 16.0]
const MAX_STEP := 1.0 / 30.0
var status_timer := 0.0
var trip_air_distance_km := 0.0
var trip_elapsed_seconds := 0.0
var time_scale_index := 0
var cabin_sleep_progress_seconds := 0.0
var last_economy_flight_state := -1
var flight_history := FlightHistory.new()

static func storm_turning(flight) -> bool:
	return flight.state == Flight.State.FLYING and flight.storm_intensity > 0.01 and absf(flight.storm_roll_bias_deg) > 0.01

static func time_of_day(elapsed_seconds: float) -> float:
	return fposmod(elapsed_seconds, 86400.0)

func advance_clocks(seconds: float, economy, sleeping: bool) -> bool:
	status_timer += seconds
	economy.advance_time(seconds, sleeping)
	return countdown.advance(seconds)

func advance_bed(seconds: float, economy, sleeping: bool) -> void:
	if not sleeping:
		cabin_sleep_progress_seconds = 0.0
		return
	cabin_sleep_progress_seconds += seconds
	while cabin_sleep_progress_seconds >= Economy.BED_REST_SECONDS:
		cabin_sleep_progress_seconds -= Economy.BED_REST_SECONDS
		economy.recover_aircraft_bed_unit()

func advance(real_delta: float, flight, economy, recorder, sleeping: bool) -> Dictionary:
	var events := {"elapsed": 0.0, "map_changed": false, "landed": false, "crashed": false, "world_exit": false, "timer_expired": false}
	var real_remaining := maxf(0.0, real_delta)
	while real_remaining > 0.000001 and flight.state != Flight.State.CRASHED:
		if storm_turning(flight):
			time_scale_index = 0
		var scale: float = TIME_SCALES[time_scale_index]
		var step := countdown.limit_step(minf(MAX_STEP, real_remaining * scale))
		var previous_state: int = flight.state
		var previous_speed: float = flight.speed_kmh
		var previous_position: Vector2 = flight.position_km
		events.timer_expired = advance_clocks(step, economy, sleeping)
		advance_bed(step, economy, sleeping)
		if not economy.game_over_reason.is_empty():
			flight.world.update_weather(step)
			flight._crash(economy.game_over_reason)
		else:
			flight.update(step) # Owns weather evolution as well as aircraft physics.
		if flight.world_exit_reached:
			events.world_exit = true
			events.elapsed += step
			break
		# The panel counter belongs to the current airborne leg. Reset it at the
		# actual liftoff transition, not when the engine starts or the ground roll
		# begins. A touch-and-go remains part of the same leg.
		if previous_state in [Flight.State.PARKED, Flight.State.LANDED] and flight.state == Flight.State.FLYING:
			trip_air_distance_km = 0.0
			trip_elapsed_seconds = 0.0
		flight_history.update(flight, previous_state, previous_position, economy.elapsed_seconds, step)
		if previous_state == Flight.State.FLYING:
			trip_air_distance_km += previous_position.distance_to(flight.position_km)
			trip_elapsed_seconds += step
		if flight.state == Flight.State.LANDED and last_economy_flight_state != Flight.State.LANDED:
			# A complete landing starts a new weather system for the next flight.
			# Touch-and-go remains in ROLLING/FLYING and does not refresh it.
			flight.world.refresh_weather()
			economy.arrive_at_airport(flight.airport_index, flight.world)
			events.landed = true
			events.map_changed = true
		last_economy_flight_state = flight.state
		if recorder.update(flight, previous_state, previous_speed, step):
			events.map_changed = true
		events.elapsed += step
		real_remaining -= step / scale
		if events.timer_expired:
			break
		# Recompute remaining *real* time at 1x after entering a storm. Do not
		# finish a previously allocated 16x frame after cancelling acceleration.
		if storm_turning(flight):
			time_scale_index = 0
	events.crashed = flight.state == Flight.State.CRASHED
	return events

func rest_at_hotel(flight, economy) -> Dictionary:
	var result := {"paid": false, "timer_expired": false, "elapsed": 0.0}
	if not economy.pay_hotel_rest(flight.airport_index):
		return result
	result.paid = true
	result.merge(_advance_ground_rest(Economy.HOTEL_REST_SECONDS, flight, economy, false), true)
	if economy.game_over_reason.is_empty() and result.elapsed >= Economy.HOTEL_REST_SECONDS - 0.000001:
		economy.fatigue = mini(Economy.NEED_SEGMENTS, economy.fatigue + 1)
	return result

static func can_skip_bed_rest(flight) -> bool:
	return flight.state in [Flight.State.PARKED, Flight.State.LANDED] and absf(flight.speed_kmh) < 0.01 and not flight.engine_running

func skip_bed_rest(flight, economy) -> Dictionary:
	if not can_skip_bed_rest(flight):
		return {"allowed": false, "elapsed": 0.0, "timer_expired": false}
	var result := _advance_ground_rest(Economy.BED_SKIP_SECONDS, flight, economy, true)
	result.allowed = true
	return result

func _advance_ground_rest(seconds: float, flight, economy, bed: bool) -> Dictionary:
	var result := {"timer_expired": false, "elapsed": 0.0}
	var remaining := seconds
	# Hotel or stationary engine-off aircraft only: no flight physics to skip.
	# Clocks, needs and weather still advance together and stop at fatal events.
	while remaining > 0.000001 and economy.game_over_reason.is_empty():
		var step := countdown.limit_step(minf(1.0, remaining))
		result.timer_expired = advance_clocks(step, economy, true)
		if bed:
			advance_bed(step, economy, true)
		flight.world.update_weather(step)
		remaining -= step
		result.elapsed += step
		if result.timer_expired:
			break
	return result
