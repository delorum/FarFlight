extends RefCounted
## One airframe, two views. Coordinates and door/cockpit positions are shared
## with navigation in main.gd; changing the skin never changes the floor plan.
const INK := Color("#a5753d")
const LIGHT := Color("#d5bd97")
const PAPER := Color("#d7d0ad")
const SHADE := PAPER
const FLOOR_Y := 330.0
const COCKPIT_FLOOR_Y := 258.0
const COCKPIT_RAMP_TOP_X := 312.0
const COCKPIT_RAMP_BOTTOM_X := 395.0
const GROUND_Y := 426.0
const SEAT_X := 275.0
const DOOR_X := 630.0
const WALK_MIN := 265.0
const PILOT_SCALE := 0.95
const PILOT_HEIGHT := 73.0 * PILOT_SCALE
const CABIN_WINDOW_Y := FLOOR_Y - 61.0 * PILOT_SCALE
const CABIN_RIB_X := [344.0,407.0,470.0,533.0,596.0,659.0]
const TAIL_RIB_X := [685.0,750.0,790.0]
const TAIL_ROOF_START := Vector2(706,240)
const TAIL_ROOF_END := Vector2(810,292)
const TAIL_WINDOW := Vector2((TAIL_RIB_X[0]+TAIL_RIB_X[1])*0.5,CABIN_WINDOW_Y)
const TAIL_HEAD_CLEARANCE := 4.0
const PILOT_HALF_WIDTH := 12.0
# Stop before the cap/head reaches the sloping roof, including body width.
const WALK_MAX := TAIL_ROOF_START.x + (FLOOR_Y - PILOT_HEIGHT - TAIL_HEAD_CLEARANCE - TAIL_ROOF_START.y) * (TAIL_ROOF_END.x - TAIL_ROOF_START.x) / (TAIL_ROOF_END.y - TAIL_ROOF_START.y) - PILOT_HALF_WIDTH

static func line(c: CanvasItem, a: Vector2, b: Vector2, color: Color = INK, width: float = 2.0) -> void:
	c.draw_line(a, b, color, width, true)

static func poly(c: CanvasItem, points: PackedVector2Array, fill: Color = PAPER, color: Color = INK, width: float = 2.2) -> void:
	c.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	c.draw_polyline(closed, color, width, true)

static func rounded(points: PackedVector2Array, amount: float = 0.12) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size():
		var previous := points[(i + points.size() - 1) % points.size()]
		var corner := points[i]
		var next := points[(i + 1) % points.size()]
		var a := corner.lerp(previous, amount)
		var b := corner.lerp(next, amount)
		for step in 7:
			var t := step / 6.0
			result.append(a.lerp(corner,t).lerp(corner.lerp(b,t),t))
	return result

static func box(c: CanvasItem, rect: Rect2, fill: Color = PAPER, color: Color = INK, radius: int = 5) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	c.draw_style_box(style, rect)

static func cabin_floor_y(local_x: float) -> float:
	return lerpf(COCKPIT_FLOOR_Y, FLOOR_Y, clampf(inverse_lerp(COCKPIT_RAMP_TOP_X, COCKPIT_RAMP_BOTTOM_X, local_x), 0.0, 1.0))

static func cabin_window_position(local_x: float) -> Vector2:
	return Vector2(local_x, CABIN_WINDOW_Y + cabin_floor_y(local_x) - FLOOR_Y)

static func cabin_panel_window_position(panel_index: int) -> Vector2:
	return cabin_window_position((CABIN_RIB_X[panel_index]+CABIN_RIB_X[panel_index+1])*0.5)

static func _panel_point(u: float, v: float) -> Vector2:
	# Oblique panel plane; use airframe coordinates so mirroring stays shared.
	return Vector2(221, 234) + Vector2(24, -3) * u + Vector2(11, 48) * v

