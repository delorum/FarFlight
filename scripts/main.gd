extends Control

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
const MapRenderLayerScript = preload("res://scripts/map_render_layer.gd")
const AircraftArt = preload("res://scripts/aircraft_art.gd")
const WeatherRadarArt = preload("res://scripts/weather_radar_art.gd")
const WeatherRadarCache = preload("res://scripts/weather_radar_cache.gd")
const EconomyScript = preload("res://scripts/economy.gd")

const MAP_MARGIN := 14.0
const PANEL_HEIGHT := 280.0
const CONTOUR_STEP_M := 250.0
const SAMPLE_GRID := 192
const INSTRUMENT_RADIUS := 50.0
const INSTRUMENT_GAP := 14.0
const THROTTLE_HOLD_DELAY := 0.32
const THROTTLE_HOLD_RATE := 0.35
const USE_STYLIZED_YOKE := true
const MAX_MAP_ZOOM := 24.0
const INITIAL_MAP_RADIUS_KM := 40.0
const APPROACH_DETAIL_MIN_ZOOM := 20.0
const WIND_OVERLAY_ALTITUDES := [0.0, 1500.0, 3000.0, 5000.0]
const TIME_SCALES := [1.0, 2.0, 4.0, 8.0, 16.0]
const FLIGHT_TIME_STEP := 1.0 / 30.0

enum ViewMode { COCKPIT, CABIN, APRON, AIRPORT, OPERATIONS, MAIL, SHOP, HOTEL, FUEL }

var world
var flight
var economy
var receiver_frequencies := [305, 327]
var active_receiver := -1
var receiver_frequency_entry := ""
var map_zoom := 1.0
var map_center := Vector2.ONE * FlightWorldScript.SIZE_KM * 0.5
var contour_segments: Array[Dictionary] = []
var terrain_peaks: Array[Dictionary] = []
var measurement_lines: Array[Dictionary] = []
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
var dragging_yoke := false
var dragging_throttle := false
var last_mouse := Vector2.ZERO
var status_timer := 0.0
var clock_seconds := 12.0 * 60.0 * 60.0
var trip_air_distance_km := 0.0
var trip_elapsed_seconds := 0.0
var flight_trajectory: Array[Dictionary] = []
var trajectory_finished := false
var trajectory_recording_started := false
var trajectory_elapsed_seconds := 0.0
var trajectory_distance_km := 0.0
var trajectory_last_position := Vector2.ZERO
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
var wind_overlay_index := 0
var last_wind_overlay_altitude_m := -INF
var view_mode := ViewMode.COCKPIT
var scene_player_x := 180.0
var scene_player_facing := 1.0
var scene_walk_phase := 0.0
var apron_aircraft_on_left := true
var scene_notice := ""
var scene_is_walking := false
var propeller_phase := 0.0
var cabin_terrain_zoom := 0
var cabin_terrain_profile := PackedVector2Array()
var cabin_terrain_timer := 0.0
var cabin_rain_blue := true
var cabin_fog_travel_px := 0.0
var large_weather_radar := false
const RADAR_RANGES_KM := [30.0, 20.0, 10.0, 5.0]
var radar_range_index := 0
var weather_radar_cache: Node
var crash_overlay: PanelContainer
var crash_description: Label
var crash_title: Label
var selected_inventory_slot := -1
var in_fuel_bay := false
var last_economy_flight_state := -1
var fuel_amount_litres := 20.0
var dragging_fuel_slider := false
var hovered_airport_index := -1
var time_scale_index := 0
var cabin_sleeping := false
var cabin_sleep_progress_seconds := 0.0

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	map_render_layer = MapRenderLayerScript.new()
	map_render_layer.controller = self
	map_render_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map_render_layer)
	weather_radar_cache = WeatherRadarCache.new()
	add_child(weather_radar_cache)
	_build_crash_overlay()
	resized.connect(_on_viewport_resized)
	regenerate_world()
	set_process(true)
	queue_redraw()

func _input(event: InputEvent) -> void:
	# Godot dispatches input to children before the shell. Let Esc reach the
	# pause menu before cabin interactions or receiver text entry consume it.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and get_parent().has_method("_pause_game"):
		get_parent()._pause_game()
		get_viewport().set_input_as_handled()
		return
	if flight != null and flight.state == FlightModelScript.State.CRASHED:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_show_crash_map()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_Z or event.physical_keycode == KEY_Z):
		if event.shift_pressed:
			_reset_time_scale()
		else:
			_cycle_time_scale()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _key_causes_time_reset(event):
		_reset_time_scale_for_action()
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_X or event.physical_keycode == KEY_X) and view_mode in [ViewMode.COCKPIT, ViewMode.CABIN]:
		if view_mode == ViewMode.COCKPIT:
			_enter_cabin()
		else:
			_set_view_mode(ViewMode.COCKPIT)
		get_viewport().set_input_as_handled()
		return
	if view_mode != ViewMode.COCKPIT:
		if event is InputEventKey and event.pressed and not event.echo:
			if view_mode == ViewMode.CABIN and cabin_terrain_zoom == 0 and event.keycode == KEY_DOWN and _near_cabin_ramp():
				in_fuel_bay = true
				scene_player_x = _aircraft_point(Vector2(315, 0)).x
				_set_default_fuel_amount()
				scene_notice = ""
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if view_mode == ViewMode.CABIN and event.keycode == KEY_LEFT and in_fuel_bay:
				in_fuel_bay = false
				scene_player_x = _aircraft_point(Vector2(AircraftArt.COCKPIT_RAMP_BOTTOM_X + 15, 0)).x
				scene_player_facing = -1.0
				scene_notice = ""
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if cabin_terrain_zoom > 0 and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
				cabin_terrain_zoom = 0
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_interact_in_scene()
			elif event.keycode == KEY_ESCAPE:
				_leave_current_scene()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		flight.toggle_engine()
		_queue_map_redraw()
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and (event.keycode == KEY_B or event.physical_keycode == KEY_B):
		_toggle_weather_radar()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode in [KEY_1, KEY_2]:
		active_receiver = 0 if event.keycode == KEY_1 else 1
		receiver_frequency_entry = ""
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo and active_receiver >= 0:
		var entered_character := char(event.unicode)
		if entered_character >= "0" and entered_character <= "9":
			_enter_receiver_frequency_digit(entered_character)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if event.keycode == KEY_BACKSPACE:
			receiver_frequency_entry = receiver_frequency_entry.left(maxi(0, receiver_frequency_entry.length() - 1))
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_commit_receiver_frequency_entry()
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if event.keycode == KEY_ESCAPE:
			receiver_frequency_entry = ""
			active_receiver = -1
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
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
		if event.keycode == KEY_SPACE:
			simulation_paused = not simulation_paused
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.keycode == KEY_C:
			flight.yoke = Vector2.ZERO
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.keycode == KEY_T:
			_reset_trip_counter()
			get_viewport().set_input_as_handled()
			queue_redraw()
		elif event.keycode == KEY_V:
			wind_overlay_index += 1
			if wind_overlay_index > WIND_OVERLAY_ALTITUDES.size():
				wind_overlay_index = 0
			last_wind_overlay_altitude_m = -INF
			get_viewport().set_input_as_handled()
			_queue_map_redraw()

func regenerate_world() -> void:
	world = FlightWorldScript.new()
	flight = FlightModelScript.new(world)
	economy = EconomyScript.new(world)
	last_economy_flight_state = flight.state
	propeller_phase = 0.0
	map_center = Vector2(world.airports[flight.airport_index].position)
	map_zoom = _initial_map_zoom(map_center)
	_clamp_map_center()
	measurement_lines.clear()
	pending_measure = null
	radar_measurement_lines.clear()
	radar_pending_measure = null
	radar_range_index = 0
	clock_seconds = 12.0 * 60.0 * 60.0
	time_scale_index = 0
	cabin_sleeping = false
	cabin_sleep_progress_seconds = 0.0
	trip_air_distance_km = 0.0
	trip_elapsed_seconds = 0.0
	_reset_flight_trajectory()
	ils_airport_index = 0
	ils_prediction_timer = 0.0
	_tune_receivers_to_departure_airport()
	_build_contours()
	_build_approach_markers()
	_update_receiver_signals()
	_update_ils_touchdown_prediction()
	_queue_map_redraw()
	queue_redraw()

func _process(delta: float) -> void:
	if flight.state == FlightModelScript.State.CRASHED:
		return
	if view_mode != ViewMode.COCKPIT:
		_update_scene_walking(delta)
	elif absf(Input.get_axis("ui_left", "ui_right")) > 0.05 or absf(Input.get_axis("ui_up", "ui_down")) > 0.05 or throttle_up_held or throttle_down_held or dragging_yoke or dragging_throttle or dragging_map or dragging_measure_point:
		# Also catches a control that was already held when Z was pressed.
		_reset_time_scale_for_action()
	if simulation_paused:
		return
	if time_scale_index != 0 and _storm_is_turning_aircraft():
		_reset_time_scale()
	var game_delta: float = delta * float(TIME_SCALES[time_scale_index])
	signal_check_timer -= game_delta
	if signal_check_timer <= 0.0:
		_update_receiver_signals()
		signal_check_timer = 1.0
	ils_prediction_timer -= game_delta
	if ils_prediction_timer <= 0.0:
		_update_ils_touchdown_prediction()
		ils_prediction_timer = 1.0
	clock_seconds = fmod(clock_seconds + game_delta, 24.0 * 60.0 * 60.0)
	economy.advance_time(game_delta, cabin_sleeping)
	_update_cabin_sleep(game_delta)
	if not economy.game_over_reason.is_empty():
		flight._crash(economy.game_over_reason)
		_update_crash_overlay()
		return
	var keyboard_yoke := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if view_mode == ViewMode.COCKPIT and not dragging_yoke:
		if absf(keyboard_yoke.x) > 0.05:
			flight.yoke.x = keyboard_yoke.x
		else:
			flight.yoke.x = move_toward(flight.yoke.x, 0.0, delta * 1.8)
		if absf(keyboard_yoke.y) > 0.05:
			# Only the pitch axis is positional: releasing Up/Down leaves the
			# elevator command where the pilot set it.
			flight.yoke.y = clampf(flight.yoke.y + keyboard_yoke.y * delta * 0.75, -1.0, 1.0)
	_update_held_throttle(delta)
	var state_before_update: int = flight.state
	var speed_before_update: float = flight.speed_kmh
	var engine_before_update: bool = flight.engine_running
	var flight_time_remaining: float = game_delta
	while flight_time_remaining > 0.000001 and flight.state != FlightModelScript.State.CRASHED:
		var flight_step := minf(FLIGHT_TIME_STEP, flight_time_remaining)
		flight.update(flight_step)
		flight_time_remaining -= flight_step
		# A coherent storm roll can begin between rendered frames while time is
		# accelerated. Expose it immediately so the pilot can take control.
		if time_scale_index != 0 and _storm_is_turning_aircraft():
			_reset_time_scale()
	if flight.state == FlightModelScript.State.LANDED and last_economy_flight_state != FlightModelScript.State.LANDED:
		economy.arrive_at_airport(flight.airport_index, world)
	last_economy_flight_state = flight.state
	# Match the small scope: heading and motion must be rendered every frame,
	# independently of the once-per-second radio/ILS signal checks.
	if large_weather_radar and view_mode == ViewMode.COCKPIT and flight.engine_running:
		_queue_map_redraw()
	if cabin_terrain_zoom > 0:
		if not _can_view_cabin_terrain():
			cabin_terrain_zoom = 0
		else:
			cabin_terrain_timer -= delta
			if cabin_terrain_timer <= 0.0:
				_update_cabin_terrain_profile()
	if engine_before_update != flight.engine_running:
		_queue_map_redraw()
	_update_propeller_animation(delta)
	if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size() and absf(flight.altitude_m - last_wind_overlay_altitude_m) >= 25.0:
		last_wind_overlay_altitude_m = flight.altitude_m
		_queue_map_redraw()
	_update_flight_trajectory(state_before_update, speed_before_update, game_delta)
	if flight.state == FlightModelScript.State.CRASHED:
		scene_is_walking = false
		dragging_yoke = false
		dragging_throttle = false
		_update_crash_overlay()
	if flight.state == FlightModelScript.State.FLYING:
		trip_air_distance_km += flight.speed_kmh / 3600.0 * game_delta
		trip_elapsed_seconds += game_delta
	status_timer += game_delta
	if flight.state == FlightModelScript.State.FLYING:
		# Accumulate travel rather than multiplying time by current speed: this
		# avoids jumps when the aircraft accelerates or changes orientation.
		var fog_speed := lerpf(12.0, 40.0, clampf(flight.speed_kmh / 220.0, 0.0, 1.0))
		cabin_fog_travel_px += fog_speed * game_delta * (1.0 if _aircraft_mirrored() else -1.0)
	queue_redraw()

func _update_cabin_sleep(game_delta: float) -> void:
	if not cabin_sleeping:
		cabin_sleep_progress_seconds = 0.0
		return
	cabin_sleep_progress_seconds += game_delta
	while cabin_sleep_progress_seconds >= EconomyScript.HOTEL_REST_SECONDS:
		cabin_sleep_progress_seconds -= EconomyScript.HOTEL_REST_SECONDS
		economy.recover_aircraft_bed_unit()
	if cabin_sleeping:
		scene_notice = "Отдых: %d/20 мин • бодрость %d/6 (не выше 2)" % [floori(cabin_sleep_progress_seconds / 60.0), economy.fatigue]

func _cycle_time_scale() -> void:
	time_scale_index = (time_scale_index + 1) % TIME_SCALES.size()
	queue_redraw()

func _reset_time_scale() -> void:
	time_scale_index = 0
	queue_redraw()

func _reset_time_scale_for_action() -> void:
	if time_scale_index != 0:
		_reset_time_scale()

func _storm_is_turning_aircraft() -> bool:
	return flight.state == FlightModelScript.State.FLYING and flight.storm_intensity > 0.01 and absf(flight.storm_roll_bias_deg) > 0.01

func _key_causes_time_reset(event: InputEventKey) -> bool:
	var code := event.keycode
	var physical := event.physical_keycode
	if code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER]:
		return true
	if code in [KEY_X, KEY_M, KEY_B, KEY_W, KEY_S, KEY_SPACE, KEY_C, KEY_T, KEY_V] or physical in [KEY_X, KEY_B, KEY_W, KEY_S]:
		return true
	if event.ctrl_pressed and code in [KEY_1, KEY_2]:
		return true
	if active_receiver >= 0:
		var entered_character := char(event.unicode)
		return (entered_character >= "0" and entered_character <= "9") or code in [KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER]
	return false

func _stop_cabin_sleep() -> void:
	if not cabin_sleeping:
		return
	cabin_sleeping = false
	cabin_sleep_progress_seconds = 0.0
	scene_notice = ""

func _build_crash_overlay() -> void:
	crash_overlay = PanelContainer.new()
	crash_overlay.visible = false
	crash_overlay.z_index = 10
	crash_overlay.add_theme_stylebox_override("panel",_rounded_box(AircraftArt.PAPER,AircraftArt.INK,2,8))
	add_child(crash_overlay)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,20)
	crash_overlay.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",16)
	margin.add_child(layout)
	crash_title = Label.new()
	crash_title.text = "ПОЛЁТ ЗАВЕРШЁН — КРУШЕНИЕ"
	crash_title.add_theme_color_override("font_color",Color("a83f38"))
	crash_title.add_theme_font_size_override("font_size",22)
	layout.add_child(crash_title)
	crash_description = Label.new()
	crash_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crash_description.custom_minimum_size = Vector2(600,90)
	crash_description.add_theme_color_override("font_color",Color("694b30"))
	layout.add_child(crash_description)
	var map_button := Button.new()
	map_button.text = "ПОКАЗАТЬ ТРАЕКТОРИЮ [ENTER]"
	map_button.pressed.connect(_show_crash_map)
	layout.add_child(map_button)
	resized.connect(_update_crash_overlay)

func _update_crash_overlay() -> void:
	if crash_overlay == null or flight == null:
		return
	var needs_death: bool = economy != null and not economy.game_over_reason.is_empty()
	crash_overlay.visible = flight.state == FlightModelScript.State.CRASHED and (view_mode != ViewMode.COCKPIT or needs_death)
	if not crash_overlay.visible:
		return
	var overlay_width := minf(760,size.x-40)
	crash_title.text = "ИГРА ОКОНЧЕНА" if needs_death else "ПОЛЁТ ЗАВЕРШЁН — КРУШЕНИЕ"
	crash_description.custom_minimum_size.x = overlay_width-44
	crash_description.text = ("Самолёт находился в сваливании.\n" if flight.stalled else "")+flight.message
	crash_overlay.size = Vector2(overlay_width,280)
	crash_overlay.position = (size-crash_overlay.size)*0.5

func _show_crash_map() -> void:
	large_weather_radar = false
	_set_view_mode(ViewMode.COCKPIT)

func _update_propeller_animation(delta: float) -> void:
	if not flight.engine_running:
		propeller_phase = 0.0
	elif not simulation_paused:
		# Deliberately slower apparent rotation than real RPM to avoid strobing.
		propeller_phase = fposmod(propeller_phase + delta * TAU * lerpf(2.8, 5.2, flight.throttle), TAU)

func _adjust_throttle_percent(step_percent: int) -> void:
	var current_percent := roundi(flight.throttle * 100.0)
	if step_percent < 0 and current_percent <= 0 and _aircraft_is_on_ground():
		flight.wheel_brakes_applied = true
		return
	if step_percent > 0:
		flight.wheel_brakes_applied = false
	flight.throttle = clampf((current_percent + step_percent) / 100.0, 0.0, 1.0)

func _reset_trip_counter() -> void:
	trip_air_distance_km = 0.0
	trip_elapsed_seconds = 0.0
	if flight != null and flight.state != FlightModelScript.State.CRASHED:
		flight._show_message("Счётчик воздушного пути сброшен", 3.0, "")

func _prepare_for_departure() -> void:
	var next_airport: int = flight.airport_index
	if not economy.pay_parking():
		flight._show_message("Не хватает денег на стоянку и подготовку", 3.0, "")
		return
	flight.prepare_at_airport(next_airport)
	_reset_flight_trajectory()
	_tune_receivers_to_departure_airport()
	_update_receiver_signals()
	_update_ils_touchdown_prediction()
	ils_prediction_timer = 1.0

