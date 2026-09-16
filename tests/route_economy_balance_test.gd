extends SceneTree

const World = preload("res://scripts/world.gd")
const Economy = preload("res://scripts/economy.gd")

func _initialize() -> void:
	for seed_value in range(31001, 31013):
		var world := World.new(seed_value)
		assert(world.all_airports_route_connected(), "Every airport must remain reachable below the new ceiling for seed %d" % seed_value)
		var economy := Economy.new(world)
		var empty_airports := 0
		for airport_index in world.airports.size():
			var service_count := economy.optional_service_count(airport_index)
			if service_count == 0:
				empty_airports += 1
			var expected_bonus: int = [35, 20, 10, 0, 0][service_count]
			assert(economy.poverty_bonus_percent(airport_index) == expected_bonus)
		assert(empty_airports <= Economy.MAX_AIRPORTS_WITHOUT_OPTIONAL_SERVICES)
		for origin in world.airports.size():
			for destination in range(origin + 1, world.airports.size()):
				var direct: float = Vector2(world.airports[origin].position).distance_to(Vector2(world.airports[destination].position))
				var route: float = world.planned_route_distance_km(origin, destination)
				assert(is_finite(route) and route + 0.001 >= direct)
	print("Low-ceiling routes and airport service balance across 12 worlds: OK")
	quit()
