extends SceneTree
const World = preload("res://scripts/world.gd")
const Flight = preload("res://scripts/flight_model.gd")
const Contact = preload("res://scripts/landing_contact.gd")
const Predictor = preload("res://scripts/landing_predictor.gd")
const Display = preload("res://scripts/ils_display_state.gd")
const Localization = preload("res://scripts/localization.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func aircraft(world, pitch: float, speed := 90.0, sink := 1.0):
	var result := Flight.new(world)
	result.position_km = world.airports[0].position
	result.heading_deg = world.airports[0].heading
	result.state = Flight.State.FLYING
	result.altitude_m = 0.05
	result.pitch_deg = pitch
	result.yoke.y = pitch / Flight.YOKE_PITCH_RANGE_DEG
	result.speed_kmh = speed
	result.vertical_speed_mps = -sink
	result.engine_running = true
	result.electrical_power = true
	result.throttle = 0.3
	return result

func _initialize() -> void:
	check(Contact.NOSE_LIMIT_DEG < -13.0 and Contact.NOSE_LIMIT_DEG > -15.0, "Nose clearance must derive from the propeller/main-gear geometry")
	check(Contact.TAIL_LIMIT_DEG > 6.0 and Contact.TAIL_LIMIT_DEG < 8.0, "Tail clearance must use the fuselage underside, not the tailwheel")
	for pitch in [Contact.NOSE_LIMIT_DEG, 0.0, Contact.TAIL_LIMIT_DEG]:
		check(Contact.part(pitch).is_empty() and Contact.contact_height_m(pitch) == 0.0, "Boundary and neutral attitudes must permit normal wheel contact")
	var world := World.new(424242)
	world.storms.clear()
	for layer in world.wind_layers:
		layer.speed_kmh = 0.0
	var normal = aircraft(world, 0.0)
	normal.yoke.y = 1.0
	check(normal._try_land() and normal.state == Flight.State.ROLLING and normal.airframe_condition == 100.0, "Actual pitch, not yoke command, must govern contact")
	for sample in [{"pitch": Contact.NOSE_LIMIT_DEG - 0.25, "part": "nose", "warning": "НОС НИЗКО"}, {"pitch": Contact.TAIL_LIMIT_DEG + 0.25, "part": "tail", "warning": "НОС ВЫСОКО"}]:
		var plane = aircraft(world, sample.pitch)
		var estimate := Contact.assess(sample.pitch, -1.0, 90.0)
		check(not estimate.fatal and estimate.damage > 0 and not estimate.safe, "A marginal body strike must damage rather than instantly destroy the airframe")
		var state := Display.build(plane, 0, true, {"valid": false}, 350)
		check(state.attitude_warning == sample.warning, "ILS warning must describe actual pitch even without a descent forecast")
		var frozen := Predictor._trajectory_result(plane, world.airports[0], 1.0, 4.0)
		check(frozen.valid and frozen.touchdown_part == sample.part and not frozen.safe_landing, "Short extrapolation must report the same contact geometry")
		check(not Display.prediction_inside_runway(frozen), "A body-strike forecast must not produce a green landing marker")
		check(plane._try_land() and plane.state == Flight.State.ROLLING and plane.last_touchdown.part == sample.part, "A minor strike must still allow rollout")
		check(is_equal_approx(plane.airframe_condition, 100.0 - float(estimate.damage)), "Strike damage must be applied exactly once")
		var impact := Predictor._impact_result(plane, world.airports[0], 1.0, 0.2, true, world.heading_vector(plane.heading_deg) * 0.005)
		check(not impact.safe_landing and impact.touchdown_part == sample.part and is_equal_approx(impact.touchdown_pitch_deg, sample.pitch), "Full prediction must retain impact evidence after the rollout resets pitch")
		var condition: float = plane.airframe_condition
		plane.yoke = Vector2.ZERO
		plane._update_ground_roll(0.01)
		check(plane.airframe_condition == condition, "Rollout must not repeat strike damage")
		var restored := Flight.new(world)
		check(restored.restore_snapshot(plane.snapshot(), plane.turbulence_rng.state) and restored.airframe_condition == condition and restored.last_touchdown.is_empty(), "Persistent damage must survive saves without persisting transient forecast evidence")
	var combined = aircraft(world, Contact.TAIL_LIMIT_DEG + 0.25, 90.0, 3.0)
	var body_damage := float(Contact.assess(combined.pitch_deg, -3.0, 90.0).damage)
	check(combined._try_land() and is_equal_approx(combined.airframe_condition, 100.0 - body_damage - Flight.touchdown_damage(-3.0)), "Hard vertical impact and body strike must add their damage")
	for sample in [{"pitch": -18.0, "sink": 5.0, "word": "носом"}, {"pitch": 12.0, "sink": 3.0, "word": "хвостом"}]:
		var plane = aircraft(world, sample.pitch, 220.0, sample.sink)
		check(plane._try_land() and plane.state == Flight.State.CRASHED and plane.message.contains(sample.word), "Severe body impact must crash and identify the struck part")
	var worn = aircraft(world, Contact.TAIL_LIMIT_DEG + 0.25)
	worn.airframe_condition = 1.0
	check(worn._try_land() and worn.state == Flight.State.CRASHED and worn.airframe_condition == 0.0, "A minor strike may destroy an already exhausted airframe")
	var early = aircraft(world, Contact.TAIL_LIMIT_DEG + 1.0)
	early.altitude_m = early.ground_contact_clearance_m() - 0.01
	check(early.altitude_m > Flight.GROUND_CONTACT_CLEARANCE_M, "Unsafe attitude must make the body touch before wheel-level ground contact")
	early.update_prediction(0.001)
	check(early.state == Flight.State.ROLLING and early.last_touchdown.part == "tail", "Actual physics must detect early body contact")
	for mode in [Predictor.Mode.FULL_SIMULATION, Predictor.Mode.SHORT_TRAJECTORY]:
		for sample in [{"pitch": Contact.NOSE_LIMIT_DEG - 0.5, "part": "nose"}, {"pitch": Contact.TAIL_LIMIT_DEG + 0.5, "part": "tail"}]:
			var plane = aircraft(world, sample.pitch, 90.0, 2.5)
			var before: Dictionary = plane.snapshot()
			var time: float = world.weather_time_seconds
			var prediction := Predictor.predict(plane, 0, mode)
			check(prediction.valid and prediction.touchdown_part == sample.part and not prediction.safe_landing, "Both scheduled modes must expose unsafe nose and tail contact")
			check(plane.snapshot() == before and world.weather_time_seconds == time, "Predicting strikes must not mutate the aircraft or world")
	var clean = aircraft(world, 0.0)
	check(Display.build(clean, 0, true, {}, 350).attitude_warning.is_empty(), "Normal attitudes must not clutter ILS")
	clean.pitch_deg = 12.0
	clean.state = Flight.State.LANDED
	check(Display.build(clean, 0, true, {}, 350).attitude_warning.is_empty(), "Touchdown pitch warning must disappear on the ground")
	var language := Localization.language
	Localization.set_language(Localization.ENGLISH, false)
	check(Localization.text("НОС НИЗКО") == "NOSE LOW" and Localization.text("НОС ВЫСОКО") == "NOSE HIGH", "Attitude warnings must support English")
	check(Localization.text("Удар хвостом • планер −3.1%").begins_with("Tail strike"), "Strike damage must be localized inside touchdown messages")
	Localization.set_language(language, false)
	print("Pitch contact geometry, early strikes, damage, ILS and both prediction modes: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
