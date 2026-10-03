extends RefCounted

const Localization = preload("res://scripts/localization.gd")
const FlightWorld = preload("res://scripts/world.gd")
const FlightModel = preload("res://scripts/flight_model.gd")
const ILSDisplayState = preload("res://scripts/ils_display_state.gd")

const BACKGROUND := Color("071012")
const SCOPE_BACKGROUND := Color("0a0e10")
const FRAME := Color("6f7f85")
const NOSE_MARKER := Color("76b8bd")
const TEXT := Color("d2dde0")
const MUTED_TEXT := Color("b8c5c8")
const GREEN := Color("65d48c")
const YELLOW := Color("e8d274")
const RED := Color("ef645e")
const RUNWAY := Color("a9c0c1")
const DISPLAY_VERTICAL_FOV_DEG := 18.0
const MIN_EYE_HEIGHT_M := 2.0
const CENTERLINE_FIRST_KM := 0.10
const CENTERLINE_DASH_KM := 0.03
const CENTERLINE_PERIOD_KM := 0.06
const CENTERLINE_MIN_MARK_PX := 1.0
const LOCALIZER_DISPLAY_LIMIT := 1.4

static func draw_large(canvas: CanvasItem, rect: Rect2, state: Dictionary) -> void:
	canvas.draw_rect(rect, BACKGROUND, true)
	canvas.draw_rect(rect, FRAME, false, 2.0)
	Localization.draw_string(canvas, ThemeDB.fallback_font, rect.position + Vector2(18, 29), "БОЛЬШОЙ ILS [I]", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36, 19, TEXT)
	if not bool(state.powered):
		_draw_unavailable(canvas, rect, "ПИТАНИЕ ВЫКЛЮЧЕНО")
		return
	if not bool(state.signal_available):
		_draw_unavailable(canvas, rect, "НЕТ СИГНАЛА")
		return
	# Both instrument sizes consume the same scheduled aiming estimate.
	var prediction: Dictionary = state.prediction
	var display_guidance: Dictionary = state.projection
	var layout := display_layout(rect)
	_draw_combined_scope(canvas, layout.scope, display_guidance, prediction)
	_draw_information(canvas, layout.left_info, layout.right_info, state)

static func display_layout(rect: Rect2) -> Dictionary:
	var margin := 24.0
	var gap := 16.0
	# The projection window is geometrically centred in the whole large display;
	# the readouts occupy only the naturally remaining space on either side.
	var scope_size := minf(rect.size.y - 104.0, rect.size.x * 0.40)
	scope_size = maxf(190.0, scope_size)
	var scope := Rect2(rect.get_center() - Vector2.ONE * scope_size * 0.5, Vector2.ONE * scope_size)
	var left_info := Rect2(
		Vector2(rect.position.x + margin, scope.position.y),
		Vector2(maxf(120.0, scope.position.x - gap - (rect.position.x + margin)), scope.size.y)
	)
	var right_info := Rect2(
		Vector2(scope.end.x + gap, scope.position.y),
		Vector2(maxf(120.0, rect.end.x - margin - (scope.end.x + gap)), scope.size.y)
	)
	return {"scope": scope, "left_info": left_info, "right_info": right_info}

static func _draw_unavailable(canvas: CanvasItem, rect: Rect2, message: String) -> void:
	var center := rect.get_center()
	var half := minf(rect.size.x, rect.size.y) * 0.13
	canvas.draw_line(center - Vector2(half, half), center + Vector2(half, half), RED, 4.0, true)
	canvas.draw_line(center + Vector2(half, -half), center + Vector2(-half, half), RED, 4.0, true)
	Localization.draw_string(canvas, ThemeDB.fallback_font, center + Vector2(-170, half + 35), message, HORIZONTAL_ALIGNMENT_CENTER, 340, 18, RED)

