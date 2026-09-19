extends RefCounted
const UILayout = preload("res://scripts/ui_layout.gd")
const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode
## Cockpit instrument rendering and layout. All drawing uses the owning canvas.

const MAP_MARGIN = UILayout.MAP_MARGIN
const INSTRUMENT_RADIUS = UILayout.INSTRUMENT_RADIUS
const FlightModelScript = preload("res://scripts/flight_model.gd")
const WeatherRadarArt = preload("res://scripts/weather_radar_art.gd")
const INSTRUMENT_GAP = UILayout.INSTRUMENT_GAP
const AircraftArt = preload("res://scripts/aircraft_art.gd")
const TIME_SCALES = preload("res://scripts/simulation_session.gd").TIME_SCALES
const FlightWorldScript = preload("res://scripts/world.gd")
const USE_STYLIZED_YOKE := true
const UIButton = preload("res://scripts/ui_button.gd")
const ECONOMY_RANGE_REFRESH_MSEC := 1000
var host: Control
var _economy_cache_valid := false
var _economy_cache_signature := 0
var _economy_cache_next_refresh_msec := 0
var _cached_altitude_range := Vector2.ZERO
var _cached_speed_range := Vector2.ZERO


func _init(controller: Control) -> void:
	host = controller

func panel_rect() -> Rect2:
	var m = host.map_rect()
	return Rect2(MAP_MARGIN, m.end.y + 8.0, host.size.x - MAP_MARGIN * 2.0, host.size.y - m.end.y - 16.0)

func _draw_panel() -> void:
	var rect = panel_rect()
	host.draw_rect(rect, Color("1d282d"), true)
	host.draw_rect(rect, Color("536067"), false, 2)
	var y = rect.position.y + 12.0
	var gauge_y = y + 96.0
	var speed_center = _instrument_center(0, gauge_y)
	if host.flight.electrical_power:
		_draw_speedometer(speed_center, INSTRUMENT_RADIUS)
		if host.flight.wheel_brakes_applied:
			host.draw_string(ThemeDB.fallback_font, speed_center + Vector2(-INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 47), "ТОРМОЗ", HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2.0, 11, Color("ef645e"))
		_draw_altimeter(_instrument_center(1, gauge_y), INSTRUMENT_RADIUS)
		_draw_radio_altimeter(_instrument_center(1, gauge_y))
		_draw_variometer(_instrument_center(2, gauge_y), INSTRUMENT_RADIUS)
		_draw_compass(_instrument_center(3, gauge_y), INSTRUMENT_RADIUS)
		_draw_horizon(_instrument_center(4, gauge_y), INSTRUMENT_RADIUS)
		_draw_beacon_instrument(_instrument_center(5, gauge_y), INSTRUMENT_RADIUS, 0)
		_draw_beacon_instrument(_instrument_center(6, gauge_y), INSTRUMENT_RADIUS, 1)
		_draw_clock(_instrument_center(7, gauge_y), INSTRUMENT_RADIUS)
		_draw_fuel_instrument(_instrument_center(8, gauge_y), INSTRUMENT_RADIUS)
		_draw_ils()
		_draw_weather_radar()
	else:
		_draw_unpowered_instruments(gauge_y)
	_draw_controls(rect)
	host._draw_airframe_condition_indicator(host, rect.position + Vector2(10, 10), true)
	var status_text: String = "ПАУЗА" if host.simulation_paused else host.flight.message
	var state_color: Color = Color("e8d274") if host.simulation_paused else _flight_message_color()
	if not host.simulation_paused and host.flight.state == FlightModelScript.State.FLYING and host.flight.stalled:
		status_text = "СВАЛИВАНИЕ — ОТДАТЬ ШТУРВАЛ ОТ СЕБЯ"
		state_color = Color("ef645e")
	elif not host.simulation_paused and host.flight.stall_warning_active():
		status_text = "ПРЕДУПРЕЖДЕНИЕ: БОЛЬШОЙ УГОЛ АТАКИ"
		state_color = Color("e8d274")
	elif not host.simulation_paused and host.flight.state == FlightModelScript.State.FLYING and host.flight.vne_exceeded():
		status_text = "ПРЕВЫШЕНА VNE — УМЕНЬШИТЬ СКОРОСТЬ"
		state_color = Color("ef645e")
	elif not host.simulation_paused and host.flight.state == FlightModelScript.State.FLYING and host.flight.overspeed_warning_active():
		status_text = "ВЫСОКАЯ СКОРОСТЬ — ИЗБЕГАТЬ РЕЗКИХ МАНЁВРОВ"
		state_color = Color("e8d274")
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, rect.size.y - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 330, 15, state_color)
	host.draw_string(ThemeDB.fallback_font, Vector2(rect.end.x - 470, rect.end.y - 10), "W/S: газ  •  стрелки: штурвал  •  Esc: меню", HORIZONTAL_ALIGNMENT_RIGHT, 446, 12, Color("aebbc1"))

func _flight_message_color() -> Color:
	if host.flight.state == FlightModelScript.State.CRASHED or host.flight.message_is_error:
		return Color("ef645e")
	if host.flight.state == FlightModelScript.State.LANDED and host.flight.message.begins_with("Успешная посадка"):
		return Color("65d48c")
	return Color("e8d274")

func _draw_radio_altimeter(center: Vector2) -> void:
	var height_m: float = host.flight.radio_height_m()
	var label = "РВ %.0f м" % height_m if height_m >= 0.0 else "РВ —"
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 34), label, HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2.0, 11, Color("73d6d0"))

