extends LogotTestCase

# Direct private runner supplies the same check/wait interface without Console
# autoloads, editor initialization, host scenes, or persisted user preferences.
func _init() -> void:
	id = "pinned_display_responsive_layout"
	display_name = "Pinned Display Responsive Layout"

func run(ctx) -> void:
	var script = load("res://addons/logot/logot_display.gd")
	var display = script.new()
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	ctx.tree.root.add_child(viewport)
	viewport.add_child(display)
	display._base_pinned_font_size = 40
	display.theme = ctx.theme
	display._ensure_pinned_overlay()
	display._pinned_overlay_suppressed = false
	display._pinned_overlay_visible = true
	var values := {
		"dev/build/version": "0.0.1-32",
		"dev/performance/fps": "60",
		"changelog/summary": "21 unseen · 21 need manual verification",
	}
	var variables: Dictionary = {}
	for address in values:
		variables[address] = script.LogotDisplayVariable.new(func(): return values[address])
	display.set_display_variables_provider(func(): return variables)
	display._pinned_display_variables.assign(values.keys())
	display._pinned_display_variable_corners = {
		"dev/build/version": "top_left", "dev/performance/fps": "top_right", "changelog/summary": "top_right",
	}
	for css_width in [360, 390]:
		for canvas_to_css in [0.5, 1.0]:
			viewport.size = Vector2i(roundi(css_width / canvas_to_css), roundi(844.0 / canvas_to_css))
			display.set_ingame_overlay_edge_overrides(112.0, 7.0, 11.0, 13.0)
			await _settle(ctx, display)
			_check_rows(ctx, display, values, "default CSS%s ratio%s" % [css_width, canvas_to_css])
	var row_ids: Dictionary = {}
	for address in values:
		row_ids[address] = display._pinned_overlay_rows[address].get_instance_id()
	# Width-only resize and getter mutation must invalidate both width and height.
	values["changelog/summary"] = "123 unseen · 456 need manual verification\nEvery count and this explicit second line must remain visible."
	for width in [780, 360, 390, 780]:
		viewport.size = Vector2i(width, 1300)
		await _settle(ctx, display)
		_check_rows(ctx, display, values, "resize %s" % width)
		for address in row_ids:
			ctx.check("row identity retained %s %s" % [width, address], display._pinned_overlay_rows[address].get_instance_id() == row_ids[address])
	# Exercise all four corners, including vertically opposing long paragraphs.
	values["bottom/left"] = "Bottom left paragraph with every word preserved through wrapping and value refresh."
	values["bottom/right"] = "Bottom right first line\nsecond line with preserved counts 789 and 987."
	for address in ["bottom/left", "bottom/right"]:
		variables[address] = script.LogotDisplayVariable.new(func(): return values[address], Callable(), Callable(), true, "", 0, null, &"", Callable(), {"wrap_value": true})
		display._pinned_display_variables.append(address)
		display._pinned_display_variable_corners[address] = "bottom_left" if address.ends_with("left") else "bottom_right"
	viewport.size = Vector2i(390, 1300)
	await _settle(ctx, display)
	_check_rows(ctx, display, values, "four corners")
	# A real interactive widget remains the same object with its editing draft.
	var widget := VBoxContainer.new()
	var edit := LineEdit.new()
	edit.text = "unfinished draft"
	edit.custom_minimum_size = Vector2(90, 28)
	widget.add_child(edit)
	display._pinned_overlay_rows["widget/draft"] = widget
	display._pinned_display_variables.append("widget/draft")
	display._pinned_display_variable_corners["widget/draft"] = "bottom_left"
	var visible: Array[String] = []
	visible.assign(display._pinned_display_variables)
	display._layout_pinned_overlay_rows(visible)
	display._layout_pinned_overlay_containers()
	await ctx.wait_frames(3)
	edit.grab_focus()
	edit.caret_column = 5
	var edit_id := edit.get_instance_id()
	viewport.size = Vector2i(360, 1300)
	display._layout_pinned_overlay_rows(visible)
	display._layout_pinned_overlay_containers()
	await ctx.wait_frames(3)
	ctx.check("widget control identity preserved", edit.get_instance_id() == edit_id)
	ctx.check("widget draft and caret preserved", edit.text == "unfinished draft" and edit.caret_column == 5)
	ctx.check("widget focus preserved", edit.has_focus())
	ctx.check("user corner preferences preserved", display._pinned_display_variable_corners["dev/build/version"] == "top_left" and display._pinned_display_variable_corners["changelog/summary"] == "top_right")
	ctx.check("user pin order preserved", display._pinned_display_variables.slice(0, 3) == values.keys().slice(0, 3))
	# Explicit overflow contract: huge content is retained, with no finite-fit claim.
	values["changelog/summary"] = "unbounded content ".repeat(500)
	await _settle(ctx, display)
	ctx.check("overflow retains complete text", values["changelog/summary"] in display._pinned_overlay_rows["changelog/summary"].get_parsed_text())
	viewport.queue_free()
	await ctx.wait_frames(3)

func _settle(ctx, display) -> void:
	display._refresh_pinned_display_variables()
	for frame in range(6):
		await ctx.wait_frames(1)
		display._poll_visible_pinned_display_variable_rows(0.016)

func _check_rows(ctx, display, values: Dictionary, label: String) -> void:
	var viewport_size: Vector2 = display.get_viewport_rect().size
	var usable := Rect2(Vector2(15, 120), viewport_size - Vector2(34, 141))
	var rects: Array[Rect2] = []
	for address in values:
		var row: RichTextLabel = display._pinned_overlay_rows[address]
		var rect := row.get_global_rect()
		ctx.check("contained %s %s" % [label, address], usable.grow(1).encloses(rect), str(rect))
		ctx.check("complete text %s %s" % [label, address], str(values[address]) in row.get_parsed_text(), row.get_parsed_text())
		ctx.check("wrapped height allocated %s %s" % [label, address], row.size.y + 1.0 >= row.get_content_height(), "size=%s content_height=%s" % [row.size, row.get_content_height()])
		ctx.check("rendered content width bounded %s %s" % [label, address], row.get_content_width() <= row.size.x + 1.0, "content=%s size=%s" % [row.get_content_width(), row.size.x])
		for previous in rects:
			ctx.check("no overlap %s %s" % [label, address], not previous.grow(-0.5).intersects(rect.grow(-0.5)), "%s vs %s" % [previous, rect])
		rects.append(rect)
