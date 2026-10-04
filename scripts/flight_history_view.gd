extends RefCounted
## History UI only; journal and cached route counts belong to FlightHistory.
const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode
const Localization = preload("res://scripts/localization.gd")
const AircraftArt = preload("res://scripts/aircraft_art.gd")
var host: Control
var view_mode: int:
	get:
		return host.side_scenes.view_mode
var history_scroll := 0
var history_selected := 0
var route_history_scroll := 0
var route_history_selected := 0
var route_history_origin := -1
var route_history_destination := -1
var route_history_level := 0
var route_history_destination_level := 0
var route_history_records_cache: Array[Dictionary] = []

func _init(controller: Control) -> void:
	host = controller

func get_history_back_rect() -> Rect2:
	var button_width := minf(270.0, host.size.x * 0.30)
	return Rect2(host.size.x - _history_right_margin() - button_width, 108.0, button_width, 44.0)

func _history_list_rect() -> Rect2:
	var left := _history_left_margin()
	return Rect2(left, 160.0, host.size.x - left - _history_right_margin(), maxf(80.0, host.size.y - 270.0))

func _history_left_margin() -> float:
	# The clock controls end at x=202. Match their 48 px distance from the left
	# edge on the other side of the column: the journal starts at x=250.
	return 250.0

func _history_right_margin() -> float:
	# There is no instrument column on the right, so retain only the normal
	# scene-edge breathing room and give the journal the otherwise empty width.
	return 40.0

func _history_visible_rows() -> int:
	return maxi(1, floori(_history_list_rect().size.y / 64.0))

func _active_history_records() -> Array[Dictionary]:
	if view_mode == ViewMode.ROUTE_HISTORY:
		return route_history_records_cache
	return host.simulation.flight_history.journal_rows()

func _history_record_at(display_index: int) -> Dictionary:
	var records := _active_history_records()
	if view_mode == ViewMode.ROUTE_HISTORY:
		return records[display_index]
	# The model caches chronological rows including crossings. Translate the
	# visible index instead of reversing the full journal on every redraw.
	return records[records.size() - 1 - display_index]

func _history_route_count(origin: int, destination: int, level: int = 0, destination_level: int = -1) -> int:
	return host.simulation.flight_history.route_count(origin, destination, level, destination_level)

func _clamp_history_selection(route_details: bool) -> void:
	var records: Array[Dictionary] = route_history_records_cache if route_details else host.simulation.flight_history.journal_rows()
	var maximum := maxi(0, records.size() - 1)
	if route_details:
		route_history_selected = clampi(route_history_selected, 0, maximum)
		route_history_scroll = clampi(route_history_scroll, 0, maxi(0, records.size() - _history_visible_rows()))
		if route_history_selected < route_history_scroll:
			route_history_scroll = route_history_selected
		elif route_history_selected >= route_history_scroll + _history_visible_rows():
			route_history_scroll = route_history_selected - _history_visible_rows() + 1
	else:
		history_selected = clampi(history_selected, 0, maximum)
		history_scroll = clampi(history_scroll, 0, maxi(0, records.size() - _history_visible_rows()))
		if history_selected < history_scroll:
			history_scroll = history_selected
		elif history_selected >= history_scroll + _history_visible_rows():
			history_scroll = history_selected - _history_visible_rows() + 1

