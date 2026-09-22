extends SceneTree

const World = preload("res://scripts/world.gd")
const Economy = preload("res://scripts/economy.gd")

func _init() -> void:
	var world = World.new(424242)
	var initial_wind: Array = world.wind_layers.duplicate(true)
	var economy = Economy.new(world)
	assert(world.wind_layers == initial_wind, "Initial setup must preserve seeded wind")
	assert(economy.fuel_airports.size() == 3)
	assert(economy.food_airports.size() == 3)
	assert(economy.hotel_airports.size() == 3)
	assert(economy.repair_airports.size() == 3)
	assert(economy.visited_airports == [0])
	assert(economy.money == 160)
	assert(is_equal_approx(economy.fuel_price_per_l(economy.fuel_airports[0]), 1.4))
	assert(is_equal_approx(economy.fuel_price_per_l(economy.fuel_airports[1]), 2.0))
	assert(is_equal_approx(economy.fuel_price_per_l(economy.fuel_airports[2]), 2.6))
	assert(economy.food_price(economy.food_airports[0]) == 14)
	assert(economy.food_price(economy.food_airports[1]) == 20)
	assert(economy.food_price(economy.food_airports[2]) == 26)
	assert(economy.hotel_rest_price(economy.hotel_airports[0]) == 7)
	assert(economy.hotel_rest_price(economy.hotel_airports[1]) == 10)
	assert(economy.hotel_rest_price(economy.hotel_airports[2]) == 13)
	var price_memory = Economy.new(world)
	var cheap_food_airport: int = price_memory.food_airports[0]
	var regular_food_airport: int = price_memory.food_airports[1]
	var expensive_food_airport: int = price_memory.food_airports[2]
	price_memory.arrive_at_airport(cheap_food_airport, world)
	price_memory.arrive_at_airport(regular_food_airport, world)
	assert("еда (+)" in price_memory.services_at(cheap_food_airport))
	assert("еда (++)" in price_memory.services_at(regular_food_airport))
	assert("еда" in price_memory.services_at(expensive_food_airport) and "еда (+++)" not in price_memory.services_at(expensive_food_airport), "Unvisited airport prices must remain unknown")
	price_memory.arrive_at_airport(expensive_food_airport, world)
	assert("еда (+++)" in price_memory.services_at(expensive_food_airport))
	var empty_airports := 0
	for airport_index in world.airports.size():
		if economy.optional_service_count(airport_index) == 0:
			empty_airports += 1
	assert(empty_airports <= Economy.MAX_AIRPORTS_WITHOUT_OPTIONAL_SERVICES)
	assert(economy.offers_at(0).size() == 3)
	var destinations := {}
	for offer in economy.offers_at(0):
		assert(int(offer.destination) != 0)
		assert(not destinations.has(offer.destination))
		destinations[offer.destination] = true
		assert(offer.route_distance_km >= offer.direct_distance_km)
		assert(offer.distance_km == offer.route_distance_km)
		assert(offer.poverty_bonus_percent == economy.poverty_bonus_percent(offer.destination))
		var base_reward := Economy.BASE_REWARD_50_KM * pow(float(offer.route_distance_km) / 50.0, Economy.DISTANCE_REWARD_EXPONENT)
		assert(offer.reward == roundi(base_reward * economy.poverty_reward_multiplier(offer.destination)))
		assert(not offer.has("urgent_deadline") and not offer.has("urgent_reward"))
	var parcel: Dictionary = economy.accept_offer(0, 0)
	assert(not parcel.is_empty() and not parcel.has("urgent_deadline"))
	assert(economy.store_carried())
	var second_parcel: Dictionary = economy.accept_offer(0, 0)
	assert(not second_parcel.is_empty() and second_parcel.id != parcel.id, "Multiple orders must be available for one trip")
	assert(economy.store_carried())
	assert(economy.take_slot(0))
	var destination := int(parcel.destination)
	var expected := int(parcel.reward)
	economy.elapsed_seconds += 24.0 * 3600.0
	var delivery: Dictionary = economy.deliver_carried(destination)
	assert(delivery.paid == expected and economy.money >= expected, "Delivery pay must not expire")
	assert(economy.take_slot(1))
	assert(economy.deliver_carried(int(second_parcel.destination)).paid == second_parcel.reward)
	var legacy_parcel: Dictionary = parcel.duplicate(true)
	legacy_parcel.erase("reward")
	legacy_parcel["normal_reward"] = 1
	legacy_parcel["urgent_reward"] = 2
	legacy_parcel["urgent_deadline"] = 0.0
	assert(economy.parcel_reward(legacy_parcel) == expected, "Saved orders from the old tariff must use the new unified price")
	var legacy_mail_save: Dictionary = economy.snapshot()
	legacy_mail_save.carried_item = legacy_parcel
	legacy_mail_save.offers_by_airport[0] = [legacy_parcel]
	var legacy_mail_restored = Economy.new()
	assert(legacy_mail_restored.restore(legacy_mail_save, world))
	assert(legacy_mail_restored.carried_item.reward == expected and not legacy_mail_restored.carried_item.has("urgent_deadline"))
	assert(legacy_mail_restored.offers_at(0)[0].reward == expected and not legacy_mail_restored.offers_at(0)[0].has("urgent_reward"))
	var old_offers: Array = economy.offers_at(0).duplicate(true)
	economy.arrive_at_airport(0, world)
	assert(economy.offers_at(0) == old_offers)
	var initial_storms: Array = world.storms.duplicate(true)
	economy.arrive_at_airport(destination, world)
	assert(economy.offers_at(destination).size() == 3)
	assert(world.wind_layers == initial_wind and world.storms == initial_storms, "Economy arrivals must not mutate physical weather")
	for layer in world.wind_layers:
		assert(layer.speed_kmh >= 8.0 and layer.speed_kmh <= 32.0)
		assert(layer.from_deg >= 0.0 and layer.from_deg <= 360.0)
	var arrival_wind: Array = world.wind_layers.duplicate(true)
	economy.arrive_at_airport(destination, world)
	assert(world.wind_layers == arrival_wind)
	var saved_arrival = Economy.new()
	assert(saved_arrival.restore(economy.snapshot()))
	saved_arrival.arrive_at_airport(destination, world)
	assert(world.wind_layers == arrival_wind, "Restoring a save must preserve the previous-airport rule")
	economy.arrive_at_airport(0, world)
	assert(world.wind_layers == arrival_wind, "Mail offer refreshes must remain independent from weather")
	assert(economy.buy_canister())
	var fuel_money_before: int = economy.money
	assert(is_equal_approx(economy.fill_carried_canister(19.7, economy.fuel_airports[0]), 19.7))
	assert(economy.money == fuel_money_before - 28)
	assert(is_equal_approx(economy.transfer_carried_fuel(7.3, 7.9), 7.3))
	assert(is_equal_approx(economy.carried_item.fuel_l, 12.4))
	assert(is_equal_approx(economy.transfer_carried_fuel(0.1, 0.06), 0.06))
	var snapshot := economy.snapshot()
	var restored = Economy.new()
	assert(restored.restore(snapshot) and restored.snapshot() == snapshot)
	var legacy_snapshot: Dictionary = snapshot.duplicate(true)
	legacy_snapshot.erase("visited_airports")
	var legacy_restored = Economy.new()
	assert(legacy_restored.restore(legacy_snapshot, world) and legacy_restored.last_landed_airport in legacy_restored.visited_airports)
	assert(is_equal_approx(restored.fuel_price_per_l(restored.fuel_airports[2]), 2.6))
	var shopper = Economy.new(world)
	var food_money_before: int = shopper.money
	assert(shopper.buy_food(shopper.food_airports[0]))
	assert(shopper.money == food_money_before - shopper.food_price(shopper.food_airports[0]))
	var needs = Economy.new(world)
	needs.advance_time(3600.0)
	assert(needs.hunger == 5 and needs.fatigue == 5)
	needs.fatigue = 1
	assert(needs.recover_aircraft_bed_unit())
	assert(needs.fatigue == 2)
	assert(not needs.recover_aircraft_bed_unit() and needs.fatigue == 2)
	var money_before_hotel: int = needs.money
	var hotel_airport: int = needs.hotel_airports[2]
	assert(needs.buy_hotel_rest(hotel_airport))
	assert(needs.fatigue == 3 and needs.money == money_before_hotel - needs.hotel_rest_price(hotel_airport))
	needs.fatigue = Economy.NEED_SEGMENTS
	var full_rest_time: float = needs.elapsed_seconds
	var full_rest_money: int = needs.money
	assert(needs.buy_hotel_rest(hotel_airport), "A full-rest pilot must still be allowed to pay for hotel time")
	assert(is_equal_approx(needs.elapsed_seconds - full_rest_time, Economy.HOTEL_REST_SECONDS))
	assert(needs.fatigue == Economy.NEED_SEGMENTS and needs.money == full_rest_money - needs.hotel_rest_price(hotel_airport))
	needs.advance_time(3600.0, true)
	assert(needs.fatigue == Economy.NEED_SEGMENTS and needs.hunger == 4)
	print("economy_test: OK")
	quit()
