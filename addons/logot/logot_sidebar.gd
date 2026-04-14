@tool
class_name LogotSidebar
extends PanelContainer

const LogLevel = preload("res://addons/logot/log_level.gd")

## Shared sidebar component used by both in-game logot and editor panel.
## Uses Godot's Tree component with clickable icons:
## - Visible icon: SHOWN (visible)
## - Hidden icon: HIDDEN (logged but not displayed)
## - Off icon: OFF (not logged at all)
## Left-click toggles between SHOWN and HIDDEN, right-click toggles OFF.

const DEFAULT_CHANNEL_DISPLAY_NAME := "General"

# Tree column indices
const COL_NAME := 0        # Name/label column (expands)
const COL_OFF := 1         # Off count column (fixed)
const COL_HIDDEN := 2      # Hidden count column (fixed)
const COL_SHOWN := 3       # Shown count column (fixed)
const COL_ICON := 4        # Icon button / checkbox column (fixed, far right)

# Stats column colors
const COLOR_SHOWN := Color.WHITE
const COLOR_HIDDEN := Color(1, 1, 1, 0.65)  # Semi-transparent white
const COLOR_OFF := Color(1, 1, 1, 0.3)     # Semi-transparent white

# Visibility icons
const ICON_VISIBLE := preload("res://addons/logot/assets/channel_visible.svg")
const ICON_HIDDEN := preload("res://addons/logot/assets/channel_hidden.svg")
const ICON_OFF := preload("res://addons/logot/assets/channel_off.svg")
const ICON_MIXED := preload("res://addons/logot/assets/channel_mixed.svg")

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
signal instance_visibility_changed(instance_id: int, mode: int)
signal setting_changed(setting_name: String, value: bool)
signal channel_deleted(channel: String)

# =============================================================================
# UI COMPONENTS (assigned from scene)
# =============================================================================
@onready var _tree: Tree = $SidebarTree

# Context menu
var _context_menu: PopupMenu
var _context_item_type: String = ""
var _context_item_value = null  # Can be int (level/instance) or String (channel)

# Tree item references
var _levels_root: TreeItem
var _channels_root: TreeItem
var _instances_root: TreeItem
var _settings_root: TreeItem

var _level_items: Dictionary = {}    # {LogLevel.X: TreeItem}
var _channel_items: Dictionary = {}  # {"channel": TreeItem}
var _instance_items: Dictionary = {}  # {instance_id: TreeItem}
var _settings_items: Dictionary = {}  # {"setting_name": TreeItem}

# Hierarchical channel tracking
var _channel_children: Dictionary = {}  # {"parent_channel": ["child1", "child2"]}
var _channel_parent: Dictionary = {}    # {"child_channel": "parent_channel"}

# =============================================================================
# STATE
# =============================================================================
var _level_visibility: Dictionary = {}
var _channel_visibility: Dictionary = {}
var _instance_visibility: Dictionary = {}  # {instance_id: VisibilityMode}
var _known_channels: Array[String] = []
var _known_instances: Dictionary = {}  # {instance_id: {name: String, number: int, active: bool}}

# Level statistics: {LogLevel.X: {shown: int, hidden: int, off: int}}
var _level_stats: Dictionary = {}
# Channel statistics: {"channel": {shown: int, hidden: int, off: int}}
var _channel_stats: Dictionary = {}
# Instance statistics: {instance_id: {shown: int, hidden: int, off: int}}
var _instance_stats: Dictionary = {}

# Settings state
var _settings: Dictionary = {}

# Available settings configuration
# Each entry: {name: String, default: bool}
var _available_settings: Array[Dictionary] = []


func _ready() -> void:
	_setup_context_menu()
	_setup_tree()
	_init_default_levels()
	_rebuild_ui()


func _setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "ContextMenu"
	add_child(_context_menu)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)


