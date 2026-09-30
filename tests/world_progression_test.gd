extends SceneTree

const World = preload("res://scripts/world.gd")
const Economy = preload("res://scripts/economy.gd")
const SaveGame = preload("res://scripts/save_game.gd")
const WorldProgression = preload("res://scripts/world_progression.gd")

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for seed_value in [424242, 21001, 21050, 21100]:
		var starting_world = WorldProgression.initial_world(seed_value)
		check(starting_world != null and starting_world.exit_portal.is_empty(), "The initial chart must hide its prevalidated exit")
		check(starting_world.all_airports_route_connected() and starting_world.ensure_exit_portal(), "Every started campaign must have connected airports and a reachable future exit")
		check(WorldProgression.initial_world(seed_value).seed_value == starting_world.seed_value, "Starting-world fallback must be reproducible from the requested seed")
		if seed_value == 424242:
			check(starting_world.seed_value == seed_value, "A playable explicit seed must not be replaced")
	var world = World.new(424242)
	var economy = Economy.new(world)
	check(economy.remaining_parcels_at(0) == 7 and economy.offers_at(0).size() == 3, "Each airport must start with seven unique outgoing parcels and show three")
	var initial_other_ids := [economy.offers_at(0)[1].id, economy.offers_at(0)[2].id]
	var first_taken: Dictionary = economy.accept_offer(0, 0)
	check(not first_taken.is_empty() and economy.offers_at(0).any(func(offer): return offer.id == initial_other_ids[0]) and economy.offers_at(0).any(func(offer): return offer.id == initial_other_ids[1]), "Accepting one offer must keep the other two visible while filling the free slot")
	economy.discard_carried()
	check(economy.remaining_parcels_at(0) == 7, "Cancelling an undelivered order must return it to the finite stock")
	economy = Economy.new(world)
	for origin in world.airports.size():
		var picked := {}
		for pickup in 7:
			economy.arrive_at_airport(origin, world)
			check(economy.offers_at(origin).size() == mini(3, 7 - pickup), "Mail offers must refill from the finite stock")
			var parcel: Dictionary = economy.accept_offer(origin, 0)
			check(not parcel.is_empty() and not picked.has(parcel.destination), "An origin-destination parcel must never be offered twice")
			picked[parcel.destination] = true
			check(economy.remaining_parcels_at(origin) == 6 - pickup, "Accepting mail must consume exactly one parcel from that airport")
			economy.deliver_carried(int(parcel.destination))
		check(economy.offers_at(origin).is_empty(), "An exhausted post office must stay empty")
	var same_seed_world = World.new(424242)
	check(world.ensure_exit_portal() and same_seed_world.ensure_exit_portal() and world.exit_portal == same_seed_world.exit_portal, "The next-map exit must be reproducible from the world seed")

	var game: Control = load("res://scenes/main.tscn").instantiate()
	game.requested_world_seed = 424242
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._set_view_mode(game.ViewMode.MAIL)
	var money_before_locked_exit: int = game.economy.money
	check(WorldProgression.transition(game.world, game.flight, game.economy, game.simulation).is_empty() and game.economy.money == money_before_locked_exit and game.flight.world == game.world, "A locked exit must leave campaign state untouched")
	var airport_screen: Vector2 = game.navigation_map.world_to_screen(Vector2(game.world.airports[0].position))
	check(game.navigation_map.map_footer_text_at(airport_screen).contains("пос. 7"), "The map hover line must show a concise remaining-parcel count")
	check(not game.world.crossed_exit(Vector2(-1.0, 100.0)), "No level exit may work before the mail objective")
	for delivery_index in Economy.DELIVERIES_TO_UNLOCK_EXIT:
		var origin := delivery_index / 7
		game.economy.arrive_at_airport(origin, game.world)
		var parcel: Dictionary = game.economy.accept_offer(origin, 0)
		game.flight.airport_index = int(parcel.destination)
		game._handle_economy_click(game._economy_button_rect(0).get_center())
		check(game.economy.deliveries_on_map == delivery_index + 1, "Every delivered parcel must advance the current-map objective")
		check(game.world.exit_portal.is_empty() == (delivery_index + 1 < Economy.DELIVERIES_TO_UNLOCK_EXIT), "The exit must appear on exactly the sixteenth delivery")
	var portal: Dictionary = game.world.exit_portal
	check(not portal.is_empty() and game.world.height_at(Vector2(portal.position)) <= World.ROUTE_CEILING_M - World.ROUTE_CLEARANCE_M, "The exit must be on reachable low ground")
	check(SaveGame.valid(SaveGame.capture(game)), "An unlocked exit must be valid in a save")
	var crossing: Vector2 = game.world.edge_position(String(portal.side), float(portal.coordinate), -0.1)
	check(game.world.crossed_exit(crossing), "Crossing the marked edge must be recognized")
	var outward: Vector2 = {"right": Vector2.RIGHT, "left": Vector2.LEFT, "top": Vector2.UP, "bottom": Vector2.DOWN}[String(portal.side)]
	check(not game.world.reached_exit(Vector2(portal.position), -outward * 0.01), "Flying inward across the marker must not cause an accidental transition")
	game.flight.state = game.FlightModelScript.State.FLYING
	game.flight.position_km = game.world.edge_position(String(portal.side), float(portal.coordinate), World.EDGE_INSET_KM + 0.1)
	game.flight.heading_deg = {"right": 90.0, "left": 270.0, "top": 0.0, "bottom": 180.0}[String(portal.side)]
	game.flight.speed_kmh = 170.0
	game.flight.altitude_m = 700.0
	game.flight.fuel_l = 40.0
	game.flight.engine_running = true
	game.flight.electrical_power = true
	game.flight.update(1.0)
	check(game.flight.world_exit_reached and game.flight.state == game.FlightModelScript.State.FLYING, "Flying outward through the marked point must request a map transition without waiting for the boundary")
	game.flight.airframe_condition = 63.0
	game.flight.fuel_l = 23.0
	game.economy.money = 777
	var old_seed: int = game.world.seed_value
	var old_side: String = portal.side
	game._transition_to_next_world()
	check(game.world.level_index == 1 and game.world.seed_value != old_seed, "The exit must generate a distinct second map")
	check(game.flight.world == game.world and game.flight.state == game.FlightModelScript.State.FLYING, "The aircraft must remain airborne in the new world")
	check(game.flight.fuel_l == 23.0 and game.flight.airframe_condition == 63.0 and game.economy.money == 777, "Fuel, damage and money must survive a map transition")
	check(game.economy.deliveries_on_map == 0 and game.economy.remaining_parcels_at(0) == 7, "A new map must receive a fresh finite mail objective")
	check(game.economy.total_deliveries == 16, "The lifetime delivery counter must not reset with the map objective")
	var entry_side := World.opposite_edge(old_side)
	var entry: Vector2 = game.flight.position_km
	check(entry.distance_to(game.world.edge_position(entry_side, entry.y if entry_side in ["left", "right"] else entry.x)) < 0.1, "The new flight must begin at the opposite edge")
	check(game.world.height_at(entry) + World.ROUTE_CLEARANCE_M <= World.ROUTE_CEILING_M, "The new entry must leave safe altitude clearance")
	var saved: Dictionary = SaveGame.capture(game)
	check(SaveGame.valid(saved), "Progress and new-world data must form a valid save")
	var restored: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(restored)
	await process_frame
	restored.set_process(false)
	check(SaveGame.restore(restored, saved), "The new map and its finite mail stock must reload")
	check(restored.world.level_index == 1 and restored.economy.remaining_parcels_at(0) == 7 and restored.economy.total_deliveries == 16, "Reloaded progress and lifetime deliveries must stay on the new map")
	var second_seed: int = restored.world.seed_value
	check(restored.world.ensure_exit_portal(), "The second map must also offer a reachable exit after its mail objective")
	restored._transition_to_next_world()
	check(restored.world.level_index == 2 and restored.world.seed_value != second_seed and restored.economy.remaining_parcels_at(0) == 7, "Successive maps must keep generating with fresh mail stock")
	print("Finite mail, sixteen-delivery exit, reachable world transition and save: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
