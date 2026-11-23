extends RefCounted

const VerticalSpace = preload("res://vertical_space.gd")
const CLIP_ITERATIONS := 12
const POSITION_TOLERANCE := 0.000001


static func plan(
	space: VerticalSpace, start: Vector3, surface: int, offset: Vector3, distance_limit: float,
	radius: float, actor_height: float, actors: Array[Vector3]
) -> Dictionary:
	var direct := _legal_path(space, start, surface, offset, distance_limit, radius, actor_height, actors)
	if not direct.is_empty():
		return direct

	var best := _clip_path(space, start, surface, offset, distance_limit, radius, actor_height, actors)
	if absf(offset.x) <= POSITION_TOLERANCE or absf(offset.z) <= POSITION_TOLERANCE:
		return best

	# Keep the available sideways motion when one part of a diagonal runs into cover.
	var best_progress := _progress(best, start, offset)
	for slide: Vector3 in [Vector3(offset.x, 0, 0), Vector3(0, 0, offset.z)]:
		var path := _clip_path(space, start, surface, slide, distance_limit, radius, actor_height, actors)
		var progress := _progress(path, start, offset)
		if progress > best_progress:
			best_progress = progress
			best = path
	return best


static func _clip_path(
	space: VerticalSpace, start: Vector3, surface: int, offset: Vector3, distance_limit: float,
	radius: float, actor_height: float, actors: Array[Vector3]
) -> Dictionary:
	var best := _legal_path(space, start, surface, offset, distance_limit, radius, actor_height, actors)
	if not best.is_empty():
		return best
	var low := 0.0
	var high := 1.0
	for _iteration in range(CLIP_ITERATIONS):
		var fraction := (low + high) * 0.5
		var candidate := _legal_path(space, start, surface, offset * fraction, distance_limit, radius, actor_height, actors)
		if candidate.is_empty():
			high = fraction
		else:
			low = fraction
			best = candidate
	return best


static func _legal_path(
	space: VerticalSpace, start: Vector3, surface: int, offset: Vector3, distance_limit: float,
	radius: float, actor_height: float, actors: Array[Vector3]
) -> Dictionary:
	var path := space.advance(start, surface, start + offset, radius)
	if path.is_empty():
		return {}
	var previous := start
	var traveled := 0.0
	for waypoint: Vector3 in path["waypoints"]:
		if VerticalSpace.crosses_actors(previous, waypoint, radius * 2.0, actor_height, actors):
			return {}
		traveled += previous.distance_to(waypoint)
		previous = waypoint
		if traveled > distance_limit + POSITION_TOLERANCE:
			return {}
	path["distance"] = traveled
	return path


static func _progress(path: Dictionary, start: Vector3, offset: Vector3) -> float:
	if path.is_empty():
		return 0.0
	var end: Vector3 = path["position"]
	return (end - start).dot(offset)
