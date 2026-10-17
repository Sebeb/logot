extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_column_scroll"
	display_name = "Command Palette Column Scroll"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	var list := LogotDisplay.AutocompleteCommandColumn.new()
	list.configure_theme(display._history_autocomplete_popup)
	list.size = Vector2(280.0, 224.0)
	var rows: Array[Dictionary] = []
	for row_index in range(24):
		rows.append({
			"label": "option_%02d" % row_index,
			"has_children": false,
			"can_submit": true,
		})

	list.set_column_data(rows, {}, 12, false, 28)
	var selected_center := list._get_row_offset_from_scroll(list._scroll_row, 12) + list._get_row_height(12) * 0.5
	var visible_center := list._get_visible_content_height_for_scroll(list._scroll_row) * 0.5
	ctx.check(
		"middle selection is centred",
		absf(selected_center - visible_center) <= float(list._row_height) * 0.5,
		"scroll=%s selected_center=%s visible_center=%s" % [list._scroll_row, selected_center, visible_center]
	)

	list.set_column_data(rows, {}, 0, false, 28)
	ctx.check("first selection scrolls to top", list._scroll_row == 0, "scroll=%s" % list._scroll_row)

	var last_row := rows.size() - 1
	list.set_column_data(rows, {}, last_row, false, 28)
	var visible_range := list.get_visible_row_range()
	ctx.check(
		"last selection scrolls to bottom and remains visible",
		list._scroll_row == list._get_max_scroll_row() and last_row >= visible_range.x and last_row < visible_range.y,
		"scroll=%s max=%s visible=%s" % [list._scroll_row, list._get_max_scroll_row(), visible_range]
	)

	# A horizontal scrollbar reduces the actual clipping viewport after the
	# nominal column height has already been chosen.
	var clipped_height: int = display._calculate_command_autocomplete_column_viewport_height(224.0, 28.0, true, 224)
	ctx.check("horizontal scrollbar height is removed from column viewport", clipped_height == 196, "height=%s" % clipped_height)
	list.custom_minimum_size.y = clipped_height
	list.size.y = clipped_height
	list.ensure_current_is_visible()
	visible_range = list.get_visible_row_range()
	ctx.check(
		"last selection remains visible in clipped multi-column viewport",
		list._scroll_row == list._get_max_scroll_row() and last_row >= visible_range.x and last_row < visible_range.y,
		"scroll=%s max=%s visible=%s" % [list._scroll_row, list._get_max_scroll_row(), visible_range]
	)

	# Exercise the native tooltip API against the same virtual-row geometry as input.
	list.set_column_data(rows, {}, 12, false, 28)
	ctx.check("scrollbar has a separate nonrow gutter", list.get_row_scrollbar_reserve_width() > 0.0)
	var hovered := list.get_visible_row_range().x
	var point := _point_for_row(list, hovered)
	ctx.check("tooltip hit point is an actual visible row", point.y >= 0.0)
	ctx.check("hovered row owns tooltip independent of selection", list.get_tooltip(point) == rows[hovered]["label"])
	ctx.check("full row right edge has same tooltip", list.get_tooltip(Vector2(list._get_column_content_width() - 1.0, point.y)) == rows[hovered]["label"])
	for outside in [Vector2(-1, point.y), Vector2(list._get_column_content_width(), point.y), Vector2(10, -1), Vector2(10, list.size.y)]:
		ctx.check("nonrow bounds have no tooltip %s" % outside, list.get_tooltip(outside).is_empty())
	var replacement: Array[Dictionary] = [{"label": "Full authored Unicode label: café and a deliberately long description that cannot fit the ordinary row", "has_children": false}]
	list.set_column_data(replacement, {}, 0, false, 28)
	point = _point_for_row(list, 0)
	ctx.check("replacement tooltip is complete and not stale", list.get_tooltip(point) == replacement[0]["label"])
	ctx.check("bottom aligned blank space has no tooltip", list.get_tooltip(Vector2(10, 0)).is_empty())
	list.set_column_data(replacement, {}, 0, false, 28, true, "Heading", "Description")
	ctx.check("column heading has no row tooltip", list.get_tooltip(Vector2(10, 1)).is_empty())
	var mixed: Array[Dictionary] = [{"label": "One", "two_line": true}, {"label": "Two", "has_children": false}]
	list.set_column_data(mixed, {}, 0, false, 28)
	ctx.check("mixed geometry includes a taller row", list._get_row_height(0) > list._get_row_height(1))
	point = _point_for_row(list, 1)
	ctx.check("mixed-height hit test selects the actual second label", list.get_tooltip(point) == "Two")
	var groups: Array[Dictionary] = [{"label": "Group", "is_group_header": true}, {"label": "Member", "has_children": false}]
	list.set_column_data(groups, {}, 1, false, 28)
	point = _point_for_row(list, 0)
	if point.y >= 0.0:
		ctx.check("group heading does not impersonate command tooltip", list.get_tooltip(point).is_empty())
	list.set_column_data([], {}, -1, false, 28)
	ctx.check("empty column does not retain tooltip", list.get_tooltip(Vector2(10, 10)).is_empty())
	list.free()


func _point_for_row(column, row_index: int) -> Vector2:
	for y in range(int(column.size.y)):
		var point := Vector2(10, y + 0.5)
		if column._get_row_index_at_position(point) == row_index:
			return point
	return Vector2(-1, -1)
