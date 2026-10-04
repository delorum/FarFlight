extends RefCounted
const Palette = preload("res://scripts/ui_palette.gd")
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
	result.set_shader_parameter("source_paper", Vector3(Palette.PAPER.r, Palette.PAPER.g, Palette.PAPER.b))
	result.set_shader_parameter("source_route", Vector3(Palette.ROUTE.r, Palette.ROUTE.g, Palette.ROUTE.b))
	result.set_shader_parameter("dark_background", Vector3(Palette.DARK_BACKGROUND.r, Palette.DARK_BACKGROUND.g, Palette.DARK_BACKGROUND.b))
	return result
