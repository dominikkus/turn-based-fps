extends Node3D

const ArenaLayout = preload("res://arena_layout.gd")
const ArenaView = preload("res://arena_view.gd")
const AimSpread = preload("res://aim_spread.gd")
const Balance = preload("res://balance.gd")
const CombatHUD = preload("res://combat_hud.gd")
const FocusBudget = preload("res://focus_budget.gd")
const TileOutline = preload("res://tile_outline.gd")
const TuningPanel = preload("res://tuning_panel.gd")
const VerticalEnemyPlan = preload("res://vertical_enemy_plan.gd")
const VerticalLayout = preload("res://vertical_layout.gd")
const VerticalSpace = preload("res://vertical_space.gd")
const WeaponLoadout = preload("res://weapon_loadout.gd")
const WeaponView = preload("res://weapon_view.gd")

const RIFLE := 1
const STEP_COST := 1
const LOOK_SENSITIVITY := 0.0022
const PITCH_LIMIT := PI * 0.49
const CONTROLS := "WASD Step · %s · R Reload · Wheel Switch · Space End Turn · F1 Tuning"

@onready var arena: ArenaView = $Arena
@onready var tile_outline: TileOutline = $TileOutline
@onready var camera: Camera3D = $PlayerCamera
@onready var weapon_view: WeaponView = $PlayerCamera/WeaponView
@onready var layout: MarginContainer = $Interface/Layout

var tuning_panel: TuningPanel
var hud: CombatHUD
var settings: Dictionary = {}
var budget: FocusBudget
var weapons: WeaponLoadout
var aim_states: Array[AimSpread] = []
var plans: Dictionary = {}
var enemy_health: Array[int] = []
var player_hp := 0
var enemies_left := 0
var round_number := 0
var player_position := Vector3.ZERO
var _space: VerticalSpace
var _vertical_layout: Dictionary = {}
var _player_surface := -1
var _outlined_surface := -1
var _enemy_surfaces: Array[int] = []
var _pillar_tiles: Array[Vector2i] = []
var _cell_scale := 0.0
var _body_radius := 0.0
var _enemy_stats: Dictionary = {}
var _spawn_rng := RandomNumberGenerator.new()
var _combat_rng := RandomNumberGenerator.new()
var _lmb_starts_firing := false
var _focus_button_down := false
var _trigger_down := false
var _tuning_open := true
var _finished := false
var _step_seconds: float
var _step_elapsed := 0.0
var _step_origin := Vector3.ZERO
var _step_targets: Array[Dictionary] = []
var _end_turn_pending := false
var _focus_after_step := false


func _ready() -> void:
	_spawn_rng.randomize()
	_combat_rng.randomize()
	hud = CombatHUD.new()
	$Interface.add_child(hud)
	# The tuning layer stays above the HUD while a result is displayed.
	$Interface.move_child(layout, -1)
	hud.replay_requested.connect(_on_replay)
	hud.hide()

	tuning_panel = TuningPanel.new()
	tuning_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	tuning_panel.size_flags_vertical = Control.SIZE_FILL
	layout.add_child(tuning_panel)
	tuning_panel.set_level_fields(15, 15, 2.0, 3, 1, true)
	tuning_panel.set_balance_fields(Balance.fields())
	tuning_panel.set_status("Create Next Level applies the firing mode and generates the arena.")
	tuning_panel.create_requested.connect(_on_create_requested)


func _on_create_requested(
	width: int, depth: int, cell_scale: float, enemy_count: int, stories: int, firing_windows: bool
) -> void:
	var values := tuning_panel.read_balance_values()
	if values.is_empty():
		return
	var message := Balance.validate(values)
	if not message.is_empty():
		tuning_panel.set_status(message, true)
		return
	var draft := {
		"width": width, "depth": depth, "cell_scale": cell_scale, "enemy_count": enemy_count,
		"stories": stories, "balance": values, "firing_windows": firing_windows,
	}
	message = _start_level(draft)
	if not message.is_empty():
		tuning_panel.set_status(message, true)


