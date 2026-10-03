extends Control
const VisualTheme = preload("res://scripts/visual_theme.gd")
const Localization = preload("res://scripts/localization.gd")

var controller: Control
var overlay: Control
var _base_signature: Array = []
var base_draw_count := 0
var overlay_draw_count := 0

func _ready() -> void:
	material = VisualTheme.create_material()
	material.set_shader_parameter("navigation_map", true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = Control.new()
	overlay.use_parent_material = true
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)

func refresh() -> void:
	var map = controller.navigation_map
	material.set_shader_parameter("theme_enabled", VisualTheme.dark and not controller.large_ils and not controller.large_weather_radar)
	var signature: Array = [controller.world, map.map_rect(), map.map_center, map.map_zoom,
		map.wind_overlay_index, roundi(controller.flight.altitude_m / 25.0) if map.wind_overlay_index == map.WIND_OVERLAY_ALTITUDES.size() else 0,
		map.weather_briefing_time_seconds, map.weather_briefing_visible,
		Localization.language, controller.large_ils, controller.large_weather_radar, VisualTheme.dark]
	if signature != _base_signature or controller.large_ils or controller.large_weather_radar:
		_base_signature = signature
		queue_redraw()
	overlay.queue_redraw()

func invalidate_base() -> void:
	_base_signature.clear()
	queue_redraw()

func _draw() -> void:
	if controller != null:
		if controller.large_ils or controller.large_weather_radar:
			controller._draw_map_on(self)
		else:
			base_draw_count += 1
			controller.navigation_map.draw_base_on(self)

func _draw_overlay() -> void:
	if controller != null and not controller.large_ils and not controller.large_weather_radar:
		overlay_draw_count += 1
		controller.navigation_map.draw_overlay_on(overlay)
