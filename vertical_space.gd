extends RefCounted

const SIDES := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const EDGE_TOLERANCE := 0.00001

var _cell_scale: float
var _half_extent: Vector2
var _centers: Array[Vector3] = []
var _slopes: Array[Vector2] = []
var _stories: Array[int] = []
var _tiles: Array[Vector2i] = []
var _surfaces_at_tile: Dictionary = {}
var _links: Array[Dictionary] = []


func _init(size: Vector2i, cell_scale: float, surfaces: Array[Dictionary], pillars: Array[Vector2i]) -> void:
	_cell_scale = cell_scale
	_half_extent = Vector2(size) * cell_scale * 0.5
	var blocked: Dictionary = {}
	for tile in pillars:
		blocked[tile] = true
	for surface in surfaces:
		var tile: Vector2i = surface["tile"]
		var slope: Vector2 = surface["slope"]
		var story: int = surface["story"]
		if story == 0 and slope == Vector2.ZERO and blocked.has(tile):
			continue
		var x := (float(tile.x) + 0.5 - float(size.x) * 0.5) * cell_scale
		var z := (float(tile.y) + 0.5 - float(size.y) * 0.5) * cell_scale
		if not _surfaces_at_tile.has(tile):
			_surfaces_at_tile[tile] = []
		_surfaces_at_tile[tile].append(_centers.size())
		_centers.append(Vector3(x, surface["height"], z))
		_slopes.append(slope)
		_stories.append(story)
		_tiles.append(tile)
		_links.append({})
	for id in range(_centers.size()):
		for direction: Vector2i in SIDES:
			for neighbor: int in _surfaces_at_tile.get(_tiles[id] + direction, []):
				if _edges_align(id, neighbor, direction):
					_links[id][direction] = neighbor
					break


func surface_count() -> int:
	return _centers.size()


func surface_center(id: int) -> Vector3:
	return _centers[id]


func surface_slope(id: int) -> Vector2:
	return _slopes[id]


func neighbor_in_direction(id: int, direction: Vector2i) -> int:
	return _links[id].get(direction, -1)


static func flat_surfaces(size: Vector2i) -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	for row in range(size.y):
		for column in range(size.x):
			surfaces.append({"tile": Vector2i(column, row), "story": 0, "height": 0.0, "slope": Vector2.ZERO})
	return surfaces


func story(id: int) -> int:
	return _stories[id] if id >= 0 else 0


func neighbors(id: int) -> Array[int]:
	var result: Array[int] = []
	result.assign(_links[id].values())
	return result


func surface_at(point: Vector3) -> int:
	var grid_position := (Vector2(point.x, point.z) + _half_extent) / _cell_scale
	var tile := Vector2i(grid_position.floor())
	for id: int in _surfaces_at_tile.get(tile, []):
		if absf(_height_at(id, Vector2(point.x, point.z)) - point.y) <= _cell_scale * EDGE_TOLERANCE:
			return id
	return -1


func advance(start: Vector3, surface_id: int, horizontal_end: Vector3, radius: float) -> Dictionary:
	if surface_id < 0 or surface_id >= _centers.size():
		return {}
	var origin := Vector2(start.x, start.z)
	var end := Vector2(horizontal_end.x, horizontal_end.z)
	var delta := end - origin
	var cursor := 0.0
	var current := surface_id
	var half := _cell_scale * 0.5
	var direction_x := Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
	var direction_z := Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP
	var waypoints: Array[Vector3] = []
	var crossings := ceili((absf(delta.x) + absf(delta.y)) / _cell_scale) + 3
	for _index in range(crossings):
		var center := _centers[current]
		var edge_x := INF
		var edge_z := INF
		if delta.x != 0.0:
			edge_x = (center.x + half * direction_x.x - origin.x) / delta.x
		if delta.y != 0.0:
			edge_z = (center.z + half * direction_z.y - origin.y) / delta.y
		var reached := clampf(minf(edge_x, edge_z), cursor, 1.0)
		var contact := origin + delta * reached
		if not _has_clearance(current, origin + delta * cursor, contact, radius):
			return {}
		var grounded := Vector3(contact.x, _height_at(current, contact), contact.y)
		if reached > cursor or waypoints.is_empty():
			waypoints.append(grounded)
		if reached >= 1.0:
			return {"position": grounded, "surface": current, "waypoints": waypoints}
		if absf(edge_x - edge_z) <= EDGE_TOLERANCE:
			current = _diagonal_neighbor(current, direction_x, direction_z)
		else:
			var side := direction_x if edge_x < edge_z else direction_z
			current = _links[current].get(side, -1)
		if current < 0:
			return {}
		cursor = reached
	return {}


