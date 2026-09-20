extends RefCounted
const UILayout = preload("res://scripts/ui_layout.gd")
const ViewMode = preload("res://scripts/scene_modes.gd").ViewMode
## Cabin, apron and airport scenes: player state, item presentation and scene geometry.

const AircraftArt = preload("res://scripts/aircraft_art.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
const EconomyScript = preload("res://scripts/economy.gd")
const CABIN_TABLE_X = UILayout.CABIN_TABLE_X
const CABIN_TABLE_SEAT_X = UILayout.CABIN_TABLE_SEAT_X
const FlightWorldScript = preload("res://scripts/world.gd")
const UIButton = preload("res://scripts/ui_button.gd")
const SERVICE_BUILDING_HEIGHT := 270.0
var host: Control
var view_mode := ViewMode.COCKPIT
var scene_player_x := 180.0
var scene_player_facing := 1.0
var scene_walk_phase := 0.0
var apron_aircraft_on_left := true
var scene_notice := ""
var scene_is_walking := false
var propeller_phase := 0.0
var cabin_terrain_zoom := 0
var cabin_terrain_profile := PackedVector2Array()
var cabin_terrain_timer := 0.0
var cabin_rain_blue := true
var cabin_fog_travel_px := 0.0
var selected_inventory_slot := -1
var in_fuel_bay := false
var fuel_amount_litres := 20.0
var dragging_fuel_slider := false
var cabin_sleeping := false
var cabin_table_seated := false
var history_scroll := 0
var history_selected := 0
var route_history_scroll := 0
var route_history_selected := 0
var route_history_origin := -1
var route_history_destination := -1
var route_history_records_cache: Array[Dictionary] = []
var history_route_counts: Dictionary = {}
var history_route_counts_size := -1

func _init(controller: Control) -> void:
	host = controller

func _set_view_mode(next_mode: int) -> void:
	cabin_table_seated = false
	if next_mode != ViewMode.CABIN:
		host._stop_cabin_sleep()
	host.weather_radar_cache.invalidate()
	cabin_terrain_zoom = 0
	view_mode = next_mode
	if view_mode != ViewMode.CABIN:
		in_fuel_bay = false
	dragging_fuel_slider = false
	if view_mode == ViewMode.FUEL:
		_set_default_fuel_amount()
	if view_mode == ViewMode.FLIGHT_HISTORY:
		history_route_counts_size = -1
		_clamp_history_selection(false)
	elif view_mode == ViewMode.ROUTE_HISTORY:
		_clamp_history_selection(true)
	scene_is_walking = false
	host.dragging_map = false
	host.map_drag_candidate = false
	host.point_drag_candidate = false
	host.dragging_measure_point = false
	host.map_render_layer.visible = view_mode == ViewMode.COCKPIT
	host.dragging_yoke = false
	host.dragging_throttle = false
	host.throttle_up_held = false
	host.throttle_down_held = false
	host.steering_left_held = false
	host.steering_right_held = false
	scene_notice = ""
	host._update_crash_overlay()
	host._queue_map_redraw()
	host.queue_redraw()

func _aircraft_mirrored() -> bool:
	# The side-view camera always looks at the same side of the aircraft.
	# The source drawing faces left, so mirror it to keep the nose right.
	return true

func _aircraft_scale() -> float:
	return minf(host.size.x * 0.84 / 1000.0, (host.size.y * 0.76 - 140.0) / AircraftArt.GROUND_Y)

func _aircraft_origin() -> Vector2:
	var width = 1000.0 * _aircraft_scale()
	var x = (host.size.x - width) * 0.5
	return Vector2(x, host.size.y * 0.76 - AircraftArt.GROUND_Y * _aircraft_scale())

func _aircraft_point(local_point: Vector2) -> Vector2:
	var point = local_point
	if _aircraft_mirrored():
		point.x = 1000.0 - point.x
	return _aircraft_origin() + point * _aircraft_scale()

func _scene_walk_bounds() -> Vector2:
	if view_mode == ViewMode.CABIN:
		var a = _aircraft_point(Vector2(AircraftArt.WALK_MIN, 0)).x
		var b = _aircraft_point(Vector2(AircraftArt.WALK_MAX, 0)).x
		return Vector2(minf(a,b),maxf(a,b))
	return Vector2(34,host.size.x-34)

func _cabin_player_position() -> Vector2:
	var local_x = (scene_player_x - _aircraft_origin().x) / _aircraft_scale()
	if _aircraft_mirrored():
		local_x = 1000.0 - local_x
	var position = _aircraft_point(Vector2(local_x, AircraftArt.cabin_floor_y(local_x)))
	if in_fuel_bay:
		position = _aircraft_point(Vector2(local_x, AircraftArt.FLOOR_Y))
	return position

func _airport_exit_x() -> float:
	return host.size.x - 48.0 if apron_aircraft_on_left else 48.0

func _can_exit_aircraft() -> bool:
	return host._aircraft_is_on_ground() and host.flight.speed_kmh <= 0.05

func _scene_hotspots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if view_mode == ViewMode.CABIN:
		return host.cabin_interactions.scene_hotspots()
	elif view_mode == ViewMode.APRON:
		var point = _aircraft_point(Vector2(AircraftArt.DOOR_X,AircraftArt.FLOOR_Y))
		result.append({"x":point.x,"rect":Rect2(point-Vector2(46,110),Vector2(92,210)),"label":"В самолёт","range":55.0})
		var exit_x = _airport_exit_x()
		result.append({"x":exit_x,"rect":Rect2(exit_x-43,host.size.y*0.76-88,86,120),"label":"В аэропорт","range":50.0})
	elif view_mode == ViewMode.AIRPORT:
		var buildings = _airport_buildings()
		for index in buildings.size():
			var x: float = host.size.x * (index + 1.0) / (buildings.size() + 1.0)
			result.append({"x":x,"rect":Rect2(x-65,host.size.y*0.76-170,130,200),"label":buildings[index].label,"kind":buildings[index].kind,"range":110.0})
		result.append({"x":45.0,"rect":Rect2(16,host.size.y*0.76-80,58,110),"label":"На ВПП","range":28.0})
	return result

func _scene_hotspot_is_near(spot: Dictionary) -> bool:
	return absf(scene_player_x - float(spot.x)) < float(spot.get("range", 38.0))

func _nearby_scene_hotspot() -> Dictionary:
	for spot in _scene_hotspots():
		if _scene_hotspot_is_near(spot):
			return spot
	return {}

func _draw_scene_hotspots() -> void:
	if host.flight.state == FlightModelScript.State.CRASHED:
		return
	var pose = _cabin_pose()
	host.draw_set_transform_matrix(pose)
	var mouse_position = pose.affine_inverse() * host.get_local_mouse_position()
	for spot in _scene_hotspots():
		var rect: Rect2 = spot.rect
		var active = host.cabin_interactions.active(spot.id) if spot.has("id") else (rect.has_point(mouse_position) or _scene_hotspot_is_near(spot))
		var color = Color("#785022") if active else AircraftArt.INK
		var label: String = spot.label
		var width = ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+20
		var x = clampf(float(spot.get("label_x", spot.x))-width*0.5,12,host.size.x-width-12)
		var y: float = spot.get("label_y", rect.end.y + 12)
		host.draw_string(ThemeDB.fallback_font,Vector2(x+10,y),label,HORIZONTAL_ALIGNMENT_CENTER,width-20,12,color)
		if active:
			host.draw_line(Vector2(x+10,y+5),Vector2(x+width-10,y+5),color,1,true)
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _click_side_scene(position: Vector2) -> void:
	if cabin_terrain_zoom > 0:
		return
	if host.flight.state == FlightModelScript.State.CRASHED:
		return
	cabin_table_seated = false
	var scene_position = _cabin_pose().affine_inverse() * position
	var pointer_direction = scene_position.x - scene_player_x
	if absf(pointer_direction) > 0.5:
		scene_player_facing = signf(pointer_direction)
	if view_mode == ViewMode.CABIN and host.cabin_interactions.click(position):
		host.queue_redraw()
		return
	if in_fuel_bay:
		in_fuel_bay = false
		dragging_fuel_slider = false
	if cabin_sleeping:
		host._stop_cabin_sleep()
	var interact = false
	var bounds = _scene_walk_bounds()
	var destination = clampf(scene_position.x,bounds.x,bounds.y)
	for spot in _scene_hotspots():
		var hit_rect: Rect2 = spot.rect
		hit_rect.size.y += 32.0
		if hit_rect.has_point(scene_position):
			destination = clampf(float(spot.x),bounds.x,bounds.y)
			interact = true
			break
	scene_player_x = destination
	scene_is_walking = false
	scene_notice = ""
	if interact:
		_interact_in_scene()
	host.queue_redraw()

func _enter_cabin(from_cockpit: bool = false) -> void:
	if from_cockpit:
		host.flight.leave_cockpit_on_ground()
	_set_view_mode(ViewMode.CABIN)
	scene_player_x = _aircraft_point(Vector2(AircraftArt.SEAT_X, 0)).x
	scene_player_facing = -1.0 if not _aircraft_mirrored() else 1.0
func _enter_apron() -> void:
	apron_aircraft_on_left = _aircraft_mirrored()
	_set_view_mode(ViewMode.APRON)
	scene_player_x = _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
	scene_player_facing = 1.0 if apron_aircraft_on_left else -1.0
func _update_scene_walking(delta: float) -> void:
	if cabin_terrain_zoom > 0:
		scene_is_walking = false
		return
	if in_fuel_bay:
		scene_is_walking = false
		scene_player_facing = 1.0
		return
	if host.flight.state == FlightModelScript.State.CRASHED:
		return
	if view_mode not in [ViewMode.CABIN, ViewMode.APRON, ViewMode.AIRPORT]:
		return
	var movement = Input.get_axis("ui_left", "ui_right")
	if cabin_sleeping and absf(movement) > 0.05:
		host._stop_cabin_sleep()
	scene_is_walking = false
	var bounds = _scene_walk_bounds()
	if absf(movement) > 0.05:
		cabin_table_seated = false
		host._reset_time_scale_for_action()
		scene_player_facing = signf(movement)
		scene_player_x = clampf(scene_player_x + movement * 190.0 * delta, bounds.x, bounds.y)
		scene_is_walking = true
	if scene_is_walking:
		scene_walk_phase += delta * 11.0
		scene_notice = ""
	host.queue_redraw()
func _interact_in_scene() -> void:
	if host.flight.state == FlightModelScript.State.CRASHED and view_mode not in [ViewMode.FLIGHT_HISTORY, ViewMode.ROUTE_HISTORY]:
		return
	match view_mode:
		ViewMode.CABIN:
			host.cabin_interactions.interact()
		ViewMode.APRON:
			var door = _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
			if absf(scene_player_x - door) < 55.0:
				_enter_cabin()
				scene_player_x = _aircraft_point(Vector2(AircraftArt.DOOR_X, 0)).x
			elif absf(scene_player_x - _airport_exit_x()) < 50.0:
				_set_view_mode(ViewMode.AIRPORT)
				scene_player_x = 45.0 if apron_aircraft_on_left else host.size.x - 45.0
		ViewMode.AIRPORT:
			if scene_player_x < 70.0 or scene_player_x > host.size.x - 70.0:
				_enter_apron()
				scene_player_x = _airport_exit_x()
			else:
				for spot in _scene_hotspots():
					if spot.has("kind") and absf(scene_player_x - float(spot.x)) < 110.0:
						_set_view_mode(int(spot.kind))
						break
		ViewMode.OPERATIONS:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.FLIGHT_HISTORY:
			_open_selected_history_route()
		ViewMode.ROUTE_HISTORY:
			pass
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL, ViewMode.REPAIR:
			_set_view_mode(ViewMode.AIRPORT)
func _leave_current_scene() -> void:
	match view_mode:
		ViewMode.ROUTE_HISTORY:
			_set_view_mode(ViewMode.FLIGHT_HISTORY)
		ViewMode.FLIGHT_HISTORY:
			if host.pause_history_active:
				host.return_to_pause_menu_from_history()
			else:
				_set_view_mode(ViewMode.OPERATIONS)
		ViewMode.OPERATIONS:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.MAIL, ViewMode.SHOP, ViewMode.HOTEL, ViewMode.FUEL, ViewMode.REPAIR:
			_set_view_mode(ViewMode.AIRPORT)
		ViewMode.AIRPORT:
			_enter_apron()
		ViewMode.APRON:
			_enter_cabin()
		ViewMode.CABIN:
			_set_view_mode(ViewMode.COCKPIT)

func _scene_prompt(text: String) -> void:
	if host.flight.state == FlightModelScript.State.CRASHED:
		text = "Enter: траектория полёта • Esc: меню"
	host.draw_line(Vector2(36, host.size.y - 69), Vector2(host.size.x - 36, host.size.y - 69), AircraftArt.LIGHT, 1.0, true)
	host.draw_string(ThemeDB.fallback_font, Vector2(36, host.size.y - 39), text, HORIZONTAL_ALIGNMENT_CENTER, host.size.x - 72, 15, AircraftArt.INK)
	var controls_text = "Esc: меню" if host.flight.state == FlightModelScript.State.CRASHED else "ЛКМ: переместиться • клик по двери: перейти • стрелки: идти • Enter: действие • Esc: меню"
	if view_mode == ViewMode.CABIN and host.flight.state != FlightModelScript.State.CRASHED:
		controls_text = "ЛКМ / стрелки: идти • Enter: действие • X: за штурвал • Esc: меню"
	host.draw_string(ThemeDB.fallback_font, Vector2(36, host.size.y - 17), controls_text, HORIZONTAL_ALIGNMENT_CENTER, host.size.x - 72, 11, Color("#ad9271"))
func _draw_pilot(position: Vector2, rotation: float = 0.0) -> void:
	var stride = sin(scene_walk_phase) * 6.0 if scene_is_walking else 0.0
	var seated = _at_cabin_table() and not scene_is_walking
	var pilot_scale = _aircraft_scale() * AircraftArt.PILOT_SCALE if view_mode in [ViewMode.CABIN, ViewMode.APRON] else AircraftArt.PILOT_SCALE
	host.draw_set_transform_matrix(_cabin_pose() * Transform2D(rotation, Vector2(1.0 if seated else scene_player_facing, 1) * pilot_scale, 0.0, position))
	var ink = Color("#795e3c")
	var cloth = Color("#cbb892")
	if seated:
		host.draw_polyline(PackedVector2Array([Vector2(-3,-21), Vector2(12,-21), Vector2(12,-3), Vector2(18,-3)]), ink, 4, true)
	else:
		host.draw_line(Vector2(-3,-21), Vector2(-7+stride,-3), ink, 5, true)
		host.draw_line(Vector2(3,-21), Vector2(6-stride,-3), ink, 5, true)
		host.draw_line(Vector2(-7+stride,-2), Vector2(-1+stride,-2), ink, 4, true)
		host.draw_line(Vector2(6-stride,-2), Vector2(12-stride,-2), ink, 4, true)
	AircraftArt.poly(host, PackedVector2Array([Vector2(-7,-49),Vector2(5,-50),Vector2(9,-25),Vector2(-8,-23)]), cloth, ink, 1.5)
	host.draw_circle(Vector2(1,-60), 8, Color("#ead3ac"))
	host.draw_arc(Vector2(1,-60), 8, 0, TAU, 24, ink, 1.5, true)
	host.draw_line(Vector2(-7,-67), Vector2(12,-67), ink, 3, true)
	host.draw_rect(Rect2(-6,-73,13,6), cloth)
	host.draw_line(Vector2(-6,-73), Vector2(7,-73), ink, 2)
	host.draw_line(Vector2(0,-46), Vector2(20,-40) if seated else Vector2(7-stride*0.7,-30), ink, 3, true)
	host.draw_line(Vector2(-6,-27), Vector2(7,-28), ink, 2)
	host.draw_circle(Vector2(7,-61), 1, ink)
	host.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _item_label(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"parcel":
			return "ПОЧТА\n%s" % host.world.airports[int(item.destination)].name
		"food": return "ЕДА"
		"canister": return "%.1f Л" % float(item.get("fuel_l", 0.0))
	return ""

func _draw_item_icon(rect: Rect2, item: Dictionary, faint: bool = false, show_label: bool = true) -> void:
	var ink = Color(AircraftArt.INK, 0.30 if faint else 1.0)
	var fill = Color(AircraftArt.PAPER, 0.22 if faint else 0.95)
	AircraftArt.box(host, rect, fill, ink, 2)
	var type = String(item.get("type", ""))
	if type == "parcel":
		host.draw_line(rect.position, rect.end, ink, 1.0)
		host.draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), ink, 1.0)
	elif type == "food":
		host.draw_arc(rect.get_center(), rect.size.x * 0.22, 0, TAU, 18, ink, 1.5, true)
	elif type == "canister":
		var liquid = _canister_liquid_rect(rect, float(item.get("fuel_l", 0.0)))
		_draw_fuel_hatching(liquid, ink)
		host.draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.58, -3), Vector2(rect.size.x * 0.25, 5)), fill, true)
		host.draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.58, -3), Vector2(rect.size.x * 0.25, 5)), ink, false, 1.0)
	if show_label and not faint and not type.is_empty():
		host.draw_string(ThemeDB.fallback_font, rect.end + Vector2(4, -4), _item_label(item), HORIZONTAL_ALIGNMENT_LEFT, 95, 8, ink)

