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


func _get_log_entries() -> Array:
	if _logot and _logot.has_method("get_log_entries"):
		return _logot.get_log_entries()
	return []


func _get_entry_display_text(entry, truncate: bool) -> String:
	var full_text = _display._format_objects(entry.objects) if _display else str(entry.objects)

	if entry.expanded:
		var formatted_trace := ""
		if _display and entry.stack_trace != "":
			formatted_trace = _display._format_stack_trace(entry.stack_trace)
		return LogotDisplay.format_display_text(full_text, entry.level, entry.channel, entry.timestamp, entry.id, false, 0, entry.stack_trace, 0, formatted_trace)

	# Collapsed view
	var display_text: String
	if truncate and entry.extra_line_count > 0:
		display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
	else:
		display_text = full_text
	var extra_lines = entry.extra_line_count if truncate else 0
	return LogotDisplay.format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace)


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
		_display._rebuild_display()


func _get_commands() -> Dictionary:
	if _logot and "console_commands" in _logot:
		return _logot.console_commands
	return {}


# =============================================================================
# LOGOT SIGNAL HANDLERS
# =============================================================================

func _on_log_entry_added(entry) -> void:
	if not _display:
		return
	_display._ensure_channel_exists(entry.channel)
	_display._update_stats_for_entry(entry)

	if _display._should_display(entry):
		_display._display_entry(entry)

	_display._update_sidebar_stats()


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
