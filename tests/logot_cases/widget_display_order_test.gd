extends LogotTestCase

const PREFIX := "test-widget-order/"


func _init() -> void:
	id = "widget_display_order"
	display_name = "Widget Display Ordering"
	scene_path = "res://Main.tscn"
	fail_fast = false


func run(ctx) -> void:
	print("USER_DATA_DIR_PROOF=", OS.get_user_data_dir())
	var console = ctx.console
	var display = console._get_active_display()
	var draft := LineEdit.new()
	draft.custom_minimum_size = Vector2(180, 40)
	var scene := PackedScene.new()
	ctx.check("draft scene packs", scene.pack(draft) == OK)
	draft.free()
	for key in ["gamma", "beta", "alpha"]:
		console.add_widget(PREFIX + key, scene, "", "Queue", 1)
	ctx.check("legacy calls retain alphabetical siblings", _tiers(display) == ["alpha", "beta", "gamma"])
	console.add_widget(PREFIX + "urgent", scene, "", "Urgent", -1, Vector2.ZERO, "Urgent", 999)
	console.add_widget(PREFIX + "gamma", scene, "", "Queue", 1, Vector2.ZERO, "Gamma", -2)
	console.set_widget_display_order(PREFIX + "beta", -2)
	ctx.check("group priority precedes explicit order and ties use tier name", _tiers(display) == ["urgent", "beta", "gamma", "alpha"])
	var matches: Array = display._build_tier_matches(PREFIX, "")
	ctx.check("static widgets are not draggable", not bool(matches[1].get("draggable", false)))

	if console.control != null:
		console.control.visible = true
	display.show_command_entry_mode("/" + PREFIX + "beta/", false)
	await ctx.wait_frames(2)
	var column = _widget_column(display)
	ctx.check("real palette embeds the selected widget", column != null)
	if column != null:
		var widget = column._embedded_widget
		var registry = console.get_widgets()[PREFIX + "beta"]
		var column_id: int = column.get_instance_id()
		var widget_id: int = widget.get_instance_id()
		widget.text = "unsaved review draft"
		widget.grab_focus()
		widget.caret_column = 7
		ctx.check("draft owns focus before update", widget.has_focus())
		ctx.check("normalized setter accepts existing address", console.set_widget_display_order("  " + PREFIX + "beta/  ", 20))
		await ctx.wait_frames(2)
		var updated = _widget_column(display)
		ctx.check("ordering update preserves registry identity", console.get_widgets()[PREFIX + "beta"] == registry)
		ctx.check("ordering update preserves column and widget identity", updated != null and updated.get_instance_id() == column_id and updated._embedded_widget.get_instance_id() == widget_id)
		ctx.check("ordering update retains focus draft and caret", is_instance_valid(widget) and widget.has_focus() and widget.text == "unsaved review draft" and widget.caret_column == 7)
		ctx.check("live sibling column refreshes after send to bottom", _visible_siblings(display) == ["urgent", "gamma", "alpha", "beta"])
	ctx.check("updated sibling builder follows new order", _tiers(display) == ["urgent", "gamma", "alpha", "beta"])
	var revision: int = console._command_catalog_revision
	ctx.check("same order succeeds without invalidation", console.set_widget_display_order(PREFIX + "beta", 20) and console._command_catalog_revision == revision)
	display.hide_command_entry_mode()
	for key in ["alpha", "beta", "gamma", "urgent"]:
		console.remove_widget(PREFIX + key)
	ctx.check("removed widgets leave no sibling metadata", _tiers(display).is_empty())
	ctx.check("setter refuses removed widget", not console.set_widget_display_order(PREFIX + "beta", -10))
	console.add_widget(PREFIX + "beta", scene)
	ctx.check("reregistering does not retain stale order", console.get_widgets()[PREFIX + "beta"].display_order == 0)
	console.remove_widget(PREFIX + "beta")
	console.widgets[PREFIX + "dictionary"] = {"scene_or_path": scene, "display_order": 5}
	console.add_widget(PREFIX + "alpha", scene)
	var dictionary: Dictionary = console.widgets[PREFIX + "dictionary"]
	ctx.check("dictionary widget supports in-place order update", console.set_widget_display_order(PREFIX + "dictionary", -1) and dictionary.display_order == -1)
	ctx.check("dictionary order reaches sibling sorting", _tiers(display) == ["dictionary", "alpha"])
	console.remove_widget(PREFIX + "dictionary")
	console.remove_widget(PREFIX + "alpha")


func _tiers(display) -> Array:
	return _match_names(display._build_tier_matches(PREFIX, ""))


func _match_names(matches: Array) -> Array:
	var names: Array = []
	for match_data in matches:
		names.append(str(match_data.get("tier", "")).trim_prefix(PREFIX))
	return names


func _widget_column(display):
	for column in display._autocomplete_column_nodes:
		if column.get_embedded_widget_path() == PREFIX + "beta":
			return column
	return null


func _visible_siblings(display) -> Array:
	for state in display._autocomplete_column_states:
		if str(state.get("prefix", "")) == PREFIX:
			return _match_names(state.get("matches", []))
	return []
