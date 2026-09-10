extends RefCounted
## One local slot. No object deserialization; an atomic rename keeps the old
## slot intact until the replacement has been written and validated.
const VERSION := 1
const PATH := "user://flight_save.dat"
const WEB_KEY := "farflight.save.v1"

# Synchronous localStorage replacement survives an immediate page close. Keep
# Variant's binary encoding: JSON alone loses Vector2 and 64-bit RNG state.
static func encode_web(data: Dictionary) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(data))

static func decode_web(encoded: String) -> Dictionary:
	if encoded.is_empty() or encoded.length() > 8 * 1024 * 1024:
		return {}
	var data: Variant = bytes_to_var(Marshalls.base64_to_raw(encoded))
	return data if valid(data) else {}

static func web_read_script() -> String:
	return "(() => { try { return localStorage.getItem(%s) || ''; } catch (_) { return ''; } })()" % JSON.stringify(WEB_KEY)

static func web_write_script(encoded: String) -> String:
	return "(() => { try { localStorage.setItem(%s, %s); return 0; } catch (_) { return 1; } })()" % [JSON.stringify(WEB_KEY), JSON.stringify(encoded)]

static func slot_exists(path: String = PATH) -> bool:
	if OS.has_feature("web") and path == PATH:
		return not str(JavaScriptBridge.eval(web_read_script())).is_empty()
	return FileAccess.file_exists(path)
const UI_FIELDS := [
	"receiver_frequencies", "map_zoom", "map_center", "measurement_lines", "pending_measure",
	"radar_measurement_lines", "radar_pending_measure", "radar_range_index", "large_weather_radar",
	"clock_seconds", "status_timer", "trip_air_distance_km", "trip_elapsed_seconds",
	"flight_trajectory", "trajectory_finished", "trajectory_recording_started",
	"trajectory_elapsed_seconds", "trajectory_distance_km", "trajectory_last_position",
	"ils_airport_index", "simulation_paused", "wind_overlay_index", "view_mode",
	"scene_player_facing", "scene_walk_phase", "apron_aircraft_on_left", "scene_notice",
	"propeller_phase", "cabin_terrain_zoom", "cabin_fog_travel_px"
]

static func flight_fields(flight) -> Dictionary:
	var result := {}
	for property in flight.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = flight.get(property.name)
			if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2]:
				result[property.name] = value
	return result

static func capture(game) -> Dictionary:
	var ui := {}
	for field in UI_FIELDS:
		ui[field] = game.get(field)
	ui["player_screen_fraction"] = game.scene_player_x / maxf(game.size.x, 1.0)
	ui["player_aircraft_x"] = (game.scene_player_x - game._aircraft_origin().x) / game._aircraft_scale()
	return {
		"version": VERSION,
		"world": {"seed": game.world.seed_value, "airports": game.world.airports,
			"beacons": game.world.beacons, "wind_layers": game.world.wind_layers,
			"storms": game.world.storms, "time": game.world.weather_time_seconds},
		"flight": flight_fields(game.flight), "rng_state": game.flight.turbulence_rng.state,
		"ui": ui,
	}.duplicate(true)

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION:
		return false
	for key in ["world", "flight", "ui"]:
		if not data.get(key) is Dictionary:
			return false
	var world: Dictionary = data.world
	if not world.get("seed") is int or not world.get("time") is float or not data.get("rng_state") is int:
		return false
	for key in ["airports", "beacons", "wind_layers", "storms"]:
		if not world.get(key) is Array:
			return false
		for item in world[key]:
			if not item is Dictionary:
				return false
	if world.airports.size() != 2 or world.beacons.size() != 6 or world.wind_layers.size() < 2:
		return false
	for airport in world.airports:
		if not airport.get("position") is Vector2 or not airport.get("heading") is float or not airport.get("name") is String:
			return false
	for beacon in world.beacons:
		if not beacon.get("position") is Vector2 or not beacon.has_all(["frequency", "range_km", "runway", "name"]):
			return false
	for layer in world.wind_layers:
		if not layer.has_all(["altitude_m", "from_deg", "speed_kmh"]):
			return false
	for storm in world.storms:
		if not storm.get("origin") is Vector2 or not storm.get("drift_kmh") is Vector2 or not storm.has_all(["radius_km", "intensity", "radar_lobes"]):
			return false
		if not storm.radar_lobes is Array:
			return false
		for lobe in storm.radar_lobes:
			if not lobe is Dictionary or not lobe.get("offset_km") is Vector2 or not lobe.has_all(["radius_scale", "strength"]):
				return false
	for field in UI_FIELDS:
		if not data.ui.has(field):
			return false
	if not data.ui.has_all(["player_screen_fraction", "player_aircraft_x"]):
		return false
	if not data.ui.receiver_frequencies is Array or data.ui.receiver_frequencies.size() != 2:
		return false
	for frequency in data.ui.receiver_frequencies:
		if not frequency is int or frequency < 190 or frequency > 535:
			return false
	for key in ["pending_measure", "radar_pending_measure"]:
		if data.ui[key] != null and not data.ui[key] is Vector2:
			return false
	if not data.ui.map_center is Vector2 or not data.ui.map_zoom is float or data.ui.map_zoom < 1.0 or data.ui.map_zoom > 12.0:
		return false
	if data.flight.get("airport_index", -1) not in [0,1] or data.ui.ils_airport_index not in [0,1] or data.ui.wind_overlay_index not in range(5):
		return false
	for key in ["measurement_lines", "radar_measurement_lines", "flight_trajectory"]:
		if not data.ui[key] is Array:
			return false
		for entry in data.ui[key]:
			if not entry is Dictionary:
				return false
			if key != "flight_trajectory" and (not entry.get("a") is Vector2 or not entry.get("b") is Vector2 or not entry.has("max_height_m")):
				return false
			if key == "flight_trajectory" and (not entry.get("position") is Vector2 or not entry.has_all(["time_seconds", "distance_km"])):
				return false
	return data.flight.get("position_km") is Vector2 and data.flight.get("state") in range(5) and data.ui.view_mode in range(5) and data.ui.radar_range_index in range(4) and data.ui.cabin_terrain_zoom in range(4)

