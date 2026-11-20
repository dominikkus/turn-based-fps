extends Node3D

const VerticalArenaView = preload("res://vertical_arena_view.gd")
const BODY_RADIUS_CELLS := 0.20
const EYE_HEIGHT_CELLS := 0.76
const BODY_HEIGHT_CELLS := 0.84
const TARGET_LAYER := 1
const PILLAR_LAYER := 2
const PILLAR_HEIGHT_CELLS := 1.65
const GRID_COLOR := Color("40636c")
const EDGE_COLOR := Color("78c9c7")
const PREVIEW_LINES_PER_AXIS := 120

var enemy_markers: Array[Node3D] = []
var enemy_labels: Array[Label3D] = []
var enemy_bodies: Array[StaticBody3D] = []
var _level: Node3D


func rebuild(width: int, depth: int, cell_scale: float, enemy_positions: Array[Vector3],
		pillar_tiles: Array[Vector2i] = []) -> void:
	_begin_rebuild()
	var footprint := Vector2(width, depth) * cell_scale
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = footprint
	_add_mesh(_level, floor_mesh, Vector3.ZERO, _material(Color("152b36")))
	_add_grid(width, depth, cell_scale, footprint * 0.5)
	_add_pillars(pillar_tiles, width, depth, cell_scale)
	for spawn in enemy_positions:
		_add_enemy(spawn, cell_scale)


func rebuild_vertical(width: int, depth: int, cell_scale: float, enemy_positions: Array[Vector3],
		pillar_tiles: Array[Vector2i], surfaces: Array[Dictionary]) -> void:
	_begin_rebuild()
	if not surfaces.is_empty():
		var structure := VerticalArenaView.build(width, depth, cell_scale, surfaces, PILLAR_LAYER)
		_level.add_child(structure)
		structure.force_update_transform()
	_add_pillars(pillar_tiles, width, depth, cell_scale)
	for spawn in enemy_positions:
		_add_enemy(spawn, cell_scale)


func _begin_rebuild() -> void:
	if _level != null:
		remove_child(_level)
		_level.queue_free()
	_level = Node3D.new()
	add_child(_level)
	enemy_markers.clear()
	enemy_labels.clear()
	enemy_bodies.clear()


func _add_pillars(tiles: Array[Vector2i], width: int, depth: int, cell_scale: float) -> void:
	if tiles.is_empty():
		return
	var size := Vector3(1.0, PILLAR_HEIGHT_CELLS, 1.0) * cell_scale
	var shape := BoxShape3D.new()
	shape.size = size
	var sections: Array[BoxMesh] = [
		_pillar_section(cell_scale, 0.93, Color("435861")),
		_pillar_section(cell_scale, 0.05, Color("8cc6bc")),
		_pillar_section(cell_scale, 0.60, Color("4b666b")),
		_pillar_section(cell_scale, PILLAR_HEIGHT_CELLS - 1.58, Color("789597")),
	]
	for tile in tiles:
		var pillar := StaticBody3D.new()
		pillar.collision_layer = PILLAR_LAYER
		pillar.collision_mask = 0
		pillar.position = Vector3(tile.x + 0.5 - width * 0.5, 0.0,
				tile.y + 0.5 - depth * 0.5) * cell_scale
		_level.add_child(pillar)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = size.y * 0.5
		pillar.add_child(collider)
		pillar.force_update_transform()
		var section_y := 0.0
		for mesh in sections:
			_add_mesh(pillar, mesh, Vector3.UP * (section_y + mesh.size.y * 0.5), null)
			section_y += mesh.size.y


func _pillar_section(cell_scale: float, height_cells: float, color: Color) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, height_cells, 1.0) * cell_scale
	var material := _material(color, false)
	material.roughness = 0.9
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	return mesh


