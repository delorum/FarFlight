extends PanelContainer
const FlightPlanSolver = preload("res://scripts/flight_plan_solver.gd")

const MAP_PAPER := Color("d7d0ad")
const HOVER_PAPER := Color("cec6a2")
const PRESSED_PAPER := Color("c4b98e")
const CONTOUR_COLOR := Color("806f4b")
const MAJOR_CONTOUR_COLOR := Color("5c4b31")
var controller: Control
var expanded := false
var dragging := false
var drag_offset := Vector2.ZERO
var body: VBoxContainer
var toggle: Button
var fields: Dictionary = {}
var current_buttons: Dictionary = {}
var profile_buttons: Array[Button] = []
var line_link_button: Button
var profile_states: Array[Dictionary] = []
var active_profile := 0
var profiles_initialized := false
var bound_line_id := -1
var selecting_line := false
var syncing_line := false
# Time is stored in minutes, distance in km, vertical speed in m/s.
const DEFAULT_DISTANCE_KM := 50.0
const MIN_DISTANCE_KM := 0.001
var values := {"distance": DEFAULT_DISTANCE_KM, "time": 20.0, "speed": 150.0, "vertical": 0.0, "altitude": 0.0}
var last_changed := "distance"
var initial_altitude := 0.0
var valid := true
var heading_based := false
var edit_order: Dictionary = {}
var edit_sequence := 0
var derive_speed := false
var derive_vertical := false
const NONNEGATIVE := ["distance", "time", "speed", "wind_speed"]
const ANGLES := ["track", "heading", "wind_from"]
const VALUE_KEYS := ["distance", "time", "speed", "vertical", "altitude", "track", "heading", "wind_from", "wind_speed"]
const ROWS := [
	["distance", "Расстояние", "км", 1.0],
	["time", "Время", "мин", 1.0],
	["speed", "Возд. скорость", "км/ч", 1.0],
	["vertical", "Верт. скорость", "м/с", 0.1],
	["altitude", "Высота 2", "м", 100.0],
	["track", "Направление пути", "°", 1.0],
	["heading", "Курс носа", "°", 1.0],
	["wind_from", "Ветер откуда", "°", 1.0],
	["wind_speed", "Скорость ветра", "км/ч", 1.0],
]

