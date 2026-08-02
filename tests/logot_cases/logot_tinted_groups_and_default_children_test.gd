extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")

const ROOT := "catalog_spec"
const TYPED_TINT := Color("3b82f6")
const TYPED_OPTION_TINT := Color("14b8a6")
const DICTIONARY_TINT := Color("a855f7")
const DICTIONARY_OPTION_TINT := Color("f97316")

var _static_terminal_count := 0
var _recursive_terminal_count := 0
var _dynamic_target := "first"


func _init() -> void:
	id = "logot_tinted_groups_and_default_children"
	display_name = "Logot Tinted Groups And Default Children"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	_register_tint_commands(console)
	_assert_tint_normalization(ctx, display)
	_register_default_child_commands(console)
	_assert_default_child_resolution(ctx, console)
	_assert_default_child_execution(ctx, console)
	_assert_invalid_default_children(ctx, console)


func _register_tint_commands(console) -> void:
	console.add_command(
		"%s/tint/typed" % ROOT,
		Callable(self, "_noop"),
		[],
		0,
		"",
		"typed group",
		3,
		"",
		0,
		"",
		null,
		TYPED_TINT
	)
	console.add_command_with_options(
		"%s/tint/typed_options" % ROOT,
		Callable(self, "_noop"),
		["value"],
		0,
		"",
		Callable(),
		Callable(),
		"",
		0,
		"typed options",
		4,
		Color.TRANSPARENT,
		TYPED_OPTION_TINT
	)
	console.console_commands["%s/tint/dictionary" % ROOT] = {
		"function": Callable(self, "_noop"),
		"arguments": [],
		"required": 0,
		"group": {
			"name": "dictionary group",
			"priority": 5,
			"tint": "a855f7",
		},
	}
	console.console_commands["%s/tint/dictionary_options" % ROOT] = {
		"function": Callable(self, "_noop"),
		"arguments": ["value"],
		"required": 0,
		"option_group": {
			"name": "dictionary options",
			"priority": 6,
			"tint": "f97316",
		},
	}
	console._notify_command_catalog_changed()


func _assert_tint_normalization(ctx, display) -> void:
	var typed_group: Dictionary = display._get_command_group_data("%s/tint/typed" % ROOT)
	ctx.check(
		"typed group tint normalizes",
		str(typed_group.get("name", "")) == "typed group" and int(typed_group.get("priority", 0)) == 3 and _matches_color(typed_group.get("tint", null), TYPED_TINT),
		str(typed_group)
	)
	var typed_option_group: Dictionary = display._get_command_option_group_data("%s/tint/typed_options" % ROOT)
	ctx.check(
		"typed option group tint normalizes",
		str(typed_option_group.get("name", "")) == "typed options" and int(typed_option_group.get("priority", 0)) == 4 and _matches_color(typed_option_group.get("tint", null), TYPED_OPTION_TINT),
		str(typed_option_group)
	)
	var dictionary_group: Dictionary = display._get_command_group_data("%s/tint/dictionary" % ROOT)
	ctx.check(
		"dictionary group tint normalizes",
		str(dictionary_group.get("name", "")) == "dictionary group" and int(dictionary_group.get("priority", 0)) == 5 and _matches_color(dictionary_group.get("tint", null), DICTIONARY_TINT),
		str(dictionary_group)
	)
	var dictionary_option_group: Dictionary = display._get_command_option_group_data("%s/tint/dictionary_options" % ROOT)
	ctx.check(
		"dictionary option group tint normalizes",
		str(dictionary_option_group.get("name", "")) == "dictionary options" and int(dictionary_option_group.get("priority", 0)) == 6 and _matches_color(dictionary_option_group.get("tint", null), DICTIONARY_OPTION_TINT),
		str(dictionary_option_group)
	)


func _register_default_child_commands(console) -> void:
	console.add_command("%s/static/child" % ROOT, Callable(self, "_run_static_terminal"))
	console.add_command("%s/static" % ROOT, Callable(), [], 0, "", "", 0, "", 0, "", null, Color.TRANSPARENT, Color.TRANSPARENT, "child")

	console.add_command("%s/recursive/branch/leaf" % ROOT, Callable(self, "_run_recursive_terminal"))
	console.add_command("%s/recursive/branch" % ROOT, Callable(), [], 0, "", "", 0, "", 0, "", null, Color.TRANSPARENT, Color.TRANSPARENT, "leaf")
	console.add_command("%s/recursive" % ROOT, Callable(), [], 0, "", "", 0, "", 0, "", null, Color.TRANSPARENT, Color.TRANSPARENT, "branch")

	console.add_command("%s/dynamic/first" % ROOT, Callable(self, "_noop"))
	console.add_command("%s/dynamic/second" % ROOT, Callable(self, "_noop"))
	console.add_command("%s/dynamic" % ROOT, Callable(), [], 0, "", "", 0, "", 0, "", null, Color.TRANSPARENT, Color.TRANSPARENT, "", Callable(self, "_get_dynamic_target"))

	console.add_command("%s/text" % ROOT, Callable(), [], 0, "", "", 0, "", 0, "", null, Color.TRANSPARENT, Color.TRANSPARENT, "../../pins/save")


