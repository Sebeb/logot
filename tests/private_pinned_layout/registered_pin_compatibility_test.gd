extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")

const PREFIX := "compatibility/pins/"

func _init() -> void:
	id = "registered_pin_compatibility"
	display_name = "Registered Pin Compatibility"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	var console: Node = ctx.console
	var display: LogotDisplay = console._get_active_display()
	ctx.check("actual runtime display exists", display != null)
	if display == null:
		return
	var window: Window = console.get_window()
	var previous_size := window.size
	console._set_touch_mode_enabled(false, false)
	console.control.visible = false
	display.hide_command_entry_mode()
	display.clear_pinned_display_variables()
	display.set_pinned_display_variables_suppressed(false)
	console.set_ingame_overlay_edge_overrides(0, 0, 0, 0)
	var template := LineEdit.new()
	template.custom_minimum_size = Vector2(240, 40)
	var packed := PackedScene.new()
	ctx.check("registered LineEdit scene packs", packed.pack(template) == OK)
	template.free()
	var widget_address := PREFIX + "draft"
	var prose_address := PREFIX + "prose"
	var value := {"text": "21 unseen · 21 need manual verification. Every count and every word remains available opposite a real registered editor."}
	console.add_widget(widget_address, packed, "", "", 0, Vector2(240, 40), "Draft")
	console.add_display_variable(prose_address, func(): return value.text, Callable(), Callable(), true, "", 0, null, &"", Callable(), {"wrap_value": true})
	console.pin_display_variable(widget_address, "top_left")
	console.pin_display_variable(prose_address, "top_right")
	window.size = Vector2i(640, 900)
	await _settle(ctx, display)
	var row: Control = display._pinned_overlay_rows.get(widget_address)
	ctx.check("registered widget produced a pin row", row != null)
	if row == null:
		return
	var edit := _find_line_edit(row)
	ctx.check("pin contains actual registered LineEdit instance", edit != null)
	if edit == null:
		return
	var registration = console.get_widgets()[widget_address]
	var row_id := row.get_instance_id()
	var control_id := edit.get_instance_id()
	var order: Array = display._pinned_display_variables.duplicate()
	edit.text = "unfinished registered draft"
	edit.grab_focus()
	edit.caret_column = 7
	ctx.check("registered editor initially owns focus", edit.has_focus())
	for width in [640, 390, 360, 640]:
		window.size = Vector2i(width, 900)
		await _settle(ctx, display)
		var prose: RichTextLabel = display._pinned_overlay_rows[prose_address]
		var usable := Rect2(Vector2(8, 8), display.get_viewport_rect().size - Vector2(16, 16))
		ctx.check("registry identity %s" % width, console.get_widgets()[widget_address] == registration)
		ctx.check("pin row identity %s" % width, display._pinned_overlay_rows[widget_address].get_instance_id() == row_id)
		ctx.check("editor identity %s" % width, _find_line_edit(display._pinned_overlay_rows[widget_address]).get_instance_id() == control_id)
		ctx.check("draft and caret %s" % width, edit.text == "unfinished registered draft" and edit.caret_column == 7)
		ctx.check("focus across resize %s" % width, edit.has_focus())
		ctx.check("requested corners %s" % width, display.get_pinned_display_variable_corner(widget_address) == "top_left" and display.get_pinned_display_variable_corner(prose_address) == "top_right")
		ctx.check("pin order %s" % width, display._pinned_display_variables == order)
		ctx.check("complete opposite prose %s" % width, str(value.text) in prose.get_parsed_text())
		ctx.check("widget contained when its minimum fits %s" % width, usable.grow(1).encloses(row.get_global_rect()), str(row.get_global_rect()))
		ctx.check("prose contained when mixed content fits %s" % width, usable.grow(1).encloses(prose.get_global_rect()), str(prose.get_global_rect()))
		ctx.check("registered widget and prose do not overlap %s" % width, not row.get_global_rect().grow(-0.5).intersects(prose.get_global_rect().grow(-0.5)), "%s vs %s" % [row.get_global_rect(), prose.get_global_rect()])
	value.text = "123 unseen · 456 need manual verification\nA complete explicitly separate line."
	console.pin_display_variable(widget_address, "bottom_left")
	await _settle(ctx, display)
	ctx.check("registry retained on pin rearrangement", console.get_widgets()[widget_address] == registration)
	ctx.check("row retained on pin rearrangement", display._pinned_overlay_rows[widget_address].get_instance_id() == row_id)
	ctx.check("control retained on pin rearrangement", _find_line_edit(display._pinned_overlay_rows[widget_address]).get_instance_id() == control_id)
	ctx.check("draft caret retained on pin rearrangement", edit.text == "unfinished registered draft" and edit.caret_column == 7)
	ctx.check("focus retained on pin rearrangement", edit.has_focus())
	ctx.check("explicit user corner change honored", display.get_pinned_display_variable_corner(widget_address) == "bottom_left")
	ctx.check("pin rearrangement preserves order", display._pinned_display_variables == order)
	ctx.check("prose getter update complete", str(value.text) in display._pinned_overlay_rows[prose_address].get_parsed_text())
	console.unpin_display_variable(widget_address)
	console.remove_widget(widget_address)
	console.unpin_display_variable(prose_address)
	console.remove_display_variable(prose_address)
	await _check_unfit_minima(ctx, console, display, window, packed)
	await _check_finite_columns(ctx, console, display, window)
	window.size = previous_size
	await ctx.wait_frames(3)

func _find_line_edit(node: Node) -> LineEdit:
	if node is LineEdit:
		return node as LineEdit
	for child in node.get_children():
		var found := _find_line_edit(child)
		if found != null:
			return found
	return null

