extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")

const ROOT := "command_descriptor"

var _legacy_call_count := 0


func _init() -> void:
	id = "command_descriptor_registration"
	display_name = "Command Descriptor Registration"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	console.add_command("%s/named/child" % ROOT, Callable(self, "_noop"))
	console.add_command("%s/named" % ROOT, {
		"function": Callable(self, "_noop"),
		"arguments": ["target"],
		"required": 1,
		"description": "Named command",
		"group": {"name": "named group", "priority": 3, "tint": Color("60a5fa")},
		"option_group": {"name": "named options", "priority": 4, "tint": Color("34d399")},
		"display_label": "Named label",
		"default_child": {"path": "child", "provider": Callable(self, "_default_child")},
		"keyboard_shortcut": KEY_F6,
	})
	console.add_command_with_options("%s/options" % ROOT, {
		"function": Callable(self, "_noop"),
		"arguments": ["value"],
		"argument_options_provider": Callable(self, "_get_options"),
		"value_getter": Callable(self, "_get_value"),
		"group": {"name": "option group", "priority": 5},
	})
	console.add_command("%s/legacy" % ROOT, Callable(self, "_run_legacy"))

	var named = console.get_console_commands().get("%s/named" % ROOT)
	ctx.check("descriptor produces typed command", named is LogotDisplay.LogotCommand)
	if named is LogotDisplay.LogotCommand:
		var command := named as LogotDisplay.LogotCommand
		ctx.check(
			"descriptor maps named fields",
			command.arguments == PackedStringArray(["target"]) and command.required == 1 and command.description == "Named command" and command.group_name == "named group" and command.group_priority == 3 and command.option_group_name == "named options" and command.option_group_priority == 4 and command.display_label == "Named label" and command.default_child_path == "child" and command.default_child_provider.is_valid() and command.keyboard_shortcut == KEY_F6,
			str(command)
		)
		ctx.check("descriptor maps group tints", command.group_tint.is_equal_approx(Color("60a5fa")) and command.option_group_tint.is_equal_approx(Color("34d399")))

	var option_values: Array = console._get_command_argument_option_values("%s/options" % ROOT, 0)
	ctx.check("option descriptor preserves providers", option_values == ["first", "second"])

	var direct_descriptor := LogotDisplay.LogotCommand.new({
		"function": Callable(self, "_noop"),
		"arguments": ["direct"],
		"group": {"name": "direct group", "priority": 6},
	})
	ctx.check("constructor accepts descriptor", direct_descriptor.arguments == PackedStringArray(["direct"]) and direct_descriptor.group_name == "direct group" and direct_descriptor.group_priority == 6)

	var legacy_result: Dictionary = console.execute_console_command("/%s/legacy" % ROOT)
	ctx.check("legacy positional shim still executes", bool(legacy_result.get("ok", false)) and _legacy_call_count == 1, str(legacy_result))


func _get_options() -> Array:
	return [["first", "second"]]


func _get_value() -> String:
	return "first"


func _default_child() -> String:
	return "child"


func _run_legacy() -> void:
	_legacy_call_count += 1


func _noop() -> void:
	pass
