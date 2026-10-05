class_name LandingPredictor
extends RefCounted
## Forecasts with an isolated aircraft copy; the real world is never mutated.
## SHORT_TRAJECTORY simulates inertia briefly, then projects constant velocity
## to runway elevation. FULL_SIMULATION retains the original complete approach.
## Both modes omit storms and their future random gusts.

const FlightModel = preload("res://scripts/flight_model.gd")
const FlightWorld = preload("res://scripts/world.gd")

# Five physics samples per predicted second keep a full several-minute approach
# cheap enough for an instrument refresh while retaining metre-scale touchdown
# accuracy (one step is roughly 5 m at normal approach speed).
const STEP_SECONDS := 0.2
const MAX_PREDICTION_SECONDS := 300.0
const MAX_DISTANCE_PAST_RUNWAY_KM := 3.0
const MAX_DISTANCE_FROM_AIRPORT_KM := 25.0
const LATERAL_YOKE_CENTER_RATE := 1.8
enum Mode { FULL_SIMULATION, SHORT_TRAJECTORY }
const SHORT_HORIZON_SECONDS := 4.0

static func no_touchdown(reason: String = "no_intersection") -> Dictionary:
	return {
		"valid": false,
		"distance_from_threshold_km": 0.0,
		"cross_track_km": 0.0,
		"prediction_seconds": 0.0,
		"reason": reason,
	}

static func predict(source, airport_index: int, mode: Mode = Mode.FULL_SIMULATION) -> Dictionary:
	var job := start_prediction(source, airport_index, mode)
	while not job.finished:
		job.advance(1500)
	return job.result

static func start_prediction(source, airport_index: int, mode: Mode = Mode.FULL_SIMULATION) -> PredictionJob:
	return PredictionJob.new(source, airport_index, mode)

class PredictionJob extends RefCounted:
	var simulated
	var airport: Dictionary
	var approach_sign := 1.0
	var elapsed := 0.0
	var finished := false
	var result: Dictionary = LandingPredictor.no_touchdown()
	var mode: LandingPredictor.Mode

	func _init(source, airport_index: int, prediction_mode: LandingPredictor.Mode) -> void:
		mode = prediction_mode
		if source == null or source.state != FlightModel.State.FLYING:
			_finish(LandingPredictor.no_touchdown("not_flying"))
			return
		if airport_index < 0 or airport_index >= source.world.airports.size():
			_finish(LandingPredictor.no_touchdown("invalid_airport"))
			return
		simulated = FlightModel.new(source.world)
		if not simulated.restore_snapshot(source.snapshot(), source.turbulence_rng.state):
			_finish(LandingPredictor.no_touchdown("invalid_state"))
			return
		airport = source.world.airports[airport_index]
		approach_sign = source.world.runway_approach_sign(airport, source.heading_deg)

	func _finish(value: Dictionary) -> void:
		result = value
		finished = true

	func advance(max_steps: int = 64, budget_usec: int = 0) -> void:
		var deadline := Time.get_ticks_usec() + budget_usec
		for step_index in max_steps:
			if finished or (step_index > 0 and budget_usec > 0 and Time.get_ticks_usec() >= deadline):
				return
			simulated.yoke.x = move_toward(simulated.yoke.x, 0.0, STEP_SECONDS * LATERAL_YOKE_CENTER_RATE)
			var previous_state: int = simulated.state
			var previous_position: Vector2 = simulated.position_km
			simulated.update_prediction(STEP_SECONDS)
			elapsed += STEP_SECONDS
			if previous_state == FlightModel.State.FLYING and simulated.state == FlightModel.State.ROLLING:
				_finish(LandingPredictor._impact_result(simulated, airport, approach_sign, elapsed, true, Vector2(simulated.position_km) - previous_position))
			elif simulated.state == FlightModel.State.CRASHED:
				var contact: bool = simulated.altitude_m <= float(simulated.world.height_at(simulated.position_km)) + FlightModel.GROUND_CONTACT_CLEARANCE_M + 0.01
				_finish(LandingPredictor._impact_result(simulated, airport, approach_sign, elapsed, false, Vector2(simulated.position_km) - previous_position) if contact else LandingPredictor.no_touchdown("airborne_crash"))
			elif mode == LandingPredictor.Mode.SHORT_TRAJECTORY and elapsed >= SHORT_HORIZON_SECONDS - 0.0001:
				_finish(LandingPredictor._trajectory_result(simulated, airport, approach_sign, elapsed))
			else:
				var coords: Vector2 = simulated.world.runway_coordinates(simulated.position_km, airport)
				if coords.x * approach_sign + FlightWorld.RUNWAY_LENGTH_KM * 0.5 > FlightWorld.RUNWAY_LENGTH_KM + MAX_DISTANCE_PAST_RUNWAY_KM:
					_finish(LandingPredictor.no_touchdown("passed_runway"))
				elif simulated.position_km.distance_to(Vector2(airport.position)) > MAX_DISTANCE_FROM_AIRPORT_KM:
					_finish(LandingPredictor.no_touchdown("left_approach"))
				elif elapsed >= MAX_PREDICTION_SECONDS:
					_finish(LandingPredictor.no_touchdown("timeout"))

