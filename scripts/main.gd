extends Control

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
const MapRenderLayerScript = preload("res://scripts/map_render_layer.gd")

const MAP_MARGIN := 14.0
const PANEL_HEIGHT := 280.0
const CONTOUR_STEP_M := 250.0
const SAMPLE_GRID := 96
const INSTRUMENT_RADIUS := 50.0
const INSTRUMENT_GAP := 14.0
const THROTTLE_HOLD_DELAY := 0.32
const THROTTLE_HOLD_RATE := 0.35
const USE_STYLIZED_YOKE := true

var world
var flight
var selected_beacons := [0, 1]
var map_zoom := 1.0
var map_center := Vector2(50, 50)
var contour_segments: Array[Dictionary] = []
var measurement_lines: Array[Dictionary] = []
var pending_measure: Variant = null
var dragging_map := false
var map_drag_candidate := false
var map_press_position := Vector2.ZERO
var point_drag_candidate := false
var dragging_measure_point := false
var dragged_measure_connections: Array[Dictionary] = []
var dragging_yoke := false
var dragging_throttle := false
var last_mouse := Vector2.ZERO
var status_timer := 0.0
var clock_seconds := 12.0 * 60.0 * 60.0
var ils_airport_index := 1
var simulation_paused := false
var signal_check_timer := 0.0
var receiver_signal_status: Array[Dictionary] = [{}, {}]
var ils_signal_status: Dictionary = {}
var ils_prediction_timer := 0.0
var ils_touchdown_prediction: Dictionary = {"valid": false, "distance_from_threshold_km": 0.0}
var map_render_layer: Control
var map_canvas: Control
var throttle_up_held := false
var throttle_down_held := false
var throttle_up_hold_time := 0.0
var throttle_down_hold_time := 0.0

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	map_render_layer = MapRenderLayerScript.new()
	map_render_layer.controller = self
	map_render_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map_render_layer)
	resized.connect(_queue_map_redraw)
	regenerate_world()
	set_process(true)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event.keycode == KEY_W or event.keycode == KEY_S):
		if event.echo:
			get_viewport().set_input_as_handled()
			return
		var increase: bool = event.keycode == KEY_W
		if increase:
			throttle_up_held = event.pressed
			throttle_up_hold_time = 0.0
		else:
			throttle_down_held = event.pressed
			throttle_down_hold_time = 0.0
			if not event.pressed and flight != null:
				flight.wheel_brakes_applied = false
		if event.pressed and flight != null:
			_adjust_throttle_percent(1 if increase else -1)
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q and event.ctrl_pressed:
			get_tree().quit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			simulation_paused = not simulation_paused
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.keycode == KEY_R:
			regenerate_world()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			flight.yoke = Vector2.ZERO
			get_viewport().set_input_as_handled()
			queue_redraw()

func regenerate_world() -> void:
	world = FlightWorldScript.new()
	flight = FlightModelScript.new(world)
	map_center = Vector2(50, 50)
	map_zoom = 1.0
	measurement_lines.clear()
	pending_measure = null
	clock_seconds = 12.0 * 60.0 * 60.0
	ils_airport_index = 1
	ils_prediction_timer = 0.0
	_build_contours()
	_update_receiver_signals()
	_update_ils_touchdown_prediction()
	_queue_map_redraw()
	queue_redraw()

func _process(delta: float) -> void:
	if simulation_paused:
		return
	signal_check_timer -= delta
	if signal_check_timer <= 0.0:
		_update_receiver_signals()
		signal_check_timer = 1.0
	ils_prediction_timer -= delta
	if ils_prediction_timer <= 0.0:
		_update_ils_touchdown_prediction()
		ils_prediction_timer = 1.0
	clock_seconds = fmod(clock_seconds + delta, 24.0 * 60.0 * 60.0)
	var keyboard_yoke := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if not dragging_yoke:
		if absf(keyboard_yoke.x) > 0.05:
			flight.yoke.x = keyboard_yoke.x
		else:
			flight.yoke.x = move_toward(flight.yoke.x, 0.0, delta * 1.8)
		if absf(keyboard_yoke.y) > 0.05:
			# Only the pitch axis is positional: releasing Up/Down leaves the
			# elevator command where the pilot set it.
			flight.yoke.y = clampf(flight.yoke.y + keyboard_yoke.y * delta * 0.75, -1.0, 1.0)
	_update_held_throttle(delta)
	flight.update(delta)
	status_timer += delta
	queue_redraw()

func _adjust_throttle_percent(step_percent: int) -> void:
	var current_percent := roundi(flight.throttle * 100.0)
	if step_percent < 0 and current_percent <= 0 and _aircraft_is_on_ground():
		flight.wheel_brakes_applied = true
		return
	if step_percent > 0:
		flight.wheel_brakes_applied = false
	flight.throttle = clampf((current_percent + step_percent) / 100.0, 0.0, 1.0)

func _update_held_throttle(delta: float) -> void:
	if throttle_up_held:
		var previous_time := throttle_up_hold_time
		throttle_up_hold_time += delta
		var active_delta := maxf(0.0, throttle_up_hold_time - THROTTLE_HOLD_DELAY) - maxf(0.0, previous_time - THROTTLE_HOLD_DELAY)
		flight.throttle = minf(1.0, flight.throttle + active_delta * THROTTLE_HOLD_RATE)
	if throttle_down_held:
		var previous_time := throttle_down_hold_time
		throttle_down_hold_time += delta
		var active_delta := maxf(0.0, throttle_down_hold_time - THROTTLE_HOLD_DELAY) - maxf(0.0, previous_time - THROTTLE_HOLD_DELAY)
		flight.throttle = maxf(0.0, flight.throttle - active_delta * THROTTLE_HOLD_RATE)
		if flight.throttle <= 0.001 and _aircraft_is_on_ground():
			flight.throttle = 0.0
			flight.wheel_brakes_applied = true

func _aircraft_is_on_ground() -> bool:
	return flight.state == FlightModelScript.State.PARKED or flight.state == FlightModelScript.State.ROLLING or flight.state == FlightModelScript.State.LANDED

func map_rect() -> Rect2:
	return Rect2(MAP_MARGIN, MAP_MARGIN, size.x - MAP_MARGIN * 2.0, max(300.0, size.y - PANEL_HEIGHT - MAP_MARGIN * 2.0))

