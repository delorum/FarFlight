extends RefCounted
## Interface preference, independent of campaign saves and world generation.
const SHADER = preload("res://shaders/landscape_theme.gdshader")
static var dark := false
static var settings_path := "user://settings.cfg"

static func initialize(path: String) -> void:
	settings_path = path
	var config := ConfigFile.new()
	dark = config.load(path) == OK and bool(config.get_value("interface", "dark_landscape", false))

static func set_dark(value: bool, persist: bool = true) -> void:
	dark = value
	if persist:
		var config := ConfigFile.new()
		config.load(settings_path)
		config.set_value("interface", "dark_landscape", dark)
		config.save(settings_path)

static func create_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SHADER
	return result
