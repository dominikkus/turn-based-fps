extends RefCounted

const RELOAD_COST: int = 2
const SWITCH_COST: int = 1
const UNLIMITED_RESERVE: int = -1

var active_index: int = 0
var _weapons: Array[Dictionary] = []


func _init(configurations: Array[Dictionary]) -> void:
	for configuration in configurations:
		var magazine_size: int = configuration["magazine_size"]
		var fire_rate: float = configuration["fire_rate"]
		_weapons.append({
			"name": configuration["name"],
			"magazine_size": magazine_size,
			"damage": configuration["damage"],
			"fire_rate": fire_rate,
			"shot_interval_usec": maxf(1.0, ceilf(1_000_000.0 / fire_rate)),
			"next_shot_usec": 0.0,
			"ammo": magazine_size,
			"reserve": configuration.get("reserve", UNLIMITED_RESERVE),
		})


func active_weapon() -> Dictionary:
	if _weapons.is_empty():
		return {}
	return _weapons[active_index].duplicate()


func can_fire() -> bool:
	return not _weapons.is_empty() and _weapons[active_index]["ammo"] > 0


func is_ready_to_fire(now_usec: int) -> bool:
	return can_fire() and now_usec >= _weapons[active_index]["next_shot_usec"]


func fire(now_usec: int) -> int:
	if not is_ready_to_fire(now_usec):
		return 0
	var weapon: Dictionary = _weapons[active_index]
	weapon["ammo"] -= 1
	weapon["next_shot_usec"] = now_usec + weapon["shot_interval_usec"]
	return weapon["damage"]


func can_reload() -> bool:
	if _weapons.is_empty():
		return false
	var weapon: Dictionary = _weapons[active_index]
	var reserve: int = weapon["reserve"]
	return weapon["ammo"] < weapon["magazine_size"] and (reserve == UNLIMITED_RESERVE or reserve > 0)


func reload() -> void:
	if not can_reload():
		return
	var weapon: Dictionary = _weapons[active_index]
	var rounds_needed: int = weapon["magazine_size"] - weapon["ammo"]
	var reserve: int = weapon["reserve"]
	if reserve != UNLIMITED_RESERVE:
		rounds_needed = mini(rounds_needed, reserve)
		weapon["reserve"] -= rounds_needed
	weapon["ammo"] += rounds_needed


func can_switch() -> bool:
	return _weapons.size() > 1


func switch(direction: int) -> void:
	if can_switch():
		active_index = posmod(active_index + posmod(direction, _weapons.size()), _weapons.size())
