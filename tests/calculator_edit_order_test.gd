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
	print("Calculator edit-order constraints: OK")
	scene.queue_free()
	quit()
