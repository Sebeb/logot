@tool
extends RefCounted

# Observe the real panel after supported readiness, before any manual teardown.
# The foreign fixture remains an unrelated bare Node with no Logot API added.
static func collect() -> Array[String]:
	return ["panel.display_initialized", "panel.endpoint_selection", "panel.connection_state"]


static func check(panel: Control, expected: Node, preexisting: bool) -> Dictionary:
	if not is_instance_valid(panel) or not panel.has_method("_get_logot"):
		return {"checks": 0, "failures": 1, "failed_labels": [], "results": [], "precondition_error": "panel.requires_live_production_panel"}
	var labels := collect()
	var display = panel.get("_display")
	var selected: Object = panel.call("_get_logot")
	var bound: Object = panel.get("_logot")
	var connected := bool(panel.get("_logot_connected"))
	var records: Array[Dictionary] = [
		{"label": labels[0], "passed": is_instance_valid(display) and display.is_inside_tree()},
		{"label": labels[1], "passed": selected == null if preexisting else is_instance_valid(expected) and selected == expected},
		{"label": labels[2], "passed": (not connected and bound == null) if preexisting else connected and bound == expected},
	]
	var failures: Array[String] = []
	for record in records:
		if not bool(record["passed"]):
			failures.append(str(record["label"]))
	return {"checks": records.size(), "failures": failures.size(), "failed_labels": failures, "results": records, "precondition_error": ""}
