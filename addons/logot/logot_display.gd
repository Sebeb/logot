@tool
class_name LogotDisplay
extends Control

## Logot display functionality.
## Provides all filtering, display, sidebar, and settings logic.
## Used via composition by logot.gd and logot_editor_panel.gd.

# =============================================================================
# SIGNALS
# =============================================================================

signal custom_setting_changed(setting_name: String, value: bool)
signal cleared()
signal level_visibility_changed(level: int, mode: int)
signal channel_visibility_changed(channel: String, mode: int)
signal channel_deleted(channel: String)
signal display_rebuilt()  # Emitted after display is rebuilt, for external stats updates

# =============================================================================
# SHARED CLASSES
# =============================================================================

class FilterStats:
	var shown_count: int = 0
	var hidden_count: int = 0
	var off_count: int = 0

	func reset() -> void:
		shown_count = 0
		hidden_count = 0
		off_count = 0


class LogEntry:
	var id: int
	var level: int              # LogLevel constant
	var channel: String         # "" for no channel (displayed as "General")
	var instance_name: String   # Name of the instance this log came from (empty for local)
	var session_id: int         # Session ID of the instance this log came from (-1 for editor)
	var objects: Array          # Original objects passed to log()
	var formatted: String       # Pre-formatted BBCode string for first line
	var formatted_full: String  # Full formatted text (all lines)
	var stack_trace: String     # Optional stack trace (hidden by default)
	var extra_line_count: int   # Number of additional lines beyond the first
	var visible: bool           # Currently displayed in RichTextLabel
	var expanded: bool          # Whether this entry is expanded to show all content
	var timestamp: String       # Captured at creation time (HH:MM:SS format)
	var collapse_count: int     # Number of duplicate entries collapsed into this one

	func _init(p_id: int, p_level: int, p_channel: String, p_objects: Array, p_formatted: String, p_formatted_full: String = "", p_stack_trace: String = "", p_extra_lines: int = 0, p_timestamp: String = "", p_instance_name: String = "", p_session_id: int = -1):
		id = p_id
		level = p_level
		channel = p_channel
		instance_name = p_instance_name
		session_id = p_session_id
		objects = p_objects
		formatted = p_formatted
		formatted_full = p_formatted_full if p_formatted_full != "" else p_formatted
		stack_trace = p_stack_trace
		extra_line_count = p_extra_lines
		visible = false
		expanded = false
		timestamp = p_timestamp
		collapse_count = 1

	## Returns true if this entry has expandable content
	func has_expandable_content() -> bool:
		return extra_line_count > 0 or stack_trace != ""


class LogotCommand:
	var function: Callable
	var arguments: PackedStringArray
	var required: int
	var description: String

	func _init(in_function: Callable, in_arguments: PackedStringArray, in_required: int = 0, in_description: String = ""):
		function = in_function
		arguments = in_arguments
		required = in_required
		description = in_description


# =============================================================================
# CONSTANTS
# =============================================================================

enum VisibilityMode { SHOWN, HIDDEN, OFF }

const LEVEL_COLORS := {
	LogLevel.ERROR: Color8(204, 101, 102),
	LogLevel.WARN: Color8(240, 198, 116),
	LogLevel.COMMAND: Color8(133, 255, 98),
	LogLevel.MESSAGE: Color8(255, 255, 255),
	LogLevel.INFO: Color8(136, 215, 179),
	LogLevel.VERBOSE: Color8(210, 180, 162),
	LogLevel.DEBUG: Color8(128, 128, 128),
}


# =============================================================================
# UI REFERENCES
# =============================================================================

var rich_label: RichTextLabel
var line_edit: LineEdit
var _sidebar  # LogotSidebar - type removed to avoid circular dependency
var _sidebar_toggle_btn: Button
var _clear_btn: Button
var _main_container: Control
var _logot_container: VBoxContainer
var _input_row: HBoxContainer


# =============================================================================
# STATE
# =============================================================================

var _level_visibility: Dictionary = {}
var _channel_visibility: Dictionary = {}
var _known_channels: Array[String] = []
var _level_stats: Dictionary = {}
var _channel_stats: Dictionary = {}
var _search_filter: String = ""

var _collapse_duplicates := false
var _wrap_text := false
var _truncate_multiline := true
var _sidebar_visible := false

var _last_displayed_entry = null
var _last_displayed_count: int = 0
var _bbcode_before_last_entry: String = ""  # Stores BBCode content before the last displayed entry

# Composition support - providers set by owner
var _settings_file: String = ""
var _welcome_message: String = "Logot\n"
var _log_entries_provider: Callable
var _entry_text_provider: Callable
var _commands_provider: Callable  # Returns Dictionary of command_name -> command_data
var _rejected_level_count_provider: Callable  # Returns int for a given level
var _rejected_channel_count_provider: Callable  # Returns int for a given channel
var _level_visibility_getter: Callable  # Returns int (VisibilityMode) for a given level
var _level_visibility_setter: Callable  # Sets visibility mode for a given level
var _channel_visibility_getter: Callable  # Returns int (VisibilityMode) for a given channel
var _channel_visibility_setter: Callable  # Sets visibility mode for a given channel
var _instance_visibility_getter: Callable  # Returns int (VisibilityMode) for a given session_id
var _custom_settings: Array = []

# Autocomplete state
var _autocomplete_popup: ItemList
var _autocomplete_selected_index := -1
var _suggestions := []
var _current_suggest := 0
var _suggesting := false

# Command history
var _command_history: Array[String] = []
var _max_history_size := 50


# =============================================================================
# COMPOSITION CONFIGURATION METHODS
# =============================================================================

func set_settings_file(path: String) -> void:
	_settings_file = path


func set_welcome_message(msg: String) -> void:
	_welcome_message = msg


func set_log_entries_provider(provider: Callable) -> void:
	_log_entries_provider = provider


