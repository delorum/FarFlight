extends RefCounted
## Optional nose-fixed perspective. All runway markings and forecast points
## share this camera; the legacy runway-centred renderer remains untouched.

const World = preload("res://scripts/world.gd")
const HORIZONTAL_FOV_DEG := 80.0
const NEAR_KM := 0.002
const APPROACH_AXIS_LENGTH_KM := 6.0
const APPROACH_AXIS_PERIOD_KM := 0.2
const LOCALIZER_SCALE_LIMIT_M := 200.0

static func approach_axis_segments(view: Rect2, guidance: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	# Fixed ground markings, not a heading ray or a forecast trajectory.
	for index in ceili(APPROACH_AXIS_LENGTH_KM / APPROACH_AXIS_PERIOD_KM):
		var along := -index * APPROACH_AXIS_PERIOD_KM
		var points := segment(view, guidance, Vector2(along, 0), Vector2(along - APPROACH_AXIS_PERIOD_KM * 0.5, 0))
		if points.size() == 2:
			result.append(points)
	return result

static func localizer_scale_state(view: Rect2, guidance: Dictionary) -> Dictionary:
	var error := float(guidance.get("localizer_error", 0.0))
	var half_width := minf(100.0, view.size.x * 0.22)
	var centre := Vector2(view.get_center().x, view.end.y - 8.0)
	var cross_m := error * float(guidance.get("localizer_tolerance_km", World.RUNWAY_WIDTH_KM * 0.5)) * 1000.0
	var cross_km := absf(cross_m) / 1000.0
	return {"centre": centre, "half_width": half_width,
		"pointer": centre + Vector2(clampf(cross_m / LOCALIZER_SCALE_LIMIT_M, -1.0, 1.0) * half_width, 0),
		"offscale": absf(cross_m) > LOCALIZER_SCALE_LIMIT_M, "error": cross_m / (LOCALIZER_SCALE_LIMIT_M * 0.5),
		"position_severity": 0 if cross_km <= World.RUNWAY_WIDTH_KM * 0.5 else (1 if cross_km <= World.RUNWAY_WIDTH_KM else 2)}

static func camera_point(guidance: Dictionary, along_km: float, cross_km: float) -> Vector3:
	var aircraft_cross := float(guidance.get("localizer_error", 0.0)) * float(guidance.get("localizer_tolerance_km", World.RUNWAY_WIDTH_KM * 0.5))
	# The simulation's runway cross axis points left; camera X points right.
	var x := aircraft_cross - cross_km
	var z := float(guidance.get("signed_distance_to_threshold_km", guidance.get("actual_distance_to_threshold_km", 1.0))) + along_km
	var y := -maxf(2.0, float(guidance.get("aircraft_altitude_m", 0.0))) / 1000.0
	var yaw := deg_to_rad(float(guidance.get("heading_error_deg", 0.0)))
	var pitch := deg_to_rad(float(guidance.get("aircraft_pitch_deg", 0.0)))
	var forward := x * sin(yaw) + z * cos(yaw)
	return Vector3(x * cos(yaw) - z * sin(yaw), y * cos(pitch) - forward * sin(pitch), y * sin(pitch) + forward * cos(pitch))

static func project(view: Rect2, point: Vector3) -> Vector2:
	var focal := view.size.x * 0.5 / tan(deg_to_rad(HORIZONTAL_FOV_DEG * 0.5))
	return view.get_center() + Vector2(point.x, -point.y) * focal / maxf(NEAR_KM, point.z)

static func clip_screen(view: Rect2, a: Vector2, b: Vector2) -> PackedVector2Array:
	var delta := b - a
	var start := 0.0
	var end := 1.0
	for axis in 2:
		if absf(delta[axis]) < 0.000001:
			if a[axis] < view.position[axis] or a[axis] > view.end[axis]:
				return PackedVector2Array()
		else:
			var first := (view.position[axis] - a[axis]) / delta[axis]
			var last := (view.end[axis] - a[axis]) / delta[axis]
			start = maxf(start, minf(first, last))
			end = minf(end, maxf(first, last))
	if start > end:
		return PackedVector2Array()
	return PackedVector2Array([a + delta * start, a + delta * end])

static func segment(view: Rect2, guidance: Dictionary, a: Vector2, b: Vector2) -> PackedVector2Array:
	var first := camera_point(guidance, a.x, a.y)
	var last := camera_point(guidance, b.x, b.y)
	if first.z < NEAR_KM and last.z < NEAR_KM:
		return PackedVector2Array()
	if first.z < NEAR_KM:
		first = first.lerp(last, (NEAR_KM - first.z) / (last.z - first.z))
	elif last.z < NEAR_KM:
		last = last.lerp(first, (NEAR_KM - last.z) / (first.z - last.z))
	return clip_screen(view, project(view, first), project(view, last))

static func draw_segment(canvas: CanvasItem, view: Rect2, guidance: Dictionary, a: Vector2, b: Vector2, color: Color) -> void:
	var points := segment(view, guidance, a, b)
	if points.size() == 2:
		canvas.draw_line(points[0], points[1], color, 1.5, true)

static func draw_runway(canvas: CanvasItem, view: Rect2, guidance: Dictionary, color: Color) -> void:
	var half := World.RUNWAY_WIDTH_KM * 0.5
	var length := World.RUNWAY_LENGTH_KM
	for side in [-half, half]:
		draw_segment(canvas, view, guidance, Vector2(0, side), Vector2(length, side), color)
	for along in [0.0, length]:
		draw_segment(canvas, view, guidance, Vector2(along, -half), Vector2(along, half), color)
	var count := floori((length - 0.13) / 0.06) + 1
	for index in count:
		var along := 0.10 + index * 0.06
		draw_segment(canvas, view, guidance, Vector2(along, 0), Vector2(along + 0.03, 0), Color(color, 0.72))
	for stripe in range(-4, 5):
		if stripe != 0:
			var cross := stripe * half / 5.3
			draw_segment(canvas, view, guidance, Vector2(0.012, cross), Vector2(0.045, cross), color)

static func track_point(guidance: Dictionary) -> Vector3:
	var yaw := deg_to_rad(float(guidance.get("course_error_deg", 0.0)) - float(guidance.get("heading_error_deg", 0.0)))
	var angle := deg_to_rad(float(guidance.get("flight_path_angle_deg", 0.0)))
	var pitch := deg_to_rad(float(guidance.get("aircraft_pitch_deg", 0.0)))
	var y := sin(angle)
	var z := cos(angle) * cos(yaw)
	return Vector3(cos(angle) * sin(yaw), y * cos(pitch) - z * sin(pitch), y * sin(pitch) + z * cos(pitch))