func _draw_unpowered_instruments(gauge_y: float) -> void:
	# Pitot/static instruments and the independent clock remain available.
	_draw_speedometer(_instrument_center(0,gauge_y),INSTRUMENT_RADIUS)
	_draw_altimeter(_instrument_center(1,gauge_y),INSTRUMENT_RADIUS)
	_draw_variometer(_instrument_center(2,gauge_y),INSTRUMENT_RADIUS)
	var titles = ["СКОРОСТЬ", "ВЫСОТА", "ВАРИОМЕТР", "КОМПАС", "АВИАГОРИЗОНТ", "ПРИЁМНИК 1", "ПРИЁМНИК 2", "ЧАСЫ", "ТОПЛИВО"]
	for index in range(3,titles.size()):
		if index == 7:
			_draw_clock(_instrument_center(index, gauge_y), INSTRUMENT_RADIUS)
			continue
		var center = _instrument_center(index, gauge_y)
		host.draw_circle(center, INSTRUMENT_RADIUS, Color("0a0e10"))
		host.draw_arc(center, INSTRUMENT_RADIUS - 2, 0, TAU, 48, Color("7d8b91"), 2)
		host.draw_string(ThemeDB.fallback_font, center - Vector2(INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 10.0), titles[index], HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2, 11, Color("b8c5c8"))
	_draw_unpowered_display(get_ils_rect(), "ILS")
	var radar_rect = get_weather_radar_rect()
	if radar_rect.size.x >= 150.0:
		if host.large_weather_radar:
			WeatherRadarArt.draw_map_button(host,radar_rect)
		else:
			_draw_unpowered_display(radar_rect, "МЕТЕОРАДАР [B]")

func _draw_unpowered_display(rect: Rect2, title: String) -> void:
	host.draw_rect(rect, Color("0a0e10"), true)
	host.draw_rect(rect, Color("6f7f85"), false, 1.5)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 12), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 10, Color("b8c5c8"))

func _draw_weather_radar() -> void:
	var rect = get_weather_radar_rect()
	if rect.size.x < 150.0:
		return
	if host.large_weather_radar:
		WeatherRadarArt.draw_map_button(host,rect)
		return
	host.draw_rect(rect, Color("071012"), true)
	host.draw_rect(rect, Color("6f7f85"), false, 1.5)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 12), "МЕТЕОРАДАР 30 км [B]", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 9, Color("b8c5c8"))
	var center = rect.position + Vector2(37, 41)
	var radius = 23.0
	host.draw_arc(center, radius, 0, TAU, 40, Color("557176"), 1.0)
	host.draw_arc(center, radius * 0.5, 0, TAU, 32, Color(0.35, 0.48, 0.50, 0.55), 1.0)
	host.draw_line(center, center + Vector2(0, -radius), Color("8ca1a4"), 1.0)
	host.draw_circle(center, 2.0, Color("d7c65c"))
	WeatherRadarArt.draw_echoes(host,host.world,host.flight,center,radius)
	for line in host.radar_measurement_lines:
		host._draw_radar_measurement(host, line.a, line.b, Color("e8d274"), center, radius)
	var info_x = rect.position.x + 68.0
	var danger_color = Color("ef645e") if host.flight.storm_intensity > 0.65 else Color("e8d274")
	if host.flight.storm_intensity > 0.05:
		host.draw_string(ThemeDB.fallback_font, Vector2(info_x, rect.position.y + 42), "ТУРБУЛЕНТНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - info_x - 4, 9, danger_color)

func _instrument_center(index: int, gauge_y: float) -> Vector2:
	var step = INSTRUMENT_RADIUS * 2.0 + INSTRUMENT_GAP
	return Vector2(panel_rect().position.x + INSTRUMENT_RADIUS + 5.0 + index * step, gauge_y)

func _draw_speedometer(center: Vector2, radius: float) -> void:
	var start_angle = -PI * 0.75
	var end_angle = PI * 0.75
	var speed_to_angle = func(value: float) -> float:
		return lerpf(start_angle, end_angle, clampf(value / 300.0, 0.0, 1.0))
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	host.draw_arc(center, radius - 5, speed_to_angle.call(FlightModelScript.VNO_KMH), speed_to_angle.call(FlightModelScript.VNE_KMH), 10, Color("e8d274"), 3.0)
	if host.flight.state == FlightModelScript.State.FLYING:
		var economy_range := optimal_speed_range()
		host.draw_arc(center, radius - 5, speed_to_angle.call(economy_range.x), speed_to_angle.call(economy_range.y), 10, Color("63b9d1"), 4.5)
	var red_angle: float = speed_to_angle.call(FlightModelScript.VNE_KMH)
	var red_outer = center + Vector2(cos(red_angle), sin(red_angle)) * (radius - 4)
	var red_inner = center + Vector2(cos(red_angle), sin(red_angle)) * (radius - 14)
	host.draw_line(red_inner, red_outer, Color("ef645e"), 3.0)
	var rotation_angle: float = speed_to_angle.call(FlightModelScript.RECOMMENDED_ROTATION_SPEED_KMH)
	var rotation_direction = Vector2(cos(rotation_angle), sin(rotation_angle))
	host.draw_line(center + rotation_direction * (radius - 16), center + rotation_direction * (radius - 4), Color("73d6d0"), 2.5)
	var rotation_label_position = center + rotation_direction * (radius - 25) - Vector2(9.0, -3.0)
	host.draw_string(ThemeDB.fallback_font, rotation_label_position, "VR", HORIZONTAL_ALIGNMENT_CENTER, 18.0, 8, Color("73d6d0"))
	# With the current simplified climb polar, best angle and best rate of climb
	# coincide at about 130 km/h. Keep one honest combined mark until the flight
	# model has distinct Vx and Vy optima.
	var climb_angle: float = speed_to_angle.call(FlightModelScript.VX_KMH)
	var climb_direction = Vector2(cos(climb_angle), sin(climb_angle))
	host.draw_line(center + climb_direction * (radius - 16), center + climb_direction * (radius - 4), Color("65d48c"), 2.5)
	var climb_label_position = center + climb_direction * (radius - 27) - Vector2(15.0, -3.0)
	host.draw_string(ThemeDB.fallback_font, climb_label_position, "VX/VY", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 7, Color("65d48c"))
	_draw_tick_scale(center, radius, 0.0, 300.0, 25.0, 50.0)
	var needle_angle: float = speed_to_angle.call(host.flight.speed_kmh)
	host.draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("ed775f"), 2)
	host.draw_circle(center, 3, Color("d8dfe0"))
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "СКОРОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	var value_color = Color("ef645e") if host.flight.speed_kmh > FlightModelScript.VNE_KMH else (Color("e8d274") if host.flight.speed_kmh > FlightModelScript.VNO_KMH else Color.WHITE)
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%.0f км/ч" % host.flight.speed_kmh, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, value_color)
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 7, radius + 32), "По земле %.0f км/ч" % host.flight.ground_speed_kmh(), HORIZONTAL_ALIGNMENT_CENTER, radius * 2 + 14, 10, Color("73d6d0"))

