extends RefCounted
## World-space geometry only: no controller, UI, camera or drawing dependency.
const StormGeometry = preload("res://scripts/storm_geometry.gd")
const CELL_KM := 10.0
const VISIBILITY_MARGIN_KM := 1.5

var _segments: Array[Dictionary] = []
var _cells: Dictionary = {}
var _visible_segments: Array[Dictionary] = []
var _visible_key := Rect2(Vector2.INF, Vector2.ZERO)
var _world_size_km := 200.0
var _storm_contours: Dictionary = {}
var _unit_circle := PackedVector2Array()

func rebuild_contours(segments: Array[Dictionary], world_size_km: float) -> void:
	_segments = segments
	_world_size_km = world_size_km
	_cells.clear()
	_visible_segments = []
	_visible_key = Rect2(Vector2.INF, Vector2.ZERO)
	for index in segments.size():
		var segment: Dictionary = segments[index]
		var low: Vector2 = Vector2(segment.a).min(segment.b) / CELL_KM
		var high: Vector2 = Vector2(segment.a).max(segment.b) / CELL_KM
		for y in range(floori(low.y), floori(high.y) + 1):
			for x in range(floori(low.x), floori(high.x) + 1):
				var key := Vector2i(x, y)
				if not _cells.has(key):
					_cells[key] = []
				_cells[key].append(index)

func visible_contours(world_rect: Rect2) -> Array[Dictionary]:
	var visible := world_rect.grow(VISIBILITY_MARGIN_KM)
	if visible == _visible_key:
		return _visible_segments
	_visible_key = visible
	if _cells.is_empty() or visible.get_area() >= _world_size_km * _world_size_km * 0.5:
		_visible_segments = _segments
		return _visible_segments
	var indices: Dictionary = {}
	var last_cell := floori(_world_size_km / CELL_KM)
	for y in range(maxi(0, floori(visible.position.y / CELL_KM)), mini(last_cell, floori(visible.end.y / CELL_KM)) + 1):
		for x in range(maxi(0, floori(visible.position.x / CELL_KM)), mini(last_cell, floori(visible.end.x / CELL_KM)) + 1):
			for index in _cells.get(Vector2i(x, y), []):
				indices[index] = true
	var ordered := indices.keys()
	ordered.sort()
	_visible_segments = []
	for index in ordered:
		_visible_segments.append(_segments[index])
	return _visible_segments

func invalidate_weather() -> void:
	_storm_contours.clear()

func cached_storm_count() -> int:
	return _storm_contours.size()

func storm_contour(storm: Dictionary, center: Vector2) -> PackedVector2Array:
	var key := hash([storm, center])
	if not _storm_contours.has(key):
		_storm_contours[key] = _build_storm_contour(storm, center)
	return _storm_contours[key]

func _build_storm_contour(storm: Dictionary, center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for sample_index in 48:
		var direction := Vector2.RIGHT.rotated(TAU * sample_index / 48.0)
		var extent := 0.0
		for lobe in storm.radar_lobes:
			var offset := Vector2(lobe.offset_km)
			var radius := StormGeometry.lobe_radius(storm, lobe)
			var projection := direction.dot(offset)
			var discriminant := projection * projection - (offset.length_squared() - radius * radius)
			if discriminant >= 0.0:
				extent = maxf(extent, projection + sqrt(discriminant))
		points.append(center + direction * extent)
	return points

func circle(center: Vector2, radius: float) -> PackedVector2Array:
	if _unit_circle.is_empty():
		for index in 40:
			_unit_circle.append(Vector2.RIGHT.rotated(TAU * index / 40.0))
	return Transform2D(0.0, Vector2.ONE * radius, 0.0, center) * _unit_circle
