class_name FlightModel
extends RefCounted

const FlightWorldScript = preload("res://scripts/world.gd")
const GLIDE_SLOPE_DEG := 3.3
const STALL_WARNING_AOA_DEG := 12.0
const STALL_AOA_DEG := 15.0
const STALL_RECOVERY_AOA_DEG := 10.0
const STALL_RECOVERY_SPEED_KMH := 68.0

enum State { PARKED, FLYING, LANDED, CRASHED }

var world
var position_km := Vector2.ZERO
var altitude_m := 0.0
var speed_kmh := 0.0
var heading_deg := 0.0
var throttle := 0.0
var yoke := Vector2.ZERO
var pitch_deg := 0.0
var bank_deg := 0.0
var vertical_speed_mps := 0.0
var angle_of_attack_deg := 0.0
var stalled := false
var fuel_l := 40.0
var fuel_capacity_l := 40.0
var state := State.PARKED
var airport_index := 0
var message := "Самолёт подготовлен к вылету"
var message_time_remaining := -1.0
var message_after_timeout := ""

func _init(flight_world) -> void:
	world = flight_world
	prepare_at_airport(0)

func prepare_at_airport(index: int) -> void:
	airport_index = index
	var airport: Dictionary = world.airports[index]
	position_km = airport.position - world.heading_vector(airport.heading) * 0.78
	heading_deg = airport.heading
	altitude_m = 0.0
	speed_kmh = 0.0
	throttle = 0.0
	yoke = Vector2.ZERO
	pitch_deg = 0.0
	bank_deg = 0.0
	vertical_speed_mps = 0.0
	angle_of_attack_deg = 0.0
	stalled = false
	state = State.PARKED
	_show_message(_ready_message(), -1.0)

func refuel() -> void:
	fuel_l = fuel_capacity_l
	_show_message("Самолёт заправлен: %.0f л" % fuel_l, 3.0, _ready_message())