func panel_rect() -> Rect2:
	var m := map_rect()
	return Rect2(MAP_MARGIN, m.end.y + 8.0, size.x - MAP_MARGIN * 2.0, size.y - m.end.y - 16.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10171b"))
	_draw_panel()

func _draw_map_on(canvas: Control) -> void:
	map_canvas = canvas
	_draw_map()
	map_canvas = null

func _queue_map_redraw() -> void:
	if map_render_layer != null:
		map_render_layer.queue_redraw()

func _draw_map() -> void:
	var rect := map_rect()
	map_canvas.draw_rect(rect, Color("d7d0ad"), true)
	map_canvas.draw_rect(rect, Color("6d6751"), false, 2.0)
	# 10 km coordinate grid.
	for k in range(0, 101, 10):
		var a := world_to_screen(Vector2(k, 0))
		var b := world_to_screen(Vector2(k, 100))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
		a = world_to_screen(Vector2(0, k))
		b = world_to_screen(Vector2(100, k))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
	for segment in contour_segments:
		var level: float = segment.level
		var color := Color("806f4b") if int(level) % 500 != 0 else Color("5c4b31")
		var width := 1.0 if int(level) % 500 != 0 else 1.7
		_draw_clipped_map_line(world_to_screen(segment.a), world_to_screen(segment.b), color, width)
	_draw_contour_labels(rect)
	for airport in world.airports:
		_draw_airport(airport)
		_draw_approach_point(airport)
	for beacon in world.beacons:
		_draw_beacon(beacon)
	for line in measurement_lines:
		_draw_measurement(line.a, line.b)
	if pending_measure != null:
		_draw_measurement(pending_measure, _snap_map_point(get_local_mouse_position()), Color(0.1, 0.25, 0.7, 0.55))
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), "НАВИГАЦИОННАЯ КАРТА • положение самолёта не отображается", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("35372e"))
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 40), "Изолинии: 250 м  •  ЛКМ: точка/линия  •  ЛКМ с движением: карта  •  ПКМ: отмена/стереть  •  колесо: масштаб", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var scale_km := 10.0
	var scale_px := scale_km * pixels_per_km()
	var scale_start := rect.end - Vector2(scale_px + 18, 18)
	map_canvas.draw_line(scale_start, scale_start + Vector2(scale_px, 0), Color("25271f"), 3)
	map_canvas.draw_string(ThemeDB.fallback_font, scale_start - Vector2(0, 6), "10 км", HORIZONTAL_ALIGNMENT_CENTER, scale_px, 12, Color("25271f"))

func _draw_contour_labels(rect: Rect2) -> void:
	var placed_by_level: Dictionary = {}
	var safe_rect := rect.grow(-28.0)
	for segment in contour_segments:
		var level := int(segment.level)
		var midpoint: Vector2 = (world_to_screen(segment.a) + world_to_screen(segment.b)) * 0.5
		if not safe_rect.has_point(midpoint):
			continue
		if not placed_by_level.has(level):
			placed_by_level[level] = []
		var positions: Array = placed_by_level[level]
		if positions.size() >= 3:
			continue
		var far_enough := true
		for existing: Vector2 in positions:
			if existing.distance_to(midpoint) < 210.0:
				far_enough = false
				break
		if not far_enough:
			continue
		var label := "%d м" % level
		var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var background := Rect2(midpoint - Vector2(text_size.x * 0.5 + 3.0, 9.0), text_size + Vector2(6.0, 3.0))
		map_canvas.draw_rect(background, Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, midpoint + Vector2(-text_size.x * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("55462f"))
		positions.append(midpoint)

func _draw_airport(airport: Dictionary) -> void:
	var center := world_to_screen(airport.position)
	var vector: Vector2 = world.heading_vector(airport.heading) * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var a := world_to_screen(airport.position - vector)
	var b := world_to_screen(airport.position + vector)
	_draw_clipped_map_line(a, b, Color("222722"), max(4.0, pixels_per_km() * 0.12))
	_draw_clipped_map_line(a, b, Color("f0ead2"), 1.0)
	if map_rect().has_point(a):
		map_canvas.draw_circle(a, 3.0, Color("20241f"))
	if map_rect().has_point(b):
		map_canvas.draw_circle(b, 3.0, Color("20241f"))
	if not map_rect().grow(-8.0).has_point(center):
		return
	var direct_course := int(round(airport.heading)) % 360
	var reverse_course := (direct_course + 180) % 360
	_draw_clamped_map_text(center + Vector2(7, -7), "%s  %03d°/%03d°" % [airport.name, direct_course, reverse_course], 12, Color("20241f"))

func _draw_approach_point(airport: Dictionary) -> void:
	var forward: Vector2 = world.heading_vector(airport.heading)
	var threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var approach_position: Vector2 = threshold - forward * 4.0
	var point := world_to_screen(approach_position)
	var threshold_screen := world_to_screen(threshold)
	if not map_rect().grow(-8.0).has_point(point):
		return
	_draw_clipped_map_line(point, threshold_screen, Color("287777"), 1.5, true)
	var diamond := PackedVector2Array([
		point + Vector2(0, -6),
		point + Vector2(6, 0),
		point + Vector2(0, 6),
		point + Vector2(-6, 0),
	])
	map_canvas.draw_colored_polygon(diamond, Color("d7d0ad"))
	map_canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("185f61"), 2.0)
	var desired_altitude := 4000.0 * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
	var approach_vertical_speed := -(92.0 / 3.6) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
	var label := "ВХОД «%s»  %.0f м • верт. %.1f м/с" % [airport.name, desired_altitude, approach_vertical_speed]
	var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	var label_position := point + Vector2(9, -9)
	if label_position.x + text_size.x + 5 > map_rect().end.x:
		label_position.x = point.x - text_size.x - 9
	if label_position.y - 13 < map_rect().position.y:
		label_position.y = point.y + 19
	label_position.x = clampf(label_position.x, map_rect().position.x + 4.0, map_rect().end.x - text_size.x - 4.0)
	label_position.y = clampf(label_position.y, map_rect().position.y + text_size.y + 2.0, map_rect().end.y - 4.0)
	map_canvas.draw_rect(Rect2(label_position + Vector2(-3, -12), text_size + Vector2(6, 4)), Color("d7d0ad"), true)
	map_canvas.draw_string(ThemeDB.fallback_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("185f61"))

