@tool
extends Node

# =============================================================================
# ENGINE LOGGER - Intercepts Godot's internal logging
# =============================================================================

class EngineLogger extends Logger:
	var _in_logger_callback := false
	var console = null

	## Intercepts engine errors and warnings (push_error, push_warning, etc.)
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		# Prevent recursive logging loops if our own logging triggers engine output.
		if _in_logger_callback:
			return
		if console == null or not console._engine_logging_enabled:
			return

		_in_logger_callback = true
		# Map error_type to our LogLevel
		var level: int
		if error_type == ERROR_TYPE_WARNING:
			level = LogLevel.WARN
		else:
			level = LogLevel.ERROR

		# Build the message
		var message: String
		if rationale != "":
			message = rationale
		else:
			message = code

		# Add source location info
		var source_info := ""
		if file != "" and line > 0:
			# Extract just the filename from the path
			var filename := file.get_file()
			source_info = " [%s:%d]" % [filename, line]

		# Extract backtrace as separate string (not included in message)
		var backtrace_str := ""
		if script_backtraces.size() > 0:
			var gdscript_idx := script_backtraces.find_custom(func(bt: ScriptBacktrace) -> bool:
				return bt.get_language_name() == "GDScript")
			if gdscript_idx != -1:
				backtrace_str = str(script_backtraces[gdscript_idx])

		var full_message := message + source_info
		console.log([full_message], level, "Godot", backtrace_str)
		_in_logger_callback = false

	## Intercepts engine messages (print, print_rich, etc.)
	func _log_message(message: String, error: bool) -> void:
		# Prevent recursive logging loops if our own logging triggers engine output.
		if _in_logger_callback:
			return
		if console == null or not console._engine_logging_enabled:
			return

		_in_logger_callback = true
		# Skip our own formatted messages (marked with Klingon lang tag)
		if message.begins_with("[lang=tlh]"):
			_in_logger_callback = false
			return

		# Trim trailing newline that print() adds
		message = message.trim_suffix("\n")

		# Skip empty messages
		if message.is_empty():
			_in_logger_callback = false
			return

		# Capture current stack trace for debugging context
		var backtrace_str := ""
		var stack := get_stack()
		if stack.size() > 0:
			var lines: PackedStringArray = []
			lines.append("GDScript backtrace (most recent call first):")
			for i in range(stack.size()):
				var frame: Dictionary = stack[i]
				lines.append("    [%d] %s (%s:%d)" % [i, frame.get("function", "?"), frame.get("source", "?"), frame.get("line", 0)])
			backtrace_str = "\n".join(lines)

		var level := LogLevel.ERROR if error else LogLevel.INFO
		console.log([message], level, "Godot", backtrace_str)
		_in_logger_callback = false


# =============================================================================
# CONFIGURATION CONSTANTS
# =============================================================================
const MAX_LOG_ENTRIES := 1000
const SIDEBAR_BREAKPOINT := 800
const DEFAULT_CHANNEL_DISPLAY_NAME := "General"
const SETTINGS_FILE := "user://console_filters.cfg"
const TEST_COMMANDS_SETTING := "addons/logot/enable_test_commands"
const CONSOLE_INTERFACING_TEST_COMMANDS_SCRIPT_PATH := "res://tests/console_interfacing/console_interfacing_commands.gd"
const DEFAULT_BRIDGE_SCREENSHOT_DIR := "user://artifacts/screenshots"

# Preload scenes and scripts
const LogLevel = preload("res://Addons/logot/log_level.gd")
const LogotDisplay = preload("res://Addons/logot/logot_display.gd")
const LogotCommandInput = preload("res://Addons/logot/logot_command_input.gd")
const LOGOT_UI_SCENE := preload("res://Addons/logot/logot.tscn")
const LogotTestManagerScript = preload("res://Addons/logot/testing/logot_test_manager.gd")
const LogotTestPanelScript = preload("res://Addons/logot/testing/logot_test_panel.gd")

# =============================================================================
# TYPE ALIASES - Use classes from LogotDisplay
# =============================================================================
const VisibilityMode = LogotDisplay.VisibilityMode
const LogEntry = LogotDisplay.LogEntry
const LogotCommand = LogotDisplay.LogotCommand
const LogotDisplayVariable = LogotDisplay.LogotDisplayVariable


# =============================================================================
# DEBUGGER COMMUNICATION (game -> editor)
# =============================================================================
const DEBUGGER_MESSAGE_PREFIX := "logot"
var _debugger_connected := false

# =============================================================================
# EXISTING CONSOLE PROPERTIES
# =============================================================================
var enabled := true
var enable_on_release_build := false : set = set_enable_on_release_build
var pause_enabled := false

# Engine logging integration
var _engine_logging_enabled := true
var _engine_logger: EngineLogger

signal console_opened
signal console_closed
signal console_unknown_command
signal log_entry_added(entry: LogEntry)
signal logs_cleared
signal channel_discovered(channel: String)
signal off_log_tracked(level: int, channel: String)

var control: Control
var rich_label: RichTextLabel
var line_edit: LineEdit
var theme: Theme = preload("res://Addons/logot/logot_theme.tres")

var console_commands := {}
var display_variables := {}
var console_history := []
var was_paused_already := false
var _pending_pinned_display_variables: Dictionary = {}
var _external_displays: Array = []
var _console_interfacing_test_commands: RefCounted = null
var _test_manager = null
var _test_panel = null
var _test_button: Button = null
var _test_panel_input_row: HBoxContainer = null

# =============================================================================
# LOG SYSTEM PROPERTIES
# =============================================================================
var _log_entries: Array[LogEntry] = []
var _next_log_id: int = 0

# Visibility modes: {LogLevel.X: VisibilityMode} and {"channel_name": VisibilityMode}
var _level_visibility: Dictionary = {}
var _channel_visibility: Dictionary = {}

# Known channels (auto-populated as logs come in)
var _known_channels: Array[String] = []

# Track logs rejected by can_log (level/channel was OFF)
var _off_level_counts: Dictionary = {}  # {level: int}
var _off_channel_counts: Dictionary = {}  # {channel: int}

# =============================================================================
# UI COMPONENTS - Display base handles most UI logic
# =============================================================================
var _logot_ui: Control  # Root of the instantiated logot UI scene
var _display: LogotDisplay  # Handles filtering, display, sidebar, autocomplete
var _is_sidebar_layout := true
var _restore_full_console_after_command_entry := false

# Settings toggles (synced with display)
var _collapse_duplicates := false
var _wrap_text := false
var _truncate_multiline := true


# =============================================================================
# CORE LOGGING FUNCTIONS
# =============================================================================

## Returns true if neither level nor channel is set to OFF
func can_log(level: int = LogLevel.MESSAGE, channel: String = "") -> bool:
	if _level_visibility.get(level, VisibilityMode.SHOWN) == VisibilityMode.OFF:
		return false
	if channel != "" and _channel_visibility.get(channel, VisibilityMode.SHOWN) == VisibilityMode.OFF:
		return false
	return true


## Log with objects array. Always evaluates objects.
## stack_trace is optional and will be hidden by default (shown when expanded)
func log(objects: Array, level: int = LogLevel.MESSAGE, channel: String = "", stack_trace: String = "") -> void:
	_ensure_channel_exists(channel)
	_ensure_level_exists(level)

	# Capture stack trace if not provided
	if stack_trace.is_empty():
		var stack := get_stack()
		if stack.size() > 0:
			var lines: PackedStringArray = []
			lines.append("GDScript backtrace (most recent call first):")
			for i in range(1, stack.size() -1):
				var frame: Dictionary = stack[i]
				lines.append("    [%d] %s (%s:%d)" % [i, frame.get("function", "?"), frame.get("source", "?"), frame.get("line", 0)])
			stack_trace = "\n".join(lines)

	var entry := _create_log_entry(objects, level, channel, stack_trace)
	_log_entries.append(entry)

	# Update display if available
	if _display:
		_display.ensure_channel(channel)
		_display.update_stats_for_entry(entry)
		if _display.should_display_entry(entry):
			_display.display_entry(entry)
			entry.visible = true
		_display.update_sidebar_statistics()

	_trim_old_entries()

	# Send to editor via debugger (for running game instances)
	_send_log_entry_to_editor(entry)

	# Emit signal for editor panel
	log_entry_added.emit(entry)


## Log with lazy evaluation. Only calls objects_fn if can_log() returns true.
## Tracks rejected logs when level or channel is OFF.
func try_log(objects_fn: Callable, level: int = LogLevel.MESSAGE, channel: String = "") -> void:
	_ensure_channel_exists(channel)
	_ensure_level_exists(level)

	if can_log(level, channel):
		var objects: Array = objects_fn.call()
		self.log(objects, level, channel)
	else:
		# Track this rejected log
		_track_off_log(level, channel)


# =============================================================================
# LOG ENTRY HELPERS
# =============================================================================

func _create_log_entry(objects: Array, level: int, channel: String, stack_trace: String = "") -> LogEntry:
	var text := _format_objects(objects)

	# Split text into lines to handle multi-line messages
	var lines := text.split("\n")
	var first_line := lines[0] if lines.size() > 0 else ""
	var extra_line_count := lines.size() - 1

	var entry_id := _next_log_id

	# Capture timestamp at creation time
	var time := Time.get_time_dict_from_system()
	var timestamp := "%02d:%02d:%02d" % [time.hour, time.minute, time.second]

	# Determine if this entry has expandable content
	var has_expandable := extra_line_count > 0 or stack_trace != ""

	# Format first line only (collapsed view) and full text (expanded view)
	var formatted_first = LogotDisplay.format_display_text(first_line, level, channel, timestamp, entry_id, true, extra_line_count, stack_trace)
	var formatted_full = LogotDisplay.format_display_text(text, level, channel, timestamp, entry_id, false, 0, stack_trace)

	var entry := LogEntry.new(entry_id, level, channel, objects, formatted_first, formatted_full, stack_trace, extra_line_count, timestamp)
	_next_log_id += 1
	return entry


## Format objects array to string (delegates to display if available)
func _format_objects(objects: Array) -> String:
	if _display:
		return _display.format_objects_for_display(objects)
	var parts: PackedStringArray = []
	for obj in objects:
		parts.append(str(obj))
	return " ".join(parts)


func get_collapsed_display_text(entry: LogEntry, truncate_multiline := _truncate_multiline) -> String:
	var display_text: String
	if truncate_multiline and entry.extra_line_count > 0:
		var full_text := _format_objects(entry.objects)
		display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
	else:
		display_text = _format_objects(entry.objects)

	var extra_lines := entry.extra_line_count if truncate_multiline else 0
	return LogotDisplay.format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace)


func _trim_old_entries() -> void:
	while _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()


## Get all log entries (for editor panel to sync)
func get_log_entries() -> Array[LogEntry]:
	return _log_entries


## Get all known channels (for editor panel to sync)
func get_known_channels() -> Array[String]:
	return _known_channels


# =============================================================================
# CHANNEL AND LEVEL MANAGEMENT
# =============================================================================

