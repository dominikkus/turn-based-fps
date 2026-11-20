extends RefCounted

var current_degrees: float

var _base_degrees: float
var _bloom_per_shot: float
var _max_degrees: float
var _recovery_delay: float
var _recovery_speed: float
var _kick_radians: float
var _recovery_wait: float


func reset(stats: Dictionary) -> void:
	_base_degrees = stats["spread_degrees"]
	_bloom_per_shot = stats["bloom_per_shot"]
	_max_degrees = stats["max_spread_degrees"]
	_recovery_delay = stats["recovery_delay"]
	_recovery_speed = stats["recovery_degrees_per_second"]
	_kick_radians = deg_to_rad(stats["kick_degrees"])
	_recovery_wait = 0.0
	current_degrees = _base_degrees


func spread_direction(camera_basis: Basis, rng: RandomNumberGenerator) -> Vector3:
	# Sample a uniform disk at unit view depth so it matches the on-screen cone.
	var radius := tan(deg_to_rad(current_degrees)) * sqrt(rng.randf())
	var azimuth := rng.randf_range(0.0, TAU)
	var camera_direction := Vector3(radius * cos(azimuth), radius * sin(azimuth), -1.0)
	return (camera_basis.orthonormalized() * camera_direction).normalized()


func register_shot() -> float:
	current_degrees = minf(current_degrees + _bloom_per_shot, _max_degrees)
	_recovery_wait = _recovery_delay
	return _kick_radians


func update(delta: float) -> void:
	var recovery_delta := maxf(delta - _recovery_wait, 0.0)
	_recovery_wait = maxf(_recovery_wait - delta, 0.0)
	current_degrees = move_toward(current_degrees, _base_degrees, recovery_delta * _recovery_speed)
