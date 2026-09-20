extends SceneTree

const Save = preload("res://scripts/save_game.gd")
const Calculator = preload("res://scripts/flight_calculator.gd")
const NavigationMap = preload("res://scripts/navigation_map.gd")

func _initialize() -> void:
	var path := Save.PATH + Save.INVALID_DEBUG_SUFFIX
	if not FileAccess.file_exists(path):
		print("No live invalid-save diagnostic snapshot")
		quit(2)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Variant = file.get_var(false)
	file.close()
	print("valid=", Save.valid(data), " reason=", Save._validation_error(data))
	if not data is Dictionary:
		quit(1)
		return
	for root_key in ["world", "flight", "ui", "economy"]:
		print("root.", root_key, " type=", type_string(typeof(data.get(root_key))))
	if data.get("ui") is Dictionary:
		var ui: Dictionary = data.ui
		var missing: Array[String] = []
		for field in Save.UI_FIELDS:
			if not ui.has(field):
				missing.append(field)
		print("missing_ui=", missing)
		print("calculator_valid=", ui.has("flight_calculator") and Calculator.valid_snapshot(ui.flight_calculator))
		if ui.get("flight_calculator") is Dictionary:
			var calculator: Dictionary = ui.flight_calculator
			print("calculator active=", calculator.get("active_profile"), " expanded=", calculator.get("expanded"), " position=", calculator.get("position"))
			for profile_index in calculator.get("profiles", []).size():
				var profile: Variant = calculator.profiles[profile_index]
				print("profile ", profile_index, " type=", type_string(typeof(profile)), " data=", profile)
		print("briefing_valid=", ui.has("weather_briefing") and NavigationMap.valid_weather_briefing(ui.weather_briefing))
		for key in ["measurement_lines", "radar_measurement_lines", "flight_trajectory"]:
			print(key, " type=", type_string(typeof(ui.get(key))), " size=", ui.get(key, []).size())
			for index in ui.get(key, []).size():
				var entry: Variant = ui[key][index]
				if not entry is Dictionary:
					print("  bad entry ", index, " type=", type_string(typeof(entry)))
				elif key != "flight_trajectory" and (not entry.get("a") is Vector2 or not entry.get("b") is Vector2 or not entry.has("max_height_m")):
					print("  bad line ", index, " =", entry)
		print("ui scalars: map_zoom=", ui.get("map_zoom"), " view=", ui.get("view_mode"), " radar_range=", ui.get("radar_range_index"), " cabin_zoom=", ui.get("cabin_terrain_zoom"), " time_scale=", ui.get("time_scale_index"))
	if data.get("flight") is Dictionary:
		print("flight: state=", data.flight.get("state"), " airport=", data.flight.get("airport_index"), " prepared=", data.flight.get("prepared_airport_index"), " condition=", data.flight.get("airframe_condition"))
	if data.get("economy") is Dictionary:
		print("economy visited=", data.economy.get("visited_airports"), " repair=", data.economy.get("repair_airports"), " inventory_size=", data.economy.get("inventory", []).size())
	quit(0)
