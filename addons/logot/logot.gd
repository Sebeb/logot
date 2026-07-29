@tool
extends Node

# =============================================================================
# ENGINE LOGGER - Intercepts Godot's internal logging
# =============================================================================

class EngineLogger extends Logger:
	var _in_logger_callback := false
	var console = null

	## Engine logger callbacks fire on whichever thread raised the message, and
	## the resource loader parses scripts off the main thread. Console.log()
	## touches the SceneTree (display nodes, in-game popups), so anything that
	## arrives off-thread has to be handed back to the main thread first.
	func _dispatch(objects: Array, level: int, channel: String, backtrace_str: String) -> void:
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			console.log(objects, level, channel, backtrace_str)
		else:
			console.call_deferred("log", objects, level, channel, backtrace_str)

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
		_dispatch([full_message], level, "Godot", backtrace_str)
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
		_dispatch([message], level, "Godot", backtrace_str)
		_in_logger_callback = false


# =============================================================================
# CONFIGURATION CONSTANTS
# =============================================================================
const MAX_LOG_ENTRIES := 1000
const SETTINGS_FILE := "user://console_filters.cfg"
const TEST_COMMANDS_SETTING := "addons/logot/enable_test_commands"
const CONSOLE_INTERFACING_TEST_COMMANDS_SCRIPT_PATH := "res://tests/console_interfacing/console_interfacing_commands.gd"
const DEFAULT_BRIDGE_SCREENSHOT_DIR := "user://artifacts/screenshots"
const _CURRENT_GIT_BRANCH_COMMAND_PATH := "dev/current_git_branch"
const _UNKNOWN_GIT_BRANCH := "unknown"
const _CURRENT_GIT_BRANCH_AHEAD_COLOR := Color(0.42, 0.9, 0.42, 1.0)
const _CURRENT_GIT_BRANCH_BEHIND_COLOR := Color(0.88, 0.44, 0.44, 1.0)
const _CURRENT_GIT_BRANCH_UNCOMMITTED_COLOR := Color(0.65, 0.65, 0.68, 1.0)
const _PERFORMANCE_FPS_PATH := "dev/performance/fps"
const _PERFORMANCE_OVERVIEW_WIDGET_PATH := "dev/performance/overview"
const _PERFORMANCE_TIME_RANGE_PATH := "dev/performance/time_range"
const _PERFORMANCE_CPU_SOURCES_WIDGET_PATH := "dev/performance/allocation/cpu"
const _PERFORMANCE_GPU_SOURCES_WIDGET_PATH := "dev/performance/allocation/gpu"
const _PERFORMANCE_CPU_SOURCE_MODE_PATH := "dev/performance/allocation/cpu/mode"
const _PERFORMANCE_SOURCE_UPDATE_SPEED_PATH := "dev/performance/allocation/update_speed"
const _PERFORMANCE_SOURCE_SNAPSHOT_PATH := "dev/performance/allocation/snapshot"
const DEFAULT_INGAME_POPUP_LIFETIME := 5.0
const INGAME_POPUP_FADE_DURATION := 0.35
const INGAME_POPUP_MAX_VISIBLE := 6
const INGAME_POPUP_MAX_SPAWNS_PER_SECOND := 8
const INGAME_POPUP_WIDTH := 440.0
const INGAME_POPUP_HEIGHT := 280.0
const INGAME_POPUP_MARGIN := 16.0
const INGAME_POPUP_COMMAND_PALETTE_GAP := 10.0
const INGAME_POPUP_SWIPE_DISMISS_THRESHOLD := 90.0
const INGAME_POPUP_SWIPE_DISMISS_TIMEOUT_MSEC := 450
const INGAME_POPUP_SWIPE_WHEEL_STEP := 36.0
const INGAME_POPUP_SWIPE_EXIT_DISTANCE := 72.0
const INGAME_POPUP_SWIPE_EXIT_DURATION := 0.18
const INGAME_POPUP_ACTION_SIZE := 28.0
const INGAME_POPUP_ACTION_GAP := 4.0
const INGAME_POPUP_SETTINGS_SECTION := "ingame_popups"
const INGAME_POPUP_COMMAND_PATH := "console/settings/ingame_popups"
const INGAME_POPUP_LEVELS_COMMAND_PATH := "console/settings/ingame_popups/levels"
const INGAME_POPUP_LEVELS_DISABLE_ALL_COMMAND_PATH := "console/settings/ingame_popups/levels/off_all"
const INGAME_POPUP_LEVELS_COPY_CONSOLE_COMMAND_PATH := "console/settings/ingame_popups/levels/copy_console"
const INGAME_POPUP_LEVELS_MIRROR_MAIN_CONSOLE_COMMAND_PATH := "console/settings/ingame_popups/levels/mirror_main_console"
const INGAME_POPUP_FADE_TIME_COMMAND_PATH := "console/settings/ingame_popups/fade_time"
const INGAME_POPUP_ENABLED_MARK := "✓"
const INGAME_POPUP_DISABLED_MARK := "✗"
const TIMER_COMMAND_GROUP_NAME := "Timers"
const TIMER_COMMAND_GROUP_PRIORITY := 225
const PERFORMANCE_HISTORY_NUM_FRAMES := 500
const PERFORMANCE_FPS_NUM_FRAMES := 25
const PERFORMANCE_GRAPH_MIN_FPS := 10
const PERFORMANCE_GRAPH_MAX_FPS := 160
const PERFORMANCE_SETTINGS_SECTION := "performance"
const PERFORMANCE_SETTINGS_KEY_MODE := "pin_mode"
const PERFORMANCE_SETTINGS_KEY_GRAPH_TIME_RANGE := "graph_time_range_sec"
const PERFORMANCE_SETTINGS_KEY_CPU_SOURCE_MODE := "cpu_source_mode"
const PERFORMANCE_SETTINGS_KEY_SOURCE_UPDATE_RATE_HZ := "source_update_rate_hz"
const PERFORMANCE_MODE_FPS := "fps"
const PERFORMANCE_MODE_OVERVIEW := "overview"
const PERFORMANCE_MODE_DETAILED := "detailed"
const PERFORMANCE_MODE_HIDDEN := "hidden"
const PERFORMANCE_GRAPH_TIME_RANGE_ALL := 0.0
const PERFORMANCE_CPU_SOURCE_MODE_RENDER := "render"
const PERFORMANCE_CPU_SOURCE_MODE_WHOLE := "whole"
const PERFORMANCE_CPU_SOURCE_MODE_BOTH := "both"
const PERFORMANCE_SOURCE_UPDATE_RATE_DEFAULT_HZ := 4.0
const PERFORMANCE_SOURCE_BRIDGE_API_VERSION := 1
const PERFORMANCE_SOURCE_SNAPSHOT_DIR := "user://artifacts/performance_snapshots"
const PIN_CORNER_TOP_LEFT := "top_left"
const PIN_CORNER_TOP_RIGHT := "top_right"
const PIN_CORNER_BOTTOM_LEFT := "bottom_left"
const PIN_CORNER_BOTTOM_RIGHT := "bottom_right"
const PIN_CORNERS := [
	PIN_CORNER_TOP_LEFT,
	PIN_CORNER_TOP_RIGHT,
	PIN_CORNER_BOTTOM_LEFT,
	PIN_CORNER_BOTTOM_RIGHT,
]
const TOUCH_EDGE_BUTTON_SIZE := Vector2(88.0, 104.0)
const TOUCH_EDGE_BUTTON_GAP := 8.0
const TOUCH_TOGGLE_BUTTON_MARGIN := 10.0
const TOUCH_TOGGLE_DEFAULT_CENTER_Y_RATIO := 0.72
const TOUCH_TOGGLE_DRAG_THRESHOLD := 8.0
const TOUCH_TOGGLE_EDGE_LEFT := "left"
const TOUCH_TOGGLE_EDGE_RIGHT := "right"
const TOUCH_TOGGLE_SETTINGS_SECTION := "touch_toggle"
const TOUCH_TOGGLE_SETTINGS_KEY_EDGE := "edge"
const TOUCH_TOGGLE_SETTINGS_KEY_CENTER_Y_RATIO := "center_y_ratio"
const TOUCH_TOGGLE_ACTION_COMMAND := "command"
const TOUCH_TOGGLE_ACTION_LOG := "log"
const VIRTUAL_KEYBOARD_SAFE_AREA_EPSILON := 0.5
const GAME_OVERLAY_CANVAS_LAYER := 8192

# Preload scenes and scripts
const LogLevel = preload("res://addons/logot/log_level.gd")
const LogotDisplay = preload("res://addons/logot/logot_display.gd")
const LogotCommandInput = preload("res://addons/logot/logot_command_input.gd")
const LOGOT_UI_SCENE := preload("res://addons/logot/logot.tscn")
const PERFORMANCE_OVERVIEW_WIDGET_SCENE := preload("res://addons/logot/widgets/performance_overview_widget.tscn")
const PERFORMANCE_SOURCE_GRAPH_WIDGET_SCENE := preload("res://addons/logot/widgets/performance_source_graph_widget.tscn")
const PerformanceSourceMonitorScript := preload("res://addons/logot/performance_source_monitor.gd")
const LogotTestManagerScript = preload("res://addons/logot/testing/logot_test_manager.gd")
const LogotTestPanelScript = preload("res://addons/logot/testing/logot_test_panel.gd")

# =============================================================================
# TYPE ALIASES - Use classes from LogotDisplay
# =============================================================================
const VisibilityMode = LogotDisplay.VisibilityMode
const LogEntry = LogotDisplay.LogEntry
const LogotCommand = LogotDisplay.LogotCommand
const LogotDisplayVariable = LogotDisplay.LogotDisplayVariable
const LogotWidget = LogotDisplay.LogotWidget
const INGAME_POPUP_LEVELS := [
	LogLevel.ERROR,
	LogLevel.WARN,
	LogLevel.COMMAND,
	LogLevel.MESSAGE,
	LogLevel.INFO,
	LogLevel.VERBOSE,
	LogLevel.DEBUG,
]


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
signal timer_started(key: String, name: String)
signal timer_paused(key: String, name: String, elapsed_text: String)
signal timer_resumed(key: String, name: String)
signal timer_stopped(key: String, name: String, elapsed_text: String)
signal performance_fps_changed()

var control: Control
var rich_label: RichTextLabel
var line_edit: LineEdit

var console_commands := {}
var _orderable_groups: Dictionary = {}
var _disabled_command_paths: Dictionary = {}
var display_variables := {}
var widgets := {}
var console_history := []
var was_paused_already := false
var _pending_pinned_display_variables: Dictionary = {}
var _ui_update_batch_depth := 0
var _ui_update_batch_displays: Array[LogotDisplay] = []
var _pending_render_texture_widget_view_mode: Dictionary = {}
var _external_displays: Array = []
var _display_variable_signal_connections: Dictionary = {}
var _timers: Dictionary = {}
var _console_interfacing_test_commands: RefCounted = null
var _test_manager = null
var _test_panel = null
var _test_button: Button = null
var _test_panel_input_row: HBoxContainer = null
var _touch_toggle_dock: Control = null
var _touch_command_palette_button: Button = null
var _touch_full_log_button: Button = null
var _touch_toggle_edge := TOUCH_TOGGLE_EDGE_RIGHT
var _touch_toggle_center_y := -1.0
var _touch_toggle_drag_active := false
var _touch_toggle_drag_moved := false
var _touch_toggle_drag_action := ""
var _touch_toggle_drag_touch_index := -1
var _touch_toggle_drag_start_position := Vector2.ZERO
var _touch_toggle_drag_pointer_offset := Vector2.ZERO
var _touch_toggle_drag_start_edge := TOUCH_TOGGLE_EDGE_RIGHT
var _touch_toggle_drag_dock_x := -1.0
var _current_git_branch := ""
var _current_git_branch_remote_status := ""
var _current_git_branch_ahead := 0
var _current_git_branch_behind := 0
var _current_git_branch_uncommitted_files := 0
var _performance_last_tick_usec := 0
var _performance_frame_history_total: Array[float] = []
var _performance_frame_history_cpu: Array[float] = []
var _performance_frame_history_gpu: Array[float] = []
var _performance_fps_history: Array[float] = []
var _performance_frames_per_second := float(PERFORMANCE_GRAPH_MIN_FPS)
var _performance_frametime_msec := 1000.0 / float(PERFORMANCE_GRAPH_MIN_FPS)
var _performance_frametime_cpu_msec := 1000.0 / float(PERFORMANCE_GRAPH_MIN_FPS)
var _performance_frametime_gpu_msec := 1000.0 / float(PERFORMANCE_GRAPH_MIN_FPS)
var _performance_frame_time_gradient := Gradient.new()
var _performance_monitor_initialized := false
var _performance_pin_mode := PERFORMANCE_MODE_FPS
var _performance_graph_time_range_sec := 10.0
var _performance_fps_signal_accum_sec := 0.0
var _performance_fps_display_text := str(PERFORMANCE_GRAPH_MIN_FPS)
var _performance_fps_display_color := Color.WHITE
var _performance_frame_time_display_text := "0.00 mspf"
var _performance_frame_time_display_color := Color.WHITE
var _performance_source_monitor: RefCounted
var _performance_cpu_source_mode := PERFORMANCE_CPU_SOURCE_MODE_RENDER
var _performance_source_update_rate_hz := PERFORMANCE_SOURCE_UPDATE_RATE_DEFAULT_HZ
var _performance_source_render_lease_frame := -1
var _performance_source_script_lease_frame := -1
var _performance_source_snapshot_pending := false
var _performance_source_snapshot_name := ""
var _performance_source_snapshot_deadline_msec := 0

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
var _restore_full_console_after_command_entry := false
var _hidden_command_palette_path := ""  # Palette path stashed by `, restored by ` or ~
var _virtual_keyboard_safe_area_height := 0.0
var _virtual_keyboard_baseline_viewport_height := 0.0

# Settings toggles (synced with display)
var _collapse_duplicates := false
var _wrap_text := false
var _truncate_multiline := true
var _touch_mode_enabled := false
var _ingame_popup_levels: Dictionary = {}
var _ingame_popup_mirror_main_console := false
var _ingame_popup_fade_time: float = DEFAULT_INGAME_POPUP_LIFETIME
var _ingame_popup_fade_enabled := true
var _ingame_popup_guard := false
var _ingame_popup_spawn_timestamps: Array[float] = []
var _ingame_popup_nodes: Dictionary = {}

var _ingame_popup_overlay: Control
var _ingame_popup_container: VBoxContainer
var _ingame_overlay_top_edge_override := 0.0
var _ingame_overlay_left_edge_override := 0.0
var _ingame_overlay_right_edge_override := 0.0
var _ingame_overlay_bottom_edge_override := 0.0
var _pinned_corner_enabled := {
	PIN_CORNER_TOP_LEFT: true,
	PIN_CORNER_TOP_RIGHT: true,
	PIN_CORNER_BOTTOM_LEFT: true,
	PIN_CORNER_BOTTOM_RIGHT: true,
}


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

	if _should_show_ingame_popup_for_entry(entry):
		if not _ingame_popup_guard:
			_ingame_popup_guard = true
			_show_ingame_popup(entry)
			_ingame_popup_guard = false

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
	var formatted_first := _format_display_text(first_line, level, channel, timestamp, entry_id, true, extra_line_count, stack_trace)
	var formatted_full := _format_display_text(text, level, channel, timestamp, entry_id, false, 0, stack_trace)

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
	return _format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace)


func _format_display_text(text: String, level: int, channel: String, timestamp: String, entry_id: int = -1, is_collapsed: bool = true, extra_lines: int = 0, stack_trace: String = "", collapse_count: int = 0, formatted_stack_trace: String = "", instance_name: String = "") -> String:
	var formatter := Callable(LogotDisplay, "format_display_text")
	if formatter.is_valid():
		return str(formatter.call(text, level, channel, timestamp, entry_id, is_collapsed, extra_lines, stack_trace, collapse_count, formatted_stack_trace, instance_name))
	return _format_display_text_fallback(text, level, channel, timestamp, entry_id, is_collapsed, extra_lines, stack_trace, collapse_count, formatted_stack_trace, instance_name)


func _format_display_text_fallback(text: String, level: int, channel: String, timestamp: String, entry_id: int = -1, is_collapsed: bool = true, extra_lines: int = 0, stack_trace: String = "", collapse_count: int = 0, formatted_stack_trace: String = "", instance_name: String = "") -> String:
	var color := _get_log_level_color_hex(level)
	var extra_indicator := ""
	if is_collapsed and extra_lines > 0:
		extra_indicator = " [i][color=dim_gray]+%d[/color][/i]" % extra_lines

	var has_expandable := extra_lines > 0 or stack_trace != ""
	var toggle_action := "expand" if is_collapsed else "collapse"
	var primary_message_content := "[color=%s]%s[/color]%s" % [color, text, extra_indicator]
	var stack_trace_content := ""
	if not is_collapsed and formatted_stack_trace != "":
		stack_trace_content = "\n" + formatted_stack_trace

	var timestamp_content := "[color=dim_gray]%s[/color]" % timestamp
	var instance_content := ""
	if instance_name != "":
		instance_content = "[color=dim_gray][%s][/color] " % instance_name

	var channel_content := ""
	if channel != "":
		channel_content = "[color=%s][%s][/color]" % [color, channel]

	var count_content := ""
	if collapse_count > 0:
		var space := " " if channel_content != "" else ""
		count_content = "%s[color=%s][%d][/color]" % [space, color, collapse_count]

	if has_expandable and entry_id >= 0:
		var url_action := "%s:%d" % [toggle_action, entry_id]
		timestamp_content = "[url=%s]%s[/url]" % [url_action, timestamp_content]
		if instance_content != "":
			instance_content = "[url=%s]%s[/url]" % [url_action, instance_content]
		if channel_content != "":
			channel_content = "[url=%s]%s[/url]" % [url_action, channel_content]
		if count_content != "":
			count_content = "[url=%s]%s[/url]" % [url_action, count_content]
		primary_message_content = "[url=%s]%s[/url]" % [url_action, primary_message_content]

	var metadata_content := "%s%s%s" % [instance_content, channel_content, count_content]
	var message_content := "%s%s" % [primary_message_content, stack_trace_content]
	return "[table=3][cell expand=0 shrink=true]%s [/cell][cell expand=0 shrink=true]%s[/cell][cell expand=1 shrink=false]%s[/cell][/table]" % [timestamp_content, metadata_content, message_content]


func _get_log_level_color_hex(level: int) -> String:
	var color: Color = LogotDisplay.LEVEL_COLORS.get(level, Color.WHITE)
	return "#" + color.to_html(false)


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
	_sync_timers_for_channel(channel)


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

func add_command(command_name : String, function : Callable, arguments = [], required: int = 0, description : String = "", group_name: String = "", group_priority: int = 0, option_group_name: String = "", option_group_priority: int = 0, display_label: String = "", icon: Texture2D = null, group_tint: Color = Color.TRANSPARENT, option_group_tint: Color = Color.TRANSPARENT, default_child_path: String = "", default_child_provider: Callable = Callable(), keyboard_shortcut: Key = KEY_NONE) -> void:
	if arguments is int:
		var param_array : PackedStringArray
		for i in range(arguments):
			param_array.append("arg_" + str(i + 1))
		console_commands[command_name] = LogotCommand.new(function, param_array, required, description, [], Callable(), Callable(), group_name, group_priority, option_group_name, option_group_priority, display_label, icon, group_tint, option_group_tint, default_child_path, default_child_provider, keyboard_shortcut)
	elif arguments is Array:
		var str_args : PackedStringArray
		for argument in arguments:
			str_args.append(str(argument))
		console_commands[command_name] = LogotCommand.new(function, str_args, required, description, [], Callable(), Callable(), group_name, group_priority, option_group_name, option_group_priority, display_label, icon, group_tint, option_group_tint, default_child_path, default_child_provider, keyboard_shortcut)
	_notify_command_catalog_changed()


func add_command_with_options(command_name: String, function: Callable, arguments: Array = [], required: int = 0, description: String = "", argument_options_provider: Callable = Callable(), value_getter: Callable = Callable(), group_name: String = "", group_priority: int = 0, option_group_name: String = "", option_group_priority: int = 0, group_tint: Color = Color.TRANSPARENT, option_group_tint: Color = Color.TRANSPARENT, default_child_path: String = "", default_child_provider: Callable = Callable(), keyboard_shortcut: Key = KEY_NONE) -> void:
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
		group_priority,
		option_group_name,
		option_group_priority,
		"",
		null,
		group_tint,
		option_group_tint,
		default_child_path,
		default_child_provider,
		keyboard_shortcut
	)
	_notify_command_catalog_changed()


## Registers a dynamic group of `{id, label}` objects which can be reordered.
## `get_order` receives one descriptor. `set_order` receives a descriptor and its new zero-based order.
func add_orderable_group(group_path: String, fetch_objects: Callable, get_order: Callable, set_order: Callable) -> void:
	var normalized_path := group_path.strip_edges().trim_prefix("/").trim_suffix("/")
	if normalized_path.is_empty() or not fetch_objects.is_valid() or not get_order.is_valid() or not set_order.is_valid():
		push_warning("Cannot add orderable group: path and fetch/get/set callables are required.")
		return
	_orderable_groups[normalized_path] = {
		"fetch": fetch_objects,
		"get_order": get_order,
		"set_order": set_order,
		"commands": [],
	}
	_rebuild_orderable_group_commands(normalized_path)


func refresh_orderable_group(group_path: String) -> void:
	var normalized_path := group_path.strip_edges().trim_prefix("/").trim_suffix("/")
	if _orderable_groups.has(normalized_path):
		_rebuild_orderable_group_commands(normalized_path)


func _rebuild_orderable_group_commands(group_path: String) -> void:
	var config: Dictionary = _orderable_groups[group_path]
	for old_path in config.get("commands", []):
		console_commands.erase(str(old_path))
	var descriptors: Array = []
	var fetched = (config.get("fetch") as Callable).call()
	if fetched is Array:
		for value in fetched:
			if value is Dictionary and (value as Dictionary).has("id") and not str((value as Dictionary).get("label", "")).strip_edges().is_empty():
				descriptors.append((value as Dictionary).duplicate())
	var get_order: Callable = config.get("get_order")
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(get_order.call(a)) < int(get_order.call(b)))
	var generated: Array[String] = []
	for descriptor_index in range(descriptors.size()):
		var descriptor: Dictionary = descriptors[descriptor_index]
		var object_path := "%s/%s" % [group_path, str(descriptor.get("id")).uri_encode()]
		var object_command := LogotCommand.new(Callable(), PackedStringArray(), 0, "", [], Callable(), Callable(), "", 0, "", 0, str(descriptor.get("label")))
		object_command.orderable_group = group_path
		object_command.orderable_object_id = descriptor.get("id")
		object_command.orderable_order = descriptor_index
		console_commands[object_path] = object_command
		generated.append(object_path)
		var actions := [
			["move up", -1, false, KEY_UP],
			["move down", 1, false, KEY_DOWN],
			["move to top", -1, true, (KEY_UP | KEY_MASK_SHIFT) as Key],
			["move to bottom", 1, true, (KEY_DOWN | KEY_MASK_SHIFT) as Key],
		]
		for action in actions:
			var action_path := "%s/%s" % [object_path, str(action[0])]
			var callback := _move_orderable_object.bind(group_path, descriptor.get("id"), int(action[1]), bool(action[2]))
			var action_command := LogotCommand.new(callback, PackedStringArray(), 0, "", [], Callable(), Callable(), "move", 0, "", 0, str(action[0]), null, Color.TRANSPARENT, Color.TRANSPARENT, "", Callable(), action[3] as Key)
			action_command.orderable_group = group_path
			console_commands[action_path] = action_command
			generated.append(action_path)
	config["commands"] = generated
	_orderable_groups[group_path] = config
	_notify_command_catalog_changed()


