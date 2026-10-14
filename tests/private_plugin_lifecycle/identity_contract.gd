@tool
extends RefCounted

# A separate targeted contract for a future reviewed editor harness. Not run by
# the existing 24+6 driver and not an excuse to relabel those collections.
# Caller supplies the real production plugin after its ordinary teardown.
static func check(plugin: EditorPlugin) -> Dictionary:
	if ProjectSettings.has_setting("autoload/Console"):
		return {"checks": 0, "failures": ["identity.requires_completed_ordinary_teardown"]}
	if not plugin.has_method("_is_logot_autoload_path"):
		return {"checks": 1, "failures": ["identity.capability_absent"]}
	var expected := "res://addons/logot/logot.gd"
	var uid := ResourceUID.text_to_id(FileAccess.get_file_as_string(expected + ".uid").strip_edges())
	if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid) or ResourceUID.get_id_path(uid) != expected:
		return {"checks": 0, "failures": ["identity.readiness_precondition"]}
	var unknown := ResourceUID.create_id()
	var unknown_value := "*" + ResourceUID.id_to_text(unknown)
	var failures: Array[String] = []
	var values := ["*" + expected, "*" + ResourceUID.id_to_text(uid), expected, "res://fixture/foreign_console.gd", unknown_value]
	var wanted := [true, true, true, false, false]
	for index in values.size():
		if bool(plugin.call("_is_logot_autoload_path", values[index])) != wanted[index]:
			failures.append("identity.value_%d" % index)
	# Unknown setting is fixture-owned metadata, never submitted to the editor's
	# autoload loader. Exercise real claim/teardown refusal, then erase our input.
	ProjectSettings.set_setting("autoload/Console", unknown_value)
	plugin.call("_ensure_console_autoload")
	if bool(plugin.get("_added_console_autoload")):
		failures.append("identity.unknown_unclaimed")
	plugin.call("_exit_tree")
	if str(ProjectSettings.get_setting("autoload/Console", "")) != unknown_value:
		failures.append("identity.unknown_preserved")
	if bool(plugin.get("_added_console_autoload")):
		failures.append("identity.unknown_released")
	ProjectSettings.set_setting("autoload/Console", null)
	return {"checks": 8, "failures": failures}
