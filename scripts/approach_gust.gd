extends RefCounted
## Smooth horizontal gusts in the final-approach area. No attitude commands.
const MAX_HEIGHT_M := 100.0
const MAX_DISTANCE_KM := 5.0
const MAX_SPEED_KMH := 12.0
const MIN_DURATION := 5.0
const MAX_DURATION := 12.0

static func initial(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 671291
	return {"start": Vector2.ZERO, "target": Vector2.ZERO, "current": Vector2.ZERO,
		"elapsed": 0.0, "duration": 0.0, "rng_state": rng.state}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["start", "target", "current", "elapsed", "duration", "rng_state"]):
		return false
	for field in ["start", "target", "current"]:
		if not value[field] is Vector2 or not value[field].is_finite() or value[field].length() > MAX_SPEED_KMH + 0.001:
			return false
	return value.rng_state is int and value.elapsed is float and value.duration is float and is_finite(value.elapsed) and is_finite(value.duration) and value.elapsed >= 0.0 and value.duration >= 0.0 and value.duration <= MAX_DURATION and value.elapsed <= value.duration + 0.00001

static func weight(world, position: Vector2, altitude_m: float, heading_deg: float, vertical_speed: float, flying: bool) -> float:
	if not flying or vertical_speed >= 2.0:
		return 0.0
	for airport in world.airports:
		if position.distance_squared_to(Vector2(airport.position)) > 36.0:
			continue
		if altitude_m < world.airport_elevation_m(airport):
			continue
		var coords: Vector2 = world.runway_coordinates(position, airport)
		var sign_value: float = world.runway_approach_sign(airport, heading_deg)
		var distance := maxf(0.0, absf(coords.x) - world.RUNWAY_LENGTH_KM * 0.5)
		var heading_error := absf(wrapf(heading_deg - float(airport.heading) - (180.0 if sign_value < 0.0 else 0.0), -180.0, 180.0))
		if distance >= MAX_DISTANCE_KM or absf(coords.y) >= 1.0 or coords.x * sign_value > world.RUNWAY_LENGTH_KM * 0.5 or heading_error >= 50.0:
			continue
		var agl: float = altitude_m - world.height_at(position)
		if agl < 0.0 or agl >= MAX_HEIGHT_M:
			return 0.0
		return (1.0 - smoothstep(70.0, MAX_HEIGHT_M, agl)) * (1.0 - smoothstep(4.0, MAX_DISTANCE_KM, distance)) * (1.0 - smoothstep(0.5, 1.0, absf(coords.y))) * (1.0 - smoothstep(30.0, 50.0, heading_error)) * (1.0 - smoothstep(0.5, 2.0, vertical_speed))
	return 0.0

static func advance(state: Dictionary, delta: float, active: bool, mean_speed_kmh: float) -> void:
	if not active:
		if state.duration > 0.0:
			state.start = Vector2.ZERO
			state.target = Vector2.ZERO
			state.current = Vector2.ZERO
			state.duration = 0.0
			state.elapsed = 0.0
		return
	var remaining := maxf(0.0, delta)
	while remaining > 0.0000001:
		if state.elapsed >= state.duration:
			var rng := RandomNumberGenerator.new()
			rng.state = state.rng_state
			state.start = state.current
			var limit := lerpf(5.0, MAX_SPEED_KMH, clampf(mean_speed_kmh / 32.0, 0.0, 1.0))
			state.target = Vector2.ZERO if rng.randf() < 0.25 else Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.4, 1.0) * limit
			state.duration = rng.randf_range(MIN_DURATION, MAX_DURATION)
			state.elapsed = 0.0
			state.rng_state = rng.state
		var step := minf(remaining, float(state.duration) - float(state.elapsed))
		state.elapsed += step
		remaining -= step
		state.current = Vector2(state.start).lerp(state.target, smoothstep(0.0, 1.0, state.elapsed / state.duration))
