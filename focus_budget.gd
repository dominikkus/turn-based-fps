extends RefCounted

const AP_TOLERANCE := 0.000000001

var max_ap: int
var usec_per_ap: float
var _available_ap := 0.0
var _segment_ap := 0.0
var _segment_ends_at := -1.0


func _init(action_points: int, seconds_per_ap: float) -> void:
	assert(action_points > 0 and is_finite(seconds_per_ap) and seconds_per_ap > 0.0)
	max_ap = action_points
	usec_per_ap = seconds_per_ap * 1_000_000.0
	refill()


func refill() -> void:
	_available_ap = float(max_ap)
	_segment_ap = 0.0
	_segment_ends_at = -1.0


func available() -> float:
	return _available_ap


func remaining(now_usec: int) -> float:
	var segment_fraction := clampf((_segment_ends_at - float(now_usec)) / usec_per_ap, 0.0, _segment_ap)
	return _available_ap + segment_fraction


func spend(cost: float, now_usec: int) -> bool:
	if not is_finite(cost) or cost < 0.0:
		return false
	if cost == 0.0:
		return true
	# An action at the boundary may close the segment before a new one is charged.
	_settle(now_usec, false)
	if _available_ap + cost * AP_TOLERANCE < cost:
		return false
	_available_ap = maxf(0.0, _available_ap - cost)
	return true


func start_focus(now_usec: int) -> bool:
	update(now_usec)
	if is_focusing(now_usec):
		return true
	if _available_ap <= 0.0:
		return false
	_reserve_segment(float(now_usec))
	return true


func stop_focus(now_usec: int) -> void:
	_settle(now_usec, false)
	_segment_ap = 0.0
	_segment_ends_at = -1.0


func update(now_usec: int) -> void:
	_settle(now_usec, true)


func is_focusing(now_usec: int) -> bool:
	return float(now_usec) < _segment_ends_at


func _settle(now_usec: int, include_boundary: bool) -> void:
	var now := float(now_usec)
	while _segment_ends_at >= 0.0 and (_segment_ends_at < now or (include_boundary and _segment_ends_at == now)):
		if _available_ap <= 0.0:
			_segment_ap = 0.0
			_segment_ends_at = -1.0
			return
		# Renew from the previous deadline so skipped frames do not stretch the clock.
		_reserve_segment(_segment_ends_at)


func _reserve_segment(start_usec: float) -> void:
	_segment_ap = minf(1.0, _available_ap)
	_available_ap -= _segment_ap
	var deadline := start_usec + _segment_ap * usec_per_ap
	# Keep floating-point noise from delaying a deadline on an exact clock tick.
	var nearest_tick := roundf(deadline)
	_segment_ends_at = nearest_tick if absf(deadline - nearest_tick) < 0.000001 else deadline