func _ensure_channel_exists(channel: String) -> void:
	if channel not in _known_channels:
		# For hierarchical channels (e.g., "navigation/nav mesh"), ensure parent channels exist first
		if "/" in channel:
			var parts := channel.split("/")
			var parent_path := ""
			for i in range(parts.size() - 1):
				if parent_path == "":
					parent_path = parts[i]
				else:
					parent_path += "/" + parts[i]
				# Recursively ensure parent exists
				_ensure_channel_exists(parent_path)

			_known_channels.append(channel)
			if channel not in _channel_visibility:
				_channel_visibility[channel] = VisibilityMode.SHOWN
			if _display:
				_display.ensure_channel(channel)
		# Notify editor via debugger
		_send_debugger_message("channel_discovered", [channel])
		channel_discovered.emit(channel)


func _ensure_level_exists(level: int) -> void:
	if level not in _level_visibility:
		_level_visibility[level] = VisibilityMode.SHOWN


## Track a log that was rejected by can_log (level or channel was OFF)
func _track_off_log(level: int, channel: String) -> void:
	# Increment rejected count for level
	if level not in _off_level_counts:
		_off_level_counts[level] = 0
	_off_level_counts[level] += 1

	# Increment rejected count for channel
	if channel not in _off_channel_counts:
		_off_channel_counts[channel] = 0
	_off_channel_counts[channel] += 1

	# Update sidebar stats if display is available
	if _display:
		# Ensure the display knows about this level/channel so stats are shown
		_display.ensure_level(level)
		_display.ensure_channel(channel)
		_display.update_sidebar_statistics()

	# Emit signal for editor panel to update its stats
	off_log_tracked.emit(level, channel)


## Get rejected log count for a level
func get_rejected_level_count(level: int) -> int:
	return _off_level_counts.get(level, 0)


## Get rejected log count for a channel
func get_rejected_channel_count(channel: String) -> int:
	return _off_channel_counts.get(channel, 0)


## Get level visibility mode
func get_level_visibility(level: int) -> int:
	return _level_visibility.get(level, VisibilityMode.SHOWN)


## Set level visibility mode
func set_level_visibility(level: int, mode: int) -> void:
	_level_visibility[level] = mode


## Get channel visibility mode
func get_channel_visibility(channel: String) -> int:
	return _channel_visibility.get(channel, VisibilityMode.SHOWN)


## Set channel visibility mode
func set_channel_visibility(channel: String, mode: int) -> void:
	_channel_visibility[channel] = mode


func _init_default_levels() -> void:
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		_ensure_level_exists(level)
	# Ensure "General" channel exists
	_ensure_channel_exists("")
	# Ensure "Godot" channel exists for engine logging
	_ensure_channel_exists("Godot")


# =============================================================================
# BACKWARD COMPATIBILITY - print_line / print_error
# =============================================================================

func print_error(text: String, print_godot := false) -> void:
	self.log([text], LogLevel.ERROR, "")
	if print_godot:
		push_error(text)


func print_line(text: String, print_godot := false) -> void:
	self.log([text], LogLevel.MESSAGE, "")
	if print_godot:
		print(text)


# =============================================================================
# CLEAR LOGS
# =============================================================================

func _clear_logs() -> void:
	_log_entries.clear()
	_next_log_id = 0
	_off_level_counts.clear()
	_off_channel_counts.clear()
	if _display:
		_display.clear_logs()
	# Notify editor via debugger
	_send_debugger_message("logs_cleared", [])
	logs_cleared.emit()


# =============================================================================
# COMMAND SYSTEM
# =============================================================================

func add_command(command_name : String, function : Callable, arguments = [], required: int = 0, description : String = "", group_name: String = "", group_priority: int = 0) -> void:
	if arguments is int:
		var param_array : PackedStringArray
		for i in range(arguments):
			param_array.append("arg_" + str(i + 1))
		console_commands[command_name] = LogotCommand.new(function, param_array, required, description, [], Callable(), Callable(), group_name, group_priority)
	elif arguments is Array:
		var str_args : PackedStringArray
		for argument in arguments:
			str_args.append(str(argument))
		console_commands[command_name] = LogotCommand.new(function, str_args, required, description, [], Callable(), Callable(), group_name, group_priority)


func add_command_with_options(command_name: String, function: Callable, arguments: Array = [], required: int = 0, description: String = "", argument_options_provider: Callable = Callable(), value_getter: Callable = Callable(), group_name: String = "", group_priority: int = 0) -> void:
	var str_args: PackedStringArray = PackedStringArray()
	for argument in arguments:
		str_args.append(str(argument))
	console_commands[command_name] = LogotCommand.new(
		function,
		str_args,
		required,
		description,
		[],
		argument_options_provider,
		value_getter,
		group_name,
		group_priority
	)


func add_setget_command(command_name: String, setter: Callable, getter: Callable, description: String = "", options_provider: Callable = Callable(), inline_color_provider: Callable = Callable(), group_name: String = "", group_priority: int = 0) -> void:
	if not setter.is_valid():
		push_warning("Cannot add set/get command '%s': invalid setter." % command_name)
		return
	if not getter.is_valid():
		push_warning("Cannot add set/get command '%s': invalid getter." % command_name)
		return

	var command_arguments: PackedStringArray = PackedStringArray(["value"])
	var argument_options_provider := func() -> Array:
		return [_resolve_setget_option_values(getter, options_provider)]
	var command_function := func(value_text: String) -> void:
		_execute_setget_command_setter(command_name, setter, getter, value_text, options_provider)

	console_commands[command_name] = LogotCommand.new(
		command_function,
		command_arguments,
		0,
		description,
		[],
		argument_options_provider,
		getter,
		group_name,
		group_priority
	)
	add_display_variable(command_name, getter, inline_color_provider)


func _resolve_setget_option_values(getter: Callable, options_provider: Callable = Callable()) -> Array:
	if options_provider.is_valid():
		return _normalize_setget_option_values(options_provider.call())

	if not getter.is_valid():
		return []

	var current_value: Variant
	current_value = getter.call()
	if typeof(current_value) == TYPE_BOOL:
		return [false, true]
	var enum_options := _resolve_setget_enum_options(getter)
	if not enum_options.is_empty():
		return enum_options

	if current_value is Object and (current_value as Object).has_method("get_options"):
		return _normalize_setget_option_values((current_value as Object).call("get_options"))

	var getter_owner = getter.get_object()
	if getter_owner != null and getter_owner is Object:
		var owner := getter_owner as Object
		if owner.has_method("get_options"):
			return _normalize_setget_option_values(owner.call("get_options"))

		var getter_method := getter.get_method()
		if not getter_method.is_empty():
			var method_base := getter_method
			if method_base.begins_with("get_"):
				method_base = method_base.substr(4)
			for method_name in [
				"get_%s_options" % method_base,
				"%s_get_options" % method_base,
				"%s_options" % method_base,
			]:
				if owner.has_method(method_name):
					var method_options = _normalize_setget_option_values(owner.call(method_name))
					if not method_options.is_empty():
						return method_options

	return []


func _resolve_setget_enum_options(getter: Callable) -> Array:
	if not getter.is_valid():
		return []

	var getter_owner = getter.get_object()
	if getter_owner == null or not (getter_owner is Object):
		return []
	var owner := getter_owner as Object
	var getter_method := getter.get_method()
	if getter_method.is_empty():
		return []

	var candidate_names: Array[String] = []
	candidate_names.append(getter_method)
	if getter_method.begins_with("get_") and getter_method.length() > 4:
		candidate_names.append(getter_method.substr(4))
	if getter_method.begins_with("_get_") and getter_method.length() > 5:
		candidate_names.append(getter_method.substr(5))

	var properties := owner.get_property_list()
	for property_info in properties:
		if not (property_info is Dictionary):
			continue
		var property_dict := property_info as Dictionary
		var property_name := str(property_dict.get("name", ""))
		if not candidate_names.has(property_name):
			continue

		var property_hint := int(property_dict.get("hint", PROPERTY_HINT_NONE))
		if property_hint != PROPERTY_HINT_ENUM:
			continue

		var hint_string := str(property_dict.get("hint_string", ""))
		var options: Array = []
		var implicit_value := 0
		for raw_entry in hint_string.split(",", false):
			var option_text := str(raw_entry).strip_edges()
			if option_text.is_empty():
				continue
			var separator_idx := option_text.find(":")
			var option_label := option_text
			var option_value: Variant = implicit_value
			if separator_idx != -1:
				option_label = option_text.substr(0, separator_idx).strip_edges()
				var explicit_value_text := option_text.substr(separator_idx + 1).strip_edges()
				if explicit_value_text.is_valid_int():
					option_value = int(explicit_value_text)
				elif explicit_value_text.is_valid_float():
					option_value = float(explicit_value_text)
				elif not explicit_value_text.is_empty():
					option_value = explicit_value_text
			else:
				option_label = option_text.strip_edges()

			if not option_label.is_empty():
				options.append({"label": option_label, "value": option_value})
				implicit_value += 1
		if not options.is_empty():
			return options

	return []


func _normalize_setget_option_values(options_data: Variant) -> Array:
	var values: Array = []
	if options_data is Array:
		for option_value in options_data:
			values.append(option_value)
		return values
	if options_data is PackedStringArray:
		for option_value in options_data:
			values.append(option_value)
		return values
	if options_data is PackedInt32Array:
		for option_value in options_data:
			values.append(option_value)
		return values
	if options_data is PackedInt64Array:
		for option_value in options_data:
			values.append(option_value)
		return values
	if options_data is PackedFloat32Array:
		for option_value in options_data:
			values.append(option_value)
		return values
	if options_data is PackedFloat64Array:
		for option_value in options_data:
			values.append(option_value)
		return values
	return values


func _match_setget_discrete_option(raw_value: String, options: Array) -> Dictionary:
	var trimmed_value := raw_value.strip_edges()
	if trimmed_value.is_empty():
		return {"matched": false}

	var lowered_value := trimmed_value.to_lower()
	for option_entry in options:
		var resolved_value = option_entry
		var candidate_texts: Array[String] = []
		if option_entry is Dictionary:
			var option_dict := option_entry as Dictionary
			resolved_value = option_dict.get("value")
			var option_label := str(option_dict.get("label", "")).strip_edges()
			if not option_label.is_empty():
				candidate_texts.append(option_label)
			candidate_texts.append(str(resolved_value))
		else:
			candidate_texts.append(str(option_entry))

		for candidate_text in candidate_texts:
			if candidate_text == trimmed_value or candidate_text.to_lower() == lowered_value:
				return {"matched": true, "value": resolved_value}
	return {"matched": false}


func _parse_bool_from_string(text: String) -> Dictionary:
	var lowered := text.strip_edges().to_lower()
	if lowered in ["true", "1", "yes", "y", "on"]:
		return {"ok": true, "value": true}
	if lowered in ["false", "0", "no", "n", "off"]:
		return {"ok": true, "value": false}
	return {"ok": false}


