extends RefCounted
## Shared storm geometry for simulation, weather radar and map briefing.

static func position(storm: Dictionary, elapsed_seconds: float) -> Vector2:
	return Vector2(storm.origin) + Vector2(storm.drift_kmh) * elapsed_seconds / 3600.0

static func lobes(storm: Dictionary) -> Array:
	var result: Array = storm.get("radar_lobes", [])
	return result if not result.is_empty() else [{"offset_km": Vector2.ZERO, "radius_scale": 1.0, "strength": 1.0}]

static func lobe_radius(storm: Dictionary, lobe: Dictionary, threshold: float = 0.0) -> float:
	var peak := float(storm.intensity) * float(lobe.strength)
	if peak <= threshold:
		return 0.0
	var ratio := 1.0 if threshold <= 0.0 else sqrt(1.0 - threshold / peak)
	return float(storm.radius_km) * float(lobe.radius_scale) * ratio

static func lobe_strength(storm: Dictionary, storm_center: Vector2, lobe: Dictionary, point: Vector2) -> float:
	var radius := float(storm.radius_km) * float(lobe.radius_scale)
	if radius <= 0.0:
		return 0.0
	var ratio := point.distance_to(storm_center + Vector2(lobe.offset_km)) / radius
	return float(storm.intensity) * float(lobe.strength) * (1.0 - ratio * ratio) if ratio < 1.0 else 0.0

static func intensity_at(storm: Dictionary, storm_center: Vector2, point: Vector2) -> float:
	var result := 0.0
	for lobe in lobes(storm):
		result = maxf(result, lobe_strength(storm, storm_center, lobe, point))
	return result

static func maximum_extent_km(storm: Dictionary) -> float:
	var result := 0.0
	for lobe in lobes(storm):
		result = maxf(result, Vector2(lobe.offset_km).length() + lobe_radius(storm, lobe))
	return result
