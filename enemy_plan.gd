extends RefCounted

const NEIGHBORS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const MAX_SEARCH_CELLS := 4096


static func plan(
	enemy: Vector3,
	player: Vector3,
	blockers: Array[Vector3],
	step_length: float,
	minimum_spacing: float,
	stats: Dictionary,
	cover: Object = null,
) -> Dictionary:
	if cover != null and cover.has_pillars():
		return _plan_with_cover(enemy, player, blockers, step_length, minimum_spacing, stats, cover)

	var move_with_shot: int = stats["move_cells_with_shot"]
	var move_without_shot: int = stats["move_cells_without_shot"]
	var best_chance := _shot_chance(enemy, player, step_length, stats)
	var best_shot_steps := 0
	var waypoints: Array[Vector3] = []
	var position := enemy

	for step in range(maxi(move_with_shot, move_without_shot)):
		var next := _advance(position, player, blockers, step_length, minimum_spacing)
		if next == position:
			break
		waypoints.append(next)
		position = next
		if step < move_with_shot:
			var chance := _shot_chance(position, player, step_length, stats)
			if chance > best_chance:
				best_chance = chance
				best_shot_steps = step + 1

	var fires := best_chance > 0.0
	if fires:
		waypoints.resize(best_shot_steps)
	else:
		waypoints.resize(mini(move_without_shot, waypoints.size()))
	return {"waypoints": waypoints, "fires": fires, "chance": best_chance, "damage": int(stats["damage"])}


static func _plan_with_cover(
	enemy: Vector3,
	player: Vector3,
	blockers: Array[Vector3],
	step_length: float,
	minimum_spacing: float,
	stats: Dictionary,
	cover: Object,
) -> Dictionary:
	var shot_budget: float = stats["move_cells_with_shot"] * step_length
	var route_budget: float = stats["move_cells_without_shot"] * step_length
	var body_radius := minimum_spacing * 0.5
	var direct_distance := enemy.distance_to(player)
	var direct_goal := _advance(enemy, player, blockers, direct_distance, minimum_spacing)
	var straight_route := bool(cover.can_walk(enemy, direct_goal, body_radius))
	var shot_end := _limit_segment(enemy, direct_goal, shot_budget)
	var walk_end := _limit_segment(enemy, direct_goal, route_budget)
	if not straight_route:
		shot_end = _stop_at_cover(enemy, shot_end, body_radius, cover)
		walk_end = _stop_at_cover(enemy, walk_end, body_radius, cover)

	var shot := {"cell": null, "point": enemy, "cost": 0.0, "chance": 0.0}
	_consider_shot(shot, null, enemy, 0.0, player, step_length, stats, cover)
	_consider_shot(shot, null, shot_end, enemy.distance_to(shot_end), player, step_length, stats, cover)
	var route := {"cell": null, "point": walk_end, "cost": enemy.distance_to(walk_end)}
	var parents: Dictionary = {}
	var already_optimal: bool = shot["chance"] >= float(stats["base_accuracy"]) and shot["chance"] > 0.0
	var reaches_player := direct_goal.distance_to(player) <= minimum_spacing + step_length * 0.0001
	# An unobstructed straight approach is already shortest and minimizes firing distance.
	if not already_optimal and not (straight_route and reaches_player and not cover.blocks_sight(shot_end, player)):
		_search_cover(enemy, player, blockers, minimum_spacing, step_length, stats, cover,
			shot_budget, route_budget, shot, route, parents)

	var fires: bool = shot["chance"] > 0.0
	var choice := shot if fires else route
	var waypoints := _build_waypoints(enemy, choice, shot_budget if fires else route_budget, parents, cover)
	var chance := 0.0
	if fires:
		var end: Vector3 = enemy if waypoints.is_empty() else waypoints.back()
		if not cover.blocks_sight(end, player):
			chance = _shot_chance(end, player, step_length, stats)
		if chance <= 0.0:
			waypoints = _build_waypoints(enemy, route, route_budget, parents, cover)
	return {"waypoints": waypoints, "fires": chance > 0.0, "chance": chance, "damage": int(stats["damage"])}


