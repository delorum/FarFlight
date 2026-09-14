extends SceneTree

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var canister_rect := Rect2(10, 20, 24, 24)
	var empty_liquid: Rect2 = scene._canister_liquid_rect(canister_rect, 0.0)
	var half_liquid: Rect2 = scene._canister_liquid_rect(canister_rect, 10.0)
	var full_liquid: Rect2 = scene._canister_liquid_rect(canister_rect, 20.0)
	check(not empty_liquid.has_area(), "Empty canisters must not show liquid")
	check(is_equal_approx(half_liquid.size.y, full_liquid.size.y * 0.5), "Liquid height must reflect the fuel fraction")
	check(half_liquid.end == full_liquid.end, "Canisters must fill from the bottom")
	check(full_liquid == canister_rect.grow(-3.0), "Full liquid must remain inside the canister contour")
	check(scene._canister_liquid_rect(canister_rect, 30.0) == full_liquid, "Liquid must not overflow the canister")
	var time_key := InputEventKey.new()
	time_key.keycode = KEY_Z
	time_key.pressed = true
	time_key.shift_pressed = true
	scene._input(time_key)
	check(scene.time_scale_index == 1, "Shift+Z must cycle time to 2x")
	for expected_index in [2, 3, 4, 0]:
		scene._input(time_key)
		check(scene.time_scale_index == expected_index, "Shift+Z must cycle all time scales and wrap to 1x")
	scene.time_scale_index = 4
	time_key.shift_pressed = false
	scene._input(time_key)
	check(scene.time_scale_index == 0, "Z must immediately restore 1x")
	scene._input(time_key)
	check(scene.time_scale_index == 0, "Repeated Z must keep time at 1x")
	scene.time_scale_index = 3
	var turn_key := InputEventKey.new()
	turn_key.keycode = KEY_RIGHT
	turn_key.pressed = true
	scene._input(turn_key)
	check(scene.time_scale_index == 0, "Aircraft control must reset accelerated time before acting")
	scene.time_scale_index = 4
	var clock_before_scale: float = scene.clock_seconds
	var economy_before_scale: float = scene.economy.elapsed_seconds
	scene._process(1.0)
	check(is_equal_approx(scene.clock_seconds - clock_before_scale, 16.0), "16x must advance the game clock by sixteen seconds per real second")
	check(is_equal_approx(scene.economy.elapsed_seconds - economy_before_scale, 16.0), "16x must advance economic deadlines and needs")
	scene.time_scale_index = 0
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.speed_kmh = 150.0
	scene.flight.altitude_m = 1500.0
	scene.flight.storm_intensity = 0.7
	scene.flight.storm_roll_bias_deg = 5.0
	scene.time_scale_index = 4
	scene._process(1.0 / 60.0)
	check(scene.time_scale_index == 0, "Storm-induced course rotation must immediately reset accelerated time")
	scene.flight.prepare_at_airport(0)
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.position_km = Vector2(100.0, 100.0)
	scene.flight.speed_kmh = 150.0
	scene.flight.altitude_m = scene.world.height_at(scene.flight.position_km) + 1500.0
	scene.world.storms.clear()
	scene.world.storms.append({"origin":scene.flight.position_km, "radius_km":6.0, "intensity":1.0, "drift_kmh":Vector2.ZERO, "radar_lobes":[{"offset_km":Vector2.ZERO, "radius_scale":1.0, "strength":1.0}]})
	scene.flight.storm_intensity = 0.0
	scene.flight.storm_roll_bias_deg = 0.0
	scene.flight.storm_roll_target_deg = 0.0
	scene.flight.storm_disturbance_timer = 0.0
	scene.time_scale_index = 4
	scene._process(1.0 / 60.0)
	check(absf(scene.flight.storm_roll_bias_deg) > 0.01 and scene.time_scale_index == 0, "A newly encountered storm roll inside an accelerated frame must reset time immediately")
	scene.flight.prepare_at_airport(0)
	check(scene._airport_buildings().size() >= 2, "Mail and flight service must always exist")
	scene._set_view_mode(scene.ViewMode.MAIL)
	var offer: Dictionary = scene.economy.offers_at(0)[0]
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(scene.economy.carried_item.get("id") == offer.id, "Clicking an offer must hand parcel to player")
	var original_deadline: float = float(scene.economy.carried_item.urgent_deadline)
	scene.economy.carried_item.urgent_deadline = scene.economy.elapsed_seconds + 42.0
	var carried_caption: String = scene._carried_item_caption(scene.economy.carried_item)
	check(carried_caption.contains(scene.world.airports[int(scene.economy.carried_item.destination)].name), "Carried parcel caption must show its destination")
	check(carried_caption.contains("42 с"), "Carried parcel caption must switch to seconds during the final minute")
	scene.economy.carried_item.urgent_deadline = scene.economy.elapsed_seconds - 1.0
	check(not scene._carried_item_caption(scene.economy.carried_item).contains("срочно"), "Expired urgent time must disappear from the carried parcel caption")
	scene.economy.carried_item.urgent_deadline = original_deadline
	scene._enter_cabin()
	check(scene._handle_inventory_click(scene._inventory_rect(0).get_center()), "Cabin cargo slot must be clickable")
	check(scene.economy.carried_item.is_empty() and scene.economy.inventory[0].get("type") == "parcel", "Parcel must be stored physically")
	var parcel_hover: String = scene._inventory_hover_description(scene._cabin_pose() * scene._inventory_rect(0).get_center())
	check(parcel_hover.begins_with("Посылка • аэропорт"), "Hovering stored cargo must describe its type and destination below the scene")
	check(parcel_hover.contains("оплата %d, срочно %d" % [offer.normal_reward, offer.urgent_reward]), "Parcel hover must show both delivery rewards")
	check(parcel_hover.contains("срочный тариф ещё"), "Parcel hover must show the remaining urgent-rate time")
	scene.economy.elapsed_seconds = float(scene.economy.inventory[0].urgent_deadline) + 1.0
	parcel_hover = scene._inventory_hover_description(scene._cabin_pose() * scene._inventory_rect(0).get_center())
	check(parcel_hover.contains("срочный срок истёк"), "Parcel hover must report an expired urgent deadline")
	check(scene._handle_inventory_click(scene._inventory_rect(0).get_center()), "Stored parcel must be retrievable")
	check(scene.economy.carried_item.get("type") == "parcel", "Parcel must return to hands")
	var destination_airport: int = int(scene.economy.carried_item.destination)
	scene.flight.airport_index = destination_airport
	scene.economy.elapsed_seconds = float(scene.economy.carried_item.urgent_deadline) - 1.0
	var urgent_delivery_button: String = scene._delivery_button_text(scene.economy.carried_item)
	check(urgent_delivery_button.contains("%d монет" % int(scene.economy.carried_item.urgent_reward)) and urgent_delivery_button.contains("срочный тариф"), "Delivery button must show urgent payout and tariff")
	scene.economy.elapsed_seconds = float(scene.economy.carried_item.urgent_deadline) + 1.0
	var normal_delivery_button: String = scene._delivery_button_text(scene.economy.carried_item)
	check(normal_delivery_button.contains("%d монет" % int(scene.economy.carried_item.normal_reward)) and normal_delivery_button.contains("обычный тариф"), "Delivery button must show normal payout and tariff after the urgent deadline")
	scene.economy.carried_item = {}
	var fuel_airport: int = scene.economy.fuel_airports[0]
	scene.flight.airport_index = fuel_airport
	scene._set_view_mode(scene.ViewMode.FUEL)
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(scene.economy.carried_item.get("type") == "canister", "Fuel station must sell an empty canister")
	var station_slider: Rect2 = scene._fuel_slider_rect()
	var station_track_start: float = station_slider.position.x + 18.0
	var station_track_end: float = station_slider.end.x - 18.0
	var slider_press := InputEventMouseButton.new()
	slider_press.button_index = MOUSE_BUTTON_LEFT
	slider_press.pressed = true
	slider_press.position = Vector2(lerpf(station_track_start, station_track_end, 0.25), station_slider.get_center().y)
	scene._handle_mouse_button(slider_press)
	var slider_drag := InputEventMouseMotion.new()
	slider_drag.position = Vector2(lerpf(station_track_start, station_track_end, 0.527), station_slider.get_center().y)
	scene._handle_mouse_motion(slider_drag)
	var slider_release := InputEventMouseButton.new()
	slider_release.button_index = MOUSE_BUTTON_LEFT
	slider_release.pressed = false
	slider_release.position = slider_drag.position
	scene._handle_mouse_button(slider_release)
	var selected: float = scene.fuel_amount_litres
	check(is_equal_approx(selected, 10.5), "Fuel sliders must drag with 0.1 litre precision")
	scene._handle_economy_click(scene._economy_button_rect(2).get_center())
	check(is_equal_approx(float(scene.economy.carried_item.get("fuel_l")), selected), "Fuel slider amount must be purchased")
	scene._set_view_mode(scene.ViewMode.CABIN)
	scene.flight.fuel_l = 28.0
	var fuel_hover_position: Vector2 = scene._fuel_device_transform() * Vector2(20.0, 20.0)
	check(scene._fuel_device_hover_description(fuel_hover_position) == "Топливо в баке: 28.0/40 л", "Hovering the cabin fuel device must show remaining tank fuel")
	scene.in_fuel_bay = true
	scene.flight.fuel_l = 37.3
	scene._set_default_fuel_amount()
	check(is_equal_approx(scene.fuel_amount_litres, 2.7), "Cabin slider must default to and stop at the tank's remaining capacity")
	scene._refuel_from_carried_canister()
	check(is_equal_approx(scene.flight.fuel_l, 40.0) and is_equal_approx(scene.economy.carried_item.fuel_l, selected - 2.7), "Cabin filler must transfer tenths without exceeding tank capacity")
	scene.in_fuel_bay = false
	var scale_button: Vector2 = scene.get_time_scale_button_rect(true).get_center()
	var scale_click := InputEventMouseButton.new()
	scale_click.button_index = MOUSE_BUTTON_LEFT
	scale_click.pressed = true
	scale_click.position = scale_button
	scene._handle_mouse_button(scale_click)
	check(scene.time_scale_index == 1, "Beige time button must select 2x")
	var walk_click := InputEventMouseButton.new()
	walk_click.button_index = MOUSE_BUTTON_LEFT
	walk_click.pressed = true
	walk_click.position = Vector2(scene.size.x * 0.5, scene.size.y * 0.5)
	scene._handle_mouse_button(walk_click)
	check(scene.time_scale_index == 0, "Mouse movement in a side scene must reset accelerated time")
	scene._handle_mouse_button(scale_click)
	var reset_click := InputEventMouseButton.new()
	reset_click.button_index = MOUSE_BUTTON_LEFT
	reset_click.pressed = true
	reset_click.position = scene.get_time_reset_button_rect(true).get_center()
	scene._handle_mouse_button(reset_click)
	check(scene.time_scale_index == 0, "Beige reset button must restore 1x")
	check(not scene.get_time_scale_button_rect(false).intersects(scene.get_ils_rect()), "Cockpit time controls must not cover ILS")
	scene.economy.fatigue = 1
	scene.economy.carried_item = {}
	scene.scene_player_x = scene._aircraft_point(Vector2(735, 0)).x
	scene._interact_in_scene()
	check(scene.cabin_sleeping, "Bed interaction must start continuous rest")
	scene._update_cabin_sleep(scene.EconomyScript.HOTEL_REST_SECONDS)
	check(scene.economy.fatigue == 2 and scene.cabin_sleeping, "Twenty continuous bed minutes must restore one unit up to two")
	scene._stop_cabin_sleep()
	check(not scene.cabin_sleeping and scene.cabin_sleep_progress_seconds == 0.0, "Getting up must reset partial bed rest")
	var bed_click: Vector2 = scene._bed_transform() * Vector2(45.0, 2.0)
	scene._click_side_scene(bed_click)
	check(scene.cabin_sleeping, "Clicking the cabin bed must immediately put the pilot to bed")
	check(is_equal_approx(scene.scene_player_x, scene._aircraft_point(Vector2(735.0, 0)).x), "Bed click must move the pilot onto the bed")
	scene._stop_cabin_sleep()
	scene.scene_player_x = scene._aircraft_point(Vector2(355, 0)).x
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	scene._input(down)
	check(scene.in_fuel_bay, "Down on the ramp must enter the fuel bay")
	check(scene.scene_player_facing > 0.0, "Entering the fuel bay with Down must face the fuel device")
	check(is_equal_approx(scene._cabin_player_position().y, scene._aircraft_point(Vector2(315, scene.AircraftArt.FLOOR_Y)).y), "Fuel bay must keep pilot feet on cabin floor")
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.pressed = true
	scene._input(left)
	check(not scene.in_fuel_bay and scene.scene_player_x < scene._aircraft_point(Vector2(scene.AircraftArt.COCKPIT_RAMP_BOTTOM_X, 0)).x, "Left must exit past the ramp into the cabin")
	scene.scene_player_x = scene._aircraft_point(Vector2(355, 0)).x
	scene._interact_in_scene()
	check(scene.in_fuel_bay, "Enter near the cockpit ramp must open the same fuel interaction as Down and mouse click")
	scene._input(left)
	var fuel_device_click: Vector2 = scene._fuel_device_transform() * Vector2(20.0, 20.0)
	var fuel_device_scene_x: float = (scene._cabin_pose().affine_inverse() * fuel_device_click).x
	scene.scene_player_x = fuel_device_scene_x - 60.0
	scene.scene_player_facing = -1.0
	scene._click_side_scene(fuel_device_click)
	check(scene.in_fuel_bay, "Clicking the cabin fuel device must enter the fuel bay")
	check(scene.scene_player_facing > 0.0, "Entering the fuel bay must face the fuel device")
	scene.scene_player_x = fuel_device_scene_x + 80.0
	scene.scene_player_facing = -1.0
	scene._click_side_scene(fuel_device_click)
	check(scene.in_fuel_bay and scene.scene_player_facing > 0.0, "Clicking the fuel device from its right must still face the tank after entering")
	scene.scene_player_facing = -1.0
	scene._update_scene_walking(0.1)
	check(scene.scene_player_facing > 0.0, "A restored fuel-bay pose must also face the tank")
	var cabin_destination: Vector2 = scene._aircraft_point(Vector2(500.0, scene.AircraftArt.FLOOR_Y))
	scene._click_side_scene(scene._cabin_pose() * cabin_destination)
	check(not scene.in_fuel_bay and is_equal_approx(scene.scene_player_x, cabin_destination.x), "Clicking elsewhere must leave the fuel bay and move the pilot")
	var pointer_left := Vector2(scene.scene_player_x - 50.0, cabin_destination.y)
	scene._click_side_scene(scene._cabin_pose() * pointer_left)
	check(scene.scene_player_facing < 0.0, "Clicking left must turn the pilot left instead of moving backward")
	var pointer_right := Vector2(scene.scene_player_x + 50.0, cabin_destination.y)
	scene._click_side_scene(scene._cabin_pose() * pointer_right)
	check(scene.scene_player_facing > 0.0, "Clicking right must turn the pilot right instead of moving backward")
	scene.in_fuel_bay = true
	scene.economy.carried_item = {"type":"canister", "fuel_l":1.0}
	scene.flight.fuel_l = 39.94
	scene._set_default_fuel_amount()
	check(is_equal_approx(scene.fuel_amount_litres, 0.1), "A fractional final tank gap must offer a 0.1 litre top-off")
	scene._refuel_from_carried_canister()
	check(is_equal_approx(scene.flight.fuel_l, scene.flight.fuel_capacity_l), "The final 0.1 litre selection must fill a fractional remaining gap")
	scene.queue_redraw()
	await process_frame
	print("Economic scenes, physical cargo and canister refuelling: %s" % ("FAIL" if failed else "OK"))
	quit(1 if failed else 0)
