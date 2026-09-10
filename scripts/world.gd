class_name FlightWorld
extends RefCounted

const SIZE_KM := 200.0
const REGION_SIZE_KM := 100.0
const REGIONS_PER_AXIS := 2
const AIRPORTS_PER_REGION := 2
const ROUTE_NDB_PER_REGION := 4
const MIN_AIRPORT_SEPARATION_KM := 45.0
const MAX_REGIONAL_AIRPORT_DISTANCE_KM := 58.0
const AIRPORT_COUNT := REGIONS_PER_AXIS * REGIONS_PER_AXIS * AIRPORTS_PER_REGION
const ROUTE_NDB_COUNT := REGIONS_PER_AXIS * REGIONS_PER_AXIS * ROUTE_NDB_PER_REGION
const BEACON_COUNT := AIRPORT_COUNT + ROUTE_NDB_COUNT
const RUNWAY_LENGTH_KM := 2.0
const RUNWAY_WIDTH_KM := 0.05
const BEACON_MIN_FREQUENCY_KHZ := 300
const BEACON_MAX_FREQUENCY_KHZ := 400
const LOCATOR_RANGE_KM := 15.0
const ROUTE_NDB_RANGE_KM := 30.0
const ILS_RANGE_KM := 15.0
const ILS_HALF_CONE_DEG := 30.0
const ILS_AIM_OFFSET_KM := 0.06
const MIN_RADIO_BLOCKING_TERRAIN_M := 250.0
const STORMS_PER_REGION := 9
const WEATHER_STORM_COUNT := REGIONS_PER_AXIS * REGIONS_PER_AXIS * STORMS_PER_REGION
const AIRPORT_NAMES := ["Северный", "Озёрный", "Речной", "Степной", "Туманный", "Каменный", "Западный", "Дальний"]

var seed_value: int
var noise := FastNoiseLite.new()
var airports: Array[Dictionary] = []
var beacons: Array[Dictionary] = []
var wind_layers: Array[Dictionary] = []
var storms: Array[Dictionary] = []
var weather_time_seconds := 0.0

func _init(requested_seed: int = 0) -> void:
	seed_value = requested_seed if requested_seed != 0 else randi_range(10000, 99999999)
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.52
	_generate_airports()
	_generate_beacons()
	_generate_weather()

func _generate_weather() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 44771
	wind_layers.clear()
	for altitude_m in [0.0, 1500.0, 3000.0, 5000.0]:
		wind_layers.append({"altitude_m": altitude_m, "from_deg": rng.randf_range(0.0, 360.0), "speed_kmh": rng.randf_range(8.0, 32.0)})
	storms.clear()
	for region_y in REGIONS_PER_AXIS:
		for region_x in REGIONS_PER_AXIS:
			var region_origin := Vector2(region_x, region_y) * REGION_SIZE_KM
			for index in STORMS_PER_REGION:
				var drift_heading := rng.randf_range(0.0, 360.0)
				var storm_radius := rng.randf_range(4.0, 8.0)
				var radar_lobes: Array[Dictionary] = [
					{"offset_km": Vector2.ZERO, "radius_scale": 0.68, "strength": 1.0},
				]
				for lobe_index in 6:
					var offset_direction := heading_vector(rng.randf_range(0.0, 360.0))
					radar_lobes.append({
						"offset_km": offset_direction * storm_radius * rng.randf_range(0.15, 0.43),
						"radius_scale": rng.randf_range(0.38, 0.62),
						"strength": rng.randf_range(0.72, 1.05),
					})
				storms.append({
					"origin": region_origin + Vector2(rng.randf_range(8.0, 92.0), rng.randf_range(8.0, 92.0)),
					"radius_km": storm_radius,
					"intensity": rng.randf_range(0.55, 1.0),
					"drift_kmh": heading_vector(drift_heading) * rng.randf_range(8.0, 18.0),
					"radar_lobes": radar_lobes,
				})

func update_weather(delta: float) -> void:
	weather_time_seconds += delta

