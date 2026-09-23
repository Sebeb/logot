extends SceneTree

const LogotExternalTestCaseScript = preload("res://addons/logot/testing/logot_external_test_case.gd")


class MockContext:
	extends RefCounted

	var failures: Array[Dictionary] = []

	func fail(name: String, details: String = "") -> void:
		failures.append({"name": name, "details": details})


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var console = root.get_node_or_null("Logot")
	_assert(console != null, "Logot autoload is available")
	var manager = console.get_test_manager()
	_assert(manager != null, "Logot test manager is available")

	var registered_case = _make_case("external_adapter_registered", Callable(self, "_complete_synchronously"))
	_assert(manager.register_test_case(registered_case), "external case registers")
	manager.refresh()
	_assert(_manager_has_test(manager, registered_case.id), "registered case survives refresh")
	_assert(manager.run_test(registered_case.id), "registered case starts")
	var result = await manager.test_run_completed
	_assert(result != null and result.passed, "registered case completes through the manager")
	_assert(manager.unregister_test_case(registered_case.id), "registered case unregisters")
	_assert(not manager.run_test(registered_case.id), "unregistered case is refused")

	var sync_case = _make_case("external_adapter_sync", Callable(self, "_complete_synchronously"))
	await sync_case.run(MockContext.new())
	_assert(sync_case._done, "synchronous completion does not hang")

	var async_case = _make_case("external_adapter_async", Callable(self, "_complete_asynchronously"))
	await async_case.run(MockContext.new())
	_assert(async_case._done, "asynchronous completion resumes through the signal")

	var missing_body_case = _make_case("external_adapter_missing", Callable())
	var missing_body_context := MockContext.new()
	await missing_body_case.run(missing_body_context)
	_assert(missing_body_context.failures.size() == 1, "missing body records one failure")
	_assert(
		str(missing_body_context.failures[0].get("name", "")) == "external_body_missing",
		"missing body records external_body_missing"
	)

	print("PASS logot_external_test_case_adapter")
	quit(0)


func _make_case(test_id: String, test_body: Callable):
	var test_case = LogotExternalTestCaseScript.new()
	test_case.id = test_id
	test_case.display_name = test_id
	test_case.scene_path = "res://Main.tscn"
	test_case.fail_fast = true
	test_case.body = test_body
	return test_case


func _manager_has_test(manager, test_id: String) -> bool:
	for test_case in manager.get_tests():
		if str(test_case.id) == test_id:
			return true
	return false


func _complete_synchronously(test_case, ctx) -> void:
	if ctx.has_method("check"):
		ctx.check("external_body_ran", true)
	test_case.complete()


func _complete_asynchronously(test_case, _ctx) -> void:
	test_case.call_deferred("complete")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAIL: %s" % message)
	quit(1)
