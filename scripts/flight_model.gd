class_name FlightModel
extends RefCounted

const FlightWorldScript = preload("res://scripts/world.gd")
const GLIDE_SLOPE_DEG := 3.3
const GLIDE_TOUCHDOWN_OFFSET_KM := FlightWorldScript.ILS_AIM_OFFSET_KM
const STALL_WARNING_AOA_DEG := 12.0
const STALL_AOA_DEG := 15.0
const STALL_RECOVERY_AOA_DEG := 10.0
const STALL_RECOVERY_SPEED_KMH := 75.0
const STALL_RECOVERY_YOKE_MAX := 0.25
const STALL_RECOVERY_HOLD_SECONDS := 0.75
const GROUND_CONTACT_CLEARANCE_M := 0.1
const CRUISE_SPEED_KMH := 200.0
const MAX_LEVEL_SPEED_KMH := 220.0
const VNO_KMH := 220.0
const VNE_KMH := 250.0
const BREAKUP_SPEED_KMH := 280.0
const MAX_AIRFRAME_STRESS := 100.0
const ROTATION_AUTHORITY_START_KMH := 60.0
const ROTATION_AUTHORITY_FULL_KMH := 100.0
const NOMINAL_STALL_SPEED_KMH := 75.0
const RECOMMENDED_ROTATION_SPEED_KMH := 75.0
const VX_KMH := 130.0
const VY_KMH := 130.0
const TAKEOFF_CONTACT_GRACE_SECONDS := 0.45

enum State { PARKED, FLYING, ROLLING, LANDED, CRASHED }

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
var stall_recovery_time := 0.0
var airframe_stress := 0.0
var wheel_brakes_applied := false
var fuel_l := 40.0
var fuel_capacity_l := 40.0
var engine_running := false
var state := State.PARKED
var airport_index := 0
var message := "Самолёт подготовлен к вылету"
var message_time_remaining := -1.0
var message_after_timeout := ""
var takeoff_grace_remaining := 0.0
var current_wind_kmh := Vector2.ZERO
var storm_intensity := 0.0
var storm_vertical_flow_mps := 0.0
var storm_roll_bias_deg := 0.0
var storm_pitch_bias_deg := 0.0
var storm_wind_gust_kmh := Vector2.ZERO
var storm_disturbance_timer := 0.0
var storm_vertical_target_mps := 0.0
var storm_roll_target_deg := 0.0
var storm_pitch_target_deg := 0.0
var storm_wind_target_kmh := Vector2.ZERO
var turbulence_rng := RandomNumberGenerator.new()

func _init(flight_world) -> void:
	world = flight_world
	turbulence_rng.seed = world.seed_value + 918273
	prepare_at_airport(0)

func prepare_at_airport(index: int, reverse_direction: bool = false) -> void:
	airport_index = index
	var airport: Dictionary = world.airports[index]
	var departure_heading: float = fposmod(float(airport.heading) + (180.0 if reverse_direction else 0.0), 360.0)
	position_km = Vector2(airport.position) - world.heading_vector(departure_heading) * 0.78
	heading_deg = departure_heading
	altitude_m = 0.0
	speed_kmh = 0.0
	throttle = 0.0
	yoke = Vector2.ZERO
	pitch_deg = 0.0
	bank_deg = 0.0
	vertical_speed_mps = 0.0
	takeoff_grace_remaining = 0.0
	angle_of_attack_deg = 0.0
	stalled = false
	stall_recovery_time = 0.0
	airframe_stress = 0.0
	wheel_brakes_applied = false
	engine_running = false
	storm_vertical_flow_mps = 0.0
	storm_roll_bias_deg = 0.0
	storm_pitch_bias_deg = 0.0
	storm_wind_gust_kmh = Vector2.ZERO
	storm_disturbance_timer = 0.0
	storm_vertical_target_mps = 0.0
	storm_roll_target_deg = 0.0
	storm_pitch_target_deg = 0.0
	storm_wind_target_kmh = Vector2.ZERO
	state = State.PARKED
	_show_message("", -1.0)

