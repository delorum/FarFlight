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
	var parked_airport_view: Dictionary = scene._cabin_visible_airport()
	check(not parked_airport_view.is_empty() and float(parked_airport_view.start_m) <= 0.0 and float(parked_airport_view.end_m) >= 0.0, "Parked side view must contain the runway beneath the aircraft")
	var runway_start_before: float = float(parked_airport_view.runway_start_m)
	var airport_centre_before: float = float(parked_airport_view.centre_m)
	# A stopped crosswind landing may retain a crabbed nose heading. The ground
	# side view must nevertheless follow the runway axis instead of slicing its
	# 50 m width diagonally and rendering a detached short strip.
	var parked_airport: Dictionary = scene.world.airports[scene.flight.airport_index]
	var parked_runway_direction: Vector2 = scene.world.heading_vector(float(parked_airport.heading))
	scene.flight.position_km = Vector2(parked_airport.position)
	scene.flight.heading_deg = float(parked_airport.heading) + 12.0
	scene.flight.state = scene.FlightModelScript.State.LANDED
	var crabbed_ground_direction: Vector2 = scene._cabin_ground_direction()
	check(absf(crabbed_ground_direction.cross(parked_runway_direction)) < 0.0001, "A landed cabin view must align with the runway despite a residual crab angle")
	var crabbed_airport_view: Dictionary = scene._cabin_visible_airport()
	check(float(crabbed_airport_view.start_m) <= -249.0 and float(crabbed_airport_view.end_m) >= 249.0, "The runway beneath a stopped aircraft must fill the visible 500 m span")
	scene.flight.prepare_at_airport(0)
	parked_airport_view = scene._cabin_visible_airport()
	runway_start_before = float(parked_airport_view.runway_start_m)
	airport_centre_before = float(parked_airport_view.centre_m)
	scene.flight.position_km += scene._cabin_ground_direction() * 0.05
	var moving_airport_view: Dictionary = scene._cabin_visible_airport()
	check(absf(float(moving_airport_view.runway_start_m) - (runway_start_before - 50.0)) < 0.1, "Runway markings must move backwards with the aircraft")
	check(absf(float(moving_airport_view.centre_m) - (airport_centre_before - 50.0)) < 0.1, "Distant airport buildings must move backwards with the aircraft")
	var airport: Dictionary = scene.world.airports[0]
	var approach_direction: Vector2 = scene.world.heading_vector(float(airport.heading))
	var threshold: Vector2 = Vector2(airport.position) - approach_direction * scene.FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	scene.flight.position_km = threshold - approach_direction * 0.3
	scene.flight.heading_deg = float(airport.heading)
	scene.flight.speed_kmh = 90.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	scene.cabin_terrain_zoom = 2
	scene._update_cabin_terrain_profile()
	var approach_airport_view: Dictionary = scene._cabin_visible_airport()
	check(not approach_airport_view.is_empty() and float(approach_airport_view.start_m) > 250.0, "Runway must enter the side view ahead on final approach")
	var runway_right := Vector2(approach_direction.y, -approach_direction.x)
	scene.flight.position_km += runway_right * 0.1
	var nearby_airport: Dictionary = scene._cabin_visible_airport()
	check(not nearby_airport.is_empty() and is_equal_approx(nearby_airport.size_scale, 1.0), "A near-miss within 100 m of the runway edge must show the airport at full size")
	scene.flight.position_km = Vector2(airport.position) + runway_right * 0.4
	nearby_airport = scene._cabin_visible_airport()
	check(not nearby_airport.is_empty() and nearby_airport.size_scale > 0.0 and nearby_airport.size_scale < 1.0, "A laterally distant airport must appear at reduced size")
	for zoom in [0, 1, 3]:
		scene.cabin_terrain_zoom = zoom
		scene._update_cabin_terrain_profile()
		scene.queue_redraw()
		await process_frame
		await process_frame
	scene.flight.position_km = Vector2(airport.position) + runway_right * 1.1
	check(scene._cabin_visible_airport().is_empty(), "Airports beyond 1 km from the runway edge must be hidden")
	var oblique_projection: Dictionary = scene.side_scenes._side_airport_projection(Vector2.ZERO, Vector2(1, 1).normalized())
	check(is_zero_approx(oblique_projection.lateral_km), "A path crossing the runway at an angle must have zero lateral separation")
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
	_test_side_airport_positions(scene)
	await _test_side_beacons(scene)
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