func _ready() -> void:
	values.merge({"track": 0.0, "heading": 0.0, "wind_from": 0.0, "wind_speed": 0.0})
	mouse_filter = Control.MOUSE_FILTER_STOP
	var palette := Theme.new()
	palette.default_font_size = 13
	for type in ["Label", "Button", "OptionButton", "LineEdit", "SpinBox"]:
		palette.set_color("font_color", type, MAJOR_CONTOUR_COLOR)
		palette.set_color("font_hover_color", type, MAJOR_CONTOUR_COLOR)
		palette.set_color("font_pressed_color", type, MAJOR_CONTOUR_COLOR)
		palette.set_color("font_focus_color", type, MAJOR_CONTOUR_COLOR)
		palette.set_color("caret_color", type, MAJOR_CONTOUR_COLOR)
		palette.set_color("selection_color", type, Color(CONTOUR_COLOR, 0.28))
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = HOVER_PAPER if state == "hover" else (PRESSED_PAPER if state == "pressed" else MAP_PAPER)
			style.border_color = MAJOR_CONTOUR_COLOR if state == "focus" else CONTOUR_COLOR
			style.set_border_width_all(1)
			style.content_margin_left = 6
			style.content_margin_right = 6
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			palette.set_stylebox(state, type, style)
	theme = palette
	var panel := StyleBoxFlat.new()
	panel.bg_color = MAP_PAPER
	panel.border_color = CONTOUR_COLOR
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	add_theme_stylebox_override("panel", panel)
	var column := VBoxContainer.new()
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var handle := Label.new()
	handle.text = "РАСЧЁТ ПОЛЁТА  ⋮⋮"
	handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.gui_input.connect(_drag_input)
	header.add_child(handle)
	var profile_group := ButtonGroup.new()
	for profile_index in 4:
		var profile_button := Button.new()
		profile_button.text = str(profile_index + 1)
		profile_button.tooltip_text = "Набор расчёта %d" % (profile_index + 1)
		profile_button.custom_minimum_size = Vector2(30, 0)
		profile_button.focus_mode = Control.FOCUS_NONE
		profile_button.toggle_mode = true
		profile_button.button_group = profile_group
		profile_button.button_pressed = profile_index == 0
		profile_button.pressed.connect(_select_profile.bind(profile_index))
		profile_buttons.append(profile_button)
		header.add_child(profile_button)
	toggle = Button.new()
	toggle.text = "Развернуть"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(func():
		expanded = not expanded
		if not expanded:
			selecting_line = false
		body.visible = expanded
		toggle.text = "Свернуть" if expanded else "Развернуть"
		_refresh_line_link_button()
		controller.navigation_map._queue_map_redraw()
		size = Vector2.ZERO
	)
	header.add_child(toggle)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	for definition in ROWS:
		var key: String = definition[0]
		if key == "altitude":
			var initial_label := Label.new()
			initial_label.text = "Высота 1"
			grid.add_child(initial_label)
			var initial_field := LineEdit.new()
			initial_field.custom_minimum_size.x = 105
			initial_field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			initial_field.select_all_on_focus = true
			initial_field.text_changed.connect(_text_changed.bind("initial_altitude"))
			initial_field.gui_input.connect(_field_input.bind("initial_altitude", 100.0))
			initial_field.focus_exited.connect(_refresh_fields)
			fields["initial_altitude"] = initial_field
			grid.add_child(initial_field)
			var initial_unit := Label.new()
			initial_unit.text = "м"
			grid.add_child(initial_unit)
			var current_altitude := Button.new()
			current_altitude.text = "Текущая"
			current_altitude.focus_mode = Control.FOCUS_NONE
			current_altitude.tooltip_text = "Обновить исходную высоту по высоте самолёта"
			current_altitude.pressed.connect(_use_current_altitude)
			current_buttons["initial_altitude"] = current_altitude
			grid.add_child(current_altitude)
		var label := Label.new()
		label.text = definition[1]
		grid.add_child(label)
		var field := LineEdit.new()
		field.custom_minimum_size.x = 105
		field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		field.select_all_on_focus = true
		field.text_changed.connect(_text_changed.bind(key))
		field.gui_input.connect(_field_input.bind(key, float(definition[3])))
		field.focus_exited.connect(_refresh_fields)
		fields[key] = field
		grid.add_child(field)
		var unit := Label.new()
		unit.text = definition[2]
		grid.add_child(unit)
		if key in ["speed", "vertical", "heading"]:
			var current := Button.new()
			current.text = "Текущий" if key == "heading" else "Текущая"
			current.focus_mode = Control.FOCUS_NONE
			current.tooltip_text = "Подставить воздушную скорость самолёта" if key == "speed" else "Подставить вертикальную скорость самолёта"
			if key == "heading":
				current.tooltip_text = "Подставить текущий курс носа самолёта"
			current.pressed.connect(_use_current.bind(key))
			current_buttons[key] = current
			grid.add_child(current)
		elif key == "track":
			var reverse := Button.new()
			reverse.text = "Обратно"
			reverse.focus_mode = Control.FOCUS_NONE
			reverse.pressed.connect(_reverse_track)
			grid.add_child(reverse)
		else:
			grid.add_child(Control.new())
	line_link_button = Button.new()
	line_link_button.focus_mode = Control.FOCUS_NONE
	line_link_button.pressed.connect(_toggle_line_link)
	body.add_child(line_link_button)
	_refresh_line_link_button()
	_refresh_fields()
	body.hide()
	call_deferred("_initialize_values")

