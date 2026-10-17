extends SceneTree
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const State = preload("res://scripts/ils_display_state.gd")
const Art = preload("res://scripts/ils_display_art.gd")
const Localization = preload("res://scripts/localization.gd")
const Glideslope = preload("res://scripts/glideslope.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	for distance in [0.0, 0.5, 4.0, 6.0]:
		var height: float = Glideslope.height_at_distance_m(distance)
		check(is_equal_approx(height, (distance + 0.06) * 1000.0 * tan(deg_to_rad(3.0))), "Shared glide geometry must preserve the three-degree slope and aim offset")
		check(is_equal_approx(Glideslope.distance_at_height_km(height), distance), "Forward and inverse glide geometry must agree")
	check(is_equal_approx(Glideslope.distance_at_height_km(0.0), -0.06), "Low glide intersections must remain beyond the threshold, not clamp to it")
	check(Glideslope.height_at_distance_m(-0.1) == 0.0, "Guidance beyond the aim point must not command negative height")
	check(is_equal_approx(Glideslope.vertical_speed_mps(100.0), -100.0 / 3.6 * tan(deg_to_rad(3.0))), "Target sink rate must use the same slope")
	var world := World.new(424242)
	var flight := Flight.new(world)
	flight.state = Flight.State.FLYING
	flight.electrical_power = true
	flight.speed_kmh = 100
	flight.current_wind_kmh = Vector2.ZERO
	var airport: Dictionary = world.airports[0]
	var slope := tan(deg_to_rad(Flight.GLIDE_SLOPE_DEG)) * 1000.0
	for reverse in [false, true]:
		flight.heading_deg = fposmod(float(airport.heading) + (180.0 if reverse else 0.0), 360.0)
		var forward: Vector2 = world.heading_vector(flight.heading_deg)
		flight.position_km = Vector2(airport.position) - forward * (4.0 + World.RUNWAY_LENGTH_KM * 0.5)
		var target := (4.0 + Flight.GLIDE_TOUCHDOWN_OFFSET_KM) * slope
		check(absf(target - 213) < 1, "The displayed glide height must agree with the 4 km map marker")
		flight.altitude_m = target - 30
		var state := State.build(flight, 0, true, {"valid": false}, 350)
		var capture: Dictionary = state.glide_capture
		check(capture.available and capture.intercept_available and is_equal_approx(capture.error_m, -30), "Both runway directions must identify an aircraft below glideslope")
		check(capture.relation_text == "НИЖЕ 30 м" and capture.color == State.CYAN, "Below-glide readout must be distinct from an above-glide warning")
		check(not capture.has("target_text"), "Compact capture readout must not include the glideslope altitude")
		check(is_equal_approx(capture.level_intercept_distance_km, 30 / slope), "Level intercept must use the same three-degree plane and aiming offset")
		var fixed_altitude: float = flight.altitude_m
		flight.position_km += forward * float(capture.level_intercept_distance_km)
		var joined := State.build(flight, 0, true, {"valid": false}, 350)
		check(joined.glide_capture.on_glide and joined.glide_capture.color == State.GREEN and flight.altitude_m == fixed_altitude, "Flying the displayed distance without changing height must reach glideslope")
		flight.position_km -= forward * float(capture.level_intercept_distance_km)
		flight.altitude_m = target + 30
		var above := State.build(flight, 0, true, {"valid": false}, 350)
		check(above.glide_capture.relation_text == "ВЫШЕ 30 м" and above.glide_capture.color == State.RED and above.glide_capture.level_intercept_distance_km < 0 and String(above.glide_capture.intercept_text).begins_with("ВХОД ПОЗАДИ"), "Above-glide state must warn that level-flight interception is already behind")
		flight.altitude_m = target - 30
		flight.current_wind_kmh = forward * 20
		var tailwind := State.build(flight, 0, true, {"valid": false}, 350)
		flight.current_wind_kmh = -forward * 20
		var headwind := State.build(flight, 0, true, {"valid": false}, 350)
		check(is_equal_approx(tailwind.glide_capture.level_intercept_distance_km, headwind.glide_capture.level_intercept_distance_km), "Pure headwind changes time to interception, not distance")
		flight.current_wind_kmh = Vector2.ZERO
	var guidance := {"signed_distance_to_threshold_km": 4.0, "desired_altitude_m": 213.0, "course_error_deg": 60.0, "along_ground_speed_kmh": 50.0}
	var oblique := State.glideslope_capture(guidance, 183, true)
	check(is_equal_approx(oblique.level_intercept_distance_km, (4.0 - (183 / slope - Flight.GLIDE_TOUCHDOWN_OFFSET_KM)) / 0.5), "Oblique ground track must convert axial distance to actual distance flown")
	guidance.along_ground_speed_kmh = 0.0
	check(not State.glideslope_capture(guidance, 183, true).intercept_available, "A non-closing aircraft must not promise a future interception")
	guidance.signed_distance_to_threshold_km = -0.1
	check(not State.glideslope_capture(guidance, 183, true).available, "Intercept cues must disappear beyond the threshold")
	check(not State.glideslope_capture(guidance, 0, false).available, "Parked aircraft must not show capture guidance")
	var view := Rect2(20, 30, 500, 500)
	var centre: Vector2 = Art.glideslope_scale_geometry(view, 0).centre
	check(Art.glideslope_scale_geometry(view, -30).pointer.y > centre.y and Art.glideslope_scale_geometry(view, 30).pointer.y < centre.y, "Vertical marker must depict aircraft below or above the fixed glideslope reference")
	check(Art.glideslope_scale_geometry(view, 150).offscale, "Large deviations must have an explicit offscale cue")
	var language := Localization.language
	Localization.set_language(Localization.ENGLISH, false)
	check(Localization.text("НИЖЕ 30 м") == "BELOW 30 m" and Localization.text("ДО ГЛИСС 0.57 км") == "GS INT 0.57 km", "Capture readouts must be localized")
	Localization.set_language(language, false)
	print("Glideslope height, level interception, runway directions, wind and scale: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
