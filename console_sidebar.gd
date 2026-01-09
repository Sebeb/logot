@tool
class_name ConsoleSidebar
extends PanelContainer

const LogLevel = preload("res://addons/logot/log_level.gd")

## Shared sidebar component used by both in-game console and editor panel.
## Uses Godot's Tree component with tri-state checkboxes:
## - Checked: SHOWN (visible)
## - Indeterminate [-]: HIDDEN (logged but not displayed)
## - Unchecked: OFF (not logged at all)

const DEFAULT_CHANNEL_DISPLAY_NAME := "General"

const LEVEL_COLORS := {
	LogLevel.ERROR: Color8(204, 101, 102),
	LogLevel.WARN: Color8(240, 198, 116),
	LogLevel.COMMAND: Color8(133, 255, 98),
	LogLevel.MESSAGE: Color8(255, 255, 255),
	LogLevel.INFO: Color8(136, 215, 179),
	LogLevel.VERBOSE: Color8(210, 180, 162),
	LogLevel.DEBUG: Color8(128, 128, 128),
}

# Visibility modes
enum VisibilityMode { SHOWN, HIDDEN, OFF }

# =============================================================================
# SIGNALS
# =============================================================================
signal level_visibility_changed(level: int, mode: int)
signal channel_visibility_changed(channel: String, mode: int)
signal setting_changed(setting_name: String, value: bool)

# =============================================================================
# UI COMPONENTS (assigned from scene)
# =============================================================================
@onready var _tree: Tree = $SidebarTree

# Tree item references
var _levels_root: TreeItem
var _channels_root: TreeItem
var _settings_root: TreeItem

var _level_items: Dictionary = {}    # {LogLevel.X: TreeItem}
var _channel_items: Dictionary = {}  # {"channel": TreeItem}
var _settings_items: Dictionary = {}  # {"setting_name": TreeItem}

# =============================================================================
# STATE
# =============================================================================
var _level_visibility: Dictionary = {}
var _channel_visibility: Dictionary = {}
var _known_channels: Array[String] = []

# Level statistics: {LogLevel.X: {shown: int, hidden: int, off: int}}
var _level_stats: Dictionary = {}
# Channel statistics: {"channel": {shown: int, hidden: int, off: int}}
var _channel_stats: Dictionary = {}

# Settings state
var _settings: Dictionary = {}

# Available settings configuration
# Each entry: {name: String, default: bool}
var _available_settings: Array[Dictionary] = []


func _ready() -> void:
	_setup_tree()
	_init_default_levels()
	_rebuild_ui()


func _setup_tree() -> void:
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)

	_tree.set_column_clip_content(0, false)
	_tree.set_column_clip_content(1, false)
	_tree.item_edited.connect(_on_tree_item_edited)

	# Create invisible root
	var root := _tree.create_item()

	# Create section roots
	_levels_root = _tree.create_item(root)
	_levels_root.set_text(0, "Levels")
	_levels_root.set_selectable(0, false)
	_levels_root.set_selectable(1, false)

	_channels_root = _tree.create_item(root)
	_channels_root.set_text(0, "Channels")
	_channels_root.set_selectable(0, false)
	_channels_root.set_selectable(1, false)

	_settings_root = _tree.create_item(root)
	_settings_root.set_text(0, "Settings")
	_settings_root.set_selectable(0, false)
	_settings_root.set_selectable(1, false)


func _init_default_levels() -> void:
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		if level not in _level_visibility:
			_level_visibility[level] = VisibilityMode.SHOWN
		if level not in _level_stats:
			_level_stats[level] = {"shown": 0, "hidden": 0, "off": 0}

	# Ensure "General" channel exists
	if "" not in _known_channels:
		_known_channels.append("")
		_channel_visibility[""] = VisibilityMode.SHOWN
		_channel_stats[""] = {"shown": 0, "hidden": 0, "off": 0}


# =============================================================================
# PUBLIC API
# =============================================================================

## Configure available settings for this sidebar
## settings_config: Array of {name: String, label: String, default: bool}
func configure_settings(settings_config: Array) -> void:
	_available_settings.clear()
	for config in settings_config:
		_available_settings.append(config)
		if config.name not in _settings:
			_settings[config.name] = config.get("default", false)

	_rebuild_settings_items()


## Get a setting value
func get_setting(name: String) -> bool:
	return _settings.get(name, false)


## Set a setting value
func set_setting(name: String, value: bool) -> void:
	_settings[name] = value
	if _settings_items.has(name):
		_settings_items[name].set_checked(0, value)


