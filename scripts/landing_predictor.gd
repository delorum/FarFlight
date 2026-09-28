class_name LandingPredictor
extends RefCounted
## Forward-simulates an isolated aircraft copy with unchanged pilot controls.
## The real world and aircraft are never mutated. Wind layers are sampled at
## every predicted altitude; storms and their future random gusts are omitted.

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

static func no_touchdown(reason: String = "no_intersection") -> Dictionary:
	return {
		"valid": false,
		"distance_from_threshold_km": 0.0,
		"cross_track_km": 0.0,
		"prediction_seconds": 0.0,
		"reason": reason,
	}

static func predict(source, airport_index: int) -> Dictionary:
	if source == null or source.state != FlightModel.State.FLYING:
		return no_touchdown("not_flying")
	if airport_index < 0 or airport_index >= source.world.airports.size():
		return no_touchdown("invalid_airport")
	var simulated := FlightModel.new(source.world)
	if not simulated.restore_snapshot(source.snapshot(), source.turbulence_rng.state):
		return no_touchdown("invalid_state")
	var airport: Dictionary = source.world.airports[airport_index]
	var approach_sign: float = source.world.runway_approach_sign(airport, source.heading_deg)
	var elapsed := 0.0
	while elapsed < MAX_PREDICTION_SECONDS:
		# With no new input the real cockpit recentres only the lateral yoke axis;
		# throttle and longitudinal yoke position remain where the pilot left them.
		simulated.yoke.x = move_toward(simulated.yoke.x, 0.0, STEP_SECONDS * LATERAL_YOKE_CENTER_RATE)
		var previous_state: int = simulated.state
		simulated.update_prediction(STEP_SECONDS)
		elapsed += STEP_SECONDS
		if previous_state == FlightModel.State.FLYING and simulated.state == FlightModel.State.ROLLING:
			return _impact_result(simulated, airport, approach_sign, elapsed, true)
		if simulated.state == FlightModel.State.CRASHED:
			var terrain_contact: bool = simulated.altitude_m <= float(source.world.height_at(simulated.position_km)) + FlightModel.GROUND_CONTACT_CLEARANCE_M + 0.01
			return _impact_result(simulated, airport, approach_sign, elapsed, false) if terrain_contact else no_touchdown("airborne_crash")
		var coords: Vector2 = source.world.runway_coordinates(simulated.position_km, airport)
		var distance_from_threshold := coords.x * approach_sign + FlightWorld.RUNWAY_LENGTH_KM * 0.5
		if distance_from_threshold > FlightWorld.RUNWAY_LENGTH_KM + MAX_DISTANCE_PAST_RUNWAY_KM:
			return no_touchdown("passed_runway")
		if simulated.position_km.distance_to(Vector2(airport.position)) > MAX_DISTANCE_FROM_AIRPORT_KM:
			return no_touchdown("left_approach")
	return no_touchdown("timeout")

static func _impact_result(simulated, airport: Dictionary, approach_sign: float, elapsed: float, safe_landing: bool) -> Dictionary:
	var coords: Vector2 = simulated.world.runway_coordinates(simulated.position_km, airport)
	return {
		"valid": true,
		"distance_from_threshold_km": coords.x * approach_sign + FlightWorld.RUNWAY_LENGTH_KM * 0.5,
		"cross_track_km": coords.y * approach_sign,
		"predicted_position": simulated.position_km,
		"prediction_seconds": elapsed,
		"safe_landing": safe_landing,
		"reason": "landing" if safe_landing else "ground_impact",
	}
