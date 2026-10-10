extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var calc = scene.flight_calculator
	for layer in scene.world.wind_layers:
		layer.speed_kmh = 0.0
	calc._set_value("initial_altitude", 1000.0)
	calc._set_value("speed", 120.0)
	calc._set_value("distance", 60.0)
	calc._set_value("time", 20.0)
	assert(calc.valid and is_equal_approx(calc.values.speed, 180.0))
	assert(is_equal_approx(calc.values.distance, 60.0))
	calc._set_value("speed", 150.0)
	assert(is_equal_approx(calc.values.time, 24.0) and is_equal_approx(calc.values.distance, 60.0))
	calc._set_value("distance", 75.0)
	assert(is_equal_approx(calc.values.time, 30.0))
	calc._set_value("speed", 180.0)
	assert(is_equal_approx(calc.values.distance, 75.0) and is_equal_approx(calc.values.time, 25.0))
	calc._set_value("time", 10.0)
	calc._set_value("altitude", 2200.0)
	assert(calc.valid and is_equal_approx(calc.values.vertical, 2.0))
	calc._set_value("vertical", 4.0)
	assert(is_equal_approx(calc.values.altitude, 3400.0) and is_equal_approx(calc.values.time, 10.0) and is_equal_approx(calc.values.distance, 75.0))
	calc._set_value("time", 10.0)
	calc._set_value("vertical", 1.0)
	assert(is_equal_approx(calc.values.time, 10.0) and is_equal_approx(calc.values.altitude, 1600.0))
	calc._set_value("altitude", 400.0)
	assert(calc.valid and is_equal_approx(calc.values.altitude, 400.0) and calc.values.vertical < 0.0)
	calc._set_value("vertical", 2.0)
	assert(calc.valid and calc.values.altitude > calc.initial_altitude)
	# Solving airspeed from distance and time includes wind, not just D/T.
	calc._set_value("track", 90.0)
	calc._set_value("wind_from", 90.0)
	calc._set_value("wind_speed", 30.0)
	calc._set_value("distance", 60.0)
	calc._set_value("time", 30.0)
	assert(calc.valid and is_equal_approx(calc.values.speed, 150.0))
	calc._set_value("heading", 90.0)
	calc._set_value("distance", 60.0)
	calc._set_value("time", 20.0)
	assert(calc.valid and is_equal_approx(calc.values.speed, 210.0))
	calc._set_value("altitude", 3000.0)
	var distance_before_zero_time: float = calc.values.distance
	calc._set_value("time", 0.0)
	assert(not calc.valid and is_equal_approx(calc.values.time, 0.0))
	assert(is_equal_approx(calc.values.distance, distance_before_zero_time), "An impossible zero-time edit must never erase the planned distance")
	_test_linked_text_entry(scene)
	print("Calculator edit-order constraints: OK")
	scene.queue_free()
	quit()

func _test_linked_text_entry(scene) -> void:
	var calc = scene.flight_calculator
	calc._set_value("speed", 150.0)
	calc._set_value("wind_speed", 0.0)
	var start := Vector2(100, 5)
	var end := Vector2(120, 5)
	scene.measurement_lines.assign([{"id": 900, "a": start, "b": end, "max_height_m": 0.0}])
	assert(calc.bind_line(900, start, end))
	for text in ["1", "18", "180"]:
		calc.fields.track.text = text
		calc.fields.track.caret_column = text.length()
		calc._text_changed(text, "track")
		assert(calc.fields.track.text == text and calc.fields.track.caret_column == text.length(), "Linked bearing entry must preserve text and caret, including rejected intermediate bearings")
		assert(is_equal_approx(calc.values.distance, 20.0), "Typing a linked bearing must preserve the distance anchor")
		if text != "180":
			assert(not calc.valid and scene.measurement_lines[0].b == end, "Rejected partial bearings must leave the linked geometry unchanged")
	assert(calc.valid and is_equal_approx(calc.values.track, 180.0))
	assert(Vector2(scene.measurement_lines[0].b).distance_to(Vector2(100, 25)) < 0.001, "Completed bearing must rotate the line after an intermediate rejection")
	calc.fields.heading.text = "1"
	calc.fields.heading.caret_column = 1
	calc._text_changed("1", "heading")
	assert(calc.fields.heading.text == "1" and calc.fields.heading.caret_column == 1, "Linked nose-course entry must also preserve rejected partial input")
	calc.fields.heading.text = "180"
	calc.fields.heading.caret_column = 3
	calc._text_changed("180", "heading")
	assert(calc.valid and is_equal_approx(calc.values.heading, 180.0))
	calc.fields.distance.text = "200"
	calc.fields.distance.caret_column = 3
	calc._text_changed("200", "distance")
	assert(not calc.valid and calc.fields.distance.text == "200" and calc.fields.distance.caret_column == 3 and is_equal_approx(calc.values.distance, 20.0), "Rejected length must preserve editable text without changing the distance anchor")
