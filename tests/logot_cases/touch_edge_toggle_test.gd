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

	var viewport_size: Vector2 = console.get_viewport().get_visible_rect().size
	ctx.check("touch edge dock starts on right edge", is_equal_approx(dock.global_position.x + dock.size.x, viewport_size.x), "dock=%s viewport=%s" % [dock.get_global_rect(), viewport_size])

	console._on_touch_command_palette_button_pressed()
	await ctx.wait_frames(1)
	ctx.check("command palette button opens command entry mode", display.is_command_entry_mode())
	ctx.check("command palette button shows console control", console.control.visible)
	ctx.check("command palette hides log body", not display.rich_label.visible)

	console._on_touch_full_log_button_pressed()
	await ctx.wait_frames(1)
	ctx.check("full log button exits command entry mode", not display.is_command_entry_mode())
	ctx.check("full log button keeps full log visible", console.control.visible)
	ctx.check("full log button shows log body", display.rich_label.visible)

	var start_position: Vector2 = dock.global_position + dock.size * 0.5
	console._begin_touch_toggle_drag(start_position, console.TOUCH_TOGGLE_ACTION_LOG, -1)
	console._update_touch_toggle_drag(Vector2(2.0, start_position.y - 90.0))
	console._end_touch_toggle_drag(Vector2(2.0, start_position.y - 90.0))
	await ctx.wait_frames(1)

	ctx.check("drag snaps dock to left edge", console._touch_toggle_edge == console.TOUCH_TOGGLE_EDGE_LEFT)
	ctx.check("left edge dock is flush", is_equal_approx(dock.global_position.x, 0.0), "dock=%s" % dock.get_global_rect())
