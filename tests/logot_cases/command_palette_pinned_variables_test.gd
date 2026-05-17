extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_pinned_variables"
	display_name = "Command Palette Pinned Variables"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	var address := "tests/command_palette_pin"
	console.add_display_variable(address, func(): return "visible")
	console.pin_display_variable(address)

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
	console._close_command_entry_view()