func _add_grid(width: int, depth: int, cell_scale: float, half_size: Vector2) -> void:
	var lines := ImmediateMesh.new()
	var material := _material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var y := cell_scale * 0.003
	var column_stride := ceili(float(width) / PREVIEW_LINES_PER_AXIS)
	for column in range(column_stride, width, column_stride):
		var x := column * cell_scale - half_size.x
		_add_line(lines, Vector3(x, y, -half_size.y), Vector3(x, y, half_size.y), GRID_COLOR)
	var row_stride := ceili(float(depth) / PREVIEW_LINES_PER_AXIS)
	for row in range(row_stride, depth, row_stride):
		var z := row * cell_scale - half_size.y
		_add_line(lines, Vector3(-half_size.x, y, z), Vector3(half_size.x, y, z), GRID_COLOR)
	var corners := [
		Vector3(-half_size.x, y, -half_size.y),
		Vector3(half_size.x, y, -half_size.y),
		Vector3(half_size.x, y, half_size.y),
		Vector3(-half_size.x, y, half_size.y),
	]
	for index in range(corners.size()):
		_add_line(lines, corners[index], corners[(index + 1) % corners.size()], EDGE_COLOR)
	lines.surface_end()
	_add_mesh(_level, lines, Vector3.ZERO, null)


func _add_enemy(spawn: Vector3, cell_scale: float) -> void:
	var enemy := Node3D.new()
	_level.add_child(enemy)
	enemy.position = spawn
	var body := CapsuleMesh.new()
	body.radial_segments = 16
	body.rings = 6
	body.radius = BODY_RADIUS_CELLS * cell_scale
	body.height = BODY_HEIGHT_CELLS * cell_scale
	var material := _material(Color("d26d4c"), false)
	var center := Vector3.UP * body.height * 0.5
	_add_mesh(enemy, body, center, material)
	var hitbox := StaticBody3D.new()
	hitbox.collision_layer = TARGET_LAYER
	hitbox.collision_mask = 0
	hitbox.set_meta("enemy_index", enemy_markers.size())
	enemy.add_child(hitbox)
	var capsule := CapsuleShape3D.new()
	capsule.radius = body.radius
	capsule.height = body.height
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position = center
	hitbox.add_child(collider)
	hitbox.force_update_transform()

	var band := CylinderMesh.new()
	band.radial_segments = 16
	band.top_radius = body.radius * 1.02
	band.bottom_radius = band.top_radius
	band.height = cell_scale * 0.065
	_add_mesh(enemy, band, Vector3.UP * body.height * 0.68, _material(Color("ffe3ab")))

	var label := Label3D.new()
	label.position = Vector3.UP * cell_scale * 1.04
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.modulate = Color("ffe5d7")
	label.outline_size = 5
	label.font_size = 32
	label.pixel_size = 0.0012
	label.text = "Enemy %d" % (enemy_markers.size() + 1)
	enemy.add_child(label)
	enemy_markers.append(enemy)
	enemy_labels.append(label)
	enemy_bodies.append(hitbox)


func remove_enemy(index: int) -> void:
	enemy_markers[index].hide()
	enemy_bodies[index].collision_layer = 0


func draw_tracer(start: Vector3, end: Vector3, color: Color, cell_scale: float) -> void:
	var span := end - start
	if span.length_squared() < 0.00000001 * cell_scale * cell_scale:
		return
	var streak := CylinderMesh.new()
	streak.top_radius = cell_scale * 0.003
	streak.bottom_radius = streak.top_radius
	streak.height = span.length()
	streak.radial_segments = 3
	streak.rings = 0
	var tracer := MeshInstance3D.new()
	tracer.mesh = streak
	tracer.material_override = _material(color)
	tracer.basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	tracer.position = (start + end) * 0.5
	_level.add_child(tracer)
	get_tree().create_timer(0.12).timeout.connect(tracer.queue_free)


func _material(color: Color, unshaded: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_mesh(parent: Node3D, mesh: Mesh, local_position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = local_position
	parent.add_child(instance)


func _add_line(lines: ImmediateMesh, start: Vector3, end: Vector3, color: Color) -> void:
	lines.surface_set_color(color)
	lines.surface_add_vertex(start)
	lines.surface_set_color(color)
	lines.surface_add_vertex(end)
