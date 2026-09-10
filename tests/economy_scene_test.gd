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
	check(scene._airport_buildings().size() >= 2, "Mail and flight service must always exist")
	scene._set_view_mode(scene.ViewMode.MAIL)
	var offer: Dictionary = scene.economy.offers_at(0)[0]
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(scene.economy.carried_item.get("id") == offer.id, "Clicking an offer must hand parcel to player")
	scene._enter_cabin()
	check(scene._handle_inventory_click(scene._inventory_rect(0).get_center()), "Cabin cargo slot must be clickable")
	check(scene.economy.carried_item.is_empty() and scene.economy.inventory[0].get("type") == "parcel", "Parcel must be stored physically")
	check(scene._handle_inventory_click(scene._inventory_rect(0).get_center()), "Stored parcel must be retrievable")
	check(scene.economy.carried_item.get("type") == "parcel", "Parcel must return to hands")
	scene.economy.carried_item = {}
	var fuel_airport: int = scene.economy.fuel_airports[0]
	scene.flight.airport_index = fuel_airport
	scene._set_view_mode(scene.ViewMode.FUEL)
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(scene.economy.carried_item.get("type") == "canister", "Fuel station must sell an empty canister")
	scene._set_fuel_amount_from_mouse(Vector2(scene._fuel_slider_rect().get_center().x, scene._fuel_slider_rect().get_center().y))
	var selected: int = scene.fuel_amount_litres
	scene._handle_economy_click(scene._economy_button_rect(2).get_center())
	check(scene.economy.carried_item.get("fuel_l") == selected, "Fuel slider amount must be purchased")
	scene._set_view_mode(scene.ViewMode.CABIN)
	scene.in_fuel_bay = true
	scene.flight.fuel_l = 0.0
	scene._refuel_from_carried_canister()
	check(scene.flight.fuel_l == selected and scene.economy.carried_item.fuel_l == 0, "Cabin filler must transfer selected litres")
	scene.queue_redraw()
	await process_frame
	print("Economic scenes, physical cargo and canister refuelling: %s" % ("FAIL" if failed else "OK"))
	quit(1 if failed else 0)
