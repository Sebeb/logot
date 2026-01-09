@tool
extends Control

## Editor panel for displaying logot logs.
## Creates a LogotDisplay and adds logot.tscn as its child.
## Configures it for editor use.

const LogotDisplay = preload("res://addons/logot/logot_display.gd")
const LOGOT_UI_SCENE := preload("res://addons/logot/logot.tscn")
const SETTINGS_FILE := "user://logot_editor_filters.cfg"

# UI reference - the actual display component
var _display

# Editor-specific settings
var _clear_on_play := true

# Guard against recursive clear
var _clearing := false

# Logot connection
var _logot = null
var _logot_connected := false
var _connect_in_progress := false
var _connect_attempts := 0

# Debugger plugin for running game instances
var _debugger_plugin = null

# Instance log entries: {instance_id: Array[LogEntry]}
var _instance_log_entries: Dictionary = {}

# Instance statistics: {instance_id: {level: FilterStats, channel: FilterStats}}
var _instance_stats: Dictionary = {}

# Instance naming
var _instance_names: Dictionary = {}  # {session_id: String}
var _next_game_instance_number := 1

# Special session ID for the editor instance
const EDITOR_SESSION_ID := -1

const MAX_CONNECT_ATTEMPTS := 60
const CONNECT_RETRY_DELAY_SEC := 0.25


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Create the display base as a child
	_display = LogotDisplay.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_display)

	# Add the logot UI as a child of the display
	var logot_ui := LOGOT_UI_SCENE.instantiate()
	logot_ui.name = "LogotUI"
	logot_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.add_child(logot_ui)

	# Configure for editor use
	_display.set_settings_file(SETTINGS_FILE)
	_display.set_welcome_message("Editor Logot\n")
	_display.set_log_entries_provider(_get_log_entries)
	_display.set_entry_text_provider(_get_entry_display_text)

	# Add editor-specific sidebar settings
	_display.add_custom_setting("clear_on_play", "Clear on play", true)
	_display.custom_setting_changed.connect(_on_custom_setting_changed)
	_display.cleared.connect(_on_cleared)
	_display.level_visibility_changed.connect(_on_level_visibility_changed)
	_display.channel_visibility_changed.connect(_on_channel_visibility_changed)
	_display.display_rebuilt.connect(_on_display_rebuilt)

	# Initialize the display
	_display._init_base()
	_display._setup_ui_nodes()
	_display._connect_ui_signals()
	_display._setup_sidebar()
	_display._init_display()

	# Load our settings
	_load_settings()

	# Connect line edit for commands
	if _display.line_edit:
		_display.line_edit.text_submitted.connect(_on_text_entered)
		_display.line_edit.text_changed.connect(_on_text_changed)
		_display.line_edit.gui_input.connect(_on_line_edit_gui_input)

	# Set up autocomplete popup reference on the display base
	# Use explicit path since unique name lookup may not work reliably in @tool context
	var autocomplete_popup = logot_ui.get_node_or_null("MainContainer/LogotContainer/VBoxContainer/AutocompletePopup")
	if autocomplete_popup:
		_display.set_autocomplete_popup(autocomplete_popup)

	# Connect to Logot autoload
	call_deferred("_connect_to_logot")

	# Connect debugger plugin if already set
	if _debugger_plugin:
		_connect_debugger_plugin()


## Set the debugger plugin reference (called from logot_plugin.gd)
func set_debugger_plugin(plugin) -> void:
	_debugger_plugin = plugin
	_connect_debugger_plugin()


