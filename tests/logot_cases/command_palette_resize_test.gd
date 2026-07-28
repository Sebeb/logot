extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "command_palette_resize"
	display_name = "Command Palette Resize"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	# Headless defaults to a 64x64 window, which leaves no room to resize into.
	var window: Window = display.get_window()
	var previous_window_size: Vector2i = window.size
	window.size = Vector2i(1280, 720)
	await ctx.wait_frames(2)

	if console.control != null:
		console.control.visible = true
	if console.line_edit != null:
		console.line_edit.text = ""
		console.line_edit.grab_focus()

	# The handle is a pointer affordance, so the palette must be in its non-touch layout.
	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	display.hide_command_entry_mode(false)
	display.reset_autocomplete()
	display._command_palette_height_override = 0.0
	await ctx.wait_frames()

	console.line_edit.text = "/"
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(2)

	var command_popup = console.control.get_node_or_null("AutocompleteOverlay/CommandAutocompletePopup")
	ctx.check("command palette is visible", command_popup != null and command_popup.visible)
	if command_popup == null:
		return

	var handle = console.control.get_node_or_null("AutocompleteOverlay/CommandPaletteResizeHandle")
	ctx.check("resize handle exists and is visible", handle != null and handle.visible)
	if handle == null:
		return

	var handle_rect: Rect2 = handle.get_global_rect()
	var popup_rect: Rect2 = command_popup.get_global_rect()
	ctx.check(
		"handle sits above the palette",
		handle_rect.end.y <= popup_rect.position.y + 1.0,
		"handle_bottom=%s popup_top=%s" % [handle_rect.end.y, popup_rect.position.y]
	)
	ctx.check(
		"handle is horizontally centred on the palette",
		absf(handle_rect.get_center().x - popup_rect.get_center().x) <= 1.0,
		"handle_center=%s popup_center=%s" % [handle_rect.get_center().x, popup_rect.get_center().x]
	)
	ctx.check("handle is on screen", handle_rect.position.y >= 0.0, "handle_top=%s" % handle_rect.position.y)

	var default_height: float = float(display._get_command_palette_default_height())
	var max_height: float = display._get_command_palette_max_height()
	var min_height: float = minf(default_height * 0.5, max_height)

	# Dragging upwards past the top of the window clamps to the available space,
	# leaving room for the handle itself.
	display._set_command_palette_height_override(max_height + 4000.0)
	await ctx.wait_frames(2)
	ctx.check(
		"height clamps to the window",
		is_equal_approx(display._command_palette_height_override, max_height),
		"override=%s max=%s" % [display._command_palette_height_override, max_height]
	)
	handle_rect = handle.get_global_rect()
	ctx.check("handle stays on screen at max height", handle_rect.position.y >= 0.0, "handle_top=%s" % handle_rect.position.y)

	# Dragging downwards past the floor clamps to half the default height.
	display._set_command_palette_height_override(1.0)
	await ctx.wait_frames(2)
	ctx.check(
		"height clamps to half the default height",
		is_equal_approx(display._command_palette_height_override, min_height),
		"override=%s min=%s" % [display._command_palette_height_override, min_height]
	)

	# Drive the real drag: press on the handle, move up 40px, release.
	display._set_command_palette_height_override(min_height)
	await ctx.wait_frames(2)
	var grab_point: Vector2 = handle.get_global_rect().get_center()
	_emit_handle_button(handle, grab_point, true)
	_emit_handle_motion(handle, grab_point - Vector2(0.0, 40.0))
	_emit_handle_button(handle, grab_point - Vector2(0.0, 40.0), false)
	await ctx.wait_frames(2)

	var resized_height: float = minf(maxf(min_height + 40.0, min_height), max_height)
	ctx.check(
		"dragging up by 40px grows the palette by 40px",
		absf(display._command_palette_height_override - resized_height) <= 1.0,
		"override=%s expected=%s" % [display._command_palette_height_override, resized_height]
	)
	ctx.check("drag released", not display._command_palette_resize_dragging)
	await ctx.wait_frames(2)
	popup_rect = command_popup.get_global_rect()
	ctx.check(
		"palette adopts the dragged height",
		absf(popup_rect.size.y - resized_height) <= 1.0,
		"popup_height=%s expected=%s" % [popup_rect.size.y, resized_height]
	)
	handle_rect = handle.get_global_rect()
	ctx.check(
		"handle follows the resized palette",
		handle_rect.end.y <= popup_rect.position.y + 1.0,
		"handle_bottom=%s popup_top=%s" % [handle_rect.end.y, popup_rect.position.y]
	)

	# The dragged height survives a settings round trip.
	var config := ConfigFile.new()
	display._save_custom_settings(config)
	display._command_palette_height_override = 0.0
	display._load_custom_settings(config)
	ctx.check(
		"dragged height persists through save/load",
		is_equal_approx(display._command_palette_height_override, resized_height),
		"override=%s expected=%s" % [display._command_palette_height_override, resized_height]
	)

	# The drag released above wrote a height to the real settings file; put it back.
	display._command_palette_height_override = 0.0
	display._save_filter_settings()
	display.reset_autocomplete()
	await ctx.wait_seconds(0.25)
	ctx.check("resize handle hides with the palette", not handle.visible)

	window.size = previous_window_size


func _emit_handle_button(handle: Control, at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.global_position = at
	event.position = at - handle.get_global_rect().position
	handle.gui_input.emit(event)


func _emit_handle_motion(handle: Control, at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.global_position = at
	event.position = at - handle.get_global_rect().position
	handle.gui_input.emit(event)
