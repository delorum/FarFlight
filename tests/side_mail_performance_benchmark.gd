extends SceneTree
## Manual CPU draw-submission comparison, not an FPS assertion.
## Run the same script on baseline and current code with the real renderer.
const VisualTheme = preload("res://scripts/visual_theme.gd")
var samples: Array[int] = []
var measuring := false
var mode := "side"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.requested_world_seed = 424242
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	scene.flight_calculator.hide()
	var airport: Dictionary = scene.world.airports[0]
	var forward: Vector2 = scene.world.heading_vector(float(airport.heading))
	scene.world.beacons.append({"position": airport.position + forward * 0.1, "runway": -1})
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.speed_kmh = 150.0
	scene.flight.heading_deg = float(airport.heading) + 45.0
	scene.flight.current_wind_kmh = Vector2.ZERO
	scene.flight.altitude_m = scene.world.height_at(airport.position) + 80.0
	scene.draw.connect(func():
		var start := Time.get_ticks_usec()
		if mode == "side":
			var rect := Rect2(36, 115, scene.size.x - 72, scene.size.y - 200)
			var anchor := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.28)
			var scale := minf(rect.size.x / scene.side_scenes._cabin_terrain_span_m(), rect.size.y / 190.0)
			var view: Dictionary = scene.side_scenes._cabin_visible_airport()
			if not view.is_empty():
				scene.side_scenes._draw_distant_airport(view, rect, anchor, scale)
				scene.side_scenes._draw_side_runway(view, rect, anchor, scale)
			scene.side_scenes._draw_side_beacons(rect, anchor, scale)
		else:
			scene.side_scenes._draw_economy_scene()
		if measuring:
			samples.append(Time.get_ticks_usec() - start)
	)
	var results := {}
	for scenario in ["side", "mail"]:
		mode = scenario
		scene._set_view_mode(scene.ViewMode.CABIN if mode == "side" else scene.ViewMode.MAIL)
		scene.cabin_terrain_zoom = 2 if mode == "side" else 0
		for dark in [false, true]:
			VisualTheme.set_dark(dark, false)
			scene.material.set_shader_parameter("theme_enabled", dark)
			samples.clear()
			for frame in 180:
				measuring = frame >= 30
				scene.flight.position_km = Vector2(airport.position) + forward * sin(frame * 0.05) * 0.2
				scene.queue_redraw()
				await process_frame
			measuring = false
			samples.sort()
			results[scenario + ("_dark" if dark else "_light")] = {"samples":samples.size(), "median_usec":samples[samples.size()/2], "p95_usec":samples[floori(samples.size()*0.95)]}
	print("SIDE_MAIL_BENCHMARK ", JSON.stringify(results))
	scene.free()
	quit()
