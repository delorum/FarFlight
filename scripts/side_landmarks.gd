extends RefCounted
## Side-view landmark visibility, projection and schematic drawing only.
const AircraftArt = preload("res://scripts/aircraft_art.gd")
const FlightWorldScript = preload("res://scripts/world.gd")
const FlightModelScript = preload("res://scripts/flight_model.gd")
var host: Control
const LANDMARK_FULL_SIZE_KM := 0.1
const LANDMARK_VISIBILITY_KM := 1.0
const SIDE_AIRPORT_BUILDINGS := [
	{"offset_m": Vector2(-52, 55), "width_m": 18.0, "depth_m": 12.0, "height_m": 8.0},
	{"offset_m": Vector2(-24, 48), "width_m": 13.0, "depth_m": 10.0, "height_m": 11.0},
	{"offset_m": Vector2(9, 60), "width_m": 24.0, "depth_m": 16.0, "height_m": 9.0},
	{"offset_m": Vector2(44, 48), "width_m": 15.0, "depth_m": 10.0, "height_m": 7.0},
]
const SIDE_AIRPORT_TOWER_OFFSET_M := Vector2(28, 75)

func _init(controller: Control) -> void:
	host = controller

func _cabin_ground_visible() -> bool:
	return host.side_scenes._cabin_ground_visible()

func _cabin_ground_direction() -> Vector2:
	return host.side_scenes._cabin_ground_direction()

func _cabin_terrain_span_m() -> float:
	return host.side_scenes._cabin_terrain_span_m()

func _aircraft_mirrored() -> bool:
	return host.side_scenes._aircraft_mirrored()

func _landmark_size_scale(lateral_km: float) -> float:
	var distance := absf(lateral_km)
	if distance <= LANDMARK_FULL_SIZE_KM:
		return 1.0
	# Schematic perspective: inverse-distance size, with a soft disappearance
	# over the final 250 m instead of a sudden cutoff of a still-visible tower.
	return LANDMARK_FULL_SIZE_KM / distance * (1.0 - smoothstep(0.75, LANDMARK_VISIBILITY_KM, distance))

func _cabin_visible_beacons() -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	if not _cabin_ground_visible():
		return visible
	var direction: Vector2 = _cabin_ground_direction() * (1.0 if _aircraft_mirrored() else -1.0)
	var half_span_km: float = _cabin_terrain_span_m() / 2000.0
	for beacon in host.world.beacons:
		if int(beacon.get("runway", -1)) >= 0:
			continue
		var offset: Vector2 = Vector2(beacon.position) - host.flight.position_km
		var along: float = offset.dot(direction)
		var lateral_km := absf(offset.cross(direction))
		if lateral_km < LANDMARK_VISIBILITY_KM and absf(along) <= half_span_km + 0.03:
			visible.append({"centre_m": along * 1000.0, "position": Vector2(beacon.position), "size_scale": _landmark_size_scale(lateral_km)})
	return visible

