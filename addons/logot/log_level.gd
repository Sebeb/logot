class_name LogLevel
extends RefCounted

## Indicating that something has gone wrong in a way which is likely to be fatal
const ERROR := 1 << 1
## Indicating that something has gone wrong, but it's not fatal and we may proceed
const WARN := 1 << 2
## Command input/output from the console
const COMMAND := 1 << 3
## Info on key events
const MESSAGE := 1 << 4
## Basic info about actions
const INFO := 1 << 5
## Excessive info about every small detail
const VERBOSE := 1 << 6
## Micro detail info that is only useful for debugging
const DEBUG := 1 << 7

const names := {
	ERROR: "ERROR",
	WARN: "WARN",
	COMMAND: "COMMAND",
	MESSAGE: "MESSAGE",
	INFO: "INFO",
	VERBOSE: "VERBOSE",
	DEBUG: "DEBUG"
}

static var inited := false

static func _get_console():
	if Engine.has_singleton("Console"):
		return Engine.get_singleton("Console")
	var tree := Engine.get_main_loop()
	if tree and tree.root and tree.root.has_node("Console"):
		return tree.root.get_node("Console")
	return null

static func init():
	if inited: return
	inited = true
	if Engine.is_editor_hint(): return
	var console = _get_console()
	if console:
		console.add_command("log_level", print_log_level)
		EngineDebugger.register_message_capture("LogLevel", on_remote_filter_change)
		console.log(["LogLevel: Initialized " + str(EngineDebugger.has_capture("LogLevel"))], LogLevel.DEBUG, "Editor")

static func print_log_level():
	var print_str = "Log levels:\n"
	for level_value in names.keys():
		print_str += "%s: %s\n" % [names[level_value], str((bool)(current & level_value))]
	var console = _get_console()
	if console:
		console.log([print_str], LogLevel.MESSAGE, "Editor")
		console.log(["LogLevel: Initialized " + str(EngineDebugger.has_capture("LogLevel"))], LogLevel.DEBUG, "Editor")

static func on_remote_filter_change(_msg, filter_value):
	var console = _get_console()
	if console:
		console.log(["LogLevel received" + _msg + ": " + str(filter_value[0])], LogLevel.DEBUG, "Editor")
	if Engine.is_editor_hint(): return

	current = filter_value[0]
	if console:
		console.log(["LogLevel: Remote filter changed to: " + str(current)], LogLevel.DEBUG, "Editor")

static var _current := -1
static var current := 0:
	set(value):
		if value == _current: return
		_current = value
		init()
		ProjectSettings.set_setting("logging/log_level", value)

	get:
		init()
		if _current == -1:
			var setting = ProjectSettings.get_setting("logging/log_level")
			if setting != null && setting != 0:
				_current = setting
			else:
				_current = LogLevel.ERROR | LogLevel.WARN | LogLevel.COMMAND | LogLevel.MESSAGE
		return _current
