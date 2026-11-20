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
) -> Dictionary:
	var shot_steps: int = stats["move_cells_with_shot"]
	var walking_steps: int = stats["move_cells_without_shot"]
	var base_accuracy: float = stats["base_accuracy"]
	var best_chance := _hit_chance(enemy, player, cell_scale, stats, sight)
	var best_shot := enemy_surface
	var next_angle := -1
	var next_angle_chance := 0.0
	var parents: Dictionary = {}
	var steps: Dictionary = {enemy_surface: 0}
	var reachable: Array[int] = [enemy_surface]

	var can_improve_shot := shot_steps > 0 and best_chance < base_accuracy
	var needs_walking_route := walking_steps > 0 and best_chance == 0.0
	if enemy_surface >= 0 and (can_improve_shot or needs_walking_route):
		var actors := blockers.duplicate()
		actors.append(player)
		var body_height := ArenaView.BODY_HEIGHT_CELLS * cell_scale
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
				if steps.has(neighbor):
					continue
				var destination: Vector3 = space.surface_center(neighbor)
				if not _can_step(position, surface, destination, neighbor, minimum_spacing, body_height, actors, space):
					continue
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
		waypoints.append(space.surface_center(final_surface))
	return {
		"waypoints": waypoints, "surface": final_surface,
		"fires": best_chance > 0.0, "chance": best_chance, "damage": int(stats["damage"]),
	}


static func _can_step(
	start: Vector3, start_surface: int, end: Vector3, end_surface: int, spacing: float,
	body_height: float, actors: Array[Vector3], space: Object,
) -> bool:
	var leg: Dictionary = space.advance(start, start_surface, end, spacing * 0.5)
	if leg.is_empty() or leg["surface"] != end_surface:
		return false
	var previous := start
	for point: Vector3 in leg["waypoints"]:
		if VerticalSpace.crosses_actors(previous, point, spacing, body_height, actors):
			return false
		previous = point
	return previous == end or not VerticalSpace.crosses_actors(previous, end, spacing, body_height, actors)


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
