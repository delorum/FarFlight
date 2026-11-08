extends RefCounted
## Lightweight pitch-contact model, shared by actual and predicted touchdown.
## Coordinates match the side-view airframe (nose left, screen Y downward).
const MAIN_WHEEL_CENTER := Vector2(327, 393)
const MAIN_WHEEL_RADIUS := 33.0
const MAIN_WHEEL_CONTACT := Vector2(MAIN_WHEEL_CENTER.x, MAIN_WHEEL_CENTER.y + MAIN_WHEEL_RADIUS)
const PROPELLER_CENTER := Vector2(107, 264)
const PROPELLER_RADIUS := 107.0
const PROPELLER_BOTTOM := Vector2(PROPELLER_CENTER.x, PROPELLER_CENTER.y + PROPELLER_RADIUS)
const TAIL_UNDERSIDE := Vector2(845, 364)
const ART_UNITS_PER_METRE := 50.0
const NOSE_LIMIT_DEG := -rad_to_deg(atan2(MAIN_WHEEL_CONTACT.y - PROPELLER_BOTTOM.y, MAIN_WHEEL_CONTACT.x - PROPELLER_BOTTOM.x))
const TAIL_LIMIT_DEG := rad_to_deg(atan2(MAIN_WHEEL_CONTACT.y - TAIL_UNDERSIDE.y, TAIL_UNDERSIDE.x - MAIN_WHEEL_CONTACT.x))
# Conservative bound avoids geometry/trigonometry while well above the ground.
const MAX_CONTACT_HEIGHT_M := (TAIL_UNDERSIDE.x - MAIN_WHEEL_CONTACT.x + MAIN_WHEEL_CONTACT.y - TAIL_UNDERSIDE.y) / ART_UNITS_PER_METRE
const FATAL_IMPACT_SPEED_MPS := 5.5
const MIN_STRIKE_DAMAGE := 2.0
const MAX_STRIKE_DAMAGE := 35.0

static func part(pitch_deg: float) -> String:
	if pitch_deg < NOSE_LIMIT_DEG - 0.00001:
		return "nose"
	if pitch_deg > TAIL_LIMIT_DEG + 0.00001:
		return "tail"
	return ""

static func contact_height_m(pitch_deg: float) -> float:
	var hit := part(pitch_deg)
	if hit.is_empty():
		return 0.0
	var point := PROPELLER_BOTTOM if hit == "nose" else TAIL_UNDERSIDE
	return maxf(0.0, (point - MAIN_WHEEL_CONTACT).rotated(deg_to_rad(pitch_deg)).y / ART_UNITS_PER_METRE)

static func assess(pitch_deg: float, vertical_speed_mps: float, airspeed_kmh: float) -> Dictionary:
	var hit := part(pitch_deg)
	var excess := maxf(NOSE_LIMIT_DEG - pitch_deg, pitch_deg - TAIL_LIMIT_DEG) if not hit.is_empty() else 0.0
	# A gameplay impact proxy, not a rigid-body solver: a deeper strike at
	# higher forward speed adds severity to the normal downward impact.
	var forward_impact := maxf(0.0, airspeed_kmh) / 3.6 * sin(deg_to_rad(minf(excess, 90.0)))
	var impact := Vector2(maxf(0.0, -vertical_speed_mps), forward_impact).length()
	var severity := clampf(impact / FATAL_IMPACT_SPEED_MPS, 0.0, 1.0)
	return {"part": hit, "pitch_deg": pitch_deg, "contact_height_m": contact_height_m(pitch_deg),
		"damage": lerpf(MIN_STRIKE_DAMAGE, MAX_STRIKE_DAMAGE, severity * severity) if not hit.is_empty() else 0.0,
		"fatal": impact >= FATAL_IMPACT_SPEED_MPS,
		"safe": hit.is_empty() and vertical_speed_mps > -FATAL_IMPACT_SPEED_MPS}
