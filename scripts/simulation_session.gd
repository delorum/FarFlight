extends RefCounted
## One clock and bounded step for physics, needs and flight recording.
## No drawing, input polling or scene objects; consumers handle returned events.
const Flight = preload("res://scripts/flight_model.gd")
const Economy = preload("res://scripts/economy.gd")
const TIME_SCALES := [1.0, 2.0, 4.0, 8.0, 16.0]
const MAX_STEP := 1.0 / 30.0
var clock_seconds := 12.0 * 3600.0
var status_timer := 0.0
var trip_air_distance_km := 0.0
var trip_elapsed_seconds := 0.0
var time_scale_index := 0
var cabin_sleep_progress_seconds := 0.0
var last_economy_flight_state := -1

static func storm_turning(flight) -> bool:
	return flight.state == Flight.State.FLYING and flight.storm_intensity > 0.01 and absf(flight.storm_roll_bias_deg) > 0.01

func advance_clocks(seconds: float, economy, sleeping: bool) -> void:
	clock_seconds = fmod(clock_seconds + seconds, 86400.0)
	status_timer += seconds
	economy.advance_time(seconds, sleeping)

func advance_bed(seconds: float, economy, sleeping: bool) -> void:
	if not sleeping:
		cabin_sleep_progress_seconds = 0.0
		return
	cabin_sleep_progress_seconds += seconds
	while cabin_sleep_progress_seconds >= Economy.HOTEL_REST_SECONDS:
		cabin_sleep_progress_seconds -= Economy.HOTEL_REST_SECONDS
		economy.recover_aircraft_bed_unit()

func advance(real_delta: float, flight, economy, recorder, sleeping: bool) -> Dictionary:
	var events := {"elapsed": 0.0, "map_changed": false, "landed": false, "crashed": false}
	var real_remaining := maxf(0.0, real_delta)
	while real_remaining > 0.000001 and flight.state != Flight.State.CRASHED:
		if storm_turning(flight):
			time_scale_index = 0
		var scale: float = TIME_SCALES[time_scale_index]
		var step := minf(MAX_STEP, real_remaining * scale)
		var previous_state: int = flight.state
		var previous_speed: float = flight.speed_kmh
		var previous_position: Vector2 = flight.position_km
		advance_clocks(step, economy, sleeping)
		advance_bed(step, economy, sleeping)
		if not economy.game_over_reason.is_empty():
			flight.world.update_weather(step)
			flight._crash(economy.game_over_reason)
		else:
			flight.update(step) # Owns weather evolution as well as aircraft physics.
		if previous_state == Flight.State.FLYING:
			trip_air_distance_km += previous_position.distance_to(flight.position_km)
			trip_elapsed_seconds += step
		if flight.state == Flight.State.LANDED and last_economy_flight_state != Flight.State.LANDED:
			economy.arrive_at_airport(flight.airport_index, flight.world)
			events.landed = true
			events.map_changed = true
		last_economy_flight_state = flight.state
		if recorder.update(flight, previous_state, previous_speed, step):
			events.map_changed = true
		events.elapsed += step
		real_remaining -= step / scale
		# Recompute remaining *real* time at 1x after entering a storm. Do not
		# finish a previously allocated 16x frame after cancelling acceleration.
		if storm_turning(flight):
			time_scale_index = 0
	events.crashed = flight.state == Flight.State.CRASHED
	return events

func rest_at_hotel(flight, economy) -> bool:
	if not economy.pay_hotel_rest(flight.airport_index):
		return false
	var remaining := Economy.HOTEL_REST_SECONDS
	# No flight integration while away in the hotel; clocks/needs/weather
	# still advance together and stop at the same fatal event.
	while remaining > 0.000001 and economy.game_over_reason.is_empty():
		var step := minf(1.0, remaining)
		advance_clocks(step, economy, true)
		flight.world.update_weather(step)
		remaining -= step
	if economy.game_over_reason.is_empty():
		economy.fatigue = mini(Economy.NEED_SEGMENTS, economy.fatigue + 1)
	return true