func storm_position(storm: Dictionary) -> Vector2:
	var moved: Vector2 = storm.origin + Vector2(storm.drift_kmh) * weather_time_seconds / 3600.0
	return Vector2(fposmod(moved.x, SIZE_KM), fposmod(moved.y, SIZE_KM))

func wind_at(altitude_m: float) -> Vector2:
	var lower: Dictionary = wind_layers[0]
	var upper: Dictionary = wind_layers[-1]
	for index in range(1, wind_layers.size()):
		if altitude_m <= float(wind_layers[index].altitude_m):
			lower = wind_layers[index - 1]
			upper = wind_layers[index]
			break
	var ratio := inverse_lerp(float(lower.altitude_m), float(upper.altitude_m), clampf(altitude_m, float(lower.altitude_m), float(upper.altitude_m))) if lower != upper else 0.0
	var lower_vector := heading_vector(float(lower.from_deg) + 180.0) * float(lower.speed_kmh)
	var upper_vector := heading_vector(float(upper.from_deg) + 180.0) * float(upper.speed_kmh)
	return lower_vector.lerp(upper_vector, ratio)

func storm_intensity_at(position_km: Vector2) -> float:
	var result := 0.0
	for storm in storms:
		var ratio := position_km.distance_to(storm_position(storm)) / float(storm.radius_km)
		if ratio < 1.0:
			result = maxf(result, float(storm.intensity) * (1.0 - ratio * ratio))
	return result

func weather_report(airport: Dictionary) -> String:
	var layer: Dictionary = wind_layers[0]
	var nearest_storm := INF
	for storm in storms:
		nearest_storm = minf(nearest_storm, Vector2(airport.position).distance_to(storm_position(storm)))
	var storm_text := "гроз нет" if nearest_storm > 30.0 else "гроза %.0f км" % nearest_storm
	return "%s: ветер %03d° %.0f км/ч • %s" % [airport.name, roundi(float(layer.from_deg)) % 360, float(layer.speed_kmh), storm_text]

func wind_forecast_reports() -> Array[String]:
	var reports: Array[String] = []
	for layer in wind_layers:
		var altitude_label := "У поверхности" if float(layer.altitude_m) <= 0.0 else "%d м" % roundi(float(layer.altitude_m))
		reports.append("%s: %03d° %.0f км/ч" % [altitude_label, roundi(float(layer.from_deg)) % 360, float(layer.speed_kmh)])
	return reports

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
		# Keep the published approach point and its surroundings visibly clear
		# on the topographic map, not merely the exact runway centerline.
		var corridor_width: float = 0.70 + end_distance * 0.18
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
	airports.clear()
	var positions: Array[Vector2] = []
	# A locally good pair can block an airport in a neighbouring region. Retry
	# the complete layout so the 45 km rule applies to all eight airports.
	for layout_attempt in 80:
		positions.clear()
		var complete := true
		for region_y in REGIONS_PER_AXIS:
			for region_x in REGIONS_PER_AXIS:
				var region_origin := Vector2(region_x, region_y) * REGION_SIZE_KM
				var pair := _find_airport_pair(rng, region_origin, positions)
				if pair.is_empty():
					complete = false
					break
				positions.append_array(pair)
			if not complete:
				break
		if complete:
			break
	if positions.size() != AIRPORT_COUNT:
		positions = _fallback_airport_layout()
	for region_y in REGIONS_PER_AXIS:
		for region_x in REGIONS_PER_AXIS:
			var pair_start := (region_y * REGIONS_PER_AXIS + region_x) * AIRPORTS_PER_REGION
			var route_heading := vector_heading(positions[pair_start + 1] - positions[pair_start])
			for pair_index in AIRPORTS_PER_REGION:
				var airport_index := pair_start + pair_index
				var base_heading: float = route_heading + (180.0 if pair_index == 1 else 0.0)
				airports.append({
					"name": AIRPORT_NAMES[airport_index],
					"position": positions[airport_index],
					"heading": fmod(base_heading + rng.randf_range(-28.0, 28.0) + 360.0, 360.0),
					"region": Vector2i(region_x, region_y),
				})