## Connect to debugger plugin signals
func _connect_debugger_plugin() -> void:
	if not _debugger_plugin:
		return

	if not _debugger_plugin.instance_started.is_connected(_on_instance_started):
		_debugger_plugin.instance_started.connect(_on_instance_started)
	if not _debugger_plugin.instance_stopped.is_connected(_on_instance_stopped):
		_debugger_plugin.instance_stopped.connect(_on_instance_stopped)
	if not _debugger_plugin.log_received.is_connected(_on_instance_log_received):
		_debugger_plugin.log_received.connect(_on_instance_log_received)
	if not _debugger_plugin.channel_discovered.is_connected(_on_instance_channel_discovered):
		_debugger_plugin.channel_discovered.connect(_on_instance_channel_discovered)
	if not _debugger_plugin.logs_cleared.is_connected(_on_instance_logs_cleared):
		_debugger_plugin.logs_cleared.connect(_on_instance_logs_cleared)


func _get_log_entries() -> Array:
	var all_entries: Array = []

	# Get editor instance entries (mark with editor session ID)
	if _logot and _logot.has_method("get_log_entries"):
		for entry in _logot.get_log_entries():
			# Mark editor entries with the editor session ID if not already set
			if entry.session_id == -1:
				entry.session_id = EDITOR_SESSION_ID
			all_entries.append(entry)

	# Get game instance entries (already have session_id set from _create_entry_from_data)
	for session_id in _instance_log_entries:
		if session_id == EDITOR_SESSION_ID:
			continue  # Skip editor entries (already added above)
		for entry in _instance_log_entries[session_id]:
			all_entries.append(entry)

	# Sort by ID to maintain chronological order
	all_entries.sort_custom(func(a, b): return a.id < b.id)

	return all_entries


func _get_entry_display_text(entry, truncate: bool) -> String:
	var full_text = _display._format_objects(entry.objects) if _display else str(entry.objects)
	var instance_name: String = entry.instance_name

	if entry.expanded:
		var formatted_trace := ""
		if _display and entry.stack_trace != "":
			formatted_trace = _display._format_stack_trace(entry.stack_trace)
		return LogotDisplay.format_display_text(full_text, entry.level, entry.channel, entry.timestamp, entry.id, false, 0, entry.stack_trace, 0, formatted_trace, instance_name)

	# Collapsed view
	var display_text: String
	if truncate and entry.extra_line_count > 0:
		display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
	else:
		display_text = full_text
	var extra_lines = entry.extra_line_count if truncate else 0
	return LogotDisplay.format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace, 0, "", instance_name)


func _on_custom_setting_changed(setting_name: String, value: bool) -> void:
	if setting_name == "clear_on_play":
		_clear_on_play = value
		_save_settings()


func _on_cleared() -> void:
	# Also clear the main Logot's log entries (with guard to prevent recursion)
	if _clearing:
		return
	_clearing = true
	if _logot and _logot.has_method("_clear_logs"):
		_logot._clear_logs()
	_clearing = false


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		if config.has_section("editor_settings"):
			_clear_on_play = config.get_value("editor_settings", "clear_on_play", true)

	if _display:
		_display.set_custom_setting("clear_on_play", _clear_on_play)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)  # Load existing to preserve other settings
	config.set_value("editor_settings", "clear_on_play", _clear_on_play)
	config.save(SETTINGS_FILE)


# =============================================================================
# LOGOT CONNECTION
# =============================================================================

func _connect_to_logot() -> void:
	if _logot_connected or _connect_in_progress:
		return

	_connect_in_progress = true
	while not _logot_connected and _connect_attempts < MAX_CONNECT_ATTEMPTS:
		_logot = _get_logot()
		if _logot:
			# Connect signals
			if _logot.has_signal("log_entry_added") and not _logot.log_entry_added.is_connected(_on_log_entry_added):
				_logot.log_entry_added.connect(_on_log_entry_added)
			if _logot.has_signal("logs_cleared") and not _logot.logs_cleared.is_connected(_on_logs_cleared):
				_logot.logs_cleared.connect(_on_logs_cleared)
			if _logot.has_signal("channel_discovered") and not _logot.channel_discovered.is_connected(_on_channel_discovered):
				_logot.channel_discovered.connect(_on_channel_discovered)
			if _logot.has_signal("off_log_tracked") and not _logot.off_log_tracked.is_connected(_on_off_log_tracked):
				_logot.off_log_tracked.connect(_on_off_log_tracked)

			_logot_connected = true
			_sync_existing_entries()
			break

		_connect_attempts += 1
		if _connect_attempts >= MAX_CONNECT_ATTEMPTS:
			if _display and _display.rich_label:
				_display.rich_label.append_text("Logot autoload not available.\n")
			_connect_in_progress = false
			return

		if get_tree():
			await get_tree().create_timer(CONNECT_RETRY_DELAY_SEC).timeout
		else:
			break

	_connect_in_progress = false


