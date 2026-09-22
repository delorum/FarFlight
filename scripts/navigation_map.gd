extends RefCounted
const UILayout = preload("res://scripts/ui_layout.gd")
const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode
## Map camera, annotations, wind overlay and rendering; panel/cabin layout stays outside.

const MAP_MARGIN = UILayout.MAP_MARGIN
const PANEL_HEIGHT = UILayout.PANEL_HEIGHT
const RADAR_RANGES_KM := [30.0, 20.0, 10.0, 5.0]
const RADAR_ANNOTATION_RETENTION_KM := 30.0
const WeatherRadarArt = preload("res://scripts/weather_radar_art.gd")
const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
const WIND_OVERLAY_ALTITUDES = FlightWorldScript.WIND_ALTITUDES_M
const APPROACH_DETAIL_MIN_ZOOM := 20.0
const MAX_MAP_ZOOM := 24.0
const ILS_CAPTURE_ARC_SEGMENTS := 12
const INITIAL_MAP_RADIUS_KM := 40.0
const SAMPLE_GRID := 192
const CONTOUR_STEP_M := 250.0
const MEASUREMENT_COLOR := Color("254d9a")
const LINKED_MEASUREMENT_COLOR := Color("c46f24")
const ACTIVE_LINKED_MEASUREMENT_COLOR := Color("b72f29")
var host: Control
var map_zoom := 1.0
var map_center := Vector2.ONE * FlightWorldScript.SIZE_KM * 0.5
var contour_segments: Array[Dictionary] = []
var terrain_peaks: Array[Dictionary] = []
var measurement_lines: Array[Dictionary] = []
var next_measurement_line_id := 1
var pending_measure: Variant = null
var radar_measurement_lines: Array[Dictionary] = []
var radar_pending_measure: Variant = null
var active_measurement_lines: Array[Dictionary]:
	get:
		return radar_measurement_lines if large_weather_radar else measurement_lines
var active_pending_measure: Variant:
	get:
		return radar_pending_measure if large_weather_radar else pending_measure
	set(value):
		if large_weather_radar:
			radar_pending_measure = value
		else:
			pending_measure = value
var dragging_map := false
var map_drag_candidate := false
var map_press_position := Vector2.ZERO
var point_drag_candidate := false
var dragging_measure_point := false
var dragged_measure_connections: Array[Dictionary] = []
var map_canvas: Control
var wind_overlay_index := 0
var last_wind_overlay_altitude_m := -INF
var large_weather_radar := false
var radar_range_index := 0
var hovered_airport_index := -1
var hovered_wind_arrow := false
var hovered_measurement_line_index := -1
var hovered_weather_storm_index := -1
var hovered_weather_storm_anchor := Vector2.INF
var measurement_label_refresh_remaining := 0.0
var measurement_label_ground_speed_kmh := -INF
var weather_briefing_storms: Array[Dictionary] = []
var weather_briefing_time_seconds := 0.0
var weather_briefing_visible := true
var weather_briefing_age_minute := -1

func _init(controller: Control) -> void:
	host = controller

func refresh_weather_briefing() -> void:
	weather_briefing_storms.clear()
	for storm in host.world.storms:
		weather_briefing_storms.append({
			"center": host.world.storm_position(storm),
			"radius_km": float(storm.radius_km),
			"intensity": float(storm.intensity),
			"drift_kmh": Vector2(storm.drift_kmh),
			"radar_lobes": host.world.storm_lobes(storm).duplicate(true),
		})
	weather_briefing_time_seconds = host.economy.elapsed_seconds
	weather_briefing_age_minute = 0
	hovered_weather_storm_index = -1
	hovered_weather_storm_anchor = Vector2.INF
	_queue_map_redraw()

func weather_briefing_snapshot() -> Dictionary:
	return {
		"storms": weather_briefing_storms.duplicate(true),
		"time_seconds": weather_briefing_time_seconds,
		"visible": weather_briefing_visible,
	}.duplicate(true)

static func valid_weather_briefing(data: Variant) -> bool:
	if not data is Dictionary or not data.get("storms") is Array or not data.get("time_seconds") is float or not data.get("visible") is bool:
		return false
	if not is_finite(float(data.time_seconds)) or float(data.time_seconds) < 0.0:
		return false
	for storm in data.storms:
		if not storm is Dictionary or not storm.get("center") is Vector2 or not storm.get("drift_kmh") is Vector2:
			return false
		if not storm.get("radius_km") is float or not storm.get("intensity") is float or not storm.get("radar_lobes") is Array:
			return false
		if float(storm.radius_km) <= 0.0 or not is_finite(float(storm.radius_km)):
			return false
		for lobe in storm.radar_lobes:
			if not lobe is Dictionary or not lobe.get("offset_km") is Vector2 or not lobe.get("radius_scale") is float or not lobe.get("strength") is float:
				return false
	return true

func restore_weather_briefing(data: Dictionary) -> bool:
	if not valid_weather_briefing(data):
		return false
	weather_briefing_storms.assign(data.storms.duplicate(true))
	weather_briefing_time_seconds = data.time_seconds
	weather_briefing_visible = data.visible
	weather_briefing_age_minute = floori(weather_briefing_age_seconds() / 60.0)
	hovered_weather_storm_index = -1
	hovered_weather_storm_anchor = Vector2.INF
	return true

func weather_briefing_age_seconds() -> float:
	return maxf(0.0, host.economy.elapsed_seconds - weather_briefing_time_seconds)

func weather_briefing_age_text() -> String:
	var total_minutes := floori(weather_briefing_age_seconds() / 60.0)
	if total_minutes <= 0:
		return "только что"
	if total_minutes < 60:
		return "%d мин" % total_minutes
	return "%d ч %02d мин" % [total_minutes / 60, total_minutes % 60]

func toggle_weather_briefing() -> void:
	weather_briefing_visible = not weather_briefing_visible
	hovered_weather_storm_index = -1
	hovered_weather_storm_anchor = Vector2.INF
	_queue_map_redraw()
	host.queue_redraw()

func map_rect() -> Rect2:
	return Rect2(MAP_MARGIN, MAP_MARGIN, host.size.x - MAP_MARGIN * 2.0, max(300.0, host.size.y - PANEL_HEIGHT - MAP_MARGIN * 2.0))

func _draw_map_on(canvas: Control) -> void:
	map_canvas = canvas
	if large_weather_radar:
		if host.flight.electrical_power:
			host.weather_radar_cache.update_cache(host.world, host.flight, host.status_timer, RADAR_RANGES_KM[radar_range_index])
		WeatherRadarArt.draw_large(canvas,map_rect(),host.world,host.flight,host.weather_radar_cache.get_texture(),RADAR_RANGES_KM[radar_range_index])
		WeatherRadarArt.draw_storm_motion(canvas, map_rect(), host.world, host.flight, host.get_local_mouse_position(), RADAR_RANGES_KM[radar_range_index])
		if host.flight.electrical_power:
			_draw_radar_measurements(canvas)
		host._draw_economy_hud(canvas, false)
	else:
		_draw_map()
	map_canvas = null

func _toggle_weather_radar() -> void:
	host.weather_radar_cache.invalidate()
	large_weather_radar = not large_weather_radar
	update_weather_storm_hover(-1, Vector2.ZERO)
	# Preserve map camera, finished marks and a pending line, but stop gestures.
	dragging_map = false
	map_drag_candidate = false
	point_drag_candidate = false
	dragging_measure_point = false
	dragged_measure_connections.clear()
	_queue_map_redraw()
	host.queue_redraw()

func _radar_contains(point: Vector2) -> bool:
	return point.distance_to(WeatherRadarArt.scope_center(map_rect())) <= WeatherRadarArt.scope_radius(map_rect())

func _measurement_to_screen(point: Vector2) -> Vector2:
	if not large_weather_radar:
		return world_to_screen(point)
	return WeatherRadarArt.scope_center(map_rect()) + (point - host.flight.position_km).rotated(-deg_to_rad(host.flight.heading_deg)) * WeatherRadarArt.scope_radius(map_rect()) / float(RADAR_RANGES_KM[radar_range_index])

func _measurement_from_screen(point: Vector2) -> Vector2:
	if not large_weather_radar:
		return screen_to_world(point)
	return host.flight.position_km + ((point - WeatherRadarArt.scope_center(map_rect())) * float(RADAR_RANGES_KM[radar_range_index]) / WeatherRadarArt.scope_radius(map_rect())).rotated(deg_to_rad(host.flight.heading_deg))

