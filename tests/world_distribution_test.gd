extends SceneTree

const World = preload("res://scripts/world.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func region_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / World.REGION_SIZE_KM), floori(position.y / World.REGION_SIZE_KM))

func _initialize() -> void:
	var highest_airport_site := 0.0
	var shortest_airport_distance := INF
	for seed_value in range(21001, 21101):
		var world = World.new(seed_value)
		check(world.airports.size() == World.AIRPORT_COUNT, "World must contain eight airports")
		check(world.beacons.size() == World.BEACON_COUNT, "World must contain eight airport and sixteen route beacons")
		check(world.storms.size() == World.WEATHER_STORM_COUNT, "Storm density must scale with world area")
		for first_index in world.airports.size():
			for second_index in range(first_index + 1, world.airports.size()):
				var distance: float = Vector2(world.airports[first_index].position).distance_to(Vector2(world.airports[second_index].position))
				shortest_airport_distance = minf(shortest_airport_distance, distance)
				check(distance >= World.MIN_AIRPORT_SEPARATION_KM, "Every pair of airports must be at least 45 km apart")
		for region_y in World.REGIONS_PER_AXIS:
			for region_x in World.REGIONS_PER_AXIS:
				var region := Vector2i(region_x, region_y)
				var airports_here := 0
				var ndbs_here := 0
				var storms_here := 0
				var occupied_subcells := {}
				for airport in world.airports:
					if region_of(airport.position) == region:
						airports_here += 1
						var raw_site_height: float = world.raw_height_at(airport.position)
						highest_airport_site = maxf(highest_airport_site, raw_site_height)
						check(raw_site_height < 250.0, "Airport sites must start below the first contour before clearing")
				for beacon in world.beacons:
					if int(beacon.runway) < 0 and region_of(beacon.position) == region:
						ndbs_here += 1
						var local_position: Vector2 = Vector2(beacon.position) - Vector2(region) * World.REGION_SIZE_KM
						occupied_subcells[Vector2i(floori(local_position.x / 50.0), floori(local_position.y / 50.0))] = true
				for storm in world.storms:
					if region_of(storm.origin) == region:
						storms_here += 1
				check(airports_here == World.AIRPORTS_PER_REGION, "Each 100×100 region must contain two airports")
				check(ndbs_here == World.ROUTE_NDB_PER_REGION, "Each 100×100 region must contain four route NDBs")
				check(occupied_subcells.size() == 4, "Each 50×50 subcell must contain one route NDB")
				check(storms_here == World.STORMS_PER_REGION, "Each region must start with equal storm density")
	print("200×200 world: evenly distributed; shortest airport pair %.2f km; highest raw airport site %.0f m: %s" % [shortest_airport_distance, highest_airport_site, "FAIL" if failed else "OK"])
	quit(1 if failed else 0)
