extends PanelContainer

signal create_requested(width: int, depth: int, cell_scale: float, enemy_count: int, stories: int,
		firing_windows: bool)

# Vector2i grid dimensions use signed 32-bit coordinates.
const MAX_WHOLE_NUMBER: int = 2147483647
const TEXT_COLOR := Color("ecf2f7")
const MUTED_COLOR := Color("afc2d2")
const ERROR_COLOR := Color("ffac9f")

var _width_field: LineEdit
var _depth_field: LineEdit
var _stories_field: LineEdit
var _scale_field: LineEdit
var _enemies_field: LineEdit
var _firing_windows: CheckButton
var _field_scroll: ScrollContainer
var _balance_title: Label
var _balance_grid: GridContainer
var _balance_inputs: Array[Dictionary] = []
var _submit_button: Button
var _status_label: Label


func _init() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("182431")
	background.border_color = Color("385267")
	background.set_border_width_all(1)
	background.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", background)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Level tuning"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	content.add_child(title)

	_firing_windows = CheckButton.new()
	_firing_windows.text = "LMB starts firing"
	_firing_windows.tooltip_text = (
		"Hold RMB to start the AP bar and keep it running. Release RMB to let the current segment finish.\n"
		+ "Enable this to let LMB start one AP segment too. LMB fires while the bar is running.\n"
		+ "Create Next Level applies the setting."
	)
	content.add_child(_firing_windows)

	_field_scroll = ScrollContainer.new()
	_field_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_field_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	_field_scroll.follow_focus = true
	_field_scroll.custom_minimum_size = Vector2(324, 220)
	_field_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_field_scroll)

	var field_groups := VBoxContainer.new()
	field_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field_groups.add_theme_constant_override("separation", 12)
	_field_scroll.add_child(field_groups)

	var fields := _add_field_grid(field_groups)
	_width_field = _add_field(fields, "Grid width", "Cells")
	_depth_field = _add_field(fields, "Grid depth", "Cells")
	_stories_field = _add_field(fields, "Stories", "Number of floors")
	_scale_field = _add_field(fields, "Cell scale", "World units per cell")
	_enemies_field = _add_field(fields, "Enemy count", "Enemies")

	_balance_title = Label.new()
	_balance_title.text = "Combat balance"
	_balance_title.add_theme_font_size_override("font_size", 18)
	_balance_title.add_theme_color_override("font_color", TEXT_COLOR)
	_balance_title.hide()
	field_groups.add_child(_balance_title)
	_balance_grid = _add_field_grid(field_groups)
	_balance_grid.hide()

	_submit_button = Button.new()
	_submit_button.text = "Create Next Level"
	_submit_button.custom_minimum_size.y = 36
	_submit_button.pressed.connect(_on_create_pressed)
	content.add_child(_submit_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status_label)
	set_status("Enter the values to generate a level.")


func set_submit_label(label_text: String) -> void:
	_submit_button.text = label_text


func set_status(message: String, is_error: bool = false) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()
	if is_error:
		_status_label.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_status_label.add_theme_color_override("font_color", MUTED_COLOR)


func set_level_fields(width: int, depth: int, cell_scale: float, enemy_count: int,
		stories: int = 1, firing_windows: bool = false) -> void:
	_width_field.text = str(width)
	_depth_field.text = str(depth)
	_stories_field.text = str(stories)
	_scale_field.text = str(cell_scale)
	_enemies_field.text = str(enemy_count)
	_firing_windows.button_pressed = firing_windows


func set_balance_fields(fields: Array[Dictionary]) -> void:
	for child in _balance_grid.get_children():
		_balance_grid.remove_child(child)
		child.queue_free()
	_balance_inputs.clear()

	for field in fields:
		var hint := "Number"
		if field["is_integer"]:
			hint = "Whole number"
		var input := _add_field(_balance_grid, field["label"], hint)
		if field.has("value"):
			input.text = str(field["value"])
		_balance_inputs.append({"field": field.duplicate(), "input": input})

	_balance_title.visible = not fields.is_empty()
	_balance_grid.visible = not fields.is_empty()


func read_balance_values() -> Dictionary:
	var values: Dictionary = {}
	for entry in _balance_inputs:
		var field: Dictionary = entry["field"]
		var value: Variant = _read_numeric_value(
			entry["input"], field["label"], field["is_integer"], field["minimum"],
			field.get("maximum")
		)
		if value == null:
			return {}
		values[field["key"]] = value
	return values


func _add_field_grid(container: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	container.add_child(grid)
	return grid


func _add_field(grid: GridContainer, caption: String, hint: String) -> LineEdit:
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 132
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(label)

	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size.x = 156
	field.placeholder_text = hint
	field.tooltip_text = caption
	grid.add_child(field)
	return field


func _on_create_pressed() -> void:
	var width: Variant = _read_numeric_value(_width_field, "Grid width", true, 1, MAX_WHOLE_NUMBER)
	if width == null:
		return
	var depth: Variant = _read_numeric_value(_depth_field, "Grid depth", true, 1, MAX_WHOLE_NUMBER)
	if depth == null:
		return
	var stories: Variant = _read_numeric_value(_stories_field, "Stories", true, 1, MAX_WHOLE_NUMBER)
	if stories == null:
		return
	var cell_scale: Variant = _read_numeric_value(_scale_field, "Cell scale", false, 0.0)
	if cell_scale == null:
		return
	if cell_scale == 0.0:
		_show_field_error(_scale_field, "Cell scale must be greater than zero.")
		return
	var enemy_count: Variant = _read_numeric_value(_enemies_field, "Enemy count", true, 0, MAX_WHOLE_NUMBER)
	if enemy_count == null:
		return
	create_requested.emit(width, depth, cell_scale, enemy_count, stories, _firing_windows.button_pressed)


func _read_numeric_value(
	field: LineEdit, caption: String, is_integer: bool, minimum: Variant, maximum: Variant = null
) -> Variant:
	var text := field.text.strip_edges()
	var value: Variant
	if is_integer:
		value = _parse_integer(text)
		if value == null:
			_show_field_error(field, "%s needs a whole number within the supported range." % caption)
			return null
	else:
		if text.is_valid_float():
			value = text.to_float()
		if value == null or not is_finite(value):
			_show_field_error(field, "%s needs a finite number." % caption)
			return null
		value = text.to_float()
	if value < minimum:
		_show_field_error(field, "%s must be at least %s." % [caption, minimum])
		return null
	if maximum != null and value > maximum:
		_show_field_error(field, "%s must be at most %s." % [caption, maximum])
		return null
	return value


func _parse_integer(text: String) -> Variant:
	if not text.is_valid_int():
		return null
	var negative := text.begins_with("-")
	var digits := text.lstrip("+-").lstrip("0")
	if digits.is_empty():
		return 0
	var limit := "9223372036854775807"
	if negative:
		limit = "9223372036854775808"
	if digits.length() > limit.length():
		return null
	if digits.length() == limit.length() and digits.casecmp_to(limit) > 0:
		return null
	if negative:
		return ("-" + digits).to_int()
	return digits.to_int()


func _show_field_error(field: LineEdit, message: String) -> void:
	set_status(message, true)
	if field.is_inside_tree():
		field.grab_focus()
		_field_scroll.ensure_control_visible(field)
		field.select_all()