static func crosses_actors(
	start: Vector3, end: Vector3, spacing: float, height: float, actors: Array[Vector3]
) -> bool:
	var start_xz := Vector2(start.x, start.z)
	var travel := Vector2(end.x, end.z) - start_xz
	var length_squared := travel.length_squared()
	var lift := end.y - start.y
	for actor in actors:
		var low := 0.0
		var high := 1.0
		if lift == 0.0:
			if absf(start.y - actor.y) >= height:
				continue
		else:
			var lower := (actor.y - height - start.y) / lift
			var upper := (actor.y + height - start.y) / lift
			low = maxf(0.0, minf(lower, upper))
			high = minf(1.0, maxf(lower, upper))
			if low >= high:
				continue
		var offset := Vector2(actor.x, actor.z) - start_xz
		var phase := clampf(offset.dot(travel) / length_squared, low, high) if length_squared > 0.0 else low
		if offset.distance_squared_to(travel * phase) < spacing * spacing:
			return true
	return false


func _height_at(id: int, point: Vector2) -> float:
	var center := _centers[id]
	return center.y + _slopes[id].dot(point - Vector2(center.x, center.z))


func _edges_align(id: int, neighbor: int, direction: Vector2i) -> bool:
	var edge := Vector2(direction) * _cell_scale * 0.5
	var tangent := Vector2(-direction.y, direction.x) * _cell_scale * 0.5
	var tolerance := _cell_scale * EDGE_TOLERANCE
	var leading := _centers[id].y + _slopes[id].dot(edge)
	var trailing := _centers[neighbor].y + _slopes[neighbor].dot(-edge)
	var slope_difference := (_slopes[id] - _slopes[neighbor]).dot(tangent)
	return (
		absf(leading - trailing + slope_difference) <= tolerance
		and absf(leading - trailing - slope_difference) <= tolerance
	)


func _diagonal_neighbor(id: int, x: Vector2i, z: Vector2i) -> int:
	var along_x: int = _links[id].get(x, -1)
	var along_z: int = _links[id].get(z, -1)
	if along_x < 0 or along_z < 0:
		return -1
	var diagonal: int = _links[along_x].get(z, -1)
	return diagonal if diagonal == _links[along_z].get(x, -1) else -1


func _has_clearance(id: int, start: Vector2, end: Vector2, radius: float) -> bool:
	var center := Vector2(_centers[id].x, _centers[id].z)
	var half := _cell_scale * 0.5
	var clearance := maxf(0.0, radius - _cell_scale * EDGE_TOLERANCE)
	var links := _links[id]
	for side: Vector2i in SIDES:
		if not links.has(side):
			var direction := Vector2(side)
			var reach := maxf((start - center).dot(direction), (end - center).dot(direction))
			if reach > half - clearance:
				return false
	# A body can touch a missing diagonal tile while its center stays on an open tile.
	for x in [Vector2i.LEFT, Vector2i.RIGHT]:
		for z in [Vector2i.UP, Vector2i.DOWN]:
			if links.has(x) and links.has(z) and _diagonal_neighbor(id, x, z) < 0:
				var corner := center + Vector2(x + z) * half
				var closest := Geometry2D.get_closest_point_to_segment(corner, start, end)
				if closest.distance_squared_to(corner) < clearance * clearance:
					return false
	return true
