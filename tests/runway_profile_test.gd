extends SceneTree
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const State = preload("res://scripts/ils_display_state.gd")
const Camera = preload("res://scripts/ils_cockpit_projection.gd")
const Practice = preload("res://scripts/landing_practice.gd")
const Save = preload("res://scripts/save_game.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(World.SHORT_RUNWAY_SIZE_KM == Vector2(0.8, 0.02) and World.LEGACY_RUNWAY_SIZE_KM == Vector2(2.0, 0.05), "Both runway profiles must retain their intended dimensions")
	check(World.RUNWAY_SIZE_KM == (World.SHORT_RUNWAY_SIZE_KM if World.USE_SHORT_RUNWAYS else World.LEGACY_RUNWAY_SIZE_KM), "One switch must select both dimensions together")
	var world := World.new(424242)
	world.storms.clear()
	for airport_index in world.airports.size():
		for reverse in [false, true]:
			var flight := Flight.new(world)
			flight.prepare_at_airport(airport_index, reverse)
			var coords: Vector2 = world.runway_coordinates(flight.position_km, world.airports[airport_index])
			check(absf(coords.x) < World.RUNWAY_LENGTH_KM * 0.5 and absf(coords.y) < 0.00001, "Prepared aircraft must start within either runway direction")
	var airport: Dictionary = world.airports[0]
	var forward: Vector2 = world.heading_vector(airport.heading)
	var right := Vector2(forward.y, -forward.x)
	var half_width := World.RUNWAY_WIDTH_KM * 0.5
	for lateral in [half_width - 0.001, half_width + 0.001]:
		var flight := Flight.new(world)
		flight.state = Flight.State.FLYING
		flight.position_km = Vector2(airport.position) + right * lateral
		flight.altitude_m = 0.0
		flight.vertical_speed_mps = -1.0
		flight.speed_kmh = 90
		check(flight._try_land() == (lateral < half_width), "Touchdown eligibility must follow the selected runway edge")
		var forecast := {"valid": true, "safe_landing": true, "distance_from_threshold_km": World.RUNWAY_LENGTH_KM * 0.5, "cross_track_km": lateral}
		check(State.prediction_inside_runway(forecast) == (lateral < half_width), "ILS forecast colour must use the same edge as touchdown physics")
	var rollout := Flight.new(world)
	rollout.state = Flight.State.ROLLING
	rollout.position_km = Vector2(airport.position) + forward * (World.RUNWAY_LENGTH_KM * 0.5 - 0.005)
	rollout.speed_kmh = 90
	rollout.throttle = 0
	rollout.wheel_brakes_applied = true
	for step in 60:
		rollout.update(1.0 / 60.0)
		if rollout.state == Flight.State.CRASHED:
			break
	check(rollout.state == Flight.State.CRASHED, "A late touchdown must retain a real longitudinal overrun risk")
	var practice := Flight.new(world)
	Practice.configure(world, practice)
	var guidance: Dictionary = practice.landing_guidance(practice.airport_index)
	check(is_equal_approx(guidance.signed_distance_to_threshold_km, 6.0), "Landing practice must remain six kilometres from the selected threshold")
	var view := Rect2(0, 0, 500, 500)
	var scale := Camera.localizer_scale_state(view, {"localizer_error": 1.0, "localizer_tolerance_km": half_width + 0.001})
	check(scale.position_severity == 1, "Localizer scale must warn immediately outside the selected runway width")
	_test_save_migration()
	print("Runway profile, starts, touchdown edges, rollout, practice and legacy saves: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)

func _test_save_migration() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var source := Save.capture(game)
	var airport: Dictionary = game.world.airports[0]
	var forward: Vector2 = game.world.heading_vector(airport.heading)
	var right := Vector2(forward.y, -forward.x)
	var old_position: Vector2 = Vector2(airport.position) - forward * 0.78 + right * 0.02
	source.world.erase("runway_size_km")
	source.flight.position_km = old_position
	source.flight.yoke = Vector2(0.2, 0.3)
	source.flight.throttle = 0.4
	source.flight.fuel_l = 19.0
	source.ui.trajectory_last_position = old_position
	source.ui.flight_trajectory[0].position = old_position
	var untouched := source.duplicate(true)
	check(Save.valid(source) and Save.restore(game, source), "Legacy saves without geometry metadata must load")
	var coords: Vector2 = game.world.runway_coordinates(game.flight.position_km, airport)
	check(absf(coords.x) < World.RUNWAY_LENGTH_KM * 0.5 and absf(coords.y) < World.RUNWAY_WIDTH_KM * 0.5, "An old stopped aircraft must be placed inside the selected runway")
	check(game.flight.fuel_l == 19 and game.flight.yoke == Vector2(0.2, 0.3) and game.flight.throttle == 0.4 and game.economy.snapshot() == source.economy, "Compatibility relocation must preserve controls, fuel and economy")
	check(source == untouched, "Migration must not mutate the saved snapshot")
	game._process(0.0)
	check(game.trajectory_distance_km == source.ui.trajectory_distance_km, "Migration must not add artificial flight distance")
	var current := Save.capture(game)
	check(current.world.runway_size_km == World.RUNWAY_SIZE_KM, "New saves must record the geometry used for future profile changes")
	var actual_position: Vector2 = game.flight.position_km
	check(Save.restore(game, current) and game.flight.position_km == actual_position, "Repeated loading under the same profile must not relocate again")
	for state in [Flight.State.FLYING, Flight.State.ROLLING]:
		var moving := source.duplicate(true)
		moving.flight.state = state
		moving.flight.speed_kmh = 90.0
		moving.flight.altitude_m = 234.0 if state == Flight.State.FLYING else 0.0
		check(Save.restore(game, moving) and game.flight.position_km == old_position, "Profile migration must never teleport an airborne or moving aircraft")
	var corrupt := current.duplicate(true)
	corrupt.world.runway_size_km = Vector2(-1, 0.02)
	check(not Save.valid(corrupt), "Invalid saved dimensions must be rejected")
