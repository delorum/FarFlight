extends SceneTree
const Countdown = preload("res://scripts/clock_countdown.gd")
const Save = preload("res://scripts/save_game.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var timer := Countdown.new()
	check(timer.state == Countdown.State.RESET, "Timer starts hidden")
	timer.adjust_minutes(1)
	check(timer.time_text() == "01:00" and timer.state == Countdown.State.PAUSED, "Wheel sets one minute and arms a paused timer")
	timer.advance(10)
	check(timer.remaining_seconds == 60, "Stopped timer must not advance")
	timer.advance_blink(0.6)
	check(not timer.digits_visible(), "Paused timer digits must blink")
	var angle := timer.target_angle(0)
	check(not is_equal_approx(angle, timer.target_angle(60)), "Stopped timer target follows the clock")
	timer.toggle()
	timer.advance(10)
	check(is_equal_approx(angle, timer.target_angle(10)), "Running timer target must remain fixed")
	check(timer.time_text() == "00:50" and timer.digits_visible(), "Running timer must decrease without blinking")
	timer.adjust_minutes(100)
	check(timer.remaining_seconds == 3540, "Timer maximum is 59 minutes")
	timer.adjust_minutes(-100)
	check(timer.state == Countdown.State.RESET, "Setting zero must hide the timer")
	timer.adjust_minutes(1)
	check(timer.limit_step(100) == 100, "Paused timer must not limit simulated time")
	timer.toggle()
	check(timer.limit_step(100) == 60 and timer.limit_step(0.01) == 0.01, "Running timer must limit only steps past expiry")
	check(timer.advance(60), "Countdown must return an expiry event on reaching zero")
	check(not timer.advance(1), "An expired timer must not return repeated expiry events")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	timer = game.simulation.countdown
	var centre: Vector2 = game._instrument_center(7, game.panel_rect().position.y + 108.0)
	check(game.instrument_panel.clock_center() == centre, "Clock input and drawing must share cockpit geometry")
	var wheel := InputEventMouseButton.new()
	wheel.position = centre
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	game.time_scale_index = 4
	game._handle_mouse_button(wheel)
	check(timer.remaining_seconds == 60 and game.time_scale_index == 4, "Clock wheel must not zoom the map or reset acceleration")
	var click := InputEventMouseButton.new()
	click.position = centre
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._handle_mouse_button(click)
	check(timer.state == Countdown.State.RUNNING, "Clock click starts countdown")
	game.simulation_paused = true
	game._process(1)
	check(timer.remaining_seconds == 60, "Game pause must freeze countdown")
	game.simulation_paused = false
	game._process(0.5)
	check(is_equal_approx(timer.remaining_seconds, 52), "Countdown must follow 16x simulated time")
	game._handle_mouse_button(click)
	game._process(0.5)
	check(is_equal_approx(timer.remaining_seconds, 52), "Timer pause must leave game running without counting down")
	var saved := Save.capture(game)
	check(Save.valid(saved), "Timer state must produce a valid save")
	timer.reset()
	check(Save.restore(game, saved), "Paused timer state must restore")
	check(timer.state == Countdown.State.PAUSED and is_equal_approx(timer.remaining_seconds, 52), "Save must preserve countdown time and state")
	saved.ui.countdown_state.remaining_seconds = NAN
	check(not Save.valid(saved), "Non-finite timer data must be rejected")
	var old_saved := Save.capture(game)
	old_saved.ui.erase("countdown_state")
	check(Save.valid(old_saved), "Countdown must remain an optional save field")
	var missing_time_saved := old_saved.duplicate(true)
	missing_time_saved.ui.erase("time_scale_index")
	check(not Save.valid(missing_time_saved), "Modern saves must require time-scale fields regardless of optional countdown")
	missing_time_saved.version = 3
	missing_time_saved.ui.erase("cabin_sleeping")
	missing_time_saved.ui.erase("cabin_sleep_progress_seconds")
	check(Save.valid(missing_time_saved), "Version-3 saves must not require version-4 time fields")
	check(Save.restore(game, old_saved) and timer.state == Countdown.State.RESET, "Older saves without countdown must load with timer reset")
	timer.remaining_seconds = 0.1
	timer.state = Countdown.State.PAUSED
	timer.toggle()
	var before: float = game.economy.elapsed_seconds
	game._process(1)
	check(game.simulation_paused and timer.expired and timer.time_text() == "00:00", "Expiry must automatically pause game")
	check(timer.state == Countdown.State.PAUSED and game.time_scale_index == 0, "Expiry must pause timer and reset acceleration to 1x")
	timer.advance_blink(0.6)
	check(not timer.digits_visible(), "Expired zeros must blink")
	check(is_equal_approx(game.economy.elapsed_seconds - before, 0.1), "Accelerated simulation must stop at exact timer expiry")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	game._input(space)
	check(not game.simulation_paused and timer.state == Countdown.State.RESET, "Space after expiry must resume game and hide digits and tick")
	game._process(0.1)
	check(not game.simulation_paused, "Expired timer must not pause again after resuming")
	click.button_index = MOUSE_BUTTON_RIGHT
	game._handle_mouse_button(click)
	check(timer.state == Countdown.State.RESET, "Right click must reset and hide timer")
	game._handle_mouse_button(wheel)
	click.button_index = MOUSE_BUTTON_LEFT
	game._handle_mouse_button(click)
	game._set_view_mode(game.ViewMode.CABIN)
	check(game.instrument_panel.clock_center() == Vector2(109, 172) and game.instrument_panel.clock_radius() == 34, "Side scenes must retain clock display geometry")
	wheel.position = Vector2(109, 172)
	for view in [game.ViewMode.CABIN, game.ViewMode.HOTEL, game.ViewMode.FLIGHT_HISTORY]:
		game._set_view_mode(view)
		for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			wheel.button_index = button
			check(not game.instrument_panel.handle_clock_mouse(wheel), "Side-view clock must not consume timer input")
			check(timer.remaining_seconds == 60 and timer.state == Countdown.State.RUNNING, "Side-view clock input must not change, pause or reset timer")
	game._set_view_mode(game.ViewMode.CABIN)
	var running_saved := Save.capture(game)
	timer.reset()
	check(Save.restore(game, running_saved) and timer.state == Countdown.State.RUNNING, "Running timer must resume after save restore")
	game._input(space)
	game._input(space)
	check(timer.state == Countdown.State.RUNNING and timer.remaining_seconds == 60, "Ordinary Space pause must not reset an unexpired countdown")
	game._set_view_mode(game.ViewMode.HOTEL)
	game.economy.money = 10000
	var rest_button: Vector2 = game._economy_button_rect(0).get_center()
	before = game.economy.elapsed_seconds
	game.simulation_paused = true
	game._handle_economy_click(rest_button)
	check(game.economy.elapsed_seconds == before and timer.remaining_seconds == 60, "Hotel must not advance game or timer while paused")
	game.simulation_paused = false
	game.time_scale_index = 4
	game._handle_economy_click(rest_button)
	check(game.simulation_paused and timer.expired, "Hotel countdown expiry must pause the game")
	check(game.time_scale_index == 0, "Hotel timer expiry must reset acceleration to 1x")
	check(is_equal_approx(game.economy.elapsed_seconds - before, 60), "Hotel rest must stop at timer expiry")
	print("Clock countdown, input, game time, exact expiry and save: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