func set_entry_text_provider(provider: Callable) -> void:
	_entry_text_provider = provider


func set_commands_provider(provider: Callable) -> void:
	_commands_provider = provider


func set_rejected_level_count_provider(provider: Callable) -> void:
	_rejected_level_count_provider = provider


func set_rejected_channel_count_provider(provider: Callable) -> void:
	_rejected_channel_count_provider = provider


func set_level_visibility_provider(getter: Callable, setter: Callable) -> void:
	_level_visibility_getter = getter
	_level_visibility_setter = setter


func set_channel_visibility_provider(getter: Callable, setter: Callable) -> void:
	_channel_visibility_getter = getter
	_channel_visibility_setter = setter


func set_instance_visibility_provider(getter: Callable) -> void:
	_instance_visibility_getter = getter


## Get level visibility mode (uses provider if set, otherwise local dictionary)
func _get_level_visibility(level: int) -> int:
	if _level_visibility_getter.is_valid():
		return _level_visibility_getter.call(level)
	return _level_visibility.get(level, VisibilityMode.SHOWN)


## Set level visibility mode (uses provider if set, otherwise local dictionary)
func _set_level_visibility(level: int, mode: int) -> void:
	if _level_visibility_setter.is_valid():
		_level_visibility_setter.call(level, mode)
	else:
		_level_visibility[level] = mode


## Get channel visibility mode (uses provider if set, otherwise local dictionary)
func _get_channel_visibility(channel: String) -> int:
	if _channel_visibility_getter.is_valid():
		return _channel_visibility_getter.call(channel)
	return _channel_visibility.get(channel, VisibilityMode.SHOWN)


## Set channel visibility mode (uses provider if set, otherwise local dictionary)
func _set_channel_visibility(channel: String, mode: int) -> void:
	if _channel_visibility_setter.is_valid():
		_channel_visibility_setter.call(channel, mode)
	else:
		_channel_visibility[channel] = mode


## Get instance visibility mode (uses provider if set, otherwise SHOWN)
func _get_instance_visibility(session_id: int) -> int:
	if _instance_visibility_getter.is_valid():
		return _instance_visibility_getter.call(session_id)
	return VisibilityMode.SHOWN


func set_autocomplete_popup(popup: ItemList) -> void:
	_autocomplete_popup = popup


func add_custom_setting(name: String, label: String, default: bool) -> void:
	_custom_settings.append({"name": name, "label": label, "default": default})
	if _sidebar:
		_sidebar.add_setting(name, label, default)


func set_custom_setting(name: String, value: bool) -> void:
	if _sidebar:
		_sidebar.set_setting(name, value)


# =============================================================================
# VIRTUAL METHODS - Override in subclass
# =============================================================================

## Return the settings file path
func _get_settings_file() -> String:
	return _settings_file


## Return the welcome message
func _get_welcome_message() -> String:
	return _welcome_message


## Return log entries array
func _get_log_entries() -> Array:
	if _log_entries_provider.is_valid():
		return _log_entries_provider.call()
	return []


## Return display text for an entry
func _get_entry_display_text(entry, truncate: bool, count: int = 1) -> String:
	if _entry_text_provider.is_valid():
		var text: String = _entry_text_provider.call(entry, truncate)
		return text

	var full_text := _format_objects(entry.objects)
	var display_text: String
	var extra_lines: int
	var instance_name: String = entry.instance_name if "instance_name" in entry else ""

	if entry.expanded:
		# Expanded: show full text with stack trace
		display_text = full_text
		extra_lines = 0
		var formatted_trace := _format_stack_trace(entry.stack_trace) if entry.stack_trace != "" else ""
		return format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, false, extra_lines, entry.stack_trace, count, formatted_trace, instance_name)
	else:
		# Collapsed: show first line only if truncating
		if truncate and entry.extra_line_count > 0:
			display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
		else:
			display_text = full_text
		extra_lines = entry.extra_line_count if truncate else 0
		return format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace, count, "", instance_name)


## Return additional sidebar settings
func _get_sidebar_settings() -> Array:
	return []


## Return logot commands dictionary
func _get_commands() -> Dictionary:
	if _commands_provider.is_valid():
		return _commands_provider.call()
	return {}


## Called when a custom setting changes
func _on_custom_setting_changed(setting_name: String, value: bool) -> void:
	custom_setting_changed.emit(setting_name, value)


## Called after logs are cleared
func _on_cleared() -> void:
	cleared.emit()


## Toggle entry expansion (override if entries stored elsewhere)
func _toggle_entry_expansion(entry_id: int) -> void:
	for entry in _get_log_entries():
		if entry.id == entry_id:
			entry.expanded = not entry.expanded
			_rebuild_display()
			return


# =============================================================================
# INITIALIZATION
# =============================================================================

func _init_base() -> void:
	_init_default_levels()
	_load_filter_settings()


func _setup_ui_nodes() -> void:
	# Find the UI root - either direct child LogotUI or self
	var ui_root: Node = self
	if has_node("LogotUI"):
		ui_root = get_node("LogotUI")

	# Get nodes from UI root
	if ui_root.has_node("MainContainer"):
		_main_container = ui_root.get_node("MainContainer")
	if _main_container and _main_container.has_node("LogotContainer"):
		_logot_container = _main_container.get_node("LogotContainer")
	if _logot_container and _logot_container.has_node("RichTextLabel"):
		rich_label = _logot_container.get_node("RichTextLabel")
	if _logot_container and _logot_container.has_node("InputRow"):
		_input_row = _logot_container.get_node("InputRow")
	elif _logot_container and _logot_container.has_node("VBoxContainer/InputRow"):
		_input_row = _logot_container.get_node("VBoxContainer/InputRow")
	if _input_row:
		if _input_row.has_node("LineEdit"):
			line_edit = _input_row.get_node("LineEdit")
		if _input_row.has_node("ClearButton"):
			_clear_btn = _input_row.get_node("ClearButton")
		if _input_row.has_node("SidebarToggleButton"):
			_sidebar_toggle_btn = _input_row.get_node("SidebarToggleButton")
	if _main_container and _main_container.has_node("Sidebar"):
		_sidebar = _main_container.get_node("Sidebar")


