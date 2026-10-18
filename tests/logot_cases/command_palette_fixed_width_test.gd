extends LogotTestCase

func _init() -> void:
	id = "command_palette_fixed_width"
	display_name = "Fixed performance widget retains horizontal reachability"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	print("USER_DATA_DIR_PROOF=", OS.get_user_data_dir())
	var console = ctx.console
	var display = console._get_active_display()
	var window: Window = display.get_window()
	var previous_size := window.size
	var previous_method: String = display.get_current_input_method()
	var previous_scale: float = display.get_render_scale_percent("command_palette", "keyboard")
	var previous_visible: bool = console.control.visible
	window.size = Vector2i(320, 844)
	display.hide_command_entry_mode(false)
	display.set_current_input_method("keyboard")
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	console.control.visible = true
	await ctx.wait_frames(8)
	display.line_edit.text = "/dev/performance/overview/"
	display.on_text_changed_autocomplete(display.line_edit.text)
	await ctx.wait_seconds(0.3)
	var column = display._autocomplete_column_nodes[display._autocomplete_active_column_index]
	var widget: Control = column._embedded_widget
	ctx.check("actual built-in performance overview mounted", widget != null and widget.get_script().resource_path == "res://addons/logot/widgets/performance_overview_widget.gd")
	if widget != null:
		var scroll: ScrollContainer = display._command_autocomplete_scroll
		ctx.check("actual viewport320 with narrow toolbar", display.get_viewport_rect().size.x == 320 and scroll.size.x < 220, str(scroll.get_global_rect()))
		ctx.check("consumer retains its hard minimum", widget.get_combined_minimum_size().x >= 210 and widget.size.x >= widget.get_combined_minimum_size().x, str(widget.size))
		ctx.check("column owns complete hard widget extent", widget.get_global_rect().end.x <= column.get_global_rect().end.x, "widget=%s column=%s" % [widget.get_global_rect(), column.get_global_rect()])
		var right_in_content := widget.get_global_rect().end.x - scroll.get_global_rect().position.x + scroll.scroll_horizontal
		scroll.scroll_horizontal = int(scroll.get_h_scroll_bar().max_value)
		await ctx.wait_frames(3)
		ctx.check("maximum scroll range reaches complete widget", scroll.scroll_horizontal + scroll.size.x >= right_in_content, "right=%s max=%s" % [right_in_content, scroll.scroll_horizontal])
		# Preview columns may follow the widget, so full-end scroll can pass it.
		# Scroll to the reachable widget edge and prove actual pixels lie inside.
		scroll.scroll_horizontal = maxi(0, int(ceil(right_in_content - scroll.size.x)))
		await ctx.wait_frames(3)
		ctx.check("widget right edge is actually visible through scrolling", widget.get_global_rect().end.x >= scroll.get_global_rect().position.x and widget.get_global_rect().end.x <= scroll.get_global_rect().end.x + 1, "widget=%s scroll=%s" % [widget.get_global_rect(), scroll.get_global_rect()])
		ctx.check("overflow stays scrollable", scroll.get_h_scroll_bar().max_value > scroll.get_h_scroll_bar().page)
	display.reset_autocomplete()
	display.set_render_scale_percent("command_palette", "keyboard", previous_scale)
	display.set_current_input_method(previous_method)
	console.control.visible = previous_visible
	window.size = previous_size