func _draw_side_beacons(rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	for beacon in _cabin_visible_beacons():
		var ink := AircraftArt.INK.lerp(AircraftArt.PAPER, 0.35)
		var fill := AircraftArt.LIGHT.lerp(AircraftArt.PAPER, 0.35)
		# Fade the fixed-width strokes too, so a tiny tower does not leave a dot
		# that abruptly disappears at the visibility boundary.
		var opacity := minf(1.0, float(beacon.size_scale) * 10.0)
		ink.a *= opacity
		fill.a *= opacity
		var x: float = anchor.x + float(beacon.centre_m) * pixels_per_m
		var y: float = anchor.y + (host.flight.altitude_m - host.world.height_at(beacon.position)) * pixels_per_m
		var object_scale: float = pixels_per_m * float(beacon.size_scale)
		var top: float = y - 20.0 * object_scale
		var half_width: float = 3.0 * object_scale
		_draw_side_clipped_line(Vector2(x - half_width, y), Vector2(x, top), ink, 1.2, rect)
		_draw_side_clipped_line(Vector2(x + half_width, y), Vector2(x, top), ink, 1.2, rect)
		for brace in 4:
			var lower: float = y - 20.0 * object_scale * brace / 4.0
			var upper: float = y - 20.0 * object_scale * (brace + 1.0) / 4.0
			var lower_width: float = half_width * (4 - brace) / 4.0
			var upper_width: float = half_width * (3 - brace) / 4.0
			_draw_side_clipped_line(Vector2(x - lower_width, lower), Vector2(x + upper_width, upper), ink, 0.8, rect)
			_draw_side_clipped_line(Vector2(x + lower_width, lower), Vector2(x - upper_width, upper), ink, 0.8, rect)
		_draw_side_clipped_line(Vector2(x, top), Vector2(x, top - 3.0 * object_scale), ink, 1.2, rect)
		var body := Rect2(x + 7.0 * object_scale, y - 5.0 * object_scale, 10.0 * object_scale, 5.0 * object_scale)
		if body.intersects(rect):
			host.draw_rect(body.intersection(rect), fill, true)
		for edge in [[body.position, Vector2(body.end.x, body.position.y)], [Vector2(body.end.x, body.position.y), body.end], [body.end, Vector2(body.position.x, body.end.y)], [Vector2(body.position.x, body.end.y), body.position]]:
			_draw_side_clipped_line(edge[0], edge[1], ink, 1.0, rect)
		var roof_peak := Vector2(body.get_center().x, body.position.y - 2.0 * object_scale)
		_draw_side_clipped_line(body.position, roof_peak, ink, 1.0, rect)
		_draw_side_clipped_line(roof_peak, Vector2(body.end.x, body.position.y), ink, 1.0, rect)
		var door_x: float = body.get_center().x
		_draw_side_clipped_line(Vector2(door_x, y), Vector2(door_x, y - 3.0 * object_scale), ink, 1.0, rect)

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
		var size_scale := 1.0
		if interval.x > interval.y:
			# Nearby flyovers without a direct crossing still show a distant strip.
			var projection := _side_airport_projection(local_position, local_direction)
			if float(projection.lateral_km) >= LANDMARK_VISIBILITY_KM:
				continue
			size_scale = _landmark_size_scale(float(projection.lateral_km))
			var centre := Vector2(projection.interval).x * 0.5 + Vector2(projection.interval).y * 0.5
			interval = Vector2(centre, centre) + (Vector2(projection.interval) - Vector2(centre, centre)) * size_scale
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
				"crossing_view": host.flight.state == FlightModelScript.State.FLYING and absf(local_direction.y) > 0.25,
				"size_scale": size_scale,
				"start_m": clipped_start * 1000.0,
				"end_m": clipped_end * 1000.0,
				"runway_start_m": interval.x * 1000.0,
				"runway_end_m": interval.y * 1000.0,
				"centre_m": centre_parameter * 1000.0,
			}
	return nearest

func _side_airport_projection(origin: Vector2, direction: Vector2) -> Dictionary:
	var along_min := INF
	var along_max := -INF
	var across_min := INF
	var across_max := -INF
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			var offset := Vector2(x_sign * FlightWorldScript.RUNWAY_LENGTH_KM * 0.5, y_sign * FlightWorldScript.RUNWAY_WIDTH_KM * 0.5) - origin
			var along := offset.dot(direction)
			var across := offset.cross(direction)
			along_min = minf(along_min, along)
			along_max = maxf(along_max, along)
			across_min = minf(across_min, across)
			across_max = maxf(across_max, across)
	return {"interval": Vector2(along_min, along_max), "lateral_km": maxf(0.0, maxf(across_min, -across_max))}

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

func _side_airport_landmark_projection(airport: Dictionary, offset_m: Vector2) -> Dictionary:
	var forward: Vector2 = host.world.heading_vector(float(airport.heading))
	var right := Vector2(forward.y, -forward.x)
	var position := Vector2(airport.position) + (forward * offset_m.x + right * offset_m.y) / 1000.0
	var direction := _cabin_ground_direction() * (1.0 if _aircraft_mirrored() else -1.0)
	var relative: Vector2 = position - host.flight.position_km
	var lateral := absf(relative.cross(direction))
	return {"centre_m": relative.dot(direction) * 1000.0, "lateral_km": lateral,
		"size_scale": _landmark_size_scale(lateral),
		"along_weight": absf(forward.dot(direction)), "across_weight": absf(right.dot(direction))}

