extends LogotTestCase


func _init() -> void:
	id = "virtual_keyboard_safe_area"
	display_name = "Virtual Keyboard Safe Area"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	console.control.visible = true
	console._set_touch_mode_enabled(true, false)
	await ctx.wait_frames(2)

	console.set_process(false)
	var viewport_height: float = float(console.get_viewport().get_visible_rect().size.y)
	var keyboard_height: float = minf(20.0, maxf(1.0, viewport_height * 0.25))
	console._apply_virtual_keyboard_safe_area_height(keyboard_height)
	await ctx.wait_frames(2)

	var safe_bottom: float = viewport_height - keyboard_height
	ctx.check(
		"keyboard reserve is tracked",
		is_equal_approx(console.get_virtual_keyboard_safe_area_height(), keyboard_height),
		"height=%s" % console.get_virtual_keyboard_safe_area_height()
	)
	ctx.check(
		"display root reserves keyboard space",
		is_equal_approx(display.offset_bottom, -keyboard_height),
		"offset_bottom=%s" % display.offset_bottom
	)
	ctx.check(
		"log UI bottom sits above keyboard",
		console.control.get_global_rect().end.y <= safe_bottom + 1.0,
		"log_bottom=%s safe_bottom=%s" % [console.control.get_global_rect().end.y, safe_bottom]
	)
	ctx.check(
		"line edit sits above keyboard",
		console.line_edit.get_global_rect().end.y <= safe_bottom + 1.0,
		"line_edit_bottom=%s safe_bottom=%s" % [console.line_edit.get_global_rect().end.y, safe_bottom]
	)
	console._apply_virtual_keyboard_safe_area_height(0.0)
	console._set_touch_mode_enabled(false, false)
	console.set_process(true)
	await ctx.wait_frames(2)
	ctx.check(
		"keyboard reserve clears",
		is_zero_approx(console.get_virtual_keyboard_safe_area_height()) and is_zero_approx(display.offset_bottom),
		"height=%s offset_bottom=%s" % [console.get_virtual_keyboard_safe_area_height(), display.offset_bottom]
	)
