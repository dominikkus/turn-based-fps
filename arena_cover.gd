extends RefCounted

var size: Vector2i
var cell_scale: float
var _half_size: Vector2
var _occupied: Dictionary = {}
var _bounds: Array[Rect2] = []


func _init(grid_size: Vector2i, scale: float, pillars: Array[Vector2i]) -> void:
	size = grid_size
	cell_scale = scale
	_half_size = Vector2(size) * cell_scale * 0.5
	for tile in pillars:
		_occupied[tile] = true
		var corner := Vector2(tile) * cell_scale - _half_size
		_bounds.append(Rect2(corner, Vector2.ONE * cell_scale))


func has_pillars() -> bool:
	return not _bounds.is_empty()


func cell_at(point: Vector3) -> Vector2i:
	return Vector2i(((Vector2(point.x, point.z) + _half_size) / cell_scale).floor())


func cell_center(tile: Vector2i) -> Vector3:
	var center := (Vector2(tile) + Vector2.ONE * 0.5) * cell_scale - _half_size
	return Vector3(center.x, 0.0, center.y)


func is_open(tile: Vector2i) -> bool:
	return (
		tile.x >= 0 and tile.x < size.x and tile.y >= 0 and tile.y < size.y
		and not _occupied.has(tile)
	)


func can_walk(start: Vector3, end: Vector3, radius: float) -> bool:
	var limits := _half_size - Vector2.ONE * radius
	if absf(end.x) > limits.x or absf(end.z) > limits.y:
		return false
	# Permit exact contact without trapping an actor on the edge of a pillar.
	var padding := maxf(0.0, radius - cell_scale * 0.000001)
	return not _crosses_pillar(start, end, padding)


func blocks_sight(start: Vector3, end: Vector3) -> bool:
	return _crosses_pillar(start, end, 0.0)


func _crosses_pillar(start: Vector3, end: Vector3, padding: float) -> bool:
	var origin := Vector2(start.x, start.z)
	var direction := Vector2(end.x, end.z) - origin
	for bounds in _bounds:
		if _intersects(origin, direction, bounds.grow(padding)):
			return true
	return false


func _intersects(origin: Vector2, direction: Vector2, bounds: Rect2) -> bool:
	var enter := 0.0
	var exit := 1.0
	for axis in range(2):
		var lower := bounds.position[axis]
		var upper := bounds.end[axis]
		var movement := direction[axis]
		if movement == 0.0:
			if origin[axis] < lower or origin[axis] > upper:
				return false
			continue
		var first := (lower - origin[axis]) / movement
		var second := (upper - origin[axis]) / movement
		enter = maxf(enter, minf(first, second))
		exit = minf(exit, maxf(first, second))
		if enter > exit:
			return false
	return true
