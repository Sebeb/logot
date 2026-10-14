extends LogotTestCase
const Display = preload("res://addons/logot/logot_display.gd")
class Content extends Control:
	func is_logot_palette_content() -> bool: return true
	func get_logot_palette_preferred_width() -> float: return 900.0

func _init() -> void:
	id = "command_palette_content"
	display_name = "Scrollable Palette Content"
	scene_path = "res://Main.tscn"
	fail_fast = true

func run(ctx) -> void:
	var display = ctx.console._get_active_display()
	var column := Display.AutocompleteCommandColumn.new()
	column.size = Vector2(350, 500)
	var content := Content.new()
	content.custom_minimum_size = Vector2(100, 1600)
	column.set_embedded_widget(content, "test/content")
	column.set_column_data([], {}, -1, false, 28, true, "Details")
	ctx.check("content-only column has a scrollbar", column._row_scrollbar.visible)
	var top: float = content.position.y
	ctx.check("down arrow consumes content scroll", column.scroll_content_before_selection(1))
	ctx.check("scrolling reveals another line", content.position.y == top - 28 and content.visible)
	column.set_column_data([], {}, -1, false, 28, true, "Details")
	ctx.check("refresh preserves content position", content.position.y == top - 28)
	for index in range(100): column.scroll_content_before_selection(1)
	ctx.check("bottom is reachable", column._get_scroll_slot() == column._get_max_scroll_slot())
	ctx.check("down resumes selection at bottom", not column.scroll_content_before_selection(1))
	ctx.check("up scrolls toward top", column.scroll_content_before_selection(-1))
	ctx.check("body clips below heading", column._content_clip.position.y == column._header_height)
	var rows: Array[Dictionary] = []
	for index in range(30): rows.append({"label": "option-%d" % index})
	column.set_column_data(rows, {}, 0, false, 28)
	column._set_scroll_slot(column._get_content_widget_slots())
	column.set_column_data(rows, {}, 25, false, 28)
	var visible: Vector2i = column.get_visible_row_range()
	ctx.check("selected trailing option remains visible", 25 >= visible.x and 25 < visible.y)
	ctx.check("up navigates later options before returning to body", not column.scroll_content_before_selection(-1))
	var previous_size: Vector2i = display.get_window().size
	var previous_scale: float = display.get_render_scale_percent("command_palette", "keyboard")
	var previous_method: String = display.get_current_input_method()
	display.get_window().size = Vector2i(1440, 900)
	display.set_current_input_method("keyboard")
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	await ctx.wait_frames(2)
	var active: Dictionary = {}
	var inactive: Dictionary = {}
	var active_layout := {"width": 300}
	var inactive_layout := {"width": 300}
	display._resolve_autocomplete_column_width(column, active, display._autocomplete_active_column_index, active_layout, "", 0)
	display._resolve_autocomplete_column_width(column, inactive, display._autocomplete_active_column_index + 1, inactive_layout, "", 0)
	ctx.check("active prose column expands wider", active.width > inactive.width)
	ctx.check("inactive prose column respects compact cap", inactive.width <= 380)
	var normal: int = display._get_command_autocomplete_max_column_width()
	display.set_render_scale_percent("command_palette", "keyboard", 200)
	ctx.check("column width cap scales with rendering", display._get_command_autocomplete_max_column_width() == normal * 2)
	column.configure_theme(display._history_autocomplete_popup)
	ctx.check("scaled measurement uses the drawn font", column.get_theme_font_size("font_size") == column._font_size)
	var expected_width := int(ceil(column._font.get_string_size("controller", HORIZONTAL_ALIGNMENT_LEFT, -1, column._font_size).x))
	ctx.check("labels measure at render size", display._measure_autocomplete_text_width(column, "controller") == expected_width)
	column._set_scroll_slot(0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	ctx.check("pressed wheel scrolls content", column._handle_mouse_wheel(wheel) and column._get_scroll_slot() > 0)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	ctx.check("wheel scrolls upward", column._handle_mouse_wheel(wheel) and column._get_scroll_slot() == 0)
	wheel.pressed = false
	ctx.check("wheel release does not scroll twice", not column._handle_mouse_wheel(wheel))
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	column.configure_theme(display._history_autocomplete_popup)
	var long_rows: Array[Dictionary] = [{"label": "PLAYGROUND-PRIVATE-PG-FIXTURE-WITH-A-LONG-OPTION-NAME", "value_loaded": true}]
	var compact: Dictionary = display._measure_command_autocomplete_column_layout(column, "plain/", long_rows, "Options", "", 0, 0, false)
	var wide: Dictionary = display._measure_command_autocomplete_column_layout(column, "plain/", long_rows, "Options", "", 0, 0, true)
	ctx.check("ordinary active columns expand for long names", wide.width > compact.width and wide.width <= 960)
	display.set_render_scale_percent("command_palette", "keyboard", previous_scale)
	display.set_current_input_method(previous_method)
	display.get_window().size = previous_size
	column.free()