func _move_orderable_object(group_path: String, object_id: Variant, direction: int, absolute: bool) -> void:
	if not _orderable_groups.has(group_path):
		return
	var config: Dictionary = _orderable_groups[group_path]
	var fetched = (config.get("fetch") as Callable).call()
	if not (fetched is Array):
		return
	var objects: Array = (fetched as Array).duplicate()
	var get_order: Callable = config.get("get_order")
	objects.sort_custom(func(a, b) -> bool: return int(get_order.call(a)) < int(get_order.call(b)))
	var from_index := -1
	for index in range(objects.size()):
		if objects[index] is Dictionary and (objects[index] as Dictionary).get("id") == object_id:
			from_index = index
			break
	if from_index < 0:
		return
	var to_index := (0 if direction < 0 else objects.size() - 1) if absolute else clampi(from_index + direction, 0, objects.size() - 1)
	if to_index == from_index:
		return
	var moved = objects.pop_at(from_index)
	objects.insert(to_index, moved)
	var set_order: Callable = config.get("set_order")
	for index in range(objects.size()):
		set_order.call(objects[index], index)
	_rebuild_orderable_group_commands(group_path)


func _drag_orderable_object(group_path: String, object_id: Variant, target_id: Variant) -> void:
	if not _orderable_groups.has(group_path):
		return
	var config: Dictionary = _orderable_groups[group_path]
	var fetched = (config.get("fetch") as Callable).call()
	if not (fetched is Array):
		return
	var objects: Array = (fetched as Array).duplicate()
	var get_order: Callable = config.get("get_order")
	objects.sort_custom(func(a, b) -> bool: return int(get_order.call(a)) < int(get_order.call(b)))
	var from_index := -1
	var to_index := -1
	for index in range(objects.size()):
		if objects[index] is Dictionary:
			var id = (objects[index] as Dictionary).get("id")
			if id == object_id:
				from_index = index
			if id == target_id:
				to_index = index
	if from_index < 0 or to_index < 0 or from_index == to_index:
		return
	var moved = objects.pop_at(from_index)
	objects.insert(to_index, moved)
	var set_order: Callable = config.get("set_order")
	for index in range(objects.size()):
		set_order.call(objects[index], index)
	_rebuild_orderable_group_commands(group_path)


func add_setget_command(command_name: String, setter: Callable, getter: Callable, description: String = "", options_provider: Callable = Callable(), inline_color_provider: Callable = Callable(), group_name: String = "", group_priority: int = 0, option_group_name: String = "", option_group_priority: int = 0, change_signal_source: Object = null, change_signal_name: StringName = &"") -> void:
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
		group_priority,
		option_group_name,
		option_group_priority
	)
	add_display_variable(command_name, getter, inline_color_provider, Callable(), true, group_name, group_priority, change_signal_source, change_signal_name)


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
			if address_str.is_empty() or (not display_variables.has(address_str) and not widgets.has(address_str)) or pinned_addresses.has(address_str):
				continue
			pinned_addresses.append(address_str)

	for pending_address in _pending_pinned_display_variables:
		var pending_address_str := str(pending_address)
		if pending_address_str.is_empty() or (not display_variables.has(pending_address_str) and not widgets.has(pending_address_str)) or pinned_addresses.has(pending_address_str):
			continue
		var pending = _pending_pinned_display_variables[pending_address]
		if pending is Dictionary and not bool((pending as Dictionary).get("pinned", false)):
			continue
		if not (pending is Dictionary) and not bool(pending):
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
	if console_commands.has(normalized_path) or not normalized_path.begins_with("pins/"):
		return normalized_path

	var alias_remainder := normalized_path.substr("pins/".length())
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


func _normalize_pin_corner(corner: String) -> String:
	var normalized_corner := corner.strip_edges().to_lower()
	if PIN_CORNERS.has(normalized_corner):
		return normalized_corner
	return PIN_CORNER_TOP_LEFT


func _is_pinnable_console_item(command_candidate: String) -> bool:
	return display_variables.has(command_candidate) or widgets.has(command_candidate)


func _is_render_texture_widget_console_item(command_candidate: String) -> bool:
	if command_candidate.is_empty() or not widgets.has(command_candidate):
		return false
	var widget_data = widgets.get(command_candidate, null)
	return widget_data is Dictionary and str((widget_data as Dictionary).get("widget_type", "")).strip_edges().to_lower() == "render_texture"


func _normalize_render_texture_widget_view_mode(mode: String) -> String:
	var normalized_mode := mode.strip_edges().to_lower()
	if normalized_mode == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
		return LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
	if normalized_mode in [LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY, "overlay", "fullscreen/overlay"]:
		return LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY
	return LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE


func _resolve_display_variable_pin_subcommand(command_candidate: String, option_segment: String) -> Dictionary:
	if command_candidate.is_empty() or not _is_pinnable_console_item(command_candidate):
		return {"valid": false}

	var option_lowered := option_segment.strip_edges().to_lower()
	var pin_state: Variant = null
	var pin_corner := PIN_CORNER_TOP_LEFT
	var render_texture_view_mode := ""
	if option_lowered == "pin":
		pin_state = true
	elif option_lowered.begins_with("pin/"):
		var raw_corner := option_lowered.trim_prefix("pin/")
		if not PIN_CORNERS.has(raw_corner):
			return {"valid": false}
		pin_state = true
		pin_corner = raw_corner
	elif option_lowered == "unpin":
		pin_state = false
	elif _is_render_texture_widget_console_item(command_candidate):
		if option_lowered in [
			LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN,
			LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY,
			"overlay",
			"fullscreen/overlay"
		]:
			render_texture_view_mode = _normalize_render_texture_widget_view_mode(option_lowered)
		elif option_lowered in ["fullscreen_off", "fullscreen/off", "fullscreen_none", "fullscreen/none"]:
			render_texture_view_mode = LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
		else:
			return {"valid": false}
	else:
		return {"valid": false}

	var resolution := {
		"valid": true,
		"command_name": "",
		"injected_arguments": [],
		"is_option_subcommand": true,
		"is_display_variable_pin_action": true,
		"display_variable_address": command_candidate,
		"display_variable_pin_state": pin_state == true,
		"display_variable_pin_corner": pin_corner,
	}
	if not render_texture_view_mode.is_empty():
		resolution["display_variable_render_texture_view_mode"] = render_texture_view_mode
	return resolution


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

	if widgets.has(normalized_path):
		return {
			"valid": true,
			"command_name": "",
			"injected_arguments": [],
			"is_option_subcommand": false,
			"is_widget_command": true,
			"widget_address": normalized_path,
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


## Resolves the optional default child declared by a command.  The returned focus paths
## include every intermediate tier so the palette can preview multi-tier defaults.
func resolve_default_child_chain(command_name: String) -> Dictionary:
	var origin := command_name.strip_edges().trim_prefix("/").trim_suffix("/")
	if origin.is_empty() or not console_commands.has(origin):
		return {"valid": false, "has_default": false, "error": "Command is not registered."}

	var focus_paths: Array[String] = []
	var visited_commands: Dictionary = {}
	var current_command := origin
	for depth in range(32):
		var default_spec := _get_command_default_child_spec(current_command)
		if not bool(default_spec.get("has_default", false)):
			if current_command == origin:
				return {"valid": true, "has_default": false, "focus_paths": focus_paths}
			return _build_default_child_terminal_result(origin, current_command, [], focus_paths)
		if not bool(default_spec.get("valid", true)):
			return _build_default_child_error(origin, str(default_spec.get("error", "Invalid default child.")), focus_paths)
		if visited_commands.has(current_command):
			return _build_default_child_error(origin, "cycle detected at '%s'." % current_command, focus_paths)
		visited_commands[current_command] = true

		var supplied_path := str(default_spec.get("path", "")).strip_edges().trim_prefix("/").trim_suffix("/")
		if supplied_path.is_empty():
			return _build_default_child_error(origin, "default child path is empty.", focus_paths)
		var normalized_target := _normalize_default_child_target(current_command, supplied_path)
		if not bool(normalized_target.get("valid", false)):
			return _build_default_child_error(origin, str(normalized_target.get("error", "invalid relative path.")), focus_paths)
		var target_path := str(normalized_target.get("path", ""))
		var target_segments := target_path.split("/", false)
		var current_segments := current_command.split("/", false).size()
		for segment_index in range(current_segments, target_segments.size()):
			var focus_path := "/".join(target_segments.slice(0, segment_index + 1))
			if not focus_paths.has(focus_path):
				focus_paths.append(focus_path)
		if is_command_path_disabled(target_path):
			return _build_default_child_error(origin, "target '%s' is disabled." % target_path, focus_paths)

		var target_resolution := _resolve_console_command_path(target_path)
		if not bool(target_resolution.get("valid", false)):
			return _build_default_child_error(origin, "target '%s' is missing or stale." % target_path, focus_paths)
		var target_command := str(target_resolution.get("command_name", ""))
		if target_command.is_empty() or not console_commands.has(target_command):
			return _build_default_child_error(origin, "target '%s' does not resolve to a command." % target_path, focus_paths)
		if is_command_path_disabled(target_command):
			return _build_default_child_error(origin, "target command '%s' is disabled." % target_command, focus_paths)
		if bool(target_resolution.get("is_option_subcommand", false)):
			return _build_default_child_terminal_result(origin, target_command, target_resolution.get("injected_arguments", []), focus_paths)
		current_command = target_command

	return _build_default_child_error(origin, "maximum recursive depth (32) exceeded.", focus_paths)


func _normalize_default_child_target(current_command: String, supplied_path: String) -> Dictionary:
	var segments: Array[String] = []
	for existing_segment in current_command.split("/", false):
		segments.append(existing_segment)
	for raw_segment in supplied_path.split("/", false):
		var segment := raw_segment.strip_edges()
		if segment.is_empty() or segment == ".":
			continue
		if segment == "..":
			if segments.is_empty():
				return {"valid": false, "error": "path escapes the command root."}
			segments.remove_at(segments.size() - 1)
			continue
		segments.append(segment)
	if segments.is_empty():
		return {"valid": false, "error": "path resolves to an empty command."}
	return {"valid": true, "path": "/".join(segments)}


func _get_command_default_child_spec(command_name: String) -> Dictionary:
	var command_data = console_commands.get(command_name)
	var static_path := ""
	var provider := Callable()
	if command_data is LogotCommand:
		var command := command_data as LogotCommand
		static_path = command.default_child_path
		provider = command.default_child_provider
	elif command_data is Dictionary:
		var command_dict := command_data as Dictionary
		static_path = str(command_dict.get("default_child_path", command_dict.get("default_child", "")))
		var nested_default = command_dict.get("default_child", null)
		if nested_default is Dictionary:
			var nested_default_dict := nested_default as Dictionary
			static_path = str(nested_default_dict.get("path", nested_default_dict.get("value", static_path)))
			provider = nested_default_dict.get("provider", Callable()) as Callable
		else:
			provider = command_dict.get("default_child_provider", Callable()) as Callable
	if provider.is_valid():
		var provided_path: Variant = provider.call()
		if not (provided_path is String):
			return {"has_default": true, "valid": false, "error": "default-child provider for '%s' did not return a String." % command_name}
		static_path = str(provided_path)
	if static_path.strip_edges().is_empty():
		return {"has_default": false, "valid": true}
	return {"has_default": true, "valid": true, "path": static_path}


func _build_default_child_terminal_result(origin: String, command_name: String, injected_arguments: Array, focus_paths: Array[String]) -> Dictionary:
	var command_data = console_commands.get(command_name)
	var command_callable := _get_command_callable(command_data)
	if not command_callable.is_valid() and not _is_text_input_option_command(command_name):
		return _build_default_child_error(origin, "terminal '%s' is not executable." % command_name, focus_paths)
	return {
		"valid": true,
		"has_default": true,
		"origin": origin,
		"terminal_command": command_name,
		"injected_arguments": injected_arguments.duplicate(),
		"focus_paths": focus_paths.duplicate(),
	}


func _build_default_child_error(origin: String, reason: String, focus_paths: Array[String]) -> Dictionary:
	return {
		"valid": false,
		"has_default": true,
		"origin": origin,
		"error": "Invalid default child for '/%s': %s" % [origin, reason],
		"focus_paths": focus_paths.duplicate(),
	}


func _get_command_callable(command_data: Variant) -> Callable:
	if command_data is LogotCommand:
		return (command_data as LogotCommand).function
	if command_data is Dictionary:
		var command_function = (command_data as Dictionary).get("function", Callable())
		return command_function as Callable if command_function is Callable else Callable()
	return Callable()


func _get_command_required_count(command_data: Variant) -> int:
	if command_data is LogotCommand:
		return (command_data as LogotCommand).required
	if command_data is Dictionary:
		return int((command_data as Dictionary).get("required", 0))
	return 0


func _get_command_argument_names(command_data: Variant) -> Array:
	if command_data is LogotCommand:
		return Array((command_data as LogotCommand).arguments)
	if command_data is Dictionary:
		var arguments = (command_data as Dictionary).get("arguments", [])
		return Array(arguments) if arguments is Array or arguments is PackedStringArray else []
	return []


func _validate_default_child_commands() -> void:
	for command_name_variant in console_commands:
		var command_name := str(command_name_variant)
		var result := resolve_default_child_chain(command_name)
		if bool(result.get("has_default", false)) and not bool(result.get("valid", false)):
			print_error(str(result.get("error", "Invalid default child for '/%s'." % command_name)))


func can_execute_console_command(command_path: String) -> bool:
	return not is_command_path_disabled(command_path) and bool(_resolve_console_command_path(command_path).get("valid", false))


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
	_disabled_command_paths.erase(command_name)
	_notify_command_catalog_changed()


## Disables a command path and every descendant path in Logot's command palette.
func set_command_path_disabled(command_path: String, disabled: bool = true) -> void:
	var normalized_path := command_path.strip_edges().trim_prefix("/").trim_suffix("/")
	if normalized_path.is_empty():
		return
	if disabled:
		_disabled_command_paths[normalized_path] = true
	else:
		_disabled_command_paths.erase(normalized_path)
	_notify_command_catalog_changed()


func is_command_path_disabled(command_path: String) -> bool:
	var normalized_path := command_path.strip_edges().trim_prefix("/").trim_suffix("/")
	if normalized_path.is_empty():
		return false
	for disabled_path_variant in _disabled_command_paths:
		var disabled_path := str(disabled_path_variant)
		if normalized_path == disabled_path or normalized_path.begins_with(disabled_path + "/"):
			return true
	return false

func add_display_variable(address: String, getter: Callable, inline_color_provider: Callable = Callable(), items_provider: Callable = Callable(), pinnable: bool = true, group_name: String = "", group_priority: int = 0, change_signal_source: Object = null, change_signal_name: StringName = &"", display_label_provider: Callable = Callable()) -> void:
	display_variables[address] = LogotDisplayVariable.new(getter, inline_color_provider, items_provider, pinnable, group_name, group_priority, change_signal_source, change_signal_name, display_label_provider)
	_register_display_variable_signal(address, change_signal_source, change_signal_name)
	_notify_command_catalog_changed()


func remove_display_variable(address: String) -> void:
	_unregister_display_variable_signal(address)
	display_variables.erase(address)
	notify_display_variable_changed(address)
	_notify_command_catalog_changed()


func add_widget(address: String, scene_or_path: Variant, description: String = "", group_name: String = "", group_priority: int = 0, default_minimum_size: Vector2 = Vector2.ZERO, display_label: String = "") -> void:
	var normalized_address := address.strip_edges().trim_suffix("/")
	if normalized_address.is_empty():
		push_warning("Cannot add Logot widget with an empty address.")
		return
	widgets[normalized_address] = LogotWidget.new(scene_or_path, description, group_name, group_priority, default_minimum_size, display_label)
	_notify_command_catalog_changed()


func add_render_texture_widget(address: String, texture_getter: Callable, description: String = "", group_name: String = "", group_priority: int = 0, default_minimum_size: Vector2 = Vector2(220, 160)) -> void:
	var normalized_address := address.strip_edges().trim_suffix("/")
	if normalized_address.is_empty():
		push_warning("Cannot add Logot render texture widget with an empty address.")
		return
	if not texture_getter.is_valid():
		push_warning("Cannot add Logot render texture widget '%s': invalid texture getter." % normalized_address)
		return
	widgets[normalized_address] = {
		"widget_type": "render_texture",
		"texture_getter": texture_getter,
		"description": description,
		"group_name": group_name.strip_edges(),
		"group_priority": group_priority if not group_name.strip_edges().is_empty() else 0,
		"default_minimum_size": default_minimum_size,
	}
	_notify_command_catalog_changed()


func remove_widget(address: String) -> void:
	var normalized_address := address.strip_edges().trim_suffix("/")
	if normalized_address.is_empty():
		return
	widgets.erase(normalized_address)
	_notify_command_catalog_changed()


func get_widgets() -> Dictionary:
	return widgets.duplicate()


func pin(key: String, value_or_getter: Variant, change_signal_source: Object = null, change_signal_name: StringName = &"") -> void:
	var address := key.strip_edges()
	if address.is_empty():
		print_error("Pin key cannot be empty.")
		return

	var getter: Callable
	var use_change_signal := false
	if value_or_getter is Callable:
		getter = value_or_getter as Callable
		if not getter.is_valid():
			print_error("Pin getter for '%s' is not valid." % address)
			return
		use_change_signal = true
	else:
		var pinned_value: Variant
		pinned_value = value_or_getter
		getter = func() -> Variant:
			return pinned_value

	add_display_variable(
		address,
		getter,
		Callable(),
		Callable(),
		true,
		"",
		0,
		change_signal_source if use_change_signal else null,
		change_signal_name if use_change_signal else &""
	)
	pin_display_variable(address)


func unpin(key: String) -> void:
	var address := key.strip_edges()
	if address.is_empty():
		print_error("Pin key cannot be empty.")
		return

	unpin_display_variable(address)
	remove_display_variable(address)


func start_timer(key: String, name: String = "", channel: String = "") -> bool:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		print_error("Timer key cannot be empty.")
		return false

	var timer_name := name.strip_edges()
	if timer_name.is_empty():
		timer_name = normalized_key

	var timer_channel := channel.strip_edges()
	_ensure_channel_exists(timer_channel)
	_timers[normalized_key] = {
		"name": timer_name,
		"channel": timer_channel,
		"accumulated_usec": 0,
		"running": true,
		"counting": false,
		"started_usec": 0,
	}
	_ensure_timer_display_variables(normalized_key)
	_sync_timer_runtime_state(normalized_key)
	timer_started.emit(normalized_key, timer_name)
	return true


func pause_timer(key: String) -> bool:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		print_error("Timer key cannot be empty.")
		return false
	if not _timers.has(normalized_key):
		print_error("Timer not found: %s" % normalized_key)
		return false

	_sync_timer_runtime_state(normalized_key)
	var timer_state: Dictionary = _timers[normalized_key]
	if not bool(timer_state.get("running", false)):
		print_error("Timer is not running: %s" % normalized_key)
		return false

	timer_state["accumulated_usec"] = _get_timer_elapsed_usec_from_state(timer_state)
	timer_state["running"] = false
	timer_state["counting"] = false
	timer_state["started_usec"] = 0
	_timers[normalized_key] = timer_state
	_sync_timer_runtime_state(normalized_key)
	timer_paused.emit(normalized_key, str(timer_state.get("name", normalized_key)), _format_duration_usec(_get_timer_elapsed_usec_from_state(timer_state)))
	return true


func resume_timer(key: String) -> bool:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		print_error("Timer key cannot be empty.")
		return false
	if not _timers.has(normalized_key):
		print_error("Timer not found: %s" % normalized_key)
		return false

	_sync_timer_runtime_state(normalized_key)
	var timer_state: Dictionary = _timers[normalized_key]
	if bool(timer_state.get("running", false)):
		print_error("Timer is already running: %s" % normalized_key)
		return false

	timer_state["running"] = true
	timer_state["counting"] = false
	timer_state["started_usec"] = 0
	_timers[normalized_key] = timer_state
	_sync_timer_runtime_state(normalized_key)
	timer_resumed.emit(normalized_key, str(timer_state.get("name", normalized_key)))
	return true


func stop_timer(key: String) -> bool:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		print_error("Timer key cannot be empty.")
		return false
	if not _timers.has(normalized_key):
		print_error("Timer not found: %s" % normalized_key)
		return false

	_sync_timer_runtime_state(normalized_key)
	var timer_state: Dictionary = _timers[normalized_key]
	var timer_name := str(timer_state.get("name", normalized_key))
	var timer_channel := str(timer_state.get("channel", ""))
	var final_duration_text := _format_duration_usec(_get_timer_elapsed_usec_from_state(timer_state))

	_unpin_timer_display_variables(normalized_key)
	_remove_timer_display_variables(normalized_key)
	_timers.erase(normalized_key)
	self.log(
		["Timer [color=light_green]%s[/color] stopped at [color=light_green]%s[/color]." % [_escape_bbcode_text(timer_name), final_duration_text]],
		LogLevel.MESSAGE,
		timer_channel
	)
	timer_stopped.emit(normalized_key, timer_name, final_duration_text)
	return true


func has_timer(key: String) -> bool:
	var normalized_key := _normalize_timer_key(key)
	return not normalized_key.is_empty() and _timers.has(normalized_key)


func is_timer_running(key: String) -> bool:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return false
	_sync_timer_runtime_state(normalized_key)
	return bool((_timers[normalized_key] as Dictionary).get("counting", false))


func get_timer_name(key: String) -> String:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return ""
	return str((_timers[normalized_key] as Dictionary).get("name", normalized_key))


func get_timer_channel(key: String) -> String:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return ""
	return str((_timers[normalized_key] as Dictionary).get("channel", ""))


func get_timer_elapsed_seconds(key: String) -> float:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return 0.0
	_sync_timer_runtime_state(normalized_key)
	return float(_get_timer_elapsed_usec_from_state(_timers[normalized_key])) / 1000000.0


func get_timer_elapsed_text(key: String) -> String:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return ""
	_sync_timer_runtime_state(normalized_key)
	return _format_duration_usec(_get_timer_elapsed_usec_from_state(_timers[normalized_key]))


func get_timer_keys() -> Array[String]:
	var keys: Array[String] = []
	for timer_key in _timers.keys():
		keys.append(str(timer_key))
	keys.sort()
	return keys


func _normalize_timer_key(key: String) -> String:
	return key.strip_edges()


func _get_timer_channel_visibility_mode(channel: String) -> int:
	return get_channel_visibility(channel)


func _should_timer_count(timer_state: Dictionary) -> bool:
	return (
		bool(timer_state.get("running", false))
		and _get_timer_channel_visibility_mode(str(timer_state.get("channel", ""))) != VisibilityMode.OFF
	)


func _should_timer_pin(timer_state: Dictionary) -> bool:
	return (
		bool(timer_state.get("running", false))
		and _get_timer_channel_visibility_mode(str(timer_state.get("channel", ""))) == VisibilityMode.SHOWN
	)


func _sync_timer_runtime_state(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return

	var timer_state: Dictionary = _timers[normalized_key]
	var counting := bool(timer_state.get("counting", false))
	var should_count := _should_timer_count(timer_state)

	if counting and not should_count:
		timer_state["accumulated_usec"] = _get_timer_elapsed_usec_from_state(timer_state)
		timer_state["counting"] = false
		timer_state["started_usec"] = 0
	elif should_count and not counting:
		timer_state["counting"] = true
		timer_state["started_usec"] = Time.get_ticks_usec()

	_timers[normalized_key] = timer_state
	if _should_timer_pin(timer_state):
		_pin_timer_display_variables(normalized_key)
	else:
		_unpin_timer_display_variables(normalized_key)
	_notify_timer_display_variables_changed(normalized_key)


func _sync_timers_for_channel(channel: String) -> void:
	var normalized_channel := channel.strip_edges()
	for timer_key in get_timer_keys():
		var timer_state: Dictionary = _timers[timer_key]
		if str(timer_state.get("channel", "")) != normalized_channel:
			continue
		_sync_timer_runtime_state(timer_key)


func _get_timer_elapsed_usec_from_state(timer_state: Dictionary) -> int:
	var accumulated_usec := int(timer_state.get("accumulated_usec", 0))
	if not bool(timer_state.get("counting", false)):
		return maxi(0, accumulated_usec)

	var started_usec := int(timer_state.get("started_usec", 0))
	if started_usec <= 0:
		return maxi(0, accumulated_usec)
	return maxi(0, accumulated_usec + (Time.get_ticks_usec() - started_usec))


func _format_duration_usec(duration_usec: int) -> String:
	var safe_duration_usec := maxi(0, duration_usec)
	var total_msec := int(safe_duration_usec / 1000)
	var hours := int(total_msec / 3600000)
	var minutes := int((total_msec / 60000) % 60)
	var seconds := int((total_msec / 1000) % 60)
	var milliseconds := int(total_msec % 1000)
	return "%02d:%02d:%02d.%03d" % [hours, minutes, seconds, milliseconds]


func _get_timer_display_address(key: String) -> String:
	return "timers/%s" % key


func _ensure_timer_display_variables(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		return

	add_display_variable(
		_get_timer_display_address(normalized_key),
		Callable(self, "_get_timer_display_time").bind(normalized_key),
		Callable(),
		Callable(),
		true,
		TIMER_COMMAND_GROUP_NAME,
		TIMER_COMMAND_GROUP_PRIORITY,
		null,
		&"",
		Callable(self, "_get_timer_display_name").bind(normalized_key)
	)


func _remove_timer_display_variables(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		return
	remove_display_variable(_get_timer_display_address(normalized_key))


func _pin_timer_display_variables(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		return
	pin_display_variable(_get_timer_display_address(normalized_key))


func _unpin_timer_display_variables(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		return
	unpin_display_variable(_get_timer_display_address(normalized_key))


func _notify_timer_display_variables_changed(key: String) -> void:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty():
		return
	notify_display_variable_changed(_get_timer_display_address(normalized_key))


func _get_timer_display_name(key: String) -> String:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return ""
	return str((_timers[normalized_key] as Dictionary).get("name", normalized_key))


func _get_timer_display_time(key: String) -> String:
	var normalized_key := _normalize_timer_key(key)
	if normalized_key.is_empty() or not _timers.has(normalized_key):
		return ""
	return _format_duration_usec(_get_timer_elapsed_usec_from_state(_timers[normalized_key]))


func _get_running_timer_key_options() -> Array:
	var keys: Array = []
	for timer_key in get_timer_keys():
		_sync_timer_runtime_state(timer_key)
		if is_timer_running(timer_key):
			keys.append(timer_key)
	return keys


func _get_paused_timer_key_options() -> Array:
	var keys: Array = []
	for timer_key in get_timer_keys():
		_sync_timer_runtime_state(timer_key)
		if not is_timer_running(timer_key):
			keys.append(timer_key)
	return keys


func _get_known_timer_key_options() -> Array:
	var keys: Array = []
	for timer_key in get_timer_keys():
		keys.append(timer_key)
	return keys


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
	_sync_pinned_display_state_to(display)
	_apply_pinned_corner_availability_to(display)
	_sync_render_texture_widget_view_mode_to(display)
	if display.has_method("set_pinned_display_variables_suppressed"):
		display.set_pinned_display_variables_suppressed(_should_suppress_pinned_overlay())
	_apply_pending_pinned_display_variables_to(display)
	_apply_pending_render_texture_widget_view_mode_to(display)
	display.invalidate_command_catalog()


func unregister_external_display(display: LogotDisplay) -> void:
	if display == null:
		return

	for index in range(_external_displays.size() - 1, -1, -1):
		var existing_display = _external_displays[index].get_ref()
		if existing_display == null or existing_display == display:
			_external_displays.remove_at(index)


func _get_live_displays() -> Array[LogotDisplay]:
	var live_displays: Array[LogotDisplay] = []
	if _display != null:
		live_displays.append(_display)

	for index in range(_external_displays.size() - 1, -1, -1):
		var external_display = _external_displays[index].get_ref()
		if external_display == null:
			_external_displays.remove_at(index)
			continue
		if not (external_display is LogotDisplay):
			continue
		var typed_display := external_display as LogotDisplay
		if live_displays.has(typed_display):
			continue
		live_displays.append(typed_display)

	return live_displays


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


func batch_ui_updates(callback: Callable) -> bool:
	if not callback.is_valid():
		push_warning("Logot.batch_ui_updates: Invalid callback.")
		return false
	if _ui_update_batch_depth == 0:
		_ui_update_batch_displays = _get_live_displays()
		for display in _ui_update_batch_displays:
			display.begin_ui_update_batch()
	_ui_update_batch_depth += 1
	callback.call()
	_ui_update_batch_depth -= 1
	if _ui_update_batch_depth == 0:
		for display in _ui_update_batch_displays:
			if display != null and is_instance_valid(display):
				display.end_ui_update_batch()
		_ui_update_batch_displays.clear()
	return true


func _sync_pinned_display_state_to(target_display: LogotDisplay) -> void:
	if target_display == null:
		return

	var pinned_addresses: Dictionary = {}
	for live_display in _get_live_displays():
		if live_display == target_display:
			continue
		for address in live_display.get_pinned_display_variables():
			var normalized_address := str(address).strip_edges()
			if normalized_address.is_empty() or pinned_addresses.has(normalized_address):
				continue
			var corner := PIN_CORNER_TOP_LEFT
			if live_display.has_method("get_pinned_display_variable_corner"):
				corner = _normalize_pin_corner(str(live_display.get_pinned_display_variable_corner(normalized_address)))
			pinned_addresses[normalized_address] = {
				"corner": corner,
				"transient": live_display.has_method("is_display_variable_transiently_pinned") and bool(live_display.call("is_display_variable_transiently_pinned", normalized_address)),
			}

	for address in pinned_addresses:
		var pin_data := pinned_addresses[address] as Dictionary
		if bool(pin_data.get("transient", false)):
			target_display.set_display_variable_transiently_pinned(str(address), true, str(pin_data.get("corner", PIN_CORNER_TOP_LEFT)))
		else:
			target_display.pin_display_variable(str(address), str(pin_data.get("corner", PIN_CORNER_TOP_LEFT)))


func _sync_render_texture_widget_view_mode_to(target_display: LogotDisplay) -> void:
	if target_display == null or not target_display.has_method("set_render_texture_widget_view_mode"):
		return

	for live_display in _get_live_displays():
		if live_display == target_display:
			continue
		if not live_display.has_method("get_render_texture_widget_view_mode"):
			continue
		for widget_address in widgets.keys():
			var address_str := str(widget_address).strip_edges()
			if address_str.is_empty() or not _is_render_texture_widget_console_item(address_str):
				continue
			var active_mode := _normalize_render_texture_widget_view_mode(str(live_display.get_render_texture_widget_view_mode(address_str)))
			if active_mode == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE:
				continue
			target_display.set_render_texture_widget_view_mode(address_str, active_mode)
			return


func pin_display_variable(address: String, corner: String = PIN_CORNER_TOP_LEFT) -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		_pending_pinned_display_variables[address] = {
			"pinned": true,
			"corner": _normalize_pin_corner(corner),
		}
		return

	_pending_pinned_display_variables.erase(address)
	for display in live_displays:
		display.pin_display_variable(address, _normalize_pin_corner(corner))


func unpin_display_variable(address: String) -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		_pending_pinned_display_variables[address] = {
			"pinned": false,
			"corner": PIN_CORNER_TOP_LEFT,
		}
		return

	_pending_pinned_display_variables.erase(address)
	for display in live_displays:
		display.unpin_display_variable(address)


func set_display_variable_pinned(address: String, pinned: bool, corner: String = PIN_CORNER_TOP_LEFT) -> void:
	if pinned:
		pin_display_variable(address, corner)
	else:
		unpin_display_variable(address)


func set_display_variable_transiently_pinned(address: String, pinned: bool, corner: String = PIN_CORNER_TOP_LEFT) -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		_pending_pinned_display_variables[address] = {
			"pinned": pinned,
			"corner": _normalize_pin_corner(corner),
			"transient": true,
		}
		return
	_pending_pinned_display_variables.erase(address)
	for display in live_displays:
		display.set_display_variable_transiently_pinned(address, pinned, _normalize_pin_corner(corner))


func is_display_variable_pinned(address: String) -> bool:
	var active_display := _get_active_display()
	if active_display:
		return active_display.is_display_variable_pinned(address)
	var pending = _pending_pinned_display_variables.get(address, false)
	if pending is Dictionary:
		return bool((pending as Dictionary).get("pinned", false))
	return bool(pending)


func set_pinned_corner_enabled(corner: String, enabled: bool) -> bool:
	var normalized_corner := _normalize_pin_corner(corner)
	if bool(_pinned_corner_enabled.get(normalized_corner, true)) == enabled:
		return true
	if not enabled and get_enabled_pinned_corners().size() <= 1:
		print_error("Cannot disable pinned corner '%s': at least one pinned variable corner must remain enabled." % normalized_corner)
		return false
	_pinned_corner_enabled[normalized_corner] = enabled
	for display in _get_live_displays():
		if display.has_method("set_pinned_corner_enabled"):
			display.set_pinned_corner_enabled(normalized_corner, enabled)
	return true


func is_pinned_corner_enabled(corner: String) -> bool:
	return bool(_pinned_corner_enabled.get(_normalize_pin_corner(corner), true))


func get_enabled_pinned_corners() -> Array[String]:
	var enabled_corners: Array[String] = []
	for corner in PIN_CORNERS:
		if bool(_pinned_corner_enabled.get(corner, true)):
			enabled_corners.append(corner)
	return enabled_corners


func get_effective_pinned_display_variable_corner(address: String) -> String:
	var active_display := _get_active_display()
	if active_display != null and active_display.has_method("get_effective_pinned_display_variable_corner"):
		return str(active_display.get_effective_pinned_display_variable_corner(address))
	return PIN_CORNER_TOP_LEFT


func _apply_pinned_corner_availability_to(target_display: LogotDisplay) -> void:
	if target_display == null or not target_display.has_method("set_pinned_corner_enabled"):
		return
	for corner in PIN_CORNERS:
		target_display.set_pinned_corner_enabled(corner, bool(_pinned_corner_enabled.get(corner, true)))


func set_render_texture_widget_view_mode(address: String, mode: String) -> bool:
	var normalized_mode := _normalize_render_texture_widget_view_mode(mode)
	var normalized_address := address.strip_edges()
	if normalized_mode != LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE:
		if normalized_address.is_empty() or not _is_render_texture_widget_console_item(normalized_address):
			return false

	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		_pending_render_texture_widget_view_mode = {
			"address": normalized_address,
			"mode": normalized_mode,
		}
		return true

	var applied := false
	for display in live_displays:
		if display != null and display.has_method("set_render_texture_widget_view_mode"):
			applied = (display.set_render_texture_widget_view_mode(normalized_address, normalized_mode) == true) or applied
	if applied:
		_pending_render_texture_widget_view_mode.clear()
	return applied


func get_render_texture_widget_view_mode(address: String) -> String:
	var normalized_address := address.strip_edges()
	var active_display := _get_active_display()
	if active_display and active_display.has_method("get_render_texture_widget_view_mode"):
		return str(active_display.get_render_texture_widget_view_mode(normalized_address))
	if _pending_render_texture_widget_view_mode.is_empty():
		return LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
	if str(_pending_render_texture_widget_view_mode.get("address", "")) != normalized_address:
		return LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
	return _normalize_render_texture_widget_view_mode(str(_pending_render_texture_widget_view_mode.get("mode", LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE)))


func get_console_commands() -> Dictionary:
	return console_commands.duplicate()


func get_display_variables() -> Dictionary:
	return display_variables


func notify_display_variable_changed(address: String) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty():
		return

	for display in _get_live_displays():
		display.invalidate_display_variable(normalized_address)


func _register_display_variable_signal(address: String, source: Object, signal_name: StringName) -> void:
	_unregister_display_variable_signal(address)
	if source == null or not is_instance_valid(source) or signal_name == &"":
		return
	if not source.has_signal(signal_name):
		return

	var callback := func(_arg1 = null, _arg2 = null, _arg3 = null, _arg4 = null, _arg5 = null, _arg6 = null) -> void:
		_on_display_variable_signal_emitted(address)
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)
	_display_variable_signal_connections[address] = {
		"source": source,
		"signal_name": signal_name,
		"callback": callback,
	}


func _unregister_display_variable_signal(address: String) -> void:
	if not _display_variable_signal_connections.has(address):
		return

	var connection = _display_variable_signal_connections[address]
	_display_variable_signal_connections.erase(address)
	var source = connection.get("source", null)
	var signal_name = connection.get("signal_name", &"")
	var callback = connection.get("callback", Callable())
	if source == null or not is_instance_valid(source):
		return
	if signal_name == &"" or not (callback is Callable):
		return
	if source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)


func _on_display_variable_signal_emitted(address: String) -> void:
	notify_display_variable_changed(address)


func _notify_command_catalog_changed() -> void:
	_validate_default_child_commands()
	for display in _get_live_displays():
		display.invalidate_command_catalog()


func set_ingame_overlay_edge_overrides(top: float = 0.0, left: float = 0.0, right: float = 0.0, bottom: float = 0.0) -> void:
	_ingame_overlay_top_edge_override = maxf(0.0, top)
	_ingame_overlay_left_edge_override = maxf(0.0, left)
	_ingame_overlay_right_edge_override = maxf(0.0, right)
	_ingame_overlay_bottom_edge_override = maxf(0.0, bottom)
	_apply_ingame_overlay_edge_overrides()


func set_ingame_overlay_top_edge_override(value: float) -> void:
	set_ingame_overlay_edge_overrides(value, _ingame_overlay_left_edge_override, _ingame_overlay_right_edge_override, _ingame_overlay_bottom_edge_override)


func set_ingame_overlay_left_edge_override(value: float) -> void:
	set_ingame_overlay_edge_overrides(_ingame_overlay_top_edge_override, value, _ingame_overlay_right_edge_override, _ingame_overlay_bottom_edge_override)


func set_ingame_overlay_right_edge_override(value: float) -> void:
	set_ingame_overlay_edge_overrides(_ingame_overlay_top_edge_override, _ingame_overlay_left_edge_override, value, _ingame_overlay_bottom_edge_override)


func set_ingame_overlay_bottom_edge_override(value: float) -> void:
	set_ingame_overlay_edge_overrides(_ingame_overlay_top_edge_override, _ingame_overlay_left_edge_override, _ingame_overlay_right_edge_override, value)


func get_ingame_overlay_top_edge_override() -> float:
	return _ingame_overlay_top_edge_override


func get_ingame_overlay_left_edge_override() -> float:
	return _ingame_overlay_left_edge_override


func get_ingame_overlay_right_edge_override() -> float:
	return _ingame_overlay_right_edge_override


func get_ingame_overlay_bottom_edge_override() -> float:
	return _ingame_overlay_bottom_edge_override


func rebuild_display_view() -> void:
	if _display:
		_display.rebuild_display()


func _apply_ingame_overlay_edge_overrides() -> void:
	if _display and _display.has_method("set_ingame_overlay_edge_overrides"):
		_display.set_ingame_overlay_edge_overrides(
			_ingame_overlay_top_edge_override,
			_ingame_overlay_left_edge_override,
			_ingame_overlay_right_edge_override,
			_ingame_overlay_bottom_edge_override
		)
	_update_ingame_popup_layout()


# =============================================================================
# LIFECYCLE
# =============================================================================

func _enter_tree() -> void:
	# Initialize log system
	_init_default_levels()
	_load_performance_pin_mode()

	# Register engine logger to intercept Godot's internal logging
	if _engine_logger == null:
		_engine_logger = EngineLogger.new()
		_engine_logger.console = self
		OS.add_logger(_engine_logger)

	# Only set up game UI when NOT in editor
	if not Engine.is_editor_hint():
		_load_ingame_popup_settings()
		_load_touch_toggle_settings()
		_setup_game_ui()
		_setup_debugger_connection()
		call_deferred("_apply_saved_performance_pin_mode")

	process_mode = PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_performance_monitor(_delta)
	_update_virtual_keyboard_safe_area()
	_update_ingame_popup_layout()
	_update_touch_toggle_button_layout()


func _should_track_virtual_keyboard_safe_area() -> bool:
	return OS.get_name() == "Android" or OS.has_feature("android")


func _get_virtual_keyboard_safe_area_height() -> float:
	if not _should_track_virtual_keyboard_safe_area():
		return 0.0
	if DisplayServer.get_name() == "headless":
		return 0.0

	var viewport := get_viewport()
	var viewport_height := 0.0
	if viewport != null:
		viewport_height = float(viewport.get_visible_rect().size.y)

	var keyboard_height := float(DisplayServer.virtual_keyboard_get_height())
	if keyboard_height <= 0.0:
		_virtual_keyboard_baseline_viewport_height = viewport_height
		return 0.0

	if viewport == null:
		return keyboard_height

	if _virtual_keyboard_baseline_viewport_height <= 0.0 or viewport_height > _virtual_keyboard_baseline_viewport_height:
		_virtual_keyboard_baseline_viewport_height = viewport_height

	var window_height := float(DisplayServer.window_get_size().y)
	if viewport_height > 0.0 and window_height > 0.0 and not is_equal_approx(viewport_height, window_height):
		keyboard_height *= viewport_height / window_height

	var already_reserved_by_viewport := maxf(0.0, _virtual_keyboard_baseline_viewport_height - viewport_height)
	keyboard_height = maxf(0.0, keyboard_height - already_reserved_by_viewport)

	return clampf(keyboard_height, 0.0, maxf(0.0, viewport_height - 1.0))


func _update_virtual_keyboard_safe_area() -> void:
	_apply_virtual_keyboard_safe_area_height(_get_virtual_keyboard_safe_area_height())


func _apply_virtual_keyboard_safe_area_height(height: float) -> void:
	var target_height := maxf(0.0, height)
	var viewport := get_viewport()
	if viewport != null:
		var viewport_height := float(viewport.get_visible_rect().size.y)
		if viewport_height > 0.0:
			target_height = minf(target_height, maxf(0.0, viewport_height - 1.0))
	if absf(_virtual_keyboard_safe_area_height - target_height) <= VIRTUAL_KEYBOARD_SAFE_AREA_EPSILON:
		return

	_virtual_keyboard_safe_area_height = target_height
	if _display != null and is_instance_valid(_display):
		_display.offset_bottom = -target_height
		if _display.has_method("refresh_safe_area_layout"):
			_display.refresh_safe_area_layout()
			_display.call_deferred("refresh_safe_area_layout")
	_update_touch_toggle_button_layout()


func get_virtual_keyboard_safe_area_height() -> float:
	return _virtual_keyboard_safe_area_height


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
			if _display and _display.has_method("refresh_input_action_button_layout"):
				_display.refresh_input_action_button_layout()

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
	canvas_layer.layer = GAME_OVERLAY_CANVAS_LAYER
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
	_display.set_command_path_disabled_provider(is_command_path_disabled)
	_display.set_default_child_resolver(resolve_default_child_chain)
	_display.set_orderable_reorder_handler(_drag_orderable_object)
	_display.set_display_variables_provider(func(): return display_variables)
	_display.set_widgets_provider(func(): return widgets)
	_display.set_rejected_level_count_provider(func(level): return get_rejected_level_count(level))
	_display.set_rejected_channel_count_provider(func(channel): return get_rejected_channel_count(channel))
	_display.set_level_visibility_provider(get_level_visibility, set_level_visibility)
	_display.set_channel_visibility_provider(get_channel_visibility, set_channel_visibility)
	_display.add_custom_setting("touch_mode", "Touch mode", _should_enable_touch_mode_by_default())

	# Connect signals for visibility changes
	_display.cleared.connect(_on_display_cleared)
	_display.channel_deleted.connect(_on_channel_deleted)
	_display.custom_setting_changed.connect(_on_display_custom_setting_changed)
	_display.command_palette_submit_requested.connect(_on_command_palette_submit_requested)
	_display.command_palette_execute_keep_open_requested.connect(_on_command_palette_execute_keep_open_requested)
	_display.command_palette_close_requested.connect(_on_command_palette_close_requested)

	# Initialize the display
	_display.initialize_display()
	_apply_pinned_corner_availability_to(_display)
	_sync_console_setting_cache_from_display()
	_set_touch_mode_enabled(_get_console_setting_value("touch_mode", _should_enable_touch_mode_by_default()), false)
	_ensure_ingame_popup_overlay()
	_apply_ingame_overlay_edge_overrides()
	_ensure_touch_toggle_button(canvas_layer)
	_sync_pinned_overlay_suppression()

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

	_sync_pinned_display_state_to(_display)
	_sync_render_texture_widget_view_mode_to(_display)
	_apply_pending_pinned_display_variables()
	_apply_pending_render_texture_widget_view_mode()
	_ensure_test_panel()


func _ensure_ingame_popup_overlay() -> void:
	if _ingame_popup_overlay or not _display:
		return

	var overlay := Control.new()
	overlay.name = "IngamePopupOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.process_mode = PROCESS_MODE_ALWAYS
	overlay.z_index = 210
	_display.add_child(overlay)
	_ingame_popup_overlay = overlay

	var container := VBoxContainer.new()
	container.name = "IngamePopupContainer"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.process_mode = PROCESS_MODE_ALWAYS
	container.alignment = BoxContainer.ALIGNMENT_END
	container.add_theme_constant_override("separation", 6)
	container.anchor_left = 0.0
	container.anchor_top = 1.0
	container.anchor_right = 0.0
	container.anchor_bottom = 1.0
	container.offset_left = INGAME_POPUP_MARGIN
	container.offset_top = -INGAME_POPUP_HEIGHT - INGAME_POPUP_MARGIN
	container.offset_right = INGAME_POPUP_WIDTH + INGAME_POPUP_MARGIN
	container.offset_bottom = -INGAME_POPUP_MARGIN
	container.grow_horizontal = Control.GROW_DIRECTION_END
	container.grow_vertical = Control.GROW_DIRECTION_BEGIN
	overlay.add_child(container)
	_ingame_popup_container = container
	_raise_ingame_popup_overlay()
	_update_ingame_popup_layout()


func _raise_ingame_popup_overlay() -> void:
	if _display == null or _ingame_popup_overlay == null:
		return
	if _ingame_popup_overlay.get_parent() != _display:
		return
	_display.move_child(_ingame_popup_overlay, _display.get_child_count() - 1)


func _is_command_palette_visible() -> bool:
	if _display == null:
		return false
	return _display.is_command_palette_active()


func _get_command_palette_reserved_height() -> float:
	if _display == null:
		return 0.0
	return _display.get_command_palette_reserved_height()


func _update_ingame_popup_layout() -> void:
	if _ingame_popup_overlay == null or _ingame_popup_container == null:
		return
	var bottom_margin := INGAME_POPUP_MARGIN + _ingame_overlay_bottom_edge_override
	var left_margin := INGAME_POPUP_MARGIN + _ingame_overlay_left_edge_override
	var reserved_height := _get_command_palette_reserved_height()
	if reserved_height > 0.0:
		bottom_margin += reserved_height + INGAME_POPUP_COMMAND_PALETTE_GAP
		_raise_ingame_popup_overlay()
	_ingame_popup_container.offset_left = left_margin
	_ingame_popup_container.offset_right = left_margin + INGAME_POPUP_WIDTH
	_ingame_popup_container.offset_top = -INGAME_POPUP_HEIGHT - bottom_margin
	_ingame_popup_container.offset_bottom = -bottom_margin


func _should_suspend_ingame_popups() -> bool:
	return control != null and control.visible and not _is_command_palette_visible()


func _should_show_ingame_popup_for_entry(entry: LogEntry) -> bool:
	if entry == null:
		return false
	return entry.visible and _is_ingame_popup_level_effectively_enabled(entry.level)


func _show_ingame_popup(entry: LogEntry) -> void:
	if Engine.is_editor_hint() or not _should_show_ingame_popup_for_entry(entry):
		return
	if _should_suspend_ingame_popups():
		return

	_ensure_ingame_popup_overlay()
	if _ingame_popup_container == null:
		return
	_raise_ingame_popup_overlay()
	_update_ingame_popup_layout()

	var popup_signature := _get_ingame_popup_signature(entry)
	var existing_popup := _find_ingame_popup(popup_signature)
	if existing_popup != null:
		if bool(existing_popup.get_meta("dismiss_animating", false)):
			_free_ingame_popup(existing_popup)
		else:
			_update_existing_ingame_popup(existing_popup, entry)
			return

	if not _can_spawn_ingame_popup():
		return

	while _ingame_popup_container.get_child_count() >= INGAME_POPUP_MAX_VISIBLE:
		var oldest_popup := _ingame_popup_container.get_child(0)
		if oldest_popup:
			_free_ingame_popup(oldest_popup)
		else:
			break

	var popup_panel := PanelContainer.new()
	popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_panel.process_mode = PROCESS_MODE_ALWAYS
	popup_panel.modulate = Color(1, 1, 1, 1)
	popup_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_panel.custom_minimum_size = Vector2(INGAME_POPUP_WIDTH, 0)
	popup_panel.set_meta("signature", popup_signature)
	popup_panel.set_meta("message_text", _format_objects(entry.objects))
	popup_panel.set_meta("entry_level", entry.level)
	popup_panel.set_meta("entry_channel", entry.channel)
	popup_panel.set_meta("timestamp", entry.timestamp)
	popup_panel.set_meta("extra_line_count", entry.extra_line_count)
	popup_panel.set_meta("duplicate_count", 0)
	popup_panel.set_meta("expanded", false)
	popup_panel.set_meta("hovered", false)
	popup_panel.set_meta("swipe_dismiss_progress", 0.0)
	popup_panel.set_meta("swipe_dismiss_last_msec", 0)
	popup_panel.set_meta("dismiss_animating", false)

	var panel_style := _build_ingame_popup_panel_style(entry.level)
	popup_panel.add_theme_stylebox_override("panel", panel_style)

	var popup_label := RichTextLabel.new()
	popup_label.bbcode_enabled = true
	popup_label.fit_content = true
	popup_label.clip_contents = false
	popup_label.scroll_active = false
	popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_label.focus_mode = Control.FOCUS_NONE
	popup_label.meta_underlined = false
	popup_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_label.custom_minimum_size = Vector2(INGAME_POPUP_WIDTH - 46.0, 0)
	if rich_label:
		popup_label.theme = rich_label.theme
		var popup_font := rich_label.get_theme_font("normal_font")
		if popup_font:
			popup_label.add_theme_font_override("normal_font", popup_font)
		var popup_font_size := rich_label.get_theme_font_size("normal_font_size")
		if popup_font_size > 0:
			popup_label.add_theme_font_size_override("normal_font_size", popup_font_size)

	var close_button := Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Close popup"
	close_button.visible = false
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.anchor_left = 1.0
	close_button.anchor_top = 0.0
	close_button.anchor_right = 1.0
	close_button.anchor_bottom = 0.0
	close_button.offset_left = 0.0
	close_button.offset_top = -INGAME_POPUP_ACTION_SIZE / 2.0
	close_button.offset_right = INGAME_POPUP_ACTION_SIZE
	close_button.offset_bottom = INGAME_POPUP_ACTION_SIZE / 2.0
	close_button.custom_minimum_size = Vector2(INGAME_POPUP_ACTION_SIZE, INGAME_POPUP_ACTION_SIZE)
	close_button.z_index = 2
	_style_ingame_popup_close_button(close_button)
	close_button.pressed.connect(func() -> void:
		_free_ingame_popup(popup_panel)
	)

	var copy_button := Button.new()
	copy_button.text = "⧉"
	copy_button.tooltip_text = "Copy popup message"
	copy_button.visible = false
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.mouse_filter = Control.MOUSE_FILTER_STOP
	copy_button.anchor_left = 1.0
	copy_button.anchor_top = 0.0
	copy_button.anchor_right = 1.0
	copy_button.anchor_bottom = 0.0
	copy_button.offset_left = -INGAME_POPUP_ACTION_SIZE - INGAME_POPUP_ACTION_GAP
	copy_button.offset_top = -INGAME_POPUP_ACTION_SIZE / 2.0
	copy_button.offset_right = -INGAME_POPUP_ACTION_GAP
	copy_button.offset_bottom = INGAME_POPUP_ACTION_SIZE / 2.0
	copy_button.custom_minimum_size = Vector2(INGAME_POPUP_ACTION_SIZE, INGAME_POPUP_ACTION_SIZE)
	copy_button.z_index = 2
	_style_ingame_popup_close_button(copy_button)
	copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(str(popup_panel.get_meta("message_text", "")))
	)

	var count_badge := PanelContainer.new()
	count_badge.visible = false
	count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_badge.anchor_left = 1.0
	count_badge.anchor_top = 0.0
	count_badge.anchor_right = 1.0
	count_badge.anchor_bottom = 0.0
	count_badge.offset_left = 0.0
	count_badge.offset_top = -INGAME_POPUP_ACTION_SIZE / 2.0
	count_badge.offset_right = INGAME_POPUP_ACTION_SIZE
	count_badge.offset_bottom = INGAME_POPUP_ACTION_SIZE / 2.0
	count_badge.custom_minimum_size = Vector2(INGAME_POPUP_ACTION_SIZE, INGAME_POPUP_ACTION_SIZE)
	count_badge.z_index = 2
	_style_ingame_popup_count_badge(count_badge, entry.level)

	var count_label := Label.new()
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	count_label.add_theme_color_override("font_color", Color(0.08, 0.09, 0.11, 1.0))
	count_label.add_theme_font_size_override("font_size", 14)
	count_badge.add_child(count_label)

	popup_panel.add_child(popup_label)
	popup_label.add_child(copy_button)
	popup_label.add_child(close_button)
	popup_label.add_child(count_badge)
	_ingame_popup_container.add_child(popup_panel)
	popup_panel.set_meta("popup_label", popup_label)
	popup_panel.set_meta("close_button", close_button)
	popup_panel.set_meta("copy_button", copy_button)
	popup_panel.set_meta("count_badge", count_badge)
	popup_panel.set_meta("count_label", count_label)
	_register_ingame_popup(popup_signature, popup_panel)
	_record_ingame_popup_spawn()
	_render_ingame_popup(popup_panel)
	popup_panel.mouse_entered.connect(func() -> void:
		_set_ingame_popup_hover_state(popup_panel, true)
	)
	popup_panel.gui_input.connect(func(event: InputEvent) -> void:
		_handle_ingame_popup_gui_input(popup_panel, event)
	)
	popup_panel.mouse_exited.connect(func() -> void:
		_reset_ingame_popup_swipe_dismiss(popup_panel)
		call_deferred("_refresh_ingame_popup_hover_state_by_signature", popup_signature)
	)
	close_button.mouse_entered.connect(func() -> void:
		_set_ingame_popup_hover_state(popup_panel, true)
	)
	close_button.mouse_exited.connect(func() -> void:
		call_deferred("_refresh_ingame_popup_hover_state_by_signature", popup_signature)
	)
	copy_button.mouse_entered.connect(func() -> void:
		_set_ingame_popup_hover_state(popup_panel, true)
	)
	copy_button.mouse_exited.connect(func() -> void:
		call_deferred("_refresh_ingame_popup_hover_state_by_signature", popup_signature)
	)
	_schedule_ingame_popup_fade(popup_panel, true)


func _build_ingame_popup_panel_style(level: int) -> StyleBoxFlat:
	var level_color: Color = LogotDisplay.LEVEL_COLORS.get(level, Color.WHITE)
	var tinted_background := Color(
		level_color.r * 0.08 + 0.015,
		level_color.g * 0.08 + 0.02,
		level_color.b * 0.08 + 0.03,
		1.0
	)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = tinted_background
	panel_style.border_color = level_color.lerp(Color(1, 1, 1, 1), 0.18)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 6.0
	return panel_style


func _style_ingame_popup_count_badge(badge: PanelContainer, level: int) -> void:
	var level_color: Color = LogotDisplay.LEVEL_COLORS.get(level, Color.WHITE)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(level_color.r, level_color.g, level_color.b, 0.9)
	badge_style.border_color = Color(level_color.r, level_color.g, level_color.b, 1.0)
	badge_style.border_width_left = 1
	badge_style.border_width_top = 1
	badge_style.border_width_right = 1
	badge_style.border_width_bottom = 1
	var radius := int(INGAME_POPUP_ACTION_SIZE / 2.0)
	badge_style.corner_radius_top_left = radius
	badge_style.corner_radius_top_right = radius
	badge_style.corner_radius_bottom_right = radius
	badge_style.corner_radius_bottom_left = radius
	badge_style.content_margin_left = 0.0
	badge_style.content_margin_top = 0.0
	badge_style.content_margin_right = 0.0
	badge_style.content_margin_bottom = 0.0
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.add_theme_color_override("font_color", Color(0.08, 0.09, 0.11, 1.0))
	badge.add_theme_font_size_override("font_size", 14)


func _get_ingame_popup_signature(entry: LogEntry) -> String:
	return "%d|%s|%s" % [entry.level, entry.channel, _format_objects(entry.objects)]


func _register_ingame_popup(signature: String, popup_panel: Control) -> void:
	_ingame_popup_nodes[signature] = weakref(popup_panel)


func _find_ingame_popup(signature: String) -> Control:
	if not _ingame_popup_nodes.has(signature):
		return null
	var popup_ref = _ingame_popup_nodes[signature]
	if popup_ref is WeakRef:
		var popup_node = (popup_ref as WeakRef).get_ref()
		if popup_node != null and is_instance_valid(popup_node):
			return popup_node as Control
	_ingame_popup_nodes.erase(signature)
	return null


func _prune_ingame_popup_spawn_timestamps(now_seconds: float) -> void:
	var threshold := now_seconds - 1.0
	while not _ingame_popup_spawn_timestamps.is_empty() and _ingame_popup_spawn_timestamps[0] < threshold:
		_ingame_popup_spawn_timestamps.remove_at(0)


func _can_spawn_ingame_popup() -> bool:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	_prune_ingame_popup_spawn_timestamps(now_seconds)
	return _ingame_popup_spawn_timestamps.size() < INGAME_POPUP_MAX_SPAWNS_PER_SECOND


func _record_ingame_popup_spawn() -> void:
	var now_seconds := Time.get_ticks_msec() / 1000.0
	_prune_ingame_popup_spawn_timestamps(now_seconds)
	_ingame_popup_spawn_timestamps.append(now_seconds)


func _update_existing_ingame_popup(popup_panel: Control, entry: LogEntry) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	if bool(popup_panel.get_meta("dismiss_animating", false)):
		return
	popup_panel.set_meta("timestamp", entry.timestamp)
	popup_panel.set_meta("extra_line_count", entry.extra_line_count)
	popup_panel.set_meta("duplicate_count", int(popup_panel.get_meta("duplicate_count", 0)) + 1)
	_reset_ingame_popup_swipe_dismiss(popup_panel)
	_render_ingame_popup(popup_panel)
	if _ingame_popup_container != null and popup_panel.get_parent() == _ingame_popup_container:
		_ingame_popup_container.move_child(popup_panel, _ingame_popup_container.get_child_count() - 1)
	if bool(popup_panel.get_meta("hovered", false)):
		_stop_ingame_popup_fade(popup_panel)
	else:
		_schedule_ingame_popup_fade(popup_panel, true)


func _render_ingame_popup(popup_panel: Control) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	var popup_label = popup_panel.get_meta("popup_label", null) as RichTextLabel
	var count_badge = popup_panel.get_meta("count_badge", null) as PanelContainer
	var count_label = popup_panel.get_meta("count_label", null) as Label
	var close_button = popup_panel.get_meta("close_button", null) as Button
	var copy_button = popup_panel.get_meta("copy_button", null) as Button
	if popup_label:
		popup_label.clear()
		popup_label.append_text(_format_ingame_popup_text(
			str(popup_panel.get_meta("message_text", "")),
			int(popup_panel.get_meta("entry_level", LogLevel.MESSAGE)),
			str(popup_panel.get_meta("entry_channel", "")),
			int(popup_panel.get_meta("extra_line_count", 0)),
			bool(popup_panel.get_meta("expanded", false))
		))
	if count_label:
		count_label.text = str(int(popup_panel.get_meta("duplicate_count", 0)))
	if count_badge and close_button and copy_button:
		var duplicate_count := int(popup_panel.get_meta("duplicate_count", 0))
		count_badge.visible = duplicate_count > 0 and not bool(popup_panel.get_meta("hovered", false))
		close_button.visible = bool(popup_panel.get_meta("hovered", false))
		copy_button.visible = bool(popup_panel.get_meta("hovered", false))


func _set_ingame_popup_hover_state(popup_panel: Control, hovered: bool) -> void:
	if popup_panel == null:
		return
	if not is_instance_valid(popup_panel):
		return
	var was_hovered := bool(popup_panel.get_meta("hovered", false))
	if was_hovered == hovered:
		return
	popup_panel.set_meta("hovered", hovered)
	_render_ingame_popup(popup_panel)
	if hovered:
		_stop_ingame_popup_fade(popup_panel)
	else:
		_reset_ingame_popup_swipe_dismiss(popup_panel)
		_schedule_ingame_popup_fade(popup_panel, true)


func _toggle_ingame_popup_expanded(popup_panel: Control) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	popup_panel.set_meta("expanded", not bool(popup_panel.get_meta("expanded", false)))
	_render_ingame_popup(popup_panel)


func _refresh_ingame_popup_hover_state(popup_panel) -> void:
	if popup_panel == null:
		return
	if not (popup_panel is Control):
		return
	var popup_control := popup_panel as Control
	if not is_instance_valid(popup_control):
		return
	var close_button = popup_control.get_meta("close_button", null) as Button
	var copy_button = popup_control.get_meta("copy_button", null) as Button
	if close_button == null or not is_instance_valid(close_button) or copy_button == null or not is_instance_valid(copy_button):
		return
	var mouse_position := popup_control.get_global_mouse_position()
	var hovered := (
		popup_control.get_global_rect().has_point(mouse_position)
		or close_button.get_global_rect().has_point(mouse_position)
		or copy_button.get_global_rect().has_point(mouse_position)
	)
	_set_ingame_popup_hover_state(popup_control, hovered)


func _refresh_ingame_popup_hover_state_by_signature(signature: String) -> void:
	if signature.is_empty():
		return
	var popup_panel := _find_ingame_popup(signature)
	if popup_panel == null:
		return
	_refresh_ingame_popup_hover_state(popup_panel)


func _handle_ingame_popup_gui_input(popup_panel: Control, event: InputEvent) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	if bool(popup_panel.get_meta("dismiss_animating", false)):
		popup_panel.accept_event()
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_toggle_ingame_popup_expanded(popup_panel)
			popup_panel.accept_event()
			return
		if not mouse_event.pressed:
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_accumulate_ingame_popup_swipe_dismiss(popup_panel, INGAME_POPUP_SWIPE_WHEEL_STEP)
			popup_panel.accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_reset_ingame_popup_swipe_dismiss(popup_panel)
			return

	if event is InputEventPanGesture:
		var pan_event := event as InputEventPanGesture
		if absf(pan_event.delta.x) <= absf(pan_event.delta.y):
			return
		var horizontal_amount := absf(pan_event.delta.x)
		if is_zero_approx(horizontal_amount):
			return
		# Trackpad pan direction can vary with platform scroll settings, so any
		# dominant horizontal pan over the popup is treated as dismissal intent.
		_accumulate_ingame_popup_swipe_dismiss(popup_panel, horizontal_amount)
		popup_panel.accept_event()


func _accumulate_ingame_popup_swipe_dismiss(popup_panel: Control, amount: float) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel) or amount <= 0.0:
		return

	var now_msec := Time.get_ticks_msec()
	var last_input_msec := int(popup_panel.get_meta("swipe_dismiss_last_msec", 0))
	var progress := 0.0
	if last_input_msec > 0 and now_msec - last_input_msec <= INGAME_POPUP_SWIPE_DISMISS_TIMEOUT_MSEC:
		progress = float(popup_panel.get_meta("swipe_dismiss_progress", 0.0))

	progress += amount
	popup_panel.set_meta("swipe_dismiss_progress", progress)
	popup_panel.set_meta("swipe_dismiss_last_msec", now_msec)
	_set_ingame_popup_hover_state(popup_panel, true)

	if progress >= INGAME_POPUP_SWIPE_DISMISS_THRESHOLD:
		_dismiss_ingame_popup_with_swipe(popup_panel)


func _reset_ingame_popup_swipe_dismiss(popup_panel: Control) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	popup_panel.set_meta("swipe_dismiss_progress", 0.0)
	popup_panel.set_meta("swipe_dismiss_last_msec", 0)


func _dismiss_ingame_popup_with_swipe(popup_panel: Control) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	if bool(popup_panel.get_meta("dismiss_animating", false)):
		return

	popup_panel.set_meta("dismiss_animating", true)
	_reset_ingame_popup_swipe_dismiss(popup_panel)
	_stop_ingame_popup_fade(popup_panel)

	var dismiss_tween := popup_panel.create_tween()
	dismiss_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	dismiss_tween.set_trans(Tween.TRANS_CUBIC)
	dismiss_tween.set_ease(Tween.EASE_OUT)
	dismiss_tween.parallel().tween_property(
		popup_panel,
		"position:x",
		popup_panel.position.x - INGAME_POPUP_SWIPE_EXIT_DISTANCE,
		INGAME_POPUP_SWIPE_EXIT_DURATION
	)
	dismiss_tween.parallel().tween_property(
		popup_panel,
		"modulate:a",
		0.0,
		INGAME_POPUP_SWIPE_EXIT_DURATION
	)
	dismiss_tween.finished.connect(func() -> void:
		if is_instance_valid(popup_panel):
			_free_ingame_popup(popup_panel)
	)


func _style_ingame_popup_close_button(button: Button) -> void:
	var radius := int(INGAME_POPUP_ACTION_SIZE / 2.0)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.18, 0.98)
	normal.border_color = Color(0.5, 0.54, 0.64, 0.98)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_right = radius
	normal.corner_radius_bottom_left = radius

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.26, 0.34, 1.0)
	hover.border_color = Color(0.72, 0.78, 0.92, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.28, 0.18, 0.2, 1.0)
	pressed.border_color = Color(0.9, 0.58, 0.62, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 16)