func _canister_liquid_rect(rect: Rect2, fuel_l: float) -> Rect2:
	return _liquid_level_rect(rect.grow(-3.0), fuel_l, float(EconomyScript.CANISTER_CAPACITY_L))

func _liquid_level_rect(interior: Rect2, fuel_l: float, capacity_l: float) -> Rect2:
	var ratio = clampf(fuel_l / capacity_l, 0.0, 1.0) if capacity_l > 0.0 else 0.0
	var height = maxf(0.0, interior.size.y) * ratio
	return Rect2(Vector2(interior.position.x, interior.end.y - height), Vector2(maxf(0.0, interior.size.x), height))

func _draw_fuel_hatching(liquid: Rect2, ink: Color) -> void:
	if not liquid.has_area():
		return
	# The same clipped diagonal strokes and surface for cans and tank glass.
	var offset = -liquid.size.y
	while offset < liquid.size.x:
		var start = maxf(0.0, -offset)
		var finish = minf(liquid.size.y, liquid.size.x - offset)
		if finish > start:
			var a = liquid.position + Vector2(offset + start, liquid.size.y - start)
			var b = liquid.position + Vector2(offset + finish, liquid.size.y - finish)
			host.draw_line(a, b, ink, 0.8, true)
		offset += 5.0
	host.draw_line(liquid.position, Vector2(liquid.end.x, liquid.position.y), ink, 1.0, true)

func _inventory_rect(slot: int) -> Rect2:
	var column = slot % 3
	var row = slot / 3
	var top_left = _aircraft_point(Vector2(520.0 + column * 31.0, 247.0 + row * 34.0))
	return Rect2(top_left, Vector2(27, 29) * _aircraft_scale())

func _draw_cabin_economy_objects() -> void:
	host.draw_set_transform_matrix(_cabin_pose())
	# Six tiedown bays beside the cargo door.
	for slot in EconomyScript.INVENTORY_CAPACITY:
		var rect = _inventory_rect(slot)
		_draw_item_icon(rect, host.economy.inventory[slot], host.economy.inventory[slot].is_empty(), false)
	_draw_cabin_bed()
	_draw_cabin_table()
	AircraftArt.draw_lower_wing(host, _aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), _cabin_pitch())
	_draw_cabin_fuel_device()
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _table_transform() -> Transform2D:
	return _cabin_pose() * Transform2D(0.0, Vector2.ONE * _aircraft_scale(), 0.0, _aircraft_point(Vector2(CABIN_TABLE_X, AircraftArt.FLOOR_Y)))

func _table_has_point(position: Vector2) -> bool:
	return host.cabin_interactions.has_point("table", position)

func _at_cabin_table() -> bool:
	return cabin_table_seated and _near_cabin_table()

func _near_cabin_table() -> bool:
	return view_mode == ViewMode.CABIN and not in_fuel_bay and not cabin_sleeping and absf(scene_player_x - _aircraft_point(Vector2(CABIN_TABLE_SEAT_X, 0)).x) < 12.0 * _aircraft_scale()