func handle_history_key(keycode: int) -> bool:
	if view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY]:
		return false
	var records := _active_history_records()
	if keycode in [KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		var selected := route_history_selected if view_mode == ViewMode.ROUTE_HISTORY else history_selected
		match keycode:
			KEY_UP: selected -= 1
			KEY_DOWN: selected += 1
			KEY_PAGEUP: selected -= _history_visible_rows()
			KEY_PAGEDOWN: selected += _history_visible_rows()
			KEY_HOME: selected = 0
			KEY_END: selected = records.size() - 1
		selected = clampi(selected, 0, maxi(0, records.size() - 1))
		if view_mode == ViewMode.ROUTE_HISTORY:
			route_history_selected = selected
		else:
			history_selected = selected
		_clamp_history_selection(view_mode == ViewMode.ROUTE_HISTORY)
		host.queue_redraw()
		return true
	return false

func handle_history_mouse(event: InputEventMouseButton) -> bool:
	if view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY] or not event.pressed:
		return false
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var delta := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if view_mode == ViewMode.ROUTE_HISTORY:
			route_history_scroll += delta
		else:
			history_scroll += delta
		_clamp_history_scroll(view_mode == ViewMode.ROUTE_HISTORY)
		# Keep keyboard selection inside the newly scrolled viewport so drawing
		# does not immediately pull the list back to the previous selection.
		var first_visible := route_history_scroll if view_mode == ViewMode.ROUTE_HISTORY else history_scroll
		var last_visible := mini(_active_history_records().size() - 1, first_visible + _history_visible_rows() - 1)
		if view_mode == ViewMode.ROUTE_HISTORY:
			route_history_selected = clampi(route_history_selected, first_visible, maxi(first_visible, last_visible))
		else:
			history_selected = clampi(history_selected, first_visible, maxi(first_visible, last_visible))
		host.queue_redraw()
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if get_history_back_rect().has_point(event.position):
		host.side_scenes._leave_current_scene()
		return true
	var list_rect := _history_list_rect()
	if not list_rect.has_point(event.position):
		return false
	var scroll := route_history_scroll if view_mode == ViewMode.ROUTE_HISTORY else history_scroll
	var row := floori((event.position.y - list_rect.position.y) / 64.0) + scroll
	var records := _active_history_records()
	if row < 0 or row >= records.size():
		return false
	if view_mode == ViewMode.ROUTE_HISTORY:
		route_history_selected = row
	else:
		history_selected = row
	host.queue_redraw()
	return true

func _clamp_history_scroll(route_details: bool) -> void:
	var count := _active_history_records().size()
	var maximum := maxi(0, count - _history_visible_rows())
	if route_details:
		route_history_scroll = clampi(route_history_scroll, 0, maximum)
	else:
		history_scroll = clampi(history_scroll, 0, maximum)

func _open_selected_history_route() -> void:
	var records := _active_history_records()
	if records.is_empty() or history_selected < 0 or history_selected >= records.size():
		return
	var record: Dictionary = _history_record_at(history_selected)
	if record.get("kind", "") == "world_transition":
		return
	var count: int = _history_route_count(int(record.origin), int(record.destination), int(record.get("level", 0)), int(record.get("destination_level", record.get("level", 0))))
	if count < 2:
		return
	route_history_origin = int(record.origin)
	route_history_destination = int(record.destination)
	route_history_level = int(record.get("level", 0))
	route_history_destination_level = int(record.get("destination_level", route_history_level))
	route_history_records_cache = host.simulation.flight_history.route_records(route_history_origin, route_history_destination, route_history_level, route_history_destination_level)
	route_history_selected = 0
	route_history_scroll = 0
	host.side_scenes._set_view_mode(ViewMode.ROUTE_HISTORY)

func _format_history_duration(seconds_value: float) -> String:
	var total := maxi(0, roundi(seconds_value))
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]

func _format_history_timestamp(seconds_value: float) -> String:
	var total := maxi(0, floori(seconds_value))
	var day := total / 86400 + 1
	var within_day := total % 86400
	return "день %d %02d:%02d:%02d" % [day, within_day / 3600, (within_day % 3600) / 60, within_day % 60]

func _format_history_details(record: Dictionary) -> String:
	var duration := float(record.duration_seconds)
	var distance := float(record.distance_km)
	var average := "%.1f" % (distance * 3600.0 / duration) if duration > 0.0 else "—"
	return "%.1f км • %s • СР. %s км/ч • %s → %s" % [distance, _format_history_duration(duration), average, _format_history_timestamp(float(record.start_seconds)), _format_history_timestamp(float(record.end_seconds))]

func _history_world_label(origin_level: int, destination_level: int) -> String:
	return Localization.text("Мир %d" % (origin_level + 1)) if origin_level == destination_level else Localization.text("Мир %d → %d" % [origin_level + 1, destination_level + 1])

func _history_airport_name(record: Dictionary, endpoint: String) -> String:
	var stored := String(record.get(endpoint + "_name", ""))
	return stored if not stored.is_empty() else String(host.world.airports[int(record[endpoint])].name)