func _start_level(draft: Dictionary, keep_layout := false) -> String:
	var width: int = draft["width"]
	var depth: int = draft["depth"]
	var cell_scale: float = draft["cell_scale"]
	var count: int = draft["enemy_count"]
	var stories: int = draft.get("stories", 1)
	var extent := Vector2(width, depth) * cell_scale
	if not extent.is_finite() or maxf(extent.x, extent.y) > 100_000.0 or cell_scale < 0.0001:
		return "The grid scale or arena size is outside the camera’s supported range."
	var radius := cell_scale * ArenaView.BODY_RADIUS_CELLS
	var values: Dictionary = draft["balance"]
	var spawns: Dictionary
	if stories > 1:
		if keep_layout:
			spawns = VerticalLayout.respawn(_vertical_layout, width, depth, cell_scale, count, radius, _spawn_rng)
		else:
			spawns = VerticalLayout.roll(width, depth, cell_scale, count, radius, _spawn_rng, values["pillar_tiles"], stories)
	elif keep_layout:
		spawns = ArenaLayout.respawn(width, depth, cell_scale, count, radius, _spawn_rng, _pillar_tiles, true)
	else:
		spawns = ArenaLayout.roll(width, depth, cell_scale, count, radius, _spawn_rng, values["pillar_tiles"], true)
	if spawns.has("error"):
		return spawns["error"]

	var size := Vector2i(width, depth)
	var surfaces: Array[Dictionary] = spawns["surfaces"] if stories > 1 else VerticalSpace.flat_surfaces(size)
	var space := VerticalSpace.new(size, cell_scale, surfaces, spawns["pillars"])
	var player_surface := space.surface_at(spawns["player"])
	var enemy_surfaces: Array[int] = []
	var enemy_positions: Array[Vector3] = []
	if player_surface < 0:
		return "Could not find a walkable player spawn. Try creating the level again."
	for point: Vector3 in spawns["enemies"]:
		var surface := space.surface_at(point)
		if surface < 0:
			return "Could not find a walkable enemy spawn. Try creating the level again."
		enemy_surfaces.append(surface)
		enemy_positions.append(space.surface_center(surface))

	settings = draft.duplicate(true)
	_cell_scale = cell_scale
	_body_radius = radius
	_pillar_tiles = spawns["pillars"]
	_space = space
	_vertical_layout = spawns if stories > 1 else {}
	_player_surface = player_surface
	_enemy_surfaces = enemy_surfaces
	_lmb_starts_firing = draft.get("firing_windows", false)
	var ap_seconds: float = values.get("ap_seconds", values.get("firing_window_seconds", Balance.AP_SECONDS))
	budget = FocusBudget.new(values["ap"], ap_seconds)
	var fire_controls := "LMB Fire" if _lmb_starts_firing else "RMB Start · LMB Fire"
	fire_controls += " · Hold RMB to keep spending AP"
	hud.set_controls(CONTROLS % fire_controls)
	weapons = WeaponLoadout.new(Balance.loadout(values))
	weapon_view.set_cell_scale(cell_scale)
	weapon_view.set_weapon(weapons.active_index)
	weapon_view.show()
	aim_states.clear()
	for index in range(Balance.WEAPON_NAMES.size()):
		var state := AimSpread.new()
		state.reset(Balance.aim_profile(values, index))
		aim_states.append(state)
	_enemy_stats = Balance.enemy_stats(values)
	player_position = space.surface_center(player_surface)
	_step_seconds = values["step_seconds"]
	_step_origin = player_position
	_step_elapsed = 0.0
	_step_targets.clear()
	_end_turn_pending = false
	_focus_after_step = false
	player_hp = values["player_hp"]
	enemies_left = count
	round_number = 1
	enemy_health.clear()
	enemy_health.resize(count)
	enemy_health.fill(values["enemy_hp"])
	if stories == 1:
		arena.rebuild(width, depth, cell_scale, enemy_positions, _pillar_tiles)
	else:
		arena.rebuild_vertical(width, depth, cell_scale, enemy_positions, _pillar_tiles, surfaces)
	_outlined_surface = -1
	_outline_surface(player_surface)
	_update_camera_position()
	camera.rotation = Vector3.ZERO
	var toward_center := -player_position
	if toward_center.length_squared() > 0.0:
		camera.rotation.y = atan2(-toward_center.x, -toward_center.z)
	camera.near = cell_scale * 0.025
	var vertical_span := (stories - 1) * cell_scale * VerticalLayout.STORY_HEIGHT_CELLS
	camera.far = Vector3(extent.x, vertical_span, extent.y).length() * 1.5 + cell_scale
	_focus_button_down = false
	_trigger_down = false
	_finished = false
	hud.hide_result()
	var start_buttons := "LMB or RMB" if _lmb_starts_firing else "RMB"
	tuning_panel.set_status("%s starts the AP bar. Create Next Level applies edits." % start_buttons)
	_set_tuning(false)
	hud.set_feedback("Turn 1")
	_update_enemy_plans()
	_update_hud(Time.get_ticks_usec())
	if enemies_left == 0:
		_show_result(true)
	return ""


