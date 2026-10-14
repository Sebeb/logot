@tool
extends RefCounted

# Separately collected and counted, immediately after real ordinary teardown.
# No editor loader receives the fixture-owned unknown UID setting.
static func collect(plugin: EditorPlugin) -> Array[String]:
	if not plugin.has_method("_is_logot_autoload_path"):
		return ["identity.capability_absent"]
	return ["identity.singleton_path", "identity.singleton_uid", "identity.path", "identity.foreign_path", "identity.unknown_uid", "identity.unknown_unclaimed", "identity.unknown_preserved", "identity.unknown_released"]


static func check(plugin: EditorPlugin) -> Dictionary:
	if ProjectSettings.has_setting("autoload/Console"):
		return _precondition("identity.requires_completed_ordinary_teardown")
	if not plugin.has_method("_is_logot_autoload_path"):
		return _result([{"label": "identity.capability_absent", "passed": false}])
	var expected := "res://addons/logot/logot.gd"
	var uid := ResourceUID.text_to_id(FileAccess.get_file_as_string(expected + ".uid").strip_edges())
	if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid) or ResourceUID.get_id_path(uid) != expected:
		return _precondition("identity.readiness_precondition")
	var unknown := ResourceUID.create_id()
	if unknown == ResourceUID.INVALID_ID or ResourceUID.has_id(unknown):
		return _precondition("identity.requires_unregistered_uid")
	var unknown_value := "*" + ResourceUID.id_to_text(unknown)
	var records: Array[Dictionary] = []
	var labels := collect(plugin)
	var values := ["*" + expected, "*" + ResourceUID.id_to_text(uid), expected, "res://fixture/foreign_console.gd", unknown_value]
	var wanted := [true, true, true, false, false]
	for index in values.size():
		records.append({"label": labels[index], "passed": bool(plugin.call("_is_logot_autoload_path", values[index])) == wanted[index]})
	# Only inject our metadata after verifying the prior setting is absent.
	# Direct setting changes do not invoke editor autoload loader operations.
	ProjectSettings.set_setting("autoload/Console", unknown_value)
	plugin.call("_ensure_console_autoload")
	records.append({"label": labels[5], "passed": not bool(plugin.get("_added_console_autoload"))})
	plugin.call("_exit_tree")
	records.append({"label": labels[6], "passed": str(ProjectSettings.get_setting("autoload/Console", "")) == unknown_value})
	records.append({"label": labels[7], "passed": not bool(plugin.get("_added_console_autoload"))})
	ProjectSettings.set_setting("autoload/Console", null)
	return _result(records)


static func _precondition(reason: String) -> Dictionary:
	return {"checks": 0, "failures": 1, "failed_labels": [], "results": [], "precondition_error": reason}


static func _result(records: Array[Dictionary]) -> Dictionary:
	var failed_labels: Array[String] = []
	for record in records:
		if not bool(record["passed"]):
			failed_labels.append(str(record["label"]))
	return {"checks": records.size(), "failures": failed_labels.size(), "failed_labels": failed_labels, "results": records, "precondition_error": ""}
