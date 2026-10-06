extends RefCounted
## Display/input notation only; calculations and saves still use decimal minutes.
static func minutes_seconds(minutes: float) -> String:
	var seconds := maxi(0, roundi(minutes * 60.0))
	return "%d.%02d" % [seconds / 60, seconds % 60]

static func parse_minutes_seconds(text: String) -> float:
	var parts := text.strip_edges().replace(",", ".").split(".")
	if parts.size() > 2 or not _digits(parts[0]):
		return NAN
	var seconds := 0
	if parts.size() == 2 and not parts[1].is_empty():
		if parts[1].length() > 2 or not _digits(parts[1]):
			return NAN
		seconds = parts[1].rpad(2, "0").to_int()
		if seconds >= 60:
			return NAN
	return parts[0].to_float() + seconds / 60.0

static func _digits(text: String) -> bool:
	if text.is_empty():
		return false
	for character in text:
		if not "0123456789".contains(character):
			return false
	return true