func _draw_altimeter(center: Vector2, radius: float) -> void:
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# A wind-optimal altitude only has meaning after takeoff, when there is an
	# actual ground track. On the apron the broad near-equal range otherwise
	# makes almost the entire scale look recommended.
	if host.flight.state == FlightModelScript.State.FLYING:
		var economy_range := optimal_altitude_range()
		var economy_start := _scale_angle(economy_range.x, 0.0, FlightModelScript.ABSOLUTE_CEILING_M)
		var economy_end := _scale_angle(economy_range.y, 0.0, FlightModelScript.ABSOLUTE_CEILING_M)
		host.draw_arc(center, radius - 5, economy_start, economy_end, 12, Color("63b9d1"), 4.5)
	_draw_tick_scale(center, radius, 0.0, FlightModelScript.ABSOLUTE_CEILING_M, 50.0, 100.0)
	var needle_angle := _scale_angle(host.flight.altitude_m, 0.0, FlightModelScript.ABSOLUTE_CEILING_M)
	host.draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("ed775f"), 2)
	host.draw_circle(center, 3, Color("d8dfe0"))
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ВЫСОТА", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%.0f м" % host.flight.altitude_m, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func optimal_altitude_range(force_refresh := false) -> Vector2:
	_refresh_economy_range_cache(force_refresh)
	return _cached_altitude_range

func _calculate_optimal_altitude_range() -> Vector2:
	const STEP_M := 10.0
	var track_deg := _economy_track_deg()
	var track_forward: Vector2 = host.world.heading_vector(track_deg)
	var track_right := Vector2(track_forward.y, -track_forward.x)
	var scores: PackedFloat32Array = []
	var best_score := -INF
	var best_index := 0
	var sample_count := floori(FlightModelScript.ABSOLUTE_CEILING_M / STEP_M) + 1
	for sample_index in sample_count:
		var altitude := sample_index * STEP_M
		var score := -INF
		for airspeed in range(ceili(FlightModelScript.NOMINAL_STALL_SPEED_KMH + 15.0), floori(FlightModelScript.VNO_KMH) + 1):
			score = maxf(score, _economy_range_score(airspeed, altitude, track_forward, track_right))
		scores.append(score)
		if score > best_score:
			best_score = score
			best_index = sample_index
	return _near_optimal_range(scores, best_index, best_score, 0.0, STEP_M)

func optimal_speed_range(force_refresh := false) -> Vector2:
	_refresh_economy_range_cache(force_refresh)
	return _cached_speed_range

func _calculate_optimal_speed_range() -> Vector2:
	const STEP_KMH := 1.0
	var minimum_speed := ceilf(FlightModelScript.NOMINAL_STALL_SPEED_KMH + 15.0)
	var track_deg := _economy_track_deg()
	var track_forward: Vector2 = host.world.heading_vector(track_deg)
	var track_right := Vector2(track_forward.y, -track_forward.x)
	var scores: PackedFloat32Array = []
	var best_score := -INF
	var best_index := 0
	var sample_count := floori((FlightModelScript.VNO_KMH - minimum_speed) / STEP_KMH) + 1
	for sample_index in sample_count:
		var airspeed := minimum_speed + sample_index * STEP_KMH
		var score := _economy_range_score(airspeed, host.flight.altitude_m, track_forward, track_right)
		scores.append(score)
		if score > best_score:
			best_score = score
			best_index = sample_index
	return _near_optimal_range(scores, best_index, best_score, minimum_speed, STEP_KMH)

func _refresh_economy_range_cache(force_refresh := false) -> void:
	# This is a cruise-planning cue, not a primary flight instrument. Updating it
	# once per real second keeps turns, climbs and accelerated simulation from
	# repeatedly running the two-dimensional search during rendering.
	var now_msec := Time.get_ticks_msec()
	if _economy_cache_valid and not force_refresh and now_msec < _economy_cache_next_refresh_msec:
		return
	_economy_cache_next_refresh_msec = now_msec + ECONOMY_RANGE_REFRESH_MSEC
	var signature := hash([
		roundi(host.flight.heading_deg / 2.0),
		roundi(host.flight.speed_kmh / 2.0),
		roundi(host.flight.altitude_m / 5.0),
		host.world.wind_layers,
	])
	if _economy_cache_valid and not force_refresh and signature == _economy_cache_signature:
		return
	_economy_cache_valid = true
	_economy_cache_signature = signature
	_cached_speed_range = _calculate_optimal_speed_range()
	_cached_altitude_range = _calculate_optimal_altitude_range()

func _economy_track_deg() -> float:
	# Use forecast wind rather than the momentary storm gust so both gauges give
	# a stable recommendation during turbulence.
	var airspeed := maxf(host.flight.speed_kmh, FlightModelScript.NOMINAL_STALL_SPEED_KMH + 15.0)
	var ground_vector: Vector2 = host.world.heading_vector(host.flight.heading_deg) * airspeed + host.world.wind_at(host.flight.altitude_m)
	return host.world.vector_heading(ground_vector) if ground_vector.length_squared() > 0.0001 else host.flight.heading_deg

func _economy_range_score(airspeed: float, altitude: float, track_forward: Vector2, track_right: Vector2) -> float:
	var power_factor := FlightModelScript.altitude_power_factor_at(altitude)
	var required_throttle := (airspeed - 35.0) / (185.0 * power_factor)
	if required_throttle < 0.0 or required_throttle > 1.0:
		return -INF
	var wind: Vector2 = host.world.wind_at(altitude)
	var crosswind := wind.dot(track_right)
	if absf(crosswind) >= airspeed:
		return -INF
	var along_air := sqrt(airspeed * airspeed - crosswind * crosswind)
	var ground_speed := along_air + wind.dot(track_forward)
	var fuel_flow := FlightModelScript.sea_level_fuel_flow_lpm(required_throttle) * FlightModelScript.altitude_fuel_factor_at(altitude)
	return ground_speed / fuel_flow if ground_speed > 0.0 and fuel_flow > 0.0 else -INF