func _draw_beacon(beacon: Dictionary) -> void:
	var p := world_to_screen(beacon.position)
	if not map_rect().grow(-8.0).has_point(p):
		return
	var radius := 5.0
	var points := PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, radius), p + Vector2(-radius, radius)])
	map_canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color("972d25"), 2.0)
	_draw_clamped_map_text(p + Vector2(7, 12), "%s %.0f" % [beacon.name, beacon.frequency], 11, Color("76231d"))

func _draw_measurement(a_world: Vector2, b_world: Vector2, color := Color("254d9a")) -> void:
	var a := world_to_screen(a_world)
	var b := world_to_screen(b_world)
	_draw_clipped_map_line(a, b, color, 2.0, true)
	if map_rect().has_point(a):
		map_canvas.draw_circle(a, 3, color)
	if map_rect().has_point(b):
		map_canvas.draw_circle(b, 3, color)
	var distance := a_world.distance_to(b_world)
	var bearing: float = world.vector_heading(b_world - a_world)
	var direct_course := int(round(bearing)) % 360
	var reverse_course := (direct_course + 180) % 360
	var label := "%.1f км  %03d° / %03d°" % [distance, direct_course, reverse_course]
	var visible_segment := _clip_line_to_rect(a, b, map_rect().grow(-3.0))
	if visible_segment.size() == 2:
		var visible_direction: Vector2 = visible_segment[1] - visible_segment[0]
		var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		# A label is useful only when the visible line is substantially longer
		# than the text. Zooming in increases this length and reveals the label.
		if visible_direction.length() >= text_size.x * 1.35 + 20.0:
			var midpoint: Vector2 = (visible_segment[0] + visible_segment[1]) * 0.5
			if map_rect().grow(-24.0).has_point(midpoint):
				_draw_rotated_map_label(midpoint, visible_direction, label, color)

func _draw_clipped_map_line(a: Vector2, b: Vector2, color: Color, width: float, dashed := false) -> void:
	var clipped := _clip_line_to_rect(a, b, map_rect().grow(-maxf(1.0, width * 0.5)))
	if clipped.size() != 2:
		return
	if dashed:
		map_canvas.draw_dashed_line(clipped[0], clipped[1], color, width, 7.0)
	else:
		map_canvas.draw_line(clipped[0], clipped[1], color, width, true)

