extends RefCounted
## Cabin interaction registry. One entry supplies geometry, proximity, action
## and prompt to mouse input, Enter and highlighted labels.
const Art = preload("res://scripts/aircraft_art.gd")
const Flight = preload("res://scripts/flight_model.gd")
var host: Control

func _init(controller: Control) -> void:
	host = controller

func scene_hotspots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in [[Art.SEAT_X, "В кресло пилота", "seat"], [Art.DOOR_X, "На перрон", "door"]]:
		if item[2] == "door" and host.flight.state == Flight.State.FLYING:
			continue
		var point: Vector2 = host._aircraft_point(Vector2(item[0], Art.cabin_floor_y(item[0])))
		var scale: float = host._aircraft_scale()
		var label_y: float = point.y + 14.0 * scale if item[2] == "seat" else host._aircraft_point(Vector2(0, Art.FLOOR_Y)).y + 44.0
		result.append({"id": item[2], "x": point.x,
			"rect": Rect2(point - Vector2(43,105), Vector2(86,137)),
			"label": item[1], "label_y": label_y,
			"label_x": point.x + (16.0 * scale if item[2] == "seat" else 0.0), "range": 38.0})
	return result

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id": "bed", "rect": Rect2(-6, -25, 108, 51), "transform": host._bed_transform(),
			"near": host._bed_is_near, "action": _bed, "prompt": "лечь на кровать"},
		{"id": "fuel", "rect": Rect2(-12, -8, 112, 76), "transform": host._fuel_device_transform(),
			"near": host._near_cabin_ramp, "action": _fuel, "prompt": "перейти к заправке"},
		{"id": "table", "rect": Rect2(-5, -55, 80, 72), "transform": host._table_transform(),
			"near": host._near_cabin_table, "action": _table, "prompt": "сесть за стол"},
	]
	for spot in scene_hotspots():
		var hit_rect: Rect2 = spot.rect
		hit_rect.size.y += 32.0
		result.append({"id": spot.id, "rect": hit_rect, "transform": host._cabin_pose(),
			"near": host._scene_hotspot_is_near.bind(spot), "action": _seat if spot.id == "seat" else _door, "prompt": spot.label})
	return result

func entry(id: String) -> Dictionary:
	for item in entries():
		if item.id == id:
			return item
	return {}

func has_point(id: String, position: Vector2) -> bool:
	var item := entry(id)
	return not item.is_empty() and item.rect.has_point(item.transform.affine_inverse() * position)

func active(id: String) -> bool:
	var item := entry(id)
	if item.is_empty():
		return false
	return item.near.call() or item.rect.has_point(item.transform.affine_inverse() * host.get_local_mouse_position())

func click(position: Vector2) -> bool:
	for item in entries():
		if item.rect.has_point(item.transform.affine_inverse() * position):
			item.action.call()
			return true
	return false

func nearby() -> Dictionary:
	# Keep furniture ahead of the wider doorway/ramp ranges.
	for id in ["table", "seat", "fuel", "bed", "door"]:
		var item := entry(id)
		if not item.is_empty() and item.near.call():
			return item
	return {}

func interact() -> void:
	if host.cabin_sleeping:
		host._stop_cabin_sleep()
	elif host.in_fuel_bay:
		host._refuel_from_carried_canister()
	elif host._at_cabin_table():
		host._eat_at_table()
	else:
		var item := nearby()
		if not item.is_empty():
			item.action.call()

func prompt() -> String:
	if host.cabin_sleeping:
		return "Enter: встать с кровати"
	if host.in_fuel_bay:
		return "Enter: заправить самолёт"
	if host._at_cabin_table():
		return "Enter: съесть еду" if host.economy.carried_item.get("type", "") == "food" else "Возьмите еду и принесите её к столу"
	var item := nearby()
	return "Enter: " + String(item.prompt) if not item.is_empty() else ""

func _bed() -> void:
	if not host.cabin_sleeping:
		host._start_cabin_sleep()

func _fuel() -> void:
	host._stop_cabin_sleep()
	host._enter_fuel_bay()

func _table() -> void:
	host.in_fuel_bay = false
	host.dragging_fuel_slider = false
	host._stop_cabin_sleep()
	host.scene_player_x = host._aircraft_point(Vector2(host.CABIN_TABLE_SEAT_X, 0)).x
	host.scene_player_facing = 1.0
	host.scene_is_walking = false
	host.cabin_table_seated = true
	host.scene_notice = ""

func _seat() -> void:
	host._stop_cabin_sleep()
	host.in_fuel_bay = false
	host.cabin_table_seated = false
	host._set_view_mode(host.ViewMode.COCKPIT)

func _door() -> void:
	if host._can_exit_aircraft():
		host._stop_cabin_sleep()
		host.in_fuel_bay = false
		host.cabin_table_seated = false
		host._enter_apron()
	else:
		host.scene_notice = "Выход доступен после остановки на ВПП"