static func _draw_cockpit_console(c: CanvasItem, powered: bool) -> void:
	var edge := INK
	var metal := INK
	var face := PAPER
	var glass := PAPER
	var markings := INK
	# Console depth, sloping fascia and padded glare shield below the windscreen.
	poly(c, PackedVector2Array([Vector2(214,234), Vector2(221,235), Vector2(232,285), Vector2(214,293)]), PAPER, edge, 1.2)
	poly(c, PackedVector2Array([_panel_point(0,0), _panel_point(1,0), _panel_point(1,1), _panel_point(0,1)]), face, edge, 1.2)
	poly(c, rounded(PackedVector2Array([Vector2(211,230), Vector2(244,226), Vector2(250,231), Vector2(248,236), Vector2(215,239)]), 0.2), PAPER, edge, 1)
	line(c, Vector2(215,231), Vector2(243,228), metal, 1)
	# A regular grid in panel-local coordinates keeps equal gauge sizes,
	# balanced side margins and a clear gap above the radio strip.
	for row in 3:
		for column in 2:
			var u := 0.27 + column * 0.46
			var v := 0.23 + row * 0.205
			var rim := PackedVector2Array()
			for step in 25:
				var angle := TAU * step / 24.0
				rim.append(_panel_point(u + cos(angle) * 0.145, v + sin(angle) * 0.075))
			poly(c, rim, glass, metal, 0.8)
			if powered:
				for tick in 5:
					var angle := PI * (0.75 + tick * 0.375)
					line(c, _panel_point(u + cos(angle) * 0.105, v + sin(angle) * 0.053), _panel_point(u + cos(angle) * 0.08, v + sin(angle) * 0.04), markings, 0.55)
				var needle_angle := -2.3 + row * 0.8 + column * 1.4
				line(c, _panel_point(u, v), _panel_point(u + cos(needle_angle) * 0.095, v + sin(needle_angle) * 0.048), markings, 0.7)
	# Small radio/control strip and flush fasteners.
	poly(c, PackedVector2Array([_panel_point(0.125,0.80), _panel_point(0.875,0.80), _panel_point(0.875,0.91), _panel_point(0.125,0.91)]), glass, metal, 0.6)
	if powered:
		line(c, _panel_point(0.22,0.855), _panel_point(0.57,0.855), INK, 0.8)
	c.draw_circle(_panel_point(0.75,0.855), 0.7, metal)
	for screw in [Vector2(0.065,0.14), Vector2(0.935,0.14), Vector2(0.065,0.95), Vector2(0.935,0.95)]:
		c.draw_circle(_panel_point(screw.x,screw.y), 0.6, markings)

static func _draw_cockpit_controls(c: CanvasItem) -> void:
	var edge := INK
	var metal := PAPER
	var face := INK
	# Rudder pedals and steering column, with a padded, forked yoke.
	line(c, Vector2(249,FLOOR_Y-2), Vector2(254,309), edge, 2.6)
	line(c, Vector2(249,FLOOR_Y-2), Vector2(254,309), metal, 1)
	box(c, Rect2(245,FLOOR_Y-4,8,4), PAPER, INK, 1)
	var yoke := PackedVector2Array([Vector2(249,297), Vector2(247,304), Vector2(251,310), Vector2(258,309), Vector2(263,303), Vector2(261,296)])
	c.draw_polyline(yoke, edge, 3.5, true)
	c.draw_polyline(yoke, metal, 1, true)
	line(c, Vector2(249,297), Vector2(248,301), face, 4)
	line(c, Vector2(261,296), Vector2(262,300), face, 4)
	line(c, Vector2(249,297), Vector2(248,301), PAPER, 2)
	line(c, Vector2(261,296), Vector2(262,300), PAPER, 2)
	for pedal_x in [224,235]:
		poly(c, PackedVector2Array([Vector2(pedal_x,318), Vector2(pedal_x+7,316), Vector2(pedal_x+9,320), Vector2(pedal_x+1,323)]), metal, edge, 0.8)
	# Raised wall-mounted throttle quadrant, with visible mounting plate and
	# brackets; its underside clears the seat cushion rather than resting on it.
	poly(c, PackedVector2Array([Vector2(267,281),Vector2(283,281),Vector2(283,300),Vector2(267,300)]), PAPER, LIGHT, 0.8)
	for screw in [Vector2(269,283),Vector2(281,283),Vector2(269,298),Vector2(281,298)]:
		c.draw_circle(screw, 0.65, INK)
	line(c, Vector2(269,295), Vector2(271,299), INK, 1)
	line(c, Vector2(281,295), Vector2(279,299), INK, 1)
	box(c, Rect2(269,287,12,9), metal, edge, 2)
	line(c, Vector2(273,289), Vector2(269,276), edge, 1.5)
	line(c, Vector2(278,289), Vector2(278,278), edge, 1.3)
	c.draw_circle(Vector2(269,276), 2.3, PAPER)
	c.draw_arc(Vector2(269,276), 2.3, 0, TAU, 16, INK, 0.8, true)
	c.draw_circle(Vector2(278,278), 1.8, PAPER)
	c.draw_arc(Vector2(278,278), 1.8, 0, TAU, 16, INK, 0.8, true)

