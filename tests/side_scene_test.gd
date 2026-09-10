extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failed = true
		push_error(description)

func click_and_walk(scene: Control, spot: Dictionary) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Rect2(spot.rect).get_center()
	scene._handle_mouse_button(click)

func _run() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	for panel_index in 4:
		var window_position: Vector2 = scene.AircraftArt.cabin_panel_window_position(panel_index)
		var left_rib: float = scene.AircraftArt.CABIN_RIB_X[panel_index]
		var right_rib: float = scene.AircraftArt.CABIN_RIB_X[panel_index+1]
		check(is_equal_approx(window_position.x-left_rib,right_rib-window_position.x), "Portholes must be centered between panel ribs")
		var eye_y: float = scene.AircraftArt.cabin_floor_y(window_position.x) - 61.0 * scene.AircraftArt.PILOT_SCALE
		check(is_equal_approx(window_position.y,eye_y), "Portholes must follow eye height on both ramp and level floor")
	check(is_equal_approx(scene.AircraftArt.TAIL_WINDOW.x-scene.AircraftArt.TAIL_RIB_X[0],scene.AircraftArt.TAIL_RIB_X[1]-scene.AircraftArt.TAIL_WINDOW.x), "Tail porthole must be centered between ribs")
	scene.flight.engine_running = false
	scene._update_propeller_animation(0.1)
	check(is_zero_approx(scene.propeller_phase), "Stopped engine must not rotate propeller")
	scene.flight.engine_running = true
	scene._update_propeller_animation(0.1)
	var running_phase: float = scene.propeller_phase
	check(running_phase > 0, "Running engine must rotate propeller")
	check(scene.AircraftArt.propeller_blade_points(0) != scene.AircraftArt.propeller_blade_points(running_phase), "Propeller phase must change blade geometry")
	scene.simulation_paused = true
	scene._update_propeller_animation(0.1)
	check(scene.propeller_phase == running_phase, "Pause must freeze propeller")
	scene.simulation_paused = false
	scene.flight.engine_running = false
	scene._update_propeller_animation(0.1)
	check(is_zero_approx(scene.propeller_phase), "Stopping engine must restore vertical blade position")
	for reverse_direction in [false,true]:
		scene.flight.prepare_at_airport(0,reverse_direction)
		scene._enter_cabin()
		var cabin_aircraft_origin: Vector2 = scene._aircraft_origin()
		var mirrored: bool = scene._aircraft_mirrored()
		check(mirrored, "Nose must face right for either departure direction")
		var departure_heading: float = scene.flight.heading_deg
		for heading in [0.0, 90.0, 180.0, 270.0]:
			scene.flight.heading_deg = heading
			check(scene._aircraft_mirrored(), "Changing heading must not flip the side view")
		scene.flight.heading_deg = departure_heading
		for local_x in [scene.AircraftArt.SEAT_X, 335.0, 370.0, scene.AircraftArt.DOOR_X]:
			scene.scene_player_x = scene._aircraft_point(Vector2(local_x, 0)).x
			var expected: Vector2 = scene._aircraft_point(Vector2(local_x, scene.AircraftArt.cabin_floor_y(local_x)))
			check(scene._cabin_player_position().is_equal_approx(expected), "Pilot must follow raised deck and ramp in both orientations")
		check(scene.AircraftArt.cabin_floor_y(scene.AircraftArt.SEAT_X) == scene.AircraftArt.COCKPIT_FLOOR_Y, "Seat must be on raised deck")
		check(scene.AircraftArt.cabin_floor_y(scene.AircraftArt.DOOR_X) == scene.AircraftArt.FLOOR_Y, "Cargo door must stay at original floor height")
		var aft_point: Vector2 = scene._aircraft_point(Vector2(705,scene.AircraftArt.FLOOR_Y))
		scene._click_side_scene(aft_point)
		check(scene.view_mode == scene.ViewMode.CABIN and is_equal_approx(scene.scene_player_x,aft_point.x), "Must walk behind cargo door without exiting")
		scene._click_side_scene(scene._aircraft_point(Vector2(850,scene.AircraftArt.FLOOR_Y)))
		var tail_limit: Vector2 = scene._aircraft_point(Vector2(scene.AircraftArt.WALK_MAX,scene.AircraftArt.FLOOR_Y))
		check(scene._cabin_player_position().is_equal_approx(tail_limit), "Walking must stop at tail headroom limit in both orientations")
		var roof_start: Vector2 = scene.AircraftArt.TAIL_ROOF_START
		var roof_end: Vector2 = scene.AircraftArt.TAIL_ROOF_END
		var head_edge_x: float = scene.AircraftArt.WALK_MAX + scene.AircraftArt.PILOT_HALF_WIDTH
		var ceiling_y := lerpf(roof_start.y,roof_end.y,inverse_lerp(roof_start.x,roof_end.x,head_edge_x))
		check(scene.AircraftArt.FLOOR_Y-ceiling_y >= scene.AircraftArt.PILOT_HEIGHT+scene.AircraftArt.TAIL_HEAD_CLEARANCE-0.001, "Pilot cap must fit below tail ceiling")
		click_and_walk(scene,scene._scene_hotspots()[1])
		check(scene.view_mode == scene.ViewMode.APRON,"Click on cabin door must reach apron")
		check(scene._aircraft_mirrored() == mirrored,"Cutaway and exterior must use the same orientation")
		check(scene._aircraft_origin().is_equal_approx(cabin_aircraft_origin), "Cutaway and apron aircraft must keep the same screen position")
		click_and_walk(scene,scene._scene_hotspots()[1])
		check(scene.view_mode == scene.ViewMode.AIRPORT,"Click airport exit must reach airport")
		click_and_walk(scene,scene._scene_hotspots()[0])
		check(scene.view_mode == scene.ViewMode.OPERATIONS,"Click operations door must enter service building")
		click_and_walk(scene, {"rect":scene.get_building_exit_rect()})
		check(scene.view_mode == scene.ViewMode.AIRPORT,"Click exit must immediately leave the building")
		scene._enter_apron()
		click_and_walk(scene,scene._scene_hotspots()[0])
		check(scene.view_mode == scene.ViewMode.CABIN,"Click exterior door must board aircraft")
		click_and_walk(scene,scene._scene_hotspots()[0])
		check(scene.view_mode == scene.ViewMode.COCKPIT,"Click pilot seat must restore cockpit")
		check(scene.map_render_layer.visible,"Map must be restored")
		scene._enter_cabin()
		var bounds: Vector2 = scene._scene_walk_bounds()
		scene._click_side_scene(Vector2(-100,0))
		check(is_equal_approx(scene.scene_player_x,bounds.x),"Click must immediately move within cabin bounds")
		scene.flight.state = scene.FlightModelScript.State.FLYING
		scene.flight.speed_kmh = 150
		check(scene._scene_hotspots().size() == 1, "Only seat hotspot must remain in flight")
		var seat_spot: Dictionary = scene._scene_hotspots()[0]
		check(seat_spot.label_y < scene._aircraft_point(Vector2(0,scene.AircraftArt.FLOOR_Y)).y, "Seat label must be inside fuselage below raised deck")
		var door_position: Vector2 = scene._aircraft_point(Vector2(scene.AircraftArt.DOOR_X,scene.AircraftArt.FLOOR_Y))
		scene._click_side_scene(door_position)
		scene._interact_in_scene()
		check(scene.view_mode == scene.ViewMode.CABIN,"Door must stay closed in flight")
		check(scene.scene_notice.is_empty(), "Airborne door must not offer an action or warning")
		scene.flight.state = scene.FlightModelScript.State.ROLLING
		click_and_walk(scene,scene._scene_hotspots()[1])
		check(scene.view_mode == scene.ViewMode.CABIN,"Door must stay closed during rollout")
	var key := InputEventKey.new()
	key.keycode = KEY_X
	key.pressed = true
	for zoom in range(4):
		scene._enter_cabin()
		scene.scene_player_x = scene._aircraft_point(Vector2(scene.AircraftArt.WALK_MAX,0)).x
		scene.cabin_terrain_zoom = zoom
		scene._input(key)
		check(scene.view_mode == scene.ViewMode.COCKPIT and scene.cabin_terrain_zoom == 0, "X must return from anywhere in cabin at every zoom")
		check(scene.map_render_layer.visible, "X must restore instrument/navigation view")
		scene._input(key)
		check(scene.view_mode == scene.ViewMode.CABIN, "X must still enter cabin")
		key.echo = true
		scene._input(key)
		check(scene.view_mode == scene.ViewMode.CABIN, "Holding X must not toggle repeatedly")
		key.echo = false
	key.keycode = KEY_NONE
	key.physical_keycode = KEY_X
	scene._input(key)
	check(scene.view_mode == scene.ViewMode.COCKPIT, "Physical X must work with alternate keyboard layout")
	print("Side scenes: both orientations, click travel, boarding, service, seat, bounds and X toggle — ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