func _prepare_from_operations(reverse_direction: bool) -> void:
	flight.prepare_at_airport(flight.airport_index, reverse_direction)
	_reset_flight_trajectory()
	_tune_receivers_to_departure_airport()
	_update_receiver_signals()
	_update_ils_touchdown_prediction()
	ils_prediction_timer = 1.0
	apron_aircraft_on_left = not reverse_direction
	scene_notice = "Самолёт подготовлен к вылету курсом %03d°" % roundi(flight.heading_deg)

func _pay_and_prepare(reverse_direction: bool) -> void:
	if not economy.pay_parking():
		scene_notice = "Не хватает денег на стоянку и подготовку"
		return
	_prepare_from_operations(reverse_direction)
	scene_notice += " • оплачено %d монет" % EconomyScript.PARKING_PRICE

func _near_cabin_ramp() -> bool:
	var ramp_x := _aircraft_point(Vector2((AircraftArt.COCKPIT_RAMP_TOP_X + AircraftArt.COCKPIT_RAMP_BOTTOM_X) * 0.5, 0)).x
	return absf(scene_player_x - ramp_x) < 55.0

func _refuel_from_carried_canister() -> void:
	var moved: float = economy.transfer_carried_fuel(fuel_amount_litres, flight.fuel_capacity_l - flight.fuel_l)
	if moved <= 0:
		scene_notice = "Нужна канистра с топливом или бак уже полон"
	else:
		flight.fuel_l = minf(flight.fuel_capacity_l, flight.fuel_l + moved)
		_set_default_fuel_amount()
		scene_notice = "Перелито %.1f л • в баке %.1f/%.0f л" % [moved, flight.fuel_l, flight.fuel_capacity_l]

func _handle_economy_click(position: Vector2) -> void:
	if _economy_button_rect(5).has_point(position):
		_leave_current_scene()
		return
	match view_mode:
		ViewMode.MAIL:
			var row := 0
			if economy.carried_item.get("type", "") == "parcel" and int(economy.carried_item.get("destination", -1)) == flight.airport_index:
				if _economy_button_rect(row).has_point(position):
					var delivery: Dictionary = economy.deliver_carried(flight.airport_index)
					scene_notice = "Доставлено: +%d монет%s" % [delivery.paid, " • срочно" if delivery.urgent else ""]
					return
				row += 1
			var offers: Array = economy.offers_at(flight.airport_index)
			for index in offers.size():
				if _economy_button_rect(row + index).has_point(position):
					var parcel: Dictionary = economy.accept_offer(flight.airport_index, index)
					scene_notice = "Посылка получена — отнесите её в самолёт" if not parcel.is_empty() else "Сначала освободите руки"
					return
		ViewMode.SHOP:
			if _economy_button_rect(0).has_point(position):
				scene_notice = "Еда куплена — отнесите её в самолёт" if economy.buy_food() else "Не хватает денег или руки заняты"
		ViewMode.HOTEL:
			if _economy_button_rect(0).has_point(position):
				if economy.fatigue >= EconomyScript.NEED_SEGMENTS:
					scene_notice = "Вы уже полностью отдохнули"
				elif economy.buy_hotel_rest():
					clock_seconds = fmod(clock_seconds + EconomyScript.HOTEL_REST_SECONDS, 86400.0)
					world.update_weather(EconomyScript.HOTEL_REST_SECONDS)
					scene_notice = "Отдых 20 минут • бодрость %d/6" % economy.fatigue
				else:
					scene_notice = "Не хватает денег"
		ViewMode.FUEL:
			if _economy_button_rect(0).has_point(position):
				if economy.buy_canister():
					_set_default_fuel_amount()
					scene_notice = "Канистра куплена"
				else:
					scene_notice = "Не хватает денег или руки заняты"
			elif _set_fuel_amount_from_mouse(position):
				scene_notice = "Выбрано %.1f л" % fuel_amount_litres
			elif _economy_button_rect(2).has_point(position):
				var bought: float = economy.fill_carried_canister(fuel_amount_litres)
				_set_default_fuel_amount()
				scene_notice = "Куплено %.1f л топлива" % bought if bought > 0 else "Возьмите канистру или проверьте деньги"
			elif _economy_button_rect(3).has_point(position):
				var paid: int = economy.sell_carried_canister()
				scene_notice = "Получено %d монет" % paid if paid > 0 else "Возьмите канистру"

func _tune_receivers_to_departure_airport() -> void:
	for beacon in world.beacons:
		if int(beacon.get("runway", -1)) == flight.airport_index:
			var departure_frequency := int(beacon.frequency)
			receiver_frequencies[0] = departure_frequency
			receiver_frequencies[1] = departure_frequency
			return

func _reset_flight_trajectory() -> void:
	flight_trajectory.clear()
	trajectory_finished = false
	trajectory_recording_started = false
	trajectory_elapsed_seconds = 0.0
	trajectory_distance_km = 0.0
	if flight != null:
		trajectory_last_position = flight.position_km
		flight_trajectory.append(_make_trajectory_point(flight.position_km))
	if map_render_layer != null:
		_queue_map_redraw()

func _make_trajectory_point(position: Vector2) -> Dictionary:
	return {
		"position": position,
		"time_seconds": trajectory_elapsed_seconds,
		"distance_km": trajectory_distance_km,
	}

func _update_flight_trajectory(previous_state: int, previous_speed: float, delta: float) -> void:
	# A stopped aircraft may depart again without using the preparation button.
	# Treat its first movement as the beginning of a completely new flight.
	if previous_state == FlightModelScript.State.LANDED and previous_speed <= 0.05 and flight.speed_kmh > 0.05:
		_reset_flight_trajectory()
	var moved_distance := trajectory_last_position.distance_to(flight.position_km)
	if moved_distance > 0.000001 or flight.speed_kmh > 0.05:
		trajectory_recording_started = true
	if trajectory_recording_started:
		trajectory_elapsed_seconds += delta
		trajectory_distance_km += moved_distance
	trajectory_last_position = flight.position_km
	if flight_trajectory.is_empty():
		flight_trajectory.append(_make_trajectory_point(flight.position_km))
	elif Vector2(flight_trajectory[-1].position).distance_to(flight.position_km) >= 0.03:
		flight_trajectory.append(_make_trajectory_point(flight.position_km))
	var just_finished: bool = (
		flight.state == FlightModelScript.State.CRASHED and previous_state != FlightModelScript.State.CRASHED
	) or (
		flight.state == FlightModelScript.State.LANDED and previous_state != FlightModelScript.State.LANDED
	)
	if just_finished:
		if not Vector2(flight_trajectory[-1].position).is_equal_approx(flight.position_km):
			flight_trajectory.append(_make_trajectory_point(flight.position_km))
		trajectory_finished = true
		flight._show_message("%s • путь %.1f км • время %s" % [flight.message, trajectory_distance_km, _format_trajectory_time(trajectory_elapsed_seconds)], -1.0, "")
		_queue_map_redraw()

func _format_trajectory_time(seconds_value: float) -> String:
	var total_seconds := maxi(0, roundi(seconds_value))
	var hours: int = total_seconds / 3600
	var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func _set_view_mode(next_mode: int) -> void:
	if next_mode != ViewMode.CABIN:
		_stop_cabin_sleep()
	weather_radar_cache.invalidate()
	cabin_terrain_zoom = 0
	view_mode = next_mode
	if view_mode != ViewMode.CABIN:
		in_fuel_bay = false
	dragging_fuel_slider = false
	if view_mode == ViewMode.FUEL:
		_set_default_fuel_amount()
	scene_is_walking = false
	dragging_map = false
	map_drag_candidate = false
	point_drag_candidate = false
	dragging_measure_point = false
	map_render_layer.visible = view_mode == ViewMode.COCKPIT
	dragging_yoke = false
	dragging_throttle = false
	throttle_up_held = false
	throttle_down_held = false
	scene_notice = ""
	_update_crash_overlay()
	_queue_map_redraw()
	queue_redraw()

func _aircraft_mirrored() -> bool:
	# The side-view camera always looks at the same side of the aircraft.
	# The source drawing faces left, so mirror it to keep the nose right.
	return true

func _aircraft_scale() -> float:
	return minf(size.x * 0.84 / 1000.0, (size.y * 0.76 - 140.0) / AircraftArt.GROUND_Y)

func _aircraft_origin() -> Vector2:
	var width := 1000.0 * _aircraft_scale()
	var x := (size.x - width) * 0.5
	return Vector2(x, size.y * 0.76 - AircraftArt.GROUND_Y * _aircraft_scale())

func _aircraft_point(local_point: Vector2) -> Vector2:
	var point := local_point
	if _aircraft_mirrored():
		point.x = 1000.0 - point.x
	return _aircraft_origin() + point * _aircraft_scale()

func _scene_walk_bounds() -> Vector2:
	if view_mode == ViewMode.CABIN:
		var a := _aircraft_point(Vector2(AircraftArt.WALK_MIN, 0)).x
		var b := _aircraft_point(Vector2(AircraftArt.WALK_MAX, 0)).x
		return Vector2(minf(a,b),maxf(a,b))
	return Vector2(34,size.x-34)

func _cabin_player_position() -> Vector2:
	var local_x := (scene_player_x - _aircraft_origin().x) / _aircraft_scale()
	if _aircraft_mirrored():
		local_x = 1000.0 - local_x
	var position := _aircraft_point(Vector2(local_x, AircraftArt.cabin_floor_y(local_x)))
	if in_fuel_bay:
		position = _aircraft_point(Vector2(local_x, AircraftArt.FLOOR_Y))
	return position

func _airport_exit_x() -> float:
	return size.x - 48.0 if apron_aircraft_on_left else 48.0

func _can_exit_aircraft() -> bool:
	return _aircraft_is_on_ground() and flight.speed_kmh <= 0.05

func _scene_hotspots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if view_mode == ViewMode.CABIN:
		for entry in [[AircraftArt.SEAT_X,"В кресло пилота"],[AircraftArt.DOOR_X,"На перрон"]]:
			if entry[0] == AircraftArt.DOOR_X and flight.state == FlightModelScript.State.FLYING:
				continue
			var point := _aircraft_point(Vector2(entry[0],AircraftArt.cabin_floor_y(entry[0])))
			var label_y := point.y + 14.0 * _aircraft_scale() if entry[0] == AircraftArt.SEAT_X else _aircraft_point(Vector2(0,AircraftArt.FLOOR_Y)).y+44
			var label_x := point.x + (16.0 * _aircraft_scale() if entry[0] == AircraftArt.SEAT_X else 0.0)
			result.append({"x":point.x,"rect":Rect2(point-Vector2(43,105),Vector2(86,137)),"label":entry[1],"label_y":label_y,"label_x":label_x})
	elif view_mode == ViewMode.APRON:
		var point := _aircraft_point(Vector2(AircraftArt.DOOR_X,AircraftArt.FLOOR_Y))
		result.append({"x":point.x,"rect":Rect2(point-Vector2(46,110),Vector2(92,210)),"label":"В самолёт"})
		var exit_x := _airport_exit_x()
		result.append({"x":exit_x,"rect":Rect2(exit_x-43,size.y*0.76-88,86,120),"label":"В аэропорт"})
	elif view_mode == ViewMode.AIRPORT:
		var buildings := _airport_buildings()
		for index in buildings.size():
			var x: float = size.x * (index + 1.0) / (buildings.size() + 1.0)
			result.append({"x":x,"rect":Rect2(x-65,size.y*0.76-170,130,200),"label":buildings[index].label,"kind":buildings[index].kind})
		result.append({"x":45.0,"rect":Rect2(16,size.y*0.76-80,58,110),"label":"На ВПП"})
	return result

func _draw_scene_hotspots() -> void:
	if flight.state == FlightModelScript.State.CRASHED:
		return
	var pose := _cabin_pose()
	draw_set_transform_matrix(pose)
	for spot in _scene_hotspots():
		var rect: Rect2 = spot.rect
		var hovered := rect.has_point(pose.affine_inverse() * get_local_mouse_position())
		var color := Color("#785022") if hovered else AircraftArt.INK
		var label: String = spot.label
		var width := ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+20
		var x := clampf(float(spot.get("label_x", spot.x))-width*0.5,12,size.x-width-12)
		var y: float = spot.get("label_y", rect.end.y + 12)
		draw_string(ThemeDB.fallback_font,Vector2(x+10,y),label,HORIZONTAL_ALIGNMENT_CENTER,width-20,12,color)
		if hovered:
			draw_line(Vector2(x+10,y+5),Vector2(x+width-10,y+5),color,1,true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _click_side_scene(position: Vector2) -> void:
	if cabin_terrain_zoom > 0:
		return
	if view_mode == ViewMode.CABIN and _bed_has_point(position):
		if not cabin_sleeping:
			_start_cabin_sleep()
		queue_redraw()
		return
	if view_mode == ViewMode.CABIN and _fuel_device_has_point(position):
		in_fuel_bay = true
		scene_player_x = _aircraft_point(Vector2(315, 0)).x
		_set_default_fuel_amount()
		scene_notice = ""
		scene_is_walking = false
		queue_redraw()
		return
	if in_fuel_bay:
		in_fuel_bay = false
		dragging_fuel_slider = false
	if cabin_sleeping:
		_stop_cabin_sleep()
	if flight.state == FlightModelScript.State.CRASHED:
		return
	position = _cabin_pose().affine_inverse() * position
	var interact := false
	var bounds := _scene_walk_bounds()
	var destination := clampf(position.x,bounds.x,bounds.y)
	for spot in _scene_hotspots():
		var hit_rect: Rect2 = spot.rect
		hit_rect.size.y += 32.0
		if hit_rect.has_point(position):
			destination = clampf(float(spot.x),bounds.x,bounds.y)
			interact = true
			break
	if not is_equal_approx(destination, scene_player_x):
		scene_player_facing = signf(destination - scene_player_x)
	scene_player_x = destination
	scene_is_walking = false
	scene_notice = ""
	if interact:
		_interact_in_scene()
	queue_redraw()

func _enter_cabin() -> void:
	_set_view_mode(ViewMode.CABIN)
	scene_player_x = _aircraft_point(Vector2(AircraftArt.SEAT_X, 0)).x
	scene_player_facing = -1.0 if not _aircraft_mirrored() else 1.0
func _enter_apron() -> void:
	apron_aircraft_on_left = _aircraft_mirrored()
	_set_view_mode(ViewMode.APRON)
	scene_player_x = _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
	scene_player_facing = 1.0 if apron_aircraft_on_left else -1.0
func _update_scene_walking(delta: float) -> void:
	if cabin_terrain_zoom > 0:
		scene_is_walking = false
		return
	if in_fuel_bay:
		scene_is_walking = false
		return
	if flight.state == FlightModelScript.State.CRASHED:
		return
	if view_mode not in [ViewMode.CABIN, ViewMode.APRON, ViewMode.AIRPORT]:
		return
	var movement := Input.get_axis("ui_left", "ui_right")
	if cabin_sleeping and absf(movement) > 0.05:
		_stop_cabin_sleep()
	scene_is_walking = false
	var bounds := _scene_walk_bounds()
	if absf(movement) > 0.05:
		_reset_time_scale_for_action()
		scene_player_facing = signf(movement)
		scene_player_x = clampf(scene_player_x + movement * 190.0 * delta, bounds.x, bounds.y)
		scene_is_walking = true
	if scene_is_walking:
		scene_walk_phase += delta * 11.0
		scene_notice = ""
	queue_redraw()
func _interact_in_scene() -> void:
	if flight.state == FlightModelScript.State.CRASHED:
		return
	match view_mode:
		ViewMode.CABIN:
			if cabin_sleeping:
				_stop_cabin_sleep()
				return
			if in_fuel_bay:
				_refuel_from_carried_canister()
				return
			var seat := _aircraft_point(Vector2(AircraftArt.SEAT_X, 0)).x
			var door := _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
			var bed := _aircraft_point(Vector2(735.0, 0)).x
			if absf(scene_player_x - seat) < 38.0:
				_set_view_mode(ViewMode.COCKPIT)
			elif absf(scene_player_x - bed) < 38.0:
				_start_cabin_sleep()
			elif flight.state != FlightModelScript.State.FLYING and absf(scene_player_x - door) < 38.0:
				if _can_exit_aircraft():
					_enter_apron()
				else:
					scene_notice = "Выход доступен после остановки на ВПП"
		ViewMode.APRON:
			var door := _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
			if absf(scene_player_x - door) < 55.0:
				_enter_cabin()
				scene_player_x = _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
			elif absf(scene_player_x - _airport_exit_x()) < 50.0:
				_set_view_mode(ViewMode.AIRPORT)
				scene_player_x = 45.0 if apron_aircraft_on_left else size.x - 45.0
		ViewMode.AIRPORT:
			if scene_player_x < 70.0 or scene_player_x > size.x - 70.0:
				_enter_apron()
				scene_player_x = _airport_exit_x()
			else:
				for spot in _scene_hotspots():
					if spot.has("kind") and absf(scene_player_x - float(spot.x)) < 110.0:
						_set_view_mode(int(spot.kind))
						break
		ViewMode.OPERATIONS:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL:
			_set_view_mode(ViewMode.AIRPORT)
func _leave_current_scene() -> void:
	match view_mode:
		ViewMode.OPERATIONS:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.AIRPORT:
			_enter_apron()
		ViewMode.APRON:
			_enter_cabin()
		ViewMode.CABIN:
			_set_view_mode(ViewMode.COCKPIT)

func _scene_prompt(text: String) -> void:
	if flight.state == FlightModelScript.State.CRASHED:
		text = "Enter: траектория полёта • Esc: меню"
	draw_line(Vector2(36, size.y - 69), Vector2(size.x - 36, size.y - 69), AircraftArt.LIGHT, 1.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(36, size.y - 39), text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 72, 15, AircraftArt.INK)
	var controls_text := "Esc: меню" if flight.state == FlightModelScript.State.CRASHED else "ЛКМ: переместиться • клик по двери: перейти • стрелки: идти • Enter: действие • Esc: меню"
	if view_mode == ViewMode.CABIN and flight.state != FlightModelScript.State.CRASHED:
		controls_text = "ЛКМ / стрелки: идти • Enter: действие • X: за штурвал • Esc: меню"
	draw_string(ThemeDB.fallback_font, Vector2(36, size.y - 17), controls_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - 72, 11, Color("#ad9271"))
func _draw_pilot(position: Vector2, rotation: float = 0.0) -> void:
	var stride := sin(scene_walk_phase) * 6.0 if scene_is_walking else 0.0
	var pilot_scale := _aircraft_scale() * AircraftArt.PILOT_SCALE if view_mode in [ViewMode.CABIN, ViewMode.APRON] else AircraftArt.PILOT_SCALE
	draw_set_transform_matrix(_cabin_pose() * Transform2D(rotation, Vector2(scene_player_facing, 1) * pilot_scale, 0.0, position))
	var ink := Color("#795e3c")
	var cloth := Color("#cbb892")
	draw_line(Vector2(-3,-21), Vector2(-7+stride,-3), ink, 5, true)
	draw_line(Vector2(3,-21), Vector2(6-stride,-3), ink, 5, true)
	draw_line(Vector2(-7+stride,-2), Vector2(-1+stride,-2), ink, 4, true)
	draw_line(Vector2(6-stride,-2), Vector2(12-stride,-2), ink, 4, true)
	AircraftArt.poly(self, PackedVector2Array([Vector2(-7,-49),Vector2(5,-50),Vector2(9,-25),Vector2(-8,-23)]), cloth, ink, 1.5)
	draw_circle(Vector2(1,-60), 8, Color("#ead3ac"))
	draw_arc(Vector2(1,-60), 8, 0, TAU, 24, ink, 1.5, true)
	draw_line(Vector2(-7,-67), Vector2(12,-67), ink, 3, true)
	draw_rect(Rect2(-6,-73,13,6), cloth)
	draw_line(Vector2(-6,-73), Vector2(7,-73), ink, 2)
	draw_line(Vector2(0,-46), Vector2(7-stride*0.7,-30), ink, 3, true)
	draw_line(Vector2(-6,-27), Vector2(7,-28), ink, 2)
	draw_circle(Vector2(7,-61), 1, ink)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _item_label(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"parcel":
			return "ПОЧТА\n%s" % world.airports[int(item.destination)].name
		"food": return "ЕДА"
		"canister": return "%.1f Л" % float(item.get("fuel_l", 0.0))
	return ""

func _draw_item_icon(rect: Rect2, item: Dictionary, faint: bool = false, show_label: bool = true) -> void:
	var ink := Color(AircraftArt.INK, 0.30 if faint else 1.0)
	var fill := Color(AircraftArt.PAPER, 0.22 if faint else 0.95)
	AircraftArt.box(self, rect, fill, ink, 2)
	var type := String(item.get("type", ""))
	if type == "parcel":
		draw_line(rect.position, rect.end, ink, 1.0)
		draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), ink, 1.0)
	elif type == "food":
		draw_arc(rect.get_center(), rect.size.x * 0.22, 0, TAU, 18, ink, 1.5, true)
	elif type == "canister":
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.58, -3), Vector2(rect.size.x * 0.25, 5)), fill, true)
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.58, -3), Vector2(rect.size.x * 0.25, 5)), ink, false, 1.0)
	if show_label and not faint and not type.is_empty():
		draw_string(ThemeDB.fallback_font, rect.end + Vector2(4, -4), _item_label(item), HORIZONTAL_ALIGNMENT_LEFT, 95, 8, ink)