func _get_logot():
	if Engine.has_singleton("Logot"):
		return Engine.get_singleton("Logot")

	var root = get_tree().root if get_tree() else null
	if root and root.has_node("Logot"):
		return root.get_node("Logot")

	return null


func _sync_existing_entries() -> void:
	if _logot and _display:
		if _logot.has_method("get_known_channels"):
			for channel in _logot.get_known_channels():
				_display._ensure_channel_exists(channel)
		# Set up commands provider for autocomplete
		_display.set_commands_provider(_get_commands)

		# Before setting up providers, capture the loaded visibility settings from display
		# These were loaded from config in _init_base() before providers were set
		var loaded_level_visibility: Dictionary = _display._level_visibility.duplicate()
		var loaded_channel_visibility: Dictionary = _display._channel_visibility.duplicate()

		# Set up visibility providers to use logot's visibility dictionaries
		if _logot.has_method("get_level_visibility") and _logot.has_method("set_level_visibility"):
			_display.set_level_visibility_provider(_logot.get_level_visibility, _logot.set_level_visibility)
		if _logot.has_method("get_channel_visibility") and _logot.has_method("set_channel_visibility"):
			_display.set_channel_visibility_provider(_logot.get_channel_visibility, _logot.set_channel_visibility)

		# Apply the loaded visibility settings to the Logot
		# This ensures filter state from config is applied at startup
		for level in loaded_level_visibility:
			_logot.set_level_visibility(level, loaded_level_visibility[level])
		for channel in loaded_channel_visibility:
			_logot.set_channel_visibility(channel, loaded_channel_visibility[channel])

		# Set up rejected count providers for OFF stats
		if _logot.has_method("get_rejected_level_count"):
			_display.set_rejected_level_count_provider(_logot.get_rejected_level_count)
		if _logot.has_method("get_rejected_channel_count"):
			_display.set_rejected_channel_count_provider(_logot.get_rejected_channel_count)

		# Set up instance visibility provider
		_display.set_instance_visibility_provider(_get_instance_visibility)

		# Add "Editor" as the first instance
		_register_editor_instance()

		_display._rebuild_display()


## Register the Editor as a special instance
func _register_editor_instance() -> void:
	if not _display or not _display._sidebar:
		return

	_instance_names[EDITOR_SESSION_ID] = "Editor"
	_instance_log_entries[EDITOR_SESSION_ID] = []
	_instance_stats[EDITOR_SESSION_ID] = {"level": {}, "channel": {}}

	_display._sidebar.add_instance(EDITOR_SESSION_ID, "Editor")

	# Connect to instance visibility changes
	if not _display._sidebar.instance_visibility_changed.is_connected(_on_instance_visibility_changed):
		_display._sidebar.instance_visibility_changed.connect(_on_instance_visibility_changed)

	# Log the editor instance registration
	_log_instance_event("[color=cyan]Instance connected:[/color] Editor")


func _get_commands() -> Dictionary:
	if _logot and "console_commands" in _logot:
		return _logot.console_commands
	return {}


## Get instance visibility mode for a session_id (used as provider for display)
func _get_instance_visibility(session_id: int) -> int:
	if _display and _display._sidebar:
		return _display._sidebar.get_instance_visibility(session_id)
	return LogotDisplay.VisibilityMode.SHOWN


# =============================================================================
# LOGOT SIGNAL HANDLERS
# =============================================================================

