extends Control

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")

const MAP_MARGIN := 14.0
const PANEL_HEIGHT := 246.0
const CONTOUR_STEP_M := 250.0
const SAMPLE_GRID := 48
const INSTRUMENT_RADIUS := 50.0
const INSTRUMENT_GAP := 14.0

var world
var flight
var selected_beacons := [0, 1]
var map_zoom := 1.0
var map_center := Vector2(50, 50)
var contour_segments: Array[Dictionary] = []
var measurement_lines: Array[Dictionary] = []
var pending_measure: Variant = null
var dragging_map := false
var dragging_yoke := false
var dragging_throttle := false
var last_mouse := Vector2.ZERO
var status_timer := 0.0
var clock_seconds := 12.0 * 60.0 * 60.0

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	regenerate_world()
	set_process(true)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q and event.ctrl_pressed:
			get_tree().quit()
			get_viewport().set_input_as_handled()

func regenerate_world() -> void:
	world = FlightWorldScript.new()
	flight = FlightModelScript.new(world)
	map_center = Vector2(50, 50)
	map_zoom = 1.0
	measurement_lines.clear()
	pending_measure = null
	clock_seconds = 12.0 * 60.0 * 60.0
	_build_contours()
	queue_redraw()

func _process(delta: float) -> void:
	clock_seconds = fmod(clock_seconds + delta, 24.0 * 60.0 * 60.0)
	var keyboard_yoke := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if not dragging_yoke:
		if keyboard_yoke.length() > 0.05:
			flight.yoke = keyboard_yoke.limit_length(1.0)
		else:
			flight.yoke = flight.yoke.move_toward(Vector2.ZERO, delta * 1.8)
	if Input.is_key_pressed(KEY_W):
		flight.throttle = min(1.0, flight.throttle + delta * 0.35)
	if Input.is_key_pressed(KEY_S):
		flight.throttle = max(0.0, flight.throttle - delta * 0.35)
	flight.update(delta)
	status_timer += delta
	queue_redraw()

func map_rect() -> Rect2:
	return Rect2(MAP_MARGIN, MAP_MARGIN, size.x - MAP_MARGIN * 2.0, max(300.0, size.y - PANEL_HEIGHT - MAP_MARGIN * 2.0))

func panel_rect() -> Rect2:
	var m := map_rect()
	return Rect2(MAP_MARGIN, m.end.y + 8.0, size.x - MAP_MARGIN * 2.0, size.y - m.end.y - 16.0)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10171b"))
	_draw_map()
	_draw_panel()

func _draw_map() -> void:
	var rect := map_rect()
	draw_rect(rect, Color("d7d0ad"), true)
	draw_rect(rect, Color("6d6751"), false, 2.0)
	# 10 km coordinate grid.
	for k in range(0, 101, 10):
		var a := world_to_screen(Vector2(k, 0))
		var b := world_to_screen(Vector2(k, 100))
		draw_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
		a = world_to_screen(Vector2(0, k))
		b = world_to_screen(Vector2(100, k))
		draw_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
	for segment in contour_segments:
		var level: float = segment.level
		var color := Color("806f4b") if int(level) % 500 != 0 else Color("5c4b31")
		var width := 1.0 if int(level) % 500 != 0 else 1.7
		draw_line(world_to_screen(segment.a), world_to_screen(segment.b), color, width, true)
	_draw_contour_labels(rect)
	for airport in world.airports:
		_draw_airport(airport)
	for beacon in world.beacons:
		_draw_beacon(beacon)
	for line in measurement_lines:
		_draw_measurement(line.a, line.b)
	if pending_measure != null:
		_draw_measurement(pending_measure, screen_to_world(get_local_mouse_position()), Color(0.1, 0.25, 0.7, 0.55))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), "НАВИГАЦИОННАЯ КАРТА • положение самолёта не отображается", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("35372e"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 40), "Изолинии: 250 м (жирные: 500 м)  •  Shift+ЛКМ: линия  •  ПКМ: стереть  •  колесо: масштаб  •  ЛКМ: двигать", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var scale_km := 10.0
	var scale_px := scale_km * pixels_per_km()
	var scale_start := rect.end - Vector2(scale_px + 18, 18)
	draw_line(scale_start, scale_start + Vector2(scale_px, 0), Color("25271f"), 3)
	draw_string(ThemeDB.fallback_font, scale_start - Vector2(0, 6), "10 км", HORIZONTAL_ALIGNMENT_CENTER, scale_px, 12, Color("25271f"))

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
		draw_rect(background, Color("d7d0ad"), true)
		draw_string(ThemeDB.fallback_font, midpoint + Vector2(-text_size.x * 0.5, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("55462f"))
		positions.append(midpoint)

func _draw_airport(airport: Dictionary) -> void:
	var center := world_to_screen(airport.position)
	var vector: Vector2 = world.heading_vector(airport.heading) * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var a := world_to_screen(airport.position - vector)
	var b := world_to_screen(airport.position + vector)
	draw_line(a, b, Color("222722"), max(4.0, pixels_per_km() * 0.12), true)
	draw_line(a, b, Color("f0ead2"), 1.0, true)
	draw_circle(a, 3.0, Color("20241f"))
	draw_circle(b, 3.0, Color("20241f"))
	draw_string(ThemeDB.fallback_font, center + Vector2(7, -7), "%s  %03d°" % [airport.name, int(airport.heading)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("20241f"))

func _draw_beacon(beacon: Dictionary) -> void:
	var p := world_to_screen(beacon.position)
	var radius := 5.0
	var points := PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, radius), p + Vector2(-radius, radius)])
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color("972d25"), 2.0)
	draw_string(ThemeDB.fallback_font, p + Vector2(7, 12), "%s %.0f" % [beacon.name, beacon.frequency], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("76231d"))

