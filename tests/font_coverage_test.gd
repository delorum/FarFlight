extends SceneTree
## System font fallback hides missing glyphs on desktop, but not in Web exports.
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var font := ThemeDB.fallback_font
	check(font is FontVariation, "Project fallback must preserve the default font and add bundled symbol coverage")
	if font is FontVariation:
		check(font.base_font != null and font.base_font.resource_path == "res://assets/fonts/OpenSans_SemiBold.woff2", "Ordinary text must retain Godot's original Open Sans SemiBold")
		check(font.get_string_size("Русский English 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).is_equal_approx(font.base_font.get_string_size("Русский English 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)), "Fallback symbols must not change text widths")
	var server := TextServerManager.get_primary_interface()
	var fonts := font.get_rids()
	check(fonts.size() >= 2, "Default text and bundled symbol fonts must both be active")
	for rid in fonts:
		server.font_set_allow_system_fallback(rid, false)
	var required := "■□✓⇧←→↑↓▲▼•×°−—…РусскийEnglish"
	# Also cover every non-ASCII character in source strings so newly added UI
	# symbols cannot silently depend on fonts installed on a developer's machine.
	var literal := RegEx.new()
	literal.compile('"(?:[^"\\\\]|\\\\.)*"')
	for file_name in DirAccess.get_files_at("res://scripts"):
		if not file_name.ends_with(".gd"):
			continue
		for match_result in literal.search_all(FileAccess.get_file_as_string("res://scripts/" + file_name)):
			for character in match_result.get_string():
				if character.unicode_at(0) > 127 and not required.contains(character):
					required += character
	for character in required:
		var line := TextLine.new()
		line.add_string(character, font, 16)
		var glyphs := server.shaped_text_get_glyphs(line.get_rid())
		check(not glyphs.is_empty(), "Character must produce a glyph: " + character)
		for glyph in glyphs:
			check(glyph.font_rid.is_valid() and glyph.index != 0 and fonts.has(glyph.font_rid), "Glyph must come from project fonts, not system fallback: %s U+%04X" % [character, character.unicode_at(0)])
	var label := Label.new()
	check(label.get_theme_font("font") == font, "Controls and custom drawing must share the same font fallback")
	label.free()
	print("Bundled UI glyph coverage without system fonts (%d characters): " % required.length(), "FAIL" if failed else "OK")
	quit(1 if failed else 0)
