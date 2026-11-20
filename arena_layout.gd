extends RefCounted

const MAX_GRID_TILES := 4096
const MAX_ENEMIES := 700
const CLUSTER_CHANCE := 0.75
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func roll(
	width: int,
	depth: int,
	cell_scale: float,
	enemy_count: int,
	body_radius: float,
	rng: RandomNumberGenerator,
	pillar_count: int = 0,
	spawn_centered: bool = false,
) -> Dictionary:
	var error := _validate(width, depth, cell_scale, enemy_count, body_radius, pillar_count)
	if not error.is_empty():
		return {"error": error}
	if pillar_count == 0:
		return respawn(width, depth, cell_scale, enemy_count, body_radius, rng, [], spawn_centered)

	var bounds := Rect2i(0, 0, width, depth)
	var tree := _grow_spanning_tree(bounds, rng)
	var leaves: Array[Vector2i] = []
	var leaf_slots: Dictionary[Vector2i, int] = {}
	for tile in tree:
		if tree[tile].size() == 1:
			leaf_slots[tile] = leaves.size()
			leaves.append(tile)

	# Removing a leaf preserves a path between every pair of remaining open tiles.
	var pillars: Array[Vector2i] = []
	for _index in range(pillar_count):
		var tile := _choose_leaf(leaves, leaf_slots, pillars, rng)
		var slot := leaf_slots[tile]
		leaf_slots[leaves.back()] = slot
		_take_tile(leaves, slot)
		leaf_slots.erase(tile)

		var branch: Vector2i = tree[tile][0]
		tree[branch].erase(tile)
		if tree[branch].size() == 1:
			leaf_slots[branch] = leaves.size()
			leaves.append(branch)
		tree.erase(tile)
		pillars.append(tile)

	var open_tiles: Array[Vector2i] = []
	open_tiles.assign(tree.keys())
	return _spawn(open_tiles, pillars, bounds.size, cell_scale, enemy_count, body_radius, rng, spawn_centered)


static func respawn(
	width: int,
	depth: int,
	cell_scale: float,
	enemy_count: int,
	body_radius: float,
	rng: RandomNumberGenerator,
	pillars: Array[Vector2i],
	spawn_centered: bool = false,
) -> Dictionary:
	var error := _validate(width, depth, cell_scale, enemy_count, body_radius, pillars.size())
	if not error.is_empty():
		return {"error": error}
	var bounds := Rect2i(0, 0, width, depth)
	var blocked := {}
	for tile in pillars:
		if not bounds.has_point(tile) or blocked.has(tile):
			return {"error": "A retained pillar tile is out of bounds or duplicated."}
		blocked[tile] = true
	var open_tiles: Array[Vector2i] = []
	for row in range(depth):
		for column in range(width):
			var tile := Vector2i(column, row)
			if not blocked.has(tile):
				open_tiles.append(tile)
	return _spawn(open_tiles, pillars.duplicate(), bounds.size, cell_scale, enemy_count, body_radius, rng, spawn_centered)


static func _validate(
	width: int, depth: int, cell_scale: float, enemy_count: int, body_radius: float, pillar_count: int,
) -> String:
	if width < 1 or depth < 1 or not is_finite(cell_scale) or cell_scale <= 0.0:
		return "Enter positive grid dimensions and a finite cell scale."
	if float(width) * float(depth) > MAX_GRID_TILES:
		return "This prototype supports up to %d grid tiles." % MAX_GRID_TILES
	if enemy_count < 0 or enemy_count > MAX_ENEMIES:
		return "Enemy count must be between 0 and %d." % MAX_ENEMIES
	if pillar_count < 0 or pillar_count >= width * depth - enemy_count:
		return "Leave at least one open tile for the player and one for each enemy."
	if not is_finite(body_radius) or body_radius < 0.0 or body_radius > cell_scale * 0.5:
		return "The player and enemies must fit inside a grid tile."
	var arena_size := Vector2(width * cell_scale, depth * cell_scale)
	if not arena_size.is_finite() or arena_size.x <= 0.0 or arena_size.y <= 0.0:
		return "Those dimensions are outside the arena's drawing range."
	return ""


static func _grow_spanning_tree(bounds: Rect2i, rng: RandomNumberGenerator) -> Dictionary:
	var root := Vector2i(rng.randi_range(0, bounds.size.x - 1), rng.randi_range(0, bounds.size.y - 1))
	var tree := {root: []}
	var frontier: Array[Vector2i] = [root]
	while not frontier.is_empty():
		var tile := _take_tile(frontier, rng.randi_range(0, frontier.size() - 1))
		for direction: Vector2i in NEIGHBORS:
			var neighbor := tile + direction
			if bounds.has_point(neighbor) and not tree.has(neighbor):
				tree[neighbor] = [tile]
				tree[tile].append(neighbor)
				frontier.append(neighbor)
	return tree


static func _choose_leaf(
	leaves: Array[Vector2i],
	leaf_slots: Dictionary[Vector2i, int],
	pillars: Array[Vector2i],
	rng: RandomNumberGenerator,
) -> Vector2i:
	if not pillars.is_empty() and rng.randf() < CLUSTER_CHANCE:
		var last: Vector2i = pillars.back()
		var nearby: Array[Vector2i] = []
		for direction: Vector2i in NEIGHBORS:
			if leaf_slots.has(last + direction):
				nearby.append(last + direction)
		if not nearby.is_empty():
			return nearby[rng.randi_range(0, nearby.size() - 1)]
	return leaves[rng.randi_range(0, leaves.size() - 1)]


static func _spawn(
	open_tiles: Array[Vector2i],
	pillars: Array[Vector2i],
	size: Vector2i,
	cell_scale: float,
	enemy_count: int,
	body_radius: float,
	rng: RandomNumberGenerator,
	spawn_centered: bool,
) -> Dictionary:
	var footprint := Vector2(size) * cell_scale
	# Leave room for Vector3 precision at the outer edge of the arena.
	var padding := maxf(footprint.x, footprint.y) * 0.0000001
	var jitter := 0.0 if spawn_centered else maxf(0.0, cell_scale * 0.5 - body_radius - padding)
	var player_tile := _take_tile(open_tiles, rng.randi_range(0, open_tiles.size() - 1))
	var player := _spawn_position(player_tile, size, cell_scale, jitter, rng)
	var enemies: Array[Vector3] = []
	for _index in range(enemy_count):
		var tile := _take_tile(open_tiles, rng.randi_range(0, open_tiles.size() - 1))
		enemies.append(_spawn_position(tile, size, cell_scale, jitter, rng))
	return {"player": player, "enemies": enemies, "pillars": pillars}


static func _take_tile(tiles: Array[Vector2i], index: int) -> Vector2i:
	var tile := tiles[index]
	tiles[index] = tiles.back()
	tiles.pop_back()
	return tile


static func _spawn_position(
	tile: Vector2i, size: Vector2i, cell_scale: float, jitter: float, rng: RandomNumberGenerator,
) -> Vector3:
	var x := (float(tile.x) + 0.5 - float(size.x) * 0.5) * cell_scale
	var z := (float(tile.y) + 0.5 - float(size.y) * 0.5) * cell_scale
	if jitter > 0.0:
		x += lerpf(-jitter, jitter, rng.randf())
		z += lerpf(-jitter, jitter, rng.randf())
	return Vector3(x, 0.0, z)