func _draw_clamped_map_text(position: Vector2, label: String, font_size: int, color: Color) -> void:
	var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var safe_position := Vector2(
		clampf(position.x, map_rect().position.x + 4.0, map_rect().end.x - text_size.x - 4.0),
		clampf(position.y, map_rect().position.y + text_size.y + 2.0, map_rect().end.y - 4.0)
	)
	map_canvas.draw_string(ThemeDB.fallback_font, safe_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _clip_line_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	# Liang–Barsky line clipping in screen coordinates.
	var delta := b - a
	var t_min := 0.0
	var t_max := 1.0
	var p_values := [-delta.x, delta.x, -delta.y, delta.y]
	var q_values := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		var p: float = p_values[i]
		var q: float = q_values[i]
		if is_zero_approx(p):
			if q < 0.0:
				return PackedVector2Array()
			continue
		var ratio := q / p
		if p < 0.0:
			t_min = maxf(t_min, ratio)
		else:
			t_max = minf(t_max, ratio)
		if t_min > t_max:
			return PackedVector2Array()
	return PackedVector2Array([a + delta * t_min, a + delta * t_max])

func _draw_rotated_map_label(position: Vector2, line_direction: Vector2, label: String, color: Color) -> void:
	var angle := line_direction.angle()
	# Keep text parallel to the line, but never render it upside down.
	if angle > PI * 0.5 or angle < -PI * 0.5:
		angle += PI
	var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	map_canvas.draw_set_transform(position, angle, Vector2.ONE)
	# Keep a clear gap between the line at local Y=0 and the label above it.
	map_canvas.draw_rect(Rect2(Vector2(-text_size.x * 0.5 - 3.0, -25.0), text_size + Vector2(6.0, 4.0)), Color("d7d0ad"), true)
	map_canvas.draw_string(ThemeDB.fallback_font, Vector2(-text_size.x * 0.5, -13.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	map_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_panel() -> void:
	var rect := panel_rect()
	draw_rect(rect, Color("1d282d"), true)
	draw_rect(rect, Color("536067"), false, 2)
	var y := rect.position.y + 12.0
	var gauge_y := y + 96.0
	var speed_center := _instrument_center(0, gauge_y)
	_draw_round_gauge(speed_center, INSTRUMENT_RADIUS, "СКОРОСТЬ", "%.0f" % flight.speed_kmh, "км/ч", flight.speed_kmh / 200.0)
	if flight.wheel_brakes_applied:
		draw_string(ThemeDB.fallback_font, speed_center + Vector2(-INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 34), "ТОРМОЗ", HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2.0, 11, Color("ef645e"))
	_draw_round_gauge(_instrument_center(1, gauge_y), INSTRUMENT_RADIUS, "ВЫСОТА", "%.0f" % flight.altitude_m, "м", flight.altitude_m / 5000.0)
	_draw_variometer(_instrument_center(2, gauge_y), INSTRUMENT_RADIUS)
	_draw_compass(_instrument_center(3, gauge_y), INSTRUMENT_RADIUS)
	_draw_horizon(_instrument_center(4, gauge_y), INSTRUMENT_RADIUS)
	_draw_beacon_instrument(_instrument_center(5, gauge_y), INSTRUMENT_RADIUS, 0)
	_draw_beacon_instrument(_instrument_center(6, gauge_y), INSTRUMENT_RADIUS, 1)
	_draw_clock(_instrument_center(7, gauge_y), INSTRUMENT_RADIUS)
	_draw_fuel_instrument(_instrument_center(8, gauge_y), INSTRUMENT_RADIUS)
	_draw_ils()
	_draw_controls(rect)
	var status_text: String = "ПАУЗА" if simulation_paused else flight.message
	var state_color: Color = Color("e8d274") if simulation_paused else (Color("65d48c") if flight.state == FlightModelScript.State.LANDED else (Color("ef645e") if flight.state == FlightModelScript.State.CRASHED else Color("e8d274")))
	if not simulation_paused and flight.state == FlightModelScript.State.FLYING and flight.stalled:
		status_text = "СВАЛИВАНИЕ — ОТДАТЬ ШТУРВАЛ ОТ СЕБЯ"
		state_color = Color("ef645e")
	elif not simulation_paused and flight.stall_warning_active():
		status_text = "ПРЕДУПРЕЖДЕНИЕ: БОЛЬШОЙ УГОЛ АТАКИ"
		state_color = Color("e8d274")
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, rect.size.y - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 330, 15, state_color)
	draw_string(ThemeDB.fallback_font, Vector2(rect.end.x - 470, rect.end.y - 10), "W/S: газ  •  стрелки/C: штурвал  •  R: новая карта", HORIZONTAL_ALIGNMENT_RIGHT, 446, 12, Color("aebbc1"))

func _instrument_center(index: int, gauge_y: float) -> Vector2:
	var step := INSTRUMENT_RADIUS * 2.0 + INSTRUMENT_GAP
	return Vector2(panel_rect().position.x + INSTRUMENT_RADIUS + 5.0 + index * step, gauge_y)

func _draw_round_gauge(center: Vector2, radius: float, title: String, value: String, unit: String, ratio: float) -> void:
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	for i in 11:
		var angle: float = lerpf(-PI * 0.75, PI * 0.75, i / 10.0)
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 6)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 12)
		draw_line(inner, outer, Color("d2dde0"), 1)
	var needle_angle: float = lerpf(-PI * 0.75, PI * 0.75, clampf(ratio, 0, 1))
	draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("ed775f"), 2)
	draw_circle(center, 3, Color("d8dfe0"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), title, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%s %s" % [value, unit], HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func _draw_compass(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	for degrees in range(0, 360, 30):
		# The compass rose is fixed: north is always at the top.
		var angle := deg_to_rad(degrees - 90)
		var p := center + Vector2(cos(angle), sin(angle)) * (radius - 14)
		var mark := "N" if degrees == 0 else ("E" if degrees == 90 else ("S" if degrees == 180 else ("W" if degrees == 270 else str(degrees))))
		draw_string(ThemeDB.fallback_font, p - Vector2(11, -4), mark, HORIZONTAL_ALIGNMENT_CENTER, 22, 10, Color("d5ddde"))
	var heading_angle: float = deg_to_rad(flight.heading_deg - 90.0)
	var heading_vector := Vector2(cos(heading_angle), sin(heading_angle))
	var arrow_tip := center + heading_vector * (radius - 8.0)
	var arrow_side := Vector2(-heading_vector.y, heading_vector.x)
	draw_line(center - heading_vector * 10.0, arrow_tip, Color("e5b752"), 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		arrow_tip,
		arrow_tip - heading_vector * 12.0 + arrow_side * 6.0,
		arrow_tip - heading_vector * 12.0 - arrow_side * 6.0,
	]), Color("e5b752"))
	draw_circle(center, 3.0, Color("e5b752"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "КОМПАС", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%03d°" % int(round(flight.heading_deg)), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func _draw_variometer(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# Шкала симметрична: -10 м/с слева, 0 сверху, +10 м/с справа.
	for i in 11:
		var value := -10.0 + i * 2.0
		var angle := lerpf(-PI * 0.75, PI * 0.75, inverse_lerp(-10.0, 10.0, value))
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 6)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 12)
		draw_line(inner, outer, Color("d2dde0"), 1)
	var shown_speed: float = clampf(flight.vertical_speed_mps, -10.0, 10.0)
	var needle_angle: float = lerpf(-PI * 0.75, PI * 0.75, inverse_lerp(-10.0, 10.0, shown_speed))
	draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("79cfa4"), 2)
	draw_circle(center, 3, Color("d8dfe0"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ВАРИОМЕТР", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%+.1f м/с" % flight.vertical_speed_mps, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func _draw_clock(center: Vector2, radius: float) -> void:
	var whole_seconds := int(clock_seconds)
	var hours: int = whole_seconds / 3600
	var minutes: int = (whole_seconds % 3600) / 60
	var seconds: int = whole_seconds % 60
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 1, 0, TAU, 40, Color("7d8b91"), 2)
	for hour_mark in 12:
		var mark_angle := deg_to_rad(hour_mark * 30.0 - 90.0)
		var outer := center + Vector2(cos(mark_angle), sin(mark_angle)) * (radius - 4)
		var inner_length := 8.0 if hour_mark % 3 == 0 else 5.0
		var inner := center + Vector2(cos(mark_angle), sin(mark_angle)) * (radius - inner_length)
		draw_line(inner, outer, Color("d2dde0"), 1.5)
	var hour_angle := deg_to_rad(fmod(hours, 12) * 30.0 + minutes * 0.5 - 90.0)
	var minute_angle := deg_to_rad(minutes * 6.0 + seconds * 0.1 - 90.0)
	var second_angle := deg_to_rad(seconds * 6.0 - 90.0)
	draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * (radius * 0.48), Color("edf2f2"), 3.0, true)
	draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * (radius * 0.68), Color("edf2f2"), 2.0, true)
	draw_line(center, center + Vector2(cos(second_angle), sin(second_angle)) * (radius * 0.73), Color("ed775f"), 1.0, true)
	draw_circle(center, 2.5, Color("edf2f2"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ЧАСЫ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%02d:%02d:%02d" % [hours, minutes, seconds], HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 13, Color.WHITE)

func _draw_fuel_instrument(center: Vector2, radius: float) -> void:
	var flow: float = flight.fuel_flow_lpm()
	var estimated_range: float = flight.estimated_range_km()
	var max_flow := 0.78
	var remaining_ratio: float = clampf(flight.fuel_l / flight.fuel_capacity_l, 0.0, 1.0)
	var flow_ratio: float = clampf(flow / max_flow, 0.0, 1.0)
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	draw_line(center + Vector2(0, -radius + 3), center + Vector2(0, radius - 3), Color("536067"), 1.0)
	for i in 6:
		var left_angle: float = lerpf(PI * 0.5, PI * 1.5, i / 5.0)
		var right_angle: float = lerpf(-PI * 0.5, PI * 0.5, i / 5.0)
		for angle in [left_angle, right_angle]:
			var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 6)
			var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 12)
			draw_line(inner, outer, Color("d2dde0"), 1)
	var left_needle_angle: float = lerpf(PI * 0.5, PI * 1.5, remaining_ratio)
	var right_needle_angle: float = lerpf(-PI * 0.5, PI * 0.5, flow_ratio)
	draw_line(center, center + Vector2(cos(left_needle_angle), sin(left_needle_angle)) * (radius - 15), Color("e6c75b"), 2.0, true)
	draw_line(center, center + Vector2(cos(right_needle_angle), sin(right_needle_angle)) * (radius - 15), Color("6fc78c"), 2.0, true)
	draw_circle(center, 3.0, Color("d8dfe0"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, 5), "ОСТ", HORIZONTAL_ALIGNMENT_CENTER, radius, 8, Color("e6c75b"))
	draw_string(ThemeDB.fallback_font, center + Vector2(0, 5), "РАСХ", HORIZONTAL_ALIGNMENT_CENTER, radius, 8, Color("6fc78c"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ТОПЛИВО", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), "Расход %.1f л/мин" % flow, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color("6fc78c"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 7.0, radius + 29), "%.1f/%.0f л • запас %.0f км" % [flight.fuel_l, flight.fuel_capacity_l, estimated_range], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 14.0, 9, Color.WHITE)

func _draw_ils() -> void:
	var rect := get_ils_rect()
	var guidance: Dictionary = flight.landing_guidance(ils_airport_index, ils_signal_status.get("available", false))
	var airport: Dictionary = guidance.airport
	draw_rect(rect, Color("0a0e10"), true)
	draw_rect(rect, Color("6f7f85"), false, 1.5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 12), "ILS %s  [нажать]" % airport.name, HORIZONTAL_ALIGNMENT_LEFT, 200, 10, Color("b8c5c8"))
	var display := Rect2(rect.position + Vector2(7, 16), Vector2(82, 35))
	var center := display.get_center()
	var airport_cross_color := Color("66878a")
	draw_line(Vector2(display.position.x, center.y), Vector2(display.end.x, center.y), airport_cross_color, 1.5)
	draw_line(Vector2(center.x, display.position.y), Vector2(center.x, display.end.y), airport_cross_color, 1.5)
	draw_circle(center, 2.5, airport_cross_color)
	if not guidance.signal_available:
		draw_line(display.position + Vector2(8, 4), display.end - Vector2(8, 4), Color("c95d55"), 2.0)
		draw_line(Vector2(display.end.x - 8, display.position.y + 4), Vector2(display.position.x + 8, display.end.y - 4), Color("c95d55"), 2.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 37), "НЕТ СИГНАЛА", HORIZONTAL_ALIGNMENT_LEFT, 104, 10, Color("c95d55"))
		return
	draw_line(rect.position + Vector2(207, 4), rect.position + Vector2(207, rect.size.y - 4), Color("536067"), 1.0)
	var desired_vs: float = -(flight.speed_kmh / 3.6) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
	var altitude_color := _ils_parameter_color(absf(guidance.glide_error), true)
	var vertical_speed_color := _ils_parameter_color(absf(flight.vertical_speed_mps - desired_vs) / 0.35, true)
	var course_error_color := _ils_parameter_color(absf(guidance.course_error_deg), true, 1.0, 5.0)
	var approach_speed_color := Color("65d48c")
	if flight.speed_kmh >= 100.0:
		approach_speed_color = Color("ef645e")
	elif flight.speed_kmh > 95.0:
		approach_speed_color = Color("e8d274")
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 22), "H %.1f м" % flight.altitude_m, HORIZONTAL_ALIGNMENT_LEFT, 76, 12, altitude_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(292, 22), "VS %+.2f м/с" % flight.vertical_speed_mps, HORIZONTAL_ALIGNMENT_LEFT, 105, 12, vertical_speed_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(399, 22), "V %.1f км/ч" % flight.speed_kmh, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 407, 11, approach_speed_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 42), "ОТКЛ. КУРСА %+.1f°" % guidance.course_error_deg, HORIZONTAL_ALIGNMENT_LEFT, 132, 12, course_error_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(350, 42), "ДО ВПП %.2f км" % guidance.actual_distance_to_threshold_km, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 358, 12, Color.WHITE)
	if ils_touchdown_prediction.valid:
		var touchdown_distance: float = ils_touchdown_prediction.distance_from_threshold_km
		var touchdown_color := Color("65d48c") if touchdown_distance >= 0.0 and touchdown_distance <= FlightWorldScript.RUNWAY_LENGTH_KM else Color("ef645e")
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 61), "КАСАНИЕ %+.2f км ОТ ТОРЦА" % touchdown_distance, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 224, 12, touchdown_color)
	else:
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 61), "КАСАНИЕ — НЕТ СНИЖЕНИЯ", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 224, 12, Color("e8d274"))
	# Runway edges live on the airport's fixed horizontal axis. Far from the
	# airport they are close together; towards the threshold they spread apart.
	var runway_half_width_km := FlightWorldScript.RUNWAY_WIDTH_KM * 0.5
	var runway_edge_error: float = runway_half_width_km / guidance.localizer_tolerance_km
	var runway_edge_spacing: float = maxf(2.0, runway_edge_error * display.size.x * 0.30)
	for side in [-1.0, 1.0]:
		var edge_x: float = center.x + side * runway_edge_spacing
		draw_line(Vector2(edge_x, center.y - 5.0), Vector2(edge_x, center.y + 5.0), Color("a9c0c1"), 2.0)
	# The fixed cross is the airport. The moving cross is the aircraft: right of
	# center means right of the localizer, above center means above glide path.
	var localizer_x: float = center.x + clampf(guidance.localizer_error, -1.4, 1.4) * display.size.x * 0.30
	var glide_y: float = center.y - clampf(guidance.glide_error, -1.4, 1.4) * display.size.y * 0.30
	var localizer_severity: float = maxf(absf(guidance.localizer_error), absf(guidance.course_error_deg) / 14.0)
	var glide_severity: float = absf(guidance.glide_error)
	var localizer_line_color := _ils_parameter_color(localizer_severity, true)
	var glide_line_color := _ils_parameter_color(glide_severity, true)
	var aircraft_center_color := _ils_parameter_color(maxf(localizer_severity, glide_severity), true)
	draw_line(Vector2(localizer_x, display.position.y + 3), Vector2(localizer_x, display.end.y - 3), localizer_line_color, 2.0)
	draw_line(Vector2(display.position.x + 3, glide_y), Vector2(display.end.x - 3, glide_y), glide_line_color, 2.0)
	draw_circle(Vector2(localizer_x, glide_y), 2.5, aircraft_center_color)
	var localizer_color := Color("65d48c") if guidance.in_localizer else Color("e8d274")
	var glide_color := Color("65d48c") if guidance.in_glide else Color("e8d274")
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 30), "СТВОР" if guidance.in_localizer else "ВНЕ СТВОРА", HORIZONTAL_ALIGNMENT_LEFT, 104, 10, localizer_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 44), "ГЛИСС" if guidance.in_glide else ("ВЫСОКО" if guidance.glide_error > 0 else "НИЗКО"), HORIZONTAL_ALIGNMENT_LEFT, 104, 10, glide_color)

