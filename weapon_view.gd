extends Node3D

const VIEW_SCALE := 0.32
const HOLD_POSITION := Vector3(0.169, -0.152, -0.246)
const HOLD_YAW := PI / 15.0

var _hold := Node3D.new()
var _pistol := Node3D.new()
var _rifle := Node3D.new()
var _pistol_muzzle := Marker3D.new()
var _rifle_muzzle := Marker3D.new()
var _active_index := 0
var _kick_tween: Tween


func _ready() -> void:
	_hold.position = HOLD_POSITION
	_hold.rotation.y = HOLD_YAW
	add_child(_hold)
	_hold.add_child(_pistol)
	_hold.add_child(_rifle)
	_pistol.name = "Pistol"
	_pistol.position.y = 0.023
	_rifle.name = "Rifle"

	var graphite := _material(Color("3c525d"))
	var dark := _material(Color("222b32"))
	var tan := _material(Color("a28868"))
	var accent := _material(Color("8de4dc"), 0.65)
	var glove := _material(Color("776b56"))
	var sleeve := _material(Color("425751"))
	_build_pistol(graphite, dark, accent, glove, sleeve)
	_build_rifle(graphite, dark, tan, accent, glove, sleeve)
	set_weapon(_active_index)


func set_cell_scale(cell_scale: float) -> void:
	scale = Vector3.ONE * cell_scale * VIEW_SCALE


func set_weapon(index: int) -> void:
	_reset_kick()
	_active_index = index
	_pistol.visible = index == 0
	_rifle.visible = index == 1


func muzzle_position() -> Vector3:
	if _active_index == 0:
		return _pistol_muzzle.global_position
	return _rifle_muzzle.global_position


func kick() -> void:
	_reset_kick()
	_hold.position.z += 0.024
	_hold.rotation.x = 0.055
	_kick_tween = create_tween().set_parallel(true)
	_kick_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_kick_tween.tween_property(_hold, "position:z", HOLD_POSITION.z, 0.11)
	_kick_tween.tween_property(_hold, "rotation:x", 0.0, 0.11)


func _reset_kick() -> void:
	if _kick_tween != null:
		_kick_tween.kill()
		_kick_tween = null
	_hold.position = HOLD_POSITION
	_hold.rotation.x = 0.0


func _build_pistol(graphite: Material, dark: Material, accent: Material, glove: Material,
		sleeve: Material) -> void:
	_box(_pistol, Vector3(0, 0.004, -0.036), Vector3(0.059, 0.043, 0.168), graphite)
	_box(_pistol, Vector3(0, -0.023, -0.026), Vector3(0.052, 0.025, 0.134), dark)
	_box(_pistol, Vector3(0, -0.055, 0.021), Vector3(0.044, 0.082, 0.046), dark, 18.0)
	_box(_pistol, Vector3(0, 0.029, -0.101), Vector3(0.010, 0.012, 0.012), accent)
	_box(_pistol, Vector3(0, 0.028, 0.032), Vector3(0.034, 0.009, 0.013), dark)
	_cylinder(_pistol, Vector3(0, 0.003, -0.121), 0.015, 0.012, dark)
	_cylinder(_pistol, Vector3(0, 0.003, -0.128), 0.007, 0.003, _material(Color("151f27")))
	for stripe in range(3):
		_box(_pistol, Vector3(0, 0.006, 0.012 + stripe * 0.01),
				Vector3(0.061, 0.032, 0.003), dark, -14.0)
	_model_holding_hand(_pistol, glove, sleeve, Vector3(0.008, -0.067, 0.036))
	_pistol_muzzle.position = Vector3(0, 0.003, -0.133)
	_pistol.add_child(_pistol_muzzle)


func _build_rifle(graphite: Material, dark: Material, tan: Material, accent: Material,
		glove: Material, sleeve: Material) -> void:
	_box(_rifle, Vector3(0, -0.001, -0.051), Vector3(0.069, 0.053, 0.133), graphite)
	_box(_rifle, Vector3(0, 0.003, -0.165), Vector3(0.060, 0.049, 0.122), tan)
	_box(_rifle, Vector3(0, 0.025, -0.120), Vector3(0.043, 0.013, 0.226), dark)
	_box(_rifle, Vector3(0, 0.038, -0.062), Vector3(0.034, 0.022, 0.038), graphite)
	_box(_rifle, Vector3(0, 0.05, -0.070), Vector3(0.020, 0.006, 0.010), accent)
	_box(_rifle, Vector3(0, 0.031, -0.215), Vector3(0.014, 0.015, 0.015), accent)
	_box(_rifle, Vector3(0, -0.074, -0.077), Vector3(0.044, 0.102, 0.057), dark, 13.0)
	_box(_rifle, Vector3(0, -0.043, 0.005), Vector3(0.041, 0.057, 0.043), dark, 19.0)
	_cylinder(_rifle, Vector3(0, 0, -0.248), 0.010, 0.069, graphite)
	_cylinder(_rifle, Vector3(0, 0, -0.285), 0.018, 0.027, dark)
	_cylinder(_rifle, Vector3(0, 0, -0.299), 0.008, 0.003, _material(Color("151f27")))
	for vent in range(3):
		_box(_rifle, Vector3(0, 0.013, -0.153 - vent * 0.018),
				Vector3(0.061, 0.011, 0.007), dark)
	_model_holding_hand(_rifle, glove, sleeve, Vector3(0.008, -0.063, 0.029))
	_box(_rifle, Vector3(-0.041, -0.050, -0.113), Vector3(0.064, 0.065, 0.090), glove, 32.0)
	_box(_rifle, Vector3(-0.064, -0.093, -0.042), Vector3(0.071, 0.071, 0.134), sleeve, 30.0)
	_rifle_muzzle.position = Vector3(0, 0, -0.304)
	_rifle.add_child(_rifle_muzzle)


func _model_holding_hand(model: Node3D, glove: Material, sleeve: Material, grip: Vector3) -> void:
	_box(model, grip, Vector3(0.064, 0.063, 0.078), glove, 21.0)
	_box(model, grip + Vector3(-0.026, 0.017, -0.023), Vector3(0.021, 0.025, 0.062), glove, 14.0)
	_box(model, grip + Vector3(0.010, -0.049, 0.041), Vector3(0.074, 0.073, 0.102), sleeve, 23.0)


func _box(model: Node3D, center: Vector3, size: Vector3, material: Material,
		pitch_degrees := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_part(model, center, mesh, material, deg_to_rad(pitch_degrees))


func _cylinder(model: Node3D, center: Vector3, radius: float, length: float,
		material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 0
	_add_part(model, center, mesh, material, PI * 0.5)


func _add_part(model: Node3D, center: Vector3, mesh: Mesh, material: Material,
		pitch: float) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.position = center
	part.rotation.x = pitch
	model.add_child(part)


func _material(color: Color, glow := 0.25) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = glow
	return material
