extends Node
## Rasterize north-up echoes once per simulation second; rotate the texture
## when drawing the scope, without rebuilding/clipping storm polygons.
const Art = preload("res://scripts/weather_radar_art.gd")
const TEXTURE_SIZE := 1024
var viewport: SubViewport
var canvas: Node2D
var cached_world
var snapshot: Dictionary = {}
var last_update_time := -INF
var refresh_count := 0
var cached_range_km := 30.0

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(TEXTURE_SIZE, TEXTURE_SIZE)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	canvas = Node2D.new()
	viewport.add_child(canvas)
	canvas.draw.connect(_draw_echoes)

func invalidate() -> void:
	last_update_time = -INF

func update_cache(world, flight, simulation_time: float, range_km: float = 30.0) -> void:
	if cached_world == world and cached_range_km == range_km and simulation_time >= last_update_time and simulation_time - last_update_time < 1.0:
		return
	cached_world = world
	cached_range_km = range_km
	last_update_time = simulation_time
	snapshot = {"position_km": flight.position_km, "heading_deg": 0.0}
	refresh_count += 1
	canvas.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_echoes() -> void:
	if cached_world == null:
		return
	Art.draw_echoes(canvas, cached_world, snapshot, Vector2.ONE * TEXTURE_SIZE * 0.5, TEXTURE_SIZE * 0.5 - 2.0, cached_range_km)

func get_texture() -> Texture2D:
	return viewport.get_texture()