func _on_replay() -> void:
	var message := _start_level(settings, true)
	if not message.is_empty():
		hud.show_result("Could not roll new spawns", message)


func _set_tuning(is_open: bool) -> void:
	_tuning_open = is_open
	tuning_panel.visible = is_open
	hud.visible = not is_open
	var capture := not is_open and not _finished
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	if is_open:
		_close_firing_segment(Time.get_ticks_usec())
		_focus_button_down = false
		_focus_after_step = false


func _input(event: InputEvent) -> void:
	if settings.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F1, KEY_ESCAPE]:
		_set_tuning(not _tuning_open)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _tuning_open or _finished or settings.is_empty():
		return
	var now := Time.get_ticks_usec()
	if event is InputEventMouseMotion:
		camera.rotation.y -= event.relative.x * LOOK_SENSITIVITY
		_adjust_pitch(-event.relative.y * LOOK_SENSITIVITY)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event, now)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.physical_keycode, now)


func _handle_mouse_button(event: InputEventMouseButton, now: int) -> void:
	match event.button_index:
		MOUSE_BUTTON_RIGHT:
			_focus_button_down = event.pressed
			if not event.pressed:
				_focus_after_step = false
				budget.stop_continuous(now)
			elif _step_targets.is_empty():
				_begin_continuous_firing(now)
			elif not _end_turn_pending:
				_focus_after_step = true
		MOUSE_BUTTON_LEFT:
			_trigger_down = event.pressed
			if event.pressed:
				_try_fire(now, true)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed and not _end_turn_pending:
				_switch_weapon(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1, now)


func _begin_continuous_firing(now: int) -> void:
	if not weapons.can_fire():
		hud.set_feedback("Magazine empty · Release RMB to reload or switch")
	elif not budget.begin_continuous(now):
		hud.set_feedback("Firing needs 1 AP")
	else:
		hud.set_feedback("")


func _handle_key(key: Key, now: int) -> void:
	if _end_turn_pending:
		return
	match key:
		KEY_W: _try_step(Vector2.UP, now)
		KEY_S: _try_step(Vector2.DOWN, now)
		KEY_A: _try_step(Vector2.LEFT, now)
		KEY_D: _try_step(Vector2.RIGHT, now)
		KEY_R: _reload(now)
		KEY_SPACE:
			_focus_after_step = false
			if _step_targets.is_empty():
				_end_turn(now)
			else:
				_end_turn_pending = true


func _process(delta: float) -> void:
	if _tuning_open or _finished or settings.is_empty():
		return
	for state in aim_states:
		state.update(delta)
	var now := Time.get_ticks_usec()
	budget.update(now)
	if _trigger_down and weapons.active_index == RIFLE:
		_try_fire(now)
	_advance_steps(delta, now)
	_update_hud(now)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not settings.is_empty() and not _tuning_open:
		_set_tuning(true)


