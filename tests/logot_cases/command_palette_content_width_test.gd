extends LogotTestCase

const ADDRESS := "test-visible-width/review"

func _init() -> void:
	id = "command_palette_content_width"
	display_name = "Ordinary palette content fits its toolbar viewport"
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
	var body := VBoxContainer.new()
	body.set_script(preload("res://tests/fixtures/readable_palette_content.gd"))
	var label := Label.new()
	label.text = "Beginning and ending of complete ordinary review detail remain inside the toolbar-constrained palette."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)
	label.owner = body
	var scene := PackedScene.new()
	ctx.check("responsive content packs", scene.pack(body) == OK)
	body.free()
	console.add_widget(ADDRESS, scene, "", "Reviews", 1, Vector2(0, 200), "Complete ordinary review")
	window.size = Vector2i(390, 844)
	display.hide_command_entry_mode(false)
	display.set_current_input_method("keyboard")
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	console.control.visible = true
	await ctx.wait_frames(8)
	display.line_edit.text = "/" + ADDRESS + "/"
	display.on_text_changed_autocomplete(display.line_edit.text)
	await ctx.wait_seconds(0.3)
	_check_visible_content(ctx, display, true)
	var original_widget: Control = display._autocomplete_column_nodes[display._autocomplete_active_column_index]._embedded_widget
	for width in [320, 390]:
		window.size = Vector2i(width, 844)
		await ctx.wait_frames(8)
		await ctx.wait_seconds(0.3)
		_check_visible_content(ctx, display, true)
		ctx.check("resize preserves mounted widget identity", display._autocomplete_column_nodes[display._autocomplete_active_column_index]._embedded_widget == original_widget)
		ctx.check("resize preserves exact selected input", display.line_edit.text == "/" + ADDRESS + "/")
	# The dedicated input has no toolbar and must retain its separate sizing.
	display.show_command_entry_mode("/" + ADDRESS + "/", false)
	await ctx.wait_seconds(0.3)
	_check_visible_content(ctx, display, false)
	console.remove_widget(ADDRESS)
	display.hide_command_entry_mode()
	display.reset_autocomplete()
	display.set_render_scale_percent("command_palette", "keyboard", old_scale)
	display.set_current_input_method(old_method)
	console.control.visible = old_visible
	window.size = old_size

func _check_visible_content(ctx, display, ordinary: bool) -> void:
	var column = display._autocomplete_column_nodes[display._autocomplete_active_column_index]
	var widget: Control = column._embedded_widget
	ctx.check("real responsive content mounted ordinary=%s" % ordinary, widget != null)
	if widget == null:
		return
	ctx.check("current logical viewport matches window", display.get_viewport_rect().size.x == display.get_window().size.x)
	var scroll: Rect2 = display._command_autocomplete_scroll.get_global_rect()
	var clip: Rect2 = column._content_clip.get_global_rect().intersection(scroll)
	ctx.check("route has expected toolbar width", (scroll.size.x < display.get_viewport_rect().size.x - 24) if ordinary else (scroll.size.x >= 366), str(scroll))
	ctx.check("active column fits actual scroll width", column.size.x <= scroll.size.x + 1, "column=%s scroll=%s" % [column.size, scroll])
	ctx.check("embedded content right fits visible clip", widget.get_global_rect().end.x <= clip.end.x + 1, "widget=%s clip=%s" % [widget.get_global_rect(), clip])
	ctx.check("embedded content beginning fits visible clip", widget.get_global_rect().position.x >= clip.position.x - 1)
	ctx.check("actual label right fits visible clip", widget.get_child(0).get_global_rect().end.x <= clip.end.x + 1)
