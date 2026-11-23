extends RefCounted

const ArenaView = preload("res://arena_view.gd")
const VerticalSpace = preload("res://vertical_space.gd")


static func plan(
	enemy: Vector3,
	enemy_surface: int,
	player: Vector3,
	player_surface: int,
	blockers: Array[Vector3],
	cell_scale: float,
	minimum_spacing: float,
	stats: Dictionary,
	space: Object,
	sight: Callable,
	free_move: bool = false,
) -> Dictionary:
	if free_move:
		return _plan_free(enemy, enemy_surface, player, player_surface, blockers, cell_scale,
			minimum_spacing, stats, space, sight)

	var shot_steps: int = stats["move_cells_with_shot"]
	var walking_steps: int = stats["move_cells_without_shot"]
	var base_accuracy: float = stats["base_accuracy"]
	var best_chance := _hit_chance(enemy, player, cell_scale, stats, sight)
	var best_shot := enemy_surface
	var next_angle := -1
	var next_angle_chance := 0.0
	var parents: Dictionary = {}
	var legs: Dictionary = {}
	var steps: Dictionary = {enemy_surface: 0}
	var reachable: Array[int] = [enemy_surface]

	var can_improve_shot := shot_steps > 0 and best_chance < base_accuracy
	var needs_walking_route := walking_steps > 0 and best_chance == 0.0
	if enemy_surface >= 0 and (can_improve_shot or needs_walking_route):
		var actors := blockers.duplicate()
		actors.append(player)
		var footprint := Vector2(minimum_spacing, ArenaView.BODY_HEIGHT_CELLS * cell_scale)
		var current := 0
		while current < reachable.size():
			var surface := reachable[current]
			current += 1
			var distance: int = steps[surface]
			if distance > shot_steps and (best_chance > 0.0 or walking_steps == 0):
				break
			if next_angle >= 0 and distance > shot_steps and distance > int(steps[next_angle]):
				break

			var position: Vector3 = space.surface_center(surface)
			var chance := best_chance if surface == enemy_surface else _hit_chance(position, player, cell_scale, stats, sight)
			if distance <= shot_steps and chance > best_chance:
				best_shot = surface
				best_chance = chance
				# Breadth-first order finds the shortest path to any full-accuracy shot.
				if chance >= base_accuracy:
					break
			elif distance > shot_steps and chance > 0.0:
				if next_angle < 0 or (distance == int(steps[next_angle]) and chance > next_angle_chance):
					next_angle = surface
					next_angle_chance = chance

			for neighbor: int in space.neighbors(surface):
				if neighbor == player_surface or steps.has(neighbor):
					continue
				var destination: Vector3 = space.surface_center(neighbor)
				var leg := _walk_leg(position, surface, destination, footprint, actors, space, neighbor)
				if leg.is_empty():
					continue
				legs[neighbor] = leg["waypoints"]
				parents[neighbor] = surface
				steps[neighbor] = distance + 1
				reachable.append(neighbor)

	var selected := best_shot
	var budget := shot_steps
	if best_chance <= 0.0:
		budget = walking_steps
		if next_angle >= 0:
			selected = next_angle
		elif enemy_surface >= 0 and walking_steps > 0:
			selected = _closest_reached(reachable, player, player_surface, space)

	var route: Array[int] = []
	while selected != enemy_surface:
		route.append(selected)
		selected = parents[selected]
	route.reverse()
	var waypoints: Array[Vector3] = []
	var final_surface := enemy_surface
	for index in range(mini(budget, route.size())):
		final_surface = route[index]
		waypoints.append_array(legs[final_surface])
	return {
		"waypoints": waypoints, "surface": final_surface,
		"fires": best_chance > 0.0, "chance": best_chance, "damage": int(stats["damage"]),
	}


