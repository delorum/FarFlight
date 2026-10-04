extends SceneTree

const Save = preload("res://scripts/save_game.gd")
const SessionMode = preload("res://scripts/session_mode.gd")
const LandingPractice = preload("res://scripts/landing_practice.gd")

var failed := false
var slot := "user://test_landing_practice_%d.dat" % Time.get_ticks_usec()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func button_texts(shell) -> Array[String]:
	var result: Array[String] = []
	for child in shell.content.get_children():
		if child is Button:
			result.append(child.text)
	return result

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var shell = load("res://scenes/game_shell.tscn").instantiate()
	shell.save_path = slot
	shell.settings_path = slot + ".settings"
	root.add_child(shell)
	await process_frame
	shell._start_landing_training()
	var training = shell.game
	var guidance: Dictionary = training.flight.landing_guidance(training.flight.airport_index, true)
	check(SessionMode.is_landing_practice(training.session_mode) and training.flight.state == training.FlightModelScript.State.FLYING, "Practice must start directly in flight")
	check(is_equal_approx(float(guidance.actual_distance_to_threshold_km), 6.0), "Practice must begin 6 km before the threshold")
	check(is_equal_approx(training.flight.altitude_m, 234.0) and is_equal_approx(training.flight.throttle, 0.70) and is_equal_approx(training.flight.fuel_l, 40.0), "Practice must set altitude, throttle and fuel")
	check(training.flight.electrical_power and training.flight.engine_running and training.large_ils, "Practice must open powered large ILS")
	check(training.world.storms.is_empty() and not training.world.wind_layers.is_empty(), "Practice must clear storms and retain the wind-layer structure")
	check(training.world.wind_layers.any(func(layer: Dictionary): return float(layer.speed_kmh) > 0.0), "Practice must retain generated wind")
	check(training.flight.current_wind_kmh.is_equal_approx(training.world.wind_at(training.flight.altitude_m)), "Practice aircraft must start with the generated wind at its altitude")
	training.world.refresh_weather()
	LandingPractice.clear_storms(training.world)
	check(training.world.storms.is_empty() and training.world.wind_layers.any(func(layer: Dictionary): return float(layer.speed_kmh) > 0.0), "Weather refresh must keep wind and clear storms in practice")
	check(training.ils_signal_status.get("available", false), "Practice must tune the runway ILS")
	check(not Save.slot_exists(slot), "Practice must not create a campaign save")
	check(Save.write_slot(training, slot) == ERR_UNAUTHORIZED and not Save.slot_exists(slot), "Save boundary must reject practice")
	shell._pause_game()
	check(button_texts(shell) == ["Начать заново", "В главное меню", "Настройки"], "Practice pause menu must offer restart and title")
	var first_seed: int = training.world.seed_value
	shell._restart_landing_training()
	check(shell.game != training and SessionMode.is_landing_practice(shell.game.session_mode) and shell.game.world.seed_value != first_seed, "Restart must create a new independent attempt")
	shell._pause_game()
	shell._leave_landing_training()
	check(shell.game == null and shell.menu_open and not Save.slot_exists(slot), "Leaving practice must preserve an empty save slot")
	shell._new_game(424242)
	check(shell.game.world.wind_layers.any(func(layer: Dictionary): return float(layer.speed_kmh) > 0.0), "Campaign wind must remain enabled")
	check(Save.write_slot(shell.game, slot) == OK, "Campaign must still save normally")
	var saved_bytes := FileAccess.get_file_as_bytes(slot)
	shell._start_landing_training()
	shell.game.flight._crash("Practice crash test")
	shell.game._process(0.0)
	check(FileAccess.get_file_as_bytes(slot) == saved_bytes, "A practice crash must preserve campaign save bytes")
	shell._pause_game()
	shell._restart_landing_training()
	shell._pause_game()
	shell._leave_landing_training()
	check(FileAccess.get_file_as_bytes(slot) == saved_bytes, "Restarting and leaving practice must preserve campaign save bytes")
	for path in [slot, slot + ".tmp", slot + ".settings"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Landing practice session and save isolation: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
