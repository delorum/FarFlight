extends SceneTree
const World = preload("res://scripts/world.gd")
const Economy = preload("res://scripts/economy.gd")
const Save = preload("res://scripts/save_game.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world := World.new(424242)
	var economy := Economy.new(world)
	economy.advance_parking(1199, 0)
	check(economy.money == 160 and economy.parking_amount_due() == 0, "First twenty minutes must be free")
	economy.advance_parking(1, 0)
	check(economy.money == 160 and economy.parking_amount_due() == 6, "A completed period must accrue six coins without withdrawing money")
	economy.advance_parking(300, 0)
	check(economy.pay_parking() and economy.money == 154 and economy.parking_amount_due() == 0, "Payment at 25 minutes must cover the current period")
	check(economy.pay_parking() and economy.money == 154, "Repeated payment must not double-charge")
	economy.advance_parking(899, 0)
	check(economy.parking_amount_due() == 0, "Payment must remain valid until 40 minutes")
	economy.advance_parking(1, 0)
	check(economy.parking_amount_due() == 6, "At 40 minutes only the next unpaid period must be due")
	economy.money = 5
	check(not economy.pay_parking() and economy.money == 5 and economy.parking_paid_periods == 1, "Insufficient funds must leave both money and paid periods unchanged")
	economy.advance_parking(1200, 0)
	check(economy.parking_amount_due() == 12 and economy.money == 5, "Long stays must accumulate unpaid periods without automatic withdrawals")
	var data := economy.snapshot()
	var restored := Economy.new(world)
	check(restored.restore(data, world) and restored.parking_amount_due() == 12, "Saves must preserve elapsed time and paid periods")
	for invalid in [NAN, INF, -1.0, "bad"]:
		var broken := data.duplicate(true)
		broken.parking_elapsed_seconds = invalid
		check(not restored.restore(broken, world), "Corrupt parking time must be rejected")
	var broken := data.duplicate(true)
	broken.parking_paid_periods = 100
	check(not restored.restore(broken, world), "Saves must not prepay future parking periods")
	var legacy := data.duplicate(true)
	for field in ["parking_airport", "parking_elapsed_seconds", "parking_paid_periods"]:
		legacy.erase(field)
	check(restored.restore(legacy, world) and restored.parking_elapsed_seconds == 0 and restored.parking_amount_due() == 0, "Pre-parking saves must start a fresh free period")
	economy.advance_parking(0, -1)
	economy.advance_parking(1199, 0)
	check(economy.parking_amount_due() == 0 and economy.parking_paid_periods == 0, "Returning to the same airport must start a fresh stay")
	economy.advance_parking(2401, 0)
	check(economy.parking_amount_due() == 18, "One hour must cost eighteen coins")
	economy.advance_to_world(World.new(515151))
	check(economy.parking_elapsed_seconds == 0 and economy.parking_amount_due() == 0, "World transitions must clear the previous stay")
	_test_game()
	print("Manual parking payment, 20-minute periods, clearance, rest and saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)

func _test_game() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	if not game.has_method("_pay_airport_stay"):
		check(false, "Game scene must load its parking payment implementation")
		game.free()
		return
	root.add_child(game)
	game.set_process(false)
	game.economy.money = 1000
	game.economy.parking_elapsed_seconds = 1199
	game.simulation_paused = true
	game._process(1)
	check(game.economy.parking_elapsed_seconds == 1199, "Pause must freeze parking time")
	game.simulation_paused = false
	game.time_scale_index = 4
	game._process(1)
	check(is_equal_approx(game.economy.parking_elapsed_seconds, 1215) and game.economy.money == 1000 and not game.flight.parking_clearance, "Accelerated time must accrue parking without withdrawing funds")
	game.time_scale_index = 0
	game.flight.electrical_power = true
	game.flight.toggle_engine()
	check(not game.flight.engine_running and game.flight.message.contains("стоянку"), "Starting an engine for departure must require parking payment")
	game._set_view_mode(game.ViewMode.OPERATIONS)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = game.side_scenes.get_operations_parking_rect().get_center()
	game.simulation_paused = true
	game._handle_mouse_button(click)
	check(game.economy.money == 1000, "Pause must block parking payment")
	game.simulation_paused = false
	game._handle_mouse_button(click)
	check(game.economy.money == 994 and game.flight.parking_clearance and game.economy.parking_amount_due() == 0, "Flight service payment button must settle parking and grant clearance")
	var elapsed: float = game.economy.parking_elapsed_seconds
	game.flight.departure_authorized = false
	game._pay_and_prepare(false)
	check(game.economy.money == 982 and game.economy.parking_elapsed_seconds == elapsed, "Preparation must cost twelve coins separately without resetting parking")
	game._pay_and_prepare(false)
	check(game.economy.money == 982, "Preparing the already selected runway must remain free")
	game.simulation.skip_bed_rest(game.flight, game.economy)
	check(game.economy.money == 982 and game.economy.parking_amount_due() == 6 and not game.flight.parking_clearance, "Bed skips must accrue the next fee without changing money or paid preparation")
	var hotel_price: int = game.economy.hotel_rest_price(game.flight.airport_index)
	game.simulation.rest_at_hotel(game.flight, game.economy)
	check(game.economy.money == 982 - hotel_price and game.economy.parking_amount_due() == 12, "Hotel rest must charge only accommodation and accrue parking separately")
	var saved := Save.capture(game)
	check(Save.valid(saved) and Save.restore(game, saved) and game.economy.parking_amount_due() == 12 and not game.flight.parking_clearance, "Loading must preserve fees and immediately restore departure restrictions")
	saved.economy.parking_paid_periods = -1
	check(not Save.valid(saved), "Save validation must reject corrupt paid periods")
	game.flight.state = game.FlightModelScript.State.LANDED
	game.flight.engine_running = true
	game.flight.departure_authorized = true
	game.flight.throttle = 1
	game.flight.speed_kmh = 80
	game.flight.pitch_deg = 10
	game.flight.yoke.y = 1
	game.simulation.advance(game.SimulationSession.MAX_STEP, game.flight, game.economy, game.recorder, false)
	check(game.flight.state != game.FlightModelScript.State.FLYING and game.flight.departure_authorized, "Unpaid new periods must block liftoff without cancelling paid preparation")
	game._pay_airport_stay()
	game.flight.speed_kmh = 80
	game.flight.pitch_deg = 10
	game.simulation.advance(game.SimulationSession.MAX_STEP, game.flight, game.economy, game.recorder, false)
	check(game.flight.state == game.FlightModelScript.State.FLYING and game.economy.parking_elapsed_seconds == 0, "Paid parking must permit liftoff and end the stay")
	var language: String = game.Localization.language
	game.Localization.set_language(game.Localization.ENGLISH, false)
	check(game.Localization.text(game._operations_parking_button_text()).begins_with("PARKING:"), "Flight service parking display must be localized")
	game.Localization.set_language(language, false)