func _initialize_values() -> void:
	if profiles_initialized:
		return
	values.speed = controller.flight.speed_kmh
	values.track = controller.flight.heading_deg
	values.heading = controller.flight.heading_deg
	values.vertical = controller.flight.vertical_speed_mps
	initial_altitude = controller.flight.altitude_m
	values.altitude = initial_altitude
	if values.speed <= 0.0:
		values.time = 0.0
	_recalculate()
	_use_forecast()
	profile_states.resize(4)
	for profile_index in profile_states.size():
		profile_states[profile_index] = _capture_profile_state()
	profiles_initialized = true
	position = controller.map_rect().position + Vector2(340, 12)

func _capture_profile_state() -> Dictionary:
	var normalized_values: Dictionary = {}
	for key in VALUE_KEYS:
		normalized_values[key] = float(values.get(key, 0.0))
	var normalized_edit_order: Dictionary = {}
	for key in edit_order:
		normalized_edit_order[str(key)] = int(edit_order[key])
	return {
		"values": normalized_values,
		"last_changed": last_changed,
		"initial_altitude": float(initial_altitude),
		"heading_based": heading_based,
		"edit_order": normalized_edit_order,
		"edit_sequence": int(edit_sequence),
		"derive_speed": derive_speed,
		"derive_vertical": derive_vertical,
		"bound_line_id": int(bound_line_id),
	}

func _normalize_profile_state(state: Dictionary) -> Dictionary:
	var normalized_values: Dictionary = {}
	var state_values: Dictionary = state.get("values", {})
	for key in VALUE_KEYS:
		normalized_values[key] = float(state_values.get(key, values.get(key, 0.0)))
	# Older saves and the original on-ground initialization could contain a
	# zero-length plan. A calculator tab always represents a real leg now, so
	# keep a useful distance instead of reviving that destructive state.
	if float(normalized_values.distance) < MIN_DISTANCE_KM:
		normalized_values.distance = DEFAULT_DISTANCE_KM
	var normalized_edit_order: Dictionary = {}
	var state_edit_order: Dictionary = state.get("edit_order", {})
	for key in state_edit_order:
		normalized_edit_order[str(key)] = maxi(0, int(state_edit_order[key]))
	var normalized_last_changed := str(state.get("last_changed", "distance"))
	if normalized_last_changed not in ["distance", "time", "altitude"]:
		normalized_last_changed = "distance"
	return {
		"values": normalized_values,
		"last_changed": normalized_last_changed,
		"initial_altitude": float(state.get("initial_altitude", initial_altitude)),
		"heading_based": bool(state.get("heading_based", false)),
		"edit_order": normalized_edit_order,
		"edit_sequence": maxi(0, int(state.get("edit_sequence", 0))),
		"derive_speed": bool(state.get("derive_speed", false)),
		"derive_vertical": bool(state.get("derive_vertical", false)),
		"bound_line_id": maxi(-1, int(state.get("bound_line_id", -1))),
	}

func snapshot() -> Dictionary:
	_initialize_values()
	profile_states[active_profile] = _capture_profile_state()
	for profile_index in profile_states.size():
		profile_states[profile_index] = _normalize_profile_state(profile_states[profile_index])
	return {
		"profiles": profile_states.duplicate(true),
		"active_profile": active_profile,
		"expanded": expanded,
		"position": position,
	}.duplicate(true)

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("profiles") is Array or data.profiles.size() != 4:
		return false
	if not data.get("active_profile") is int or data.active_profile not in range(4):
		return false
	if not data.get("expanded") is bool or not data.get("position") is Vector2:
		return false
	var saved_position: Vector2 = data.position
	if not is_finite(saved_position.x) or not is_finite(saved_position.y):
		return false
	for profile in data.profiles:
		if not profile is Dictionary or not profile.get("values") is Dictionary:
			return false
		if not profile.values.has_all(VALUE_KEYS):
			return false
		for key in VALUE_KEYS:
			if not profile.values[key] is float or not is_finite(float(profile.values[key])):
				return false
		if not profile.get("initial_altitude") is float or not is_finite(float(profile.initial_altitude)):
			return false
		if not profile.get("last_changed") is String or profile.last_changed not in ["distance", "time", "altitude"]:
			return false
		if not profile.get("heading_based") is bool or not profile.get("derive_speed") is bool or not profile.get("derive_vertical") is bool:
			return false
		if profile.has("bound_line_id") and (not profile.bound_line_id is int or int(profile.bound_line_id) < -1):
			return false
		if not profile.get("edit_sequence") is int or profile.edit_sequence < 0 or not profile.get("edit_order") is Dictionary:
			return false
		for key in profile.edit_order:
			if not key is String or not profile.edit_order[key] is int or int(profile.edit_order[key]) < 0:
				return false
	return true