static func _plan_free(
	enemy: Vector3, enemy_surface: int, player: Vector3, player_surface: int,
	blockers: Array[Vector3], cell_scale: float, minimum_spacing: float, stats: Dictionary,
	space: Object, sight: Callable,
) -> Dictionary:
	var shot_budget: float = stats["move_cells_with_shot"] * cell_scale
	var walk_budget: float = stats["move_cells_without_shot"] * cell_scale
	var footprint := Vector2(minimum_spacing, ArenaView.BODY_HEIGHT_CELLS * cell_scale)
	var actors := blockers.duplicate()
	actors.append(player)
	var empty_path: Array[Vector3] = []
	var origin := {"position": enemy, "surface": enemy_surface, "cost": 0.0, "parent": -1,
		"waypoints": empty_path}
	var shot := _prefer_shot({}, origin, player, cell_scale, stats, sight)
	if enemy_surface < 0 or (shot_budget <= 0.0 and walk_budget <= 0.0):
		return _free_result(origin, float(shot.get("chance", 0.0)), stats)
	var direct_shot := _free_approach(origin, player, shot_budget, footprint, actors, space)
	shot = _prefer_shot(shot, direct_shot, player, cell_scale, stats, sight)
	var direct_walk := _free_approach(origin, player, walk_budget, footprint, actors, space)
	var future := _prefer_shot({}, direct_walk, player, cell_scale, stats, sight)

	# A free-moving enemy can start off-center. That position is a separate node from its tile center.
	var origin_id: int = enemy_surface if enemy == space.surface_center(enemy_surface) else -1
	var records: Dictionary = {origin_id: origin}
	var frontier: Array[int] = [origin_id]
	while not frontier.is_empty():
		if not shot.is_empty() and float(shot["chance"]) >= float(stats["base_accuracy"]):
			break
		var current_id := _take_nearest(frontier, records)
		var current: Dictionary = records[current_id]
		var cost: float = current["cost"]
		if cost > shot_budget and (not shot.is_empty() or walk_budget <= 0.0):
			break
		if cost > shot_budget and not future.is_empty() and cost > float(future["cost"]):
			break
		if cost <= shot_budget:
			shot = _prefer_shot(shot, current, player, cell_scale, stats, sight)
			if current_id != origin_id:
				var aim := _free_approach(current, player, shot_budget - cost, footprint, actors, space)
				if not aim.is_empty():
					aim["parent"] = current_id
					shot = _prefer_shot(shot, aim, player, cell_scale, stats, sight)
		elif walk_budget > 0.0:
			var angle := _prefer_shot({}, current, player, cell_scale, stats, sight)
			if not angle.is_empty() and (future.is_empty() or _earlier_angle(angle, future)):
				future = angle

		var position: Vector3 = current["position"]
		var neighbors: Array[int] = space.neighbors(current["surface"])
		if current_id == -1:
			neighbors.append(enemy_surface)
		for neighbor in neighbors:
			var destination: Vector3 = space.surface_center(neighbor)
			var distance := _flat_distance(position, destination)
			var total := cost + distance
			if distance <= 0.0 or (records.has(neighbor) and total >= float(records[neighbor]["cost"])):
				continue
			if cost < shot_budget and total > shot_budget:
				var end := position.lerp(destination, (shot_budget - cost) / distance)
				var partial := _free_prefix(current, end, footprint, actors, space)
				if not partial.is_empty():
					partial["parent"] = current_id
					shot = _prefer_shot(shot, partial, player, cell_scale, stats, sight)
			var leg := _walk_leg(position, current["surface"], destination, footprint, actors, space, neighbor)
			if leg.is_empty():
				continue
			leg["parent"] = current_id
			leg["cost"] = total
			if not records.has(neighbor):
				frontier.append(neighbor)
			records[neighbor] = leg

	if not shot.is_empty():
		var moved := _follow_free_path(origin, shot, records, shot_budget, footprint, actors, space)
		var chance := _hit_chance(moved["position"], player, cell_scale, stats, sight)
		if chance > 0.0:
			return _free_result(moved, chance, stats)
	if walk_budget <= 0.0:
		return _free_result(origin, 0.0, stats)
	var goal := future
	if goal.is_empty():
		goal = _free_route_goal(origin, direct_walk, records, player, player_surface, space)
	return _free_result(_follow_free_path(origin, goal, records, walk_budget, footprint, actors, space), 0.0, stats)