static func _search_cover(
	enemy: Vector3,
	player: Vector3,
	blockers: Array[Vector3],
	minimum_spacing: float,
	step_length: float,
	stats: Dictionary,
	cover: Object,
	shot_budget: float,
	route_budget: float,
	shot: Dictionary,
	route: Dictionary,
	parents: Dictionary,
) -> void:
	var center_cell: Vector2i = cover.cell_at(enemy)
	var costs: Dictionary = {}
	var open: Array[Vector2i] = []
	for x in range(-1, 2):
		for z in range(-1, 2):
			var cell := center_cell + Vector2i(x, z)
			if not cover.is_open(cell):
				continue
			var center: Vector3 = cover.cell_center(cell)
			if not _clear_segment(enemy, center, player, blockers, minimum_spacing, cover):
				continue
			var cost := enemy.distance_to(center)
			if cost <= shot_budget:
				_consider_shot(shot, cell, center, cost, player, step_length, stats, cover)
			elif shot_budget > 0.0:
				var point := _limit_segment(enemy, center, shot_budget)
				_consider_shot(shot, null, point, enemy.distance_to(point), player, step_length, stats, cover)
			costs[cell] = cost
			parents[cell] = null
			open.append(cell)

	for visited in range(MAX_SEARCH_CELLS):
		if open.is_empty():
			break
		var best := 0
		for index in range(1, open.size()):
			if costs[open[index]] < costs[open[best]]:
				best = index
		var cell := open[best]
		open.remove_at(best)
		var traveled: float = costs[cell]
		if shot["chance"] > 0.0 and traveled > shot_budget:
			break
		var center: Vector3 = cover.cell_center(cell)
		if traveled <= shot_budget:
			_consider_shot(shot, cell, center, traveled, player, step_length, stats, cover)
			var shot_approach := _advance(center, player, blockers, shot_budget - traveled, minimum_spacing)
			if cover.can_walk(center, shot_approach, minimum_spacing * 0.5):
				_consider_shot(shot, cell, shot_approach, traveled + center.distance_to(shot_approach),
					player, step_length, stats, cover)
		if route_budget > 0.0:
			_consider_route(route, cell, center, traveled, player)
			var approach := _advance(center, player, blockers, center.distance_to(player), minimum_spacing)
			if cover.can_walk(center, approach, minimum_spacing * 0.5):
				_consider_route(route, cell, approach, traveled + center.distance_to(approach), player)
			var goal: Vector3 = route["point"]
			if traveled >= shot_budget and goal.distance_to(player) <= minimum_spacing + step_length * 0.0001:
				if traveled >= float(route["cost"]):
					break
		elif traveled >= shot_budget:
			break

		for direction in NEIGHBORS:
			var next_cell: Vector2i = cell + direction
			if not cover.is_open(next_cell):
				continue
			var next: Vector3 = cover.cell_center(next_cell)
			var cost := traveled + center.distance_to(next)
			if cost >= float(costs.get(next_cell, INF)):
				continue
			if not _clear_segment(center, next, player, blockers, minimum_spacing, cover):
				continue
			if traveled < shot_budget and cost > shot_budget:
				var point := _limit_segment(center, next, shot_budget - traveled)
				_consider_shot(shot, cell, point, shot_budget, player, step_length, stats, cover)
			if not costs.has(next_cell):
				open.append(next_cell)
			costs[next_cell] = cost
			parents[next_cell] = cell


static func _consider_shot(
	shot: Dictionary,
	cell: Variant,
	point: Vector3,
	cost: float,
	player: Vector3,
	step_length: float,
	stats: Dictionary,
	cover: Object,
) -> void:
	var chance := _shot_chance(point, player, step_length, stats)
	if chance <= 0.0 or chance < float(shot["chance"]):
		return
	if chance == float(shot["chance"]) and cost >= float(shot["cost"]):
		return
	if not cover.blocks_sight(point, player):
		shot.merge({"cell": cell, "point": point, "cost": cost, "chance": chance}, true)


static func _consider_route(route: Dictionary, cell: Vector2i, point: Vector3, cost: float, player: Vector3) -> void:
	var current: Vector3 = route["point"]
	var current_distance := current.distance_squared_to(player)
	var distance := point.distance_squared_to(player)
	if distance < current_distance or (is_equal_approx(distance, current_distance) and cost < float(route["cost"])):
		route.merge({"cell": cell, "point": point, "cost": cost}, true)


