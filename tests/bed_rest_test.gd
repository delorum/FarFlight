extends SceneTree
const Save = preload("res://scripts/save_game.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._set_view_mode(game.ViewMode.CABIN)
	game.flight.engine_running = false
	game.flight.state = game.FlightModelScript.State.PARKED
	game.flight.speed_kmh = 0.0
	game.economy.fatigue = 3
	game.economy.hunger = 6
	game.economy.need_accumulator_seconds = 0.0
	game._start_cabin_sleep()
	check(game.side_scenes.can_skip_bed_rest(), "Stopped sleeping aircraft must offer the skip button")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = game.side_scenes.bed_skip_button_rect().get_center()
	var clock_before: float = game.economy.elapsed_seconds
	var weather_before: float = game.world.weather_time_seconds
	var position_before: Vector2 = game.flight.position_km
	var fuel_before: float = game.flight.fuel_l
	var money_before: int = game.economy.money
	game._handle_mouse_button(click)
	check(game.cabin_sleeping and game.cabin_sleep_progress_seconds == 1200 and game.economy.fatigue == 3, "First skip must preserve partial sleep without granting a segment")
	game._handle_mouse_button(click)
	var saved := Save.capture(game)
	check(Save.valid(saved), "Forty minutes of partial bed rest must be a valid save")
	game.cabin_sleep_progress_seconds = 0.0
	check(Save.restore(game, saved) and game.cabin_sleeping and game.cabin_sleep_progress_seconds == 2400, "Loading must preserve partial hourly rest")
	game._handle_mouse_button(click)
	check(game.economy.fatigue == 4 and game.cabin_sleep_progress_seconds == 0, "Three skips must restore exactly one energy segment")
	check(is_equal_approx(game.economy.elapsed_seconds - clock_before, 3600) and is_equal_approx(game.world.weather_time_seconds - weather_before, 3600), "Clock and weather must advance together")
	check(game.economy.hunger == 5, "An hour of bed rest must consume one hunger segment")
	check(game.flight.position_km == position_before and game.flight.fuel_l == fuel_before and game.economy.money == money_before, "Engine-off ground rest must not move the aircraft or spend fuel or money")
	game.simulation_paused = true
	clock_before = game.economy.elapsed_seconds
	game._handle_mouse_button(click)
	check(game.economy.elapsed_seconds == clock_before, "Game pause must prevent skip")
	game.simulation_paused = false
	game.simulation.countdown.adjust_minutes(1)
	game.simulation.countdown.toggle()
	game.time_scale_index = 4
	game._handle_mouse_button(click)
	check(game.simulation_paused and game.time_scale_index == 0 and game.simulation.countdown.expired, "Countdown expiry must interrupt skip, pause and reset acceleration")
	check(game.economy.elapsed_seconds - clock_before == 60 and game.cabin_sleep_progress_seconds == 60, "Interrupted rest must preserve only actual elapsed sleep")
	game.simulation_paused = false
	game.simulation.countdown.reset()
	game.economy.fatigue = 6
	check(game.side_scenes.can_skip_bed_rest(), "Full energy must still allow waiting in bed")
	game.flight.engine_running = true
	check(not game.side_scenes.can_skip_bed_rest(), "Running engine must prevent stationary-only skip")
	game.flight.engine_running = false
	game.flight.state = game.FlightModelScript.State.FLYING
	clock_before = game.economy.elapsed_seconds
	check(not game.side_scenes.can_skip_bed_rest(), "Skip button must be absent in flight")
	game.side_scenes.skip_bed_rest()
	check(game.economy.elapsed_seconds == clock_before, "Programmatic skip must also reject flight")
	game.economy.fatigue = 2
	game.cabin_sleep_progress_seconds = 0.0
	game.simulation.advance_bed(game.EconomyScript.BED_REST_SECONDS, game.economy, game.cabin_sleeping)
	check(game.economy.fatigue == 3, "In-flight bed recovery must use the same hourly interval")
	game.flight.state = game.FlightModelScript.State.PARKED
	game.economy.hunger = 1
	game.economy.need_accumulator_seconds = 3599.0
	clock_before = game.economy.elapsed_seconds
	game.side_scenes.skip_bed_rest()
	check(game.flight.state == game.FlightModelScript.State.CRASHED and game.economy.elapsed_seconds - clock_before == 1, "Fatal hunger must interrupt skip and show game over immediately")
	game.regenerate_world(424242)
	game._set_view_mode(game.ViewMode.HOTEL)
	game.economy.hunger = 1
	game.economy.need_accumulator_seconds = 3599.0
	game.economy.money = 10000
	clock_before = game.economy.elapsed_seconds
	game._handle_economy_click(game._economy_button_rect(0).get_center())
	check(game.flight.state == game.FlightModelScript.State.CRASHED and game.view_mode == game.ViewMode.COCKPIT, "Hotel fatal hunger must show the same immediate game-over screen as bed rest")
	check(game.economy.elapsed_seconds - clock_before == 1, "Hotel fatal event must also stop time immediately")
	print("Hourly bed recovery, ground skip, weather, countdown and saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
