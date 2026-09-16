extends PanelContainer

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
var profile_states: Array[Dictionary] = []
var active_profile := 0
var profiles_initialized := false
# Time is stored in minutes, distance in km, vertical speed in m/s.
var values := {"distance": 50.0, "time": 20.0, "speed": 150.0, "vertical": 0.0, "altitude": 0.0}
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
		body.visible = expanded
		toggle.text = "Свернуть" if expanded else "Развернуть"
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
			reverse.pressed.connect(func(): _set_value("track", float(values.track) + 180.0))
			grid.add_child(reverse)
		else:
			grid.add_child(Control.new())
	_refresh_fields()
	body.hide()
	call_deferred("_initialize_values")

func _initialize_values() -> void:
	values.speed = controller.flight.speed_kmh
	values.track = controller.flight.heading_deg
	values.heading = controller.flight.heading_deg
	values.vertical = controller.flight.vertical_speed_mps
	initial_altitude = controller.flight.altitude_m
	values.altitude = initial_altitude
	if values.speed <= 0.0:
		values.distance = 0.0
		values.time = 0.0
	_recalculate()
	_use_forecast()
	profile_states.resize(4)
	for profile_index in profile_states.size():
		profile_states[profile_index] = _capture_profile_state()
	profiles_initialized = true
	position = controller.map_rect().position + Vector2(340, 12)

func _capture_profile_state() -> Dictionary:
	return {
		"values": values.duplicate(true),
		"last_changed": last_changed,
		"initial_altitude": initial_altitude,
		"heading_based": heading_based,
		"edit_order": edit_order.duplicate(true),
		"edit_sequence": edit_sequence,
		"derive_speed": derive_speed,
		"derive_vertical": derive_vertical,
	}

func _select_profile(profile_index: int) -> void:
	if not profiles_initialized or profile_index == active_profile:
		return
	get_viewport().gui_release_focus()
	profile_states[active_profile] = _capture_profile_state()
	active_profile = profile_index
	var state: Dictionary = profile_states[active_profile]
	values = state.values.duplicate(true)
	last_changed = state.last_changed
	initial_altitude = state.initial_altitude
	heading_based = state.heading_based
	edit_order = state.edit_order.duplicate(true)
	edit_sequence = state.edit_sequence
	derive_speed = state.derive_speed
	derive_vertical = state.derive_vertical
	_recalculate()

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
	if key == "initial_altitude":
		initial_altitude = number
	else:
		values[key] = fposmod(number, 360.0) if key in ANGLES else number
	if key in ["track", "heading"]:
		heading_based = key == "heading"
	_select_constraints(key)
	edit_sequence += 1
	edit_order[key] = edit_sequence
	if key == "initial_altitude":
		_use_forecast(editing_key)
	else:
		_recalculate(editing_key)

func _recent(key: String) -> int:
	return int(edit_order.get(key, 0))

func _select_constraints(key: String) -> void:
	derive_speed = false
	derive_vertical = false
	var height_edit := maxi(_recent("altitude"), _recent("initial_altitude"))
	var duration_edit := maxi(_recent("time"), _recent("distance"))
	if key in ["distance", "time"]:
		var other := "time" if key == "distance" else "distance"
		derive_speed = _recent(other) > _recent("speed")
		# A zero duration cannot cover a nonzero distance: release the older
		# constraint instead of producing an infinite airspeed.
		if float(values.time) <= 0.0:
			derive_speed = false
		last_changed = "time" if derive_speed else key
		derive_vertical = height_edit > _recent("vertical")
	elif key in ["altitude", "initial_altitude"]:
		var difference := float(values.altitude) - initial_altitude
		if duration_edit > _recent("vertical") or is_zero_approx(float(values.vertical)) or difference * float(values.vertical) < 0.0:
			last_changed = "time"
			derive_vertical = true
		else:
			last_changed = "altitude"
	elif key == "vertical":
		last_changed = "altitude" if height_edit > duration_edit else ("distance" if _recent("distance") > _recent("time") else "time")
		_release_unreachable_altitude(key)
	elif key in ["speed", "wind_from", "wind_speed", "track", "heading"]:
		last_changed = "distance" if _recent("distance") >= _recent("time") else "time"
		if height_edit > duration_edit and _recent("vertical") > duration_edit:
			last_changed = "altitude"

