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
	check(is_equal_approx(flight.airframe_condition, 100.0 - 100.0 / 6.0), "Ordinary flight must consume one of six airframe squares per hour")

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
	_test_touchdown_damage(world)

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
	check(scene._airframe_bar() == "■■■■■■", "A healthy aircraft must show six airframe squares")
	scene.flight.airframe_condition = 100.0 - Flight.NORMAL_WEAR_PER_HOUR
	check(scene._airframe_bar() == "■■■■■□", "One ordinary flight hour must empty exactly one airframe square")
	scene.flight.airframe_condition = 0.0
	check(scene._airframe_bar() == "□□□□□□", "An exhausted airframe scale must contain six empty squares")
	scene.flight.airport_index = repair_airport
	check(scene._airport_buildings().any(func(building): return building.kind == scene.ViewMode.REPAIR), "Repair airport must draw a dedicated hangar")
	scene.flight.airframe_condition = 80.0
	scene.flight.state = Flight.State.FLYING
	scene.flight.speed_kmh = 220.0
	scene.flight.storm_intensity = 0.0
	check(scene._airframe_indicator_text().contains("80.0% • износ 0.278%/мин"), "Panel must show exact condition and ordinary wear per minute")
	scene.economy.money = 100
	scene._set_view_mode(scene.ViewMode.REPAIR)
	scene._handle_economy_click(scene._economy_button_rect(0).get_center())
	check(is_equal_approx(scene.flight.airframe_condition, 100.0) and scene.economy.money == 58, "Repair hangar must restore the aircraft and charge its local rate")

	print("Airframe wear, destruction, repair distribution and pricing: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)

func _test_touchdown_damage(world) -> void:
	var previous_damage := -1.0
	for sink in [1.99, 2.0, 3.0, 5.49]:
		var landing = Flight.new(world)
		landing.position_km = Vector2(world.airports[0].position)
		landing.altitude_m = 0.0
		landing.speed_kmh = 100.0
		landing.vertical_speed_mps = -sink
		landing.state = Flight.State.FLYING
		check(landing._try_land() and landing.state == Flight.State.ROLLING, "Nonfatal runway contact must enter ground roll")
		var damage := Flight.touchdown_damage(-sink)
		check(is_equal_approx(landing.airframe_condition, 100.0 - damage), "Hard touchdown must deduct its impact damage exactly once")
		check(damage > previous_damage, "Impact damage must increase with descent speed")
		check(damage == 0.0 if sink < 2.0 else landing.message.contains("планер −"), "Soft contact must be undamaged; hard contact must report the loss")
		landing._update_airframe_condition(60.0)
		check(is_equal_approx(landing.airframe_condition, 100.0 - damage), "Ground roll must not apply touchdown damage again")
		var restored = Flight.new(world)
		check(restored.restore_snapshot(landing.snapshot(), landing.turbulence_rng.state) and is_equal_approx(restored.airframe_condition, landing.airframe_condition), "Touchdown damage must survive the existing save format")
		previous_damage = damage
	check(is_equal_approx(Flight.touchdown_damage(-2.0), 2.0), "The hard-touchdown boundary must cost two condition points")
	var worn = Flight.new(world)
	worn.position_km = Vector2(world.airports[0].position)
	worn.state = Flight.State.FLYING
	worn.airframe_condition = 1.0
	worn.vertical_speed_mps = -2.0
	check(worn._try_land() and worn.state == Flight.State.CRASHED and worn.airframe_condition == 0.0, "A hard touchdown must destroy an airframe with insufficient condition")
	var fatal = Flight.new(world)
	fatal.position_km = Vector2(world.airports[0].position)
	fatal.state = Flight.State.FLYING
	fatal.vertical_speed_mps = -5.5
	check(not fatal._try_land(), "The existing fatal descent-speed limit must remain unchanged")