func _ils_parameter_color(error: float, signal_available: bool, green_limit: float = 1.0, yellow_limit: float = 2.0) -> Color:
	if not signal_available or error > yellow_limit:
		return Color("ef645e")
	if error > green_limit:
		return Color("e8d274")
	return Color("65d48c")

func _draw_horizon(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("0a0e10"))
	var horizon_offset: float = flight.pitch_deg * 1.9
	var angle: float = deg_to_rad(-flight.bank_deg)
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var horizon_center: Vector2 = center + normal * horizon_offset
	draw_line(horizon_center - direction * 52, horizon_center + direction * 52, Color("d9e3e4"), 3)
	draw_line(center - Vector2(25, 0), center - Vector2(7, 0), Color("e7c25f"), 3)
	draw_line(center + Vector2(7, 0), center + Vector2(25, 0), Color("e7c25f"), 3)
	draw_circle(center, 3, Color("e7c25f"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "АВИАГОРИЗОНТ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	var aoa_color := Color("ef645e") if flight.stalled else (Color("e8d274") if flight.stall_warning_active() else Color.WHITE)
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "УА %+.1f°" % flight.angle_of_attack_deg, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 12, aoa_color)

func _draw_beacon_instrument(center: Vector2, radius: float, instrument: int) -> void:
	var beacon: Dictionary = world.beacons[selected_beacons[instrument]]
	var delta: Vector2 = beacon.position - flight.position_km
	var absolute_bearing: float = world.vector_heading(delta)
	var signal_status: Dictionary = receiver_signal_status[instrument]
	var signal_available: bool = signal_status.get("available", false)
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# North-up receiver: the arrow shows absolute map bearing, independent of heading.
	var needle_angle: float = deg_to_rad(absolute_bearing - 90.0)
	var needle_direction := Vector2(cos(needle_angle), sin(needle_angle))
	var needle_side := Vector2(-needle_direction.y, needle_direction.x)
	var needle_tip := center + needle_direction * (radius - 7.0)
	if signal_available:
		draw_line(center - needle_direction * 10.0, needle_tip, Color("73d6d0"), 1.5, true)
		draw_colored_polygon(PackedVector2Array([
			needle_tip,
			needle_tip - needle_direction * 8.0 + needle_side * 3.5,
			needle_tip - needle_direction * 8.0 - needle_side * 3.5,
		]), Color("73d6d0"))
		draw_circle(center, 2.5, Color("73d6d0"))
	else:
		draw_line(center + Vector2(-12, -12), center + Vector2(12, 12), Color("c95d55"), 2.0)
		draw_line(center + Vector2(12, -12), center + Vector2(-12, 12), Color("c95d55"), 2.0)
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ПРИЁМНИК %d" % (instrument + 1), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), "%s  %.0f кГц  R%.0f" % [beacon.name, beacon.frequency, beacon.range_km], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 9, Color.WHITE)
	if signal_available:
		var direct_course := int(round(absolute_bearing)) % 360
		var reverse_course := (direct_course + 180) % 360
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), "%.1f км  %03d°/%03d°" % [delta.length(), direct_course, reverse_course], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 10, Color("73d6d0"))
	else:
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), signal_status.get("reason", "НЕТ СИГНАЛА"), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 9, Color("c95d55"))

