class_name EconomyModel
extends RefCounted

const INVENTORY_CAPACITY := 6
const NEED_SEGMENTS := 6
const CANISTER_CAPACITY_L := 20
const FUEL_PRICE_PER_L := 2
const CANISTER_PRICE := 15
const FOOD_PRICE := 20
const HOTEL_PRICE := 30
const HOTEL_REST_SECONDS := 20.0 * 60.0
const HOTEL_REST_PRICE := HOTEL_PRICE / 3
const SERVICE_PRICE_MULTIPLIERS := [0.7, 1.0, 1.3]
const REPAIR_PRICE_PER_POINT := 3.0
const PARKING_PRICE := 12
const BASE_REWARD_50_KM := 60
const URGENT_MULTIPLIER := 2
const DEADLINE_SPEED_KMH := 130.0
const DEADLINE_RESERVE_SECONDS := 10.0 * 60.0
const POVERTY_REWARD_MULTIPLIERS := [1.35, 1.20, 1.10, 1.0, 1.0]
const MAX_AIRPORTS_WITHOUT_OPTIONAL_SERVICES := 2

var money := 160
var hunger := 6
var fatigue := 6
var elapsed_seconds := 0.0
var need_accumulator_seconds := 0.0
var inventory: Array[Dictionary] = []
var carried_item: Dictionary = {}
var offers_by_airport: Dictionary = {}
var fuel_airports: Array[int] = []
var food_airports: Array[int] = []
var hotel_airports: Array[int] = []
var repair_airports: Array[int] = []
var visited_airports: Array[int] = []
var last_landed_airport := -1
var next_parcel_id := 1
var game_over_reason := ""

func _init(world = null) -> void:
	for _slot in INVENTORY_CAPACITY:
		inventory.append({})
	if world != null:
		configure_world(world)

func configure_world(world) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.seed_value) ^ 0x51EC0
	fuel_airports = _pick_three(rng, world.airports.size())
	food_airports = _pick_three(rng, world.airports.size())
	hotel_airports = _pick_three(rng, world.airports.size())
	repair_airports = _generate_repair_airports(world)
	_balance_service_coverage(world.airports.size())
	arrive_at_airport(0, world)

func _generate_repair_airports(world) -> Array[int]:
	# A separate seed keeps the established fuel/food/hotel distribution stable
	# when repair shops are added to an existing world or save.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.seed_value) ^ 0x7A11F
	return _pick_three(rng, world.airports.size())