func _inventory_rect(slot: int) -> Rect2:
	var column := slot % 3
	var row := slot / 3
	var top_left := _aircraft_point(Vector2(520.0 + column * 31.0, 247.0 + row * 34.0))
	return Rect2(top_left, Vector2(27, 29) * _aircraft_scale())

func _draw_cabin_economy_objects() -> void:
	draw_set_transform_matrix(_cabin_pose())
	# Six tiedown bays beside the cargo door.
	for slot in EconomyScript.INVENTORY_CAPACITY:
		var rect := _inventory_rect(slot)
		_draw_item_icon(rect, economy.inventory[slot], economy.inventory[slot].is_empty(), false)
	_draw_cabin_bed()
	_draw_cabin_fuel_device()
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _bed_transform() -> Transform2D:
	return _cabin_pose() * Transform2D(0.0, Vector2.ONE * _aircraft_scale(), 0.0, _aircraft_point(Vector2(790, 307)))

func _bed_has_point(position: Vector2) -> bool:
	var local_position := _bed_transform().affine_inverse() * position
	return Rect2(-6, -25, 108, 67).has_point(local_position)

func _start_cabin_sleep() -> void:
	if not economy.carried_item.is_empty():
		scene_notice = "Перед сном освободите руки"
		return
	scene_player_x = _aircraft_point(Vector2(735.0, 0)).x
	in_fuel_bay = false
	dragging_fuel_slider = false
	cabin_sleeping = true
	cabin_sleep_progress_seconds = 0.0
	scene_is_walking = false
	scene_notice = "Вы легли отдохнуть • каждые 20 минут +1, не выше 2"

func _draw_cabin_bed() -> void:
	draw_set_transform_matrix(_bed_transform())
	# Mattress top is y=0; the frame stands on the cabin floor at y=23.
	for x in [4.0, 90.0]:
		draw_line(Vector2(x, 8), Vector2(x, 23), AircraftArt.INK, 2.2, true)
	draw_line(Vector2(3, 11), Vector2(93, 11), AircraftArt.INK, 2.2, true)
	AircraftArt.box(self, Rect2(0, -10, 5, 25), AircraftArt.PAPER, AircraftArt.INK, 2)
	AircraftArt.box(self, Rect2(91, -20, 5, 35), AircraftArt.PAPER, AircraftArt.INK, 2)
	AircraftArt.box(self, Rect2(5, 0, 86, 9), Color("ddd2b1"), AircraftArt.INK, 3)
	draw_line(Vector2(10, 6), Vector2(86, 6), AircraftArt.LIGHT, 1, true)
	AircraftArt.box(self, Rect2(71, -4, 18, 5), Color("e1d6b8"), AircraftArt.LIGHT, 2)
	draw_string(ThemeDB.fallback_font, Vector2(0, 39), "КРОВАТЬ • ENTER", HORIZONTAL_ALIGNMENT_CENTER, 96, 8, AircraftArt.INK)

func _draw_sleeping_pilot() -> void:
	draw_set_transform_matrix(_bed_transform())
	var ink := Color("795e3c")
	var cloth := Color("cbb892")
	# A dedicated supine profile: back on mattress, nose and closed eye upward.
	draw_line(Vector2(18, -3), Vector2(45, -4), ink, 5, true)
	draw_line(Vector2(16, -3), Vector2(15, -8), ink, 3, true)
	AircraftArt.poly(self, PackedVector2Array([Vector2(43,-7),Vector2(61,-12),Vector2(69,-9),Vector2(70,-2),Vector2(43,-2)]), cloth, ink, 1.3)
	draw_line(Vector2(65,-7), Vector2(55,-8), ink, 2, true)
	draw_line(Vector2(55,-8), Vector2(53,-12), ink, 1.5, true)
	draw_circle(Vector2(79,-11), 7, Color("ead3ac"))
	draw_arc(Vector2(79,-11), 7, 0, TAU, 24, ink, 1.2, true)
	draw_line(Vector2(81,-16), Vector2(84,-15), ink, 1, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_cabin_fuel_device() -> void:
	draw_set_transform_matrix(_fuel_device_transform())
	# Reservoir, pump, shutoff valve and fuel pipe through the engine bulkhead.
	var ink := AircraftArt.INK
	draw_polyline(PackedVector2Array([Vector2(40,30),Vector2(48,30),Vector2(48,12),Vector2(94,12)]), ink, 2, true)
	AircraftArt.box(self, Rect2(0, 5, 39, 40), Color("d0c29d"), ink, 6)
	for y in [14.0, 36.0]:
		draw_line(Vector2(2,y), Vector2(37,y), AircraftArt.LIGHT, 2, true)
	AircraftArt.box(self, Rect2(7, -1, 13, 6), AircraftArt.PAPER, ink, 2)
	draw_line(Vector2(7,-3), Vector2(20,-3), ink, 2, true)
	draw_circle(Vector2(13,23), 6, AircraftArt.PAPER)
	draw_arc(Vector2(13,23), 6, 0, TAU, 20, ink, 1, true)
	draw_line(Vector2(13,23), Vector2(16,20), ink, 1, true)
	AircraftArt.box(self, Rect2(27,18,5,14), AircraftArt.PAPER, ink, 1)
	draw_line(Vector2(29,29),Vector2(29,23),ink,2,true)
	draw_circle(Vector2(48,12), 4, AircraftArt.PAPER)
	draw_line(Vector2(44,8),Vector2(52,16),ink,1.5,true)
	draw_line(Vector2(44,16),Vector2(52,8),ink,1.5,true)
	draw_line(Vector2(5,45),Vector2(5,50),ink,2,true)
	draw_line(Vector2(34,45),Vector2(34,50),ink,2,true)
	draw_string(ThemeDB.fallback_font, Vector2(-10,64), "ЗАПРАВКА", HORIZONTAL_ALIGNMENT_CENTER, 65, 8, ink)

func _fuel_device_transform() -> Transform2D:
	return _cabin_pose() * Transform2D(0.0, Vector2.ONE * _aircraft_scale(), 0.0, _aircraft_point(Vector2(295, 280)))

func _fuel_device_hover_description(position: Vector2) -> String:
	if _fuel_device_has_point(position):
		return "Топливо в баке: %.1f/%.0f л" % [flight.fuel_l, flight.fuel_capacity_l]
	return ""

func _fuel_device_has_point(position: Vector2) -> bool:
	var local_position := _fuel_device_transform().affine_inverse() * position
	return Rect2(-12.0, -8.0, 112.0, 76.0).has_point(local_position)

func _draw_carried_item(pilot_position: Vector2) -> void:
	if economy.carried_item.is_empty():
		return
	draw_set_transform_matrix(_cabin_pose())
	# Keep the load in front of the pilot after either left/right turn.
	var item_offset_x := 10.0 if scene_player_facing > 0.0 else -34.0
	_draw_item_icon(Rect2(pilot_position + Vector2(item_offset_x, -44), Vector2(24, 24)), economy.carried_item)
	draw_set_transform_matrix(Transform2D.IDENTITY)

func _handle_inventory_click(position: Vector2) -> bool:
	if in_fuel_bay and _set_fuel_amount_from_mouse(position, Vector2(36, size.y - 152)):
		scene_notice = ""
		return true
	if not economy.carried_item.is_empty():
		var carried_type := String(economy.carried_item.get("type", ""))
		if _carried_action_rect(0).has_point(position):
			scene_notice = "Предмет уложен" if economy.store_carried() else "Нет свободных слотов"
			return true
		if carried_type == "food" and _carried_action_rect(1).has_point(position):
			scene_notice = "Сытость %d/6" % economy.hunger if economy.eat_carried() else "Вы уже сыты"
			return true
		if carried_type == "canister" and _carried_action_rect(1).has_point(position):
			if in_fuel_bay:
				_refuel_from_carried_canister()
			else:
				scene_notice = "Подойдите к лестнице и нажмите ↓, чтобы заправить самолёт"
			return true
		if _carried_action_rect(2).has_point(position):
			economy.discard_carried()
			scene_notice = "Предмет выброшен"
			return true
	position = _cabin_pose().affine_inverse() * position
	for slot in EconomyScript.INVENTORY_CAPACITY:
		if _inventory_rect(slot).grow(4.0).has_point(position):
			selected_inventory_slot = slot
			if economy.inventory[slot].is_empty():
				scene_notice = "Предмет уложен в грузовой отсек" if economy.store_carried(slot) else "Слот пуст"
			elif economy.carried_item.is_empty():
				economy.take_slot(slot)
				scene_notice = "Вы взяли: " + _item_label(economy.carried_item).replace("\n", " — ")
			else:
				scene_notice = "Сначала освободите руки"
			return true
	return false

func _inventory_hover_description(position: Vector2) -> String:
	var cabin_position := _cabin_pose().affine_inverse() * position
	for slot in EconomyScript.INVENTORY_CAPACITY:
		var item: Dictionary = economy.inventory[slot]
		if not item.is_empty() and _inventory_rect(slot).grow(4.0).has_point(cabin_position):
			match String(item.get("type", "")):
				"parcel":
					var remaining: float = float(item.get("urgent_deadline", 0.0)) - economy.elapsed_seconds
					var deadline_text: String = "срочный тариф ещё %s" % _format_short_time(remaining) if remaining >= 0.0 else "срочный срок истёк"
					return "Посылка • аэропорт «%s» • оплата %d, срочно %d • %s" % [world.airports[int(item.destination)].name, int(item.get("normal_reward", 0)), int(item.get("urgent_reward", 0)), deadline_text]
				"food":
					return "Еда • восстанавливает 1 деление сытости"
				"canister":
					return "Канистра • %.1f/%d л топлива" % [float(item.get("fuel_l", 0)), EconomyScript.CANISTER_CAPACITY_L]
	return ""

func _carried_action_rect(index: int) -> Rect2:
	return Rect2(size.x - 376.0 + index * 120.0, size.y - 112.0, 112.0, 30.0)

func _draw_carried_actions() -> void:
	if economy.carried_item.is_empty():
		return
	var middle_action := "ЗАПРАВИТЬ" if economy.carried_item.get("type", "") == "canister" else "СЪЕСТЬ"
	var entries := [[0, "УЛОЖИТЬ"], [2, "ВЫБРОСИТЬ"]]
	if economy.carried_item.get("type", "") in ["food", "canister"]:
		entries.insert(1, [1, middle_action])
	for entry in entries:
		_draw_menu_button(_carried_action_rect(entry[0]), entry[1], 13)
	if in_fuel_bay:
		_draw_fuel_amount_slider(Vector2(36, size.y - 152))

func _fuel_slider_rect(origin: Vector2 = Vector2.INF) -> Rect2:
	return Rect2(_economy_button_rect(1).position if origin == Vector2.INF else origin, Vector2(_economy_button_rect(1).size.x, 38))

func _draw_fuel_amount_slider(origin: Vector2 = Vector2.INF) -> void:
	var rect := _fuel_slider_rect(origin)
	AircraftArt.box(self, rect, AircraftArt.PAPER, AircraftArt.INK, 3)
	var track := Rect2(rect.position + Vector2(18, 23), Vector2(rect.size.x - 36, 3))
	draw_rect(track, AircraftArt.LIGHT, true)
	var maximum := _fuel_slider_maximum()
	var knob_x := lerpf(track.position.x, track.end.x, clampf(fuel_amount_litres / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0)
	draw_circle(Vector2(knob_x, track.get_center().y), 6, AircraftArt.INK)
	var label := "Объём: %.1f л • клик или перетаскивание" % fuel_amount_litres
	if view_mode == ViewMode.CABIN and in_fuel_bay and economy.carried_item.get("type", "") == "canister":
		var canister_after := maxf(0.0, float(economy.carried_item.get("fuel_l", 0.0)) - fuel_amount_litres)
		var tank_after := minf(flight.fuel_capacity_l, flight.fuel_l + fuel_amount_litres)
		label = "Заправить %.1f л • останется %.1f л • бак %.1f/%.0f л" % [fuel_amount_litres, canister_after, tank_after, flight.fuel_capacity_l]
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 16), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20, 11, AircraftArt.INK)

func _set_fuel_amount_from_mouse(position: Vector2, origin: Vector2 = Vector2.INF, allow_outside: bool = false) -> bool:
	var rect := _fuel_slider_rect(origin)
	if not allow_outside and not rect.has_point(position):
		return false
	var maximum := _fuel_slider_maximum()
	if maximum <= 0.0:
		fuel_amount_litres = 0.0
		return true
	var raw_amount := inverse_lerp(rect.position.x + 18, rect.end.x - 18, position.x) * maximum
	fuel_amount_litres = clampf(snappedf(raw_amount, 0.1), minf(0.1, maximum), maximum)
	return true

func _fuel_slider_maximum() -> float:
	if view_mode == ViewMode.CABIN and in_fuel_bay:
		if economy.carried_item.get("type", "") != "canister":
			return 0.0
		return snappedf(maxf(0.0, minf(float(economy.carried_item.get("fuel_l", 0.0)), flight.fuel_capacity_l - flight.fuel_l)), 0.1)
	if economy.carried_item.get("type", "") == "canister":
		return snappedf(maxf(0.0, EconomyScript.CANISTER_CAPACITY_L - float(economy.carried_item.get("fuel_l", 0.0))), 0.1)
	return float(EconomyScript.CANISTER_CAPACITY_L)

func _set_default_fuel_amount() -> void:
	fuel_amount_litres = _fuel_slider_maximum()

func _active_fuel_slider_origin() -> Vector2:
	return Vector2(36, size.y - 152) if view_mode == ViewMode.CABIN and in_fuel_bay else Vector2.INF

func _fuel_slider_is_active() -> bool:
	return (view_mode == ViewMode.CABIN and in_fuel_bay) or view_mode == ViewMode.FUEL
func _draw_scene_background(title: String) -> float:
	draw_rect(Rect2(Vector2.ZERO, size), AircraftArt.PAPER, true)
	var ground_y := size.y * 0.76
	draw_string(ThemeDB.fallback_font, Vector2(38, 44), "FAR FLIGHT   /   ПОЧТОВАЯ АВИАЦИЯ", HORIZONTAL_ALIGNMENT_LEFT, size.x - 76, 11, Color("#b29a78"))
	draw_string(ThemeDB.fallback_font, Vector2(36, 79), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 72, 24, AircraftArt.INK)
	draw_line(Vector2(36, 98), Vector2(size.x-36,98), AircraftArt.LIGHT, 1, true)
	# Faint horizon, grass and broken ground lines echo the architectural reference.
	if view_mode != ViewMode.CABIN:
		for i in 9:
			var x := size.x * (i + 0.25) / 9.0
			draw_line(Vector2(x,ground_y+12),Vector2(x+size.x/13.0,ground_y+12),AircraftArt.LIGHT,1,true)
			for blade in 3:
				var start := Vector2(x+blade*6,ground_y+10)
				draw_line(start,start+Vector2(blade*2-2,-7-blade*2),AircraftArt.LIGHT,1,true)
	return ground_y