func _clamp_measurement_screen(point: Vector2) -> Vector2:
	if large_weather_radar:
		var center = WeatherRadarArt.scope_center(map_rect())
		return center + (point - center).limit_length(WeatherRadarArt.scope_radius(map_rect()) - 3.0)
	var rect = map_rect().grow(-3.0)
	return point.clamp(rect.position, rect.end)

func _draw_radar_measurements(canvas: CanvasItem) -> void:
	for line in radar_measurement_lines:
		_draw_radar_measurement(canvas, line.a, line.b, Color("e8d274"))
	if radar_pending_measure != null:
		_draw_radar_measurement(canvas, radar_pending_measure, _snap_map_point(_clamp_measurement_screen(host.get_local_mouse_position())), Color("b9c9ce"))

func _draw_radar_measurement(canvas: CanvasItem, a_world: Vector2, b_world: Vector2, color: Color, center := Vector2.INF, radius := -1.0) -> void:
	var range_km = WeatherRadarArt.RANGE_KM
	if radius < 0.0:
		range_km = RADAR_RANGES_KM[radar_range_index]
		center = WeatherRadarArt.scope_center(map_rect())
		radius = WeatherRadarArt.scope_radius(map_rect())
	var a: Vector2 = center + (a_world - host.flight.position_km).rotated(-deg_to_rad(host.flight.heading_deg)) * radius / range_km
	var b: Vector2 = center + (b_world - host.flight.position_km).rotated(-deg_to_rad(host.flight.heading_deg)) * radius / range_km
	var clipped = WeatherRadarArt.clip_segment(a, b, center, radius - 2.0)
	if clipped.size() == 2:
		canvas.draw_line(clipped[0], clipped[1], color, 1.7 if radius > 50.0 else 1.0, true)
	for point in [a,b]:
		if point.distance_to(center) < radius - 4.0:
			canvas.draw_circle(point, 3.5 if radius > 50.0 else 1.3, color)

func update_dynamic_annotations(delta: float) -> void:
	_prune_distant_radar_measurements()
	var current_briefing_minute := floori(weather_briefing_age_seconds() / 60.0)
	if current_briefing_minute != weather_briefing_age_minute:
		weather_briefing_age_minute = current_briefing_minute
		_queue_map_redraw()
	if measurement_lines.is_empty():
		measurement_label_ground_speed_kmh = host.flight.ground_speed_kmh()
		return
	measurement_label_refresh_remaining -= delta
	if measurement_label_refresh_remaining > 0.0:
		return
	measurement_label_refresh_remaining = 0.5
	var ground_speed: float = host.flight.ground_speed_kmh()
	if not is_equal_approx(ground_speed, measurement_label_ground_speed_kmh):
		measurement_label_ground_speed_kmh = ground_speed
		_queue_map_redraw()

func _prune_distant_radar_measurements() -> void:
	var removed := false
	for index in range(radar_measurement_lines.size() - 1, -1, -1):
		var line: Dictionary = radar_measurement_lines[index]
		if Vector2(line.a).distance_to(host.flight.position_km) > RADAR_ANNOTATION_RETENTION_KM and Vector2(line.b).distance_to(host.flight.position_km) > RADAR_ANNOTATION_RETENTION_KM:
			radar_measurement_lines.remove_at(index)
			removed = true
	if removed:
		dragged_measure_connections.clear()
		dragging_measure_point = false
		point_drag_candidate = false
		_queue_map_redraw()

func _handle_radar_mouse_button(event: InputEventMouseButton) -> void:
	var inside: bool = _radar_contains(event.position) and host.flight.electrical_power
	if inside and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		radar_range_index = clampi(radar_range_index + (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, RADAR_RANGES_KM.size() - 1)
		_queue_map_redraw()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and inside:
		if radar_pending_measure != null:
			radar_pending_measure = null
		else:
			_erase_nearest_measurement(event.position)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and inside:
			map_press_position = event.position
			if radar_pending_measure == null:
				dragged_measure_connections = _find_measure_connections(event.position)
			else:
				dragged_measure_connections.clear()
			point_drag_candidate = not dragged_measure_connections.is_empty()
			map_drag_candidate = not point_drag_candidate
		elif not event.pressed:
			if dragging_measure_point:
				_snap_dragged_measure_point_to_endpoint(_clamp_measurement_screen(event.position))
				_refresh_measurement_max_heights(dragged_measure_connections)
			elif inside and (map_drag_candidate or point_drag_candidate):
				_handle_map_click(event.position)
			map_drag_candidate = false
			point_drag_candidate = false
			dragging_measure_point = false
			dragged_measure_connections.clear()
			host.dragging_throttle = false
			host.dragging_yoke = false
	_queue_map_redraw()

func _queue_map_redraw() -> void:
	if host.map_render_layer != null:
		host.map_render_layer.queue_redraw()

func _draw_map() -> void:
	var rect = map_rect()
	map_canvas.draw_rect(rect, Color("d7d0ad"), true)
	map_canvas.draw_rect(rect, Color("6d6751"), false, 2.0)
	# 10 km coordinate grid.
	for k in range(0, int(FlightWorldScript.SIZE_KM) + 1, 10):
		var a = world_to_screen(Vector2(k, 0))
		var b = world_to_screen(Vector2(k, FlightWorldScript.SIZE_KM))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
		a = world_to_screen(Vector2(0, k))
		b = world_to_screen(Vector2(FlightWorldScript.SIZE_KM, k))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
	_draw_weather_briefing(rect)
	for segment in contour_segments:
		var level: float = segment.level
		var color = Color("806f4b") if int(level) % 500 != 0 else Color("5c4b31")
		var width = 1.0 if int(level) % 500 != 0 else 1.7
		_draw_clipped_map_line(world_to_screen(segment.a), world_to_screen(segment.b), color, width)
	_draw_wind_overlay(rect)
	_draw_contour_labels(rect)
	_draw_terrain_peaks(rect)
	for airport in host.world.airports:
		_draw_airport(airport)
		_draw_approach_point(airport)
	for beacon in host.world.beacons:
		_draw_beacon(beacon)
	ensure_measurement_line_ids()
	var highlighted_line_id: int = host.flight_calculator.highlighted_line_id()
	for line in measurement_lines:
		var line_id := int(line.id)
		var linked: bool = host.flight_calculator.profile_for_line(line_id) >= 0
		var highlighted: bool = line_id == highlighted_line_id
		_draw_measurement(line.a, line.b, measurement_line_color(linked, highlighted), line.get("max_height_m", -1.0), linked, highlighted, line_id)
	if pending_measure != null:
		_draw_measurement(pending_measure, _snap_map_point(host.get_local_mouse_position()), Color(0.1, 0.25, 0.7, 0.55))
	_draw_completed_flight_trajectory()
	host._draw_economy_hud(map_canvas, false)
	_draw_hovered_weather_storm_motion(rect)
	_draw_hovered_airport_services(rect)
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), "НАВИГАЦИОННАЯ КАРТА", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("35372e"))
	var wind_altitude_label: String
	if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size():
		wind_altitude_label = "текущая %.0f м" % host.flight.altitude_m
	elif wind_overlay_index == 0:
		wind_altitude_label = "у поверхности"
	else:
		wind_altitude_label = "%d м" % roundi(float(WIND_OVERLAY_ALTITUDES[wind_overlay_index]))
	var wind_hint = "V: ветер [%s]" % wind_altitude_label
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 39), "Метеосводка: возраст %s" % weather_briefing_age_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var map_hints = [
		wind_hint,
		"ЛКМ: точка/линия",
		"ЛКМ с движением: карта",
		"ПКМ: отмена/стереть",
		"Колесо: масштаб",
		"Колесо над приёмником: 1 кГц, с Shift: 10 кГц",
	]
	for hint_index in map_hints.size():
		map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 58 + hint_index * 17), map_hints[hint_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var scale_km = 10.0
	var scale_px = scale_km * pixels_per_km()
	var scale_start = rect.end - Vector2(scale_px + 18, 18)
	map_canvas.draw_line(scale_start, scale_start + Vector2(scale_px, 0), Color("25271f"), 3)
	map_canvas.draw_string(ThemeDB.fallback_font, scale_start - Vector2(0, 6), "10 км", HORIZONTAL_ALIGNMENT_CENTER, scale_px, 12, Color("25271f"))

func _draw_hovered_airport_services(rect: Rect2) -> void:
	var mouse = host.get_local_mouse_position()
	if not rect.has_point(mouse):
		return
	var text := measurement_line_description_at(mouse)
	# A storm has its own local arrow and label, like the weather radar, so do
	# not repeat the same information in the map-wide footer.
	if text.is_empty() and weather_briefing_storm_at(mouse) >= 0:
		return
	if text.is_empty():
		var index := _airport_hover_index(mouse)
		if _wind_arrow_hovered(mouse):
			text = "Ветер: " + _wind_arrow_description()
		elif index >= 0:
			var airport: Dictionary = host.world.airports[index]
			text = "%s: %s" % [airport.name, ", ".join(host.economy.services_at(index))]
	if not text.is_empty():
		map_canvas.draw_rect(Rect2(rect.position.x + 8, rect.end.y - 47, minf(520.0, rect.size.x - 16), 25), Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 14, rect.end.y - 29), text, HORIZONTAL_ALIGNMENT_LEFT, minf(508.0, rect.size.x - 28), 12, Color("35372e"))