func _convert_setget_input_to_value(raw_value: String, current_value: Variant, discrete_options: Array) -> Dictionary:
	var option_match := _match_setget_discrete_option(raw_value, discrete_options)
	if option_match.get("matched", false):
		return {"ok": true, "value": option_match.get("value")}

	var current_type := typeof(current_value)
	match current_type:
		TYPE_BOOL:
			var parsed_bool := _parse_bool_from_string(raw_value)
			if parsed_bool.get("ok", false):
				return {"ok": true, "value": parsed_bool.get("value", false)}
			return {"ok": false, "error": "Expected a boolean value (true/false)."}
		TYPE_INT:
			var trimmed := raw_value.strip_edges()
			if trimmed.is_valid_int():
				return {"ok": true, "value": int(trimmed)}
			if trimmed.is_valid_float():
				var float_value := float(trimmed)
				if is_equal_approx(float_value, round(float_value)):
					return {"ok": true, "value": int(float_value)}
			return {"ok": false, "error": "Expected an integer value."}
		TYPE_FLOAT:
			var trimmed_float := raw_value.strip_edges()
			if trimmed_float.is_valid_float() or trimmed_float.is_valid_int():
				return {"ok": true, "value": float(trimmed_float)}
			return {"ok": false, "error": "Expected a float value."}
		TYPE_STRING:
			return {"ok": true, "value": raw_value}
		TYPE_STRING_NAME:
			return {"ok": true, "value": StringName(raw_value)}
		_:
			var parsed_value = str_to_var(raw_value)
			if typeof(parsed_value) == current_type:
				return {"ok": true, "value": parsed_value}
			return {"ok": true, "value": raw_value}


func _extract_setget_option_value(option_entry: Variant) -> Variant:
	if option_entry is Dictionary:
		return (option_entry as Dictionary).get("value")
	return option_entry


func _find_setget_option_index(current_value: Variant, options: Array) -> int:
	var current_text := str(current_value)
	for option_index in range(options.size()):
		var option_value = _extract_setget_option_value(options[option_index])
		var exact_match: bool = typeof(option_value) == typeof(current_value) and option_value == current_value
		if exact_match:
			return option_index
		if str(option_value) == current_text:
			return option_index
	return -1


func _normalize_single_command_option_list(option_data: Variant) -> Array:
	var values: Array = []
	if option_data is Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedStringArray:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedInt32Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedInt64Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedFloat32Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedFloat64Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	values.append(option_data)
	return values


func _normalize_command_option_values(options_data: Variant) -> Array:
	var normalized: Array = []
	if not (options_data is Array):
		return normalized

	var options_array: Array = options_data
	if options_array.is_empty():
		return normalized

	var first_value = options_array[0]
	if first_value is Array or first_value is PackedStringArray or first_value is PackedInt32Array or first_value is PackedInt64Array or first_value is PackedFloat32Array or first_value is PackedFloat64Array:
		for option_group in options_array:
			normalized.append(_normalize_single_command_option_list(option_group))
	else:
		normalized.append(_normalize_single_command_option_list(options_array))
	return normalized


func _get_command_argument_option_values(command_name: String, argument_index: int = 0) -> Array:
	if argument_index < 0:
		return []
	if not console_commands.has(command_name):
		return []

	var command_data = console_commands[command_name]
	if command_data is LogotCommand:
		var command := command_data as LogotCommand
		if command.argument_options_provider.is_valid():
			var provided_options = _normalize_command_option_values(command.argument_options_provider.call())
			if argument_index < provided_options.size():
				return provided_options[argument_index]

		var static_options = _normalize_command_option_values(command.argument_options)
		if argument_index < static_options.size():
			return static_options[argument_index]
		return []

	if command_data is Dictionary:
		var options_data = (command_data as Dictionary).get("argument_options", [])
		var normalized_options = _normalize_command_option_values(options_data)
		if argument_index < normalized_options.size():
			return normalized_options[argument_index]
		return []

	return []


func _is_setget_command(command_name: String) -> bool:
	if not console_commands.has(command_name):
		return false

	var command_data = console_commands[command_name]
	if command_data is LogotCommand:
		return (command_data as LogotCommand).value_getter.is_valid()
	if command_data is Dictionary:
		return bool((command_data as Dictionary).get("is_setget", false))
	return false


func _is_text_input_option_command(command_name: String) -> bool:
	return command_name == "pins/save"


func _get_pinned_display_variables_for_alias_resolution() -> Array[String]:
	var pinned_addresses: Array[String] = []

	var active_display := _get_active_display()
	if active_display and active_display.has_method("get_pinned_display_variables"):
		for address in active_display.get_pinned_display_variables():
			var address_str := str(address)
			if address_str.is_empty() or not display_variables.has(address_str) or pinned_addresses.has(address_str):
				continue
			pinned_addresses.append(address_str)

	for pending_address in _pending_pinned_display_variables:
		var pending_address_str := str(pending_address)
		if pending_address_str.is_empty() or not display_variables.has(pending_address_str) or pinned_addresses.has(pending_address_str):
			continue
		pinned_addresses.append(pending_address_str)

	pinned_addresses.sort()
	return pinned_addresses


func _encode_pins_view_alias_token(address: String) -> String:
	return address.uri_encode()


func _decode_pins_view_alias_token(token: String) -> String:
	return token.uri_decode()


func _resolve_pins_view_alias_token_target(token: String) -> String:
	if token.is_empty():
		return ""
	var decoded_address := _decode_pins_view_alias_token(token)
	if decoded_address.is_empty():
		return ""
	for address in _get_pinned_display_variables_for_alias_resolution():
		if address == decoded_address:
			return decoded_address
	return ""


func _resolve_pins_view_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if normalized_path == "pins/view" or not normalized_path.begins_with("pins/view/"):
		return normalized_path

	var alias_remainder := normalized_path.substr("pins/view/".length())
	if alias_remainder.is_empty():
		return normalized_path

	var first_separator := alias_remainder.find("/")
	var alias_token := alias_remainder if first_separator == -1 else alias_remainder.substr(0, first_separator)
	var token_suffix := "" if first_separator == -1 else alias_remainder.substr(first_separator)
	var token_target := _resolve_pins_view_alias_token_target(alias_token)
	if not token_target.is_empty():
		return token_target + token_suffix

	var best_match := ""
	for pinned_address in _get_pinned_display_variables_for_alias_resolution():
		if alias_remainder == pinned_address or alias_remainder.begins_with(pinned_address + "/"):
			if pinned_address.length() > best_match.length():
				best_match = pinned_address

	if best_match.is_empty():
		return normalized_path
	return best_match + alias_remainder.substr(best_match.length())


func _validate_command_option_segment(command_name: String, option_segment: String) -> Dictionary:
	if _is_setget_command(command_name):
		var command_data = console_commands.get(command_name)
		if command_data is LogotCommand:
			var value_getter := (command_data as LogotCommand).value_getter
			if not value_getter.is_valid():
				return {"checked": false, "valid": true}
			var current_value: Variant
			current_value = value_getter.call()
			var converted: Dictionary
			converted = _convert_setget_input_to_value(option_segment, current_value, _get_command_argument_option_values(command_name, 0))
			return {"checked": true, "valid": bool(converted.get("ok", false))}
		return {"checked": false, "valid": true}

	if _is_text_input_option_command(command_name):
		var validation := _validate_pin_overlay_name(option_segment)
		return {"checked": true, "valid": bool(validation.get("ok", false))}

	return {"checked": false, "valid": false}


func _resolve_display_variable_pin_subcommand(command_candidate: String, option_segment: String) -> Dictionary:
	if command_candidate.is_empty() or not display_variables.has(command_candidate):
		return {"valid": false}

	var option_lowered := option_segment.strip_edges().to_lower()
	var pin_state: Variant = null
	if option_lowered == "pin":
		pin_state = true
	elif option_lowered == "unpin":
		pin_state = false
	else:
		return {"valid": false}

	return {
		"valid": true,
		"command_name": "",
		"injected_arguments": [],
		"is_option_subcommand": true,
		"is_display_variable_pin_action": true,
		"display_variable_address": command_candidate,
		"display_variable_pin_state": bool(pin_state),
	}


func _resolve_console_command_path_internal(command_path: String, allow_alias_resolution: bool) -> Dictionary:
	var normalized_path := command_path.strip_edges()
	if normalized_path.is_empty():
		return {"valid": false}

	if allow_alias_resolution:
		var alias_resolved_path := _resolve_pins_view_alias_command_path(normalized_path)
		if alias_resolved_path != normalized_path:
			return _resolve_console_command_path_internal(alias_resolved_path, false)

	if console_commands.has(normalized_path):
		return {
			"valid": true,
			"command_name": normalized_path,
			"injected_arguments": [],
			"is_option_subcommand": false,
		}

	var segments := normalized_path.split("/", false)
	if segments.size() < 2:
		return {"valid": false}

	for split_index in range(segments.size() - 1, 0, -1):
		var command_candidate := "/".join(segments.slice(0, split_index))
		var option_segment := "/".join(segments.slice(split_index, segments.size()))
		if option_segment.is_empty():
			continue

		var display_variable_pin_resolution := _resolve_display_variable_pin_subcommand(command_candidate, option_segment)
		if display_variable_pin_resolution.get("valid", false):
			return display_variable_pin_resolution

		if not console_commands.has(command_candidate):
			continue

		if _is_setget_command(command_candidate):
			var setget_validation := _validate_command_option_segment(command_candidate, option_segment)
			if setget_validation.get("checked", false) and not setget_validation.get("valid", false):
				continue
			return {
				"valid": true,
				"command_name": command_candidate,
				"injected_arguments": [option_segment],
				"is_option_subcommand": true,
			}

		var option_match := _match_setget_discrete_option(option_segment, _get_command_argument_option_values(command_candidate, 0))
		if option_match.get("matched", false):
			return {
				"valid": true,
				"command_name": command_candidate,
				"injected_arguments": [option_segment],
				"is_option_subcommand": true,
			}

		var text_input_validation := _validate_command_option_segment(command_candidate, option_segment)
		if text_input_validation.get("checked", false) and text_input_validation.get("valid", false):
			return {
				"valid": true,
				"command_name": command_candidate,
				"injected_arguments": [option_segment],
				"is_option_subcommand": true,
			}

	return {"valid": false}


func _resolve_console_command_path(command_path: String) -> Dictionary:
	return _resolve_console_command_path_internal(command_path, true)


func can_execute_console_command(command_path: String) -> bool:
	return bool(_resolve_console_command_path(command_path).get("valid", false))


func _execute_setget_command_setter(command_name: String, setter: Callable, getter: Callable, value_text: String, options_provider: Callable = Callable()) -> void:
	if not setter.is_valid() or not getter.is_valid():
		print_error("Set/get command '%s' is missing a valid setter/getter." % command_name)
		return

	var current_value: Variant
	current_value = getter.call()
	var discrete_options: Array
	discrete_options = _resolve_setget_option_values(getter, options_provider)
	if value_text.strip_edges().is_empty():
		if discrete_options.is_empty():
			print_error("Failed to set '%s': this command requires a value." % command_name)
			return
		var current_index: int
		current_index = _find_setget_option_index(current_value, discrete_options)
		var next_index := 0 if current_index == -1 else (current_index + 1) % discrete_options.size()
		setter.call(_extract_setget_option_value(discrete_options[next_index]))
		var active_display := _get_active_display()
		if active_display and active_display.has_method("refresh_setget_option_highlight"):
			active_display.refresh_setget_option_highlight(command_name)
		return

	var converted := _convert_setget_input_to_value(value_text, current_value, discrete_options)
	if not converted.get("ok", false):
		var conversion_error := str(converted.get("error", "Invalid value for command '%s'." % command_name))
		print_error("Failed to set '%s': %s Received '%s'." % [command_name, conversion_error, value_text])
		return

	setter.call(converted.get("value"))
	var active_display := _get_active_display()
	if active_display and active_display.has_method("refresh_setget_option_highlight"):
		active_display.refresh_setget_option_highlight(command_name)