func update(delta: float) -> void:
	_update_message(delta)
	if state == State.CRASHED or state == State.LANDED:
		return
	if fuel_l <= 0.0:
		throttle = 0.0
	else:
		fuel_l = max(0.0, fuel_l - fuel_flow_lpm() * delta / 60.0)

	var roll_authority := 0.32 if stalled else 1.0
	bank_deg = move_toward(bank_deg, yoke.x * 38.0 * roll_authority, delta * 55.0 * roll_authority)
	# Pulling the yoke down/towards the pilot raises the nose; pushing it up lowers it.
	pitch_deg = move_toward(pitch_deg, yoke.y * 18.0, delta * 30.0)
	_update_angle_of_attack()
	if state == State.FLYING:
		if not stalled and angle_of_attack_deg >= STALL_AOA_DEG:
			stalled = true
		elif stalled and angle_of_attack_deg <= STALL_RECOVERY_AOA_DEG and speed_kmh >= STALL_RECOVERY_SPEED_KMH:
			stalled = false
	if stalled:
		# A separated airflow pitches the nose down even while the pilot keeps pulling.
		pitch_deg = move_toward(pitch_deg, -8.0, delta * 18.0)
		_update_angle_of_attack()
	var speed_factor: float = clampf(speed_kmh / 95.0, 0.15, 1.45)
	heading_deg = fposmod(heading_deg + bank_deg * 0.34 * speed_factor * roll_authority * delta, 360.0)

	# In flight the airframe tends to retain a minimum glide speed. This gives
	# about 92 km/h at 30% power and 200 km/h at roughly 87% power.
	var glide_speed: float = 35.0 if state == State.FLYING else 0.0
	var raw_pitch_climb: float = pitch_deg * 0.55 * clampf((speed_kmh - 55.0) / 75.0, 0.0, 1.0) * altitude_power_factor()
	var available_climb: float = max_available_climb_mps()
	# Raising the nose converts airspeed into height. Near the practical ceiling
	# there is not enough excess power to sustain the requested climb, so the
	# unmet part causes additional speed loss and eventually excessive AoA.
	var unsupported_climb: float = maxf(0.0, raw_pitch_climb - available_climb)
	var target_speed: float = glide_speed + throttle * 190.0 * altitude_power_factor() - abs(pitch_deg) * 1.2 - unsupported_climb * 8.0
	var acceleration: float = (target_speed - speed_kmh) * 0.22
	speed_kmh = clamp(speed_kmh + acceleration * delta, 0.0, 200.0)

	var lift_factor: float = clampf((speed_kmh - 55.0) / 75.0, 0.0, 1.0)
	var lift_efficiency := 0.25 if stalled else 1.0
	raw_pitch_climb = pitch_deg * 0.55 * lift_factor * altitude_power_factor()
	var pitch_climb: float = raw_pitch_climb
	if pitch_climb > 0.0:
		pitch_climb = minf(pitch_climb, available_climb)
	pitch_climb *= lift_efficiency
	# At 30% power, neutral pitch and ~92 km/h this produces a conventional
	# three-degree glide path (about -1.3 m/s).
	var low_power_sink: float = maxf(0.0, 0.45 - throttle) * 19.0 * lift_factor
	var low_speed_sink: float = 0.0 if speed_kmh >= 62.0 else (62.0 - speed_kmh) * 0.17
	var separated_flow_sink: float = (6.0 + maxf(0.0, angle_of_attack_deg - STALL_AOA_DEG) * 0.45) if stalled else 0.0
	var target_vs: float = pitch_climb - low_power_sink - low_speed_sink - separated_flow_sink
	vertical_speed_mps = move_toward(vertical_speed_mps, target_vs, delta * 4.5)

	var direction: Vector2 = world.heading_vector(heading_deg)
	position_km += direction * (speed_kmh / 3600.0) * delta
	var terrain: float = world.height_at(position_km)
	var next_altitude: float = altitude_m + vertical_speed_mps * delta

	if state == State.PARKED:
		var current_airport: Dictionary = world.airports[airport_index]
		var coords: Vector2 = world.runway_coordinates(position_km, current_airport)
		if speed_kmh > 68.0 and target_vs > 0.4:
			state = State.FLYING
			_show_message("Взлёт выполнен", 3.0, "")
		else:
			next_altitude = 0.0
			vertical_speed_mps = 0.0
			if abs(coords.y) > 0.22 or abs(coords.x) > FlightWorldScript.RUNWAY_LENGTH_KM * 0.7:
				_crash("Самолёт выкатился за пределы аэродрома")
				return

	altitude_m = clamp(next_altitude, 0.0, 5000.0)
	_update_angle_of_attack()
	if position_km.x < 0 or position_km.y < 0 or position_km.x > FlightWorldScript.SIZE_KM or position_km.y > FlightWorldScript.SIZE_KM:
		_crash("Самолёт покинул район полётов")
		return

	# Give the aircraft a few metres to leave a zero-elevation runway before
	# terrain collision becomes active; rising terrain is still detected after it lifts.
	if state == State.FLYING and altitude_m <= terrain + 3.0 and (altitude_m > 3.0 or vertical_speed_mps <= 0.0):
		if _try_land():
			return
		_crash("Столкновение с рельефом: высота земли %.0f м" % terrain)

func _try_land() -> bool:
	for i in world.airports.size():
		var airport: Dictionary = world.airports[i]
		var coords: Vector2 = world.runway_coordinates(position_km, airport)
		var aligned: bool = min(angle_difference_deg(heading_deg, airport.heading), angle_difference_deg(heading_deg, fmod(airport.heading + 180.0, 360.0))) < 14.0
		if abs(coords.x) <= FlightWorldScript.RUNWAY_LENGTH_KM * 0.5 and abs(coords.y) <= 0.13 and aligned and speed_kmh < 100.0 and vertical_speed_mps > -5.5 and throttle <= 0.12:
			state = State.LANDED
			airport_index = i
			altitude_m = 0.0
			speed_kmh = 0.0
			vertical_speed_mps = 0.0
			_show_message("Успешная посадка в аэропорту «%s»" % airport.name, -1.0)
			return true
	return false

