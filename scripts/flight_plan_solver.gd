extends RefCounted
## Pure flight-plan math. The widget owns editing history, map bindings and UI;
## this module only derives values for a fixed, caller-owned route distance.

const MIN_DISTANCE_KM := 0.001

static func solve(input: Dictionary, initial_altitude: float, from_heading: bool, derive_airspeed: bool, derive_vertical: bool) -> Dictionary:
	var output := input.duplicate()
	var locked_distance := float(output.distance)
	if locked_distance < MIN_DISTANCE_KM:
		return {"valid": false, "reason": "Расстояние должно быть больше нуля", "navigation_valid": false}
	if derive_airspeed:
		var required := required_airspeed(output, from_heading)
		if not required.valid:
			return {"valid": false, "reason": required.reason, "navigation_valid": true}
		output.speed = required.speed
	var wind := navigation(output, from_heading)
	if not wind.valid:
		return {"valid": false, "reason": wind.reason, "navigation_valid": false}
	output.heading = wind.heading
	output.track = wind.track
	var prediction := calculate(output, "distance", initial_altitude, from_heading)
	if not prediction.valid:
		prediction["navigation_valid"] = true
		return prediction
	if derive_vertical:
		var minutes: float = prediction.values.time
		var height_difference: float = float(output.altitude) - initial_altitude
		if minutes <= 0.0:
			return {"valid": false, "reason": "Для расчёта высоты нужна ненулевая длительность", "navigation_valid": true}
		output.vertical = height_difference / (minutes * 60.0)
		prediction = calculate(output, "distance", initial_altitude, from_heading)
	if prediction.valid:
		prediction.values.distance = locked_distance
	prediction["navigation_valid"] = true
	return prediction

static func required_airspeed(input: Dictionary, from_heading: bool) -> Dictionary:
	var minutes: float = input.time
	if minutes <= 0.0:
		return {"valid": false, "reason": "Для ненулевого расстояния задайте время больше нуля"}
	var required_ground_speed: float = float(input.distance) / minutes * 60.0
	var wind_angle := deg_to_rad(float(input.wind_from))
	var wind_vector := Vector2(-sin(wind_angle), cos(wind_angle)) * float(input.wind_speed)
	var angle := deg_to_rad(float(input.heading if from_heading else input.track))
	var forward := Vector2(sin(angle), -cos(angle))
	if not from_heading:
		return {"valid": true, "speed": (forward * required_ground_speed - wind_vector).length()}
	var along := wind_vector.dot(forward)
	var discriminant := required_ground_speed * required_ground_speed - (wind_vector.length_squared() - along * along)
	var speed := -along + sqrt(maxf(0.0, discriminant))
	if discriminant < -0.000001 or speed < 0.0:
		return {"valid": false, "reason": "Такое время и расстояние недостижимы при заданных ветре и курсе"}
	return {"valid": true, "speed": speed}

static func calculate(input: Dictionary, changed: String, altitude: float, from_heading: bool = false) -> Dictionary:
	var output := input.duplicate()
	var wind := navigation(output, from_heading)
	if not wind.valid:
		return wind
	var ground_speed: float = wind.speed
	output.heading = wind.heading
	output.track = wind.track
	var minutes: float = output.time
	if changed == "distance":
		if ground_speed <= 0.0 and output.distance > 0.0:
			return {"valid": false, "reason": "Для расчёта времени нужна скорость больше нуля"}
		minutes = float(output.distance) / ground_speed * 60.0 if ground_speed > 0.0 else 0.0
	elif changed == "altitude":
		var height_difference: float = output.altitude - altitude
		if is_zero_approx(height_difference):
			minutes = 0.0
		elif is_zero_approx(float(output.vertical)) or height_difference * float(output.vertical) < 0.0:
			return {"valid": false, "reason": "Для этой высоты задайте набор (+) или снижение (−)"}
		else:
			minutes = height_difference / float(output.vertical) / 60.0
	output.time = minutes
	var calculated_distance := ground_speed * minutes / 60.0
	if calculated_distance < MIN_DISTANCE_KM:
		return {"valid": false, "reason": "Расстояние не может быть обнулено: измените время или скорость"}
	output.distance = calculated_distance
	output.altitude = altitude + float(output.vertical) * minutes * 60.0
	for key in output:
		if not is_finite(float(output[key])):
			return {"valid": false, "reason": "Значения слишком велики для расчёта"}
	return {"valid": true, "values": output}

static func navigation(input: Dictionary, from_heading: bool) -> Dictionary:
	if not from_heading:
		var result := wind_triangle(float(input.speed), float(input.get("track", 0.0)), float(input.get("wind_from", 0.0)), float(input.get("wind_speed", 0.0)))
		result["track"] = float(input.get("track", 0.0))
		return result
	var heading: float = input.get("heading", 0.0)
	var angle := deg_to_rad(heading)
	var wind_angle := deg_to_rad(float(input.get("wind_from", 0.0)))
	var velocity := Vector2(sin(angle), -cos(angle)) * float(input.speed) + Vector2(-sin(wind_angle), cos(wind_angle)) * float(input.get("wind_speed", 0.0))
	if velocity.length_squared() < 0.00000001:
		return {"valid": false, "reason": "Нет движения над землёй: направление пути не определено"}
	return {"valid": true, "heading": heading, "track": fposmod(rad_to_deg(atan2(velocity.x, -velocity.y)), 360.0), "speed": velocity.length()}

static func wind_triangle(airspeed: float, track: float, wind_from: float, wind_speed: float) -> Dictionary:
	# Compass angles increase clockwise; wind direction means FROM.
	var angle := deg_to_rad(track)
	var forward := Vector2(sin(angle), -cos(angle))
	var right := Vector2(cos(angle), sin(angle))
	var wind_angle := deg_to_rad(wind_from)
	var wind := Vector2(-sin(wind_angle), cos(wind_angle)) * wind_speed
	var crosswind := wind.dot(right)
	if absf(crosswind) > airspeed + 0.000001:
		return {"valid": false, "reason": "Боковой ветер слишком силён: выбранный путь удержать невозможно"}
	var along_air := sqrt(maxf(0.0, airspeed * airspeed - crosswind * crosswind))
	var ground_speed := along_air + wind.dot(forward)
	if ground_speed <= 0.000001 and (airspeed > 0.000001 or wind_speed > 0.000001):
		return {"valid": false, "reason": "Ветер не позволяет продвигаться по выбранному пути"}
	var correction := rad_to_deg(atan2(-crosswind, along_air)) if airspeed > 0.000001 else 0.0
	return {"valid": true, "heading": fposmod(track + correction, 360.0), "speed": maxf(0.0, ground_speed)}