func remove_command(command_name : String) -> void:
	console_commands.erase(command_name)


func add_display_variable(address: String, getter: Callable, inline_color_provider: Callable = Callable()) -> void:
	display_variables[address] = LogotDisplayVariable.new(getter, inline_color_provider)


func remove_display_variable(address: String) -> void:
	display_variables.erase(address)


func pin(key: String, value_or_getter: Variant) -> void:
	var address := key.strip_edges()
	if address.is_empty():
		print_error("Pin key cannot be empty.")
		return

	var getter: Callable
	if value_or_getter is Callable:
		getter = value_or_getter as Callable
		if not getter.is_valid():
			print_error("Pin getter for '%s' is not valid." % address)
			return
	else:
		var pinned_value: Variant
		pinned_value = value_or_getter
		getter = func() -> Variant:
			return pinned_value

	add_display_variable(address, getter)
	pin_display_variable(address)


func unpin(key: String) -> void:
	var address := key.strip_edges()
	if address.is_empty():
		print_error("Pin key cannot be empty.")
		return

	unpin_display_variable(address)
	remove_display_variable(address)


func register_external_display(display: LogotDisplay) -> void:
	if display == null:
		return

	for index in range(_external_displays.size() - 1, -1, -1):
		var existing_display = _external_displays[index].get_ref()
		if existing_display == null:
			_external_displays.remove_at(index)
			continue
		if existing_display == display:
			return

	_external_displays.append(weakref(display))
	_apply_pending_pinned_display_variables_to(display)


func unregister_external_display(display: LogotDisplay) -> void:
	if display == null:
		return

	for index in range(_external_displays.size() - 1, -1, -1):
		var existing_display = _external_displays[index].get_ref()
		if existing_display == null or existing_display == display:
			_external_displays.remove_at(index)


func _get_active_display() -> LogotDisplay:
	if _display:
		return _display

	for index in range(_external_displays.size() - 1, -1, -1):
		var external_display = _external_displays[index].get_ref()
		if external_display == null:
			_external_displays.remove_at(index)
			continue
		if external_display is LogotDisplay:
			return external_display as LogotDisplay
	return null


func pin_display_variable(address: String) -> void:
	var active_display := _get_active_display()
	if active_display:
		active_display.pin_display_variable(address)
	else:
		_pending_pinned_display_variables[address] = true


func unpin_display_variable(address: String) -> void:
	var active_display := _get_active_display()
	if active_display:
		active_display.unpin_display_variable(address)
	else:
		_pending_pinned_display_variables[address] = false


func set_display_variable_pinned(address: String, pinned: bool) -> void:
	if pinned:
		pin_display_variable(address)
	else:
		unpin_display_variable(address)


func is_display_variable_pinned(address: String) -> bool:
	var active_display := _get_active_display()
	if active_display:
		return active_display.is_display_variable_pinned(address)
	return bool(_pending_pinned_display_variables.get(address, false))


func get_console_commands() -> Dictionary:
	return console_commands


func get_display_variables() -> Dictionary:
	return display_variables


func rebuild_display_view() -> void:
	if _display:
		_display.rebuild_display()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _enter_tree() -> void:
	# Initialize log system
	_init_default_levels()

	# Register engine logger to intercept Godot's internal logging
	if _engine_logger == null:
		_engine_logger = EngineLogger.new()
		_engine_logger.console = self
		OS.add_logger(_engine_logger)

	# Only set up game UI when NOT in editor
	if not Engine.is_editor_hint():
		_setup_game_ui()
		_setup_debugger_connection()

	process_mode = PROCESS_MODE_ALWAYS


# =============================================================================
# DEBUGGER CONNECTION (for editor communication)
# =============================================================================

## Set up debugger connection to communicate with editor
func _setup_debugger_connection() -> void:
	if not EngineDebugger.is_active():
		return

	# Register message capture for receiving commands from editor
	EngineDebugger.register_message_capture(DEBUGGER_MESSAGE_PREFIX, _on_debugger_message)
	_debugger_connected = true

	# Send hello message to let editor know we're here
	var project_name = ProjectSettings.get_setting("application/config/name", "Game")
	_send_debugger_message("hello", [project_name])


## Handle messages from editor debugger plugin
func _on_debugger_message(message: String, data: Array) -> bool:
	match message:
		"logot:set_level_visibility":
			if data.size() >= 2:
				set_level_visibility(int(data[0]), int(data[1]))
				if _display:
					_display.rebuild_display()
			return true
		"logot:set_channel_visibility":
			if data.size() >= 2:
				set_channel_visibility(str(data[0]), int(data[1]))
				if _display:
					_display.rebuild_display()
			return true
		"logot:clear":
			_clear_logs()
			return true
		"logot:execute_command":
			var request_id := ""
			var command_text := ""
			var stream_output := false
			if data.size() >= 1 and data[0] is Dictionary:
				var payload := data[0] as Dictionary
				request_id = str(payload.get("request_id", ""))
				command_text = str(payload.get("command", ""))
				stream_output = bool(payload.get("stream_output", false))
			elif data.size() >= 2:
				request_id = str(data[0])
				command_text = str(data[1])
				if data.size() >= 3:
					stream_output = bool(data[2])

			var command_result := execute_console_command(command_text, request_id, stream_output)
			_send_debugger_message("command_result", [command_result])
			return true
	return false


## Send a message to the editor debugger plugin
func _send_debugger_message(message: String, data: Array = []) -> void:
	if not _debugger_connected or not EngineDebugger.is_active():
		return
	EngineDebugger.send_message(DEBUGGER_MESSAGE_PREFIX + ":" + message, data)


## Send log entry to editor (called when a new log is created)
func _send_log_entry_to_editor(entry: LogEntry) -> void:
	if not _debugger_connected:
		return

	var entry_data := _serialize_log_entry(entry)
	_send_debugger_message("log_entry", [entry_data])


func _serialize_log_entry(entry: LogEntry) -> Dictionary:
	return {
		"id": entry.id,
		"level": entry.level,
		"channel": entry.channel,
		"objects": entry.objects,
		"formatted": entry.formatted,
		"formatted_full": entry.formatted_full,
		"stack_trace": entry.stack_trace,
		"extra_line_count": entry.extra_line_count,
		"timestamp": entry.timestamp,
	}


func execute_console_command(command_input: String, request_id: String = "", stream_output := false) -> Dictionary:
	var normalized_command := command_input.strip_edges()
	if normalized_command.is_empty():
		return {
			"request_id": request_id,
			"command": "",
			"ok": false,
			"error": "Command is empty.",
			"output_entries": [],
		}
	if not normalized_command.begins_with("/"):
		normalized_command = "/" + normalized_command

	var start_entry_index := _log_entries.size()
	var execution_result := _execute_command(normalized_command)
	var output_entries: Array = []
	for index in range(start_entry_index, _log_entries.size()):
		output_entries.append(_serialize_log_entry(_log_entries[index]))

	var has_error_output := false
	for entry_data in output_entries:
		if int((entry_data as Dictionary).get("level", 0)) == LogLevel.ERROR:
			has_error_output = true
			break

	if stream_output:
		for entry_data in output_entries:
			_send_debugger_message("command_output", [{
				"request_id": request_id,
				"entry": entry_data,
			}])

	var is_ok := bool(execution_result.get("ok", false)) and not has_error_output
	var error_text := str(execution_result.get("error", ""))
	if not is_ok and error_text.is_empty() and has_error_output:
		error_text = "Command emitted error output."

	return {
		"request_id": request_id,
		"command": normalized_command,
		"ok": is_ok,
		"error": error_text,
		"output_entries": output_entries,
	}


func get_test_manager():
	return _test_manager


func _ensure_test_manager():
	if _test_manager != null and is_instance_valid(_test_manager):
		return _test_manager

	_test_manager = LogotTestManagerScript.new(self)
	_test_manager.name = "LogotTestManager"
	add_child(_test_manager)
	return _test_manager


func _ensure_test_panel() -> void:
	if Engine.is_editor_hint():
		return
	if DisplayServer.get_name() == "headless":
		return
	if _logot_ui == null:
		return

	if _test_panel == null or not is_instance_valid(_test_panel):
		_test_panel = LogotTestPanelScript.new()
		_test_panel.name = "LogotTestPanel"
		_logot_ui.add_child(_test_panel)

	var input_row = _logot_ui.get_node_or_null("MainContainer/LogotContainer/VBoxContainer/InputRow")
	if input_row is HBoxContainer:
		_test_panel_input_row = input_row as HBoxContainer
		if _test_button == null or not is_instance_valid(_test_button):
			_test_button = Button.new()
			_test_button.text = "Tests"
			_test_button.pressed.connect(_toggle_test_panel)
			_test_panel_input_row.add_child(_test_button)
			var clear_button = _test_panel_input_row.get_node_or_null("ClearButton")
			if clear_button != null:
				_test_panel_input_row.move_child(_test_button, clear_button.get_index())

	_test_panel.set_manager(_ensure_test_manager())


func _toggle_test_panel() -> void:
	if _test_panel == null or not is_instance_valid(_test_panel):
		return
	_test_panel.toggle_visible()


## Set up the in-game console overlay UI (only called when running as game)
func _setup_game_ui() -> void:
	# Load console history
	var console_history_file := FileAccess.open("user://console_history.txt", FileAccess.READ)
	if console_history_file:
		while !console_history_file.eof_reached():
			var line := console_history_file.get_line()
			if line.length():
				add_input_history(line)

	# Create CanvasLayer for overlay
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 3
	add_child(canvas_layer)

	# Create the display base
	_display = LogotDisplay.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(_display)

	# Instantiate the logot UI scene as a child of display
	_logot_ui = LOGOT_UI_SCENE.instantiate()
	_logot_ui.name = "LogotUI"
	_logot_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.add_child(_logot_ui)

	# Configure the display base
	_display.set_settings_file(SETTINGS_FILE)
	_display.set_welcome_message("Development console.\n")
	_display.set_log_entries_provider(func(): return _log_entries)
	_display.set_entry_text_provider(func(entry, truncate): return get_collapsed_display_text(entry, truncate))
	_display.set_commands_provider(func(): return console_commands)
	_display.set_display_variables_provider(func(): return display_variables)
	_display.set_rejected_level_count_provider(func(level): return get_rejected_level_count(level))
	_display.set_rejected_channel_count_provider(func(channel): return get_rejected_channel_count(channel))
	_display.set_level_visibility_provider(get_level_visibility, set_level_visibility)
	_display.set_channel_visibility_provider(get_channel_visibility, set_channel_visibility)

	# Connect signals for visibility changes
	_display.custom_setting_changed.connect(_on_display_setting_changed)
	_display.cleared.connect(_on_display_cleared)
	_display.channel_deleted.connect(_on_channel_deleted)

	# Initialize the display
	_display.initialize_display()
	_sync_console_setting_cache_from_display()

	# Get references to UI nodes from display
	_logot_ui.visible = false
	control = _logot_ui
	rich_label = _display.rich_label
	line_edit = _display.line_edit

	# Set up autocomplete popups
	var history_popup = _logot_ui.get_node_or_null("AutocompleteOverlay/HistoryAutocompletePopup")
	if history_popup:
		_display.set_history_autocomplete_popup(history_popup)
	var command_popup = _logot_ui.get_node_or_null("AutocompleteOverlay/CommandAutocompletePopup")
	if command_popup:
		var command_scroll = command_popup.get_node_or_null("ScrollContainer")
		var columns_container = command_popup.get_node_or_null("ScrollContainer/ColumnsContainer")
		if command_scroll and columns_container:
			_display.set_command_autocomplete_popup(command_popup, command_scroll, columns_container)
	for command in console_history:
		_display.add_to_command_history(command)

	# Connect line edit signals
	if line_edit:
		line_edit.text_submitted.connect(on_text_entered)
		line_edit.text_changed.connect(on_line_edit_text_changed)
		line_edit.gui_input.connect(_on_line_edit_gui_input)

	_apply_pending_pinned_display_variables()
	_ensure_test_panel()