static func propeller_blade_points(phase: float, opposite: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	var angle := phase + (PI if opposite else 0.0)
	for point in [Vector2(-1,-8), Vector2(-9,-40), Vector2(-6,-93), Vector2(0,-107), Vector2(3,-62), Vector2(4,-9)]:
		# Side projection of rotation around the engine shaft, not a windmill
		# spinning in the screen plane. A little depth keeps motion legible.
		points.append(Vector2(107 + point.x + point.y * sin(angle) * 0.08, 264 + point.y * cos(angle)))
	return points

static func _draw_propeller(c: CanvasItem, powered: bool, phase: float) -> void:
	if not powered:
		phase = 0.0
	line(c, Vector2(114,264), Vector2(129,264), INK, 5)
	if powered:
		var disk := PackedVector2Array()
		for step in 41:
			var angle := TAU * step / 40.0
			disk.append(Vector2(107 + sin(angle) * 10, 264 + cos(angle) * 107))
		poly(c, disk, Color(INK,0.05), Color(INK,0.16), 0.8)
		for trail in [0.3,0.6]:
			for opposite in [false,true]:
				poly(c, propeller_blade_points(phase-trail, opposite), Color(INK,0.05), Color(INK,0.15), 1)
	for opposite in [false,true]:
		poly(c, propeller_blade_points(phase, opposite), Color(PAPER,0.65) if powered else PAPER, INK, 1.5)
	c.draw_circle(Vector2(107,264), 8, PAPER)
	c.draw_arc(Vector2(107,264), 8, 0, TAU, 20, INK, 2, true)

static func pitch_transform(origin: Vector2, scale_value: float, mirrored: bool, pitch_deg: float) -> Transform2D:
	var pivot := origin + Vector2(500,264) * scale_value
	var angle := deg_to_rad(pitch_deg) * (-1.0 if mirrored else 1.0)
	return Transform2D(angle, pivot - pivot.rotated(angle))

static func draw_small_aircraft(c: CanvasItem, origin: Vector2, scale_value: float, mirrored: bool, pitch_deg: float = 0.0) -> void:
	# Same raised cockpit, cargo body and round tail, with screen-space strokes
	# instead of subpixel outlines from scaling down the detailed cabin artwork.
	var transform := Transform2D(0.0, Vector2(-scale_value if mirrored else scale_value, scale_value), 0.0, origin + Vector2(1000.0 * scale_value if mirrored else 0.0, 0))
	transform = pitch_transform(origin, scale_value, mirrored, pitch_deg) * transform
	var outline := PackedVector2Array([
		Vector2(132,236), Vector2(150,214), Vector2(192,203), Vector2(241,152),
		Vector2(287,150), Vector2(330,182), Vector2(706,230), Vector2(788,272),
		Vector2(836,130), Vector2(868,103), Vector2(887,105), Vector2(915,155),
		Vector2(934,336), Vector2(918,350), Vector2(845,364), Vector2(540,345),
		Vector2(329,345), Vector2(153,314), Vector2(132,296)])
	poly(c, transform * outline, PAPER, INK, 1.2)
	for pair in [[Vector2(289,137), Vector2(534,137)], [Vector2(319,328), Vector2(522,328)], [Vector2(107,184), Vector2(107,344)], [Vector2(327,345), Vector2(327,393)]]:
		line(c, transform * pair[0], transform * pair[1], INK, 1.2)
	c.draw_circle(transform * Vector2(327,393), maxf(1.2, scale_value * 33.0), INK)
	c.draw_circle(transform * Vector2(905,412), maxf(0.8, scale_value * 14.0), INK)

static func draw_aircraft(c: CanvasItem, origin: Vector2, scale_value: float, mirrored: bool, cutaway: bool, powered: bool = false, propeller_phase: float = 0.0, pitch_deg: float = 0.0) -> void:
	var airframe_transform := Transform2D(0.0, Vector2(-scale_value if mirrored else scale_value, scale_value), 0.0, origin + Vector2(1000.0 * scale_value if mirrored else 0.0, 0))
	airframe_transform = pitch_transform(origin, scale_value, mirrored, pitch_deg) * airframe_transform
	c.draw_set_transform_matrix(airframe_transform)
	# Rounded vertical tail behind the tapering fuselage.
	poly(c, rounded(PackedVector2Array([Vector2(783,295), Vector2(808,210), Vector2(836,130), Vector2(850,110), Vector2(868,103), Vector2(887,105), Vector2(903,122), Vector2(915,155), Vector2(931,327), Vector2(862,347)]),0.22))
	line(c, Vector2(878,117), Vector2(904,319))
	line(c, Vector2(892,185), Vector2(914,182), LIGHT)
	line(c, Vector2(900,243), Vector2(922,240), LIGHT)
	# Struts, main wheels and tailwheel: the silhouette rests on one baseline.
	line(c, Vector2(314,321), Vector2(327,390), INK, 5)
	line(c, Vector2(420,320), Vector2(327,390), INK, 5)
	line(c, Vector2(343,327), Vector2(359,391), LIGHT, 4)
	c.draw_circle(Vector2(361,396), 28, SHADE)
	c.draw_arc(Vector2(361,396), 28, 0, TAU, 40, LIGHT, 2, true)
	c.draw_circle(Vector2(327,393), 33, PAPER)
	c.draw_arc(Vector2(327,393), 33, 0, TAU, 48, INK, 3, true)
	c.draw_arc(Vector2(327,393), 24, 0, TAU, 40, INK, 1.5, true)
	c.draw_arc(Vector2(327,393), 10, 0, TAU, 24, INK, 2, true)
	line(c, Vector2(890,360), Vector2(902,405), INK, 3)
	c.draw_circle(Vector2(905,412), 14, PAPER)
	c.draw_arc(Vector2(905,412), 14, 0, TAU, 24, INK, 2, true)
	# Rounded radial engine, raised cockpit and long tapering cargo fuselage.
	poly(c, rounded(PackedVector2Array([
		Vector2(150,214), Vector2(192,203), Vector2(222,166), Vector2(241,152),
		Vector2(287,150), Vector2(313,178), Vector2(370,189), Vector2(706,230), Vector2(788,272),
		Vector2(865,296), Vector2(918,316), Vector2(934,336), Vector2(918,350),
		Vector2(845,364), Vector2(706,355), Vector2(540,345), Vector2(329,345),
		Vector2(212,330), Vector2(153,314), Vector2(137,296), Vector2(132,236)])))
	# A lightly shaded belly gives volume while keeping the reference's line art.
	poly(c, PackedVector2Array([Vector2(214,316), Vector2(331,329), Vector2(538,331), Vector2(707,343), Vector2(844,351), Vector2(918,346), Vector2(845,364), Vector2(706,355), Vector2(540,345), Vector2(329,345), Vector2(212,330)]), SHADE, LIGHT, 1)
	box(c, Rect2(129,216,77,99), PAPER, INK, 18)
	line(c, Vector2(145,226), Vector2(145,304))
	line(c, Vector2(194,223), Vector2(194,306), LIGHT)
	_draw_propeller(c, powered, propeller_phase)
	# Windscreen geometry is identical inside and outside.
	poly(c, PackedVector2Array([Vector2(219,207), Vector2(242,166), Vector2(265,164), Vector2(265,210)]), SHADE)
	poly(c, PackedVector2Array([Vector2(272,164), Vector2(285,165), Vector2(305,185), Vector2(307,211), Vector2(272,211)]), SHADE)
	line(c, Vector2(235,190), Vector2(253,171), PAPER, 3)
	if cutaway:
		# Open side panel: roof, ribs, windows, empty cargo floor and pilot seat.
		poly(c, PackedVector2Array([Vector2(216,219), Vector2(310,221), Vector2(340,207), Vector2(665,231), TAIL_ROOF_START, TAIL_ROOF_END, Vector2(827,325), Vector2(810,FLOOR_Y), Vector2(245,FLOOR_Y), Vector2(216,317)]), PAPER, LIGHT, 1.5)
		for rib_x in CABIN_RIB_X:
			line(c, Vector2(rib_x,225), Vector2(rib_x,324), LIGHT, 1)
		for rib_x in TAIL_RIB_X:
			var roof_y := lerpf(TAIL_ROOF_START.y, TAIL_ROOF_END.y, (rib_x-TAIL_ROOF_START.x)/(TAIL_ROOF_END.x-TAIL_ROOF_START.x))
			line(c, Vector2(rib_x,roof_y+3), Vector2(rib_x,FLOOR_Y-4), LIGHT, 1)
		for panel_index in 4:
			var window_position := cabin_panel_window_position(panel_index)
			c.draw_circle(window_position,13,SHADE)
			c.draw_arc(window_position,13,0,TAU,32,LIGHT,1.8,true)
		# Raised flight deck and a continuous ramp share the character's floor profile.
		poly(c, PackedVector2Array([Vector2(214,COCKPIT_FLOOR_Y), Vector2(COCKPIT_RAMP_TOP_X,COCKPIT_FLOOR_Y), Vector2(COCKPIT_RAMP_BOTTOM_X,FLOOR_Y), Vector2(214,FLOOR_Y)]), PAPER, LIGHT, 1)
		c.draw_polyline(PackedVector2Array([Vector2(214,COCKPIT_FLOOR_Y), Vector2(COCKPIT_RAMP_TOP_X,COCKPIT_FLOOR_Y), Vector2(COCKPIT_RAMP_BOTTOM_X,FLOOR_Y), Vector2(810,FLOOR_Y)]), INK, 2.5, true)
		for ramp_x in range(321,391,12):
			var ramp_y := cabin_floor_y(ramp_x)
			line(c, Vector2(ramp_x,ramp_y+4), Vector2(ramp_x+6,ramp_y+4), LIGHT, 1)
		line(c, Vector2(242,337), Vector2(806,337), LIGHT)
		for floor_x in range(350,807,40):
			line(c, Vector2(floor_x,332), Vector2(floor_x-6,337), LIGHT, 1)
		# Lift the seat and mechanical controls with the deck, but fit the panel
		# immediately below the unchanged windscreen instead of covering the glass.
		c.draw_set_transform_matrix(airframe_transform * Transform2D(0.0, Vector2(0,COCKPIT_FLOOR_Y-FLOOR_Y)))
		box(c, Rect2(285,269,13,43), SHADE, INK, 4)
		box(c, Rect2(258,306,40,9), SHADE, INK, 3)
		line(c, Vector2(281,315), Vector2(281,330), INK, 3)
		_draw_cockpit_controls(c)
		c.draw_set_transform_matrix(airframe_transform * Transform2D(0.0, Vector2(1,0.65), 0.0, Vector2(-6,214-226*0.65)))
		_draw_cockpit_console(c, powered)
		c.draw_set_transform_matrix(airframe_transform)
		# The cargo door remains at the same physical station in both views.
		box(c, Rect2(601,232,65,99), PAPER, LIGHT, 11)
		c.draw_arc(Vector2(633,CABIN_WINDOW_Y),9,0,TAU,24,LIGHT,1.5,true)
		line(c, Vector2(650,287), Vector2(657,287))
	else:
		for panel_index in 4:
			var window_position := cabin_panel_window_position(panel_index)
			c.draw_circle(window_position, 13, SHADE)
			c.draw_arc(window_position, 13, 0, TAU, 32, INK, 1.8, true)
		box(c, Rect2(601,232,65,99), PAPER, INK, 11)
		box(c, Rect2(610,241,47,80), PAPER, LIGHT, 8)
		c.draw_arc(Vector2(633,CABIN_WINDOW_Y), 9, 0, TAU, 24, INK, 1.5, true)
		line(c, Vector2(650,287), Vector2(657,287))
		line(c, Vector2(211,284), Vector2(592,299), LIGHT)
		line(c, Vector2(674,308), Vector2(870,329), LIGHT)
	# Same aft porthole in the interior and exterior views.
	c.draw_circle(TAIL_WINDOW, 11, PAPER)
	c.draw_arc(TAIL_WINDOW, 11, 0, TAU, 32, LIGHT if cutaway else INK, 1.8, true)
	# Near wing is ghosted in cutaway mode to leave the cabin readable.
	var wing_ink := LIGHT if cutaway else INK
	box(c, Rect2(289,128,245,18), PAPER, wing_ink, 8)
	line(c, Vector2(304,138), Vector2(518,138), LIGHT, 1)
	if not cutaway:
		line(c, Vector2(335,147), Vector2(358,320), INK, 3)
		line(c, Vector2(497,147), Vector2(481,320), INK, 3)
		line(c, Vector2(342,149), Vector2(478,318), LIGHT, 1)
	else:
		# End exactly on the straight sections of the outer fuselage roof.
		var front_attach_y := lerpf(178.0, 189.0, (343.0 - 313.0) / (370.0 - 313.0))
		var rear_attach_y := lerpf(189.0, 230.0, (491.0 - 370.0) / (706.0 - 370.0))
		line(c,Vector2(335,146),Vector2(343,front_attach_y),INK,1.5)
		line(c,Vector2(497,146),Vector2(491,rear_attach_y),INK,1.5)
	box(c, Rect2(319,320,203,16), PAPER, wing_ink, 7)
	# Horizontal tailplane.
	poly(c, rounded(PackedVector2Array([Vector2(819,318), Vector2(901,309), Vector2(949,318), Vector2(952,326), Vector2(891,333), Vector2(820,328)])))
	line(c, Vector2(842,323), Vector2(935,323), LIGHT, 1)
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
