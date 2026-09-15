extends RefCounted
## Shared immediate-mode button for the code-drawn cockpit and paper scenes.
## Labels use font metrics and fit their content box in either palette.
const Art = preload("res://scripts/aircraft_art.gd")

static func draw(canvas: Control, rect: Rect2, label: String, paper: bool,
		font_size: int = 14, indicator: Color = Color.TRANSPARENT, enabled: bool = true) -> void:
	var hovered := enabled and rect.has_point(canvas.get_local_mouse_position())
	var fill := Art.PAPER.darkened(0.04) if hovered else Art.PAPER
	var border: Color = Art.INK
	var ink: Color = Art.INK
	if not paper:
		fill = Color("334b55") if enabled else Color("29383e")
		border = Color("82979f") if enabled else Color("53646b")
		ink = Color.WHITE if enabled else Color("89979c")
	if paper:
		Art.box(canvas, rect, fill, border, 3)
	else:
		canvas.draw_rect(rect, fill, true)
		canvas.draw_rect(rect, border, false, 1)
	var left := 10.0 if paper else 4.0
	var right := 10.0 if paper else 3.0
	if indicator.a > 0.0:
		canvas.draw_circle(rect.position + Vector2(9, rect.size.y * 0.5), 4.0, indicator)
		left = 16.0
	var width := maxf(1.0, rect.size.x - left - right)
	var font := ThemeDB.fallback_font
	while font_size > 7 and (font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width or font.get_height(font_size) > rect.size.y - 4.0):
		font_size -= 1
	var fitted := label
	# Pathological narrow viewports still cannot draw text outside the button.
	while not fitted.is_empty() and font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		fitted = fitted.left(fitted.length() - 1)
	var baseline := rect.position.y + (rect.size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	canvas.draw_string(font, Vector2(rect.position.x + left, baseline), fitted, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, ink)