func _on_log_entry_added(entry) -> void:
	if not _display:
		return

	# Mark entry with editor session ID
	entry.session_id = EDITOR_SESSION_ID

	# Check if Editor instance is OFF (don't even track the entry)
	if _display._sidebar:
		var instance_mode = _display._sidebar.get_instance_visibility(EDITOR_SESSION_ID)
		if instance_mode == LogotDisplay.VisibilityMode.OFF:
			_update_instance_off_stats(EDITOR_SESSION_ID, {
				"level": entry.level,
				"channel": entry.channel
			})
			return

	_display._ensure_channel_exists(entry.channel)
	_display._update_stats_for_entry(entry)
	_update_instance_stats(EDITOR_SESSION_ID, entry)

	# _should_display now handles level, channel, AND instance visibility
	if _display._should_display(entry):
		_display._display_entry(entry)

	_display._update_sidebar_stats()
	_update_sidebar_instance_stats()


func _on_logs_cleared() -> void:
	# Guard to prevent recursion when we initiated the clear
	if _clearing:
		return
	_clearing = true
	if _display:
		_display._clear_logs()
	_clearing = false


func _on_channel_discovered(channel: String) -> void:
	if _display:
		_display._ensure_channel_exists(channel)


func _on_off_log_tracked(level: int, channel: String) -> void:
	if _display:
		_display._ensure_level_exists(level)
		_display._ensure_channel_exists(channel)
		_display._update_sidebar_stats()


func _on_level_visibility_changed(level: int, mode: int) -> void:
	if _logot and _logot.has_method("set_level_visibility"):
		_logot.set_level_visibility(level, mode)
		# Rebuild in-game display if it exists (it uses providers, so just rebuild)
		if "_display" in _logot and _logot._display:
			_logot._display._rebuild_display()


func _on_channel_visibility_changed(channel: String, mode: int) -> void:
	if _logot and _logot.has_method("set_channel_visibility"):
		_logot.set_channel_visibility(channel, mode)
		# Rebuild in-game display if it exists (it uses providers, so just rebuild)
		if "_display" in _logot and _logot._display:
			_logot._display._rebuild_display()


func _on_display_rebuilt() -> void:
	# Update instance stats after any display rebuild (level/channel/instance visibility changes)
	_update_sidebar_instance_stats()


# =============================================================================
# INSTANCE SIGNAL HANDLERS (from debugger plugin)
# =============================================================================

func _on_instance_started(session_id: int) -> void:
	if not _display:
		# Defer until display is ready
		call_deferred("_on_instance_started", session_id)
		return

	# Register if not already registered
	if session_id not in _instance_names:
		_register_game_instance(session_id)

	# Log the connection
	var instance_name := _instance_names.get(session_id, "Unknown")
	_log_instance_event("[color=cyan]Instance connected:[/color] %s" % instance_name)


## Register a game instance with a generated name and initialize storage
func _register_game_instance(session_id: int) -> void:
	# Generate a meaningful instance name
	var instance_name := _generate_instance_name(session_id)
	_instance_names[session_id] = instance_name

	# Initialize storage for this instance
	_instance_log_entries[session_id] = []
	_instance_stats[session_id] = {"level": {}, "channel": {}}

	# Add instance to sidebar
	if _display and _display._sidebar:
		_display._sidebar.add_instance(session_id, instance_name)

		# Connect to instance visibility changes
		if not _display._sidebar.instance_visibility_changed.is_connected(_on_instance_visibility_changed):
			_display._sidebar.instance_visibility_changed.connect(_on_instance_visibility_changed)


func _on_instance_stopped(session_id: int) -> void:
	if not _display:
		return

	# Get instance name before removing
	var instance_name := _instance_names.get(session_id, "Unknown")

	# Mark instance as inactive in sidebar (keeps stats visible)
	if _display._sidebar:
		_display._sidebar.remove_instance(session_id)

	# Log the disconnection
	_log_instance_event("[color=orange]Instance disconnected:[/color] %s" % instance_name)