func _setup_tree() -> void:
	_tree.columns = 5
	_tree.set_column_expand(COL_NAME, true)
	_tree.set_column_expand(COL_OFF, false)
	_tree.set_column_expand(COL_HIDDEN, false)
	_tree.set_column_expand(COL_SHOWN, false)
	_tree.set_column_expand(COL_ICON, false)

	_tree.set_column_clip_content(COL_NAME, false)
	_tree.set_column_clip_content(COL_OFF, false)
	_tree.set_column_clip_content(COL_HIDDEN, false)
	_tree.set_column_clip_content(COL_SHOWN, false)
	_tree.set_column_clip_content(COL_ICON, true)
	_tree.set_column_custom_minimum_width(COL_ICON, 50)
	_tree.item_edited.connect(_on_tree_item_edited)
	_tree.button_clicked.connect(_on_tree_button_clicked)
	_tree.gui_input.connect(_on_tree_gui_input)
	_tree.item_collapsed.connect(_on_tree_item_collapsed)

	# Create invisible root
	var root := _tree.create_item()

	# Create section roots
	_levels_root = _tree.create_item(root)
	_levels_root.set_text(COL_NAME, "Levels")
	_levels_root.set_icon(COL_SHOWN, ICON_VISIBLE)
	_levels_root.set_icon(COL_HIDDEN, ICON_HIDDEN)
	_levels_root.set_icon(COL_OFF, ICON_OFF)
	_levels_root.set_tooltip_text(COL_SHOWN, "Shown Logs Count")
	_levels_root.set_tooltip_text(COL_HIDDEN, "Hidden Logs Count")
	_levels_root.set_tooltip_text(COL_OFF, "Off Logs Count")
	_set_item_not_selectable(_levels_root)

	_channels_root = _tree.create_item(root)
	_channels_root.set_text(COL_NAME, "Channels")
	_set_item_not_selectable(_channels_root)

	_instances_root = _tree.create_item(root)
	_instances_root.set_text(COL_NAME, "Instances")
	_set_item_not_selectable(_instances_root)
	_instances_root.visible = false  # Hidden until instances are detected

	_settings_root = _tree.create_item(root)
	_settings_root.set_text(COL_NAME, "Settings")
	_set_item_not_selectable(_settings_root)


## Helper to set all columns as not selectable
func _set_item_not_selectable(item: TreeItem) -> void:
	item.set_selectable(COL_NAME, false)
	item.set_selectable(COL_SHOWN, false)
	item.set_selectable(COL_HIDDEN, false)
	item.set_selectable(COL_OFF, false)
	item.set_selectable(COL_ICON, false)


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
		_settings_items[name].set_checked(COL_NAME, value)


## Add a channel if not already known
func add_channel(channel: String) -> void:
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
				add_channel(parent_path)

			# Register this channel as a child of its direct parent
			var direct_parent := "/".join(parts.slice(0, parts.size() - 1))
			if direct_parent not in _channel_children:
				_channel_children[direct_parent] = []
			if channel not in _channel_children[direct_parent]:
				_channel_children[direct_parent].append(channel)
			_channel_parent[channel] = direct_parent

		_known_channels.append(channel)
		if channel not in _channel_visibility:
			_channel_visibility[channel] = VisibilityMode.SHOWN
		if channel not in _channel_stats:
			_channel_stats[channel] = {"shown": 0, "hidden": 0, "off": 0}
		_rebuild_ui()


## Add a running instance
func add_instance(instance_id: int, instance_name: String, instance_number: int = -1) -> void:
	var needs_rebuild := false

	if instance_id not in _known_instances:
		_known_instances[instance_id] = {"name": instance_name, "number": instance_number, "active": true}
		needs_rebuild = true
	else:
		# Update existing instance
		_known_instances[instance_id].name = instance_name
		if instance_number >= 0:
			_known_instances[instance_id].number = instance_number
		elif not _known_instances[instance_id].has("number"):
			_known_instances[instance_id].number = -1
		_known_instances[instance_id].active = true

	if instance_id not in _instance_visibility:
		_instance_visibility[instance_id] = VisibilityMode.SHOWN
	if instance_id not in _instance_stats:
		_instance_stats[instance_id] = {"shown": 0, "hidden": 0, "off": 0}

	# Show the instances section
	if _instances_root:
		_instances_root.visible = true

	if needs_rebuild:
		_rebuild_ui()
	else:
		_update_ui()