func _find_airport_pair(rng: RandomNumberGenerator, region_origin: Vector2, occupied: Array[Vector2]) -> Array[Vector2]:
	# Search pairs directly: every 100 km region gets two low sites separated by
	# a useful route, while no airport may approach any earlier one too closely.
	var best_pair: Array[Vector2] = []
	var best_score := INF
	for attempt in 2600:
		var first := region_origin + Vector2(rng.randf_range(12.0, 88.0), rng.randf_range(12.0, 88.0))
		var second := first + heading_vector(rng.randf_range(0.0, 360.0)) * rng.randf_range(MIN_AIRPORT_SEPARATION_KM, MAX_REGIONAL_AIRPORT_DISTANCE_KM)
		var local_second := second - region_origin
		if local_second.x < 12.0 or local_second.x > 88.0 or local_second.y < 12.0 or local_second.y > 88.0:
			continue
		var separated := true
		for other in occupied:
			if first.distance_to(other) < MIN_AIRPORT_SEPARATION_KM or second.distance_to(other) < MIN_AIRPORT_SEPARATION_KM:
				separated = false
				break
		if not separated:
			continue
		var first_height := raw_height_at(first)
		var second_height := raw_height_at(second)
		var score := maxf(first_height, second_height) + (first_height + second_height) * 0.20
		if score < best_score:
			best_score = score
			best_pair = [first, second]
	return best_pair

func _fallback_airport_layout() -> Array[Vector2]:
	# Repeated offsets form a lattice whose shortest distance is about 53.9 km,
	# including across shared region borders.
	var result: Array[Vector2] = []
	for region_y in REGIONS_PER_AXIS:
		for region_x in REGIONS_PER_AXIS:
			var origin := Vector2(region_x, region_y) * REGION_SIZE_KM
			result.append(origin + Vector2(20.0, 25.0))
			result.append(origin + Vector2(70.0, 45.0))
	return result

func _generate_beacons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9187
	beacons.clear()
	# Separate RNG keeps beacon positions unchanged when frequency rules change.
	var frequency_rng := RandomNumberGenerator.new()
	frequency_rng.seed = seed_value + 51793
	var available := range(BEACON_MIN_FREQUENCY_KHZ, BEACON_MAX_FREQUENCY_KHZ + 1)
	var frequencies: Array[int] = []
	for i in BEACON_COUNT:
		var selected := frequency_rng.randi_range(0, available.size() - 1)
		frequencies.append(available[selected])
		available.remove_at(selected)
	# Runway locator beacons share the runway centre so their bearing and range
	# are identical for approaches from either direction.
	for i in airports.size():
		var airport: Dictionary = airports[i]
		beacons.append({"name": "RWY-%d" % (i + 1), "frequency": frequencies[i], "position": airport.position, "runway": i, "range_km": LOCATOR_RANGE_KM, "class": "LOC"})
	var ndb_index := 0
	for region_y in REGIONS_PER_AXIS:
		for region_x in REGIONS_PER_AXIS:
			var region_origin := Vector2(region_x, region_y) * REGION_SIZE_KM
			# One NDB in each 50×50 subcell prevents clusters and empty areas.
			for cell_y in 2:
				for cell_x in 2:
					var cell_origin := region_origin + Vector2(cell_x, cell_y) * (REGION_SIZE_KM * 0.5)
					var p := cell_origin + Vector2(rng.randf_range(10.0, 40.0), rng.randf_range(10.0, 40.0))
					for retry in 12:
						var too_close := false
						for airport in airports:
							if p.distance_to(Vector2(airport.position)) < 6.0:
								too_close = true
								break
						if not too_close:
							break
						p = cell_origin + Vector2(rng.randf_range(10.0, 40.0), rng.randf_range(10.0, 40.0))
					beacons.append({"name": "NDB-%s" % char(65 + ndb_index), "frequency": frequencies[airports.size() + ndb_index], "position": p, "runway": -1, "range_km": ROUTE_NDB_RANGE_KM, "class": "MH"})
					ndb_index += 1

