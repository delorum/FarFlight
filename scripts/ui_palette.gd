extends RefCounted
## Named source colours for landscape art and final colours for native controls.
## Constants keep draw calls allocation-free; resolve control colours on theme changes.
const PAPER := Color("d7d0ad")
const DARK_BACKGROUND := Color("071012")
const SCENE_INK := Color("a5753d")
const SCENE_LIGHT := Color("d5bd97")
const MAP_INK := Color("5c4b31")
const CONTOUR := Color("806f4b")
const MAP_TEXT := Color("35372e")
const MAP_HINT := Color("55574a")
const MAP_FRAME := Color("6d6751")
const MAP_SCALE := Color("25271f")
const HOVER_LIGHT := Color("cec6a2")
const PRESSED_LIGHT := Color("c4b98e")
const HOVER_DARK := Color("202b2f")
const PRESSED_DARK := Color("334044")
const WARNING := Color("e8d274")
const ERROR := Color("ef645e")
const ERROR_LIGHT := Color("a3483f")
const CLOCK_FACE := Color("0a0e10")
const CLOCK_HAND := Color("edf2f2")
const CLOCK_SECOND_HAND := Color("ed775f")
const CLOCK_HAND_DARK := PAPER * Color(0.78, 0.78, 0.78)
const CLOCK_SECOND_HAND_DARK := PAPER * Color(0.72, 0.72, 0.72)
const CLOCK_RIM := Color("7d8b91")
const CLOCK_MARK := Color("d2dde0")
const ROUTE := Color("254d9a")
const LINKED_ROUTE := Color("c46f24")
const ACTIVE_ROUTE := Color("b72f29")
const MENU_INK := Color("513e2c")
const MENU_LINK_LIGHT := Color("8a552f")
const MENU_ERROR_LIGHT := Color("893f2f")
const MENU_VEIL_LIGHT := Color(0.90, 0.85, 0.72)
const MENU_FILL_LIGHT := Color(0.93, 0.89, 0.79)
const MENU_BORDER_LIGHT := Color(0.40, 0.29, 0.18)
const MENU_DISABLED_LIGHT := Color(0.36, 0.30, 0.24)
const MENU_PLACEHOLDER_LIGHT := Color(0.32, 0.25, 0.18)

static func background(dark: bool) -> Color:
	return DARK_BACKGROUND if dark else PAPER

static func text_color(dark: bool) -> Color:
	return PAPER if dark else MAP_INK

static func border(dark: bool) -> Color:
	return PAPER.darkened(0.28) if dark else CONTOUR

static func hover(dark: bool) -> Color:
	return HOVER_DARK if dark else HOVER_LIGHT

static func pressed(dark: bool) -> Color:
	return PRESSED_DARK if dark else PRESSED_LIGHT

static func error(dark: bool) -> Color:
	return ERROR if dark else ERROR_LIGHT