func _update_receiver_signals() -> void:
	if world == null or flight == null:
		return
	for instrument in 2:
		var beacon: Dictionary = world.beacons[selected_beacons[instrument]]
		receiver_signal_status[instrument] = world.beacon_signal(beacon, flight.position_km, flight.altitude_m)
	var ils_beacon: Dictionary = world.beacons[ils_airport_index]
	ils_signal_status = world.beacon_signal(ils_beacon, flight.position_km, flight.altitude_m)

func _update_ils_touchdown_prediction() -> void:
	if flight == null:
		return
	ils_touchdown_prediction = flight.touchdown_prediction(ils_airport_index)

func _draw_controls(rect: Rect2) -> void:
	var throttle_rect := get_throttle_rect()
	draw_rect(throttle_rect, Color("0a0e10"), true)
	draw_rect(throttle_rect, Color("6f7f85"), false, 2)
	var handle_y: float = lerpf(throttle_rect.end.y - 8, throttle_rect.position.y + 8, flight.throttle)
	draw_rect(Rect2(throttle_rect.position.x - 5, handle_y - 5, throttle_rect.size.x + 10, 10), Color("e49a4f"), true)
	draw_string(ThemeDB.fallback_font, throttle_rect.position - Vector2(13, 7), "ГАЗ", HORIZONTAL_ALIGNMENT_CENTER, throttle_rect.size.x + 26, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, Vector2(throttle_rect.position.x - 56, handle_y + 5), "%d%%" % roundi(flight.throttle * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 44, 11, Color.WHITE)
	var yoke_rect := get_yoke_rect()
	if USE_STYLIZED_YOKE:
		_draw_stylized_yoke(yoke_rect)
	else:
		_draw_legacy_yoke(yoke_rect)
	draw_string(ThemeDB.fallback_font, yoke_rect.position - Vector2(0, 7), "ШТУРВАЛ", HORIZONTAL_ALIGNMENT_CENTER, yoke_rect.size.x, 11, Color("b8c5c8"))
	var center_button := get_center_yoke_button_rect()
	draw_rect(center_button, Color("334b55"), true)
	draw_rect(center_button, Color("82979f"), false, 1)
	draw_string(ThemeDB.fallback_font, center_button.position + Vector2(0, 17), "ЦЕНТР", HORIZONTAL_ALIGNMENT_CENTER, center_button.size.x, 10, Color.WHITE)
	if flight.state == FlightModelScript.State.PARKED or flight.state == FlightModelScript.State.LANDED or flight.state == FlightModelScript.State.CRASHED:
		var button := get_action_button_rect()
		draw_rect(button, Color("334b55"), true)
		draw_rect(button, Color("82979f"), false, 1)
		var label := "ПОДГОТОВИТЬ К ВЫЛЕТУ" if flight.state != FlightModelScript.State.PARKED else "ЗАПРАВИТЬ И ВЫРОВНЯТЬ"
		draw_string(ThemeDB.fallback_font, button.position + Vector2(0, 21), label, HORIZONTAL_ALIGNMENT_CENTER, button.size.x, 12, Color.WHITE)

func _draw_legacy_yoke(yoke_rect: Rect2) -> void:
	draw_circle(yoke_rect.get_center(), yoke_rect.size.x * 0.5, Color("0a0e10"))
	draw_arc(yoke_rect.get_center(), yoke_rect.size.x * 0.5, 0, TAU, 48, Color("6f7f85"), 2)
	var knob: Vector2 = yoke_rect.get_center() + flight.yoke * yoke_rect.size.x * 0.38
	draw_line(yoke_rect.get_center(), knob, Color("89999f"), 3)
	draw_circle(knob, 10, Color("d9c15e"))

func _draw_stylized_yoke(yoke_rect: Rect2) -> void:
	var center := yoke_rect.get_center()
	var radius := yoke_rect.size.x * 0.5
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius, 0, TAU, 48, Color("6f7f85"), 2)
	var rotation: float = deg_to_rad(flight.yoke.x * 28.0)
	var depth_scale: float = 1.0 + flight.yoke.y * 0.16
	draw_set_transform(center, rotation, Vector2.ONE * depth_scale)
	var silhouette := PackedVector2Array([
		Vector2(-34, -24), Vector2(-39, -7), Vector2(-35, 12),
		Vector2(-25, 25), Vector2(-10, 27), Vector2(0, 21),
		Vector2(10, 27), Vector2(25, 25), Vector2(35, 12),
		Vector2(39, -7), Vector2(34, -24),
	])
	draw_polyline(silhouette, Color("273238"), 13.0, true)
	draw_polyline(silhouette, Color("75838a"), 2.2, true)
	draw_line(Vector2(-34, -23), Vector2(-39, -7), Color("9aa7ac"), 3.0, true)
	draw_line(Vector2(34, -23), Vector2(39, -7), Color("9aa7ac"), 3.0, true)
	draw_rect(Rect2(-10, -5, 20, 34), Color("1b2428"), true)
	draw_rect(Rect2(-10, -5, 20, 34), Color("657278"), false, 1.5)
	draw_circle(Vector2(-34, -25), 8.0, Color("202a2f"))
	draw_circle(Vector2(34, -25), 8.0, Color("202a2f"))
	draw_arc(Vector2(-34, -25), 8.0, 0, TAU, 20, Color("7b898f"), 1.5)
	draw_arc(Vector2(34, -25), 8.0, 0, TAU, 20, Color("7b898f"), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_throttle_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 178, rect.position.y + 62, 28, 112)

