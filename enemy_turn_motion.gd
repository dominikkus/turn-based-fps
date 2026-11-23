extends RefCounted

const SECONDS_PER_CELL := 0.18
const MAX_DURATION := 0.70

var _routes: Dictionary = {}
var _duration := 0.0
var _elapsed := 0.0


func _init(origins: Dictionary, plans: Dictionary, cell_scale: float) -> void:
	assert(is_finite(cell_scale) and cell_scale > 0.0)
	var longest := 0.0
	for index in plans:
		if not origins.has(index):
			continue
		var points: Array[Vector3] = [origins[index]]
		var distances := PackedFloat64Array([0.0])
		var length := 0.0
		for destination: Vector3 in plans[index]["waypoints"]:
			var start: Vector3 = points.back()
			var leg := start.distance_to(destination)
			if leg > 0.0:
				length += leg
				points.append(destination)
				distances.append(length)
		if length > 0.0:
			_routes[index] = {"points": points, "distances": distances}
			longest = maxf(longest, length)
	if longest > 0.0:
		_duration = clampf(SECONDS_PER_CELL * longest / cell_scale, SECONDS_PER_CELL, MAX_DURATION)


func is_empty() -> bool:
	return _routes.is_empty()


func advance(delta: float) -> Dictionary:
	if is_empty():
		return {}
	_elapsed = minf(_duration, _elapsed + maxf(delta, 0.0))
	var progress := smoothstep(0.0, 1.0, _elapsed / _duration)
	var positions := {}
	for index in _routes:
		var route: Dictionary = _routes[index]
		positions[index] = _position_at(route["points"], route["distances"], progress)
	return positions


func finished() -> bool:
	return _elapsed >= _duration


static func reserve_path(start: Vector3, waypoints: Array[Vector3], spacing: float) -> Array[Vector3]:
	assert(is_finite(spacing) and spacing > 0.0)
	var samples: Array[Vector3] = []
	for destination in waypoints:
		var length := start.distance_to(destination)
		if length <= 0.0:
			continue
		var steps := ceili(length / spacing)
		for step in range(1, steps):
			samples.append(start.lerp(destination, float(step) / float(steps)))
		samples.append(destination)
		start = destination
	return samples


static func _position_at(points: Array[Vector3], distances: PackedFloat64Array, progress: float) -> Vector3:
	var travel := distances[-1] * progress
	for index in range(1, points.size()):
		if travel == distances[index]:
			return points[index]
		if travel < distances[index]:
			var fraction := inverse_lerp(distances[index - 1], distances[index], travel)
			return points[index - 1].lerp(points[index], fraction)
	return points[-1]