## Add a channel if not already known
func add_channel(channel: String) -> void:
	if channel not in _known_channels:
		_known_channels.append(channel)
		if channel not in _channel_visibility:
			_channel_visibility[channel] = VisibilityMode.SHOWN
		if channel not in _channel_stats:
			_channel_stats[channel] = {"shown": 0, "hidden": 0, "off": 0}
		_rebuild_ui()


## Get level visibility mode
func get_level_visibility(level: int) -> int:
	return _level_visibility.get(level, VisibilityMode.SHOWN)


## Set level visibility mode
func set_level_visibility(level: int, mode: int) -> void:
	_level_visibility[level] = mode
	_update_ui()


## Get channel visibility mode
func get_channel_visibility(channel: String) -> int:
	return _channel_visibility.get(channel, VisibilityMode.SHOWN)


## Set channel visibility mode
func set_channel_visibility(channel: String, mode: int) -> void:
	_channel_visibility[channel] = mode
	_update_ui()


## Update statistics for a level
func set_level_stats(level: int, shown: int, hidden: int, off: int) -> void:
	_level_stats[level] = {"shown": shown, "hidden": hidden, "off": off}
	_update_stats_display()


## Update statistics for a channel
func set_channel_stats(channel: String, shown: int, hidden: int, off: int) -> void:
	_channel_stats[channel] = {"shown": shown, "hidden": hidden, "off": off}
	_update_stats_display()


## Reset all statistics to zero
func reset_stats() -> void:
	for level in _level_stats:
		_level_stats[level] = {"shown": 0, "hidden": 0, "off": 0}
	for channel in _channel_stats:
		_channel_stats[channel] = {"shown": 0, "hidden": 0, "off": 0}
	_update_stats_display()


## Load visibility settings from a ConfigFile
func load_from_config(config: ConfigFile) -> void:
	if config.has_section("levels"):
		for key in config.get_section_keys("levels"):
			_level_visibility[int(key)] = config.get_value("levels", key)

	if config.has_section("channels"):
		for key in config.get_section_keys("channels"):
			var channel := "" if key == "__general__" else key
			_channel_visibility[channel] = config.get_value("channels", key)
			if channel not in _known_channels:
				_known_channels.append(channel)
				_channel_stats[channel] = {"shown": 0, "hidden": 0, "off": 0}

	if config.has_section("settings"):
		for setting in _available_settings:
			var setting_name: String = setting.name
			if config.has_section_key("settings", setting_name):
				_settings[setting_name] = config.get_value("settings", setting_name)

	_rebuild_ui()


## Save visibility settings to a ConfigFile
func save_to_config(config: ConfigFile) -> void:
	for level in _level_visibility:
		config.set_value("levels", str(level), _level_visibility[level])

	for channel in _channel_visibility:
		var key: String = channel if channel != "" else "__general__"
		config.set_value("channels", key, _channel_visibility[channel])

	for setting in _available_settings:
		config.set_value("settings", setting.name, _settings.get(setting.name, setting.get("default", false)))


## Get all level visibilities
func get_all_level_visibilities() -> Dictionary:
	return _level_visibility.duplicate()


## Get all channel visibilities
func get_all_channel_visibilities() -> Dictionary:
	return _channel_visibility.duplicate()


## Get known channels
func get_known_channels() -> Array[String]:
	return _known_channels.duplicate()


# =============================================================================
# TREE BUILDING
# =============================================================================

func _rebuild_ui() -> void:
	if not _tree or not _levels_root or not _channels_root:
		return

	# Clear existing level items
	var level_child := _levels_root.get_first_child()
	while level_child:
		var next := level_child.get_next()
		_levels_root.remove_child(level_child)
		level_child.free()
		level_child = next

	# Clear existing channel items
	var channel_child := _channels_root.get_first_child()
	while channel_child:
		var next := channel_child.get_next()
		_channels_root.remove_child(channel_child)
		channel_child.free()
		channel_child = next

	_level_items.clear()
	_channel_items.clear()

	# Build level items
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		_add_level_tree_item(level)

	# Build channel items
	for channel in _known_channels:
		_add_channel_tree_item(channel)

	_update_ui()


func _rebuild_settings_items() -> void:
	if not _tree or not _settings_root:
		return

	# Clear existing settings items
	var settings_child := _settings_root.get_first_child()
	while settings_child:
		var next := settings_child.get_next()
		_settings_root.remove_child(settings_child)
		settings_child.free()
		settings_child = next

	_settings_items.clear()

	# Build settings items
	for setting in _available_settings:
		var item := _tree.create_item(_settings_root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, setting.get("label", setting.name))
		item.set_editable(0, true)
		item.set_checked(0, _settings.get(setting.name, setting.get("default", false)))
		item.set_selectable(0, false)
		item.set_selectable(1, false)
		item.set_metadata(0, {"type": "setting", "name": setting.name})
		_settings_items[setting.name] = item


