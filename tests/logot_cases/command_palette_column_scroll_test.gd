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
