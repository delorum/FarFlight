extends SceneTree

const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func calm_world():
	var world = World.new(424242)
	world.storms.clear()
	for layer in world.wind_layers:
		layer.speed_kmh = 0.0
	return world

func _run() -> void:
	var flight = Flight.new(calm_world())
	flight.state = Flight.State.FLYING
	flight.position_km = Vector2(50,50)
	flight.altitude_m = 2500
	flight.speed_kmh = 200
	flight.throttle = 0.87
	flight.engine_running = false
	var stalled_during_glide := false
	for frame in 7200:
		flight.update(1.0/60.0)
		stalled_during_glide = stalled_during_glide or flight.stalled
	check(not stalled_during_glide,"Engine shutdown alone must not cause a stall in neutral trim")
	check(flight.speed_kmh >= 90 and flight.speed_kmh <= 110,"Engine-out trim must settle near 100 km/h, not 46")
	check(flight.vertical_speed_mps >= -5 and flight.vertical_speed_mps <= -3,"Engine-out glide must lose 3--5 m/s")
	check(flight.altitude_m < 2150 and is_zero_approx(flight.fuel_flow_lpm()),"Gliding must consume height, not fuel")
	print("Engine-out glide: V=%.2f VS=%.2f" % [flight.speed_kmh,flight.vertical_speed_mps])
	flight.yoke.y = 0.6
	var encountered_stall := false
	for frame in 2400:
		flight.update(1.0/60.0)
		if flight.stalled:
			encountered_stall = true
			break
	check(encountered_stall,"Trying to stretch a glide with strong aft yoke must cause a stall")
	flight.yoke.y = -0.25
	for frame in 1800:
		flight.update(1.0/60.0)
		if not flight.stalled:
			break
	check(not flight.stalled and flight.state == Flight.State.FLYING,"Unloading the yoke must permit engine-out stall recovery")
	# Regression: low airspeed must not create a comfortable low-sink equilibrium.
	flight = Flight.new(calm_world())
	flight.state = Flight.State.FLYING
	flight.position_km = Vector2(50,50)
	flight.altitude_m = 2500
	flight.speed_kmh = 46
	var low_speed_stall := false
	for frame in 3600:
		flight.update(1.0/60.0)
		low_speed_stall = low_speed_stall or flight.stalled
	check(low_speed_stall and flight.speed_kmh > 75,"Insufficient lift at 46 km/h must lead to sinking/stall and recovery, not stable flight")
	# Actual airborne simulation while the player walks in the cabin.
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.world.storms.clear()
	for layer in scene.world.wind_layers:
		layer.speed_kmh = 0.0
	scene.flight.state = Flight.State.FLYING
	scene.flight.position_km = Vector2(50,50)
	scene.flight.altitude_m = scene.world.height_at(Vector2(50,50))+80
	scene.flight.speed_kmh = 90
	scene.flight.engine_running = false
	scene.flight.yoke = Vector2(0,1)
	scene._reset_flight_trajectory()
	scene._enter_cabin()
	var cabin_stalled := false
	for frame in 7200:
		scene._process(1.0/60.0)
		cabin_stalled = cabin_stalled or scene.flight.stalled
		if scene.flight.state == Flight.State.CRASHED:
			break
	check(cabin_stalled and scene.flight.state == Flight.State.CRASHED,"Unattended cabin flight must continue through stall to terrain impact")
	check(scene.view_mode == scene.ViewMode.CABIN and scene.crash_overlay.visible,"Crash result must be visible without returning to cockpit")
	check(scene.crash_description.text.contains(scene.flight.message),"Crash overlay must show the actual cause and flight summary")
	check(scene.trajectory_finished,"Crash in cabin must finish flight trajectory")
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO,scene.size).encloses(scene.crash_overlay.get_rect()),"Crash overlay must fit on screen after text wrapping")
	var final_position: Vector2 = scene.flight.position_km
	var final_player_x: float = scene.scene_player_x
	var final_time: float = scene.clock_seconds
	scene._click_side_scene(Vector2.ZERO)
	scene._interact_in_scene()
	scene._process(1.0)
	check(scene.scene_player_x == final_player_x and scene.flight.position_km == final_position and scene.clock_seconds == final_time,"Crash must freeze walking, interactions and simulation")
	scene._show_crash_map()
	check(scene.view_mode == scene.ViewMode.COCKPIT and not scene.crash_overlay.visible and scene.trajectory_finished,"Debrief must show the completed trajectory")
	var restart_key := InputEventKey.new()
	restart_key.keycode = KEY_R
	restart_key.physical_keycode = KEY_R
	restart_key.pressed = true
	scene._input(restart_key)
	check(scene.flight.state == Flight.State.CRASHED and scene.flight.position_km == final_position,"R must not reset the game after a crash")
	print("Engine-out physics and cabin crash: ","FAIL" if failed else "OK")
	quit(1 if failed else 0)
