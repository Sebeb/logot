@tool
extends EditorPlugin

const EditorPanelScript = preload("res://addons/logot/editor/logot_editor_panel.gd")
const LogotDebuggerPlugin = preload("res://addons/logot/editor/logot_debugger_plugin.gd")

var _editor_panel: Control
var _editor_dock: EditorDock
var _debugger_plugin: EditorDebuggerPlugin


func _enter_tree() -> void:
	print("Logot plugin activated.")
	add_autoload_singleton("Console", "res://addons/logot/logot.gd")

	# Create and register the debugger plugin for game instance communication
	_debugger_plugin = LogotDebuggerPlugin.new()
	add_debugger_plugin(_debugger_plugin)

	# Create editor panel - it instantiates logot.tscn internally
	# No inheritance issues since logot_editor_panel.gd extends Control directly
	_editor_panel = Control.new()
	_editor_panel.name = "LogotPanel"
	_editor_panel.set_script(EditorPanelScript)
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Pass the debugger plugin reference to the editor panel
	_editor_panel.set_debugger_plugin(_debugger_plugin)

	var shortcut = Shortcut.new()
	var key_event = InputEventKey.new()
	key_event.keycode = KEY_QUOTELEFT
	# key_event.meta_pressed = true
	# key_event.command_or_control_autoremap = true # Swaps Ctrl for Command on Mac.
	shortcut.events = [key_event]

	_editor_dock = EditorDock.new()
	_editor_dock.name = "LogotDock"
	_editor_dock.title = "Logot"
	_editor_dock.layout_key = "Logot"
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_editor_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_editor_dock.dock_shortcut = shortcut
	_editor_dock.add_child(_editor_panel)
	add_dock(_editor_dock)


	# Connect to editor play signal for "clear on play" feature
	var editor_interface := get_editor_interface()
	if editor_interface:
		editor_interface.get_base_control().get_tree().tree_changed.connect(_check_play_state)


func _exit_tree() -> void:
	remove_autoload_singleton("Console")

	if _debugger_plugin:
		remove_debugger_plugin(_debugger_plugin)
		_debugger_plugin = null

	if _editor_dock:
		remove_dock(_editor_dock)
		_editor_dock.queue_free()
		_editor_dock = null
		_editor_panel = null


var _was_playing := false

func _check_play_state() -> void:
	var editor_interface := get_editor_interface()
	if not editor_interface:
		return

	var is_playing := editor_interface.is_playing_scene()
	if is_playing and not _was_playing:
		# Game just started
		if _editor_panel and _editor_panel.has_method("on_game_started"):
			_editor_panel.on_game_started()

	_was_playing = is_playing