func restore_snapshot(data: Dictionary) -> bool:
	if not valid_snapshot(data):
		return false
	_initialize_values()
	profile_states.clear()
	for saved_profile in data.profiles:
		profile_states.append(_normalize_profile_state(saved_profile))
	_sanitize_profile_line_links()
	active_profile = data.active_profile
	_apply_profile_state(profile_states[active_profile])
	for profile_index in profile_buttons.size():
		profile_buttons[profile_index].button_pressed = profile_index == active_profile
	expanded = data.expanded
	body.visible = expanded
	toggle.text = "Свернуть" if expanded else "Развернуть"
	position = data.position
	size = Vector2.ZERO
	return true

func _sanitize_profile_line_links() -> void:
	var used_line_ids: Dictionary = {}
	for profile_index in profile_states.size():
		var state: Dictionary = profile_states[profile_index]
		var line_id := int(state.get("bound_line_id", -1))
		if line_id < 0:
			continue
		if used_line_ids.has(line_id) or controller.navigation_map.measurement_line_by_id(line_id).is_empty():
			state.bound_line_id = -1
		else:
			used_line_ids[line_id] = true
		profile_states[profile_index] = state

func _apply_profile_state(state: Dictionary) -> void:
	values = state.values.duplicate(true)
	last_changed = state.last_changed
	initial_altitude = state.initial_altitude
	heading_based = state.heading_based
	edit_order = state.edit_order.duplicate(true)
	edit_sequence = state.edit_sequence
	derive_speed = state.derive_speed
	derive_vertical = state.derive_vertical
	bound_line_id = int(state.get("bound_line_id", -1))
	selecting_line = false
	_recalculate()
	_sync_active_profile_from_line()
	_refresh_line_link_button()

func _select_profile(profile_index: int) -> void:
	if not profiles_initialized or profile_index == active_profile:
		return
	get_viewport().gui_release_focus()
	profile_states[active_profile] = _capture_profile_state()
	active_profile = profile_index
	_apply_profile_state(profile_states[active_profile])
	controller.navigation_map._queue_map_redraw()

func _text_changed(text: String, key: String) -> void:
	var normalized := text.strip_edges().replace(",", ".")
	# Allow incomplete edits ("-", an empty field, etc.) without fighting the
	# caret or replacing what the player is currently typing.
	if not normalized.is_valid_float():
		return
	var number := normalized.to_float()
	if not is_finite(number) or (key in NONNEGATIVE and number < 0.0):
		return
	_change_value(key, number, key)

func _field_input(event: InputEvent, key: String, step_value: float) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		var number := snappedf(_field_value(key) + direction * step_value, 0.001)
		if key in NONNEGATIVE:
			number = maxf(0.0, number)
		_set_value(key, number)
		accept_event()

func _set_value(key: String, number: float) -> void:
	_change_value(key, number)