func _update_storm_disturbance(delta: float) -> void:
	if storm_intensity > 0.01:
		storm_disturbance_timer -= delta
		if storm_disturbance_timer <= 0.0:
			# A coherent pocket lasts long enough for the aircraft to gain/lose
			# meaningful altitude and heading. The next pocket is unpredictable,
			# but transitions into it remain gradual rather than needle noise.
			storm_disturbance_timer = turbulence_rng.randf_range(4.0, 8.0)
			var vertical_sign := -1.0 if turbulence_rng.randf() < 0.5 else 1.0
			var roll_sign := -1.0 if turbulence_rng.randf() < 0.5 else 1.0
			var pitch_sign := -1.0 if turbulence_rng.randf() < 0.5 else 1.0
			storm_vertical_target_mps = vertical_sign * turbulence_rng.randf_range(3.0, 7.0)
			storm_roll_target_deg = roll_sign * turbulence_rng.randf_range(12.0, 26.0)
			storm_pitch_target_deg = pitch_sign * turbulence_rng.randf_range(2.0, 7.0)
			storm_wind_target_kmh = world.heading_vector(turbulence_rng.randf_range(0.0, 360.0)) * turbulence_rng.randf_range(20.0, 55.0)
	else:
		storm_disturbance_timer = 0.0
		storm_vertical_target_mps = 0.0
		storm_roll_target_deg = 0.0
		storm_pitch_target_deg = 0.0
		storm_wind_target_kmh = Vector2.ZERO

	var intensity := storm_intensity
	storm_vertical_flow_mps = move_toward(storm_vertical_flow_mps, storm_vertical_target_mps * intensity, delta * 1.4)
	storm_roll_bias_deg = move_toward(storm_roll_bias_deg, storm_roll_target_deg * intensity, delta * 5.0)
	storm_pitch_bias_deg = move_toward(storm_pitch_bias_deg, storm_pitch_target_deg * intensity, delta * 1.5)
	storm_wind_gust_kmh = storm_wind_gust_kmh.move_toward(storm_wind_target_kmh * intensity, delta * 8.0)

func refuel() -> void:
	fuel_l = fuel_capacity_l
	_show_message("Самолёт заправлен: %.0f л" % fuel_l, 3.0, "")

func toggle_engine() -> void:
	if state == State.CRASHED:
		return
	engine_running = not engine_running
	_show_message("Двигатель запущен" if engine_running else "Двигатель остановлен", 3.0, "")

