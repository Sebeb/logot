extends LogotTestCase


func _init() -> void:
	id = "command_group_scope"
	display_name = "Command Group Scope"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var display = ctx.console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	ctx.check("root dev submenu has no inherited group", _match_has_no_group(display._build_tier_matches("", ""), "dev"))
	ctx.check("performance submenu has no inherited group", _match_has_no_group(display._build_tier_matches("dev/", ""), "dev/performance"))
	ctx.check("performance commands have no redundant group", _match_has_no_group(display._build_tier_matches("dev/performance/", ""), "dev/performance/time_range"))

	var option_matches: Array = display._build_tier_matches("dev/performance/time_range/", "")
	ctx.check("time-range exposes options", not option_matches.is_empty())
	for match_data in option_matches:
		ctx.check("time-range option has no command group", str((match_data as Dictionary).get("group_name", "")).strip_edges().is_empty())


func _match_has_no_group(matches: Array, tier: String) -> bool:
	for match_data in matches:
		var match := match_data as Dictionary
		if str(match.get("tier", "")) == tier:
			return str(match.get("group_name", "")).strip_edges().is_empty()
	return false