static func _draw_combined_scope(canvas: CanvasItem, scope: Rect2, guidance: Dictionary, prediction: Dictionary) -> void:
	canvas.draw_rect(scope, SCOPE_BACKGROUND, true)
	canvas.draw_rect(scope, FRAME, false, 1.5)
	var inner := scope.grow(-18.0)
	var geometry := projected_runway_geometry(inner, guidance)
	_draw_projected_runway(canvas, geometry)
	# The large aircraft cross uses exactly the same localizer/glideslope errors
	# as the small ILS. A short arrow shows its ground-track trend separately.
	var aircraft_marker := localizer_marker_position(inner, guidance)
	var aircraft_error := maxf(absf(float(guidance.localizer_error)), absf(float(guidance.glide_error)))
	var aircraft_color := _parameter_color(aircraft_error, 1.0, 2.0)
	var aircraft_offscale := aircraft_lateral_offscale_info(inner, guidance)
	var nose_offscale := nose_heading_offscale_info(inner, guidance)
	# Separate the two edge readouts if both instruments reach the same side.
	if bool(aircraft_offscale.visible) and bool(nose_offscale.visible) and int(aircraft_offscale.side) == int(nose_offscale.side):
		var aircraft_y := Vector2(aircraft_offscale.position).y
		var nose_y := Vector2(nose_offscale.position).y
		if absf(aircraft_y - nose_y) < 36.0:
			aircraft_offscale.position = Vector2(aircraft_marker.x, clampf(aircraft_y + 18.0, inner.position.y + 18.0, inner.end.y - 18.0))
			nose_offscale.position = Vector2(Vector2(nose_offscale.position).x, clampf(nose_y - 18.0, inner.position.y + 18.0, inner.end.y - 18.0))
	if bool(aircraft_offscale.visible):
		_draw_offscale_arrow(canvas, inner, aircraft_offscale, aircraft_color, false)
	else:
		_draw_aircraft_marker(canvas, inner, aircraft_marker, aircraft_color)
		_draw_ground_track_arrow(canvas, inner, aircraft_marker, guidance, aircraft_color)
	# The compact marker is a nose-direction cue, distinct from the larger
	# aircraft marker above. Beyond the horizontal range it becomes an arrow.
	if bool(nose_offscale.visible):
		_draw_offscale_arrow(canvas, inner, nose_offscale, NOSE_MARKER, true)
	else:
		_draw_nose_marker(canvas, inner, nose_marker_position(inner, guidance))
	if bool(prediction.get("valid", false)):
		var marker := touchdown_cross_position(inner, guidance, prediction)
		_draw_touchdown_marker(canvas, marker, GREEN if prediction_inside_runway(prediction) else RED)

static func projected_runway_geometry(view: Rect2, guidance: Dictionary) -> Dictionary:
	var fallback_distance_km := float(guidance.get("actual_distance_to_threshold_km", 1.0))
	var signed_distance_km := float(guidance.get("signed_distance_to_threshold_km", fallback_distance_km))
	var fallback_altitude_m := maxf(0.0, fallback_distance_km) * 1000.0 * tan(deg_to_rad(FlightModel.GLIDE_SLOPE_DEG))
	var altitude_km := maxf(MIN_EYE_HEIGHT_M, float(guidance.get("aircraft_altitude_m", guidance.get("desired_altitude_m", fallback_altitude_m)))) / 1000.0
	# A fixed focal length and horizon represent a camera whose view angle never
	# changes. Ground points move toward the observer as their signed distance
	# approaches zero instead of the whole runway being re-centred every frame.
	var focal_length := view.size.y * 0.5 / tan(deg_to_rad(DISPLAY_VERTICAL_FOV_DEG * 0.5))
	var horizon_y := view.get_center().y - focal_length * tan(deg_to_rad(FlightModel.GLIDE_SLOPE_DEG))
	var runway_center_x := view.get_center().x
	var runway_half_width_km := FlightWorld.RUNWAY_WIDTH_KM * 0.5
	var bottom_room := maxf(1.0, view.end.y - 2.0 - horizon_y)
	var side_room := maxf(1.0, view.size.x * 0.5 - 2.0)
	# Clip the near part against the lower/side edges of the projection window.
	# Once the threshold passes below the aircraft it therefore remains behind
	# the viewer rather than reappearing and shrinking with an absolute range.
	var near_clip_distance := maxf(0.002, maxf(focal_length * altitude_km / bottom_room, focal_length * runway_half_width_km / side_room))
	var visible_near_distance := maxf(signed_distance_km, near_clip_distance)
	var far_distance_km := maxf(visible_near_distance + 0.001, signed_distance_km + FlightWorld.RUNWAY_LENGTH_KM)
	var near_y := horizon_y + focal_length * altitude_km / visible_near_distance
	var far_y := horizon_y + focal_length * altitude_km / far_distance_km
	var near_half := focal_length * runway_half_width_km / visible_near_distance
	var far_half := focal_length * runway_half_width_km / far_distance_km
	var near_clipped := signed_distance_km < near_clip_distance
	return {
		"center_x": runway_center_x,
		"far_y": far_y,
		"near_y": near_y,
		"far_half": far_half,
		"near_half": near_half,
		"far_left": Vector2(runway_center_x - far_half, far_y),
		"far_right": Vector2(runway_center_x + far_half, far_y),
		"near_left": Vector2(runway_center_x - near_half, near_y),
		"near_right": Vector2(runway_center_x + near_half, near_y),
		"near_clipped": near_clipped,
		"signed_distance_to_threshold_km": signed_distance_km,
		"visible_near_distance_km": visible_near_distance,
		"far_distance_km": far_distance_km,
		"altitude_km": altitude_km,
		"focal_length": focal_length,
		"horizon_y": horizon_y,
	}