## Generate a meaningful name for an instance
func _generate_instance_name(session_id: int) -> String:
	# Check if debugger plugin has a name from the game
	var game_name := ""
	if _debugger_plugin:
		game_name = _debugger_plugin.get_session_name(session_id)

	# If the game provided a project name, use "Game N (ProjectName)"
	# Otherwise just use "Game N"
	if game_name != "" and game_name != "Instance %d" % session_id:
		var name := "Game %d (%s)" % [_next_game_instance_number, game_name]
		_next_game_instance_number += 1
		return name
	else:
		var name := "Game %d" % _next_game_instance_number
		_next_game_instance_number += 1
		return name


## Log an instance connection/disconnection event
func _log_instance_event(message: String) -> void:
	if not _display or not _display.rich_label:
		return

	# Get current timestamp
	var time := Time.get_time_dict_from_system()
	var timestamp := "%02d:%02d:%02d" % [time.hour, time.minute, time.second]

	# Format and display the message
	var formatted := "[color=dim_gray]%s[/color] %s\n" % [timestamp, message]
	_display.rich_label.append_text(formatted)


func _on_instance_log_received(session_id: int, entry_data: Dictionary) -> void:
	if not _display:
		return

	# Auto-register instance if not already registered (handles race condition)
	if session_id not in _instance_names:
		_register_game_instance(session_id)

	# Check if this instance is OFF (don't even track the entry)
	if _display._sidebar:
		var instance_mode = _display._sidebar.get_instance_visibility(session_id)
		if instance_mode == LogotDisplay.VisibilityMode.OFF:
			_update_instance_off_stats(session_id, entry_data)
			return

	# Reconstruct LogEntry from the data (includes session_id)
	var entry = _create_entry_from_data(entry_data, session_id)

	# Store in instance log entries
	_instance_log_entries[session_id].append(entry)

	_display._ensure_channel_exists(entry.channel)
	_display._update_stats_for_entry(entry)
	_update_instance_stats(session_id, entry)

	# _should_display now handles level, channel, AND instance visibility
	if _display._should_display(entry):
		_display._display_entry(entry)

	_display._update_sidebar_stats()
	_update_sidebar_instance_stats()


func _on_instance_channel_discovered(session_id: int, channel: String) -> void:
	if _display:
		_display._ensure_channel_exists(channel)


func _on_instance_logs_cleared(session_id: int) -> void:
	if session_id in _instance_log_entries:
		_instance_log_entries[session_id].clear()
	if session_id in _instance_stats:
		_instance_stats[session_id] = {"level": {}, "channel": {}}
	# Instance stats will be updated via display_rebuilt signal
	if _display:
		_display._rebuild_display()


func _on_instance_visibility_changed(instance_id: int, mode: int) -> void:
	# Rebuild display to reflect visibility change
	# Instance stats will be updated via the display_rebuilt signal
	if _display:
		_display._rebuild_display()


## Create a LogEntry from serialized data received from game instance
func _create_entry_from_data(data: Dictionary, session_id: int) -> LogotDisplay.LogEntry:
	# Get the instance name for this session
	var instance_name := _instance_names.get(session_id, "")

	var entry = LogotDisplay.LogEntry.new(
		data.get("id", 0),
		data.get("level", 0),
		data.get("channel", ""),
		data.get("objects", []),
		data.get("formatted", ""),
		data.get("formatted_full", ""),
		data.get("stack_trace", ""),
		data.get("extra_line_count", 0),
		data.get("timestamp", ""),
		instance_name,
		session_id
	)
	return entry


## Update stats for a specific instance
func _update_instance_stats(session_id: int, entry) -> void:
	if session_id not in _instance_stats:
		_instance_stats[session_id] = {"level": {}, "channel": {}}

	var stats = _instance_stats[session_id]

	# Update level stats
	if entry.level not in stats.level:
		stats.level[entry.level] = {"shown": 0, "hidden": 0, "off": 0}
	stats.level[entry.level].shown += 1

	# Update channel stats
	if entry.channel not in stats.channel:
		stats.channel[entry.channel] = {"shown": 0, "hidden": 0, "off": 0}
	stats.channel[entry.channel].shown += 1