func _release_unreachable_altitude(key: String) -> void:
	if key != "vertical" or last_changed != "altitude":
		return
	# Levelling off or reversing the climb/descent preserves the planned
	# duration and derives a new destination altitude instead.
	var vertical := float(values.vertical)
	var height_difference := float(values.altitude) - initial_altitude
	if is_zero_approx(vertical) or height_difference * vertical < 0.0:
		last_changed = "time"

func _use_current(key: String) -> void:
	var number: float = controller.flight.speed_kmh if key == "speed" else controller.flight.vertical_speed_mps
	if key == "heading":
		number = controller.flight.heading_deg
	_set_value(key, number)

func _use_current_altitude() -> void:
	_set_value("initial_altitude", controller.flight.altitude_m)

func _use_forecast(editing_key: String = "") -> void:
	var wind: Vector2 = controller.world.wind_at(initial_altitude)
	values.wind_speed = wind.length()
	values.wind_from = fposmod(rad_to_deg(atan2(-wind.x, wind.y)), 360.0) if wind.length_squared() > 0.000001 else 0.0
	_recalculate(editing_key)

func use_line(a: Vector2, b: Vector2) -> void:
	var delta := b - a
	if delta.length_squared() < 0.000001:
		return
	values.distance = delta.length()
	values.track = fposmod(rad_to_deg(atan2(delta.x, -delta.y)), 360.0)
	heading_based = false
	expanded = true
	body.show()
	toggle.text = "Свернуть"
	_set_value("distance", delta.length())

func _recalculate(editing_key: String = "") -> void:
	var speed_error := ""
	if derive_speed:
		var required_ground_speed := float(values.distance) / float(values.time) * 60.0
		var wind_angle := deg_to_rad(float(values.wind_from))
		var wind_vector := Vector2(-sin(wind_angle), cos(wind_angle)) * float(values.wind_speed)
		var angle := deg_to_rad(float(values.heading if heading_based else values.track))
		var forward := Vector2(sin(angle), -cos(angle))
		if heading_based:
			var along := wind_vector.dot(forward)
			var discriminant := required_ground_speed * required_ground_speed - (wind_vector.length_squared() - along * along)
			var speed := -along + sqrt(maxf(0.0, discriminant))
			if discriminant < -0.000001 or speed < 0.0:
				speed_error = "Такое время и расстояние недостижимы при заданных ветре и курсе"
			else:
				values.speed = speed
		else:
			values.speed = (forward * required_ground_speed - wind_vector).length()
	if derive_vertical and last_changed == "time":
		_derive_vertical_speed()
	var wind := navigation(values, heading_based)
	if wind.valid:
		values.heading = wind.heading
		values.track = wind.track
	var prediction := calculate(values, last_changed, initial_altitude, heading_based)
	if not speed_error.is_empty():
		prediction = {"valid": false, "reason": speed_error}
	if prediction.valid and derive_vertical and last_changed == "distance":
		values.time = prediction.values.time
		_derive_vertical_speed()
		prediction = calculate(values, "time", initial_altitude, heading_based)
	valid = prediction.valid
	if valid:
		values = prediction.values
	for key in fields:
		fields[key].tooltip_text = "" if valid else prediction.reason
		fields[key].add_theme_color_override("font_color", MAJOR_CONTOUR_COLOR if valid else Color("a3483f"))
	_refresh_fields(editing_key)
	if not wind.valid:
		var derived := "track" if heading_based else "heading"
		if derived != editing_key:
			fields[derived].text = "—"

func _derive_vertical_speed() -> void:
	var difference := float(values.altitude) - initial_altitude
	if float(values.time) > 0.0:
		values.vertical = difference / (float(values.time) * 60.0)
	elif not is_zero_approx(difference):
		if maxi(_recent("time"), _recent("distance")) > maxi(_recent("altitude"), _recent("initial_altitude")):
			# A newly entered zero duration/distance wins over the old height.
			values.altitude = initial_altitude
			return
		# No duration has been established yet. Start with a modest climb or
		# descent and solve its duration, keeping the newly entered height.
		values.vertical = signf(difference) * maxf(1.0, absf(float(values.vertical)))
		values.time = difference / float(values.vertical) / 60.0

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
	output.distance = ground_speed * minutes / 60.0
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