func _stop_ingame_popup_fade_internal(popup_panel: Control) -> void:
	var fade_tween = popup_panel.get_meta("fade_tween") if popup_panel.has_meta("fade_tween") else null
	if fade_tween != null and is_instance_valid(fade_tween):
		(fade_tween as Tween).kill()
	popup_panel.set_meta("fade_tween", null)
	popup_panel.modulate = Color(1, 1, 1, 1)


func _stop_ingame_popup_fade(popup_panel: Control) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	if _ingame_popup_guard:
		return
	_ingame_popup_guard = true
	_stop_ingame_popup_fade_internal(popup_panel)
	_ingame_popup_guard = false


func _schedule_ingame_popup_fade(popup_panel: Control, reset_timer: bool = false) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	var was_guarded := _ingame_popup_guard
	_ingame_popup_guard = true

	_stop_ingame_popup_fade_internal(popup_panel)
	if not _ingame_popup_fade_enabled:
		_ingame_popup_guard = was_guarded
		return

	if reset_timer:
		popup_panel.modulate = Color(1, 1, 1, 1)

	var popup_lifetime := maxf(0.0, _ingame_popup_fade_time)
	var popup_fade_duration := minf(INGAME_POPUP_FADE_DURATION, popup_lifetime)
	var popup_tween := popup_panel.create_tween()
	popup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	popup_panel.set_meta("fade_tween", popup_tween)
	popup_tween.tween_interval(maxf(0.0, popup_lifetime - popup_fade_duration))
	popup_tween.tween_property(popup_panel, "modulate:a", 0.0, popup_fade_duration)
	popup_tween.finished.connect(func() -> void:
		if is_instance_valid(popup_panel):
			_free_ingame_popup(popup_panel)
	)
	_ingame_popup_guard = was_guarded


func _free_ingame_popup(popup_panel: Node) -> void:
	if popup_panel == null or not is_instance_valid(popup_panel):
		return
	var popup_parent := popup_panel.get_parent()
	if popup_parent != null:
		popup_parent.remove_child(popup_panel)
	if _ingame_popup_guard:
		_unregister_ingame_popup_node(popup_panel)
		popup_panel.queue_free()
		return
	_ingame_popup_guard = true
	_unregister_ingame_popup_node(popup_panel)
	if popup_panel is Control:
		_stop_ingame_popup_fade_internal(popup_panel as Control)
	popup_panel.queue_free()
	_ingame_popup_guard = false


func _format_ingame_popup(entry: LogEntry) -> String:
	var popup_text := _format_objects(entry.objects)
	return _format_ingame_popup_text(popup_text, entry.level, entry.channel, entry.extra_line_count, false)


func _unregister_ingame_popup_node(popup_panel: Node) -> void:
	var signature := str(popup_panel.get_meta("signature", ""))
	if signature.is_empty():
		return
	if not _ingame_popup_nodes.has(signature):
		return
	var popup_ref = _ingame_popup_nodes[signature]
	if popup_ref is WeakRef:
		var popup_node = (popup_ref as WeakRef).get_ref()
		if popup_node == popup_panel or popup_node == null:
			_ingame_popup_nodes.erase(signature)
			return
	_ingame_popup_nodes.erase(signature)


func _format_ingame_popup_text(message_text: String, level: int, channel: String, extra_line_count: int = 0, expanded: bool = false) -> String:
	var display_text := message_text if expanded else (message_text.split("\n")[0] if "\n" in message_text else message_text)
	var extra_indicator := ""
	if extra_line_count > 0 and not expanded:
		extra_indicator = " [i][color=#98A5BA]+%d[/color][/i]" % extra_line_count

	var level_color := LogotDisplay.LEVEL_COLORS.get(level, Color.WHITE) as Color
	var message_color := level_color.lerp(Color(0.96, 0.98, 1.0, 1.0), 0.72)
	var message_color_hex := "#" + message_color.to_html(false)
	var channel_markup := ""
	if not channel.is_empty():
		channel_markup = "[color=#D8E0EE][%s][/color] " % [
			_escape_ingame_popup_bbcode(channel),
		]

	return "%s[color=%s]%s[/color]%s" % [
		channel_markup,
		message_color_hex,
		display_text,
		extra_indicator,
	]


func _escape_ingame_popup_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _clear_ingame_popups() -> void:
	if _ingame_popup_container == null:
		_ingame_popup_nodes.clear()
		_ingame_popup_spawn_timestamps.clear()
		return
	for child in _ingame_popup_container.get_children():
		child.queue_free()
	_ingame_popup_nodes.clear()
	_ingame_popup_spawn_timestamps.clear()


func _init_ingame_popup_level_defaults() -> void:
	for level in INGAME_POPUP_LEVELS:
		if not _ingame_popup_levels.has(level):
			_ingame_popup_levels[level] = false


func _get_ingame_popup_level_key(level: int) -> String:
	var level_name := str(LogLevel.names.get(level, "level_%d" % level))
	return level_name.to_lower()


func _get_ingame_popup_level_command_path(level: int) -> String:
	return "%s/%s" % [INGAME_POPUP_LEVELS_COMMAND_PATH, _get_ingame_popup_level_key(level)]


func _get_ingame_popup_level_label(level: int) -> String:
	return _get_ingame_popup_level_key(level)


func _get_ingame_popup_level_display_name(level: int) -> String:
	return str(LogLevel.names.get(level, "LEVEL_%d" % level))


func _is_ingame_popup_level_enabled(level: int) -> bool:
	_init_ingame_popup_level_defaults()
	return bool(_ingame_popup_levels.get(level, false))


func _is_ingame_popup_level_available(level: int) -> bool:
	return get_level_visibility(level) != VisibilityMode.OFF


func _is_ingame_popup_level_effectively_enabled(level: int) -> bool:
	if _ingame_popup_mirror_main_console:
		return get_level_visibility(level) == VisibilityMode.SHOWN
	return _is_ingame_popup_level_available(level) and _is_ingame_popup_level_enabled(level)


