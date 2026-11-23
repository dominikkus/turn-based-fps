extends RefCounted

const WEAPON_NAMES := ["Pistol", "AR"]
const AP_SECONDS := 0.35
const FREE_MOVE_SPEED := 4.0
const FREE_MOVE_AP_PER_METER := 1.0
const PISTOL_FIRE_RATE := 5.0
const AR_FIRE_RATE := 8.0


static func fields() -> Array[Dictionary]:
	var settings: Array[Dictionary] = [
		_field("pillar_tiles", "Pillar tiles", 30, 0),
		_field("ap", "AP per turn", 5, 1, 100),
		_field("step_seconds", "Seconds per movement step", 0.16, 0.04, 1.0),
		_field("free_move_speed", "Free move speed (m/s)", FREE_MOVE_SPEED, 0.1, 25.0),
		_field("free_move_ap_per_meter", "Free move AP per meter", FREE_MOVE_AP_PER_METER, 0.01, 50.0),
		_field("ap_seconds", "Seconds per AP", AP_SECONDS, 0.001, 600.0),
		_field("player_hp", "Player HP", 5, 1),
		_field("enemy_hp", "Enemy HP", 2, 1),
		_field("enemy_damage", "Enemy damage", 1, 0),
		_field("enemy_accuracy", "Enemy base accuracy (%)", 70.0, 0.0, 100.0),
		_field("enemy_range", "Enemy range (cells)", 6.0, 0.01),
		_field("enemy_near", "Enemy full-accuracy radius (cells)", 1.0, 0.0),
		_field("enemy_shoot_move", "Enemy steps with shot", 1, 0, 32),
		_field("enemy_move", "Enemy steps without shot", 2, 0, 32),
	]
	for prefix: String in ["pistol", "ar"]:
		var rifle := prefix == "ar"
		var caption := "AR" if rifle else "Pistol"
		settings.append_array([
			_field(prefix + "_mag", caption + " magazine", 15 if rifle else 5, 1),
			_field(prefix + "_total", caption + " total ammo", 60 if rifle else 20, 1),
			_field(prefix + "_damage", caption + " damage", 1 if rifle else 2, 1),
			_field(prefix + "_rate", caption + " rounds per second", AR_FIRE_RATE if rifle else PISTOL_FIRE_RATE,
				0.05 if rifle else 1.0 / 60.0, 60.0 if rifle else 1000.0),
			_field(prefix + "_spread", caption + " base spread (°)", 7.50 if rifle else 4.00, 0.0, 45.0),
			_field(prefix + "_cap", caption + " max spread (°)", 10.10 if rifle else 4.65, 0.0, 45.0),
			_field(prefix + "_bloom", caption + " bloom per shot (°)", 0.35 if rifle else 0.18, 0.0, 45.0),
			_field(prefix + "_kick", caption + " upward kick (°)", 0.35 if rifle else 0.75, 0.0, 15.0),
			_field(prefix + "_delay", caption + " recovery starts (s)", 0.14 if rifle else 0.10, 0.0, 10.0),
			_field(prefix + "_settle", caption + " full recovery (s)", 0.50 if rifle else 0.25, 0.001, 20.0),
		])
	return settings


static func validate(values: Dictionary) -> String:
	var ap_seconds: float = values.get("ap_seconds", AP_SECONDS)
	if not is_finite(ap_seconds) or ap_seconds <= 0.0:
		return "Seconds per AP must be finite and greater than zero."
	if values["enemy_near"] > values["enemy_range"]:
		return "Enemy full-accuracy radius must fit inside enemy range."
	for prefix: String in ["pistol", "ar"]:
		var caption := "AR" if prefix == "ar" else "Pistol"
		var rate := _fire_rate(values, prefix)
		if not is_finite(rate) or rate <= 0.0:
			return "%s rounds per second must be finite and greater than zero." % caption
		if values[prefix + "_total"] < values[prefix + "_mag"]:
			return "%s total ammo must fit a full starting magazine." % caption
		if values[prefix + "_spread"] > values[prefix + "_cap"]:
			return "%s base spread must be at most its max spread." % caption
		if values[prefix + "_settle"] <= values[prefix + "_delay"]:
			return "%s full recovery must be later than recovery start." % caption
	return ""


static func enemy_stats(values: Dictionary) -> Dictionary:
	return {
		"range_cells": values["enemy_range"],
		"full_accuracy_cells": values["enemy_near"],
		"base_accuracy": values["enemy_accuracy"] / 100.0,
		"damage": values["enemy_damage"],
		"move_cells_with_shot": values["enemy_shoot_move"],
		"move_cells_without_shot": values["enemy_move"],
	}


static func loadout(values: Dictionary) -> Array[Dictionary]:
	var configurations: Array[Dictionary] = []
	for name: String in WEAPON_NAMES:
		var prefix: String = name.to_lower()
		var magazine: int = values[prefix + "_mag"]
		configurations.append({
			"name": name,
			"magazine_size": magazine,
			"damage": values[prefix + "_damage"],
			"fire_rate": _fire_rate(values, prefix),
			"reserve": values[prefix + "_total"] - magazine,
		})
	return configurations


static func _fire_rate(values: Dictionary, prefix: String) -> float:
	if prefix == "ar":
		return float(values.get("ar_rate", AR_FIRE_RATE))
	if values.has("pistol_rate"):
		return float(values["pistol_rate"])
	var interval: float = values.get("pistol_shot_interval", 1.0 / PISTOL_FIRE_RATE)
	return 1.0 / interval if is_finite(interval) and interval > 0.0 else NAN


static func aim_profile(values: Dictionary, index: int) -> Dictionary:
	var prefix: String = WEAPON_NAMES[index].to_lower()
	var base_spread: float = values[prefix + "_spread"]
	var max_spread: float = values[prefix + "_cap"]
	var delay: float = values[prefix + "_delay"]
	var decay_time: float = values[prefix + "_settle"] - delay
	return {
		"spread_degrees": base_spread,
		"max_spread_degrees": max_spread,
		"bloom_per_shot": values[prefix + "_bloom"],
		"kick_degrees": values[prefix + "_kick"],
		"recovery_delay": delay,
		"recovery_degrees_per_second": (max_spread - base_spread) / decay_time,
	}


static func _field(
	key: String, label: String, value: Variant, minimum: Variant, maximum: Variant = 2147483647
) -> Dictionary:
	return {
		"key": key, "label": label, "value": value, "is_integer": value is int,
		"minimum": minimum, "maximum": maximum,
	}
