extends Control
class_name BusPathOverlay
## White circle showing the bus's circular route on the minimap.
##
## minimap.gd computes the polyline points (already in this node's local
## coordinates) each update and pushes them here with set_path(). Drawing on a
## separate overlay node keeps the line above the minimap background texture,
## which would otherwise cover a _draw() on the Minimap control itself.

var _points: PackedVector2Array = PackedVector2Array()
var _color: Color = Color(1, 1, 1, 1)
var _width: float = 2.0

func set_path(points: PackedVector2Array, color: Color, width: float) -> void:
	_points = points
	_color = color
	_width = width
	queue_redraw()

func _draw() -> void:
	if _points.is_empty():
		return
	draw_polyline(_points, _color, _width, true)