func _change_value(key: String, number: float, editing_key: String = "") -> void:
	if key == "distance" and number < MIN_DISTANCE_KM:
		# Never let a transient zero collapse a plan or a linked map vector. Keep
		# the previous distance and show the rejected edit as an invalid state.
		_show_error("Расстояние должно быть больше нуля", editing_key)
		return
	var previous_state := _capture_profile_state()
	if key == "initial_altitude":
		initial_altitude = number
	else:
		values[key] = fposmod(number, 360.0) if key in ANGLES else number
	if key in ["track", "heading"]:
		heading_based = key == "heading"
	_select_constraints(key)
	# Legacy save fields are retained for compatibility, but never override the
	# distance-owned solve mode, even when this profile is linked to a line.
	edit_sequence += 1
	edit_order[key] = edit_sequence
	if key == "initial_altitude":
		_use_forecast(editing_key)
	else:
		_recalculate(editing_key)
	var line_error := _sync_active_line_from_calculator()
	if not line_error.is_empty():
		_apply_profile_state(previous_state)
		_show_error(line_error, editing_key)

func _recent(key: String) -> int:
	return int(edit_order.get(key, 0))

func _select_constraints(key: String) -> void:
	derive_speed = false
	derive_vertical = false
	var height_edit := maxi(_recent("altitude"), _recent("initial_altitude"))
	# Distance is the permanent anchor of every calculator tab. Only editing the
	# distance field itself or moving its linked map line may change it.
	last_changed = "distance"
	if key == "time":
		# A manually entered duration is satisfied by deriving the airspeed. If it
		# is impossible, the edit remains red and the route length stays intact.
		derive_speed = true
		derive_vertical = height_edit > _recent("vertical")
	elif key == "distance":
		derive_vertical = height_edit > _recent("vertical")
	elif key in ["altitude", "initial_altitude"]:
		derive_vertical = true
	elif key == "vertical":
		# The new vertical speed determines Height 2 over the fixed route time.
		derive_vertical = false
	elif key in ["speed", "wind_from", "wind_speed", "track", "heading"]:
		derive_vertical = height_edit > _recent("vertical")

func _use_current(key: String) -> void:
	var number: float = controller.flight.speed_kmh if key == "speed" else controller.flight.vertical_speed_mps
	if key == "heading":
		number = controller.flight.heading_deg
	_set_value(key, number)

func _use_current_altitude() -> void:
	_set_value("initial_altitude", controller.flight.altitude_m)

func _reverse_track() -> void:
	if bound_line_id >= 0:
		var line: Dictionary = controller.navigation_map.reverse_calculator_line(bound_line_id)
		if not line.is_empty():
			_sync_values_from_line(line.a, line.b)
			profile_states[active_profile] = _capture_profile_state()
			controller.navigation_map._queue_map_redraw()
			return
	_set_value("track", float(values.track) + 180.0)

func _use_forecast(editing_key: String = "") -> void:
	var wind: Vector2 = controller.world.wind_at(initial_altitude)
	values.wind_speed = wind.length()
	values.wind_from = fposmod(rad_to_deg(atan2(-wind.x, wind.y)), 360.0) if wind.length_squared() > 0.000001 else 0.0
	_recalculate(editing_key)

func _toggle_line_link() -> void:
	if bound_line_id >= 0:
		var old_line_id := bound_line_id
		bound_line_id = -1
		selecting_line = false
		profile_states[active_profile] = _capture_profile_state()
		controller.navigation_map.calculator_line_unlinked(old_line_id)
	else:
		selecting_line = not selecting_line
	_refresh_line_link_button()
	controller.navigation_map._queue_map_redraw()

func _refresh_line_link_button() -> void:
	if line_link_button == null:
		return
	if bound_line_id >= 0:
		line_link_button.text = "ОТВЯЗАТЬ ОТ ЛИНИИ"
	elif selecting_line:
		line_link_button.text = "ОТМЕНИТЬ ВЫБОР ЛИНИИ"
	else:
		line_link_button.text = "ПРИВЯЗАТЬ К ЛИНИИ"

func awaiting_line_binding() -> bool:
	return visible and expanded and selecting_line and bound_line_id < 0