static func _trajectory_result(simulated, airport: Dictionary, approach_sign: float, elapsed: float) -> Dictionary:
	# Only the short horizon models inertia. Beyond it, freeze ground velocity
	# and descent: this is an aiming estimate, not knowledge of future wind layers.
	if simulated.vertical_speed_mps >= -0.05:
		return no_touchdown("not_descending")
	var height: float = simulated.altitude_m - simulated.world.height_at(Vector2(airport.position))
	var seconds: float = maxf(0.0, height) / -simulated.vertical_speed_mps
	if seconds + elapsed > MAX_PREDICTION_SECONDS:
		return no_touchdown("timeout")
	var velocity: Vector2 = simulated.world.heading_vector(simulated.heading_deg) * simulated.speed_kmh + simulated.current_wind_kmh
	var position: Vector2 = simulated.position_km + velocity * (seconds / 3600.0)
	var coords: Vector2 = simulated.world.runway_coordinates(position, airport)
	return {
		"valid": true,
		"distance_from_threshold_km": coords.x * approach_sign + FlightWorld.RUNWAY_LENGTH_KM * 0.5,
		"cross_track_km": coords.y * approach_sign,
		"touchdown_course_error_deg": touchdown_course_error_deg(simulated, airport, approach_sign, velocity),
		"predicted_position": position,
		"prediction_seconds": elapsed + seconds,
		"safe_landing": simulated.vertical_speed_mps > -FlightModel.FATAL_TOUCHDOWN_SINK_MPS,
		"reason": "trajectory_estimate",
	}

static func touchdown_course_error_deg(simulated, airport: Dictionary, approach_sign: float, velocity: Vector2) -> float:
	var runway_heading := float(airport.heading) + (180.0 if approach_sign < 0 else 0.0)
	var course: float = simulated.world.vector_heading(velocity) if velocity.length_squared() > 0.000000000001 else simulated.heading_deg
	return wrapf(course - runway_heading, -180.0, 180.0)

static func _impact_result(simulated, airport: Dictionary, approach_sign: float, elapsed: float, safe_landing: bool, displacement: Vector2) -> Dictionary:
	var coords: Vector2 = simulated.world.runway_coordinates(simulated.position_km, airport)
	return {
		"valid": true,
		"distance_from_threshold_km": coords.x * approach_sign + FlightWorld.RUNWAY_LENGTH_KM * 0.5,
		"cross_track_km": coords.y * approach_sign,
		# Last airborne displacement retains wind and direction even if impact
		# resets the aircraft's speed, pitch or other ground-state values.
		"touchdown_course_error_deg": touchdown_course_error_deg(simulated, airport, approach_sign, displacement),
		"predicted_position": simulated.position_km,
		"prediction_seconds": elapsed,
		"safe_landing": safe_landing,
		"reason": "landing" if safe_landing else "ground_impact",
	}
