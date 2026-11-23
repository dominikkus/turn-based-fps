extends Control

signal replay_requested

const INK := Color("eef6fc")
const MUTED := Color("b6c9d5")
const ACCENT := Color("a1f3ed")
const PANEL := Color(0.046, 0.081, 0.115, 0.94)
const BORDER := Color("3f5b6c")


class ActionMeter extends Control:
	const EMPTY := Color("233d4d")
	const AVAILABLE := Color("65b3b5")
	const FOCUS := Color("9ef4e9")
	const GAP := 4.0

	var current_ap := 0.0
	var max_ap := 0
	var focusing := false

	func _init() -> void:
		custom_minimum_size.y = 12.0
		mouse_filter = MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if max_ap <= 0:
			return

		var fill_color := FOCUS if focusing else AVAILABLE
		var gap := minf(GAP, size.x / max_ap * 0.27)
		var segment_width := (size.x - gap * (max_ap - 1)) / max_ap

		for index in range(max_ap):
			var x := index * (segment_width + gap)
			draw_rect(Rect2(x, 0.0, segment_width, size.y), EMPTY)
			var fill_fraction := clampf(current_ap - index, 0.0, 1.0)
			if fill_fraction > 0.0:
				draw_rect(Rect2(x, 0.0, segment_width * fill_fraction, size.y), fill_color)


var _combat_info: CenterContainer
var _meter := ActionMeter.new()
var _reticle_radius := 0.0
var _aiming := false
var _ap_text: Label
var _hp_text: Label
var _enemy_text: Label
var _story_text: Label
var _weapon_text: Label
var _feedback: Label
var _controls: Label
var _result: ColorRect
var _result_title: Label
var _result_detail: Label
var _replay: Button


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_combat_info()
	_build_result()
	resized.connect(queue_redraw)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_combat_info.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_combat_info.grow_vertical = GROW_DIRECTION_BEGIN
	_combat_info.offset_top = -16.0
	_combat_info.offset_bottom = -16.0
	_result.set_anchors_and_offsets_preset(PRESET_FULL_RECT)


func set_combat_state(current_ap: float, max_ap: int, focusing: bool, hp: int,
		max_hp: int, enemies_left: int, label_on_active: String = "Focus") -> void:
	_meter.current_ap = clampf(current_ap, 0.0, max_ap)
	_meter.max_ap = max_ap
	_meter.focusing = focusing
	_meter.queue_redraw()
	var action_label := label_on_active if focusing else "AP"
	_ap_text.text = "%s  %s / %d" % [action_label, String.num(_meter.current_ap, 2), max_ap]
	_ap_text.add_theme_color_override("font_color", ACCENT if focusing else INK)
	_hp_text.text = "HP  %d / %d" % [hp, max_hp]
	_hp_text.visible = max_hp > 0
	_enemy_text.text = "%d enemy" % enemies_left if enemies_left == 1 else "%d enemies" % enemies_left


func set_story(story: int, total: int) -> void:
	_story_text.visible = total > 1
	if _story_text.visible:
		_story_text.text = "Floor %d / %d" % [story, total]


func set_weapon_state(weapon: String, ammo: int, magazine_size: int, reserve: int = -1) -> void:
	_weapon_text.visible = magazine_size > 0
	if magazine_size <= 0:
		return
	_weapon_text.text = "%s  ·  %d / %d ammo" % [weapon, ammo, magazine_size]
	if reserve >= 0:
		_weapon_text.text += "  ·  %d reserve" % reserve


func set_reticle_radius(radius_px: float) -> void:
	var radius := maxf(radius_px, 0.0) if is_finite(radius_px) else 0.0
	if radius == _reticle_radius:
		return
	_reticle_radius = radius
	if _aiming:
		queue_redraw()


func set_aiming(is_aiming: bool) -> void:
	if _aiming == is_aiming:
		return
	_aiming = is_aiming
	queue_redraw()


func set_controls(text: String) -> void:
	_controls.text = text
	_controls.visible = not text.is_empty()


func set_feedback(text: String) -> void:
	_feedback.text = text
	_feedback.visible = not text.is_empty()


func show_result(title: String, detail: String) -> void:
	_result_title.text = title
	_result_detail.text = detail
	_result_detail.visible = not detail.is_empty()
	_combat_info.hide()
	_result.show()
	if is_inside_tree():
		_replay.grab_focus()
	queue_redraw()


func hide_result() -> void:
	_replay.release_focus()
	_result.hide()
	_combat_info.show()
	queue_redraw()


func _draw() -> void:
	if _result.visible:
		return
	var center := size * 0.5
	var outline := Color(0.02, 0.05, 0.08, 0.9)
	if _aiming and _reticle_radius >= 2.0:
		var points := ceili(clampf(_reticle_radius * 1.5, 16.0, 160.0))
		draw_arc(center, _reticle_radius, 0.0, TAU, points, outline, 3.0, true)
		draw_arc(center, _reticle_radius, 0.0, TAU, points, ACCENT, 1.25, true)
		return
	var dot := ACCENT if _aiming else INK
	draw_circle(center, 2.0, outline, true, -1.0, true)
	draw_circle(center, 1.25, dot, true, -1.0, true)


func _build_combat_info() -> void:
	_combat_info = CenterContainer.new()
	_combat_info.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_combat_info)

	var card := _add_card(_combat_info, 360.0)
	var stats := HBoxContainer.new()
	stats.mouse_filter = MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 18)
	card.add_child(stats)
	_hp_text = _add_label(stats, 16, INK)
	_enemy_text = _add_label(stats, 16, MUTED)
	_story_text = _add_label(stats, 15, MUTED)
	_story_text.hide()
	_ap_text = _add_label(stats, 16, INK)
	_ap_text.size_flags_horizontal = SIZE_EXPAND_FILL
	_ap_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(_meter)

	_weapon_text = _add_label(card, 15, INK)
	_weapon_text.hide()
	_feedback = _add_label(card, 15, INK)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.hide()
	_controls = _add_label(card, 13, MUTED)
	_controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls.hide()


func _build_result() -> void:
	_result = ColorRect.new()
	_result.color = Color(0.015, 0.035, 0.05, 0.7)
	_result.hide()
	add_child(_result)

	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_result.add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var card := _add_card(center, 320.0)
	card.add_theme_constant_override("separation", 14)
	_result_title = _add_label(card, 26, INK)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail = _add_label(card, 15, MUTED)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_replay = Button.new()
	_replay.text = "Replay"
	_replay.custom_minimum_size.y = 40.0
	_replay.pressed.connect(replay_requested.emit)
	card.add_child(_replay)


func _add_card(parent: Control, minimum_width: float) -> VBoxContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0

	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.x = minimum_width
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var list := VBoxContainer.new()
	list.mouse_filter = MOUSE_FILTER_IGNORE
	list.add_theme_constant_override("separation", 8)
	panel.add_child(list)
	return list


func _add_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