func _assert_default_child_resolution(ctx, console) -> void:
	var static_result: Dictionary = console.resolve_default_child_chain("%s/static" % ROOT)
	ctx.check(
		"static default resolves its child",
		bool(static_result.get("valid", false)) and str(static_result.get("terminal_command", "")) == "%s/static/child" % ROOT and static_result.get("focus_paths", []) == ["%s/static/child" % ROOT],
		str(static_result)
	)
	var recursive_result: Dictionary = console.resolve_default_child_chain("%s/recursive" % ROOT)
	ctx.check(
		"recursive defaults resolve the terminal chain",
		bool(recursive_result.get("valid", false)) and str(recursive_result.get("terminal_command", "")) == "%s/recursive/branch/leaf" % ROOT and recursive_result.get("focus_paths", []) == ["%s/recursive/branch" % ROOT, "%s/recursive/branch/leaf" % ROOT],
		str(recursive_result)
	)
	var dynamic_first: Dictionary = console.resolve_default_child_chain("%s/dynamic" % ROOT)
	_dynamic_target = "second"
	console._notify_command_catalog_changed()
	var dynamic_second: Dictionary = console.resolve_default_child_chain("%s/dynamic" % ROOT)
	ctx.check(
		"dynamic default refreshes its resolution",
		str(dynamic_first.get("terminal_command", "")) == "%s/dynamic/first" % ROOT and str(dynamic_second.get("terminal_command", "")) == "%s/dynamic/second" % ROOT,
		"first=%s second=%s" % [str(dynamic_first), str(dynamic_second)]
	)
	var text_result: Dictionary = console.resolve_default_child_chain("%s/text" % ROOT)
	ctx.check(
		"text input terminal is a valid default child",
		bool(text_result.get("valid", false)) and str(text_result.get("terminal_command", "")) == "pins/save",
		str(text_result)
	)


func _assert_default_child_execution(ctx, console) -> void:
	_static_terminal_count = 0
	var static_execution: Dictionary = console.execute_console_command("/%s/static" % ROOT)
	ctx.check(
		"direct static execution invokes its terminal exactly once",
		bool(static_execution.get("ok", false)) and _static_terminal_count == 1,
		"result=%s count=%d" % [str(static_execution), _static_terminal_count]
	)
	_recursive_terminal_count = 0
	var recursive_execution: Dictionary = console.execute_console_command("/%s/recursive" % ROOT)
	ctx.check(
		"direct recursive execution invokes only the final terminal once",
		bool(recursive_execution.get("ok", false)) and _recursive_terminal_count == 1,
		"result=%s count=%d" % [str(recursive_execution), _recursive_terminal_count]
	)


func _assert_invalid_default_children(ctx, console) -> void:
	var cycle_a := _new_command()
	cycle_a.default_child_path = "../cycle_b"
	var cycle_b := _new_command()
	cycle_b.default_child_path = "../cycle_a"
	console.console_commands["%s/invalid/cycle_a" % ROOT] = cycle_a
	console.console_commands["%s/invalid/cycle_b" % ROOT] = cycle_b
	var cycle_result: Dictionary = console.resolve_default_child_chain("%s/invalid/cycle_a" % ROOT)
	ctx.check("default cycles are rejected", not bool(cycle_result.get("valid", true)) and str(cycle_result.get("error", "")).contains("cycle"), str(cycle_result))

	var missing_parent := _new_command()
	missing_parent.default_child_path = "missing"
	console.console_commands["%s/invalid/missing_parent" % ROOT] = missing_parent
	var missing_result: Dictionary = console.resolve_default_child_chain("%s/invalid/missing_parent" % ROOT)
	ctx.check("missing default targets are rejected", not bool(missing_result.get("valid", true)) and str(missing_result.get("error", "")).contains("missing or stale"), str(missing_result))

	var disabled_leaf := _new_command(Callable(self, "_noop"))
	var disabled_parent := _new_command()
	disabled_parent.default_child_path = "leaf"
	console.console_commands["%s/invalid/disabled/leaf" % ROOT] = disabled_leaf
	console.console_commands["%s/invalid/disabled" % ROOT] = disabled_parent
	console._disabled_command_paths["%s/invalid/disabled/leaf" % ROOT] = true
	var disabled_result: Dictionary = console.resolve_default_child_chain("%s/invalid/disabled" % ROOT)
	ctx.check("disabled default targets are rejected", not bool(disabled_result.get("valid", true)) and str(disabled_result.get("error", "")).contains("disabled"), str(disabled_result))
	console._disabled_command_paths.erase("%s/invalid/disabled/leaf" % ROOT)


func _new_command(callback: Callable = Callable()) -> LogotDisplay.LogotCommand:
	return LogotDisplay.LogotCommand.new(callback, PackedStringArray())


func _matches_color(value: Variant, expected: Color) -> bool:
	return value is Color and (value as Color).is_equal_approx(expected)


func _get_dynamic_target() -> String:
	return _dynamic_target


func _run_static_terminal() -> void:
	_static_terminal_count += 1


func _run_recursive_terminal() -> void:
	_recursive_terminal_count += 1


func _noop() -> void:
	pass
