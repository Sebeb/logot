extends LogotTestCase


func _init() -> void:
	id = "orderable_groups_shortcuts_and_highlights"
	display_name = "Orderable Groups, Shortcuts, and Highlights"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var objects := [
		{"id": "alpha", "label": "Alpha", "order": 0},
		{"id": "beta", "label": "Beta", "order": 1},
		{"id": "gamma", "label": "Gamma", "order": 2},
	]
	var fetch := func() -> Array: return objects
	var get_order := func(object: Dictionary) -> int: return int(object.get("order", 0))
	var set_order := func(object: Dictionary, order: int) -> void:
		for stored in objects:
			if stored.get("id") == object.get("id"):
				stored["order"] = order

	ctx.console.add_orderable_group("test-orderable/items", fetch, get_order, set_order)
	var commands: Dictionary = ctx.console.get_console_commands()
	ctx.check("orderable objects become labeled commands", commands.has("test-orderable/items/alpha") and commands["test-orderable/items/alpha"].display_label == "Alpha")
	ctx.check("objects carry orderable metadata", commands["test-orderable/items/alpha"].orderable_group == "test-orderable/items")
	ctx.check("move submenu contains four actions", commands.has("test-orderable/items/alpha/move_up") and commands.has("test-orderable/items/alpha/move_down") and commands.has("test-orderable/items/alpha/move_to_top") and commands.has("test-orderable/items/alpha/move_to_bottom"))
	ctx.check("move actions use expected shortcuts", commands["test-orderable/items/alpha/move_up"].keyboard_shortcut == KEY_UP and commands["test-orderable/items/alpha/move_to_top"].keyboard_shortcut == (KEY_UP | KEY_MASK_SHIFT))

	ctx.console._move_orderable_object("test-orderable/items", "beta", -1, false)
	ctx.check("move callback rewrites every order", objects[0].order == 1 and objects[1].order == 0 and objects[2].order == 2)
	ctx.console._drag_orderable_object("test-orderable/items", "gamma", "beta")
	ctx.check("drag callback moves to target position", objects[2].order == 0 and objects[1].order == 1 and objects[0].order == 2)

	var display = ctx.console._get_active_display()
	ctx.check("active display exists", display != null)
	var object_matches: Array = display._build_tier_matches("test-orderable/items/", "")
	var alpha_match := _find_match(object_matches, "test-orderable/items/alpha")
	ctx.check("orderable row exposes drag metadata", bool(alpha_match.get("draggable", false)) and alpha_match.get("orderable_object_id") == "alpha")
	ctx.check("palette rows follow current object order", str(object_matches[0].get("tier", "")).ends_with("gamma") and str(object_matches[1].get("tier", "")).ends_with("beta") and str(object_matches[2].get("tier", "")).ends_with("alpha"))
	display._autocomplete_active_column_index = 0
	var shortcut_states: Array[Dictionary] = [
		{"matches": [
			{"tier": "current/top", "keyboard_shortcut": KEY_K},
			{"tier": "current/lower", "keyboard_shortcut": KEY_K},
		]},
		{"preview": true, "matches": [
			{"tier": "preview/top", "keyboard_shortcut": KEY_K},
			{"tier": "preview/lower", "keyboard_shortcut": KEY_K},
		]},
	]
	display._autocomplete_column_states = shortcut_states
	display._resolve_visible_keyboard_shortcuts()
	var current_matches: Array = display._autocomplete_column_states[0].matches
	var preview_matches: Array = display._autocomplete_column_states[1].matches
	ctx.check("preview shortcut trumps current shortcut", bool(current_matches[0].get("shortcut_trumped", false)) and not bool(preview_matches[0].get("shortcut_trumped", false)))
	ctx.check("top sibling wins shortcut clash", bool(current_matches[1].get("shortcut_trumped", false)) and bool(preview_matches[1].get("shortcut_trumped", false)))
	ctx.check("preview shortcuts become invisible highlights", bool(preview_matches[0].get("highlighted", false)) and bool(preview_matches[1].get("highlighted", false)))

	var rows: Array[Dictionary] = []
	for index in range(10):
		rows.append({"label": str(index), "highlighted": index in [0, 5, 9]})
	var collapsed: Array = display._collapse_rows_between_highlights(rows, 6)
	ctx.check("multi-highlight gaps collapse to fit", collapsed.size() <= 6)
	ctx.check("collapsed gaps retain all highlights", _count_highlights(collapsed) == 3)
	ctx.check("collapsed gaps render disabled summaries", _has_hidden_summary(collapsed))
	var expanded: Array = display._collapse_rows_between_highlights(rows, 12)
	ctx.check("larger palette restores hidden rows", expanded.size() == rows.size())


func _find_match(matches: Array, tier: String) -> Dictionary:
	for match_variant in matches:
		var match: Dictionary = match_variant
		if str(match.get("tier", "")) == tier:
			return match
	return {}


func _count_highlights(rows: Array) -> int:
	var count := 0
	for row_variant in rows:
		var row: Dictionary = row_variant
		if bool(row.get("highlighted", false)) or bool(row.get("default_focus", false)):
			count += 1
	return count


func _has_hidden_summary(rows: Array) -> bool:
	for row_variant in rows:
		var row: Dictionary = row_variant
		if bool(row.get("disabled", false)) and str(row.get("label", "")).contains("hidden options"):
			return true
	return false
