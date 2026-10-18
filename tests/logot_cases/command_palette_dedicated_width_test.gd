extends LogotTestCase

const ADDRESS := "test-dedicated-width/review"

func _init() -> void:
	id = "command_palette_dedicated_width"
	display_name = "Dedicated responsive content fits child-preview viewport"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	print("USER_DATA_DIR_PROOF=", OS.get_user_data_dir())
	var console = ctx.console
	var display = console._get_active_display()
	var window: Window = display.get_window()
	var old_size := window.size
	var old_method: String = display.get_current_input_method()
	var old_scale: float = display.get_render_scale_percent("command_palette", "keyboard")
	var old_visible: bool = console.control.visible
	# Native headless omits the production Tests action. Add an equivalent
	# sibling through its real HBox layout so the input is not falsely full-width.
	var action := Button.new()
	action.text = "Tests"
	display.line_edit.get_parent().add_child(action)
	var body := VBoxContainer.new()
	body.set_script(preload("res://tests/fixtures/readable_palette_content.gd"))
	var label := Label.new()
	label.text = "Complete child-preview detail: beginning and final words must both fit the actual dedicated palette."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	label.owner = body
	var scene := PackedScene.new()
	ctx.check("responsive content packs", scene.pack(body) == OK)
	body.free()
	console.add_widget(ADDRESS, scene, "", "Reviews", 1, Vector2(0, 200), "Complete dedicated review")
	window.size = Vector2i(390, 844)
	display.set_current_input_method("keyboard")
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	console.control.visible = true
	await ctx.wait_frames(8)
	display.show_command_entry_mode("/" + ADDRESS + "/", false)
	await ctx.wait_seconds(0.3)
	var column = display._autocomplete_column_nodes[display._autocomplete_active_column_index]
	var original_widget: Control = column._embedded_widget
	column._set_scroll_slot(column._get_max_scroll_slot())
	display.autocomplete_select_next()
	await ctx.wait_seconds(0.3)
	column = display._autocomplete_column_nodes[display._autocomplete_active_column_index]
	column._set_scroll_slot(0)
	var scroll: Rect2 = display._command_autocomplete_scroll.get_global_rect()
	var popup: Rect2 = display._command_autocomplete_popup.get_global_rect()
	var clip: Rect2 = column._content_clip.get_global_rect().intersection(scroll)
	var widget: Control = column._embedded_widget
	ctx.check("dedicated input is the exercised route", display.is_command_entry_mode())
	ctx.check("actual390 viewport has sibling-constrained palette", display.get_viewport_rect().size.x == 390 and scroll.size.x < 366, str(scroll))
	ctx.check("child preview actually opened", display._autocomplete_active_column_index + 1 < display._autocomplete_column_nodes.size())
	ctx.check("child selection preserves responsive widget", widget == original_widget)
	ctx.check("active column fits actual scroll", column.size.x <= scroll.size.x + 1, "column=%s scroll=%s" % [column.get_global_rect(), scroll])
	ctx.check("active column fits popup", column.get_global_rect().position.x >= popup.position.x - 1 and column.get_global_rect().end.x <= popup.end.x + 1, str(column.get_global_rect()))
	ctx.check("embedded body right fits visible content", widget.get_global_rect().end.x <= clip.end.x + 1, "widget=%s clip=%s" % [widget.get_global_rect(), clip])
	ctx.check("actual child text right fits visible content", widget.get_child(0).get_global_rect().end.x <= clip.end.x + 1)
	console.remove_widget(ADDRESS)
	display.hide_command_entry_mode()
	display.reset_autocomplete()
	action.queue_free()
	await ctx.wait_frames(2)
	display.set_render_scale_percent("command_palette", "keyboard", old_scale)
	display.set_current_input_method(old_method)
	console.control.visible = old_visible
	window.size = old_size