func _airport_cluster_layout(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> Dictionary:
	var airport: Dictionary = host.world.airports[int(view.airport_index)]
	var projections: Array[Dictionary] = []
	for building_index in SIDE_AIRPORT_BUILDINGS.size():
		var building: Dictionary = SIDE_AIRPORT_BUILDINGS[building_index]
		var projection := _side_airport_landmark_projection(airport, building.offset_m)
		projection.building_index = building_index
		projections.append(projection)
	var tower_projection := _side_airport_landmark_projection(airport, SIDE_AIRPORT_TOWER_OFFSET_M)
	var cluster_shift_px := 0.0
	if bool(view.get("crossing_view", false)):
		for projection in projections + [tower_projection]:
			projection.centre_m = float(view.centre_m) + (float(projection.centre_m) - float(view.centre_m)) * 0.2
		# Paint distant buildings first; foreground walls and roofs hide them.
		projections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.lateral_km) > float(b.lateral_km))
		# This is deliberately a schematic side-on view: keep the short runway
		# slice unobstructed and place the service cluster beside it, not on it.
		var minimum_x := INF
		var maximum_x := -INF
		for projection in projections + [tower_projection]:
			if float(projection.lateral_km) >= LANDMARK_VISIBILITY_KM:
				continue
			var x := anchor.x + float(projection.centre_m) * pixels_per_m
			var half_width := 25.0 * float(projection.size_scale)
			minimum_x = minf(minimum_x, x - half_width)
			maximum_x = maxf(maximum_x, x + half_width)
		if minimum_x < INF:
			var runway_start := anchor.x + float(view.runway_start_m) * pixels_per_m
			var runway_end := anchor.x + float(view.runway_end_m) * pixels_per_m
			var cluster_width := maximum_x - minimum_x
			if rect.end.x - runway_end >= cluster_width + 12.0 or rect.end.x - runway_end >= runway_start - rect.position.x:
				cluster_shift_px = runway_end + 12.0 - minimum_x
			else:
				cluster_shift_px = runway_start - 12.0 - maximum_x
	return {"buildings": projections, "tower": tower_projection, "shift_px": cluster_shift_px}

func _draw_distant_airport(view: Dictionary, rect: Rect2, anchor: Vector2, pixels_per_m: float) -> void:
	var runway_y = _side_runway_y(int(view.airport_index), anchor, pixels_per_m)
	if runway_y < rect.position.y or runway_y > rect.end.y + 20.0:
		return
	# Fixed runway-local footprints, projected onto actual ground motion.
	# The longitudinal view retains world-space spacing. Side-on flyovers
	# compress the cluster for a clearer overlapping, depth-like silhouette.
	var layout := _airport_cluster_layout(view, rect, anchor, pixels_per_m)
	var projections: Array[Dictionary] = layout.buildings
	var tower_projection: Dictionary = layout.tower
	var cluster_shift_px: float = layout.shift_px
	for projection in projections:
		var building: Dictionary = SIDE_AIRPORT_BUILDINGS[int(projection.building_index)]
		if float(projection.lateral_km) >= LANDMARK_VISIBILITY_KM:
			continue
		var size_scale: float = projection.size_scale
		var opacity := minf(1.0, size_scale * 10.0)
		var distant_ink = Color(AircraftArt.INK.lerp(AircraftArt.PAPER, 0.48), opacity)
		var distant_fill = Color(AircraftArt.LIGHT.lerp(AircraftArt.PAPER, 0.42), opacity)
		var centre_x = anchor.x + float(projection.centre_m) * pixels_per_m + cluster_shift_px
		var projected_width: float = float(building.width_m) * float(projection.along_weight) + float(building.depth_m) * float(projection.across_weight)
		var width_px = clampf(projected_width * pixels_per_m, 9.0, 46.0) * size_scale
		var height_px = clampf(float(building.height_m) * pixels_per_m, 7.0, 30.0) * size_scale
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
			Vector2(body.position.x - 2.0 * size_scale, body.position.y),
			Vector2(centre_x, body.position.y - height_px * 0.42),
			Vector2(body.end.x + 2.0 * size_scale, body.position.y),
		])
		if bool(view.get("crossing_view", false)) and rect.encloses(Rect2(roof[0], Vector2(roof[2].x - roof[0].x, 0.0)).expand(roof[1])):
			host.draw_colored_polygon(roof, distant_fill)
		_draw_side_clipped_line(roof[0], roof[1], distant_ink, 1.1, rect)
		_draw_side_clipped_line(roof[1], roof[2], distant_ink, 1.1, rect)
		if width_px >= 14.0:
			var door = Rect2(centre_x - 2.0 * size_scale, runway_y - height_px * 0.55, 4.0 * size_scale, height_px * 0.55)
			for edge in [
				[door.position, Vector2(door.end.x, door.position.y)],
				[Vector2(door.end.x, door.position.y), door.end],
				[door.end, Vector2(door.position.x, door.end.y)],
				[Vector2(door.position.x, door.end.y), door.position],
			]:
				_draw_side_clipped_line(edge[0], edge[1], distant_ink, 0.8, rect)
	# A modest locator/radio mast rises just above the distant airport buildings.
	if float(tower_projection.lateral_km) >= LANDMARK_VISIBILITY_KM:
		return
	var size_scale: float = tower_projection.size_scale
	var distant_ink = Color(AircraftArt.INK.lerp(AircraftArt.PAPER, 0.48), minf(1.0, size_scale * 10.0))
	var tower_x = anchor.x + float(tower_projection.centre_m) * pixels_per_m + cluster_shift_px
	var tower_height = clampf(17.0 * pixels_per_m, 24.0, 48.0) * size_scale
	var tower_half_width = clampf(clampf(17.0 * pixels_per_m, 24.0, 48.0) * 0.18, 5.0, 8.0) * size_scale
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
		_draw_side_clipped_line(Vector2(tower_x, tower_top), Vector2(tower_x, tower_top - 7.0 * size_scale), distant_ink, 1.2, rect)
		if rect.has_point(Vector2(tower_x, tower_top - 8.5 * size_scale)):
			host.draw_circle(Vector2(tower_x, tower_top - 8.5 * size_scale), 1.8 * size_scale, distant_ink)

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
	_draw_runway_strip_screen(start_x, end_x, runway_y, dash_origin_x, float(view.get("size_scale", 1.0)), bool(view.get("crossing_view", false)))

