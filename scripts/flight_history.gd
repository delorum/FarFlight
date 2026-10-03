extends RefCounted
## Persistent completed-flight log. An active entry survives an airborne save;
## touch-and-go does not split it because only a full LANDING completes a row.

const Flight = preload("res://scripts/flight_model.gd")

var records: Array[Dictionary] = []
var transitions: Array[Dictionary] = []
var _journal: Array[Dictionary] = []
var _journal_size := Vector2i(-1, -1)
var active := false
var active_origin := -1
var active_level := 0
var active_origin_name := ""
var active_start_seconds := 0.0
var active_distance_km := 0.0

func reset() -> void:
	records.clear()
	transitions.clear()
	_journal_size = Vector2i(-1, -1)
	active = false
	active_origin = -1
	active_level = 0
	active_origin_name = ""
	active_start_seconds = 0.0
	active_distance_km = 0.0

func update(flight, previous_state: int, previous_position: Vector2, elapsed_seconds: float, step: float) -> void:
	if not active and previous_state != Flight.State.FLYING and flight.state == Flight.State.FLYING:
		active = true
		active_origin = int(flight.airport_index)
		active_level = int(flight.world.level_index)
		active_origin_name = String(flight.world.airports[active_origin].name)
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
			"level": active_level,
			"destination_level": int(flight.world.level_index),
			"origin_name": active_origin_name,
			"destination_name": String(flight.world.airports[int(flight.airport_index)].name),
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

func add_world_transition(from_level: int, to_level: int, elapsed_seconds: float) -> void:
	transitions.append({"kind": "world_transition", "from_level": from_level, "to_level": to_level, "time_seconds": elapsed_seconds})

func recover_legacy_transitions(current_level: int, elapsed_seconds: float) -> void:
	# Old saves retained world numbers but not crossing timestamps. Position
	# their separators before the first flight of the next world without
	# presenting this sorting anchor as an actual crossing time.
	for level in current_level:
		var anchor := elapsed_seconds
		for record in records:
			if int(record.get("level", 0)) > level:
				anchor = float(record.start_seconds)
				break
		transitions.append({"kind": "world_transition", "from_level": level, "to_level": level + 1, "time_seconds": anchor, "time_known": false})

func journal_rows() -> Array[Dictionary]:
	var size := Vector2i(records.size(), transitions.size())
	if size != _journal_size:
		_journal_size = size
		_journal = []
		_journal.append_array(records)
		_journal.append_array(transitions)
		_journal.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_time := float(a.get("end_seconds", a.get("time_seconds", 0.0)))
			var b_time := float(b.get("end_seconds", b.get("time_seconds", 0.0)))
			if a_time != b_time:
				return a_time < b_time
			if a.get("kind", "") == "world_transition" and b.get("kind", "") == "world_transition":
				return int(a.from_level) < int(b.from_level)
			return a.get("kind", "flight") == "world_transition" and b.get("kind", "flight") != "world_transition"
		)
	return _journal

func route_records(origin: int, destination: int, level: int = -1, destination_level: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in records:
		if int(record.origin) == origin and int(record.destination) == destination and (level < 0 or int(record.get("level", 0)) == level):
			if level < 0 or int(record.get("destination_level", record.get("level", 0))) == (destination_level if destination_level >= 0 else level):
				result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.duration_seconds), float(b.duration_seconds)):
			return float(a.duration_seconds) < float(b.duration_seconds)
		return float(a.start_seconds) < float(b.start_seconds)
	)
	return result

func route_count(origin: int, destination: int, level: int = -1, destination_level: int = -1) -> int:
	var count := 0
	for record in records:
		if int(record.origin) == origin and int(record.destination) == destination and (level < 0 or int(record.get("level", 0)) == level):
			if level < 0 or int(record.get("destination_level", record.get("level", 0))) == (destination_level if destination_level >= 0 else level):
				count += 1
	return count

func snapshot() -> Dictionary:
	return {
		"records": records.duplicate(true),
		"transitions": transitions.duplicate(true),
		"active": active,
		"active_origin": active_origin,
		"active_level": active_level,
		"active_origin_name": active_origin_name,
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
	if data.has("active_level") and (not data.active_level is int or int(data.active_level) < 0):
		return false
	if data.has("active_origin_name") and not data.active_origin_name is String:
		return false
	if data.has("transitions"):
		if not data.transitions is Array:
			return false
		for event in data.transitions:
			if not event is Dictionary or event.get("kind") != "world_transition":
				return false
			if not event.get("from_level") is int or not event.get("to_level") is int or int(event.from_level) < 0 or int(event.to_level) != int(event.from_level) + 1:
				return false
			if not event.get("time_seconds") is float or not is_finite(float(event.time_seconds)) or float(event.time_seconds) < 0.0:
				return false
			if event.has("time_known") and not event.time_known is bool:
				return false
	for record in data.records:
		if not record is Dictionary or not record.has_all(["origin", "destination", "distance_km", "duration_seconds", "start_seconds", "end_seconds"]):
			return false
		if not record.origin is int or int(record.origin) not in range(airport_count):
			return false
		if not record.destination is int or int(record.destination) not in range(airport_count):
			return false
		if record.has("level") and (not record.level is int or int(record.level) < 0):
			return false
		if record.has("destination_level") and (not record.destination_level is int or int(record.destination_level) < 0):
			return false
		for key in ["origin_name", "destination_name"]:
			if record.has(key) and not record[key] is String:
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
	transitions.assign(data.get("transitions", []).duplicate(true))
	_journal_size = Vector2i(-1, -1)
	active = data.active
	active_origin = data.active_origin
	active_level = int(data.get("active_level", 0))
	active_origin_name = String(data.get("active_origin_name", ""))
	active_start_seconds = data.active_start_seconds
	active_distance_km = data.active_distance_km
	return true
