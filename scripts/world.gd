class_name FlightWorld
extends RefCounted

const SIZE_KM := 100.0
const RUNWAY_LENGTH_KM := 2.0
const BEACON_FREQUENCIES := [305.0, 327.0, 348.0, 371.0, 392.0, 415.0]

var seed_value: int
var noise := FastNoiseLite.new()
var airports: Array[Dictionary] = []
var beacons: Array[Dictionary] = []

func _init(requested_seed: int = 0) -> void:
	seed_value = requested_seed if requested_seed != 0 else randi_range(10000, 99999999)
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.52
	_generate_airports()
	_generate_beacons()

func raw_height_at(point_km: Vector2) -> float:
	var continental := (noise.get_noise_2d(point_km.x, point_km.y) + 1.0) * 0.5
	var ridges: float = abs(noise.get_noise_2d(point_km.x * 2.35 + 70.0, point_km.y * 2.35 - 30.0))
	var h: float = pow(max(0.0, continental - 0.30) / 0.70, 1.75) * 2700.0
	h += pow(ridges, 3.0) * 850.0
	return clamp(h - 180.0, 0.0, 3200.0)

func height_at(point_km: Vector2) -> float:
	var height: float = raw_height_at(point_km)
	for airport in airports:
		var along_cross := runway_coordinates(point_km, airport)
		var along: float = along_cross.x
		var cross: float = abs(along_cross.y)
		# Clear the strip plus a broad, gently widening approach at both ends.
		var end_distance: float = max(0.0, abs(along) - RUNWAY_LENGTH_KM * 0.5)
		var corridor_width: float = 0.42 + end_distance * 0.13
		if abs(along) < 8.5 and cross < corridor_width:
			var cross_blend := smoothstep(corridor_width, corridor_width * 0.55, cross)
			var end_blend := smoothstep(8.5, 6.5, abs(along))
			height = lerp(height, 0.0, cross_blend * end_blend)
	return height

func runway_coordinates(point_km: Vector2, airport: Dictionary) -> Vector2:
	var airport_position: Vector2 = airport.position
	var delta: Vector2 = point_km - airport_position
	var forward: Vector2 = heading_vector(airport.heading)
	var right: Vector2 = Vector2(forward.y, -forward.x)
	return Vector2(delta.dot(forward), delta.dot(right))

func heading_vector(degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(sin(radians), -cos(radians))

func _generate_airports() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var first := _find_low_point(rng, Vector2(12, 12), Vector2(88, 88), [])
	var candidates: Array[Vector2] = []
	for i in 1800:
		var p := Vector2(rng.randf_range(10, 90), rng.randf_range(10, 90))
		var d := p.distance_to(first)
		if d >= 45.0 and d <= 58.0 and raw_height_at(p) < 550.0:
			candidates.append(p)
	var second := candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else Vector2(78, 78)
	var route_heading := vector_heading(second - first)
	airports = [
		{"name": "Северный", "position": first, "heading": fmod(route_heading + rng.randf_range(-28, 28) + 360.0, 360.0)},
		{"name": "Озёрный", "position": second, "heading": fmod(route_heading + 180.0 + rng.randf_range(-28, 28) + 360.0, 360.0)},
	]

func _find_low_point(rng: RandomNumberGenerator, low: Vector2, high: Vector2, excluded: Array) -> Vector2:
	var best := Vector2(20, 20)
	var best_height := INF
	for i in 1200:
		var p := Vector2(rng.randf_range(low.x, high.x), rng.randf_range(low.y, high.y))
		var h := raw_height_at(p)
		if h < best_height:
			best = p
			best_height = h
	return best

func _generate_beacons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9187
	beacons.clear()
	# The first two are at the far threshold/end of each runway.
	for i in airports.size():
		var airport: Dictionary = airports[i]
		var end_position: Vector2 = airport.position + heading_vector(airport.heading) * (RUNWAY_LENGTH_KM * 0.5)
		beacons.append({"name": "RWY-%d" % (i + 1), "frequency": BEACON_FREQUENCIES[i], "position": end_position, "runway": i})
	for i in 4:
		var p := Vector2(rng.randf_range(12, 88), rng.randf_range(12, 88))
		beacons.append({"name": "NDB-%s" % char(65 + i), "frequency": BEACON_FREQUENCIES[i + 2], "position": p, "runway": -1})

func vector_heading(delta: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