static func _free_result(leg: Dictionary, chance: float, stats: Dictionary) -> Dictionary:
	return {"waypoints": leg["waypoints"], "surface": leg["surface"],
		"fires": chance > 0.0, "chance": chance, "damage": int(stats["damage"])}


static func _take_nearest(frontier: Array[int], records: Dictionary) -> int:
	var best := 0
	for index in range(1, frontier.size()):
		if records[frontier[index]]["cost"] < records[frontier[best]]["cost"]:
			best = index
	var result := frontier[best]
	frontier.remove_at(best)
	return result


static func _prefer_shot(
	best: Dictionary, candidate: Dictionary, player: Vector3, scale: float, stats: Dictionary, sight: Callable,
) -> Dictionary:
	if candidate.is_empty():
		return best
	var chance := _hit_chance(candidate["position"], player, scale, stats, sight)
	var current_chance: float = best.get("chance", 0.0)
	if chance > current_chance or (chance > 0.0 and chance == current_chance and candidate["cost"] < best["cost"]):
		var result := candidate.duplicate()
		result["chance"] = chance
		return result
	return best


static func _earlier_angle(candidate: Dictionary, best: Dictionary) -> bool:
	return candidate["cost"] < best["cost"] or (candidate["cost"] == best["cost"] and candidate["chance"] > best["chance"])


static func _free_route_goal(
	origin: Dictionary, direct: Dictionary, records: Dictionary, player: Vector3, player_surface: int, space: Object,
) -> Dictionary:
	var surface_distances := _surface_distances(player_surface, space) if player_surface >= 0 else {}
	var choices := records.values()
	if not direct.is_empty():
		choices.append(direct)
	var best := origin
	var best_steps: float = surface_distances.get(best["surface"], INF)
	var position: Vector3 = best["position"]
	var best_distance := position.distance_squared_to(player)
	for candidate: Dictionary in choices:
		var steps: float = surface_distances.get(candidate["surface"], INF)
		var point: Vector3 = candidate["position"]
		var distance := point.distance_squared_to(player)
		if steps < best_steps or (steps == best_steps and distance < best_distance):
			best = candidate
			best_steps = steps
			best_distance = distance
	return best


static func _free_approach(
	from: Dictionary, target: Vector3, budget: float, footprint: Vector2, actors: Array[Vector3], space: Object,
) -> Dictionary:
	var origin: Vector3 = from["position"]
	var distance := _flat_distance(origin, target)
	var travel := minf(budget, distance - footprint.x)
	if travel <= 0.0:
		return {}
	return _free_prefix(from, origin.lerp(target, travel / distance), footprint, actors, space)


static func _free_prefix(
	from: Dictionary, end: Vector3, footprint: Vector2, actors: Array[Vector3], space: Object,
) -> Dictionary:
	var start: Vector3 = from["position"]
	var best := _walk_leg(start, from["surface"], end, footprint, actors, space)
	if best.is_empty():
		var clear := 0.0
		var blocked := 1.0
		# Only free movement may use the last legal point before an obstacle or actor.
		for iteration in range(12):
			var fraction := (clear + blocked) * 0.5
			var candidate := _walk_leg(start, from["surface"], start.lerp(end, fraction), footprint, actors, space)
			if candidate.is_empty():
				blocked = fraction
			else:
				clear = fraction
				best = candidate
	if not best.is_empty():
		var distance := _flat_distance(start, best["position"])
		if distance <= 0.0:
			return {}
		best["cost"] = float(from["cost"]) + distance
		best["parent"] = -1
	return best