func get_yoke_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 136, rect.position.y + 62, 112, 112)

func get_action_button_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 234, rect.position.y + 211, 210, 28)

func get_center_yoke_button_rect() -> Rect2:
	var yoke_rect := get_yoke_rect()
	return Rect2(yoke_rect.get_center().x - 41.5, yoke_rect.end.y + 7, 83, 24)

func get_ils_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.get_center().x - 242.5, rect.end.y - 82.0, 485, 68)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var mrect := map_rect()
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and mrect.has_point(event.position):
		_zoom_at(event.position, 1.18)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and mrect.has_point(event.position):
		_zoom_at(event.position, 1.0 / 1.18)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			map_drag_candidate = false
			point_drag_candidate = false
			if get_throttle_rect().has_point(event.position):
				dragging_throttle = true
				_update_throttle(event.position)
			elif get_yoke_rect().has_point(event.position):
				dragging_yoke = true
				_update_yoke(event.position)
			elif get_center_yoke_button_rect().has_point(event.position):
				flight.yoke = Vector2.ZERO
			elif get_action_button_rect().has_point(event.position) and flight.state in [FlightModelScript.State.PARKED, FlightModelScript.State.LANDED, FlightModelScript.State.CRASHED]:
				var next_airport: int = flight.airport_index
				flight.prepare_at_airport(next_airport)
				flight.refuel()
				ils_airport_index = 1 - next_airport
				_update_receiver_signals()
				_update_ils_touchdown_prediction()
				ils_prediction_timer = 1.0
			elif get_ils_rect().has_point(event.position):
				ils_airport_index = 1 - ils_airport_index
				_update_receiver_signals()
				_update_ils_touchdown_prediction()
				ils_prediction_timer = 1.0
			elif _beacon_receiver_hit(event.position, 0):
				selected_beacons[0] = (selected_beacons[0] + 1) % world.beacons.size()
				_update_receiver_signals()
			elif _beacon_receiver_hit(event.position, 1):
				selected_beacons[1] = (selected_beacons[1] + 1) % world.beacons.size()
				_update_receiver_signals()
			elif mrect.has_point(event.position):
				map_press_position = event.position
				last_mouse = event.position
				if pending_measure == null:
					dragged_measure_connections = _find_measure_connections(event.position)
				else:
					dragged_measure_connections.clear()
				if dragged_measure_connections.is_empty():
					map_drag_candidate = true
				else:
					point_drag_candidate = true
		else:
			if dragging_measure_point:
				_snap_dragged_measure_point_to_endpoint(event.position)
			if (map_drag_candidate and not dragging_map or point_drag_candidate and not dragging_measure_point) and mrect.has_point(event.position):
				_handle_map_click(event.position)
			map_drag_candidate = false
			point_drag_candidate = false
			dragging_map = false
			dragging_measure_point = false
			dragged_measure_connections.clear()
			dragging_yoke = false
			dragging_throttle = false
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mrect.has_point(event.position):
		if pending_measure != null:
			pending_measure = null
		else:
			_erase_nearest_measurement(event.position)
	_queue_map_redraw()
	queue_redraw()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if point_drag_candidate and not dragging_measure_point and event.position.distance_to(map_press_position) >= 4.0:
		dragging_measure_point = true
	if dragging_measure_point:
		var rect := map_rect().grow(-3.0)
		var clamped_screen := Vector2(
			clampf(event.position.x, rect.position.x, rect.end.x),
			clampf(event.position.y, rect.position.y, rect.end.y)
		)
		var new_world := screen_to_world(clamped_screen)
		new_world.x = clampf(new_world.x, 0.0, FlightWorldScript.SIZE_KM)
		new_world.y = clampf(new_world.y, 0.0, FlightWorldScript.SIZE_KM)
		for connection in dragged_measure_connections:
			measurement_lines[connection.line_index][connection.endpoint] = new_world
		_queue_map_redraw()
		queue_redraw()
		return
	if map_drag_candidate and not dragging_map and event.position.distance_to(map_press_position) >= 6.0:
		dragging_map = true
	if dragging_map:
		map_center -= event.relative / pixels_per_km()
		_clamp_map_center()
		_queue_map_redraw()
	if dragging_yoke:
		_update_yoke(event.position)
	if dragging_throttle:
		_update_throttle(event.position)
	if pending_measure != null:
		_queue_map_redraw()