func _draw_runway_strip_screen(start_x: float, end_x: float, runway_y: float, dash_origin_x: float = NAN, size_scale: float = 1.0, side_on: bool = false) -> void:
	var opacity := minf(1.0, size_scale * 10.0)
	var runway_rect = Rect2(start_x, runway_y - 2.0 * size_scale, maxf(0.0, end_x - start_x), 9.0 * size_scale)
	host.draw_rect(runway_rect, Color(Color("b6a779"), opacity), true)
	host.draw_line(Vector2(start_x, runway_y - 2.0 * size_scale), Vector2(end_x, runway_y - 2.0 * size_scale), Color(AircraftArt.INK, opacity), 2.0 * size_scale, true)
	host.draw_line(Vector2(start_x, runway_y + 7.0 * size_scale), Vector2(end_x, runway_y + 7.0 * size_scale), Color(AircraftArt.LIGHT, opacity), 1.2 * size_scale, true)
	if side_on:
		var stripe_x := (start_x + end_x) * 0.5
		host.draw_line(Vector2(stripe_x, runway_y - 1.0 * size_scale), Vector2(stripe_x, runway_y + 6.0 * size_scale), Color(Color("ded5b5"), opacity), 2.0 * size_scale, true)
		return
	if is_nan(dash_origin_x):
		dash_origin_x = start_x
	# Subpixel distant strips need no individual markings.
	if size_scale < 0.02:
		return
	var dash_x = dash_origin_x + 15.0 * size_scale
	if dash_x + 24.0 * size_scale < start_x:
		dash_x += ceilf((start_x - dash_x - 24.0 * size_scale) / (45.0 * size_scale)) * 45.0 * size_scale
	while dash_x < end_x - 8.0 * size_scale:
		var visible_dash_start = maxf(dash_x, start_x)
		var visible_dash_end = minf(dash_x + 24.0 * size_scale, end_x)
		if visible_dash_end > visible_dash_start:
			host.draw_line(Vector2(visible_dash_start, runway_y + 2.5 * size_scale), Vector2(visible_dash_end, runway_y + 2.5 * size_scale), Color(Color("ded5b5"), opacity), 2.0 * size_scale, true)
		dash_x += 45.0 * size_scale
