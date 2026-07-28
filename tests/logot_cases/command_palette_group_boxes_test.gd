extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")
const ROW_HEIGHT := 28.0
const COLUMN_WIDTH := 320.0


func _init() -> void:
	id = "command_palette_group_boxes"
	display_name = "Command Palette Group Boxes"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var display = ctx.console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	# state          -> header + two options
	#   state/limits -> nested header + one option
	#   state/       -> nested headerless box + one option
	# .loose         -> top-level headerless box + one option
	var matches: Array = [
		{"tier": "alpha", "group_name": "state"},
		{"tier": "beta", "group_name": "state"},
		{"tier": "gamma", "group_name": "state/limits"},
		{"tier": "delta", "group_name": "state/"},
		{"tier": "epsilon", "group_name": ".loose"},
		{"tier": "zeta", "group_name": ""},
	]
	var build_result: Dictionary = display._build_command_autocomplete_rows("", matches, -1, true)
	var rows: Array[Dictionary] = []
	for row_variant in build_result.get("rows", []):
		rows.append(row_variant as Dictionary)

	var labels: Array[String] = []
	for row_data in rows:
		var prefix := "#" if bool(row_data.get("is_group_header", false)) else ""
		labels.append("%s%s@%d" % [prefix, str(row_data.get("label", "")), _depth(row_data)])
	var layout := ",".join(labels)
	ctx.check(
		"headers, nesting and headerless boxes lay out in order",
		layout == "#state@1,alpha@1,beta@1,#limits@2,gamma@2,delta@2,epsilon@1,zeta@0",
		layout
	)

	# Every box opens exactly once and closes exactly once, so no group is left dangling.
	for level_index in range(2):
		var starts := 0
		var ends := 0
		for row_data in rows:
			var levels := LogotDisplay.AutocompleteCommandColumn.get_group_levels(row_data)
			if level_index >= levels.size():
				continue
			if bool((levels[level_index] as Dictionary).get("start", false)):
				starts += 1
			if bool((levels[level_index] as Dictionary).get("end", false)):
				ends += 1
		ctx.check(
			"level %d opens and closes evenly" % level_index,
			starts == 2 and ends == 2,
			"starts=%d ends=%d" % [starts, ends]
		)

	var list := LogotDisplay.AutocompleteCommandColumn.new()
	list.configure_theme(display._history_autocomplete_popup)
	list.size = Vector2(COLUMN_WIDTH, ROW_HEIGHT * float(rows.size()) + 8.0)
	list.set_column_data(rows, {}, -1, false, int(ROW_HEIGHT))

	# The "state" box spans its header plus everything nested inside it, and its side
	# edges must run edge to edge on every row in between so the outline never breaks.
	var state_rows := range(0, 6)
	var previous_bottom := -1.0
	for row_index in state_rows:
		var row_rect := Rect2(0.0, ROW_HEIGHT * float(row_index), COLUMN_WIDTH, ROW_HEIGHT)
		var levels := LogotDisplay.AutocompleteCommandColumn.get_group_levels(rows[row_index])
		var box_rect: Rect2 = list._get_group_level_rect(row_rect, levels, 0)
		if previous_bottom >= 0.0:
			ctx.check(
				"row %d continues the outer border" % row_index,
				is_equal_approx(box_rect.position.y, previous_bottom),
				"top=%s previous_bottom=%s" % [box_rect.position.y, previous_bottom]
			)
		previous_bottom = box_rect.position.y + box_rect.size.y

	# The header paints inside its own border rather than across the full row.
	var header_rect := Rect2(0.0, 0.0, COLUMN_WIDTH, ROW_HEIGHT)
	var header_levels := LogotDisplay.AutocompleteCommandColumn.get_group_levels(rows[0])
	var header_box: Rect2 = list._get_group_level_rect(header_rect, header_levels, 0)
	var header_fill: Rect2 = list._get_group_interior_rect(header_rect, header_levels)
	ctx.check(
		"header fill stays inside the group border",
		header_fill.position.x >= header_box.position.x and header_fill.end.x <= header_box.end.x and header_fill.size.x > 0.0,
		"fill=%s box=%s" % [header_fill, header_box]
	)
	ctx.check(
		"header fill is narrower than the row",
		header_fill.size.x < COLUMN_WIDTH,
		"fill_width=%s row_width=%s" % [header_fill.size.x, COLUMN_WIDTH]
	)
	ctx.check(
		"header joins the option below it",
		is_equal_approx(header_box.end.y, ROW_HEIGHT),
		"header_bottom=%s row_height=%s" % [header_box.end.y, ROW_HEIGHT]
	)

	# A nested box is inset from its parent so the two borders stay visible.
	var nested_rect := Rect2(0.0, ROW_HEIGHT * 3.0, COLUMN_WIDTH, ROW_HEIGHT)
	var nested_levels := LogotDisplay.AutocompleteCommandColumn.get_group_levels(rows[3])
	ctx.check("nested header sits two levels deep", nested_levels.size() == 2, "levels=%d" % nested_levels.size())
	if nested_levels.size() == 2:
		var outer_box: Rect2 = list._get_group_level_rect(nested_rect, nested_levels, 0)
		var inner_box: Rect2 = list._get_group_level_rect(nested_rect, nested_levels, 1)
		ctx.check(
			"nested box is inset inside its parent",
			inner_box.position.x > outer_box.position.x and inner_box.end.x < outer_box.end.x,
			"inner=%s outer=%s" % [inner_box, outer_box]
		)
		ctx.check(
			"nested rows indent their content clear of the parent border",
			LogotDisplay.AutocompleteCommandColumn.get_group_content_indent(rows[3]) > 0.0
		)

	# Scrolling into a group pins its nearest header, including from a nested box.
	ctx.check("outer group pins its own header", list._sticky_group_header_indices[1] == 0, "sticky=%d" % list._sticky_group_header_indices[1])
	ctx.check("nested group pins the nested header", list._sticky_group_header_indices[4] == 3, "sticky=%d" % list._sticky_group_header_indices[4])
	ctx.check(
		"headerless nested rows fall back to the outer header",
		list._sticky_group_header_indices[5] == 0,
		"sticky=%d" % list._sticky_group_header_indices[5]
	)
	ctx.check("headerless top-level rows pin nothing", list._sticky_group_header_indices[6] == -1, "sticky=%d" % list._sticky_group_header_indices[6])
	ctx.check("ungrouped rows pin nothing", list._sticky_group_header_indices[7] == -1, "sticky=%d" % list._sticky_group_header_indices[7])

	list.free()


func _depth(row_data: Dictionary) -> int:
	return LogotDisplay.AutocompleteCommandColumn.get_group_levels(row_data).size()
