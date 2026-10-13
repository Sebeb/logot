extends SceneTree
func _init() -> void:
	var token := str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	var actual := OS.get_user_data_dir()
	print("USERDATA_PROOF=", actual)
	var expected := OS.get_environment("HOME") + "/Library/Application Support/" + token
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false) or not token.begins_with("logot-pinned-private-") or token.contains("/") or actual != expected:
		push_error("Private project userdata proof failed")
		quit(2)
		return
	quit(0)
