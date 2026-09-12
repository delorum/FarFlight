extends RefCounted
## Shared echoes: enlarging the scope reveals the same weather, not extra data.
const RANGE_KM := 30.0
const ECHO_ZONES := [
	{"threshold":0.0, "color":Color(0.72,0.76,0.20,0.40)},
	{"threshold":0.35, "color":Color(0.94,0.65,0.10,0.72)},
	{"threshold":0.70, "color":Color(0.88,0.16,0.11,0.82)},
]

static func _circle(center: Vector2, radius: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in steps:
		var angle := TAU*step/steps
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	return points

static func draw_echoes(canvas: CanvasItem, world, flight, center: Vector2, radius: float, range_km: float = RANGE_KM) -> void:
	var boundary := _circle(center,radius,96)
	# Draw weak returns first across ALL storms, so they cannot hide a red core.
	for zone in ECHO_ZONES:
		for storm in world.storms:
			var relative: Vector2 = (world.storm_position(storm)-flight.position_km).rotated(-deg_to_rad(flight.heading_deg))
			if relative.length() > range_km+float(storm.radius_km)*1.2:
				continue
			var lobes: Array = world.storm_lobes(storm)
			for lobe in lobes:
				var peak: float = float(storm.intensity)*float(lobe.strength)
				if peak <= float(zone.threshold):
					continue
				var ratio := 1.0 if float(zone.threshold) <= 0.0 else sqrt(1.0-float(zone.threshold)/peak)
				var offset: Vector2 = Vector2(lobe.offset_km).rotated(-deg_to_rad(flight.heading_deg))
				var echo_center := center+(relative+offset)/range_km*radius
				var echo_radius: float = float(storm.radius_km)*float(lobe.radius_scale)*ratio/range_km*radius
				var distance := center.distance_to(echo_center)
				if distance >= radius+echo_radius:
					continue
				if distance+echo_radius <= radius:
					canvas.draw_circle(echo_center,echo_radius,zone.color)
				else:
					for clipped in Geometry2D.intersect_polygons(_circle(echo_center,echo_radius,48),boundary):
						if clipped.size() >= 3:
							canvas.draw_colored_polygon(clipped,zone.color)

static func scope_radius(rect: Rect2) -> float:
	return maxf(1.0, minf((rect.size.y-112)*0.5,(rect.size.x-280)*0.5))

static func scope_center(rect: Rect2) -> Vector2:
	return Vector2(rect.position.x+(rect.size.x-220)*0.5,rect.position.y+62+scope_radius(rect))

static func clip_segment(a: Vector2, b: Vector2, center: Vector2, radius: float) -> PackedVector2Array:
	var direction := b - a
	var length_squared := direction.length_squared()
	if length_squared < 0.000001:
		return PackedVector2Array([a,b]) if a.distance_to(center) <= radius else PackedVector2Array()
	var relative := a - center
	var projection := relative.dot(direction)
	var discriminant := projection * projection - length_squared * (relative.length_squared() - radius * radius)
	if discriminant < 0.0:
		return PackedVector2Array()
	var root := sqrt(discriminant)
	var start := maxf(0.0, (-projection - root) / length_squared)
	var end := minf(1.0, (-projection + root) / length_squared)
	return PackedVector2Array([a + direction * start, a + direction * end]) if start <= end else PackedVector2Array()

static func draw_large(canvas: CanvasItem, rect: Rect2, world, flight, echoes: Texture2D = null, range_km: float = RANGE_KM) -> void:
	var font := ThemeDB.fallback_font
	var text_color := Color("b8c5c8")
	canvas.draw_rect(rect,Color("071012"))
	canvas.draw_rect(rect,Color("6f7f85"),false,2)
	canvas.draw_string(font,rect.position+Vector2(20,29),"МЕТЕОРАДАР [B]",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-40,19,text_color)
	if not flight.engine_running:
		return
	var radius := scope_radius(rect)
	var center := scope_center(rect)
	var grid := Color("375353")
	canvas.draw_circle(center,radius,Color("091a1b"))
	if echoes != null:
		canvas.draw_set_transform(center, -deg_to_rad(flight.heading_deg))
		canvas.draw_texture_rect(echoes, Rect2(Vector2.ONE * -radius, Vector2.ONE * radius * 2.0), false)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		draw_echoes(canvas,world,flight,center,radius,range_km)
	for angle_deg in range(0,360,30):
		var direction := Vector2(sin(deg_to_rad(angle_deg)),-cos(deg_to_rad(angle_deg)))
		canvas.draw_line(center+direction*14,center+direction*radius,Color(0.28,0.43,0.43,0.4),1,true)
		var mark := center+direction*(radius+17)
		canvas.draw_string(font,mark+Vector2(-18,4),"%03d°" % angle_deg,HORIZONTAL_ALIGNMENT_CENTER,36,11,text_color)
	var ring_step := 5 if range_km >= 20.0 else (2 if range_km >= 10.0 else 1)
	for ring_km in range(ring_step,int(range_km)+1,ring_step):
		var ring_radius := radius*ring_km/range_km
		canvas.draw_arc(center,ring_radius,0,TAU,120,grid,1,true)
		canvas.draw_string(font,center+Vector2(6,-ring_radius+13),"%d км" % ring_km,HORIZONTAL_ALIGNMENT_LEFT,55,11,text_color)
	canvas.draw_colored_polygon(PackedVector2Array([center+Vector2(0,-11),center+Vector2(3,-2),center+Vector2(10,3),center+Vector2(2,3),center+Vector2(2,8),center+Vector2(0,6),center+Vector2(-2,8),center+Vector2(-2,3),center+Vector2(-10,3),center+Vector2(-3,-2)]),Color("dfcd84"))
	var legend := Vector2(rect.end.x-204,rect.position.y+198)
	for index in 3:
		canvas.draw_rect(Rect2(legend+Vector2(0,index*27-10),Vector2(10,10)),ECHO_ZONES[index].color)
		canvas.draw_string(font,legend+Vector2(18,index*27),["Слабые осадки","Сильные осадки","Грозовое ядро"][index],HORIZONTAL_ALIGNMENT_LEFT,169,12,text_color)
	canvas.draw_string(font,Vector2(rect.position.x+20,rect.end.y-16),"ЛКМ: точка / линия • тянуть точку: изменить • ПКМ: отменить / стереть • [B]: карта",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-40,12,text_color)

static func draw_map_button(canvas: CanvasItem, rect: Rect2) -> void:
	# A paper-map icon, deliberately without aircraft position or live navigation.
	canvas.draw_rect(rect,Color("d7d0ad"))
	canvas.draw_rect(rect,Color("8b8263"),false,1.5)
	for fraction in [0.33,0.66]:
		var x: float = rect.position.x+rect.size.x*fraction
		canvas.draw_line(Vector2(x,rect.position.y+18),Vector2(x,rect.end.y-4),Color("b9b08b"),1)
	for row in 3:
		var points := PackedVector2Array()
		for step in 24:
			var u := step/23.0
			points.append(rect.position+Vector2(5+u*(rect.size.x-10),28+row*10+sin(u*TAU+row*0.7)*4))
		canvas.draw_polyline(points,Color("968260"),1,true)
	canvas.draw_string(ThemeDB.fallback_font,rect.position+Vector2(7,13),"КАРТА [B]",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-14,10,Color("5c5138"))