func _draw_measurement(a_world: Vector2, b_world: Vector2, color := Color("254d9a")) -> void:
	var a := world_to_screen(a_world)
	var b := world_to_screen(b_world)
	draw_dashed_line(a, b, color, 2.0, 7.0)
	draw_circle(a, 3, color)
	draw_circle(b, 3, color)
	var distance := a_world.distance_to(b_world)
	var bearing: float = world.vector_heading(b_world - a_world)
	var label := "%.1f км  %03d°" % [distance, int(round(bearing)) % 360]
	draw_string(ThemeDB.fallback_font, (a + b) * 0.5 + Vector2(5, -5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

func _draw_panel() -> void:
	var rect := panel_rect()
	draw_rect(rect, Color("1d282d"), true)
	draw_rect(rect, Color("536067"), false, 2)
	var y := rect.position.y + 12.0
	var gauge_y := y + 96.0
	_draw_round_gauge(_instrument_center(0, gauge_y), INSTRUMENT_RADIUS, "СКОРОСТЬ", "%.0f" % flight.speed_kmh, "км/ч", flight.speed_kmh / 200.0)
	_draw_round_gauge(_instrument_center(1, gauge_y), INSTRUMENT_RADIUS, "ВЫСОТА", "%.0f" % flight.altitude_m, "м", flight.altitude_m / 5000.0)
	_draw_variometer(_instrument_center(2, gauge_y), INSTRUMENT_RADIUS)
	_draw_compass(_instrument_center(3, gauge_y), INSTRUMENT_RADIUS)
	_draw_horizon(_instrument_center(4, gauge_y), INSTRUMENT_RADIUS)
	_draw_beacon_instrument(_instrument_center(5, gauge_y), INSTRUMENT_RADIUS, 0)
	_draw_beacon_instrument(_instrument_center(6, gauge_y), INSTRUMENT_RADIUS, 1)
	_draw_clock(_instrument_center(7, gauge_y), INSTRUMENT_RADIUS)
	_draw_controls(rect)
	var state_color: Color = Color("65d48c") if flight.state == FlightModelScript.State.LANDED else (Color("ef645e") if flight.state == FlightModelScript.State.CRASHED else Color("e8d274"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, rect.size.y - 10), flight.message, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 330, 15, state_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 320, rect.size.y - 10), "W/S газ  •  стрелки штурвал  •  R новая карта", HORIZONTAL_ALIGNMENT_LEFT, 310, 12, Color("aebbc1"))

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

func _draw_beacon_instrument(center: Vector2, radius: float, instrument: int) -> void:
	var beacon: Dictionary = world.beacons[selected_beacons[instrument]]
	var delta: Vector2 = beacon.position - flight.position_km
	var absolute_bearing: float = world.vector_heading(delta)
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# North-up receiver: the arrow shows absolute map bearing, independent of heading.
	var needle_angle: float = deg_to_rad(absolute_bearing - 90.0)
	var needle_direction := Vector2(cos(needle_angle), sin(needle_angle))
	var needle_side := Vector2(-needle_direction.y, needle_direction.x)
	var needle_tip := center + needle_direction * (radius - 7.0)
	draw_line(center - needle_direction * 10.0, needle_tip, Color("73d6d0"), 1.5, true)
	draw_colored_polygon(PackedVector2Array([
		needle_tip,
		needle_tip - needle_direction * 8.0 + needle_side * 3.5,
		needle_tip - needle_direction * 8.0 - needle_side * 3.5,
	]), Color("73d6d0"))
	draw_circle(center, 2.5, Color("73d6d0"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ПРИЁМНИК %d" % (instrument + 1), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), "%s  %.0f кГц" % [beacon.name, beacon.frequency], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color.WHITE)
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 29), "%.1f км  %03d°" % [delta.length(), int(round(absolute_bearing))], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 11, Color("73d6d0"))

func _draw_controls(rect: Rect2) -> void:
	var throttle_rect := get_throttle_rect()
	draw_rect(throttle_rect, Color("0a0e10"), true)
	draw_rect(throttle_rect, Color("6f7f85"), false, 2)
	var handle_y: float = lerpf(throttle_rect.end.y - 8, throttle_rect.position.y + 8, flight.throttle)
	draw_rect(Rect2(throttle_rect.position.x - 5, handle_y - 5, throttle_rect.size.x + 10, 10), Color("e49a4f"), true)
	draw_string(ThemeDB.fallback_font, throttle_rect.position - Vector2(13, 7), "ГАЗ", HORIZONTAL_ALIGNMENT_CENTER, throttle_rect.size.x + 26, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, throttle_rect.end + Vector2(-12, 16), "%d%%" % int(flight.throttle * 100), HORIZONTAL_ALIGNMENT_CENTER, 48, 11, Color.WHITE)
	var yoke_rect := get_yoke_rect()
	draw_circle(yoke_rect.get_center(), yoke_rect.size.x * 0.5, Color("0a0e10"))
	draw_arc(yoke_rect.get_center(), yoke_rect.size.x * 0.5, 0, TAU, 48, Color("6f7f85"), 2)
	var knob: Vector2 = yoke_rect.get_center() + flight.yoke * yoke_rect.size.x * 0.38
	draw_line(yoke_rect.get_center(), knob, Color("89999f"), 3)
	draw_circle(knob, 10, Color("d9c15e"))
	draw_string(ThemeDB.fallback_font, yoke_rect.position - Vector2(0, 7), "ШТУРВАЛ", HORIZONTAL_ALIGNMENT_CENTER, yoke_rect.size.x, 11, Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - 194, 24), "ТОПЛИВО  %.1f / %.0f л" % [flight.fuel_l, flight.fuel_capacity_l], HORIZONTAL_ALIGNMENT_CENTER, 180, 13, Color("d7e2e3"))
	var fuel_rect := Rect2(rect.end.x - 194, rect.position.y + 31, 180, 10)
	draw_rect(fuel_rect, Color("0a0e10"), true)
	draw_rect(Rect2(fuel_rect.position, Vector2(fuel_rect.size.x * flight.fuel_l / flight.fuel_capacity_l, fuel_rect.size.y)), Color("5dbb87"), true)
	if flight.state == FlightModelScript.State.PARKED or flight.state == FlightModelScript.State.LANDED or flight.state == FlightModelScript.State.CRASHED:
		var button := get_action_button_rect()
		draw_rect(button, Color("334b55"), true)
		draw_rect(button, Color("82979f"), false, 1)
		var label := "ПОДГОТОВИТЬ К ВЫЛЕТУ" if flight.state != FlightModelScript.State.PARKED else "ЗАПРАВИТЬ И ВЫРОВНЯТЬ"
		draw_string(ThemeDB.fallback_font, button.position + Vector2(0, 21), label, HORIZONTAL_ALIGNMENT_CENTER, button.size.x, 12, Color.WHITE)

