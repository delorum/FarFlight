extends RefCounted
## Shared geometry for map markers, ILS guidance and level-flight interception.
## Distances are signed kilometres before the near runway threshold.
const ANGLE_DEG := 3.0
const AIM_OFFSET_KM := 0.06
const SLOPE := tan(deg_to_rad(ANGLE_DEG))
const HEIGHT_PER_KM := 1000.0 * SLOPE

static func height_at_distance_m(distance_to_threshold_km: float) -> float:
	return maxf(0.0, distance_to_threshold_km + AIM_OFFSET_KM) * HEIGHT_PER_KM

static func distance_at_height_km(altitude_m: float) -> float:
	# Do not clamp: low heights intersect beyond the near threshold.
	return altitude_m / HEIGHT_PER_KM - AIM_OFFSET_KM

static func vertical_speed_mps(along_ground_speed_kmh: float) -> float:
	return -(along_ground_speed_kmh / 3.6) * SLOPE
