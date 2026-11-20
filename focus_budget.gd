extends RefCounted

var max_ap: int
var usec_per_ap: float
var _whole_ap: int
var _segment_ends_at := -1.0
var _continuous := false


func _init(action_points: int, seconds_per_ap: float) -> void:
	assert(action_points > 0 and is_finite(seconds_per_ap) and seconds_per_ap > 0.0)
	max_ap = action_points
	usec_per_ap = seconds_per_ap * 1_000_000.0
	refill()


func refill() -> void:
	_whole_ap = max_ap
	_segment_ends_at = -1.0
	_continuous = false


func remaining(now_usec: int) -> float:
	var segment_fraction := clampf((_segment_ends_at - float(now_usec)) / usec_per_ap, 0.0, 1.0)
	return float(_whole_ap) + segment_fraction


func spend(cost: int, now_usec: int) -> bool:
	assert(cost > 0)
	# An action at the boundary may close the segment before a new one is charged.
	_settle(now_usec, false)
	if _whole_ap < cost:
		return false
	_whole_ap -= cost
	return true


func begin_segment(now_usec: int) -> bool:
	update(now_usec)
	if is_spending(now_usec):
		return true
	if _whole_ap == 0:
		return false
	_whole_ap -= 1
	_segment_ends_at = float(now_usec) + usec_per_ap
	return true


func begin_continuous(now_usec: int) -> bool:
	if not begin_segment(now_usec):
		return false
	_continuous = true
	return true


func stop_continuous(now_usec: int) -> void:
	_settle(now_usec, false)
	_continuous = false


func update(now_usec: int) -> void:
	_settle(now_usec, true)


func is_spending(now_usec: int) -> bool:
	return float(now_usec) < _segment_ends_at


func is_continuous() -> bool:
	return _continuous


func close_segment(now_usec: int) -> void:
	stop_continuous(now_usec)
	_segment_ends_at = -1.0


func _settle(now_usec: int, include_boundary: bool) -> void:
	var now := float(now_usec)
	while _continuous and (_segment_ends_at < now or (include_boundary and _segment_ends_at == now)):
		if _whole_ap == 0:
			_continuous = false
			_segment_ends_at = -1.0
			return
		_whole_ap -= 1
		# Renew from the previous deadline so skipped frames do not stretch the clock.
		_segment_ends_at += usec_per_ap