func _connect_ui_signals() -> void:
	if rich_label:
		rich_label.meta_clicked.connect(_on_log_meta_clicked)
		rich_label.meta_underlined = false
		rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _wrap_text else TextServer.AUTOWRAP_OFF

	if _clear_btn:
		_clear_btn.pressed.connect(_clear_logs)

	if _sidebar_toggle_btn:
		_sidebar_toggle_btn.toggled.connect(_on_sidebar_toggle)
		_sidebar_toggle_btn.button_pressed = _sidebar_visible

	if _sidebar:
		_sidebar.visible = _sidebar_visible


func _setup_sidebar() -> void:
	if not _sidebar:
		return

	var settings := [
		{"name": "collapse_duplicates", "label": "Collapse duplicates", "default": false},
		{"name": "wrap_text", "label": "Wrap text", "default": false},
		{"name": "truncate_multiline", "label": "Truncate multiline logs", "default": true},
	]
	settings.append_array(_get_sidebar_settings())
	settings.append_array(_custom_settings)

	_sidebar.configure_settings(settings)
	_sidebar.level_visibility_changed.connect(_on_level_visibility_changed)
	_sidebar.channel_visibility_changed.connect(_on_channel_visibility_changed)
	_sidebar.channel_deleted.connect(_on_channel_deleted)
	_sidebar.setting_changed.connect(_on_setting_changed)

	_sync_sidebar_state()


func _init_display() -> void:
	if rich_label:
		rich_label.append_text(_get_welcome_message())


func _init_default_levels() -> void:
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		# Only initialize local dictionary if no provider is set
		if not _level_visibility_getter.is_valid() and level not in _level_visibility:
			_level_visibility[level] = VisibilityMode.SHOWN
		if level not in _level_stats:
			_level_stats[level] = FilterStats.new()
	_ensure_channel_exists("")


# =============================================================================
# CHANNEL AND LEVEL MANAGEMENT
# =============================================================================

func _ensure_channel_exists(channel: String) -> void:
	if channel not in _known_channels:
		_known_channels.append(channel)
		# Only initialize local dictionary if no provider is set
		if not _channel_visibility_getter.is_valid() and channel not in _channel_visibility:
			_channel_visibility[channel] = VisibilityMode.SHOWN
		if channel not in _channel_stats:
			_channel_stats[channel] = FilterStats.new()
		if _sidebar:
			_sidebar.add_channel(channel)


func _ensure_level_exists(level: int) -> void:
	# Only initialize local dictionary if no provider is set
	if not _level_visibility_getter.is_valid() and level not in _level_visibility:
		_level_visibility[level] = VisibilityMode.SHOWN
	if level not in _level_stats:
		_level_stats[level] = FilterStats.new()


func get_known_channels() -> Array[String]:
	return _known_channels


# =============================================================================
# DISPLAY LOGIC
# =============================================================================

func _should_display(entry) -> bool:
	var level_mode = _get_level_visibility(entry.level)
	var channel_mode = _get_channel_visibility(entry.channel)

	# Check instance visibility using the entry's session_id
	var instance_mode = _get_instance_visibility(entry.session_id)

	if _search_filter != "":
		var search_text := _format_objects(entry.objects).to_lower()
		if not search_text.contains(_search_filter):
			return false

	return level_mode == VisibilityMode.SHOWN and channel_mode == VisibilityMode.SHOWN and instance_mode == VisibilityMode.SHOWN


func _format_objects(objects: Array) -> String:
	var parts: PackedStringArray = []
	for obj in objects:
		parts.append(str(obj))
	return " ".join(parts)


static func _get_level_color_hex(level: int) -> String:
	var color: Color = LEVEL_COLORS.get(level, Color.WHITE)
	return "#" + color.to_html(false)


## Formats text for display as a BBCode table row with timestamp, channel, and message.
## This is the core static formatting function for all log entry display.
## Parameters:
##   - text: The message text to display
##   - level: Log level (determines color)
##   - channel: Channel name (can be empty)
##   - timestamp: Timestamp string
##   - entry_id: Entry ID for URL actions (use -1 if not applicable)
##   - is_collapsed: Whether this is a collapsed view
##   - extra_lines: Number of hidden lines (for collapsed view indicator)
##   - stack_trace: Stack trace string (for expanded view, or to determine expandability)
##   - collapse_count: Number of collapsed duplicates (badge shown after channel)
##   - formatted_stack_trace: Pre-formatted stack trace BBCode (for expanded view)
##   - instance_name: Name of the instance this log came from (empty for local/editor)
static func format_display_text(text: String, level: int, channel: String, timestamp: String, entry_id: int = -1, is_collapsed: bool = true, extra_lines: int = 0, stack_trace: String = "", collapse_count: int = 0, formatted_stack_trace: String = "", instance_name: String = "") -> String:
	var color: String = LogotDisplay._get_level_color_hex(level)

	# Build extra lines indicator for collapsed view
	var extra_indicator := ""
	if is_collapsed and extra_lines > 0:
		extra_indicator = " [i][color=dim_gray]+%d[/color][/i]" % extra_lines

	# Determine if this entry has expandable content and the toggle action
	var has_expandable := extra_lines > 0 or stack_trace != ""
	var toggle_action := "expand" if is_collapsed else "collapse"

	# Build message content
	var message_content := "[color=%s]%s[/color]%s" % [color, text, extra_indicator]
	# Append formatted stack trace for expanded view
	if not is_collapsed and formatted_stack_trace != "":
		message_content += "\n" + formatted_stack_trace

	# Build cell contents
	var timestamp_content := "[color=dim_gray]%s[/color]" % timestamp

	# Instance content (shown before channel if from a remote instance)
	var instance_content := ""
	if instance_name != "":
		instance_content = "[color=dim_gray][%s][/color] " % instance_name

	# Channel content with optional collapse count badge
	var channel_content := ""
	if channel != "":
		channel_content = "[color=%s][%s][/color]" % [color, channel]

	var count_content := ""
	if collapse_count > 0:
		var space := " " if channel_content != "" else ""
		count_content = "%s[color=%s][%d][/color]" % [space, color, collapse_count]

	# Wrap contents in URL if expandable (URLs must wrap text, not tables)
	if has_expandable and entry_id >= 0:
		var url_action := "%s:%d" % [toggle_action, entry_id]
		timestamp_content = "[url=%s]%s[/url]" % [url_action, timestamp_content]
		if instance_content != "":
			instance_content = "[url=%s]%s[/url]" % [url_action, instance_content]
		if channel_content != "":
			channel_content = "[url=%s]%s[/url]" % [url_action, channel_content]
		if count_content != "":
			count_content = "[url=%s]%s[/url]" % [url_action, count_content]
		message_content = "[url=%s]%s[/url]" % [url_action, message_content]

	# Build single row: [timestamp] [instance + channel + count] [message]
	return "[table=3][cell]%s [/cell] [cell]%s%s%s%s[/cell][/table]" % [timestamp_content, instance_content, channel_content, count_content, message_content]


