extends RefCounted

const ArenaLayout = preload("res://arena_layout.gd")
const STORY_HEIGHT_CELLS := 1.9
const MIN_STORIES := 2
const MAX_STORIES := 10


static func roll(
	width: int, depth: int, cell_scale: float, enemy_count: int, body_radius: float,
	rng: RandomNumberGenerator, pillar_count: int, stories: int,
) -> Dictionary:
	var error := _validate(width, depth, cell_scale, enemy_count, body_radius)
	if not error.is_empty():
		return {"error": error}
	if stories < MIN_STORIES or stories > MAX_STORIES:
		return {"error": "Multi-story layouts support %d to %d stories." % [MIN_STORIES, MAX_STORIES]}
	if pillar_count < 0 or pillar_count >= width * depth - 3:
		return {"error": "Leave at least four ground tiles for the ramp and its landing."}

	var along_z := depth > width or (depth == width and rng.randi_range(0, 1) == 0)
	var run_space := maxi(width, depth)
	var across_space := mini(width, depth)
	var max_run := mini(4, mini(run_space - 2, width * depth - pillar_count - 1))
	var run := rng.randi_range(3, max_run)
	var end_margin := 2 if run_space >= run + 4 else 1
	var first := rng.randi_range(end_margin, run_space - run - end_margin)
	var low_landing := first - 1
	var high_landing := first + run
	var lane_band := floori(float(across_space - 3) / 3.0)
	var lanes := Vector2i(rng.randi_range(0, lane_band), rng.randi_range(across_space - 1 - lane_band, across_space - 1))
	var bounds := Rect2i(0, 0, width, depth)

	var ground_ramp := {}
	for step in range(run):
		ground_ramp[_tile(lanes.x, first + step, along_z)] = true
	var ground_landing := _tile(lanes.x, low_landing, along_z)
	var ground := _ground_layout(bounds, ground_ramp, ground_landing, pillar_count, rng)
	var pillars: Array[Vector2i] = ground["pillars"]
	var surfaces: Array[Dictionary] = []
	for tile: Vector2i in ground["tiles"]:
		surfaces.append(_surface(tile, 0, 0.0, Vector2.ZERO))

	var story_height := STORY_HEIGHT_CELLS * cell_scale
	for story in range(1, stories):
		# Successive ramps reverse direction, so the two landings share a bridge row.
		var at_high_end := story % 2 == 1
		var bridge_row := high_landing if at_high_end else low_landing
		var away := 1 if at_high_end else -1
		for tile in _deck_tiles(lanes, bridge_row, away, across_space, run_space, along_z, rng):
			surfaces.append(_surface(tile, story, story * story_height, Vector2.ZERO))
	for story in range(stories - 1):
		var forward := story % 2 == 0
		var lane := lanes.x if forward else lanes.y
		var gradient := STORY_HEIGHT_CELLS / float(run) * (1.0 if forward else -1.0)
		var slope := Vector2(0.0, gradient) if along_z else Vector2(gradient, 0.0)
		for step in range(run):
			var along := first + (step if forward else run - step - 1)
			var height := (story + (float(step) + 0.5) / float(run)) * story_height
			surfaces.append(_surface(_tile(lane, along, along_z), story, height, slope))

	return _spawn(surfaces, pillars, bounds.size, cell_scale, enemy_count, rng)


static func respawn(
	layout: Dictionary, width: int, depth: int, cell_scale: float, enemy_count: int,
	body_radius: float, rng: RandomNumberGenerator,
) -> Dictionary:
	var error := _validate(width, depth, cell_scale, enemy_count, body_radius)
	if not error.is_empty():
		return {"error": error}
	var surfaces: Array[Dictionary] = layout["surfaces"]
	var pillars: Array[Vector2i] = layout["pillars"]
	return _spawn(surfaces, pillars, Vector2i(width, depth), cell_scale, enemy_count, rng)


static func _validate(width: int, depth: int, cell_scale: float, enemy_count: int, body_radius: float) -> String:
	if mini(width, depth) < 3 or maxi(width, depth) < 5:
		return "Multi-story layouts need at least a 3 × 5 grid in either orientation."
	if float(width) * float(depth) > ArenaLayout.MAX_GRID_TILES:
		return "This prototype supports up to %d grid tiles per footprint." % ArenaLayout.MAX_GRID_TILES
	if not is_finite(cell_scale) or cell_scale <= 0.0:
		return "Cell scale must be finite and greater than zero."
	var extent := Vector3(width * cell_scale, MAX_STORIES * STORY_HEIGHT_CELLS * cell_scale, depth * cell_scale)
	if not extent.is_finite() or extent.x <= 0.0 or extent.y <= 0.0 or extent.z <= 0.0:
		return "Those dimensions are outside the arena's drawing range."
	if enemy_count < 0 or enemy_count > ArenaLayout.MAX_ENEMIES:
		return "Enemy count must be between 0 and %d." % ArenaLayout.MAX_ENEMIES
	if not is_finite(body_radius) or body_radius < 0.0 or body_radius > cell_scale * 0.5:
		return "The player and enemies must fit inside a grid tile."
	return ""


