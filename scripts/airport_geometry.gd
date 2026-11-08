extends RefCounted
## One elevation datum and approach/terrain geometry for generation, map and ILS.
const MAX_ELEVATION_M := 300.0
const APPROACH_LENGTH_KM := 6.0
const APPROACH_STEP_KM := 0.25
const PRACTICE_ENTRY_HEIGHT_M := 234.0

class TerrainPatch extends RefCounted:
	var airport: Dictionary
	var position: Vector2
	var forward: Vector2
	var lateral: Vector2
	var radius: float
	var legacy: bool
	var engineered: bool
	func _init(field: Dictionary, half_length: float, use_elevation: bool) -> void:
		airport = field
		position = field.position
		var angle := deg_to_rad(float(field.heading))
		forward = Vector2(sin(angle), -cos(angle))
		lateral = Vector2(forward.y, -forward.x)
		legacy = not use_elevation
		engineered = legacy or bool(field.get("engineered_approach", false))
		var outer_length := 8.5 if legacy else half_length + APPROACH_LENGTH_KM + 2.1
		radius = outer_length + 0.7 + outer_length * 0.18 if engineered else half_length + 1.2 + 0.75

static func elevation(airport: Dictionary) -> float:
	return float(airport.get("elevation_m", 0.0))

static func terrain_height(raw: float, coords: Vector2, airport: Dictionary, half_length: float) -> float:
	var end_distance := maxf(0.0, absf(coords.x) - half_length)
	# Only the apron/runway and their immediate surroundings are levelled.
	var blend := (1.0 - smoothstep(0.35, 0.75, absf(coords.y))) * (1.0 - smoothstep(0.5, 1.2, end_distance))
	return lerpf(raw, elevation(airport), blend)

static func engineered_height(raw: float, coords: Vector2, height_m: float, half_length: float, legacy: bool) -> float:
	var end_distance := maxf(0.0, absf(coords.x) - half_length)
	var width := 0.70 + end_distance * 0.18
	var clear_length := 6.5 if legacy else half_length + APPROACH_LENGTH_KM + 0.1
	if absf(coords.x) >= clear_length + 2.0 or absf(coords.y) >= width:
		return raw
	var blend := smoothstep(width, width * 0.55, absf(coords.y)) * smoothstep(clear_length + 2.0, clear_length, absf(coords.x))
	return lerpf(raw, height_m, blend)
