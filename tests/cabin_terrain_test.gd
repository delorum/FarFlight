extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene._enter_cabin()
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scene._handle_mouse_button(wheel)
	check(scene.cabin_terrain_zoom == 1, "Zoom must also work while parked")
	scene.cabin_terrain_zoom = 0
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.position_km = Vector2(50, 50)
	var terrain: float = scene.world.height_at(scene.flight.position_km)
	scene.flight.altitude_m = terrain + 100.0
	scene._handle_mouse_button(wheel)
	check(scene.cabin_terrain_zoom == 1, "Zoom must work at cloud base")
	check(not scene._cabin_ground_visible(), "Ground must be hidden at 100 m")
	scene.cabin_terrain_zoom = 0
	scene.flight.altitude_m = terrain + 80.0
	scene.flight.speed_kmh = 100.0
	scene.flight.current_wind_kmh = Vector2(20, -10)
	for reverse in [false, true]:
		scene.flight.heading_deg = scene.world.airports[0].heading + (180.0 if reverse else 0.0)
		scene._handle_mouse_button(wheel)
		check(scene.cabin_terrain_zoom > 0, "Overview must work below 100 m, even with engine stopped")
		var velocity: Vector2 = scene.world.heading_vector(scene.flight.heading_deg) * 100.0 + scene.flight.current_wind_kmh
		var direction := 1.0 if scene._aircraft_mirrored() else -1.0
		for sample in scene.cabin_terrain_profile:
			var point: Vector2 = scene.flight.position_km + velocity.normalized() * sample.x * direction / 1000.0
			check(is_equal_approx(sample.y, scene.world.height_at(point)), "Terrain must match ground track and orientation")
	var player_x: float = scene.scene_player_x
	scene._click_side_scene(Vector2(10, 10))
	check(scene.scene_player_x == player_x, "Overview clicks must not teleport cabin character")
	for i in 5:
		scene._handle_mouse_button(wheel)
	check(scene.cabin_terrain_zoom == 3, "Zoom must be bounded")
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for i in 3:
		scene._handle_mouse_button(wheel)
	check(scene.cabin_terrain_zoom == 0, "Wheel must return to cabin")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	scene._handle_mouse_button(wheel)
	scene.flight.altitude_m = terrain + 110.0
	scene._process(0.0)
	check(scene.cabin_terrain_zoom == 1, "Climbing into cloud must preserve zoom")
	check(not scene._cabin_ground_visible(), "Cloud must hide ground")
	for mirrored in [false, true]:
		var pose = scene.AircraftArt.pitch_transform(Vector2.ZERO, 1.0, mirrored, 15.0)
		var nose := Vector2(900,264) if mirrored else Vector2(100,264)
		check((pose * nose).y < 264.0, "Positive pitch raises nose in either orientation")
	scene.flight.altitude_m = scene.world.height_at(scene.flight.position_km) + 80.0
	check(scene._cabin_ground_visible(), "Descending below cloud must restore ground")
	scene._handle_mouse_button(wheel)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	scene._input(key)
	check(scene.cabin_terrain_zoom == 0 and scene.view_mode == scene.ViewMode.CABIN, "Enter must restore cabin without activating its hotspots")
	print("Cabin terrain, zoom, visibility and input: ", "FAIL" if failed else "OK")
	for zoom in range(4):
		scene.cabin_terrain_zoom = zoom
		scene._update_cabin_terrain_profile()
		scene.flight.altitude_m = scene.world.height_at(scene.flight.position_km) + 99.9
		var before: float = scene._cabin_cloud_base_y(0.5)
		scene.flight.altitude_m += 0.2
		var after: float = scene._cabin_cloud_base_y(0.5)
		check(is_equal_approx(after - before, 0.2 * scene._cabin_weather_scale()), "Crossing cloud base must move boundary continuously at current scale")
	print("Cloud base continuity at all four zooms: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