func update(delta: float) -> void:
	_update_message(delta)
	world.update_weather(delta)
	storm_intensity = world.storm_intensity_at(position_km) if state == State.FLYING else 0.0
	_update_storm_disturbance(delta)
	current_wind_kmh = world.wind_at(altitude_m) + storm_wind_gust_kmh if state == State.FLYING else Vector2.ZERO
	if state == State.CRASHED:
		return
	if fuel_l <= 0.0:
		throttle = 0.0
		engine_running = false
	else:
		fuel_l = max(0.0, fuel_l - fuel_flow_lpm() * delta / 60.0)
	if state == State.ROLLING:
		_update_ground_roll(delta)
		return
	if state == State.FLYING and takeoff_grace_remaining > 0.0:
		takeoff_grace_remaining = maxf(0.0, takeoff_grace_remaining - delta)

	var roll_authority := 0.32 if stalled else 1.0
	var storm_roll_command := storm_roll_bias_deg if state == State.FLYING else 0.0
	bank_deg = move_toward(bank_deg, (yoke.x * 38.0 + storm_roll_command) * roll_authority, delta * 55.0 * roll_authority)
	# Pulling the yoke down/towards the pilot raises the nose; pushing it up lowers it.
	if stalled:
		# During separated flow the elevator retains only weak authority and
		# cannot overpower the aircraft's natural nose-down recovery tendency.
		var stalled_pitch_target := -8.0 + yoke.y * 3.0
		pitch_deg = move_toward(pitch_deg, stalled_pitch_target, delta * 24.0)
	else:
		# Airflow controls how quickly the elevator can change pitch, not the
		# attitude selected by a held yoke. Reducing speed must not automatically
		# lower the nose and save the aircraft from a high-angle-of-attack stall.
		var pitch_command := yoke.y * 18.0 + (storm_pitch_bias_deg if state == State.FLYING else 0.0)
		if state == State.PARKED or state == State.LANDED:
			pitch_command = clampf(pitch_command, -10.0, 10.0)
		pitch_deg = move_toward(pitch_deg, pitch_command, delta * 30.0 * elevator_authority())
	_update_angle_of_attack()
	if state == State.FLYING:
		if not stalled and angle_of_attack_deg >= STALL_AOA_DEG:
			stalled = true
			stall_recovery_time = 0.0
			# Start the nose drop immediately on the frame the stall begins.
			pitch_deg = move_toward(pitch_deg, -8.0 + yoke.y * 3.0, delta * 24.0)
			_update_angle_of_attack()
		elif stalled:
			# Recovery requires the pilot to unload the elevator and maintain
			# attached-flow conditions. Full aft yoke can no longer trigger an
			# automatic stall/recovery/stall oscillation.
			var recovery_conditions := (
				yoke.y <= STALL_RECOVERY_YOKE_MAX
				and angle_of_attack_deg <= STALL_RECOVERY_AOA_DEG
				and speed_kmh >= STALL_RECOVERY_SPEED_KMH
			)
			if recovery_conditions:
				stall_recovery_time += delta
				if stall_recovery_time >= STALL_RECOVERY_HOLD_SECONDS:
					stalled = false
					stall_recovery_time = 0.0
			else:
				stall_recovery_time = 0.0
	var speed_factor: float = clampf(speed_kmh / 95.0, 0.15, 1.45)
	heading_deg = fposmod(heading_deg + bank_deg * 0.34 * speed_factor * roll_authority * delta, 360.0)

	# In flight the airframe tends to retain a minimum glide speed. This gives
	# about 91 km/h at 30% power, 200 km/h at roughly 89% power and a
	# maximum level speed of about 220 km/h at full power near sea level.
	var glide_speed: float = 35.0 if state == State.FLYING else 0.0
	var raw_pitch_climb: float = pitch_deg * 0.55 * clampf((speed_kmh - 55.0) / 75.0, 0.0, 1.0) * altitude_power_factor()
	var available_climb: float = max_available_climb_mps()
	# Raising the nose converts airspeed into height. Near the practical ceiling
	# there is not enough excess power to sustain the requested climb, so the
	# unmet part causes additional speed loss and eventually excessive AoA.
	var unsupported_climb: float = maxf(0.0, raw_pitch_climb - available_climb)
	var climb_drag: float = maxf(0.0, pitch_deg) * 1.2
	# A large sustained pull creates rapidly increasing induced drag. It can
	# briefly convert speed into height, but cannot be used as a permanent
	# maximum-climb command: the aircraft slows towards a high-AoA stall.
	var nose_up_ratio := clampf(maxf(0.0, pitch_deg) / 18.0, 0.0, 1.0)
	var heavy_pull_ratio := smoothstep(0.55, 1.0, nose_up_ratio)
	var high_angle_drag := 155.0 * heavy_pull_ratio * heavy_pull_ratio if state == State.FLYING else 0.0
	var dive_drag: float = maxf(0.0, -pitch_deg) * 0.25
	# Losing altitude converts potential energy into airspeed. A normal approach
	# keeps the established response, while the extra nonlinear term lets a steep
	# dive accelerate through VNE instead of meeting an artificial speed wall.
	var descent_speed_mps := maxf(0.0, -vertical_speed_mps)
	var gravity_dive_bonus: float = descent_speed_mps * 4.0 + maxf(0.0, descent_speed_mps - 3.0) * 3.0
	var powered_throttle := throttle if engine_running else 0.0
	var target_speed: float = glide_speed + powered_throttle * 185.0 * altitude_power_factor() - climb_drag - high_angle_drag - dive_drag - unsupported_climb * 8.0 + gravity_dive_bonus
	var acceleration: float = (target_speed - speed_kmh) * 0.22
	# There is intentionally no operational hard speed cap. Aerodynamic drag
	# limits level flight, while a sufficiently steep dive can carry the aircraft
	# through the caution range and beyond VNE.
	speed_kmh = maxf(0.0, speed_kmh + acceleration * delta)
	_update_airframe_stress(delta)
	if state == State.CRASHED:
		return
	if (state == State.PARKED or state == State.LANDED) and wheel_brakes_applied:
		speed_kmh = maxf(0.0, speed_kmh - 10.0 * delta)

	var lift_factor: float = clampf((speed_kmh - 55.0) / 75.0, 0.0, 1.0)
	var lift_efficiency := 0.25 if stalled else 1.0
	raw_pitch_climb = pitch_deg * 0.55 * lift_factor * altitude_power_factor()
	var pitch_climb: float = raw_pitch_climb
	if pitch_climb > 0.0:
		pitch_climb = minf(pitch_climb, available_climb)
	pitch_climb *= lift_efficiency
	# At 30% power, neutral pitch and ~92 km/h this produces a conventional
	# three-degree glide path (about -1.3 m/s).
	var low_power_sink: float = maxf(0.0, 0.45 - powered_throttle) * 17.5 * lift_factor
	var low_speed_sink: float = 0.0 if speed_kmh >= 62.0 else (62.0 - speed_kmh) * 0.17
	var separated_flow_sink: float = (6.0 + maxf(0.0, angle_of_attack_deg - STALL_AOA_DEG) * 0.45) if stalled else 0.0
	var target_vs: float = pitch_climb - low_power_sink - low_speed_sink - separated_flow_sink + storm_vertical_flow_mps
	# Outside storms the established response stays untouched. In a severe cell
	# aircraft inertia prevents it from instantly following a newly encountered
	# vertical air current; that temporary relative airflow changes AoA and can
	# produce a genuine gust-induced stall.
	var vertical_response := lerpf(4.5, 0.9, storm_intensity)
	vertical_speed_mps = move_toward(vertical_speed_mps, target_vs, delta * vertical_response)

	var direction: Vector2 = world.heading_vector(heading_deg)
	position_km += (direction * speed_kmh + current_wind_kmh) / 3600.0 * delta
	var terrain: float = world.height_at(position_km)
	var next_altitude: float = altitude_m + vertical_speed_mps * delta

	if state == State.PARKED or state == State.LANDED:
		var current_airport: Dictionary = world.airports[airport_index]
		var coords: Vector2 = world.runway_coordinates(position_km, current_airport)
		if speed_kmh > 68.0 and target_vs > 0.4:
			state = State.FLYING
			wheel_brakes_applied = false
			# Collision grace only protects against numerical re-contact with the
			# runway. It no longer changes the commanded pitch or lift.
			takeoff_grace_remaining = TAKEOFF_CONTACT_GRACE_SECONDS
			_show_message("Взлёт выполнен", 3.0, "")
		else:
			next_altitude = 0.0
			vertical_speed_mps = 0.0
			if abs(coords.y) > FlightWorldScript.RUNWAY_WIDTH_KM * 0.5 or abs(coords.x) > FlightWorldScript.RUNWAY_LENGTH_KM * 0.5:
				_crash("Выехали за пределы ВПП «%s»: боковое отклонение %.1f м" % [current_airport.name, absf(coords.y) * 1000.0] if abs(coords.y) > FlightWorldScript.RUNWAY_WIDTH_KM * 0.5 else "Выехали за торец ВПП «%s»" % current_airport.name)
				return

	altitude_m = clamp(next_altitude, 0.0, 5000.0)
	_update_angle_of_attack()
	if position_km.x < 0 or position_km.y < 0 or position_km.x > FlightWorldScript.SIZE_KM or position_km.y > FlightWorldScript.SIZE_KM:
		_crash("Самолёт покинул район полётов")
		return

	# Altitude represents the aircraft's contact point in this simplified model,
	# so both touchdown prediction and actual terrain contact use the same level.
	if state == State.FLYING and takeoff_grace_remaining <= 0.0 and altitude_m <= terrain + GROUND_CONTACT_CLEARANCE_M and (altitude_m > GROUND_CONTACT_CLEARANCE_M or vertical_speed_mps <= 0.0):
		if _try_land():
			return
		var landing_failure := _landing_failure_reason()
		_crash(landing_failure if not landing_failure.is_empty() else "Столкновение с рельефом: высота земли %.0f м" % terrain)