func beacon_signal(beacon: Dictionary, aircraft_position_km: Vector2, aircraft_altitude_m: float) -> Dictionary:
	var beacon_position: Vector2 = beacon.position
	var distance_km: float = aircraft_position_km.distance_to(beacon_position)
	var max_range_km: float = beacon.range_km
	if distance_km > max_range_km:
		return {"available": false, "reason": "НЕТ СИГНАЛА", "distance_km": distance_km, "range_km": max_range_km}
	if distance_km < 0.05:
		return {"available": true, "reason": "", "distance_km": distance_km, "range_km": max_range_km}
	var aircraft_antenna_m := aircraft_altitude_m + 2.0
	var beacon_antenna_m := height_at(beacon_position) + 20.0
	var sample_count := clampi(int(ceil(distance_km / 0.5)), 2, 128)
	for sample in range(1, sample_count):
		var ratio: float = sample / float(sample_count)
		var sample_position := aircraft_position_km.lerp(beacon_position, ratio)
		var radio_ray_height := lerpf(aircraft_antenna_m, beacon_antenna_m, ratio)
		# A small Fresnel-like clearance makes grazing a ridge unreliable too.
		var clearance_margin := 8.0 * sin(PI * ratio)
		var terrain_height := height_at(sample_position)
		# Only charted relief can create radio shadow. Without this floor, tiny
		# sub-contour undulations blocked a ground-level receiver despite the map
		# showing no obstacle between aircraft and beacon.
		if terrain_height >= MIN_RADIO_BLOCKING_TERRAIN_M and terrain_height + clearance_margin > radio_ray_height:
			return {"available": false, "reason": "НЕТ СИГНАЛА", "distance_km": distance_km, "range_km": max_range_km}
	return {"available": true, "reason": "", "distance_km": distance_km, "range_km": max_range_km}

func ils_signal(airport_index: int, aircraft_position_km: Vector2, aircraft_altitude_m: float, aircraft_heading_deg: float) -> Dictionary:
	var airport: Dictionary = airports[airport_index]
	var approach_sign: float = runway_approach_sign(airport, aircraft_heading_deg)
	var forward: Vector2 = heading_vector(airport.heading) * approach_sign
	var delta: Vector2 = aircraft_position_km - Vector2(airport.position)
	var right := Vector2(forward.y, -forward.x)
	var along: float = delta.dot(forward)
	var cross: float = delta.dot(right)
	# Use the far threshold as the virtual cone apex. This keeps the selected
	# course valid throughout approach and ground roll, ending only after the
	# aircraft passes that threshold. The physical locator is in the centre.
	var forward_distance_km: float = RUNWAY_LENGTH_KM * 0.5 - along
	var distance_to_beacon_km := aircraft_position_km.distance_to(Vector2(airport.position))
	if forward_distance_km <= 0.0 or distance_to_beacon_km > ILS_RANGE_KM:
		return {"available": false, "reason": "НЕТ СИГНАЛА", "distance_km": distance_to_beacon_km, "range_km": ILS_RANGE_KM}
	var cone_angle_deg := rad_to_deg(atan2(absf(cross), forward_distance_km))
	if cone_angle_deg > ILS_HALF_CONE_DEG:
		return {"available": false, "reason": "НЕТ СИГНАЛА", "distance_km": distance_to_beacon_km, "range_km": ILS_RANGE_KM}
	# The locator itself is in the runway centre; the far threshold above is the
	# virtual apex used only to retain guidance throughout the ground roll.
	var transmitter := {"position": airport.position, "range_km": ILS_RANGE_KM}
	return beacon_signal(transmitter, aircraft_position_km, aircraft_altitude_m)

func runway_approach_sign(airport: Dictionary, aircraft_heading_deg: float) -> float:
	var direct_error := absf(wrapf(aircraft_heading_deg - float(airport.heading), -180.0, 180.0))
	var reverse_heading := fmod(float(airport.heading) + 180.0, 360.0)
	var reverse_error := absf(wrapf(aircraft_heading_deg - reverse_heading, -180.0, 180.0))
	return 1.0 if direct_error <= reverse_error else -1.0

func vector_heading(delta: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
