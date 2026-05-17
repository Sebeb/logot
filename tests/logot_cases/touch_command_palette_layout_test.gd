extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")

var _long_press_count := 0


func _init() -> void:
	id = "touch_command_palette_layout"
	display_name = "Touch Command Palette Layout"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	if console.control != null:
		console.control.visible = true
		if console.line_edit != null:
			console.line_edit.text = ""
			console.line_edit.release_focus()

		_long_press_count = 0
		console.add_command(
			"test/long_press_no_hide",
			_record_long_press,
			[],
			0,
			"Long press test command."
		)

	var previous_keyboard_scale: float = display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_KEYBOARD)
	var previous_touch_scale: float = display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_TOUCH)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_KEYBOARD, 100.0)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_TOUCH, 100.0)

	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	var keyboard_row_height: int = display._get_scaled_autocomplete_item_height()
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH)
	var touch_row_height: int = display._get_scaled_autocomplete_item_height()
	ctx.check(
		"touch command palette rows are twice keyboard height",
		touch_row_height == keyboard_row_height * 2,
		"keyboard=%s touch=%s" % [keyboard_row_height, touch_row_height]
	)

	console.line_edit.text = "/console/"
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(2)

	var command_popup = console.control.get_node_or_null("AutocompleteOverlay/CommandAutocompletePopup")
	ctx.check("touch command palette is visible", command_popup != null and command_popup.visible)

	var visible_column_count := 0
	var visible_column_index := -1
	for column_index in range(display._autocomplete_column_nodes.size()):
		var column_node = display._autocomplete_column_nodes[column_index]
		if column_node is Control and column_node.visible:
			visible_column_count += 1
			visible_column_index = column_index

	ctx.check(
		"touch command palette shows exactly one column",
		visible_column_count == 1,
		"visible=%s active=%s total=%s" % [visible_column_count, display._autocomplete_active_column_index, display._autocomplete_column_nodes.size()]
	)
	ctx.check(
		"touch command palette shows active column",
		visible_column_index == display._autocomplete_active_column_index,
		"visible_index=%s active=%s" % [visible_column_index, display._autocomplete_active_column_index]
	)

	if command_popup != null:
		var viewport_rect: Rect2 = display.get_viewport_rect()
		var popup_rect: Rect2 = command_popup.get_global_rect()
		ctx.check(
			"touch command palette takes full viewport width",
			is_equal_approx(popup_rect.size.x, viewport_rect.size.x),
			"popup_width=%s viewport_width=%s" % [popup_rect.size.x, viewport_rect.size.x]
		)
		ctx.check(
			"touch command palette takes full viewport height",
			is_equal_approx(popup_rect.size.y, viewport_rect.size.y),
			"popup_height=%s viewport_height=%s" % [popup_rect.size.y, viewport_rect.size.y]
		)

		console.line_edit.text = "/"
		console.line_edit.caret_column = console.line_edit.text.length()
		display.on_text_changed_autocomplete(console.line_edit.text)
		await ctx.wait_frames(2)
		var root_list = display._autocomplete_column_nodes[display._autocomplete_active_column_index] if display._autocomplete_active_column_index >= 0 and display._autocomplete_active_column_index < display._autocomplete_column_nodes.size() else null
		ctx.check("touch root column exists", root_list is LogotDisplay.AutocompleteCommandColumn)
		if root_list is LogotDisplay.AutocompleteCommandColumn:
			var typed_root_list := root_list as LogotDisplay.AutocompleteCommandColumn
			var max_scroll: int = typed_root_list._get_max_scroll_row()
			var previous_scroll: int = typed_root_list._scroll_row
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = false
			typed_root_list._gui_input(wheel)
			ctx.check(
				"touch command palette wheel scrolls rows",
				max_scroll == 0 or typed_root_list._scroll_row > previous_scroll,
				"before=%s after=%s max=%s" % [previous_scroll, typed_root_list._scroll_row, max_scroll]
			)
			var scroll_before_drag: int = typed_root_list._scroll_row
			typed_root_list._begin_pointer_press(Vector2(10.0, 10.0), -1)
			typed_root_list._update_pointer_press(Vector2(10.0, 10.0 - float(touch_row_height) * 1.5))
			typed_root_list._end_pointer_press(Vector2(10.0, 10.0 - float(touch_row_height) * 1.5), -1)
			ctx.check(
				"touch command palette drag scrolls rows",
				max_scroll == 0 or typed_root_list._scroll_row > scroll_before_drag,
				"before=%s after=%s max=%s" % [scroll_before_drag, typed_root_list._scroll_row, max_scroll]
			)
			var first_selectable_row := -1
			var console_row := -1
			for row_index in range(typed_root_list.get_rows().size()):
				var row_data: Dictionary = typed_root_list.get_rows()[row_index]
				if not bool(row_data.get("is_group_header", false)):
					if first_selectable_row < 0:
						first_selectable_row = row_index
					if str(row_data.get("label", "")) == "console":
						console_row = row_index
			if first_selectable_row >= 0:
				ctx.check("touch rows are not persistently selected", typed_root_list._get_row_selection_state(first_selectable_row) == 0)
				typed_root_list._set_transient_highlight(first_selectable_row)
				ctx.check("touch row highlights during tap feedback", typed_root_list._get_row_selection_state(first_selectable_row) == 2)
				typed_root_list._schedule_transient_highlight_clear()
				await ctx.wait_seconds(0.14)
				ctx.check("touch row highlight clears after tap feedback", typed_root_list._get_row_selection_state(first_selectable_row) == 0)
			if console_row >= 0:
				var root_active_index: int = display._autocomplete_active_column_index
				display._on_command_autocomplete_column_row_activated(console_row, typed_root_list)
				await ctx.wait_seconds(0.18)
				ctx.check(
					"touch row tap navigates right to next column",
					display._autocomplete_active_column_index > root_active_index,
					"before=%s after=%s" % [root_active_index, display._autocomplete_active_column_index]
				)
				display.autocomplete_move_left()
				await ctx.wait_seconds(0.18)
				ctx.check(
					"touch back navigation returns to previous column",
					display._autocomplete_active_column_index == root_active_index,
					"expected=%s actual=%s" % [root_active_index, display._autocomplete_active_column_index]
				)

		console.line_edit.text = "/test/"
		console.line_edit.caret_column = console.line_edit.text.length()
		display.on_text_changed_autocomplete(console.line_edit.text)
		await ctx.wait_frames(2)
		var test_list = display._autocomplete_column_nodes[display._autocomplete_active_column_index] if display._autocomplete_active_column_index >= 0 and display._autocomplete_active_column_index < display._autocomplete_column_nodes.size() else null
		if test_list is LogotDisplay.AutocompleteCommandColumn:
			var typed_test_list := test_list as LogotDisplay.AutocompleteCommandColumn
			for row_index in range(typed_test_list.get_rows().size()):
				var row_data: Dictionary = typed_test_list.get_rows()[row_index]
				if str(row_data.get("label", "")) == "long_press_no_hide":
					display._on_command_autocomplete_column_row_long_pressed(row_index, typed_test_list)
					break
		await ctx.wait_frames(1)
		ctx.check("touch long press executes command", _long_press_count == 1, "count=%s" % _long_press_count)
		ctx.check("touch long press keeps command palette open", command_popup != null and command_popup.visible and display.is_command_entry_mode())

		display._enter_touch_parameter_command("timers/start")
		await ctx.wait_frames(1)
		ctx.check("touch parameter command focuses input", console.line_edit != null and console.line_edit.has_focus())
		ctx.check("touch parameter command adds trailing space", console.line_edit != null and console.line_edit.text == "/timers/start ")

		var layout_list := LogotDisplay.AutocompleteCommandColumn.new()
		layout_list.configure_theme(display._history_autocomplete_popup)
		layout_list.size = Vector2(180.0, 240.0)
		var rows: Array[Dictionary] = [{
			"label": "very_long_option_label_that_cannot_share_a_line",
			"value_text": "very_long_exposed_value",
			"has_children": false,
			"can_submit": false,
		}]
		var layout: Dictionary = display._measure_command_autocomplete_column_layout(layout_list, "", rows, "Layout", "")
		layout_list.set_column_data(rows, layout, -1, false, keyboard_row_height)
		ctx.check("keyboard row becomes two-line when value cannot fit", bool(rows[0].get("two_line", false)))
		ctx.check("keyboard two-line row is double height", is_equal_approx(layout_list._get_row_height(0), float(keyboard_row_height * 2)))
		layout_list.set_column_data(rows, layout, -1, false, touch_row_height)
		ctx.check("touch two-line row is double height", is_equal_approx(layout_list._get_row_height(0), float(touch_row_height * 2)))

	display.reset_autocomplete()
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_KEYBOARD, previous_keyboard_scale)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_TOUCH, previous_touch_scale)
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)


func _record_long_press() -> void:
	_long_press_count += 1