static func _draw_projected_runway(canvas: CanvasItem, geometry: Dictionary) -> void:
	var runway_height := float(geometry.near_y) - float(geometry.far_y)
	var stroke := clampf(float(geometry.near_half) * 0.035, 1.0, 2.5)
	canvas.draw_line(geometry.near_left, geometry.far_left, RUNWAY, stroke, true)
	canvas.draw_line(geometry.near_right, geometry.far_right, RUNWAY, stroke, true)
	canvas.draw_line(geometry.far_left, geometry.far_right, RUNWAY, stroke, true)
	if not bool(geometry.near_clipped):
		canvas.draw_line(geometry.near_left, geometry.near_right, RUNWAY, minf(3.0, stroke + 0.5), true)
	var center_x := float(geometry.center_x)
	if not bool(geometry.near_clipped) and float(geometry.near_half) >= 7.0 and runway_height >= 7.0:
		var threshold_y := float(geometry.near_y) - clampf(runway_height * 0.10, 1.5, 6.0)
		for stripe in range(-4, 5):
			if stripe == 0:
				continue
			var stripe_x := center_x + stripe * float(geometry.near_half) / 5.3
			var stripe_half := maxf(0.7, float(geometry.near_half) * 0.035)
			canvas.draw_line(Vector2(stripe_x - stripe_half, threshold_y), Vector2(stripe_x + stripe_half, threshold_y), RUNWAY, stroke)
	# Each dash has a fixed position on the real runway. Its perspective position
	# therefore moves toward the bottom edge and disappears behind the aircraft.
	for dash in projected_centerline_dashes(geometry):
		canvas.draw_line(dash.near_point, dash.far_point, Color(RUNWAY, 0.72), float(dash.width_px), true)