func measurement_line_description_at(screen_position: Vector2) -> String:
	if large_weather_radar or not map_rect().has_point(screen_position):
		return ""
	var line_index := _measurement_line_index_at(screen_position)
	if line_index < 0:
		return ""
	var line: Dictionary = measurement_lines[line_index]
	var line_id := int(line.get("id", -1))
	var directed: bool = host.flight_calculator.profile_for_line(line_id) >= 0
	return _measurement_label_text(line.a, line.b, line.get("max_height_m", -1.0), directed, line_id)

func weather_briefing_motion_text(storm: Dictionary) -> String:
	var drift := Vector2(storm.drift_kmh)
	var approximate_heading := (roundi(host.world.vector_heading(drift) / 10.0) * 10) % 360
	var approximate_speed := maxi(5, roundi(drift.length() / 5.0) * 5)
	return "≈%03d° • ≈%d км/ч" % [approximate_heading, approximate_speed]

func update_weather_storm_hover(storm_index: int, pointer: Vector2) -> bool:
	if storm_index == hovered_weather_storm_index:
		return false
	hovered_weather_storm_index = storm_index
	# Capture the first visible point inside the cell. The annotation remains
	# there until the pointer leaves this storm instead of following every motion.
	hovered_weather_storm_anchor = pointer if storm_index >= 0 else Vector2.INF
	return true