func _apply_pending_pinned_display_variables() -> void:
	if not _display:
		return
	_apply_pending_pinned_display_variables_to(_display)


func _apply_pending_pinned_display_variables_to(target_display: LogotDisplay) -> void:
	if not target_display:
		return

	for address in _pending_pinned_display_variables:
		if bool(_pending_pinned_display_variables[address]):
			target_display.pin_display_variable(str(address))
		else:
			target_display.unpin_display_variable(str(address))
	_pending_pinned_display_variables.clear()


func _on_display_setting_changed(setting_name: String, value: bool) -> void:
	match setting_name:
		"collapse_duplicates":
			_collapse_duplicates = value
		"wrap_text":
			_wrap_text = value
		"truncate_multiline":
			_truncate_multiline = value


func _on_display_cleared() -> void:
	# Display was cleared, sync our log entries
	_log_entries.clear()
	_next_log_id = 0
	logs_cleared.emit()


func _on_channel_deleted(channel: String) -> void:
	# Remove channel from our tracking
	_known_channels.erase(channel)
	_channel_visibility.erase(channel)
	_off_channel_counts.erase(channel)


func _exit_tree() -> void:
	# Remove engine logger
	if _engine_logger != null:
		OS.remove_logger(_engine_logger)
		_engine_logger = null

	# Only save history when running as game
	if Engine.is_editor_hint():
		return

	var console_history_file := FileAccess.open("user://console_history.txt", FileAccess.WRITE)
	if console_history_file:
		var write_index := 0
		var start_write_index := console_history.size() - 100
		for line in console_history:
			if write_index >= start_write_index:
				console_history_file.store_line(line)
			write_index += 1


func _sync_console_setting_cache_from_display() -> void:
	if not _display:
		return
	_collapse_duplicates = _get_console_setting_value("collapse_duplicates", _collapse_duplicates)
	_wrap_text = _get_console_setting_value("wrap_text", _wrap_text)
	_truncate_multiline = _get_console_setting_value("truncate_multiline", _truncate_multiline)


func _get_console_setting_value(setting_name: String, fallback: bool) -> bool:
	if _display:
		return _display.get_setting(setting_name, fallback)
	return fallback


func _set_console_setting_value(setting_name: String, value: bool) -> void:
	match setting_name:
		"collapse_duplicates":
			_collapse_duplicates = value
		"wrap_text":
			_wrap_text = value
		"truncate_multiline":
			_truncate_multiline = value

	if _display:
		_display.apply_setting(setting_name, value)


func _get_setting_collapse_duplicates() -> bool:
	return _get_console_setting_value("collapse_duplicates", _collapse_duplicates)


func _set_setting_collapse_duplicates(value: bool) -> void:
	_set_console_setting_value("collapse_duplicates", value)


func _get_setting_wrap_text() -> bool:
	return _get_console_setting_value("wrap_text", _wrap_text)


func _set_setting_wrap_text(value: bool) -> void:
	_set_console_setting_value("wrap_text", value)


func _get_setting_truncate_multiline() -> bool:
	return _get_console_setting_value("truncate_multiline", _truncate_multiline)


func _set_setting_truncate_multiline(value: bool) -> void:
	_set_console_setting_value("truncate_multiline", value)


func _register_console_setting_commands() -> void:
	add_setget_command(
		"console/settings/collapse_duplicates",
		_set_setting_collapse_duplicates,
		_get_setting_collapse_duplicates,
		"Set whether duplicate logs are collapsed."
	)
	add_setget_command(
		"console/settings/wrap_text",
		_set_setting_wrap_text,
		_get_setting_wrap_text,
		"Set whether log lines wrap."
	)
	add_setget_command(
		"console/settings/truncate_multiline",
		_set_setting_truncate_multiline,
		_get_setting_truncate_multiline,
		"Set whether multi-line logs are truncated in collapsed view."
	)


func _register_pin_commands() -> void:
	add_command("pins/view", _command_view_pins, [], 0, "Shows currently pinned display variables and their pin/unpin commands.")
	add_command("pins/clear", _command_clear_pins, [], 0, "Clears all pinned display variables.")
	add_command_with_options(
		"pins/save",
		_command_save_pins_overlay,
		["name"],
		1,
		"Saves the current pin selection to a named overlay.",
		_get_saved_pin_overlay_name_options
	)
	add_command_with_options(
		"pins/load",
		_command_load_pins_overlay,
		["name"],
		1,
		"Loads pinned display variables from a named overlay.",
		_get_saved_pin_overlay_name_options
	)


func _register_bridge_commands() -> void:
	add_command(
		"bridge/screenshot",
		_command_bridge_screenshot,
		["path", "name"],
		0,
		"Captures the current viewport to PNG. Accepts an optional path and optional custom name."
	)


func _register_console_interfacing_test_commands() -> void:
	if not ResourceLoader.exists(CONSOLE_INTERFACING_TEST_COMMANDS_SCRIPT_PATH):
		return

	var test_commands_script = load(CONSOLE_INTERFACING_TEST_COMMANDS_SCRIPT_PATH)
	if test_commands_script == null:
		print_error("Failed to load %s" % CONSOLE_INTERFACING_TEST_COMMANDS_SCRIPT_PATH)
		return

	_console_interfacing_test_commands = test_commands_script.new(self)
	if _console_interfacing_test_commands != null and _console_interfacing_test_commands.has_method("register"):
		_console_interfacing_test_commands.register()


func _ready() -> void:
	# Commands available in both editor and game
	add_command("console/clear", clear, 0, 0, "Clears the text on the console.")
	add_command("console/help", help, 0, 0, "Displays instructions on how to use the console.")
	add_command("console/commands", commands_list, 0, 0, "Lists all commands and their descriptions.")
	add_command("console/calc", calculate, ["mathematical expression to evaluate"], 0, "Evaluates the math passed in for quick arithmetic.")
	_register_bridge_commands()
	_ensure_test_manager()

	if _are_test_commands_enabled():
		add_command("console/test_logging", _cmd_test_logging, [], 0, "Test all logging functionality")
		add_command("console/test_off_tracking", _cmd_test_off_tracking, [], 0, "Test OFF visibility tracking")
		add_command("console/test_nested_channels", _cmd_test_nested_channels, [], 0, "Test nested/hierarchical channel functionality")
		_register_console_interfacing_test_commands()
	_register_console_setting_commands()
	_register_pin_commands()

	# Game-only commands
	if not Engine.is_editor_hint():
		add_command("console/quit", quit, 0, 0, "Quits the game.")
		add_command("exit", quit, 0, 0, "Quits the game.")
		add_command("restart", restart_application, 0, 0, "Restarts the game application.")
		add_command("console/delete_history", delete_history, 0, 0, "Deletes the history of previously entered commands.")


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _input(event : InputEvent) -> void:
	# Don't handle input in editor
	if Engine.is_editor_hint():
		return

	if event is InputEventKey:
		if _handle_line_edit_autocomplete_input(event):
			get_tree().get_root().set_input_as_handled()
			return
		if event.get_physical_keycode_with_modifiers() == KEY_QUOTELEFT:
			if event.pressed:
				toggle_console(false)
			get_tree().get_root().set_input_as_handled()
		elif event.physical_keycode == KEY_QUOTELEFT and event.is_command_or_control_pressed():
			if event.pressed:
				if control.visible:
					toggle_size()
				else:
					toggle_console(false)
					toggle_size()
			get_tree().get_root().set_input_as_handled()
		elif event.pressed and not event.echo and event.unicode == "/".unicode_at(0) and enabled and control and _display and not control.visible:
			_open_command_entry_view()
			get_tree().get_root().set_input_as_handled()
		elif (event.get_physical_keycode_with_modifiers() == KEY_ESCAPE or event.keycode == KEY_BACK) and control.visible:
			if event.pressed:
				_handle_escape_input()
				get_tree().get_root().set_input_as_handled()
		if control.visible and event.pressed:
			if event.get_physical_keycode_with_modifiers() == KEY_PAGEUP:
				var scroll := rich_label.get_v_scroll_bar()
				var tween := create_tween()
				tween.tween_property(scroll, "value", scroll.value - (scroll.page - scroll.page * 0.1), 0.1)
				get_tree().get_root().set_input_as_handled()
			if event.get_physical_keycode_with_modifiers() == KEY_PAGEDOWN:
				var scroll := rich_label.get_v_scroll_bar()
				var tween := create_tween()
				tween.tween_property(scroll, "value", scroll.value + (scroll.page - scroll.page * 0.1), 0.1)
				get_tree().get_root().set_input_as_handled()


func _handle_line_edit_autocomplete_input(event: InputEventKey) -> bool:
	if event and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK):
		if control and control.visible and line_edit and line_edit.has_focus():
			_handle_escape_input()
			return true

	return LogotCommandInput.handle_autocomplete_navigation(
		event,
		_display,
		line_edit,
		Callable(self, "_close_command_entry_view")
	)


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not _display:
		return
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if _handle_line_edit_autocomplete_input(key_event) or _handle_line_edit_submit_input(key_event):
		line_edit.accept_event()
		line_edit.call_deferred("grab_focus")


func _handle_line_edit_submit_input(event: InputEventKey) -> bool:
	if not LogotCommandInput.is_submit_event(event, line_edit):
		return false

	var keep_input := event.shift_pressed
	var selected_history_command := LogotCommandInput.get_selected_history_command(_display)
	if not selected_history_command.is_empty():
		_submit_line_edit_input(selected_history_command, keep_input, false)
		return true

	if not line_edit.text.strip_edges().begins_with("/"):
		return false

	_submit_line_edit_input(line_edit.text, keep_input, true)
	return true


# =============================================================================
# CONSOLE VISIBILITY
# =============================================================================

func toggle_size() -> void:
	if control.anchor_bottom == 1.0:
		control.anchor_bottom = 1.9
	else:
		control.anchor_bottom = 1.0


