extends Control
const UILayout = preload("res://scripts/ui_layout.gd")

const SideScenes = preload("res://scripts/side_scenes.gd")
var side_scenes := SideScenes.new(self)

const NavigationMap = preload("res://scripts/navigation_map.gd")
var navigation_map := NavigationMap.new(self)

const InstrumentPanel = preload("res://scripts/instrument_panel.gd")
var instrument_panel := InstrumentPanel.new(self)

const FlightRecorder = preload("res://scripts/flight_recorder.gd")
const SimulationSession = preload("res://scripts/simulation_session.gd")
var recorder := FlightRecorder.new()
var simulation := SimulationSession.new()

const CabinInteractions = preload("res://scripts/cabin_interactions.gd")
var cabin_interactions := CabinInteractions.new(self)

const UIButton = preload("res://scripts/ui_button.gd")

const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
const MapRenderLayerScript = preload("res://scripts/map_render_layer.gd")
const AircraftArt = preload("res://scripts/aircraft_art.gd")
const WeatherRadarArt = preload("res://scripts/weather_radar_art.gd")
const WeatherRadarCache = preload("res://scripts/weather_radar_cache.gd")
const EconomyScript = preload("res://scripts/economy.gd")
const FlightCalculatorScript = preload("res://scripts/flight_calculator.gd")

const MAP_MARGIN = UILayout.MAP_MARGIN
const PANEL_HEIGHT = UILayout.PANEL_HEIGHT
const CONTOUR_STEP_M := 250.0
const SAMPLE_GRID := 192
const INSTRUMENT_RADIUS = UILayout.INSTRUMENT_RADIUS
const INSTRUMENT_GAP = UILayout.INSTRUMENT_GAP
const THROTTLE_HOLD_DELAY := 0.32
const THROTTLE_HOLD_RATE := 0.35
const STEERING_TAP_DEGREES := 0.1
const STEERING_FINE_RATE_DEG_S := 0.1
const USE_STYLIZED_YOKE := true
const MAX_MAP_ZOOM := 24.0
const INITIAL_MAP_RADIUS_KM := 40.0
const APPROACH_DETAIL_MIN_ZOOM := 20.0
const WIND_OVERLAY_ALTITUDES = FlightWorldScript.WIND_ALTITUDES_M
const TIME_SCALES = SimulationSession.TIME_SCALES
# Mirrored scene: both door-to-inventory and inventory-to-chair gaps are 19 units.
const CABIN_TABLE_X = UILayout.CABIN_TABLE_X
const CABIN_TABLE_SEAT_X = UILayout.CABIN_TABLE_SEAT_X

const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode

var world
var flight
var economy
var requested_world_seed := 0
# Compatibility facade for input, calculator and v3/v4 saves. State lives in
# its owning module; these properties never keep a second copy.
var receiver_frequencies := [305, 327]
var active_receiver := -1
var map_zoom: float:
	get:
		return navigation_map.map_zoom
	set(value):
		navigation_map.map_zoom = value
var map_center: Vector2:
	get:
		return navigation_map.map_center
	set(value):
		navigation_map.map_center = value
var contour_segments: Array[Dictionary]:
	get:
		return navigation_map.contour_segments
	set(value):
		navigation_map.contour_segments = value
var terrain_peaks: Array[Dictionary]:
	get:
		return navigation_map.terrain_peaks
	set(value):
		navigation_map.terrain_peaks = value
var measurement_lines: Array[Dictionary]:
	get:
		return navigation_map.measurement_lines
	set(value):
		navigation_map.measurement_lines = value
var pending_measure: Variant:
	get:
		return navigation_map.pending_measure
	set(value):
		navigation_map.pending_measure = value
var radar_measurement_lines: Array[Dictionary]:
	get:
		return navigation_map.radar_measurement_lines
	set(value):
		navigation_map.radar_measurement_lines = value
var radar_pending_measure: Variant:
	get:
		return navigation_map.radar_pending_measure
	set(value):
		navigation_map.radar_pending_measure = value
var active_measurement_lines: Array[Dictionary]:
	get:
		return navigation_map.active_measurement_lines
	set(value):
		navigation_map.active_measurement_lines = value
var active_pending_measure: Variant:
	get:
		return navigation_map.active_pending_measure
	set(value):
		navigation_map.active_pending_measure = value
var dragging_map: bool:
	get:
		return navigation_map.dragging_map
	set(value):
		navigation_map.dragging_map = value
var map_drag_candidate: bool:
	get:
		return navigation_map.map_drag_candidate
	set(value):
		navigation_map.map_drag_candidate = value
var map_press_position: Vector2:
	get:
		return navigation_map.map_press_position
	set(value):
		navigation_map.map_press_position = value
var point_drag_candidate: bool:
	get:
		return navigation_map.point_drag_candidate
	set(value):
		navigation_map.point_drag_candidate = value
var dragging_measure_point: bool:
	get:
		return navigation_map.dragging_measure_point
	set(value):
		navigation_map.dragging_measure_point = value
var dragged_measure_connections: Array[Dictionary]:
	get:
		return navigation_map.dragged_measure_connections
	set(value):
		navigation_map.dragged_measure_connections = value
var dragging_yoke := false
var dragging_throttle := false
var last_mouse := Vector2.ZERO
var status_timer: float:
	get:
		return simulation.status_timer
	set(value):
		simulation.status_timer = value
var clock_seconds: float:
	get:
		return simulation.clock_seconds
	set(value):
		simulation.clock_seconds = value
var trip_air_distance_km: float:
	get:
		return simulation.trip_air_distance_km
	set(value):
		simulation.trip_air_distance_km = value
var trip_elapsed_seconds: float:
	get:
		return simulation.trip_elapsed_seconds
	set(value):
		simulation.trip_elapsed_seconds = value
