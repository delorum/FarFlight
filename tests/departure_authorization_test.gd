extends SceneTree

const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight = Flight.new(World.new(424242))
	assert(flight.departure_authorized, "A new game must begin prepared for departure")
	flight.toggle_engine()
	assert(flight.engine_running)
	flight.toggle_engine()
	assert(not flight.engine_running and not flight.departure_authorized, "Stopping the engine on the ground must revoke departure preparation")
	flight.toggle_engine()
	assert(not flight.engine_running and flight.message_is_error and flight.message == Flight.DEPARTURE_BLOCKED_MESSAGE, "A blocked start must explain the required payment and runway choice as an error")

	flight.prepare_at_airport(0)
	assert(flight.departure_authorized)
	flight.departure_authorized = false
	flight.state = Flight.State.PARKED
	flight.engine_running = true
	flight.throttle = 1.0
	flight.speed_kmh = 90.0
	flight.pitch_deg = 10.0
	flight.yoke.y = 1.0
	flight.update(0.1)
	assert(flight.state != Flight.State.FLYING and flight.message_is_error, "An unprepared aircraft must remain on the runway even with takeoff speed and pitch")

	var touch_and_go = Flight.new(World.new(424242))
	touch_and_go.state = Flight.State.ROLLING
	touch_and_go.engine_running = true
	touch_and_go.speed_kmh = 90.0
	touch_and_go.toggle_engine()
	assert(touch_and_go.departure_authorized, "Stopping the engine during rollout must not revoke authorization before a full stop")
	touch_and_go.toggle_engine()
	assert(touch_and_go.engine_running, "The engine must remain restartable during rollout")
	touch_and_go.throttle = 1.0
	touch_and_go.yoke.y = 1.0
	for frame in 120:
		touch_and_go.update(1.0 / 60.0)
		if touch_and_go.state == Flight.State.FLYING:
			break
	assert(touch_and_go.state == Flight.State.FLYING and touch_and_go.departure_authorized, "Touch-and-go must remain available until the aircraft fully stops")

	var completed_rollout = Flight.new(World.new(424242))
	completed_rollout.state = Flight.State.ROLLING
	completed_rollout.speed_kmh = 0.04
	completed_rollout.update(0.1)
	assert(completed_rollout.state == Flight.State.LANDED and completed_rollout.speed_kmh == 0.0 and not completed_rollout.departure_authorized, "Departure authorization must be revoked only at a complete stop")

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene.flight.state = Flight.State.LANDED
	scene.flight._show_message("Успешная посадка в аэропорту «Тестовый»")
	assert(scene._flight_message_color() == Color("65d48c"), "Successful landing status must be green")
	scene.flight.state = Flight.State.PARKED
	scene.flight._show_message("Обычное сообщение")
	assert(scene._flight_message_color() == Color("e8d274"), "Ordinary information must remain yellow")
	scene.flight.prepare_at_airport(0)
	scene.flight.toggle_engine()
	scene._enter_cabin(true)
	assert(not scene.flight.engine_running and not scene.flight.departure_authorized, "Leaving the pilot seat on the ground must stop and secure the aircraft")

	var parking_money: int = scene.economy.money
	scene._pay_and_prepare(true)
	assert(scene.flight.departure_authorized and scene.economy.money == parking_money - scene.EconomyScript.PARKING_PRICE, "Payment and runway selection must restore departure authorization")
	var selected_heading: float = scene.flight.heading_deg
	scene._enter_cabin(false)
	assert(scene.flight.departure_authorized and is_equal_approx(scene.flight.heading_deg, selected_heading), "Boarding through the cabin after service must preserve the selected runway and authorization")

	print("Departure authorization, touch-and-go, automatic shutdown and blocked start warning: OK")
	quit()
