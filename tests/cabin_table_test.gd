extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	scene._enter_cabin()
	scene.economy.hunger = 3
	scene.economy.carried_item = {"type": "food"}
	scene.scene_player_x = scene._aircraft_point(Vector2(560,0)).x
	scene._handle_inventory_click(scene._carried_action_rect(1).get_center())
	assert(scene.economy.hunger == 3 and not scene.economy.carried_item.is_empty(), "Food must not be edible away from the table")
	var table_click: Vector2 = scene._table_transform() * Vector2(40,-35)
	scene._click_side_scene(table_click)
	assert(scene._at_cabin_table() and not scene.scene_is_walking, "Clicking the table must seat the pilot immediately")
	assert(scene.economy.hunger == 3, "Sitting down must not consume food automatically")
	scene._interact_in_scene()
	assert(scene.economy.hunger == 4 and scene.economy.carried_item.is_empty(), "Enter at the table must eat carried food")
	scene.economy.carried_item = {"type": "food"}
	scene._handle_inventory_click(scene._carried_action_rect(1).get_center())
	assert(scene.economy.hunger == 5 and scene.economy.carried_item.is_empty(), "Eat button at the table must work")
	scene.economy.carried_item = {"type": "canister", "fuel_l": 10.0}
	scene._eat_at_table()
	assert(scene.economy.hunger == 5 and scene.economy.carried_item.type == "canister")
	scene.economy.carried_item = {"type": "food"}
	scene._enter_fuel_bay()
	scene._eat_at_table()
	assert(scene.economy.hunger == 5, "Fuel bay must not permit eating")
	# Clicking the table from the bay must leave it, including in pitched flight.
	scene.flight.state = scene.FlightModelScript.State.FLYING
	scene.flight.pitch_deg = 12.0
	scene._click_side_scene(scene._table_transform() * Vector2(40,-35))
	assert(scene._at_cabin_table() and not scene.in_fuel_bay, "Clicking the table from the fuel bay must seat the pilot")
	scene._eat_at_table()
	assert(scene.economy.hunger == 6)
	scene.economy.carried_item = {"type": "food"}
	scene._eat_at_table()
	assert(not scene.economy.carried_item.is_empty(), "Eating when full must not discard food")
	# Merely reaching/passing the interaction range is ordinary movement and
	# must not trigger the chair unless the furniture itself was clicked.
	scene.cabin_table_seated = false
	scene.scene_player_x = scene._aircraft_point(Vector2(scene.CABIN_TABLE_SEAT_X, 0)).x
	scene._update_scene_walking(0.01)
	assert(scene._near_cabin_table() and not scene._at_cabin_table(), "Passing by the table must not seat the pilot")
	scene._interact_in_scene()
	assert(scene._at_cabin_table())
	Input.action_press("ui_left")
	scene._update_scene_walking(0.01)
	Input.action_release("ui_left")
	assert(not scene._at_cabin_table(), "Arrow movement must leave the chair immediately")
	for mode in [scene.ViewMode.AIRPORT, scene.ViewMode.APRON, scene.ViewMode.COCKPIT]:
		scene.view_mode = mode
		scene.economy.hunger = 3
		scene._eat_at_table()
		assert(scene.economy.hunger == 3 and not scene.economy.carried_item.is_empty())
	print("Cabin table and eating restrictions: OK")
	scene.queue_free()
	quit()