static func read_slot(path: String = PATH) -> Dictionary:
	if OS.has_feature("web") and path == PATH:
		var encoded: Variant = JavaScriptBridge.eval(web_read_script())
		return decode_web(encoded) if encoded is String else {}
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 32 * 1024 * 1024:
		return {}
	var data: Variant = file.get_var(false)
	return data if valid(data) else {}

static func write_slot(game, path: String = PATH) -> Error:
	var data := capture(game)
	if not valid(data):
		return ERR_INVALID_DATA
	if OS.has_feature("web") and path == PATH:
		var encoded := encode_web(data)
		if decode_web(encoded) != data:
			return ERR_FILE_CORRUPT
		var result: Variant = JavaScriptBridge.eval(web_write_script(encoded))
		if result == null or result != 0:
			return ERR_CANT_CREATE
		return OK if JavaScriptBridge.eval(web_read_script()) == encoded else ERR_FILE_CORRUPT
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(data, false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if read_slot(temporary) != data:
		return ERR_FILE_CORRUPT
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

static func restore(game, data: Dictionary) -> bool:
	if not valid(data):
		return false
	var new_world = game.FlightWorldScript.new(data.world.seed)
	new_world.airports.assign(data.world.airports)
	new_world.beacons.assign(data.world.beacons)
	new_world.wind_layers.assign(data.world.wind_layers)
	new_world.storms.assign(data.world.storms)
	new_world.weather_time_seconds = data.world.time
	var new_flight = game.FlightModelScript.new(new_world)
	# Reject incomplete/incompatible flight data before changing the live game.
	for field in flight_fields(new_flight):
		if not data.flight.has(field) or typeof(data.flight[field]) != typeof(new_flight.get(field)):
			return false
		new_flight.set(field, data.flight[field])
	new_flight.turbulence_rng.state = data.rng_state
	for field in UI_FIELDS:
		if typeof(data.ui[field]) != typeof(game.get(field)) and field not in ["pending_measure", "radar_pending_measure"]:
			return false
	game.world = new_world
	game.flight = new_flight
	game._set_view_mode(data.ui.view_mode)
	for field in UI_FIELDS:
		if game.get(field) is Array:
			game.get(field).assign(data.ui[field])
		else:
			game.set(field, data.ui[field])
	if game.view_mode in [game.ViewMode.CABIN, game.ViewMode.APRON]:
		game.scene_player_x = game._aircraft_origin().x + float(data.ui.player_aircraft_x) * game._aircraft_scale()
	else:
		game.scene_player_x = float(data.ui.player_screen_fraction) * game.size.x
	game.scene_is_walking = false
	game.flight.wheel_brakes_applied = false
	game.receiver_frequency_entry = ""
	game.active_receiver = -1
	game._build_contours()
	game._build_approach_markers()
	game._update_receiver_signals()
	game._update_ils_touchdown_prediction()
	game._update_cabin_terrain_profile()
	game._update_crash_overlay()
	game.weather_radar_cache.invalidate()
	game._queue_map_redraw()
	game.queue_redraw()
	return true