func _eat_at_table() -> void:
	if not _at_cabin_table():
		scene_notice = "Поесть можно только за столом в салоне"
		return
	if host.economy.carried_item.get("type", "") != "food":
		scene_notice = "Возьмите еду и принесите её к столу"
		return
	scene_notice = "Сытость %d/6" % host.economy.hunger if host.economy.eat_carried() else "Вы уже сыты"

func _draw_cabin_table() -> void:
	host.draw_set_transform_matrix(_table_transform())
	var ink = AircraftArt.INK
	# A plain wooden chair and narrow table, matching the bed's frame.
	AircraftArt.box(host, Rect2(-1, -51, 4, 51), AircraftArt.PAPER, ink, 2)
	AircraftArt.box(host, Rect2(2, -25, 20, 4), Color("ddd2b1"), ink, 2)
	host.draw_line(Vector2(19,-21), Vector2(19,0), ink, 2, true)
	AircraftArt.box(host, Rect2(24,-40,47,5), Color("ddd2b1"), ink, 2)
	for x in [28.0, 67.0]:
		host.draw_line(Vector2(x,-35), Vector2(x,0), ink, 2, true)
	host.draw_line(Vector2(28,-12), Vector2(67,-12), AircraftArt.LIGHT, 1, true)
	var active = host.cabin_interactions.active("table")
	var color = Color("785022") if active else ink
	host.draw_string(ThemeDB.fallback_font, Vector2(21,17), "СТОЛ", HORIZONTAL_ALIGNMENT_CENTER, 42, 8, color)
	if active:
		host.draw_line(Vector2(31,21), Vector2(53,21), color, 1, true)
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _bed_transform() -> Transform2D:
	return _cabin_pose() * Transform2D(0.0, Vector2.ONE * _aircraft_scale(), 0.0, _aircraft_point(Vector2(790, 307)))

func _bed_has_point(position: Vector2) -> bool:
	return host.cabin_interactions.has_point("bed", position)

func _bed_is_near() -> bool:
	return absf(scene_player_x - _aircraft_point(Vector2(735.0, 0)).x) < 38.0

func _start_cabin_sleep() -> void:
	if not host.economy.carried_item.is_empty():
		scene_notice = "Перед сном освободите руки"
		return
	cabin_table_seated = false
	scene_player_x = _aircraft_point(Vector2(735.0, 0)).x
	in_fuel_bay = false
	dragging_fuel_slider = false
	cabin_sleeping = true
	host.cabin_sleep_progress_seconds = 0.0
	scene_is_walking = false
	scene_notice = "Вы легли отдохнуть • каждые 20 минут +1, не выше 2"

func _draw_cabin_bed() -> void:
	host.draw_set_transform_matrix(_bed_transform())
	# Mattress top is y=0; the frame stands on the cabin floor at y=23.
	for x in [4.0, 90.0]:
		host.draw_line(Vector2(x, 8), Vector2(x, 23), AircraftArt.INK, 2.2, true)
	host.draw_line(Vector2(3, 11), Vector2(93, 11), AircraftArt.INK, 2.2, true)
	AircraftArt.box(host, Rect2(0, -10, 5, 25), AircraftArt.PAPER, AircraftArt.INK, 2)
	AircraftArt.box(host, Rect2(91, -20, 5, 35), AircraftArt.PAPER, AircraftArt.INK, 2)
	AircraftArt.box(host, Rect2(5, 0, 86, 9), Color("ddd2b1"), AircraftArt.INK, 3)
	host.draw_line(Vector2(10, 6), Vector2(86, 6), AircraftArt.LIGHT, 1, true)
	AircraftArt.box(host, Rect2(71, -4, 18, 5), Color("e1d6b8"), AircraftArt.LIGHT, 2)
	var active = cabin_sleeping or host.cabin_interactions.active("bed")
	var label_color = Color("#785022") if active else AircraftArt.INK
	host.draw_string(ThemeDB.fallback_font, Vector2(0, 39), "КРОВАТЬ", HORIZONTAL_ALIGNMENT_CENTER, 96, 8, label_color)
	if active:
		host.draw_line(Vector2(25, 42), Vector2(71, 42), label_color, 1.0, true)

func _draw_sleeping_pilot() -> void:
	host.draw_set_transform_matrix(_bed_transform())
	var ink = Color("795e3c")
	var cloth = Color("cbb892")
	# A dedicated supine profile: back on mattress, nose and closed eye upward.
	host.draw_line(Vector2(18, -3), Vector2(45, -4), ink, 5, true)
	host.draw_line(Vector2(16, -3), Vector2(15, -8), ink, 3, true)
	AircraftArt.poly(host, PackedVector2Array([Vector2(43,-7),Vector2(61,-12),Vector2(69,-9),Vector2(70,-2),Vector2(43,-2)]), cloth, ink, 1.3)
	host.draw_line(Vector2(65,-7), Vector2(55,-8), ink, 2, true)
	host.draw_line(Vector2(55,-8), Vector2(53,-12), ink, 1.5, true)
	host.draw_circle(Vector2(79,-11), 7, Color("ead3ac"))
	host.draw_arc(Vector2(79,-11), 7, 0, TAU, 24, ink, 1.2, true)
	host.draw_line(Vector2(81,-16), Vector2(84,-15), ink, 1, true)
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_cabin_fuel_device() -> void:
	host.draw_set_transform_matrix(_fuel_device_transform())
	# Reservoir, pump, shutoff valve and fuel pipe through the engine bulkhead.
	var ink = AircraftArt.INK
	host.draw_polyline(PackedVector2Array([Vector2(40,30),Vector2(48,30),Vector2(48,12),Vector2(94,12)]), ink, 2, true)
	AircraftArt.box(host, Rect2(0, 5, 39, 40), Color("d0c29d"), ink, 6)
	for y in [14.0, 36.0]:
		host.draw_line(Vector2(15,y), Vector2(37,y), AircraftArt.LIGHT, 2, true)
	var glass = Rect2(3, 8, 10, 34)
	host.draw_rect(glass, AircraftArt.PAPER, true)
	_draw_fuel_hatching(_liquid_level_rect(glass, host.flight.fuel_l, host.flight.fuel_capacity_l), ink)
	host.draw_line(Vector2(14, 7), Vector2(14, 43), ink, 1.0, true)
	AircraftArt.box(host, Rect2(7, -1, 13, 6), AircraftArt.PAPER, ink, 2)
	host.draw_line(Vector2(7,-3), Vector2(20,-3), ink, 2, true)
	# Three equal gaps: glass divider → dial → vertical gauge → tank edge.
	var instrument_gap = (39.0 - 14.0 - 10.0 - 5.0) / 3.0
	var dial_center = Vector2(14.0 + instrument_gap + 5.0, 23.0)
	var gauge_x = dial_center.x + 5.0 + instrument_gap
	host.draw_circle(dial_center, 5, AircraftArt.PAPER)
	host.draw_arc(dial_center, 5, 0, TAU, 20, ink, 1, true)
	host.draw_line(dial_center, dial_center + Vector2(3,-3), ink, 1, true)
	AircraftArt.box(host, Rect2(gauge_x,18,5,14), AircraftArt.PAPER, ink, 1)
	host.draw_line(Vector2(gauge_x+2.5,29),Vector2(gauge_x+2.5,23),ink,2,true)
	host.draw_circle(Vector2(48,12), 4, AircraftArt.PAPER)
	host.draw_line(Vector2(44,8),Vector2(52,16),ink,1.5,true)
	host.draw_line(Vector2(44,16),Vector2(52,8),ink,1.5,true)
	host.draw_line(Vector2(5,45),Vector2(5,50),ink,2,true)
	host.draw_line(Vector2(34,45),Vector2(34,50),ink,2,true)
	var active = in_fuel_bay or host.cabin_interactions.active("fuel")
	var label_color = Color("#785022") if active else ink
	host.draw_string(ThemeDB.fallback_font, Vector2(-10,64), "ЗАПРАВКА", HORIZONTAL_ALIGNMENT_CENTER, 65, 8, label_color)
	if active:
		host.draw_line(Vector2(2, 67), Vector2(43, 67), label_color, 1.0, true)

func _fuel_device_transform() -> Transform2D:
	return _cabin_pose() * Transform2D(0.0, Vector2.ONE * _aircraft_scale(), 0.0, _aircraft_point(Vector2(295, 280)))

func _fuel_device_hover_description(position: Vector2) -> String:
	if _fuel_device_has_point(position):
		return "Топливо в баке: %.1f/%.0f л" % [host.flight.fuel_l, host.flight.fuel_capacity_l]
	return ""

func _fuel_device_has_point(position: Vector2) -> bool:
	return host.cabin_interactions.has_point("fuel", position)

func _draw_carried_item(pilot_position: Vector2) -> void:
	if host.economy.carried_item.is_empty():
		return
	host.draw_set_transform_matrix(_cabin_pose())
	# Keep the load in front of the pilot after either left/right turn.
	var item_offset_x = 10.0 if scene_player_facing > 0.0 or _at_cabin_table() else -34.0
	var item_rect = Rect2(pilot_position + Vector2(item_offset_x, -44), Vector2(24, 24))
	if _at_cabin_table():
		item_rect = Rect2(_aircraft_point(Vector2(CABIN_TABLE_X, AircraftArt.FLOOR_Y)) + Vector2(34, -64) * _aircraft_scale(), Vector2(24,24) * _aircraft_scale())
	if _at_cabin_table() and host.economy.carried_item.get("type", "") == "food":
		_draw_table_food()
		host.draw_set_transform_matrix(_cabin_pose())
	else:
		_draw_item_icon(item_rect, host.economy.carried_item, false, false)
	var caption = _carried_item_caption(host.economy.carried_item)
	var text_width = clampf(ThemeDB.fallback_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 16.0, 64.0, 280.0)
	var text_x = clampf(item_rect.get_center().x - text_width * 0.5, 12.0, host.size.x - text_width - 12.0)
	# Keep the caption clear of both the carried object and the pilot's head.
	host.draw_string(ThemeDB.fallback_font, Vector2(text_x, pilot_position.y - 82.0), caption, HORIZONTAL_ALIGNMENT_CENTER, text_width, 9, AircraftArt.INK)
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_table_food() -> void:
	host.draw_set_transform_matrix(_table_transform())
	# Side-on plate resting on the tabletop, with a flattened fried egg.
	for layer in [
		[Vector2(47,-43), Vector2(17,3), AircraftArt.PAPER, AircraftArt.INK],
		[Vector2(47,-44), Vector2(12,2.8), Color("e1d6b8"), AircraftArt.LIGHT],
		[Vector2(49,-45), Vector2(4,2), Color("cbb892"), AircraftArt.INK],
	]:
		var points = PackedVector2Array()
		for step in 32:
			var angle = TAU * float(step) / 32.0
			points.append(layer[0] + Vector2(cos(angle), sin(angle)) * layer[1])
		AircraftArt.poly(host, points, layer[2], layer[3], 1.0)
	host.draw_set_transform_matrix(Transform2D.IDENTITY)