func _try_step(direction: Vector2, now: int) -> void:
	if budget.is_continuous() or _focus_after_step:
		hud.set_feedback("Release RMB to move")
		return
	var forward := -camera.basis.z
	var facing := Vector2i(0, int(signf(forward.z)))
	if absf(forward.x) > absf(forward.z):
		facing = Vector2i(int(signf(forward.x)), 0)
	var right := Vector2i(-facing.y, facing.x)
	var offset := right * int(direction.x) - facing * int(direction.y)
	var surface := _player_surface
	if not _step_targets.is_empty():
		surface = _step_targets.back()["surface"]
	var next := _space.neighbor_in_direction(surface, offset)
	if next < 0:
		hud.set_feedback("That step is blocked")
		return
	var start := _space.surface_center(surface)
	var destination := _space.surface_center(next)
	var step := _space.advance(start, surface, destination, _body_radius)
	if step.is_empty() or step["surface"] != next:
		hud.set_feedback("That step is blocked")
		return
	var waypoints: Array[Vector3] = step["waypoints"]
	waypoints[-1] = destination
	if _path_blocked_by_enemy(start, waypoints):
		hud.set_feedback("An enemy blocks that step")
		return
	if not budget.spend(STEP_COST, now):
		hud.set_feedback("A step costs 1 AP")
		return
	_close_firing_segment(now)
	if _step_targets.is_empty():
		_step_origin = player_position
	step["position"] = destination
	_step_targets.append(step)
	hud.set_feedback("")


func _path_blocked_by_enemy(start: Vector3, waypoints: Array[Vector3]) -> bool:
	var spacing := 2.0 * _body_radius - 0.000001 * _cell_scale
	var height := ArenaView.BODY_HEIGHT_CELLS * _cell_scale
	var actors: Array[Vector3] = []
	for index in range(enemy_health.size()):
		if enemy_health[index] > 0:
			actors.append(arena.enemy_markers[index].position)
	for end in waypoints:
		if VerticalSpace.crosses_actors(start, end, spacing, height, actors):
			return true
		start = end
	return false


func _advance_steps(delta: float, now: int) -> void:
	if _step_targets.is_empty():
		return
	_step_elapsed += delta
	while _step_elapsed >= _step_seconds:
		_step_elapsed -= _step_seconds
		var step: Dictionary = _step_targets.pop_front()
		player_position = step["position"]
		_player_surface = step["surface"]
		_step_origin = player_position
		_outline_surface(_player_surface)
		_update_enemy_plans()
		if _step_targets.is_empty():
			_step_elapsed = 0.0
			_update_camera_position()
			if _end_turn_pending:
				_end_turn_pending = false
				_end_turn(now)
			elif _focus_after_step:
				_focus_after_step = false
				_begin_continuous_firing(now)
			return
	var progress := smoothstep(0.0, 1.0, _step_elapsed / _step_seconds)
	var current: Dictionary = _step_targets.front()
	player_position = _interpolate_step(current, progress)
	_outline_surface(_player_surface if progress < 0.5 else int(current["surface"]))
	_update_camera_position()


func _interpolate_step(step: Dictionary, progress: float) -> Vector3:
	var end: Vector3 = step["position"]
	var horizontal := Vector2(end.x - _step_origin.x, end.z - _step_origin.z)
	var left := horizontal.length() * progress
	var cursor := _step_origin
	for waypoint: Vector3 in step["waypoints"]:
		var leg := Vector2(waypoint.x - cursor.x, waypoint.z - cursor.z).length()
		if leg > 0.0 and left <= leg:
			return cursor.lerp(waypoint, left / leg)
		left -= leg
		cursor = waypoint
	return end


func _reload(now: int) -> void:
	if _focus_button_down:
		hud.set_feedback("Release RMB to reload")
		return
	if not weapons.can_reload():
		var weapon := weapons.active_weapon()
		hud.set_feedback("Magazine full" if weapon["ammo"] == weapon["magazine_size"] else "No reserve ammo")
		return
	if not budget.spend(WeaponLoadout.RELOAD_COST, now):
		hud.set_feedback("Reload costs 2 AP")
		return
	_close_firing_segment(now)
	weapons.reload()
	hud.set_feedback("%s reloaded" % weapons.active_weapon()["name"])