func _test_side_airport_positions(scene) -> void:
	var airport: Dictionary = scene.world.airports[0]
	var forward: Vector2 = scene.world.heading_vector(float(airport.heading))
	var right := Vector2(forward.y, -forward.x)
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.position_km = Vector2(airport.position)
	scene.flight.speed_kmh = 100.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	var offset := Vector2(-52, 55)
	for angle in [0.0, 45.0, 90.0, 180.0]:
		scene.flight.heading_deg = float(airport.heading) + angle
		var direction: Vector2 = scene._cabin_ground_direction() * (1.0 if scene._aircraft_mirrored() else -1.0)
		var projected: Dictionary = scene.side_scenes._side_airport_landmark_projection(airport, offset)
		var relative := forward * offset.x + right * offset.y
		var runway_view: Dictionary = scene._cabin_visible_airport()
		var interval: Vector2 = scene.side_scenes._line_runway_interval(Vector2.ZERO, Vector2(forward.dot(direction), right.dot(direction)))
		check(not runway_view.is_empty() and absf(float(runway_view.runway_end_m) - float(runway_view.runway_start_m) - (interval.y - interval.x) * 1000.0) < 0.1, "Crossing runway must retain the short ground-track intersection")
		check(bool(runway_view.crossing_view) == (angle == 45.0 or angle == 90.0), "Oblique crossings must use a single stripe and a cluster beside the runway")
		if runway_view.crossing_view:
			var rect := Rect2(36, 115, 1208, 600)
			var anchor := rect.get_center()
			var layout: Dictionary = scene.side_scenes.landmarks._airport_cluster_layout(runway_view, rect, anchor, 1.0)
			var minimum_x := INF
			var maximum_x := -INF
			for item in layout.buildings + [layout.tower]:
				var centre_x := anchor.x + float(item.centre_m) + float(layout.shift_px)
				minimum_x = minf(minimum_x, centre_x - 25.0 * float(item.size_scale))
				maximum_x = maxf(maximum_x, centre_x + 25.0 * float(item.size_scale))
			check(minimum_x >= anchor.x + float(runway_view.runway_end_m) + 11.9 or maximum_x <= anchor.x + float(runway_view.runway_start_m) - 11.9, "Side-on airport cluster must remain outside the runway with a gap")
			var previous_lateral := INF
			for item in layout.buildings:
				check(float(item.lateral_km) <= previous_lateral, "Overlapping buildings must be drawn from farthest to nearest")
				previous_lateral = float(item.lateral_km)
		check(absf(float(projected.centre_m) - relative.dot(direction)) < 0.03, "Airport buildings must follow fixed world positions at every crossing angle")
		check(absf(float(projected.lateral_km) * 1000.0 - absf(relative.cross(direction))) < 0.03, "Each airport building must use its own lateral distance")
		scene.flight.position_km += direction * 0.05
		var moved: Dictionary = scene.side_scenes._side_airport_landmark_projection(airport, offset)
		check(absf(float(moved.centre_m) - float(projected.centre_m) + 50.0) < 0.03, "Fixed airport buildings must move backwards with aircraft motion")
		scene.flight.position_km = Vector2(airport.position)
	scene.flight.heading_deg = float(airport.heading)
	scene.flight.position_km += right * 0.5
	var distant: Dictionary = scene.side_scenes._side_airport_landmark_projection(airport, offset)
	check(distant.size_scale > 0.0 and distant.size_scale < 1.0, "Airport buildings must shrink according to their individual lateral distance")

func _test_side_beacons(scene) -> void:
	var saved_beacons: Array = scene.world.beacons.duplicate(true)
	scene.flight.position_km = Vector2(scene.world.airports[0].position)
	scene.flight.altitude_m = scene.world.height_at(scene.flight.position_km) + 80.0
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.heading_deg = 37.0
	scene.flight.speed_kmh = 100.0
	scene.flight.current_wind_kmh = Vector2(20, -10)
	scene.cabin_terrain_zoom = 1
	var direction: Vector2 = scene._cabin_ground_direction()
	var right := Vector2(direction.y, -direction.x)
	var position: Vector2 = scene.flight.position_km + direction * 0.1 + right * 0.05
	scene.world.beacons.assign([
		{"position": position, "runway": -1},
		{"position": position, "runway": 0},
	])
	var visible: Array[Dictionary] = scene.side_scenes._cabin_visible_beacons()
	check(visible.size() == 1, "Nearby standalone beacon must be visible; airport beacon must not be duplicated")
	check(is_equal_approx(visible[0].size_scale, 1.0), "Beacon within 100 m must keep its full size")
	var centre: float = visible[0].centre_m
	scene.flight.position_km += direction * 0.05
	visible = scene.side_scenes._cabin_visible_beacons()
	check(visible.size() == 1 and absf(absf(visible[0].centre_m - centre) - 50.0) < 0.01, "Beacon must move with ground-track motion including wind drift")
	for zoom in [0, 1, 3]:
		scene.cabin_terrain_zoom = zoom
		scene._update_cabin_terrain_profile()
		scene.queue_redraw()
		await process_frame
		await process_frame
	scene.cabin_terrain_zoom = 1
	scene.world.beacons[0].position = scene.flight.position_km + right * 0.15
	visible = scene.side_scenes._cabin_visible_beacons()
	check(visible.size() == 1 and visible[0].size_scale > 0.0 and visible[0].size_scale < 1.0, "Beacon beyond 100 m must remain visible at reduced size")
	var previous_scale := 1.0
	for lateral in [0.1, 0.172, 0.3, 0.75, 0.9, 0.999]:
		var scale: float = scene.side_scenes._side_beacon_size_scale(lateral)
		check(scale > 0.0 and scale <= previous_scale, "Beacon size must decrease smoothly with lateral distance")
		check(is_equal_approx(scale, scene.side_scenes._side_beacon_size_scale(-lateral)), "Visibility must be symmetric on both sides of the aircraft")
		previous_scale = scale
	check(previous_scale < 0.0001, "Beacon must shrink to nearly zero before the cutoff")
	scene.world.beacons[0].position = scene.flight.position_km + right * 1.01
	check(scene.side_scenes._cabin_visible_beacons().is_empty(), "Beacon beyond 1 km laterally must be hidden")
	scene.world.beacons[0].position = scene.flight.position_km + direction * 2.0
	check(scene.side_scenes._cabin_visible_beacons().is_empty(), "Beacon outside the view span must be hidden")
	scene.world.beacons[0].position = scene.flight.position_km
	scene.flight.altitude_m = scene.world.height_at(scene.flight.position_km) + 100.0
	check(scene.side_scenes._cabin_visible_beacons().is_empty(), "Beacons must be hidden at 100 m AGL")
	scene.world.beacons.assign(saved_beacons)
