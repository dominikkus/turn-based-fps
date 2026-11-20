extends Node3D

const HALF_EXTENT := 0.475
const EDGE_WIDTH := 0.013
const FLOOR_LIFT := 0.007
const LINE_COLOR := Color(0.47, 0.71, 0.68, 0.56)


func _init() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = LINE_COLOR
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var outer := HALF_EXTENT
	var inner := outer - EDGE_WIDTH
	_add_strip(mesh, -outer, -outer, outer, -inner)
	_add_strip(mesh, -outer, inner, outer, outer)
	_add_strip(mesh, -outer, -inner, -inner, inner)
	_add_strip(mesh, inner, -inner, outer, inner)
	mesh.surface_end()

	var outline := MeshInstance3D.new()
	outline.mesh = mesh
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)
	hide()


func show_tile(center: Vector3, slope: Vector2, cell_scale: float) -> void:
	# The basis keeps the strip flat in tile coordinates and maps it to the ramp plane.
	var tile_basis := Basis(
		Vector3(1.0, slope.x, 0.0) * cell_scale,
		Vector3.UP * cell_scale,
		Vector3(0.0, slope.y, 1.0) * cell_scale
	)
	var pose := Transform3D(tile_basis, center + Vector3.UP * (FLOOR_LIFT * cell_scale))
	if is_inside_tree():
		if global_transform != pose:
			global_transform = pose
	else:
		transform = pose
	show()


func _add_strip(mesh: ImmediateMesh, left: float, near: float, right: float, far: float) -> void:
	var a := Vector3(left, 0.0, near)
	var b := Vector3(right, 0.0, near)
	var c := Vector3(right, 0.0, far)
	var d := Vector3(left, 0.0, far)
	for point in [a, b, c, a, c, d]:
		mesh.surface_add_vertex(point)
