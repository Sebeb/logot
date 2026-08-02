extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")
const VALUE_COUNT := 64

var _getter_counts: Dictionary = {}


func _init() -> void:
	id = "autocomplete_incremental_updates"
	display_name = "Autocomplete Incremental Updates"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	display.set_current_input_method(LogotDisplay.INPUT_METHOD_KEYBOARD)
	if console.control != null:
		console.control.visible = true

	var addresses: Array[String] = []
	for value_index in range(VALUE_COUNT):
		var address := "perf_values/item_%02d" % value_index
		addresses.append(address)
		console.add_display_variable(address, _read_value.bind(address))

	# Give the headless column enough width to distinguish the short and long layouts.
	console.line_edit.custom_minimum_size.x = 380.0
	console.line_edit.size.x = 380.0
	# Keep the initial viewport at the short values so the final long value proves that
	# scrolling can refine width without preloading the entire column.
	display._autocomplete_highlighted_tiers["perf_values/"] = "perf_values/item_00"
	console.line_edit.text = "/perf_values/"
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(2)

	ctx.check("visible values are hydrated", not _getter_counts.is_empty(), str(_getter_counts.keys()))
	ctx.check(
		"offscreen value getters are skipped",
		_getter_counts.size() < VALUE_COUNT,
		"called=%d total=%d" % [_getter_counts.size(), VALUE_COUNT]
	)

	var active_index: int = display._autocomplete_active_column_index
	var active_column = display._autocomplete_column_nodes[active_index] if active_index >= 0 and active_index < display._autocomplete_column_nodes.size() else null
	var active_column_id: int = active_column.get_instance_id() if active_column != null else 0
	var initial_width := int(display._autocomplete_column_states[active_index].get("width", 0)) if active_index >= 0 and active_index < display._autocomplete_column_states.size() else 0
	if active_column != null:
		active_column._scroll_rows(VALUE_COUNT)
		await ctx.wait_frames(2)
	var widened_width := int(display._autocomplete_column_states[active_index].get("width", 0)) if active_index >= 0 and active_index < display._autocomplete_column_states.size() else 0
	ctx.check(
		"scrolling a long value widens the column lazily",
		widened_width > initial_width,
		"initial=%d widened=%d" % [initial_width, widened_width]
	)

	display._debug_autocomplete_update_count = 0
	for query in ["/perf_values/i", "/perf_values/it", "/perf_values/item_1"]:
		console.line_edit.text = query
		console.line_edit.caret_column = query.length()
		display.on_text_changed_autocomplete(query)
	await ctx.wait_frames(2)
	ctx.check(
		"same-frame input performs one filter update",
		display._debug_autocomplete_update_count == 1,
		"updates=%d" % display._debug_autocomplete_update_count
	)
	active_index = display._autocomplete_active_column_index
	active_column = display._autocomplete_column_nodes[active_index] if active_index >= 0 and active_index < display._autocomplete_column_nodes.size() else null
	ctx.check(
		"filtering preserves the active column control",
		active_column != null and active_column.get_instance_id() == active_column_id,
		"before=%d after=%d" % [active_column_id, active_column.get_instance_id() if active_column != null else 0]
	)

	_getter_counts.clear()
	console.line_edit.text = "//item"
	console.line_edit.caret_column = console.line_edit.text.length()
	display.on_text_changed_autocomplete(console.line_edit.text)
	await ctx.wait_frames(2)
	_getter_counts.clear()
	display.update_autocomplete_popup()
	ctx.check("global search executes no value getters", _getter_counts.is_empty(), str(_getter_counts))

	display.hide_command_entry_mode()
	display._debug_autocomplete_update_count = 0
	display.show_command_entry_mode("/", false)
	await ctx.wait_frames(2)
	ctx.check(
		"opening builds autocomplete once",
		display._debug_autocomplete_update_count == 1,
		"updates=%d" % display._debug_autocomplete_update_count
	)

	display.hide_command_entry_mode()
	for address in addresses:
		console.remove_display_variable(address)


func _read_value(address: String) -> String:
	_getter_counts[address] = int(_getter_counts.get(address, 0)) + 1
	if address.ends_with("item_63"):
		return "this is the widest lazy value in the column"
	return address
