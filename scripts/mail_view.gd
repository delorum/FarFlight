extends RefCounted
## Post-office rows, scrolling, drawing and clicks share a single layout.
const AircraftArt = preload("res://scripts/aircraft_art.gd")
const EconomyScript = preload("res://scripts/economy.gd")
var host: Control
var scroll := 0

func _init(controller: Control) -> void:
	host = controller

func _has_delivery() -> bool:
	return host.economy.carried_item.get("type", "") == "parcel" and int(host.economy.carried_item.get("destination", -1)) == host.flight.airport_index

func _economy_button_rect(index: int) -> Rect2:
	return host.side_scenes._economy_button_rect(index)

func _delivery_button_text(parcel: Dictionary) -> String:
	return host.side_scenes._delivery_button_text(parcel)

func _draw_menu_button(rect: Rect2, label: String) -> void:
	host.side_scenes._draw_menu_button(rect, label)

func _economy_exit_rect() -> Rect2:
	return Rect2(host.size.x * 0.48, maxf(229.0, host.size.y - 128.0), minf(520.0, host.size.x * 0.46), 48.0)

func _mail_row_count() -> int:
	var delivery := _has_delivery()
	return host.economy.offers_at(host.flight.airport_index).size() + (1 if delivery else 0)

func _mail_visible_rows() -> int:
	return maxi(1, floori((_economy_exit_rect().position.y - 165.0 - 12.0) / 64.0))

func _clamp_scroll() -> void:
	scroll = clampi(scroll, 0, maxi(0, _mail_row_count() - _mail_visible_rows()))

func _mail_row_rect(index: int) -> Rect2:
	if index < scroll or index >= scroll + _mail_visible_rows():
		return Rect2()
	return _economy_button_rect(index - scroll)

func handle_scroll(event: InputEventMouseButton) -> void:
	if not event.pressed or event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	var list_rect := Rect2(_economy_button_rect(0).position, Vector2(_economy_button_rect(0).size.x + 20.0, _economy_exit_rect().position.y - 165.0))
	if list_rect.has_point(event.position):
		scroll += 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		_clamp_scroll()


func draw() -> void:
	_clamp_scroll()
	var mail_status := "ПОСЫЛОК ОСТАЛОСЬ: %d • ПЕРЕХОД ОТКРЫТ" % host.economy.remaining_parcels_at(host.flight.airport_index) if not host.world.exit_portal.is_empty() else "ПОСЫЛОК ОСТАЛОСЬ: %d • ДО НОВОЙ КАРТЫ: %d" % [host.economy.remaining_parcels_at(host.flight.airport_index), maxi(0, EconomyScript.DELIVERIES_TO_UNLOCK_EXIT - host.economy.deliveries_on_map)]
	host.draw_localized_string(ThemeDB.fallback_font, Vector2(host.size.x * 0.48, 147), mail_status, HORIZONTAL_ALIGNMENT_LEFT, host.size.x * 0.46, 13, AircraftArt.INK)
	var row = 0
	if _has_delivery():
		if _mail_row_rect(row).has_area():
			_draw_menu_button(_mail_row_rect(row), _delivery_button_text(host.economy.carried_item))
		row += 1
	for offer in host.economy.offers_at(host.flight.airport_index):
		if not _mail_row_rect(row).has_area():
			row += 1
			continue
		var destination: String = host.world.airports[int(offer.destination)].name
		var poverty_bonus := int(offer.get("poverty_bonus_percent", 0))
		var bonus_text := " • надбавка +%d%%" % poverty_bonus if poverty_bonus > 0 else ""
		_draw_menu_button(_mail_row_rect(row), "%s • маршрут %.0f км • %d монет%s" % [destination, offer.distance_km, host.economy.parcel_reward(offer), bonus_text])
		row += 1
	if _mail_row_count() > _mail_visible_rows():
		var track := Rect2(_economy_button_rect(0).end.x + 8.0, 165.0, 4.0, _mail_visible_rows() * 64.0 - 16.0)
		host.draw_rect(track, Color(AircraftArt.INK, 0.2), true)
		var thumb_height := track.size.y * float(_mail_visible_rows()) / _mail_row_count()
		var thumb_y := track.position.y + (track.size.y - thumb_height) * float(scroll) / (_mail_row_count() - _mail_visible_rows())
		host.draw_rect(Rect2(track.position.x, thumb_y, track.size.x, thumb_height), AircraftArt.INK, true)

func handle_click(position: Vector2) -> void:
	_clamp_scroll()
	var row := 0
	if _has_delivery():
		if _mail_row_rect(row).has_point(position):
			var delivery: Dictionary = host.economy.deliver_carried(host.flight.airport_index)
			if host.economy.deliveries_on_map >= EconomyScript.DELIVERIES_TO_UNLOCK_EXIT and host.world.exit_portal.is_empty():
				host.world.ensure_exit_portal()
				host._queue_map_redraw()
			host.scene_notice = "Доставлено: +%d монет • переход открыт на карте" % delivery.paid if not host.world.exit_portal.is_empty() and host.economy.deliveries_on_map == EconomyScript.DELIVERIES_TO_UNLOCK_EXIT else "Доставлено: +%d монет • %d/16" % [delivery.paid, host.economy.deliveries_on_map]
			return
		row += 1
	var offers: Array = host.economy.offers_at(host.flight.airport_index)
	for index in offers.size():
		if _mail_row_rect(row + index).has_point(position):
			var parcel: Dictionary = host.economy.accept_offer(host.flight.airport_index, index)
			host.scene_notice = "Посылка получена — отнесите её в самолёт" if not parcel.is_empty() else "Сначала освободите руки"
			return