func bind_line(line_id: int, a: Vector2, b: Vector2) -> bool:
	_initialize_values()
	var delta := b - a
	if line_id < 0 or delta.length_squared() < 0.000001:
		return false
	controller.navigation_map.release_calculator_line(line_id, active_profile)
	bound_line_id = line_id
	selecting_line = false
	_sync_values_from_line(a, b)
	profile_states[active_profile] = _capture_profile_state()
	_refresh_line_link_button()
	controller.navigation_map._queue_map_redraw()
	return true

func _sync_values_from_line(a: Vector2, b: Vector2) -> void:
	var delta := b - a
	if delta.length_squared() < 0.000001:
		return
	syncing_line = true
	values.distance = delta.length()
	values.track = fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
	edit_sequence += 1
	edit_order.distance = edit_sequence
	edit_order.track = edit_sequence
	heading_based = false
	last_changed = "distance"
	derive_speed = false
	derive_vertical = false
	_recalculate()
	syncing_line = false

func _sync_active_profile_from_line() -> void:
	if bound_line_id < 0 or controller == null:
		return
	var line: Dictionary = controller.navigation_map.measurement_line_by_id(bound_line_id)
	if line.is_empty():
		bound_line_id = -1
		profile_states[active_profile] = _capture_profile_state()
		_refresh_line_link_button()
		return
	var delta: Vector2 = Vector2(line.b) - Vector2(line.a)
	var line_track := fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
	var track_difference := absf(fposmod(line_track - float(values.track) + 180.0, 360.0) - 180.0)
	if not is_equal_approx(delta.length(), float(values.distance)) or track_difference > 0.0001:
		_sync_values_from_line(line.a, line.b)
	profile_states[active_profile] = _capture_profile_state()

func measurement_line_changed(line: Dictionary) -> void:
	var line_id := int(line.get("id", -1))
	var profile_index := profile_for_line(line_id)
	if profile_index < 0:
		return
	if profile_index == active_profile:
		_sync_values_from_line(line.a, line.b)
		profile_states[active_profile] = _capture_profile_state()
		return
	var state: Dictionary = profile_states[profile_index].duplicate(true)
	var line_delta: Vector2 = Vector2(line.b) - Vector2(line.a)
	if line_delta.length_squared() < 0.000001:
		return
	state.values.distance = line_delta.length()
	state.values.track = fposmod(rad_to_deg(atan2(line_delta.x, -line_delta.y)), 360.0)
	state.heading_based = false
	state.last_changed = "distance"
	state.derive_speed = false
	state.derive_vertical = false
	var prediction := FlightPlanSolver.solve(state.values, float(state.initial_altitude), false, false, false)
	if prediction.valid:
		state.values = prediction.values
	profile_states[profile_index] = state

func measurement_line_removed(line_id: int) -> void:
	for profile_index in profile_states.size():
		var state: Dictionary = _capture_profile_state() if profile_index == active_profile else profile_states[profile_index]
		if int(state.get("bound_line_id", -1)) != line_id:
			continue
		state.bound_line_id = -1
		profile_states[profile_index] = state
		if profile_index == active_profile:
			bound_line_id = -1
			selecting_line = false
	_refresh_line_link_button()

func clear_line_links() -> void:
	bound_line_id = -1
	selecting_line = false
	for profile_index in profile_states.size():
		var state: Dictionary = _capture_profile_state() if profile_index == active_profile else profile_states[profile_index]
		state.bound_line_id = -1
		profile_states[profile_index] = state
	_refresh_line_link_button()

func release_line_from_other_profiles(line_id: int, except_profile: int) -> void:
	for profile_index in profile_states.size():
		if profile_index == except_profile:
			continue
		var state: Dictionary = _capture_profile_state() if profile_index == active_profile else profile_states[profile_index]
		if int(state.get("bound_line_id", -1)) != line_id:
			continue
		state.bound_line_id = -1
		profile_states[profile_index] = state
		if profile_index == active_profile:
			bound_line_id = -1
	_refresh_line_link_button()

