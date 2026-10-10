extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var time_key := InputEventKey.new()
	time_key.keycode = KEY_Z
	time_key.pressed = true
	time_key.shift_pressed = true
	scene._input(time_key)
	check(scene.time_scale_index == 1, "Shift+Z must cycle time to 2x")
	for expected_index in [2, 3, 4, 0]:
		scene._input(time_key)
		check(scene.time_scale_index == expected_index, "Shift+Z must cycle all time scales and wrap to 1x")
	scene.time_scale_index = 4
	time_key.shift_pressed = false
	scene._input(time_key)
	check(scene.time_scale_index == 0, "Z must restore 1x")
	scene.time_scale_index = 3
	var turn_key := InputEventKey.new()
	turn_key.keycode = KEY_RIGHT
	turn_key.pressed = true
	var heading_before_tap: float = scene.flight.heading_deg
	scene._input(turn_key)
	check(scene.time_scale_index == 0, "Aircraft control must reset accelerated time before acting")
	check(is_equal_approx(scene.flight.heading_deg, heading_before_tap), "A plain arrow press must steer through the yoke")
	Input.action_press("ui_right")
	scene._process(0.0)
	check(is_equal_approx(scene.flight.yoke.x, 1.0), "Plain right arrow must engage full yoke immediately")
	Input.action_release("ui_right")
	turn_key.pressed = false
	scene._input(turn_key)
	scene.flight.yoke.x = 0.0
	scene.flight.heading_deg = snappedf(scene.flight.heading_deg, 0.1)
	heading_before_tap = scene.flight.heading_deg
	turn_key.shift_pressed = true
	turn_key.pressed = true
	scene._input(turn_key)
	check(is_equal_approx(scene.flight.heading_deg, heading_before_tap), "Fine steering must not rotate a stationary aircraft")
	scene._update_held_steering(1.0)
	check(is_equal_approx(scene.flight.heading_deg, heading_before_tap), "Held fine steering must not rotate a stationary aircraft")
	scene.flight.speed_kmh = 10.0
	scene._input(turn_key)
	check(is_equal_approx(scene.flight.heading_deg, fposmod(heading_before_tap + 0.1, 360.0)), "Shift+Right must nudge heading by 0.1 degree")
	turn_key.pressed = false
	scene._input(turn_key)
	turn_key.keycode = KEY_LEFT
	turn_key.pressed = true
	scene._input(turn_key)
	check(is_equal_approx(scene.flight.heading_deg, heading_before_tap), "Opposite Shift+arrow must undo the trim")
	turn_key.pressed = false
	scene._input(turn_key)
	turn_key.keycode = KEY_RIGHT
	turn_key.pressed = true
	scene._input(turn_key)
	scene._update_held_steering(1.0)
	check(is_equal_approx(scene.flight.heading_deg, fposmod(heading_before_tap + 0.2, 360.0)), "Holding Shift+Right must add 0.1 degree per second")
	check(is_zero_approx(scene.flight.yoke.x), "Fine steering must not deflect the yoke")
	scene.flight.speed_kmh = 0.0
	turn_key.pressed = false
	scene._input(turn_key)
	var pitch_key := InputEventKey.new()
	pitch_key.keycode = KEY_UP
	pitch_key.shift_pressed = true
	pitch_key.pressed = true
	scene.flight.yoke.y = 0.0
	scene._input(pitch_key)
	check(is_equal_approx(scene.flight.yoke.y * scene.YOKE_PITCH_RANGE_DEG, -0.1), "Shift+Up must move the yoke by 0.1 degree")
	check(scene.instrument_panel.pitch_yoke_readout(scene.flight.yoke.y * scene.YOKE_PITCH_RANGE_DEG).direction == -1, "Forward yoke must show a downward flight arrow")
	pitch_key.pressed = false
	scene._input(pitch_key)
	pitch_key.keycode = KEY_DOWN
	pitch_key.pressed = true
	scene._input(pitch_key)
	check(is_zero_approx(scene.flight.yoke.y), "Shift+Down must undo the pitch trim")
	scene._input(pitch_key)
	check(is_equal_approx(scene.flight.yoke.y * scene.YOKE_PITCH_RANGE_DEG, 0.1), "Shift+Down must pull the yoke back by 0.1 degree")
	check(scene.instrument_panel.pitch_yoke_readout(scene.flight.yoke.y * scene.YOKE_PITCH_RANGE_DEG).direction == 1, "Aft yoke must show an upward flight arrow")
	pitch_key.pressed = false
	scene._input(pitch_key)
	scene.flight.yoke.y = 0.0
	Input.action_press("ui_up")
	scene.cockpit_input.update_keyboard_yoke(0.2)
	check(scene.flight.yoke.y < 0.0, "Plain Up must push the yoke forward, matching Shift+Up")
	Input.action_release("ui_up")
	scene.flight.yoke.y = 0.0
	Input.action_press("ui_down")
	scene.cockpit_input.update_keyboard_yoke(0.2)
	check(scene.flight.yoke.y > 0.0, "Plain Down must pull the yoke back, matching Shift+Down")
	Input.action_release("ui_down")
	var gauge_y: float = scene.panel_rect().position.y + 108.0
	var attitude_center: Vector2 = scene._instrument_center(4, gauge_y)
	var receiver_center: Vector2 = scene._instrument_center(5, gauge_y)
	check(receiver_center.x - attitude_center.x - scene.INSTRUMENT_RADIUS * 2.0 >= 34.0, "The pitch readout must have a gap between the attitude gauge and receiver")
	var fuel_center: Vector2 = scene._instrument_center(8, gauge_y)
	check(fuel_center.x + scene.INSTRUMENT_RADIUS < scene.get_throttle_rect().position.x, "Spacing the gauges must leave room before the throttle")
	var power_key := InputEventKey.new()
	power_key.keycode = KEY_P
	power_key.pressed = true
	scene._input(power_key)
	check(scene.flight.electrical_power, "P must turn on electrical power")
	var engine_key := InputEventKey.new()
	engine_key.keycode = KEY_M
	engine_key.pressed = true
	scene._input(engine_key)
	check(scene.flight.engine_running, "M must start the authorized engine when power is on")
	scene._input(engine_key)
	check(not scene.flight.engine_running, "M must stop the engine")
	scene._input(power_key)
	check(not scene.flight.electrical_power, "P must turn off electrical power")
	var overlay_before: int = scene.wind_overlay_index
	var overlay_key := InputEventKey.new()
	overlay_key.keycode = KEY_V
	overlay_key.pressed = true
	scene._input(overlay_key)
	check(scene.wind_overlay_index != overlay_before, "V must cycle wind overlay")
	var throttle_key := InputEventKey.new()
	throttle_key.keycode = KEY_W
	throttle_key.pressed = true
	scene._input(throttle_key)
	check(is_equal_approx(scene.flight.throttle, 0.01), "W tap must add one percent throttle")
	scene._update_held_throttle(0.5)
	check(scene.flight.throttle > 0.01, "Holding W must increase throttle after the delay")
	throttle_key.pressed = false
	scene._input(throttle_key)
	check(not scene.throttle_up_held, "Releasing W must clear held throttle")
	scene.simulation_paused = true
	scene.flight.throttle = 0.5
	scene.flight.yoke = Vector2(0.3, -0.2)
	var paused_heading: float = scene.flight.heading_deg
	for code in [KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_C]:
		for fine in [false, true]:
			var paused_key := InputEventKey.new()
			paused_key.keycode = code
			paused_key.shift_pressed = fine
			paused_key.pressed = true
			scene._input(paused_key)
			paused_key.pressed = false
			scene._input(paused_key)
	Input.action_press("ui_right")
	Input.action_press("ui_up")
	scene.cockpit_input.update_keyboard_yoke(1.0)
	Input.action_release("ui_right")
	Input.action_release("ui_up")
	scene._update_held_throttle(1.0)
	scene._update_held_steering(1.0)
	scene._update_yoke(scene.get_yoke_rect().position)
	scene._update_throttle(scene.get_throttle_rect().position)
	for rect in [scene.get_yoke_rect(), scene.get_throttle_rect(), scene.get_center_yoke_button_rect()]:
		var paused_click := InputEventMouseButton.new()
		paused_click.button_index = MOUSE_BUTTON_LEFT
		paused_click.pressed = true
		paused_click.position = rect.get_center()
		scene._handle_panel_controls_mouse_button(paused_click)
	check(is_equal_approx(scene.flight.throttle, 0.5), "Pause must block throttle taps, holds and mouse input")
	check(scene.flight.yoke.is_equal_approx(Vector2(0.3, -0.2)), "Pause must block yoke input, fine steps and centering")
	check(is_equal_approx(scene.flight.heading_deg, paused_heading), "Pause must block fine heading steps")
	check(not scene.dragging_yoke and not scene.dragging_throttle and not scene.throttle_up_held and not scene.throttle_down_held, "Paused input must not arm controls for resuming")
	_test_paused_power(scene)
	scene.simulation_paused = false
	throttle_key.pressed = true
	scene._input(throttle_key)
	check(is_equal_approx(scene.flight.throttle, 0.51), "Throttle control must work again after resuming")
	throttle_key.pressed = false
	scene._input(throttle_key)
	scene.flight.state = scene.flight.State.LANDED
	scene.flight.speed_kmh = 0.0
	scene.flight.engine_running = false
	scene.flight.electrical_power = false
	scene.flight.yoke = Vector2(0.5, 0.5)
	Input.action_press("ui_up")
	scene.cockpit_input.update_keyboard_yoke(0.2)
	Input.action_release("ui_up")
	check(scene.flight.yoke.y < 0.5, "Yoke movement must remain available after landing with power and engine off")
	var center_key := InputEventKey.new()
	center_key.keycode = KEY_C
	center_key.pressed = true
	scene._input(center_key)
	check(scene.flight.yoke == Vector2.ZERO, "C must center the yoke after landing with power and engine off")
	_test_heading_tenths(scene)
	_test_occupied_controls(scene)
	_test_control_reset(scene)
	print("Cockpit keyboard control and time scale: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)

func _test_control_reset(scene) -> void:
	var input = scene.cockpit_input
	var yoke: Vector2 = scene.flight.yoke
	var throttle: float = scene.flight.throttle
	for blocked_by_pause in [true, false]:
		input.throttle_up_held = true
		input.throttle_down_held = true
		input.throttle_up_hold_time = 2.0
		input.throttle_down_hold_time = 2.0
		input.steering_left_held = true
		input.steering_right_held = true
		input.steering_hold_seconds = 0.5
		scene.dragging_yoke = true
		scene.dragging_throttle = true
		if blocked_by_pause:
			scene.simulation_paused = true
		else:
			scene.economy.carried_item = {"type": "food"}
			input.update_held_throttle(1.0)
		check(not input.controls_available(), "Pause and occupied hands must share the unavailable-control policy")
		check(not input.throttle_up_held and not input.throttle_down_held and not input.steering_left_held and not input.steering_right_held, "Blocking controls must clear all held commands")
		check(input.throttle_up_hold_time == 0 and input.throttle_down_hold_time == 0 and input.steering_hold_seconds == 0 and not scene.dragging_yoke and not scene.dragging_throttle, "Control reset must clear repeat timers and mouse dragging")
		scene.simulation_paused = false
		scene.economy.carried_item = {}
		input.update_held_throttle(1.0)
		input.update_held_steering(1.0)
		check(scene.flight.yoke == yoke and scene.flight.throttle == throttle, "Resuming must not replay held controls or change set positions")

func _test_occupied_controls(scene) -> void:
	scene.economy.carried_item = {"type": "food"}
	var heading: float = scene.flight.heading_deg
	var yoke: Vector2 = scene.flight.yoke
	var throttle: float = scene.flight.throttle
	var power: bool = scene.flight.electrical_power
	var engine: bool = scene.flight.engine_running
	for code in [KEY_W, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_C, KEY_P, KEY_M]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = true
		event.shift_pressed = true
		scene._input(event)
	for rect in [scene.get_throttle_rect(), scene.get_yoke_rect(), scene.get_center_yoke_button_rect(), scene.get_power_button_rect(), scene.get_engine_button_rect()]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rect.get_center()
		scene._handle_panel_controls_mouse_button(click)
	scene._update_yoke(scene.get_yoke_rect().position)
	scene._update_throttle(scene.get_throttle_rect().position)
	scene.cockpit_input.adjust_throttle_percent(1)
	check(scene.flight.heading_deg == heading and scene.flight.yoke == yoke and scene.flight.throttle == throttle, "Occupied hands must block course, yoke and throttle control even in a legacy cockpit state")
	check(scene.flight.electrical_power == power and scene.flight.engine_running == engine, "Occupied hands must block power and engine controls")
	scene.economy.carried_item = {}

func _test_paused_power(scene) -> void:
	var original_power: bool = scene.flight.electrical_power
	var original_engine: bool = scene.flight.engine_running
	for enabled in [false, true]:
		scene.flight.electrical_power = enabled
		scene.flight.engine_running = enabled
		for code in [KEY_P, KEY_M]:
			for physical_only in [false, true]:
				var event := InputEventKey.new()
				event.keycode = KEY_NONE if physical_only else code
				event.physical_keycode = code
				event.pressed = true
				scene._input(event)
				check(scene.flight.electrical_power == enabled and scene.flight.engine_running == enabled, "Pause must block power and engine hotkeys in both initial states")
		for rect in [scene.get_power_button_rect(), scene.get_engine_button_rect()]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = rect.get_center()
			scene._handle_mouse_button(click)
			check(scene.flight.electrical_power == enabled and scene.flight.engine_running == enabled, "Pause must block power and engine mouse buttons in both initial states")
	scene.flight.electrical_power = original_power
	scene.flight.engine_running = original_engine

func _test_heading_tenths(scene) -> void:
	scene.flight.state = scene.flight.State.FLYING
	scene.flight.yoke = Vector2.ZERO
	scene.flight.bank_deg = 0.0
	var key := InputEventKey.new()
	key.shift_pressed = true
	for keycode in [KEY_LEFT, KEY_RIGHT]:
		key.keycode = keycode
		scene.flight.heading_deg = 179.349 if keycode == KEY_LEFT else 179.149
		key.pressed = true
		scene._input(key)
		check("%.1f" % scene.flight.heading_deg == "179.2", "A fine tap must reach the neighbouring displayed tenth from either direction")
		for frame in 30:
			scene._update_held_steering(1.0 / 60.0)
		check("%.1f" % scene.flight.heading_deg == "179.2", "A short hold must not drift into a second displayed step")
		key.pressed = false
		scene._input(key)
		scene._update_held_steering(1.0)
		check("%.1f" % scene.flight.heading_deg == "179.2", "Releasing a fine key must cancel its repeat")
	scene.flight.heading_deg = 359.9
	key.keycode = KEY_RIGHT
	key.pressed = true
	scene._input(key)
	check(is_zero_approx(scene.flight.heading_deg), "Fine right steering must wrap 359.9 to 0.0")
	key.pressed = false
	scene._input(key)
	key.keycode = KEY_LEFT
	key.pressed = true
	scene._input(key)
	check(is_equal_approx(scene.flight.heading_deg, 359.9), "Fine left steering must wrap 0.0 to 359.9")
	key.pressed = false
	scene._input(key)
