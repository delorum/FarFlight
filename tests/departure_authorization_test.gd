extends SceneTree

const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var flight = Flight.new(World.new(424242))
	assert(flight.departure_authorized, "A new game must begin prepared for departure")
	assert(not flight.electrical_power, "A prepared aircraft must begin with its electrical power off")
	flight.toggle_engine()
	assert(not flight.engine_running and flight.message_is_error and flight.message == Flight.POWER_REQUIRED_MESSAGE, "The engine must require electrical power")
	flight.toggle_electrical_power()
	flight.toggle_engine()
	assert(flight.engine_running)
	flight.toggle_electrical_power()
	assert(not flight.electrical_power and not flight.engine_running and flight.message == "Питание и двигатель выключены", "Switching master power off must also stop the running engine")
	flight.toggle_electrical_power()
	assert(flight.electrical_power and not flight.engine_running, "Switching master power on must not start the engine")
	flight.toggle_engine()
	assert(flight.engine_running)
	flight.toggle_engine()
	assert(not flight.engine_running and flight.departure_authorized, "Stopping the engine before takeoff must preserve paid departure preparation")
	var fuel_before_power_only: float = flight.fuel_l
	flight.throttle = 1.0
	flight.update(60.0)
	assert(is_equal_approx(flight.fuel_l, fuel_before_power_only), "Powered instruments without a running engine must consume no fuel")
	flight.departure_authorized = false
	flight.toggle_engine()
	assert(not flight.engine_running and flight.message_is_error and flight.message == Flight.DEPARTURE_BLOCKED_MESSAGE, "A blocked start must explain the required payment and runway choice as an error")
	flight.toggle_electrical_power()
	assert(not flight.electrical_power and not flight.departure_authorized, "Electrical power must remain switchable without departure authorization")
	flight.toggle_electrical_power()
	var legacy_power_snapshot := flight.snapshot()
	legacy_power_snapshot.electrical_power = false
	legacy_power_snapshot.engine_running = true
	var restored_legacy_power = Flight.new(World.new(424242))
	assert(restored_legacy_power.restore_snapshot(legacy_power_snapshot, flight.turbulence_rng.state))
	assert(not restored_legacy_power.electrical_power and not restored_legacy_power.engine_running, "Loading an old power-off save must stop its formerly independent engine")

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
	touch_and_go.electrical_power = true
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
	var action_buttons := [scene.get_cabin_button_rect(), scene.get_trajectory_button_rect(), scene.get_weather_briefing_button_rect(), scene.get_power_button_rect(), scene.get_engine_button_rect()]
	var longest_labels := ["САЛОН", "ТР: ВЫКЛ", "ГР: ВЫКЛ", "ВЫКЛЮЧИТЬ ПИТАНИЕ [P]", "ОСТАНОВИТЬ ДВИГАТЕЛЬ [M]"]
	for button_index in action_buttons.size():
		assert(scene.panel_rect().encloses(action_buttons[button_index]), "Every cockpit action button must remain inside the panel")
		var indicator_width := 16.0 if button_index in [3, 4] else 4.0
		var text_width: float = ThemeDB.fallback_font.get_string_size(longest_labels[button_index], HORIZONTAL_ALIGNMENT_CENTER, -1, 7).x
		assert(text_width <= action_buttons[button_index].size.x - indicator_width - 3.0, "Even the longest action label must fit without clipping at the minimum font size")
		for other_index in button_index:
			assert(not action_buttons[other_index].intersects(action_buttons[button_index]), "Cockpit action button labels need separate, non-overlapping bounds")
	var briefing_button: Rect2 = scene.get_weather_briefing_button_rect()
	assert(briefing_button.end.x < scene.get_ils_rect().position.x and scene.panel_rect().encloses(briefing_button), "Weather layer button must fit to the left of ILS")
	assert(ThemeDB.fallback_font.get_string_size("ГР: ВЫКЛ", HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x <= briefing_button.size.x - 7.0, "Weather layer button label must fit at the minimum button font size")
	var power_key := InputEventKey.new()
	power_key.keycode = KEY_NONE
	power_key.physical_keycode = KEY_P
	power_key.pressed = true
	scene._input(power_key)
	assert(scene.flight.electrical_power, "Physical P must turn electrical power on with any keyboard layout")
	scene._input(power_key)
	assert(not scene.flight.electrical_power, "P must toggle electrical power off")
	var power_click := InputEventMouseButton.new()
	power_click.button_index = MOUSE_BUTTON_LEFT
	power_click.pressed = true
	power_click.position = scene.get_power_button_rect().get_center()
	scene._handle_mouse_button(power_click)
	assert(scene.flight.electrical_power, "The cockpit power button must energize the instruments")
	scene.flight.toggle_engine()
	scene._enter_cabin(true)
	assert(not scene.flight.engine_running and scene.flight.departure_authorized, "Leaving the pilot seat before takeoff must stop the engine but preserve preparation")
	scene.flight.departure_authorized = false # Simulate a completed landing and full stop.

	var parking_money: int = scene.economy.money
	scene._pay_and_prepare(true)
	assert(scene.flight.departure_authorized and scene.economy.money == parking_money - scene.EconomyScript.PARKING_PRICE, "Payment and runway selection must restore departure authorization")
	var selected_heading: float = scene.flight.heading_deg
	var money_after_preparation: int = scene.economy.money
	scene.flight.toggle_electrical_power()
	scene.flight.toggle_engine()
	scene._enter_cabin(true)
	assert(not scene.flight.engine_running and scene.flight.departure_authorized and is_equal_approx(scene.flight.heading_deg, selected_heading), "Paid runway preparation must survive starting the engine and returning to the cabin without taking off")
	scene._pay_and_prepare(true)
	assert(scene.economy.money == money_after_preparation and is_equal_approx(scene.flight.heading_deg, selected_heading), "Selecting the already paid runway again must be free and preserve preparation")
	assert(scene.scene_notice.contains("оплата не требуется") and scene._operations_status_text().contains("ВПП %03d°" % roundi(selected_heading)), "Flight service must explain the free repeated choice and show the prepared runway")
	assert(scene._operations_runway_button_text(true).contains("БЕСПЛАТНО") and scene._operations_runway_button_text(false).contains("СМЕНИТЬ ВПП"), "Flight-service buttons must distinguish a free repeated choice from a paid runway change")
	scene._pay_and_prepare(false)
	assert(scene.economy.money == money_after_preparation - scene.EconomyScript.PARKING_PRICE and not is_equal_approx(scene.flight.heading_deg, selected_heading), "Changing the prepared runway must charge for a new preparation")
	selected_heading = scene.flight.heading_deg
	scene._enter_cabin(false)
	assert(scene.flight.departure_authorized and is_equal_approx(scene.flight.heading_deg, selected_heading), "Boarding through the cabin after service must preserve the selected runway and authorization")

	print("Departure authorization, touch-and-go, automatic shutdown and blocked start warning: OK")
	quit()