## Remove/deactivate a running instance
func remove_instance(instance_id: int) -> void:
	if instance_id in _known_instances:
		_known_instances[instance_id].active = false
		_update_ui()
		# Hide instances section if no active instances
		var has_active := false
		for id in _known_instances:
			if _known_instances[id].active:
				has_active = true
				break
		if not has_active and _instances_root:
			_instances_root.visible = false


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


## Get instance visibility mode
func get_instance_visibility(instance_id: int) -> int:
	return _instance_visibility.get(instance_id, VisibilityMode.SHOWN)


## Set instance visibility mode
func set_instance_visibility(instance_id: int, mode: int) -> void:
	_instance_visibility[instance_id] = mode
	_update_ui()


## Update statistics for a level
func set_level_stats(level: int, shown: int, hidden: int, off: int) -> void:
	_level_stats[level] = {"shown": shown, "hidden": hidden, "off": off}
	_update_stats_display()


## Update statistics for a channel
func set_channel_stats(channel: String, shown: int, hidden: int, off: int) -> void:
	_channel_stats[channel] = {"shown": shown, "hidden": hidden, "off": off}
	_update_stats_display()


## Update statistics for an instance
func set_instance_stats(instance_id: int, shown: int, hidden: int, off: int) -> void:
	_instance_stats[instance_id] = {"shown": shown, "hidden": hidden, "off": off}
	_update_stats_display()


## Reset all statistics to zero
func reset_stats() -> void:
	for level in _level_stats:
		_level_stats[level] = {"shown": 0, "hidden": 0, "off": 0}
	for channel in _channel_stats:
		_channel_stats[channel] = {"shown": 0, "hidden": 0, "off": 0}
	for instance_id in _instance_stats:
		_instance_stats[instance_id] = {"shown": 0, "hidden": 0, "off": 0}
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

	# Clear existing instance items
	if _instances_root:
		var instance_child := _instances_root.get_first_child()
		while instance_child:
			var next := instance_child.get_next()
			_instances_root.remove_child(instance_child)
			instance_child.free()
			instance_child = next

	_level_items.clear()
	_channel_items.clear()
	_instance_items.clear()

	# Build level items
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		_add_level_tree_item(level)

	# Build channel items hierarchically (only add root-level channels here)
	for channel in _known_channels:
		# Only add channels that don't have a parent (root level or "General")
		if channel not in _channel_parent:
			_add_channel_tree_item(channel, _channels_root)

	# Build instance items (only active ones)
	var has_active_instances := false
	for instance_id in _known_instances:
		if _known_instances[instance_id].active:
			_add_instance_tree_item(instance_id)
			has_active_instances = true

	# Show/hide instances section based on whether there are active instances
	if _instances_root:
		_instances_root.visible = has_active_instances

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
		# Use checkbox mode in the name column so checkbox appears next to text
		item.set_cell_mode(COL_NAME, TreeItem.CELL_MODE_CHECK)
		item.set_text(COL_NAME, setting.get("label", setting.name))
		item.set_editable(COL_NAME, true)
		item.set_checked(COL_NAME, _settings.get(setting.name, setting.get("default", false)))
		_set_item_not_selectable(item)
		item.set_metadata(COL_NAME, {"type": "setting", "name": setting.name})
		_settings_items[setting.name] = item


func _add_level_tree_item(level: int) -> void:
	var item := _tree.create_item(_levels_root)
	var level_name: String = LogLevel.names.get(level, "UNKNOWN").capitalize()
	var color: Color = LEVEL_COLORS.get(level, Color.WHITE)

	item.set_text(COL_NAME, level_name)
	item.set_custom_color(COL_NAME, color)
	_set_item_not_selectable(item)

	# Store level in metadata for callback
	item.set_metadata(COL_NAME, {"type": "level", "value": level})

	# Stats columns setup
	_setup_stats_columns(item)

	# Add visibility icon button in icon column (far right)
	var mode = _level_visibility.get(level, VisibilityMode.SHOWN)
	item.add_button(COL_ICON, _get_icon_for_mode(mode), 0)

	_level_items[level] = item


