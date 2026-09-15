extends RefCounted
## Ground-truth flight log; presentation decides when the player may see it.
const Flight = preload("res://scripts/flight_model.gd")
var flight_trajectory: Array[Dictionary] = []
var trajectory_finished := false
var trajectory_recording_started := false
var final_trajectory_visible := true
var trajectory_elapsed_seconds := 0.0
var trajectory_distance_km := 0.0
var trajectory_last_position := Vector2.ZERO

func reset(flight) -> void:
	flight_trajectory.clear()
	trajectory_finished = false
	trajectory_recording_started = false
	final_trajectory_visible = true
	trajectory_elapsed_seconds = 0.0
	trajectory_distance_km = 0.0
	if flight != null:
		trajectory_last_position = flight.position_km
		flight_trajectory.append(point(flight.position_km))

func point(position: Vector2) -> Dictionary:
	return {"position": position, "time_seconds": trajectory_elapsed_seconds, "distance_km": trajectory_distance_km}

func update(flight, previous_state: int, previous_speed: float, delta: float) -> bool:
	var changed := false
	if previous_state == Flight.State.LANDED and previous_speed <= 0.05 and flight.speed_kmh > 0.05:
		reset(flight)
		changed = true
	var distance := trajectory_last_position.distance_to(flight.position_km)
	var was_recording := trajectory_recording_started
	if distance > 0.000001 or flight.speed_kmh > 0.05:
		trajectory_recording_started = true
	changed = changed or (trajectory_recording_started and not was_recording)
	if trajectory_recording_started and not trajectory_finished:
		trajectory_elapsed_seconds += delta
		trajectory_distance_km += distance
	trajectory_last_position = flight.position_km
	if flight_trajectory.is_empty() or Vector2(flight_trajectory[-1].position).distance_to(flight.position_km) >= 0.03:
		flight_trajectory.append(point(flight.position_km))
	var finished: bool = flight.state in [Flight.State.CRASHED, Flight.State.LANDED] and flight.state != previous_state
	if finished:
		if not Vector2(flight_trajectory[-1].position).is_equal_approx(flight.position_km):
			flight_trajectory.append(point(flight.position_km))
		trajectory_finished = true
		final_trajectory_visible = true
		flight._show_message("%s • путь %.1f км • время %s" % [flight.message, trajectory_distance_km, format_time(trajectory_elapsed_seconds)], -1.0, "")
	return changed or finished

static func format_time(seconds_value: float) -> String:
	var total := maxi(0, roundi(seconds_value))
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]
