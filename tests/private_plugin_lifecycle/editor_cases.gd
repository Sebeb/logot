@tool
extends "res://addons/logot/logot_plugin.gd"

# Inherits the real plugin, including its real editor registration APIs.
# Explicit teardown calls are intentional: the contract includes repeated exit.
const SETTING := "autoload/Console"
const FOREIGN := "*res://fixture/foreign_console.gd"
var _checks := 0
var _failures := 0


func _enter_tree() -> void:
	if ProjectSettings.get_setting("lifecycle_test/preexisting", false):
		add_autoload_singleton("Console", "res://fixture/foreign_console.gd")
	super._enter_tree()
	call_deferred("_run_lifecycle_cases")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("LIFECYCLE PASS ", label)
	else:
		_failures += 1
		push_error("LIFECYCLE FAIL " + label)


func _run_lifecycle_cases() -> void:
	if ProjectSettings.get_setting("lifecycle_test/preexisting", false):
		_run_preexisting_activation()
		return
	# Ordinary activation used the complete production _enter_tree above.
	_check(_added_console_autoload, "ordinary.claimed")
	_check(str(ProjectSettings.get_setting(SETTING, "")) == "*" + LOGOT_AUTOLOAD_PATH, "ordinary.created")
	super._exit_tree()
	_check(not ProjectSettings.has_setting(SETTING), "ordinary.removed")
	_check(not _added_console_autoload, "ordinary.released")

	# Real editor removal before production teardown reproduces the missing setting.
	_ensure_console_autoload()
	_check(_added_console_autoload, "absent.claimed")
	remove_autoload_singleton("Console")
	_check(not ProjectSettings.has_setting(SETTING), "absent.precondition")
	super._exit_tree()
	_check(not ProjectSettings.has_setting(SETTING), "absent.stays_absent")
	_check(not _added_console_autoload, "absent.released")

	# No ownership is acquired when a foreign autoload predates activation.
	add_autoload_singleton("Console", "res://fixture/foreign_console.gd")
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "preexisting.precondition")
	_ensure_console_autoload()
	_check(not _added_console_autoload, "preexisting.unclaimed")
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "preexisting.preserved")
	remove_autoload_singleton("Console")

	# Replace an entry that this activation did create, through the real editor API.
	_ensure_console_autoload()
	_check(_added_console_autoload, "replaced.claimed")
	remove_autoload_singleton("Console")
	add_autoload_singleton("Console", "res://fixture/foreign_console.gd")
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "replaced.precondition")
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "replaced.preserved")
	_check(not _added_console_autoload, "replaced.released")
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "repeated.foreign_preserved")
	remove_autoload_singleton("Console")
	super._exit_tree()
	_check(not ProjectSettings.has_setting(SETTING), "repeated.absent")
	_check(not _added_console_autoload, "repeated.released")

	# Both legal Godot autoload spellings identify the same owned script.
	_ensure_console_autoload()
	ProjectSettings.set_setting(SETTING, LOGOT_AUTOLOAD_PATH)
	super._exit_tree()
	_check(not ProjectSettings.has_setting(SETTING), "unstarred.owned_removed")
	_check(not _added_console_autoload, "unstarred.released")

	# A foreign non-singleton spelling is preserved too.
	_ensure_console_autoload()
	ProjectSettings.set_setting(SETTING, FOREIGN.trim_prefix("*"))
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN.trim_prefix("*"), "unstarred.foreign_preserved")
	_check(not _added_console_autoload, "unstarred.foreign_released")
	remove_autoload_singleton("Console")
	_check(not ProjectSettings.has_setting(SETTING), "final.absent")
	_check(_debugger_plugin == null and _editor_dock == null and _editor_panel == null, "final.editor_references_released")
	print("LIFECYCLE RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 and _checks == 24 else 1)


func _run_preexisting_activation() -> void:
	_check(not _added_console_autoload, "cold_foreign.unclaimed")
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "cold_foreign.preserved_during_enter")
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "cold_foreign.preserved_during_exit")
	_check(not _added_console_autoload, "cold_foreign.released")
	super._exit_tree()
	_check(str(ProjectSettings.get_setting(SETTING, "")) == FOREIGN, "cold_foreign.repeated_exit")
	_check(_debugger_plugin == null and _editor_dock == null and _editor_panel == null, "cold_foreign.editor_references_released")
	remove_autoload_singleton("Console")
	print("LIFECYCLE RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 and _checks == 6 else 1)
