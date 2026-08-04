class_name PlatformNavigationSurface
extends RefCounted

var id: StringName
var left_x := 0.0
var right_x := 0.0
var top_y := 0.0
var one_way := false
var is_ground := false


func _init(surface_id: StringName = &"", left := 0.0, right := 0.0, top := 0.0, surface_one_way := false, surface_is_ground := false) -> void:
	id = surface_id
	left_x = minf(left, right)
	right_x = maxf(left, right)
	top_y = top
	one_way = surface_one_way
	is_ground = surface_is_ground


func contains_feet(position: Vector2, x_margin := 0.0, y_tolerance := 16.0) -> bool:
	var safe_left := left_x + maxf(x_margin, 0.0)
	var safe_right := right_x - maxf(x_margin, 0.0)
	return safe_left <= safe_right and position.x >= safe_left and position.x <= safe_right and absf(position.y - top_y) <= y_tolerance


func center_x() -> float:
	return (left_x + right_x) * 0.5


func safe_left_x(margin := 0.0) -> float:
	var inset := maxf(margin, 0.0)
	return left_x + inset if left_x + inset <= right_x - inset else center_x()


func safe_right_x(margin := 0.0) -> float:
	var inset := maxf(margin, 0.0)
	return right_x - inset if left_x + inset <= right_x - inset else center_x()


func clamp_safe_x(x: float, margin := 0.0) -> float:
	return clampf(x, safe_left_x(margin), safe_right_x(margin))


func get_safe_drop_edge_candidates(margin := 0.0) -> Array[float]:
	var left := safe_left_x(margin)
	var right := safe_right_x(margin)
	if is_equal_approx(left, right):
		return [left]
	return [left, right]