func _get_ingame_popup_level_indicator(level: int) -> String:
	return INGAME_POPUP_ENABLED_MARK if _is_ingame_popup_level_effectively_enabled(level) else INGAME_POPUP_DISABLED_MARK


func _get_ingame_popup_level_indicator_color(level: int) -> Color:
	if _ingame_popup_mirror_main_console:
		return Color(0.36, 0.84, 0.55, 1.0) if _is_ingame_popup_level_effectively_enabled(level) else Color(0.55, 0.57, 0.62, 1.0)
	if not _is_ingame_popup_level_available(level):
		return Color(0.55, 0.57, 0.62, 1.0)
	return Color(0.36, 0.84, 0.55, 1.0) if _is_ingame_popup_level_enabled(level) else Color(0.88, 0.44, 0.44, 1.0)


func _get_visibility_mode_label(mode: int) -> String:
	match mode:
		VisibilityMode.SHOWN:
			return "shown"
		VisibilityMode.HIDDEN:
			return "hidden"
		VisibilityMode.OFF:
			return "off"
		_:
			return "shown"


func _save_ingame_popup_settings() -> void:
	_init_ingame_popup_level_defaults()
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	for level in INGAME_POPUP_LEVELS:
		config.set_value(INGAME_POPUP_SETTINGS_SECTION, _get_ingame_popup_level_key(level), _is_ingame_popup_level_enabled(level))
	config.set_value(
		INGAME_POPUP_SETTINGS_SECTION,
		"mirror_main_console",
		_ingame_popup_mirror_main_console
	)
	config.set_value(
		INGAME_POPUP_SETTINGS_SECTION,
		"fade_time",
		"off" if not _ingame_popup_fade_enabled else _get_ingame_popup_fade_time_setting_value()
	)
	config.save(SETTINGS_FILE)


func _load_ingame_popup_settings() -> void:
	_init_ingame_popup_level_defaults()

	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return

	if config.has_section(INGAME_POPUP_SETTINGS_SECTION):
		for level in INGAME_POPUP_LEVELS:
			_ingame_popup_levels[level] = bool(config.get_value(INGAME_POPUP_SETTINGS_SECTION, _get_ingame_popup_level_key(level), false))
		_ingame_popup_mirror_main_console = bool(config.get_value(
			INGAME_POPUP_SETTINGS_SECTION,
			"mirror_main_console",
			false
		))
		_set_ingame_popup_fade_time_setting(str(config.get_value(
			INGAME_POPUP_SETTINGS_SECTION,
			"fade_time",
			str(DEFAULT_INGAME_POPUP_LIFETIME)
		)), false)
		return

	if config.has_section_key("settings", "ingame_popups"):
		var legacy_enabled := bool(config.get_value("settings", "ingame_popups", false))
		for level in INGAME_POPUP_LEVELS:
			_ingame_popup_levels[level] = legacy_enabled


func _save_touch_toggle_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value(TOUCH_TOGGLE_SETTINGS_SECTION, TOUCH_TOGGLE_SETTINGS_KEY_EDGE, _touch_toggle_edge)
	var viewport_size := _get_touch_toggle_viewport_size()
	if viewport_size.y > 0.0 and _touch_toggle_center_y >= 0.0:
		config.set_value(
			TOUCH_TOGGLE_SETTINGS_SECTION,
			TOUCH_TOGGLE_SETTINGS_KEY_CENTER_Y_RATIO,
			clampf(_touch_toggle_center_y / viewport_size.y, 0.0, 1.0)
		)
	config.save(SETTINGS_FILE)


func _load_touch_toggle_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	var edge := str(config.get_value(TOUCH_TOGGLE_SETTINGS_SECTION, TOUCH_TOGGLE_SETTINGS_KEY_EDGE, _touch_toggle_edge))
	if edge == TOUCH_TOGGLE_EDGE_LEFT or edge == TOUCH_TOGGLE_EDGE_RIGHT:
		_touch_toggle_edge = edge
	var viewport_size := _get_touch_toggle_viewport_size()
	if viewport_size.y > 0.0:
		var center_y_ratio := float(config.get_value(
			TOUCH_TOGGLE_SETTINGS_SECTION,
			TOUCH_TOGGLE_SETTINGS_KEY_CENTER_Y_RATIO,
			TOUCH_TOGGLE_DEFAULT_CENTER_Y_RATIO
		))
		_touch_toggle_center_y = clampf(center_y_ratio, 0.0, 1.0) * viewport_size.y


func _set_ingame_popup_level_enabled(level: int, enabled: bool) -> bool:
	_init_ingame_popup_level_defaults()
	if enabled and not _is_ingame_popup_level_available(level):
		print_error("Cannot enable popup for %s while the main console level is OFF." % _get_ingame_popup_level_display_name(level))
		return false

	_ingame_popup_levels[level] = enabled
	_save_ingame_popup_settings()
	if not enabled:
		_clear_ingame_popups()
	return true


func _toggle_ingame_popup_level(level: int) -> void:
	var next_enabled := not _is_ingame_popup_level_enabled(level)
	if not _set_ingame_popup_level_enabled(level, next_enabled):
		return
	var mirror_suffix := ""
	if _ingame_popup_mirror_main_console:
		mirror_suffix = " (stored for custom mode; currently bypassed by mirror main console)"
	print_line("Ingame popup custom filter for %s: %s%s" % [
		_get_ingame_popup_level_display_name(level),
		"on" if next_enabled else "off",
		mirror_suffix,
	])


func _disable_all_ingame_popup_levels() -> void:
	_init_ingame_popup_level_defaults()
	for level in INGAME_POPUP_LEVELS:
		_ingame_popup_levels[level] = false
	_save_ingame_popup_settings()
	_clear_ingame_popups()
	if _ingame_popup_mirror_main_console:
		print_line("Stored custom ingame popup levels disabled for all log levels. Mirror main console is still active.")
		return
	print_line("Ingame popups disabled for all log levels.")


func _copy_ingame_popup_levels_from_console() -> void:
	_init_ingame_popup_level_defaults()
	for level in INGAME_POPUP_LEVELS:
		_ingame_popup_levels[level] = get_level_visibility(level) == VisibilityMode.SHOWN
	_save_ingame_popup_settings()
	if _ingame_popup_mirror_main_console:
		print_line("Stored custom ingame popup levels copied from the main console visibility. Mirror main console is still active.")
		return
	print_line("Ingame popup levels copied from the main console visibility.")


func _get_ingame_popup_mirror_main_console() -> bool:
	return _ingame_popup_mirror_main_console


func _set_ingame_popup_mirror_main_console(enabled: bool) -> void:
	if _ingame_popup_mirror_main_console == enabled:
		return
	_ingame_popup_mirror_main_console = enabled
	_save_ingame_popup_settings()
	_clear_ingame_popups()


func _get_ingame_popup_fade_time_options() -> Array:
	return ["off", "1", "3", "5", "10"]


func _get_ingame_popup_fade_time_setting_value() -> String:
	return "off" if not _ingame_popup_fade_enabled else str(_ingame_popup_fade_time)


func _set_ingame_popup_fade_time_setting(raw_value: String, persist: bool = true) -> bool:
	var trimmed_value := raw_value.strip_edges().to_lower()
	if trimmed_value == "off":
		_ingame_popup_fade_enabled = false
		if persist:
			_save_ingame_popup_settings()
		return true

	var numeric_text := raw_value.strip_edges()
	if not (numeric_text.is_valid_float() or numeric_text.is_valid_int()):
		if persist:
			print_error("Ingame popup fade time must be a number of seconds or 'off'.")
		return false

	var next_value := float(numeric_text)
	if next_value < 0.0:
		if persist:
			print_error("Ingame popup fade time must be zero or greater.")
		return false

	_ingame_popup_fade_time = next_value
	_ingame_popup_fade_enabled = true
	if persist:
		_save_ingame_popup_settings()
	return true


func _command_ingame_popups_summary() -> void:
	var lines: PackedStringArray = []
	lines.append("Ingame popup settings:")
	lines.append("  /%s" % INGAME_POPUP_LEVELS_COMMAND_PATH)
	lines.append("  /%s (%s)" % [INGAME_POPUP_FADE_TIME_COMMAND_PATH, _get_ingame_popup_fade_time_setting_value()])
	lines.append("  log level mode: %s" % ("mirror main console" if _ingame_popup_mirror_main_console else "custom popup levels"))
	print_line("\n".join(lines))


func _command_ingame_popup_levels_summary() -> void:
	var lines: PackedStringArray = []
	lines.append("Ingame popup log levels:")
	lines.append("  /%s (%s)" % [
		INGAME_POPUP_LEVELS_MIRROR_MAIN_CONSOLE_COMMAND_PATH,
		"on" if _ingame_popup_mirror_main_console else "off",
	])
	lines.append("  /%s" % INGAME_POPUP_LEVELS_DISABLE_ALL_COMMAND_PATH)
	lines.append("  /%s" % INGAME_POPUP_LEVELS_COPY_CONSOLE_COMMAND_PATH)
	if _ingame_popup_mirror_main_console:
		lines.append("  mirroring the main console log level filter; custom popup level settings are bypassed.")
	else:
		lines.append("  using custom popup log level settings.")
	for level in INGAME_POPUP_LEVELS:
		if _ingame_popup_mirror_main_console:
			lines.append("  %s %s (main: %s, custom stored: %s)" % [
				_get_ingame_popup_level_indicator(level),
				_get_ingame_popup_level_display_name(level),
				_get_visibility_mode_label(get_level_visibility(level)),
				"on" if _is_ingame_popup_level_enabled(level) else "off",
			])
		else:
			lines.append("  %s %s (main: %s)" % [
				_get_ingame_popup_level_indicator(level),
				_get_ingame_popup_level_display_name(level),
				_get_visibility_mode_label(get_level_visibility(level)),
			])
	print_line("\n".join(lines))


func _apply_pending_pinned_display_variables() -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		return
	for live_display in live_displays:
		_apply_pending_pinned_display_variables_to(live_display, false)
	_pending_pinned_display_variables.clear()


func _apply_pending_pinned_display_variables_to(target_display: LogotDisplay, clear_pending: bool = true) -> void:
	if not target_display:
		return

	for address in _pending_pinned_display_variables:
		var pending = _pending_pinned_display_variables[address]
		var pinned := false
		var corner := PIN_CORNER_TOP_LEFT
		var transient := false
		if pending is Dictionary:
			pinned = bool((pending as Dictionary).get("pinned", false))
			corner = _normalize_pin_corner(str((pending as Dictionary).get("corner", PIN_CORNER_TOP_LEFT)))
			transient = bool((pending as Dictionary).get("transient", false))
		else:
			pinned = bool(pending)
		if transient:
			target_display.set_display_variable_transiently_pinned(str(address), pinned, corner)
		elif pinned:
			target_display.pin_display_variable(str(address), corner)
		else:
			target_display.unpin_display_variable(str(address))
	if clear_pending:
		_pending_pinned_display_variables.clear()


func _apply_pending_render_texture_widget_view_mode() -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		return
	for live_display in live_displays:
		_apply_pending_render_texture_widget_view_mode_to(live_display, false)
	_pending_render_texture_widget_view_mode.clear()


func _apply_pending_render_texture_widget_view_mode_to(target_display: LogotDisplay, clear_pending: bool = true) -> void:
	if not target_display or _pending_render_texture_widget_view_mode.is_empty():
		return
	if not target_display.has_method("set_render_texture_widget_view_mode"):
		return

	var pending_address := str(_pending_render_texture_widget_view_mode.get("address", ""))
	var pending_mode := _normalize_render_texture_widget_view_mode(str(_pending_render_texture_widget_view_mode.get("mode", LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE)))
	target_display.set_render_texture_widget_view_mode(pending_address, pending_mode)
	if clear_pending:
		_pending_render_texture_widget_view_mode.clear()


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
	if _performance_source_monitor != null:
		_performance_source_monitor.call("set_capture_enabled", false, false)

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


func _on_display_custom_setting_changed(setting_name: String, value: bool) -> void:
	if setting_name == "touch_mode":
		_set_touch_mode_enabled(value, false)


func _on_command_palette_submit_requested(command_text: String) -> void:
	_submit_line_edit_input(command_text, false, false)


func _on_command_palette_execute_keep_open_requested(command_text: String) -> void:
	var submitted_text := command_text.strip_edges()
	if submitted_text.is_empty() or not submitted_text.begins_with("/"):
		return
	_execute_command(submitted_text)
	if _display != null:
		var palette_text := "/" if line_edit == null else line_edit.text.strip_edges()
		if not palette_text.begins_with("/"):
			palette_text = "/"
		_display.show_command_entry_mode(palette_text, false)


func _on_command_palette_close_requested() -> void:
	_close_command_entry_view()


func _sync_pinned_overlay_suppression() -> void:
	var suppressed := _should_suppress_pinned_overlay()
	for display in _get_live_displays():
		if display.has_method("set_pinned_display_variables_suppressed"):
			display.set_pinned_display_variables_suppressed(suppressed)


func _should_suppress_pinned_overlay() -> bool:
	if not _is_console_control_visible():
		return false
	if _display != null and _display.is_command_entry_mode() and _display.get_current_input_method() != LogotDisplay.INPUT_METHOD_TOUCH:
		return false
	return true


func _should_enable_touch_mode_by_default() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _get_setting_touch_mode() -> bool:
	return _get_console_setting_value("touch_mode", _touch_mode_enabled)


func _set_setting_touch_mode(value: bool) -> void:
	_set_console_setting_value("touch_mode", value)


func _set_touch_mode_enabled(value: bool, sync_display_setting: bool = true) -> void:
	_touch_mode_enabled = value
	if sync_display_setting and _display:
		_display.apply_setting("touch_mode", value)
	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH if _touch_mode_enabled else LogotDisplay.INPUT_METHOD_KEYBOARD)
		if _display.has_method("set_touch_sidebar_fullscreen_enabled"):
			_display.set_touch_sidebar_fullscreen_enabled(_touch_mode_enabled)
	_sync_pinned_overlay_suppression()
	_update_touch_toggle_button()


func _ensure_touch_toggle_button(parent: Node) -> void:
	if _touch_toggle_dock != null and is_instance_valid(_touch_toggle_dock):
		_update_touch_toggle_button()
		return
	if parent == null:
		return

	var dock := Control.new()
	dock.name = "TouchConsoleEdgeDock"
	dock.focus_mode = Control.FOCUS_NONE
	dock.mouse_filter = Control.MOUSE_FILTER_PASS
	dock.z_index = 200
	dock.set_anchors_preset(Control.PRESET_TOP_LEFT)
	parent.add_child(dock)
	_touch_toggle_dock = dock

	var command_button := _create_touch_edge_button(
		"TouchCommandPaletteButton",
		"/",
		"Open command palette",
		TOUCH_TOGGLE_ACTION_COMMAND
	)
	dock.add_child(command_button)
	_touch_command_palette_button = command_button

	var log_button := _create_touch_edge_button(
		"TouchFullLogButton",
		"≡",
		"Open full log",
		TOUCH_TOGGLE_ACTION_LOG
	)
	dock.add_child(log_button)
	_touch_full_log_button = log_button

	_update_touch_toggle_button()


func _create_touch_edge_button(button_name: String, icon_text: String, tooltip: String, action: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = icon_text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size = TOUCH_EDGE_BUTTON_SIZE
	button.size = TOUCH_EDGE_BUTTON_SIZE
	button.clip_text = true
	button.gui_input.connect(_on_touch_edge_button_gui_input.bind(action))
	_style_touch_edge_button(button)
	return button


func _update_touch_toggle_button_layout() -> void:
	if _touch_toggle_dock == null or not is_instance_valid(_touch_toggle_dock):
		return
	var viewport_size := _get_touch_toggle_viewport_size()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var dock_size := Vector2(
		TOUCH_EDGE_BUTTON_SIZE.x,
		TOUCH_EDGE_BUTTON_SIZE.y * 2.0 + TOUCH_EDGE_BUTTON_GAP
	)
	var min_y := TOUCH_TOGGLE_BUTTON_MARGIN
	var max_y := maxf(
		min_y,
		viewport_size.y - _virtual_keyboard_safe_area_height - TOUCH_TOGGLE_BUTTON_MARGIN - dock_size.y
	)
	if _touch_toggle_center_y < 0.0:
		_touch_toggle_center_y = viewport_size.y * TOUCH_TOGGLE_DEFAULT_CENTER_Y_RATIO

	var dock_y := clampf(_touch_toggle_center_y - dock_size.y * 0.5, min_y, max_y)
	_touch_toggle_center_y = dock_y + dock_size.y * 0.5
	var dock_x := 0.0 if _touch_toggle_edge == TOUCH_TOGGLE_EDGE_LEFT else viewport_size.x - dock_size.x
	if _touch_toggle_drag_active and _touch_toggle_drag_moved and _touch_toggle_drag_dock_x >= 0.0:
		dock_x = clampf(_touch_toggle_drag_dock_x, 0.0, maxf(0.0, viewport_size.x - dock_size.x))

	_touch_toggle_dock.position = Vector2(dock_x, dock_y)
	_touch_toggle_dock.size = dock_size
	_touch_toggle_dock.custom_minimum_size = dock_size

	if _touch_command_palette_button != null and is_instance_valid(_touch_command_palette_button):
		_touch_command_palette_button.position = Vector2.ZERO
		_touch_command_palette_button.size = TOUCH_EDGE_BUTTON_SIZE
		_style_touch_edge_button(_touch_command_palette_button)
	if _touch_full_log_button != null and is_instance_valid(_touch_full_log_button):
		_touch_full_log_button.position = Vector2(0.0, TOUCH_EDGE_BUTTON_SIZE.y + TOUCH_EDGE_BUTTON_GAP)
		_touch_full_log_button.size = TOUCH_EDGE_BUTTON_SIZE
		_style_touch_edge_button(_touch_full_log_button)


func _get_touch_toggle_viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2(DisplayServer.window_get_size())


func _style_touch_edge_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.1, 0.13, 0.9)
	normal.border_color = Color(0.5, 0.55, 0.65, 0.95)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	if _touch_toggle_edge == TOUCH_TOGGLE_EDGE_LEFT:
		normal.corner_radius_top_left = 0
		normal.corner_radius_bottom_left = 0
		normal.corner_radius_top_right = int(TOUCH_EDGE_BUTTON_SIZE.y * 0.5)
		normal.corner_radius_bottom_right = int(TOUCH_EDGE_BUTTON_SIZE.y * 0.5)
	else:
		normal.corner_radius_top_left = int(TOUCH_EDGE_BUTTON_SIZE.y * 0.5)
		normal.corner_radius_bottom_left = int(TOUCH_EDGE_BUTTON_SIZE.y * 0.5)
		normal.corner_radius_top_right = 0
		normal.corner_radius_bottom_right = 0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.16, 0.22, 0.96)
	hover.border_color = Color(0.68, 0.76, 0.88, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.14, 0.2, 0.98)
	pressed.border_color = Color(0.58, 0.7, 0.88, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 42)


func _update_touch_toggle_button() -> void:
	if _touch_toggle_dock == null or not is_instance_valid(_touch_toggle_dock):
		return
	_update_touch_toggle_button_layout()
	_touch_toggle_dock.visible = _touch_mode_enabled and not _is_console_control_visible()
	if _touch_command_palette_button != null and is_instance_valid(_touch_command_palette_button):
		_touch_command_palette_button.tooltip_text = "Open command palette"
	if _touch_full_log_button != null and is_instance_valid(_touch_full_log_button):
		var command_entry_open := _display != null and _display.is_command_entry_mode()
		_touch_full_log_button.tooltip_text = "Open full log" if command_entry_open or not _is_console_control_visible() else "Hide full log"


func _on_touch_edge_button_gui_input(event: InputEvent, action: String) -> void:
	if not _touch_mode_enabled:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		var pointer_position := _get_touch_toggle_event_position(event)
		if mouse_event.pressed:
			_begin_touch_toggle_drag(pointer_position, action, -1)
		elif _touch_toggle_drag_active and _touch_toggle_drag_action == action:
			var should_activate := not _touch_toggle_drag_moved
			_end_touch_toggle_drag(pointer_position)
			if should_activate:
				_activate_touch_edge_button(action)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _touch_toggle_drag_active and _touch_toggle_drag_action == action and _touch_toggle_drag_touch_index == -1:
			_update_touch_toggle_drag(_get_touch_toggle_event_position(event))
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		var pointer_position := _get_touch_toggle_event_position(event)
		if touch_event.pressed:
			_begin_touch_toggle_drag(pointer_position, action, touch_event.index)
		elif _touch_toggle_drag_active and _touch_toggle_drag_action == action and _touch_toggle_drag_touch_index == touch_event.index:
			var should_activate := not _touch_toggle_drag_moved
			_end_touch_toggle_drag(pointer_position)
			if should_activate:
				_activate_touch_edge_button(action)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if _touch_toggle_drag_active and _touch_toggle_drag_action == action and _touch_toggle_drag_touch_index == drag_event.index:
			_update_touch_toggle_drag(_get_touch_toggle_event_position(event))
			get_viewport().set_input_as_handled()


func _get_touch_toggle_event_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).position
	return get_viewport().get_mouse_position()


func _begin_touch_toggle_drag(pointer_position: Vector2, action: String, touch_index: int) -> void:
	if _touch_toggle_dock == null or not is_instance_valid(_touch_toggle_dock):
		return
	_touch_toggle_drag_active = true
	_touch_toggle_drag_moved = false
	_touch_toggle_drag_action = action
	_touch_toggle_drag_touch_index = touch_index
	_touch_toggle_drag_start_position = pointer_position
	_touch_toggle_drag_pointer_offset = pointer_position - _touch_toggle_dock.global_position
	_touch_toggle_drag_start_edge = _touch_toggle_edge
	_touch_toggle_drag_dock_x = _touch_toggle_dock.position.x


func _update_touch_toggle_drag(pointer_position: Vector2) -> void:
	if not _touch_toggle_drag_active:
		return
	if pointer_position.distance_to(_touch_toggle_drag_start_position) >= TOUCH_TOGGLE_DRAG_THRESHOLD:
		_touch_toggle_drag_moved = true
	if not _touch_toggle_drag_moved:
		return

	var viewport_size := _get_touch_toggle_viewport_size()
	if viewport_size.x > 0.0:
		_touch_toggle_drag_dock_x = pointer_position.x - _touch_toggle_drag_pointer_offset.x
	var dock_height := TOUCH_EDGE_BUTTON_SIZE.y * 2.0 + TOUCH_EDGE_BUTTON_GAP
	_touch_toggle_center_y = pointer_position.y - _touch_toggle_drag_pointer_offset.y + dock_height * 0.5
	_update_touch_toggle_button_layout()


func _end_touch_toggle_drag(pointer_position: Vector2) -> void:
	var did_drag := _touch_toggle_drag_moved
	if did_drag:
		_update_touch_toggle_drag(pointer_position)
		var viewport_size := _get_touch_toggle_viewport_size()
		if viewport_size.x > 0.0:
			var dock_width := TOUCH_EDGE_BUTTON_SIZE.x
			var dock_center_x := clampf(_touch_toggle_drag_dock_x, 0.0, maxf(0.0, viewport_size.x - dock_width)) + dock_width * 0.5
			_touch_toggle_edge = TOUCH_TOGGLE_EDGE_LEFT if dock_center_x < viewport_size.x * 0.5 else TOUCH_TOGGLE_EDGE_RIGHT
	_touch_toggle_drag_active = false
	_touch_toggle_drag_moved = false
	_touch_toggle_drag_action = ""
	_touch_toggle_drag_touch_index = -1
	_touch_toggle_drag_dock_x = -1.0
	_update_touch_toggle_button_layout()
	if did_drag:
		_save_touch_toggle_settings()


func _activate_touch_edge_button(action: String) -> void:
	match action:
		TOUCH_TOGGLE_ACTION_COMMAND:
			_on_touch_command_palette_button_pressed()
		TOUCH_TOGGLE_ACTION_LOG:
			_on_touch_full_log_button_pressed()