func _add_channel_tree_item(channel: String, parent_item: TreeItem) -> void:
	var item := _tree.create_item(parent_item)

	# For hierarchical channels, only show the last part of the name
	var display_name: String
	if channel == "":
		display_name = DEFAULT_CHANNEL_DISPLAY_NAME
	elif "/" in channel:
		display_name = channel.get_slice("/", channel.get_slice_count("/") - 1)
	else:
		display_name = channel

	item.set_text(COL_NAME, display_name)
	_set_item_not_selectable(item)

	# Store channel in metadata for callback
	item.set_metadata(COL_NAME, {"type": "channel", "value": channel})

	# Stats columns setup
	_setup_stats_columns(item)

	# Add visibility icon button in icon column (far right)
	var mode = _channel_visibility.get(channel, VisibilityMode.SHOWN)
	item.add_button(COL_ICON, _get_icon_for_mode(mode), 0)

	_channel_items[channel] = item

	# Recursively add children if this channel has any
	if channel in _channel_children:
		for child_channel in _channel_children[channel]:
			_add_channel_tree_item(child_channel, item)


func _add_instance_tree_item(instance_id: int) -> void:
	var item := _tree.create_item(_instances_root)
	var instance_data: Dictionary = _known_instances.get(instance_id, {})
	var display_name: String = instance_data.get("name", "Instance %d" % instance_id)
	var instance_number: int = int(instance_data.get("number", -1))

	item.set_text(COL_NAME, _format_instance_display_name(display_name, instance_number))
	_set_item_not_selectable(item)

	# Store instance_id in metadata for callback
	item.set_metadata(COL_NAME, {"type": "instance", "value": instance_id})

	# Stats columns setup
	_setup_stats_columns(item)

	# Add visibility icon button in icon column (far right)
	var mode = _instance_visibility.get(instance_id, VisibilityMode.SHOWN)
	item.add_button(COL_ICON, _get_icon_for_mode(mode), 0)

	_instance_items[instance_id] = item


func _format_instance_display_name(instance_name: String, instance_number: int) -> String:
	if instance_number >= 0:
		return "[%d] %s" % [instance_number, instance_name]
	return instance_name