func _carried_item_caption(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"parcel":
			var destination: String = String(host.world.airports[int(item.destination)].name)
			var remaining: float = float(item.get("urgent_deadline", 0.0)) - host.economy.elapsed_seconds
			if remaining > 0.0:
				var time_text: String = "%d с" % ceili(remaining) if remaining < 60.0 else host._format_short_time(remaining)
				return "ПОЧТА → %s • срочно %s" % [destination, time_text]
			return "ПОЧТА → %s" % destination
		"food":
			return "ЕДА"
		"canister":
			return "КАНИСТРА • %.1f Л" % float(item.get("fuel_l", 0.0))
	return ""

func _handle_inventory_click(position: Vector2) -> bool:
	if in_fuel_bay and _set_fuel_amount_from_mouse(position, Vector2(36, host.size.y - 152)):
		scene_notice = ""
		return true
	if not host.economy.carried_item.is_empty():
		var carried_type = String(host.economy.carried_item.get("type", ""))
		if _carried_action_rect(0).has_point(position):
			scene_notice = "Предмет уложен" if host.economy.store_carried() else "Нет свободных слотов"
			return true
		if carried_type == "food" and _carried_action_rect(1).has_point(position):
			_eat_at_table()
			return true
		if carried_type == "canister" and _carried_action_rect(1).has_point(position):
			if in_fuel_bay:
				host._refuel_from_carried_canister()
			else:
				scene_notice = "Подойдите к лестнице и нажмите ↓, чтобы заправить самолёт"
			return true
		if _carried_action_rect(2).has_point(position):
			host.economy.discard_carried()
			scene_notice = "Предмет выброшен"
			return true
	position = _cabin_pose().affine_inverse() * position
	for slot in EconomyScript.INVENTORY_CAPACITY:
		if _inventory_rect(slot).grow(4.0).has_point(position):
			selected_inventory_slot = slot
			if host.economy.inventory[slot].is_empty():
				scene_notice = "Предмет уложен в грузовой отсек" if host.economy.store_carried(slot) else "Слот пуст"
			elif host.economy.carried_item.is_empty():
				host.economy.take_slot(slot)
				scene_notice = "Вы взяли: " + _item_label(host.economy.carried_item).replace("\n", " — ")
			else:
				scene_notice = "Сначала освободите руки"
			return true
	return false

func _inventory_hover_description(position: Vector2) -> String:
	var cabin_position = _cabin_pose().affine_inverse() * position
	for slot in EconomyScript.INVENTORY_CAPACITY:
		var item: Dictionary = host.economy.inventory[slot]
		if not item.is_empty() and _inventory_rect(slot).grow(4.0).has_point(cabin_position):
			match String(item.get("type", "")):
				"parcel":
					var remaining: float = float(item.get("urgent_deadline", 0.0)) - host.economy.elapsed_seconds
					var deadline_text: String = "срочный тариф ещё %s" % host._format_short_time(remaining) if remaining >= 0.0 else "срочный срок истёк"
					return "Посылка • аэропорт «%s» • оплата %d, срочно %d • %s" % [host.world.airports[int(item.destination)].name, int(item.get("normal_reward", 0)), int(item.get("urgent_reward", 0)), deadline_text]
				"food":
					return "Еда • восстанавливает 1 деление сытости"
				"canister":
					return "Канистра • %.1f/%d л топлива" % [float(item.get("fuel_l", 0)), EconomyScript.CANISTER_CAPACITY_L]
	return ""

func _carried_action_rect(index: int) -> Rect2:
	return Rect2(host.size.x - 376.0 + index * 120.0, host.size.y - 112.0, 112.0, 30.0)

func _draw_carried_actions() -> void:
	if host.economy.carried_item.is_empty():
		return
	var middle_action = "ЗАПРАВИТЬ" if host.economy.carried_item.get("type", "") == "canister" else "СЪЕСТЬ"
	var entries = [[0, "УЛОЖИТЬ"], [2, "ВЫБРОСИТЬ"]]
	if host.economy.carried_item.get("type", "") == "canister" or (host.economy.carried_item.get("type", "") == "food" and _at_cabin_table()):
		entries.insert(1, [1, middle_action])
	for entry in entries:
		_draw_menu_button(_carried_action_rect(entry[0]), entry[1], 13)
	if in_fuel_bay:
		_draw_fuel_amount_slider(Vector2(36, host.size.y - 152))

func _fuel_slider_rect(origin: Vector2 = Vector2.INF) -> Rect2:
	return Rect2(_economy_button_rect(1).position if origin == Vector2.INF else origin, Vector2(_economy_button_rect(1).size.x, 38))

func _draw_fuel_amount_slider(origin: Vector2 = Vector2.INF) -> void:
	var rect = _fuel_slider_rect(origin)
	AircraftArt.box(host, rect, AircraftArt.PAPER, AircraftArt.INK, 3)
	var track = Rect2(rect.position + Vector2(18, 23), Vector2(rect.size.x - 36, 3))
	host.draw_rect(track, AircraftArt.LIGHT, true)
	var maximum = _fuel_slider_maximum()
	var knob_x = lerpf(track.position.x, track.end.x, clampf(fuel_amount_litres / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0)
	host.draw_circle(Vector2(knob_x, track.get_center().y), 6, AircraftArt.INK)
	var label = "Объём: %.1f л • клик или перетаскивание" % fuel_amount_litres
	if view_mode == ViewMode.CABIN and in_fuel_bay and host.economy.carried_item.get("type", "") == "canister":
		var canister_after = maxf(0.0, float(host.economy.carried_item.get("fuel_l", 0.0)) - fuel_amount_litres)
		var tank_after = minf(host.flight.fuel_capacity_l, host.flight.fuel_l + fuel_amount_litres)
		label = "Заправить %.1f л • останется %.1f л • бак %.1f/%.0f л" % [fuel_amount_litres, canister_after, tank_after, host.flight.fuel_capacity_l]
	host.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10, 16), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20, 11, AircraftArt.INK)

func _set_fuel_amount_from_mouse(position: Vector2, origin: Vector2 = Vector2.INF, allow_outside: bool = false) -> bool:
	var rect = _fuel_slider_rect(origin)
	if not allow_outside and not rect.has_point(position):
		return false
	var maximum = _fuel_slider_maximum()
	if maximum <= 0.0:
		fuel_amount_litres = 0.0
		return true
	var raw_amount = inverse_lerp(rect.position.x + 18, rect.end.x - 18, position.x) * maximum
	fuel_amount_litres = clampf(snappedf(raw_amount, 0.1), minf(0.1, maximum), maximum)
	return true

func _fuel_slider_maximum() -> float:
	if view_mode == ViewMode.CABIN and in_fuel_bay:
		if host.economy.carried_item.get("type", "") != "canister":
			return 0.0
		return snappedf(maxf(0.0, minf(float(host.economy.carried_item.get("fuel_l", 0.0)), host.flight.fuel_capacity_l - host.flight.fuel_l)), 0.1)
	if host.economy.carried_item.get("type", "") == "canister":
		return snappedf(maxf(0.0, EconomyScript.CANISTER_CAPACITY_L - float(host.economy.carried_item.get("fuel_l", 0.0))), 0.1)
	return float(EconomyScript.CANISTER_CAPACITY_L)

func _set_default_fuel_amount() -> void:
	fuel_amount_litres = _fuel_slider_maximum()

func _active_fuel_slider_origin() -> Vector2:
	return Vector2(36, host.size.y - 152) if view_mode == ViewMode.CABIN and in_fuel_bay else Vector2.INF

func _fuel_slider_is_active() -> bool:
	return (view_mode == ViewMode.CABIN and in_fuel_bay) or view_mode == ViewMode.FUEL
func _draw_scene_background(title: String) -> float:
	host.draw_rect(Rect2(Vector2.ZERO, host.size), AircraftArt.PAPER, true)
	var ground_y = host.size.y * 0.76
	host.draw_string(ThemeDB.fallback_font, Vector2(38, 44), "FAR FLIGHT   /   ПОЧТОВАЯ АВИАЦИЯ", HORIZONTAL_ALIGNMENT_LEFT, host.size.x - 76, 11, Color("#b29a78"))
	host.draw_string(ThemeDB.fallback_font, Vector2(36, 79), title, HORIZONTAL_ALIGNMENT_LEFT, host.size.x - 72, 24, AircraftArt.INK)
	host.draw_line(Vector2(36, 98), Vector2(host.size.x-36,98), AircraftArt.LIGHT, 1, true)
	# Faint horizon, grass and broken ground lines echo the architectural reference.
	if view_mode != ViewMode.CABIN:
		for i in 9:
			var x = host.size.x * (i + 0.25) / 9.0
			host.draw_line(Vector2(x,ground_y+12),Vector2(x+host.size.x/13.0,ground_y+12),AircraftArt.LIGHT,1,true)
			for blade in 3:
				var start = Vector2(x+blade*6,ground_y+10)
				host.draw_line(start,start+Vector2(blade*2-2,-7-blade*2),AircraftArt.LIGHT,1,true)
	return ground_y