var flight_trajectory: Array[Dictionary]:
	get:
		return recorder.flight_trajectory
	set(value):
		recorder.flight_trajectory = value
var trajectory_finished: bool:
	get:
		return recorder.trajectory_finished
	set(value):
		recorder.trajectory_finished = value
var trajectory_recording_started: bool:
	get:
		return recorder.trajectory_recording_started
	set(value):
		recorder.trajectory_recording_started = value
var final_trajectory_visible: bool:
	get:
		return recorder.final_trajectory_visible
	set(value):
		recorder.final_trajectory_visible = value
var trajectory_elapsed_seconds: float:
	get:
		return recorder.trajectory_elapsed_seconds
	set(value):
		recorder.trajectory_elapsed_seconds = value
var trajectory_distance_km: float:
	get:
		return recorder.trajectory_distance_km
	set(value):
		recorder.trajectory_distance_km = value
var trajectory_last_position: Vector2:
	get:
		return recorder.trajectory_last_position
	set(value):
		recorder.trajectory_last_position = value
var ils_airport_index := 1
var simulation_paused := false
var run_finish_save_attempted := false
var pause_history_active := false
var pause_history_return_view_mode := ViewMode.COCKPIT
var pause_history_previous_simulation_paused := false
var pause_history_return_state: Dictionary = {}
var signal_check_timer := 0.0
var receiver_signal_status: Array[Dictionary] = [{}, {}]
var ils_signal_status: Dictionary = {}
var ils_prediction_timer := 0.0
var ils_touchdown_prediction: Dictionary = {"valid": false, "distance_from_threshold_km": 0.0}
var map_render_layer: Control
var map_canvas: Control:
	get:
		return navigation_map.map_canvas
	set(value):
		navigation_map.map_canvas = value
var throttle_up_held := false
var throttle_down_held := false
var throttle_up_hold_time := 0.0
var throttle_down_hold_time := 0.0
var steering_left_held := false
var steering_right_held := false
var wind_overlay_index: int:
	get:
		return navigation_map.wind_overlay_index
	set(value):
		navigation_map.wind_overlay_index = value
var last_wind_overlay_altitude_m: float:
	get:
		return navigation_map.last_wind_overlay_altitude_m
	set(value):
		navigation_map.last_wind_overlay_altitude_m = value
var view_mode: int:
	get:
		return side_scenes.view_mode
	set(value):
		side_scenes.view_mode = value
var scene_player_x: float:
	get:
		return side_scenes.scene_player_x
	set(value):
		side_scenes.scene_player_x = value
var scene_player_facing: float:
	get:
		return side_scenes.scene_player_facing
	set(value):
		side_scenes.scene_player_facing = value
var scene_walk_phase: float:
	get:
		return side_scenes.scene_walk_phase
	set(value):
		side_scenes.scene_walk_phase = value
var apron_aircraft_on_left: bool:
	get:
		return side_scenes.apron_aircraft_on_left
	set(value):
		side_scenes.apron_aircraft_on_left = value
var scene_notice: String:
	get:
		return side_scenes.scene_notice
	set(value):
		side_scenes.scene_notice = value
var scene_is_walking: bool:
	get:
		return side_scenes.scene_is_walking
	set(value):
		side_scenes.scene_is_walking = value
var propeller_phase: float:
	get:
		return side_scenes.propeller_phase
	set(value):
		side_scenes.propeller_phase = value
var cabin_terrain_zoom: int:
	get:
		return side_scenes.cabin_terrain_zoom
	set(value):
		side_scenes.cabin_terrain_zoom = value
var cabin_terrain_profile: PackedVector2Array:
	get:
		return side_scenes.cabin_terrain_profile
	set(value):
		side_scenes.cabin_terrain_profile = value
var cabin_terrain_timer: float:
	get:
		return side_scenes.cabin_terrain_timer
	set(value):
		side_scenes.cabin_terrain_timer = value
var cabin_rain_blue: bool:
	get:
		return side_scenes.cabin_rain_blue
	set(value):
		side_scenes.cabin_rain_blue = value
var cabin_fog_travel_px: float:
	get:
		return side_scenes.cabin_fog_travel_px
	set(value):
		side_scenes.cabin_fog_travel_px = value
var large_weather_radar: bool:
	get:
		return navigation_map.large_weather_radar
	set(value):
		navigation_map.large_weather_radar = value
const RADAR_RANGES_KM := [30.0, 20.0, 10.0, 5.0]
var radar_range_index: int:
	get:
		return navigation_map.radar_range_index
	set(value):
		navigation_map.radar_range_index = value
var weather_radar_cache: Node
var crash_overlay: PanelContainer
var crash_description: Label
var crash_title: Label
var selected_inventory_slot: int:
	get:
		return side_scenes.selected_inventory_slot
	set(value):
		side_scenes.selected_inventory_slot = value
var in_fuel_bay: bool:
	get:
		return side_scenes.in_fuel_bay
	set(value):
		side_scenes.in_fuel_bay = value
var last_economy_flight_state: int:
	get:
		return simulation.last_economy_flight_state
	set(value):
		simulation.last_economy_flight_state = value
var fuel_amount_litres: float:
	get:
		return side_scenes.fuel_amount_litres
	set(value):
		side_scenes.fuel_amount_litres = value
var dragging_fuel_slider: bool:
	get:
		return side_scenes.dragging_fuel_slider
	set(value):
		side_scenes.dragging_fuel_slider = value
var hovered_airport_index: int:
	get:
		return navigation_map.hovered_airport_index
	set(value):
		navigation_map.hovered_airport_index = value
var hovered_wind_arrow: bool:
	get:
		return navigation_map.hovered_wind_arrow
	set(value):
		navigation_map.hovered_wind_arrow = value