func _pick_three(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var pool: Array[int] = []
	for index in count:
		pool.append(index)
	for index in range(pool.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value := pool[index]
		pool[index] = pool[other]
		pool[other] = value
	var result: Array[int] = []
	for index in mini(3, pool.size()):
		result.append(pool[index])
	return result

func services_at(airport_index: int) -> Array[String]:
	var result: Array[String] = ["почта", "лётная служба"]
	if airport_index in fuel_airports:
		result.append(_known_price_label("топливо", fuel_airports, airport_index))
	if airport_index in food_airports:
		result.append(_known_price_label("еда", food_airports, airport_index))
	if airport_index in hotel_airports:
		result.append(_known_price_label("гостиница", hotel_airports, airport_index))
	if airport_index in repair_airports:
		result.append(_known_price_label("ремонт", repair_airports, airport_index))
	return result

func _known_price_label(label: String, service_airports: Array[int], airport_index: int) -> String:
	if airport_index not in visited_airports:
		return label
	var known_airports: Array[int] = []
	# Service arrays are stored in ascending price order. Filtering that array by
	# visited locations therefore ranks only prices the pilot has actually seen.
	for service_airport in service_airports:
		if service_airport in visited_airports:
			known_airports.append(service_airport)
	if known_airports.size() < 2:
		return label
	var known_rank := known_airports.find(airport_index)
	if known_rank < 0:
		return label
	var price_marks := ""
	for _mark in known_rank + 1:
		price_marks += "+"
	return "%s (%s)" % [label, price_marks]

func optional_service_count(airport_index: int) -> int:
	var count := 0
	for service_airports in [fuel_airports, food_airports, hotel_airports, repair_airports]:
		if airport_index in service_airports:
			count += 1
	return count

func poverty_reward_multiplier(airport_index: int) -> float:
	var count := clampi(optional_service_count(airport_index), 0, POVERTY_REWARD_MULTIPLIERS.size() - 1)
	return float(POVERTY_REWARD_MULTIPLIERS[count])

func poverty_bonus_percent(airport_index: int) -> int:
	return roundi((poverty_reward_multiplier(airport_index) - 1.0) * 100.0)

func _balance_service_coverage(airport_count: int) -> void:
	# Preserve three locations and their cheap/normal/expensive array positions,
	# but prevent a random world from filling a few hubs and leaving most of the
	# map devoid of useful stops.
	while true:
		var empty_airports: Array[int] = []
		for airport_index in airport_count:
			if optional_service_count(airport_index) == 0:
				empty_airports.append(airport_index)
		if empty_airports.size() <= MAX_AIRPORTS_WITHOUT_OPTIONAL_SERVICES:
			return
		var target := empty_airports[0]
		var moved := false
		for service_airports in [fuel_airports, food_airports, hotel_airports, repair_airports]:
			for tier in range(service_airports.size() - 1, -1, -1):
				var donor := int(service_airports[tier])
				if optional_service_count(donor) > 1:
					service_airports[tier] = target
					moved = true
					break
			if moved:
				break
		if not moved:
			return

func _service_price_multiplier(service_airports: Array[int], airport_index: int) -> float:
	# The shuffled array order is part of the saved world: cheap, regular, expensive.
	var tier := service_airports.find(airport_index)
	if tier < 0 or tier >= SERVICE_PRICE_MULTIPLIERS.size():
		return 1.0
	return float(SERVICE_PRICE_MULTIPLIERS[tier])

func fuel_price_per_l(airport_index: int) -> float:
	return float(FUEL_PRICE_PER_L) * _service_price_multiplier(fuel_airports, airport_index)

func fuel_purchase_cost(litres: float, airport_index: int) -> int:
	return ceili(maxf(0.0, litres) * fuel_price_per_l(airport_index))

func food_price(airport_index: int) -> int:
	return roundi(float(FOOD_PRICE) * _service_price_multiplier(food_airports, airport_index))

func hotel_rest_price(airport_index: int) -> int:
	return roundi(float(HOTEL_REST_PRICE) * _service_price_multiplier(hotel_airports, airport_index))

func repair_price_per_point(airport_index: int) -> float:
	return REPAIR_PRICE_PER_POINT * _service_price_multiplier(repair_airports, airport_index)

func repair_cost(condition_points: float, airport_index: int) -> int:
	return ceili(maxf(0.0, condition_points) * repair_price_per_point(airport_index))

func buy_repair(requested_points: float, airport_index: int) -> float:
	var price_per_point := repair_price_per_point(airport_index)
	var affordable := floorf(float(money) / price_per_point * 10.0 + 0.0001) / 10.0
	var repaired := minf(maxf(0.0, requested_points), affordable)
	if repaired <= 0.0:
		return 0.0
	money -= repair_cost(repaired, airport_index)
	return repaired

func arrive_at_airport(airport_index: int, world) -> void:
	if airport_index not in visited_airports:
		visited_airports.append(airport_index)
	if airport_index == last_landed_airport:
		return
	last_landed_airport = airport_index
	offers_by_airport[airport_index] = _generate_offers(airport_index, world)

func _generate_offers(origin: int, world) -> Array[Dictionary]:
	var candidates: Array[int] = []
	for index in world.airports.size():
		if index != origin:
			candidates.append(index)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.seed_value) ^ (origin + 1) * 7919 ^ int(elapsed_seconds * 10.0) ^ next_parcel_id * 104729
	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = value
	var offers: Array[Dictionary] = []
	for candidate_index in mini(3, candidates.size()):
		var destination := candidates[candidate_index]
		var direct_distance: float = Vector2(world.airports[origin].position).distance_to(Vector2(world.airports[destination].position))
		var route_distance: float = world.planned_route_distance_km(origin, destination)
		if not is_finite(route_distance):
			# Explicitly seeded legacy worlds can predate the route rules. Avoid an
			# impossible deadline while still allowing their old saves to continue.
			route_distance = direct_distance
		var poverty_multiplier := poverty_reward_multiplier(destination)
		var normal_reward := maxi(1, roundi(BASE_REWARD_50_KM * pow(route_distance / 50.0, 1.12) * poverty_multiplier))
		offers.append({
			"type": "parcel", "id": next_parcel_id, "origin": origin,
			"destination": destination, "distance_km": route_distance,
			"direct_distance_km": direct_distance, "route_distance_km": route_distance,
			"destination_service_count": optional_service_count(destination),
			"poverty_bonus_percent": poverty_bonus_percent(destination),
			"normal_reward": normal_reward,
			"urgent_reward": normal_reward * URGENT_MULTIPLIER,
			"accepted_at": -1.0, "urgent_deadline": -1.0,
		})
		next_parcel_id += 1
	return offers

func offers_at(airport_index: int) -> Array:
	return offers_by_airport.get(airport_index, [])

func accept_offer(airport_index: int, offer_index: int) -> Dictionary:
	if not carried_item.is_empty():
		return {}
	var offers: Array = offers_at(airport_index)
	if offer_index < 0 or offer_index >= offers.size():
		return {}
	var parcel: Dictionary = offers.pop_at(offer_index).duplicate(true)
	parcel.accepted_at = elapsed_seconds
	var route_distance := float(parcel.get("route_distance_km", parcel.distance_km))
	parcel.urgent_deadline = elapsed_seconds + route_distance / DEADLINE_SPEED_KMH * 3600.0 + DEADLINE_RESERVE_SECONDS
	carried_item = parcel
	offers_by_airport[airport_index] = offers
	return parcel

func first_empty_slot() -> int:
	for index in inventory.size():
		if inventory[index].is_empty():
			return index
	return -1

func store_carried(slot: int = -1) -> bool:
	if carried_item.is_empty():
		return false
	if slot < 0:
		slot = first_empty_slot()
	if slot < 0 or slot >= inventory.size() or not inventory[slot].is_empty():
		return false
	inventory[slot] = carried_item
	carried_item = {}
	return true

func take_slot(slot: int) -> bool:
	if not carried_item.is_empty() or slot < 0 or slot >= inventory.size() or inventory[slot].is_empty():
		return false
	carried_item = inventory[slot]
	inventory[slot] = {}
	return true

func discard_carried() -> void:
	carried_item = {}

func deliver_carried(airport_index: int) -> Dictionary:
	if carried_item.get("type", "") != "parcel" or int(carried_item.get("destination", -1)) != airport_index:
		return {}
	var urgent: bool = elapsed_seconds <= float(carried_item.urgent_deadline)
	var reward := int(carried_item.urgent_reward if urgent else carried_item.normal_reward)
	var result := carried_item.duplicate(true)
	result["urgent"] = urgent
	result["paid"] = reward
	money += reward
	carried_item = {}
	return result

func buy_food(airport_index: int = -1) -> bool:
	var price := food_price(airport_index)
	if money < price or not carried_item.is_empty():
		return false
	money -= price
	carried_item = {"type": "food"}
	return true

func buy_canister() -> bool:
	if money < CANISTER_PRICE or not carried_item.is_empty():
		return false
	money -= CANISTER_PRICE
	carried_item = {"type": "canister", "fuel_l": 0}
	return true

func fill_carried_canister(litres: float, airport_index: int = -1) -> float:
	if carried_item.get("type", "") != "canister":
		return 0.0
	var price_per_l := fuel_price_per_l(airport_index)
	var current: float = float(carried_item.get("fuel_l", 0.0))
	var room: float = CANISTER_CAPACITY_L - current
	# Purchases are offered in tenths of a litre, so do not return a fraction
	# which the canister display would then round upward for free.
	var affordable: float = floorf(float(money) / price_per_l * 10.0 + 0.0001) / 10.0
	var limit: float = minf(room, affordable)
	var requested: float = clampf(litres, 0.0, limit)
	var bought: float = limit if limit <= litres + 0.05001 else floorf(requested * 10.0 + 0.0001) / 10.0
	carried_item.fuel_l = snappedf(current + bought, 0.1)
	money -= fuel_purchase_cost(bought, airport_index)
	return bought

func sell_carried_canister() -> int:
	if carried_item.get("type", "") != "canister":
		return 0
	var paid := CANISTER_PRICE + floori(float(carried_item.get("fuel_l", 0.0)) * FUEL_PRICE_PER_L)
	money += paid
	carried_item = {}
	return paid

func eat_carried() -> bool:
	if carried_item.get("type", "") != "food" or hunger >= NEED_SEGMENTS:
		return false
	hunger += 1
	carried_item = {}
	return true

func transfer_carried_fuel(requested_litres: float, aircraft_room_l: float) -> float:
	if carried_item.get("type", "") != "canister":
		return 0.0
	var current: float = float(carried_item.get("fuel_l", 0.0))
	var limit: float = minf(current, maxf(0.0, aircraft_room_l))
	var requested: float = clampf(requested_litres, 0.0, limit)
	# Fuel burn leaves arbitrary fractions in the tank. A selection within half
	# a decilitre of the remaining room means "fill to full".
	var moved: float = limit if limit <= requested_litres + 0.05001 else floorf(requested * 10.0 + 0.0001) / 10.0
	carried_item.fuel_l = maxf(0.0, current - moved)
	return moved

func pay_parking() -> bool:
	if money < PARKING_PRICE:
		return false
	money -= PARKING_PRICE
	return true

func pay_hotel_rest(airport_index: int = -1) -> bool:
	var price := hotel_rest_price(airport_index)
	if money < price or fatigue >= NEED_SEGMENTS:
		return false
	money -= price
	return true

# Standalone economy API; the game session coordinates clocks and weather.
func buy_hotel_rest(airport_index: int = -1) -> bool:
	if not pay_hotel_rest(airport_index):
		return false
	advance_time(HOTEL_REST_SECONDS, true)
	if game_over_reason.is_empty():
		fatigue = mini(NEED_SEGMENTS, fatigue + 1)
	return true

func recover_aircraft_bed_unit() -> bool:
	if fatigue >= 2:
		return false
	fatigue += 1
	return true

func advance_time(delta: float, resting: bool = false, _unused_sleep_cap: int = 6) -> void:
	if not game_over_reason.is_empty() or delta <= 0.0:
		return
	elapsed_seconds += delta
	need_accumulator_seconds += delta
	while need_accumulator_seconds >= 3600.0:
		need_accumulator_seconds -= 3600.0
		hunger -= 1
		if not resting:
			fatigue -= 1
		if hunger <= 0:
			hunger = 0
			game_over_reason = "Вы умерли от голода"
			return
		if fatigue <= 0:
			fatigue = 0
			game_over_reason = "Вы умерли от усталости"
			return

func snapshot() -> Dictionary:
	return {
		"money": money, "hunger": hunger, "fatigue": fatigue,
		"elapsed_seconds": elapsed_seconds, "need_accumulator_seconds": need_accumulator_seconds,
		"inventory": inventory, "carried_item": carried_item, "offers_by_airport": offers_by_airport,
		"fuel_airports": fuel_airports, "food_airports": food_airports, "hotel_airports": hotel_airports,
		"repair_airports": repair_airports, "visited_airports": visited_airports,
		"last_landed_airport": last_landed_airport, "next_parcel_id": next_parcel_id,
		"game_over_reason": game_over_reason,
	}.duplicate(true)

func restore(data: Dictionary, world = null) -> bool:
	if not data.has_all(["money", "hunger", "fatigue", "elapsed_seconds", "need_accumulator_seconds", "inventory", "carried_item", "offers_by_airport", "fuel_airports", "food_airports", "hotel_airports", "last_landed_airport", "next_parcel_id", "game_over_reason"]):
		return false
	if not data.inventory is Array or data.inventory.size() != INVENTORY_CAPACITY:
		return false
	if not data.carried_item is Dictionary or not data.offers_by_airport is Dictionary:
		return false
	for item in data.inventory:
		if not item is Dictionary:
			return false
	var service_keys := ["fuel_airports", "food_airports", "hotel_airports"]
	if data.has("repair_airports"):
		service_keys.append("repair_airports")
	elif world == null:
		return false
	for service_key in service_keys:
		if not data[service_key] is Array or data[service_key].size() != 3:
			return false
		var seen := {}
		for airport_index in data[service_key]:
			if not airport_index is int or airport_index < 0 or airport_index >= 8 or seen.has(airport_index):
				return false
			seen[airport_index] = true
	if not data.money is int or not data.hunger is int or not data.fatigue is int:
		return false
	if data.hunger < 0 or data.hunger > NEED_SEGMENTS or data.fatigue < 0 or data.fatigue > NEED_SEGMENTS:
		return false
	money = int(data.money)
	hunger = int(data.hunger)
	fatigue = int(data.fatigue)
	elapsed_seconds = float(data.elapsed_seconds)
	need_accumulator_seconds = float(data.need_accumulator_seconds)
	inventory.assign(data.inventory)
	carried_item = data.carried_item.duplicate(true)
	offers_by_airport = data.offers_by_airport.duplicate(true)
	fuel_airports.assign(data.fuel_airports)
	food_airports.assign(data.food_airports)
	hotel_airports.assign(data.hotel_airports)
	if data.has("repair_airports"):
		repair_airports.assign(data.repair_airports)
	else:
		repair_airports = _generate_repair_airports(world)
	_balance_service_coverage(world.airports.size() if world != null else 8)
	last_landed_airport = int(data.last_landed_airport)
	visited_airports.clear()
	if data.has("visited_airports"):
		if not data.visited_airports is Array:
			return false
		for airport_index in data.visited_airports:
			if not airport_index is int or airport_index < 0 or airport_index >= (world.airports.size() if world != null else 8) or airport_index in visited_airports:
				return false
			visited_airports.append(airport_index)
	else:
		# Older saves did not track visits explicitly. Mail-offer origins are the
		# best available record of airports at which the player has already landed.
		for origin in offers_by_airport.keys():
			var airport_index := int(origin)
			if airport_index >= 0 and airport_index < (world.airports.size() if world != null else 8) and airport_index not in visited_airports:
				visited_airports.append(airport_index)
		if last_landed_airport >= 0 and last_landed_airport not in visited_airports:
			visited_airports.append(last_landed_airport)
	next_parcel_id = int(data.next_parcel_id)
	game_over_reason = String(data.game_over_reason)
	return true
