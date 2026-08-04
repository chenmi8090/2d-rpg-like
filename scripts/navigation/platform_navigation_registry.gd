class_name PlatformNavigationRegistry
extends Node

var _surfaces: Dictionary = {}
var _links: Dictionary = {}


func _ready() -> void:
	add_to_group("platform_navigation_registry")


func clear() -> void:
	_surfaces.clear()
	_links.clear()


func register_surface(id: StringName, left_x: float, right_x: float, top_y: float, one_way: bool, is_ground := false) -> void:
	_surfaces[id] = PlatformNavigationSurface.new(id, left_x, right_x, top_y, one_way, is_ground)
	if not _links.has(id):
		_links[id] = []


func add_bidirectional_link(first: StringName, second: StringName) -> void:
	_add_link(first, second)
	_add_link(second, first)


func _add_link(from_id: StringName, to_id: StringName) -> void:
	if not _surfaces.has(from_id) or not _surfaces.has(to_id):
		return
	var neighbors: Array = _links.get(from_id, [])
	if to_id not in neighbors:
		neighbors.append(to_id)
	_links[from_id] = neighbors


func get_surface(id: StringName) -> PlatformNavigationSurface:
	return _surfaces.get(id) as PlatformNavigationSurface


func get_surface_at_position(position: Vector2, x_margin := 0.0, y_tolerance := 16.0) -> PlatformNavigationSurface:
	var best: PlatformNavigationSurface
	var best_distance := INF
	for surface in _surfaces.values():
		var candidate := surface as PlatformNavigationSurface
		if candidate.contains_feet(position, x_margin, y_tolerance):
			var distance := absf(position.y - candidate.top_y)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func find_path(from_id: StringName, to_id: StringName) -> Array[StringName]:
	var empty: Array[StringName] = []
	if not _surfaces.has(from_id) or not _surfaces.has(to_id):
		return empty
	if from_id == to_id:
		return [from_id]

	var queue: Array[StringName] = [from_id]
	var previous: Dictionary = {from_id: &""}
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		for neighbor_value in _links.get(current, []):
			var neighbor := StringName(neighbor_value)
			if previous.has(neighbor):
				continue
			previous[neighbor] = current
			if neighbor == to_id:
				var path: Array[StringName] = [to_id]
				var step: StringName = current
				while step != &"":
					path.push_front(step)
					step = StringName(previous.get(step, &""))
				return path
			queue.append(neighbor)
	return empty


func find_nearest_route(from_id: StringName, to_id: StringName, start_x: float, target_x: float, margin := 0.0) -> Dictionary:
	if not _surfaces.has(from_id) or not _surfaces.has(to_id):
		return {}
	if from_id == to_id:
		return {
			"surface_ids": [from_id],
			"cost": absf(start_x - target_x),
			"first_transition_x": start_x,
			"first_entry_x": start_x,
			"first_direction": signf(target_x - start_x),
			"first_kind": &"walk",
		}
	var paths: Array[Array] = []
	_collect_simple_paths(from_id, to_id, [from_id], paths)
	var best: Dictionary = {}
	for path_value in paths:
		var candidate := _evaluate_surface_path(path_value, start_x, target_x, margin)
		if not candidate.is_empty() and _route_is_better(candidate, best, start_x, target_x):
			best = candidate
	return best


func _collect_simple_paths(current: StringName, target: StringName, path: Array[StringName], results: Array[Array]) -> void:
	if current == target:
		results.append(path.duplicate())
		return
	for neighbor_value in _links.get(current, []):
		var neighbor := StringName(neighbor_value)
		if neighbor in path:
			continue
		var next_path := path.duplicate()
		next_path.append(neighbor)
		_collect_simple_paths(neighbor, target, next_path, results)


