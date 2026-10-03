extends RefCounted
## Cockpit keyboard commands and held flight controls.

const FlightModel = preload("res://scripts/flight_model.gd")
const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode
const THROTTLE_HOLD_DELAY := 0.32
const THROTTLE_HOLD_RATE := 0.35
const STEERING_TAP_DEGREES := 0.1
const STEERING_FINE_RATE_DEG_S := 0.1
const YOKE_FINE_STEP_DEG := 0.1

var host: Control
var throttle_up_held := false
var throttle_down_held := false
var throttle_up_hold_time := 0.0
var throttle_down_hold_time := 0.0
var steering_left_held := false
var steering_right_held := false

func _init(owner: Control) -> void:
	host = owner

func handle_key(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	if event.pressed and not event.echo and not event.ctrl_pressed and (event.keycode == KEY_P or event.physical_keycode == KEY_P):
		host.flight.toggle_electrical_power()
		host.invalidate_weather_radar_caches()
		host._queue_map_redraw()
		return true
	if event.pressed and not event.echo and event.keycode == KEY_M:
		host.flight.toggle_engine()
		host._queue_map_redraw()
		return true
	if event.pressed and not event.echo and not event.ctrl_pressed and (event.keycode == KEY_B or event.physical_keycode == KEY_B):
		host._toggle_weather_radar()
		return true
	if event.pressed and not event.echo and not event.ctrl_pressed and (event.keycode == KEY_I or event.physical_keycode == KEY_I):
		host._toggle_large_ils()
		return true
	if event.keycode in [KEY_UP, KEY_DOWN] and event.shift_pressed:
		if event.pressed and not event.echo and not host.dragging_yoke:
			# Match the continuous axis: Up pushes forward (negative pitch),
			# Down pulls back (positive pitch).
			var step := -YOKE_FINE_STEP_DEG if event.keycode == KEY_UP else YOKE_FINE_STEP_DEG
			host.flight.yoke.y = clampf(host.flight.yoke.y + step / FlightModel.YOKE_PITCH_RANGE_DEG, -1.0, 1.0)
		return true
	if event.keycode in [KEY_LEFT, KEY_RIGHT]:
		if event.echo:
			return true
		var steer_right: bool = event.keycode == KEY_RIGHT
		if event.pressed and event.shift_pressed and not host.dragging_yoke:
			if steer_right:
				steering_right_held = true
			else:
				steering_left_held = true
			host.flight.heading_deg = fposmod(host.flight.heading_deg + (STEERING_TAP_DEGREES if steer_right else -STEERING_TAP_DEGREES), 360.0)
		elif steer_right:
			steering_right_held = false
		else:
			steering_left_held = false
		return true
	if event.keycode in [KEY_W, KEY_S]:
		if event.echo:
			return true
		var increase: bool = event.keycode == KEY_W
		if increase:
			throttle_up_held = event.pressed
			throttle_up_hold_time = 0.0
		else:
			throttle_down_held = event.pressed
			throttle_down_hold_time = 0.0
			if not event.pressed:
				host.flight.wheel_brakes_applied = false
		if event.pressed:
			adjust_throttle_percent(1 if increase else -1)
		return true
	if event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				host.flight.yoke = Vector2.ZERO
				return true
			KEY_T:
				host._reset_trip_counter()
				return true
			KEY_V:
				host.wind_overlay_index += 1
				if host.wind_overlay_index > host.WIND_OVERLAY_ALTITUDES.size():
					host.wind_overlay_index = 0
				host.last_wind_overlay_altitude_m = -INF
				host._queue_map_redraw()
				return true
	return false

func update_keyboard_yoke(delta: float) -> void:
	var steering_axis := 0.0 if steering_left_held or steering_right_held else Input.get_axis("ui_left", "ui_right")
	var fine_pitch_active := Input.is_key_pressed(KEY_SHIFT) and absf(Input.get_axis("ui_up", "ui_down")) > 0.05
	var keyboard_yoke := Vector2(steering_axis, 0.0 if fine_pitch_active else Input.get_axis("ui_up", "ui_down"))
	if host.flight_calculator != null and host.flight_calculator.editing():
		keyboard_yoke = Vector2.ZERO
	if host.view_mode == ViewMode.COCKPIT and not host.dragging_yoke:
		if absf(keyboard_yoke.x) > 0.05:
			host.flight.yoke.x = keyboard_yoke.x
		else:
			host.flight.yoke.x = move_toward(host.flight.yoke.x, 0.0, delta * 1.8)
		if absf(keyboard_yoke.y) > 0.05:
			# Releasing Up/Down leaves the elevator command where the pilot set it.
			host.flight.yoke.y = clampf(host.flight.yoke.y + keyboard_yoke.y * delta * 0.75, -1.0, 1.0)

func adjust_throttle_percent(step_percent: int) -> void:
	var current_percent := roundi(host.flight.throttle * 100.0)
	if step_percent < 0 and current_percent <= 0 and host._aircraft_is_on_ground():
		host.flight.wheel_brakes_applied = true
		return
	if step_percent > 0:
		host.flight.wheel_brakes_applied = false
	host.flight.throttle = clampf((current_percent + step_percent) / 100.0, 0.0, 1.0)

func update_held_throttle(delta: float) -> void:
	if throttle_up_held:
		var previous_time := throttle_up_hold_time
		throttle_up_hold_time += delta
		var active_delta := maxf(0.0, throttle_up_hold_time - THROTTLE_HOLD_DELAY) - maxf(0.0, previous_time - THROTTLE_HOLD_DELAY)
		host.flight.throttle = minf(1.0, host.flight.throttle + active_delta * THROTTLE_HOLD_RATE)
	if throttle_down_held:
		var previous_time := throttle_down_hold_time
		throttle_down_hold_time += delta
		var active_delta := maxf(0.0, throttle_down_hold_time - THROTTLE_HOLD_DELAY) - maxf(0.0, previous_time - THROTTLE_HOLD_DELAY)
		host.flight.throttle = maxf(0.0, host.flight.throttle - active_delta * THROTTLE_HOLD_RATE)
		if host.flight.throttle <= 0.001 and host._aircraft_is_on_ground():
			host.flight.throttle = 0.0
			host.flight.wheel_brakes_applied = true

func update_held_steering(delta: float) -> void:
	var direction := float(int(steering_right_held) - int(steering_left_held))
	if not is_zero_approx(direction):
		host.flight.heading_deg = fposmod(host.flight.heading_deg + direction * STEERING_FINE_RATE_DEG_S * delta, 360.0)

static func key_causes_time_reset(event: InputEventKey) -> bool:
	var code := event.keycode
	var physical := event.physical_keycode
	if code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER]:
		return true
	return code in [KEY_X, KEY_M, KEY_B, KEY_I, KEY_W, KEY_S, KEY_SPACE, KEY_C, KEY_T, KEY_V] or physical in [KEY_X, KEY_B, KEY_I, KEY_W, KEY_S]
