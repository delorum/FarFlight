extends RefCounted
## One set of ILS values and presentation rules for both instrument sizes.

const FlightModel = preload("res://scripts/flight_model.gd")
const FlightWorld = preload("res://scripts/world.gd")
const LandingPredictor = preload("res://scripts/landing_predictor.gd")

const TEXT := Color("d2dde0")
const GREEN := Color("65d48c")
const YELLOW := Color("e8d274")
const RED := Color("ef645e")
const MIN_APPROACH_GROUND_SPEED_KMH := 5.0
const STEEP_ANGLE_CAUTION_MARGIN_DEG := 0.5
const STEEP_ANGLE_DANGER_MARGIN_DEG := 1.5

static func build(flight, airport_index: int, signal_available: bool, prediction: Dictionary, frequency_khz: int) -> Dictionary:
	var guidance: Dictionary = flight.landing_guidance(airport_index, signal_available)
	var powered: bool = flight.electrical_power
	var available: bool = powered and bool(guidance.get("signal_available", false))
	var show_forecast: bool = flight.state == FlightModel.State.FLYING
	var has_prediction: bool = show_forecast and bool(prediction.get("valid", false))
	var desired_vs := float(guidance.get("desired_vertical_speed_mps", 0.0))
	var altitude_color := parameter_color(absf(float(guidance.get("glide_error", 0.0))))
	var vertical_speed_color := parameter_color(absf(flight.vertical_speed_mps - desired_vs) / 0.35)
	var course_color := parameter_color(absf(float(guidance.get("course_error_deg", 0.0))), 1.0, 5.0)
	var speed_color := GREEN if flight.speed_kmh <= 100.0 else (YELLOW if flight.speed_kmh <= 115.0 else RED)
	var touchdown_color := GREEN if has_prediction and prediction_inside_runway(prediction) else (RED if has_prediction else YELLOW)
	var along_ground_speed_kmh := float(guidance.get("along_ground_speed_kmh", 0.0))
	var angle_available: bool = flight.state == FlightModel.State.FLYING and along_ground_speed_kmh >= MIN_APPROACH_GROUND_SPEED_KMH
	var descent_angle: float = descent_angle_deg(flight.vertical_speed_mps, along_ground_speed_kmh) if angle_available else 0.0
	var angle_color: Color = descent_angle_color(descent_angle) if angle_available else TEXT
	var ground_speed_mps := maxf(0.1, flight.ground_speed_kmh() / 3.6)
	var projection := guidance.duplicate()
	projection["aircraft_altitude_m"] = flight.altitude_m
	projection["aircraft_pitch_deg"] = flight.pitch_deg
	projection["flight_path_angle_deg"] = rad_to_deg(atan2(flight.vertical_speed_mps, ground_speed_mps))
	projection["desired_flight_path_angle_deg"] = rad_to_deg(atan2(desired_vs, ground_speed_mps))
	return {
		"powered": powered,
		"signal_available": available,
		"guidance": guidance,
		"projection": projection,
		"prediction": prediction if has_prediction else LandingPredictor.no_touchdown("not_flying"),
		"show_forecast": show_forecast,
		"has_prediction": has_prediction,
		"title": "ILS %03d кГц" % frequency_khz,
		"altitude_text": "H %.1f м" % flight.altitude_m,
		"vertical_speed_text": "VS %+.2f м/с" % flight.vertical_speed_mps,
		"speed_text": "V %.1f км/ч" % flight.speed_kmh,
		"descent_angle_text": "УГОЛ %.1f°" % descent_angle if angle_available else "УГОЛ —",
		"descent_angle_color": angle_color,
		"course_text": "ОТКЛ. ПУТИ %+.1f°" % float(guidance.get("course_error_deg", 0.0)),
		"distance_text": "ДО ВПП %.2f км" % float(guidance.get("actual_distance_to_threshold_km", 0.0)),
		"touchdown_text": "КАСАНИЕ %+.2f км ОТ ТОРЦА" % float(prediction.get("distance_from_threshold_km", 0.0)) if has_prediction else "КАСАНИЕ — НЕ ПРОГНОЗИРУЕТСЯ",
		"lateral_text": "БОК %+.0f м" % (float(prediction.get("cross_track_km", 0.0)) * 1000.0) if has_prediction else "",
		"altitude_color": altitude_color,
		"vertical_speed_color": vertical_speed_color,
		"speed_color": speed_color,
		"course_color": course_color,
		"touchdown_color": touchdown_color,
	}

static func descent_angle_deg(vertical_speed_mps: float, along_ground_speed_kmh: float) -> float:
	if along_ground_speed_kmh < MIN_APPROACH_GROUND_SPEED_KMH:
		return 0.0
	var angle := rad_to_deg(atan2(-vertical_speed_mps, along_ground_speed_kmh / 3.6))
	return 0.0 if absf(angle) < 0.05 else angle

static func descent_angle_color(angle_deg: float) -> Color:
	var excess := angle_deg - FlightModel.GLIDE_SLOPE_DEG
	if excess > STEEP_ANGLE_DANGER_MARGIN_DEG:
		return RED
	if excess > STEEP_ANGLE_CAUTION_MARGIN_DEG:
		return YELLOW
	return GREEN if absf(excess) <= STEEP_ANGLE_CAUTION_MARGIN_DEG else TEXT

static func prediction_inside_runway(prediction: Dictionary) -> bool:
	if not bool(prediction.get("valid", false)) or not bool(prediction.get("safe_landing", true)):
		return false
	var along := float(prediction.get("distance_from_threshold_km", 0.0))
	var cross := absf(float(prediction.get("cross_track_km", 0.0)))
	return along >= 0.0 and along <= FlightWorld.RUNWAY_LENGTH_KM and cross <= FlightWorld.RUNWAY_WIDTH_KM * 0.5

static func parameter_color(error: float, green_limit := 1.0, yellow_limit := 2.0) -> Color:
	if error > yellow_limit:
		return RED
	if error > green_limit:
		return YELLOW
	return GREEN