## Helper to set up stats columns with proper alignment and colors
func _setup_stats_columns(item: TreeItem) -> void:
	for col in [COL_SHOWN, COL_HIDDEN, COL_OFF]:
		item.set_text_alignment(col, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_text_overrun_behavior(col, TextServer.OVERRUN_NO_TRIMMING)
	item.set_custom_color(COL_SHOWN, COLOR_SHOWN)
	item.set_custom_color(COL_HIDDEN, COLOR_HIDDEN)
	item.set_custom_color(COL_OFF, COLOR_OFF)


## Get the icon for a visibility mode
func _get_icon_for_mode(mode: int) -> Texture2D:
	match mode:
		VisibilityMode.SHOWN:
			return ICON_VISIBLE
		VisibilityMode.HIDDEN:
			return ICON_HIDDEN
		VisibilityMode.OFF:
			return ICON_OFF
	return ICON_VISIBLE


## Get all descendant channels of a parent channel (recursive)
func _get_all_descendants(channel: String) -> Array[String]:
	var descendants: Array[String] = []
	if channel in _channel_children:
		for child in _channel_children[channel]:
			descendants.append(child)
			descendants.append_array(_get_all_descendants(child))
	return descendants


## Check if a channel has children
func _has_children(channel: String) -> bool:
	return channel in _channel_children and _channel_children[channel].size() > 0


## Get aggregated stats for a channel including all descendants
func _get_aggregated_stats(channel: String) -> Dictionary:
	var base_stats: Dictionary = _channel_stats.get(channel, {"shown": 0, "hidden": 0, "off": 0})
	var stats := {"shown": base_stats.shown, "hidden": base_stats.hidden, "off": base_stats.off}
	for descendant in _get_all_descendants(channel):
		var desc_stats: Dictionary = _channel_stats.get(descendant, {"shown": 0, "hidden": 0, "off": 0})
		stats.shown += desc_stats.shown
		stats.hidden += desc_stats.hidden
		stats.off += desc_stats.off
	return stats


## Determine the visibility icon for a collapsed parent channel
## Returns ICON_MIXED if children have different visibility states
func _get_collapsed_visibility_icon(channel: String) -> Texture2D:
	var own_mode := _channel_visibility.get(channel, VisibilityMode.SHOWN)
	var all_same := true

	for descendant in _get_all_descendants(channel):
		var desc_mode := _channel_visibility.get(descendant, VisibilityMode.SHOWN)
		if desc_mode != own_mode:
			all_same = false
			break

	if all_same:
		return _get_icon_for_mode(own_mode)
	else:
		return ICON_MIXED


## Update a tree item's button icon to reflect visibility mode
func _update_tree_item_icon(item: TreeItem, mode: int) -> void:
	item.set_button(COL_ICON, 0, _get_icon_for_mode(mode))


func _update_ui() -> void:
	# Update level items
	for level in _level_items:
		var item: TreeItem = _level_items[level]
		var mode = _level_visibility.get(level, VisibilityMode.SHOWN)
		var base_color: Color = LEVEL_COLORS.get(level, Color.WHITE)
		_update_tree_item_icon(item, mode)
		_update_tree_item_style(item, mode, base_color)

	# Update channel items
	for channel in _channel_items:
		var item: TreeItem = _channel_items[channel]
		var mode = _channel_visibility.get(channel, VisibilityMode.SHOWN)

		# For channels with children, check if collapsed to show mixed icon
		if _has_children(channel) and item.collapsed:
			item.set_button(COL_ICON, 0, _get_collapsed_visibility_icon(channel))
		else:
			_update_tree_item_icon(item, mode)

		_update_tree_item_style(item, mode, Color.WHITE)

	# Update instance items
	for instance_id in _instance_items:
		var item: TreeItem = _instance_items[instance_id]
		var mode = _instance_visibility.get(instance_id, VisibilityMode.SHOWN)
		_update_tree_item_icon(item, mode)
		# Gray out inactive instances
		var is_active: bool = _known_instances.get(instance_id, {}).get("active", false)
		var base_color := Color.WHITE if is_active else COLOR_HIDDEN
		_update_tree_item_style(item, mode, base_color)

	# Update settings items (checkbox in name column)
	for setting_name in _settings_items:
		_settings_items[setting_name].set_checked(COL_NAME, _settings.get(setting_name, false))

	_update_stats_display()


## Update a tree item's visual style based on visibility mode
## OFF = semi-transparent, others = normal
func _update_tree_item_style(item: TreeItem, mode: int, base_color: Color) -> void:
	if mode == VisibilityMode.OFF:
		item.set_custom_color(COL_NAME, COLOR_OFF)
	else:
		# Normal styling
		item.set_custom_color(COL_NAME, base_color)
	item.set_custom_color(COL_SHOWN, COLOR_SHOWN)
	item.set_custom_color(COL_HIDDEN, COLOR_HIDDEN)
	item.set_custom_color(COL_OFF, COLOR_OFF)


func _update_stats_display() -> void:
	# Update level stats
	for level in _level_items:
		var item: TreeItem = _level_items[level]
		var stats = _level_stats.get(level, {"shown": 0, "hidden": 0, "off": 0})
		var mode = _level_visibility.get(level, VisibilityMode.SHOWN)
		_set_item_stats(item, stats, mode)

	# Update channel stats
	for channel in _channel_items:
		var item: TreeItem = _channel_items[channel]
		var mode = _channel_visibility.get(channel, VisibilityMode.SHOWN)

		# For channels with children that are collapsed, show aggregated stats
		var stats: Dictionary
		var is_collapsed_parent := _has_children(channel) and item.collapsed
		if is_collapsed_parent:
			stats = _get_aggregated_stats(channel)
		else:
			stats = _channel_stats.get(channel, {"shown": 0, "hidden": 0, "off": 0})

		_set_item_stats(item, stats, mode, is_collapsed_parent)

	# Update instance stats
	for instance_id in _instance_items:
		var item: TreeItem = _instance_items[instance_id]
		var stats = _instance_stats.get(instance_id, {"shown": 0, "hidden": 0, "off": 0})
		var mode = _instance_visibility.get(instance_id, VisibilityMode.SHOWN)
		_set_item_stats(item, stats, mode)


## Set stats for an item across the three stats columns
## - Don't show 0 counts
## - Off counts only shown on OFF items (or collapsed parents with any off counts)
func _set_item_stats(item: TreeItem, stats: Dictionary, mode: int, is_collapsed_parent: bool = false) -> void:
	# Shown count - only display if > 0
	item.set_text(COL_SHOWN, str(stats.shown) if stats.shown > 0 else "")
	item.set_tooltip_text(COL_SHOWN, "Shown Logs Count")


	# Hidden count - only display if > 0
	item.set_text(COL_HIDDEN, str(stats.hidden) if stats.hidden > 0 else "")
	item.set_tooltip_text(COL_HIDDEN, "Hidden Logs Count")

	# Off count - only display if > 0 AND (mode is OFF OR this is a collapsed parent with aggregated off counts)
	if stats.off > 0 and (mode == VisibilityMode.OFF or is_collapsed_parent):
		item.set_text(COL_OFF, str(stats.off))
	else:
		item.set_text(COL_OFF, "")
	item.set_tooltip_text(COL_OFF, "Off Logs Count")


# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_tree_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null:
		return

	var metadata = item.get_metadata(COL_NAME)
	if not metadata is Dictionary:
		return

	var item_type: String = metadata.get("type", "")

	# Only settings use checkboxes (in name column)
	if item_type == "setting":
		var setting_name: String = metadata.get("name", "")
		_settings[setting_name] = item.is_checked(COL_NAME)
		setting_changed.emit(setting_name, _settings[setting_name])


## Handle button clicks on tree items (left-click on visibility icons)
## Handle button clicks on tree items (clicking on visibility icon)
func _on_tree_button_clicked(item: TreeItem, _column: int, _id: int, _mouse_button_index: int) -> void:
	var metadata = item.get_metadata(COL_NAME)
	if not metadata is Dictionary:
		return

	var item_type: String = metadata.get("type", "")

	# Left-click on icon cycles between SHOWN and HIDDEN
	match item_type:
		"level":
			var level: int = metadata.get("value", 0)
			_cycle_level_visibility(level)
		"channel":
			var channel: String = metadata.get("value", "")
			_cycle_channel_visibility(channel)
		"instance":
			var instance_id: int = metadata.get("value", 0)
			_cycle_instance_visibility(instance_id)


## Handle right-click on tree rows to show context menu
func _on_tree_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return

	var item := _tree.get_item_at_position(event.position)
	if item == null:
		return

	var metadata = item.get_metadata(COL_NAME)
	if not metadata is Dictionary:
		return

	var item_type: String = metadata.get("type", "")

	# Only handle level, channel, and instance items (not settings)
	if item_type != "level" and item_type != "channel" and item_type != "instance":
		return

	if event.button_index == MOUSE_BUTTON_RIGHT:
		_show_context_menu(item, metadata, event.global_position)
		_tree.accept_event()


## Context menu IDs
enum ContextMenuID {
	SET_SHOWN = 0,
	SET_HIDDEN = 1,
	SET_OFF = 2,
	SEPARATOR = 3,
	DELETE_CHANNEL = 4,
}


## Show context menu for a tree item
func _show_context_menu(_item: TreeItem, metadata: Dictionary, global_pos: Vector2) -> void:
	_context_menu.clear()

	_context_item_type = metadata.get("type", "")
	_context_item_value = metadata.get("value")

	# Get current visibility mode
	var current_mode: int = VisibilityMode.SHOWN
	match _context_item_type:
		"level":
			current_mode = _level_visibility.get(_context_item_value, VisibilityMode.SHOWN)
		"channel":
			current_mode = _channel_visibility.get(_context_item_value, VisibilityMode.SHOWN)
		"instance":
			current_mode = _instance_visibility.get(_context_item_value, VisibilityMode.SHOWN)

	# Add visibility options with checkmarks for current state
	_context_menu.add_icon_item(ICON_VISIBLE, "Shown", ContextMenuID.SET_SHOWN)
	_context_menu.set_item_checked(0, current_mode == VisibilityMode.SHOWN)

	_context_menu.add_icon_item(ICON_HIDDEN, "Hidden", ContextMenuID.SET_HIDDEN)
	_context_menu.set_item_checked(1, current_mode == VisibilityMode.HIDDEN)

	_context_menu.add_icon_item(ICON_OFF, "Off", ContextMenuID.SET_OFF)
	_context_menu.set_item_checked(2, current_mode == VisibilityMode.OFF)

	# Add delete option for channels only
	if _context_item_type == "channel":
		_context_menu.add_separator()
		_context_menu.add_item("Delete Channel", ContextMenuID.DELETE_CHANNEL)

	# Convert to screen coordinates for popup positioning
	var screen_pos := get_window().position + Vector2i(global_pos)
	_context_menu.position = screen_pos
	_context_menu.popup()


## Handle context menu selection
func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		ContextMenuID.SET_SHOWN:
			_set_item_visibility(VisibilityMode.SHOWN)
		ContextMenuID.SET_HIDDEN:
			_set_item_visibility(VisibilityMode.HIDDEN)
		ContextMenuID.SET_OFF:
			_set_item_visibility(VisibilityMode.OFF)
		ContextMenuID.DELETE_CHANNEL:
			if _context_item_type == "channel":
				_delete_channel(_context_item_value)


## Set visibility for the current context menu item
func _set_item_visibility(mode: int) -> void:
	match _context_item_type:
		"level":
			_level_visibility[_context_item_value] = mode
			_update_ui()
			level_visibility_changed.emit(_context_item_value, mode)
		"channel":
			var channel: String = _context_item_value
			# Check if this channel has children and is collapsed - if so, cascade the change
			var item: TreeItem = _channel_items.get(channel)
			var should_cascade := _has_children(channel) and item != null and item.collapsed

			_channel_visibility[channel] = mode
			channel_visibility_changed.emit(channel, mode)

			if should_cascade:
				for descendant in _get_all_descendants(channel):
					_channel_visibility[descendant] = mode
					channel_visibility_changed.emit(descendant, mode)

			_update_ui()
		"instance":
			_instance_visibility[_context_item_value] = mode
			_update_ui()
			instance_visibility_changed.emit(_context_item_value, mode)


## Delete a channel and all its children
func _delete_channel(channel: String) -> void:
	# Collect all channels to delete (this channel and all descendants)
	var channels_to_delete: Array[String] = [channel]
	channels_to_delete.append_array(_get_all_descendants(channel))

	# Remove from known channels, visibility, stats, and hierarchy tracking
	for ch in channels_to_delete:
		_known_channels.erase(ch)
		_channel_visibility.erase(ch)
		_channel_stats.erase(ch)
		_channel_children.erase(ch)
		_channel_parent.erase(ch)

	# Update parent's children list if this channel had a parent
	for parent_ch in _channel_children:
		var children: Array = _channel_children[parent_ch]
		for ch in channels_to_delete:
			children.erase(ch)

	# Emit signal for each deleted channel
	for ch in channels_to_delete:
		channel_deleted.emit(ch)

	_rebuild_ui()


## Left-click cycles between SHOWN and HIDDEN only
func _cycle_level_visibility(level: int) -> void:
	var current = _level_visibility.get(level, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		# If currently OFF, clicking enables it as SHOWN
		next_mode = VisibilityMode.SHOWN
	else:
		# Toggle between SHOWN and HIDDEN
		next_mode = VisibilityMode.HIDDEN if current == VisibilityMode.SHOWN else VisibilityMode.SHOWN
	_level_visibility[level] = next_mode
	_update_ui()
	level_visibility_changed.emit(level, next_mode)


## Left-click cycles between SHOWN and HIDDEN only
func _cycle_channel_visibility(channel: String) -> void:
	var current = _channel_visibility.get(channel, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		# If currently OFF, clicking enables it as SHOWN
		next_mode = VisibilityMode.SHOWN
	else:
		# Toggle between SHOWN and HIDDEN
		next_mode = VisibilityMode.HIDDEN if current == VisibilityMode.SHOWN else VisibilityMode.SHOWN

	# Check if this channel has children and is collapsed - if so, cascade the change
	var item: TreeItem = _channel_items.get(channel)
	var should_cascade := _has_children(channel) and item != null and item.collapsed

	_channel_visibility[channel] = next_mode
	channel_visibility_changed.emit(channel, next_mode)

	if should_cascade:
		for descendant in _get_all_descendants(channel):
			_channel_visibility[descendant] = next_mode
			channel_visibility_changed.emit(descendant, next_mode)

	_update_ui()


## Right-click toggles OFF state
func _toggle_level_off(level: int) -> void:
	var current = _level_visibility.get(level, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		next_mode = VisibilityMode.SHOWN
	else:
		next_mode = VisibilityMode.OFF
	_level_visibility[level] = next_mode
	_update_ui()
	level_visibility_changed.emit(level, next_mode)


## Right-click toggles OFF state
func _toggle_channel_off(channel: String) -> void:
	var current = _channel_visibility.get(channel, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		next_mode = VisibilityMode.SHOWN
	else:
		next_mode = VisibilityMode.OFF

	# Check if this channel has children and is collapsed - if so, cascade the change
	var item: TreeItem = _channel_items.get(channel)
	var should_cascade := _has_children(channel) and item != null and item.collapsed

	_channel_visibility[channel] = next_mode
	channel_visibility_changed.emit(channel, next_mode)

	if should_cascade:
		for descendant in _get_all_descendants(channel):
			_channel_visibility[descendant] = next_mode
			channel_visibility_changed.emit(descendant, next_mode)

	_update_ui()


## Handle tree item collapse/expand to update aggregated stats and icons
func _on_tree_item_collapsed(item: TreeItem) -> void:
	var metadata = item.get_metadata(COL_NAME)
	if not metadata is Dictionary:
		return

	var item_type: String = metadata.get("type", "")
	if item_type == "channel":
		# Update UI to reflect collapsed/expanded state
		_update_ui()
		_update_stats_display()


## Left-click cycles between SHOWN and HIDDEN only for instances
func _cycle_instance_visibility(instance_id: int) -> void:
	var current = _instance_visibility.get(instance_id, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		# If currently OFF, clicking enables it as SHOWN
		next_mode = VisibilityMode.SHOWN
	else:
		# Toggle between SHOWN and HIDDEN
		next_mode = VisibilityMode.HIDDEN if current == VisibilityMode.SHOWN else VisibilityMode.SHOWN
	_instance_visibility[instance_id] = next_mode
	_update_ui()
	instance_visibility_changed.emit(instance_id, next_mode)


## Right-click toggles OFF state for instances
func _toggle_instance_off(instance_id: int) -> void:
	var current = _instance_visibility.get(instance_id, VisibilityMode.SHOWN)
	var next_mode: int
	if current == VisibilityMode.OFF:
		next_mode = VisibilityMode.SHOWN
	else:
		next_mode = VisibilityMode.OFF
	_instance_visibility[instance_id] = next_mode
	_update_ui()
	instance_visibility_changed.emit(instance_id, next_mode)
