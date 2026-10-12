extends LogotTestCase

func _init() -> void:
	id = "responsive_console_input"
	display_name = "Responsive Console Input"
	fail_fast = false

func run(ctx) -> void:
	var console: Node = ctx.console
	var display: Control = console._get_active_display()
	var viewport: Viewport = display.get_viewport()
	var previous_size: Vector2i = viewport.size if viewport is SubViewport else console.get_window().size
	var previous_method: String = display.get_current_input_method()
	console.control.visible = true
	console.line_edit.grab_focus()
	console.line_edit.text = "/console/help"
	console.line_edit.caret_column = 6
	for width in [780, 520]:
		if viewport is SubViewport: viewport.size = Vector2i(width, 1688)
		else: console.get_window().size = Vector2i(width, 1688)
		for method in ["keyboard", "touch"]:
			display.set_current_input_method(method)
			await ctx.wait_frames(4)
			var bounds := viewport.get_visible_rect()
			ctx.check("input fits %s %s" % [width, method], bounds.encloses(console.line_edit.get_global_rect()), str(console.line_edit.get_global_rect()))
			ctx.check("input remains useful %s %s" % [width, method], console.line_edit.size.x >= 200.0)
			ctx.check("caret remains stable", console.line_edit.caret_column == 6)
			ctx.check("focus remains stable", console.line_edit.has_focus())
			ctx.check("all original filters retained", display._collapsed_level_buttons.size() == 7)
			for record in display._collapsed_level_buttons.values():
				ctx.check("filter stays visible in viewport", record.button.is_visible_in_tree() and bounds.encloses(record.button.get_global_rect()), str(record.button.get_global_rect()))
	for level in display.LOG_LEVELS:
		var before: int = display._get_level_visibility(level)
		var button: Button = display._collapsed_level_buttons[level].button
		button.pressed.emit()
		ctx.check("existing filter handler changes mode", display._get_level_visibility(level) != before)
		button.pressed.emit()
		button.pressed.emit()
		ctx.check("filter cycle restores mode", display._get_level_visibility(level) == before)
	ctx.check("filter actions preserve caret", console.line_edit.caret_column == 6)
	ctx.check("filter actions preserve focus", console.line_edit.has_focus())
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(3)
	ctx.check("native command palette still opens", display._is_command_popup_visible())
	console.add_input_history("/console/help")
	ctx.check("native history retained", console.console_history.has("/console/help"))
	display.set_current_input_method(previous_method)
	if viewport is SubViewport: viewport.size = previous_size
	else: console.get_window().size = previous_size
