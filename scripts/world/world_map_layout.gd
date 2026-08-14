class_name WorldMapLayout
extends Node2D

@export var floor_center := Vector2(1450.0, 680.0)
@export var floor_size := Vector2(3000.0, 80.0)
@export var platform_rects: Array[Rect2] = []
@export var background_color := Color("172933")
@export var hill_color := Color("27454b")
@export var accent_color := Color("ecd06b")


func _ready() -> void:
	_build_visuals()


func get_floor_center() -> Vector2:
	return floor_center


func get_floor_size() -> Vector2:
	return floor_size


func get_platform_rects() -> Array[Rect2]:
	return platform_rects.duplicate()


func _build_visuals() -> void:
	var background := ColorRect.new()
	background.offset_left = -4000.0
	background.offset_top = -2000.0
	background.offset_right = 5000.0
	background.offset_bottom = 1200.0
	background.color = background_color
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true
	add_child(background)

	var hills := Polygon2D.new()
	hills.polygon = PackedVector2Array([
		Vector2(-600.0, 590.0), Vector2(-180.0, 350.0), Vector2(220.0, 565.0),
		Vector2(650.0, 310.0), Vector2(1080.0, 575.0), Vector2(1510.0, 330.0),
		Vector2(1960.0, 570.0), Vector2(2380.0, 300.0), Vector2(3060.0, 590.0),
	])
	hills.color = hill_color
	add_child(hills)

	var marker := Polygon2D.new()
	marker.position = Vector2(floor_center.x, 150.0)
	marker.polygon = PackedVector2Array([
		Vector2(-34.0, -34.0), Vector2(34.0, -34.0),
		Vector2(34.0, 34.0), Vector2(-34.0, 34.0),
	])
	marker.color = accent_color
	add_child(marker)