func _draw_cabin_scene() -> void:
	_draw_scene_background("Борт 02 / салон")
	if cabin_terrain_zoom > 0:
		_draw_cabin_terrain()
		return
	_draw_cabin_weather(false)
	_draw_cabin_airport_close_view()
	_draw_cabin_weather(true)
	AircraftArt.draw_aircraft(self, _aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), true, flight.engine_running, propeller_phase, _cabin_pitch())
	_draw_cabin_economy_objects()
	if cabin_sleeping:
		_draw_sleeping_pilot()
	else:
		_draw_pilot(_cabin_player_position())
	_draw_carried_item(_cabin_player_position())
	_draw_scene_hotspots()
	_draw_carried_actions()
	var prompt := "Грузовой отсек • самолёт продолжает полёт" if flight.state == FlightModelScript.State.FLYING else "Грузовой отсек • самолёт на стоянке"
	if _can_view_cabin_terrain():
		prompt += " • колесо вниз: отдалить"
	for spot in _scene_hotspots():
		if absf(scene_player_x - float(spot.x)) < 38:
			prompt = "Enter: " + String(spot.label)
	var inventory_description := _inventory_hover_description(get_local_mouse_position())
	var fuel_description := _fuel_device_hover_description(get_local_mouse_position())
	if flight.stall_warning_active():
		prompt = "СВАЛИВАНИЕ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ" if flight.stalled else "БОЛЬШОЙ УГОЛ АТАКИ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ"
		_scene_prompt(prompt)
	else:
		var hover_description := inventory_description if not inventory_description.is_empty() else fuel_description
		_scene_prompt(hover_description if not hover_description.is_empty() else (scene_notice if not scene_notice.is_empty() else prompt))
func _can_view_cabin_terrain() -> bool:
	return view_mode == ViewMode.CABIN and flight.state != FlightModelScript.State.CRASHED

func _cabin_pitch() -> float:
	return flight.pitch_deg if flight.state == FlightModelScript.State.FLYING else 0.0

func _cabin_pose() -> Transform2D:
	if view_mode != ViewMode.CABIN:
		return Transform2D.IDENTITY
	return AircraftArt.pitch_transform(_aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), _cabin_pitch())

func _cabin_ground_visible() -> bool:
	return flight.altitude_m - world.height_at(flight.position_km) < 100.0

func _cabin_terrain_span_m() -> float:
	return 500.0 * pow(1.5, maxi(0, cabin_terrain_zoom - 1))

func _cabin_ground_direction() -> Vector2:
	var velocity: Vector2 = world.heading_vector(flight.heading_deg) * flight.speed_kmh + flight.current_wind_kmh
	return velocity.normalized() if velocity.length_squared() > 0.01 else world.heading_vector(flight.heading_deg)

func _update_cabin_terrain_profile() -> void:
	cabin_terrain_timer = 0.1
	cabin_terrain_profile.clear()
	# Section along actual ground motion, including drift, not just nose heading.
	var direction := _cabin_ground_direction()
	var screen_direction := 1.0 if _aircraft_mirrored() else -1.0
	var span := _cabin_terrain_span_m()
	var count := ceili(span / 2.0)
	for i in range(count + 1):
		var offset := lerpf(-span * 0.5, span * 0.5, float(i) / count)
		var point: Vector2 = flight.position_km + direction * offset * screen_direction / 1000.0
		cabin_terrain_profile.append(Vector2(offset, world.height_at(point)))

func _draw_cabin_terrain() -> void:
	var rect := Rect2(36, 115, size.x - 72, size.y - 200)
	# Equal horizontal/vertical scale preserves terrain slopes. The schematic
	# airframe is represented as a 12 m aircraft instead of a screen-sized cabin.
	var pixels_per_m := minf(rect.size.x / _cabin_terrain_span_m(), rect.size.y / 190.0)
	var anchor := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.28)
	var previous := Vector2.ZERO
	_draw_cabin_weather(false)
	var ground_visible := _cabin_ground_visible()
	var airport_view := _cabin_visible_airport()
	if ground_visible and not airport_view.is_empty():
		_draw_distant_airport(airport_view, rect, anchor, pixels_per_m)
	for i in cabin_terrain_profile.size():
		var sample := cabin_terrain_profile[i]
		var point := anchor + Vector2(sample.x, flight.altitude_m - sample.y) * pixels_per_m
		if i > 0 and ground_visible:
			var segment := _clip_line_to_rect(previous, point, rect)
			if segment.size() == 2:
				draw_line(segment[0], segment[1], AircraftArt.INK, 1.6, true)
		previous = point
	if ground_visible and not airport_view.is_empty():
		_draw_side_runway(airport_view, rect, anchor, pixels_per_m)
	var aircraft_scale := 12.0 * pixels_per_m / 1000.0
	AircraftArt.draw_small_aircraft(self, anchor - Vector2(500, AircraftArt.GROUND_Y) * aircraft_scale, aircraft_scale, _aircraft_mirrored(), _cabin_pitch())
	_draw_cabin_weather(true)
	var prompt := "Колесо: масштаб • Enter / Esc: в салон • X: за штурвал"
	if flight.stall_warning_active():
		prompt = "СВАЛИВАНИЕ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ" if flight.stalled else "БОЛЬШОЙ УГОЛ АТАКИ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ"
	draw_string(ThemeDB.fallback_font, Vector2(36, size.y - 39), prompt, HORIZONTAL_ALIGNMENT_CENTER, size.x - 72, 15, AircraftArt.INK)
	draw_string(ThemeDB.fallback_font, Vector2(36, size.y - 17), "Вид вниз вдоль пути • полёт продолжается • Esc: меню", HORIZONTAL_ALIGNMENT_CENTER, size.x - 72, 11, AircraftArt.INK)

func _draw_cabin_airport_close_view() -> void:
	if not _cabin_ground_visible():
		return
	var airport_view := _cabin_visible_airport()
	if airport_view.is_empty():
		return
	var rect := Rect2(36, 115, size.x - 72, size.y - 200)
	# The landscape keeps the 500 m overview scale behind the full-size cutaway.
	# Its ground reference is the aircraft's wheels, so the runway sits beneath
	# them while parked and rises into view naturally during the last descent.
	var pixels_per_m := minf(rect.size.x / _cabin_terrain_span_m(), rect.size.y / 190.0)
	var wheel_ground_y := _aircraft_origin().y + AircraftArt.GROUND_Y * _aircraft_scale()
	var anchor := Vector2(rect.get_center().x, wheel_ground_y)
	_draw_side_runway(airport_view, rect, anchor, pixels_per_m)

func _cabin_visible_airport() -> Dictionary:
	var screen_world_direction := _cabin_ground_direction() * (1.0 if _aircraft_mirrored() else -1.0)
	var half_span_km := _cabin_terrain_span_m() / 2000.0
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for airport_index in world.airports.size():
		var airport: Dictionary = world.airports[airport_index]
		var local_position: Vector2 = world.runway_coordinates(flight.position_km, airport)
		var runway_forward: Vector2 = world.heading_vector(float(airport.heading))
		var runway_right := Vector2(runway_forward.y, -runway_forward.x)
		var local_direction := Vector2(screen_world_direction.dot(runway_forward), screen_world_direction.dot(runway_right))
		var interval := _line_runway_interval(local_position, local_direction)
		var clipped_start := maxf(interval.x, -half_span_km)
		var clipped_end := minf(interval.y, half_span_km)
		if clipped_start > clipped_end:
			continue
		var centre_parameter: float = (Vector2(airport.position) - flight.position_km).dot(screen_world_direction)
		var distance: float = absf(centre_parameter)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = {
				"airport_index": airport_index,
				"start_m": clipped_start * 1000.0,
				"end_m": clipped_end * 1000.0,
				"runway_start_m": interval.x * 1000.0,
				"runway_end_m": interval.y * 1000.0,
				"centre_m": centre_parameter * 1000.0,
			}
	return nearest

func _line_runway_interval(origin: Vector2, direction: Vector2) -> Vector2:
	var low := -INF
	var high := INF
	var half_length := FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var half_width := FlightWorldScript.RUNWAY_WIDTH_KM * 0.5
	if absf(direction.x) < 0.000001:
		if absf(origin.x) > half_length:
			return Vector2(INF, -INF)
	else:
		var first_x := (-half_length - origin.x) / direction.x
		var second_x := (half_length - origin.x) / direction.x
		low = maxf(low, minf(first_x, second_x))
		high = minf(high, maxf(first_x, second_x))
	if absf(direction.y) < 0.000001:
		if absf(origin.y) > half_width:
			return Vector2(INF, -INF)
	else:
		var first_y := (-half_width - origin.y) / direction.y
		var second_y := (half_width - origin.y) / direction.y
		low = maxf(low, minf(first_y, second_y))
		high = minf(high, maxf(first_y, second_y))
	return Vector2(low, high) if low <= high else Vector2(INF, -INF)

func _side_runway_y(airport_index: int, anchor: Vector2, pixels_per_m: float) -> float:
	var airport: Dictionary = world.airports[airport_index]
	var runway_height: float = world.height_at(Vector2(airport.position))
	return anchor.y + (flight.altitude_m - runway_height) * pixels_per_m

func _draw_distant_airport(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	var runway_y := _side_runway_y(int(view.airport_index), anchor, pixels_per_m)
	if runway_y < rect.position.y or runway_y > rect.end.y + 20.0:
		return
	# Buildings share the airport's world coordinate instead of being clamped to
	# a screen edge; they must travel backwards and leave the frame on takeoff.
	var cluster_m := float(view.centre_m)
	var distant_ink := AircraftArt.INK.lerp(AircraftArt.PAPER, 0.48)
	var distant_fill := AircraftArt.LIGHT.lerp(AircraftArt.PAPER, 0.42)
	for building in [
		{"offset_m": -52.0, "width_m": 18.0, "height_m": 8.0},
		{"offset_m": -24.0, "width_m": 13.0, "height_m": 11.0},
		{"offset_m": 9.0, "width_m": 24.0, "height_m": 9.0},
		{"offset_m": 44.0, "width_m": 15.0, "height_m": 7.0},
	]:
		var centre_x := anchor.x + (cluster_m + float(building.offset_m)) * pixels_per_m
		var width_px := clampf(float(building.width_m) * pixels_per_m, 9.0, 46.0)
		var height_px := clampf(float(building.height_m) * pixels_per_m, 7.0, 30.0)
		if centre_x + width_px < rect.position.x or centre_x - width_px > rect.end.x:
			continue
		var body := Rect2(centre_x - width_px * 0.5, runway_y - height_px, width_px, height_px)
		var visible_body := body.intersection(rect)
		if visible_body.has_area():
			draw_rect(visible_body, distant_fill, true)
		for edge in [
			[body.position, Vector2(body.end.x, body.position.y)],
			[Vector2(body.end.x, body.position.y), body.end],
			[body.end, Vector2(body.position.x, body.end.y)],
			[Vector2(body.position.x, body.end.y), body.position],
		]:
			_draw_side_clipped_line(edge[0], edge[1], distant_ink, 1.1, rect)
		var roof := PackedVector2Array([
			Vector2(body.position.x - 2.0, body.position.y),
			Vector2(centre_x, body.position.y - height_px * 0.42),
			Vector2(body.end.x + 2.0, body.position.y),
		])
		_draw_side_clipped_line(roof[0], roof[1], distant_ink, 1.1, rect)
		_draw_side_clipped_line(roof[1], roof[2], distant_ink, 1.1, rect)
		if width_px >= 14.0:
			var door := Rect2(centre_x - 2.0, runway_y - height_px * 0.55, 4.0, height_px * 0.55)
			for edge in [
				[door.position, Vector2(door.end.x, door.position.y)],
				[Vector2(door.end.x, door.position.y), door.end],
				[door.end, Vector2(door.position.x, door.end.y)],
				[Vector2(door.position.x, door.end.y), door.position],
			]:
				_draw_side_clipped_line(edge[0], edge[1], distant_ink, 0.8, rect)
	# A modest locator/radio mast rises just above the distant airport buildings.
	var tower_x := anchor.x + (cluster_m + 28.0) * pixels_per_m
	var tower_height := clampf(17.0 * pixels_per_m, 24.0, 48.0)
	var tower_half_width := clampf(tower_height * 0.18, 5.0, 8.0)
	if tower_x + tower_half_width >= rect.position.x and tower_x - tower_half_width <= rect.end.x:
		var tower_top := runway_y - tower_height
		_draw_side_clipped_line(Vector2(tower_x - tower_half_width, runway_y), Vector2(tower_x, tower_top), distant_ink, 1.2, rect)
		_draw_side_clipped_line(Vector2(tower_x + tower_half_width, runway_y), Vector2(tower_x, tower_top), distant_ink, 1.2, rect)
		for brace_index in 3:
			var upper_y := runway_y - tower_height * (brace_index + 1.0) / 4.0
			var lower_y := runway_y - tower_height * brace_index / 4.0
			var upper_half := tower_half_width * (upper_y - tower_top) / tower_height
			var lower_half := tower_half_width * (lower_y - tower_top) / tower_height
			_draw_side_clipped_line(Vector2(tower_x - lower_half, lower_y), Vector2(tower_x + upper_half, upper_y), distant_ink, 0.9, rect)
			_draw_side_clipped_line(Vector2(tower_x + lower_half, lower_y), Vector2(tower_x - upper_half, upper_y), distant_ink, 0.9, rect)
		_draw_side_clipped_line(Vector2(tower_x, tower_top), Vector2(tower_x, tower_top - 7.0), distant_ink, 1.2, rect)
		if rect.has_point(Vector2(tower_x, tower_top - 8.5)):
			draw_circle(Vector2(tower_x, tower_top - 8.5), 1.8, distant_ink)

func _draw_side_clipped_line(a: Vector2, b: Vector2, color: Color, width: float, rect: Rect2) -> void:
	var clipped := _clip_line_to_rect(a, b, rect)
	if clipped.size() == 2:
		draw_line(clipped[0], clipped[1], color, width, true)

func _draw_side_runway(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	var start_x := clampf(anchor.x + float(view.start_m) * pixels_per_m, rect.position.x, rect.end.x)
	var end_x := clampf(anchor.x + float(view.end_m) * pixels_per_m, rect.position.x, rect.end.x)
	var runway_y := _side_runway_y(int(view.airport_index), anchor, pixels_per_m)
	if runway_y < rect.position.y - 8.0 or runway_y > rect.end.y:
		return
	var dash_origin_x := anchor.x + float(view.runway_start_m) * pixels_per_m
	_draw_runway_strip_screen(start_x, end_x, runway_y, dash_origin_x)

func _draw_runway_strip_screen(start_x: float, end_x: float, runway_y: float, dash_origin_x: float = NAN) -> void:
	var runway_rect := Rect2(start_x, runway_y - 2.0, maxf(0.0, end_x - start_x), 9.0)
	draw_rect(runway_rect, Color("b6a779"), true)
	draw_line(Vector2(start_x, runway_y - 2.0), Vector2(end_x, runway_y - 2.0), AircraftArt.INK, 2.0, true)
	draw_line(Vector2(start_x, runway_y + 7.0), Vector2(end_x, runway_y + 7.0), AircraftArt.LIGHT, 1.2, true)
	if is_nan(dash_origin_x):
		dash_origin_x = start_x
	var dash_x := dash_origin_x + 15.0
	if dash_x + 24.0 < start_x:
		dash_x += ceilf((start_x - dash_x - 24.0) / 45.0) * 45.0
	while dash_x < end_x - 8.0:
		var visible_dash_start := maxf(dash_x, start_x)
		var visible_dash_end := minf(dash_x + 24.0, end_x)
		if visible_dash_end > visible_dash_start:
			draw_line(Vector2(visible_dash_start, runway_y + 2.5), Vector2(visible_dash_end, runway_y + 2.5), Color("ded5b5"), 2.0, true)
		dash_x += 45.0

func _cabin_weather_scale() -> float:
	if cabin_terrain_zoom == 0:
		return _aircraft_scale() * 1000.0 / 12.0
	return minf((size.x - 72.0) / _cabin_terrain_span_m(), (size.y - 200.0) / 190.0)

func _cabin_cloud_base_y(fraction: float) -> float:
	var scale_y := _cabin_weather_scale()
	var reference_y := _aircraft_origin().y + AircraftArt.GROUND_Y * _aircraft_scale()
	var terrain: float = world.height_at(flight.position_km)
	if cabin_terrain_zoom > 0:
		reference_y = 115.0 + (size.y - 200.0) * 0.28
		if not cabin_terrain_profile.is_empty():
			var offset := (fraction - 0.5) * (size.x - 72.0) / scale_y
			var sample_index := clampf((offset / _cabin_terrain_span_m() + 0.5) * (cabin_terrain_profile.size() - 1), 0.0, cabin_terrain_profile.size() - 1)
			var left := floori(sample_index)
			terrain = lerpf(cabin_terrain_profile[left].y, cabin_terrain_profile[mini(left + 1, cabin_terrain_profile.size() - 1)].y, sample_index - left)
	var world_x := (fraction - 0.5) * (size.x - 72.0) / scale_y
	return reference_y + (flight.altitude_m - terrain - 100.0 + 0.25 * sin(world_x * TAU / 30.0 + status_timer * 0.2)) * scale_y

func _draw_cabin_weather(foreground: bool) -> void:
	var rect := Rect2(36, 115, size.x - 72, size.y - 200)
	var severity: float = flight.storm_intensity
	var time := status_timer
	if not foreground:
		# The cloud base stays in world space, even after entering the layer.
		var edge := PackedVector2Array()
		for i in range(121):
			var fraction := i / 120.0
			var y := _cabin_cloud_base_y(fraction)
			edge.append(Vector2(lerpf(rect.position.x, rect.end.x, fraction), clampf(y, rect.position.y, rect.end.y)))
		var fill := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y)])
		for i in range(edge.size() - 1, -1, -1):
			fill.append(edge[i])
		var cloud_depth := 0.0
		for point in edge:
			cloud_depth = maxf(cloud_depth, point.y - rect.position.y)
		if cloud_depth > 0.1:
			draw_colored_polygon(fill, Color("c9c3a7").lerp(Color("b5af98"), severity * 0.45))
		draw_polyline(edge, Color("b9ac8e"), 1.3, true)
		return
	var fog_bottom := PackedFloat32Array()
	for i in range(61):
		fog_bottom.append(_cabin_cloud_base_y(i / 60.0))
	if fog_bottom[30] > rect.position.y or fog_bottom[0] > rect.position.y or fog_bottom[60] > rect.position.y:
		# Light translucent fog ribbons leave the schematic cabin legible.
		for row in range(7):
			var ribbon := PackedVector2Array()
			for i in range(61):
				var fraction := i / 60.0
				# Wave pattern travels from nose to tail, slowly enough to retain
				# the quiet schematic style. Adjacent bands have slight parallax.
				var phase := (fraction * rect.size.x + cabin_fog_travel_px * (0.85 + row * 0.05)) * 12.0 / rect.size.x
				var y := rect.position.y + rect.size.y * (row + 0.5) / 7.0 + sin(phase + row * 2.0) * 12.0
				ribbon.append(Vector2(lerpf(rect.position.x, rect.end.x, fraction), y))
			for i in range(1, ribbon.size()):
				var cloud_bottom := minf(fog_bottom[i - 1], fog_bottom[i]) - 6.0
				var clip_rect := rect
				clip_rect.size.y = clampf(cloud_bottom - rect.position.y, 0.0, rect.size.y)
				if clip_rect.size.y <= 0.0:
					continue
				var segment := _clip_line_to_rect(ribbon[i - 1], ribbon[i], clip_rect)
				if segment.size() == 2:
					draw_line(segment[0], segment[1], Color(0.91, 0.88, 0.76, 0.28), 12.0, true)
	if severity > 0.0:
		var zone := 0 if severity < 0.35 else (1 if severity < 0.70 else 2)
		var count: int = [45, 110, 220][zone]
		var rain := Color("537c94") if cabin_rain_blue else Color("9b825f")
		rain.a = [0.40, 0.52, 0.65][zone]
		for i in count:
			var x := fposmod(i * 137.507 - time * (35.0 + zone * 18.0), rect.size.x)
			var y := fposmod(i * 97.31 + time * (180.0 + zone * 90.0), rect.size.y)
			var start := rect.position + Vector2(x, y)
			var end := start + Vector2(-6.0 - zone * 3.0, 14.0 + zone * 8.0)
			var clipped := _clip_line_to_rect(start, end, rect)
			if clipped.size() == 2:
				draw_line(clipped[0], clipped[1], rain, 1.0 + zone * 0.25, true)

