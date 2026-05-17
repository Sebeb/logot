extends LogotTestCase


func _init() -> void:
	id = "touch_edge_toggle"
	display_name = "Touch Edge Toggle"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	console._set_touch_mode_enabled(true)
	await ctx.wait_frames(1)

	var dock: Control = console._touch_toggle_dock
	ctx.check("touch edge dock exists", dock != null and is_instance_valid(dock))
	if dock == null or not is_instance_valid(dock):
		return

	ctx.check("touch edge dock is visible", dock.visible)
	ctx.check("command palette button exists", console._touch_command_palette_button != null and is_instance_valid(console._touch_command_palette_button))
	ctx.check("full log button exists", console._touch_full_log_button != null and is_instance_valid(console._touch_full_log_button))
	ctx.check("touch edge buttons are thumb sized", console.TOUCH_EDGE_BUTTON_SIZE.x >= 88.0 and console.TOUCH_EDGE_BUTTON_SIZE.y >= 104.0, "size=%s" % console.TOUCH_EDGE_BUTTON_SIZE)

	var viewport_size: Vector2 = console.get_viewport().get_visible_rect().size
	ctx.check("touch edge dock starts on right edge", is_equal_approx(dock.global_position.x + dock.size.x, viewport_size.x), "dock=%s viewport=%s" % [dock.get_global_rect(), viewport_size])

	console._on_touch_command_palette_button_pressed()
	await ctx.wait_frames(1)
	ctx.check("command palette button opens command entry mode", display.is_command_entry_mode())
	ctx.check("command palette button shows console control", console.control.visible)
	ctx.check("command palette hides log body", not display.rich_label.visible)
	ctx.check("touch edge dock hides while command palette is open", not dock.visible)
	ctx.check("touch command palette does not focus text input immediately", console.line_edit == null or not console.line_edit.has_focus())

	console._on_touch_full_log_button_pressed()
	await ctx.wait_frames(1)
	ctx.check("full log button exits command entry mode", not display.is_command_entry_mode())
	ctx.check("full log button keeps full log visible", console.control.visible)
	ctx.check("full log button shows log body", display.rich_label.visible)
	ctx.check("touch edge dock hides while full log is open", not dock.visible)

	console.toggle_console(false)
	await ctx.wait_frames(1)
	ctx.check("touch edge dock returns when console closes", dock.visible)

	var start_position: Vector2 = dock.global_position + dock.size * 0.5
	console._begin_touch_toggle_drag(start_position, console.TOUCH_TOGGLE_ACTION_LOG, -1)
	console._update_touch_toggle_drag(Vector2(2.0, start_position.y - 90.0))
	ctx.check("drag keeps original edge until release", console._touch_toggle_edge == console.TOUCH_TOGGLE_EDGE_RIGHT)
	console._end_touch_toggle_drag(Vector2(2.0, start_position.y - 90.0))
	await ctx.wait_frames(1)

	ctx.check("drag snaps dock to left edge", console._touch_toggle_edge == console.TOUCH_TOGGLE_EDGE_LEFT)
	ctx.check("left edge dock is flush", is_equal_approx(dock.global_position.x, 0.0), "dock=%s" % dock.get_global_rect())
	ctx.check("drag does not open full log", not console.control.visible)

	if console.control != null:
		console.control.visible = true
	if display._sidebar_toggle_btn != null:
		display._sidebar_toggle_btn.button_pressed = true
	await ctx.wait_frames(2)

	var sidebar = display._sidebar
	ctx.check("touch sidebar exists", sidebar != null and is_instance_valid(sidebar))
	if sidebar == null or not is_instance_valid(sidebar):
		return

	var sidebar_rect: Rect2 = (sidebar as Control).get_global_rect()
	ctx.check(
		"touch sidebar covers full viewport width",
		sidebar_rect.position.x <= 0.0 and sidebar_rect.end.x >= viewport_size.x,
		"sidebar=%s viewport=%s" % [sidebar_rect, viewport_size]
	)
	ctx.check("touch sidebar hides log container", not display._logot_container.visible)
	ctx.check("touch sidebar close button is visible", sidebar._close_button != null and sidebar._close_button.is_visible_in_tree())

	console._handle_escape_input()
	await ctx.wait_frames(1)
	ctx.check("escape closes touch sidebar", not sidebar.visible and display._logot_container.visible)

	if display._sidebar_toggle_btn != null:
		display._sidebar_toggle_btn.button_pressed = true
	await ctx.wait_frames(1)
	if sidebar._close_button != null:
		sidebar._close_button.pressed.emit()
	await ctx.wait_frames(1)
	ctx.check("touch sidebar close button closes sidebar", not sidebar.visible and display._logot_container.visible)