func _near_optimal_range(scores: PackedFloat32Array, best_index: int, best_score: float, minimum: float, step: float) -> Vector2:
	const NEAR_OPTIMAL_RATIO := 0.95
	var first := best_index
	var last := best_index
	while first > 0 and scores[first - 1] >= best_score * NEAR_OPTIMAL_RATIO:
		first -= 1
	while last + 1 < scores.size() and scores[last + 1] >= best_score * NEAR_OPTIMAL_RATIO:
		last += 1
	return Vector2(minimum + first * step, minimum + last * step)

func _scale_angle(value: float, minimum: float, maximum: float) -> float:
	return lerpf(-PI * 0.75, PI * 0.75, clampf(inverse_lerp(minimum, maximum, value), 0.0, 1.0))

func _draw_tick_scale(center: Vector2, radius: float, minimum: float, maximum: float, minor_step: float, major_step: float) -> void:
	var tick_count := roundi((maximum - minimum) / minor_step)
	for tick_index in tick_count + 1:
		var tick_value := minimum + tick_index * minor_step
		var angle := _scale_angle(tick_value, minimum, maximum)
		var major := is_equal_approx(tick_value / major_step, roundf(tick_value / major_step))
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 7)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - (15 if major else 11))
		host.draw_line(inner, outer, Color("d2dde0"), 1.4 if major else 1.0)

func _draw_compass(center: Vector2, radius: float) -> void:
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	for degrees in range(0, 360, 30):
		# The compass rose is fixed: north is always at the top.
		var angle = deg_to_rad(degrees - 90)
		var direction = Vector2(cos(angle), sin(angle))
		var cardinal := degrees % 90 == 0
		var outer = center + direction * (radius - 7)
		var inner = center + direction * (radius - (16 if cardinal else 11))
		host.draw_line(inner, outer, Color("d5ddde"), 1.5 if cardinal else 1.0)
		if cardinal:
			var p = center + direction * (radius - 25)
			var mark = "N" if degrees == 0 else ("E" if degrees == 90 else ("S" if degrees == 180 else "W"))
			host.draw_string(ThemeDB.fallback_font, p - Vector2(11, -4), mark, HORIZONTAL_ALIGNMENT_CENTER, 22, 10, Color("d5ddde"))
	var heading_angle: float = deg_to_rad(host.flight.heading_deg - 90.0)
	var heading_vector = Vector2(cos(heading_angle), sin(heading_angle))
	var arrow_tip = center + heading_vector * (radius - 8.0)
	var arrow_side = Vector2(-heading_vector.y, heading_vector.x)
	host.draw_line(center - heading_vector * 10.0, arrow_tip, Color("e5b752"), 3.0, true)
	host.draw_colored_polygon(PackedVector2Array([
		arrow_tip,
		arrow_tip - heading_vector * 12.0 + arrow_side * 6.0,
		arrow_tip - heading_vector * 12.0 - arrow_side * 6.0,
	]), Color("e5b752"))
	host.draw_circle(center, 3.0, Color("e5b752"))
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "КОМПАС", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%03d°" % int(round(host.flight.heading_deg)), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func _draw_variometer(center: Vector2, radius: float) -> void:
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# Шкала симметрична: короткое деление 1 м/с, длинное через 5 м/с.
	_draw_tick_scale(center, radius, -10.0, 10.0, 1.0, 5.0)
	var shown_speed: float = clampf(host.flight.vertical_speed_mps, -10.0, 10.0)
	var needle_angle: float = lerpf(-PI * 0.75, PI * 0.75, inverse_lerp(-10.0, 10.0, shown_speed))
	host.draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("79cfa4"), 2)
	host.draw_circle(center, 3, Color("d8dfe0"))
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ВАРИОМЕТР", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%+.1f м/с" % host.flight.vertical_speed_mps, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, Color.WHITE)

func _draw_clock(center: Vector2, radius: float, beige: bool = false) -> void:
	var whole_seconds = int(host.clock_seconds)
	var hours: int = whole_seconds / 3600
	var minutes: int = (whole_seconds % 3600) / 60
	var seconds: int = whole_seconds % 60
	var ink = AircraftArt.INK if beige else Color("edf2f2")
	host.draw_circle(center, radius, AircraftArt.PAPER if beige else Color("0a0e10"))
	host.draw_arc(center, radius - 1, 0, TAU, 40, AircraftArt.INK if beige else Color("7d8b91"), 2)
	for hour_mark in 12:
		var mark_angle = deg_to_rad(hour_mark * 30.0 - 90.0)
		var outer = center + Vector2(cos(mark_angle), sin(mark_angle)) * (radius - 6.0)
		var inner_radius = radius - (15.0 if hour_mark % 3 == 0 else 11.0)
		var inner = center + Vector2(cos(mark_angle), sin(mark_angle)) * inner_radius
		host.draw_line(inner, outer, AircraftArt.INK if beige else Color("d2dde0"), 1.5)
	var hour_angle = deg_to_rad(fmod(hours, 12) * 30.0 + minutes * 0.5 - 90.0)
	var minute_angle = deg_to_rad(minutes * 6.0 + seconds * 0.1 - 90.0)
	var second_angle = deg_to_rad(seconds * 6.0 - 90.0)
	host.draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * (radius * 0.48), ink, 3.0, true)
	host.draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * (radius * 0.68), ink, 2.0, true)
	host.draw_line(center, center + Vector2(cos(second_angle), sin(second_angle)) * (radius * 0.73), AircraftArt.LIGHT if beige else Color("ed775f"), 1.0, true)
	host.draw_circle(center, 2.5, ink)
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ЧАСЫ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, AircraftArt.INK if beige else Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 14), "%02d:%02d:%02d" % [hours, minutes, seconds], HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, AircraftArt.INK if beige else Color.WHITE)
	if beige:
		return
	var trip_whole_seconds = int(host.trip_elapsed_seconds)
	var trip_minutes: int = trip_whole_seconds / 60
	var trip_seconds: int = trip_whole_seconds % 60
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 8.0, radius + 29), "ПУТЬ %.1f км • %02d:%02d" % [host.trip_air_distance_km, trip_minutes, trip_seconds], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 16.0, 10, Color("73d6d0"))
	var reset_button = get_trip_reset_button_rect()
	host.draw_rect(reset_button, Color("334b55"), true)
	host.draw_rect(reset_button, Color("82979f"), false, 1.0)
	host.draw_string(ThemeDB.fallback_font, reset_button.position + Vector2(0.0, 13.0), "СБРОС [T]", HORIZONTAL_ALIGNMENT_CENTER, reset_button.size.x, 8, Color.WHITE)

