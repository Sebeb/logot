extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "render_scale_settings"
	display_name = "Render Scale Settings"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return
	var root_matches: Array = display._build_tier_matches("", "")
	var console_root_match: Dictionary = {}
	var pins_root_match: Dictionary = {}
	for match_data in root_matches:
		if str((match_data as Dictionary).get("tier", "")) == "console":
			console_root_match = match_data
		elif str((match_data as Dictionary).get("tier", "")) == "pins":
			pins_root_match = match_data
	ctx.check("console root command is in the console group", console_root_match.get("group_name", "") == "console")
	ctx.check("pins root command is in the console group", pins_root_match.get("group_name", "") == "console")

	var render_scale_matches: Array = display._build_tier_matches("console/settings/render_scale/", "")
	for match_data in render_scale_matches:
		ctx.check("render scale commands have no group", not (match_data as Dictionary).has("group_name"))

	var fresh_display := LogotDisplay.new()
	ctx.check(
		"keyboard log defaults to 100",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_KEYBOARD), 100.0)
	)
	ctx.check(
		"keyboard command palette defaults to 100",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_KEYBOARD), 100.0)
	)
	ctx.check(
		"keyboard pinned variables defaults to 100",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES, LogotDisplay.INPUT_METHOD_KEYBOARD), 100.0)
	)
	ctx.check(
		"controller log defaults to 120",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_CONTROLLER), 120.0)
	)
	ctx.check(
		"controller command palette defaults to 120",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_CONTROLLER), 120.0)
	)
	ctx.check(
		"controller pinned variables defaults to 100",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES, LogotDisplay.INPUT_METHOD_CONTROLLER), 100.0)
	)
	ctx.check(
		"touch log defaults to 125",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_TOUCH), 125.0)
	)
	ctx.check(
		"touch command palette defaults to 135",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE, LogotDisplay.INPUT_METHOD_TOUCH), 135.0)
	)
	ctx.check(
		"touch pinned variables defaults to 110",
		is_equal_approx(fresh_display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES, LogotDisplay.INPUT_METHOD_TOUCH), 110.0)
	)
	fresh_display.free()

	var previous_controller_log_scale: float = display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_CONTROLLER)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_CONTROLLER, 150.0)
	ctx.check(
		"controller log setting updates",
		is_equal_approx(display.get_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_CONTROLLER), 150.0)
	)
	display.set_render_scale_percent(LogotDisplay.RENDER_SCALE_TARGET_LOG, LogotDisplay.INPUT_METHOD_CONTROLLER, previous_controller_log_scale)

	display.set_current_input_method(LogotDisplay.INPUT_METHOD_CONTROLLER)
	ctx.check("current input method switches to controller", display.get_current_input_method() == LogotDisplay.INPUT_METHOD_CONTROLLER)
	display._pinned_corner_redirects[LogotDisplay.PINNED_OVERLAY_CORNER_TOP_LEFT] = true
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH)
	ctx.check("current input method switches to touch", display.get_current_input_method() == LogotDisplay.INPUT_METHOD_TOUCH)
	ctx.check("touch input disables pinned corner side swapping", display._pinned_corner_redirects.is_empty())
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	ctx.check("current input method switches to keyboard", display.get_current_input_method() == LogotDisplay.INPUT_METHOD_KEYBOARD)