## Parse and format a single stack frame line
## Returns formatted "function (filename:line)" with clickable URL, or empty string if no match
func _format_single_stack_frame(line: String) -> String:
	var stripped := line.strip_edges()
	if stripped.is_empty():
		return ""
	# Skip header lines
	if stripped.begins_with("GDScript backtrace"):
		return ""
	# Regex to match stack frame lines like "    [0] function_name (res://path/file.gd:123)"
	var regex := RegEx.new()
	regex.compile("\\[\\d+\\]\\s+([^\\(]+)\\s*\\(([^\\)]+)\\)")
	var match_result := regex.search(line)
	if match_result:
		var function_name := match_result.get_string(1).strip_edges()
		var location := match_result.get_string(2)  # e.g., "res://path/file.gd:123"
		var last_colon := location.rfind(":")
		if last_colon != -1:
			var file_path := location.substr(0, last_colon)
			var line_num := location.substr(last_colon + 1)
			var file_name := file_path.get_file()
			var display_text := "%s (%s:%s)" % [function_name, file_name, line_num]
			return "[url=open_file:%s:%s][color=dim_gray]%s[/color][/url]" % [file_path, line_num, display_text]
	return ""


func _get_top_stack_frame(stack_trace: String) -> String:
	if stack_trace.is_empty():
		return ""
	var lines := stack_trace.split("\n")
	for line in lines:
		var formatted := _format_single_stack_frame(line)
		if not formatted.is_empty():
			return formatted
	return ""


func _format_stack_trace(stack_trace: String) -> String:
	if stack_trace.is_empty():
		return ""
	var lines := stack_trace.split("\n")
	var formatted_lines: PackedStringArray = []
	for line in lines:
		var formatted := _format_single_stack_frame(line)
		if not formatted.is_empty():
			formatted_lines.append(formatted)
	return "\n".join(formatted_lines)


func _is_scrolled_to_bottom() -> bool:
	if not rich_label:
		return true
	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		return true
	# Consider "at bottom" if within 1 pixel of the maximum scroll value
	return scrollbar.value >= scrollbar.max_value - scrollbar.page - 1.0


func _scroll_to_bottom() -> void:
	if not rich_label:
		return
	var scrollbar := rich_label.get_v_scroll_bar()
	if scrollbar:
		scrollbar.value = scrollbar.max_value


func _display_entry(entry) -> void:
	if not rich_label:
		return

	# Check if we should auto-scroll after adding content
	var was_at_bottom := _is_scrolled_to_bottom()

	var display_text: String = _get_entry_display_text(entry, _truncate_multiline)

	var is_duplicate := false
	if _collapse_duplicates and _last_displayed_entry != null:
		var last_content := _format_objects(_last_displayed_entry.objects)
		var current_content := _format_objects(entry.objects)
		is_duplicate = (current_content == last_content
			and entry.level == _last_displayed_entry.level
			and entry.channel == _last_displayed_entry.channel)

	if is_duplicate:
		_last_displayed_count += 1
		_last_displayed_entry.collapse_count = _last_displayed_count
		_last_displayed_entry.timestamp = entry.timestamp

		# Rebuild display using stored BBCode (preserves formatting and URLs)
		rich_label.clear()
		rich_label.append_text(_bbcode_before_last_entry)

		var entry_text := _get_entry_display_text(_last_displayed_entry, _truncate_multiline, _last_displayed_count)
		rich_label.append_text(entry_text + "\n")
	else:
		# Accumulate the previous entry's BBCode before moving to the new entry
		if _last_displayed_entry != null:
			var prev_text: String = _get_entry_display_text(_last_displayed_entry, _truncate_multiline, _last_displayed_count)
			_bbcode_before_last_entry += prev_text + "\n"

		_last_displayed_entry = entry
		_last_displayed_count = 1
		rich_label.append_text(display_text + "\n")

	entry.visible = true

	# Only auto-scroll if we were already at the bottom
	if was_at_bottom:
		_scroll_to_bottom()


func _rebuild_display() -> void:
	if not rich_label:
		return

	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	_bbcode_before_last_entry = _get_welcome_message()
	rich_label.clear()
	rich_label.append_text(_get_welcome_message())

	for entry in _get_log_entries():
		_ensure_channel_exists(entry.channel)
		_update_stats_for_entry(entry)
		if _should_display(entry):
			_display_entry(entry)
		else:
			entry.visible = false

	_update_sidebar_stats()
	display_rebuilt.emit()