var hovered_weather_storm_index: int:
	get:
		return navigation_map.hovered_weather_storm_index
	set(value):
		navigation_map.hovered_weather_storm_index = value
var time_scale_index: int:
	get:
		return simulation.time_scale_index
	set(value):
		simulation.time_scale_index = value
var cabin_sleeping: bool:
	get:
		return side_scenes.cabin_sleeping
	set(value):
		side_scenes.cabin_sleeping = value
var cabin_table_seated: bool:
	get:
		return side_scenes.cabin_table_seated
	set(value):
		side_scenes.cabin_table_seated = value
var cabin_sleep_progress_seconds: float:
	get:
		return simulation.cabin_sleep_progress_seconds
	set(value):
		simulation.cabin_sleep_progress_seconds = value
var flight_calculator: PanelContainer

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	map_render_layer = MapRenderLayerScript.new()
	map_render_layer.controller = self
	map_render_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(map_render_layer)
	flight_calculator = FlightCalculatorScript.new()
	flight_calculator.controller = self
	add_child(flight_calculator)
	weather_radar_cache = WeatherRadarCache.new()
	add_child(weather_radar_cache)
	_build_crash_overlay()
	resized.connect(_on_viewport_resized)
	regenerate_world(requested_world_seed)
	set_process(true)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and flight_calculator != null and flight_calculator.editing() and not flight_calculator.get_global_rect().has_point(event.position):
		get_viewport().gui_release_focus()
	# Godot dispatches input to children before the shell. Let Esc reach the
	# pause menu before cabin interactions or receiver text entry consume it.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and get_parent().has_method("_pause_game"):
		get_parent()._pause_game()
		get_viewport().set_input_as_handled()
		return
	# Simulation pause is global: it must remain available in the cockpit, the
	# cabin, exterior views and every airport building.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if not pause_history_active:
			simulation_paused = not simulation_paused
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if flight_calculator != null and flight_calculator.editing() and event is InputEventKey:
		return
	if flight != null and flight.state == FlightModelScript.State.CRASHED and view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY]:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_show_crash_map()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_Z or event.physical_keycode == KEY_Z):
		if event.shift_pressed:
			_cycle_time_scale()
		else:
			_reset_time_scale()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and _key_causes_time_reset(event):
		_reset_time_scale_for_action()
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_X or event.physical_keycode == KEY_X) and view_mode in [ViewMode.COCKPIT, ViewMode.CABIN]:
		if view_mode == ViewMode.COCKPIT:
			_enter_cabin(true)
		else:
			_set_view_mode(ViewMode.COCKPIT)
		get_viewport().set_input_as_handled()
		return
	if view_mode != ViewMode.COCKPIT:
		if event is InputEventKey and event.pressed and not event.echo:
			if side_scenes.handle_history_key(event.keycode):
				get_viewport().set_input_as_handled()
				return
			if view_mode == ViewMode.CABIN and cabin_terrain_zoom == 0 and event.keycode == KEY_DOWN and _near_cabin_ramp():
				_enter_fuel_bay()
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
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and (event.keycode == KEY_P or event.physical_keycode == KEY_P):
		flight.toggle_electrical_power()
		weather_radar_cache.invalidate()
		_queue_map_redraw()
		get_viewport().set_input_as_handled()
		queue_redraw()
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
	if event is InputEventKey and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		if event.echo:
			get_viewport().set_input_as_handled()
			return
		var steer_right: bool = event.keycode == KEY_RIGHT
		if event.pressed:
			if event.shift_pressed and not dragging_yoke:
				if steer_right:
					steering_right_held = true
				else:
					steering_left_held = true
				flight.heading_deg = fposmod(flight.heading_deg + (STEERING_TAP_DEGREES if steer_right else -STEERING_TAP_DEGREES), 360.0)
			else:
				# Plain arrows are read as an immediate continuous yoke axis in
				# _process(). They no longer wait behind the fine-steering timer.
				if steer_right:
					steering_right_held = false
				else:
					steering_left_held = false
		else:
			if steer_right:
				steering_right_held = false
			else:
				steering_left_held = false
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
		if event.keycode == KEY_C:
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

