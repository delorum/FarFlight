extends SceneTree

const Camera = preload("res://scripts/ils_cockpit_projection.gd")
const Art = preload("res://scripts/ils_display_art.gd")
const State = preload("res://scripts/ils_display_state.gd")
const Localization = preload("res://scripts/localization.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	var view := Rect2(20, 30, 500, 500)
	var guidance := {"signed_distance_to_threshold_km": 6.0, "aircraft_altitude_m": 234.0, "aircraft_pitch_deg": 0.0, "heading_error_deg": 0.0, "localizer_error": 0.0, "localizer_tolerance_km": 0.05}
	var centre := Camera.project(view, Camera.camera_point(guidance, 0, 0))
	check(is_equal_approx(centre.x, view.get_center().x) and centre.y > view.get_center().y, "Level nose must see runway centred below it")
	guidance.heading_error_deg = 10.0
	var crab := Camera.project(view, Camera.camera_point(guidance, 0, 0))
	check(crab.x < centre.x and view.has_point(crab), "Nose right must move runway left; a 10-degree crab must fit")
	guidance.heading_error_deg = 70.0
	check(not view.has_point(Camera.project(view, Camera.camera_point(guidance, 0, 0))), "Runway must leave the window without clamping")
	guidance.heading_error_deg = 0.0
	guidance.localizer_error = 2.0
	check(Camera.project(view, Camera.camera_point(guidance, 0, 0)).x > centre.x, "Aircraft left of runway must see runway right")
	guidance.localizer_error = 0.0
	guidance.aircraft_pitch_deg = 5.0
	check(Camera.project(view, Camera.camera_point(guidance, 0, 0)).y > centre.y, "Raising nose must move ground downward")
	guidance.aircraft_pitch_deg = 0.0
	guidance.signed_distance_to_threshold_km = -0.1
	check(Camera.camera_point(guidance, 0, 0).z < 0, "Passed threshold must remain behind the camera")
	var edge := Camera.segment(view, guidance, Vector2(0, 0.025), Vector2(2, 0.025))
	check(edge.size() == 2, "Runway crossing the near plane must clip rather than disappear")
	for point in edge:
		check(point.x >= view.position.x and point.x <= view.end.x and point.y >= view.position.y and point.y <= view.end.y, "Clipped segments must stay inside the scope")
	guidance.signed_distance_to_threshold_km = 1.0
	var left := Camera.project(view, Camera.camera_point(guidance, 0.1, 0.025))
	var right := Camera.project(view, Camera.camera_point(guidance, 0.1, -0.025))
	var touchdown := Camera.project(view, Camera.camera_point(guidance, 0.1, 0.0))
	check(touchdown.is_equal_approx((left + right) * 0.5), "Forecast on axis must share the runway's camera and projection")
	guidance.course_error_deg = 0.0
	guidance.heading_error_deg = 10.0
	guidance.flight_path_angle_deg = -3.0
	check(Camera.project(view, Camera.track_point(guidance)).x < view.get_center().x, "Track compensated for a right-pointing nose must appear left")
	check(Art.USE_COCKPIT_PERSPECTIVE, "New renderer must be enabled, with legacy helpers still available")
	guidance.heading_error_deg = 0.0
	guidance.localizer_error = 0.0
	var axis := Camera.approach_axis_segments(view, guidance)
	check(not axis.is_empty(), "Extended runway axis must be visible before the threshold")
	for points in axis:
		check(is_equal_approx(points[0].x, view.get_center().x) and is_equal_approx(points[1].x, view.get_center().x), "Axis extension must align with runway centre")
	var scale := Camera.localizer_scale_state(view, guidance)
	check(Vector2(scale.pointer).is_equal_approx(scale.centre), "Aircraft on axis must centre the localizer scale")
	guidance.localizer_error = 1.0
	var offset := Camera.localizer_scale_state(view, guidance)
	check(Vector2(offset.pointer).x > Vector2(offset.centre).x, "Runway axis right of aircraft must move scale pointer right")
	guidance.heading_error_deg = 25.0
	check(Vector2(Camera.localizer_scale_state(view, guidance).pointer).is_equal_approx(offset.pointer), "Scale must measure position, not nose heading")
	guidance.localizer_error = -5.0
	check(Camera.localizer_scale_state(view, guidance).offscale, "Large deviation must use an explicit offscale cue")
	guidance.localizer_tolerance_km = 0.2
	guidance.localizer_error = 0.5
	check(Camera.localizer_scale_state(view, guidance).position_severity == 2, "100 metres off axis must be red despite a wide ILS capture tolerance")
	guidance.localizer_error = 0.2
	check(Camera.localizer_scale_state(view, guidance).position_severity == 1, "40 metres off axis must be caution")
	guidance.localizer_error = 0.1
	check(Camera.localizer_scale_state(view, guidance).position_severity == 0, "20 metres off axis must be inside runway width")
	guidance.localizer_error = -0.385
	var distant_scale := Camera.localizer_scale_state(view, guidance)
	guidance.localizer_tolerance_km = 0.1
	guidance.localizer_error = -0.77
	check(Vector2(Camera.localizer_scale_state(view, guidance).pointer).is_equal_approx(distant_scale.pointer), "Same 77-metre offset must keep the same scale position despite narrowing ILS tolerance")
	guidance.localizer_error = -0.5
	check(Vector2(Camera.localizer_scale_state(view, guidance).pointer).x > Vector2(distant_scale.pointer).x, "Closing from 77 to 50 metres on the left must move pointer right towards centre")
	guidance.localizer_tolerance_km = 0.05
	guidance.signed_distance_to_threshold_km = -0.1
	guidance.heading_error_deg = 0.0
	check(Camera.approach_axis_segments(view, guidance).is_empty(), "Axis before the threshold must pass behind the viewer after crossing it")
	guidance.signed_distance_to_threshold_km = 0.1
	guidance.ground_speed_kmh = 144.0
	guidance.localizer_error = 1.0
	guidance.course_error_deg = 3.0
	var closing := State.axis_motion(guidance)
	check(closing.closing_mps > 2.0 and closing.error_rate < 0.0 and closing.motion_color == State.GREEN, "Moving right towards an axis on the right must be closing with a leftward scale trend")
	check(closing.axis_text == "ОСЬ → 50 м", "Axis direction and metres must describe current position, not forecast")
	check(closing.motion_text == "СБЛ. +2.1 м/с", "Rightward closing must show a positive velocity")
	guidance.course_error_deg = -3.0
	var departing := State.axis_motion(guidance)
	check(departing.closing_mps < 0.0 and departing.error_rate > 0.0 and departing.motion_color == State.YELLOW, "Moving away must show outward trend and warning colour")
	check(departing.motion_text == "УХОД -2.1 м/с", "Leftward divergence must show a negative velocity")
	guidance.localizer_error = -1.0
	check(State.axis_motion(guidance).closing_mps > 0, "Closing must also work on the opposite side")
	check(State.axis_motion(guidance).motion_text == "СБЛ. -2.1 м/с", "Leftward closing must retain its negative sign")
	guidance.course_error_deg = 3.0
	check(State.axis_motion(guidance).motion_text == "УХОД +2.1 м/с", "Rightward divergence must retain its positive sign")
	guidance.course_error_deg = 0.0
	check(State.axis_motion(guidance).motion_text == "ПАРАЛЛ.", "Parallel ground track must show no lateral closing")
	guidance.localizer_error = 0.0
	guidance.course_error_deg = 3.0
	check(State.axis_motion(guidance).motion_color == State.YELLOW, "Crossing the axis must not falsely show continued closing")
	guidance.ground_speed_kmh = 0.0
	check(is_zero_approx(float(State.axis_motion(guidance).error_rate)), "Stationary aircraft must have no trend")
	check(is_equal_approx(Art.localizer_trend_arrow_length(0.001, 100.0), 8.0), "Slow subpixel movement must immediately show a readable arrow")
	check(is_equal_approx(Art.localizer_trend_arrow_length(-0.001, 100.0), -8.0), "Slow movement in the opposite direction must remain visible")
	check(is_zero_approx(Art.localizer_trend_arrow_length(0.0, 100.0)), "Stationary pointer must have no trend arrow")
	check(is_equal_approx(Art.localizer_trend_arrow_length(1.0, 100.0), 25.0), "Fast trend must keep a bounded arrow length")
	Localization.language = Localization.ENGLISH
	check(Localization.text(closing.axis_text) == "AXIS → 50 m", "Dynamic axis indication must translate")
	check(Localization.text(closing.motion_text).begins_with("CLOSING "), "Closing speed must translate")
	Localization.language = Localization.RUSSIAN
	print("Nose-fixed ILS perspective and clipping: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
