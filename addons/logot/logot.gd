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
		console.log_msg([full_message], level, "Godot", backtrace_str)
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
		console.log_msg([message], level, "Godot", backtrace_str)
		_in_logger_callback = false


# =============================================================================
# CONFIGURATION CONSTANTS
# =============================================================================
const MAX_LOG_ENTRIES := 1000
const SIDEBAR_BREAKPOINT := 800
const DEFAULT_CHANNEL_DISPLAY_NAME := "General"
const SETTINGS_FILE := "user://console_filters.cfg"

# Preload scenes and scripts
const LogLevel = preload("res://addons/logot/log_level.gd")
const LogotDisplay = preload("res://addons/logot/logot_display.gd")
const LOGOT_UI_SCENE := preload("res://addons/logot/logot.tscn")

# =============================================================================
# TYPE ALIASES - Use classes from LogotDisplay
# =============================================================================
const VisibilityMode = LogotDisplay.VisibilityMode
const LogEntry = LogotDisplay.LogEntry
const LogotCommand = LogotDisplay.LogotCommand


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
var theme: Theme = preload("res://addons/logot/logot_theme.tres")

var console_commands := {}
var console_history := []
var console_history_index := 0
var was_paused_already := false

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
func log_msg(objects: Array, level: int = LogLevel.MESSAGE, channel: String = "", stack_trace: String = "") -> void:
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
		_display._ensure_channel_exists(channel)
		_display._update_stats_for_entry(entry)
		if _display._should_display(entry):
			_display._display_entry(entry)
			entry.visible = true
		_display._update_sidebar_stats()

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
		log_msg(objects, level, channel)
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
		return _display._format_objects(objects)
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
			_display._ensure_channel_exists(channel)
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
		_display._ensure_level_exists(level)
		_display._ensure_channel_exists(channel)
		_display._update_sidebar_stats()

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
	log_msg([text], LogLevel.ERROR, "")
	if print_godot:
		push_error(text)


func print_line(text: String, print_godot := false) -> void:
	log_msg([text], LogLevel.MESSAGE, "")
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
		_display._clear_logs()
	# Notify editor via debugger
	_send_debugger_message("logs_cleared", [])
	logs_cleared.emit()


# =============================================================================
# COMMAND SYSTEM
# =============================================================================

func add_command(command_name : String, function : Callable, arguments = [], required: int = 0, description : String = "") -> void:
	if arguments is int:
		var param_array : PackedStringArray
		for i in range(arguments):
			param_array.append("arg_" + str(i + 1))
		console_commands[command_name] = LogotCommand.new(function, param_array, required, description)
	elif arguments is Array:
		var str_args : PackedStringArray
		for argument in arguments:
			str_args.append(str(argument))
		console_commands[command_name] = LogotCommand.new(function, str_args, required, description)