func regenerate_world(requested_seed: int = 0) -> void:
	run_finish_save_attempted = false
	world = FlightWorldScript.new(requested_seed)
	flight = FlightModelScript.new(world)
	economy = EconomyScript.new(world)
	navigation_map.refresh_weather_briefing()
	last_economy_flight_state = flight.state
	propeller_phase = 0.0
	map_center = Vector2(world.airports[flight.airport_index].position)
	map_zoom = _initial_map_zoom(map_center)
	_clamp_map_center()
	flight_calculator.clear_line_links()
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
	simulation.flight_history.reset()
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
		# A crash may happen while the pilot is in the cabin, at an airport scene,
		# or while the full-screen weather radar is open. Always leave those views
		# for the navigation-map debrief instead of trapping the player behind a
		# display whose controls are intentionally disabled after game over.
		if view_mode not in [ViewMode.COCKPIT, ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY] or large_weather_radar:
			_show_crash_map()
		if not run_finish_save_attempted and get_parent().has_method("_on_run_finished"):
			run_finish_save_attempted = true
			get_parent()._on_run_finished(self)
		if view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY]:
			return
	if view_mode != ViewMode.COCKPIT:
		_update_scene_walking(delta)
	elif not flight_calculator.editing() and (steering_left_held or steering_right_held or absf(Input.get_axis("ui_left", "ui_right")) > 0.05 or absf(Input.get_axis("ui_up", "ui_down")) > 0.05 or throttle_up_held or throttle_down_held or dragging_yoke or dragging_throttle):
		# Also catches a control that was already held when Z was pressed.
		_reset_time_scale_for_action()
	if simulation_paused:
		return
	if time_scale_index != 0 and _storm_is_turning_aircraft():
		_reset_time_scale()
	_update_held_steering(delta)
	# Shift+arrow is a direct fine course adjustment and must not also feed the
	# yoke axis. Plain arrows reach the yoke immediately through the input map.
	var steering_axis := 0.0 if steering_left_held or steering_right_held else Input.get_axis("ui_left", "ui_right")
	var keyboard_yoke := Vector2(steering_axis, Input.get_axis("ui_up", "ui_down"))
	if flight_calculator != null and flight_calculator.editing():
		keyboard_yoke = Vector2.ZERO
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
	var engine_before_update: bool = flight.engine_running
	var events := simulation.advance(delta, flight, economy, recorder, cabin_sleeping)
	var game_delta: float = events.elapsed
	if events.landed:
		navigation_map.refresh_weather_briefing()
		weather_radar_cache.invalidate()
	navigation_map.update_dynamic_annotations(delta)
	signal_check_timer -= game_delta
	if signal_check_timer <= 0.0:
		_update_receiver_signals()
		signal_check_timer = 1.0
	ils_prediction_timer -= game_delta
	if ils_prediction_timer <= 0.0:
		_update_ils_touchdown_prediction()
		ils_prediction_timer = 1.0
	if events.map_changed:
		_queue_map_redraw()
	_update_cabin_sleep_notice()
	# Match the small scope: heading and motion must be rendered every frame,
	# independently of the once-per-second radio/ILS signal checks.
	if large_weather_radar and view_mode == ViewMode.COCKPIT and flight.electrical_power:
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
	if flight.state == FlightModelScript.State.CRASHED:
		scene_is_walking = false
		dragging_yoke = false
		dragging_throttle = false
		_show_crash_map()
		_update_crash_overlay()
	if flight.state == FlightModelScript.State.FLYING:
		# Accumulate travel rather than multiplying time by current speed: this
		# avoids jumps when the aircraft accelerates or changes orientation.
		var fog_speed := lerpf(12.0, 40.0, clampf(flight.speed_kmh / 220.0, 0.0, 1.0))
		cabin_fog_travel_px += fog_speed * game_delta * (1.0 if _aircraft_mirrored() else -1.0)
	queue_redraw()

func _update_cabin_sleep(game_delta: float) -> void:
	simulation.advance_bed(game_delta, economy, cabin_sleeping)
	_update_cabin_sleep_notice()

func _update_cabin_sleep_notice() -> void:
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
	return SimulationSession.storm_turning(flight)

func _key_causes_time_reset(event: InputEventKey) -> bool:
	var code := event.keycode
	var physical := event.physical_keycode
	if code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER]:
		return true
	if code in [KEY_X, KEY_M, KEY_B, KEY_W, KEY_S, KEY_SPACE, KEY_C, KEY_T, KEY_V] or physical in [KEY_X, KEY_B, KEY_W, KEY_S]:
		return true
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
	crash_overlay.visible = flight.state == FlightModelScript.State.CRASHED and view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY] and (view_mode != ViewMode.COCKPIT or needs_death)
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
	final_trajectory_visible = true
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
		flight._show_message("Счётчик пройденного пути сброшен", 3.0, "")

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
	if _operations_runway_is_selected(reverse_direction):
		scene_notice = "Самолёт уже подготовлен к вылету с ВПП %03d° • оплата не требуется" % _operations_runway_heading(reverse_direction)
		return
	if not economy.pay_parking():
		scene_notice = "Не хватает денег на стоянку и подготовку • выбранная ВПП не изменена" if flight.departure_authorized else "Не хватает денег на стоянку и подготовку"
		return
	_prepare_from_operations(reverse_direction)
	scene_notice += " • оплачено %d монет" % EconomyScript.PARKING_PRICE

func _operations_runway_heading(reverse_direction: bool) -> int:
	var airport: Dictionary = world.airports[flight.airport_index]
	return (roundi(float(airport.heading)) + (180 if reverse_direction else 0)) % 360

func _operations_runway_is_selected(reverse_direction: bool) -> bool:
	return flight.is_prepared_for(flight.airport_index, reverse_direction)

func _operations_status_text() -> String:
	if not flight.departure_authorized:
		return "СТАТУС: САМОЛЁТ НЕ ПОДГОТОВЛЕН К ВЫЛЕТУ"
	return "СТАТУС: ПОДГОТОВЛЕН К ВЫЛЕТУ С ВПП %03d°" % roundi(flight.prepared_heading_deg())

func _operations_runway_button_text(reverse_direction: bool) -> String:
	var heading := _operations_runway_heading(reverse_direction)
	if _operations_runway_is_selected(reverse_direction):
		return "ПОДГОТОВЛЕНО • ВПП %03d° • БЕСПЛАТНО" % heading
	if flight.departure_authorized:
		return "СМЕНИТЬ ВПП НА %03d° • %d МОНЕТ" % [heading, EconomyScript.PARKING_PRICE]
	return "ПОДГОТОВИТЬ К ВЫЛЕТУ • ВПП %03d° • %d МОНЕТ" % [heading, EconomyScript.PARKING_PRICE]

func _refresh_weather_briefing() -> void:
	navigation_map.refresh_weather_briefing()
	scene_notice = "Метеосводка обновлена • положение гроз зафиксировано на %02d:%02d" % [floori(clock_seconds / 3600.0), floori(fmod(clock_seconds, 3600.0) / 60.0)]
	_queue_map_redraw()
	queue_redraw()

func _near_cabin_ramp() -> bool:
	var ramp_x := _aircraft_point(Vector2((AircraftArt.COCKPIT_RAMP_TOP_X + AircraftArt.COCKPIT_RAMP_BOTTOM_X) * 0.5, 0)).x
	return absf(scene_player_x - ramp_x) < 55.0

