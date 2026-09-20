extends RefCounted
## Persistent completed-flight log. An active entry survives an airborne save;
## touch-and-go does not split it because only a full LANDING completes a row.

const Flight = preload("res://scripts/flight_model.gd")

var records: Array[Dictionary] = []
var active := false
var active_origin := -1
var active_start_seconds := 0.0
var active_distance_km := 0.0

func reset() -> void:
	records.clear()
	active = false
	active_origin = -1
	active_start_seconds = 0.0
	active_distance_km = 0.0

func update(flight, previous_state: int, previous_position: Vector2, elapsed_seconds: float, step: float) -> void:
	if not active and previous_state != Flight.State.FLYING and flight.state == Flight.State.FLYING:
		active = true
		active_origin = int(flight.airport_index)
		active_start_seconds = maxf(0.0, elapsed_seconds - step)
		active_distance_km = 0.0
	if active and previous_state == Flight.State.FLYING:
		active_distance_km += previous_position.distance_to(flight.position_km)
	if not active:
		return
	if flight.state == Flight.State.LANDED:
		var end_seconds := maxf(active_start_seconds, elapsed_seconds)
		records.append({
			"origin": active_origin,
			"destination": int(flight.airport_index),
			"distance_km": active_distance_km,
			"duration_seconds": end_seconds - active_start_seconds,
			"start_seconds": active_start_seconds,
			"end_seconds": end_seconds,
		})
		active = false
		active_origin = -1
		active_distance_km = 0.0
	elif flight.state == Flight.State.CRASHED:
		active = false
		active_origin = -1
		active_distance_km = 0.0

func route_records(origin: int, destination: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		if int(record.origin) == origin and int(record.destination) == destination:
			result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.duration_seconds), float(b.duration_seconds)):
			return float(a.duration_seconds) < float(b.duration_seconds)
		return float(a.start_seconds) < float(b.start_seconds)
	)
	return result

func route_count(origin: int, destination: int) -> int:
	var count := 0
	for record in records:
		if int(record.origin) == origin and int(record.destination) == destination:
			count += 1
	return count

func snapshot() -> Dictionary:
	return {
		"records": records.duplicate(true),
		"active": active,
		"active_origin": active_origin,
		"active_start_seconds": active_start_seconds,
		"active_distance_km": active_distance_km,
	}.duplicate(true)

static func valid_snapshot(data: Variant, airport_count: int = 8) -> bool:
	if not data is Dictionary or not data.get("records") is Array:
		return false
	if not data.get("active") is bool or not data.get("active_origin") is int:
		return false
	if not data.get("active_start_seconds") is float or not data.get("active_distance_km") is float:
		return false
	if float(data.active_start_seconds) < 0.0 or float(data.active_distance_km) < 0.0:
		return false
	if data.active and int(data.active_origin) not in range(airport_count):
		return false
	for record in data.records:
		if not record is Dictionary or not record.has_all(["origin", "destination", "distance_km", "duration_seconds", "start_seconds", "end_seconds"]):
			return false
		if not record.origin is int or int(record.origin) not in range(airport_count):
			return false
		if not record.destination is int or int(record.destination) not in range(airport_count):
			return false
		for key in ["distance_km", "duration_seconds", "start_seconds", "end_seconds"]:
			if not record[key] is float or not is_finite(float(record[key])) or float(record[key]) < 0.0:
				return false
		if float(record.end_seconds) < float(record.start_seconds):
			return false
	return true

func restore_snapshot(data: Dictionary, airport_count: int = 8) -> bool:
	if not valid_snapshot(data, airport_count):
		return false
	records.assign(data.records.duplicate(true))
	active = data.active
	active_origin = data.active_origin
	active_start_seconds = data.active_start_seconds
	active_distance_km = data.active_distance_km
	return true