func _on_touch_command_palette_button_pressed() -> void:
	if not _touch_mode_enabled:
		return
	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH)
	_open_command_entry_view(false)
	_update_touch_toggle_button()


func _on_touch_full_log_button_pressed() -> void:
	if not _touch_mode_enabled:
		return
	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH)
	if _display and _display.is_command_entry_mode():
		_display.hide_command_entry_mode()
		_restore_full_console_after_command_entry = false
		if control != null and is_instance_valid(control):
			control.visible = true
			if not _touch_mode_enabled and line_edit != null and is_instance_valid(line_edit):
				line_edit.grab_focus()
		_update_touch_toggle_button()
		return
	if _is_console_control_visible():
		toggle_console(false)
		return
	if control == null or not is_instance_valid(control) or not enabled:
		return
	control.visible = true
	_clear_ingame_popups()
	_restore_full_console_after_command_entry = false
	was_paused_already = get_tree().paused
	get_tree().paused = was_paused_already || pause_enabled
	console_opened.emit()
	_sync_pinned_overlay_suppression()
	_update_touch_toggle_button()


func _set_console_setting_value(setting_name: String, value: bool) -> void:
	match setting_name:
		"collapse_duplicates":
			_collapse_duplicates = value
		"wrap_text":
			_wrap_text = value
		"truncate_multiline":
			_truncate_multiline = value
		"touch_mode":
			_touch_mode_enabled = value

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


func _cycle_performance_pin_mode(reverse: bool = false) -> void:
	if reverse:
		_set_performance_pin_mode(_previous_performance_pin_mode(_performance_pin_mode))
	else:
		_set_performance_pin_mode(_next_performance_pin_mode(_performance_pin_mode))


func _next_performance_pin_mode(mode: String) -> String:
	match _normalize_performance_pin_mode(mode):
		PERFORMANCE_MODE_HIDDEN:
			return PERFORMANCE_MODE_FPS
		PERFORMANCE_MODE_FPS:
			return PERFORMANCE_MODE_OVERVIEW
		PERFORMANCE_MODE_OVERVIEW:
			# Detailed only adds allocation graphs; without either source it repeats overview.
			if has_performance_allocation_data():
				return PERFORMANCE_MODE_DETAILED
			return PERFORMANCE_MODE_HIDDEN
		PERFORMANCE_MODE_DETAILED:
			return PERFORMANCE_MODE_HIDDEN
	return PERFORMANCE_MODE_HIDDEN


func _previous_performance_pin_mode(mode: String) -> String:
	match _normalize_performance_pin_mode(mode):
		PERFORMANCE_MODE_FPS:
			return PERFORMANCE_MODE_HIDDEN
		PERFORMANCE_MODE_OVERVIEW:
			return PERFORMANCE_MODE_FPS
		PERFORMANCE_MODE_DETAILED:
			return PERFORMANCE_MODE_OVERVIEW
		PERFORMANCE_MODE_HIDDEN:
			# Mirrors _next_performance_pin_mode's overview/detailed skip in reverse.
			if has_performance_allocation_data():
				return PERFORMANCE_MODE_DETAILED
			return PERFORMANCE_MODE_OVERVIEW
	return PERFORMANCE_MODE_HIDDEN


func _set_performance_pin_mode(mode: String, save: bool = true) -> void:
	var normalized_mode := _normalize_performance_pin_mode(mode)
	_performance_pin_mode = normalized_mode

	var active_display := _get_active_display()
	if active_display and active_display.has_method("set_pinned_display_variables_visible"):
		active_display.set_pinned_display_variables_visible(true)

	match normalized_mode:
		PERFORMANCE_MODE_FPS:
			set_display_variable_pinned(_PERFORMANCE_FPS_PATH, true, PIN_CORNER_TOP_RIGHT)
			set_display_variable_pinned(_PERFORMANCE_OVERVIEW_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_CPU_SOURCES_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_GPU_SOURCES_WIDGET_PATH, false)
		PERFORMANCE_MODE_OVERVIEW:
			set_display_variable_pinned(_PERFORMANCE_FPS_PATH, false)
			set_display_variable_pinned(_PERFORMANCE_OVERVIEW_WIDGET_PATH, true, PIN_CORNER_TOP_RIGHT)
			set_display_variable_transiently_pinned(_PERFORMANCE_CPU_SOURCES_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_GPU_SOURCES_WIDGET_PATH, false)
		PERFORMANCE_MODE_DETAILED:
			set_display_variable_pinned(_PERFORMANCE_FPS_PATH, false)
			set_display_variable_pinned(_PERFORMANCE_OVERVIEW_WIDGET_PATH, true, PIN_CORNER_TOP_RIGHT)
			set_display_variable_transiently_pinned(_PERFORMANCE_CPU_SOURCES_WIDGET_PATH, _should_pin_cpu_performance_sources(), PIN_CORNER_TOP_RIGHT)
			set_display_variable_transiently_pinned(_PERFORMANCE_GPU_SOURCES_WIDGET_PATH, _should_pin_gpu_performance_sources(), PIN_CORNER_TOP_RIGHT)
		PERFORMANCE_MODE_HIDDEN:
			set_display_variable_pinned(_PERFORMANCE_FPS_PATH, false)
			set_display_variable_pinned(_PERFORMANCE_OVERVIEW_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_CPU_SOURCES_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_GPU_SOURCES_WIDGET_PATH, false)
		_:
			set_display_variable_pinned(_PERFORMANCE_FPS_PATH, false)
			set_display_variable_pinned(_PERFORMANCE_OVERVIEW_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_CPU_SOURCES_WIDGET_PATH, false)
			set_display_variable_transiently_pinned(_PERFORMANCE_GPU_SOURCES_WIDGET_PATH, false)

	if save:
		_save_performance_pin_mode()


func _apply_saved_performance_pin_mode() -> void:
	var mode := _performance_pin_mode
	if mode == PERFORMANCE_MODE_DETAILED and not has_performance_allocation_data():
		mode = PERFORMANCE_MODE_OVERVIEW
	_set_performance_pin_mode(mode, false)


func _normalize_performance_pin_mode(mode: String) -> String:
	var normalized_mode := mode.strip_edges().to_lower()
	if normalized_mode in [PERFORMANCE_MODE_FPS, PERFORMANCE_MODE_OVERVIEW, PERFORMANCE_MODE_DETAILED, PERFORMANCE_MODE_HIDDEN]:
		return normalized_mode
	return PERFORMANCE_MODE_HIDDEN


func _save_performance_pin_mode() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value(PERFORMANCE_SETTINGS_SECTION, PERFORMANCE_SETTINGS_KEY_MODE, _performance_pin_mode)
	config.set_value(PERFORMANCE_SETTINGS_SECTION, PERFORMANCE_SETTINGS_KEY_GRAPH_TIME_RANGE, _performance_graph_time_range_sec)
	config.set_value(PERFORMANCE_SETTINGS_SECTION, PERFORMANCE_SETTINGS_KEY_CPU_SOURCE_MODE, _performance_cpu_source_mode)
	config.set_value(PERFORMANCE_SETTINGS_SECTION, PERFORMANCE_SETTINGS_KEY_SOURCE_UPDATE_RATE_HZ, _performance_source_update_rate_hz)
	config.save(SETTINGS_FILE)


func _load_performance_pin_mode() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		_performance_pin_mode = PERFORMANCE_MODE_FPS
		return
	_performance_pin_mode = _normalize_performance_pin_mode(str(config.get_value(
		PERFORMANCE_SETTINGS_SECTION,
		PERFORMANCE_SETTINGS_KEY_MODE,
		PERFORMANCE_MODE_FPS
	)))
	_performance_graph_time_range_sec = _normalize_performance_graph_time_range(float(config.get_value(
		PERFORMANCE_SETTINGS_SECTION,
		PERFORMANCE_SETTINGS_KEY_GRAPH_TIME_RANGE,
		_performance_graph_time_range_sec
	)))
	_performance_cpu_source_mode = _normalize_performance_source_cpu_mode(str(config.get_value(
		PERFORMANCE_SETTINGS_SECTION,
		PERFORMANCE_SETTINGS_KEY_CPU_SOURCE_MODE,
		PERFORMANCE_CPU_SOURCE_MODE_RENDER
	)))
	_performance_source_update_rate_hz = _normalize_performance_source_update_rate_hz(float(config.get_value(
		PERFORMANCE_SETTINGS_SECTION,
		PERFORMANCE_SETTINGS_KEY_SOURCE_UPDATE_RATE_HZ,
		PERFORMANCE_SOURCE_UPDATE_RATE_DEFAULT_HZ
	)))


func _toggle_all_pins_visibility() -> void:
	var live_displays := _get_live_displays()
	if live_displays.is_empty():
		return

	var active_display := _get_active_display()
	var next_visible := true
	if active_display and active_display.has_method("toggle_pinned_display_variables_visible"):
		next_visible = bool(active_display.toggle_pinned_display_variables_visible())
	else:
		var first_display := live_displays[0]
		if first_display.has_method("is_pinned_display_variables_visible"):
			next_visible = not bool(first_display.is_pinned_display_variables_visible())

	for display in live_displays:
		if display == active_display:
			continue
		if display.has_method("set_pinned_display_variables_visible"):
			display.set_pinned_display_variables_visible(next_visible)


func _set_setting_truncate_multiline(value: bool) -> void:
	_set_console_setting_value("truncate_multiline", value)


func _get_render_scale_setting(target: String, input_method: String) -> float:
	if _display:
		return _display.get_render_scale_percent(target, input_method)
	var normalized_method := input_method.strip_edges().to_lower()
	var normalized_target := target.strip_edges().to_lower()
	if normalized_method == LogotDisplay.INPUT_METHOD_CONTROLLER:
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_LOG:
			return LogotDisplay.DEFAULT_RENDER_SCALE_CONTROLLER_LOG
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE:
			return LogotDisplay.DEFAULT_RENDER_SCALE_CONTROLLER_COMMAND_PALETTE
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES:
			return LogotDisplay.DEFAULT_RENDER_SCALE_CONTROLLER_PINNED_VARIABLES
	if normalized_method == LogotDisplay.INPUT_METHOD_TOUCH:
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_LOG:
			return LogotDisplay.DEFAULT_RENDER_SCALE_TOUCH_LOG
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE:
			return LogotDisplay.DEFAULT_RENDER_SCALE_TOUCH_COMMAND_PALETTE
		if normalized_target == LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES:
			return LogotDisplay.DEFAULT_RENDER_SCALE_TOUCH_PINNED_VARIABLES
	return LogotDisplay.DEFAULT_RENDER_SCALE_KEYBOARD


func _set_render_scale_setting(target: String, input_method: String, value: float) -> void:
	if _display:
		_display.set_render_scale_percent(target, input_method, value)


func _get_render_scale_options() -> Array:
	return [50.0, 75.0, 100.0, 110.0, 120.0, 125.0, 150.0, 175.0, 200.0]


func _register_render_scale_setting_command(command_name: String, target: String, input_method: String, description: String) -> void:
	add_setget_command(
		command_name,
		func(value: float) -> void:
			_set_render_scale_setting(target, input_method, value),
		func() -> float:
			return _get_render_scale_setting(target, input_method),
		description,
		_get_render_scale_options,
		Callable(),
	)


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
	add_setget_command(
		"console/settings/touch_mode",
		_set_setting_touch_mode,
		_get_setting_touch_mode,
		"Set whether touch mode is enabled."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/log/keyboard",
		LogotDisplay.RENDER_SCALE_TARGET_LOG,
		LogotDisplay.INPUT_METHOD_KEYBOARD,
		"Set the keyboard log render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/log/controller",
		LogotDisplay.RENDER_SCALE_TARGET_LOG,
		LogotDisplay.INPUT_METHOD_CONTROLLER,
		"Set the controller log render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/log/touch",
		LogotDisplay.RENDER_SCALE_TARGET_LOG,
		LogotDisplay.INPUT_METHOD_TOUCH,
		"Set the touch log render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/command_palette/keyboard",
		LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE,
		LogotDisplay.INPUT_METHOD_KEYBOARD,
		"Set the keyboard command palette render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/command_palette/controller",
		LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE,
		LogotDisplay.INPUT_METHOD_CONTROLLER,
		"Set the controller command palette render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/command_palette/touch",
		LogotDisplay.RENDER_SCALE_TARGET_COMMAND_PALETTE,
		LogotDisplay.INPUT_METHOD_TOUCH,
		"Set the touch command palette render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/pinned_variables/keyboard",
		LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES,
		LogotDisplay.INPUT_METHOD_KEYBOARD,
		"Set the keyboard pinned variables render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/pinned_variables/controller",
		LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES,
		LogotDisplay.INPUT_METHOD_CONTROLLER,
		"Set the controller pinned variables render scale percentage."
	)
	_register_render_scale_setting_command(
		"console/settings/render_scale/pinned_variables/touch",
		LogotDisplay.RENDER_SCALE_TARGET_PINNED_VARIABLES,
		LogotDisplay.INPUT_METHOD_TOUCH,
		"Set the touch pinned variables render scale percentage."
	)


func _register_ingame_popup_commands() -> void:
	add_command(
		INGAME_POPUP_COMMAND_PATH,
		_command_ingame_popups_summary,
		[],
		0,
		"Configure in-game popup behavior."
	)
	add_command(
		INGAME_POPUP_LEVELS_COMMAND_PATH,
		_command_ingame_popup_levels_summary,
		[],
		0,
		"Configure which log levels appear as in-game popups."
	)
	add_command(
		INGAME_POPUP_LEVELS_DISABLE_ALL_COMMAND_PATH,
		_disable_all_ingame_popup_levels,
		[],
		0,
		"Disable in-game popups for every log level."
	)
	add_command(
		INGAME_POPUP_LEVELS_COPY_CONSOLE_COMMAND_PATH,
		_copy_ingame_popup_levels_from_console,
		[],
		0,
		"Copy the main console's shown log levels into the custom popup filter."
	)
	add_setget_command(
		INGAME_POPUP_LEVELS_MIRROR_MAIN_CONSOLE_COMMAND_PATH,
		_set_ingame_popup_mirror_main_console,
		_get_ingame_popup_mirror_main_console,
		"Set whether popups mirror the main console's log level filter instead of using custom popup log levels."
	)
	add_setget_command(
		INGAME_POPUP_FADE_TIME_COMMAND_PATH,
		func(value: String) -> void:
			_set_ingame_popup_fade_time_setting(value),
		_get_ingame_popup_fade_time_setting_value,
		"Set how long popups stay visible in seconds, or 'off' to disable auto-fading.",
		_get_ingame_popup_fade_time_options
	)

	for level in INGAME_POPUP_LEVELS:
		var command_path := _get_ingame_popup_level_command_path(level)
		var level_label := _get_ingame_popup_level_display_name(level)
		add_command(
			command_path,
			Callable(self, "_toggle_ingame_popup_level").bind(level),
			[],
			0,
			"Toggle the custom in-game popup filter for %s logs." % level_label
		)
		add_display_variable(
			command_path,
			Callable(self, "_get_ingame_popup_level_indicator").bind(level),
			Callable(self, "_get_ingame_popup_level_indicator_color").bind(level)
		)


func _register_dev_commands() -> void:
	add_command(
		_CURRENT_GIT_BRANCH_COMMAND_PATH,
		_command_current_git_branch,
		[],
		0,
		"Prints the current git branch name."
	)
	add_display_variable(_CURRENT_GIT_BRANCH_COMMAND_PATH, _get_current_git_branch, Callable(), _get_current_git_branch_display_items)
	_register_performance_commands()


func _register_performance_commands() -> void:
	_ensure_performance_monitor_initialized()
	add_command(
		_PERFORMANCE_FPS_PATH,
		_command_performance_fps,
		[],
		0,
		"Prints the current FPS."
	)
	add_display_variable(
		_PERFORMANCE_FPS_PATH,
		_get_performance_fps_text,
		_get_performance_fps_color,
		Callable(),
		true,
		"",
		0,
		self,
		&"performance_fps_changed"
	)
	add_widget(
		_PERFORMANCE_OVERVIEW_WIDGET_PATH,
		PERFORMANCE_OVERVIEW_WIDGET_SCENE,
		"Performance Overview: FPS and aggregate frame timing graphs.",
		"",
		0,
		Vector2(210.0, 170.0),
		"Performance Overview"
	)
	add_widget(
		_PERFORMANCE_CPU_SOURCES_WIDGET_PATH,
		PERFORMANCE_SOURCE_GRAPH_WIDGET_SCENE,
		"Shows the top CPU allocation buckets and their frame-time history.",
		"",
		0,
		Vector2(210.0, 226.0),
		"CPU Allocation"
	)
	add_widget(
		_PERFORMANCE_GPU_SOURCES_WIDGET_PATH,
		PERFORMANCE_SOURCE_GRAPH_WIDGET_SCENE,
		"Shows the top GPU allocation buckets and their frame-time history.",
		"",
		0,
		Vector2(210.0, 226.0),
		"GPU Allocation"
	)
	add_setget_command(
		_PERFORMANCE_TIME_RANGE_PATH,
		_set_performance_graph_time_range,
		_get_performance_graph_time_range,
		"Set the performance graph time range.",
		_get_performance_graph_time_range_options,
		Callable()
	)
	add_setget_command(
		_PERFORMANCE_CPU_SOURCE_MODE_PATH,
		_set_performance_source_cpu_mode,
		get_performance_source_cpu_mode,
		"Choose render CPU, whole-frame CPU, or both allocation panels.",
		_get_performance_source_cpu_mode_options,
		Callable()
	)
	add_setget_command(
		_PERFORMANCE_SOURCE_UPDATE_SPEED_PATH,
		_set_performance_source_update_rate_hz,
		get_performance_source_update_rate_hz,
		"Set allocation widget update speed in refreshes per second.",
		_get_performance_source_update_rate_options,
		Callable()
	)
	add_command(
		_PERFORMANCE_SOURCE_SNAPSHOT_PATH,
		_command_performance_source_snapshot,
		["name"],
		0,
		"Save the current CPU/GPU allocation breakdown and visible history as JSON."
	)


func _command_performance_fps() -> void:
	print_line("Current FPS: %s" % _get_performance_fps_text())


func _set_performance_graph_time_range(value: Variant) -> void:
	_performance_graph_time_range_sec = _normalize_performance_graph_time_range(float(value))
	_trim_performance_source_history_to_time_range()
	_save_performance_pin_mode()


func _get_performance_graph_time_range() -> float:
	return _performance_graph_time_range_sec


func _get_performance_graph_time_range_options() -> Array:
	return [
		{"label": "2s", "value": 2.0},
		{"label": "5s", "value": 5.0},
		{"label": "10s", "value": 10.0},
		{"label": "30s", "value": 30.0},
		{"label": "60s", "value": 60.0},
		{"label": "All", "value": PERFORMANCE_GRAPH_TIME_RANGE_ALL},
	]


func _normalize_performance_graph_time_range(value: float) -> float:
	if value <= 0.0:
		return PERFORMANCE_GRAPH_TIME_RANGE_ALL
	return clampf(value, 1.0, 300.0)


func _set_performance_source_cpu_mode(value: Variant) -> void:
	_performance_cpu_source_mode = _normalize_performance_source_cpu_mode(str(value))
	_save_performance_pin_mode()
	_update_performance_source_capture_requests()


func get_performance_source_cpu_mode() -> String:
	return _performance_cpu_source_mode


