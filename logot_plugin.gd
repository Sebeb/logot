@tool
extends EditorPlugin

const EditorPanelScript = preload("res://addons/logot/editor/logot_editor_panel.gd")

var _editor_panel: Control
var _scroll_container: ScrollContainer


func _enter_tree() -> void:
	print("Logot plugin activated.")
	add_autoload_singleton("Logot", "res://addons/logot/logot.gd")

	# Create editor panel - it instantiates logot.tscn internally
	# No inheritance issues since logot_editor_panel.gd extends Control directly
	_editor_panel = Control.new()
	_editor_panel.set_script(EditorPanelScript)

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "LogotPanel"
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.add_child(_editor_panel)
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_control_to_bottom_panel(_scroll_container, "Logot")

	# Connect to editor play signal for "clear on play" feature
	var editor_interface := get_editor_interface()
	if editor_interface:
		editor_interface.get_base_control().get_tree().tree_changed.connect(_check_play_state)


func _exit_tree() -> void:
	remove_autoload_singleton("Logot")

	if _scroll_container:
		remove_control_from_bottom_panel(_scroll_container)
		_scroll_container.queue_free()
		_scroll_container = null
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