func _draw_time_controls(beige: bool = false) -> void:
	UIButton.draw(host, get_time_scale_button_rect(beige), "ВРЕМЯ %d× [⇧Z]" % roundi(TIME_SCALES[host.time_scale_index]), beige, 9)
	UIButton.draw(host, get_time_reset_button_rect(beige), "1× [Z]", beige, 9)

func _draw_fuel_instrument(center: Vector2, radius: float) -> void:
	var flow: float = host.flight.fuel_flow_lpm()
	var estimated_range: float = host.flight.estimated_range_km()
	var max_flow = 0.95
	var remaining_ratio: float = clampf(host.flight.fuel_l / host.flight.fuel_capacity_l, 0.0, 1.0)
	var flow_ratio: float = clampf(flow / max_flow, 0.0, 1.0)
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	host.draw_line(center + Vector2(0, -radius + 3), center + Vector2(0, radius - 3), Color("536067"), 1.0)
	for i in 6:
		var left_angle: float = lerpf(PI * 0.5, PI * 1.5, i / 5.0)
		var right_angle: float = lerpf(-PI * 0.5, PI * 0.5, i / 5.0)
		for angle in [left_angle, right_angle]:
			var outer = center + Vector2(cos(angle), sin(angle)) * (radius - 6)
			var inner = center + Vector2(cos(angle), sin(angle)) * (radius - 12)
			host.draw_line(inner, outer, Color("d2dde0"), 1)
	var left_needle_angle: float = lerpf(PI * 0.5, PI * 1.5, remaining_ratio)
	var right_needle_angle: float = lerpf(-PI * 0.5, PI * 0.5, flow_ratio)
	host.draw_line(center, center + Vector2(cos(left_needle_angle), sin(left_needle_angle)) * (radius - 15), Color("e6c75b"), 2.0, true)
	host.draw_line(center, center + Vector2(cos(right_needle_angle), sin(right_needle_angle)) * (radius - 15), Color("6fc78c"), 2.0, true)
	host.draw_circle(center, 3.0, Color("d8dfe0"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, 5), "ОСТ", HORIZONTAL_ALIGNMENT_CENTER, radius, 8, Color("e6c75b"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(0, 5), "РАСХ", HORIZONTAL_ALIGNMENT_CENTER, radius, 8, Color("6fc78c"))
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ТОПЛИВО", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), "Расход %.2f л/мин" % flow, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color("6fc78c"))
	# Keep the wide caption box centered on the gauge without clipping units.
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-90.0, radius + 29), "%.1f/%.0f л • запас %.0f км" % [host.flight.fuel_l, host.flight.fuel_capacity_l, estimated_range], HORIZONTAL_ALIGNMENT_CENTER, 180.0, 10, Color.WHITE)