func disable():
	enabled = false
	toggle_console(true)


func enable():
	enabled = true


func toggle_console(reset_on_hide: bool = true) -> void:
	if enabled and not control.visible:
		control.visible = true
		_restore_full_console_after_command_entry = false
		was_paused_already = get_tree().paused
		get_tree().paused = was_paused_already || pause_enabled
		line_edit.grab_focus()
		console_opened.emit()
		return

	control.visible = false
	if reset_on_hide:
		if _display and _display.is_command_entry_mode():
			_display.hide_command_entry_mode()
		_restore_full_console_after_command_entry = false
		control.anchor_bottom = 1.0
		scroll_to_bottom()
		if _display:
			_display.reset_autocomplete()
			_display.clear_autocomplete_highlight_memory()
	if pause_enabled and !was_paused_already:
		get_tree().paused = false
	console_closed.emit()


func _handle_escape_input() -> void:
	if _test_panel != null and is_instance_valid(_test_panel) and _test_panel.visible:
		_test_panel.hide()
		return
	if _is_escape_close_state():
		toggle_console(true)
		return

	_reset_console_for_escape()


func _is_escape_close_state() -> bool:
	if not line_edit:
		return true
	var normalized_text := line_edit.text.strip_edges()
	return normalized_text.is_empty() or normalized_text == "/"


func _reset_console_for_escape() -> void:
	if not line_edit:
		return

	line_edit.text = "/"
	line_edit.caret_column = line_edit.text.length()
	line_edit.grab_focus()
	if _display:
		_display.begin_command_palette_reset_navigation()
		_display.clear_autocomplete_highlight_memory()
		_display.on_text_changed_autocomplete(line_edit.text)


func is_visible():
	return control.visible


func is_capturing_keyboard_input() -> bool:
	return (
		enabled
		and control != null
		and control.visible
		and line_edit != null
		and line_edit.has_focus()
	)


func scroll_to_bottom() -> void:
	if rich_label == null:
		return
	var scroll: ScrollBar = rich_label.get_v_scroll_bar()
	scroll.value = scroll.max_value - scroll.page


# =============================================================================
# COMMAND INPUT HANDLING
# =============================================================================

func parse_line_input(text : String) -> PackedStringArray:
	var out_array : PackedStringArray
	var in_quotes := false
	var escaped := false
	var token_started := false
	var token : String
	for c in text:
		if c == '\\':
			escaped = true
			token_started = true
			continue
		elif escaped:
			if c == 'n':
				c = '\n'
			elif c == 't':
				c = '\t'
			elif c == 'r':
				c = '\r'
			elif c == 'a':
				c = '\a'
			elif c == 'b':
				c = '\b'
			elif c == 'f':
				c = '\f'
			escaped = false
		elif c == '\"':
			in_quotes = !in_quotes
			token_started = true
			continue
		elif c == ' ' or c == '\t':
			if !in_quotes:
				if token_started:
					out_array.push_back(token)
					token = ""
					token_started = false
				continue
		token += c
		token_started = true
	if escaped:
		token += "\\"
		token_started = true
	if token_started:
		out_array.push_back(token)
	return out_array


func on_text_entered(new_text : String) -> void:
	_submit_line_edit_input(new_text, false, true)


func _extract_command_name(command_input: String) -> String:
	return LogotCommandInput.extract_command_name(command_input, parse_line_input)


func _resolve_submitted_text(raw_text: String, prefer_autocomplete_selection: bool) -> String:
	return LogotCommandInput.resolve_submitted_text(raw_text, prefer_autocomplete_selection, _display)


func _are_test_commands_enabled() -> bool:
	var env_value := OS.get_environment("LOGOT_ENABLE_TEST_COMMANDS").strip_edges().to_lower()
	match env_value:
		"1", "true", "yes", "on":
			return true
		"0", "false", "no", "off":
			return false

	if ProjectSettings.has_setting(TEST_COMMANDS_SETTING):
		return bool(ProjectSettings.get_setting(TEST_COMMANDS_SETTING))

	return OS.is_debug_build()


func _submit_line_edit_input(raw_text: String, keep_input: bool = false, prefer_autocomplete_selection: bool = false) -> bool:
	var submitted_text := _resolve_submitted_text(raw_text, prefer_autocomplete_selection)
	if submitted_text.is_empty():
		return false

	var is_command_input := submitted_text.begins_with("/")

	if not keep_input:
		if line_edit != null:
			scroll_to_bottom()
		if _display:
			_display.reset_autocomplete()
		if line_edit != null:
			line_edit.clear()
			if !Engine.is_editor_hint():
				line_edit.grab_focus()

		if _display:
			_display.set_search_filter("")
			_display.rebuild_display()

		if _display and _display.is_command_entry_mode():
			_close_command_entry_view()
	else:
		if line_edit != null:
			line_edit.grab_focus()

	if is_command_input:
		_execute_command(submitted_text)
		return true

	return not keep_input


## Execute a command string (must start with /)
func _execute_command(command_input: String) -> Dictionary:
	var command_text := command_input.substr(1)  # Remove the leading /
	add_input_history(command_input)
	if _display:
		_display.add_to_command_history(command_input)
	self.log(["[i]> " + command_input + "[/i]"], LogLevel.COMMAND, "")
	var text_split := parse_line_input(command_text)
	if text_split.is_empty():
		return {"ok": false, "error": "Command is empty."}

	var requested_command := str(text_split[0]).strip_edges()
	var command_resolution := _resolve_console_command_path(requested_command)
	if not command_resolution.get("valid", false):
		console_unknown_command.emit(requested_command)
		print_error("Command not found: /%s" % requested_command)
		return {"ok": false, "error": "Command not found: /%s" % requested_command}

	if command_resolution.get("is_display_variable_pin_action", false):
		_execute_display_variable_pin_action(
			str(command_resolution.get("display_variable_address", "")),
			bool(command_resolution.get("display_variable_pin_state", false))
		)
		return {"ok": true}

	var text_command := str(command_resolution.get("command_name", ""))
	var arguments: Array = text_split.slice(1)
	for injected_argument in command_resolution.get("injected_arguments", []):
		arguments.insert(0, str(injected_argument))

	if text_command == "console/calc":
		var expression := ""
		for word in arguments:
			expression += word
		console_commands[text_command].function.callv([expression])
		return {"ok": true}

	if arguments.size() < console_commands[text_command].required:
		print_error("Too few arguments! Required < %d >" % console_commands[text_command].required)
		return {"ok": false, "error": "Too few arguments."}
	elif arguments.size() > console_commands[text_command].arguments.size():
		print_error("Too many arguments! < %d > Max" % console_commands[text_command].arguments.size())
		return {"ok": false, "error": "Too many arguments."}

	while arguments.size() < console_commands[text_command].arguments.size():
		arguments.append("")

	console_commands[text_command].function.callv(arguments)
	return {"ok": true}


func on_line_edit_text_changed(new_text: String) -> void:
	if _display:
		_display.on_text_changed_autocomplete(new_text)


func _open_command_entry_view() -> void:
	if not enabled or not control or not _display:
		return
	if _display.is_command_entry_mode():
		return

	_restore_full_console_after_command_entry = control.visible
	if not control.visible:
		control.visible = true
		was_paused_already = get_tree().paused
		get_tree().paused = was_paused_already || pause_enabled
		console_opened.emit()

	_display.show_command_entry_mode("/")


func _close_command_entry_view() -> void:
	if not _display or not _display.is_command_entry_mode():
		return

	_display.hide_command_entry_mode()
	if _restore_full_console_after_command_entry:
		line_edit.grab_focus()
	else:
		control.visible = false
		control.anchor_bottom = 1.0
		scroll_to_bottom()
		if _display:
			_display.clear_autocomplete_highlight_memory()
		if pause_enabled and !was_paused_already:
			get_tree().paused = false
		console_closed.emit()

	_restore_full_console_after_command_entry = false


# =============================================================================
# BUILT-IN COMMANDS
# =============================================================================

func quit() -> void:
	get_tree().quit()


func restart_application() -> void:
	# When running from the editor, request an in-editor restart instead of spawning externally.
	if _debugger_connected and EngineDebugger.is_active():
		_send_debugger_message("restart", [])
		get_tree().quit()
		return

	var launch_args := OS.get_cmdline_args()

	# Prefer restart-on-exit when available; this preserves platform-specific launch behavior.
	if OS.has_method("set_restart_on_exit"):
		OS.call("set_restart_on_exit", true, launch_args)
		get_tree().quit()
		return

	# Fallback: launch a new instance and quit the current one.
	if OS.has_method("create_instance"):
		var restart_result: int = int(OS.call("create_instance", launch_args))
		if restart_result == OK:
			get_tree().quit()
			return
		print_error("Failed to restart application (error %d)." % restart_result)
		return

	print_error("Restart is not supported on this platform/runtime.")


func clear() -> void:
	_clear_logs()


func delete_history() -> void:
	console_history.clear()
	if _display:
		_display.clear_command_history()
	DirAccess.remove_absolute("user://console_history.txt")


func _sanitize_bridge_screenshot_name(value: String) -> String:
	var sanitized := value.strip_edges().to_lower()
	for character in ["/", "\\", ":", " ", "\t", "\n", "\r", "\"", "'", "[", "]", "(", ")", "{", "}", ","]:
		sanitized = sanitized.replace(character, "_")
	while sanitized.find("__") != -1:
		sanitized = sanitized.replace("__", "_")
	sanitized = sanitized.trim_prefix("_").trim_suffix("_")
	return sanitized if not sanitized.is_empty() else "screenshot"


func _looks_like_screenshot_path(value: String) -> bool:
	var normalized := value.strip_edges()
	if normalized.is_empty():
		return false
	return (
		normalized.begins_with("res://")
		or normalized.begins_with("user://")
		or normalized.is_absolute_path()
		or "/" in normalized
		or "\\" in normalized
		or normalized.to_lower().ends_with(".png")
	)


func _resolve_bridge_screenshot_output_path(path_text: String, custom_name: String = "") -> String:
	var normalized_path := path_text.strip_edges()
	if normalized_path.is_empty():
		var normalized_name := _sanitize_bridge_screenshot_name(custom_name)
		if custom_name.strip_edges().is_empty():
			var now := Time.get_datetime_dict_from_system()
			normalized_path = "%s/logot_%04d%02d%02d_%02d%02d%02d.png" % [
				DEFAULT_BRIDGE_SCREENSHOT_DIR,
				int(now.get("year", 1970)),
				int(now.get("month", 1)),
				int(now.get("day", 1)),
				int(now.get("hour", 0)),
				int(now.get("minute", 0)),
				int(now.get("second", 0)),
			]
		else:
			normalized_path = "%s/%s.png" % [DEFAULT_BRIDGE_SCREENSHOT_DIR, normalized_name]

	if not normalized_path.to_lower().ends_with(".png"):
		normalized_path += ".png"

	if normalized_path.begins_with("res://") or normalized_path.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized_path)

	if normalized_path.is_absolute_path():
		return normalized_path

	return ProjectSettings.globalize_path("%s/%s" % [DEFAULT_BRIDGE_SCREENSHOT_DIR, normalized_path])