func _rounded_box(fill: Color, border: Color, border_width: float, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(roundi(border_width))
	box.set_corner_radius_all(roundi(radius))
	return box

func _draw_side_aircraft(_center: Vector2, _flip_direction: bool) -> void:
	AircraftArt.draw_aircraft(self, _aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), false, flight.engine_running, propeller_phase)
func _draw_apron_scene() -> void:
	var runway_y := _draw_scene_background("ВПП / " + String(world.airports[flight.airport_index].name))
	_draw_runway_strip_screen(35.0, size.x - 35.0, runway_y)
	_draw_side_aircraft(Vector2.ZERO, false)
	# Boarding steps align with the very same cargo door used in the cutaway.
	var door := _aircraft_point(Vector2(AircraftArt.DOOR_X, AircraftArt.FLOOR_Y))
	var foot := Vector2(door.x+22,runway_y)
	draw_line(door,foot,AircraftArt.INK,1.5,true)
	draw_line(door+Vector2(-20,0),foot+Vector2(-20,0),AircraftArt.INK,1.5,true)
	for step in range(1,5):
		var at := door.lerp(foot,step/5.0)
		draw_line(at-Vector2(22,0),at+Vector2(2,0),AircraftArt.INK,1.5,true)
	_draw_pilot(Vector2(scene_player_x,runway_y))
	_draw_carried_item(Vector2(scene_player_x,runway_y))
	_draw_scene_hotspots()
	var prompt := "Борт 02 • малый грузовой биплан"
	for spot in _scene_hotspots():
		if absf(scene_player_x - float(spot.x)) < 55:
			prompt = "Enter: " + String(spot.label)
	_scene_prompt(prompt)
func _draw_building(center_x: float, floor_y: float, building_size: Vector2, label: String, _color: Color) -> void:
	var r := Rect2(center_x-building_size.x/2,floor_y-building_size.y,building_size.x,building_size.y)
	AircraftArt.box(self,r,AircraftArt.PAPER,AircraftArt.INK,0)
	AircraftArt.poly(self,PackedVector2Array([Vector2(r.position.x-14,r.position.y),Vector2(center_x,r.position.y-55),Vector2(r.end.x+14,r.position.y)]))
	draw_line(Vector2(r.position.x-8,r.position.y-9),Vector2(center_x,r.position.y-65),AircraftArt.INK,1.5,true)
	draw_line(Vector2(center_x,r.position.y-65),Vector2(r.end.x+8,r.position.y-9),AircraftArt.INK,1.5,true)
	for i in 3:
		var y := r.position.y+55+i*28
		draw_line(Vector2(r.position.x+7,y),Vector2(r.end.x-7,y),AircraftArt.LIGHT,1,true)
	for side in [-1,1]:
		var win := Rect2(center_x+side*building_size.x*0.32-17,r.position.y+49,34,56)
		AircraftArt.box(self,win,AircraftArt.PAPER,AircraftArt.INK,0)
		draw_line(Vector2(win.get_center().x,win.position.y),Vector2(win.get_center().x,win.end.y),AircraftArt.INK,1,true)
		draw_line(Vector2(win.position.x,win.position.y+28),Vector2(win.end.x,win.position.y+28),AircraftArt.INK,1,true)
		draw_line(Vector2(win.position.x-4,win.end.y+5),Vector2(win.end.x+4,win.end.y+5),AircraftArt.INK,1.5,true)
	AircraftArt.box(self,Rect2(center_x-22,floor_y-76,44,76),AircraftArt.PAPER,AircraftArt.INK,2)
	AircraftArt.box(self,Rect2(center_x-15,floor_y-67,30,29),AircraftArt.PAPER,AircraftArt.LIGHT,0)
	draw_circle(Vector2(center_x+14,floor_y-29),2,AircraftArt.INK)
	for i in 3:
		draw_line(Vector2(center_x-28-i*6,floor_y+i*5),Vector2(center_x+28+i*6,floor_y+i*5),AircraftArt.INK,1.5,true)
	draw_string(ThemeDB.fallback_font,Vector2(r.position.x,r.position.y+29),label,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,AircraftArt.INK)
func _draw_airport_scene() -> void:
	var floor_y := _draw_scene_background("АЭРОПОРТ «%s»" % world.airports[flight.airport_index].name)
	var buildings := _airport_buildings()
	for index in buildings.size():
		var x := size.x * (index + 1.0) / (buildings.size() + 1.0)
		var height := 220.0 - float(index % 3) * 22.0
		_draw_building(x, floor_y, Vector2(minf(205.0, size.x / (buildings.size() + 1.7)), height), buildings[index].label.to_upper(), AircraftArt.PAPER)
	# Feet rest on the path in front of the lowest doorstep, not above it.
	_draw_pilot(Vector2(scene_player_x, floor_y + 12))
	_draw_carried_item(Vector2(scene_player_x, floor_y + 12))
	_draw_scene_hotspots()
	var prompt := "Стрелки: идти"
	for spot in _scene_hotspots():
		if spot.has("kind") and absf(scene_player_x - float(spot.x)) < 110.0:
			prompt = "ENTER: " + String(spot.label)
			break
	_scene_prompt(scene_notice if not scene_notice.is_empty() else prompt)

func _airport_buildings() -> Array[Dictionary]:
	var buildings: Array[Dictionary] = [
		{"label":"Лётная служба", "kind":ViewMode.OPERATIONS},
		{"label":"Почта", "kind":ViewMode.MAIL},
	]
	if flight.airport_index in economy.fuel_airports:
		buildings.append({"label":"Заправка", "kind":ViewMode.FUEL})
	if flight.airport_index in economy.food_airports:
		buildings.append({"label":"Магазин", "kind":ViewMode.SHOP})
	if flight.airport_index in economy.hotel_airports:
		buildings.append({"label":"Гостиница", "kind":ViewMode.HOTEL})
	return buildings

func get_operations_refuel_rect() -> Rect2:
	return Rect2(size.x * 0.54, size.y * 0.32, minf(390.0, size.x * 0.40), 52)

func get_operations_runway_rect(reverse_direction: bool) -> Rect2:
	return Rect2(size.x * 0.54, size.y * (0.48 if not reverse_direction else 0.59), minf(390.0, size.x * 0.40), 52)

func get_building_exit_rect() -> Rect2:
	return Rect2(size.x * 0.54, get_operations_runway_rect(true).end.y + 18.0, minf(390.0, size.x * 0.40), 52)

func _draw_menu_button(rect: Rect2, text: String, font_size: int = 14) -> void:
	var fill := AircraftArt.PAPER.darkened(0.04) if rect.has_point(get_local_mouse_position()) else AircraftArt.PAPER
	AircraftArt.box(self,rect,fill,AircraftArt.INK,3)
	var font := ThemeDB.fallback_font
	var baseline_y := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	draw_string(font, Vector2(rect.position.x + 10.0, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, font_size, AircraftArt.INK)

func _draw_operations_scene() -> void:
	var floor_y := _draw_scene_background("ЛЁТНАЯ СЛУЖБА")
	_draw_building(size.x*0.25,floor_y,Vector2(size.x*0.35,minf(350,floor_y-200)),"ЛЁТНАЯ СЛУЖБА",AircraftArt.PAPER)
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.52, 120), "ОБСЛУЖИВАНИЕ САМОЛЁТА", HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.44, 18, Color("34372f"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.54, size.y * 0.27), "Топливо: %.1f / %.0f л" % [flight.fuel_l, flight.fuel_capacity_l], HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.40, 16, Color("34372f"))
	draw_string(ThemeDB.fallback_font, get_operations_refuel_rect().position + Vector2(0, 30), "Стоянка и подготовка: %d монет" % EconomyScript.PARKING_PRICE, HORIZONTAL_ALIGNMENT_CENTER, get_operations_refuel_rect().size.x, 15, AircraftArt.INK)
	var airport: Dictionary = world.airports[flight.airport_index]
	var direct_heading := roundi(float(airport.heading)) % 360
	var reverse_heading := (direct_heading + 180) % 360
	_draw_menu_button(get_operations_runway_rect(false), "ПОДГОТОВИТЬ К ВЫЛЕТУ  %03d°" % direct_heading)
	_draw_menu_button(get_operations_runway_rect(true), "ПОДГОТОВИТЬ К ВЫЛЕТУ  %03d°" % reverse_heading)
	_draw_menu_button(get_building_exit_rect(), "ВЫЙТИ В АЭРОПОРТ [ESC]")
	_scene_prompt(scene_notice if not scene_notice.is_empty() else "ENTER / ESC: выйти из здания")

func _economy_button_rect(index: int) -> Rect2:
	return Rect2(size.x * 0.48, 165.0 + index * 64.0, minf(520.0, size.x * 0.46), 48.0)

func _draw_economy_scene() -> void:
	var titles := {ViewMode.MAIL:"ПОЧТА", ViewMode.SHOP:"МАГАЗИН", ViewMode.HOTEL:"ГОСТИНИЦА", ViewMode.FUEL:"ЗАПРАВКА"}
	var title: String = titles.get(view_mode, "СЛУЖБА")
	var floor_y := _draw_scene_background(title)
	_draw_building(size.x * 0.23, floor_y, Vector2(size.x * 0.32, minf(340.0, floor_y - 190.0)), title, AircraftArt.PAPER)
	draw_string(ThemeDB.fallback_font, Vector2(size.x * 0.48, 120), "%s • %d монет" % [world.airports[flight.airport_index].name, economy.money], HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.46, 18, AircraftArt.INK)
	match view_mode:
		ViewMode.MAIL:
			var row := 0
			if economy.carried_item.get("type", "") == "parcel" and int(economy.carried_item.get("destination", -1)) == flight.airport_index:
				_draw_menu_button(_economy_button_rect(row), "СДАТЬ ПОСЫЛКУ • получить оплату")
				row += 1
			for offer in economy.offers_at(flight.airport_index):
				var destination: String = world.airports[int(offer.destination)].name
				_draw_menu_button(_economy_button_rect(row), "%s • %.0f км • %d / срочно %d" % [destination, offer.distance_km, offer.normal_reward, offer.urgent_reward])
				row += 1
		ViewMode.SHOP:
			_draw_menu_button(_economy_button_rect(0), "КУПИТЬ ЕДУ • %d монет" % EconomyScript.FOOD_PRICE)
		ViewMode.HOTEL:
			_draw_menu_button(_economy_button_rect(0), "ОТДОХНУТЬ 20 МИНУТ • %d монет" % EconomyScript.HOTEL_REST_PRICE)
		ViewMode.FUEL:
			_draw_menu_button(_economy_button_rect(0), "КУПИТЬ ПУСТУЮ КАНИСТРУ • %d" % EconomyScript.CANISTER_PRICE)
			_draw_fuel_amount_slider()
			_draw_menu_button(_economy_button_rect(2), "КУПИТЬ %.1f Л • %d монет" % [fuel_amount_litres, ceili(fuel_amount_litres * EconomyScript.FUEL_PRICE_PER_L)])
			_draw_menu_button(_economy_button_rect(3), "ПРОДАТЬ КАНИСТРУ И ТОПЛИВО")
	_draw_menu_button(_economy_button_rect(5), "ВЫЙТИ В АЭРОПОРТ [ESC]")
	_scene_prompt(scene_notice if not scene_notice.is_empty() else "Клик: действие • Esc: выйти")

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
	match view_mode:
		ViewMode.COCKPIT:
			_draw_panel()
		ViewMode.CABIN:
			_draw_cabin_scene()
		ViewMode.APRON:
			_draw_apron_scene()
		ViewMode.AIRPORT:
			_draw_airport_scene()
		ViewMode.OPERATIONS:
			_draw_operations_scene()
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL:
			_draw_economy_scene()
	if view_mode != ViewMode.COCKPIT:
		_draw_economy_hud(self, false)
		_draw_clock(Vector2(109, 172), 34.0, true)
		_draw_time_controls(true)

func _draw_economy_hud(canvas: CanvasItem, dark: bool) -> void:
	if economy == null:
		return
	var color := Color("e8e4d5") if dark else AircraftArt.INK
	var x := size.x - 360.0
	if view_mode != ViewMode.COCKPIT:
		var goal_text := " • ЦЕЛЬ ДОСТИГНУТА" if economy.money >= EconomyScript.GOAL_COINS else " • цель %d" % EconomyScript.GOAL_COINS
		canvas.draw_string(ThemeDB.fallback_font, Vector2(x, 34), "%d монет%s" % [economy.money, goal_text], HORIZONTAL_ALIGNMENT_LEFT, 330, 13, color)
		canvas.draw_string(ThemeDB.fallback_font, Vector2(x, 53), "Сытость %s  Бодрость %s" % [_need_bar(economy.hunger), _need_bar(economy.fatigue)], HORIZONTAL_ALIGNMENT_LEFT, 330, 12, color)

func _need_bar(value: int) -> String:
	return "■".repeat(clampi(value, 0, 6)) + "□".repeat(6 - clampi(value, 0, 6))

func _format_short_time(seconds_value: float) -> String:
	var total_minutes := maxi(0, ceili(seconds_value / 60.0))
	return "%d:%02d" % [total_minutes / 60, total_minutes % 60]

func _draw_map_on(canvas: Control) -> void:
	map_canvas = canvas
	if large_weather_radar:
		if flight.engine_running:
			weather_radar_cache.update_cache(world, flight, status_timer, RADAR_RANGES_KM[radar_range_index])
		WeatherRadarArt.draw_large(canvas,map_rect(),world,flight,weather_radar_cache.get_texture(),RADAR_RANGES_KM[radar_range_index])
		if flight.engine_running:
			_draw_radar_measurements(canvas)
		_draw_economy_hud(canvas, false)
	else:
		_draw_map()
	map_canvas = null

func _toggle_weather_radar() -> void:
	weather_radar_cache.invalidate()
	large_weather_radar = not large_weather_radar
	# Preserve map camera, finished marks and a pending line, but stop gestures.
	dragging_map = false
	map_drag_candidate = false
	point_drag_candidate = false
	dragging_measure_point = false
	dragged_measure_connections.clear()
	_queue_map_redraw()
	queue_redraw()

func _radar_contains(point: Vector2) -> bool:
	return point.distance_to(WeatherRadarArt.scope_center(map_rect())) <= WeatherRadarArt.scope_radius(map_rect())

func _measurement_to_screen(point: Vector2) -> Vector2:
	if not large_weather_radar:
		return world_to_screen(point)
	return WeatherRadarArt.scope_center(map_rect()) + (point - flight.position_km).rotated(-deg_to_rad(flight.heading_deg)) * WeatherRadarArt.scope_radius(map_rect()) / float(RADAR_RANGES_KM[radar_range_index])

func _measurement_from_screen(point: Vector2) -> Vector2:
	if not large_weather_radar:
		return screen_to_world(point)
	return flight.position_km + ((point - WeatherRadarArt.scope_center(map_rect())) * float(RADAR_RANGES_KM[radar_range_index]) / WeatherRadarArt.scope_radius(map_rect())).rotated(deg_to_rad(flight.heading_deg))

func _clamp_measurement_screen(point: Vector2) -> Vector2:
	if large_weather_radar:
		var center := WeatherRadarArt.scope_center(map_rect())
		return center + (point - center).limit_length(WeatherRadarArt.scope_radius(map_rect()) - 3.0)
	var rect := map_rect().grow(-3.0)
	return point.clamp(rect.position, rect.end)

func _draw_radar_measurements(canvas: CanvasItem) -> void:
	for line in radar_measurement_lines:
		_draw_radar_measurement(canvas, line.a, line.b, Color("e8d274"))
	if radar_pending_measure != null:
		_draw_radar_measurement(canvas, radar_pending_measure, _snap_map_point(_clamp_measurement_screen(get_local_mouse_position())), Color("b9c9ce"))

