extends PanelContainer

signal create_requested(width: int, depth: int, cell_scale: float, enemy_count: int, stories: int,
		player_free_move: bool, enemy_free_move: bool)

enum Section { ARENA, PLAYER, ENEMIES, PISTOL, AR }

const SECTION_NAMES := ["Arena", "Player", "Enemies", "Pistol", "AR"]
const SECTION_ACCENTS := [
	Color("8bd0c6"), Color("8cc7ec"), Color("eea993"), Color("e7c889"), Color("b8b8ef"),
]

# Vector2i grid dimensions use signed 32-bit coordinates.
const MAX_WHOLE_NUMBER: int = 2147483647
const TEXT_COLOR := Color("ecf2f7")
const MUTED_COLOR := Color("afc2d2")
const ERROR_COLOR := Color("ffac9f")
const INPUT_BACKGROUND := Color("223543")
const INPUT_BORDER := Color("3b5568")

var _width_field: LineEdit
var _depth_field: LineEdit
var _stories_field: LineEdit
var _scale_field: LineEdit
var _enemies_field: LineEdit
var _player_movement: OptionButton
var _enemy_movement: OptionButton
var _tabs: Array[Button] = []
var _scrolls: Array[ScrollContainer] = []
var _level_grids: Array[GridContainer] = []
var _balance_grids: Array[GridContainer] = []
var _balance_inputs: Array[Dictionary] = []
var _page_style: StyleBoxFlat
var _submit_button: Button
var _status_label: Label


func _init() -> void:
	custom_minimum_size.x = 472.0
	add_theme_stylebox_override("panel", _style(Color("182431"), Color("385267"), 12))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Level tuning"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	content.add_child(title)

	_build_sections(content)
	var arena := _level_grids[Section.ARENA]
	_width_field = _add_field(arena, "Grid width", "Cells", Section.ARENA)
	_depth_field = _add_field(arena, "Grid depth", "Cells", Section.ARENA)
	_stories_field = _add_field(arena, "Stories", "Number of floors", Section.ARENA)
	_scale_field = _add_field(arena, "Cell scale", "World units per cell", Section.ARENA)
	_player_movement = _add_movement_choice(_level_grids[Section.PLAYER])
	var enemies := _level_grids[Section.ENEMIES]
	_enemies_field = _add_field(enemies, "Enemy count", "Enemies", Section.ENEMIES)
	_enemy_movement = _add_movement_choice(enemies)

	_submit_button = Button.new()
	_submit_button.text = "Create Next Level"
	_submit_button.custom_minimum_size.y = 42
	_submit_button.add_theme_font_size_override("font_size", 16)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		_submit_button.add_theme_color_override(state, Color("102934"))
	_submit_button.add_theme_stylebox_override("normal", _style(Color("86c8be"), Color("9fd8cf")))
	_submit_button.add_theme_stylebox_override("hover", _style(Color("a0d9cf"), Color("c3e7e1")))
	_submit_button.add_theme_stylebox_override("pressed", _style(Color("6eada4"), Color("86c8be")))
	_submit_button.pressed.connect(_on_create_pressed)
	content.add_child(_submit_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 14)
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
		stories: int = 1, player_free_move: bool = false, enemy_free_move: bool = false) -> void:
	_width_field.text = str(width)
	_depth_field.text = str(depth)
	_stories_field.text = str(stories)
	_scale_field.text = str(cell_scale)
	_enemies_field.text = str(enemy_count)
	_player_movement.select(1 if player_free_move else 0)
	_enemy_movement.select(1 if enemy_free_move else 0)


func set_balance_fields(fields: Array[Dictionary]) -> void:
	for grid in _balance_grids:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
		grid.hide()
	_balance_inputs.clear()

	for field in fields:
		var section := _field_section(field)
		var grid := _balance_grids[section]
		var hint := "Whole number" if field["is_integer"] else "Number"
		var caption := _section_caption(field["label"], section)
		var input := _add_field(grid, caption, hint, section)
		if field.has("value"):
			input.text = str(field["value"])
		_balance_inputs.append({"field": field.duplicate(), "input": input})
		grid.show()


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