func _draw_cabin_scene() -> void:
	_draw_scene_background("Борт 02 / салон")
	if cabin_terrain_zoom > 0:
		_draw_cabin_terrain()
		return
	_draw_cabin_weather(false)
	_draw_cabin_airport_close_view()
	_draw_cabin_weather(true)
	AircraftArt.draw_aircraft(host, _aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), true, host.flight.engine_running, propeller_phase, _cabin_pitch())
	_draw_cabin_economy_objects()
	if cabin_sleeping:
		_draw_sleeping_pilot()
	else:
		_draw_pilot(_cabin_player_position())
	_draw_carried_item(_cabin_player_position())
	_draw_scene_hotspots()
	_draw_carried_actions()
	var prompt = "Грузовой отсек • самолёт продолжает полёт" if host.flight.state == FlightModelScript.State.FLYING else "Грузовой отсек • самолёт на стоянке"
	if _can_view_cabin_terrain():
		prompt += " • колесо вниз: отдалить"
	var interaction_prompt = host.cabin_interactions.prompt()
	if not interaction_prompt.is_empty():
		prompt = interaction_prompt
	var inventory_description = _inventory_hover_description(host.get_local_mouse_position())
	var fuel_description = _fuel_device_hover_description(host.get_local_mouse_position())
	if host.flight.stall_warning_active():
		prompt = "СВАЛИВАНИЕ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ" if host.flight.stalled else "БОЛЬШОЙ УГОЛ АТАКИ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ"
		_scene_prompt(prompt)
	else:
		var hover_description = inventory_description
		if hover_description.is_empty() and not fuel_description.is_empty():
			hover_description = fuel_description
			if in_fuel_bay or host._near_cabin_ramp():
				hover_description += " • " + prompt
		_scene_prompt(hover_description if not hover_description.is_empty() else (scene_notice if not scene_notice.is_empty() else prompt))
func _can_view_cabin_terrain() -> bool:
	return view_mode == ViewMode.CABIN and host.flight.state != FlightModelScript.State.CRASHED

func _cabin_pitch() -> float:
	return host.flight.pitch_deg if host.flight.state == FlightModelScript.State.FLYING else 0.0

func _cabin_pose() -> Transform2D:
	if view_mode != ViewMode.CABIN:
		return Transform2D.IDENTITY
	return AircraftArt.pitch_transform(_aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), _cabin_pitch())

func _cabin_ground_visible() -> bool:
	return host.flight.altitude_m - host.world.height_at(host.flight.position_km) < 100.0

func _cabin_terrain_span_m() -> float:
	return 500.0 * pow(1.5, maxi(0, cabin_terrain_zoom - 1))

func _cabin_ground_direction() -> Vector2:
	if host.flight.state != FlightModelScript.State.FLYING:
		# After a crosswind landing the nose can retain a small crab angle. A
		# longitudinal side view through the very narrow runway at that angle
		# produces a short, detached-looking strip. On the ground the camera is
		# aligned with the current runway axis, while the nose still chooses which
		# of its two directions faces forward.
		var airport: Dictionary = host.world.airports[host.flight.airport_index]
		var runway_direction: Vector2 = host.world.heading_vector(float(airport.heading))
		if runway_direction.dot(host.world.heading_vector(host.flight.heading_deg)) < 0.0:
			runway_direction = -runway_direction
		return runway_direction
	var velocity: Vector2 = host.world.heading_vector(host.flight.heading_deg) * host.flight.speed_kmh + host.flight.current_wind_kmh
	return velocity.normalized() if velocity.length_squared() > 0.01 else host.world.heading_vector(host.flight.heading_deg)

func _update_cabin_terrain_profile() -> void:
	cabin_terrain_timer = 0.1
	cabin_terrain_profile.clear()
	# Section along actual ground motion, including drift, not just nose heading.
	var direction = _cabin_ground_direction()
	var screen_direction = 1.0 if _aircraft_mirrored() else -1.0
	var span = _cabin_terrain_span_m()
	var count = ceili(span / 2.0)
	for i in range(count + 1):
		var offset = lerpf(-span * 0.5, span * 0.5, float(i) / count)
		var point: Vector2 = host.flight.position_km + direction * offset * screen_direction / 1000.0
		cabin_terrain_profile.append(Vector2(offset, host.world.height_at(point)))

func _draw_cabin_terrain() -> void:
	var rect = Rect2(36, 115, host.size.x - 72, host.size.y - 200)
	# Equal horizontal/vertical scale preserves terrain slopes. The schematic
	# airframe is represented as a 12 m aircraft instead of a screen-sized cabin.
	var pixels_per_m = minf(rect.size.x / _cabin_terrain_span_m(), rect.size.y / 190.0)
	var anchor = Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.28)
	var previous = Vector2.ZERO
	_draw_cabin_weather(false)
	var ground_visible = _cabin_ground_visible()
	var airport_view = _cabin_visible_airport()
	if ground_visible and not airport_view.is_empty():
		_draw_distant_airport(airport_view, rect, anchor, pixels_per_m)
	for i in cabin_terrain_profile.size():
		var sample = cabin_terrain_profile[i]
		var point = anchor + Vector2(sample.x, host.flight.altitude_m - sample.y) * pixels_per_m
		if i > 0 and ground_visible:
			var segment = host._clip_line_to_rect(previous, point, rect)
			if segment.size() == 2:
				host.draw_line(segment[0], segment[1], AircraftArt.INK, 1.6, true)
		previous = point
	if ground_visible and not airport_view.is_empty():
		_draw_side_runway(airport_view, rect, anchor, pixels_per_m)
	var aircraft_scale = 12.0 * pixels_per_m / 1000.0
	AircraftArt.draw_small_aircraft(host, anchor - Vector2(500, AircraftArt.GROUND_Y) * aircraft_scale, aircraft_scale, _aircraft_mirrored(), _cabin_pitch())
	_draw_cabin_weather(true)
	var prompt = "Колесо: масштаб • Enter / Esc: в салон • X: за штурвал"
	if host.flight.stall_warning_active():
		prompt = "СВАЛИВАНИЕ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ" if host.flight.stalled else "БОЛЬШОЙ УГОЛ АТАКИ — ВЕРНИТЕСЬ ЗА ШТУРВАЛ"
	host.draw_string(ThemeDB.fallback_font, Vector2(36, host.size.y - 39), prompt, HORIZONTAL_ALIGNMENT_CENTER, host.size.x - 72, 15, AircraftArt.INK)
	host.draw_string(ThemeDB.fallback_font, Vector2(36, host.size.y - 17), "Вид вниз вдоль пути • полёт продолжается • Esc: меню", HORIZONTAL_ALIGNMENT_CENTER, host.size.x - 72, 11, AircraftArt.INK)

func _draw_cabin_airport_close_view() -> void:
	if not _cabin_ground_visible():
		return
	var airport_view = _cabin_visible_airport()
	if airport_view.is_empty():
		return
	var rect = Rect2(36, 115, host.size.x - 72, host.size.y - 200)
	# The landscape keeps the 500 m overview scale behind the full-size cutaway.
	# Its ground reference is the aircraft's wheels, so the runway sits beneath
	# them while parked and rises into view naturally during the last descent.
	var pixels_per_m = minf(rect.size.x / _cabin_terrain_span_m(), rect.size.y / 190.0)
	var wheel_ground_y = _aircraft_origin().y + AircraftArt.GROUND_Y * _aircraft_scale()
	var anchor = Vector2(rect.get_center().x, wheel_ground_y)
	_draw_side_runway(airport_view, rect, anchor, pixels_per_m)

func _cabin_visible_airport() -> Dictionary:
	var screen_world_direction = _cabin_ground_direction() * (1.0 if _aircraft_mirrored() else -1.0)
	var half_span_km = _cabin_terrain_span_m() / 2000.0
	var nearest: Dictionary = {}
	var nearest_distance = INF
	for airport_index in host.world.airports.size():
		var airport: Dictionary = host.world.airports[airport_index]
		var local_position: Vector2 = host.world.runway_coordinates(host.flight.position_km, airport)
		var runway_forward: Vector2 = host.world.heading_vector(float(airport.heading))
		var runway_right = Vector2(runway_forward.y, -runway_forward.x)
		var local_direction = Vector2(screen_world_direction.dot(runway_forward), screen_world_direction.dot(runway_right))
		var interval = _line_runway_interval(local_position, local_direction)
		var clipped_start = maxf(interval.x, -half_span_km)
		var clipped_end = minf(interval.y, half_span_km)
		if clipped_start > clipped_end:
			continue
		var centre_parameter: float = (Vector2(airport.position) - host.flight.position_km).dot(screen_world_direction)
		var distance: float = absf(centre_parameter)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = {
				"airport_index": airport_index,
				"start_m": clipped_start * 1000.0,
				"end_m": clipped_end * 1000.0,
				"runway_start_m": interval.x * 1000.0,
				"runway_end_m": interval.y * 1000.0,
				"centre_m": centre_parameter * 1000.0,
			}
	return nearest

func _line_runway_interval(origin: Vector2, direction: Vector2) -> Vector2:
	var low = -INF
	var high = INF
	var half_length = FlightWorldScript.RUNWAY_LENGTH_KM * 0.5
	var half_width = FlightWorldScript.RUNWAY_WIDTH_KM * 0.5
	if absf(direction.x) < 0.000001:
		if absf(origin.x) > half_length:
			return Vector2(INF, -INF)
	else:
		var first_x = (-half_length - origin.x) / direction.x
		var second_x = (half_length - origin.x) / direction.x
		low = maxf(low, minf(first_x, second_x))
		high = minf(high, maxf(first_x, second_x))
	if absf(direction.y) < 0.000001:
		if absf(origin.y) > half_width:
			return Vector2(INF, -INF)
	else:
		var first_y = (-half_width - origin.y) / direction.y
		var second_y = (half_width - origin.y) / direction.y
		low = maxf(low, minf(first_y, second_y))
		high = minf(high, maxf(first_y, second_y))
	return Vector2(low, high) if low <= high else Vector2(INF, -INF)

func _side_runway_y(airport_index: int, anchor: Vector2, pixels_per_m: float) -> float:
	var airport: Dictionary = host.world.airports[airport_index]
	var runway_height: float = host.world.height_at(Vector2(airport.position))
	return anchor.y + (host.flight.altitude_m - runway_height) * pixels_per_m

