extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_pinned_variables"
	display_name = "Command Palette Pinned Variables"
	scene_path = "res://Main.tscn"
	fail_fast = false


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	var address := "tests/command_palette_pin"
	console.add_display_variable(address, func(): return "visible")
	console.pin_display_variable(address)
	var long_value_address := "tests/command_palette_long_value"
	console.add_display_variable(long_value_address, func(): return "value ".repeat(80), Callable(), Callable(), true, "", 0, null, &"", func(): return "short label")
	console.pin_display_variable(long_value_address)
	var long_label_address := "tests/command_palette_long_label"
	console.add_display_variable(long_label_address, func(): return "visible", Callable(), Callable(), true, "", 0, null, &"", func(): return "long pinned label ".repeat(30))
	console.pin_display_variable(long_label_address)
	var multiline_value_address := "tests/command_palette_multiline_value"
	console.add_display_variable(multiline_value_address, func(): return "first line\nsecond line")
	console.pin_display_variable(multiline_value_address)
	var wrapping_value_address := "tests/command_palette_wrapping_value"
	console.add_display_variable(wrapping_value_address, func(): return "A declared prose value wraps beneath its label across every line required by the available column width.", Callable(), Callable(), true, "", 0, null, &"", Callable(), {"wrap_value": true})
	console.pin_display_variable(wrapping_value_address)
	var rich_text_value_address := "tests/command_palette_rich_text_value"
	console.pin(rich_text_value_address, "[color=#ff2e2ef2]Generation Cells[/color]")
	var root_matches: Array = display._build_tier_matches("", "")
	var pins_matches: Array = display._build_tier_matches("pins/", "")
	var encoded_address := address.uri_encode()
	var root_contains_pinned_address := false
	var pins_match: Dictionary = {}
	for match_data in root_matches:
		var tier := str((match_data as Dictionary).get("tier", ""))
		if tier == address:
			root_contains_pinned_address = true
	for match_data in pins_matches:
		if str((match_data as Dictionary).get("tier", "")) == "pins/%s" % encoded_address:
			pins_match = match_data
	ctx.check("pinned variable is absent from root autocomplete", not root_contains_pinned_address)
	ctx.check("pinned variable appears directly under pins", not pins_match.is_empty())
	ctx.check("pinned variable group is prioritized", int(pins_match.get("group_priority", 0)) < 0)

	console._set_touch_mode_enabled(false, false)
	if console.control != null:
		console.control.visible = false
	display.hide_command_entry_mode()
	await ctx.wait_frames(2)

	console._open_command_entry_view()
	await ctx.wait_frames(2)

	ctx.check("command palette opened command entry mode", display.is_command_entry_mode())
	ctx.check("command palette hides log body", display.rich_label != null and not display.rich_label.visible)
	ctx.check("command palette is not in touch mode", display.get_current_input_method() != LogotDisplay.INPUT_METHOD_TOUCH)
	ctx.check(
		"pinned variables show with command palette only",
		display._pinned_overlay_root != null and display._pinned_overlay_root.visible,
		"root=%s visible=%s" % [display._pinned_overlay_root, display._pinned_overlay_root.visible if display._pinned_overlay_root != null else false]
	)
	ctx.check(
		"pinned variable row is visible",
		display._pinned_overlay_rows.has(address) and display._pinned_overlay_rows[address].visible,
		"rows=%s" % [display._pinned_overlay_rows.keys()]
	)
	ctx.check(
		"long pinned values move beneath their title",
		bool(display._pinned_overlay_rows[long_value_address].get_meta("logot_pin_stacked_value", false)),
		"row=%s" % [display._pinned_overlay_rows[long_value_address].get_parsed_text()]
	)
	ctx.check(
		"wrapping pinned titles move their value beneath them",
		bool(display._pinned_overlay_rows[long_label_address].get_meta("logot_pin_stacked_value", false)),
		"row=%s" % [display._pinned_overlay_rows[long_label_address].get_parsed_text()]
	)
	ctx.check(
		"multiline pinned values retain their line breaks beneath the title",
		bool(display._pinned_overlay_rows[multiline_value_address].get_meta("logot_pin_stacked_value", false))
			and "first line\nsecond line" in display._pinned_overlay_rows[multiline_value_address].get_parsed_text(),
		"row=%s" % [display._pinned_overlay_rows[multiline_value_address].get_parsed_text()]
	)
	ctx.check(
		"declared-wrapping pinned values move beneath their title",
		bool(display._pinned_overlay_rows[wrapping_value_address].get_meta("logot_pin_stacked_value", false))
	)
	ctx.check("non-declaring display variables remain compact", not bool(display._get_display_variable_render_snapshot(address).get("wrap_value", false)))
	ctx.check("declared-wrapping snapshot exposes its declaration", bool(display._get_display_variable_render_snapshot(wrapping_value_address).get("wrap_value", false)))

	var mixed_column = LogotDisplay.AutocompleteCommandColumn.new()
	display.add_child(mixed_column)
	mixed_column.configure_theme(display)
	mixed_column.size = Vector2(260.0, 320.0)
	var mixed_rows: Array[Dictionary] = [
		{"label": "compact before", "value_text": "one", "measured_value_width": 40},
		{"label": "wrapped prose", "value_text": "This declared prose value needs several measured lines in the narrow test column.", "wrap_value": true, "measured_value_width": 400},
		{"label": "compact after", "value_text": "two", "measured_value_width": 40},
	]
	mixed_column.set_column_data(mixed_rows, {}, -1, false, 32)
	var wrapped_height: float = mixed_column._get_row_height(1)
	ctx.check("declared-wrapping column value uses N-line measured height", wrapped_height > 64.0, "height=%s rows=%s" % [wrapped_height, mixed_column.get_rows()])
	ctx.check("non-declaring column rows retain one-line height", is_equal_approx(mixed_column._get_row_height(0), 32.0) and is_equal_approx(mixed_column._get_row_height(2), 32.0))
	var third_row_y := mixed_column._get_rows_top_for_scroll(0) + mixed_column._get_row_height(0) + wrapped_height + 1.0
	ctx.check("mixed-height hit-testing resolves the row after wrapped prose", mixed_column._get_row_index_at_position(Vector2(10.0, third_row_y)) == 2, "y=%s prefix=%s" % [third_row_y, mixed_column._row_height_prefix])
	await ctx.capture_visual("declared_wrapping_column_and_overlay")
	ctx.check(
		"pinned custom values parse BBCode",
		"Generation Cells" in display._pinned_overlay_rows[rich_text_value_address].get_parsed_text()
			and not "[color=" in display._pinned_overlay_rows[rich_text_value_address].get_parsed_text(),
		"row=%s" % [display._pinned_overlay_rows[rich_text_value_address].get_parsed_text()]
	)

	# Both overlays share one canvas layer, so z_index alone decides who occludes whom.
	var popup = display._command_autocomplete_popup
	var handle = display._command_palette_resize_handle
	ctx.check(
		"command palette draws above the pinned variables",
		popup != null and popup.z_index > display._pinned_overlay_root.z_index,
		"palette_z=%s pinned_z=%s" % [popup.z_index if popup != null else null, display._pinned_overlay_root.z_index]
	)
	ctx.check(
		"resize handle draws above the pinned variables",
		handle != null and handle.z_index > display._pinned_overlay_root.z_index,
		"handle_z=%s pinned_z=%s" % [handle.z_index if handle != null else null, display._pinned_overlay_root.z_index]
	)
	ctx.check(
		"palette overlays share the pinned variables canvas",
		popup != null and popup.get_canvas() == display._pinned_overlay_root.get_canvas(),
		"palette_canvas=%s pinned_canvas=%s" % [
			popup.get_canvas() if popup != null else null,
			display._pinned_overlay_root.get_canvas(),
		]
	)

	console._set_touch_mode_enabled(true, false)
	await ctx.wait_frames(1)
	ctx.check(
		"touch command palette still suppresses pinned variables",
		display._pinned_overlay_root != null and not display._pinned_overlay_root.visible
	)

	console._set_touch_mode_enabled(false, false)
	await ctx.wait_frames(1)
	ctx.check(
		"leaving touch mode restores command palette pins",
		display._pinned_overlay_root != null and display._pinned_overlay_root.visible
	)

	console.unpin_display_variable(address)
	console.remove_display_variable(address)
	console.unpin_display_variable(long_value_address)
	console.remove_display_variable(long_value_address)
	console.unpin_display_variable(long_label_address)
	console.remove_display_variable(long_label_address)
	console.unpin_display_variable(multiline_value_address)
	console.remove_display_variable(multiline_value_address)
	console.unpin_display_variable(wrapping_value_address)
	console.remove_display_variable(wrapping_value_address)
	mixed_column.queue_free()
	console.unpin(rich_text_value_address)
	console._close_command_entry_view()