func profile_for_line(line_id: int) -> int:
	if line_id < 0:
		return -1
	for profile_index in profile_states.size():
		var state: Dictionary = _capture_profile_state() if profile_index == active_profile else profile_states[profile_index]
		if int(state.get("bound_line_id", -1)) == line_id:
			return profile_index
	return -1

func highlighted_line_id() -> int:
	return bound_line_id if expanded and visible else -1

func line_time_minutes(line_id: int) -> float:
	var profile_index := profile_for_line(line_id)
	if profile_index < 0:
		return -1.0
	var state: Dictionary = _capture_profile_state() if profile_index == active_profile else profile_states[profile_index]
	return float(state.values.time)

func _sync_active_line_from_calculator() -> String:
	if syncing_line or bound_line_id < 0 or not valid or controller == null:
		return ""
	profile_states[active_profile] = _capture_profile_state()
	syncing_line = true
	var line: Dictionary = controller.navigation_map.update_calculator_line(bound_line_id, float(values.distance), float(values.track))
	if line.is_empty():
		bound_line_id = -1
	elif bool(line.get("rejected", false)):
		syncing_line = false
		return str(line.get("reason", "Связанную линию невозможно обновить"))
	else:
		var actual_distance := Vector2(line.a).distance_to(Vector2(line.b))
		if not is_equal_approx(actual_distance, float(values.distance)):
			_sync_values_from_line(line.a, line.b)
	syncing_line = false
	profile_states[active_profile] = _capture_profile_state()
	_refresh_line_link_button()
	return ""

func _recalculate(editing_key: String = "") -> void:
	var prediction := FlightPlanSolver.solve(values, initial_altitude, heading_based, derive_speed, derive_vertical)
	valid = prediction.valid
	if valid:
		values = prediction.values
	_apply_validation_style("" if valid else prediction.reason)
	_refresh_fields(editing_key)
	if not bool(prediction.get("navigation_valid", true)):
		var derived := "track" if heading_based else "heading"
		if derived != editing_key:
			fields[derived].text = "—"

func _show_error(reason: String, editing_key: String = "") -> void:
	valid = false
	_apply_validation_style(reason)
	_refresh_fields(editing_key)

func _apply_validation_style(reason: String) -> void:
	for key in fields:
		fields[key].tooltip_text = reason
		fields[key].add_theme_color_override("font_color", MAJOR_CONTOUR_COLOR if reason.is_empty() else Color("a3483f"))

func _refresh_fields(editing_key: String = "") -> void:
	for key in fields:
		if key != editing_key:
			fields[key].text = _format_value(_field_value(key))

func _field_value(key: String) -> float:
	return initial_altitude if key == "initial_altitude" else float(values[key])

func _format_value(number: float) -> String:
	return ("%.3f" % number).trim_suffix("0").trim_suffix("0").trim_suffix("0").trim_suffix(".")

func editing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return is_visible_in_tree() and focus != null and is_ancestor_of(focus)

func _drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		drag_offset = get_global_mouse_position() - global_position
		accept_event()

func _process(_delta: float) -> void:
	visible = controller.view_mode == controller.ViewMode.COCKPIT and not controller.large_weather_radar
	if not visible:
		dragging = false
		return
	if dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			global_position = get_global_mouse_position() - drag_offset
		else:
			dragging = false
	var bounds: Rect2 = controller.map_rect().grow(-4)
	position = position.clamp(bounds.position, (bounds.end - size).max(bounds.position))

static func calculate(input: Dictionary, changed: String, altitude: float, from_heading: bool = false) -> Dictionary:
	return FlightPlanSolver.calculate(input, changed, altitude, from_heading)

static func navigation(input: Dictionary, from_heading: bool) -> Dictionary:
	return FlightPlanSolver.navigation(input, from_heading)

static func wind_triangle(airspeed: float, track: float, wind_from: float, wind_speed: float) -> Dictionary:
	return FlightPlanSolver.wind_triangle(airspeed, track, wind_from, wind_speed)
