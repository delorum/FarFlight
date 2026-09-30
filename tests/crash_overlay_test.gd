extends SceneTree

const Localization = preload("res://scripts/localization.gd")

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	Localization.set_language(Localization.RUSSIAN)
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.economy.elapsed_seconds = 26.0 * 3600.0 + 62.0
	scene.economy.total_deliveries = 19
	scene.economy.game_over_reason = "Вы умерли от голода"
	scene.flight._crash(scene.economy.game_over_reason)
	scene._update_crash_overlay()
	check(scene.crash_overlay.visible and not scene.crash_overlay_collapsed, "Fatal needs must initially show the complete results panel")
	check(scene.crash_stats.text == "Время игры: 1 д 02:01:02 • доставок: 19", "Results must show total game time and run-wide deliveries")
	var full_height: float = scene.crash_overlay.size.y
	scene.crash_map_button.emit_signal("pressed")
	check(scene.crash_overlay.visible and scene.crash_overlay_collapsed and scene.crash_overlay.size.y < full_height, "The track button must collapse the blocking panel")
	check(scene.crash_expand_button.visible and not scene.crash_details.visible and scene.final_trajectory_visible, "The collapsed panel must reveal the flight track and allow reopening")
	var moved_position: Vector2 = scene.crash_overlay.position + Vector2(35, 25)
	scene.crash_overlay.position = moved_position
	scene._update_crash_overlay()
	check(scene.crash_overlay.position == moved_position, "Results refreshes must not snap a moved panel back")
	scene.crash_expand_button.emit_signal("pressed")
	check(not scene.crash_overlay_collapsed and scene.crash_details.visible and scene.crash_overlay.size.y == full_height, "The panel must expand again")
	Localization.set_language(Localization.ENGLISH)
	scene.localization_changed()
	check(scene.crash_stats.text == "Play time: 1 d 02:01:02 • deliveries: 19", "Results statistics must be localized")
	Localization.set_language(Localization.RUSSIAN)
	print("Collapsible game-over panel, flight track and run statistics: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
