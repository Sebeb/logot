@tool
extends Control

## Editor panel for displaying console logs.
## Creates a ConsoleDisplay and adds console.tscn as its child.
## Configures it for editor use.

const ConsoleDisplay = preload("res://addons/logot/console_display.gd")
const CONSOLE_UI_SCENE := preload("res://addons/logot/console.tscn")
const SETTINGS_FILE := "user://console_editor_filters.cfg"

# UI reference - the actual display component
var _display

# Editor-specific settings
var _clear_on_play := true

# Guard against recursive clear
var _clearing := false

# Console connection
var _console = null
var _console_connected := false
var _connect_in_progress := false
var _connect_attempts := 0

const MAX_CONNECT_ATTEMPTS := 60
const CONNECT_RETRY_DELAY_SEC := 0.25


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Create the display base as a child
	_display = ConsoleDisplay.new()
	_display.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_display)

	# Add the console UI as a child of the display
	var console_ui := CONSOLE_UI_SCENE.instantiate()
	console_ui.name = "ConsoleUI"
	console_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_display.add_child(console_ui)

	# Configure for editor use
	_display.set_settings_file(SETTINGS_FILE)
	_display.set_welcome_message("Editor Console\n")
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
	var autocomplete_popup = console_ui.get_node_or_null("MainContainer/ConsoleContainer/VBoxContainer/AutocompletePopup")
	if autocomplete_popup:
		_display.set_autocomplete_popup(autocomplete_popup)

	# Connect to Console autoload
	call_deferred("_connect_to_console")


func _get_log_entries() -> Array:
	if _console and _console.has_method("get_log_entries"):
		return _console.get_log_entries()
	return []


func _get_entry_display_text(entry, truncate: bool) -> String:
	var full_text = _display._format_objects(entry.objects) if _display else str(entry.objects)

	if entry.expanded:
		var formatted_trace := ""
		if _display and entry.stack_trace != "":
			formatted_trace = _display._format_stack_trace(entry.stack_trace)
		return ConsoleDisplay.format_display_text(full_text, entry.level, entry.channel, entry.timestamp, entry.id, false, 0, entry.stack_trace, 0, formatted_trace)

	# Collapsed view
	var display_text: String
	if truncate and entry.extra_line_count > 0:
		display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
	else:
		display_text = full_text
	var extra_lines = entry.extra_line_count if truncate else 0
	return ConsoleDisplay.format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace)


func _on_custom_setting_changed(setting_name: String, value: bool) -> void:
	if setting_name == "clear_on_play":
		_clear_on_play = value
		_save_settings()


func _on_cleared() -> void:
	# Also clear the main Console's log entries (with guard to prevent recursion)
	if _clearing:
		return
	_clearing = true
	if _console and _console.has_method("_clear_logs"):
		_console._clear_logs()
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
# CONSOLE CONNECTION
# =============================================================================

func _connect_to_console() -> void:
	if _console_connected or _connect_in_progress:
		return

	_connect_in_progress = true
	while not _console_connected and _connect_attempts < MAX_CONNECT_ATTEMPTS:
		_console = _get_console()
		if _console:
			# Connect signals
			if _console.has_signal("log_entry_added") and not _console.log_entry_added.is_connected(_on_log_entry_added):
				_console.log_entry_added.connect(_on_log_entry_added)
			if _console.has_signal("logs_cleared") and not _console.logs_cleared.is_connected(_on_logs_cleared):
				_console.logs_cleared.connect(_on_logs_cleared)
			if _console.has_signal("channel_discovered") and not _console.channel_discovered.is_connected(_on_channel_discovered):
				_console.channel_discovered.connect(_on_channel_discovered)

			_console_connected = true
			_sync_existing_entries()
			break

		_connect_attempts += 1
		if _connect_attempts >= MAX_CONNECT_ATTEMPTS:
			if _display and _display.rich_label:
				_display.rich_label.append_text("Console autoload not available.\n")
			_connect_in_progress = false
			return

		if get_tree():
			await get_tree().create_timer(CONNECT_RETRY_DELAY_SEC).timeout
		else:
			break

	_connect_in_progress = false


func _get_console():
	if Engine.has_singleton("Console"):
		return Engine.get_singleton("Console")

	var root = get_tree().root if get_tree() else null
	if root and root.has_node("Console"):
		return root.get_node("Console")

	return null


func _sync_existing_entries() -> void:
	if _console and _display:
		if _console.has_method("get_known_channels"):
			for channel in _console.get_known_channels():
				_display._ensure_channel_exists(channel)
		# Set up commands provider for autocomplete
		_display.set_commands_provider(_get_commands)
		# Set up visibility providers to use console's visibility dictionaries
		if _console.has_method("get_level_visibility") and _console.has_method("set_level_visibility"):
			_display.set_level_visibility_provider(_console.get_level_visibility, _console.set_level_visibility)
		if _console.has_method("get_channel_visibility") and _console.has_method("set_channel_visibility"):
			_display.set_channel_visibility_provider(_console.get_channel_visibility, _console.set_channel_visibility)
		_display._rebuild_display()


func _get_commands() -> Dictionary:
	if _console and "console_commands" in _console:
		return _console.console_commands
	return {}


# =============================================================================
# CONSOLE SIGNAL HANDLERS
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


func _on_level_visibility_changed(level: int, mode: int) -> void:
	if _console and _console.has_method("set_level_visibility"):
		_console.set_level_visibility(level, mode)
		# Rebuild in-game display if it exists (it uses providers, so just rebuild)
		if "_display" in _console and _console._display:
			_console._display._rebuild_display()


func _on_channel_visibility_changed(channel: String, mode: int) -> void:
	if _console and _console.has_method("set_channel_visibility"):
		_console.set_channel_visibility(channel, mode)
		# Rebuild in-game display if it exists (it uses providers, so just rebuild)
		if "_display" in _console and _console._display:
			_console._display._rebuild_display()

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
		_display.line_edit.set

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
		if _console and _console.has_method("on_text_entered"):
			_console.on_text_entered(text)


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