static func projected_centerline_dashes(geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var signed_distance := float(geometry.signed_distance_to_threshold_km)
	var visible_near := float(geometry.visible_near_distance_km)
	var focal_height := float(geometry.focal_length) * float(geometry.altitude_km)
	var center_x := float(geometry.center_x)
	var horizon_y := float(geometry.horizon_y)
	var dash_count := floori((FlightWorld.RUNWAY_LENGTH_KM - CENTERLINE_FIRST_KM - CENTERLINE_DASH_KM) / CENTERLINE_PERIOD_KM) + 1
	for index in dash_count:
		var along_start := CENTERLINE_FIRST_KM + index * CENTERLINE_PERIOD_KM
		var near_distance := maxf(visible_near, signed_distance + along_start)
		var far_distance := signed_distance + along_start + CENTERLINE_DASH_KM
		if far_distance <= near_distance:
			continue
		var near_y := horizon_y + focal_height / near_distance
		var far_y := horizon_y + focal_height / far_distance
		var middle_y := (near_y + far_y) * 0.5
		var mark_half_height := maxf(near_y - far_y, CENTERLINE_MIN_MARK_PX) * 0.5
		result.append({
			"along_start_km": along_start,
			"near_point": Vector2(center_x, middle_y + mark_half_height),
			"far_point": Vector2(center_x, middle_y - mark_half_height),
			"width_px": clampf(float(geometry.focal_length) * 0.001 / near_distance, 1.0, 3.0),
		})
	return result

static func touchdown_cross_position(view: Rect2, guidance: Dictionary, prediction: Dictionary) -> Vector2:
	var geometry := projected_runway_geometry(view, guidance)
	# Project the predicted point through the same fixed camera as the runway.
	# This remains correct after the threshold itself has passed behind the view.
	var point_distance := float(geometry.signed_distance_to_threshold_km) + float(prediction.get("distance_from_threshold_km", 0.0))
	point_distance = maxf(point_distance, float(geometry.visible_near_distance_km))
	var result := Vector2(
		float(geometry.center_x) + float(geometry.focal_length) * float(prediction.get("cross_track_km", 0.0)) / point_distance,
		float(geometry.horizon_y) + float(geometry.focal_length) * float(geometry.altitude_km) / point_distance
	)
	return Vector2(clampf(result.x, view.position.x + 8.0, view.end.x - 8.0), clampf(result.y, view.position.y + 8.0, view.end.y - 8.0))

static func nose_marker_position(view: Rect2, guidance: Dictionary) -> Vector2:
	var half_fov := DISPLAY_VERTICAL_FOV_DEG * 0.5
	var heading_offset := clampf(float(guidance.get("heading_error_deg", 0.0)) / half_fov, -1.0, 1.0)
	# The centre of the projection looks down the nominal glideslope. A nose at
	# Negative target glideslope therefore sits in the middle; a higher pitch moves it upward.
	var pitch_from_view := float(guidance.get("aircraft_pitch_deg", -FlightModel.GLIDE_SLOPE_DEG)) + FlightModel.GLIDE_SLOPE_DEG
	var pitch_offset := clampf(pitch_from_view / half_fov, -1.0, 1.0)
	return Vector2(
		view.get_center().x + heading_offset * (view.size.x * 0.5 - 8.0),
		view.get_center().y - pitch_offset * (view.size.y * 0.5 - 8.0)
	)

static func flight_path_marker_position(view: Rect2, guidance: Dictionary) -> Vector2:
	var half_fov := DISPLAY_VERTICAL_FOV_DEG * 0.5
	var course_offset := clampf(float(guidance.get("course_error_deg", 0.0)) / half_fov, -1.0, 1.0)
	var vertical_from_view := float(guidance.get("flight_path_angle_deg", -FlightModel.GLIDE_SLOPE_DEG)) + FlightModel.GLIDE_SLOPE_DEG
	var vertical_offset := clampf(vertical_from_view / half_fov, -1.0, 1.0)
	return Vector2(
		view.get_center().x + course_offset * (view.size.x * 0.5 - 8.0),
		view.get_center().y - vertical_offset * (view.size.y * 0.5 - 8.0)
	)

static func localizer_marker_position(view: Rect2, guidance: Dictionary) -> Vector2:
	return view.get_center() - Vector2(
		clampf(float(guidance.get("localizer_error", 0.0)), -LOCALIZER_DISPLAY_LIMIT, LOCALIZER_DISPLAY_LIMIT) * view.size.x * 0.30,
		clampf(float(guidance.get("glide_error", 0.0)), -LOCALIZER_DISPLAY_LIMIT, LOCALIZER_DISPLAY_LIMIT) * view.size.y * 0.30
	)

static func aircraft_lateral_offscale_info(view: Rect2, guidance: Dictionary) -> Dictionary:
	var error := float(guidance.get("localizer_error", 0.0))
	if absf(error) <= LOCALIZER_DISPLAY_LIMIT:
		return {"visible": false}
	# Positive localizer error appears left to the pilot, so metres to the
	# right of the runway have the opposite sign.
	var lateral_m := -error * float(guidance.get("localizer_tolerance_km", FlightWorld.RUNWAY_WIDTH_KM * 0.5)) * 1000.0
	return {
		"visible": true,
		"position": localizer_marker_position(view, guidance),
		"side": 1 if lateral_m > 0.0 else -1,
		"label": "ОСЬ %+.0f м" % lateral_m,
	}

static func nose_heading_offscale_info(view: Rect2, guidance: Dictionary) -> Dictionary:
	var heading_error := float(guidance.get("heading_error_deg", 0.0))
	if absf(heading_error) <= DISPLAY_VERTICAL_FOV_DEG * 0.5:
		return {"visible": false}
	return {
		"visible": true,
		"position": nose_marker_position(view, guidance),
		"side": 1 if heading_error > 0.0 else -1,
		"label": "НОС %+.1f°" % heading_error,
	}

static func prediction_inside_runway(prediction: Dictionary) -> bool:
	return ILSDisplayState.prediction_inside_runway(prediction)

static func _draw_nose_marker(canvas: CanvasItem, view: Rect2, center: Vector2) -> void:
	var arm := clampf(view.size.x * 0.035, 11.0, 18.0)
	var gap := 4.0
	canvas.draw_line(center - Vector2(arm, 0), center - Vector2(gap, 0), NOSE_MARKER, 2.0, true)
	canvas.draw_line(center + Vector2(gap, 0), center + Vector2(arm, 0), NOSE_MARKER, 2.0, true)
	canvas.draw_line(center - Vector2(0, arm), center - Vector2(0, gap), NOSE_MARKER, 2.0, true)
	canvas.draw_line(center + Vector2(0, gap), center + Vector2(0, arm), NOSE_MARKER, 2.0, true)
	canvas.draw_circle(center, 2.0, NOSE_MARKER)

static func _draw_offscale_arrow(canvas: CanvasItem, view: Rect2, info: Dictionary, color: Color, label_above: bool) -> void:
	var center: Vector2 = info.position
	var side := float(info.side)
	var tip := Vector2(view.end.x - 3.0 if side > 0.0 else view.position.x + 3.0, center.y)
	canvas.draw_line(center - Vector2(side * 5.0, 0.0), tip, color, 2.0, true)
	canvas.draw_line(tip, tip - Vector2(side * 7.0, 5.0), color, 2.0, true)
	canvas.draw_line(tip, tip - Vector2(side * 7.0, -5.0), color, 2.0, true)
	var label := Localization.text(info.label)
	var font_size := 12
	var font := ThemeDB.fallback_font
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_x := tip.x - label_width - 12.0 if side > 0.0 else tip.x + 12.0
	label_x = clampf(label_x, view.position.x + 4.0, view.end.x - label_width - 4.0)
	var baseline := center.y - 12.0 if label_above else center.y + 22.0
	baseline = clampf(baseline, view.position.y + font_size + 4.0, view.end.y - 4.0)
	canvas.draw_rect(Rect2(Vector2(label_x - 3.0, baseline - font_size - 2.0), Vector2(label_width + 6.0, font_size + 5.0)), Color(SCOPE_BACKGROUND, 0.9), true)
	canvas.draw_string(font, Vector2(label_x, baseline), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

static func _draw_aircraft_marker(canvas: CanvasItem, view: Rect2, center: Vector2, color: Color) -> void:
	var arm := clampf(view.size.x * 0.065, 18.0, 30.0)
	canvas.draw_line(center - Vector2(arm, 0), center + Vector2(arm, 0), color, 2.2, true)
	canvas.draw_line(center - Vector2(0, arm), center + Vector2(0, arm), color, 2.2, true)
	canvas.draw_circle(center, 7.0, BACKGROUND)
	canvas.draw_arc(center, 7.0, 0.0, TAU, 24, color, 2.0, true)

static func _draw_ground_track_arrow(canvas: CanvasItem, view: Rect2, center: Vector2, guidance: Dictionary, color: Color) -> void:
	var direction := Vector2(
		clampf(float(guidance.get("course_error_deg", 0.0)), -9.0, 9.0),
		-clampf(float(guidance.get("flight_path_angle_deg", 0.0)) - float(guidance.get("desired_flight_path_angle_deg", 0.0)), -9.0, 9.0)
	)
	if direction.length() < 0.5:
		return
	var unit := direction.normalized()
	var available := minf(
		(view.end.x - center.x if unit.x > 0.0 else center.x - view.position.x) / maxf(absf(unit.x), 0.001),
		(view.end.y - center.y if unit.y > 0.0 else center.y - view.position.y) / maxf(absf(unit.y), 0.001)
	) - 4.0
	if available < 16.0:
		return
	var start := center + unit * 10.0
	var tip := center + unit * minf(27.0, available)
	canvas.draw_line(start, tip, color, 1.5, true)
	canvas.draw_line(tip, tip - unit * 6.0 + unit.orthogonal() * 3.0, color, 1.5, true)
	canvas.draw_line(tip, tip - unit * 6.0 - unit.orthogonal() * 3.0, color, 1.5, true)

static func _draw_touchdown_marker(canvas: CanvasItem, center: Vector2, color: Color) -> void:
	# A compact diamond keeps the prediction distinct from the ILS cross. The
	# marker exists only when the unchanged-control forward simulation reaches
	# the ground.
	var radius := 7.0
	var points := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	canvas.draw_polyline(points, color, 2.0, true)

static func _draw_information(canvas: CanvasItem, left: Rect2, right: Rect2, state: Dictionary) -> void:
	var line_height := clampf(right.size.y / 12.0, 24.0, 38.0)
	var font_size := clampi(roundi(line_height * 0.48), 12, 16)
	# Keep only the tuned frequency on the left, close to the centred scope.
	_draw_info_line(canvas, left.position.x, left.get_center().y + font_size * 0.35, left.size.x, state.title, TEXT, font_size, HORIZONTAL_ALIGNMENT_RIGHT)

	# Repeat the small ILS' compact information layout on the right.
	var show_forecast: bool = state.show_forecast
	var has_prediction: bool = state.has_prediction
	var row_count := 3 + (1 if show_forecast else 0)
	var row_offset: float = (row_count - 1) * 0.5
	var right_y := right.get_center().y - line_height * row_offset
	draw_info_segments(canvas, right.position.x, right_y, [
		{"text": state.altitude_text, "color": state.altitude_color},
		{"text": state.vertical_speed_text, "color": state.vertical_speed_color},
		{"text": state.speed_text, "color": state.speed_color},
	], font_size)
	right_y += line_height
	draw_info_segments(canvas, right.position.x, right_y, [
		{"text": state.course_text, "color": state.course_color},
		{"text": state.distance_text, "color": TEXT},
	], font_size)
	right_y += line_height
	_draw_info_line(canvas, right.position.x, right_y, right.size.x, state.descent_angle_text, state.descent_angle_color, font_size)
	right_y += line_height
	if has_prediction:
		draw_info_segments(canvas, right.position.x, right_y, [
			{"text": state.touchdown_text, "color": state.touchdown_color},
			{"text": state.lateral_text, "color": state.touchdown_color},
		], font_size, right.size.x)
	elif show_forecast:
		_draw_info_line(canvas, right.position.x, right_y, right.size.x, state.touchdown_text, state.touchdown_color, font_size)
	Localization.draw_string(canvas, ThemeDB.fallback_font, right.position + Vector2(0, right.size.y - 6), "I: КАРТА", HORIZONTAL_ALIGNMENT_LEFT, right.size.x, 12, MUTED_TEXT)

static func _draw_info_line(canvas: CanvasItem, x: float, y: float, width: float, value: String, color: Color, font_size: int, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	Localization.draw_string(canvas, ThemeDB.fallback_font, Vector2(x, y), value, alignment, width, font_size, color)

static func draw_info_segments(canvas: CanvasItem, x: float, y: float, segments: Array, font_size: int, max_width: float = INF) -> void:
	# The small scope has fixed-width rows; preserve all values by fitting each
	# whole row rather than reserving oversized columns for individual values.
	while font_size > 8 and _info_segments_width(segments, font_size) > max_width:
		font_size -= 1
	var cursor := x
	var separator := " • "
	var separator_width := ThemeDB.fallback_font.get_string_size(separator, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	for index in segments.size():
		if index > 0:
			canvas.draw_string(ThemeDB.fallback_font, Vector2(cursor, y), separator, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MUTED_TEXT)
			cursor += separator_width
		var segment: Dictionary = segments[index]
		var localized := Localization.text(segment.text)
		canvas.draw_string(ThemeDB.fallback_font, Vector2(cursor, y), localized, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, segment.color)
		cursor += ThemeDB.fallback_font.get_string_size(localized, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

static func _info_segments_width(segments: Array, font_size: int) -> float:
	var width := 0.0
	for index in segments.size():
		if index > 0:
			width += ThemeDB.fallback_font.get_string_size(" • ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		width += ThemeDB.fallback_font.get_string_size(Localization.text(segments[index].text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return width

static func _parameter_color(error: float, green_limit := 1.0, yellow_limit := 2.0) -> Color:
	return ILSDisplayState.parameter_color(error, green_limit, yellow_limit)