func _draw_distant_airport(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	var runway_y = _side_runway_y(int(view.airport_index), anchor, pixels_per_m)
	if runway_y < rect.position.y or runway_y > rect.end.y + 20.0:
		return
	# Buildings share the airport's world coordinate instead of being clamped to
	# a screen edge; they must travel backwards and leave the frame on takeoff.
	var cluster_m = float(view.centre_m)
	var distant_ink = AircraftArt.INK.lerp(AircraftArt.PAPER, 0.48)
	var distant_fill = AircraftArt.LIGHT.lerp(AircraftArt.PAPER, 0.42)
	for building in [
		{"offset_m": -52.0, "width_m": 18.0, "height_m": 8.0},
		{"offset_m": -24.0, "width_m": 13.0, "height_m": 11.0},
		{"offset_m": 9.0, "width_m": 24.0, "height_m": 9.0},
		{"offset_m": 44.0, "width_m": 15.0, "height_m": 7.0},
	]:
		var centre_x = anchor.x + (cluster_m + float(building.offset_m)) * pixels_per_m
		var width_px = clampf(float(building.width_m) * pixels_per_m, 9.0, 46.0)
		var height_px = clampf(float(building.height_m) * pixels_per_m, 7.0, 30.0)
		if centre_x + width_px < rect.position.x or centre_x - width_px > rect.end.x:
			continue
		var body = Rect2(centre_x - width_px * 0.5, runway_y - height_px, width_px, height_px)
		var visible_body = body.intersection(rect)
		if visible_body.has_area():
			host.draw_rect(visible_body, distant_fill, true)
		for edge in [
			[body.position, Vector2(body.end.x, body.position.y)],
			[Vector2(body.end.x, body.position.y), body.end],
			[body.end, Vector2(body.position.x, body.end.y)],
			[Vector2(body.position.x, body.end.y), body.position],
		]:
			_draw_side_clipped_line(edge[0], edge[1], distant_ink, 1.1, rect)
		var roof = PackedVector2Array([
			Vector2(body.position.x - 2.0, body.position.y),
			Vector2(centre_x, body.position.y - height_px * 0.42),
			Vector2(body.end.x + 2.0, body.position.y),
		])
		_draw_side_clipped_line(roof[0], roof[1], distant_ink, 1.1, rect)
		_draw_side_clipped_line(roof[1], roof[2], distant_ink, 1.1, rect)
		if width_px >= 14.0:
			var door = Rect2(centre_x - 2.0, runway_y - height_px * 0.55, 4.0, height_px * 0.55)
			for edge in [
				[door.position, Vector2(door.end.x, door.position.y)],
				[Vector2(door.end.x, door.position.y), door.end],
				[door.end, Vector2(door.position.x, door.end.y)],
				[Vector2(door.position.x, door.end.y), door.position],
			]:
				_draw_side_clipped_line(edge[0], edge[1], distant_ink, 0.8, rect)
	# A modest locator/radio mast rises just above the distant airport buildings.
	var tower_x = anchor.x + (cluster_m + 28.0) * pixels_per_m
	var tower_height = clampf(17.0 * pixels_per_m, 24.0, 48.0)
	var tower_half_width = clampf(tower_height * 0.18, 5.0, 8.0)
	if tower_x + tower_half_width >= rect.position.x and tower_x - tower_half_width <= rect.end.x:
		var tower_top = runway_y - tower_height
		_draw_side_clipped_line(Vector2(tower_x - tower_half_width, runway_y), Vector2(tower_x, tower_top), distant_ink, 1.2, rect)
		_draw_side_clipped_line(Vector2(tower_x + tower_half_width, runway_y), Vector2(tower_x, tower_top), distant_ink, 1.2, rect)
		for brace_index in 3:
			var upper_y = runway_y - tower_height * (brace_index + 1.0) / 4.0
			var lower_y = runway_y - tower_height * brace_index / 4.0
			var upper_half = tower_half_width * (upper_y - tower_top) / tower_height
			var lower_half = tower_half_width * (lower_y - tower_top) / tower_height
			_draw_side_clipped_line(Vector2(tower_x - lower_half, lower_y), Vector2(tower_x + upper_half, upper_y), distant_ink, 0.9, rect)
			_draw_side_clipped_line(Vector2(tower_x + lower_half, lower_y), Vector2(tower_x - upper_half, upper_y), distant_ink, 0.9, rect)
		_draw_side_clipped_line(Vector2(tower_x, tower_top), Vector2(tower_x, tower_top - 7.0), distant_ink, 1.2, rect)
		if rect.has_point(Vector2(tower_x, tower_top - 8.5)):
			host.draw_circle(Vector2(tower_x, tower_top - 8.5), 1.8, distant_ink)

func _draw_side_clipped_line(a: Vector2, b: Vector2, color: Color, width: float, rect: Rect2) -> void:
	var clipped = host._clip_line_to_rect(a, b, rect)
	if clipped.size() == 2:
		host.draw_line(clipped[0], clipped[1], color, width, true)

func _draw_side_runway(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	var start_x = clampf(anchor.x + float(view.start_m) * pixels_per_m, rect.position.x, rect.end.x)
	var end_x = clampf(anchor.x + float(view.end_m) * pixels_per_m, rect.position.x, rect.end.x)
	var runway_y = _side_runway_y(int(view.airport_index), anchor, pixels_per_m)
	if runway_y < rect.position.y - 8.0 or runway_y > rect.end.y:
		return
	var dash_origin_x = anchor.x + float(view.runway_start_m) * pixels_per_m
	_draw_runway_strip_screen(start_x, end_x, runway_y, dash_origin_x)

func _draw_runway_strip_screen(start_x: float, end_x: float, runway_y: float, dash_origin_x: float = NAN) -> void:
	var runway_rect = Rect2(start_x, runway_y - 2.0, maxf(0.0, end_x - start_x), 9.0)
	host.draw_rect(runway_rect, Color("b6a779"), true)
	host.draw_line(Vector2(start_x, runway_y - 2.0), Vector2(end_x, runway_y - 2.0), AircraftArt.INK, 2.0, true)
	host.draw_line(Vector2(start_x, runway_y + 7.0), Vector2(end_x, runway_y + 7.0), AircraftArt.LIGHT, 1.2, true)
	if is_nan(dash_origin_x):
		dash_origin_x = start_x
	var dash_x = dash_origin_x + 15.0
	if dash_x + 24.0 < start_x:
		dash_x += ceilf((start_x - dash_x - 24.0) / 45.0) * 45.0
	while dash_x < end_x - 8.0:
		var visible_dash_start = maxf(dash_x, start_x)
		var visible_dash_end = minf(dash_x + 24.0, end_x)
		if visible_dash_end > visible_dash_start:
			host.draw_line(Vector2(visible_dash_start, runway_y + 2.5), Vector2(visible_dash_end, runway_y + 2.5), Color("ded5b5"), 2.0, true)
		dash_x += 45.0

func _cabin_weather_scale() -> float:
	if cabin_terrain_zoom == 0:
		return _aircraft_scale() * 1000.0 / 12.0
	return minf((host.size.x - 72.0) / _cabin_terrain_span_m(), (host.size.y - 200.0) / 190.0)

func _cabin_cloud_base_y(fraction: float) -> float:
	var scale_y = _cabin_weather_scale()
	var reference_y = _aircraft_origin().y + AircraftArt.GROUND_Y * _aircraft_scale()
	var terrain: float = host.world.height_at(host.flight.position_km)
	if cabin_terrain_zoom > 0:
		reference_y = 115.0 + (host.size.y - 200.0) * 0.28
		if not cabin_terrain_profile.is_empty():
			var offset = (fraction - 0.5) * (host.size.x - 72.0) / scale_y
			var sample_index = clampf((offset / _cabin_terrain_span_m() + 0.5) * (cabin_terrain_profile.size() - 1), 0.0, cabin_terrain_profile.size() - 1)
			var left = floori(sample_index)
			terrain = lerpf(cabin_terrain_profile[left].y, cabin_terrain_profile[mini(left + 1, cabin_terrain_profile.size() - 1)].y, sample_index - left)
	var world_x = (fraction - 0.5) * (host.size.x - 72.0) / scale_y
	return reference_y + (host.flight.altitude_m - terrain - 100.0 + 0.25 * sin(world_x * TAU / 30.0 + host.status_timer * 0.2)) * scale_y

func _draw_cabin_weather(foreground: bool) -> void:
	var rect = Rect2(36, 115, host.size.x - 72, host.size.y - 200)
	var severity: float = host.flight.storm_intensity
	var time = host.status_timer
	if not foreground:
		# The cloud base stays in world space, even after entering the layer.
		var edge = PackedVector2Array()
		for i in range(121):
			var fraction = i / 120.0
			var y = _cabin_cloud_base_y(fraction)
			edge.append(Vector2(lerpf(rect.position.x, rect.end.x, fraction), clampf(y, rect.position.y, rect.end.y)))
		var fill = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y)])
		for i in range(edge.size() - 1, -1, -1):
			fill.append(edge[i])
		var cloud_depth = 0.0
		for point in edge:
			cloud_depth = maxf(cloud_depth, point.y - rect.position.y)
		if cloud_depth > 0.1:
			host.draw_colored_polygon(fill, Color("c9c3a7").lerp(Color("b5af98"), severity * 0.45))
		host.draw_polyline(edge, Color("b9ac8e"), 1.3, true)
		return
	var fog_bottom = PackedFloat32Array()
	for i in range(61):
		fog_bottom.append(_cabin_cloud_base_y(i / 60.0))
	if fog_bottom[30] > rect.position.y or fog_bottom[0] > rect.position.y or fog_bottom[60] > rect.position.y:
		# Light translucent fog ribbons leave the schematic cabin legible.
		for row in range(7):
			var ribbon = PackedVector2Array()
			for i in range(61):
				var fraction = i / 60.0
				# Wave pattern travels from nose to tail, slowly enough to retain
				# the quiet schematic style. Adjacent bands have slight parallax.
				var phase = (fraction * rect.size.x + cabin_fog_travel_px * (0.85 + row * 0.05)) * 12.0 / rect.size.x
				var y = rect.position.y + rect.size.y * (row + 0.5) / 7.0 + sin(phase + row * 2.0) * 12.0
				ribbon.append(Vector2(lerpf(rect.position.x, rect.end.x, fraction), y))
			for i in range(1, ribbon.size()):
				var cloud_bottom = minf(fog_bottom[i - 1], fog_bottom[i]) - 6.0
				var clip_rect = rect
				clip_rect.size.y = clampf(cloud_bottom - rect.position.y, 0.0, rect.size.y)
				if clip_rect.size.y <= 0.0:
					continue
				var segment = host._clip_line_to_rect(ribbon[i - 1], ribbon[i], clip_rect)
				if segment.size() == 2:
					host.draw_line(segment[0], segment[1], Color(0.91, 0.88, 0.76, 0.28), 12.0, true)
	if severity > 0.0:
		var zone = 0 if severity < 0.35 else (1 if severity < 0.70 else 2)
		var count: int = [45, 110, 220][zone]
		var rain = Color("537c94") if cabin_rain_blue else Color("9b825f")
		rain.a = [0.40, 0.52, 0.65][zone]
		for i in count:
			var x = fposmod(i * 137.507 - time * (35.0 + zone * 18.0), rect.size.x)
			var y = fposmod(i * 97.31 + time * (180.0 + zone * 90.0), rect.size.y)
			var start = rect.position + Vector2(x, y)
			var end = start + Vector2(-6.0 - zone * 3.0, 14.0 + zone * 8.0)
			var clipped = host._clip_line_to_rect(start, end, rect)
			if clipped.size() == 2:
				host.draw_line(clipped[0], clipped[1], rain, 1.0 + zone * 0.25, true)