func _switch_weapon(direction: int, now: int) -> void:
	if _focus_button_down:
		hud.set_feedback("Release RMB to switch")
		return
	if not weapons.can_switch():
		return
	if not budget.spend(WeaponLoadout.SWITCH_COST, now):
		hud.set_feedback("Switching costs 1 AP")
		return
	_close_firing_segment(now)
	weapons.switch(direction)
	weapon_view.set_weapon(weapons.active_index)
	hud.set_feedback("%s equipped" % weapons.active_weapon()["name"])


func _close_firing_segment(now: int) -> void:
	budget.close_segment(now)
	_trigger_down = false


func _try_fire(now: int, trigger_pressed := false) -> void:
	if _end_turn_pending or not _step_targets.is_empty():
		if trigger_pressed:
			hud.set_feedback("Finish moving before firing")
		return
	if not weapons.can_fire():
		_show_empty_magazine()
		return
	budget.update(now)
	if not _lmb_starts_firing and not budget.is_spending(now):
		if trigger_pressed:
			hud.set_feedback("Hold RMB to start firing")
		return
	if not weapons.is_ready_to_fire(now):
		if trigger_pressed:
			hud.set_feedback("%s cycling" % weapons.active_weapon()["name"])
		return
	if not budget.begin_segment(now):
		_trigger_down = false
		hud.set_feedback("Firing needs 1 AP")
		return

	var aim := aim_states[weapons.active_index]
	var direction := aim.spread_direction(camera.global_basis, _combat_rng)
	var origin := camera.global_position
	var end := origin + direction * camera.far
	var hit := _trace_ray(origin, end, ArenaView.TARGET_LAYER | ArenaView.PILLAR_LAYER)
	var damage := weapons.fire(now)
	var tracer_start := weapon_view.muzzle_position()
	if not hit.is_empty():
		end = hit["position"]
	var obstruction := _trace_ray(tracer_start, end, ArenaView.PILLAR_LAYER)
	if not obstruction.is_empty():
		hit = obstruction
		end = hit["position"]
	arena.draw_tracer(tracer_start, end, Color("ffe39a"), _cell_scale)
	weapon_view.kick()
	_adjust_pitch(aim.register_shot())

	if hit.is_empty():
		hud.set_feedback("")
	else:
		var collider: Object = hit["collider"]
		if collider.has_meta("enemy_index"):
			_damage_enemy(collider.get_meta("enemy_index"), damage)
		else:
			hud.set_feedback("Pillar blocked the shot")
	if not weapons.can_fire() and not _finished:
		budget.stop_continuous(now)
		_show_empty_magazine()


func _show_empty_magazine() -> void:
	_trigger_down = false
	if _focus_button_down:
		hud.set_feedback("Magazine empty · Release RMB to reload or switch")
	else:
		hud.set_feedback("Magazine empty · R to reload or wheel to switch")


func _trace_ray(start: Vector3, end: Vector3, mask: int) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(start, end, mask)
	return get_world_3d().direct_space_state.intersect_ray(ray)


func _damage_enemy(index: int, damage: int) -> void:
	enemy_health[index] = maxi(0, enemy_health[index] - damage)
	if enemy_health[index] == 0:
		arena.remove_enemy(index)
		enemies_left -= 1
		hud.set_feedback("Enemy down")
		if enemies_left == 0:
			_show_result(true)
			return
	else:
		hud.set_feedback("Hit · %d damage" % damage)
	_update_enemy_plans()


func _update_enemy_plans() -> void:
	plans.clear()
	var positions: Dictionary = {}
	for index in range(enemy_health.size()):
		if enemy_health[index] > 0:
			positions[index] = arena.enemy_markers[index].position
	# Forecast and execute in the same order so earlier movers block later ones.
	for index in positions:
		var others: Array[Vector3] = []
		for other_index in positions:
			if other_index != index:
				others.append(positions[other_index])
		var plan := VerticalEnemyPlan.plan(
			positions[index], _enemy_surfaces[index], player_position, _player_surface, others,
			_cell_scale, 2.0 * _body_radius, _enemy_stats, _space, _enemy_has_sight
		)
		plans[index] = plan
		var waypoints: Array[Vector3] = plan["waypoints"]
		if not waypoints.is_empty():
			positions[index] = waypoints.back()
		var label := arena.enemy_labels[index]
		if plan["fires"]:
			label.text = "◎ %s · %d dmg" % [_format_chance(plan["chance"]), plan["damage"]]
			label.modulate = Color("ffd2a0")
		elif waypoints.is_empty():
			label.text = "HOLD"
			label.modulate = Color("b7d9de")
		else:
			label.text = "➜ MOVE"
			label.modulate = Color("b7d9de")