func _add_level_tree_item(level: int) -> void:
	var item := _tree.create_item(_levels_root)
	var level_name: String = LogLevel.names.get(level, "UNKNOWN").capitalize()
	var color: Color = LEVEL_COLORS.get(level, Color.WHITE)

	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_text(0, level_name)
	item.set_custom_color(0, color)
	item.set_editable(0, true)
	item.set_selectable(0, false)
	item.set_selectable(1, false)

	# Store level in metadata for callback
	item.set_metadata(0, {"type": "level", "value": level})

	# Set initial checkbox state
	_update_tree_item_checkbox(item, _level_visibility.get(level, VisibilityMode.SHOWN))

	# Stats in column 1
	item.set_text(1, "(0/0/0)")
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)

	_level_items[level] = item


func _add_channel_tree_item(channel: String) -> void:
	var item := _tree.create_item(_channels_root)
	var display_name := channel if channel != "" else DEFAULT_CHANNEL_DISPLAY_NAME

	item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	item.set_text(0, display_name)
	item.set_editable(0, true)
	item.set_selectable(0, false)
	item.set_selectable(1, false)

	# Store channel in metadata for callback
	item.set_metadata(0, {"type": "channel", "value": channel})

	# Set initial checkbox state
	_update_tree_item_checkbox(item, _channel_visibility.get(channel, VisibilityMode.SHOWN))

	# Stats in column 1
	item.set_text(1, "(0/0/0)")
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
	item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)

	_channel_items[channel] = item


## Update a tree item's checkbox to reflect visibility mode
## SHOWN = checked, HIDDEN = indeterminate ([-]), OFF = unchecked
func _update_tree_item_checkbox(item: TreeItem, mode: int) -> void:
	match mode:
		VisibilityMode.SHOWN:
			item.set_checked(0, true)
			item.set_indeterminate(0, false)
		VisibilityMode.HIDDEN:
			item.set_checked(0, false)
			item.set_indeterminate(0, true)
		VisibilityMode.OFF:
			item.set_checked(0, false)
			item.set_indeterminate(0, false)


func _update_ui() -> void:
	# Update level items
	for level in _level_items:
		var item: TreeItem = _level_items[level]
		var mode = _level_visibility.get(level, VisibilityMode.SHOWN)
		_update_tree_item_checkbox(item, mode)

	# Update channel items
	for channel in _channel_items:
		var item: TreeItem = _channel_items[channel]
		var mode = _channel_visibility.get(channel, VisibilityMode.SHOWN)
		_update_tree_item_checkbox(item, mode)

	# Update settings items
	for setting_name in _settings_items:
		_settings_items[setting_name].set_checked(0, _settings.get(setting_name, false))

	_update_stats_display()


func _update_stats_display() -> void:
	# Update level stats
	for level in _level_items:
		var item: TreeItem = _level_items[level]
		var stats = _level_stats.get(level, {"shown": 0, "hidden": 0, "off": 0})
		item.set_text(1, "(%d/%d/%d)" % [stats.shown, stats.hidden, stats.off])
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)

	# Update channel stats
	for channel in _channel_items:
		var item: TreeItem = _channel_items[channel]
		var stats = _channel_stats.get(channel, {"shown": 0, "hidden": 0, "off": 0})
		item.set_text(1, "(%d/%d/%d)" % [stats.shown, stats.hidden, stats.off])
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text_overrun_behavior(1, TextServer.OVERRUN_NO_TRIMMING)


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_tree_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null:
		return

	var metadata = item.get_metadata(0)
	if not metadata is Dictionary:
		return

	var item_type: String = metadata.get("type", "")

	match item_type:
		"setting":
			var setting_name: String = metadata.get("name", "")
			_settings[setting_name] = item.is_checked(0)
			setting_changed.emit(setting_name, _settings[setting_name])

		"level":
			var level: int = metadata.get("value", 0)
			_cycle_level_visibility(level)

		"channel":
			var channel: String = metadata.get("value", "")
			_cycle_channel_visibility(channel)


func _cycle_level_visibility(level: int) -> void:
	var current = _level_visibility.get(level, VisibilityMode.SHOWN)
	var next_mode = (current + 1) % 3
	_level_visibility[level] = next_mode
	_update_ui()
	level_visibility_changed.emit(level, next_mode)


func _cycle_channel_visibility(channel: String) -> void:
	var current = _channel_visibility.get(channel, VisibilityMode.SHOWN)
	var next_mode = (current + 1) % 3
	_channel_visibility[channel] = next_mode
	_update_ui()
	channel_visibility_changed.emit(channel, next_mode)
