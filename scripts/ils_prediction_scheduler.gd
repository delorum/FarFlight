extends RefCounted
## Owns forecast lifecycle; physics stays in LandingPredictor. No UI dependency.
const Predictor = preload("res://scripts/landing_predictor.gd")
# Set FULL_SIMULATION to restore the complete approach simulation.
const DEFAULT_PREDICTION_MODE := Predictor.Mode.SHORT_TRAJECTORY
const REFRESH_INTERVAL := 0.5
const FRAME_STEP_LIMIT := 128
const FRAME_BUDGET_USEC := 1000

var remaining_seconds := 0.0
var job: Predictor.PredictionJob
var result: Dictionary = Predictor.no_touchdown()
var _airport_index := -1
var prediction_mode: Predictor.Mode = DEFAULT_PREDICTION_MODE
var _published_airport := -1
var _published_world
var _published_mode: Predictor.Mode = DEFAULT_PREDICTION_MODE

func cancel() -> void:
	job = null
	_airport_index = -1
	remaining_seconds = 0.0

func suspend(is_flying: bool) -> void:
	cancel()
	if not is_flying and bool(result.get("valid", false)):
		result = Predictor.no_touchdown("not_flying")

func refresh_immediately(source, airport_index: int) -> void:
	# Initialization/load only. Regular flight uses the budgeted update path.
	cancel()
	if source == null:
		return
	result = Predictor.predict(source, airport_index, prediction_mode) if airport_index >= 0 else Predictor.no_touchdown("no_runway_frequency")
	_published_airport = airport_index
	_published_world = source.world
	_published_mode = prediction_mode

func update(source, airport_index: int, signal_available: bool, delta: float) -> void:
	if source == null or airport_index < 0 or not signal_available:
		cancel()
		result = Predictor.no_touchdown("no_signal")
		return
	if job != null and (_airport_index != airport_index or job.simulated.world != source.world or job.mode != prediction_mode):
		cancel()
	remaining_seconds -= delta
	if job == null and remaining_seconds <= 0.0:
		job = Predictor.start_prediction(source, airport_index, prediction_mode)
		_airport_index = airport_index
		remaining_seconds = REFRESH_INTERVAL
	if job != null:
		job.advance(FRAME_STEP_LIMIT, FRAME_BUDGET_USEC)
		if job.finished:
			var next: Dictionary = job.result.duplicate()
			# Light smoothing shared by both displays. Never carry an old runway,
			# invalid forecast or a different algorithm into a new estimate.
			if prediction_mode == Predictor.Mode.SHORT_TRAJECTORY and next.get("reason") == "trajectory_estimate" and _published_mode == prediction_mode and _published_airport == airport_index and _published_world == source.world and bool(next.valid) and bool(result.get("valid", false)):
				for key in ["distance_from_threshold_km", "cross_track_km", "prediction_seconds"]:
					next[key] = lerpf(float(result[key]), float(next[key]), 0.8)
				next.predicted_position = Vector2(result.predicted_position).lerp(Vector2(next.predicted_position), 0.8)
			result = next
			_published_airport = airport_index
			_published_world = source.world
			_published_mode = prediction_mode
			job = null
