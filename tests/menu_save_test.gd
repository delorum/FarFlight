extends SceneTree

const Save = preload("res://scripts/save_game.gd")
var failed := false
var slot := "user://test_menu_save_%d.dat" % Time.get_ticks_usec()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.save_path = slot
	root.add_child(shell)
	await process_frame
	check(shell.menu_open and shell.game == null, "Startup must show title menu without running a flight")
	shell._open_about()
	check(shell.about_open, "About page must open")
	shell._close_about()
	shell._new_game()
	var game = shell.game
	game.economy.money = 347
	game.economy.hunger = 4
	game.economy.inventory[2] = {"type":"food"}
	check(not shell.menu_open and game.is_processing(), "New game must start simulation")
	game.set_process(false)
	game.flight.state = game.FlightModelScript.State.FLYING
	game.flight.position_km = Vector2(50,50)
	game.flight.altitude_m = 2500.0
	game.flight.speed_kmh = 170.0
	game.flight.throttle = 0.87
	game.flight.engine_running = true
	game.flight.fuel_l = 23.75
	game.receiver_frequencies = [333,377]
	game.world.weather_time_seconds = 123.45
	game.clock_seconds = 43777.0
	game.measurement_lines.append({"a":Vector2(20,30),"b":Vector2(40,50),"max_height_m":500.0})
	game.radar_measurement_lines.append({"a":Vector2(50,50),"b":Vector2(52,48),"max_height_m":-1.0})
	game.pending_measure = Vector2(23,31)
	game.radar_pending_measure = Vector2(49,51)
	game.radar_range_index = 2
	game._enter_cabin()
	game.scene_player_x = game._aircraft_point(Vector2(650,0)).x
	game.cabin_terrain_zoom = 2
	game.throttle_down_held = true
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(shell.menu_open and not game.is_processing() and not game.visible, "Escape must pause and cover cabin with title menu")
	check(not game.throttle_down_held, "Pause must release held throttle input")
	var clock_before: float = game.clock_seconds
	await process_frame
	await process_frame
	check(game.clock_seconds == clock_before, "Time must not advance behind menu")
	var snapshot := Save.capture(game)
	check(Save.valid(snapshot), "Captured game must validate")
	check(Save.decode_web(Save.encode_web(snapshot)) == snapshot, "Browser encoding must preserve vectors, RNG integers and full state")
	check(Save.decode_web("").is_empty(), "Missing browser slot must be empty")
	var saved_error := Save.write_slot(game,slot)
	check(saved_error == OK, "Save file must be written atomically: %s" % error_string(saved_error))
	var data := Save.read_slot(slot)
	check(not data.is_empty(), "Written save must be readable")
	if data.is_empty():
		quit(1)
		return
	var loaded: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(loaded)
	loaded.set_process(false)
	check(Save.restore(loaded,data), "Full snapshot must restore")
	check(loaded.flight.fuel_l == 23.75 and loaded.flight.engine_running, "Fuel and engine must survive loading")
	check(loaded.flight.position_km == Vector2(50,50) and loaded.flight.altitude_m == 2500.0, "Mid-flight position and altitude must survive loading")
	check(loaded.world.beacons == game.world.beacons and loaded.world.storms == game.world.storms, "Generated frequencies and storm state must survive loading")
	check(loaded.measurement_lines == game.measurement_lines and loaded.radar_measurement_lines == game.radar_measurement_lines, "Both independent annotation sets must survive loading")
	check(loaded.pending_measure == game.pending_measure and loaded.radar_pending_measure == game.radar_pending_measure, "Unfinished annotations must survive loading")
	check(loaded.view_mode == game.ViewMode.CABIN and loaded.cabin_terrain_zoom == 2, "Side scene and zoom must survive loading")
	check(is_equal_approx(loaded.scene_player_x,game.scene_player_x), "Cabin character position must survive loading")
	check(loaded.clock_seconds == clock_before and loaded.receiver_frequencies == [333,377], "Time and radio tuning must survive loading")
	check(loaded.economy.money == 347 and loaded.economy.hunger == 4 and loaded.economy.inventory[2].type == "food", "Money, needs and cargo must survive loading")
	for frame in 60:
		game.flight.update(1.0/60.0)
		loaded.flight.update(1.0/60.0)
	check(loaded.flight.position_km.is_equal_approx(game.flight.position_km) and is_equal_approx(loaded.flight.altitude_m,game.flight.altitude_m), "Loaded physics must continue identically, including turbulence RNG")
	check(Save.write_slot(game,slot) == OK, "Second save must replace single slot")
	var broken := data.duplicate(true)
	broken.version = 999
	check(not Save.valid(broken) and not Save.restore(loaded,broken), "Unknown save versions must be rejected")
	var corrupt_path := slot + ".corrupt"
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_var({"version":1})
	corrupt.close()
	check(Save.read_slot(corrupt_path).is_empty(), "Incomplete saves must be rejected")
	var old_save := Save.read_slot(slot)
	shell.save_path = "user://missing_menu_test_%d/slot.dat" % Time.get_ticks_usec()
	shell._save_and_exit()
	check(shell.menu_open and not shell.error_text.is_empty(), "Failed save must leave menu open instead of quitting")
	check(Save.read_slot(slot) == old_save, "Failed save must not damage existing slot")
	shell.save_path = slot
	shell._resume_game()
	check(not shell.menu_open and game.visible and game.is_processing(), "Continue must restore gameplay")
	game.set_process(false)
	# Startup Continue uses the same complete restoration path.
	var second_shell = load("res://scenes/game_shell.tscn").instantiate()
	second_shell.save_path = slot
	root.add_child(second_shell)
	second_shell._continue_game()
	check(second_shell.game != null and not second_shell.menu_open, "Startup Continue must load the slot")
	for path in [slot, slot + ".tmp", corrupt_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Title/pause menu, atomic save, full load, continued physics and invalid saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
