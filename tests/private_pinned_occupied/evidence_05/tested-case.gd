extends RefCounted

func run(ctx) -> void:
	var script = load("res://addons/logot/logot_display.gd")
	var console_script = load("res://addons/logot/logot.gd")
	var display = script.new()
	var console = console_script.new()
	var supported: bool = display.has_method("get_pinned_overlay_occupied_rects") and display.has_method("get_pinned_overlay_viewport") and display.has_signal("pinned_overlay_occupied_rects_changed")
	ctx.check("display exposes new occupied geometry capability", supported)
	ctx.check("Console exposes runtime occupied geometry capability", console.has_method("get_pinned_overlay_occupied_rects") and console.has_method("get_pinned_overlay_viewport") and console.has_signal("pinned_overlay_occupied_rects_changed"))
	if not supported or not console.has_method("get_pinned_overlay_occupied_rects"):
		display.free()
		console.free()
		return # Honest baseline capability assertion failures, not parser failure.
	ctx.check("detached display has empty/null availability", _empty(display.get_pinned_overlay_occupied_rects()) and display.get_pinned_overlay_viewport() == null)
	ctx.check("unbound Console has empty/null availability", _empty(console.get_pinned_overlay_occupied_rects()) and console.get_pinned_overlay_viewport() == null)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	viewport.disable_3d = true
	ctx.tree.root.add_child(viewport)
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	layer.add_child(display)
	display.theme = ctx.theme
	display._base_pinned_font_size = 40
	display.set_settings_file("user://occupied-test.cfg")
	display._ensure_pinned_overlay()
	var events: Array[Dictionary] = []
	display.pinned_overlay_occupied_rects_changed.connect(func(): events.append({"rects": display.get_pinned_overlay_occupied_rects(), "viewport": display.get_pinned_overlay_viewport()}))
	var console_events: Array[Dictionary] = []
	console.pinned_overlay_occupied_rects_changed.connect(func(): console_events.append({"rects": console.get_pinned_overlay_occupied_rects(), "viewport": console.get_pinned_overlay_viewport()}))
	console._bind_pinned_occupied_runtime_display(display)
	var values := {"summary": "21 unseen · 21 need manual verification"}
	var variables := {"summary": script.LogotDisplayVariable.new(func(): return values.summary, Callable(), Callable(), true, "", 0, null, &"", Callable(), {"wrap_value": true})}
	display.set_display_variables_provider(func(): return variables)
	display.set_display_variable_transiently_pinned("summary", true, "top_left")
	await ctx.wait_frames(6)
	_check(ctx, display, "initial wrapped row")
	ctx.check("owning SubViewport is explicit", display.get_pinned_overlay_viewport() == viewport and console.get_pinned_overlay_viewport() == viewport)
	ctx.check("Console forwards runtime snapshot", console.get_pinned_overlay_occupied_rects() == display.get_pinned_overlay_occupied_rects())
	var original: Rect2 = display.get_pinned_overlay_occupied_rects().top_left
	var copy: Dictionary = display.get_pinned_overlay_occupied_rects()
	copy.top_left = Rect2(1, 2, 3, 4)
	copy.clear()
	ctx.check("snapshot dictionary mutation cannot mutate cache", display.get_pinned_overlay_occupied_rects().top_left == original)
	var count := events.size()
	for iteration in range(10):
		display._invalidate_pinned_occupied_rects()
	await ctx.wait_frames(8)
	ctx.check("coalesced no-op invalidations emit nothing", events.size() == count)
	ctx.check("settle callback disconnects after finite work", not display._pinned_occupied_pending)
	values.summary = "A much longer summary with several explicit lines\nOne two three four five six seven eight nine ten\nEvery count remains visible through wrapping."
	display.invalidate_display_variable("summary")
	await ctx.wait_frames(6)
	_check(ctx, display, "wrapped grow")
	var grown: Rect2 = display.get_pinned_overlay_occupied_rects().top_left
	ctx.check("wrapped value growth changes occupied height", grown.size.y > original.size.y)
	values.summary = "Short"
	display.invalidate_display_variable("summary")
	await ctx.wait_frames(6)
	_check(ctx, display, "wrapped shrink")
	ctx.check("wrapped value shrink reduces occupied height", display.get_pinned_overlay_occupied_rects().top_left.size.y < grown.size.y)
	for corner in ["top_right", "bottom_left", "bottom_right", "top_left"]:
		display.set_display_variable_transiently_pinned("summary", true, corner)
		await ctx.wait_frames(6)
		_check(ctx, display, "corner " + corner)
		ctx.check("effective corner is occupied " + corner, display.get_pinned_overlay_occupied_rects()[corner] != Rect2())
	viewport.size = Vector2i(780, 1200)
	await ctx.wait_frames(6)
	_check(ctx, display, "viewport resize")
	display.set_ingame_overlay_edge_overrides(120.0, 17.0, 11.0, 9.0)
	await ctx.wait_frames(6)
	_check(ctx, display, "inset update")
	ctx.check("insets move actual occupied origin", display.get_pinned_overlay_occupied_rects().top_left.position.y >= 120.0)
	display.set_render_scale_percent("pinned_variables", display.get_current_input_method(), 200.0)
	await ctx.wait_frames(6)
	_check(ctx, display, "render scale")
	layer.transform = Transform2D(0.12, Vector2(13, 21)).scaled(Vector2(1.25, 0.8))
	await ctx.wait_frames(6)
	_check(ctx, display, "CanvasLayer rotation scale translation")
	layer.follow_viewport_enabled = true
	viewport.canvas_transform = Transform2D(0.0, Vector2(31, 14)).scaled(Vector2(0.75, 1.1))
	await ctx.wait_frames(6)
	_check(ctx, display, "viewport canvas transform")
	var row: Control = display._pinned_overlay_rows.summary
	var host := Control.new()
	host.position = Vector2(7, 19)
	host.scale = Vector2(1.2, 0.9)
	layer.add_child(host)
	var occupied: Rect2 = display.get_pinned_overlay_occupied_rects().top_left
	var inverse := host.get_global_transform_with_canvas().affine_inverse()
	var local_points: PackedVector2Array = inverse * PackedVector2Array([occupied.position, occupied.position + Vector2(occupied.size.x, 0), occupied.end, occupied.position + Vector2(0, occupied.size.y)])
	var local := Rect2(local_points[0], Vector2.ZERO)
	for point in local_points:
		local = local.expand(point)
	var row_points: PackedVector2Array = inverse * row.get_global_transform_with_canvas() * PackedVector2Array([Vector2.ZERO, row.size])
	ctx.check("same-viewport host inverse conversion contains actual row", host.get_viewport() == display.get_pinned_overlay_viewport() and local.grow(0.01).has_point(row_points[0]) and local.grow(0.01).has_point(row_points[1]))
	row.rotation = 0.2
	await ctx.wait_frames(6)
	_check(ctx, display, "individual row transform")
	# Pause existing layout polling only for this focused observer sequence.
	# This prevents periodic container layout from resetting Control rotation;
	# all invalidation and bounded sampling must come from the observer itself.
	var was_processing: bool = display.is_processing()
	display.set_process(false)
	await ctx.wait_frames(6)
	for step in [{"angle": 0.05, "name": "toward original"}, {"angle": 0.0, "name": "return original"}, {"angle": 0.18, "name": "subsequent rotation"}]:
		var angle: float = float(step.angle)
		var label: String = "independent " + str(step.name)
		var event_count: int = events.size()
		row.rotation = angle
		await ctx.wait_frames(6)
		ctx.check(label + " fixture retains requested transform", is_equal_approx(row.rotation, angle) and not display.is_processing())
		_check(ctx, display, label)
		ctx.check(label + " publishes exactly one changed geometry", events.size() == event_count + 1)
	display.set_process(was_processing)
	row.hide()
	await ctx.wait_frames(6)
	ctx.check("hidden row reports empty", _empty(display.get_pinned_overlay_occupied_rects()))
	row.show()
	await ctx.wait_frames(6)
	_check(ctx, display, "shown row")
	display.set_pinned_display_variables_suppressed(true)
	await ctx.wait_frames(6)
	ctx.check("suppressed overlay reports empty", _empty(display.get_pinned_overlay_occupied_rects()))
	display.set_pinned_display_variables_suppressed(false)
	await ctx.wait_frames(6)
	_check(ctx, display, "unsuppressed overlay")
	display.set_pinned_display_variables_visible(false)
	await ctx.wait_frames(6)
	ctx.check("user-hidden overlay reports empty", _empty(display.get_pinned_overlay_occupied_rects()))
	display.set_pinned_display_variables_visible(true)
	await ctx.wait_frames(6)
	_check(ctx, display, "user-shown overlay")
	values["second"] = "Second row"
	variables["second"] = script.LogotDisplayVariable.new(func(): return values.second)
	display.set_display_variable_transiently_pinned("second", true, "top_left")
	await ctx.wait_frames(6)
	_check(ctx, display, "multiple rows union")
	display.set_display_variable_transiently_pinned("second", false)
	variables.erase("second")
	await ctx.wait_frames(6)
	_check(ctx, display, "last additional pin removed")
	values.summary = "Overflow line\n".repeat(100)
	display.invalidate_display_variable("summary")
	await ctx.wait_frames(6)
	_check(ctx, display, "retained oversized paragraph")
	ctx.check("overflow bounds are not clipped to viewport", display.get_pinned_overlay_occupied_rects().top_left.size.y > viewport.size.y)
	values.summary = "Short"
	display.invalidate_display_variable("summary")
	await ctx.wait_frames(6)
	var distinct := true
	for index in range(1, events.size()):
		distinct = distinct and (events[index].rects != events[index - 1].rects or events[index].viewport != events[index - 1].viewport)
	ctx.check("unchanged geometry never duplicates publications", distinct)
	# Registry removal queues the old row. No stale row remains occupied.
	variables.erase("summary")
	display.invalidate_command_catalog()
	await ctx.wait_frames(6)
	ctx.check("removed registry entry reports empty", _empty(display.get_pinned_overlay_occupied_rects()))
	variables.summary = script.LogotDisplayVariable.new(func(): return "restored")
	display.invalidate_command_catalog()
	await ctx.wait_frames(6)
	_check(ctx, display, "registry re-registration")
	row = display._pinned_overlay_rows.summary
	display.set_display_variable_transiently_pinned("summary", false)
	ctx.check("removed row queued for deletion", row.is_queued_for_deletion())
	await ctx.wait_frames(6)
	ctx.check("queued-free row excluded safely", _empty(display.get_pinned_overlay_occupied_rects()))
	# Restore an occupied old display so the no-forwarding assertion exercises
	# a real geometry publication rather than an already-empty no-op.
	display.set_display_variable_transiently_pinned("summary", true, "top_left")
	await ctx.wait_frames(6)
	ctx.check("old display is occupied before replacement", display.get_pinned_overlay_occupied_rects().top_left != Rect2())
	# Replacement publishes empty/null before the new owner becomes available.
	var replacement = script.new()
	var second_viewport := SubViewport.new()
	second_viewport.size = Vector2i(390, 844)
	ctx.tree.root.add_child(second_viewport)
	second_viewport.add_child(replacement)
	var start := console_events.size()
	console._bind_pinned_occupied_runtime_display(replacement)
	ctx.check("replacement first publishes empty/null", console_events.size() >= start + 2 and console_events[start].viewport == null and _empty(console_events[start].rects))
	ctx.check("replacement explicitly supplies its coordinate owner", console.get_pinned_overlay_viewport() == second_viewport)
	await ctx.wait_frames(6)
	start = console_events.size()
	display.set_pinned_display_variables_suppressed(true)
	await ctx.wait_frames(6)
	ctx.check("replaced display actually publishes suppressed empty geometry", _empty(display.get_pinned_overlay_occupied_rects()))
	ctx.check("replaced display cannot notify Console", console_events.size() == start)
	console._bind_pinned_occupied_runtime_display(display)
	start = console_events.size()
	var retained_reentry_row: Control = display._pinned_overlay_rows.summary
	display._invalidate_pinned_occupied_rects()
	layer.remove_child(display)
	ctx.check("display exit listeners observe empty/null synchronously", events.back().viewport == null and _empty(events.back().rects))
	ctx.check("Console exit listeners observe empty/null synchronously", console_events.size() > start and console_events.back().viewport == null and _empty(console_events.back().rects))
	await ctx.wait_frames(4)
	ctx.check("late settle callback cancelled on exit", not display._pinned_occupied_pending)
	layer.add_child(display)
	console._bind_pinned_occupied_runtime_display(display)
	await ctx.wait_frames(6)
	ctx.check("display re-entry restores coordinate availability", display.get_pinned_overlay_viewport() == viewport and console.get_pinned_overlay_viewport() == viewport)
	# Real Console registration/removal APIs require a visible fixture. Earlier
	# suppression is deliberately retained through teardown, then restored here.
	display.set_pinned_display_variables_suppressed(false)
	display.set_pinned_display_variables_visible(true)
	ctx.check("real registry fixture permits visible pins", display._are_pinned_display_variables_effectively_visible() and display.is_inside_tree() and console.get_pinned_overlay_viewport() == viewport)
	display.set_process(false)
	await ctx.wait_frames(6)
	ctx.check("re-entry retains observed row identity", display._pinned_overlay_rows.summary == retained_reentry_row)
	var reentry_event_count: int = events.size()
	retained_reentry_row.rotation = 0.11
	await ctx.wait_frames(6)
	ctx.check("re-entry fixture retains requested transform", is_equal_approx(retained_reentry_row.rotation, 0.11) and not display.is_processing())
	_check(ctx, display, "independent rotation after re-entry")
	ctx.check("independent rotation after re-entry publishes once", events.size() == reentry_event_count + 1)
	display.set_process(was_processing)
	console._display = display
	display.set_display_variables_provider(console.get_display_variables)
	console.add_display_variable("registry/live", func(): return "registered through Console")
	console.pin_display_variable("registry/live", "top_right")
	await ctx.wait_frames(6)
	_check(ctx, display, "real Console registration")
	ctx.check("Console registered row occupies requested corner", display.get_pinned_overlay_occupied_rects().top_right != Rect2())
	console.remove_display_variable("registry/live")
	await ctx.wait_frames(6)
	ctx.check("real Console registry removal becomes empty", _empty(display.get_pinned_overlay_occupied_rects()))
	console._display = null
	console.register_external_display(replacement)
	console._bind_pinned_occupied_runtime_display(null)
	ctx.check("Console never falls back to registered external display", console.get_pinned_overlay_viewport() == null and _empty(console.get_pinned_overlay_occupied_rects()))
	console.unregister_external_display(replacement)
	console.free()
	viewport.queue_free()
	second_viewport.queue_free()
	await ctx.wait_frames(6)

