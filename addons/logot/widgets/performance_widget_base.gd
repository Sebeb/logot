@tool
extends VBoxContainer

# Shared Logot widget lifecycle contract used by Performance Overview and the
# CPU/GPU source widgets. LogotDisplay configures and refreshes these methods.
@export var refresh_in_background := true


func configure_logot_widget(_address: String, _mode: String, _corner: String) -> void:
	pass


func refresh_logot_widget(_delta: float) -> void:
	pass


func _get_logot_console() -> Node:
	if Engine.is_editor_hint():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var console := tree.root.get_node_or_null("Console")
	if console == null:
		console = tree.root.get_node_or_null("Logot")
	return console
