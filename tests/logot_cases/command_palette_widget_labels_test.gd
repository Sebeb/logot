extends LogotTestCase

const PREFIX := "test-readable/changes/0.0.1/"
const ADDRESS := PREFIX + "INTERNAL-RECORD-IDENTIFIER"
const HUMAN_LABEL := "An ordinary human change description that remains readable in the command palette"

func _init() -> void:
	id = "command_palette_widget_labels"
	display_name = "Readable Widget Rows and Narrow Keyboard Palette"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	print("USER_DATA_DIR_PROOF=", OS.get_user_data_dir())
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return
	var previous_size: Vector2i = display.get_window().size
	var previous_method: String = display.get_current_input_method()
	var previous_scale: float = display.get_render_scale_percent("command_palette", "keyboard")
	var detail := VBoxContainer.new()
	detail.set_script(preload("res://tests/fixtures/readable_palette_content.gd"))
	var prose := Label.new()
	prose.text = "Beginning of review detail\nA long review remains available without losing the start of each line."
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(prose)
	prose.owner = detail
	detail.custom_minimum_size = Vector2(320, 240)
	var scene := PackedScene.new()
	ctx.check("detail scene packs", scene.pack(detail) == OK)
	detail.free()
	console.add_widget(ADDRESS, scene, "", "Reviews", 1, Vector2(320, 240), HUMAN_LABEL)
	display.get_window().size = Vector2i(390, 844)
	display.set_current_input_method("keyboard")
	display.set_render_scale_percent("command_palette", "keyboard", 100)
	if console.control != null:
		console.control.visible = true
	await ctx.wait_frames(2)
	display.show_command_entry_mode("/" + PREFIX, false)
	await ctx.wait_frames(3)
	var rendered_label := ""
	for node in display._autocomplete_column_nodes:
		for row in node.get_rows():
			if str(row.get("command_path", "")) == ADDRESS or str(row.get("label", "")) == HUMAN_LABEL or str(row.get("label", "")) == "INTERNAL-RECORD-IDENTIFIER":
				rendered_label = str(row.get("label", ""))
	ctx.check("ordinary rendered row uses registered human label", rendered_label == HUMAN_LABEL, rendered_label)
	ctx.check("global search path override remains exact", display._get_autocomplete_tier_label(PREFIX, {"tier": ADDRESS, "full_label_override": "/" + ADDRESS}) == "/" + ADDRESS)
	ctx.check("explicit tier label override remains exact", display._get_autocomplete_tier_label(PREFIX, {"tier": ADDRESS, "tier_label_override": "Explicit"}) == "Explicit")
	display.show_command_entry_mode("/" + ADDRESS + "/", false)
	await ctx.wait_frames(4)
	display.autocomplete_select_next()
	await ctx.wait_frames(2)
	var active = null
	for node in display._autocomplete_column_nodes:
		if node._embedded_widget != null:
			active = node
	ctx.check("actual prose detail column exists", active != null)
	if active == null:
		return
	var popup: Rect2 = display._command_autocomplete_popup.get_global_rect()
	var active_rect: Rect2 = active.get_global_rect()
	var viewport: Rect2 = display.get_viewport_rect()
	ctx.check("keyboard popup stays inside390 viewport", popup.position.x >= viewport.position.x - 1 and popup.end.x <= viewport.end.x + 1, str(popup))
	ctx.check("active review starts inside popup", active_rect.position.x >= popup.position.x - 1, "active=%s popup=%s" % [active_rect, popup])
	ctx.check("active review ends inside popup", active_rect.end.x <= popup.end.x + 1, "active=%s popup=%s" % [active_rect, popup])
	ctx.check("selected widget remains present", active._embedded_widget != null)
	console.remove_widget(ADDRESS)
	display.reset_autocomplete()
	display.set_render_scale_percent("command_palette", "keyboard", previous_scale)
	display.set_current_input_method(previous_method)
	display.get_window().size = previous_size