static func _ground_layout(
	bounds: Rect2i, ramp: Dictionary, landing: Vector2i, pillar_count: int, rng: RandomNumberGenerator,
) -> Dictionary:
	var parents := {landing: landing}
	var child_counts := {}
	var frontier: Array[Vector2i] = [landing]
	while not frontier.is_empty():
		var tile := _take_tile(frontier, rng.randi_range(0, frontier.size() - 1))
		var children := 0
		for direction: Vector2i in ArenaLayout.NEIGHBORS:
			var neighbor := tile + direction
			if bounds.has_point(neighbor) and not ramp.has(neighbor) and not parents.has(neighbor):
				parents[neighbor] = tile
				frontier.append(neighbor)
				children += 1
		child_counts[tile] = children

	var leaves: Array[Vector2i] = []
	for tile: Vector2i in parents:
		if tile != landing and child_counts[tile] == 0:
			leaves.append(tile)
	var pillars: Array[Vector2i] = []
	for _index in range(pillar_count):
		# Keep the root landing open and only remove leaves of its connected tree.
		var slot := rng.randi_range(0, leaves.size() - 1)
		if not pillars.is_empty() and rng.randf() < ArenaLayout.CLUSTER_CHANCE:
			var last: Vector2i = pillars.back()
			var adjacent: Array[Vector2i] = []
			for direction: Vector2i in ArenaLayout.NEIGHBORS:
				var neighbor := last + direction
				if neighbor != landing and parents.has(neighbor) and child_counts[neighbor] == 0:
					adjacent.append(neighbor)
			if not adjacent.is_empty():
				slot = leaves.find(adjacent[rng.randi_range(0, adjacent.size() - 1)])
		var tile := _take_tile(leaves, slot)
		var parent: Vector2i = parents[tile]
		parents.erase(tile)
		child_counts[parent] -= 1
		if parent != landing and child_counts[parent] == 0:
			leaves.append(parent)
		pillars.append(tile)
	return {"tiles": parents.keys(), "pillars": pillars}


static func _deck_tiles(
	lanes: Vector2i, bridge_row: int, away: int, across_space: int, run_space: int,
	along_z: bool, rng: RandomNumberGenerator,
) -> Array:
	var deck := {}
	for across in range(lanes.x, lanes.y + 1):
		deck[_tile(across, bridge_row, along_z)] = true
	var depth_limit := run_space - 1 - bridge_row if away > 0 else bridge_row
	for lane: int in [lanes.x, lanes.y]:
		var left_edge := maxi(0, lane - rng.randi_range(1, 3))
		var right_edge := mini(across_space - 1, lane + rng.randi_range(1, 3))
		var platform_depth := mini(depth_limit, rng.randi_range(1, 3))
		for across in range(left_edge, right_edge + 1):
			for step in range(platform_depth + 1):
				deck[_tile(across, bridge_row + away * step, along_z)] = true
	return deck.keys()


static func _spawn(
	surfaces: Array[Dictionary], pillars: Array[Vector2i], size: Vector2i, cell_scale: float,
	enemy_count: int, rng: RandomNumberGenerator,
) -> Dictionary:
	var flat_surfaces: Array[Dictionary] = []
	for surface in surfaces:
		if surface["slope"] == Vector2.ZERO:
			flat_surfaces.append(surface)
	if flat_surfaces.size() <= enemy_count:
		return {"error": "Only %d flat spawn tiles are available. Lower the enemy or pillar count." % flat_surfaces.size()}
	var player := _spawn_position(flat_surfaces, size, cell_scale, rng)
	var enemies: Array[Vector3] = []
	for _index in range(enemy_count):
		enemies.append(_spawn_position(flat_surfaces, size, cell_scale, rng))
	return {"surfaces": surfaces, "pillars": pillars, "player": player, "enemies": enemies}


static func _spawn_position(
	flat_surfaces: Array[Dictionary], size: Vector2i, cell_scale: float, rng: RandomNumberGenerator,
) -> Vector3:
	var index := rng.randi_range(0, flat_surfaces.size() - 1)
	var surface := flat_surfaces[index]
	flat_surfaces[index] = flat_surfaces.back()
	flat_surfaces.pop_back()
	var tile: Vector2i = surface["tile"]
	var center := (Vector2(tile) + Vector2(0.5, 0.5) - Vector2(size) * 0.5) * cell_scale
	return Vector3(center.x, surface["height"], center.y)


static func _surface(tile: Vector2i, story: int, height: float, slope: Vector2) -> Dictionary:
	return {"tile": tile, "story": story, "height": height, "slope": slope}


static func _tile(across: int, along: int, along_z: bool) -> Vector2i:
	return Vector2i(across, along) if along_z else Vector2i(along, across)


static func _take_tile(tiles: Array[Vector2i], index: int) -> Vector2i:
	var tile := tiles[index]
	tiles[index] = tiles.back()
	tiles.pop_back()
	return tile
