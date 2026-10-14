@tool
extends "res://addons/logot/logot_plugin.gd"

# Inherits the real plugin, including its real editor registration APIs.
# Explicit teardown calls are intentional: the contract includes repeated exit.
const IdentityContract = preload("res://fixture/identity_contract.gd")

const SETTING := "autoload/Console"
const FOREIGN := "*res://fixture/foreign_console.gd"
var _checks := 0
var _failures := 0
var _identity_failures := 0


var _filesystem: EditorFileSystem
var _sources_completed := false
var _classes_updated := false
var _filesystem_changed := false
var _driver_started := false
var _deadline_unix_ms := 0


func _enter_tree() -> void:
	var deadline_arguments := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lifecycle-deadline-unix-ms="):
			deadline_arguments += 1
			var value := argument.trim_prefix("--lifecycle-deadline-unix-ms=")
			if value.is_valid_int():
				_deadline_unix_ms = value.to_int()
	if deadline_arguments != 1 or _deadline_unix_ms <= int(Time.get_unix_time_from_system() * 1000.0):
		push_error("LIFECYCLE admission missing or expired fixed deadline")
		get_tree().quit(2)
		return
	_filesystem = EditorInterface.get_resource_filesystem()
	_filesystem.sources_changed.connect(_on_sources_changed)
	_filesystem.script_classes_updated.connect(_on_classes_updated)
	_filesystem.filesystem_changed.connect(_on_filesystem_changed)
	if ProjectSettings.get_setting("lifecycle_test/preexisting", false):
		add_autoload_singleton("Console", "res://fixture/foreign_console.gd")
	super._enter_tree()
	set_process(true)


func _on_sources_changed(_changed: bool) -> void:
	_sources_completed = true


func _on_classes_updated() -> void:
	_classes_updated = true


func _on_filesystem_changed() -> void:
	_filesystem_changed = true


func _process(_delta: float) -> void:
	if int(Time.get_unix_time_from_system() * 1000.0) >= _deadline_unix_ms:
		set_process(false)
		push_error("LIFECYCLE fixed deadline reached")
		get_tree().quit(2)
		return
	if _driver_started or not _sources_completed or not _classes_updated or not _filesystem_changed:
		return
	if _filesystem.is_scanning() or _filesystem.is_importing():
		return
	# Observe completion, then require the actual resource mapping before mutation.
	var uid := ResourceUID.text_to_id(FileAccess.get_file_as_string(LOGOT_AUTOLOAD_PATH + ".uid").strip_edges())
	if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid):
		return
	if ResourceUID.get_id_path(uid) != LOGOT_AUTOLOAD_PATH:
		push_error("LIFECYCLE ready UID maps to unexpected resource")
		get_tree().quit(2)
		return
	_driver_started = true
	print("LIFECYCLE READY ", JSON.stringify({"schema": 1, "collection": "lifecycle", "scenario": "preexisting" if ProjectSettings.get_setting("lifecycle_test/preexisting", false) else "main", "sources_completed": _sources_completed, "classes_updated": _classes_updated, "filesystem_changed": _filesystem_changed, "scanning": _filesystem.is_scanning(), "importing": _filesystem.is_importing(), "deadline_unix_ms": _deadline_unix_ms}))
	_run_lifecycle_cases()


func _identity(raw: String) -> Dictionary:
	var path := raw.trim_prefix("*")
	var known := true
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		known = uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid)
		path = ResourceUID.get_id_path(uid) if known else ""
	return {"raw": raw, "resolved": path, "known": known, "singleton": raw.begins_with("*")}


func _same_resource(raw: String, expected: String) -> bool:
	var actual := _identity(raw)
	return actual.known and actual.resolved == expected.trim_prefix("*") and actual.singleton == expected.begins_with("*")


func _check(condition: bool, label: String) -> void:
	var witness := _identity(str(ProjectSettings.get_setting(SETTING, "")))
	witness["schema"] = 1
	witness["collection"] = "lifecycle"
	witness["ordinal"] = _checks + 1
	witness["passed"] = condition
	witness["label"] = label
	witness["exists"] = ProjectSettings.has_setting(SETTING)
	print("LIFECYCLE WITNESS ", JSON.stringify(witness))
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
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), "*" + LOGOT_AUTOLOAD_PATH), "ordinary.created")
	super._exit_tree()
	_check(not ProjectSettings.has_setting(SETTING), "ordinary.removed")
	_check(not _added_console_autoload, "ordinary.released")
	_run_identity_contract()

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
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "preexisting.precondition")
	_ensure_console_autoload()
	_check(not _added_console_autoload, "preexisting.unclaimed")
	super._exit_tree()
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "preexisting.preserved")
	remove_autoload_singleton("Console")

	# Replace an entry that this activation did create, through the real editor API.
	_ensure_console_autoload()
	_check(_added_console_autoload, "replaced.claimed")
	remove_autoload_singleton("Console")
	add_autoload_singleton("Console", "res://fixture/foreign_console.gd")
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "replaced.precondition")
	super._exit_tree()
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "replaced.preserved")
	_check(not _added_console_autoload, "replaced.released")
	super._exit_tree()
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "repeated.foreign_preserved")
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
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN.trim_prefix("*")), "unstarred.foreign_preserved")
	_check(not _added_console_autoload, "unstarred.foreign_released")
	remove_autoload_singleton("Console")
	_check(not ProjectSettings.has_setting(SETTING), "final.absent")
	_check(_debugger_plugin == null and _editor_dock == null and _editor_panel == null, "final.editor_references_released")
	print("LIFECYCLE RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 and _checks == 24 and _identity_failures == 0 else 1)


func _run_preexisting_activation() -> void:
	_check(not _added_console_autoload, "cold_foreign.unclaimed")
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "cold_foreign.preserved_during_enter")
	super._exit_tree()
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "cold_foreign.preserved_during_exit")
	_check(not _added_console_autoload, "cold_foreign.released")
	super._exit_tree()
	_check(_same_resource(str(ProjectSettings.get_setting(SETTING, "")), FOREIGN), "cold_foreign.repeated_exit")
	_check(_debugger_plugin == null and _editor_dock == null and _editor_panel == null, "cold_foreign.editor_references_released")
	remove_autoload_singleton("Console")
	print("LIFECYCLE RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 and _checks == 6 else 1)


func _run_identity_contract() -> void:
	var labels: Array[String] = IdentityContract.collect(self)
	print("LIFECYCLE IDENTITY COLLECTION ", JSON.stringify({"schema": 1, "collection": "identity", "labels": labels, "expected_checks": labels.size()}))
	var result: Dictionary = IdentityContract.check(self)
	var records: Array = result["results"]
	for index in records.size():
		var record: Dictionary = records[index]
		print("LIFECYCLE IDENTITY CHECK ", JSON.stringify({"schema": 1, "collection": "identity", "ordinal": index + 1, "label": record["label"], "passed": record["passed"]}))
	_identity_failures = int(result["failures"])
	if int(result["checks"]) != labels.size() or records.size() != labels.size() or not str(result["precondition_error"]).is_empty():
		_identity_failures = maxi(1, _identity_failures)
	print("LIFECYCLE IDENTITY RESULT ", JSON.stringify({"schema": 1, "collection": "identity", "checks": result["checks"], "failures": _identity_failures, "failed_labels": result["failed_labels"], "precondition_error": result["precondition_error"]}))