func _build_sections(content: VBoxContainer) -> void:
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 5)
	content.add_child(tab_row)

	var section_panel := PanelContainer.new()
	section_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_style = _style(Color("121e2a"), Color("426071"), 8)
	_page_style.content_margin_left = 12.0
	_page_style.content_margin_right = 12.0
	_page_style.content_margin_top = 12.0
	_page_style.content_margin_bottom = 12.0
	section_panel.add_theme_stylebox_override("panel", _page_style)
	content.add_child(section_panel)
	var pages := Control.new()
	pages.custom_minimum_size.y = 220.0
	section_panel.add_child(pages)

	var tab_group := ButtonGroup.new()
	for section in range(SECTION_NAMES.size()):
		var tab := _add_tab(tab_row, section, tab_group)
		_tabs.append(tab)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.follow_focus = true
		pages.add_child(scroll)
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_scrolls.append(scroll)
		var groups := VBoxContainer.new()
		groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		groups.add_theme_constant_override("separation", 7)
		scroll.add_child(groups)
		var level_grid := _add_field_grid(groups)
		var balance_grid := _add_field_grid(groups)
		level_grid.visible = section < Section.PISTOL
		balance_grid.hide()
		_level_grids.append(level_grid)
		_balance_grids.append(balance_grid)
	_select_section(Section.ARENA)


func _add_tab(row: HBoxContainer, section: int, group: ButtonGroup) -> Button:
	var accent: Color = SECTION_ACCENTS[section]
	var tab := Button.new()
	tab.text = SECTION_NAMES[section]
	tab.toggle_mode = true
	tab.button_group = group
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.custom_minimum_size.y = 36.0
	tab.add_theme_font_size_override("font_size", 14)
	tab.add_theme_color_override("font_color", MUTED_COLOR)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		tab.add_theme_color_override(state, accent)
	tab.add_theme_stylebox_override("normal", _style(Color("1d2c3a"), Color("324858")))
	tab.add_theme_stylebox_override("hover", _style(Color("263747"), accent.darkened(0.50)))
	var selected := _style(Color("223543").lerp(accent, 0.14), accent.darkened(0.38))
	selected.border_width_bottom = 2
	tab.add_theme_stylebox_override("pressed", selected)
	tab.add_theme_stylebox_override("hover_pressed", selected)
	tab.pressed.connect(_select_section.bind(section))
	row.add_child(tab)
	return tab


func _select_section(section: int) -> void:
	for index in range(_scrolls.size()):
		_scrolls[index].visible = index == section
		_tabs[index].set_pressed_no_signal(index == section)
	var accent: Color = SECTION_ACCENTS[section]
	_page_style.border_color = accent.darkened(0.50)


func _field_section(field: Dictionary) -> int:
	var named := str(field.get("section", "")).to_lower()
	for section in range(SECTION_NAMES.size()):
		if named == SECTION_NAMES[section].to_lower():
			return section
	var key := str(field["key"])
	if key == "pillar_tiles":
		return Section.ARENA
	if key.begins_with("enemy_"):
		return Section.ENEMIES
	if key.begins_with("pistol_"):
		return Section.PISTOL
	if key.begins_with("ar_"):
		return Section.AR
	return Section.PLAYER


func _section_caption(caption: String, section: int) -> String:
	var prefix := "Enemy " if section == Section.ENEMIES else str(SECTION_NAMES[section]) + " "
	var trimmed := caption.trim_prefix(prefix)
	return trimmed.left(1).to_upper() + trimmed.substr(1)


func _style(background: Color, border: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	return style


func _add_field_grid(container: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 7)
	container.add_child(grid)
	return grid


func _add_field_label(grid: GridContainer, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 218.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(label)


func _add_field(grid: GridContainer, caption: String, hint: String, section: int) -> LineEdit:
	_add_field_label(grid, caption)
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(120.0, 30.0)
	field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	field.placeholder_text = hint
	field.tooltip_text = caption
	field.set_meta("section", section)
	field.add_theme_font_size_override("font_size", 15)
	field.add_theme_stylebox_override("normal", _style(INPUT_BACKGROUND, INPUT_BORDER))
	grid.add_child(field)
	return field


func _add_movement_choice(grid: GridContainer) -> OptionButton:
	_add_field_label(grid, "Movement")
	var movement := OptionButton.new()
	movement.add_item("Grid steps")
	movement.add_item("Free movement")
	movement.select(0)
	movement.custom_minimum_size = Vector2(120.0, 34.0)
	movement.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	movement.add_theme_font_size_override("font_size", 15)
	grid.add_child(movement)
	return movement


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
	create_requested.emit(width, depth, cell_scale, enemy_count, stories,
			_player_movement.selected == 1, _enemy_movement.selected == 1)


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
		var section: int = field.get_meta("section")
		_select_section(section)
		field.grab_focus()
		_scrolls[section].ensure_control_visible.call_deferred(field)
		field.select_all()
