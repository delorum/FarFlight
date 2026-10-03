extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _run() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	await process_frame
	await process_frame
	var map = scene.navigation_map
	var layer = scene.map_render_layer
	map._queue_map_redraw()
	await process_frame
	await process_frame
	var base_count: int = layer.base_draw_count
	var overlay_count: int = layer.overlay_draw_count
	map._queue_map_redraw()
	await process_frame
	await process_frame
	check(layer.base_draw_count == base_count, "Dynamic annotations must not redraw terrain and storm geometry")
	check(layer.overlay_draw_count > overlay_count, "Dynamic annotations must still redraw")
	map.map_zoom = 24.0
	map.map_center = Vector2(100, 100)
	map._queue_map_redraw()
	await process_frame
	await process_frame
	check(layer.base_draw_count > base_count, "Camera changes must invalidate the base layer")
	var rect: Rect2 = map.map_rect()
	var candidates: Array[Dictionary] = map._visible_contour_segments(rect)
	check(candidates.size() < map.contour_segments.size(), "Close-up maps must not scan every contour segment")
	var visible := Rect2(map.screen_to_world(rect.position), rect.size / map.pixels_per_km()).grow(1.5)
	for segment in map.contour_segments:
		var bounds := Rect2(Vector2(segment.a).min(segment.b), (Vector2(segment.a) - Vector2(segment.b)).abs()).grow(0.001)
		if bounds.intersects(visible):
			check(candidates.has(segment), "Spatial culling must retain every potentially visible segment")
	var storm: Dictionary = map.weather_briefing_storms[0]
	var contour: PackedVector2Array = map._weather_briefing_contour(storm, storm.center)
	var cache_count: int = map.geometry_cache.cached_storm_count()
	map.map_center += Vector2(1, 2)
	var moved: PackedVector2Array = map._weather_briefing_contour(storm, storm.center)
	check(map.geometry_cache.cached_storm_count() == cache_count, "Panning must reuse world-space storm contours")
	check(moved[0].is_equal_approx(contour[0] - Vector2(1, 2) * map.pixels_per_km()), "Cached storm contours must follow the camera")
	map.refresh_weather_briefing()
	check(map.geometry_cache.cached_storm_count() == 0, "New weather must invalidate storm geometry")
	check(scene.small_weather_radar_cache.viewport.size == Vector2i(128, 128), "Small radar must use its own small echo texture")
	for cache in [scene.weather_radar_cache, scene.small_weather_radar_cache]:
		cache.update_cache(scene.world, scene.flight, 100.0)
	var large_refreshes: int = scene.weather_radar_cache.refresh_count
	var small_refreshes: int = scene.small_weather_radar_cache.refresh_count
	scene.invalidate_weather_radar_caches()
	for cache in [scene.weather_radar_cache, scene.small_weather_radar_cache]:
		cache.update_cache(scene.world, scene.flight, 100.0)
	check(scene.weather_radar_cache.refresh_count == large_refreshes + 1 and scene.small_weather_radar_cache.refresh_count == small_refreshes + 1, "Unified invalidation must refresh both radars immediately")
	map.measurement_lines.assign([
		{"id": 101, "a": Vector2(20, 50), "b": Vector2(120, 50), "max_height_m": -1.0},
		{"id": 102, "a": Vector2(30, 90), "b": Vector2(130, 90), "max_height_m": -1.0},
	])
	map.pending_measure = Vector2(50, 50)
	for line in map.measurement_lines:
		map._measurement_label_text(line.a, line.b, -1.0, false, line.id)
		check(is_equal_approx(line.max_height_m, map._maximum_terrain_height_on_line(line.a, line.b)), "Legacy line heights must be cached independently, not use the preview cache")
	map.pending_measure = null
	var airport: Dictionary = scene.world.airports[0]
	scene.receiver_frequencies[0] = int(scene.world.beacons[0].frequency)
	scene.flight.position_km = Vector2(airport.position) - scene.world.heading_vector(airport.heading) * 6.0
	scene.flight.heading_deg = airport.heading
	scene.flight.altitude_m = 234.0
	scene.flight.speed_kmh = 174.0
	scene.flight.throttle = 0.7
	scene.flight.engine_running = true
	scene.flight.electrical_power = true
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.ils_signal_status = {"available": false}
	scene.ils_prediction_scheduler.prediction_mode = scene.LandingPredictorScript.Mode.FULL_SIMULATION
	scene._advance_ils_touchdown_prediction(0.1)
	check(scene.ils_prediction_scheduler.job == null and not bool(scene.ils_touchdown_prediction.valid), "Unavailable ILS must not run a forecast")
	scene.ils_signal_status.available = true
	scene._advance_ils_touchdown_prediction(0.1)
	check(scene.ils_prediction_scheduler.job != null, "A long ILS forecast must be spread across frames")
	if scene.ils_prediction_scheduler.job != null:
		check(scene.ils_prediction_scheduler.job.elapsed <= 128 * scene.LandingPredictorScript.STEP_SECONDS + 0.001, "Forecast work must obey the frame step limit")
	var reference: Dictionary = scene.LandingPredictorScript.predict(scene.flight, 0)
	for frame in 200:
		if scene.ils_prediction_scheduler.job == null:
			break
		scene._advance_ils_touchdown_prediction(0.0)
	check(scene.ils_prediction_scheduler.job == null and scene.ils_touchdown_prediction == reference, "Scheduled forecast must publish the complete unchanged result")
	scene.ils_prediction_timer = 0.0
	scene._advance_ils_touchdown_prediction(0.1)
	scene.ils_signal_status.available = false
	scene._advance_ils_touchdown_prediction(0.1)
	check(scene.ils_prediction_scheduler.job == null, "Losing ILS must cancel an unfinished forecast")
	scene.queue_free()
	await process_frame
	if not failed:
		print("Map layers, contour spatial culling, storm geometry and small radar cache: OK")
	quit(1 if failed else 0)
