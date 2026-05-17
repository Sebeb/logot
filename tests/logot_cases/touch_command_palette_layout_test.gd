extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


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
		console.line_edit.grab_focus()

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

	display.reset_autocomplete()
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_KEYBOARD, previous_keyboard_scale)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_TOUCH, previous_touch_scale)
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
