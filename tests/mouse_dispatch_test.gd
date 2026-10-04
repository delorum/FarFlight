extends SceneTree
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func click(scene: Control, position: Vector2, pressed := true, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	scene._handle_mouse_button(event)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.pending_measure = null
	scene.measurement_lines.clear()
	scene.time_scale_index = 3
	var position: Vector2 = scene.map_rect().get_center()
	click(scene, position)
	check(scene.map_drag_candidate and scene.time_scale_index == 3, "Chart presses must prepare panning without resetting accelerated time")
	click(scene, position, false)
	check(not scene.map_drag_candidate and scene.pending_measure != null, "Chart release must place a point and clear drag state")
	click(scene, position, true, MOUSE_BUTTON_RIGHT)
	check(scene.pending_measure == null, "Right click must cancel an unfinished route")
	var zoom: float = scene.map_zoom
	click(scene, position, true, MOUSE_BUTTON_WHEEL_UP)
	check(scene.map_zoom > zoom and scene.time_scale_index == 3, "Chart zoom must preserve accelerated time")

	scene.flight.yoke = Vector2(0.4, 0.2)
	click(scene, scene.get_center_yoke_button_rect().get_center())
	check(scene.flight.yoke == Vector2.ZERO and scene.time_scale_index == 0, "Yoke button must still act and reset accelerated time")
	click(scene, scene.get_throttle_rect().get_center())
	check(scene.dragging_throttle, "Throttle must start dragging through the panel handler")
	click(scene, position, false)
	check(not scene.dragging_throttle and not scene.dragging_yoke, "Release over the chart must also end panel dragging")
	var frequency: int = scene.receiver_frequencies[0]
	var gauge_y: float = scene.panel_rect().position.y + 108.0
	click(scene, scene._instrument_center(5, gauge_y), true, MOUSE_BUTTON_WHEEL_UP)
	check(scene.receiver_frequencies[0] == frequency + 1, "Receiver wheel must not be routed to chart zoom")

	click(scene, scene.get_ils_rect().get_center())
	check(scene.large_ils, "ILS preview must still open the large instrument")
	click(scene, position)
	check(not scene.map_drag_candidate and scene.pending_measure == null, "Large ILS must not accept chart drawing")
	click(scene, scene.get_ils_rect().get_center())
	check(not scene.large_ils, "ILS preview must return to the chart")
	scene._set_view_mode(scene.ViewMode.OPERATIONS)
	click(scene, scene.get_operations_history_rect().get_center())
	check(scene.view_mode == scene.ViewMode.FLIGHT_HISTORY, "Operations must dispatch clicks to the history view")
	click(scene, scene.side_scenes.get_history_back_rect().get_center())
	check(scene.view_mode == scene.ViewMode.OPERATIONS, "History back must return to the previous scene")

	scene._set_view_mode(scene.ViewMode.COCKPIT)
	scene.flight.state = scene.FlightModelScript.State.CRASHED
	var throttle: float = scene.flight.throttle
	click(scene, scene.get_throttle_rect().get_center())
	check(scene.flight.throttle == throttle and not scene.dragging_throttle, "Crash gating must remain before aircraft controls")
	scene.free()
	if not failed:
		print("Mouse dispatch across chart, instruments and side scenes: OK")
	quit(1 if failed else 0)
