extends LogotTestCase

const ADDRESS := "compatibility/occupied_bounds/runtime_bridge"

func _init() -> void:
	id = "occupied_bounds_runtime_bridge"
	display_name = "Occupied Bounds Runtime Bridge"
	scene_path = "res://Main.tscn"
	fail_fast = false

func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("real Console ready in Main context", console.is_inside_tree() and console.is_node_ready() and display != null and ctx.scene_root != null and ctx.scene_root.scene_file_path == "res://Main.tscn")
	if display == null:
		return
	var viewport: Viewport = console.get_viewport()
	ctx.check("runtime public coordinate owner is Main viewport", console.get_pinned_overlay_viewport() == viewport and ctx.scene_root.get_viewport() == viewport)
	# Configure the real display for a visible fixture; never bind it manually.
	console.control.visible = false
	display.hide_command_entry_mode()
	display.clear_pinned_display_variables()
	display.set_pinned_display_variables_visible(true)
	display.set_pinned_display_variables_suppressed(false)
	await ctx.wait_frames(6)
	var events: Array[Dictionary] = []
	var changed: Callable = func(): events.append({"rects": console.get_pinned_overlay_occupied_rects(), "viewport": console.get_pinned_overlay_viewport()})
	console.pinned_overlay_occupied_rects_changed.connect(changed)
	console.add_display_variable(ADDRESS, func(): return "Live runtime registered value")
	console.pin_display_variable(ADDRESS, "top_left")
	await ctx.wait_frames(6)
	ctx.check("live value registered through public Console", console.get_display_variables().has(ADDRESS))
	var occupied: Dictionary = console.get_pinned_overlay_occupied_rects()
	var rect: Rect2 = occupied.get("top_left", Rect2())
	ctx.check("runtime public bounds include live visible registration", rect.size.x > 0.0 and rect.size.y > 0.0 and console.get_pinned_overlay_viewport() == viewport)
	ctx.check("runtime public signal forwards settled live geometry", not events.is_empty() and events.back().rects == occupied and events.back().viewport == viewport)
	occupied.clear()
	ctx.check("runtime public snapshot is detached", console.get_pinned_overlay_occupied_rects().get("top_left", Rect2()) == rect and rect != Rect2())
	var before_remove: int = events.size()
	console.unpin_display_variable(ADDRESS)
	console.remove_display_variable(ADDRESS)
	await ctx.wait_frames(6)
	ctx.check("public registry removal clears runtime occupied bounds", not console.get_display_variables().has(ADDRESS) and _empty(console.get_pinned_overlay_occupied_rects()))
	ctx.check("runtime public signal publishes removal geometry", events.size() > before_remove and _empty(events.back().rects) and events.back().viewport == viewport)
	console.pinned_overlay_occupied_rects_changed.disconnect(changed)

func _empty(rects: Dictionary) -> bool:
	if rects.size() != 4:
		return false
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		if rects.get(corner, Rect2(1, 1, 1, 1)) != Rect2():
			return false
	return true
