extends RefCounted
## Per-chart directed mail stock and offers; lifetime delivery count survives charts.
var offers_by_airport: Dictionary = {}
var remaining_destinations_by_airport: Dictionary = {}
var deliveries_on_map := 0
var total_deliveries := 0
var last_landed_airport := -1
var next_parcel_id := 1

func reset_for_world(airport_count: int) -> void:
	offers_by_airport.clear()
	remaining_destinations_by_airport.clear()
	deliveries_on_map = 0
	last_landed_airport = -1
	for origin in airport_count:
		var destinations: Array[int] = []
		for destination in airport_count:
			if destination != origin:
				destinations.append(destination)
		remaining_destinations_by_airport[origin] = destinations

func remaining_at(airport_index: int) -> int:
	return remaining_destinations_by_airport.get(airport_index, []).size()

func offers_at(airport_index: int) -> Array:
	return offers_by_airport.get(airport_index, [])

func arrive_at_airport(origin: int, world, elapsed_seconds: float, make_offer: Callable) -> void:
	if origin == last_landed_airport:
		return
	last_landed_airport = origin
	offers_by_airport[origin] = _generate_offers(origin, world, elapsed_seconds, make_offer)

func _generate_offers(origin: int, world, elapsed_seconds: float, make_offer: Callable) -> Array[Dictionary]:
	var candidates: Array[int] = []
	for destination in remaining_destinations_by_airport.get(origin, []):
		candidates.append(int(destination))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.seed_value) ^ (origin + 1) * 7919 ^ int(elapsed_seconds * 10.0) ^ next_parcel_id * 104729
	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value := candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = value
	var offers: Array[Dictionary] = []
	for candidate_index in mini(3, candidates.size()):
		offers.append(make_offer.call(origin, candidates[candidate_index], next_parcel_id, world))
		next_parcel_id += 1
	return offers

func accept_offer(origin: int, offer_index: int) -> Dictionary:
	var offers: Array = offers_at(origin)
	if offer_index < 0 or offer_index >= offers.size():
		return {}
	var parcel: Dictionary = offers.pop_at(offer_index).duplicate(true)
	var remaining: Array = remaining_destinations_by_airport.get(origin, [])
	remaining.erase(int(parcel.destination))
	remaining_destinations_by_airport[origin] = remaining
	# A vacant offer slot stays vacant until landing here after another airport.
	offers_by_airport[origin] = offers
	return parcel

func return_parcel(parcel: Dictionary) -> void:
	var origin := int(parcel.get("origin", -1))
	var destination := int(parcel.get("destination", -1))
	if remaining_destinations_by_airport.has(origin):
		var remaining: Array = remaining_destinations_by_airport[origin]
		if destination not in remaining:
			remaining.append(destination)
			remaining_destinations_by_airport[origin] = remaining

func record_delivery() -> void:
	deliveries_on_map += 1
	total_deliveries += 1

func snapshot() -> Dictionary:
	return {
		"offers_by_airport": offers_by_airport,
		"remaining_destinations_by_airport": remaining_destinations_by_airport,
		"deliveries_on_map": deliveries_on_map,
		"total_deliveries": total_deliveries,
		"last_landed_airport": last_landed_airport,
		"next_parcel_id": next_parcel_id,
	}.duplicate(true)

static func valid_snapshot(data: Dictionary, airport_count: int) -> bool:
	if not data.get("offers_by_airport") is Dictionary or not data.get("next_parcel_id") is int or int(data.next_parcel_id) < 1:
		return false
	if not data.get("last_landed_airport") is int or int(data.last_landed_airport) not in range(-1, airport_count):
		return false
	if data.has("remaining_destinations_by_airport"):
		if not data.remaining_destinations_by_airport is Dictionary or not data.get("deliveries_on_map") is int or int(data.deliveries_on_map) < 0:
			return false
		for origin in airport_count:
			var remaining: Variant = data.remaining_destinations_by_airport.get(origin)
			if not remaining is Array or remaining.size() > airport_count - 1:
				return false
			var seen := {}
			for destination in remaining:
				if not destination is int or destination == origin or destination not in range(airport_count) or seen.has(destination):
					return false
				seen[destination] = true
	if data.has("total_deliveries") and (not data.total_deliveries is int or int(data.total_deliveries) < 0):
		return false
	for origin in data.offers_by_airport.keys():
		if not data.offers_by_airport[origin] is Array:
			return false
	return true

func restore(data: Dictionary, airport_count: int, cargo: Array) -> bool:
	if not valid_snapshot(data, airport_count):
		return false
	if data.has("remaining_destinations_by_airport"):
		remaining_destinations_by_airport = data.remaining_destinations_by_airport.duplicate(true)
		deliveries_on_map = int(data.deliveries_on_map)
	else:
		# Pre-progression saves had infinite mail; reserve any accepted cargo.
		reset_for_world(airport_count)
		for item in cargo:
			if item.get("type", "") == "parcel":
				var origin := int(item.get("origin", -1))
				if remaining_destinations_by_airport.has(origin):
					remaining_destinations_by_airport[origin].erase(int(item.get("destination", -1)))
		deliveries_on_map = 0
	total_deliveries = int(data.get("total_deliveries", deliveries_on_map))
	offers_by_airport = data.offers_by_airport.duplicate(true)
	last_landed_airport = int(data.last_landed_airport)
	next_parcel_id = int(data.next_parcel_id)
	return true