func capture_screenshot(path_text: String = "", custom_name: String = "", log_result := true) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		var headless_result := {
			"ok": false,
			"path": "",
			"name": custom_name.strip_edges(),
			"error": "Screenshot capture is not available in headless mode.",
		}
		if log_result:
			print_error(str(headless_result.error))
		return headless_result

	var viewport := get_viewport()
	if viewport == null:
		var no_viewport_result := {
			"ok": false,
			"path": "",
			"name": custom_name.strip_edges(),
			"error": "No viewport is available for screenshot capture.",
		}
		if log_result:
			print_error(str(no_viewport_result.error))
		return no_viewport_result

	var viewport_texture := viewport.get_texture()
	if viewport_texture == null:
		var no_texture_result := {
			"ok": false,
			"path": "",
			"name": custom_name.strip_edges(),
			"error": "No viewport texture is available for screenshot capture.",
		}
		if log_result:
			print_error(str(no_texture_result.error))
		return no_texture_result

	var screenshot_image := viewport_texture.get_image()
	if screenshot_image == null or screenshot_image.is_empty():
		var empty_image_result := {
			"ok": false,
			"path": "",
			"name": custom_name.strip_edges(),
			"error": "Screenshot capture returned an empty image.",
		}
		if log_result:
			print_error(str(empty_image_result.error))
		return empty_image_result

	var output_path := _resolve_bridge_screenshot_output_path(path_text, custom_name)
	var output_dir := output_path.get_base_dir()
	var mkdir_err := DirAccess.make_dir_recursive_absolute(output_dir)
	if mkdir_err != OK:
		var mkdir_result := {
			"ok": false,
			"path": output_path,
			"name": custom_name.strip_edges(),
			"error": "Failed to create screenshot directory '%s' (error %d)." % [output_dir, mkdir_err],
		}
		if log_result:
			print_error(str(mkdir_result.error))
		return mkdir_result

	var save_err := screenshot_image.save_png(output_path)
	if save_err != OK:
		var save_result := {
			"ok": false,
			"path": output_path,
			"name": custom_name.strip_edges(),
			"error": "Failed to save screenshot '%s' (error %d)." % [output_path, save_err],
		}
		if log_result:
			print_error(str(save_result.error))
		return save_result

	var result := {
		"ok": true,
		"path": output_path,
		"name": custom_name.strip_edges(),
		"error": "",
	}
	if log_result:
		var label := " '%s'" % result.name if not str(result.name).is_empty() else ""
		print_line("Screenshot%s saved to %s" % [label, output_path])
	return result


func _command_bridge_screenshot(path: String = "", name: String = "") -> void:
	var resolved_path := path
	var resolved_name := name
	if resolved_name.is_empty() and not resolved_path.is_empty() and not _looks_like_screenshot_path(resolved_path):
		resolved_name = resolved_path
		resolved_path = ""
	capture_screenshot(resolved_path, resolved_name, true)


