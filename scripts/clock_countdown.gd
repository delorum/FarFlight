extends RefCounted
## Independent clock alarm, advanced only by simulated time.
enum State { RESET, PAUSED, RUNNING }
const MAX_SECONDS := 59.0 * 60.0
var state: State = State.RESET
var remaining_seconds := 0.0
var expired := false
var blink_seconds := 0.0

func reset() -> void:
	state = State.RESET
	remaining_seconds = 0.0
	expired = false
	blink_seconds = 0.0

func adjust_minutes(direction: int) -> void:
	remaining_seconds = clampf(remaining_seconds + direction * 60.0, 0.0, MAX_SECONDS)
	expired = false
	blink_seconds = 0.0
	if remaining_seconds <= 0.0:
		reset()
	elif state == State.RESET:
		state = State.PAUSED

func toggle() -> void:
	if remaining_seconds <= 0.0:
		return
	state = State.PAUSED if state == State.RUNNING else State.RUNNING
	blink_seconds = 0.0

func limit_step(seconds: float) -> float:
	return minf(seconds, remaining_seconds) if state == State.RUNNING else seconds

## True only on the step that reaches zero, not on subsequent paused steps.
func advance(seconds: float) -> bool:
	if state != State.RUNNING:
		return false
	remaining_seconds = maxf(0.0, remaining_seconds - maxf(0.0, seconds))
	if remaining_seconds <= 0.0000001:
		remaining_seconds = 0.0
		state = State.PAUSED
		expired = true
		blink_seconds = 0.0
		return true
	return false

func advance_blink(real_seconds: float) -> bool:
	var was_visible := digits_visible()
	blink_seconds = fposmod(blink_seconds + maxf(0.0, real_seconds), 1.0)
	return was_visible != digits_visible()

func digits_visible() -> bool:
	return state != State.PAUSED or blink_seconds < 0.5

func time_text() -> String:
	var seconds := ceili(remaining_seconds)
	return "%02d:%02d" % [seconds / 60, seconds % 60]

func target_angle(clock_seconds: float) -> float:
	return fposmod(clock_seconds + remaining_seconds, 3600.0) / 3600.0 * TAU - PI * 0.5

func snapshot() -> Dictionary:
	return {"state": int(state), "remaining_seconds": remaining_seconds, "expired": expired}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or not value.get("state") is int or value.state not in [State.RESET, State.PAUSED, State.RUNNING]:
		return false
	if not value.get("remaining_seconds") is float or not is_finite(value.remaining_seconds) or value.remaining_seconds < 0 or value.remaining_seconds > MAX_SECONDS or not value.get("expired") is bool:
		return false
	if value.state == State.RESET:
		return value.remaining_seconds == 0.0 and not value.expired
	if value.state == State.RUNNING:
		return value.remaining_seconds > 0.0 and not value.expired
	return (value.remaining_seconds == 0.0) == value.expired

func restore(value: Dictionary) -> void:
	reset()
	if valid_snapshot(value):
		state = value.state
		remaining_seconds = value.remaining_seconds
		expired = value.expired