# =============================================================================
# STATISTICS
# =============================================================================

func _update_stats_for_entry(entry) -> void:
	var level_mode = _get_level_visibility(entry.level)
	var channel_mode = _get_channel_visibility(entry.channel)
	var instance_mode = _get_instance_visibility(entry.session_id)

	var level_stats: FilterStats = _level_stats.get(entry.level)
	var channel_stats: FilterStats = _channel_stats.get(entry.channel)

	if level_stats == null:
		level_stats = FilterStats.new()
		_level_stats[entry.level] = level_stats
	if channel_stats == null:
		channel_stats = FilterStats.new()
		_channel_stats[entry.channel] = channel_stats

	var hidden_by_search := false
	if _search_filter != "":
		var search_text := _format_objects(entry.objects).to_lower()
		hidden_by_search = not search_text.contains(_search_filter)

	# Entry is shown only if all filters allow it
	var is_shown: bool = (level_mode == VisibilityMode.SHOWN) and (channel_mode == VisibilityMode.SHOWN) and (instance_mode == VisibilityMode.SHOWN) and not hidden_by_search

	# Note: We no longer track off_count here. Logs that exist but are hidden by OFF mode
	# are just hidden, not "off". The off_count is now only for logs that were never created
	# because they failed can_log() - tracked separately via rejected counts.
	if is_shown:
		level_stats.shown_count += 1
		channel_stats.shown_count += 1
	else:
		level_stats.hidden_count += 1
		channel_stats.hidden_count += 1


func _reset_stats() -> void:
	for level in _level_stats:
		_level_stats[level].reset()
	for channel in _channel_stats:
		_channel_stats[channel].reset()


func _update_sidebar_stats() -> void:
	if not _sidebar:
		return

	for level in _level_stats:
		var stats: FilterStats = _level_stats[level]
		# Get rejected count from provider (logs that were never created due to can_log failing)
		var rejected_count := 0
		if _rejected_level_count_provider.is_valid():
			rejected_count = _rejected_level_count_provider.call(level)
		_sidebar.set_level_stats(level, stats.shown_count, stats.hidden_count, rejected_count)

	for channel in _channel_stats:
		var stats: FilterStats = _channel_stats[channel]
		# Get rejected count from provider (logs that were never created due to can_log failing)
		var rejected_count := 0
		if _rejected_channel_count_provider.is_valid():
			rejected_count = _rejected_channel_count_provider.call(channel)
		_sidebar.set_channel_stats(channel, stats.shown_count, stats.hidden_count, rejected_count)


# =============================================================================
# VISIBILITY CONTROL
# =============================================================================

func can_log(level: int, channel: String = "") -> bool:
	if _get_level_visibility(level) == VisibilityMode.OFF:
		return false
	if channel != "" and _get_channel_visibility(channel) == VisibilityMode.OFF:
		return false
	return true


func set_level_visibility(level: int, mode: int) -> void:
	_set_level_visibility(level, mode)
	_save_filter_settings()
	_rebuild_display()


func set_channel_visibility(channel: String, mode: int) -> void:
	_set_channel_visibility(channel, mode)
	_save_filter_settings()
	_rebuild_display()


# =============================================================================
# SIDEBAR SIGNAL HANDLERS
# =============================================================================

func _on_level_visibility_changed(level: int, mode: int) -> void:
	_set_level_visibility(level, mode)
	_save_filter_settings()
	_rebuild_display()
	level_visibility_changed.emit(level, mode)


func _on_channel_visibility_changed(channel: String, mode: int) -> void:
	_set_channel_visibility(channel, mode)
	_save_filter_settings()
	_rebuild_display()

	channel_visibility_changed.emit(channel, mode)


func _on_channel_deleted(channel: String) -> void:
	# Remove from local tracking if using local visibility
	if not _channel_visibility_getter.is_valid():
		_channel_visibility.erase(channel)
	_known_channels.erase(channel)
	_channel_stats.erase(channel)
	_save_filter_settings()
	_rebuild_display()

	channel_deleted.emit(channel)


func _on_setting_changed(setting_name: String, value: bool) -> void:
	match setting_name:
		"collapse_duplicates":
			_collapse_duplicates = value
			_save_filter_settings()
			_rebuild_display()
		"wrap_text":
			_wrap_text = value
			if rich_label:
				rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _wrap_text else TextServer.AUTOWRAP_OFF
			_save_filter_settings()
		"truncate_multiline":
			_truncate_multiline = value
			_save_filter_settings()
			_rebuild_display()
		_:
			_on_custom_setting_changed(setting_name, value)


func _on_sidebar_toggle(toggled_on: bool) -> void:
	_sidebar_visible = toggled_on
	if _sidebar:
		_sidebar.visible = _sidebar_visible
	_save_filter_settings()


# =============================================================================
# LOG META CLICK HANDLING
# =============================================================================

func _on_log_meta_clicked(meta: Variant) -> void:
	var meta_str := str(meta)
	if meta_str.begins_with("expand:") or meta_str.begins_with("collapse:"):
		var parts := meta_str.split(":")
		if parts.size() >= 2:
			var entry_id := int(parts[1])
			_toggle_entry_expansion(entry_id)
	elif meta_str.begins_with("open_file:"):
		var content := meta_str.substr(len("open_file:"))
		var last_colon := content.rfind(":")
		if last_colon != -1:
			var file_path := content.substr(0, last_colon)
			var line_num := int(content.substr(last_colon + 1))
			_open_file_in_editor(file_path, line_num)