func _enter_fuel_bay() -> void:
	cabin_table_seated = false
	in_fuel_bay = true
	scene_player_facing = 1.0
	scene_player_x = _aircraft_point(Vector2(315, 0)).x
	_set_default_fuel_amount()
	scene_notice = ""
	scene_is_walking = false

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
				scene_notice = "Еда куплена — отнесите её в самолёт" if economy.buy_food(flight.airport_index) else "Не хватает денег или руки заняты"
		ViewMode.HOTEL:
			if _economy_button_rect(0).has_point(position):
				if economy.fatigue >= EconomyScript.NEED_SEGMENTS:
					scene_notice = "Вы уже полностью отдохнули"
				elif simulation.rest_at_hotel(flight, economy):
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
				var bought: float = economy.fill_carried_canister(fuel_amount_litres, flight.airport_index)
				_set_default_fuel_amount()
				scene_notice = "Куплено %.1f л топлива" % bought if bought > 0 else "Возьмите канистру или проверьте деньги"
			elif _economy_button_rect(3).has_point(position):
				var paid: int = economy.sell_carried_canister()
				scene_notice = "Получено %d монет" % paid if paid > 0 else "Возьмите канистру"
		ViewMode.REPAIR:
			if _economy_button_rect(0).has_point(position):
				var missing: float = FlightModelScript.MAX_AIRFRAME_CONDITION - float(flight.airframe_condition)
				if missing <= 0.001:
					scene_notice = "Самолёт уже полностью исправен"
				else:
					var repaired: float = economy.buy_repair(missing, flight.airport_index)
					if repaired > 0.0:
						flight.airframe_condition = minf(FlightModelScript.MAX_AIRFRAME_CONDITION, flight.airframe_condition + repaired)
						scene_notice = "Отремонтировано %.1f • состояние %.1f/100" % [repaired, flight.airframe_condition]
					else:
						scene_notice = "Не хватает денег на ремонт"

func _tune_receivers_to_departure_airport() -> void:
	for beacon in world.beacons:
		if int(beacon.get("runway", -1)) == flight.airport_index:
			var departure_frequency := int(beacon.frequency)
			receiver_frequencies[0] = departure_frequency
			receiver_frequencies[1] = departure_frequency
			return

func _reset_flight_trajectory() -> void:
	recorder.reset(flight)
	_queue_map_redraw()

func _make_trajectory_point(position: Vector2) -> Dictionary:
	return recorder.point(position)

func _update_flight_trajectory(previous_state: int, previous_speed: float, delta: float) -> void:
	if recorder.update(flight, previous_state, previous_speed, delta):
		_queue_map_redraw()

func _format_trajectory_time(seconds_value: float) -> String:
	return FlightRecorder.format_time(seconds_value)

func _set_view_mode(next_mode: int) -> void:
	side_scenes._set_view_mode(next_mode)

func open_flight_history_from_pause() -> void:
	pause_history_active = true
	pause_history_return_view_mode = view_mode
	pause_history_previous_simulation_paused = simulation_paused
	pause_history_return_state = {
		"cabin_terrain_zoom": cabin_terrain_zoom,
		"in_fuel_bay": in_fuel_bay,
		"cabin_table_seated": cabin_table_seated,
		"cabin_sleeping": cabin_sleeping,
		"cabin_sleep_progress_seconds": cabin_sleep_progress_seconds,
		"scene_notice": scene_notice,
		"scene_player_x": scene_player_x,
		"scene_player_facing": scene_player_facing,
		"scene_walk_phase": scene_walk_phase,
		"scene_is_walking": scene_is_walking,
		"large_weather_radar": large_weather_radar,
	}
	simulation_paused = true
	large_weather_radar = false
	_set_view_mode(ViewMode.FLIGHT_HISTORY)

func _prepare_return_from_pause_history() -> void:
	if not pause_history_active:
		return
	pause_history_active = false
	_set_view_mode(pause_history_return_view_mode)
	simulation_paused = pause_history_previous_simulation_paused
	for field in pause_history_return_state:
		set(field, pause_history_return_state[field])
	pause_history_return_state.clear()
	_update_crash_overlay()
	queue_redraw()

func return_to_pause_menu_from_history() -> void:
	_prepare_return_from_pause_history()
	if get_parent().has_method("_pause_game"):
		get_parent()._pause_game()

func _aircraft_mirrored() -> bool:
	return side_scenes._aircraft_mirrored()

func _aircraft_scale() -> float:
	return side_scenes._aircraft_scale()

func _aircraft_origin() -> Vector2:
	return side_scenes._aircraft_origin()

func _aircraft_point(local_point: Vector2) -> Vector2:
	return side_scenes._aircraft_point(local_point)

func _scene_walk_bounds() -> Vector2:
	return side_scenes._scene_walk_bounds()

func _cabin_player_position() -> Vector2:
	return side_scenes._cabin_player_position()

func _can_exit_aircraft() -> bool:
	return side_scenes._can_exit_aircraft()

func _scene_hotspots() -> Array[Dictionary]:
	return side_scenes._scene_hotspots()

func _scene_hotspot_is_near(spot: Dictionary) -> bool:
	return side_scenes._scene_hotspot_is_near(spot)

func _click_side_scene(position: Vector2) -> void:
	side_scenes._click_side_scene(position)

func _enter_cabin(from_cockpit: bool = false) -> void:
	side_scenes._enter_cabin(from_cockpit)

func _enter_apron() -> void:
	side_scenes._enter_apron()

func _update_scene_walking(delta: float) -> void:
	side_scenes._update_scene_walking(delta)

func _interact_in_scene() -> void:
	side_scenes._interact_in_scene()

