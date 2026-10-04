extends SceneTree
## Manual comparison against another project checkout, not a timing assertion.
## Use the same Godot build, display and machine for both runs.
const VisualTheme = preload("res://scripts/visual_theme.gd")
var samples: Array[int] = []
var measure := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.regenerate_world(7182)
	await process_frame
	scene.map_render_layer.visible = false
	scene.flight_calculator.visible = false
	var canvas := Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.material = VisualTheme.create_material()
	canvas.material.set_shader_parameter("navigation_map", true)
	root.add_child(canvas)
	canvas.draw.connect(func():
		var start := Time.get_ticks_usec()
		scene.navigation_map.draw_base_on(canvas)
		scene.navigation_map.draw_overlay_on(canvas)
		if measure:
			samples.append(Time.get_ticks_usec() - start)
	)
	var results := {}
	for dark in [false, true]:
		canvas.material.set_shader_parameter("theme_enabled", dark)
		samples.clear()
		for frame in 130:
			measure = frame >= 30
			scene.map_zoom = 2.0
			scene.map_center = Vector2(100 + sin(frame * 0.13) * 20, 100 + cos(frame * 0.13) * 20)
			canvas.queue_redraw()
			await process_frame
		measure = false
		samples.sort()
		results["dark" if dark else "light"] = {
			"samples": samples.size(),
			"draw_median_usec": samples[samples.size() / 2],
			"draw_p95_usec": samples[floori(samples.size() * 0.95)],
		}
	print("MAP_DRAW_BENCHMARK ", JSON.stringify(results))
	scene.free()
	canvas.free()
	quit()