func _draw_flight_history_scene() -> void:
	var route_details := view_mode == ViewMode.ROUTE_HISTORY
	host.side_scenes._draw_scene_background("СТАТИСТИКА ПОЛЁТОВ • МИР %d" % (host.world.level_index + 1))
	var records := _active_history_records()
	var title := "ИСТОРИЯ ПОЛЁТОВ • НОВЫЕ СВЕРХУ"
	if route_details and route_history_origin in range(host.world.airports.size()) and route_history_destination in range(host.world.airports.size()):
		title = "%s • %s → %s • ВСЕГО ПОЛЁТОВ: %d • РЕКОРД СВЕРХУ" % [_history_world_label(route_history_level, route_history_destination_level), _history_airport_name(records[0], "origin") if not records.is_empty() else host.world.airports[route_history_origin].name, _history_airport_name(records[0], "destination") if not records.is_empty() else host.world.airports[route_history_destination].name, records.size()]
	var back_rect := get_history_back_rect()
	host.draw_localized_string(ThemeDB.fallback_font, Vector2(_history_left_margin(), 139), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(100.0, back_rect.position.x - _history_left_margin() - 18.0), 17, AircraftArt.INK)
	host.side_scenes._draw_menu_button(get_history_back_rect(), "НАЗАД")
	var list_rect := _history_list_rect()
	host.draw_rect(list_rect, Color("d7d0ad"), true)
	host.draw_rect(list_rect, AircraftArt.INK, false, 1.0)
	if records.is_empty():
		host.draw_localized_string(ThemeDB.fallback_font, list_rect.position + Vector2(0, 42), "Завершённых полётов пока нет", HORIZONTAL_ALIGNMENT_CENTER, list_rect.size.x, 17, AircraftArt.INK)
		host.side_scenes._scene_prompt("Колесо / ↑↓: прокрутка • Enter: открыть рекорды маршрута • кнопка «Назад»: вернуться")
		return
	_clamp_history_selection(route_details)
	var scroll := route_history_scroll if route_details else history_scroll
	var selected := route_history_selected if route_details else history_selected
	var end_index := mini(records.size(), scroll + _history_visible_rows())
	for record_index in range(scroll, end_index):
		var record: Dictionary = _history_record_at(record_index)
		var row_rect := Rect2(list_rect.position + Vector2(5, (record_index - scroll) * 64.0 + 4), Vector2(list_rect.size.x - 10, 56))
		if record_index == selected:
			host.draw_rect(row_rect, Color("c4ba91"), true)
		if record.get("kind", "") == "world_transition":
			host.draw_line(row_rect.position + Vector2(10, 4), Vector2(row_rect.end.x - 10, row_rect.position.y + 4), AircraftArt.INK, 1.0)
			host.draw_localized_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 25), "ПЕРЕХОД: МИР %d → МИР %d" % [int(record.from_level) + 1, int(record.to_level) + 1], HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 15, AircraftArt.INK)
			var transition_time := _format_history_timestamp(float(record.time_seconds)) if bool(record.get("time_known", true)) else "Время перехода не записано"
			host.draw_localized_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 46), transition_time, HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 13, Color("6f5b3e"))
			continue
		var origin_name: String = _history_airport_name(record, "origin")
		var destination_name: String = _history_airport_name(record, "destination")
		var level := int(record.get("level", 0))
		var destination_level := int(record.get("destination_level", level))
		var count: int = _history_route_count(int(record.origin), int(record.destination), level, destination_level)
		var count_text := Localization.text(" • всего полётов: %d • Enter: рекорды" % count) if not route_details and count > 1 else ""
		var rank_text := "%d. " % (record_index + 1) if route_details else ""
		if route_details and record_index == 0:
			rank_text += Localization.text("РЕКОРД • ")
		host.draw_localized_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 21), "%s%s • %s → %s%s" % [rank_text, _history_world_label(level, destination_level), origin_name, destination_name, count_text], HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 15, AircraftArt.INK)
		var details := _format_history_details(record)
		host.draw_localized_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 43), details, HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 13, Color("6f5b3e"))
	if records.size() > _history_visible_rows():
		var bar := Rect2(list_rect.end.x - 7, list_rect.position.y + 4, 3, list_rect.size.y - 8)
		host.draw_rect(bar, Color("aa9c72"), true)
		var thumb_height := maxf(22.0, bar.size.y * _history_visible_rows() / float(records.size()))
		var thumb_y := bar.position.y + (bar.size.y - thumb_height) * scroll / float(maxi(1, records.size() - _history_visible_rows()))
		host.draw_rect(Rect2(bar.position.x - 1, thumb_y, 5, thumb_height), AircraftArt.INK, true)
	host.side_scenes._scene_prompt("Колесо / ↑↓: прокрутка • Enter: открыть рекорды маршрута • кнопка «Назад»: вернуться")