func _evaluate_surface_path(path: Array, start_x: float, target_x: float, margin: float) -> Dictionary:
	var states: Array[Dictionary] = [{"x": start_x, "cost": 0.0}]
	for index in range(path.size() - 1):
		var current := get_surface(StringName(path[index]))
		var next := get_surface(StringName(path[index + 1]))
		if current == null or next == null:
			return {}
		var expanded: Array[Dictionary] = []
		for state in states:
			for transition in _transition_candidates(current, next, float(state.x), margin):
				var candidate := state.duplicate()
				candidate.x = float(transition.entry_x)
				candidate.cost = float(state.cost) + float(transition.cost)
				if index == 0:
					candidate.first_transition_x = float(transition.transition_x)
					candidate.first_entry_x = float(transition.entry_x)
					candidate.first_direction = float(transition.direction)
					candidate.first_kind = StringName(transition.kind)
				expanded.append(candidate)
		states = expanded
		if states.is_empty():
			return {}
	var target_surface := get_surface(StringName(path[-1]))
	var best_state: Dictionary = {}
	for state in states:
		var total := float(state.cost) + absf(float(state.x) - target_surface.clamp_safe_x(target_x, margin))
		var candidate := state.duplicate()
		candidate.cost = total
		candidate.surface_ids = path.duplicate()
		if best_state.is_empty() or total < float(best_state.cost) - 0.5:
			best_state = candidate
	return best_state


func _transition_candidates(current: PlatformNavigationSurface, next: PlatformNavigationSurface, current_x: float, margin: float) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if next.top_y < current.top_y - 8.0:
		var overlap_left := maxf(current.safe_left_x(margin), next.safe_left_x(margin))
		var overlap_right := minf(current.safe_right_x(margin), next.safe_right_x(margin))
		var launch_x := 0.0
		var entry_x := 0.0
		if overlap_left <= overlap_right:
			launch_x = clampf(current_x, overlap_left, overlap_right)
			entry_x = launch_x
		elif next.center_x() > current.center_x():
			launch_x = current.safe_right_x(margin)
			entry_x = next.safe_left_x(margin)
		else:
			launch_x = current.safe_left_x(margin)
			entry_x = next.safe_right_x(margin)
		candidates.append({
			"transition_x": launch_x,
			"entry_x": entry_x,
			"direction": signf(entry_x - launch_x),
			"kind": &"jump",
			"cost": absf(current_x - launch_x) + absf(entry_x - launch_x) + 12.0,
		})
		return candidates
	for edge_x in current.get_safe_drop_edge_candidates(margin):
		var entry_x := next.clamp_safe_x(edge_x, margin)
		var direction := -1.0 if is_equal_approx(edge_x, current.safe_left_x(margin)) else 1.0
		candidates.append({
			"transition_x": edge_x,
			"entry_x": entry_x,
			"direction": direction,
			"kind": &"drop",
			"cost": absf(current_x - edge_x) + absf(entry_x - edge_x) + 4.0,
		})
	return candidates


func _route_is_better(candidate: Dictionary, current_best: Dictionary, start_x: float, target_x: float) -> bool:
	if current_best.is_empty():
		return true
	var candidate_cost := float(candidate.cost)
	var best_cost := float(current_best.cost)
	if candidate_cost < best_cost - 0.5:
		return true
	if candidate_cost > best_cost + 0.5:
		return false
	var candidate_path: Array = candidate.surface_ids
	var best_path: Array = current_best.surface_ids
	if candidate_path.size() != best_path.size():
		return candidate_path.size() < best_path.size()
	var candidate_first := absf(float(candidate.first_transition_x) - start_x)
	var best_first := absf(float(current_best.first_transition_x) - start_x)
	if not is_equal_approx(candidate_first, best_first):
		return candidate_first < best_first
	var target_direction := signf(target_x - start_x)
	if float(candidate.first_direction) == target_direction and float(current_best.first_direction) != target_direction:
		return true
	return false


func get_surface_count() -> int:
	return _surfaces.size()


func has_link(from_id: StringName, to_id: StringName) -> bool:
	return to_id in _links.get(from_id, [])
