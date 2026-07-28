extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_hidden_path"
	display_name = "Command Palette Hidden Path"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	console._hidden_command_palette_path = ""
	await _open_palette_at(ctx, console, display, "/console/")

	# ` stashes the open palette's path and hides the console.
	await _press_key(ctx, console, KEY_QUOTELEFT)
	ctx.check("backtick hides the console", not console.control.visible)
	ctx.check("backtick leaves command entry mode", not display.is_command_entry_mode())
	ctx.check(
		"backtick remembers the palette path",
		console._hidden_command_palette_path == "/console/",
		"hidden_path=%s" % console._hidden_command_palette_path
	)

	# / opens a fresh palette at the root without consuming the stashed path.
	await _press_key(ctx, console, KEY_SLASH)
	ctx.check("slash reopens the palette", console.control.visible and display.is_command_entry_mode())
	ctx.check("slash opens at the root", console.line_edit.text == "/", "text=%s" % console.line_edit.text)
	ctx.check(
		"slash keeps the remembered path",
		console._hidden_command_palette_path == "/console/",
		"hidden_path=%s" % console._hidden_command_palette_path
	)

	# Closing that palette still leaves the stashed path for ~ to restore.
	console._close_command_entry_view()
	await ctx.wait_frames()
	ctx.check("closing the palette hides the console", not console.control.visible)

	await _press_key(ctx, console, KEY_QUOTELEFT, true)
	ctx.check("tilde reopens the palette", console.control.visible and display.is_command_entry_mode())
	ctx.check(
		"tilde restores the remembered path",
		console.line_edit.text == "/console/",
		"text=%s" % console.line_edit.text
	)
	ctx.check(
		"restoring consumes the remembered path",
		console._hidden_command_palette_path.is_empty(),
		"hidden_path=%s" % console._hidden_command_palette_path
	)

	# Hiding again overwrites the remembered path, and ` restores it while closed.
	_set_palette_text(console, display, "/console/settings")
	await ctx.wait_frames()
	await _press_key(ctx, console, KEY_QUOTELEFT)
	ctx.check(
		"hiding again overwrites the remembered path",
		console._hidden_command_palette_path == "/console/settings",
		"hidden_path=%s" % console._hidden_command_palette_path
	)

	await _press_key(ctx, console, KEY_QUOTELEFT)
	ctx.check("backtick reopens the palette", console.control.visible and display.is_command_entry_mode())
	ctx.check(
		"backtick restores the remembered path",
		console.line_edit.text == "/console/settings",
		"text=%s" % console.line_edit.text
	)

	# A root palette is not worth remembering: ` falls back to the console.
	_set_palette_text(console, display, "/")
	await ctx.wait_frames()
	await _press_key(ctx, console, KEY_QUOTELEFT)
	ctx.check("root palette closes into the console", console.control.visible)
	ctx.check("root palette leaves command entry mode", not display.is_command_entry_mode())
	ctx.check(
		"root palette is not remembered",
		console._hidden_command_palette_path.is_empty(),
		"hidden_path=%s" % console._hidden_command_palette_path
	)


func _open_palette_at(ctx, console, display, path: String):
	console._open_command_entry_view()
	await ctx.wait_frames()
	_set_palette_text(console, display, path)
	await ctx.wait_frames()
	ctx.check("palette opens at %s" % path, display.is_command_entry_mode() and console.control.visible)


func _set_palette_text(console, display, path: String) -> void:
	console.line_edit.text = path
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)


func _press_key(ctx, console, keycode: int, shift := false):
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.shift_pressed = shift
	event.pressed = true
	if keycode == KEY_SLASH:
		event.unicode = "/".unicode_at(0)
	console._input(event)
	await ctx.wait_frames()