func _draw_radar_measurement(canvas: CanvasItem, a_world: Vector2, b_world: Vector2, color: Color, center := Vector2.INF, radius := -1.0) -> void:
	var range_km := WeatherRadarArt.RANGE_KM
	if radius < 0.0:
		range_km = RADAR_RANGES_KM[radar_range_index]
		center = WeatherRadarArt.scope_center(map_rect())
		radius = WeatherRadarArt.scope_radius(map_rect())
	var a: Vector2 = center + (a_world - flight.position_km).rotated(-deg_to_rad(flight.heading_deg)) * radius / range_km
	var b: Vector2 = center + (b_world - flight.position_km).rotated(-deg_to_rad(flight.heading_deg)) * radius / range_km
	var clipped := WeatherRadarArt.clip_segment(a, b, center, radius - 2.0)
	if clipped.size() == 2:
		canvas.draw_line(clipped[0], clipped[1], color, 1.7 if radius > 50.0 else 1.0, true)
	for point in [a,b]:
		if point.distance_to(center) < radius - 4.0:
			canvas.draw_circle(point, 3.5 if radius > 50.0 else 1.3, color)

func _handle_radar_mouse_button(event: InputEventMouseButton) -> void:
	var inside: bool = _radar_contains(event.position) and flight.engine_running
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
			dragging_throttle = false
			dragging_yoke = false
	_queue_map_redraw()

func _queue_map_redraw() -> void:
	if map_render_layer != null:
		map_render_layer.queue_redraw()

func _draw_map() -> void:
	var rect := map_rect()
	map_canvas.draw_rect(rect, Color("d7d0ad"), true)
	map_canvas.draw_rect(rect, Color("6d6751"), false, 2.0)
	# 10 km coordinate grid.
	for k in range(0, int(FlightWorldScript.SIZE_KM) + 1, 10):
		var a := world_to_screen(Vector2(k, 0))
		var b := world_to_screen(Vector2(k, FlightWorldScript.SIZE_KM))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
		a = world_to_screen(Vector2(0, k))
		b = world_to_screen(Vector2(FlightWorldScript.SIZE_KM, k))
		_draw_clipped_map_line(a, b, Color(0.25, 0.28, 0.22, 0.18), 1.0)
	for segment in contour_segments:
		var level: float = segment.level
		var color := Color("806f4b") if int(level) % 500 != 0 else Color("5c4b31")
		var width := 1.0 if int(level) % 500 != 0 else 1.7
		_draw_clipped_map_line(world_to_screen(segment.a), world_to_screen(segment.b), color, width)
	_draw_wind_overlay(rect)
	_draw_contour_labels(rect)
	_draw_terrain_peaks(rect)
	for airport in world.airports:
		_draw_airport(airport)
		_draw_approach_point(airport)
	for beacon in world.beacons:
		_draw_beacon(beacon)
	for line in measurement_lines:
		_draw_measurement(line.a, line.b, Color("254d9a"), line.get("max_height_m", -1.0))
	if pending_measure != null:
		_draw_measurement(pending_measure, _snap_map_point(get_local_mouse_position()), Color(0.1, 0.25, 0.7, 0.55))
	_draw_completed_flight_trajectory()
	_draw_economy_hud(map_canvas, false)
	_draw_hovered_airport_services(rect)
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 20), "НАВИГАЦИОННАЯ КАРТА", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("35372e"))
	map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 38), "Положение самолёта не отображается", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var wind_altitude_label: String
	if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size():
		wind_altitude_label = "текущая %.0f м" % flight.altitude_m
	elif wind_overlay_index == 0:
		wind_altitude_label = "у поверхности"
	else:
		wind_altitude_label = "%d м" % roundi(float(WIND_OVERLAY_ALTITUDES[wind_overlay_index]))
	var wind_hint := "V: ветер [%s]" % wind_altitude_label
	var map_hints := [
		"Изолинии: 250 м",
		wind_hint,
		"ЛКМ: точка/линия",
		"ЛКМ с движением: карта",
		"ПКМ: отмена/стереть",
		"Колесо: масштаб",
		"Ctrl+1/2: выбрать приёмник",
		"Цифры: частота • колесо над приёмником: 1 кГц, с Shift: 10 кГц",
	]
	for hint_index in map_hints.size():
		map_canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 57 + hint_index * 17), map_hints[hint_index], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("55574a"))
	var scale_km := 10.0
	var scale_px := scale_km * pixels_per_km()
	var scale_start := rect.end - Vector2(scale_px + 18, 18)
	map_canvas.draw_line(scale_start, scale_start + Vector2(scale_px, 0), Color("25271f"), 3)
	map_canvas.draw_string(ThemeDB.fallback_font, scale_start - Vector2(0, 6), "10 км", HORIZONTAL_ALIGNMENT_CENTER, scale_px, 12, Color("25271f"))

func _draw_hovered_airport_services(rect: Rect2) -> void:
	var mouse := get_local_mouse_position()
	if not rect.has_point(mouse):
		return
	var index := _airport_hover_index(mouse)
	if index >= 0:
		var airport: Dictionary = world.airports[index]
		var text := "%s: %s" % [airport.name, ", ".join(economy.services_at(index))]
		map_canvas.draw_rect(Rect2(rect.position.x + 8, rect.end.y - 47, minf(520.0, rect.size.x - 16), 25), Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 14, rect.end.y - 29), text, HORIZONTAL_ALIGNMENT_LEFT, minf(508.0, rect.size.x - 28), 12, Color("35372e"))

func _airport_hover_index(mouse: Vector2) -> int:
	if not map_rect().has_point(mouse):
		return -1
	for index in world.airports.size():
		var airport: Dictionary = world.airports[index]
		var center := world_to_screen(airport.position)
		var vector: Vector2 = world.heading_vector(airport.heading) * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
		var a := world_to_screen(airport.position - vector)
		var b := world_to_screen(airport.position + vector)
		var label_anchor: Vector2 = (a if a.y <= b.y else b) + Vector2(10, -21)
		var label_width := ThemeDB.fallback_font.get_string_size(String(airport.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 100.0
		if mouse.distance_to(center) <= 32.0 or Rect2(label_anchor, Vector2(label_width, 27)).has_point(mouse):
			return index
	return -1

func _draw_wind_overlay(rect: Rect2) -> void:
	var altitude_m: float = flight.altitude_m if wind_overlay_index == WIND_OVERLAY_ALTITUDES.size() else WIND_OVERLAY_ALTITUDES[wind_overlay_index]
	var wind: Vector2 = world.wind_at(altitude_m)
	if wind.length_squared() < 0.001:
		return
	var visible_min := screen_to_world(rect.position).clamp(Vector2.ZERO, Vector2.ONE * FlightWorldScript.SIZE_KM)
	var visible_max := screen_to_world(rect.end).clamp(Vector2.ZERO, Vector2.ONE * FlightWorldScript.SIZE_KM)
	var spacing_km := 16.0
	var start_x := ceilf(visible_min.x / spacing_km) * spacing_km
	var start_y := ceilf(visible_min.y / spacing_km) * spacing_km
	var arrow_length := remap(clampf(wind.length(), 0.0, 40.0), 0.0, 40.0, 12.0, 27.0)
	var direction := wind.normalized()
	var color := Color(0.10, 0.42, 0.48, 0.50)
	var arrow_altitude_label := "%d м" % roundi(altitude_m)
	var x := start_x
	while x <= visible_max.x:
		var y := start_y
		while y <= visible_max.y:
			var center := world_to_screen(Vector2(x, y))
			var half_vector := direction * arrow_length * 0.5
			var tip := center + half_vector
			var tail := center - half_vector
			_draw_clipped_map_line(tail, tip, color, 1.5)
			var backward := -direction
			_draw_clipped_map_line(tip, tip + backward.rotated(0.55) * 6.0, color, 1.5)
			_draw_clipped_map_line(tip, tip + backward.rotated(-0.55) * 6.0, color, 1.5)
			var label_position := center + Vector2(arrow_length * 0.5 + 7.0, 4.0)
			var label_width := rect.end.x - label_position.x - 4.0
			if label_width >= 30.0 and label_position.y >= rect.position.y + 10.0 and label_position.y <= rect.end.y - 3.0:
				map_canvas.draw_string(ThemeDB.fallback_font, label_position, arrow_altitude_label, HORIZONTAL_ALIGNMENT_LEFT, label_width, 9, Color(0.10, 0.36, 0.41, 0.62))
			y += spacing_km
		x += spacing_km

func _draw_completed_flight_trajectory() -> void:
	if not trajectory_finished or flight_trajectory.is_empty():
		return
	var path_color := Color("a83f38") if flight.state == FlightModelScript.State.CRASHED else Color("176f75")
	for point_index in range(1, flight_trajectory.size()):
		_draw_clipped_map_line(world_to_screen(flight_trajectory[point_index - 1].position), world_to_screen(flight_trajectory[point_index].position), path_color, 2.0)
	var aircraft_position := world_to_screen(flight.position_km)
	var safe_rect := map_rect().grow(-10.0)
	aircraft_position.x = clampf(aircraft_position.x, safe_rect.position.x, safe_rect.end.x)
	aircraft_position.y = clampf(aircraft_position.y, safe_rect.position.y, safe_rect.end.y)
	_draw_map_aircraft(aircraft_position, flight.heading_deg, path_color)

func _draw_map_aircraft(position: Vector2, heading_deg: float, color: Color) -> void:
	map_canvas.draw_set_transform(position, deg_to_rad(heading_deg), Vector2.ONE)
	# Compact top-down silhouette of a small single-engine high-wing aircraft:
	# straight wing and tailplane first, then the fuselage, cabin and propeller.
	var wing := PackedVector2Array([
		Vector2(-12, -3), Vector2(12, -3), Vector2(12, 2), Vector2(3, 2),
		Vector2(2, 3), Vector2(-2, 3), Vector2(-3, 2), Vector2(-12, 2),
	])
	var tailplane := PackedVector2Array([
		Vector2(-6, 7), Vector2(6, 7), Vector2(6, 10),
		Vector2(2, 9), Vector2(-2, 9), Vector2(-6, 10),
	])
	var fuselage := PackedVector2Array([
		Vector2(0, -11), Vector2(3, -8), Vector2(3, 4), Vector2(2, 10),
		Vector2(0, 12), Vector2(-2, 10), Vector2(-3, 4), Vector2(-3, -8),
	])
	for part in [wing, tailplane, fuselage]:
		map_canvas.draw_colored_polygon(part, Color("c8ced0"))
		var part_outline: PackedVector2Array = part.duplicate()
		part_outline.append(part[0])
		map_canvas.draw_polyline(part_outline, color, 1.5, true)
	var cabin := PackedVector2Array([
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

func _draw_terrain_peaks(rect: Rect2) -> void:
	var safe_rect := rect.grow(-18.0)
	for peak in terrain_peaks:
		var position := world_to_screen(peak.position)
		if safe_rect.has_point(position):
			_draw_clamped_map_text(position + Vector2(5.0, -5.0), "▲ %.0f м" % float(peak.height), 11, Color("4d3d29"))

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
	var upper_runway_end := a if a.y <= b.y else b
	_draw_clamped_map_text(upper_runway_end + Vector2(10, -9), "%s  %03d°/%03d°" % [airport.name, direct_course, reverse_course], 12, Color("20241f"))

func _draw_approach_point(airport: Dictionary) -> void:
	# Keep the overview map readable: detailed glide-path markings appear only
	# at the maximum zoom and the immediately preceding wheel-zoom level.
	if map_zoom < APPROACH_DETAIL_MIN_ZOOM:
		return
	for approach_sign in [1.0, -1.0]:
		_draw_approach_direction(airport, approach_sign)

func _draw_approach_direction(airport: Dictionary, approach_sign: float) -> void:
	var forward: Vector2 = world.heading_vector(airport.heading) * approach_sign
	var threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var touchdown_target: Vector2 = threshold + forward * FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM
	var approach_vertical_speed := -(92.0 / 3.6) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
	var markers_by_direction: Dictionary = airport.get("approach_markers", {})
	var markers: Array = markers_by_direction.get(str(int(approach_sign)), [])
	if markers.is_empty():
		return
	var farthest_distance_km: float = markers[-1].distance_km
	var farthest_position := threshold - forward * farthest_distance_km
	_draw_clipped_map_line(world_to_screen(farthest_position), world_to_screen(touchdown_target), Color("287777"), 1.5, true)
	for marker in markers:
		var distance_km: float = marker.distance_km
		var approach_position: Vector2 = threshold - forward * distance_km
		var point := world_to_screen(approach_position)
		if not map_rect().grow(-8.0).has_point(point):
			continue
		var diamond := PackedVector2Array([
			point + Vector2(0, -6), point + Vector2(6, 0),
			point + Vector2(0, 6), point + Vector2(-6, 0),
		])
		map_canvas.draw_colored_polygon(diamond, Color("d7d0ad"))
		map_canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("185f61"), 2.0)
		var desired_altitude: float = marker.altitude_m
		var label := "%.1f км • %.0f м • %.1f м/с" % [float(marker.distance_km), desired_altitude, approach_vertical_speed]
		var text_size := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		var label_position := point + Vector2(12.0, 4.0)
		label_position.x = clampf(label_position.x, map_rect().position.x + 4.0, map_rect().end.x - text_size.x - 4.0)
		label_position.y = clampf(label_position.y, map_rect().position.y + text_size.y + 2.0, map_rect().end.y - 4.0)
		map_canvas.draw_rect(Rect2(label_position + Vector2(-3, -11), text_size + Vector2(6, 3)), Color("d7d0ad"), true)
		map_canvas.draw_string(ThemeDB.fallback_font, label_position, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("185f61"))

func _build_approach_markers() -> void:
	for airport in world.airports:
		var markers_by_direction: Dictionary = {}
		for approach_sign in [1.0, -1.0]:
			var markers: Array[Dictionary] = []
			for distance_km in range(4, 21, 4):
				var distance: float = float(distance_km)
				if not _approach_path_is_clear(airport, distance, approach_sign):
					continue
				var altitude_m := (distance * 1000.0 + FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM * 1000.0) * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
				markers.append({"distance_km": distance, "altitude_m": altitude_m})
			markers_by_direction[str(int(approach_sign))] = markers
		airport.approach_markers = markers_by_direction

func _approach_path_is_clear(airport: Dictionary, start_distance_km: float, approach_sign: float) -> bool:
	var forward: Vector2 = world.heading_vector(airport.heading) * approach_sign
	var threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var sample_count := maxi(1, ceili(start_distance_km / 0.10))
	for sample_index in sample_count + 1:
		var distance_km := start_distance_km * sample_index / float(sample_count)
		var position := threshold - forward * distance_km
		var glide_altitude_m := (distance_km + FlightModelScript.GLIDE_TOUCHDOWN_OFFSET_KM) * 1000.0 * tan(deg_to_rad(FlightModelScript.GLIDE_SLOPE_DEG))
		if world.height_at(position) >= glide_altitude_m:
			return false
	return true

func _draw_beacon(beacon: Dictionary) -> void:
	var p := world_to_screen(beacon.position)
	if not map_rect().grow(-8.0).has_point(p):
		return
	var radius := 5.0
	var points := PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius, radius), p + Vector2(-radius, radius)])
	map_canvas.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color("972d25"), 2.0)
	_draw_clamped_map_text(p + Vector2(11, 4), "%s %.0f кГц R%.0f" % [beacon.name, beacon.frequency, beacon.range_km], 11, Color("76231d"))

func _draw_measurement(a_world: Vector2, b_world: Vector2, color := Color("254d9a"), cached_max_height := -1.0) -> void:
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
	var max_height: float = cached_max_height if cached_max_height >= 0.0 else _maximum_terrain_height_on_line(a_world, b_world)
	var label := "%.1f км  %03d° / %03d°  %.0f м" % [distance, direct_course, reverse_course, max_height]
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
	if flight.engine_running:
		_draw_speedometer(speed_center, INSTRUMENT_RADIUS)
		if flight.wheel_brakes_applied:
			draw_string(ThemeDB.fallback_font, speed_center + Vector2(-INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 34), "ТОРМОЗ", HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2.0, 11, Color("ef645e"))
		_draw_round_gauge(_instrument_center(1, gauge_y), INSTRUMENT_RADIUS, "ВЫСОТА", "%.0f" % flight.altitude_m, "м", flight.altitude_m / 5000.0)
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
	var status_text: String = "ПАУЗА" if simulation_paused else flight.message
	var state_color: Color = Color("e8d274") if simulation_paused else (Color("65d48c") if flight.state == FlightModelScript.State.LANDED else (Color("ef645e") if flight.state == FlightModelScript.State.CRASHED else Color("e8d274")))
	if not simulation_paused and flight.state == FlightModelScript.State.FLYING and flight.stalled:
		status_text = "СВАЛИВАНИЕ — ОТДАТЬ ШТУРВАЛ ОТ СЕБЯ"
		state_color = Color("ef645e")
	elif not simulation_paused and flight.stall_warning_active():
		status_text = "ПРЕДУПРЕЖДЕНИЕ: БОЛЬШОЙ УГОЛ АТАКИ"
		state_color = Color("e8d274")
	elif not simulation_paused and flight.state == FlightModelScript.State.FLYING and flight.vne_exceeded():
		status_text = "ПРЕВЫШЕНА VNE — УМЕНЬШИТЬ СКОРОСТЬ"
		state_color = Color("ef645e")
	elif not simulation_paused and flight.state == FlightModelScript.State.FLYING and flight.overspeed_warning_active():
		status_text = "ВЫСОКАЯ СКОРОСТЬ — ИЗБЕГАТЬ РЕЗКИХ МАНЁВРОВ"
		state_color = Color("e8d274")
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, rect.size.y - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 330, 15, state_color)
	draw_string(ThemeDB.fallback_font, Vector2(rect.end.x - 470, rect.end.y - 10), "W/S: газ  •  стрелки: штурвал  •  Esc: меню", HORIZONTAL_ALIGNMENT_RIGHT, 446, 12, Color("aebbc1"))

func _draw_radio_altimeter(center: Vector2) -> void:
	var height_m: float = flight.radio_height_m()
	var label := "РВ %.0f м" % height_m if height_m >= 0.0 else "РВ —"
	draw_string(ThemeDB.fallback_font, center + Vector2(-INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 34), label, HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2.0, 11, Color("73d6d0"))

