extends Control

var controller: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if controller != null:
		controller._draw_map_on(self)