func remove_command(command_name : String) -> void:
	console_commands.erase(command_name)


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
					_display._rebuild_display()
			return true
		"logot:set_channel_visibility":
			if data.size() >= 2:
				set_channel_visibility(str(data[0]), int(data[1]))
				if _display:
					_display._rebuild_display()
			return true
		"logot:clear":
			_clear_logs()
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

	# Serialize entry data for transmission
	var entry_data := {
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
	_send_debugger_message("log_entry", [entry_data])


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
	_display.visible = false
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
	_display.set_rejected_level_count_provider(func(level): return get_rejected_level_count(level))
	_display.set_rejected_channel_count_provider(func(channel): return get_rejected_channel_count(channel))
	_display.set_level_visibility_provider(get_level_visibility, set_level_visibility)
	_display.set_channel_visibility_provider(get_channel_visibility, set_channel_visibility)

	# Connect signals for visibility changes
	_display.custom_setting_changed.connect(_on_display_setting_changed)
	_display.cleared.connect(_on_display_cleared)
	_display.channel_deleted.connect(_on_channel_deleted)

	# Initialize the display
	_display._init_base()
	_display._setup_ui_nodes()
	_display._connect_ui_signals()
	_display._setup_sidebar()
	_display._init_display()

	# Get references to UI nodes from display
	control = _display
	rich_label = _display.rich_label
	line_edit = _display.line_edit

	# Set up autocomplete popup
	var autocomplete_popup = _logot_ui.get_node_or_null("%AutocompletePopup")
	if autocomplete_popup:
		_display.set_autocomplete_popup(autocomplete_popup)

	# Connect line edit signals
	if line_edit:
		line_edit.text_submitted.connect(on_text_entered)
		line_edit.text_changed.connect(on_line_edit_text_changed)
		line_edit.gui_input.connect(_on_line_edit_gui_input)


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


func _ready() -> void:
	# Commands available in both editor and game
	add_command("clear", clear, 0, 0, "Clears the text on the console.")
	add_command("help", help, 0, 0, "Displays instructions on how to use the console.")
	add_command("commands", commands_list, 0, 0, "Lists all commands and their descriptions.")
	add_command("calc", calculate, ["mathematical expression to evaluate"], 0, "Evaluates the math passed in for quick arithmetic.")

	add_command("console/test_logging", _cmd_test_logging, [], 0, "Test all logging functionality")
	add_command("console/test_off_tracking", _cmd_test_off_tracking, [], 0, "Test OFF visibility tracking")
	add_command("console/test_nested_channels", _cmd_test_nested_channels, [], 0, "Test nested/hierarchical channel functionality")

	# Game-only commands
	if not Engine.is_editor_hint():
		add_command("quit", quit, 0, 0, "Quits the game.")
		add_command("exit", quit, 0, 0, "Quits the game.")
		add_command("delete_history", delete_history, 0, 0, "Deletes the history of previously entered commands.")


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _input(event : InputEvent) -> void:
	# Don't handle input in editor
	if Engine.is_editor_hint():
		return

	if event is InputEventKey:
		if event.get_physical_keycode_with_modifiers() == KEY_QUOTELEFT:
			if event.pressed:
				toggle_console()
			get_tree().get_root().set_input_as_handled()
		elif event.physical_keycode == KEY_QUOTELEFT and event.is_command_or_control_pressed():
			if event.pressed:
				if control.visible:
					toggle_size()
				else:
					toggle_console()
					toggle_size()
			get_tree().get_root().set_input_as_handled()
		elif (event.get_physical_keycode_with_modifiers() == KEY_ESCAPE or event.keycode == KEY_BACK) and control.visible:
			if event.pressed:
				toggle_console()
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


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not _display:
		return
	if not event is InputEventKey or not event.pressed:
		return

	var key_event := event as InputEventKey

	# Handle autocomplete navigation
	if _display.is_autocomplete_visible():
		if key_event.keycode == KEY_DOWN:
			_display.autocomplete_select_next()
			line_edit.accept_event()
		elif key_event.keycode == KEY_UP:
			_display.autocomplete_select_prev()
			line_edit.accept_event()
		elif key_event.keycode == KEY_TAB:
			_display.confirm_autocomplete()
			line_edit.accept_event()
		elif key_event.keycode == KEY_ESCAPE:
			_display.hide_autocomplete()
			line_edit.accept_event()
	else:
		# UP/DOWN for history when autocomplete not visible
		if key_event.keycode == KEY_UP:
			_display.autocomplete_select_prev()
			line_edit.accept_event()
		elif key_event.keycode == KEY_DOWN:
			if console_history_index < console_history.size():
				console_history_index += 1
				if console_history_index < console_history.size():
					line_edit.text = console_history[console_history_index]
					line_edit.caret_column = line_edit.text.length()
				else:
					line_edit.text = ""
				_display.reset_autocomplete()
			line_edit.accept_event()


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
	toggle_console()


func enable():
	enabled = true


func toggle_console() -> void:
	if enabled:
		control.visible = !control.visible
	else:
		control.visible = false

	if control.visible:
		was_paused_already = get_tree().paused
		get_tree().paused = was_paused_already || pause_enabled
		line_edit.grab_focus()
		console_opened.emit()
	else:
		control.anchor_bottom = 1.0
		scroll_to_bottom()
		if _display:
			_display.reset_autocomplete()
		if pause_enabled and !was_paused_already:
			get_tree().paused = false
		console_closed.emit()


func is_visible():
	return control.visible


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
	var token : String
	for c in text:
		if c == '\\':
			escaped = true
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
			continue
		elif c == ' ' or c == '\t':
			if !in_quotes:
				out_array.push_back(token)
				token = ""
				continue
		token += c
	out_array.push_back(token)
	return out_array


func on_text_entered(new_text : String) -> void:
	# Handle UI updates if line_edit is available (in-game console)
	if line_edit != null:
		scroll_to_bottom()
		if _display:
			_display.reset_autocomplete()
		line_edit.clear()
		if !Engine.is_editor_hint():
			line_edit.grab_focus()

	# Clear search filter when entering text
	if _display:
		_display._search_filter = ""
		_display._rebuild_display()

	if not new_text.strip_edges().is_empty():
		# Commands must start with /
		if new_text.begins_with("/"):
			_execute_command(new_text)


## Execute a command string (must start with /)
func _execute_command(command_input: String) -> void:
	var command_text := command_input.substr(1)  # Remove the leading /
	add_input_history(command_input)
	if _display:
		_display.add_to_command_history(command_input)
	log_msg(["[i]> " + command_input + "[/i]"], LogLevel.COMMAND, "")
	var text_split := parse_line_input(command_text)
	var text_command := text_split[0]

	if console_commands.has(text_command):
		var arguments := text_split.slice(1)

		if text_command.match("calc"):
			var expression := ""
			for word in arguments:
				expression += word
			console_commands[text_command].function.callv([expression])
			return

		if arguments.size() < console_commands[text_command].required:
			print_error("Too few arguments! Required < %d >" % console_commands[text_command].required)
			return
		elif arguments.size() > console_commands[text_command].arguments.size():
			print_error("Too many arguments! < %d > Max" % console_commands[text_command].arguments.size())
			return

		while arguments.size() < console_commands[text_command].arguments.size():
			arguments.append("")

		console_commands[text_command].function.callv(arguments)
	else:
		console_unknown_command.emit(text_command)
		print_error("Command not found: /%s" % text_command)


func on_line_edit_text_changed(new_text: String) -> void:
	if _display:
		_display.on_text_changed_autocomplete(new_text)


# =============================================================================
# BUILT-IN COMMANDS
# =============================================================================

func quit() -> void:
	get_tree().quit()


func clear() -> void:
	_clear_logs()


func delete_history() -> void:
	console_history.clear()
	console_history_index = 0
	DirAccess.remove_absolute("user://console_history.txt")


func help() -> void:
	log_msg(["[color=cyan]Help:[/color]
	[color=cyan]Search:[/color]
		Type text to filter logs in real-time
		Press Enter to confirm and clear the search
	[color=cyan]Commands (prefix with /):[/color]
		[color=light_green]/calc[/color]: Calculates a given expression
		[color=light_green]/clear[/color]: Clears the registry view
		[color=light_green]/commands[/color]: Shows a reduced list of all the currently registered commands
		[color=light_green]/commands_list[/color]: Shows a detailed list of all the currently registered commands
		[color=light_green]/delete_history[/color]: Deletes the commands history
		[color=light_green]/quit[/color]: Quits the game
		[color=light_green]/log_show[/color]: Set level/channel to SHOWN
		[color=light_green]/log_hide[/color]: Set level/channel to HIDDEN
		[color=light_green]/log_off[/color]: Set level/channel to OFF
		[color=light_green]/log_stats[/color]: Show all filter statistics
	[color=cyan]Controls:[/color]
		[color=light_blue]Up[/color] and [color=light_blue]Down[/color] arrow keys to navigate commands history
		[color=light_blue]PageUp[/color] and [color=light_blue]PageDown[/color] to scroll registry
		[[color=light_blue]Ctrl[/color] + [color=light_blue]~[/color]] to change console size between half screen and full screen
		[color=light_blue]~[/color] or [color=light_blue]Esc[/color] key to close the console
		[color=light_blue]Tab[/color] key to autocomplete, [color=light_blue]Tab[/color] again to cycle between matching suggestions"])


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
	var cmds := []
	for command in console_commands:
		cmds.append(str(command))
	cmds.sort()
	log_msg([str(cmds)])


func commands_list() -> void:
	var cmds := []
	for command in console_commands:
		cmds.append(str(command))
	cmds.sort()

	var output := ""
	for command in cmds:
		var arguments_string := ""
		var description : String = console_commands[command].description
		for i in range(console_commands[command].arguments.size()):
			if i < console_commands[command].required:
				arguments_string += "  [color=cornflower_blue]<" + console_commands[command].arguments[i] + ">[/color]"
			else:
				arguments_string += "  <" + console_commands[command].arguments[i] + ">"
		output += "[color=light_green]%s[/color][color=gray]%s[/color]:   %s\n" % [command, arguments_string, description]
	log_msg([output])


func add_input_history(text : String) -> void:
	if !console_history.size() or text != console_history.back():
		console_history.append(text)
	console_history_index = console_history.size()


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
	log_msg(["This is an ERROR message"], LogLevel.ERROR, "")
	log_msg(["This is a WARN message"], LogLevel.WARN, "")
	log_msg(["This is a COMMAND message"], LogLevel.COMMAND, "")
	log_msg(["This is a MESSAGE (default level)"], LogLevel.MESSAGE, "")
	log_msg(["This is an INFO message"], LogLevel.INFO, "")
	log_msg(["This is a VERBOSE message"], LogLevel.VERBOSE, "")
	log_msg(["This is a DEBUG message"], LogLevel.DEBUG, "")
	print_line("")

	# Test 2: Multiple objects in a single log
	print_line("[color=light_green]Test 2: Multiple Objects[/color]")
	log_msg(["Player health:", 100, "Mana:", 50, {"status": "alive"}], LogLevel.MESSAGE, "")
	log_msg([Vector2(10, 20), Vector3(1, 2, 3), Color.RED], LogLevel.INFO, "")
	print_line("")

	# Test 3: Channels
	print_line("[color=light_green]Test 3: Channels[/color]")
	log_msg(["Message in General channel"], LogLevel.MESSAGE, "")
	log_msg(["Message in Player channel"], LogLevel.MESSAGE, "Player")
	log_msg(["Message in Combat channel"], LogLevel.MESSAGE, "Combat")
	log_msg(["Message in Network channel"], LogLevel.MESSAGE, "Network")
	log_msg(["Error in Audio channel"], LogLevel.ERROR, "Audio")
	print_line("")

	# Test 4: Multi-line messages
	print_line("[color=light_green]Test 4: Multi-line Messages[/color]")
	log_msg(["Line 1\nLine 2\nLine 3\nLine 4"], LogLevel.MESSAGE, "")
	log_msg(["A multi-line\nerror message\nwith details"], LogLevel.ERROR, "Test")
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
	log_msg(["Message with [brackets] and <angle brackets>"], LogLevel.MESSAGE, "")
	log_msg(["Tab\there and\tthere"], LogLevel.INFO, "")
	log_msg(["Unicode: émoji → αβγ 日本語"], LogLevel.MESSAGE, "")
	print_line("")

	# Test 9: Empty and edge cases
	print_line("[color=light_green]Test 9: Edge Cases[/color]")
	log_msg([""], LogLevel.MESSAGE, "")  # Empty string
	log_msg([null], LogLevel.INFO, "")  # Null value
	log_msg([0, 0.0, false, []], LogLevel.DEBUG, "")  # Falsy values
	print_line("")

	# Test 10: Duplicate messages (for collapse testing)
	print_line("[color=light_green]Test 10: Duplicate Messages (for collapse testing)[/color]")
	log_msg(["Duplicate message"], LogLevel.MESSAGE, "Test")
	log_msg(["Duplicate message"], LogLevel.MESSAGE, "Test")
	log_msg(["Duplicate message"], LogLevel.MESSAGE, "Test")
	log_msg(["Different message"], LogLevel.MESSAGE, "Test")
	log_msg(["Duplicate message"], LogLevel.MESSAGE, "Test")
	print_line("")

	# Test 11: Long message
	print_line("[color=light_green]Test 11: Long Message[/color]")
	var long_text := "This is a very long message that tests how the console handles text that might exceed normal display widths. "
	long_text += "It contains multiple sentences and should test word wrapping functionality. "
	long_text += "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
	log_msg([long_text], LogLevel.MESSAGE, "Console")
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
	log_msg(["Message in navigation channel"], LogLevel.INFO, "navigation")
	log_msg(["Message in navigation/pathfinding"], LogLevel.INFO, "navigation/pathfinding")
	log_msg(["Message in navigation/nav mesh"], LogLevel.INFO, "navigation/nav mesh")
	log_msg(["Message in navigation/nav mesh/generation"], LogLevel.DEBUG, "navigation/nav mesh/generation")
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
	log_msg(["Physics root message"], LogLevel.MESSAGE, "physics")
	log_msg(["Physics collision message"], LogLevel.MESSAGE, "physics/collision")
	log_msg(["Physics collision/broad phase"], LogLevel.DEBUG, "physics/collision/broad phase")
	log_msg(["Physics collision/narrow phase"], LogLevel.DEBUG, "physics/collision/narrow phase")
	log_msg(["Physics rigidbody message"], LogLevel.INFO, "physics/rigidbody")
	print_line("")

	# Test 5: Deep nesting test
	print_line("[color=light_green]Test 5: Deep Nesting Test[/color]")
	log_msg(["Level 1"], LogLevel.INFO, "a")
	log_msg(["Level 2"], LogLevel.INFO, "a/b")
	log_msg(["Level 3"], LogLevel.INFO, "a/b/c")
	log_msg(["Level 4"], LogLevel.INFO, "a/b/c/d")
	log_msg(["Level 5"], LogLevel.INFO, "a/b/c/d/e")
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