func _escape_bbcode_text(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _get_saved_pin_overlay_name_options() -> Array:
	var active_display := _get_active_display()
	if not active_display or not active_display.has_method("get_saved_pinned_overlay_names"):
		return []
	return active_display.get_saved_pinned_overlay_names()


func _validate_pin_overlay_name(raw_name: String) -> Dictionary:
	var overlay_name := raw_name.strip_edges()
	if overlay_name.is_empty():
		return {"ok": false, "error": "Overlay name cannot be empty."}

	for invalid_character in ["/", "\\", " ", "\t", "\n", "\r"]:
		if overlay_name.find(invalid_character) != -1:
			return {"ok": false, "error": "Overlay names cannot contain spaces or slashes."}

	return {"ok": true, "name": overlay_name}


func _execute_display_variable_pin_action(address: String, pinned: bool) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty():
		print_error("Display variable address is required for pin actions.")
		return
	if not display_variables.has(normalized_address):
		print_error("Display variable not found: %s" % normalized_address)
		return

	set_display_variable_pinned(normalized_address, pinned)
	var action_text := "Pinned" if pinned else "Unpinned"
	print_line("%s [color=light_green]%s[/color]." % [action_text, _escape_bbcode_text(normalized_address)])


func _command_view_pins() -> void:
	var active_display := _get_active_display()
	if not active_display:
		print_error("No active display is available for pin commands.")
		return

	var pinned_addresses := active_display.get_pinned_display_variables()
	if pinned_addresses.is_empty():
		print_line("No display variables are currently pinned.")
		return

	pinned_addresses.sort()
	var lines: PackedStringArray = []
	lines.append("[color=cyan]Pinned display variables:[/color]")
	for address in pinned_addresses:
		var address_str := str(address)
		if address_str.is_empty():
			continue
		var escaped_address := _escape_bbcode_text(address_str)
		lines.append("  [color=light_green]%s[/color] [color=gray](on: /%s/pin | off: /%s/unpin)[/color]" % [escaped_address, escaped_address, escaped_address])
	self.log(["\n".join(lines)], LogLevel.MESSAGE, "")


func _command_clear_pins() -> void:
	var active_display := _get_active_display()
	if not active_display:
		print_error("No active display is available for pin commands.")
		return

	var pinned_count := active_display.get_pinned_display_variables().size()
	if pinned_count == 0:
		print_line("No pinned display variables to clear.")
		return

	active_display.clear_pinned_display_variables()
	print_line("Cleared %d pinned display variable(s)." % pinned_count)


func _command_save_pins_overlay(name: String) -> void:
	var active_display := _get_active_display()
	if not active_display:
		print_error("No active display is available for pin overlays.")
		return

	var validation := _validate_pin_overlay_name(name)
	if not validation.get("ok", false):
		print_error(str(validation.get("error", "Invalid overlay name.")))
		return

	var overlay_name := str(validation.get("name", ""))
	if not active_display.save_pinned_overlay(overlay_name):
		print_error("Failed to save pin overlay '%s'." % overlay_name)
		return

	var pinned_count := active_display.get_pinned_display_variables().size()
	print_line("Saved %d pinned variable(s) to overlay [color=light_green]%s[/color]." % [pinned_count, _escape_bbcode_text(overlay_name)])


func _command_load_pins_overlay(name: String) -> void:
	var active_display := _get_active_display()
	if not active_display:
		print_error("No active display is available for pin overlays.")
		return

	var validation := _validate_pin_overlay_name(name)
	if not validation.get("ok", false):
		print_error(str(validation.get("error", "Invalid overlay name.")))
		return

	var overlay_name := str(validation.get("name", ""))
	if not active_display.load_pinned_overlay(overlay_name):
		print_error("Pin overlay not found: %s" % overlay_name)
		return

	var pinned_count := active_display.get_pinned_display_variables().size()
	print_line("Loaded overlay [color=light_green]%s[/color] with %d pinned variable(s)." % [_escape_bbcode_text(overlay_name), pinned_count])


func _get_sorted_command_names() -> Array[String]:
	var commands: Array[String] = []
	for command_name in console_commands:
		commands.append(str(command_name))
	commands.sort()
	return commands


func _get_command_arguments_markup(command_name: String) -> String:
	var command_data = console_commands.get(command_name)
	if not (command_data is LogotCommand):
		return ""

	var command := command_data as LogotCommand
	var arguments_markup := ""
	for index in range(command.arguments.size()):
		var argument_name := command.arguments[index]
		if index < command.required:
			arguments_markup += "  [color=cornflower_blue]<%s>[/color]" % argument_name
		else:
			arguments_markup += "  <%s>" % argument_name
	return arguments_markup


func _build_help_commands_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for command_name in _get_sorted_command_names():
		var command_data = console_commands.get(command_name)
		if not (command_data is LogotCommand):
			continue
		var description := str((command_data as LogotCommand).description)
		lines.append("			[color=light_green]/%s[/color][color=gray]%s[/color]: %s" % [
			command_name,
			_get_command_arguments_markup(command_name),
			description,
		])
	return lines


func help() -> void:
	var lines: PackedStringArray = []
	lines.append("[color=cyan]Help:[/color]")
	lines.append("	[color=cyan]Search:[/color]")
	lines.append("		Type text to filter logs in real-time")
	lines.append("		Press Enter to confirm and clear the search")
	lines.append("	[color=cyan]Commands (prefix with /):[/color]")
	lines.append_array(_build_help_commands_lines())
	lines.append("	[color=cyan]Controls:[/color]")
	lines.append("		[color=light_blue]Up[/color] from an empty input box to browse commands")
	lines.append("		[color=light_blue]Down[/color] from an empty input box or bare [color=light_blue]/[/color] to browse recent commands")
	lines.append("		[color=light_blue]PageUp[/color] and [color=light_blue]PageDown[/color] to scroll registry")
	lines.append("		[[color=light_blue]Ctrl[/color] + [color=light_blue]~[/color]] to change console size between half screen and full screen")
	lines.append("		[color=light_blue]~[/color] hides/restores the console without resetting state")
	lines.append("		[color=light_blue]Esc[/color] resets to root [color=light_blue]/[/color], then closes on a second press")
	lines.append("		[color=light_blue]Up[/color] and [color=light_blue]Down[/color] move within the active autocomplete column")
	lines.append("		[color=light_blue]Right[/color] or [color=light_blue]Tab[/color] commits the highlighted branch to the next column")
	lines.append("		[color=light_blue]Left[/color] moves back to the previous autocomplete column")
	self.log(["\n".join(lines)])


func calculate(command : String) -> void:
	var expression := Expression.new()
	var error = expression.parse(command)
	if error:
		print_error("%s" % expression.get_error_text())
		return
	var result = expression.execute()
	if not expression.has_execute_failed():
		print_line(str(result))
	else:
		print_error("%s" % expression.get_error_text())


func commands() -> void:
	self.log([str(_get_sorted_command_names())])


func commands_list() -> void:
	var cmds := _get_sorted_command_names()

	var output := ""
	for command in cmds:
		var arguments_string := _get_command_arguments_markup(command)
		var description : String = str((console_commands[command] as LogotCommand).description)
		output += "[color=light_green]%s[/color][color=gray]%s[/color]:   %s\n" % [command, arguments_string, description]
	self.log([output])


func add_input_history(text : String) -> void:
	if !console_history.size() or text != console_history.back():
		console_history.append(text)


func set_enable_on_release_build(enable : bool):
	enable_on_release_build = enable
	if !enable_on_release_build:
		if !OS.is_debug_build():
			disable()


# =============================================================================
# TEST COMMAND
# =============================================================================

## Test command that exercises all logging functionality
func _cmd_test_logging() -> void:
	print_line("[color=cyan]========== LOGGING TEST STARTED ==========[/color]")
	print_line("")

	# Test 1: All log levels
	print_line("[color=light_green]Test 1: All Log Levels[/color]")
	self.log(["This is an ERROR message"], LogLevel.ERROR, "")
	self.log(["This is a WARN message"], LogLevel.WARN, "")
	self.log(["This is a COMMAND message"], LogLevel.COMMAND, "")
	self.log(["This is a MESSAGE (default level)"], LogLevel.MESSAGE, "")
	self.log(["This is an INFO message"], LogLevel.INFO, "")
	self.log(["This is a VERBOSE message"], LogLevel.VERBOSE, "")
	self.log(["This is a DEBUG message"], LogLevel.DEBUG, "")
	print_line("")

	# Test 2: Multiple objects in a single log
	print_line("[color=light_green]Test 2: Multiple Objects[/color]")
	self.log(["Player health:", 100, "Mana:", 50, {"status": "alive"}], LogLevel.MESSAGE, "")
	self.log([Vector2(10, 20), Vector3(1, 2, 3), Color.RED], LogLevel.INFO, "")
	print_line("")

	# Test 3: Channels
	print_line("[color=light_green]Test 3: Channels[/color]")
	self.log(["Message in General channel"], LogLevel.MESSAGE, "")
	self.log(["Message in Player channel"], LogLevel.MESSAGE, "Player")
	self.log(["Message in Combat channel"], LogLevel.MESSAGE, "Combat")
	self.log(["Message in Network channel"], LogLevel.MESSAGE, "Network")
	self.log(["Error in Audio channel"], LogLevel.ERROR, "Audio")
	print_line("")

	# Test 4: Multi-line messages
	print_line("[color=light_green]Test 4: Multi-line Messages[/color]")
	self.log(["Line 1\nLine 2\nLine 3\nLine 4"], LogLevel.MESSAGE, "")
	self.log(["A multi-line\nerror message\nwith details"], LogLevel.ERROR, "Test")
	print_line("")

	# Test 5: try_log (lazy evaluation)
	print_line("[color=light_green]Test 5: try_log (Lazy Evaluation)[/color]")
	try_log(func(): return ["Lazy evaluated message at " + str(Time.get_ticks_msec()) + "ms"], LogLevel.INFO, "")
	try_log(func():
		var expensive_data := []
		for i in range(5):
			expensive_data.append("item_%d" % i)
		return ["Computed data:", expensive_data]
	, LogLevel.DEBUG, "Test")
	print_line("")

	# Test 6: can_log check
	print_line("[color=light_green]Test 6: can_log Check[/color]")
	print_line("can_log(ERROR): %s" % str(can_log(LogLevel.ERROR)))
	print_line("can_log(DEBUG): %s" % str(can_log(LogLevel.DEBUG)))
	print_line("can_log(MESSAGE, 'Player'): %s" % str(can_log(LogLevel.MESSAGE, "Player")))
	print_line("")

	# Test 7: Backward compatibility methods
	print_line("[color=light_green]Test 7: Backward Compatibility[/color]")
	print_line("Using print_line() method")
	print_error("Using print_error() method")
	print_line("")

	# Test 8: Special characters and BBCode
	print_line("[color=light_green]Test 8: Special Characters[/color]")
	self.log(["Message with [brackets] and <angle brackets>"], LogLevel.MESSAGE, "")
	self.log(["Tab\there and\tthere"], LogLevel.INFO, "")
	self.log(["Unicode: émoji → αβγ 日本語"], LogLevel.MESSAGE, "")
	print_line("")

	# Test 9: Empty and edge cases
	print_line("[color=light_green]Test 9: Edge Cases[/color]")
	self.log([""], LogLevel.MESSAGE, "")  # Empty string
	self.log([null], LogLevel.INFO, "")  # Null value
	self.log([0, 0.0, false, []], LogLevel.DEBUG, "")  # Falsy values
	print_line("")

	# Test 10: Duplicate messages (for collapse testing)
	print_line("[color=light_green]Test 10: Duplicate Messages (for collapse testing)[/color]")
	self.log(["Duplicate message"], LogLevel.MESSAGE, "Test")
	self.log(["Duplicate message"], LogLevel.MESSAGE, "Test")
	self.log(["Duplicate message"], LogLevel.MESSAGE, "Test")
	self.log(["Different message"], LogLevel.MESSAGE, "Test")
	self.log(["Duplicate message"], LogLevel.MESSAGE, "Test")
	print_line("")

	# Test 11: Long message
	print_line("[color=light_green]Test 11: Long Message[/color]")
	var long_text := "This is a very long message that tests how the console handles text that might exceed normal display widths. "
	long_text += "It contains multiple sentences and should test word wrapping functionality. "
	long_text += "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
	self.log([long_text], LogLevel.MESSAGE, "Console")
	print_line("")

	# Show stats after all tests
	print_line("[color=cyan]========== LOGGING TEST COMPLETE ==========[/color]")
	print_line("Run [color=light_green]/log_stats[/color] to see statistics")


func _cmd_test_off_tracking() -> void:
	print_line("[color=cyan]========== OFF TRACKING TEST ==========[/color]")
	print_line("")

	# Store current visibility
	var original_debug_vis := get_level_visibility(LogLevel.DEBUG)
	print_line("Original DEBUG visibility: %d" % original_debug_vis)

	# Get initial off count
	var initial_off_count := get_rejected_level_count(LogLevel.DEBUG)
	print_line("Initial DEBUG off count: %d" % initial_off_count)

	# Set DEBUG to OFF
	set_level_visibility(LogLevel.DEBUG, VisibilityMode.OFF)
	print_line("Set DEBUG to OFF (mode=%d)" % VisibilityMode.OFF)

	# Verify visibility is OFF
	print_line("can_log(DEBUG): %s" % str(can_log(LogLevel.DEBUG)))

	# Try to log some DEBUG messages
	print_line("Calling try_log 3 times with DEBUG level...")
	try_log(func(): return ["Test OFF message 1"], LogLevel.DEBUG, "")
	try_log(func(): return ["Test OFF message 2"], LogLevel.DEBUG, "")
	try_log(func(): return ["Test OFF message 3"], LogLevel.DEBUG, "")

	# Check the off count
	var new_off_count := get_rejected_level_count(LogLevel.DEBUG)
	print_line("New DEBUG off count: %d (expected %d)" % [new_off_count, initial_off_count + 3])

	# Check sidebar state (works in both game and editor contexts)
	if _display and _display._sidebar:
		var sidebar_stats = _display._sidebar._level_stats.get(LogLevel.DEBUG, {})
		print_line("Game sidebar DEBUG stats: %s" % str(sidebar_stats))
	else:
		print_line("Game display not available (expected in editor)")

	# Restore original visibility
	set_level_visibility(LogLevel.DEBUG, original_debug_vis)
	print_line("Restored DEBUG visibility to: %d" % original_debug_vis)

	print_line("")
	print_line("[color=cyan]========== OFF TRACKING TEST COMPLETE ==========[/color]")


func _cmd_test_nested_channels() -> void:
	print_line("[color=cyan]========== NESTED CHANNELS TEST ==========[/color]")
	print_line("")

	# Test 1: Create hierarchical channels
	print_line("[color=light_green]Test 1: Creating Hierarchical Channels[/color]")
	self.log(["Message in navigation channel"], LogLevel.INFO, "navigation")
	self.log(["Message in navigation/pathfinding"], LogLevel.INFO, "navigation/pathfinding")
	self.log(["Message in navigation/nav mesh"], LogLevel.INFO, "navigation/nav mesh")
	self.log(["Message in navigation/nav mesh/generation"], LogLevel.DEBUG, "navigation/nav mesh/generation")
	print_line("")

	# Test 2: Verify parent channels were created
	print_line("[color=light_green]Test 2: Verifying Parent Channels Exist[/color]")
	var channels := get_known_channels()
	print_line("Known channels: %s" % str(channels))

	var expected_channels := ["navigation", "navigation/pathfinding", "navigation/nav mesh", "navigation/nav mesh/generation"]
	for expected in expected_channels:
		if expected in channels:
			print_line("  [OK] Channel '%s' exists" % expected)
		else:
			print_line("  [FAIL] Channel '%s' NOT found" % expected)
	print_line("")

	# Test 3: Test visibility on nested channels
	print_line("[color=light_green]Test 3: Testing Visibility on Nested Channels[/color]")
	print_line("Setting 'navigation/nav mesh' to HIDDEN...")
	set_channel_visibility("navigation/nav mesh", VisibilityMode.HIDDEN)
	print_line("  navigation visibility: %d" % get_channel_visibility("navigation"))
	print_line("  navigation/nav mesh visibility: %d (should be 1=HIDDEN)" % get_channel_visibility("navigation/nav mesh"))
	print_line("  navigation/nav mesh/generation visibility: %d" % get_channel_visibility("navigation/nav mesh/generation"))
	print_line("")

	# Test 4: Log more messages to different nested channels
	print_line("[color=light_green]Test 4: Logging to Multiple Nested Channels[/color]")
	self.log(["Physics root message"], LogLevel.MESSAGE, "physics")
	self.log(["Physics collision message"], LogLevel.MESSAGE, "physics/collision")
	self.log(["Physics collision/broad phase"], LogLevel.DEBUG, "physics/collision/broad phase")
	self.log(["Physics collision/narrow phase"], LogLevel.DEBUG, "physics/collision/narrow phase")
	self.log(["Physics rigidbody message"], LogLevel.INFO, "physics/rigidbody")
	print_line("")

	# Test 5: Deep nesting test
	print_line("[color=light_green]Test 5: Deep Nesting Test[/color]")
	self.log(["Level 1"], LogLevel.INFO, "a")
	self.log(["Level 2"], LogLevel.INFO, "a/b")
	self.log(["Level 3"], LogLevel.INFO, "a/b/c")
	self.log(["Level 4"], LogLevel.INFO, "a/b/c/d")
	self.log(["Level 5"], LogLevel.INFO, "a/b/c/d/e")
	print_line("Created 5-level deep channel hierarchy")
	print_line("")

	# Test 6: Test OFF visibility cascading (simulating what sidebar does)
	print_line("[color=light_green]Test 6: Testing OFF Visibility[/color]")
	set_channel_visibility("physics", VisibilityMode.OFF)
	print_line("Set 'physics' to OFF")
	print_line("  can_log to physics: %s (should be false)" % str(can_log(LogLevel.MESSAGE, "physics")))
	print_line("  can_log to physics/collision: %s (should be true - children independent)" % str(can_log(LogLevel.MESSAGE, "physics/collision")))
	print_line("")

	# Reset visibility
	set_channel_visibility("navigation/nav mesh", VisibilityMode.SHOWN)
	set_channel_visibility("physics", VisibilityMode.SHOWN)

	# Show sidebar info if available
	if _display and _display._sidebar:
		print_line("[color=light_green]Sidebar Channel Hierarchy Info:[/color]")
		var sidebar = _display._sidebar
		if sidebar._channel_children.size() > 0:
			print_line("  Channel children mapping:")
			for parent in sidebar._channel_children:
				print_line("    '%s' -> %s" % [parent, str(sidebar._channel_children[parent])])
		if sidebar._channel_parent.size() > 0:
			print_line("  Channel parent mapping:")
			for child in sidebar._channel_parent:
				print_line("    '%s' <- '%s'" % [child, sidebar._channel_parent[child]])
	else:
		print_line("Sidebar not available (expected in editor mode)")

	print_line("")
	print_line("[color=cyan]========== NESTED CHANNELS TEST COMPLETE ==========[/color]")
	print_line("Check the sidebar to see the hierarchical channel structure.")
	print_line("Try collapsing/expanding parent channels to see aggregated stats and mixed icons.")