func _draw_unpowered_instruments(gauge_y: float) -> void:
	# Pitot/static instruments and the independent clock remain available.
	_draw_speedometer(_instrument_center(0,gauge_y),INSTRUMENT_RADIUS)
	_draw_round_gauge(_instrument_center(1,gauge_y),INSTRUMENT_RADIUS,"ВЫСОТА","%.0f" % flight.altitude_m,"м",flight.altitude_m/5000.0)
	_draw_variometer(_instrument_center(2,gauge_y),INSTRUMENT_RADIUS)
	var titles := ["СКОРОСТЬ", "ВЫСОТА", "ВАРИОМЕТР", "КОМПАС", "АВИАГОРИЗОНТ", "ПРИЁМНИК 1", "ПРИЁМНИК 2", "ЧАСЫ", "ТОПЛИВО"]
	for index in range(3,titles.size()):
		if index == 7:
			_draw_clock(_instrument_center(index, gauge_y), INSTRUMENT_RADIUS)
			continue
		var center := _instrument_center(index, gauge_y)
		draw_circle(center, INSTRUMENT_RADIUS, Color("0a0e10"))
		draw_arc(center, INSTRUMENT_RADIUS - 2, 0, TAU, 48, Color("7d8b91"), 2)
		draw_string(ThemeDB.fallback_font, center - Vector2(INSTRUMENT_RADIUS, INSTRUMENT_RADIUS + 10.0), titles[index], HORIZONTAL_ALIGNMENT_CENTER, INSTRUMENT_RADIUS * 2, 11, Color("b8c5c8"))
	_draw_unpowered_display(get_ils_rect(), "ILS")
	var radar_rect := get_weather_radar_rect()
	if radar_rect.size.x >= 150.0:
		if large_weather_radar:
			WeatherRadarArt.draw_map_button(self,radar_rect)
		else:
			_draw_unpowered_display(radar_rect, "МЕТЕОРАДАР [B]")

func _draw_unpowered_display(rect: Rect2, title: String) -> void:
	draw_rect(rect, Color("0a0e10"), true)
	draw_rect(rect, Color("6f7f85"), false, 1.5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 12), title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 10, Color("b8c5c8"))

func _draw_weather_radar() -> void:
	var rect := get_weather_radar_rect()
	if rect.size.x < 150.0:
		return
	if large_weather_radar:
		WeatherRadarArt.draw_map_button(self,rect)
		return
	draw_rect(rect, Color("071012"), true)
	draw_rect(rect, Color("6f7f85"), false, 1.5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(6, 12), "МЕТЕОРАДАР 30 км [B]", HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 9, Color("b8c5c8"))
	var center := rect.position + Vector2(37, 41)
	var radius := 23.0
	draw_arc(center, radius, 0, TAU, 40, Color("557176"), 1.0)
	draw_arc(center, radius * 0.5, 0, TAU, 32, Color(0.35, 0.48, 0.50, 0.55), 1.0)
	draw_line(center, center + Vector2(0, -radius), Color("8ca1a4"), 1.0)
	draw_circle(center, 2.0, Color("d7c65c"))
	WeatherRadarArt.draw_echoes(self,world,flight,center,radius)
	for line in radar_measurement_lines:
		_draw_radar_measurement(self, line.a, line.b, Color("e8d274"), center, radius)
	var info_x := rect.position.x + 68.0
	var danger_color := Color("ef645e") if flight.storm_intensity > 0.65 else Color("e8d274")
	if flight.storm_intensity > 0.05:
		draw_string(ThemeDB.fallback_font, Vector2(info_x, rect.position.y + 42), "ТУРБУЛЕНТНОСТЬ", HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - info_x - 4, 9, danger_color)

func _instrument_center(index: int, gauge_y: float) -> Vector2:
	var step := INSTRUMENT_RADIUS * 2.0 + INSTRUMENT_GAP
	return Vector2(panel_rect().position.x + INSTRUMENT_RADIUS + 5.0 + index * step, gauge_y)

func _draw_speedometer(center: Vector2, radius: float) -> void:
	var start_angle := -PI * 0.75
	var end_angle := PI * 0.75
	var speed_to_angle := func(value: float) -> float:
		return lerpf(start_angle, end_angle, clampf(value / 300.0, 0.0, 1.0))
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	# As on a conventional airspeed indicator, the lower edge of the green arc
	# marks the nominal clean-configuration stall speed; the unmarked sector
	# below it is not a normal operating range.
	draw_arc(center, radius - 5, speed_to_angle.call(FlightModelScript.NOMINAL_STALL_SPEED_KMH), speed_to_angle.call(FlightModelScript.VNO_KMH), 28, Color("65d48c"), 3.0)
	draw_arc(center, radius - 5, speed_to_angle.call(FlightModelScript.VNO_KMH), speed_to_angle.call(FlightModelScript.VNE_KMH), 10, Color("e8d274"), 3.0)
	var red_angle: float = speed_to_angle.call(FlightModelScript.VNE_KMH)
	var red_outer := center + Vector2(cos(red_angle), sin(red_angle)) * (radius - 4)
	var red_inner := center + Vector2(cos(red_angle), sin(red_angle)) * (radius - 14)
	draw_line(red_inner, red_outer, Color("ef645e"), 3.0)
	var rotation_angle: float = speed_to_angle.call(FlightModelScript.RECOMMENDED_ROTATION_SPEED_KMH)
	var rotation_direction := Vector2(cos(rotation_angle), sin(rotation_angle))
	draw_line(center + rotation_direction * (radius - 16), center + rotation_direction * (radius - 4), Color("73d6d0"), 2.5)
	var rotation_label_position := center + rotation_direction * (radius - 25) - Vector2(9.0, -3.0)
	draw_string(ThemeDB.fallback_font, rotation_label_position, "VR", HORIZONTAL_ALIGNMENT_CENTER, 18.0, 8, Color("73d6d0"))
	# With the current simplified climb polar, best angle and best rate of climb
	# coincide at about 130 km/h. Keep one honest combined mark until the flight
	# model has distinct Vx and Vy optima.
	var climb_angle: float = speed_to_angle.call(FlightModelScript.VX_KMH)
	var climb_direction := Vector2(cos(climb_angle), sin(climb_angle))
	draw_line(center + climb_direction * (radius - 16), center + climb_direction * (radius - 4), Color("65d48c"), 2.5)
	var climb_label_position := center + climb_direction * (radius - 27) - Vector2(15.0, -3.0)
	draw_string(ThemeDB.fallback_font, climb_label_position, "VX/VY", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 7, Color("65d48c"))
	for i in 11:
		var angle: float = lerpf(start_angle, end_angle, i / 10.0)
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius - 7)
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 12)
		draw_line(inner, outer, Color("d2dde0"), 1)
	var needle_angle: float = speed_to_angle.call(flight.speed_kmh)
	draw_line(center, center + Vector2(cos(needle_angle), sin(needle_angle)) * (radius - 15), Color("ed775f"), 2)
	draw_circle(center, 3, Color("d8dfe0"))
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "СКОРОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, Color("b8c5c8"))
	var value_color := Color("ef645e") if flight.speed_kmh > FlightModelScript.VNE_KMH else (Color("e8d274") if flight.speed_kmh > FlightModelScript.VNO_KMH else Color.WHITE)
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "%.0f км/ч" % flight.speed_kmh, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 14, value_color)

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

func _draw_clock(center: Vector2, radius: float, beige: bool = false) -> void:
	var whole_seconds := int(clock_seconds)
	var hours: int = whole_seconds / 3600
	var minutes: int = (whole_seconds % 3600) / 60
	var seconds: int = whole_seconds % 60
	var ink := AircraftArt.INK if beige else Color("edf2f2")
	draw_circle(center, radius, AircraftArt.PAPER if beige else Color("0a0e10"))
	draw_arc(center, radius - 1, 0, TAU, 40, AircraftArt.INK if beige else Color("7d8b91"), 2)
	for hour_mark in 12:
		var mark_angle := deg_to_rad(hour_mark * 30.0 - 90.0)
		var outer := center + Vector2(cos(mark_angle), sin(mark_angle)) * (radius - 6.0)
		var inner_radius := radius - (15.0 if hour_mark % 3 == 0 else 11.0)
		var inner := center + Vector2(cos(mark_angle), sin(mark_angle)) * inner_radius
		draw_line(inner, outer, AircraftArt.INK if beige else Color("d2dde0"), 1.5)
	var hour_angle := deg_to_rad(fmod(hours, 12) * 30.0 + minutes * 0.5 - 90.0)
	var minute_angle := deg_to_rad(minutes * 6.0 + seconds * 0.1 - 90.0)
	var second_angle := deg_to_rad(seconds * 6.0 - 90.0)
	draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * (radius * 0.48), ink, 3.0, true)
	draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * (radius * 0.68), ink, 2.0, true)
	draw_line(center, center + Vector2(cos(second_angle), sin(second_angle)) * (radius * 0.73), AircraftArt.LIGHT if beige else Color("ed775f"), 1.0, true)
	draw_circle(center, 2.5, ink)
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ЧАСЫ", HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, AircraftArt.INK if beige else Color("b8c5c8"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 14), "%02d:%02d:%02d" % [hours, minutes, seconds], HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 10, AircraftArt.INK if beige else Color.WHITE)
	if beige:
		return
	var trip_whole_seconds := int(trip_elapsed_seconds)
	var trip_minutes: int = trip_whole_seconds / 60
	var trip_seconds: int = trip_whole_seconds % 60
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 8.0, radius + 29), "ПУТЬ %.1f км • %02d:%02d" % [trip_air_distance_km, trip_minutes, trip_seconds], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 16.0, 10, Color("73d6d0"))
	var reset_button := get_trip_reset_button_rect()
	draw_rect(reset_button, Color("334b55"), true)
	draw_rect(reset_button, Color("82979f"), false, 1.0)
	draw_string(ThemeDB.fallback_font, reset_button.position + Vector2(0.0, 13.0), "СБРОС [T]", HORIZONTAL_ALIGNMENT_CENTER, reset_button.size.x, 8, Color.WHITE)

func _draw_time_controls(beige: bool = false) -> void:
	var speed_rect := get_time_scale_button_rect(beige)
	var reset_rect := get_time_reset_button_rect(beige)
	var fill := AircraftArt.PAPER if beige else Color("334b55")
	var border := AircraftArt.INK if beige else Color("82979f")
	var ink := AircraftArt.INK if beige else Color.WHITE
	for button_rect in [speed_rect, reset_rect]:
		draw_rect(button_rect, fill, true)
		draw_rect(button_rect, border, false, 1.0)
	draw_string(ThemeDB.fallback_font, speed_rect.position + Vector2(0.0, 14.0), "ВРЕМЯ %d× [Z]" % roundi(TIME_SCALES[time_scale_index]), HORIZONTAL_ALIGNMENT_CENTER, speed_rect.size.x, 9, ink)
	draw_string(ThemeDB.fallback_font, reset_rect.position + Vector2(0.0, 14.0), "1× [⇧Z]", HORIZONTAL_ALIGNMENT_CENTER, reset_rect.size.x, 9, ink)

func _draw_fuel_instrument(center: Vector2, radius: float) -> void:
	var flow: float = flight.fuel_flow_lpm()
	var estimated_range: float = flight.estimated_range_km()
	var max_flow := 0.95
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
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), "Расход %.2f л/мин" % flow, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color("6fc78c"))
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 7.0, radius + 29), "%.1f/%.0f л • запас %.0f км" % [flight.fuel_l, flight.fuel_capacity_l, estimated_range], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 14.0, 10, Color.WHITE)

func _draw_ils() -> void:
	var rect := get_ils_rect()
	var guidance: Dictionary = flight.landing_guidance(ils_airport_index, ils_signal_status.get("available", false))
	draw_rect(rect, Color("0a0e10"), true)
	draw_rect(rect, Color("6f7f85"), false, 1.5)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 12), _ils_title(), HORIZONTAL_ALIGNMENT_LEFT, 200, 10, Color("b8c5c8"))
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
	var desired_vs: float = guidance.desired_vertical_speed_mps
	var altitude_color := _ils_parameter_color(absf(guidance.glide_error), true)
	var vertical_speed_color := _ils_parameter_color(absf(flight.vertical_speed_mps - desired_vs) / 0.35, true)
	var course_error_color := _ils_parameter_color(absf(guidance.course_error_deg), true, 1.0, 5.0)
	var approach_speed_color := Color("65d48c")
	if flight.speed_kmh > 115.0:
		approach_speed_color = Color("ef645e")
	elif flight.speed_kmh > 100.0:
		approach_speed_color = Color("e8d274")
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 22), "H %.1f м" % flight.altitude_m, HORIZONTAL_ALIGNMENT_LEFT, 76, 12, altitude_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(292, 22), "VS %+.2f м/с" % flight.vertical_speed_mps, HORIZONTAL_ALIGNMENT_LEFT, 105, 12, vertical_speed_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(399, 22), "V %.1f км/ч" % flight.speed_kmh, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 407, 11, approach_speed_color)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(216, 42), "ОТКЛ. ПУТИ %+.1f°" % guidance.course_error_deg, HORIZONTAL_ALIGNMENT_LEFT, 132, 12, course_error_color)
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
	# runway_coordinates() uses a cross-runway axis whose positive side appears
	# left to the pilot on the supported approach. Invert it for the aircraft
	# symbol: if the moving line is left of the airport, steering right must move
	# it back towards the fixed centre, and vice versa.
	var localizer_x: float = center.x - clampf(guidance.localizer_error, -1.4, 1.4) * display.size.x * 0.30
	var glide_y: float = center.y - clampf(guidance.glide_error, -1.4, 1.4) * display.size.y * 0.30
	var localizer_severity: float = absf(guidance.localizer_error)
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
	var aoa_color := Color("65d48c")
	if flight.stalled or flight.angle_of_attack_deg >= FlightModelScript.STALL_AOA_DEG:
		aoa_color = Color("ef645e")
	elif flight.angle_of_attack_deg >= FlightModelScript.STALL_WARNING_AOA_DEG:
		aoa_color = Color("e8d274")
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 17), "УА %+.1f°" % flight.angle_of_attack_deg, HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 12, aoa_color)

func _draw_beacon_instrument(center: Vector2, radius: float, instrument: int) -> void:
	var signal_status: Dictionary = receiver_signal_status[instrument]
	var beacon: Variant = signal_status.get("beacon", null)
	var signal_available: bool = signal_status.get("available", false)
	draw_circle(center, radius, Color("0a0e10"))
	draw_arc(center, radius - 2, 0, TAU, 48, Color("7d8b91"), 2)
	if active_receiver == instrument:
		draw_arc(center, radius + 2, 0, TAU, 48, Color("73d6d0"), 1.5)
	# External tuning index: the complete circumference represents 0--999 kHz,
	# starting at the top and increasing clockwise.
	var frequency_angle := -PI * 0.5 + TAU * float(receiver_frequencies[instrument]) / 999.0
	var frequency_direction := Vector2(cos(frequency_angle), sin(frequency_angle))
	var frequency_side := Vector2(-frequency_direction.y, frequency_direction.x)
	var marker_tip := center + frequency_direction * (radius + 1.0)
	var marker_base := center + frequency_direction * (radius + 8.0)
	var marker_color := Color("73d6d0") if active_receiver == instrument else Color("d2dde0")
	draw_colored_polygon(PackedVector2Array([
		marker_tip,
		marker_base + frequency_side * 3.0,
		marker_base - frequency_side * 3.0,
	]), marker_color)
	# North-up receiver: the arrow shows absolute map bearing, independent of heading.
	if signal_available:
		var delta: Vector2 = beacon.position - flight.position_km
		var absolute_bearing: float = world.vector_heading(delta)
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
	else:
		draw_line(center + Vector2(-12, -12), center + Vector2(12, 12), Color("c95d55"), 2.0)
		draw_line(center + Vector2(12, -12), center + Vector2(-12, 12), Color("c95d55"), 2.0)
	var title_color := Color("73d6d0") if active_receiver == instrument else Color("b8c5c8")
	draw_string(ThemeDB.fallback_font, center - Vector2(radius, radius + 10.0), "ПРИЁМНИК %d" % (instrument + 1), HORIZONTAL_ALIGNMENT_CENTER, radius * 2, 11, title_color)
	var frequency_text := "%03d кГц" % int(receiver_frequencies[instrument])
	if active_receiver == instrument and not receiver_frequency_entry.is_empty():
		frequency_text = "%s кГц" % receiver_frequency_entry.rpad(3, "_")
	draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 5.0, radius + 14), frequency_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 10.0, 10, Color.WHITE)
	if signal_available:
		var delta: Vector2 = beacon.position - flight.position_km
		var absolute_bearing: float = world.vector_heading(delta)
		var direct_course := int(round(absolute_bearing)) % 360
		var reverse_course := (direct_course + 180) % 360
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), "%.1f км  %03d°/%03d°" % [delta.length(), direct_course, reverse_course], HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 10, Color("73d6d0"))
	else:
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 9.0, radius + 29), signal_status.get("reason", "НЕТ СИГНАЛА"), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 18.0, 10, Color("c95d55"))

func _update_receiver_signals() -> void:
	if world == null or flight == null:
		return
	for instrument in 2:
		var beacon: Variant = _beacon_for_frequency(int(receiver_frequencies[instrument]))
		if beacon == null:
			receiver_signal_status[instrument] = {"available": false, "reason": "НЕТ СИГНАЛА", "beacon": null}
		else:
			var status: Dictionary = world.beacon_signal(beacon, flight.position_km, flight.altitude_m)
			status.beacon = beacon
			receiver_signal_status[instrument] = status
	# ILS follows receiver 1. A runway frequency selects its airport; both the
	# receiver signal and the runway's forward cone must be available.
	var selected_airport := _selected_ils_airport_index()
	if selected_airport < 0:
		ils_signal_status = {"available": false, "reason": "НЕТ СИГНАЛА", "airport_index": -1}
	else:
		ils_airport_index = selected_airport
		ils_signal_status = world.ils_signal(selected_airport, flight.position_km, flight.altitude_m, flight.heading_deg)
		ils_signal_status.available = bool(ils_signal_status.get("available", false)) and bool(receiver_signal_status[0].get("available", false))
		ils_signal_status.airport_index = selected_airport
		if not ils_signal_status.available:
			ils_signal_status.reason = "НЕТ СИГНАЛА"