## Update stats when an instance log is rejected due to OFF visibility
func _update_instance_off_stats(session_id: int, entry_data: Dictionary) -> void:
	if session_id not in _instance_stats:
		_instance_stats[session_id] = {"level": {}, "channel": {}}

	var stats = _instance_stats[session_id]
	var level: int = entry_data.get("level", 0)
	var channel: String = entry_data.get("channel", "")

	if level not in stats.level:
		stats.level[level] = {"shown": 0, "hidden": 0, "off": 0}
	stats.level[level].off += 1

	if channel not in stats.channel:
		stats.channel[channel] = {"shown": 0, "hidden": 0, "off": 0}
	stats.channel[channel].off += 1

	_update_sidebar_instance_stats()


## Update sidebar with instance statistics
## Recalculates shown/hidden counts based on current visibility state of all filters
func _update_sidebar_instance_stats() -> void:
	if not _display or not _display._sidebar:
		return

	# Recalculate stats for each instance based on current visibility
	var instance_counts: Dictionary = {}  # {session_id: {shown: int, hidden: int, off: int}}

	# Initialize counts for all known instances (include OFF counts from rejected logs)
	for session_id in _instance_names:
		var off_count := 0
		# Sum up OFF counts from _instance_stats (logs rejected due to OFF visibility)
		if session_id in _instance_stats:
			var stats = _instance_stats[session_id]
			for level in stats.level:
				off_count += stats.level[level].off
		instance_counts[session_id] = {"shown": 0, "hidden": 0, "off": off_count}

	# Count entries based on current visibility of ALL filters (level, channel, instance)
	for entry in _get_log_entries():
		var session_id: int = entry.session_id
		if session_id not in instance_counts:
			instance_counts[session_id] = {"shown": 0, "hidden": 0, "off": 0}

		# Use _should_display which checks all visibility filters (level, channel, instance)
		if _display._should_display(entry):
			instance_counts[session_id].shown += 1
		else:
			instance_counts[session_id].hidden += 1

	# Update sidebar with recalculated stats
	for session_id in instance_counts:
		var counts = instance_counts[session_id]
		_display._sidebar.set_instance_stats(session_id, counts.shown, counts.hidden, counts.off)


# =============================================================================
# INPUT HANDLING
# =============================================================================

func _on_text_entered(text: String) -> void:
	if _display:
		_display.hide_autocomplete()

	if _display and _display.line_edit:
		_display.line_edit.clear()
		# Ensure focus remains in the input box after submitting
		_display.line_edit.grab_focus()

	if _display:
		_display._search_filter = ""
		_display._rebuild_display()

	if text.strip_edges().is_empty():
		return

	# Add to command history
	if _display:
		_display.add_to_command_history(text)

	# Commands start with /
	if text.begins_with("/"):
		if _logot and _logot.has_method("on_text_entered"):
			_logot.on_text_entered(text)


func _on_text_changed(new_text: String) -> void:
	if not _display:
		return
	_display.on_text_changed_autocomplete(new_text)


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
			_display.line_edit.accept_event()
		elif key_event.keycode == KEY_UP:
			_display.autocomplete_select_prev()
			_display.line_edit.accept_event()
		elif key_event.keycode == KEY_TAB:
			_display.confirm_autocomplete()
			_display.line_edit.accept_event()
		elif key_event.keycode == KEY_ESCAPE:
			_display.hide_autocomplete()
			_display.line_edit.accept_event()
	else:
		# UP arrow when autocomplete not visible - show history
		if key_event.keycode == KEY_UP:
			_display.autocomplete_select_prev()
			_display.line_edit.accept_event()


# =============================================================================
# GAME LIFECYCLE
# =============================================================================

func on_game_started() -> void:
	if _clear_on_play and _display:
		_display._clear_logs()
