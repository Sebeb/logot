extends LogotTestCase

const Display = preload("res://addons/logot/logot_display.gd")
const FULL_TEXT := "Complete hovered Unicode description café: a deliberately long human-readable label whose final words must remain available without extending beyond the phone viewport."

func _init() -> void:
	id = "command_palette_tooltip_bounds"
	display_name = "Viewport-bounded ordinary row tooltip"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	print("USER_DATA_DIR_PROOF=", OS.get_user_data_dir())
	var display = ctx.console._get_active_display()
	var root: Window = display.get_tree().root
	var previous_size := root.size
	var previous_visibility: bool = ctx.console.control.visible
	var previous_mouse := root.get_mouse_position()
	root.size = Vector2i(390, 844)
	ctx.console.control.visible = false
	var column := Display.AutocompleteCommandColumn.new()
	column.configure_theme(display._history_autocomplete_popup)
	root.add_child(column)
	for sample in [
		{"width": 390, "text": FULL_TEXT, "wrap": true},
		{"width": 320, "text": "UNBROKEN".repeat(24), "wrap": true},
		{"width": 844, "text": FULL_TEXT, "wrap": true},
		{"width": 390, "text": "Short", "wrap": false},
	]:
		# Leave the old row so each assertion observes a fresh native popup.
		_move_mouse(root, Vector2.ZERO)
		await ctx.wait_frames(2)
		root.size = Vector2i(sample.width, 844)
		column.position = Vector2(20, 100)
		column.size = Vector2(sample.width - 40, 80)
		column.set_column_data([{"label": sample.text}], {}, 0, false, 28)
		await ctx.wait_frames(3)
		var point := Vector2(column.size.x - 20, 0)
		for y in range(int(column.size.y)):
			if column.get_tooltip(Vector2(point.x, y + 0.5)) == sample.text:
				point.y = y + 0.5
				break
		ctx.check("native hover targets full row at%s" % sample.width, column.get_tooltip(point) == sample.text)
		_move_mouse(root, column.get_global_position() + point)
		await ctx.wait_seconds(0.8)
		var popup := _find_tooltip(root)
		ctx.check("real native tooltip popup mounted at%s" % sample.width, popup != null)
		if popup != null:
			var rect := Rect2(Vector2(popup.position), Vector2(popup.size))
			ctx.check("actual popup fits width%s" % sample.width, rect.position.x >= 0 and rect.end.x <= sample.width, str(rect))
			ctx.check("actual popup fits height844", rect.position.y >= 0 and rect.end.y <= 844, str(rect))
			var label := _find_label(popup)
			ctx.check("tooltip retains complete text", label != null and label.text == sample.text)
			if sample.wrap:
				ctx.check("long tooltip wraps into multiple lines", label != null and label.get_line_count() > 1)
			else:
				ctx.check("short tooltip retains natural width", rect.size.x < 150)
	column.queue_free()
	await ctx.wait_frames(2)
	root.size = previous_size
	ctx.console.control.visible = previous_visibility
	_move_mouse(root, previous_mouse)

func _move_mouse(root: Window, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion)

func _find_tooltip(node: Node) -> PopupPanel:
	for child in node.get_children(true):
		if child is PopupPanel and child.visible:
			return child
		var result := _find_tooltip(child)
		if result != null:
			return result
	return null

func _find_label(node: Node) -> Label:
	for child in node.get_children(true):
		if child is Label:
			return child
		var result := _find_label(child)
		if result != null:
			return result
	return null