func _rounded_box(fill: Color, border: Color, border_width: float, radius: float) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(roundi(border_width))
	box.set_corner_radius_all(roundi(radius))
	return box

func _draw_side_aircraft(_center: Vector2, _flip_direction: bool) -> void:
	AircraftArt.draw_aircraft(host, _aircraft_origin(), _aircraft_scale(), _aircraft_mirrored(), false, host.flight.engine_running, propeller_phase)
func _draw_apron_scene() -> void:
	var runway_y = _draw_scene_background("ВПП / " + String(host.world.airports[host.flight.airport_index].name))
	_draw_runway_strip_screen(35.0, host.size.x - 35.0, runway_y)
	_draw_side_aircraft(Vector2.ZERO, false)
	# Boarding steps align with the very same cargo door used in the cutaway.
	var door = _aircraft_point(Vector2(AircraftArt.DOOR_X, AircraftArt.FLOOR_Y))
	var foot = Vector2(door.x+22,runway_y)
	host.draw_line(door,foot,AircraftArt.INK,1.5,true)
	host.draw_line(door+Vector2(-20,0),foot+Vector2(-20,0),AircraftArt.INK,1.5,true)
	for step in range(1,5):
		var at = door.lerp(foot,step/5.0)
		host.draw_line(at-Vector2(22,0),at+Vector2(2,0),AircraftArt.INK,1.5,true)
	_draw_pilot(Vector2(scene_player_x,runway_y))
	_draw_carried_item(Vector2(scene_player_x,runway_y))
	_draw_scene_hotspots()
	var prompt = "Борт 02 • малый грузовой биплан"
	var nearby_spot = _nearby_scene_hotspot()
	if not nearby_spot.is_empty():
		prompt = "Enter: " + String(nearby_spot.label)
	_scene_prompt(prompt)
func _draw_building(center_x: float, floor_y: float, building_size: Vector2, label: String, _color: Color) -> void:
	var r = Rect2(center_x-building_size.x/2,floor_y-building_size.y,building_size.x,building_size.y)
	AircraftArt.box(host,r,AircraftArt.PAPER,AircraftArt.INK,0)
	AircraftArt.poly(host,PackedVector2Array([Vector2(r.position.x-14,r.position.y),Vector2(center_x,r.position.y-55),Vector2(r.end.x+14,r.position.y)]))
	host.draw_line(Vector2(r.position.x-8,r.position.y-9),Vector2(center_x,r.position.y-65),AircraftArt.INK,1.5,true)
	host.draw_line(Vector2(center_x,r.position.y-65),Vector2(r.end.x+8,r.position.y-9),AircraftArt.INK,1.5,true)
	for i in 3:
		var y = r.position.y+55+i*28
		host.draw_line(Vector2(r.position.x+7,y),Vector2(r.end.x-7,y),AircraftArt.LIGHT,1,true)
	for side in [-1,1]:
		var win = Rect2(center_x+side*building_size.x*0.32-17,r.position.y+49,34,56)
		AircraftArt.box(host,win,AircraftArt.PAPER,AircraftArt.INK,0)
		host.draw_line(Vector2(win.get_center().x,win.position.y),Vector2(win.get_center().x,win.end.y),AircraftArt.INK,1,true)
		host.draw_line(Vector2(win.position.x,win.position.y+28),Vector2(win.end.x,win.position.y+28),AircraftArt.INK,1,true)
		host.draw_line(Vector2(win.position.x-4,win.end.y+5),Vector2(win.end.x+4,win.end.y+5),AircraftArt.INK,1.5,true)
	AircraftArt.box(host,Rect2(center_x-22,floor_y-76,44,76),AircraftArt.PAPER,AircraftArt.INK,2)
	AircraftArt.box(host,Rect2(center_x-15,floor_y-67,30,29),AircraftArt.PAPER,AircraftArt.LIGHT,0)
	host.draw_circle(Vector2(center_x+14,floor_y-29),2,AircraftArt.INK)
	for i in 3:
		host.draw_line(Vector2(center_x-28-i*6,floor_y+i*5),Vector2(center_x+28+i*6,floor_y+i*5),AircraftArt.INK,1.5,true)
	host.draw_string(ThemeDB.fallback_font,Vector2(r.position.x,r.position.y+29),label,HORIZONTAL_ALIGNMENT_CENTER,r.size.x,13,AircraftArt.INK)
func _draw_airport_scene() -> void:
	var floor_y = _draw_scene_background("АЭРОПОРТ «%s»" % host.world.airports[host.flight.airport_index].name)
	var buildings = _airport_buildings()
	for index in buildings.size():
		var x = host.size.x * (index + 1.0) / (buildings.size() + 1.0)
		var height = 220.0 - float(index % 3) * 22.0
		_draw_building(x, floor_y, Vector2(minf(205.0, host.size.x / (buildings.size() + 1.7)), height), buildings[index].label.to_upper(), AircraftArt.PAPER)
	# Feet rest on the path in front of the lowest doorstep, not above it.
	_draw_pilot(Vector2(scene_player_x, floor_y + 12))
	_draw_carried_item(Vector2(scene_player_x, floor_y + 12))
	_draw_scene_hotspots()
	var prompt = "Стрелки: идти"
	var nearby_spot = _nearby_scene_hotspot()
	if not nearby_spot.is_empty():
		prompt = "Enter: " + String(nearby_spot.label)
	_scene_prompt(scene_notice if not scene_notice.is_empty() else prompt)

func _airport_buildings() -> Array[Dictionary]:
	var buildings: Array[Dictionary] = [
		{"label":"Лётная служба", "kind":ViewMode.OPERATIONS},
		{"label":"Почта", "kind":ViewMode.MAIL},
	]
	if host.flight.airport_index in host.economy.fuel_airports:
		buildings.append({"label":"Заправка", "kind":ViewMode.FUEL})
	if host.flight.airport_index in host.economy.food_airports:
		buildings.append({"label":"Магазин", "kind":ViewMode.SHOP})
	if host.flight.airport_index in host.economy.hotel_airports:
		buildings.append({"label":"Гостиница", "kind":ViewMode.HOTEL})
	if host.flight.airport_index in host.economy.repair_airports:
		buildings.append({"label":"Ремонтный ангар", "kind":ViewMode.REPAIR})
	return buildings

func get_operations_refuel_rect() -> Rect2:
	return Rect2(host.size.x * 0.54, host.size.y * 0.32, minf(390.0, host.size.x * 0.40), 52)

func get_operations_runway_rect(reverse_direction: bool) -> Rect2:
	return Rect2(host.size.x * 0.54, host.size.y * (0.48 if not reverse_direction else 0.59), minf(390.0, host.size.x * 0.40), 52)

func get_operations_weather_rect() -> Rect2:
	return Rect2(host.size.x * 0.54, host.size.y * 0.38, minf(390.0, host.size.x * 0.40), 52)

func get_operations_history_rect() -> Rect2:
	return Rect2(host.size.x * 0.54, host.size.y * 0.70, minf(390.0, host.size.x * 0.40), 52)

func get_building_exit_rect() -> Rect2:
	return Rect2(host.size.x * 0.54, host.size.y * 0.79, minf(390.0, host.size.x * 0.40), 52)

func _draw_menu_button(rect: Rect2, text: String, font_size: int = 14) -> void:
	UIButton.draw(host, rect, text, true, font_size)

func _draw_operations_scene() -> void:
	var floor_y = _draw_scene_background("ЛЁТНАЯ СЛУЖБА")
	_draw_building(host.size.x * 0.25, floor_y, Vector2(host.size.x * 0.35, minf(SERVICE_BUILDING_HEIGHT, floor_y - 200.0)), "ЛЁТНАЯ СЛУЖБА", AircraftArt.PAPER)
	host.draw_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.52, 120), "ОБСЛУЖИВАНИЕ САМОЛЁТА", HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.44, 18, Color("34372f"))
	var status_color = Color("567044") if host.flight.departure_authorized else Color("a3483f")
	host.draw_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.54, host.size.y * 0.22), host._operations_status_text(), HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.40, 15, status_color)
	host.draw_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.54, host.size.y * 0.27), "Топливо: %.1f / %.0f л" % [host.flight.fuel_l, host.flight.fuel_capacity_l], HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.40, 16, Color("34372f"))
	host.draw_string(ThemeDB.fallback_font, get_operations_refuel_rect().position + Vector2(0, 30), "Подготовка или смена ВПП: %d монет" % EconomyScript.PARKING_PRICE, HORIZONTAL_ALIGNMENT_CENTER, get_operations_refuel_rect().size.x, 15, AircraftArt.INK)
	_draw_menu_button(get_operations_weather_rect(), "ОБНОВИТЬ МЕТЕОСВОДКУ • %s" % host.navigation_map.weather_briefing_age_text())
	_draw_menu_button(get_operations_runway_rect(false), host._operations_runway_button_text(false))
	_draw_menu_button(get_operations_runway_rect(true), host._operations_runway_button_text(true))
	_draw_menu_button(get_operations_history_rect(), "СТАТИСТИКА ПОЛЁТОВ • %d" % host.simulation.flight_history.records.size())
	_draw_menu_button(get_building_exit_rect(), "ВЫЙТИ В АЭРОПОРТ [ENTER]")
	_scene_prompt(scene_notice if not scene_notice.is_empty() else "Enter: выйти из здания • Esc: меню")

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
	return host.simulation.flight_history.records