func get_throttle_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 290, rect.position.y + 62, 28, 112)

func get_yoke_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 242, rect.position.y + 62, 112, 112)

func get_action_button_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.end.x - 300, rect.position.y + 181, 286, 30)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			regenerate_world()
			accept_event()
		return
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
			if get_throttle_rect().has_point(event.position):
				dragging_throttle = true
				_update_throttle(event.position)
			elif get_yoke_rect().has_point(event.position):
				dragging_yoke = true
				_update_yoke(event.position)
			elif get_action_button_rect().has_point(event.position) and flight.state in [FlightModelScript.State.PARKED, FlightModelScript.State.LANDED, FlightModelScript.State.CRASHED]:
				var next_airport: int = flight.airport_index
				flight.prepare_at_airport(next_airport)
				flight.refuel()
			elif _beacon_receiver_hit(event.position, 0):
				selected_beacons[0] = (selected_beacons[0] + 1) % world.beacons.size()
			elif _beacon_receiver_hit(event.position, 1):
				selected_beacons[1] = (selected_beacons[1] + 1) % world.beacons.size()
			elif mrect.has_point(event.position):
				if event.shift_pressed:
					var point := screen_to_world(event.position)
					if pending_measure == null:
						pending_measure = point
					else:
						measurement_lines.append({"a": pending_measure, "b": point})
						pending_measure = null
				else:
					dragging_map = true
					last_mouse = event.position
		else:
			dragging_map = false
			dragging_yoke = false
			dragging_throttle = false
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mrect.has_point(event.position):
		_erase_nearest_measurement(event.position)
	queue_redraw()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if dragging_map:
		map_center -= event.relative / pixels_per_km()
		_clamp_map_center()
	if dragging_yoke:
		_update_yoke(event.position)
	if dragging_throttle:
		_update_throttle(event.position)

