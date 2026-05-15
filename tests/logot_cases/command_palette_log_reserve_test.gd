extends LogotTestCase


func _init() -> void:
	id = "command_palette_log_reserve"
	display_name = "Command Palette Log Reserve"
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

	for index in range(24):
		console.print_line("Command palette reserve line %02d" % index)

	await ctx.wait_frames()
	display.hide_command_entry_mode(false)
	display.reset_autocomplete()
	display.rebuild_display()
	await ctx.wait_frames()

	var initial_reserved_height: float = display.get_command_palette_log_reserved_height()
	ctx.check("no palette reserve before command palette opens", is_zero_approx(initial_reserved_height), "height=%s" % initial_reserved_height)

	console.line_edit.text = "/"
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(2)

	var reserved_height: float = display.get_command_palette_log_reserved_height()
	var command_popup = console.control.get_node_or_null("AutocompleteOverlay/CommandAutocompletePopup")
	ctx.check("command palette is visible", command_popup != null and command_popup.visible)
	ctx.check("command palette reserves log space", reserved_height > 0.0, "height=%s" % reserved_height)

	if command_popup != null and display.rich_label != null:
		var log_bottom: float = display.rich_label.get_global_rect().end.y
		var popup_top: float = command_popup.get_global_rect().position.y
		ctx.check(
			"log bottom sits above command palette",
			log_bottom <= popup_top + 1.0,
			"log_bottom=%s popup_top=%s" % [log_bottom, popup_top]
		)

	display.reset_autocomplete()
	await ctx.wait_seconds(0.25)
	ctx.check(
		"command palette reserve clears after palette closes",
		is_zero_approx(display.get_command_palette_log_reserved_height()),
		"height=%s" % display.get_command_palette_log_reserved_height()
	)