func _update_yoke(mouse: Vector2) -> void:
	var rect := get_yoke_rect()
	flight.yoke = ((mouse - rect.get_center()) / (rect.size.x * 0.38)).limit_length(1.0)

func _update_throttle(mouse: Vector2) -> void:
	var rect := get_throttle_rect()
	flight.throttle = clamp(inverse_lerp(rect.end.y - 8, rect.position.y + 8, mouse.y), 0.0, 1.0)
	if flight.throttle > 0.001:
		flight.wheel_brakes_applied = false

func _beacon_receiver_hit(point: Vector2, receiver: int) -> bool:
	var rect := panel_rect()
	var center := _instrument_center(5 + receiver, rect.position.y + 108.0)
	return point.distance_to(center) < INSTRUMENT_RADIUS

func _zoom_at(mouse: Vector2, factor: float) -> void:
	var before := screen_to_world(mouse)
	map_zoom = clamp(map_zoom * factor, 1.0, 12.0)
	var after := screen_to_world(mouse)
	map_center += before - after
	_clamp_map_center()

func _clamp_map_center() -> void:
	var visible_half := Vector2(map_rect().size.x, map_rect().size.y) / pixels_per_km() * 0.5
	var world_half := FlightWorldScript.SIZE_KM * 0.5
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
	return min(map_rect().size.x, map_rect().size.y) / FlightWorldScript.SIZE_KM * map_zoom

func world_to_screen(point: Vector2) -> Vector2:
	return map_rect().get_center() + (point - map_center) * pixels_per_km()

func screen_to_world(point: Vector2) -> Vector2:
	return map_center + (point - map_rect().get_center()) / pixels_per_km()

func _erase_nearest_measurement(mouse: Vector2) -> void:
	var closest := -1
	var closest_distance := 18.0
	for i in measurement_lines.size():
		var a := world_to_screen(measurement_lines[i].a)
		var b := world_to_screen(measurement_lines[i].b)
		var nearest := Geometry2D.get_closest_point_to_segment(mouse, a, b)
		var distance := mouse.distance_to(nearest)
		if distance < closest_distance:
			closest = i
			closest_distance = distance
	if closest >= 0:
		measurement_lines.remove_at(closest)

func _handle_map_click(screen_position: Vector2) -> void:
	var point := _snap_map_point(screen_position)
	if pending_measure == null:
		pending_measure = point
	else:
		measurement_lines.append({"a": pending_measure, "b": point})
		pending_measure = null

func _find_measure_connections(screen_position: Vector2) -> Array[Dictionary]:
	var selected_world := Vector2.ZERO
	var closest_pixels := 12.0
	var found := false
	for line in measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var distance := screen_position.distance_to(world_to_screen(endpoint))
			if distance < closest_pixels:
				closest_pixels = distance
				selected_world = endpoint
				found = true
	var connections: Array[Dictionary] = []
	if not found:
		return connections
	for line_index in measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = measurement_lines[line_index][endpoint_key]
			if endpoint.is_equal_approx(selected_world):
				connections.append({"line_index": line_index, "endpoint": endpoint_key})
	return connections

func _snap_dragged_measure_point_to_endpoint(screen_position: Vector2) -> void:
	var closest_pixels := 14.0
	var snap_target: Variant = null
	for line_index in measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			if _is_dragged_measure_connection(line_index, endpoint_key):
				continue
			var endpoint: Vector2 = measurement_lines[line_index][endpoint_key]
			var pixel_distance := screen_position.distance_to(world_to_screen(endpoint))
			if pixel_distance < closest_pixels:
				closest_pixels = pixel_distance
				snap_target = endpoint
	if snap_target == null:
		return
	for connection in dragged_measure_connections:
		measurement_lines[connection.line_index][connection.endpoint] = snap_target

func _is_dragged_measure_connection(line_index: int, endpoint_key: String) -> bool:
	for connection in dragged_measure_connections:
		if connection.line_index == line_index and connection.endpoint == endpoint_key:
			return true
	return false

func _snap_map_point(screen_position: Vector2) -> Vector2:
	var unsnapped := screen_to_world(screen_position)
	var closest_world := unsnapped
	var closest_pixels := 14.0
	for beacon in world.beacons:
		var beacon_position: Vector2 = beacon.position
		var pixel_distance := screen_position.distance_to(world_to_screen(beacon_position))
		if pixel_distance < closest_pixels:
			closest_pixels = pixel_distance
			closest_world = beacon_position
	for line in measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var pixel_distance := screen_position.distance_to(world_to_screen(endpoint))
			if pixel_distance < closest_pixels:
				closest_pixels = pixel_distance
				closest_world = endpoint
	return closest_world

func _build_contours() -> void:
	contour_segments.clear()
	var cell: float = FlightWorldScript.SIZE_KM / SAMPLE_GRID
	# Cache the terrain grid once. Marching every contour level over the old
	# uncached grid repeated the same height query hundreds of thousands of times.
	var heights := PackedFloat32Array()
	heights.resize((SAMPLE_GRID + 1) * (SAMPLE_GRID + 1))
	for grid_y in SAMPLE_GRID + 1:
		for grid_x in SAMPLE_GRID + 1:
			heights[grid_y * (SAMPLE_GRID + 1) + grid_x] = world.height_at(Vector2(grid_x * cell, grid_y * cell))
	for level in range(int(CONTOUR_STEP_M), 3250, int(CONTOUR_STEP_M)):
		for y in SAMPLE_GRID:
			for x in SAMPLE_GRID:
				var p0 := Vector2(x * cell, y * cell)
				var p1 := Vector2((x + 1) * cell, y * cell)
				var p2 := Vector2((x + 1) * cell, (y + 1) * cell)
				var p3 := Vector2(x * cell, (y + 1) * cell)
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

func _add_crossing(points: Array[Vector2], a: Vector2, b: Vector2, ha: float, hb: float, level: float) -> void:
	if (ha < level and hb >= level) or (hb < level and ha >= level):
		points.append(a.lerp(b, inverse_lerp(ha, hb, level)))