func _update_yoke(mouse: Vector2) -> void:
	var rect := get_yoke_rect()
	flight.yoke = ((mouse - rect.get_center()) / (rect.size.x * 0.38)).limit_length(1.0)

func _update_throttle(mouse: Vector2) -> void:
	var rect := get_throttle_rect()
	flight.throttle = clamp(inverse_lerp(rect.end.y - 8, rect.position.y + 8, mouse.y), 0.0, 1.0)

func _beacon_receiver_hit(point: Vector2, receiver: int) -> bool:
	var rect := panel_rect()
	var center := _instrument_center(5 + receiver, rect.position.y + 108.0)
	return point.distance_to(center) < INSTRUMENT_RADIUS

func _zoom_at(mouse: Vector2, factor: float) -> void:
	var before := screen_to_world(mouse)
	map_zoom = clamp(map_zoom * factor, 1.0, 5.0)
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
	else:
		pending_measure = null

func _build_contours() -> void:
	contour_segments.clear()
	var cell: float = FlightWorldScript.SIZE_KM / SAMPLE_GRID
	for level in range(int(CONTOUR_STEP_M), 3250, int(CONTOUR_STEP_M)):
		for y in SAMPLE_GRID:
			for x in SAMPLE_GRID:
				var p0 := Vector2(x * cell, y * cell)
				var p1 := Vector2((x + 1) * cell, y * cell)
				var p2 := Vector2((x + 1) * cell, (y + 1) * cell)
				var p3 := Vector2(x * cell, (y + 1) * cell)
				var points: Array[Vector2] = []
				_add_crossing(points, p0, p1, world.height_at(p0), world.height_at(p1), level)
				_add_crossing(points, p1, p2, world.height_at(p1), world.height_at(p2), level)
				_add_crossing(points, p2, p3, world.height_at(p2), world.height_at(p3), level)
				_add_crossing(points, p3, p0, world.height_at(p3), world.height_at(p0), level)
				if points.size() >= 2:
					contour_segments.append({"a": points[0], "b": points[1], "level": float(level)})
				if points.size() == 4:
					contour_segments.append({"a": points[2], "b": points[3], "level": float(level)})

func _add_crossing(points: Array[Vector2], a: Vector2, b: Vector2, ha: float, hb: float, level: float) -> void:
	if (ha < level and hb >= level) or (hb < level and ha >= level):
		points.append(a.lerp(b, inverse_lerp(ha, hb, level)))