func _normalize_performance_source_cpu_mode(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized in [
		PERFORMANCE_CPU_SOURCE_MODE_RENDER,
		PERFORMANCE_CPU_SOURCE_MODE_WHOLE,
		PERFORMANCE_CPU_SOURCE_MODE_BOTH,
	]:
		return normalized
	return PERFORMANCE_CPU_SOURCE_MODE_RENDER


func _get_performance_source_cpu_mode_options() -> Array:
	return [
		{"label": "Render CPU", "value": PERFORMANCE_CPU_SOURCE_MODE_RENDER},
		{"label": "Whole Frame", "value": PERFORMANCE_CPU_SOURCE_MODE_WHOLE},
		{"label": "Both", "value": PERFORMANCE_CPU_SOURCE_MODE_BOTH},
	]


func _set_performance_source_update_rate_hz(value: Variant) -> void:
	_performance_source_update_rate_hz = _normalize_performance_source_update_rate_hz(float(value))
	_save_performance_pin_mode()


func get_performance_source_update_rate_hz() -> float:
	return _performance_source_update_rate_hz


func get_performance_source_update_interval_sec() -> float:
	return 1.0 / maxf(1.0, _performance_source_update_rate_hz)


func _normalize_performance_source_update_rate_hz(value: float) -> float:
	return clampf(value, 1.0, 60.0)


func _get_performance_source_update_rate_options() -> Array:
	return [
		{"label": "1 Hz", "value": 1.0},
		{"label": "2 Hz", "value": 2.0},
		{"label": "4 Hz", "value": 4.0},
		{"label": "10 Hz", "value": 10.0},
		{"label": "30 Hz", "value": 30.0},
		{"label": "60 Hz", "value": 60.0},
	]


func _ensure_performance_monitor_initialized() -> void:
	if _performance_monitor_initialized:
		return
	_performance_monitor_initialized = true
	_performance_frame_history_total.resize(PERFORMANCE_HISTORY_NUM_FRAMES)
	_performance_frame_history_total.fill(_performance_frametime_msec)
	_performance_frame_history_cpu.resize(PERFORMANCE_HISTORY_NUM_FRAMES)
	_performance_frame_history_cpu.fill(_performance_frametime_cpu_msec)
	_performance_frame_history_gpu.resize(PERFORMANCE_HISTORY_NUM_FRAMES)
	_performance_frame_history_gpu.fill(_performance_frametime_gpu_msec)
	_performance_fps_history.resize(PERFORMANCE_HISTORY_NUM_FRAMES)
	_performance_fps_history.fill(_performance_frames_per_second)
	_performance_source_monitor = PerformanceSourceMonitorScript.new()
	_performance_source_monitor.call("initialize")

	# Match DebugMenu's non-linear FPS color mapping:
	# red = 10 FPS, yellow = 60 FPS, green = 110 FPS, cyan = 160 FPS.
	_performance_frame_time_gradient.set_color(0, Color8(239, 68, 68))
	_performance_frame_time_gradient.set_color(1, Color8(56, 189, 248))
	_performance_frame_time_gradient.add_point(0.3333, Color8(250, 204, 21))
	_performance_frame_time_gradient.add_point(0.6667, Color8(128, 226, 95))
	_update_performance_fps_display_cache(false)

	if not Engine.is_editor_hint() and get_viewport() != null:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _update_performance_monitor(delta: float) -> void:
	_ensure_performance_monitor_initialized()

	var current_tick := Time.get_ticks_usec()
	var frame_time_msec := maxf(delta * 1000.0, 0.001)
	if _performance_last_tick_usec > 0:
		frame_time_msec = maxf(float(current_tick - _performance_last_tick_usec) / 1000.0, 0.001)
	_performance_last_tick_usec = current_tick
	_performance_frametime_msec = frame_time_msec

	_performance_frame_history_total.push_back(frame_time_msec)
	if _performance_frame_history_total.size() > PERFORMANCE_HISTORY_NUM_FRAMES:
		_performance_frame_history_total.pop_front()

	_update_performance_source_capture_requests()
	var source_totals: Dictionary = _performance_source_monitor.call("drain_bridge_frames", frame_time_msec) as Dictionary

	var viewport_rid := get_viewport().get_viewport_rid()
	var measured_cpu_msec := RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu()
	_performance_frametime_cpu_msec = float(source_totals.get("cpu_ms", measured_cpu_msec))
	_performance_frame_history_cpu.push_back(_performance_frametime_cpu_msec)
	if _performance_frame_history_cpu.size() > PERFORMANCE_HISTORY_NUM_FRAMES:
		_performance_frame_history_cpu.pop_front()

	var measured_gpu_msec := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	_performance_frametime_gpu_msec = float(source_totals.get("gpu_ms", measured_gpu_msec))
	_performance_frame_history_gpu.push_back(_performance_frametime_gpu_msec)
	if _performance_frame_history_gpu.size() > PERFORMANCE_HISTORY_NUM_FRAMES:
		_performance_frame_history_gpu.pop_front()

	var fps_frametime_avg := _avg_last_float(_performance_frame_history_total, PERFORMANCE_FPS_NUM_FRAMES)
	_performance_frames_per_second = 1000.0 / fps_frametime_avg if fps_frametime_avg > 0.0 else 0.0
	_performance_fps_history.push_back(_performance_frames_per_second)
	if _performance_fps_history.size() > PERFORMANCE_HISTORY_NUM_FRAMES:
		_performance_fps_history.pop_front()
	_trim_performance_source_history_to_time_range()

	_performance_fps_signal_accum_sec += delta
	if _performance_fps_signal_accum_sec >= 1.0:
		_performance_fps_signal_accum_sec = fmod(_performance_fps_signal_accum_sec, 1.0)
		_update_performance_fps_display_cache(true)

	_update_pending_performance_source_snapshot()


func _avg_last_float(values: Array[float], num_values: int) -> float:
	if values.is_empty():
		return 0.0
	var count := mini(num_values, values.size())
	var start_index := values.size() - count
	var sum := 0.0
	for i in range(start_index, values.size()):
		sum += values[i]
	return sum / float(count)


func request_performance_source_collection(widget_kind: String, cpu_mode: String = "") -> void:
	_ensure_performance_monitor_initialized()
	var lease_until := int(Engine.get_process_frames()) + 2
	if widget_kind == "gpu":
		if can_collect_gpu_performance_sources():
			_performance_source_render_lease_frame = maxi(_performance_source_render_lease_frame, lease_until)
	else:
		var normalized_mode := _normalize_performance_source_cpu_mode(cpu_mode if not cpu_mode.is_empty() else _performance_cpu_source_mode)
		if normalized_mode in [PERFORMANCE_CPU_SOURCE_MODE_RENDER, PERFORMANCE_CPU_SOURCE_MODE_BOTH]:
			_performance_source_render_lease_frame = maxi(_performance_source_render_lease_frame, lease_until)
		if normalized_mode in [PERFORMANCE_CPU_SOURCE_MODE_WHOLE, PERFORMANCE_CPU_SOURCE_MODE_BOTH]:
			_performance_source_script_lease_frame = maxi(_performance_source_script_lease_frame, lease_until)
	_update_performance_source_capture_requests()


func _trim_performance_source_history_to_time_range() -> void:
	if _performance_source_monitor == null:
		return
	_performance_source_monitor.call("trim_history_limit", _get_performance_source_visible_sample_count())


func _update_performance_source_capture_requests() -> void:
	if _performance_source_monitor == null:
		return
	var current_frame := int(Engine.get_process_frames())
	var render_requested := current_frame <= _performance_source_render_lease_frame
	var scripts_requested := current_frame <= _performance_source_script_lease_frame
	if _performance_source_snapshot_pending:
		render_requested = true
		scripts_requested = true
	_performance_source_monitor.call("set_capture_enabled", render_requested, scripts_requested)


func is_performance_source_test_mode() -> bool:
	return _performance_source_monitor != null and bool(_performance_source_monitor.call("is_test_mode"))


func can_collect_gpu_performance_sources() -> bool:
	if RenderingServer.get_current_rendering_driver_name() == "metal":
		return false
	if _performance_source_monitor == null:
		return true
	var status: Dictionary = _performance_source_monitor.call("refresh_status") as Dictionary
	if bool(status.get("render_profile_seen", false)) and not bool(status.get("gpu_timestamps_available", false)):
		return false
	return true


func has_performance_allocation_data() -> bool:
	return _should_pin_cpu_performance_sources() or _should_pin_gpu_performance_sources()


func _should_pin_cpu_performance_sources() -> bool:
	_ensure_performance_monitor_initialized()
	if _performance_source_monitor == null:
		return false
	if bool(_performance_source_monitor.call("is_test_mode")):
		return not ((_performance_source_monitor.call("get_current", "render_cpu") as Dictionary).is_empty()
			and (_performance_source_monitor.call("get_current", "whole_cpu") as Dictionary).is_empty())
	return bool(_performance_source_monitor.call("is_available"))


func _should_pin_gpu_performance_sources() -> bool:
	_ensure_performance_monitor_initialized()
	if _performance_source_monitor != null and bool(_performance_source_monitor.call("is_test_mode")):
		return not (_performance_source_monitor.call("get_current", "gpu") as Dictionary).is_empty()
	if _performance_source_monitor != null and not bool(_performance_source_monitor.call("is_available")):
		return false
	return can_collect_gpu_performance_sources()


func get_performance_source_widget_snapshot(kind: String) -> Dictionary:
	_ensure_performance_monitor_initialized()
	var visible_sample_count := _get_performance_source_visible_sample_count()
	var source_snapshot: Dictionary = _performance_source_monitor.call(
		"get_widget_snapshot",
		kind,
		visible_sample_count,
		_performance_graph_time_range_sec
	) as Dictionary
	var current: Dictionary = source_snapshot.get("current", {}) as Dictionary
	var available := bool(_performance_source_monitor.call("is_available"))
	var message := "Waiting for profiler samples…"
	if not available:
		message = str(_performance_source_monitor.call("get_error"))
	elif current.is_empty():
		var status: Dictionary = _performance_source_monitor.call("refresh_status") as Dictionary
		if kind == "gpu" and (not can_collect_gpu_performance_sources() or (bool(status.get("render_profile_seen", false)) and not bool(status.get("gpu_timestamps_available", false)))):
			message = _get_gpu_timestamp_unavailable_message()
		else:
			message = "Collecting profiler samples…"
	return {
		"available": available,
		"message": message,
		"current": current,
		"history": source_snapshot.get("history", []),
		"graph_min_fps": PERFORMANCE_GRAPH_MIN_FPS,
		"graph_max_fps": PERFORMANCE_GRAPH_MAX_FPS,
		"graph_time_range_sec": float(source_snapshot.get("graph_time_range_sec", _performance_graph_time_range_sec)),
		"visible_sample_count": visible_sample_count,
	}


func _get_performance_source_visible_sample_count() -> int:
	if _performance_graph_time_range_sec <= 0.0:
		return 0
	return maxi(2, roundi(_performance_graph_time_range_sec * maxf(1.0, _performance_frames_per_second)))


func _get_gpu_timestamp_unavailable_message() -> String:
	var driver := RenderingServer.get_current_rendering_driver_name()
	var method := RenderingServer.get_current_rendering_method()
	if driver == "metal":
		return "No per-pass GPU timestamps\nGodot 4.7 Metal limitation\nUse Vulkan on Windows/Linux"
	return "GPU timestamps unavailable for %s/%s" % [method, driver]


func get_performance_source_snapshot(include_history: bool = true) -> Dictionary:
	_ensure_performance_monitor_initialized()
	return _performance_source_monitor.call(
		"get_snapshot",
		include_history,
		_get_performance_source_visible_sample_count(),
		_performance_cpu_source_mode,
		_performance_graph_time_range_sec
	) as Dictionary


func save_performance_source_snapshot(name: String = "") -> String:
	var global_directory := ProjectSettings.globalize_path(PERFORMANCE_SOURCE_SNAPSHOT_DIR)
	var directory_error := DirAccess.make_dir_recursive_absolute(global_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Failed to create performance snapshot directory: %s" % error_string(directory_error))
		return ""
	var timestamp := Time.get_datetime_string_from_system(false, true).replace("-", "").replace(":", "").replace(" ", "-")
	var safe_name := _sanitize_performance_snapshot_name(name)
	var filename := timestamp + ("-" + safe_name if not safe_name.is_empty() else "") + ".json"
	var path := PERFORMANCE_SOURCE_SNAPSHOT_DIR.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open performance snapshot: %s" % path)
		return ""
	file.store_string(JSON.stringify(get_performance_source_snapshot(true), "\t", false))
	file.close()
	return path


func _sanitize_performance_snapshot_name(value: String) -> String:
	var result := ""
	for character in value.strip_edges().to_lower():
		if character in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			result += character
		elif not result.ends_with("-"):
			result += "-"
	return result.trim_prefix("-").trim_suffix("-").left(64)


func _command_performance_source_snapshot(name: String = "") -> void:
	if _performance_source_snapshot_pending:
		print_line("A performance source snapshot is already being collected.")
		return
	_ensure_performance_monitor_initialized()
	_performance_source_snapshot_pending = true
	_performance_source_snapshot_name = name
	_performance_source_snapshot_deadline_msec = Time.get_ticks_msec() + 2000
	_update_performance_source_capture_requests()
	print_line("Collecting CPU/GPU source snapshot…")


func _update_pending_performance_source_snapshot() -> void:
	if not _performance_source_snapshot_pending:
		return
	var has_render := not (_performance_source_monitor.call("get_current", "render_cpu") as Dictionary).is_empty()
	var has_gpu := not (_performance_source_monitor.call("get_current", "gpu") as Dictionary).is_empty()
	var has_whole := not (_performance_source_monitor.call("get_current", "whole_cpu") as Dictionary).is_empty()
	var timed_out := Time.get_ticks_msec() >= _performance_source_snapshot_deadline_msec
	if not timed_out and not (has_render and has_gpu and has_whole):
		return
	var path := save_performance_source_snapshot(_performance_source_snapshot_name)
	_performance_source_snapshot_pending = false
	_performance_source_snapshot_name = ""
	_performance_source_snapshot_deadline_msec = 0
	_update_performance_source_capture_requests()
	if path.is_empty():
		print_line("Failed to save performance source snapshot.")
	elif timed_out:
		print_line("Saved partial performance source snapshot after timeout: %s" % path)
	else:
		print_line("Saved performance source snapshot: %s" % path)


func set_performance_source_test_histories(render_cpu: Array, gpu: Array, whole_cpu: Array = []) -> void:
	_ensure_performance_monitor_initialized()
	_performance_source_monitor.call("set_test_histories", render_cpu, gpu, whole_cpu)


func clear_performance_source_test_histories() -> void:
	if _performance_source_monitor != null:
		_performance_source_monitor.call("clear_test_mode")


func _get_performance_fps_text() -> String:
	_ensure_performance_monitor_initialized()
	return _performance_fps_display_text


func _get_performance_fps_color() -> Color:
	_ensure_performance_monitor_initialized()
	return _performance_fps_display_color


func _update_performance_fps_display_cache(emit_changed: bool) -> void:
	_performance_fps_display_text = "%d" % floori(_performance_frames_per_second)
	_performance_fps_display_color = _performance_color_for_fps(_performance_frames_per_second)
	_performance_frame_time_display_text = _get_performance_frame_time_text()
	_performance_frame_time_display_color = _performance_color_for_frametime(_performance_frametime_msec)
	if emit_changed:
		performance_fps_changed.emit()


func _performance_color_for_fps(fps: float) -> Color:
	return _performance_frame_time_gradient.sample(remap(fps, PERFORMANCE_GRAPH_MIN_FPS, PERFORMANCE_GRAPH_MAX_FPS, 0.0, 1.0))


func _performance_color_for_frametime(frametime_msec: float) -> Color:
	var fps := 1000.0 / frametime_msec if frametime_msec > 0.0 else 0.0
	return _performance_color_for_fps(fps)


func get_performance_snapshot() -> Dictionary:
	_ensure_performance_monitor_initialized()
	var total_stats := _performance_history_stats(_performance_frame_history_total)
	var cpu_stats := _performance_history_stats(_performance_frame_history_cpu)
	var gpu_stats := _performance_history_stats(_performance_frame_history_gpu)
	return {
		"fps": _performance_frames_per_second,
		"frametime_msec": _performance_frametime_msec,
		"frame_number": Engine.get_frames_drawn(),
		"fps_history": _performance_fps_history.duplicate(),
		"total_history": _performance_frame_history_total.duplicate(),
		"cpu_history": _performance_frame_history_cpu.duplicate(),
		"gpu_history": _performance_frame_history_gpu.duplicate(),
	"total_stats": total_stats,
		"cpu_stats": cpu_stats,
		"gpu_stats": gpu_stats,
		"fps_display_text": _performance_fps_display_text,
		"fps_display_color": _performance_fps_display_color,
		"frame_time_text": _performance_frame_time_display_text,
		"frame_time_color": _performance_frame_time_display_color,
		"history_num_frames": PERFORMANCE_HISTORY_NUM_FRAMES,
		"graph_min_fps": PERFORMANCE_GRAPH_MIN_FPS,
		"graph_max_fps": PERFORMANCE_GRAPH_MAX_FPS,
		"graph_time_range_sec": _performance_graph_time_range_sec,
		"visible_sample_count": _get_performance_source_visible_sample_count(),
		"color": _performance_color_for_fps(_performance_frames_per_second),
		"total_color": _performance_color_for_frametime(float(total_stats.get("avg", 0.0))),
		"cpu_color": _performance_color_for_frametime(float(cpu_stats.get("avg", 0.0))),
		"gpu_color": _performance_color_for_frametime(float(gpu_stats.get("avg", 0.0))),
		"settings_text": _get_performance_settings_text(),
		"information_text": _get_performance_information_text(),
	}


func _performance_history_stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"avg": 0.0, "min": 0.0, "max": 0.0, "last": 0.0}
	var sum := 0.0
	var min_value := values[0]
	var max_value := values[0]
	for value in values:
		sum += value
		min_value = minf(min_value, value)
		max_value = maxf(max_value, value)
	return {
		"avg": sum / float(values.size()),
		"min": min_value,
		"max": max_value,
		"last": values[values.size() - 1],
	}


func _get_performance_frame_time_text() -> String:
	var text := str(_performance_frametime_msec).pad_decimals(2) + " mspf"
	var vsync_string := ""
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_ENABLED:
			vsync_string = "V-Sync"
		DisplayServer.VSYNC_ADAPTIVE:
			vsync_string = "Adaptive V-Sync"
		DisplayServer.VSYNC_MAILBOX:
			vsync_string = "Mailbox V-Sync"

	if Engine.max_fps > 0 or OS.low_processor_usage_mode:
		var low_processor_max_fps := roundi(1000000.0 / OS.low_processor_usage_mode_sleep_usec)
		var fps_cap := low_processor_max_fps
		if Engine.max_fps > 0:
			fps_cap = mini(Engine.max_fps, low_processor_max_fps)
		text += " (cap: " + str(fps_cap) + " FPS"
		if not vsync_string.is_empty():
			text += " + " + vsync_string
		text += ")"
	elif not vsync_string.is_empty():
		text += " (" + vsync_string + ")"
	return text


func _get_performance_settings_text() -> String:
	var lines: PackedStringArray = []
	if ProjectSettings.has_setting("application/config/version"):
		lines.append("Project Version: %s" % ProjectSettings.get_setting("application/config/version"))

	var rendering_method := str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	var rendering_method_string := rendering_method
	match rendering_method:
		"forward_plus":
			rendering_method_string = "Forward+"
		"mobile":
			rendering_method_string = "Forward Mobile"
		"gl_compatibility":
			rendering_method_string = "Compatibility"
	lines.append("Rendering Method: %s" % rendering_method_string)

	var viewport := get_viewport()
	if viewport == null:
		return "\n".join(lines)

	var viewport_render_size := Vector2i()
	if viewport.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		viewport_render_size = viewport.get_visible_rect().size
		lines.append("Viewport: %d x %d, Window: %d x %d" % [
			viewport.get_visible_rect().size.x,
			viewport.get_visible_rect().size.y,
			viewport.size.x,
			viewport.size.y,
		])
	else:
		viewport_render_size = viewport.size
		lines.append("Viewport: %d x %d" % [viewport.size.x, viewport.size.y])

	if viewport.get_camera_3d():
		var scaling_3d_mode_string := "(unknown)"
		match viewport.scaling_3d_mode:
			Viewport.SCALING_3D_MODE_BILINEAR:
				scaling_3d_mode_string = "Bilinear"
			Viewport.SCALING_3D_MODE_FSR:
				scaling_3d_mode_string = "FSR 1.0"
			Viewport.SCALING_3D_MODE_FSR2:
				scaling_3d_mode_string = "FSR 2.2"

		var antialiasing_3d_string := ""
		if viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2:
			antialiasing_3d_string += (" + " if not antialiasing_3d_string.is_empty() else "") + "FSR 2.2"
		if viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2 and viewport.use_taa:
			antialiasing_3d_string += (" + " if not antialiasing_3d_string.is_empty() else "") + "TAA"
		if viewport.msaa_3d >= Viewport.MSAA_2X:
			antialiasing_3d_string += (" + " if not antialiasing_3d_string.is_empty() else "") + "%d x MSAA" % pow(2, viewport.msaa_3d)
		if viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA:
			antialiasing_3d_string += (" + " if not antialiasing_3d_string.is_empty() else "") + "FXAA"

		lines.append("3D scale (%s): %d%% = %d x %d" % [
			scaling_3d_mode_string,
			viewport.scaling_3d_scale * 100,
			viewport_render_size.x * viewport.scaling_3d_scale,
			viewport_render_size.y * viewport.scaling_3d_scale,
		])

		if not antialiasing_3d_string.is_empty():
			lines.append("3D Antialiasing: %s" % antialiasing_3d_string)

		var environment := viewport.get_camera_3d().get_world_3d().environment
		if environment:
			if environment.ssr_enabled:
				lines.append("SSR: %d Steps" % environment.ssr_max_steps)
			if environment.ssao_enabled:
				lines.append("SSAO: On")
			if environment.ssil_enabled:
				lines.append("SSIL: On")
			if environment.sdfgi_enabled:
				lines.append("SDFGI: %d Cascades" % environment.sdfgi_cascades)
			if environment.glow_enabled:
				lines.append("Glow: On")
			if environment.volumetric_fog_enabled:
				lines.append("Volumetric Fog: On")

	var antialiasing_2d_string := ""
	if viewport.msaa_2d >= Viewport.MSAA_2X:
		antialiasing_2d_string = "%d x MSAA" % pow(2, viewport.msaa_2d)
	if not antialiasing_2d_string.is_empty():
		lines.append("2D Antialiasing: %s" % antialiasing_2d_string)
	return "\n".join(lines)


func _get_performance_information_text() -> String:
	var adapter_string := ""
	if RenderingServer.get_video_adapter_vendor().trim_suffix(" Corporation") in RenderingServer.get_video_adapter_name():
		adapter_string = RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")
	else:
		adapter_string = RenderingServer.get_video_adapter_vendor() + " - " + RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")

	var driver_info := OS.get_video_adapter_driver_info()
	var driver_info_string := ""
	if driver_info.size() >= 2:
		driver_info_string = driver_info[1]
	else:
		driver_info_string = "(unknown)"

	var release_string := ""
	if OS.has_feature("editor"):
		release_string = "editor"
	elif OS.has_feature("debug"):
		release_string = "debug"
	else:
		release_string = "release"

	var rendering_method := str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	var rendering_driver := str(ProjectSettings.get_setting_with_override("rendering/rendering_device/driver"))
	var graphics_api_string := rendering_driver
	if rendering_method != "gl_compatibility":
		if rendering_driver == "d3d12":
			graphics_api_string = "Direct3D 12"
		elif rendering_driver == "metal":
			graphics_api_string = "Metal"
		elif rendering_driver == "vulkan":
			if OS.has_feature("macos") or OS.has_feature("ios"):
				graphics_api_string = "Vulkan via MoltenVK"
			else:
				graphics_api_string = "Vulkan"
	else:
		if rendering_driver == "opengl3_angle":
			graphics_api_string = "OpenGL via ANGLE"
		elif OS.has_feature("mobile") or rendering_driver == "opengl3_es":
			graphics_api_string = "OpenGL ES"
		elif OS.has_feature("web"):
			graphics_api_string = "WebGL"
		elif rendering_driver == "opengl3":
			graphics_api_string = "OpenGL"

	return (
		"%s, %d threads\n" % [OS.get_processor_name().replace("(R)", "").replace("(TM)", ""), OS.get_processor_count()]
		+ "%s %s (%s %s), %s %s\n" % [OS.get_name(), "64-bit" if OS.has_feature("64") else "32-bit", release_string, "double" if OS.has_feature("double") else "single", graphics_api_string, RenderingServer.get_video_adapter_api_version()]
		+ "%s, %s" % [adapter_string, driver_info_string]
	)


func _command_current_git_branch() -> void:
	print_line("Current git branch: %s" % _get_current_git_branch())


func _get_current_git_branch() -> String:
	if not _current_git_branch.is_empty():
		return _current_git_branch + _current_git_branch_remote_status

	_current_git_branch = _resolve_current_git_branch()
	if _current_git_branch.is_empty():
		_current_git_branch = _UNKNOWN_GIT_BRANCH
	return _current_git_branch + _current_git_branch_remote_status


func _get_current_git_branch_display_items() -> Array[Dictionary]:
	_get_current_git_branch()
	var items: Array[Dictionary] = [{"text": _current_git_branch}]
	if _current_git_branch_ahead > 0:
		items.append({"text": "+%d" % _current_git_branch_ahead, "color": _CURRENT_GIT_BRANCH_AHEAD_COLOR})
	if _current_git_branch_behind > 0:
		items.append({"text": "-%d" % _current_git_branch_behind, "color": _CURRENT_GIT_BRANCH_BEHIND_COLOR})
	if _current_git_branch_uncommitted_files > 0:
		items.append({"text": "~%d" % _current_git_branch_uncommitted_files, "color": _CURRENT_GIT_BRANCH_UNCOMMITTED_COLOR})
	return items


func _refresh_current_git_branch_remote_status() -> void:
	_current_git_branch_remote_status = ""
	_current_git_branch_ahead = 0
	_current_git_branch_behind = 0
	_current_git_branch_uncommitted_files = 0
	if _get_current_git_branch() == _UNKNOWN_GIT_BRANCH:
		return

	var command_output: Array = []
	var status := OS.execute("git", ["status", "--porcelain"], command_output, true)
	if status == OK and not command_output.is_empty():
		_current_git_branch_uncommitted_files = str(command_output[0]).strip_edges().split("\n", false).size()

	command_output.clear()
	status = OS.execute("git", ["fetch", "--quiet"], command_output, true)
	if status != OK:
		return

	command_output.clear()
	status = OS.execute("git", ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], command_output, true)
	if status != OK or command_output.is_empty():
		return

	var counts := str(command_output[0]).strip_edges().replace("\t", " ").split(" ", false)
	if counts.size() != 2 or not counts[0].is_valid_int() or not counts[1].is_valid_int():
		return

	_current_git_branch_ahead = counts[0].to_int()
	_current_git_branch_behind = counts[1].to_int()
	var remote_status_parts: PackedStringArray = []
	if _current_git_branch_ahead > 0:
		remote_status_parts.append("+%d" % _current_git_branch_ahead)
	if _current_git_branch_behind > 0:
		remote_status_parts.append("-%d" % _current_git_branch_behind)
	if not remote_status_parts.is_empty():
		_current_git_branch_remote_status = " " + " ".join(remote_status_parts)


func _resolve_current_git_branch() -> String:
	var command_output: Array = []
	var status := OS.execute("git", ["rev-parse", "--abbrev-ref", "HEAD"], command_output, true)
	if status == OK and not command_output.is_empty():
		var branch := str(command_output[0]).strip_edges()
		if not branch.is_empty():
			return branch

	var head_file_path := ProjectSettings.globalize_path("res://.git/HEAD")
	if head_file_path.is_empty() or not FileAccess.file_exists(head_file_path):
		return ""

	var head_file := FileAccess.open(head_file_path, FileAccess.READ)
	if head_file == null:
		return ""

	var head_line := head_file.get_line().strip_edges()
	if head_line.is_empty():
		return ""
	if head_line.begins_with("ref: "):
		var ref_path := head_line.substr(5).strip_edges()
		if ref_path.begins_with("refs/heads/"):
			return ref_path.trim_prefix("refs/heads/")
		return ref_path
	return head_line


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