func _crash(reason: String) -> void:
	state = State.CRASHED
	_show_message(reason, -1.0)

func _ready_message() -> String:
	var airport: Dictionary = world.airports[airport_index]
	return "Готов к взлёту с аэродрома «%s»" % airport.name

func _show_message(text: String, duration: float = -1.0, after_timeout: String = "") -> void:
	message = text
	message_time_remaining = duration
	message_after_timeout = after_timeout

func _update_message(delta: float) -> void:
	if message_time_remaining < 0.0:
		return
	message_time_remaining -= delta
	if message_time_remaining <= 0.0:
		message = message_after_timeout
		message_after_timeout = ""
		message_time_remaining = -1.0

func angle_difference_deg(a: float, b: float) -> float:
	return abs(fposmod(a - b + 180.0, 360.0) - 180.0)

func _update_angle_of_attack() -> void:
	var horizontal_speed_mps := speed_kmh / 3.6
	var flight_path_deg := rad_to_deg(atan2(vertical_speed_mps, maxf(horizontal_speed_mps, 1.0)))
	angle_of_attack_deg = clampf(pitch_deg - flight_path_deg, -30.0, 30.0)

func stall_warning_active() -> bool:
	return state == State.FLYING and (stalled or angle_of_attack_deg >= STALL_WARNING_AOA_DEG)

func fuel_flow_lpm() -> float:
	if fuel_l <= 0.0 or state == State.LANDED or state == State.CRASHED:
		return 0.0
	# Fictional light aircraft: 6 l/h at idle, up to 43.2 l/h at full power.
	return (0.10 + throttle * 0.62) * altitude_fuel_factor()

func altitude_fuel_factor() -> float:
	var altitude := clampf(altitude_m, 0.0, 5000.0)
	if altitude <= 2500.0:
		return lerpf(1.0, 0.82, altitude / 2500.0)
	return lerpf(0.82, 1.08, (altitude - 2500.0) / 2500.0)

func altitude_power_factor() -> float:
	if altitude_m <= 2500.0:
		return 1.0
	return lerpf(1.0, 0.82, clampf((altitude_m - 2500.0) / 2500.0, 0.0, 1.0))

func max_available_climb_mps() -> float:
	# Excess power above roughly 45% throttle can be spent on climbing. The
	# available excess fades smoothly above 3000 m and reaches zero at 5000 m.
	var throttle_excess := clampf((throttle - 0.45) / 0.55, 0.0, 1.0)
	var ceiling_factor := 1.0 - smoothstep(3000.0, 5000.0, altitude_m)
	return 10.0 * throttle_excess * ceiling_factor

func landing_guidance(index: int) -> Dictionary:
	var airport: Dictionary = world.airports[index]
	var coords: Vector2 = world.runway_coordinates(position_km, airport)
	# The supported approach is towards the negative threshold, flying along
	# the runway heading. The far-end beacon is then exactly 2 km away at touchdown.
	var distance_to_threshold_km: float = maxf(0.0, -FlightWorldScript.RUNWAY_LENGTH_KM * 0.5 - coords.x)
	var desired_altitude_m: float = distance_to_threshold_km * 1000.0 * tan(deg_to_rad(GLIDE_SLOPE_DEG))
	var localizer_tolerance_km: float = maxf(0.13, distance_to_threshold_km * 0.08)
	var glide_tolerance_m: float = maxf(15.0, desired_altitude_m * 0.15)
	var localizer_error: float = coords.y / localizer_tolerance_km
	var glide_error: float = (altitude_m - desired_altitude_m) / glide_tolerance_m
	var course_error: float = angle_difference_deg(heading_deg, airport.heading)
	return {
		"airport": airport,
		"distance_to_threshold_km": distance_to_threshold_km,
		"desired_altitude_m": desired_altitude_m,
		"localizer_error": localizer_error,
		"glide_error": glide_error,
		"in_localizer": absf(localizer_error) <= 1.0 and course_error <= 14.0,
		"in_glide": absf(glide_error) <= 1.0,
	}
