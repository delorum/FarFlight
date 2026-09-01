class_name FlightModel
extends RefCounted

const FlightWorldScript = preload("res://scripts/world.gd")

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
var fuel_l := 180.0
var fuel_capacity_l := 180.0
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
		fuel_l = max(0.0, fuel_l - (1.1 + throttle * 7.5) * delta / 60.0)

	bank_deg = move_toward(bank_deg, yoke.x * 38.0, delta * 55.0)
	# Pulling the yoke down/towards the pilot raises the nose; pushing it up lowers it.
	pitch_deg = move_toward(pitch_deg, yoke.y * 13.0, delta * 30.0)
	var speed_factor: float = clampf(speed_kmh / 95.0, 0.15, 1.45)
	heading_deg = fposmod(heading_deg + bank_deg * 0.34 * speed_factor * delta, 360.0)

	var target_speed: float = throttle * 215.0 - max(0.0, pitch_deg) * 1.25
	var acceleration: float = (target_speed - speed_kmh) * 0.22
	speed_kmh = clamp(speed_kmh + acceleration * delta, 0.0, 200.0)

	var lift_factor: float = clampf((speed_kmh - 55.0) / 75.0, 0.0, 1.0)
	var power_climb: float = (throttle - 0.43) * 8.0 * lift_factor
	var pitch_climb: float = pitch_deg * 0.55 * lift_factor
	var stall_sink: float = 0.0 if speed_kmh >= 62.0 else (62.0 - speed_kmh) * 0.17
	var target_vs: float = power_climb + pitch_climb - stall_sink
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