func _empty(rects: Dictionary) -> bool:
	if rects.size() != 4:
		return false
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		if rects.get(corner, Rect2(1, 1, 1, 1)) != Rect2():
			return false
	return true

func _check(ctx, display, label: String) -> void:
	# Independent geometry oracle uses full row transforms, not layout minima.
	var expected := {"top_left": Rect2(), "top_right": Rect2(), "bottom_left": Rect2(), "bottom_right": Rect2()}
	for address in display._pinned_overlay_rows:
		var row = display._pinned_overlay_rows[address]
		if not is_instance_valid(row) or row.is_queued_for_deletion() or not row.is_visible_in_tree():
			continue
		var points := PackedVector2Array([Vector2.ZERO, Vector2(row.size.x, 0), row.size, Vector2(0, row.size.y)])
		points = row.get_global_transform_with_canvas() * points
		var low: Vector2 = points[0]
		var high: Vector2 = points[0]
		for point in points:
			low = low.min(point)
			high = high.max(point)
		var corner: String = display.get_effective_pinned_display_variable_corner(address)
		var rect := Rect2(low, high - low)
		expected[corner] = rect if expected[corner] == Rect2() else expected[corner].merge(rect)
	var actual: Dictionary = display.get_pinned_overlay_occupied_rects()
	var matches := actual.size() == 4
	for corner in expected:
		matches = matches and actual.has(corner) and actual[corner].is_equal_approx(expected[corner])
	ctx.check(label + " equals visible row geometry", matches, str(actual) + " expected " + str(expected))