func _leave_current_scene() -> void:
	side_scenes._leave_current_scene()

func _canister_liquid_rect(rect: Rect2, fuel_l: float) -> Rect2:
	return side_scenes._canister_liquid_rect(rect, fuel_l)

func _inventory_rect(slot: int) -> Rect2:
	return side_scenes._inventory_rect(slot)

func _table_transform() -> Transform2D:
	return side_scenes._table_transform()

func _at_cabin_table() -> bool:
	return side_scenes._at_cabin_table()

func _near_cabin_table() -> bool:
	return side_scenes._near_cabin_table()

func _eat_at_table() -> void:
	side_scenes._eat_at_table()

func _bed_transform() -> Transform2D:
	return side_scenes._bed_transform()

func _bed_is_near() -> bool:
	return side_scenes._bed_is_near()

func _start_cabin_sleep() -> void:
	side_scenes._start_cabin_sleep()

func _fuel_device_transform() -> Transform2D:
	return side_scenes._fuel_device_transform()

func _fuel_device_hover_description(position: Vector2) -> String:
	return side_scenes._fuel_device_hover_description(position)

func _carried_item_caption(item: Dictionary) -> String:
	return side_scenes._carried_item_caption(item)

func _handle_inventory_click(position: Vector2) -> bool:
	return side_scenes._handle_inventory_click(position)

func _inventory_hover_description(position: Vector2) -> String:
	return side_scenes._inventory_hover_description(position)

func _carried_action_rect(index: int) -> Rect2:
	return side_scenes._carried_action_rect(index)

func _fuel_slider_rect(origin: Vector2 = Vector2.INF) -> Rect2:
	return side_scenes._fuel_slider_rect(origin)

func _set_fuel_amount_from_mouse(position: Vector2, origin: Vector2 = Vector2.INF, allow_outside: bool = false) -> bool:
	return side_scenes._set_fuel_amount_from_mouse(position, origin, allow_outside)

func _set_default_fuel_amount() -> void:
	side_scenes._set_default_fuel_amount()

func _active_fuel_slider_origin() -> Vector2:
	return side_scenes._active_fuel_slider_origin()

func _fuel_slider_is_active() -> bool:
	return side_scenes._fuel_slider_is_active()

func _draw_cabin_scene() -> void:
	side_scenes._draw_cabin_scene()

func _can_view_cabin_terrain() -> bool:
	return side_scenes._can_view_cabin_terrain()

func _cabin_pose() -> Transform2D:
	return side_scenes._cabin_pose()

func _cabin_ground_visible() -> bool:
	return side_scenes._cabin_ground_visible()

func _cabin_ground_direction() -> Vector2:
	return side_scenes._cabin_ground_direction()

func _update_cabin_terrain_profile() -> void:
	side_scenes._update_cabin_terrain_profile()

func _cabin_visible_airport() -> Dictionary:
	return side_scenes._cabin_visible_airport()

func _cabin_weather_scale() -> float:
	return side_scenes._cabin_weather_scale()

func _cabin_cloud_base_y(fraction: float) -> float:
	return side_scenes._cabin_cloud_base_y(fraction)

func _rounded_box(fill: Color, border: Color, border_width: float, radius: float) -> StyleBoxFlat:
	return side_scenes._rounded_box(fill, border, border_width, radius)

func _draw_apron_scene() -> void:
	side_scenes._draw_apron_scene()

func _draw_airport_scene() -> void:
	side_scenes._draw_airport_scene()

func _airport_buildings() -> Array[Dictionary]:
	return side_scenes._airport_buildings()

func get_operations_runway_rect(reverse_direction: bool) -> Rect2:
	return side_scenes.get_operations_runway_rect(reverse_direction)

func get_operations_weather_rect() -> Rect2:
	return side_scenes.get_operations_weather_rect()

func get_operations_history_rect() -> Rect2:
	return side_scenes.get_operations_history_rect()

func get_building_exit_rect() -> Rect2:
	return side_scenes.get_building_exit_rect()

func _draw_operations_scene() -> void:
	side_scenes._draw_operations_scene()

func _economy_button_rect(index: int) -> Rect2:
	return side_scenes._economy_button_rect(index)

func _delivery_button_text(parcel: Dictionary) -> String:
	return side_scenes._delivery_button_text(parcel)

func _draw_economy_scene() -> void:
	side_scenes._draw_economy_scene()

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

func _update_held_steering(delta: float) -> void:
	var direction := float(int(steering_right_held) - int(steering_left_held))
	if not is_zero_approx(direction):
		flight.heading_deg = fposmod(flight.heading_deg + direction * STEERING_FINE_RATE_DEG_S * delta, 360.0)

func _aircraft_is_on_ground() -> bool:
	return flight.state == FlightModelScript.State.PARKED or flight.state == FlightModelScript.State.ROLLING or flight.state == FlightModelScript.State.LANDED

func map_rect() -> Rect2:
	return navigation_map.map_rect()

func panel_rect() -> Rect2:
	return instrument_panel.panel_rect()

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
		ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY:
			side_scenes._draw_flight_history_scene()
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL, ViewMode.REPAIR:
			_draw_economy_scene()
	if view_mode != ViewMode.COCKPIT:
		_draw_economy_hud(self, false)
		_draw_clock(Vector2(109, 172), 34.0, true)
		_draw_time_controls(true)
		_draw_side_scene_pause_indicator()

func _draw_side_scene_pause_indicator() -> void:
	if not simulation_paused:
		return
	draw_string(ThemeDB.fallback_font, Vector2(0, 44), "ПАУЗА", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, AircraftArt.INK)