func _selected_ils_airport_index() -> int:
	var beacon: Variant = _beacon_for_frequency(int(receiver_frequencies[0]))
	if beacon == null:
		return -1
	var runway_index := int(beacon.get("runway", -1))
	return runway_index if runway_index >= 0 and runway_index < world.airports.size() else -1

func _ils_title() -> String:
	return "ILS %03d кГц" % int(receiver_frequencies[0])

func _beacon_for_frequency(frequency_khz: int) -> Variant:
	for beacon in world.beacons:
		if roundi(float(beacon.frequency)) == frequency_khz:
			return beacon
	return null

func _update_ils_touchdown_prediction() -> void:
	if flight == null:
		return
	if _selected_ils_airport_index() < 0:
		ils_touchdown_prediction = {"valid": false, "distance_from_threshold_km": 0.0}
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
	draw_string(ThemeDB.fallback_font, center_button.position + Vector2(0, 17), "ЦЕНТР [C]", HORIZONTAL_ALIGNMENT_CENTER, center_button.size.x, 10, Color.WHITE)
	var engine_button := get_engine_button_rect()
	draw_rect(engine_button, Color("334b55"), true)
	draw_rect(engine_button, Color("82979f"), false, 1)
	var engine_color := Color("65d48c") if flight.engine_running else Color("c95d55")
	draw_circle(engine_button.position + Vector2(13, engine_button.size.y * 0.5), 4.5, engine_color)
	draw_string(ThemeDB.fallback_font, engine_button.position + Vector2(22, 19), ("ОСТАНОВИТЬ ДВИГАТЕЛЬ [M]" if flight.engine_running else "ЗАПУСТИТЬ ДВИГАТЕЛЬ [M]"), HORIZONTAL_ALIGNMENT_CENTER, engine_button.size.x - 27, 10, Color.WHITE)
	var cabin_button := get_cabin_button_rect()
	draw_rect(cabin_button, Color("334b55"), true)
	draw_rect(cabin_button, Color("82979f"), false, 1)
	draw_string(ThemeDB.fallback_font, cabin_button.position + Vector2(0, 19), "ВЫЙТИ В САЛОН [X]", HORIZONTAL_ALIGNMENT_CENTER, cabin_button.size.x, 10, Color.WHITE)
	_draw_time_controls(false)

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

func get_engine_button_rect() -> Rect2:
	return get_action_button_rect()

func get_cabin_button_rect() -> Rect2:
	var ils_rect := get_ils_rect()
	var engine_rect := get_engine_button_rect()
	var left := ils_rect.end.x + 8.0
	return Rect2(left, engine_rect.position.y, maxf(110.0, engine_rect.position.x - left - 8.0), engine_rect.size.y)

func get_center_yoke_button_rect() -> Rect2:
	var yoke_rect := get_yoke_rect()
	return Rect2(yoke_rect.get_center().x - 41.5, yoke_rect.end.y + 7, 83, 24)

func get_trip_reset_button_rect() -> Rect2:
	var rect := panel_rect()
	var clock_center := _instrument_center(7, rect.position.y + 108.0)
	return Rect2(clock_center.x - 27.0, clock_center.y - INSTRUMENT_RADIUS - 42.0, 54.0, 18.0)

func get_time_scale_button_rect(beige: bool = false) -> Rect2:
	if beige:
		return Rect2(48.0, 229.0, 93.0, 20.0)
	var trip_rect := get_trip_reset_button_rect()
	return Rect2(trip_rect.position.x - 76.0, trip_rect.position.y, 72.0, 18.0)

func get_time_reset_button_rect(beige: bool = false) -> Rect2:
	if beige:
		return Rect2(145.0, 229.0, 57.0, 20.0)
	var trip_rect := get_trip_reset_button_rect()
	return Rect2(trip_rect.end.x + 4.0, trip_rect.position.y, 48.0, 18.0)

func get_ils_rect() -> Rect2:
	var rect := panel_rect()
	return Rect2(rect.get_center().x - 242.5, rect.end.y - 82.0, 485, 68)

func get_weather_radar_rect() -> Rect2:
	var rect := panel_rect()
	var ils_rect := get_ils_rect()
	var available_width := maxf(0.0, ils_rect.position.x - rect.position.x - 16.0)
	var radar_width := minf(184.0, available_width)
	return Rect2(ils_rect.position.x - radar_width - 8.0, rect.end.y - 82.0, radar_width, 68.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if flight.state == FlightModelScript.State.CRASHED and (view_mode != ViewMode.COCKPIT or not map_rect().has_point(event.position)):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if get_time_scale_button_rect(view_mode != ViewMode.COCKPIT).has_point(event.position):
			_cycle_time_scale()
			return
		if get_time_reset_button_rect(view_mode != ViewMode.COCKPIT).has_point(event.position):
			_reset_time_scale()
			return
	if event.pressed:
		_reset_time_scale_for_action()
	if event.button_index == MOUSE_BUTTON_LEFT and _fuel_slider_is_active():
		var slider_origin: Vector2 = _active_fuel_slider_origin()
		if event.pressed and _fuel_slider_rect(slider_origin).has_point(event.position):
			dragging_fuel_slider = true
			_set_fuel_amount_from_mouse(event.position, slider_origin)
			scene_notice = ""
			queue_redraw()
			return
		if not event.pressed and dragging_fuel_slider:
			_set_fuel_amount_from_mouse(event.position, slider_origin, true)
			dragging_fuel_slider = false
			queue_redraw()
			return
	if view_mode == ViewMode.CABIN and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and _can_view_cabin_terrain():
			cabin_terrain_zoom = mini(3, cabin_terrain_zoom + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cabin_terrain_zoom = maxi(0, cabin_terrain_zoom - 1)
		if cabin_terrain_zoom > 0:
			_update_cabin_terrain_profile()
		queue_redraw()
		return
	if view_mode == ViewMode.OPERATIONS:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if get_building_exit_rect().has_point(event.position):
				_leave_current_scene()
			elif get_operations_runway_rect(false).has_point(event.position):
				_pay_and_prepare(false)
			elif get_operations_runway_rect(true).has_point(event.position):
				_pay_and_prepare(true)
			queue_redraw()
		return
	if view_mode in [ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL]:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_economy_click(event.position)
			queue_redraw()
		return
	if view_mode != ViewMode.COCKPIT:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if view_mode == ViewMode.CABIN and _handle_inventory_click(event.position):
				queue_redraw()
				return
			_click_side_scene(event.position)
		return
	var mrect := map_rect()
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and get_weather_radar_rect().has_point(event.position):
		_toggle_weather_radar()
		return
	if large_weather_radar and (mrect.has_point(event.position) or map_drag_candidate or point_drag_candidate or dragging_measure_point):
		_handle_radar_mouse_button(event)
		return
	var hovered_receiver := _receiver_at_point(event.position)
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and hovered_receiver >= 0:
		active_receiver = hovered_receiver
		receiver_frequency_entry = ""
		var wheel_direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
		_tune_receiver_frequency(hovered_receiver, wheel_direction * (10 if event.shift_pressed else 1))
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and mrect.has_point(event.position):
		_zoom_at(event.position, 1.18)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and mrect.has_point(event.position):
		_zoom_at(event.position, 1.0 / 1.18)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			map_drag_candidate = false
			point_drag_candidate = false
			if get_trip_reset_button_rect().has_point(event.position):
				_reset_trip_counter()
			elif get_throttle_rect().has_point(event.position):
				dragging_throttle = true
				_update_throttle(event.position)
			elif get_yoke_rect().has_point(event.position):
				dragging_yoke = true
				_update_yoke(event.position)
			elif get_center_yoke_button_rect().has_point(event.position):
				flight.yoke = Vector2.ZERO
			elif get_engine_button_rect().has_point(event.position):
				flight.toggle_engine()
				_queue_map_redraw()
			elif get_cabin_button_rect().has_point(event.position):
				_enter_cabin()
			elif _beacon_receiver_hit(event.position, 0):
				active_receiver = 0
				receiver_frequency_entry = ""
			elif _beacon_receiver_hit(event.position, 1):
				active_receiver = 1
				receiver_frequency_entry = ""
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
				_refresh_measurement_max_heights(dragged_measure_connections)
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
	if flight.state == FlightModelScript.State.CRASHED and view_mode != ViewMode.COCKPIT:
		return
	if dragging_fuel_slider and _fuel_slider_is_active():
		_set_fuel_amount_from_mouse(event.position, _active_fuel_slider_origin(), true)
		scene_notice = ""
		queue_redraw()
		return
	if view_mode != ViewMode.COCKPIT:
		queue_redraw()
		return
	var next_hovered_airport := _airport_hover_index(event.position) if not large_weather_radar else -1
	if next_hovered_airport != hovered_airport_index:
		hovered_airport_index = next_hovered_airport
		_queue_map_redraw()
	if point_drag_candidate and not dragging_measure_point and event.position.distance_to(map_press_position) >= 4.0:
		dragging_measure_point = true
	if dragging_measure_point:
		var clamped_screen := _clamp_measurement_screen(event.position)
		var new_world := _measurement_from_screen(clamped_screen)
		new_world.x = clampf(new_world.x, 0.0, FlightWorldScript.SIZE_KM)
		new_world.y = clampf(new_world.y, 0.0, FlightWorldScript.SIZE_KM)
		for connection in dragged_measure_connections:
			active_measurement_lines[connection.line_index][connection.endpoint] = new_world
		_refresh_measurement_max_heights(dragged_measure_connections)
		_queue_map_redraw()
		queue_redraw()
		return
	if map_drag_candidate and not dragging_map and event.position.distance_to(map_press_position) >= 6.0:
		if large_weather_radar:
			map_drag_candidate = false
		else:
			dragging_map = true
	if dragging_map:
		map_center -= event.relative / pixels_per_km()
		_clamp_map_center()
		_queue_map_redraw()
	if dragging_yoke:
		_update_yoke(event.position)
	if dragging_throttle:
		_update_throttle(event.position)
	if active_pending_measure != null:
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

func _receiver_at_point(point: Vector2) -> int:
	for receiver in 2:
		if _beacon_receiver_hit(point, receiver):
			return receiver
	return -1

func _tune_receiver_frequency(receiver: int, delta_khz: int) -> void:
	receiver_frequencies[receiver] = clampi(int(receiver_frequencies[receiver]) + delta_khz, 190, 535)
	_update_receiver_signals()

func _enter_receiver_frequency_digit(digit: String) -> void:
	if receiver_frequency_entry.length() >= 3:
		receiver_frequency_entry = ""
	receiver_frequency_entry += digit
	if receiver_frequency_entry.length() == 3:
		_commit_receiver_frequency_entry()

func _commit_receiver_frequency_entry() -> void:
	if active_receiver < 0 or receiver_frequency_entry.is_empty():
		return
	var entered_frequency := int(receiver_frequency_entry)
	if entered_frequency >= 190 and entered_frequency <= 535:
		receiver_frequencies[active_receiver] = entered_frequency
	receiver_frequency_entry = ""
	_update_receiver_signals()

func _zoom_at(mouse: Vector2, factor: float) -> void:
	var before := screen_to_world(mouse)
	map_zoom = clamp(map_zoom * factor, _minimum_map_zoom(), MAX_MAP_ZOOM)
	var after := screen_to_world(mouse)
	map_center += before - after
	_clamp_map_center()

func _on_viewport_resized() -> void:
	_normalize_map_camera()
	_queue_map_redraw()

func _normalize_map_camera() -> void:
	map_zoom = clampf(maxf(map_zoom, _minimum_map_zoom()), _minimum_map_zoom(), MAX_MAP_ZOOM)
	_clamp_map_center()

func _minimum_map_zoom() -> float:
	var rect_size := map_rect().size
	var shorter_side := maxf(1.0, minf(rect_size.x, rect_size.y))
	# The world must cover both axes of the viewport. On a wide display this
	# crops its top and bottom at maximum zoom-out instead of exposing side gaps.
	return maxf(rect_size.x, rect_size.y) / shorter_side

func _initial_map_zoom(center: Vector2) -> float:
	var rect_size := map_rect().size
	var base_scale := _base_pixels_per_km()
	var zoom := maxf(_minimum_map_zoom(), maxf(rect_size.x, rect_size.y) / (INITIAL_MAP_RADIUS_KM * 2.0 * base_scale))
	# Keep the departure airport exactly centred. Airports near a world edge need
	# a closer view so no area outside the chart becomes visible.
	var edge_x := maxf(0.01, minf(center.x, FlightWorldScript.SIZE_KM - center.x))
	var edge_y := maxf(0.01, minf(center.y, FlightWorldScript.SIZE_KM - center.y))
	zoom = maxf(zoom, rect_size.x / (edge_x * 2.0 * base_scale))
	zoom = maxf(zoom, rect_size.y / (edge_y * 2.0 * base_scale))
	return clampf(zoom, _minimum_map_zoom(), MAX_MAP_ZOOM)

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
	return _base_pixels_per_km() * map_zoom

func _base_pixels_per_km() -> float:
	return min(map_rect().size.x, map_rect().size.y) / FlightWorldScript.SIZE_KM

func world_to_screen(point: Vector2) -> Vector2:
	return map_rect().get_center() + (point - map_center) * pixels_per_km()

func screen_to_world(point: Vector2) -> Vector2:
	return map_center + (point - map_rect().get_center()) / pixels_per_km()

func _erase_nearest_measurement(mouse: Vector2) -> void:
	var closest := -1
	var closest_distance := 18.0
	for i in active_measurement_lines.size():
		var a := _measurement_to_screen(active_measurement_lines[i].a)
		var b := _measurement_to_screen(active_measurement_lines[i].b)
		var nearest := Geometry2D.get_closest_point_to_segment(mouse, a, b)
		var distance := mouse.distance_to(nearest)
		if distance < closest_distance:
			closest = i
			closest_distance = distance
	if closest >= 0:
		active_measurement_lines.remove_at(closest)

func _handle_map_click(screen_position: Vector2) -> void:
	var point := _snap_map_point(screen_position)
	if active_pending_measure == null:
		active_pending_measure = point
	else:
		var height := -1.0 if large_weather_radar else _maximum_terrain_height_on_line(active_pending_measure, point)
		active_measurement_lines.append({"a": active_pending_measure, "b": point, "max_height_m": height})
		active_pending_measure = null

func _maximum_terrain_height_on_line(a: Vector2, b: Vector2) -> float:
	var sample_count: int = maxi(1, ceili(a.distance_to(b) / 0.10))
	var maximum_height: float = world.height_at(a)
	var previous_position: Vector2 = a
	var previous_height: float = maximum_height
	for sample_index in range(1, sample_count + 1):
		var position := a.lerp(b, sample_index / float(sample_count))
		var height: float = world.height_at(position)
		maximum_height = maxf(maximum_height, height)
		# On a rapidly changing slope, inspect the middle of the interval too.
		# This halves the local sampling step without paying that cost over flats.
		if absf(height - previous_height) >= 8.0:
			maximum_height = maxf(maximum_height, world.height_at((previous_position + position) * 0.5))
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
		refreshed[line_index] = true

func _find_measure_connections(screen_position: Vector2) -> Array[Dictionary]:
	var selected_world := Vector2.ZERO
	var closest_pixels := 12.0
	var found := false
	for line in active_measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var endpoint_screen := _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var distance := screen_position.distance_to(endpoint_screen)
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
	var closest_pixels := 14.0
	var snap_target: Variant = null
	# Both route NDBs and runway locator beacons are stored in world.beacons.
	# Check them together with user-created endpoints when a dragged node is
	# released, so every connected line lands on the exact beacon coordinate.
	for beacon in world.beacons:
		var beacon_position: Vector2 = beacon.position
		if large_weather_radar:
			continue # Do not reveal invisible beacons through radar snapping.
		var pixel_distance := screen_position.distance_to(_measurement_to_screen(beacon_position))
		if pixel_distance < closest_pixels:
			closest_pixels = pixel_distance
			snap_target = beacon_position
	for line_index in active_measurement_lines.size():
		for endpoint_key in ["a", "b"]:
			if _is_dragged_measure_connection(line_index, endpoint_key):
				continue
			var endpoint: Vector2 = active_measurement_lines[line_index][endpoint_key]
			var endpoint_screen := _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var pixel_distance := screen_position.distance_to(endpoint_screen)
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
	var unsnapped := _measurement_from_screen(screen_position)
	if large_weather_radar:
		unsnapped = unsnapped.clamp(Vector2.ZERO, Vector2.ONE * FlightWorldScript.SIZE_KM)
	var closest_world := unsnapped
	var closest_pixels := 14.0
	for beacon in world.beacons:
		var beacon_position: Vector2 = beacon.position
		if large_weather_radar:
			continue
		var pixel_distance := screen_position.distance_to(_measurement_to_screen(beacon_position))
		if pixel_distance < closest_pixels:
			closest_pixels = pixel_distance
			closest_world = beacon_position
	for line in active_measurement_lines:
		for endpoint_key in ["a", "b"]:
			var endpoint: Vector2 = line[endpoint_key]
			var endpoint_screen := _measurement_to_screen(endpoint)
			if large_weather_radar and not _radar_contains(endpoint_screen):
				continue
			var pixel_distance := screen_position.distance_to(endpoint_screen)
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
	var heights := PackedFloat32Array()
	heights.resize((SAMPLE_GRID + 1) * (SAMPLE_GRID + 1))
	for grid_y in SAMPLE_GRID + 1:
		for grid_x in SAMPLE_GRID + 1:
			heights[grid_y * (SAMPLE_GRID + 1) + grid_x] = world.height_at(Vector2(grid_x * cell, grid_y * cell))
	_find_terrain_peaks(heights, cell)
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
func _find_terrain_peaks(heights: PackedFloat32Array, cell: float) -> void:
	var candidates: Array[Dictionary] = []
	var row_size := SAMPLE_GRID + 1
	for y in range(1, SAMPLE_GRID):
		for x in range(1, SAMPLE_GRID):
			var height: float = heights[y * row_size + x]
			if height < CONTOUR_STEP_M:
				continue
			var is_peak := true
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
		var far_enough := true
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