static func _build_waypoints(
	origin: Vector3, choice: Dictionary, budget: float, parents: Dictionary, cover: Object
) -> Array[Vector3]:
	var path: Array[Vector3] = [choice["point"]]
	var cell: Variant = choice["cell"]
	while cell != null:
		path.append(cover.cell_center(cell))
		cell = parents[cell]
	path.reverse()
	var waypoints: Array[Vector3] = []
	for point in path:
		var leg := origin.distance_to(point)
		if leg == 0.0:
			continue
		if leg > budget:
			if budget > 0.0:
				waypoints.append(_limit_segment(origin, point, budget))
			break
		waypoints.append(point)
		budget -= leg
		origin = point
	return waypoints


static func _clear_segment(
	start: Vector3, end: Vector3, player: Vector3, blockers: Array[Vector3], minimum_spacing: float, cover: Object
) -> bool:
	if not cover.can_walk(start, end, minimum_spacing * 0.5):
		return false
	var minimum_squared := minimum_spacing * minimum_spacing
	if Geometry3D.get_closest_point_to_segment(player, start, end).distance_squared_to(player) < minimum_squared:
		return false
	for blocker in blockers:
		if Geometry3D.get_closest_point_to_segment(blocker, start, end).distance_squared_to(blocker) < minimum_squared:
			return false
	return true


static func _stop_at_cover(start: Vector3, end: Vector3, radius: float, cover: Object) -> Vector3:
	if cover.can_walk(start, end, radius):
		return end
	# A clear prefix of a segment remains clear when shortened.
	var clear := 0.0
	var blocked := 1.0
	for iteration in range(16):
		var fraction := (clear + blocked) * 0.5
		if cover.can_walk(start, start.lerp(end, fraction), radius):
			clear = fraction
		else:
			blocked = fraction
	return start.lerp(end, clear)


static func _limit_segment(start: Vector3, end: Vector3, distance_limit: float) -> Vector3:
	var length := start.distance_to(end)
	if length > distance_limit:
		return start.lerp(end, distance_limit / length)
	return end


static func _shot_chance(origin: Vector3, player: Vector3, cell_scale: float, stats: Dictionary) -> float:
	var dx: float = player.x - origin.x
	var dz: float = player.z - origin.z
	var distance := sqrt(dx * dx + dz * dz) / cell_scale
	var shot_range: float = stats["range_cells"]
	var full_accuracy_range: float = stats["full_accuracy_cells"]
	var base_accuracy: float = stats["base_accuracy"]
	if distance > shot_range:
		return 0.0
	if distance <= full_accuracy_range:
		return base_accuracy
	return base_accuracy * (shot_range - distance) / (shot_range - full_accuracy_range)


static func _advance(
	origin: Vector3,
	player: Vector3,
	blockers: Array[Vector3],
	step_length: float,
	minimum_spacing: float,
) -> Vector3:
	var dx: float = player.x - origin.x
	var dz: float = player.z - origin.z
	var distance := sqrt(dx * dx + dz * dz)
	if distance <= minimum_spacing:
		return origin
	var direction_x := dx / distance
	var direction_z := dz / distance
	# Keep clamped positions outside the collision boundary after Vector3 rounds them.
	var local_scale := maxf(minf(step_length, distance), maxf(absf(origin.x), absf(origin.z)))
	var precision_padding := local_scale * 0.000001
	var spacing := minimum_spacing + precision_padding
	var movement := minf(step_length, distance - spacing)
	for blocker in blockers:
		var offset_x: float = blocker.x - origin.x
		var offset_z: float = blocker.z - origin.z
		var along := offset_x * direction_x + offset_z * direction_z
		if along <= 0.0:
			continue
		var side := offset_x * direction_z - offset_z * direction_x
		var intersection := spacing * spacing - side * side
		if intersection > 0.0:
			movement = minf(movement, along - sqrt(intersection))
	if movement <= precision_padding:
		return origin
	return Vector3(origin.x + direction_x * movement, origin.y, origin.z + direction_z * movement)