func _draw_economy_hud(canvas: CanvasItem, dark: bool) -> void:
	if economy == null:
		return
	var color := Color("e8e4d5") if dark else AircraftArt.INK
	var x := size.x - 360.0
	if view_mode != ViewMode.COCKPIT:
		var label_width := 82.0
		var value_x := x + 94.0
		canvas.draw_string(ThemeDB.fallback_font, Vector2(x, 30), "Деньги", HORIZONTAL_ALIGNMENT_LEFT, label_width, 12, color)
		canvas.draw_string(ThemeDB.fallback_font, Vector2(value_x, 30), str(economy.money), HORIZONTAL_ALIGNMENT_LEFT, 58, 12, color)
		var rows := [
			["Сытость", _need_bar(economy.hunger)],
			["Бодрость", _need_bar(economy.fatigue)],
			["Планер", _airframe_bar()],
		]
		for row_index in rows.size():
			var baseline_y := 50.0 + row_index * 18.0
			canvas.draw_string(ThemeDB.fallback_font, Vector2(x, baseline_y), rows[row_index][0], HORIZONTAL_ALIGNMENT_LEFT, label_width, 12, color)
			canvas.draw_string(ThemeDB.fallback_font, Vector2(value_x, baseline_y), rows[row_index][1], HORIZONTAL_ALIGNMENT_LEFT, 126, 12, color)

func _airframe_condition_status() -> Dictionary:
	if flight.airframe_condition >= 65.0:
		return {"label":"НОРМА", "color":Color("567044")}
	if flight.airframe_condition >= 30.0:
		return {"label":"ИЗНОС", "color":Color("a67931")}
	return {"label":"КРИТИЧЕСКОЕ", "color":Color("a3483f")}

func _draw_airframe_condition_indicator(canvas: CanvasItem, position: Vector2, dark: bool) -> void:
	var status: Dictionary = _airframe_condition_status()
	var status_color: Color = status.color
	var text_color: Color = status_color.lightened(0.2) if dark else status_color
	canvas.draw_string(ThemeDB.fallback_font, position + Vector2(0, 11), _airframe_indicator_text(), HORIZONTAL_ALIGNMENT_LEFT, 410, 11, text_color)

func _airframe_indicator_text() -> String:
	var wear_per_minute: float = flight.airframe_wear_per_hour() / 60.0
	return "ПЛАНЕР: %s  %s  %.1f%% • износ %.3f%%/мин" % [_airframe_condition_status().label, _airframe_bar(), flight.airframe_condition, wear_per_minute]

func _airframe_bar() -> String:
	var filled := ceili(clampf(flight.airframe_condition, 0.0, 100.0) / 100.0 * 6.0)
	return "■".repeat(filled) + "□".repeat(6 - filled)

func _need_bar(value: int) -> String:
	return "■".repeat(clampi(value, 0, 6)) + "□".repeat(6 - clampi(value, 0, 6))

func _format_short_time(seconds_value: float) -> String:
	var total_minutes := maxi(0, ceili(seconds_value / 60.0))
	return "%d:%02d" % [total_minutes / 60, total_minutes % 60]

func _draw_map_on(canvas: Control) -> void:
	navigation_map._draw_map_on(canvas)

func _toggle_weather_radar() -> void:
	navigation_map._toggle_weather_radar()

func _measurement_to_screen(point: Vector2) -> Vector2:
	return navigation_map._measurement_to_screen(point)

func _measurement_from_screen(point: Vector2) -> Vector2:
	return navigation_map._measurement_from_screen(point)

func _clamp_measurement_screen(point: Vector2) -> Vector2:
	return navigation_map._clamp_measurement_screen(point)

func _draw_radar_measurement(canvas: CanvasItem, a_world: Vector2, b_world: Vector2, color: Color, center := Vector2.INF, radius := -1.0) -> void:
	navigation_map._draw_radar_measurement(canvas, a_world, b_world, color, center, radius)

func _handle_radar_mouse_button(event: InputEventMouseButton) -> void:
	navigation_map._handle_radar_mouse_button(event)

func _queue_map_redraw() -> void:
	navigation_map._queue_map_redraw()

func _airport_hover_index(mouse: Vector2) -> int:
	return navigation_map._airport_hover_index(mouse)

func _wind_arrow_description() -> String:
	return navigation_map._wind_arrow_description()

func _wind_arrow_hovered(mouse: Vector2) -> bool:
	return navigation_map._wind_arrow_hovered(mouse)

func _wind_arrow_centers(rect: Rect2) -> PackedVector2Array:
	return navigation_map._wind_arrow_centers(rect)

func _trajectory_overlay_visible() -> bool:
	return navigation_map._trajectory_overlay_visible()

func _map_aircraft_visible() -> bool:
	return navigation_map._map_aircraft_visible()

func _can_toggle_final_trajectory() -> bool:
	return navigation_map._can_toggle_final_trajectory()

func _toggle_final_trajectory() -> void:
	navigation_map._toggle_final_trajectory()

func _build_approach_markers() -> void:
	navigation_map._build_approach_markers()

func _clip_line_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	return navigation_map._clip_line_to_rect(a, b, rect)

func _draw_panel() -> void:
	instrument_panel._draw_panel()

func _flight_message_color() -> Color:
	return instrument_panel._flight_message_color()

func _instrument_center(index: int, gauge_y: float) -> Vector2:
	return instrument_panel._instrument_center(index, gauge_y)

func _draw_clock(center: Vector2, radius: float, beige: bool = false) -> void:
	instrument_panel._draw_clock(center, radius, beige)

func _draw_time_controls(beige: bool = false) -> void:
	instrument_panel._draw_time_controls(beige)

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

func get_throttle_rect() -> Rect2:
	return instrument_panel.get_throttle_rect()

func get_yoke_rect() -> Rect2:
	return instrument_panel.get_yoke_rect()