func _open_file_in_editor(file_path: String, line: int) -> void:
	if Engine.is_editor_hint():
		var script := load(file_path)
		if script:
			EditorInterface.edit_script(script, line)
		else:
			push_warning("Could not load script: %s" % file_path)
	else:
		var absolute_path := ProjectSettings.globalize_path(file_path)
		OS.shell_open(absolute_path)


# =============================================================================
# CLEAR LOGS
# =============================================================================

func _clear_logs() -> void:
	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	_bbcode_before_last_entry = _get_welcome_message()
	if rich_label:
		rich_label.clear()
		rich_label.append_text(_get_welcome_message())
	if _sidebar:
		_sidebar.reset_stats()
	_on_cleared()


# =============================================================================
# PERSISTENCE
# =============================================================================

func _save_filter_settings() -> void:
	var settings_file := _get_settings_file()
	if settings_file.is_empty():
		return

	var config := ConfigFile.new()

	# Save level visibility - use local dictionary or query provider for known levels
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		config.set_value("levels", str(level), _get_level_visibility(level))

	# Save channel visibility
	for channel in _known_channels:
		var key: String = channel if channel != "" else "__general__"
		config.set_value("channels", key, _get_channel_visibility(channel))

	config.set_value("settings", "collapse_duplicates", _collapse_duplicates)
	config.set_value("settings", "wrap_text", _wrap_text)
	config.set_value("settings", "truncate_multiline", _truncate_multiline)
	config.set_value("settings", "sidebar_visible", _sidebar_visible)

	_save_custom_settings(config)

	config.save(settings_file)


func _load_filter_settings() -> void:
	var settings_file := _get_settings_file()
	if settings_file.is_empty():
		return

	var config := ConfigFile.new()
	if config.load(settings_file) != OK:
		return

	if config.has_section("levels"):
		for key in config.get_section_keys("levels"):
			_set_level_visibility(int(key), config.get_value("levels", key))

	if config.has_section("channels"):
		for key in config.get_section_keys("channels"):
			var channel := "" if key == "__general__" else key
			_set_channel_visibility(channel, config.get_value("channels", key))
			if channel not in _known_channels:
				_known_channels.append(channel)

	if config.has_section("settings"):
		_collapse_duplicates = config.get_value("settings", "collapse_duplicates", false)
		_wrap_text = config.get_value("settings", "wrap_text", false)
		_truncate_multiline = config.get_value("settings", "truncate_multiline", true)
		_sidebar_visible = config.get_value("settings", "sidebar_visible", false)

	_load_custom_settings(config)


func _save_custom_settings(_config: ConfigFile) -> void:
	pass


func _load_custom_settings(_config: ConfigFile) -> void:
	pass


func _sync_sidebar_state() -> void:
	if not _sidebar:
		return

	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		_sidebar.set_level_visibility(level, _get_level_visibility(level))

	for channel in _known_channels:
		_sidebar.add_channel(channel)
		_sidebar.set_channel_visibility(channel, _get_channel_visibility(channel))

	_sidebar.set_setting("collapse_duplicates", _collapse_duplicates)
	_sidebar.set_setting("wrap_text", _wrap_text)
	_sidebar.set_setting("truncate_multiline", _truncate_multiline)


# =============================================================================
# AUTOCOMPLETE
# =============================================================================

## Calculate match score for sorting (higher = better match)
## Returns -1 if no match
func _calculate_match_score(command: String, query: String) -> int:
	if query.is_empty():
		return 0  # All commands match with neutral score when no query

	var cmd_lower := command.to_lower()
	var query_lower := query.to_lower()

	# Exact match at start is best
	if cmd_lower.begins_with(query_lower):
		return 1000 - command.length()  # Shorter commands rank higher for prefix matches

	# Contains match
	var index := cmd_lower.find(query_lower)
	if index != -1:
		return 500 - index  # Earlier position = higher score

	# Fuzzy match: check if all query chars appear in order
	var query_idx := 0
	var score := 0
	var consecutive_bonus := 0
	for i in range(cmd_lower.length()):
		if query_idx < query_lower.length() and cmd_lower[i] == query_lower[query_idx]:
			score += 10
			if consecutive_bonus > 0:
				score += consecutive_bonus * 5  # Bonus for consecutive matches
			consecutive_bonus += 1
			query_idx += 1
		else:
			consecutive_bonus = 0

	if query_idx == query_lower.length():
		return score  # All characters found

	return -1  # No match


## Get the current tier prefix from the input text
## Returns the prefix up to and including the last / (e.g., "console/" from "/console/te")
func _get_current_tier_prefix() -> String:
	if not line_edit:
		return ""
	var text := line_edit.text
	if not text.begins_with("/"):
		return ""
	var full_text := text.substr(1)  # Remove leading /
	var last_slash := full_text.rfind("/")
	if last_slash == -1:
		return ""
	return full_text.substr(0, last_slash + 1)  # Include the trailing /


## Get the next tier suggestion for a command given the current prefix
## For "console/test/foo" with prefix "console/", returns "console/test"
## For "console" with prefix "", returns "console"
func _get_next_tier(command: String, prefix: String) -> String:
	if not command.begins_with(prefix):
		return ""
	var remainder := command.substr(prefix.length())
	var next_slash := remainder.find("/")
	if next_slash == -1:
		return command  # Full command, no more tiers
	return prefix + remainder.substr(0, next_slash)  # Return up to next tier


## Check if a command has more tiers after the given prefix
func _has_sub_tiers(command: String, prefix: String) -> bool:
	if not command.begins_with(prefix):
		return false
	var remainder := command.substr(prefix.length())
	return remainder.find("/") != -1