func _register_timer_commands() -> void:
	add_command(
		"timers/start",
		_command_timer_start,
		["key", "name", "channel"],
		1,
		"Start or restart a timer. Name defaults to the key when omitted. Channel controls pinning and the final stop log destination.",
		TIMER_COMMAND_GROUP_NAME,
		TIMER_COMMAND_GROUP_PRIORITY
	)
	add_command_with_options(
		"timers/pause",
		_command_timer_pause,
		["key"],
		1,
		"Pause a running timer.",
		_get_running_timer_key_options,
		Callable(),
		TIMER_COMMAND_GROUP_NAME,
		TIMER_COMMAND_GROUP_PRIORITY
	)
	add_command_with_options(
		"timers/resume",
		_command_timer_resume,
		["key"],
		1,
		"Resume a paused timer.",
		_get_paused_timer_key_options,
		Callable(),
		TIMER_COMMAND_GROUP_NAME,
		TIMER_COMMAND_GROUP_PRIORITY
	)
	add_command_with_options(
		"timers/stop",
		_command_timer_stop,
		["key"],
		1,
		"Stop a timer and log its final duration.",
		_get_known_timer_key_options,
		Callable(),
		TIMER_COMMAND_GROUP_NAME,
		TIMER_COMMAND_GROUP_PRIORITY
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
	_register_dev_commands()
	_refresh_current_git_branch_remote_status()
	_register_pin_commands()
	_register_timer_commands()

	# Game-only commands
	if not Engine.is_editor_hint():
		add_command("console/quit", quit, 0, 0, "Quits the game.")
		add_command("exit", quit, 0, 0, "Quits the game.")
		add_command("restart", restart_application, 0, 0, "Restarts the game application.")
		add_command("console/delete_history", delete_history, 0, 0, "Deletes the history of previously entered commands.")
		_register_ingame_popup_commands()


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _input(event : InputEvent) -> void:
	# Don't handle input in editor
	if Engine.is_editor_hint():
		return

	if _handle_mobile_back_event(event):
		get_tree().get_root().set_input_as_handled()
		return

	if event is InputEventJoypadButton:
		var joypad_button_event := event as InputEventJoypadButton
		if _handle_controller_shortcut_input(joypad_button_event):
			get_tree().get_root().set_input_as_handled()
			return

	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if _handle_controller_log_input(event):
			get_tree().get_root().set_input_as_handled()
			return

	if event is InputEventKey:
		var console_visible := _is_console_control_visible()
		if _handle_line_edit_autocomplete_input(event):
			_set_current_input_method_keyboard()
			get_tree().get_root().set_input_as_handled()
			return
		if event.get_physical_keycode_with_modifiers() == KEY_QUOTELEFT:
			if event.pressed:
				_set_current_input_method_keyboard()
				_handle_console_toggle_shortcut()
			get_tree().get_root().set_input_as_handled()
		elif event.get_physical_keycode_with_modifiers() == (KEY_QUOTELEFT | KEY_MASK_SHIFT) and enabled and not console_visible:
			# Only claim ~ while the console is hidden, so it stays typeable in the input line.
			if event.pressed:
				_set_current_input_method_keyboard()
				_handle_command_palette_shortcut()
			get_tree().get_root().set_input_as_handled()
		elif event.physical_keycode == KEY_QUOTELEFT and event.is_command_or_control_pressed():
			if event.pressed:
				_set_current_input_method_keyboard()
				if console_visible:
					toggle_size()
				else:
					toggle_console(false)
					toggle_size()
			get_tree().get_root().set_input_as_handled()
		elif event.physical_keycode == KEY_F3 and event.pressed and not event.echo:
			_cycle_performance_pin_mode(event.shift_pressed)
			get_tree().get_root().set_input_as_handled()
		elif event.physical_keycode == KEY_F4 and event.pressed and not event.echo:
			_toggle_all_pins_visibility()
			get_tree().get_root().set_input_as_handled()
		elif event.pressed and not event.echo and event.unicode == "/".unicode_at(0) and enabled and control and _display and not control.visible:
			_set_current_input_method_keyboard()
			_open_command_entry_view()
			get_tree().get_root().set_input_as_handled()
		elif (event.get_physical_keycode_with_modifiers() == KEY_ESCAPE or event.keycode == KEY_BACK) and console_visible:
			if event.pressed:
				if not _handle_mobile_back_input():
					_set_current_input_method_keyboard()
					_handle_escape_input()
				get_tree().get_root().set_input_as_handled()
		if console_visible and event.pressed and rich_label != null and is_instance_valid(rich_label):
			if event.get_physical_keycode_with_modifiers() == KEY_PAGEUP:
				_set_current_input_method_keyboard()
				var scroll := rich_label.get_v_scroll_bar()
				var tween := create_tween()
				tween.tween_property(scroll, "value", scroll.value - (scroll.page - scroll.page * 0.1), 0.1)
				get_tree().get_root().set_input_as_handled()
			if event.get_physical_keycode_with_modifiers() == KEY_PAGEDOWN:
				_set_current_input_method_keyboard()
				var scroll := rich_label.get_v_scroll_bar()
				var tween := create_tween()
				tween.tween_property(scroll, "value", scroll.value + (scroll.page - scroll.page * 0.1), 0.1)
				get_tree().get_root().set_input_as_handled()


func _set_current_input_method_keyboard() -> void:
	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH if _touch_mode_enabled else LogotDisplay.INPUT_METHOD_KEYBOARD)


func _set_current_input_method_controller() -> void:
	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_CONTROLLER)


func _is_controller_modifier_held(device: int) -> bool:
	return Input.is_joy_button_pressed(device, JOY_BUTTON_BACK)


func _handle_controller_shortcut_input(event: InputEventJoypadButton) -> bool:
	if event == null:
		return false

	if event.button_index == JOY_BUTTON_BACK:
		return true

	if not event.pressed:
		return false

	if not _is_controller_modifier_held(event.device):
		return false

	match event.button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			_set_current_input_method_controller()
			toggle_console(false)
			return true
		JOY_BUTTON_A:
			_set_current_input_method_controller()
			_open_command_entry_view()
			return true
	return false


func _handle_controller_log_input(event: InputEvent) -> bool:
	if not _is_console_control_visible():
		return false

	if event.is_action_pressed("ui_cancel"):
		_set_current_input_method_controller()
		_handle_escape_input()
		return true

	if not _display:
		return false
	if not _display.is_command_entry_mode() and not _display.is_autocomplete_visible():
		return false

	if event.is_action_pressed("ui_up"):
		_set_current_input_method_controller()
		_display.autocomplete_select_prev()
		return true
	if event.is_action_pressed("ui_down"):
		_set_current_input_method_controller()
		_display.autocomplete_select_next()
		return true
	if event.is_action_pressed("ui_left"):
		_set_current_input_method_controller()
		_display.autocomplete_move_left()
		return true
	if event.is_action_pressed("ui_right"):
		_set_current_input_method_controller()
		_display.autocomplete_move_right(true)
		return true
	if event is InputEventJoypadButton:
		var joypad_button_event := event as InputEventJoypadButton
		if joypad_button_event.pressed and joypad_button_event.button_index == JOY_BUTTON_X:
			_set_current_input_method_controller()
			_handle_controller_keep_palette_execute_input()
			return true
	if event.is_action_pressed("ui_accept"):
		_set_current_input_method_controller()
		_handle_controller_accept_input()
		return true

	return false


func _handle_controller_accept_input() -> void:
	if not _display or not line_edit:
		return

	var selected_history_command := _get_selected_history_command()
	if not selected_history_command.is_empty():
		_submit_line_edit_input(selected_history_command, false, false)
		return

	if _display.has_active_command_autocomplete_match():
		if _display.is_active_command_match_submittable():
			_submit_line_edit_input(line_edit.text, false, true)
		else:
			_display.confirm_autocomplete()
		return

	if line_edit.text.strip_edges().begins_with("/"):
		_submit_line_edit_input(line_edit.text, false, true)


func _handle_controller_keep_palette_execute_input() -> void:
	if not _display or not line_edit:
		return

	var selected_history_command := _get_selected_history_command()
	if not selected_history_command.is_empty():
		_submit_line_edit_input(selected_history_command, true, false)
		return

	if _display.has_active_command_autocomplete_match():
		if _display.is_active_command_match_submittable():
			_submit_line_edit_input(line_edit.text, true, true)
		return

	if line_edit.text.strip_edges().begins_with("/"):
		_submit_line_edit_input(line_edit.text, true, true)


func _is_console_control_visible() -> bool:
	return control != null and is_instance_valid(control) and control.visible


func _handle_line_edit_autocomplete_input(event: InputEventKey) -> bool:
	if event and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK):
		if _is_console_control_visible() and line_edit and line_edit.has_focus():
			if _handle_touch_command_palette_back_or_close():
				return true
			_handle_escape_input()
			return true

	var autocomplete_handler := Callable(LogotCommandInput, "handle_autocomplete_navigation")
	if autocomplete_handler.is_valid():
		return bool(autocomplete_handler.call(
			event,
			_display,
			line_edit,
			Callable(self, "_close_command_entry_view")
		))
	return false


func _handle_touch_command_palette_back_or_close() -> bool:
	return (
		_touch_mode_enabled
		and _display != null
		and _display.has_method("touch_command_palette_back_or_close")
		and bool(_display.touch_command_palette_back_or_close())
	)


func _handle_mobile_back_event(event: InputEvent) -> bool:
	if event == null:
		return false
	if event.is_action_pressed("ui_cancel"):
		return _handle_mobile_back_input()
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_BACK or key_event.keycode == KEY_ESCAPE):
			return _handle_mobile_back_input()
	return false


func _handle_mobile_back_input() -> bool:
	if not _touch_mode_enabled or not _is_console_control_visible():
		return false

	if _display:
		_display.set_current_input_method(LogotDisplay.INPUT_METHOD_TOUCH)

	if _handle_touch_command_palette_back_or_close():
		return true

	toggle_console(true)
	return true


func _handle_touch_sidebar_back_or_close() -> bool:
	return (
		_touch_mode_enabled
		and _display != null
		and _display.has_method("close_touch_sidebar")
		and bool(_display.close_touch_sidebar())
	)


func _is_line_edit_submit_event(event: InputEventKey) -> bool:
	var submit_checker := Callable(LogotCommandInput, "is_submit_event")
	if submit_checker.is_valid():
		return bool(submit_checker.call(event, line_edit))
	if not event.pressed or event.echo:
		return false
	if not line_edit or not line_edit.has_focus():
		return false
	return event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER


func _get_selected_history_command() -> String:
	var history_getter := Callable(LogotCommandInput, "get_selected_history_command")
	if history_getter.is_valid():
		return str(history_getter.call(_display)).strip_edges()
	if not _display or not _display.has_method("get_selected_history_command"):
		return ""
	return str(_display.get_selected_history_command()).strip_edges()


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not _display:
		return
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey
	if _handle_line_edit_autocomplete_input(key_event) or _handle_line_edit_submit_input(key_event):
		_set_current_input_method_keyboard()
		line_edit.accept_event()
		line_edit.call_deferred("grab_focus")


func _handle_line_edit_submit_input(event: InputEventKey) -> bool:
	if not _is_line_edit_submit_event(event):
		return false

	var keep_input := event.shift_pressed
	var selected_history_command := _get_selected_history_command()
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
	if control == null or not is_instance_valid(control):
		return
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
	if control == null or not is_instance_valid(control):
		return
	if enabled and not control.visible:
		control.visible = true
		_clear_ingame_popups()
		_restore_full_console_after_command_entry = false
		was_paused_already = get_tree().paused
		get_tree().paused = was_paused_already || pause_enabled
		if line_edit != null and is_instance_valid(line_edit):
			line_edit.grab_focus()
		console_opened.emit()
		_sync_pinned_overlay_suppression()
		_update_touch_toggle_button()
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
	_sync_pinned_overlay_suppression()
	_update_touch_toggle_button()


func _handle_escape_input() -> void:
	if _handle_touch_sidebar_back_or_close():
		return
	if _test_panel != null and is_instance_valid(_test_panel) and _test_panel.visible:
		_test_panel.hide()
		return
	if _is_render_texture_preview_active():
		_display.clear_render_texture_widget_view_mode()
		if line_edit != null and is_instance_valid(line_edit):
			line_edit.grab_focus()
		return
	if _is_escape_close_state():
		toggle_console(true)
		return

	_reset_console_for_escape()


func _is_render_texture_preview_active() -> bool:
	return _display != null and _display.has_method("is_render_texture_widget_view_mode_active") and _display.is_render_texture_widget_view_mode_active()


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
	return _is_console_control_visible()


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
	var extractor := Callable(LogotCommandInput, "extract_command_name")
	if extractor.is_valid():
		return str(extractor.call(command_input, parse_line_input))

	var trimmed_input := command_input.strip_edges()
	if not trimmed_input.begins_with("/"):
		return ""
	var text_split := parse_line_input(trimmed_input.substr(1))
	if text_split.is_empty():
		return ""
	return str(text_split[0]).strip_edges()


func _resolve_submitted_text(raw_text: String, prefer_autocomplete_selection: bool) -> String:
	var resolver := Callable(LogotCommandInput, "resolve_submitted_text")
	if resolver.is_valid():
		return str(resolver.call(raw_text, prefer_autocomplete_selection, _display))

	var submitted_text := raw_text.strip_edges()
	if not prefer_autocomplete_selection:
		return submitted_text
	if not submitted_text.begins_with("/"):
		return submitted_text
	if not _display or not _display.has_active_command_autocomplete_match():
		return submitted_text
	return _display.get_active_command_submission_text().strip_edges()


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
	var should_refocus_input := _display == null or _display.get_current_input_method() != LogotDisplay.INPUT_METHOD_TOUCH

	if not keep_input:
		if line_edit != null:
			scroll_to_bottom()
		if _display:
			_display.reset_autocomplete()
		if line_edit != null:
			line_edit.clear()
			if should_refocus_input and !Engine.is_editor_hint():
				line_edit.grab_focus()

		if _display:
			_display.set_search_filter("")
			_display.rebuild_display()

		if _display and _display.is_command_entry_mode():
			_close_command_entry_view()
	else:
		if should_refocus_input and line_edit != null:
			line_edit.grab_focus()

	if is_command_input:
		_execute_command(submitted_text)
		if keep_input and _display:
			_display.reconcile_retained_command_path()
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
	if is_command_path_disabled(requested_command):
		print_error("Command is disabled: /%s" % requested_command)
		return {"ok": false, "error": "Command is disabled: /%s" % requested_command}
	var command_resolution := _resolve_console_command_path(requested_command)
	if not command_resolution.get("valid", false):
		var labelled_option_result := _execute_labelled_option_command(command_text)
		if not labelled_option_result.is_empty():
			return labelled_option_result
		console_unknown_command.emit(requested_command)
		print_error("Command not found: /%s" % requested_command)
		return {"ok": false, "error": "Command not found: /%s" % requested_command}

	if command_resolution.get("is_display_variable_pin_action", false):
		var resolved_display_address := str(command_resolution.get("display_variable_address", ""))
		var render_texture_view_mode := str(command_resolution.get("display_variable_render_texture_view_mode", "")).strip_edges()
		if not render_texture_view_mode.is_empty():
			_execute_render_texture_widget_view_mode_action(
				resolved_display_address,
				_normalize_render_texture_widget_view_mode(render_texture_view_mode)
			)
		else:
			_execute_display_variable_pin_action(
				resolved_display_address,
				command_resolution.get("display_variable_pin_state", false) == true,
				str(command_resolution.get("display_variable_pin_corner", PIN_CORNER_TOP_LEFT))
			)
		return {"ok": true}

	if command_resolution.get("is_widget_command", false):
		_execute_widget_command(str(command_resolution.get("widget_address", "")))
		return {"ok": true}

	var text_command := str(command_resolution.get("command_name", ""))
	var arguments: Array = text_split.slice(1)
	for injected_argument in command_resolution.get("injected_arguments", []):
		arguments.insert(0, str(injected_argument))
	if not bool(command_resolution.get("is_option_subcommand", false)) and arguments.is_empty():
		var default_result := resolve_default_child_chain(text_command)
		if bool(default_result.get("has_default", false)):
			if not bool(default_result.get("valid", false)):
				var default_error := str(default_result.get("error", "Invalid default child."))
				print_error(default_error)
				return {"ok": false, "error": default_error}
			text_command = str(default_result.get("terminal_command", text_command))
			for default_argument in default_result.get("injected_arguments", []):
				arguments.append(str(default_argument))

	var command_data = console_commands.get(text_command)
	var command_callable := _get_command_callable(command_data)
	var command_argument_names := _get_command_argument_names(command_data)
	var required_argument_count := _get_command_required_count(command_data)
	if not command_callable.is_valid():
		var unavailable_error := "Command is not executable: /%s" % text_command
		print_error(unavailable_error)
		return {"ok": false, "error": unavailable_error}

	if text_command == "console/calc":
		var expression := ""
		for word in arguments:
			expression += word
		command_callable.callv([expression])
		return {"ok": true}

	if arguments.size() < required_argument_count:
		print_error("Too few arguments! Required < %d >" % required_argument_count)
		return {"ok": false, "error": "Too few arguments."}
	elif arguments.size() > command_argument_names.size():
		var labelled_option_result := _execute_labelled_option_command(command_text)
		if not labelled_option_result.is_empty():
			return labelled_option_result
		print_error("Too many arguments! < %d > Max" % command_argument_names.size())
		return {"ok": false, "error": "Too many arguments."}

	while arguments.size() < command_argument_names.size():
		arguments.append("")

	command_callable.callv(arguments)
	return {"ok": true}


## Option sub-commands are addressed by their label ("…/allocation/cpu/mode/Render CPU"), so a
## label containing spaces is split into several tokens by the regular line parser. Re-resolve
## the untouched line as a single command path before reporting an argument-count failure.
func _execute_labelled_option_command(command_text: String) -> Dictionary:
	var whole_path := command_text.strip_edges()
	if not whole_path.contains(" ") or is_command_path_disabled(whole_path):
		return {}
	var resolution := _resolve_console_command_path(whole_path)
	if not resolution.get("valid", false) or not resolution.get("is_option_subcommand", false):
		return {}
	var command_name := str(resolution.get("command_name", ""))
	if not console_commands.has(command_name):
		return {}
	var arguments: Array = []
	for injected_argument in resolution.get("injected_arguments", []):
		arguments.append(str(injected_argument))
	var accepted_argument_count: int = console_commands[command_name].arguments.size()
	if arguments.size() < console_commands[command_name].required or arguments.size() > accepted_argument_count:
		return {}
	while arguments.size() < accepted_argument_count:
		arguments.append("")
	console_commands[command_name].function.callv(arguments)
	return {"ok": true}


func on_line_edit_text_changed(new_text: String) -> void:
	if _display:
		_display.on_text_changed_autocomplete(new_text)


func _open_command_entry_view(focus_input: bool = true, prefill_text: String = "/") -> void:
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
		_sync_pinned_overlay_suppression()
		_update_touch_toggle_button()

	_display.show_command_entry_mode(prefill_text, focus_input)
	_sync_pinned_overlay_suppression()


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
		_sync_pinned_overlay_suppression()
		_update_touch_toggle_button()

	_restore_full_console_after_command_entry = false


func _is_command_palette_open() -> bool:
	return _is_console_control_visible() and _display != null and _display.is_command_entry_mode()


func _get_command_palette_path() -> String:
	if line_edit == null or not is_instance_valid(line_edit):
		return "/"
	var path := line_edit.text.strip_edges()
	return path if path.begins_with("/") else "/"


# ` hides an open palette while remembering its path, restores that path when the console is
# closed, and otherwise toggles the console.
func _handle_console_toggle_shortcut() -> void:
	if _is_command_palette_open():
		var path := _get_command_palette_path()
		if path == "/":
			# A root palette carries nothing worth remembering, so fall back to the console.
			_restore_full_console_after_command_entry = true
			_close_command_entry_view()
			_sync_pinned_overlay_suppression()
			_update_touch_toggle_button()
			return
		_hidden_command_palette_path = path
		_restore_full_console_after_command_entry = false
		_close_command_entry_view()
		return

	if not _is_console_control_visible() and _restore_hidden_command_palette():
		return

	toggle_console(false)


# ~ shows the command palette, at the remembered path when there is one.
func _handle_command_palette_shortcut() -> void:
	if _is_command_palette_open():
		return
	if _restore_hidden_command_palette():
		return
	_open_command_entry_view()


func _restore_hidden_command_palette() -> bool:
	if _hidden_command_palette_path.is_empty():
		return false
	var path := _hidden_command_palette_path
	_hidden_command_palette_path = ""
	_open_command_entry_view(true, path)
	return true


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


func _command_timer_start(key: String, name: String = "", channel: String = "") -> void:
	start_timer(key, name, channel)


func _command_timer_pause(key: String) -> void:
	pause_timer(key)


func _command_timer_resume(key: String) -> void:
	resume_timer(key)


func _command_timer_stop(key: String) -> void:
	stop_timer(key)


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


func _execute_display_variable_pin_action(address: String, pinned: bool, corner: String = PIN_CORNER_TOP_LEFT) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty():
		print_error("Display variable address is required for pin actions.")
		return
	if not _is_pinnable_console_item(normalized_address):
		print_error("Pinnable item not found: %s" % normalized_address)
		return

	set_display_variable_pinned(normalized_address, pinned, _normalize_pin_corner(corner))
	var action_text := "Pinned" if pinned else "Unpinned"
	print_line("%s [color=light_green]%s[/color]." % [action_text, _escape_bbcode_text(normalized_address)])


func _execute_render_texture_widget_view_mode_action(address: String, mode: String) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty():
		print_error("Render texture widget address is required.")
		return
	if not _is_render_texture_widget_console_item(normalized_address):
		print_error("Render texture widget not found: %s" % normalized_address)
		return

	var normalized_mode := _normalize_render_texture_widget_view_mode(mode)
	if not set_render_texture_widget_view_mode(normalized_address, normalized_mode):
		print_error("Failed to update render texture view mode for '%s'." % normalized_address)
		return

	match normalized_mode:
		LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
			print_line("Showing [color=light_green]%s[/color] in fullscreen mode." % _escape_bbcode_text(normalized_address))
		LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY:
			print_line("Showing [color=light_green]%s[/color] in fullscreen overlay mode." % _escape_bbcode_text(normalized_address))
		_:
			print_line("Closed fullscreen render texture mode for [color=light_green]%s[/color]." % _escape_bbcode_text(normalized_address))


func _execute_widget_command(address: String) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty() or not widgets.has(normalized_address):
		print_error("Widget not found: %s" % normalized_address)
		return
	if _is_render_texture_widget_console_item(normalized_address):
		print_line("Widget [color=light_green]%s[/color] supports /%s/pin, /%s/fullscreen, /%s/fullscreen_overlay, and /%s/fullscreen_off." % [
			_escape_bbcode_text(normalized_address),
			_escape_bbcode_text(normalized_address),
			_escape_bbcode_text(normalized_address),
			_escape_bbcode_text(normalized_address),
			_escape_bbcode_text(normalized_address),
		])
		return
	print_line("Widget [color=light_green]%s[/color] can be previewed in the command palette or pinned with /%s/pin." % [
		_escape_bbcode_text(normalized_address),
		_escape_bbcode_text(normalized_address),
	])


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
	lines.append("[color=cyan]Pinned items:[/color]")
	for address in pinned_addresses:
		var address_str := str(address)
		if address_str.is_empty():
			continue
		var escaped_address := _escape_bbcode_text(address_str)
		var corner := PIN_CORNER_TOP_LEFT
		if active_display.has_method("get_pinned_display_variable_corner"):
			corner = _normalize_pin_corner(str(active_display.get_pinned_display_variable_corner(address_str)))
		lines.append("  [color=light_green]%s[/color] [color=gray](%s | move: /%s/pin/<corner> | off: /%s/unpin)[/color]" % [escaped_address, corner, escaped_address, escaped_address])
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