func _try_land() -> bool:
	for i in world.airports.size():
		var airport: Dictionary = world.airports[i]
		var coords: Vector2 = world.runway_coordinates(position_km, airport)
		# Crosswind approaches require the nose to be pointed into the wind. This
		# simplified aircraft has no separate rudder/de-crab control, so touchdown
		# eligibility is based on being over the runway, not on a fixed nose-angle
		# limit. Direction still matters during the ground roll because the player
		# must keep the aircraft inside the runway boundaries.
		if abs(coords.x) <= FlightWorldScript.RUNWAY_LENGTH_KM * 0.5 and abs(coords.y) <= FlightWorldScript.RUNWAY_WIDTH_KM * 0.5 and vertical_speed_mps <= 0.0 and vertical_speed_mps > -5.5:
			var touchdown_vertical_speed := vertical_speed_mps
			state = State.ROLLING
			airport_index = i
			altitude_m = 0.0
			vertical_speed_mps = 0.0
			pitch_deg = 0.0
			bank_deg = 0.0
			stalled = false
			stall_recovery_time = 0.0
			wheel_brakes_applied = false
			var touchdown_description := "Жёсткое касание" if touchdown_vertical_speed <= -2.0 else "Касание"
			_show_message("%s ВПП «%s» на %.1f км/ч — газ 0%%, удерживайте S для торможения" % [touchdown_description, airport.name, speed_kmh], -1.0)
			return true
	return false