func _settle(ctx, display: LogotDisplay) -> void:
	display._refresh_pinned_display_variables()
	for frame in range(6):
		await ctx.wait_frames(1)
		display._poll_visible_pinned_display_variable_rows(0.016)

func _check_unfit_minima(ctx, console: Node, display: LogotDisplay, window: Window, packed: PackedScene) -> void:
	var left := PREFIX + "overflow-left"
	var right := PREFIX + "overflow-right"
	console.add_widget(left, packed, "", "", 0, Vector2(240, 40), "Left")
	console.add_widget(right, packed, "", "", 0, Vector2(240, 40), "Right")
	console.pin_display_variable(left, "top_left")
	console.pin_display_variable(right, "top_right")
	window.size = Vector2i(390, 900)
	await _settle(ctx, display)
	ctx.check("opposing unfit minima retain both pins", console.is_display_variable_pinned(left) and console.is_display_variable_pinned(right))
	ctx.check("unfit left widget is not shrunk", display._pinned_overlay_rows[left].get_combined_minimum_size().x >= 240.0)
	ctx.check("unfit right widget is not shrunk", display._pinned_overlay_rows[right].get_combined_minimum_size().x >= 240.0)
	ctx.check("unfit minima retain requested corners", display.get_pinned_display_variable_corner(left) == "top_left" and display.get_pinned_display_variable_corner(right) == "top_right")
	for address in [left, right]:
		console.unpin_display_variable(address)
		console.remove_widget(address)


func _check_finite_columns(ctx, console: Node, display: LogotDisplay, window: Window) -> void:
	var template := ColorRect.new()
	template.custom_minimum_size = Vector2(90, 80)
	var packed := PackedScene.new()
	ctx.check("finite column widget scene packs", packed.pack(template) == OK)
	template.free()
	var addresses: Array[String] = [PREFIX + "first", PREFIX + "second", PREFIX + "third"]
	for address in addresses:
		console.add_widget(address, packed, "", "", 0, Vector2(90, 80), "Short")
		console.pin_display_variable(address, "top_right")
	window.size = Vector2i(600, 250)
	await _settle(ctx, display)
	var container: HBoxContainer = display._get_pinned_overlay_container("top_right")
	ctx.check("finite registered pins make exactly two columns", container.get_child_count() == 2, str(container.get_child_count()))
	var rightmost: Node = container.get_child(container.get_child_count() - 1)
	var leftmost: Node = container.get_child(0)
	ctx.check("first two pins stay nearest requested right corner", rightmost.get_child_count() == 2 and rightmost.get_child(0) == display._pinned_overlay_rows[addresses[0]] and rightmost.get_child(1) == display._pinned_overlay_rows[addresses[1]])
	ctx.check("third pin flows to adjacent left column", leftmost.get_child_count() == 1 and leftmost.get_child(0) == display._pinned_overlay_rows[addresses[2]])
	var rows: Array = []
	for address in addresses:
		rows.append(display._pinned_overlay_rows[address])
	for index in range(rows.size()):
		var bounds := Rect2(Vector2(8, 8), display.get_viewport_rect().size - Vector2(16, 16))
		ctx.check("finite column row contained %s" % index, bounds.grow(1).encloses(rows[index].get_global_rect()), str(rows[index].get_global_rect()))
		for other in range(index):
			ctx.check("finite columns do not overlap %s %s" % [index, other], not rows[index].get_global_rect().grow(-0.5).intersects(rows[other].get_global_rect().grow(-0.5)))
	for address in addresses:
		console.unpin_display_variable(address)
		console.remove_widget(address)
	# Removing the last pin returns before column reconstruction. Confirm the
	# stale empty-column state that made the original helper check count three.
	await ctx.wait_frames(3)
	var stale_column_counts: Array[int] = []
	for column in container.get_children():
		stale_column_counts.append(column.get_child_count())
	var stale_precondition := container.get_child_count() == 1 and stale_column_counts == [0]
	ctx.check("legacy original corner retains one empty column after last unpin", stale_precondition, str(stale_column_counts))
	if not stale_precondition:
		return
	# The helper appends columns by contract. Give it a genuinely fresh container
	# rather than changing production cleanup semantics to satisfy this test.
	var original_container := container
	container = HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_END
	container.add_theme_constant_override("separation", LogotDisplay.PINNED_OVERLAY_COLUMN_SEPARATION)
	display._pinned_overlay_root.add_child(container)
	display._pinned_overlay_corner_containers["top_right"] = container
	ctx.check("legacy helper fixture container starts genuinely empty", container.get_child_count() == 0)
	# Exercise the old helper signature directly with supported Control-only rows.
	var legacy_rows: Array = []
	for index in range(3):
		var control := ColorRect.new()
		control.custom_minimum_size = Vector2(90, 80)
		legacy_rows.append(control)
	display._layout_pinned_overlay_corner_columns("top_right", legacy_rows)
	display._layout_pinned_overlay_containers()
	await ctx.wait_frames(3)
	ctx.check("legacy two-argument helper still creates two columns", container.get_child_count() == 2, str(container.get_child_count()))
	ctx.check("legacy right column contains first two controls", container.get_child(container.get_child_count() - 1).get_children() == legacy_rows.slice(0, 2))
	ctx.check("legacy adjacent column contains final control", container.get_child(0).get_children() == legacy_rows.slice(2))
	for index in range(legacy_rows.size()):
		ctx.check("legacy Control row is contained %s" % index, display.get_viewport_rect().grow(-7).encloses(legacy_rows[index].get_global_rect()), str(legacy_rows[index].get_global_rect()))
	display._pinned_overlay_corner_containers["top_right"] = original_container
	container.queue_free()
	await ctx.wait_frames(3)