func _draw_hovered_weather_storm_motion(rect: Rect2) -> void:
	var storm_index := hovered_weather_storm_index
	if storm_index < 0:
		return
	var storm: Dictionary = weather_briefing_storms[storm_index]
	var velocity := Vector2(storm.drift_kmh)
	var direction := velocity.normalized()
	var origin := Vector2(
		clampf(hovered_weather_storm_anchor.x, rect.position.x + 48.0, rect.end.x - 48.0),
		clampf(hovered_weather_storm_anchor.y, rect.position.y + 48.0, rect.end.y - 48.0)
	)
	var tip := origin + direction * 34.0
	var color := Color("315e63")
	if velocity.length_squared() > 0.000001:
		map_canvas.draw_line(origin, tip, color, 2.0, true)
		for angle in [-0.55, 0.55]:
			map_canvas.draw_line(tip, tip - direction.rotated(angle) * 8.0, color, 2.0, true)
	var label := weather_briefing_motion_text(storm)
	var label_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_rect := WeatherRadarArt.storm_motion_label_rect(rect, origin, tip, label_size)
	if label_rect.has_area():
		map_canvas.draw_rect(label_rect, Color("d7d0ad"), true)
		map_canvas.draw_rect(label_rect, Color(0.19, 0.37, 0.39, 0.45), false, 1.0)
		map_canvas.draw_string(ThemeDB.fallback_font, label_rect.position + Vector2(4, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func _weather_briefing_contour(storm: Dictionary, center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var radius: float = float(storm.radius_km)
	for sample_index in 48:
		var direction := Vector2.RIGHT.rotated(TAU * sample_index / 48.0)
		var extent := 0.0
		for lobe in storm.radar_lobes:
			var offset := Vector2(lobe.offset_km)
			var lobe_radius := radius * float(lobe.radius_scale)
			var projection := direction.dot(offset)
			var discriminant := projection * projection - (offset.length_squared() - lobe_radius * lobe_radius)
			if discriminant >= 0.0:
				extent = maxf(extent, projection + sqrt(discriminant))
		points.append(world_to_screen(center + direction * extent))
	return points

func _weather_briefing_circle(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point_index in 40:
		points.append(center + Vector2.RIGHT.rotated(TAU * point_index / 40.0) * radius)
	return points

func _weather_briefing_maximum_extent_km(storm: Dictionary) -> float:
	var result := float(storm.radius_km)
	for lobe in storm.radar_lobes:
		result = maxf(result, Vector2(lobe.offset_km).length() + float(storm.radius_km) * float(lobe.radius_scale))
	return result

func _draw_weather_briefing_echoes(rect: Rect2, clip_polygon: PackedVector2Array) -> void:
	# Reuse the radar's thresholds and hues, with much lower opacity on paper.
	# Weak returns are drawn across every cell first so they never cover a core.
	var map_alphas := [0.10, 0.14, 0.18]
	for zone_index in WeatherRadarArt.ECHO_ZONES.size():
		var zone: Dictionary = WeatherRadarArt.ECHO_ZONES[zone_index]
		var zone_color := Color(zone.color, map_alphas[zone_index])
		for storm in weather_briefing_storms:
			for wrap_y in [-1, 0, 1]:
				for wrap_x in [-1, 0, 1]:
					var center := Vector2(storm.center) + Vector2(wrap_x, wrap_y) * FlightWorldScript.SIZE_KM
					var center_screen := world_to_screen(center)
					var maximum_extent_px := _weather_briefing_maximum_extent_km(storm) * pixels_per_km()
					if not Rect2(center_screen - Vector2.ONE * maximum_extent_px, Vector2.ONE * maximum_extent_px * 2.0).intersects(rect):
						continue
					for lobe in storm.radar_lobes:
						var peak := float(storm.intensity) * float(lobe.strength)
						if peak <= float(zone.threshold):
							continue
						var ratio := 1.0 if float(zone.threshold) <= 0.0 else sqrt(1.0 - float(zone.threshold) / peak)
						var echo_center := world_to_screen(center + Vector2(lobe.offset_km))
						var echo_radius := float(storm.radius_km) * float(lobe.radius_scale) * ratio * pixels_per_km()
						var bounds := Rect2(echo_center - Vector2.ONE * echo_radius, Vector2.ONE * echo_radius * 2.0)
						if not bounds.intersects(rect):
							continue
						if rect.encloses(bounds):
							map_canvas.draw_circle(echo_center, echo_radius, zone_color)
						else:
							for clipped_polygon in Geometry2D.intersect_polygons(_weather_briefing_circle(echo_center, echo_radius), clip_polygon):
								map_canvas.draw_colored_polygon(clipped_polygon, zone_color)

func _draw_weather_briefing(rect: Rect2) -> void:
	if not weather_briefing_visible:
		return
	var clip_polygon := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	_draw_weather_briefing_echoes(rect, clip_polygon)
	var line_color := Color(0.52, 0.54, 0.16, 0.30)
	for storm in weather_briefing_storms:
		for wrap_y in [-1, 0, 1]:
			for wrap_x in [-1, 0, 1]:
				var center := Vector2(storm.center) + Vector2(wrap_x, wrap_y) * FlightWorldScript.SIZE_KM
				var center_screen := world_to_screen(center)
				var extent_px := _weather_briefing_maximum_extent_km(storm) * pixels_per_km()
				if not Rect2(center_screen - Vector2.ONE * extent_px, Vector2.ONE * extent_px * 2.0).intersects(rect):
					continue
				var contour := _weather_briefing_contour(storm, center)
				var bounds := Rect2(contour[0], Vector2.ZERO)
				for point in contour:
					bounds = bounds.expand(point)
				if not bounds.intersects(rect):
					continue
				for point_index in contour.size():
					_draw_clipped_map_line(contour[point_index], contour[(point_index + 1) % contour.size()], line_color, 1.2)

func weather_briefing_storm_at(mouse: Vector2) -> int:
	if large_weather_radar or not weather_briefing_visible or not map_rect().has_point(mouse):
		return -1
	var point := screen_to_world(mouse)
	var strongest := 0.0
	var selected := -1
	for storm_index in weather_briefing_storms.size():
		var storm: Dictionary = weather_briefing_storms[storm_index]
		for lobe in storm.radar_lobes:
			var center := Vector2(storm.center) + Vector2(lobe.offset_km)
			var delta := point - center
			delta.x = fposmod(delta.x + FlightWorldScript.SIZE_KM * 0.5, FlightWorldScript.SIZE_KM) - FlightWorldScript.SIZE_KM * 0.5
			delta.y = fposmod(delta.y + FlightWorldScript.SIZE_KM * 0.5, FlightWorldScript.SIZE_KM) - FlightWorldScript.SIZE_KM * 0.5
			var lobe_radius := float(storm.radius_km) * float(lobe.radius_scale)
			var ratio := delta.length() / lobe_radius
			if ratio < 1.0:
				var strength := float(storm.intensity) * float(lobe.strength) * (1.0 - ratio * ratio)
				if strength > strongest:
					strongest = strength
					selected = storm_index
	return selected

func _airport_hover_index(mouse: Vector2) -> int:
	if not map_rect().has_point(mouse):
		return -1
	for index in host.world.airports.size():
		var airport: Dictionary = host.world.airports[index]
		var center = world_to_screen(airport.position)
		var vector: Vector2 = host.world.heading_vector(airport.heading) * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
		var a = world_to_screen(airport.position - vector)
		var b = world_to_screen(airport.position + vector)
		var label_anchor: Vector2 = (a if a.y <= b.y else b) + Vector2(10, -21)
		var label_width = ThemeDB.fallback_font.get_string_size(String(airport.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 100.0
		if mouse.distance_to(center) <= 32.0 or Rect2(label_anchor, Vector2(label_width, 27)).has_point(mouse):
			return index
	return -1

func _wind_overlay_altitude() -> float:
	return host.flight.altitude_m if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size() else WIND_OVERLAY_ALTITUDES[wind_overlay_index]

func _wind_arrow_description() -> String:
	var altitude_m = _wind_overlay_altitude()
	var wind: Vector2 = host.world.wind_at(altitude_m)
	var from_degrees = roundi(host.world.vector_heading(-wind)) % 360
	return "от %03d° • %.0f км/ч • %.0f м" % [from_degrees, wind.length(), altitude_m]

func _wind_arrow_hovered(mouse: Vector2) -> bool:
	if large_weather_radar or not map_rect().has_point(mouse):
		return false
	var wind: Vector2 = host.world.wind_at(_wind_overlay_altitude())
	if wind.length_squared() < 0.001:
		return false
	var length_px = remap(clampf(wind.length(), 0.0, 40.0), 0.0, 40.0, 12.0, 27.0)
	var half_vector = wind.normalized() * length_px * 0.5
	for center in _wind_arrow_centers(map_rect()):
		if mouse.distance_to(Geometry2D.get_closest_point_to_segment(mouse, center - half_vector, center + half_vector)) <= 8.0:
			return true
	return false

func _wind_arrow_centers(rect: Rect2) -> PackedVector2Array:
	var centers = PackedVector2Array()
	var safe_rect = rect.grow(-20.0)
	if not safe_rect.has_area():
		return centers
	var visible_min = screen_to_world(safe_rect.position).max(Vector2.ZERO)
	var visible_max = screen_to_world(safe_rect.end).min(Vector2.ONE * FlightWorldScript.SIZE_KM)
	if visible_min.x > visible_max.x or visible_min.y > visible_max.y:
		return centers
	# Keep the sparse, world-anchored grid for each zoom band.
	var target_px = maxf(180.0, minf(rect.size.x, rect.size.y) * 0.55)
	var target_km = screen_to_world(rect.position + Vector2(target_px, 0.0)).x - screen_to_world(rect.position).x
	var spacing_km = pow(2.0, ceilf(log(maxf(0.001, target_km)) / log(2.0)))
	var x = ceilf(visible_min.x / spacing_km) * spacing_km
	while x <= visible_max.x:
		var y = ceilf(visible_min.y / spacing_km) * spacing_km
		while y <= visible_max.y:
			centers.append(world_to_screen(Vector2(x, y)))
			y += spacing_km
		x += spacing_km
	if centers.is_empty():
		centers.append(world_to_screen((visible_min + visible_max) * 0.5))
	# Hide central arrows without relocating the remaining ones.
	var exclusion_radius = minf(rect.size.x, rect.size.y) * 0.25
	var visible_centers = PackedVector2Array()
	for center in centers:
		if center.distance_to(rect.get_center()) > exclusion_radius:
			visible_centers.append(center)
	return visible_centers

func _draw_wind_overlay(rect: Rect2) -> void:
	var altitude_m: float = host.flight.altitude_m if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size() else WIND_OVERLAY_ALTITUDES[wind_overlay_index]
	var wind: Vector2 = host.world.wind_at(altitude_m)
	if wind.length_squared() < 0.001:
		return
	var arrow_length = remap(clampf(wind.length(), 0.0, 40.0), 0.0, 40.0, 12.0, 27.0)
	var direction = wind.normalized()
	var color = Color(0.10, 0.42, 0.48, 0.50)
	var arrow_label = _wind_arrow_description()
	var label_size = ThemeDB.fallback_font.get_string_size(arrow_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
	for center in _wind_arrow_centers(rect):
		var half_vector = direction * arrow_length * 0.5
		var tip = center + half_vector
		var tail = center - half_vector
		_draw_clipped_map_line(tail, tip, color, 1.5)
		var backward = -direction
		_draw_clipped_map_line(tip, tip + backward.rotated(0.55) * 6.0, color, 1.5)
		_draw_clipped_map_line(tip, tip + backward.rotated(-0.55) * 6.0, color, 1.5)
		var label_position = center + Vector2(arrow_length * 0.5 + 7.0, 4.0)
		if map_zoom >= APPROACH_DETAIL_MIN_ZOOM and label_position.y >= rect.position.y + 10.0 and label_position.y <= rect.end.y - 3.0:
			label_position.x = clampf(label_position.x, rect.position.x + 4.0, rect.end.x - label_size.x - 4.0)
			map_canvas.draw_string(ThemeDB.fallback_font, label_position, arrow_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.10, 0.36, 0.41, 0.62))

func _draw_completed_flight_trajectory() -> void:
	var trajectory_visible := _trajectory_overlay_visible()
	var aircraft_visible := _map_aircraft_visible()
	if not trajectory_visible and not aircraft_visible:
		return
	var path_color = Color("a83f38") if host.flight.state == FlightModelScript.State.CRASHED else Color("176f75")
	if host.trajectory_finished and trajectory_visible:
		for point_index in range(1, host.flight_trajectory.size()):
			_draw_clipped_map_line(world_to_screen(host.flight_trajectory[point_index - 1].position), world_to_screen(host.flight_trajectory[point_index].position), path_color, 2.0)
	if not aircraft_visible:
		return
	var aircraft_position = world_to_screen(host.flight.position_km)
	var safe_rect = map_rect().grow(-10.0)
	aircraft_position.x = clampf(aircraft_position.x, safe_rect.position.x, safe_rect.end.x)
	aircraft_position.y = clampf(aircraft_position.y, safe_rect.position.y, safe_rect.end.y)
	_draw_map_aircraft(aircraft_position, host.flight.heading_deg, path_color)

func _trajectory_overlay_visible() -> bool:
	if host.flight_trajectory.is_empty():
		return false
	if host.trajectory_finished:
		return host.final_trajectory_visible and host.flight.state != FlightModelScript.State.FLYING
	return not host.trajectory_recording_started and host.flight.state == FlightModelScript.State.PARKED

func _map_aircraft_visible() -> bool:
	if host.flight_trajectory.is_empty():
		return false
	if host.trajectory_finished:
		return host.flight.state != FlightModelScript.State.FLYING
	return not host.trajectory_recording_started and host.flight.state == FlightModelScript.State.PARKED

func _can_toggle_final_trajectory() -> bool:
	return host.trajectory_finished and host.flight.state != FlightModelScript.State.FLYING

func _toggle_final_trajectory() -> void:
	if not _can_toggle_final_trajectory():
		return
	host.final_trajectory_visible = not host.final_trajectory_visible
	_queue_map_redraw()
	host.queue_redraw()

func _draw_map_aircraft(position: Vector2, heading_deg: float, color: Color) -> void:
	map_canvas.draw_set_transform(position, deg_to_rad(heading_deg), Vector2.ONE)
	# Compact top-down silhouette of a small single-engine high-wing aircraft:
	# straight wing and tailplane first, then the fuselage, cabin and propeller.
	var wing = PackedVector2Array([
		Vector2(-12, -3), Vector2(12, -3), Vector2(12, 2), Vector2(3, 2),
		Vector2(2, 3), Vector2(-2, 3), Vector2(-3, 2), Vector2(-12, 2),
	])
	var tailplane = PackedVector2Array([
		Vector2(-6, 7), Vector2(6, 7), Vector2(6, 10),
		Vector2(2, 9), Vector2(-2, 9), Vector2(-6, 10),
	])
	var fuselage = PackedVector2Array([
		Vector2(0, -11), Vector2(3, -8), Vector2(3, 4), Vector2(2, 10),
		Vector2(0, 12), Vector2(-2, 10), Vector2(-3, 4), Vector2(-3, -8),
	])
	for part in [wing, tailplane, fuselage]:
		map_canvas.draw_colored_polygon(part, Color("c8ced0"))
		var part_outline: PackedVector2Array = part.duplicate()
		part_outline.append(part[0])
		map_canvas.draw_polyline(part_outline, color, 1.5, true)
	var cabin = PackedVector2Array([
		Vector2(-2.3, -6.5), Vector2(2.3, -6.5),
		Vector2(2.3, -1.5), Vector2(-2.3, -1.5),
	])
	map_canvas.draw_colored_polygon(cabin, Color("58b5c0"))
	var cabin_outline: PackedVector2Array = cabin.duplicate()
	cabin_outline.append(cabin[0])
	map_canvas.draw_polyline(cabin_outline, color, 1.0, true)
	map_canvas.draw_line(Vector2(-6, -11), Vector2(6, -11), color, 1.5, true)
	map_canvas.draw_circle(Vector2.ZERO + Vector2(0, -11), 1.5, Color("e4bd4e"))
	map_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_contour_labels(rect: Rect2) -> void:
	var placed_by_level: Dictionary = {}
	var safe_rect = rect.grow(-28.0)
	for segment in contour_segments:
		var level = int(segment.level)
		var midpoint: Vector2 = (world_to_screen(segment.a) + world_to_screen(segment.b)) * 0.5
		if not safe_rect.has_point(midpoint):
			continue
		if not placed_by_level.has(level):
			placed_by_level[level] = []
		var positions: Array = placed_by_level[level]
		if positions.size() >= 3:
			continue
		var far_enough = true
		for existing: Vector2 in positions:
			if existing.distance_to(midpoint) < 210.0:
				far_enough = false
				break
		if not far_enough:
			continue
		var label = "%d м" % level
		var text_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var background = Rect2(midpoint - Vector2(text_size.x * 0.5 + 3.0, 9.0), text_size + Vector2(6.0, 3.0))
		map_canvas.draw_rect(background, Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, midpoint + Vector2(-text_size.x * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("55462f"))
		positions.append(midpoint)

func _draw_terrain_peaks(rect: Rect2) -> void:
	var safe_rect = rect.grow(-18.0)
	for peak in terrain_peaks:
		var position = world_to_screen(peak.position)
		if safe_rect.has_point(position):
			_draw_clamped_map_text(position + Vector2(5.0, -5.0), "▲ %.0f м" % float(peak.height), 11, Color("4d3d29"))

func _draw_airport(airport: Dictionary) -> void:
	var center = world_to_screen(airport.position)
	var vector: Vector2 = host.world.heading_vector(airport.heading) * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var a = world_to_screen(airport.position - vector)
	var b = world_to_screen(airport.position + vector)
	_draw_clipped_map_line(a, b, Color("222722"), max(4.0, pixels_per_km() * 0.12))
	_draw_clipped_map_line(a, b, Color("f0ead2"), 1.0)
	if map_rect().has_point(a):
		map_canvas.draw_circle(a, 3.0, Color("20241f"))
	if map_rect().has_point(b):
		map_canvas.draw_circle(b, 3.0, Color("20241f"))
	if not map_rect().grow(-8.0).has_point(center):
		return
	var direct_course = int(round(airport.heading)) % 360
	var reverse_course = (direct_course + 180) % 360
	var upper_runway_end = a if a.y <= b.y else b
	_draw_clamped_map_text(upper_runway_end + Vector2(10, -9), "%s  %03d°/%03d°" % [airport.name, direct_course, reverse_course], 12, Color("20241f"))

func _draw_approach_point(airport: Dictionary) -> void:
	# Keep the overview map readable: detailed glide-path markings appear only
	# at the maximum zoom and the immediately preceding wheel-zoom level.
	if map_zoom < APPROACH_DETAIL_MIN_ZOOM:
		return
	for approach_sign in [1.0, -1.0]:
		_draw_approach_direction(airport, approach_sign)

func _draw_approach_direction(airport: Dictionary, approach_sign: float) -> void:
	var forward: Vector2 = host.world.heading_vector(airport.heading) * approach_sign
	var threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var touchdown_target: Vector2 = threshold + forward * FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM
	var capture_boundary := ils_capture_boundary(airport, approach_sign)
	var capture_arc: PackedVector2Array = capture_boundary.arc
	var approach_color := Color("287777")
	_draw_clipped_map_line(world_to_screen(capture_boundary.apex), world_to_screen(capture_arc[0]), approach_color, 1.5, true)
	_draw_clipped_map_line(world_to_screen(capture_boundary.apex), world_to_screen(capture_arc[-1]), approach_color, 1.5, true)
	for point_index in range(1, capture_arc.size()):
		_draw_clipped_map_line(world_to_screen(capture_arc[point_index - 1]), world_to_screen(capture_arc[point_index]), approach_color, 1.5, true)
	var approach_vertical_speed = -(92.0 / 3.6) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
	var markers_by_direction: Dictionary = airport.get("approach_markers", {})
	var markers: Array = markers_by_direction.get(str(int(approach_sign)), [])
	if markers.is_empty():
		return
	var farthest_distance_km: float = markers[-1].distance_km
	var farthest_position = threshold - forward * farthest_distance_km
	_draw_clipped_map_line(world_to_screen(farthest_position), world_to_screen(touchdown_target), approach_color, 1.5, true)
	for marker in markers:
		var distance_km: float = marker.distance_km
		var approach_position: Vector2 = threshold - forward * distance_km
		var point = world_to_screen(approach_position)
		if not map_rect().grow(-8.0).has_point(point):
			continue
		var diamond = PackedVector2Array([
			point + Vector2(0, -6), point + Vector2(6, 0),
			point + Vector2(0, 6), point + Vector2(-6, 0),
		])
		map_canvas.draw_colored_polygon(diamond, Color("d7d0ad"))
		map_canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("185f61"), 2.0)
		var desired_altitude: float = marker.altitude_m
		var label = "%.1f км • %.0f м • %.1f м/с" % [float(marker.distance_km), desired_altitude, approach_vertical_speed]
		var text_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var label_position = point + Vector2(12.0, 4.0)
		label_position.x = clampf(label_position.x, map_rect().position.x + 4.0, map_rect().end.x - text_size.x - 4.0)
		label_position.y = clampf(label_position.y, map_rect().position.y + text_size.y + 2.0, map_rect().end.y - 4.0)
		map_canvas.draw_rect(Rect2(label_position + Vector2(-3, -11), text_size + Vector2(6, 3)), Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("185f61"))

func ils_capture_boundary(airport: Dictionary, approach_sign: float) -> Dictionary:
	var forward: Vector2 = host.world.heading_vector(airport.heading) * approach_sign
	# The signal model uses the far runway threshold as its virtual cone apex so
	# guidance remains available throughout the approach and ground roll.
	var apex: Vector2 = Vector2(airport.position) + forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	# The actual receiver range is circular around the beacon. Trace that same
	# boundary instead of a perpendicular crossbar whose corners would lie more
	# than 15 km away and visually promise coverage where there is none.
	var beacon_position := Vector2(airport.position)
	var approach_axis := -forward
	var arc := PackedVector2Array()
	for point_index in range(ILS_CAPTURE_ARC_SEGMENTS + 1):
		var ratio := point_index / float(ILS_CAPTURE_ARC_SEGMENTS)
		var ray_angle := deg_to_rad(lerpf(-FlightWorldScript.ILS_HALF_CONE_DEG, FlightWorldScript.ILS_HALF_CONE_DEG, ratio))
		var ray_direction := approach_axis.rotated(ray_angle)
		var apex_from_beacon := apex - beacon_position
		var projection := apex_from_beacon.dot(ray_direction)
		var discriminant := projection * projection + FlightWorldScript.ILS_RANGE_KM * FlightWorldScript.ILS_RANGE_KM - apex_from_beacon.length_squared()
		var distance_along_ray := -projection + sqrt(maxf(0.0, discriminant))
		arc.append(apex + ray_direction * distance_along_ray)
	return {"apex": apex, "arc": arc}

func _build_approach_markers() -> void:
	for airport in host.world.airports:
		var markers_by_direction: Dictionary = {}
		for approach_sign in [1.0, -1.0]:
			var markers: Array[Dictionary] = []
			for distance_km in range(4, 21, 4):
				var distance: float = float(distance_km)
				if not _approach_path_is_clear(airport, distance, approach_sign):
					continue
				var altitude_m = (distance * 1000.0 + FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM * 1000.0) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
				markers.append({"distance_km": distance, "altitude_m": altitude_m})
			markers_by_direction[str(int(approach_sign))] = markers
		airport.approach_markers = markers_by_direction

func _approach_path_is_clear(airport: Dictionary, start_distance_km: float, approach_sign: float) -> bool:
	var forward: Vector2 = host.world.heading_vector(airport.heading) * approach_sign
	var threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var sample_count = maxi(1, ceili(start_distance_km / 0.10))
	for sample_index in sample_count + 1:
		var distance_km = start_distance_km * sample_index / float(sample_count)
		var position = threshold - forward * distance_km
		var glide_altitude_m = (distance_km + FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM) * 1000.0 * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
		if host.world.height_at(position) >= glide_altitude_m:
			return false
	return true

func _draw_beacon(beacon: Dictionary) -> void:
	var p = world_to_screen(beacon.position)
	if not map_rect().grow(-8.0).has_point(p):
		return
	var radius = 5.0
	var points = PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, radius), p + Vector2(-radius, radius)])
	map_canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color("972d25"), 2.0)
	_draw_clamped_map_text(p + Vector2(11, 4), "%s %.0f кГц R%.0f" % [beacon.name, beacon.frequency, beacon.range_km], 11, Color("76231d"))

func measurement_line_color(linked: bool, highlighted: bool) -> Color:
	if highlighted:
		return ACTIVE_LINKED_MEASUREMENT_COLOR
	if linked:
		return LINKED_MEASUREMENT_COLOR
	return MEASUREMENT_COLOR

func _draw_measurement(a_world: Vector2, b_world: Vector2, color := MEASUREMENT_COLOR, cached_max_height := -1.0, directed := false, highlighted := false, line_id := -1) -> void:
	var a = world_to_screen(a_world)
	var b = world_to_screen(b_world)
	_draw_clipped_map_line(a, b, color, 2.8 if highlighted else 2.0, true)
	if map_rect().has_point(a):
		map_canvas.draw_circle(a, 3, color)
	if map_rect().has_point(b):
		map_canvas.draw_circle(b, 3, color)
	var label := _measurement_label_text(a_world, b_world, cached_max_height, directed, line_id)
	var visible_segment = _clip_line_to_rect(a, b, map_rect().grow(-3.0))
	if visible_segment.size() == 2:
		var visible_direction: Vector2 = visible_segment[1] - visible_segment[0]
		if directed and visible_direction.length() >= 28.0:
			var arrow_tip: Vector2 = visible_segment[0].lerp(visible_segment[1], 0.72)
			var backward := -visible_direction.normalized()
			map_canvas.draw_line(arrow_tip, arrow_tip + backward.rotated(0.55) * 8.0, color, 2.0, true)
			map_canvas.draw_line(arrow_tip, arrow_tip + backward.rotated(-0.55) * 8.0, color, 2.0, true)
		var text_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var midpoint: Vector2 = (visible_segment[0] + visible_segment[1]) * 0.5
		if visible_direction.length() >= text_size.x * 1.35 + 20.0:
			if map_rect().grow(-24.0).has_point(midpoint):
				_draw_rotated_map_label(midpoint, visible_direction, label, color)
			else:
				_draw_horizontal_measurement_label(midpoint, visible_direction, label, color)
		else:
			_draw_horizontal_measurement_label(midpoint, visible_direction, label, color)

func _measurement_label_text(a_world: Vector2, b_world: Vector2, cached_max_height: float, directed: bool, line_id: int) -> String:
	var distance := a_world.distance_to(b_world)
	var bearing: float = host.world.vector_heading(b_world - a_world)
	var direct_course := int(round(bearing)) % 360
	var reverse_course := (direct_course + 180) % 360
	var max_height: float = cached_max_height if cached_max_height >= 0.0 else _maximum_terrain_height_on_line(a_world, b_world)
	var linked_time: float = host.flight_calculator.line_time_minutes(line_id) if line_id >= 0 else -1.0
	var time_text := "%.1f мин" % linked_time if linked_time >= 0.0 else measurement_time_text(distance)
	# The rotated label can flip to stay upright, so its arrow is represented
	# by the directed line's geometry rather than by a glyph in this text.
	var course_text := "%03d°" % direct_course if directed else "%03d° / %03d°" % [direct_course, reverse_course]
	return "%.1f км • %s  %s  %.0f м" % [distance, time_text, course_text, max_height]

func measurement_time_text(distance_km: float) -> String:
	var ground_speed: float = host.flight.ground_speed_kmh()
	return "— мин" if ground_speed <= 0.01 else "%.1f мин" % (distance_km / ground_speed * 60.0)

func _draw_clipped_map_line(a: Vector2, b: Vector2, color: Color, width: float, dashed := false) -> void:
	var clipped = _clip_line_to_rect(a, b, map_rect().grow(-maxf(1.0, width * 0.5)))
	if clipped.size() != 2:
		return
	if dashed:
		map_canvas.draw_dashed_line(clipped[0], clipped[1], color, width, 7.0)
	else:
		map_canvas.draw_line(clipped[0], clipped[1], color, width, true)

func _draw_clamped_map_text(position: Vector2, label: String, font_size: int, color: Color) -> void:
	var text_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var safe_position = Vector2(
		clampf(position.x, map_rect().position.x + 4.0, map_rect().end.x - text_size.x - 4.0),
		clampf(position.y, map_rect().position.y + text_size.y + 2.0, map_rect().end.y - 4.0)
	)
	map_canvas.draw_string(ThemeDB.fallback_font, safe_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _clip_line_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	# Liang–Barsky line clipping in screen coordinates.
	var delta = b - a
	var t_min = 0.0
	var t_max = 1.0
	var p_values = [-delta.x, delta.x, -delta.y, delta.y]
	var q_values = [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		var p: float = p_values[i]
		var q: float = q_values[i]
		if is_zero_approx(p):
			if q < 0.0:
				return PackedVector2Array()
			continue
		var ratio = q / p
		if p < 0.0:
			t_min = maxf(t_min, ratio)
		else:
			t_max = minf(t_max, ratio)
		if t_min > t_max:
			return PackedVector2Array()
	return PackedVector2Array([a + delta * t_min, a + delta * t_max])

func _draw_rotated_map_label(position: Vector2, line_direction: Vector2, label: String, color: Color) -> void:
	var angle = line_direction.angle()
	# Keep text parallel to the line, but never render it upside down.
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI
	var text_size = ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	map_canvas.draw_set_transform(position, angle, Vector2.ONE)
	# Keep a clear gap between the line at local Y=0 and the label above it.
	map_canvas.draw_rect(Rect2(Vector2(-text_size.x * 0.5 - 3.0, -25.0), text_size + Vector2(6.0, 4.0)), Color("d7d0ad"), true)
	map_canvas.draw_string(ThemeDB.fallback_font, Vector2(-text_size.x * 0.5, -13.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	map_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_horizontal_measurement_label(midpoint: Vector2, line_direction: Vector2, label: String, color: Color) -> void:
	var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var chart := map_rect()
	var baseline := _horizontal_measurement_label_baseline(midpoint, line_direction, text_size, chart)
	map_canvas.draw_rect(Rect2(baseline - Vector2(3.0, text_size.y + 3.0), text_size + Vector2(6.0, 6.0)), Color("d7d0ad"), true)
	map_canvas.draw_string(ThemeDB.fallback_font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _horizontal_measurement_label_baseline(midpoint: Vector2, line_direction: Vector2, text_size: Vector2, chart: Rect2) -> Vector2:
	var mostly_horizontal := absf(line_direction.x) >= absf(line_direction.y)
	var baseline_y := midpoint.y - 10.0 if mostly_horizontal else midpoint.y + text_size.y * 0.5
	if mostly_horizontal and baseline_y - text_size.y - 3.0 < chart.position.y + 4.0:
		baseline_y = midpoint.y + text_size.y + 10.0
	var baseline_x := midpoint.x + 10.0
	if not mostly_horizontal and baseline_x + text_size.x + 3.0 > chart.end.x - 4.0:
		baseline_x = midpoint.x - text_size.x - 10.0
	return Vector2(
		clampf(baseline_x, chart.position.x + 4.0, chart.end.x - text_size.x - 4.0),
		clampf(baseline_y, chart.position.y + text_size.y + 4.0, chart.end.y - 4.0)
	)

func _zoom_at(mouse: Vector2, factor: float) -> void:
	update_weather_storm_hover(-1, Vector2.ZERO)
	var before = screen_to_world(mouse)
	map_zoom = clamp(map_zoom * factor, _minimum_map_zoom(), MAX_MAP_ZOOM)
	var after = screen_to_world(mouse)
	map_center += before - after
	_clamp_map_center()

func _normalize_map_camera() -> void:
	map_zoom = clampf(maxf(map_zoom, _minimum_map_zoom()), _minimum_map_zoom(), MAX_MAP_ZOOM)
	_clamp_map_center()

func _minimum_map_zoom() -> float:
	var rect_size = map_rect().size
	var shorter_side = maxf(1.0, minf(rect_size.x, rect_size.y))
	# The world must cover both axes of the viewport. On a wide display this
	# crops its top and bottom at maximum zoom-out instead of exposing side gaps.
	return maxf(rect_size.x, rect_size.y) / shorter_side

func _initial_map_zoom(center: Vector2) -> float:
	var rect_size = map_rect().size
	var base_scale = _base_pixels_per_km()
	var zoom = maxf(_minimum_map_zoom(), maxf(rect_size.x, rect_size.y) / (INITIAL_MAP_RADIUS_KM * 2.0 * base_scale))
	# Keep the departure airport exactly centred. Airports near a world edge need
	# a closer view so no area outside the chart becomes visible.
	var edge_x = maxf(0.01, minf(center.x, FlightWorldScript.SIZE_KM - center.x))
	var edge_y = maxf(0.01, minf(center.y, FlightWorldScript.SIZE_KM - center.y))
	zoom = maxf(zoom, rect_size.x / (edge_x * 2.0 * base_scale))
	zoom = maxf(zoom, rect_size.y / (edge_y * 2.0 * base_scale))
	return clampf(zoom, _minimum_map_zoom(), MAX_MAP_ZOOM)

func _clamp_map_center() -> void:
	var visible_half = Vector2(map_rect().size.x, map_rect().size.y) / pixels_per_km() * 0.5
	var world_half = FlightWorldScript.SIZE_KM * 0.5
	# On a wide screen the viewport can be wider than the whole world. In that
	# case there is no valid min/max interval, so keep that axis centered.
	if visible_half.x >= world_half:
		map_center.x = world_half
	else:
		map_center.x = clampf(map_center.x, visible_half.x, FlightWorldScript.SIZE_KM - visible_half.x)
	if visible_half.y >= world_half:
		map_center.y = world_half
	else:
		map_center.y = clampf(map_center.y, visible_half.y, FlightWorldScript.SIZE_KM - visible_half.y)

func pixels_per_km() -> float:
	return _base_pixels_per_km() * map_zoom

func _base_pixels_per_km() -> float:
	return min(map_rect().size.x, map_rect().size.y) / FlightWorldScript.SIZE_KM

func world_to_screen(point: Vector2) -> Vector2:
	return map_rect().get_center() + (point - map_center) * pixels_per_km()

func screen_to_world(point: Vector2) -> Vector2:
	return map_center + (point - map_rect().get_center()) / pixels_per_km()

func ensure_measurement_line_ids() -> void:
	var used: Dictionary = {}
	for line in measurement_lines:
		var line_id := int(line.get("id", -1))
		if line_id < 1 or used.has(line_id):
			while used.has(next_measurement_line_id):
				next_measurement_line_id += 1
			line_id = next_measurement_line_id
			line.id = line_id
			next_measurement_line_id += 1
		used[line_id] = true
		next_measurement_line_id = maxi(next_measurement_line_id, line_id + 1)

func measurement_line_by_id(line_id: int) -> Dictionary:
	ensure_measurement_line_ids()
	for line in measurement_lines:
		if int(line.id) == line_id:
			return line
	return {}

func _measurement_line_index_at(screen_position: Vector2, maximum_distance: float = 8.0) -> int:
	var nearest := -1
	var nearest_distance := maximum_distance
	for index in measurement_lines.size():
		var a := world_to_screen(measurement_lines[index].a)
		var b := world_to_screen(measurement_lines[index].b)
		var candidate := screen_position.distance_to(Geometry2D.get_closest_point_to_segment(screen_position, a, b))
		if candidate < nearest_distance:
			nearest_distance = candidate
			nearest = index
	return nearest

func bind_calculator_to_line_at(screen_position: Vector2) -> bool:
	ensure_measurement_line_ids()
	var line_index := _measurement_line_index_at(screen_position)
	if line_index < 0:
		return false
	var line: Dictionary = measurement_lines[line_index]
	return host.flight_calculator.bind_line(int(line.id), line.a, line.b)

func release_calculator_line(line_id: int, except_profile: int) -> void:
	host.flight_calculator.release_line_from_other_profiles(line_id, except_profile)

func calculator_line_unlinked(_line_id: int) -> void:
	_queue_map_redraw()

func update_calculator_line(line_id: int, requested_distance: float, track_deg: float) -> Dictionary:
	var line: Dictionary = measurement_line_by_id(line_id)
	if line.is_empty():
		return {}
	var start: Vector2 = Vector2(line.a)
	var direction: Vector2 = host.world.heading_vector(track_deg)
	var maximum_distance: float = INF
	if direction.x > 0.000001:
		maximum_distance = minf(maximum_distance, (FlightWorldScript.SIZE_KM - start.x) / direction.x)
	elif direction.x < -0.000001:
		maximum_distance = minf(maximum_distance, -start.x / direction.x)
	if direction.y > 0.000001:
		maximum_distance = minf(maximum_distance, (FlightWorldScript.SIZE_KM - start.y) / direction.y)
	elif direction.y < -0.000001:
		maximum_distance = minf(maximum_distance, -start.y / direction.y)
	if requested_distance > maxf(0.0, maximum_distance) + 0.000001:
		return {"rejected": true, "reason": "Линия такой длины и направления выходит за границу карты"}
	var actual_distance: float = requested_distance
	var old_end: Vector2 = line.b
	var new_end: Vector2 = start + direction * actual_distance
	var affected: Dictionary = {}
	for line_index in measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			if int(measurement_lines[line_index].id) == line_id and endpoint_key == "a":
				continue # The vector origin remains fixed, including after zero length.
			if Vector2(measurement_lines[line_index][endpoint_key]).is_equal_approx(old_end):
				measurement_lines[line_index][endpoint_key] = new_end
				affected[line_index] = true
	for line_index in affected:
		var affected_line: Dictionary = measurement_lines[int(line_index)]
		affected_line.max_height_m = _maximum_terrain_height_on_line(affected_line.a, affected_line.b)
		if int(affected_line.id) != line_id:
			host.flight_calculator.measurement_line_changed(affected_line)
	_queue_map_redraw()
	return line

func reverse_calculator_line(line_id: int) -> Dictionary:
	var line: Dictionary = measurement_line_by_id(line_id)
	if line.is_empty():
		return {}
	var old_start: Vector2 = line.a
	line.a = line.b
	line.b = old_start
	_queue_map_redraw()
	return line

func _erase_nearest_measurement(mouse: Vector2) -> void:
	var closest = -1
	var closest_distance = 18.0
	for i in active_measurement_lines.size():
		var a = _measurement_to_screen(active_measurement_lines[i].a)
		var b = _measurement_to_screen(active_measurement_lines[i].b)
		var nearest = Geometry2D.get_closest_point_to_segment(mouse, a, b)
		var distance = mouse.distance_to(nearest)
		if distance < closest_distance:
			closest = i
			closest_distance = distance
	if closest >= 0:
		if not large_weather_radar:
			ensure_measurement_line_ids()
			host.flight_calculator.measurement_line_removed(int(active_measurement_lines[closest].id))
		active_measurement_lines.remove_at(closest)

func _handle_map_click(screen_position: Vector2) -> void:
	var point = _snap_map_point(screen_position)
	if active_pending_measure == null:
		active_pending_measure = point
	else:
		var height = -1.0 if large_weather_radar else _maximum_terrain_height_on_line(active_pending_measure, point)
		var line: Dictionary = {"a": active_pending_measure, "b": point, "max_height_m": height}
		if not large_weather_radar:
			line.id = next_measurement_line_id
			next_measurement_line_id += 1
		active_measurement_lines.append(line)
		active_pending_measure = null

func _maximum_terrain_height_on_line(a: Vector2, b: Vector2) -> float:
	var sample_count: int = maxi(1, ceili(a.distance_to(b) / 0.10))
	var maximum_height: float = host.world.height_at(a)
	var previous_position: Vector2 = a
	var previous_height: float = maximum_height
	for sample_index in range(1, sample_count + 1):
		var position = a.lerp(b, sample_index / float(sample_count))
		var height: float = host.world.height_at(position)
		maximum_height = maxf(maximum_height, height)
		# On a rapidly changing slope, inspect the middle of the interval too.
		# This halves the local sampling step without paying that cost over flats.
		if absf(height - previous_height) >= 8.0:
			maximum_height = maxf(maximum_height, host.world.height_at((previous_position + position) * 0.5))
		previous_position = position
		previous_height = height
	# A small allowance covers residual sampling error; this is deliberately
	# much smaller than a contour interval and is not a safe-flight altitude.
	return maximum_height + 8.0

func _refresh_measurement_max_heights(connections: Array[Dictionary]) -> void:
	if large_weather_radar:
		return # Radar annotations neither need nor reveal terrain heights.
	var refreshed: Dictionary = {}
	for connection in connections:
		var line_index: int = connection.line_index
		if refreshed.has(line_index) or line_index < 0 or line_index >= measurement_lines.size():
			continue
		var line: Dictionary = measurement_lines[line_index]
		line.max_height_m = _maximum_terrain_height_on_line(line.a, line.b)
		host.flight_calculator.measurement_line_changed(line)
		refreshed[line_index] = true

func _find_measure_connections(screen_position: Vector2) -> Array[Dictionary]:
	var selected_world = Vector2.ZERO
	var closest_pixels = 12.0
	var found = false
	for line in active_measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var endpoint_screen = _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var distance = screen_position.distance_to(endpoint_screen)
			if distance < closest_pixels:
				closest_pixels = distance
				selected_world = endpoint
				found = true
	var connections: Array[Dictionary] = []
	if not found:
		return connections
	for line_index in active_measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = active_measurement_lines[line_index][endpoint_key]
			if endpoint.is_equal_approx(selected_world):
				connections.append({"line_index": line_index, "endpoint": endpoint_key})
	return connections

func _snap_dragged_measure_point_to_endpoint(screen_position: Vector2) -> void:
	var closest_pixels = 14.0
	var snap_target: Variant = null
	# Both route NDBs and runway locator beacons are stored in world.beacons.
	# Check them together with user-created endpoints when a dragged node is
	# released, so every connected line lands on the exact beacon coordinate.
	for beacon in host.world.beacons:
		var beacon_position: Vector2 = beacon.position
		if large_weather_radar:
			continue # Do not reveal invisible beacons through radar snapping.
		var pixel_distance = screen_position.distance_to(_measurement_to_screen(beacon_position))
		if pixel_distance < closest_pixels:
			closest_pixels = pixel_distance
			snap_target = beacon_position
	for line_index in active_measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			if _is_dragged_measure_connection(line_index, endpoint_key):
				continue
			var endpoint: Vector2 = active_measurement_lines[line_index][endpoint_key]
			var endpoint_screen = _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var pixel_distance = screen_position.distance_to(endpoint_screen)
			if pixel_distance < closest_pixels:
				closest_pixels = pixel_distance
				snap_target = endpoint
	if snap_target == null:
		return
	for connection in dragged_measure_connections:
		active_measurement_lines[connection.line_index][connection.endpoint] = snap_target

func _is_dragged_measure_connection(line_index: int, endpoint_key: String) -> bool:
	for connection in dragged_measure_connections:
		if connection.line_index == line_index and connection.endpoint == endpoint_key:
			return true
	return false

func _snap_map_point(screen_position: Vector2) -> Vector2:
	var unsnapped = _measurement_from_screen(screen_position)
	if large_weather_radar:
		unsnapped = unsnapped.clamp(Vector2.ZERO, Vector2.ONE * FlightWorldScript.SIZE_KM)
	var closest_world = unsnapped
	var closest_pixels = 14.0
	for beacon in host.world.beacons:
		var beacon_position: Vector2 = beacon.position
		if large_weather_radar:
			continue
		var pixel_distance = screen_position.distance_to(_measurement_to_screen(beacon_position))
		if pixel_distance < closest_pixels:
			closest_pixels = pixel_distance
			closest_world = beacon_position
	for line in active_measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var endpoint_screen = _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var pixel_distance = screen_position.distance_to(endpoint_screen)
			if pixel_distance < closest_pixels:
				closest_pixels = pixel_distance
				closest_world = endpoint
	return closest_world

func _build_contours() -> void:
	contour_segments.clear()
	terrain_peaks.clear()
	var cell: float = FlightWorldScript.SIZE_KM / SAMPLE_GRID
	# Cache the terrain grid once. Marching every contour level over the old
	# uncached grid repeated the same height query hundreds of thousands of times.
	var heights = PackedFloat32Array()
	heights.resize((SAMPLE_GRID + 1) * (SAMPLE_GRID + 1))
	for grid_y in SAMPLE_GRID + 1:
		for grid_x in SAMPLE_GRID + 1:
			heights[grid_y * (SAMPLE_GRID + 1) + grid_x] = host.world.height_at(Vector2(grid_x * cell, grid_y * cell))
	_find_terrain_peaks(heights, cell)
	for level in range(int(CONTOUR_STEP_M), 3250, int(CONTOUR_STEP_M)):
		for y in SAMPLE_GRID:
			for x in SAMPLE_GRID:
				var p0 = Vector2(x * cell, y * cell)
				var p1 = Vector2((x + 1) * cell, y * cell)
				var p2 = Vector2((x + 1) * cell, (y + 1) * cell)
				var p3 = Vector2(x * cell, (y + 1) * cell)
				var h0: float = heights[y * (SAMPLE_GRID + 1) + x]
				var h1: float = heights[y * (SAMPLE_GRID + 1) + x + 1]
				var h2: float = heights[(y + 1) * (SAMPLE_GRID + 1) + x + 1]
				var h3: float = heights[(y + 1) * (SAMPLE_GRID + 1) + x]
				var points: Array[Vector2] = []
				_add_crossing(points, p0, p1, h0, h1, level)
				_add_crossing(points, p1, p2, h1, h2, level)
				_add_crossing(points, p2, p3, h2, h3, level)
				_add_crossing(points, p3, p0, h3, h0, level)
				if points.size() >= 2:
					contour_segments.append({"a": points[0], "b": points[1], "level": float(level)})
				if points.size() == 4:
					contour_segments.append({"a": points[2], "b": points[3], "level": float(level)})
func _find_terrain_peaks(heights: PackedFloat32Array, cell: float) -> void:
	var candidates: Array[Dictionary] = []
	var row_size = SAMPLE_GRID + 1
	for y in range(1, SAMPLE_GRID):
		for x in range(1, SAMPLE_GRID):
			var height: float = heights[y * row_size + x]
			if height < CONTOUR_STEP_M:
				continue
			var is_peak = true
			for offset_y in range(-1, 2):
				for offset_x in range(-1, 2):
					if offset_x != 0 or offset_y != 0:
						if heights[(y + offset_y) * row_size + x + offset_x] >= height:
							is_peak = false
							break
				if not is_peak:
					break
			if is_peak:
				candidates.append({"position": Vector2(x * cell, y * cell), "height": height})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.height) > float(b.height))
	for candidate in candidates:
		var far_enough = true
		for chosen in terrain_peaks:
			if Vector2(candidate.position).distance_to(chosen.position) < 12.0:
				far_enough = false
				break
		if far_enough:
			terrain_peaks.append(candidate)
			if terrain_peaks.size() >= 28:
				break

func _add_crossing(points: Array[Vector2], a: Vector2, b: Vector2, ha: float, hb: float, level: float) -> void:
	if (ha < level and hb >= level) or (hb < level and ha >= level):
		points.append(a.lerp(b, inverse_lerp(ha, hb, level)))
