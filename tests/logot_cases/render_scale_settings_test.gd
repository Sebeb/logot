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
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	ctx.check("current input method switches to keyboard", display.get_current_input_method() == LogotDisplay.INPUT_METHOD_KEYBOARD)