func get_engine_button_rect() -> Rect2:
	return instrument_panel.get_engine_button_rect()

func get_cabin_button_rect() -> Rect2:
	return instrument_panel.get_cabin_button_rect()

func get_power_button_rect() -> Rect2:
	return instrument_panel.get_power_button_rect()

func get_trajectory_button_rect() -> Rect2:
	return instrument_panel.get_trajectory_button_rect()

func get_center_yoke_button_rect() -> Rect2:
	return instrument_panel.get_center_yoke_button_rect()

func get_trip_reset_button_rect() -> Rect2:
	return instrument_panel.get_trip_reset_button_rect()

func get_time_scale_button_rect(beige: bool = false) -> Rect2:
	return instrument_panel.get_time_scale_button_rect(beige)

func get_time_reset_button_rect(beige: bool = false) -> Rect2:
	return instrument_panel.get_time_reset_button_rect(beige)

func get_ils_rect() -> Rect2:
	return instrument_panel.get_ils_rect()

func get_weather_radar_rect() -> Rect2:
	return instrument_panel.get_weather_radar_rect()

func get_weather_briefing_button_rect() -> Rect2:
	return instrument_panel.get_weather_briefing_button_rect()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if flight.state == FlightModelScript.State.CRASHED and view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY] and (view_mode != ViewMode.COCKPIT or not (map_rect().has_point(event.position) or get_trajectory_button_rect().has_point(event.position))):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if get_time_scale_button_rect(view_mode != ViewMode.COCKPIT).has_point(event.position):
			_cycle_time_scale()
			return
		if get_time_reset_button_rect(view_mode != ViewMode.COCKPIT).has_point(event.position):
			_reset_time_scale()
			return
	# Planning on the chart does not affect the aircraft. Panning, zooming and
	# editing measurement lines may therefore continue at accelerated time.
	var map_interaction := view_mode == ViewMode.COCKPIT and map_rect().has_point(event.position)
	if event.pressed and not map_interaction:
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
			elif get_operations_history_rect().has_point(event.position):
				_set_view_mode(ViewMode.FLIGHT_HISTORY)
			elif get_operations_weather_rect().has_point(event.position):
				_refresh_weather_briefing()
			elif get_operations_runway_rect(false).has_point(event.position):
				_pay_and_prepare(false)
			elif get_operations_runway_rect(true).has_point(event.position):
				_pay_and_prepare(true)
			queue_redraw()
		return
	if view_mode in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY]:
		if event is InputEventMouseButton:
			side_scenes.handle_history_mouse(event)
		return
	if view_mode in [ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL, ViewMode.REPAIR]:
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
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and get_weather_briefing_button_rect().has_point(event.position):
		navigation_map.toggle_weather_briefing()
		return
	if large_weather_radar and (mrect.has_point(event.position) or map_drag_candidate or point_drag_candidate or dragging_measure_point):
		_handle_radar_mouse_button(event)
		return
	var hovered_receiver := _receiver_at_point(event.position)
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and hovered_receiver >= 0:
		active_receiver = hovered_receiver
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
			elif get_power_button_rect().has_point(event.position):
				flight.toggle_electrical_power()
				weather_radar_cache.invalidate()
				_queue_map_redraw()
			elif get_engine_button_rect().has_point(event.position):
				flight.toggle_engine()
				_queue_map_redraw()
			elif get_cabin_button_rect().has_point(event.position):
				_enter_cabin(true)
			elif get_trajectory_button_rect().has_point(event.position):
				_toggle_final_trajectory()
			elif mrect.has_point(event.position):
				if flight_calculator.awaiting_line_binding():
					navigation_map.bind_calculator_to_line_at(event.position)
				else:
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
	var next_hovered_wind := _wind_arrow_hovered(event.position)
	# Hide the fixed annotation while panning: the chart moves underneath it.
	# It will be placed again on the next ordinary pointer motion.
	var next_hovered_storm := navigation_map.weather_briefing_storm_at(event.position) if not map_drag_candidate and not dragging_map else -1
	var storm_hover_changed := navigation_map.update_weather_storm_hover(next_hovered_storm, event.position)
	if next_hovered_airport != hovered_airport_index or next_hovered_wind != hovered_wind_arrow or storm_hover_changed:
		hovered_airport_index = next_hovered_airport
		hovered_wind_arrow = next_hovered_wind
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

func _zoom_at(mouse: Vector2, factor: float) -> void:
	navigation_map._zoom_at(mouse, factor)

func _on_viewport_resized() -> void:
	_normalize_map_camera()
	_queue_map_redraw()

func _normalize_map_camera() -> void:
	navigation_map._normalize_map_camera()

func _initial_map_zoom(center: Vector2) -> float:
	return navigation_map._initial_map_zoom(center)

func _clamp_map_center() -> void:
	navigation_map._clamp_map_center()

func pixels_per_km() -> float:
	return navigation_map.pixels_per_km()

func world_to_screen(point: Vector2) -> Vector2:
	return navigation_map.world_to_screen(point)

func _erase_nearest_measurement(mouse: Vector2) -> void:
	navigation_map._erase_nearest_measurement(mouse)

func _handle_map_click(screen_position: Vector2) -> void:
	navigation_map._handle_map_click(screen_position)

func _refresh_measurement_max_heights(connections: Array[Dictionary]) -> void:
	navigation_map._refresh_measurement_max_heights(connections)

func _find_measure_connections(screen_position: Vector2) -> Array[Dictionary]:
	return navigation_map._find_measure_connections(screen_position)

func _snap_dragged_measure_point_to_endpoint(screen_position: Vector2) -> void:
	navigation_map._snap_dragged_measure_point_to_endpoint(screen_position)

func _build_contours() -> void:
	navigation_map._build_contours()