static func _follow_free_path(
	origin: Dictionary, choice: Dictionary, records: Dictionary, budget: float, footprint: Vector2,
	actors: Array[Vector3], space: Object,
) -> Dictionary:
	var path: Array[Dictionary] = [choice]
	var parent: int = choice["parent"]
	while parent >= 0:
		var node: Dictionary = records[parent]
		path.append(node)
		parent = node["parent"]
	path.reverse()
	var points: Array[Vector3] = []
	var current := origin
	for leg in path:
		var start: Vector3 = current["position"]
		var end: Vector3 = leg["position"]
		var distance := _flat_distance(start, end)
		if distance <= 0.0 or budget <= 0.0:
			continue
		if distance > budget:
			var clipped := _free_prefix(current, start.lerp(end, budget / distance), footprint, actors, space)
			if not clipped.is_empty():
				points.append_array(clipped["waypoints"])
				current = clipped
			break
		points.append_array(leg["waypoints"])
		current = leg
		budget -= distance
	return {"position": current["position"], "surface": current["surface"], "waypoints": points}


static func _flat_distance(start: Vector3, end: Vector3) -> float:
	return Vector2(start.x, start.z).distance_to(Vector2(end.x, end.z))


static func _walk_leg(
	start: Vector3, start_surface: int, end: Vector3, footprint: Vector2,
	actors: Array[Vector3], space: Object, end_surface: int = -1,
) -> Dictionary:
	var leg: Dictionary = space.advance(start, start_surface, end, footprint.x * 0.5)
	if leg.is_empty() or (end_surface >= 0 and leg["surface"] != end_surface):
		return {}
	var points: Array[Vector3] = leg["waypoints"]
	if end_surface >= 0:
		points[-1] = end
		leg["position"] = end
	var previous := start
	var flat := true
	for point in points:
		if VerticalSpace.crosses_actors(previous, point, footprint.x, footprint.y, actors):
			return {}
		flat = flat and point.y == start.y
		previous = point
	if flat:
		# A level straight segment needs only its endpoint. Ramp seams retain their height changes.
		points = [previous]
	leg["waypoints"] = points
	return leg


static func _closest_reached(
	reachable: Array[int], player: Vector3, player_surface: int, space: Object,
) -> int:
	# Graph distance favors a route up a ramp over standing directly beneath the player.
	var distances: Dictionary = {}
	if player_surface >= 0:
		distances = _surface_distances(player_surface, space)
	var closest := reachable[0]
	var closest_steps := INF
	var closest_distance := INF
	for surface in reachable:
		var steps: float = distances.get(surface, INF)
		var center: Vector3 = space.surface_center(surface)
		var squared_distance := center.distance_squared_to(player)
		if steps < closest_steps or (steps == closest_steps and squared_distance < closest_distance):
			closest = surface
			closest_steps = steps
			closest_distance = squared_distance
	return closest


static func _surface_distances(target: int, space: Object) -> Dictionary:
	var queue: Array[int] = [target]
	var distances: Dictionary = {target: 0}
	var current := 0
	while current < queue.size():
		var surface := queue[current]
		current += 1
		for neighbor: int in space.neighbors(surface):
			if not distances.has(neighbor):
				distances[neighbor] = int(distances[surface]) + 1
				queue.append(neighbor)
	return distances


static func _hit_chance(origin: Vector3, target: Vector3, scale: float, stats: Dictionary, sight: Callable) -> float:
	var distance := origin.distance_to(target) / scale
	var maximum: float = stats["range_cells"]
	var full: float = stats["full_accuracy_cells"]
	var base: float = stats["base_accuracy"]
	if base <= 0.0 or distance > maximum or not sight.call(origin, target):
		return 0.0
	if distance <= full:
		return base
	return base * (maximum - distance) / (maximum - full)
