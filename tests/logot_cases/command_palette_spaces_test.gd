extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_spaces"
	display_name = "Command Palette Spaces"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	display._command_palette_spaces.clear()
	display._active_command_palette_space = 0
	console._hidden_command_palette_path = ""

	console._open_command_entry_view()
	await ctx.wait_frames()
	_set_palette_text(console, display, "/console/")
	await ctx.wait_frames()
	ctx.check("palette opens at /console/", display.is_command_entry_mode() and console.control.visible)

	# Cmd/Ctrl+Alt+N banks the current path and makes that space current.
	await _press_number(ctx, console, KEY_1, true)
	ctx.check(
		"alt+1 saves the current path",
		display.get_command_palette_space_path(1) == "/console/",
		"space1=%s" % display.get_command_palette_space_path(1)
	)
	ctx.check("alt+1 enters space 1", display.get_active_command_palette_space() == 1)
	ctx.check("alt+1 leaves the path alone", console.line_edit.text == "/console/", "text=%s" % console.line_edit.text)

	_set_palette_text(console, display, "/dev/")
	await ctx.wait_frames()
	await _press_number(ctx, console, KEY_2, true)
	ctx.check(
		"alt+2 saves a second space",
		display.get_command_palette_space_path(2) == "/dev/",
		"space2=%s" % display.get_command_palette_space_path(2)
	)

	# Switching restores the target space.
	await _press_number(ctx, console, KEY_1)
	ctx.check("cmd+1 restores space 1", console.line_edit.text == "/console/", "text=%s" % console.line_edit.text)
	ctx.check("cmd+1 enters space 1", display.get_active_command_palette_space() == 1)

	# Leaving a space banks wherever it was left, without an explicit save.
	_set_palette_text(console, display, "/console/settings")
	await ctx.wait_frames()
	await _press_number(ctx, console, KEY_2)
	ctx.check("cmd+2 restores space 2", console.line_edit.text == "/dev/", "text=%s" % console.line_edit.text)
	ctx.check(
		"leaving space 1 banks its current path",
		display.get_command_palette_space_path(1) == "/console/settings",
		"space1=%s" % display.get_command_palette_space_path(1)
	)

	await _press_number(ctx, console, KEY_1)
	ctx.check(
		"space 1 reopens where it was left",
		console.line_edit.text == "/console/settings",
		"text=%s" % console.line_edit.text
	)

	# A partial filter is part of the position, so it survives the round trip.
	_set_palette_text(console, display, "/console/set")
	await ctx.wait_frames()
	await _press_number(ctx, console, KEY_2)
	await _press_number(ctx, console, KEY_1)
	ctx.check(
		"a partial filter survives a space switch",
		console.line_edit.text == "/console/set",
		"text=%s" % console.line_edit.text
	)

	# An unsaved space is still usable: it opens at the root.
	await _press_number(ctx, console, KEY_5)
	ctx.check("an unsaved space opens at root", console.line_edit.text == "/", "text=%s" % console.line_edit.text)
	ctx.check("an unsaved space becomes current", display.get_active_command_palette_space() == 5)
	ctx.check(
		"leaving space 1 for an unsaved space still banks it",
		display.get_command_palette_space_path(1) == "/console/set",
		"space1=%s" % display.get_command_palette_space_path(1)
	)

	# Shift+number stays available to command shortcuts.
	await _press_number(ctx, console, KEY_1, false, true)
	ctx.check("shift+1 is not a space switch", display.get_active_command_palette_space() == 5)
	ctx.check("shift+1 leaves the path alone", console.line_edit.text == "/", "text=%s" % console.line_edit.text)

	# Spaces address the input, not the popup, so a filter matching nothing can still be left.
	_set_palette_text(console, display, "/zzz-no-such-command")
	await ctx.wait_frames()
	await _press_number(ctx, console, KEY_1)
	ctx.check(
		"a dead-end filter can still switch spaces",
		console.line_edit.text == "/console/set",
		"text=%s" % console.line_edit.text
	)
	ctx.check(
		"the dead-end filter is banked with its space",
		display.get_command_palette_space_path(5) == "/zzz-no-such-command",
		"space5=%s" % display.get_command_palette_space_path(5)
	)

	# A palette reopened after a close sits at root, so leaving from root must not overwrite
	# what the active space was explicitly given.
	_set_palette_text(console, display, "/")
	await ctx.wait_frames()
	await _press_number(ctx, console, KEY_2)
	ctx.check(
		"leaving a space from root keeps its saved path",
		display.get_command_palette_space_path(1) == "/console/set",
		"space1=%s" % display.get_command_palette_space_path(1)
	)
	await _press_number(ctx, console, KEY_1)
	ctx.check(
		"the space still reopens at its saved path",
		console.line_edit.text == "/console/set",
		"text=%s" % console.line_edit.text
	)


func _set_palette_text(console, display, path: String) -> void:
	console.line_edit.text = path
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)


## Both command modifiers are set so the event reads as Cmd/Ctrl on any host platform.
func _press_number(ctx, console, keycode: int, alt := false, shift := false):
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.meta_pressed = true
	event.ctrl_pressed = true
	event.alt_pressed = alt
	event.shift_pressed = shift
	event.pressed = true
	console._input(event)
	await ctx.wait_frames()