func _history_route_key(origin: int, destination: int) -> String:
	return "%d:%d" % [origin, destination]

func _history_route_count(origin: int, destination: int) -> int:
	var records: Array[Dictionary] = host.simulation.flight_history.records
	if history_route_counts_size != records.size():
		history_route_counts.clear()
		for record in records:
			var key := _history_route_key(int(record.origin), int(record.destination))
			history_route_counts[key] = int(history_route_counts.get(key, 0)) + 1
		history_route_counts_size = records.size()
	return int(history_route_counts.get(_history_route_key(origin, destination), 0))

func _clamp_history_selection(route_details: bool) -> void:
	var records: Array[Dictionary] = route_history_records_cache if route_details else host.simulation.flight_history.records
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
		_leave_current_scene()
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
	var records: Array[Dictionary] = host.simulation.flight_history.records
	if records.is_empty() or history_selected < 0 or history_selected >= records.size():
		return
	var record: Dictionary = records[history_selected]
	var count: int = _history_route_count(int(record.origin), int(record.destination))
	if count < 2:
		return
	route_history_origin = int(record.origin)
	route_history_destination = int(record.destination)
	route_history_records_cache = host.simulation.flight_history.route_records(route_history_origin, route_history_destination)
	route_history_selected = 0
	route_history_scroll = 0
	_set_view_mode(ViewMode.ROUTE_HISTORY)

func _format_history_duration(seconds_value: float) -> String:
	var total := maxi(0, roundi(seconds_value))
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]

func _format_history_timestamp(seconds_value: float) -> String:
	var total := maxi(0, roundi(seconds_value))
	var day := total / 86400 + 1
	var within_day := total % 86400
	return "день %d %02d:%02d:%02d" % [day, within_day / 3600, (within_day % 3600) / 60, within_day % 60]

func _draw_flight_history_scene() -> void:
	var route_details := view_mode == ViewMode.ROUTE_HISTORY
	_draw_scene_background("СТАТИСТИКА ПОЛЁТОВ")
	var records := _active_history_records()
	var title := "ИСТОРИЯ ПОЛЁТОВ • ХРОНОЛОГИЧЕСКИЙ ПОРЯДОК"
	if route_details and route_history_origin in range(host.world.airports.size()) and route_history_destination in range(host.world.airports.size()):
		title = "%s → %s • ВСЕГО ПОЛЁТОВ: %d • РЕКОРД СВЕРХУ" % [host.world.airports[route_history_origin].name, host.world.airports[route_history_destination].name, records.size()]
	var back_rect := get_history_back_rect()
	host.draw_string(ThemeDB.fallback_font, Vector2(_history_left_margin(), 139), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(100.0, back_rect.position.x - _history_left_margin() - 18.0), 17, AircraftArt.INK)
	_draw_menu_button(get_history_back_rect(), "НАЗАД")
	var list_rect := _history_list_rect()
	host.draw_rect(list_rect, Color("d7d0ad"), true)
	host.draw_rect(list_rect, AircraftArt.INK, false, 1.0)
	if records.is_empty():
		host.draw_string(ThemeDB.fallback_font, list_rect.position + Vector2(0, 42), "Завершённых полётов пока нет", HORIZONTAL_ALIGNMENT_CENTER, list_rect.size.x, 17, AircraftArt.INK)
		_scene_prompt("Колесо / ↑↓: прокрутка • Enter: открыть рекорды маршрута • кнопка «Назад»: вернуться")
		return
	_clamp_history_selection(route_details)
	var scroll := route_history_scroll if route_details else history_scroll
	var selected := route_history_selected if route_details else history_selected
	var end_index := mini(records.size(), scroll + _history_visible_rows())
	for record_index in range(scroll, end_index):
		var record: Dictionary = records[record_index]
		var row_rect := Rect2(list_rect.position + Vector2(5, (record_index - scroll) * 64.0 + 4), Vector2(list_rect.size.x - 10, 56))
		if record_index == selected:
			host.draw_rect(row_rect, Color("c4ba91"), true)
		var origin_name: String = host.world.airports[int(record.origin)].name
		var destination_name: String = host.world.airports[int(record.destination)].name
		var count: int = _history_route_count(int(record.origin), int(record.destination))
		var count_text := " • всего полётов: %d • Enter: рекорды" % count if not route_details and count > 1 else ""
		var rank_text := "%d. " % (record_index + 1) if route_details else ""
		if route_details and record_index == 0:
			rank_text += "РЕКОРД • "
		host.draw_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 21), "%s%s → %s%s" % [rank_text, origin_name, destination_name, count_text], HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 15, AircraftArt.INK)
		var details := "%.1f км • %s • %s → %s" % [float(record.distance_km), _format_history_duration(float(record.duration_seconds)), _format_history_timestamp(float(record.start_seconds)), _format_history_timestamp(float(record.end_seconds))]
		host.draw_string(ThemeDB.fallback_font, row_rect.position + Vector2(10, 43), details, HORIZONTAL_ALIGNMENT_LEFT, row_rect.size.x - 20, 13, Color("6f5b3e"))
	if records.size() > _history_visible_rows():
		var bar := Rect2(list_rect.end.x - 7, list_rect.position.y + 4, 3, list_rect.size.y - 8)
		host.draw_rect(bar, Color("aa9c72"), true)
		var thumb_height := maxf(22.0, bar.size.y * _history_visible_rows() / float(records.size()))
		var thumb_y := bar.position.y + (bar.size.y - thumb_height) * scroll / float(maxi(1, records.size() - _history_visible_rows()))
		host.draw_rect(Rect2(bar.position.x - 1, thumb_y, 5, thumb_height), AircraftArt.INK, true)
	_scene_prompt("Колесо / ↑↓: прокрутка • Enter: открыть рекорды маршрута • кнопка «Назад»: вернуться")

func _economy_button_rect(index: int) -> Rect2:
	return Rect2(host.size.x * 0.48, 165.0 + index * 64.0, minf(520.0, host.size.x * 0.46), 48.0)

func _delivery_button_text(parcel: Dictionary) -> String:
	var urgent: bool = host.economy.elapsed_seconds <= float(parcel.get("urgent_deadline", -1.0))
	var reward = int(parcel.get("urgent_reward", 0) if urgent else parcel.get("normal_reward", 0))
	var tariff_status = "срочный тариф" if urgent else "обычный тариф"
	return "СДАТЬ ПОСЫЛКУ • %d монет • %s" % [reward, tariff_status]

func _draw_economy_scene() -> void:
	var titles = {ViewMode.MAIL:"ПОЧТА", ViewMode.SHOP:"МАГАЗИН", ViewMode.HOTEL:"ГОСТИНИЦА", ViewMode.FUEL:"ЗАПРАВКА", ViewMode.REPAIR:"РЕМОНТНЫЙ АНГАР"}
	var title: String = titles.get(view_mode, "СЛУЖБА")
	var floor_y = _draw_scene_background(title)
	_draw_building(host.size.x * 0.23, floor_y, Vector2(host.size.x * 0.32, minf(SERVICE_BUILDING_HEIGHT, floor_y - 190.0)), title, AircraftArt.PAPER)
	host.draw_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.48, 120), "%s • %d монет" % [host.world.airports[host.flight.airport_index].name, host.economy.money], HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.46, 18, AircraftArt.INK)
	match view_mode:
		ViewMode.MAIL:
			var row = 0
			if host.economy.carried_item.get("type", "") == "parcel" and int(host.economy.carried_item.get("destination", -1)) == host.flight.airport_index:
				_draw_menu_button(_economy_button_rect(row), _delivery_button_text(host.economy.carried_item))
				row += 1
			for offer in host.economy.offers_at(host.flight.airport_index):
				var destination: String = host.world.airports[int(offer.destination)].name
				var poverty_bonus := int(offer.get("poverty_bonus_percent", 0))
				var bonus_text := " • надбавка +%d%%" % poverty_bonus if poverty_bonus > 0 else ""
				_draw_menu_button(_economy_button_rect(row), "%s • маршрут %.0f км • %d / срочно %d%s" % [destination, offer.distance_km, offer.normal_reward, offer.urgent_reward, bonus_text])
				row += 1
		ViewMode.SHOP:
			_draw_menu_button(_economy_button_rect(0), "КУПИТЬ ЕДУ • %d монет" % host.economy.food_price(host.flight.airport_index))
		ViewMode.HOTEL:
			_draw_menu_button(_economy_button_rect(0), "ОТДОХНУТЬ 20 МИНУТ • %d монет" % host.economy.hotel_rest_price(host.flight.airport_index))
		ViewMode.FUEL:
			_draw_menu_button(_economy_button_rect(0), "КУПИТЬ ПУСТУЮ КАНИСТРУ • %d" % EconomyScript.CANISTER_PRICE)
			_draw_fuel_amount_slider()
			_draw_menu_button(_economy_button_rect(2), "КУПИТЬ %.1f Л • %d монет" % [fuel_amount_litres, host.economy.fuel_purchase_cost(fuel_amount_litres, host.flight.airport_index)])
			_draw_menu_button(_economy_button_rect(3), "ПРОДАТЬ КАНИСТРУ И ТОПЛИВО")
		ViewMode.REPAIR:
			var missing: float = maxf(0.0, FlightModelScript.MAX_AIRFRAME_CONDITION - float(host.flight.airframe_condition))
			var full_cost: int = host.economy.repair_cost(missing, host.flight.airport_index)
			host.draw_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.48, 148), "Точное состояние: %.1f/100 • %.1f мон./ед." % [host.flight.airframe_condition, host.economy.repair_price_per_point(host.flight.airport_index)], HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.46, 14, AircraftArt.INK)
			_draw_menu_button(_economy_button_rect(0), "РЕМОНТ ДО 100 • %d монет" % full_cost)
	_draw_menu_button(_economy_button_rect(5), "ВЫЙТИ В АЭРОПОРТ [ENTER]")
	_scene_prompt(scene_notice if not scene_notice.is_empty() else "Клик: действие • Enter: выйти • Esc: меню")