## Update the autocomplete popup with filtered and sorted suggestions
func update_autocomplete_popup() -> void:
	if not _autocomplete_popup or not line_edit:
		return

	var text := line_edit.text

	# Only show autocomplete for commands (starting with /)
	if not text.begins_with("/"):
		hide_autocomplete()
		return

	var full_text := text.substr(1)  # Remove the leading /

	# Determine the current tier prefix and query
	var prefix := ""
	var query := full_text
	var last_slash := full_text.rfind("/")
	if last_slash != -1:
		prefix = full_text.substr(0, last_slash + 1)  # Include trailing /
		query = full_text.substr(last_slash + 1)

	var commands := _get_commands()
	if commands.is_empty():
		hide_autocomplete()
		return

	# Build list of matching tier suggestions with scores
	# We collect unique next-tier values instead of full commands
	var tier_matches: Dictionary = {}  # tier_suggestion -> best_score
	for command in commands:
		var cmd_str := str(command)

		# Only consider commands that start with our current prefix
		if not cmd_str.begins_with(prefix):
			continue

		# Get the next tier for this command
		var next_tier := _get_next_tier(cmd_str, prefix)
		if next_tier.is_empty():
			continue

		# Calculate score based on the query matching the next tier's final segment
		var tier_segment := next_tier.substr(prefix.length())  # Just the segment we're completing
		var score := _calculate_match_score(tier_segment, query)
		if score >= 0:
			# Track the best score for each unique tier
			if not tier_matches.has(next_tier) or tier_matches[next_tier] < score:
				tier_matches[next_tier] = score

	if tier_matches.is_empty():
		hide_autocomplete()
		return

	# Convert to array and sort by score
	var matches: Array[Dictionary] = []
	for tier in tier_matches:
		matches.append({"tier": tier, "score": tier_matches[tier]})

	# Sort by score (ascending so worst match at top, best at bottom)
	matches.sort_custom(func(a, b): return a.score < b.score)

	# Populate the ItemList
	_autocomplete_popup.clear()
	for match_data in matches:
		var tier: String = match_data.tier
		# Check if this tier is just a prefix (has sub-commands under it)
		# A tier has children if any command starts with "tier/"
		var has_children := false
		for command in commands:
			var cmd_str := str(command)
			if cmd_str.begins_with(tier + "/"):
				has_children = true
				break
		var display_text := "/" + tier + ("/" if has_children else "")
		_autocomplete_popup.add_item(display_text)
		# Store the tier (without leading /) and whether it has children
		_autocomplete_popup.set_item_metadata(_autocomplete_popup.item_count - 1, {"tier": tier, "has_children": has_children})

	# Position the popup above the input line
	_position_autocomplete_popup()

	# Show the popup
	_autocomplete_popup.visible = true
	_autocomplete_selected_index = -1  # Reset selection
	_autocomplete_popup.deselect_all()


## Position the autocomplete popup above the line edit
func _position_autocomplete_popup() -> void:
	if not _autocomplete_popup or not line_edit:
		return

	# Get the line edit's global position
	var line_edit_rect := line_edit.get_global_rect()

	# Calculate popup height based on item count (max 10 items visible)
	var item_count := mini(_autocomplete_popup.item_count, 10)
	var item_height := 28  # Approximate height per item
	var popup_height := item_count * item_height + 8  # Add padding

	# Position above the line edit
	var popup_x := line_edit_rect.position.x
	var popup_y := line_edit_rect.position.y - popup_height

	# Ensure popup stays within bounds
	if popup_y < 0:
		popup_y = 0

	_autocomplete_popup.position = Vector2(popup_x, popup_y)
	_autocomplete_popup.size = Vector2(line_edit_rect.size.x, popup_height)


## Hide the autocomplete popup
func hide_autocomplete() -> void:
	if _autocomplete_popup:
		_autocomplete_popup.visible = false
		_autocomplete_selected_index = -1


## Check if autocomplete popup is visible
func is_autocomplete_visible() -> bool:
	return _autocomplete_popup and _autocomplete_popup.visible


## Select the previous item in the autocomplete (moving up visually)
func autocomplete_select_prev() -> void:
	if not _autocomplete_popup:
		return

	# If input doesn't start with /, show command history
	if line_edit and not line_edit.text.begins_with("/"):
		if not _autocomplete_popup.visible:
			# Show history popup, filtering by current text
			_update_history_popup(line_edit.text)
			if _autocomplete_popup.visible and _autocomplete_popup.item_count > 0:
				# Select the most recent (bottom) item
				_autocomplete_selected_index = _autocomplete_popup.item_count - 1
				_autocomplete_popup.select(_autocomplete_selected_index)
				_autocomplete_popup.ensure_current_is_visible()
				_apply_selected_autocomplete()
			return

	if not _autocomplete_popup.visible:
		return
	if _autocomplete_popup.item_count == 0:
		return

	if _autocomplete_selected_index <= 0:
		_autocomplete_selected_index = _autocomplete_popup.item_count - 1
	else:
		_autocomplete_selected_index -= 1

	_autocomplete_popup.select(_autocomplete_selected_index)
	_autocomplete_popup.ensure_current_is_visible()
	_apply_selected_autocomplete()


## Select the next item in the autocomplete (moving down visually)
func autocomplete_select_next() -> void:
	if not _autocomplete_popup or not _autocomplete_popup.visible:
		return
	if _autocomplete_popup.item_count == 0:
		return

	if _autocomplete_selected_index < 0 or _autocomplete_selected_index >= _autocomplete_popup.item_count - 1:
		# Start from bottom (best match) when pressing up initially
		_autocomplete_selected_index = _autocomplete_popup.item_count - 1
	else:
		_autocomplete_selected_index += 1

	_autocomplete_popup.select(_autocomplete_selected_index)
	_autocomplete_popup.ensure_current_is_visible()
	_apply_selected_autocomplete()


