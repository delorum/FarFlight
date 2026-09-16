extends SceneTree

const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Economy = preload("res://scripts/economy.gd")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = World.new(424242)
	var flight = Flight.new(world)
	flight.state = Flight.State.FLYING
	flight.speed_kmh = 200.0
	flight.storm_intensity = 0.0
	flight._update_airframe_condition(3600.0)
	check(is_equal_approx(flight.airframe_condition, 99.25), "Ordinary flight must slowly wear the aircraft")

	flight.airframe_condition = 100.0
	flight.speed_kmh = Flight.VNE_KMH
	flight._update_airframe_condition(3600.0)
	check(is_equal_approx(flight.airframe_condition, 100.0 - Flight.NORMAL_WEAR_PER_HOUR - Flight.OVERSPEED_WEAR_PER_HOUR), "Wear above the safe speed must rise quadratically")

	flight.airframe_condition = 100.0
	flight.speed_kmh = 200.0
	flight.storm_intensity = 1.0
	flight._update_airframe_condition(3600.0)
	check(is_equal_approx(flight.airframe_condition, 100.0 - Flight.NORMAL_WEAR_PER_HOUR - Flight.STORM_WEAR_PER_HOUR), "A storm core must add maximum weather wear")

	flight.airframe_condition = 0.01
	flight.storm_intensity = 0.0
	flight._update_airframe_condition(60.0)
	check(flight.state == Flight.State.CRASHED and flight.message.contains("полностью изношена"), "Zero condition must destroy the aircraft in flight")

	var economy = Economy.new(world)
	check(economy.repair_airports.size() == 3, "Exactly three airports must have repair shops")
	check(is_equal_approx(economy.repair_price_per_point(economy.repair_airports[0]), 2.1), "First repair shop must be 30% cheaper")
	check(is_equal_approx(economy.repair_price_per_point(economy.repair_airports[1]), 3.0), "Second repair shop must use the base price")
	check(is_equal_approx(economy.repair_price_per_point(economy.repair_airports[2]), 3.9), "Third repair shop must be 30% dearer")
	var money_before: int = economy.money
	var repaired: float = economy.buy_repair(10.0, economy.repair_airports[0])
	check(is_equal_approx(repaired, 10.0) and economy.money == money_before - 21, "Repair purchase must use the local price")

	var scene: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var repair_airport: int = scene.economy.repair_airports[0]
	check(scene._airframe_bar() == "■■■■■■", "A healthy aircraft must use the same six-square scale as pilot needs")
	scene.flight.airframe_condition = 0.0
	check(scene._airframe_bar() == "□□□□□□", "An exhausted airframe scale must contain six empty squares")
	scene.flight.airport_index = repair_airport
	check(scene._airport_buildings().any(func(building): return building.kind == scene.ViewMode.REPAIR), "Repair airport must draw a dedicated hangar")
	scene.flight.airframe_condition = 80.0
	scene.flight.state = Flight.State.FLYING
	scene.flight.speed_kmh = 220.0
	scene.flight.storm_intensity = 0.0
	check(scene._airframe_indicator_text().contains("80.0% • износ 0.013%/мин"), "Panel must show exact condition and ordinary wear per minute")
	scene.economy.money = 100
	scene._set_view_mode(scene.ViewMode.REPAIR)
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(is_equal_approx(scene.flight.airframe_condition, 100.0) and scene.economy.money == 58, "Repair hangar must restore the aircraft and charge its local rate")

	print("Airframe wear, destruction, repair distribution and pricing: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
