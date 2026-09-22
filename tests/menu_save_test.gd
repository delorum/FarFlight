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

func button_texts(shell) -> Array[String]:
	var result: Array[String] = []
	for child in shell.content.get_children():
		if child is Button:
			result.append(child.text)
	return result

func generated_world_signature(world) -> Dictionary:
	var airports: Array[Dictionary] = []
	for airport in world.airports:
		airports.append({
			"name": airport.name,
			"position": airport.position,
			"heading": airport.heading,
			"region": airport.region,
		})
	return {
		"seed": world.seed_value,
		"airports": airports,
		"beacons": world.beacons.duplicate(true),
		"wind_layers": world.wind_layers.duplicate(true),
		"storms": world.storms.duplicate(true),
	}

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.save_path = slot
	root.add_child(shell)
	await process_frame
	check(shell.menu_open and shell.game == null, "Startup must show title menu without running a flight")
	check(button_texts(shell) == ["Новая игра", "Об игре", "Авторы", "Выход"], "Startup without a save must hide Continue and keep the requested order")
	shell._open_about()
	check(shell.about_open, "About page must open")
	shell._close_about()
	shell._open_authors()
	check(shell.authors_open, "Authors page must open")
	var author_links: Array = shell.content.get_children().filter(func(child): return child is LinkButton)
	check(author_links.size() == 1 and author_links[0].text == "github.com/delorum" and author_links[0].uri == "https://github.com/delorum", "Authors page must expose the requested GitHub link")
	shell._close_authors()
	shell._open_new_game_setup()
	check(shell.new_game_setup_open and shell.new_game_seed_field != null, "New Game must open seed configuration before replacing the current session")
	shell.new_game_seed_field.text = "not-a-seed"
	shell._start_configured_new_game()
	check(shell.game == null and shell.new_game_setup_open and not shell.error_text.is_empty(), "Invalid seed text must keep the setup open and explain the error")
	shell.new_game_seed_field.text = "424242"
	shell._start_configured_new_game()
	var game = shell.game
	var repeated_world = game.FlightWorldScript.new(424242)
	check(game.world.seed_value == 424242 and generated_world_signature(game.world) == generated_world_signature(repeated_world), "A configured seed must reproduce the same generated world exactly")
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
	game.flight.electrical_power = true
	game.flight.engine_running = true
	game.flight.fuel_l = 23.75
	game.flight.airframe_condition = 73.5
	game.receiver_frequencies = [333,377]
	game.world.refresh_weather()
	game.world.refresh_weather()
	game.world.weather_time_seconds = 123.45
	game.economy.elapsed_seconds = 43777.0
	game.time_scale_index = 3
	game.cabin_sleeping = true
	game.cabin_sleep_progress_seconds = 777.0
	game.measurement_lines.append({"a":Vector2(20,30),"b":Vector2(40,50),"max_height_m":500.0})
	game.radar_measurement_lines.append({"a":Vector2(50,50),"b":Vector2(52,48),"max_height_m":-1.0})
	game.pending_measure = Vector2(23,31)
	game.radar_pending_measure = Vector2(49,51)
	game.radar_range_index = 2
	game.final_trajectory_visible = false
	game.navigation_map.weather_briefing_visible = false
	game.navigation_map.weather_briefing_time_seconds = 321.0
	var briefing_before_save: Dictionary = game.navigation_map.weather_briefing_snapshot()
	var calculator = game.flight_calculator
	calculator._set_value("distance", 111.0)
	calculator._set_value("track", 35.0)
	calculator._select_profile(1)
	calculator._set_value("time", 17.0)
	calculator._set_value("wind_speed", 22.0)
	calculator._select_profile(2)
	calculator._set_value("speed", 143.0)
	calculator._set_value("vertical", -1.7)
	calculator._select_profile(3)
	calculator._set_value("altitude", 480.0)
	calculator._set_value("heading", 271.0)
	calculator._select_profile(2)
	game.navigation_map.ensure_measurement_line_ids()
	var planned_line: Dictionary = game.measurement_lines[0]
	check(calculator.bind_line(int(planned_line.id), planned_line.a, planned_line.b), "A calculator profile must bind to a saved map line")
	calculator.expanded = true
	calculator.body.show()
	calculator.toggle.text = "Свернуть"
	calculator.position = Vector2(420,55)
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
	check(button_texts(shell) == ["Продолжить • seed 424242", "Статистика полётов", "Новая игра", "Сохранить и выйти"], "Pause menu must expose flight statistics and keep the requested button order")
	check(not game.throttle_down_held, "Pause must release held throttle input")
	shell._open_pause_flight_history()
	check(not shell.menu_open and game.view_mode == game.ViewMode.FLIGHT_HISTORY and game.simulation_paused, "Pause-menu statistics must open without resuming simulation")
	game.return_to_pause_menu_from_history()
	check(shell.menu_open and game.view_mode == game.ViewMode.CABIN and game.cabin_terrain_zoom == 2 and not game.simulation_paused, "Leaving pause-menu statistics must restore the previous scene state and pause menu")
	var clock_before: float = game.clock_seconds
	await process_frame
	await process_frame
	check(game.clock_seconds == clock_before, "Time must not advance behind menu")
	# A running editor can hot-reload calculator scripts while a game is open.
	# Canonicalize stale Variant number/key types instead of refusing that save.
	calculator.profile_states[1].values.distance = int(calculator.profile_states[1].values.distance)
	calculator.profile_states[1].edit_order = {StringName("distance"): 1}
	var calculator_before_save: Dictionary = game.flight_calculator.snapshot()
	game.simulation.flight_history.records.append({"origin": 0, "destination": 1, "distance_km": 24.5, "duration_seconds": 601.0, "start_seconds": 80.0, "end_seconds": 681.0})
	game.simulation.flight_history.active = true
	game.simulation.flight_history.active_origin = 0
	game.simulation.flight_history.active_start_seconds = 700.0
	game.simulation.flight_history.active_distance_km = 8.25
	var history_before_save: Dictionary = game.simulation.flight_history.snapshot()
	check(calculator_before_save.profiles[1].values.distance is float and calculator_before_save.profiles[1].edit_order.keys()[0] is String, "Calculator snapshot must normalize hot-reloaded Variant types")
	var snapshot := Save.capture(game)
	check(Save.valid(snapshot), "Captured game must validate")
	check(Save.decode_web(Save.encode_web(snapshot)) == snapshot, "Browser encoding must preserve vectors, RNG integers and full state")
	check(Save.decode_web("").is_empty(), "Missing browser slot must be empty")
	var saved_error := Save.write_slot(game,slot)
	check(saved_error == OK, "Save file must be written atomically: %s" % error_string(saved_error))
	var data := Save.read_slot(slot)
	check(not data.is_empty(), "Written save must be readable")
	check(not data.ui.has("clock_seconds"), "New saves must not duplicate the economic clock in UI state")
	if data.is_empty():
		quit(1)
		return
	var loaded: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(loaded)
	loaded.set_process(false)
	check(Save.restore(loaded,data), "Full snapshot must restore")
	check(loaded.flight.fuel_l == 23.75 and loaded.flight.engine_running and loaded.flight.electrical_power, "Fuel, engine and electrical power must survive loading")
	check(loaded.flight.airframe_condition == 73.5 and loaded.economy.repair_airports == game.economy.repair_airports, "Airframe condition and repair price locations must survive loading")
	check(loaded.flight.position_km == Vector2(50,50) and loaded.flight.altitude_m == 2500.0, "Mid-flight position and altitude must survive loading")
	check(loaded.world.beacons == game.world.beacons and loaded.world.storms == game.world.storms and loaded.world.weather_generation == 2, "Generated frequencies, storm state and deterministic weather cycle must survive loading")
	check(loaded.measurement_lines == game.measurement_lines and loaded.radar_measurement_lines == game.radar_measurement_lines, "Both independent annotation sets must survive loading")
	check(not loaded.final_trajectory_visible, "The final-trajectory visibility choice must survive loading")
	check(loaded.navigation_map.weather_briefing_snapshot() == briefing_before_save, "Weather briefing marks, age origin and visibility must survive loading")
	check(loaded.pending_measure == game.pending_measure and loaded.radar_pending_measure == game.radar_pending_measure, "Unfinished annotations must survive loading")
	check(loaded.view_mode == game.ViewMode.CABIN and loaded.cabin_terrain_zoom == 2, "Side scene and zoom must survive loading")
	check(is_equal_approx(loaded.scene_player_x,game.scene_player_x), "Cabin character position must survive loading")
	check(loaded.clock_seconds == clock_before and loaded.receiver_frequencies == [333,377], "Time and radio tuning must survive loading")
	var noon_offset_save := data.duplicate(true)
	noon_offset_save.ui.clock_seconds = fposmod(clock_before + 43200.0, 86400.0)
	check(Save.restore(loaded, noon_offset_save) and is_equal_approx(loaded.clock_seconds, clock_before), "An older noon-offset save must display the same time as its flight history")
	check(loaded.time_scale_index == 3 and loaded.cabin_sleeping and loaded.cabin_sleep_progress_seconds == 777.0, "Time scale and continuous bed rest must survive loading")
	check(loaded.economy.money == 347 and loaded.economy.hunger == 4 and loaded.economy.inventory[2].type == "food", "Money, needs and cargo must survive loading")
	check(loaded.economy.visited_airports == game.economy.visited_airports, "Visited airports and learned price rankings must survive loading")
	check(loaded.flight_calculator.snapshot() == calculator_before_save, "All four calculator profiles, active tab and panel state must survive loading")
	check(loaded.simulation.flight_history.snapshot() == history_before_save, "Completed flight history must survive loading")
	check(loaded.flight_calculator.bound_line_id == int(loaded.measurement_lines[0].id), "Calculator-to-line binding must survive loading")
	var legacy_v5_without_calculator := data.duplicate(true)
	legacy_v5_without_calculator.ui.erase("flight_calculator")
	check(Save.valid(legacy_v5_without_calculator), "Earlier v5 saves without calculator profiles must remain valid")
	var legacy_v5_without_briefing := data.duplicate(true)
	legacy_v5_without_briefing.ui.erase("weather_briefing")
	check(Save.valid(legacy_v5_without_briefing), "Earlier v5 saves without weather briefings must remain valid")
	var legacy_v5_without_weather_generation := data.duplicate(true)
	legacy_v5_without_weather_generation.world.erase("weather_generation")
	check(Save.valid(legacy_v5_without_weather_generation), "Earlier saves without a deterministic weather-cycle counter must remain valid")
	var legacy_v5_without_history := data.duplicate(true)
	legacy_v5_without_history.erase("flight_history")
	legacy_v5_without_history.ui.trajectory_recording_started = true
	legacy_v5_without_history.ui.trajectory_finished = false
	legacy_v5_without_history.ui.trajectory_elapsed_seconds = 120.0
	legacy_v5_without_history.ui.trajectory_distance_km = 6.5
	check(Save.valid(legacy_v5_without_history), "Earlier v5 saves without flight history must remain valid")
	var legacy_history_loaded: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(legacy_history_loaded)
	legacy_history_loaded.set_process(false)
	check(Save.restore(legacy_history_loaded, legacy_v5_without_history) and legacy_history_loaded.simulation.flight_history.active, "An airborne pre-history save must migrate its current flight into the new log")
	var malformed_calculator := data.duplicate(true)
	malformed_calculator.ui.flight_calculator.profiles[0].values.distance = "broken"
	check(not Save.valid(malformed_calculator), "Malformed calculator profiles must invalidate the save")
	var malformed_briefing := data.duplicate(true)
	malformed_briefing.ui.weather_briefing.storms[0].radius_km = -1.0
	check(not Save.valid(malformed_briefing), "Malformed weather briefing marks must invalidate the save")
	# A paid runway preparation is gameplay state, not a transient operations-menu
	# choice. Verify the complete disk path rather than only FlightModel.snapshot().
	var prepared_slot := "user://test_prepared_save_%d.dat" % Time.get_ticks_usec()
	var prepared_game: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(prepared_game)
	prepared_game.set_process(false)
	prepared_game.flight.departure_authorized = false
	prepared_game.flight.state = prepared_game.FlightModelScript.State.LANDED
	prepared_game.flight.airport_index = 2
	prepared_game.economy.money = 100
	prepared_game._pay_and_prepare(true)
	prepared_game._set_view_mode(prepared_game.ViewMode.OPERATIONS)
	check(prepared_game.flight.is_prepared_for(2, true), "Test setup must prepare the reverse runway")
	check(Save.write_slot(prepared_game, prepared_slot) == OK, "Paid runway preparation must be writable")
	var prepared_data := Save.read_slot(prepared_slot)
	check(prepared_data.flight.get("departure_authorized", false) and prepared_data.flight.get("prepared_airport_index", -1) == 2 and prepared_data.flight.get("prepared_reverse_direction", false), "Save file must contain authorization, airport and runway direction")
	var restored_prepared: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(restored_prepared)
	restored_prepared.set_process(false)
	check(Save.restore(restored_prepared, prepared_data), "Prepared departure save must restore")
	check(restored_prepared.flight.is_prepared_for(2, true) and restored_prepared._operations_status_text().contains("ПОДГОТОВЛЕН"), "Loaded flight service must preserve the paid preparation status")
	var restored_money: int = restored_prepared.economy.money
	restored_prepared._pay_and_prepare(true)
	check(restored_prepared.economy.money == restored_money, "Loaded preparation must keep the already selected runway free")
	if FileAccess.file_exists(prepared_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prepared_slot))
	var pre_wear_save := data.duplicate(true)
	pre_wear_save.version = 4
	pre_wear_save.flight.erase("airframe_condition")
	pre_wear_save.flight.erase("departure_authorized")
	pre_wear_save.flight.erase("message_is_error")
	pre_wear_save.flight.erase("electrical_power")
	pre_wear_save.economy.erase("repair_airports")
	var migrated: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(migrated)
	migrated.set_process(false)
	check(Save.valid(pre_wear_save) and Save.restore(migrated, pre_wear_save), "Saves from before airframe wear must migrate")
	check(migrated.flight.airframe_condition == 100.0 and migrated.economy.repair_airports.size() == 3 and migrated.flight.electrical_power, "Migrated saves must start undamaged, retain powered instruments for a running engine and deterministically add repair shops")
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
	check(button_texts(second_shell) == ["Продолжить • seed 424242", "Новая игра", "Об игре", "Авторы", "Выход"], "Startup with a save must show its world seed on Continue")
	second_shell._continue_game()
	check(second_shell.game != null and not second_shell.menu_open, "Startup Continue must load the slot")
	second_shell.game.flight._crash("Проверка завершённого прохождения")
	second_shell.game._process(0.0)
	var finished_data := Save.read_slot(slot)
	check(Save.is_finished_run(finished_data) and bool(finished_data.run_finished), "A crash must automatically replace the slot with a finished-run snapshot")
	second_shell._pause_game()
	check(button_texts(second_shell) == ["Вернуться к итогам • seed 424242", "Статистика полётов", "Новая игра", "Выйти"], "A finished run must not offer Save and Exit or continued flight")
	second_shell._open_pause_flight_history()
	check(second_shell.game.view_mode == second_shell.game.ViewMode.FLIGHT_HISTORY and not second_shell.game.crash_overlay.visible, "A crashed run must allow unobstructed flight-history viewing")
	second_shell.game.return_to_pause_menu_from_history()
	var finished_shell = load("res://scenes/game_shell.tscn").instantiate()
	finished_shell.save_path = slot
	root.add_child(finished_shell)
	check(button_texts(finished_shell) == ["Итоги • seed 424242", "Новая игра", "Об игре", "Авторы", "Выход"], "Startup must identify a finished run as Results instead of Continue")
	finished_shell._continue_game()
	check(finished_shell.game.flight.state == finished_shell.game.FlightModelScript.State.CRASHED, "Opening saved results must remain in the terminal crash state")
	for path in [slot, slot + ".tmp", corrupt_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Title/pause menu, atomic save, full load, continued physics and invalid saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