func _draw_ils() -> void:
	var rect = get_ils_rect()
	var guidance: Dictionary = host.flight.landing_guidance(host.ils_airport_index, host.ils_signal_status.get("available", false))
	host.draw_rect(rect, Color("0a0e10"), true)
	host.draw_rect(rect, Color("6f7f85"), false, 1.5)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 12), host._ils_title(), HORIZONTAL_ALIGNMENT_LEFT, 200, 10, Color("b8c5c8"))
	var display = Rect2(rect.position + Vector2(7, 16), Vector2(82, 35))
	var center = display.get_center()
	var airport_cross_color = Color("66878a")
	host.draw_line(Vector2(display.position.x, center.y), Vector2(display.end.x, center.y), airport_cross_color, 1.5)
	host.draw_line(Vector2(center.x, display.position.y), Vector2(center.x, display.end.y), airport_cross_color, 1.5)
	host.draw_circle(center, 2.5, airport_cross_color)
	if not guidance.signal_available:
		host.draw_line(display.position + Vector2(8, 4), display.end - Vector2(8, 4), Color("c95d55"), 2.0)
		host.draw_line(Vector2(display.end.x - 8, display.position.y + 4), Vector2(display.position.x + 8, display.end.y - 4), Color("c95d55"), 2.0)
		host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 37), "НЕТ СИГНАЛА", HORIZONTAL_ALIGNMENT_LEFT, 104, 10, Color("c95d55"))
		return
	host.draw_line(rect.position + Vector2(207, 4), rect.position + Vector2(207, rect.size.y - 4), Color("536067"), 1.0)
	var desired_vs: float = guidance.desired_vertical_speed_mps
	var altitude_color = _ils_parameter_color(absf(guidance.glide_error), true)
	var vertical_speed_color = _ils_parameter_color(absf(host.flight.vertical_speed_mps - desired_vs) / 0.35, true)
	var course_error_color = _ils_parameter_color(absf(guidance.course_error_deg), true, 1.0, 5.0)
	var approach_speed_color = Color("65d48c")
	if host.flight.speed_kmh > 115.0:
		approach_speed_color = Color("ef645e")
	elif host.flight.speed_kmh > 100.0:
		approach_speed_color = Color("e8d274")
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 22), "H %.1f м" % host.flight.altitude_m, HORIZONTAL_ALIGNMENT_LEFT, 76, 12, altitude_color)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(292, 22), "VS %+.2f м/с" % host.flight.vertical_speed_mps, HORIZONTAL_ALIGNMENT_LEFT, 105, 12, vertical_speed_color)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(399, 22), "V %.1f км/ч" % host.flight.speed_kmh, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 407, 11, approach_speed_color)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 42), "ОТКЛ. ПУТИ %+.1f°" % guidance.course_error_deg, HORIZONTAL_ALIGNMENT_LEFT, 132, 12, course_error_color)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(350, 42), "ДО ВПП %.2f км" % guidance.actual_distance_to_threshold_km, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 358, 12, Color.WHITE)
	if host.ils_touchdown_prediction.valid:
		var touchdown_distance: float = host.ils_touchdown_prediction.distance_from_threshold_km
		var touchdown_color = Color("65d48c") if touchdown_distance >= 0.0 and touchdown_distance <= FlightWorldScript.RUNWAY_LENGTH_KM else Color("ef645e")
		host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 61), "КАСАНИЕ %+.2f км ОТ ТОРЦА" % touchdown_distance, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 224, 12, touchdown_color)
	else:
		host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 61), "КАСАНИЕ — НЕТ СНИЖЕНИЯ", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 224, 12, Color("e8d274"))
	# Runway edges live on the airport's fixed horizontal axis. Far from the
	# airport they are close together; towards the threshold they spread apart.
	var runway_half_width_km = FlightWorldScript.RUNWAY_WIDTH_KM * 0.5
	var runway_edge_error: float = runway_half_width_km / guidance.localizer_tolerance_km
	var runway_edge_spacing: float = maxf(2.0, runway_edge_error * display.size.x * 0.30)
	for side in [-1.0, 1.0]:
		var edge_x: float = center.x + side * runway_edge_spacing
		host.draw_line(Vector2(edge_x, center.y - 5.0), Vector2(edge_x, center.y + 5.0), Color("a9c0c1"), 2.0)
	# The fixed cross is the airport. The moving cross is the aircraft: right of
	# center means right of the localizer, above center means above glide path.
	# runway_coordinates() uses a cross-runway axis whose positive side appears
	# left to the pilot on the supported approach. Invert it for the aircraft
	# symbol: if the moving line is left of the airport, steering right must move
	# it back towards the fixed centre, and vice versa.
	var localizer_x: float = center.x - clampf(guidance.localizer_error, -1.4, 1.4) * display.size.x * 0.30
	var glide_y: float = center.y - clampf(guidance.glide_error, -1.4, 1.4) * display.size.y * 0.30
	var localizer_severity: float = absf(guidance.localizer_error)
	var glide_severity: float = absf(guidance.glide_error)
	var localizer_line_color = _ils_parameter_color(localizer_severity, true)
	var glide_line_color = _ils_parameter_color(glide_severity, true)
	var aircraft_center_color = _ils_parameter_color(maxf(localizer_severity, glide_severity), true)
	host.draw_line(Vector2(localizer_x, display.position.y + 3), Vector2(localizer_x, display.end.y - 3), localizer_line_color, 2.0)
	host.draw_line(Vector2(display.position.x + 3, glide_y), Vector2(display.end.x - 3, glide_y), glide_line_color, 2.0)
	host.draw_circle(Vector2(localizer_x, glide_y), 2.5, aircraft_center_color)
	var localizer_color = Color("65d48c") if guidance.in_localizer else Color("e8d274")
	var glide_color = Color("65d48c") if guidance.in_glide else Color("e8d274")
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 30), "СТВОР" if guidance.in_localizer else "ВНЕ СТВОРА", HORIZONTAL_ALIGNMENT_LEFT, 104, 10, localizer_color)
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(96, 44), "ГЛИСС" if guidance.in_glide else ("ВЫСОКО" if guidance.glide_error > 0 else "НИЗКО"), HORIZONTAL_ALIGNMENT_LEFT, 104, 10, glide_color)

func _ils_parameter_color(error: float, signal_available: bool, green_limit: float = 1.0, yellow_limit: float = 2.0) -> Color:
	if not signal_available or error > yellow_limit:
		return Color("ef645e")
	if error > green_limit:
		return Color("e8d274")
	return Color("65d48c")

func _draw_horizon(center: Vector2, radius: float) -> void:
	host.draw_circle(center, radius, Color("0a0e10"))
	var horizon_offset: float = host.flight.pitch_deg * 1.9
	var angle: float = deg_to_rad(-host.flight.bank_deg)
	var direction: Vector2 = Vector2(cos(angle), sin(angle))
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var horizon_center: Vector2 = center + normal * horizon_offset
	host.draw_line(horizon_center - direction * 52, horizon_center + direction * 52, Color("d9e3e4"), 3)
	host.draw_line(center - Vector2(25, 0), center - Vector2(7, 0), Color("e7c25f"), 3)
	host.draw_line(center + Vector2(7, 0), center + Vector2(25, 0), Color("e7c25f"), 3)
	host.draw_circle(center, 3, Color("e7c25f"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "АВИАГОРИЗОНТ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	var aoa_color = Color("65d48c")
	if host.flight.stalled or host.flight.angle_of_attack_deg >= FlightModelScript.STALL_AOA_DEG:
		aoa_color = Color("ef645e")
	elif host.flight.angle_of_attack_deg >= FlightModelScript.STALL_WARNING_AOA_DEG:
		aoa_color = Color("e8d274")
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "УА %+.1f°" % host.flight.angle_of_attack_deg, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 12, aoa_color)

func _draw_beacon_instrument(center: Vector2, radius: float, instrument: int) -> void:
	var signal_status: Dictionary = host.receiver_signal_status[instrument]
	var beacon: Variant = signal_status.get("beacon", null)
	var signal_available: bool = signal_status.get("available", false)
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	if host.active_receiver == instrument:
		host.draw_arc(center, radius + 2, 0, TAU, 48, Color("73d6d0"), 1.5)
	# External tuning index: the complete circumference represents 0--999 kHz,
	# starting at the top and increasing clockwise.
	var frequency_angle = -PI * 0.5 + TAU * float(host.receiver_frequencies[instrument]) / 999.0
	var frequency_direction = Vector2(cos(frequency_angle), sin(frequency_angle))
	var frequency_side = Vector2(-frequency_direction.y, frequency_direction.x)
	var marker_tip = center + frequency_direction * (radius + 1.0)
	var marker_base = center + frequency_direction * (radius + 8.0)
	var marker_color = Color("73d6d0") if host.active_receiver == instrument else Color("d2dde0")
	host.draw_colored_polygon(PackedVector2Array([
		marker_tip,
		marker_base + frequency_side * 3.0,
		marker_base - frequency_side * 3.0,
	]), marker_color)
	# North-up receiver: the arrow shows absolute map bearing, independent of heading.
	if signal_available:
		var delta: Vector2 = beacon.position - host.flight.position_km
		var absolute_bearing: float = host.world.vector_heading(delta)
		var needle_angle: float = deg_to_rad(absolute_bearing - 90.0)
		var needle_direction = Vector2(cos(needle_angle), sin(needle_angle))
		var needle_side = Vector2(-needle_direction.y, needle_direction.x)
		var needle_tip = center + needle_direction * (radius - 7.0)
		host.draw_line(center - needle_direction * 10.0, needle_tip, Color("73d6d0"), 1.5, true)
		host.draw_colored_polygon(PackedVector2Array([
			needle_tip,
			needle_tip - needle_direction * 8.0 + needle_side * 3.5,
			needle_tip - needle_direction * 8.0 - needle_side * 3.5,
		]), Color("73d6d0"))
		host.draw_circle(center, 2.5, Color("73d6d0"))
	else:
		host.draw_line(center + Vector2(-12, -12), center + Vector2(12, 12), Color("c95d55"), 2.0)
		host.draw_line(center + Vector2(12, -12), center + Vector2(-12, 12), Color("c95d55"), 2.0)
	var title_color = Color("73d6d0") if host.active_receiver == instrument else Color("b8c5c8")
	host.draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ПРИЁМНИК %d" % (instrument + 1), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, title_color)
	var frequency_text = "%03d кГц" % int(host.receiver_frequencies[instrument])
	host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), frequency_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color.WHITE)
	if signal_available:
		var delta: Vector2 = beacon.position - host.flight.position_km
		var absolute_bearing: float = host.world.vector_heading(delta)
		var direct_course = int(round(absolute_bearing)) % 360
		var reverse_course = (direct_course + 180) % 360
		host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), "%.1f км  %03d°/%03d°" % [delta.length(), direct_course, reverse_course], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 10, Color("73d6d0"))
	else:
		host.draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), signal_status.get("reason", "НЕТ СИГНАЛА"), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 10, Color("c95d55"))