func _format_chance(chance: float) -> String:
	var percent := chance * 100.0
	if percent < 1.0:
		return "<1%"
	return "%d%%" % (100 if percent >= 100.0 else mini(99, roundi(percent)))


func _end_turn(now: int) -> void:
	_close_firing_segment(now)
	var shots := 0
	var damage_taken := 0
	for index in plans:
		var plan: Dictionary = plans[index]
		var waypoints: Array[Vector3] = plan["waypoints"]
		var actor := arena.enemy_markers[index]
		if not waypoints.is_empty():
			_enemy_surfaces[index] = plan["surface"]
			actor.position = _space.surface_center(_enemy_surfaces[index])
			arena.enemy_bodies[index].force_update_transform()
		if not plan["fires"]:
			continue
		shots += 1
		var chance: float = plan["chance"]
		var roll := _combat_rng.randf()
		var did_hit := chance >= 1.0 or roll < chance
		var shot_start := actor.position + Vector3.UP * _cell_scale * 0.65
		var shot_end := camera.position - Vector3.UP * _cell_scale * 0.35
		if not did_hit:
			shot_end += camera.global_basis.x * _cell_scale * 0.55
		var obstruction := _trace_ray(shot_start, shot_end, ArenaView.PILLAR_LAYER)
		if not obstruction.is_empty():
			shot_end = obstruction["position"]
			did_hit = false
		if did_hit:
			damage_taken += int(plan["damage"])
			player_hp = maxi(0, player_hp - int(plan["damage"]))
		arena.draw_tracer(shot_start, shot_end, Color("ff8969"), _cell_scale)
		if player_hp == 0:
			_show_result(false)
			return

	round_number += 1
	budget.refill()
	_update_enemy_plans()
	hud.set_feedback("Turn %d · Enemy shots %d · Damage taken %d" % [round_number, shots, damage_taken])


func _show_result(won: bool) -> void:
	_finished = true
	_close_firing_segment(Time.get_ticks_usec())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var result := "Victory" if won else "Defeat"
	hud.show_result(result, "Replay keeps the arena and rolls fresh spawns.")


func _enemy_has_sight(origin: Vector3, target: Vector3) -> bool:
	return _trace_ray(
		origin + Vector3.UP * _cell_scale * 0.65,
		target + Vector3.UP * _cell_scale * (ArenaView.EYE_HEIGHT_CELLS - 0.35),
		ArenaView.PILLAR_LAYER
	).is_empty()


func _update_camera_position() -> void:
	camera.position = player_position + Vector3.UP * ArenaView.EYE_HEIGHT_CELLS * _cell_scale


func _outline_surface(id: int) -> void:
	if id == _outlined_surface:
		return
	_outlined_surface = id
	tile_outline.show_tile(to_global(_space.surface_center(id)), _space.surface_slope(id), _cell_scale)


func _adjust_pitch(amount: float) -> void:
	camera.rotation.x = clampf(camera.rotation.x + amount, -PITCH_LIMIT, PITCH_LIMIT)


func _update_hud(now: int) -> void:
	hud.set_combat_state(
		budget.remaining(now), budget.max_ap, budget.is_spending(now),
		player_hp, settings["balance"]["player_hp"], enemies_left, "Firing"
	)
	var story := _space.story(_player_surface) + 1
	hud.set_story(story, settings.get("stories", 1))
	var weapon := weapons.active_weapon()
	hud.set_weapon_state(weapon["name"], weapon["ammo"], weapon["magazine_size"], weapon["reserve"])
	var center := camera.global_position - camera.global_basis.z
	var spread := deg_to_rad(aim_states[weapons.active_index].current_degrees)
	var edge := center + camera.global_basis.x * tan(spread)
	hud.set_reticle_radius(camera.unproject_position(edge).distance_to(camera.unproject_position(center)))