## Apply the currently selected autocomplete suggestion to the line edit
func _apply_selected_autocomplete() -> void:
	if _autocomplete_selected_index < 0 or _autocomplete_selected_index >= _autocomplete_popup.item_count:
		return

	var metadata = _autocomplete_popup.get_item_metadata(_autocomplete_selected_index)
	if metadata is Dictionary:
		# Check if this is a history item
		if metadata.get("history", false):
			line_edit.text = metadata.get("command", "")
		else:
			var tier: String = metadata.get("tier", "")
			var has_children: bool = metadata.get("has_children", false)
			# If it has children, add trailing / to allow further completion
			line_edit.text = "/" + tier + ("/" if has_children else "")
	else:
		# Fallback for old-style string metadata
		var selected_text := _autocomplete_popup.get_item_text(_autocomplete_selected_index)
		line_edit.text = selected_text
	line_edit.caret_column = line_edit.text.length()


## Confirm the autocomplete selection and close the popup
## If the selected tier has children, show the next level instead of closing
func confirm_autocomplete() -> void:
	if _autocomplete_selected_index >= 0:
		var metadata = _autocomplete_popup.get_item_metadata(_autocomplete_selected_index)
		_apply_selected_autocomplete()

		# History items just close the popup
		if metadata is Dictionary and metadata.get("history", false):
			hide_autocomplete()
			line_edit.grab_focus()
			return

		# If this tier has children, update the popup to show next level
		if metadata is Dictionary and metadata.get("has_children", false):
			update_autocomplete_popup()
			line_edit.grab_focus()
			return

	hide_autocomplete()
	line_edit.grab_focus()


## Handle autocomplete via Tab key (legacy behavior + popup support)
func autocomplete() -> void:
	if _autocomplete_popup and _autocomplete_popup.visible:
		# If popup is visible and something is selected, confirm it
		if _autocomplete_selected_index >= 0:
			confirm_autocomplete()
		else:
			# Select the bottom item (best match) and confirm
			if _autocomplete_popup.item_count > 0:
				_autocomplete_selected_index = _autocomplete_popup.item_count - 1
				confirm_autocomplete()
		return

	# Legacy behavior for when popup is not used (updated for multi-tier)
	var commands := _get_commands()
	if commands.is_empty():
		return

	var text := line_edit.text
	if not text.begins_with("/"):
		return

	var full_text := text.substr(1)  # Remove leading /

	# Determine current prefix
	var prefix := ""
	var last_slash := full_text.rfind("/")
	if last_slash != -1:
		prefix = full_text.substr(0, last_slash + 1)

	if _suggesting:
		for i in range(_suggestions.size()):
			if _current_suggest == i:
				var suggestion: Dictionary = _suggestions[i]
				var tier: String = suggestion.get("tier", "")
				var has_children: bool = suggestion.get("has_children", false)
				line_edit.text = "/" + tier + ("/" if has_children else "")
				line_edit.caret_column = line_edit.text.length()

				# If has children, refresh suggestions for the new prefix
				if has_children:
					_suggesting = false
					_suggestions.clear()
					_current_suggest = 0
					return

				if _current_suggest == _suggestions.size() - 1:
					_current_suggest = 0
				else:
					_current_suggest += 1
				return
	else:
		_suggesting = true
		# Build tier-based suggestions
		var tier_matches: Dictionary = {}
		for command in commands:
			var cmd_str := str(command)
			if not cmd_str.begins_with(prefix):
				continue
			var next_tier := _get_next_tier(cmd_str, prefix)
			if next_tier.is_empty():
				continue
			if not tier_matches.has(next_tier):
				var has_children := false
				for c in commands:
					if str(c).begins_with(next_tier + "/"):
						has_children = true
						break
				tier_matches[next_tier] = {"tier": next_tier, "has_children": has_children}

		for tier in tier_matches:
			_suggestions.append(tier_matches[tier])

		_suggestions.sort_custom(func(a, b): return a.tier < b.tier)
		autocomplete()


## Reset autocomplete state
func reset_autocomplete() -> void:
	_suggestions.clear()
	_current_suggest = 0
	_suggesting = false
	hide_autocomplete()


## Add a command to the history
func add_to_command_history(command: String) -> void:
	if command.is_empty():
		return
	# Remove duplicate if it exists
	var existing_index := _command_history.find(command)
	if existing_index != -1:
		_command_history.remove_at(existing_index)
	# Add to end (most recent)
	_command_history.append(command)
	# Trim history if too large
	while _command_history.size() > _max_history_size:
		_command_history.remove_at(0)


## Update autocomplete popup to show command history
func _update_history_popup(query: String = "") -> void:
	if not _autocomplete_popup or not line_edit:
		return

	if _command_history.is_empty():
		hide_autocomplete()
		return

	# Filter history by query if provided
	var filtered_history: Array[String] = []
	var query_lower := query.to_lower()
	for cmd in _command_history:
		if query.is_empty() or cmd.to_lower().contains(query_lower):
			filtered_history.append(cmd)

	if filtered_history.is_empty():
		hide_autocomplete()
		return

	# Populate the ItemList (oldest first, newest at bottom)
	_autocomplete_popup.clear()
	for cmd in filtered_history:
		_autocomplete_popup.add_item(cmd)
		_autocomplete_popup.set_item_metadata(_autocomplete_popup.item_count - 1, {"history": true, "command": cmd})

	# Position the popup above the input line
	_position_autocomplete_popup()

	# Show the popup
	_autocomplete_popup.visible = true
	_autocomplete_selected_index = -1
	_autocomplete_popup.deselect_all()


## Handle text changes for autocomplete
func on_text_changed_autocomplete(new_text: String) -> void:
	# Reset old autocomplete state
	_suggestions.clear()
	_current_suggest = 0
	_suggesting = false

	if new_text.begins_with("/"):
		# It's a command being typed, show autocomplete popup
		if _search_filter != "":
			_search_filter = ""
			_rebuild_display()
		update_autocomplete_popup()
	else:
		# Apply search filter and hide autocomplete
		hide_autocomplete()
		_search_filter = new_text.strip_edges().to_lower()
		_rebuild_display()