func _update_ground_roll(delta: float) -> void:
	var airport: Dictionary = world.airports[airport_index]
	# Holding S reduces the throttle and, once it reaches zero, seamlessly
	# applies the wheel brakes. Releasing S releases them.
	var engine_acceleration_kmh_s := (throttle if engine_running else 0.0) * 5.0
	var rolling_resistance_kmh_s := 0.35
	var wheel_braking_kmh_s := 10.0 if wheel_brakes_applied else 0.0
	var acceleration_kmh_s := engine_acceleration_kmh_s - rolling_resistance_kmh_s - wheel_braking_kmh_s
	speed_kmh = clampf(speed_kmh + acceleration_kmh_s * delta, 0.0, MAX_LEVEL_SPEED_KMH)
	# On the ground the lateral yoke input stands in for simple nose-wheel/rudder
	# steering. This lets the pilot remove a crosswind crab after touchdown.
	var steering_authority := clampf(speed_kmh / 25.0, 0.25, 1.0)
	heading_deg = fposmod(heading_deg + yoke.x * 28.0 * steering_authority * delta, 360.0)
	position_km += world.heading_vector(heading_deg) * (speed_kmh / 3600.0) * delta
	altitude_m = 0.0
	vertical_speed_mps = 0.0
	var coords: Vector2 = world.runway_coordinates(position_km, airport)
	var half_length := FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var half_width := FlightWorldScript.RUNWAY_WIDTH_KM * 0.5
	if absf(coords.x) > half_length or absf(coords.y) > half_width:
		_crash("Выкатились за пределы ВПП «%s»: скорость %.1f км/ч" % [airport.name, speed_kmh])
		return
	if speed_kmh <= 0.05:
		speed_kmh = 0.0
		state = State.LANDED
		_show_message("Успешная посадка в аэропорту «%s»" % airport.name, -1.0)

