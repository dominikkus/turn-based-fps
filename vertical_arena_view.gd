extends RefCounted

const THICKNESS_CELLS := 0.12
const CORNERS := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]
const GROUND := Color("1b333f")
const GROUND_LINE := Color("40616a")
const DECK := Color("2f5259")
const DECK_LINE := Color("719c9e")
const RAMP := Color("515c51")
const RAMP_LINE := Color("9baf96")
const RAMP_MARK := Color("f1c080")


static func build(width: int, depth: int, cell_scale: float, surfaces: Array[Dictionary],
		collision_layer: int) -> StaticBody3D:
	var triangles := SurfaceTool.new()
	triangles.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var grid_origin := Vector2(-width * 0.5, -depth * 0.5)
	for surface in surfaces:
		_add_surface(triangles, lines, surface, grid_origin, cell_scale)
	lines.surface_end()
	triangles.set_material(material)
	var slabs := triangles.commit()
	var shape := slabs.create_trimesh_shape()
	shape.backface_collision = true
	var geometry := StaticBody3D.new()
	geometry.name = "FloorsAndRamps"
	geometry.collision_layer = collision_layer
	geometry.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	geometry.add_child(collider)
	for mesh in [slabs, lines]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		geometry.add_child(instance)
	return geometry


static func _add_surface(triangles: SurfaceTool, lines: ImmediateMesh, surface: Dictionary,
		grid_origin: Vector2, cell_scale: float) -> void:
	var tile: Vector2i = surface["tile"]
	var story: int = surface["story"]
	var height: float = surface["height"]
	var slope: Vector2 = surface["slope"]
	var center := (Vector2(tile) + grid_origin + Vector2(0.5, 0.5)) * cell_scale
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var thickness := Vector3.DOWN * (cell_scale * THICKNESS_CELLS)
	for corner in CORNERS:
		var position := (Vector2(tile + corner) + grid_origin) * cell_scale
		var vertex := Vector3(position.x, height + slope.dot(position - center), position.y)
		top.append(vertex)
		bottom.append(vertex + thickness)

	var fill := GROUND if story == 0 else DECK
	var outline := GROUND_LINE if story == 0 else DECK_LINE
	var sloped := not slope.is_zero_approx()
	if sloped:
		fill = RAMP
		outline = RAMP_LINE
	if (tile.x + tile.y) % 2 == 0:
		fill = fill.lightened(0.025)
	_quad(triangles, top[0], top[1], top[2], top[3], fill)
	_quad(triangles, bottom[3], bottom[2], bottom[1], bottom[0], fill.darkened(0.44))
	var line_lift := Vector3.UP * (cell_scale * 0.004)
	for edge in range(4):
		var next := (edge + 1) % 4
		var side_color := outline.darkened(0.27 if edge % 2 == 0 else 0.40)
		_quad(triangles, top[edge], bottom[edge], bottom[next], top[next], side_color)
		_line(lines, top[edge] + line_lift, top[next] + line_lift, outline)
	if sloped:
		_ramp_mark(lines, center, height + line_lift.y, slope, cell_scale)


static func _ramp_mark(lines: ImmediateMesh, center: Vector2, height: float, slope: Vector2,
		cell_scale: float) -> void:
	var forward := slope.normalized() * cell_scale
	var sideways := forward.orthogonal() * 0.15
	var tail := -forward * 0.10
	var tip := _surface_point(center, height, slope, forward * 0.15)
	_line(lines, _surface_point(center, height, slope, tail - sideways), tip, RAMP_MARK)
	_line(lines, _surface_point(center, height, slope, tail + sideways), tip, RAMP_MARK)


static func _surface_point(center: Vector2, height: float, slope: Vector2,
		point: Vector2) -> Vector3:
	return Vector3(center.x + point.x, height + slope.dot(point), center.y + point.y)


static func _quad(mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	mesh.set_color(color)
	for vertex in [a, b, c, a, c, d]:
		mesh.add_vertex(vertex)


static func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