func _draw_controls(rect: Rect2) -> void:
	var throttle_rect = get_throttle_rect()
	host.draw_rect(throttle_rect, Color("0a0e10"), true)
	host.draw_rect(throttle_rect, Color("6f7f85"), false, 2)
	var handle_y: float = lerpf(throttle_rect.end.y - 8, throttle_rect.position.y + 8, host.flight.throttle)
	host.draw_rect(Rect2(throttle_rect.position.x - 5, handle_y - 5, throttle_rect.size.x + 10, 10), Color("e49a4f"), true)
	host.draw_string(ThemeDB.fallback_font, throttle_rect.position - Vector2(13, 7), "ГАЗ", HORIZONTAL_ALIGNMENT_CENTER, throttle_rect.size.x + 26, 11, Color("b8c5c8"))
	host.draw_string(ThemeDB.fallback_font, Vector2(throttle_rect.position.x - 56, handle_y + 5), "%d%%" % roundi(host.flight.throttle * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 44, 11, Color.WHITE)
	var yoke_rect = get_yoke_rect()
	if USE_STYLIZED_YOKE:
		_draw_stylized_yoke(yoke_rect)
	else:
		_draw_legacy_yoke(yoke_rect)
	host.draw_string(ThemeDB.fallback_font, yoke_rect.position - Vector2(0, 7), "ШТУРВАЛ", HORIZONTAL_ALIGNMENT_CENTER, yoke_rect.size.x, 11, Color("b8c5c8"))
	var center_button = get_center_yoke_button_rect()
	host.draw_rect(center_button, Color("334b55"), true)
	host.draw_rect(center_button, Color("82979f"), false, 1)
	host.draw_string(ThemeDB.fallback_font, center_button.position + Vector2(0, 17), "ЦЕНТР [C]", HORIZONTAL_ALIGNMENT_CENTER, center_button.size.x, 10, Color.WHITE)
	var cabin_button = get_cabin_button_rect()
	_draw_cockpit_action_button(cabin_button, "САЛОН [X]" if cabin_button.size.x >= 80.0 else "САЛОН")
	var power_button = get_power_button_rect()
	_draw_cockpit_action_button(power_button, "ВЫКЛЮЧИТЬ ПИТАНИЕ [P]" if host.flight.electrical_power else "ВКЛЮЧИТЬ ПИТАНИЕ [P]", Color("65d48c") if host.flight.electrical_power else Color("c95d55"))
	var engine_button = get_engine_button_rect()
	_draw_cockpit_action_button(engine_button, "ОСТАНОВИТЬ ДВИГАТЕЛЬ [M]" if host.flight.engine_running else "ЗАПУСТИТЬ ДВИГАТЕЛЬ [M]", Color("65d48c") if host.flight.engine_running else Color("c95d55"))
	var trajectory_button = get_trajectory_button_rect()
	var trajectory_enabled = host._can_toggle_final_trajectory()
	var trajectory_text: String
	if not trajectory_enabled:
		trajectory_text = "ТРАЕКТ.: НЕТ" if trajectory_button.size.x >= 80.0 else "ТР: НЕТ"
	elif host.final_trajectory_visible:
		trajectory_text = "ТРАЕКТ.: ВКЛ" if trajectory_button.size.x >= 80.0 else "ТР: ВКЛ"
	else:
		trajectory_text = "ТРАЕКТ.: ВЫКЛ" if trajectory_button.size.x >= 80.0 else "ТР: ВЫКЛ"
	_draw_cockpit_action_button(trajectory_button, trajectory_text, Color.TRANSPARENT, trajectory_enabled)
	var storms_button = get_weather_briefing_button_rect()
	var roomy_storms_button: bool = storms_button.size.x >= 80.0
	var storms_text: String = ("ГРОЗЫ: ВКЛ" if roomy_storms_button else "ГР: ВКЛ") if host.navigation_map.weather_briefing_visible else ("ГРОЗЫ: ВЫКЛ" if roomy_storms_button else "ГР: ВЫКЛ")
	_draw_cockpit_action_button(storms_button, storms_text)
	_draw_time_controls(false)

func _draw_cockpit_action_button(rect: Rect2, label: String, indicator: Color = Color.TRANSPARENT, enabled: bool = true) -> void:
	UIButton.draw(host, rect, label, false, 10, indicator, enabled)

func _draw_legacy_yoke(yoke_rect: Rect2) -> void:
	host.draw_circle(yoke_rect.get_center(), yoke_rect.size.x * 0.5, Color("0a0e10"))
	host.draw_arc(yoke_rect.get_center(), yoke_rect.size.x * 0.5, 0, TAU, 48, Color("6f7f85"), 2)
	var knob: Vector2 = yoke_rect.get_center() + host.flight.yoke * yoke_rect.size.x * 0.38
	host.draw_line(yoke_rect.get_center(), knob, Color("89999f"), 3)
	host.draw_circle(knob, 10, Color("d9c15e"))

func _draw_stylized_yoke(yoke_rect: Rect2) -> void:
	var center = yoke_rect.get_center()
	var radius = yoke_rect.size.x * 0.5
	host.draw_circle(center, radius, Color("0a0e10"))
	host.draw_arc(center, radius, 0, TAU, 48, Color("6f7f85"), 2)
	var rotation: float = deg_to_rad(host.flight.yoke.x * 28.0)
	var depth_scale: float = 1.0 + host.flight.yoke.y * 0.16
	host.draw_set_transform(center, rotation, Vector2.ONE * depth_scale)
	var silhouette = PackedVector2Array([
		Vector2(-34, -24), Vector2(-39, -7), Vector2(-35, 12),
		Vector2(-25, 25), Vector2(-10, 27), Vector2(0, 21),
		Vector2(10, 27), Vector2(25, 25), Vector2(35, 12),
		Vector2(39, -7), Vector2(34, -24),
	])
	host.draw_polyline(silhouette, Color("273238"), 13.0, true)
	host.draw_polyline(silhouette, Color("75838a"), 2.2, true)
	host.draw_line(Vector2(-34, -23), Vector2(-39, -7), Color("9aa7ac"), 3.0, true)
	host.draw_line(Vector2(34, -23), Vector2(39, -7), Color("9aa7ac"), 3.0, true)
	host.draw_rect(Rect2(-10, -5, 20, 34), Color("1b2428"), true)
	host.draw_rect(Rect2(-10, -5, 20, 34), Color("657278"), false, 1.5)
	host.draw_circle(Vector2(-34, -25), 8.0, Color("202a2f"))
	host.draw_circle(Vector2(34, -25), 8.0, Color("202a2f"))
	host.draw_arc(Vector2(-34, -25), 8.0, 0, TAU, 20, Color("7b898f"), 1.5)
	host.draw_arc(Vector2(34, -25), 8.0, 0, TAU, 20, Color("7b898f"), 1.5)
	host.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func get_throttle_rect() -> Rect2:
	var rect = panel_rect()
	return Rect2(rect.end.x - 178, rect.position.y + 62, 28, 112)

func get_yoke_rect() -> Rect2:
	var rect = panel_rect()
	return Rect2(rect.end.x - 136, rect.position.y + 62, 112, 112)

func _split_cockpit_action_rect(area: Rect2, index: int, count: int = 2) -> Rect2:
	var gap = 4.0 if count >= 3 else 8.0
	var button_width = maxf(0.0, (area.size.x - gap * (count - 1)) / count)
	return Rect2(area.position + Vector2(index * (button_width + gap), 0.0), Vector2(button_width, area.size.y))

func _left_cockpit_action_area() -> Rect2:
	var panel = panel_rect()
	var left = panel.position.x + 14.0
	var right = get_weather_radar_rect().position.x - 8.0
	return Rect2(left, panel.position.y + 211.0, maxf(0.0, right - left), 28.0)

func _right_cockpit_action_area() -> Rect2:
	var panel = panel_rect()
	var left = get_ils_rect().end.x + 8.0
	var right = panel.end.x - 24.0
	return Rect2(left, panel.position.y + 211.0, maxf(0.0, right - left), 28.0)

func get_engine_button_rect() -> Rect2:
	return _split_cockpit_action_rect(_right_cockpit_action_area(), 1)

func get_cabin_button_rect() -> Rect2:
	return _split_cockpit_action_rect(_left_cockpit_action_area(), 0, 3)

func get_power_button_rect() -> Rect2:
	return _split_cockpit_action_rect(_right_cockpit_action_area(), 0)

func get_trajectory_button_rect() -> Rect2:
	return _split_cockpit_action_rect(_left_cockpit_action_area(), 1, 3)

func get_center_yoke_button_rect() -> Rect2:
	var yoke_rect = get_yoke_rect()
	return Rect2(yoke_rect.get_center().x - 41.5, yoke_rect.end.y + 7, 83, 24)

func get_trip_reset_button_rect() -> Rect2:
	var rect = panel_rect()
	var clock_center = _instrument_center(7, rect.position.y + 108.0)
	return Rect2(clock_center.x - 27.0, clock_center.y - INSTRUMENT_RADIUS - 42.0, 54.0, 18.0)

func get_time_scale_button_rect(beige: bool = false) -> Rect2:
	if beige:
		return Rect2(48.0, 229.0, 93.0, 20.0)
	var trip_rect = get_trip_reset_button_rect()
	return Rect2(trip_rect.position.x - 76.0, trip_rect.position.y, 72.0, 18.0)

func get_time_reset_button_rect(beige: bool = false) -> Rect2:
	if beige:
		return Rect2(145.0, 229.0, 57.0, 20.0)
	var trip_rect = get_trip_reset_button_rect()
	return Rect2(trip_rect.end.x + 4.0, trip_rect.position.y, 48.0, 18.0)

func get_ils_rect() -> Rect2:
	var rect = panel_rect()
	return Rect2(rect.get_center().x - 242.5, rect.end.y - 82.0, 485, 68)

func get_weather_radar_rect() -> Rect2:
	var rect = panel_rect()
	var ils_rect = get_ils_rect()
	var available_width = maxf(0.0, ils_rect.position.x - rect.position.x - 16.0)
	var radar_width = minf(184.0, available_width)
	return Rect2(ils_rect.position.x - radar_width - 8.0, rect.end.y - 82.0, radar_width, 68.0)

func get_weather_briefing_button_rect() -> Rect2:
	return _split_cockpit_action_rect(_left_cockpit_action_area(), 2, 3)