func _landing_failure_reason() -> String:
	var nearest_airport: Dictionary = {}
	var nearest_coords := Vector2.ZERO
	var nearest_score := INF
	for airport in world.airports:
		var coords: Vector2 = world.runway_coordinates(position_km, airport)
		var longitudinal_excess := maxf(0.0, absf(coords.x) - FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
		var score := Vector2(longitudinal_excess, coords.y).length()
		if score < nearest_score:
			nearest_score = score
			nearest_airport = airport
			nearest_coords = coords
	# Do not describe an ordinary mountain collision as a failed runway contact.
	if nearest_airport.is_empty() or absf(nearest_coords.y) > 2.0 or absf(nearest_coords.x) > 5.0:
		return ""
	var half_runway := FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	if nearest_coords.x < -half_runway:
		return "Касание до ВПП «%s»: %.0f м" % [nearest_airport.name, (-half_runway - nearest_coords.x) * 1000.0]
	if nearest_coords.x > half_runway:
		return "Касание после конца ВПП «%s»: %.0f м" % [nearest_airport.name, (nearest_coords.x - half_runway) * 1000.0]
	if absf(nearest_coords.y) > FlightWorldScript.RUNWAY_WIDTH_KM * 0.5:
		return "Касание вне ВПП «%s»: боковое отклонение %.0f м" % [nearest_airport.name, absf(nearest_coords.y) * 1000.0]
	var failures: Array[String] = []
	if vertical_speed_mps <= -5.5:
		failures.append("жёсткое касание %+.2f м/с" % vertical_speed_mps)
	if failures.is_empty():
		return "Посадка не засчитана на ВПП «%s»" % nearest_airport.name
	return "Посадка не удалась: %s" % "; ".join(failures)

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
	# AoA depends on motion relative to the surrounding air, not on climb rate
	# over the ground. A rising air mass can carry the aircraft upward while the
	# initial gust still meets the wing from below and increases angle of attack.
	var air_relative_vertical_speed_mps := vertical_speed_mps - storm_vertical_flow_mps
	var flight_path_deg := rad_to_deg(atan2(air_relative_vertical_speed_mps, maxf(horizontal_speed_mps, 1.0)))
	angle_of_attack_deg = clampf(pitch_deg - flight_path_deg, -30.0, 30.0)

func stall_warning_active() -> bool:
	return state == State.FLYING and (stalled or angle_of_attack_deg >= STALL_WARNING_AOA_DEG)

func elevator_authority() -> float:
	if speed_kmh < ROTATION_AUTHORITY_START_KMH:
		# A small residual represents propeller wash over the tail, but it is not
		# enough to rotate the aircraft while stationary or at taxi speed.
		return 0.08 * clampf(speed_kmh / ROTATION_AUTHORITY_START_KMH, 0.0, 1.0)
	return lerpf(0.08, 1.0, smoothstep(ROTATION_AUTHORITY_START_KMH, ROTATION_AUTHORITY_FULL_KMH, speed_kmh))

func overspeed_warning_active() -> bool:
	return state == State.FLYING and speed_kmh > VNO_KMH

func vne_exceeded() -> bool:
	return state == State.FLYING and speed_kmh > VNE_KMH

func _update_airframe_stress(delta: float) -> void:
	if state != State.FLYING:
		airframe_stress = move_toward(airframe_stress, 0.0, 12.0 * delta)
		return
	if speed_kmh >= BREAKUP_SPEED_KMH:
		_crash("Разрушение планера: скорость %.1f км/ч превысила предел прочности" % speed_kmh)
		return

	var stress_rate := 0.0
	if speed_kmh > VNE_KMH:
		# At 260 km/h the pilot has roughly ten seconds to recover; at 270
		# km/h only a few seconds remain. Aerodynamic loads grow approximately
		# with the square of airspeed.
		stress_rate += 4.0 + 0.10 * pow(speed_kmh - VNE_KMH, 2.0)
	if speed_kmh > VNO_KMH:
		# Strong control inputs in the yellow arc add load even below VNE.
		var caution_ratio := (speed_kmh - VNO_KMH) / (VNE_KMH - VNO_KMH)
		var control_input := maxf(absf(yoke.x), maxf(0.0, absf(yoke.y) - 0.35))
		stress_rate += 3.0 * caution_ratio * caution_ratio * control_input * control_input

	if stress_rate > 0.0:
		airframe_stress += stress_rate * delta
	else:
		# This represents temporary structural loading and vibration rather than
		# repairable permanent damage; it subsides after returning below VNO.
		airframe_stress = move_toward(airframe_stress, 0.0, 12.0 * delta)
	if airframe_stress >= MAX_AIRFRAME_STRESS:
		_crash("Разрушение планера из-за превышения допустимой скорости (%.1f км/ч)" % speed_kmh)

func fuel_flow_lpm() -> float:
	if not engine_running or fuel_l <= 0.0 or state == State.CRASHED:
		return 0.0
	# Game-scaled engine map. A simple quadratic made low power unrealistically
	# efficient: 45% throttle could cover much more distance than cruise. These
	# monotonic reference points put best range near 75--80%, retain normal
	# 87--90% cruise, and make continuous full power distinctly expensive.
	var sea_level_flow: float
	if throttle <= 0.30:
		sea_level_flow = lerpf(0.10, 0.28, throttle / 0.30)
	elif throttle <= 0.45:
		sea_level_flow = lerpf(0.28, 0.36, inverse_lerp(0.30, 0.45, throttle))
	elif throttle <= 0.50:
		sea_level_flow = lerpf(0.36, 0.38, inverse_lerp(0.45, 0.50, throttle))
	elif throttle <= 0.75:
		sea_level_flow = lerpf(0.38, 0.445, inverse_lerp(0.50, 0.75, throttle))
	elif throttle <= 0.80:
		sea_level_flow = lerpf(0.445, 0.47, inverse_lerp(0.75, 0.80, throttle))
	elif throttle <= 0.87:
		sea_level_flow = lerpf(0.47, 0.55, inverse_lerp(0.80, 0.87, throttle))
	elif throttle <= 0.90:
		sea_level_flow = lerpf(0.55, 0.58, inverse_lerp(0.87, 0.90, throttle))
	else:
		sea_level_flow = lerpf(0.58, 0.84, inverse_lerp(0.90, 1.0, throttle))
	return sea_level_flow * altitude_fuel_factor()

func estimated_range_km() -> float:
	var flow_lpm := fuel_flow_lpm()
	if flow_lpm <= 0.0001 or speed_kmh <= 0.0:
		return 0.0
	var flight_minutes := fuel_l / flow_lpm
	return flight_minutes * speed_kmh / 60.0

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
	var powered_throttle := throttle if engine_running else 0.0
	var throttle_excess := clampf((powered_throttle - 0.45) / 0.55, 0.0, 1.0)
	var ceiling_factor := 1.0 - smoothstep(3000.0, 5000.0, altitude_m)
	return 10.0 * throttle_excess * ceiling_factor

func landing_guidance(index: int, signal_available_override: Variant = null) -> Dictionary:
	var airport: Dictionary = world.airports[index]
	var runway_beacon: Dictionary = world.beacons[index]
	var beacon_distance_km: float = position_km.distance_to(runway_beacon.position)
	var signal_available: bool = beacon_distance_km <= float(runway_beacon.range_km)
	if signal_available_override != null:
		signal_available = bool(signal_available_override)
	var approach_sign: float = world.runway_approach_sign(airport, heading_deg)
	var approach_heading: float = fposmod(float(airport.heading) + (180.0 if approach_sign < 0.0 else 0.0), 360.0)
	var forward: Vector2 = world.heading_vector(approach_heading)
	var delta: Vector2 = position_km - Vector2(airport.position)
	var right := Vector2(forward.y, -forward.x)
	var along: float = delta.dot(forward)
	var cross: float = delta.dot(right)
	var distance_to_threshold_km: float = maxf(0.0, -FlightWorldScript.RUNWAY_LENGTH_KM * 0.5 - along)
	var near_threshold: Vector2 = airport.position - forward * (FlightWorldScript.RUNWAY_LENGTH_KM * 0.5)
	var actual_distance_to_threshold_km: float = position_km.distance_to(near_threshold)
	# The ideal glide path intersects the runway 60 m beyond the threshold, not
	# at its edge. At the threshold it therefore still commands about 3.5 m AGL.
	var glide_distance_km: float = maxf(0.0, -FlightWorldScript.RUNWAY_LENGTH_KM * 0.5 + GLIDE_TOUCHDOWN_OFFSET_KM - along)
	var desired_altitude_m: float = glide_distance_km * 1000.0 * tan(deg_to_rad(GLIDE_SLOPE_DEG))
	var localizer_tolerance_km: float = maxf(FlightWorldScript.RUNWAY_WIDTH_KM * 0.5, distance_to_threshold_km * 0.08)
	var glide_tolerance_m: float = maxf(15.0, desired_altitude_m * 0.15)
	var localizer_error: float = cross / localizer_tolerance_km
	var glide_error: float = (altitude_m - desired_altitude_m) / glide_tolerance_m
	# ILS localizer describes position relative to the runway centreline. With a
	# crosswind the nose must point into the wind, so judging the localizer by
	# aircraft heading would incorrectly reject a perfectly tracked approach.
	var ground_velocity: Vector2 = world.heading_vector(heading_deg) * speed_kmh + current_wind_kmh
	var ground_track_heading: float = world.vector_heading(ground_velocity) if ground_velocity.length_squared() > 0.01 else heading_deg
	var signed_course_error: float = wrapf(ground_track_heading - approach_heading, -180.0, 180.0)
	var along_ground_speed_kmh: float = maxf(0.0, ground_velocity.dot(forward))
	var desired_vertical_speed_mps: float = -(along_ground_speed_kmh / 3.6) * tan(deg_to_rad(GLIDE_SLOPE_DEG))
	return {
		"airport": airport,
		"approach_heading": approach_heading,
		"approach_sign": approach_sign,
		"signal_available": signal_available,
		"beacon_distance_km": beacon_distance_km,
		"signal_range_km": runway_beacon.range_km,
		"distance_to_threshold_km": distance_to_threshold_km,
		"actual_distance_to_threshold_km": actual_distance_to_threshold_km,
		"desired_altitude_m": desired_altitude_m,
		"localizer_error": localizer_error,
		"localizer_tolerance_km": localizer_tolerance_km,
		"glide_error": glide_error,
		"course_error_deg": signed_course_error,
		"heading_error_deg": wrapf(heading_deg - approach_heading, -180.0, 180.0),
		"ground_track_heading": ground_track_heading,
		"desired_vertical_speed_mps": desired_vertical_speed_mps,
		"in_localizer": signal_available and absf(localizer_error) <= 1.0,
		"in_glide": signal_available and absf(glide_error) <= 1.0,
	}

func touchdown_prediction(index: int) -> Dictionary:
	var valid := vertical_speed_mps < -0.05
	if not valid:
		return {"valid": false, "distance_from_threshold_km": 0.0}
	var airport: Dictionary = world.airports[index]
	var seconds_to_surface: float = altitude_m / -vertical_speed_mps
	var ground_velocity: Vector2 = world.heading_vector(heading_deg) * speed_kmh + current_wind_kmh
	var predicted_position: Vector2 = position_km + ground_velocity / 3600.0 * seconds_to_surface
	var approach_sign: float = world.runway_approach_sign(airport, heading_deg)
	var predicted_coords: Vector2 = world.runway_coordinates(predicted_position, airport)
	var predicted_along: float = predicted_coords.x * approach_sign
	return {
		"valid": true,
		"distance_from_threshold_km": predicted_along + FlightWorldScript.RUNWAY_LENGTH_KM * 0.5,
	}
