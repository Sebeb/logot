class_name LogotTestManager
extends Node

const LogotTestCaseScript = preload("res://addons/logot/testing/logot_test_case.gd")
const LogotTestContextScript = preload("res://addons/logot/testing/logot_test_context.gd")
const LogotTestRunResultScript = preload("res://addons/logot/testing/resources/logot_test_run_result.gd")
const LogotTestCheckResultScript = preload("res://addons/logot/testing/resources/logot_test_check_result.gd")
const LogotTestVisualResultScript = preload("res://addons/logot/testing/resources/logot_test_visual_result.gd")
const LogotTestLogRecordScript = preload("res://addons/logot/testing/resources/logot_test_log_record.gd")
const LogLevel = preload("res://addons/logot/log_level.gd")

const TEST_CASES_ROOT := "res://tests/logot_cases"
const TEST_ARTIFACTS_ROOT := "user://artifacts/tests"
const TEST_GROUP_NAME := "Tests"
const TEST_GROUP_PRIORITY := 250
const TEST_ALL_COMMAND := "test/all"
const EFFECTIVE_ASSERTION_CHECK := "effective_assertion_required"
const EFFECTIVE_ASSERTION_DETAILS := "Logot tests must record at least one code or visual check."

signal tests_changed()
signal recent_results_changed()
signal test_run_started(result)
signal test_run_completed(result)
signal running_state_changed(is_running: bool)

var console = null
var _discovery_roots: Array[String] = [TEST_CASES_ROOT]
var _tests_by_id: Dictionary = {}
var _invalid_test_messages: Array[String] = []
var _last_discovery_report: Dictionary = {}
var _last_batch_report: Dictionary = {}
var _recent_results: Array = []
var _results_by_run_id: Dictionary = {}
var _latest_result_by_test_id: Dictionary = {}
var _registered_dynamic_commands: Array[String] = []
var _active_result = null
var _active_test_case = null
var _active_scene_root: Node = null
var _active_log_start_index := 0
var _active_visual_index := 0
var _sandbox_root: Node = null
var _is_running := false


func _init(in_console = null) -> void:
	console = in_console


func _ready() -> void:
	if console == null:
		console = get_parent()
	_ensure_sandbox_root()
	refresh()


func refresh() -> void:
	_discover_tests()
	_last_discovery_report = _build_discovery_report()
	_load_recent_results()
	_register_commands()
	tests_changed.emit()
	recent_results_changed.emit()


func get_tests() -> Array:
	var tests: Array = []
	for test_id in _tests_by_id.keys():
		tests.append(_tests_by_id[test_id])
	tests.sort_custom(func(a, b): return str(a.id) < str(b.id))
	return tests


func get_invalid_test_messages() -> Array[String]:
	return _invalid_test_messages.duplicate()


func get_discovery_roots() -> Array[String]:
	return _discovery_roots.duplicate()


func set_discovery_roots(roots: Array[String]) -> void:
	var normalized: Array[String] = []
	for root in roots:
		var path := str(root).strip_edges()
		if path.is_empty() or normalized.has(path):
			continue
		normalized.append(path)
	if normalized.is_empty():
		normalized.append(TEST_CASES_ROOT)
	_discovery_roots = normalized


func get_discovery_report() -> Dictionary:
	return _last_discovery_report.duplicate(true)


func get_last_batch_report() -> Dictionary:
	return _last_batch_report.duplicate(true)


func get_recent_results(limit := 25) -> Array:
	var results: Array = []
	for index in range(mini(limit, _recent_results.size())):
		results.append(_recent_results[index])
	return results


func get_result_by_run_id(run_id: String):
	return _results_by_run_id.get(run_id, null)


func get_latest_result_for_test(test_id: String):
	return _latest_result_by_test_id.get(test_id, null)


func get_last_result():
	return _recent_results[0] if not _recent_results.is_empty() else null


func is_running_test() -> bool:
	return _is_running


func run_test(test_id: String) -> bool:
	if _is_running:
		_print_error("A test run is already in progress.")
		return false
	if not _tests_by_id.has(test_id):
		_print_error("Unknown test '%s'." % test_id)
		return false
	_set_running_state(true)
	call_deferred("_run_test_async", test_id)
	return true


func run_all_tests() -> bool:
	if _is_running:
		_print_error("A test run is already in progress.")
		return false
	if not _invalid_test_messages.is_empty():
		_last_batch_report = _build_batch_report([], "Invalid test definitions prevent running all tests.")
		return false
	var tests := get_tests()
	if tests.is_empty():
		_last_batch_report = _build_batch_report([], "No tests discovered.")
		_print_error("No tests discovered.")
		return false
	_set_running_state(true)
	call_deferred("_run_all_tests_async")
	return true


func should_abort_after_failure() -> bool:
	return _active_result != null and bool(_active_result.fail_fast)


func record_code_check(name: String, passed: bool, details: String = "") -> void:
	if _active_result == null:
		return
	var check_result = LogotTestCheckResultScript.new()
	check_result.name = name
	check_result.passed = passed
	check_result.details = details
	check_result.timestamp = _timestamp_now()
	_active_result.code_checks.append(check_result)


func capture_visual_checkpoint(name: String, path: String = ""):
	if _active_result == null:
		return {"ok": false, "error": "No active test run."}

	_active_visual_index += 1
	var target_path := path.strip_edges()
	if target_path.is_empty():
		target_path = "%s/%02d_%s.png" % [
			_active_result.visual_directory,
			_active_visual_index,
			_sanitize_file_component(name)
		]

	await get_tree().process_frame
	var capture_result: Dictionary = console.capture_screenshot(target_path, name, false)

	var visual_result = LogotTestVisualResultScript.new()
	visual_result.name = name
	visual_result.passed = bool(capture_result.get("ok", false))
	visual_result.image_path = str(capture_result.get("path", ""))
	visual_result.details = str(capture_result.get("error", ""))
	visual_result.timestamp = _timestamp_now()
	_active_result.visual_checks.append(visual_result)
	return capture_result


func _run_test_async(test_id: String):
	var test_case = _tests_by_id.get(test_id, null)
	if test_case == null:
		_set_running_state(false)
		return
	await _run_test_case_async(test_case)
	_set_running_state(false)


func _run_all_tests_async() -> void:
	var run_entries: Array[Dictionary] = []
	for test_case in get_tests():
		var completed_result = await _run_test_case_async(test_case)
		if completed_result == null:
			continue
		run_entries.append(_serialize_batch_result(completed_result))
	_last_batch_report = _build_batch_report(run_entries)
	if bool(_last_batch_report.get("ok", false)):
		_print_line("All %d Logot test(s) passed." % int(_last_batch_report.get("total_tests", 0)))
	else:
		_print_error(str(_last_batch_report.get("error", "All-tests run failed.")))
	_set_running_state(false)


func _run_test_case_async(test_case):
	_active_test_case = test_case
	_active_result = LogotTestRunResultScript.new()
	_active_result.run_id = _build_run_id()
	_active_result.test_id = str(test_case.id)
	_active_result.display_name = str(test_case.display_name)
	_active_result.scene_path = str(test_case.scene_path)
	_active_result.fail_fast = bool(test_case.fail_fast)
	_active_result.started_at = _timestamp_now()
	_active_result.artifact_directory = "%s/%s" % [TEST_ARTIFACTS_ROOT, _sanitize_file_component(_active_result.test_id)]
	_active_result.visual_directory = "%s/%s/visuals" % [_active_result.artifact_directory, _active_result.run_id]
	_active_result.artifact_path = "%s/%s.tres" % [_active_result.artifact_directory, _active_result.run_id]

	_active_log_start_index = _get_console_log_count()
	_active_visual_index = 0

	_print_line("[color=cyan]Running test:[/color] %s" % _active_result.display_name)
	test_run_started.emit(_active_result)

	await _drain_sandbox_root_async()

	var run_error := ""
	var scene_instance: Node = null
	var scene_resource = load(_active_result.scene_path)
	if not (scene_resource is PackedScene):
		run_error = "Failed to load test scene: %s" % _active_result.scene_path
	else:
		scene_instance = (scene_resource as PackedScene).instantiate()
		_sandbox_root.add_child(scene_instance)
		_active_scene_root = scene_instance

	if run_error.is_empty() and scene_instance != null:
		await get_tree().process_frame
		var ctx = LogotTestContextScript.new(self, console, _active_result.test_id, scene_instance)
		await test_case.run(ctx)

	if not run_error.is_empty():
		record_code_check("test_setup", false, run_error)
		_print_error(run_error)

	_active_result.completed_at = _timestamp_now()
	_ensure_effective_assertion(_active_result)
	_collect_active_logs()
	_active_result.passed = _compute_result_passed(_active_result)
	_active_result.summary = _build_result_summary(_active_result)
	_persist_result(_active_result)
	_index_result(_active_result)

	var completed_result = _active_result
	test_run_completed.emit(completed_result)
	recent_results_changed.emit()
	_print_line(
		"[color=%s]Test %s:[/color] %s" % [
			"light_green" if completed_result.passed else "tomato",
			"passed" if completed_result.passed else "failed",
			completed_result.display_name
		]
	)

	_active_result = null
	_active_test_case = null
	_active_scene_root = null
	await _drain_sandbox_root_async()
	return completed_result


func _set_running_state(is_running: bool) -> void:
	_is_running = is_running
	running_state_changed.emit(is_running)


func _ensure_sandbox_root() -> void:
	if _sandbox_root != null and is_instance_valid(_sandbox_root):
		return
	_sandbox_root = Node.new()
	_sandbox_root.name = "LogotTestSandbox"
	_sandbox_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sandbox_root)


func _reset_sandbox_root() -> void:
	_ensure_sandbox_root()
	for child in _sandbox_root.get_children():
		child.queue_free()


func _drain_sandbox_root_async(max_frames := 30) -> void:
	_reset_sandbox_root()
	for _frame in range(max_frames):
		if _sandbox_root.get_child_count() == 0:
			for _flush_frame in range(4):
				await get_tree().process_frame
			if _sandbox_root.get_child_count() == 0:
				return
		await get_tree().process_frame


func _discover_tests() -> void:
	_tests_by_id.clear()
	_invalid_test_messages.clear()
	_last_batch_report = {}

	var seen_paths: Dictionary = {}
	for root_path in _discovery_roots:
		for script_path in _list_gd_files(root_path):
			if seen_paths.has(script_path):
				continue
			seen_paths[script_path] = true
			var script_resource = load(script_path)
			if script_resource == null:
				_invalid_test_messages.append("Failed to load test script: %s" % script_path)
				continue
			var test_case = script_resource.new()
			if not (test_case is LogotTestCaseScript):
				_invalid_test_messages.append("Script does not extend LogotTestCase: %s" % script_path)
				continue
			if not _validate_test_case(test_case, script_path):
				continue
			_tests_by_id[test_case.id] = test_case


func _validate_test_case(test_case, script_path: String) -> bool:
	var test_id := str(test_case.id).strip_edges()
	if test_id.is_empty():
		_invalid_test_messages.append("Test is missing id: %s" % script_path)
		return false
	if " " in test_id:
		_invalid_test_messages.append("Test id cannot contain spaces: %s" % test_id)
		return false
	if "/" in test_id:
		_invalid_test_messages.append("Test id cannot contain '/': %s" % test_id)
		return false
	if _tests_by_id.has(test_id):
		_invalid_test_messages.append("Duplicate test id: %s" % test_id)
		return false
	var scene_path := str(test_case.scene_path).strip_edges()
	if scene_path.is_empty():
		_invalid_test_messages.append("Test '%s' is missing scene_path." % test_id)
		return false
	if not ResourceLoader.exists(scene_path):
		_invalid_test_messages.append("Test '%s' scene does not exist: %s" % [test_id, scene_path])
		return false
	test_case.id = test_id
	test_case.display_name = str(test_case.display_name).strip_edges()
	if test_case.display_name.is_empty():
		test_case.display_name = test_id.replace("_", " ").capitalize()
	test_case.scene_path = scene_path
	test_case.fail_fast = bool(test_case.fail_fast)
	return true


func _load_recent_results() -> void:
	_recent_results.clear()
	_results_by_run_id.clear()
	_latest_result_by_test_id.clear()

	for result_path in _list_tres_files(TEST_ARTIFACTS_ROOT):
		var result_resource = load(result_path)
		if result_resource == null or not (result_resource is LogotTestRunResultScript):
			continue
		_index_result(result_resource)


func _index_result(result) -> void:
	if result == null:
		return
	_results_by_run_id[result.run_id] = result
	var replaced_existing := false
	for index in range(_recent_results.size()):
		if _recent_results[index].run_id == result.run_id:
			_recent_results[index] = result
			replaced_existing = true
			break
	if not replaced_existing:
		_recent_results.append(result)
	_recent_results.sort_custom(func(a, b): return str(a.run_id) > str(b.run_id))
	_latest_result_by_test_id[result.test_id] = result


func _register_commands() -> void:
	if console == null:
		return

	for command_name in _registered_dynamic_commands:
		console.remove_command(command_name)
	_registered_dynamic_commands.clear()

	_register_command("test/list", Callable(self, "_command_list_tests"), [], 0, "Lists discovered Logot tests.")
	_register_command(TEST_ALL_COMMAND, Callable(self, "_command_run_all_tests"), [], 0, "Runs every discovered Logot test in deterministic ID order.")
	_register_command("test/recent", Callable(self, "_command_recent_results"), [], 0, "Lists recently completed test runs.")
	_register_command("test/last", Callable(self, "_command_last_result"), [], 0, "Shows the most recent test result.")
	_register_command("test/reload", Callable(self, "_command_reload"), [], 0, "Reloads test definitions and persisted results.")

	for test_case in get_tests():
		var command_token := _command_test_token(String(test_case.id))
		_register_command(
			"test/%s" % command_token,
			Callable(self, "_command_run_test").bind(String(test_case.id)),
			[],
			0,
			"Run test: %s." % test_case.display_name
		)
		_register_command(
			"test/%s_latest" % command_token,
			Callable(self, "_command_last_result_for_test").bind(String(test_case.id)),
			[],
			0,
			"Show latest result: %s." % test_case.display_name
		)

	for result in _recent_results:
		var result_command_name := "test/%s_%s_%s" % [
			_command_test_token(String(result.test_id)),
			"pass" if bool(result.passed) else "fail",
			String(result.run_id)
		]
		_register_command(
			result_command_name,
			Callable(self, "_command_show_result").bind(String(result.run_id)),
			[],
			0,
			"%s %s at %s." % [
				"PASS" if bool(result.passed) else "FAIL",
				result.display_name,
				result.completed_at
			]
		)


func _register_command(command_name: String, callable: Callable, arguments: Array, required: int, description: String) -> void:
	console.add_command(command_name, callable, arguments, required, description, TEST_GROUP_NAME, TEST_GROUP_PRIORITY)
	_registered_dynamic_commands.append(command_name)


func _command_reload() -> void:
	refresh()
	if not _invalid_test_messages.is_empty():
		_print_error("Reload found %d invalid Logot test definition(s)." % _invalid_test_messages.size())
		_log_invalid_test_messages()
		return
	_print_line("Reloaded %d test(s)." % _tests_by_id.size())


func _command_list_tests() -> void:
	var lines: PackedStringArray = []
	lines.append("[color=cyan]Discovered tests:[/color]")
	for test_case in get_tests():
		lines.append("  [color=light_green]%s[/color] -> %s" % [test_case.id, test_case.display_name])
	if lines.size() == 1:
		lines.append("  No tests discovered.")
	console.log(["\n".join(lines)], LogLevel.MESSAGE, "Tests")
	if not _invalid_test_messages.is_empty():
		_print_error("Discovery found %d invalid Logot test definition(s)." % _invalid_test_messages.size())
		_log_invalid_test_messages()


func _command_run_all_tests() -> void:
	if not _invalid_test_messages.is_empty():
		_last_batch_report = _build_batch_report([], "Invalid test definitions prevent running all tests.")
		_print_error("Cannot run all tests while discovery has invalid definitions.")
		_log_invalid_test_messages()
		return
	if not run_all_tests() and str(_last_batch_report.get("error", "")).is_empty():
		_last_batch_report = _build_batch_report([], "Unable to start all-tests run.")


func _command_recent_results() -> void:
	var lines: PackedStringArray = []
	lines.append("[color=cyan]Recent test results:[/color]")
	var recent = get_recent_results(10)
	for result in recent:
		lines.append("  [%s] [color=%s]%s[/color] %s" % [
			result.completed_at,
			"light_green" if result.passed else "tomato",
			"PASS" if result.passed else "FAIL",
			result.display_name
		])
	if recent.is_empty():
		lines.append("  No test results found.")
	console.log(["\n".join(lines)], LogLevel.MESSAGE, "Tests")


func _command_last_result() -> void:
	var result = get_last_result()
	if result == null:
		_print_error("No test results found.")
		return
	_log_result_summary(result)


func _command_last_result_for_test(test_id: String) -> void:
	var result = get_latest_result_for_test(test_id)
	if result == null:
		_print_error("No previous result for '%s'." % test_id)
		return
	_log_result_summary(result)


func _command_run_test(test_id: String) -> void:
	run_test(test_id)


func _command_show_result(run_id: String) -> void:
	var result = get_result_by_run_id(run_id)
	if result == null:
		_print_error("Unknown test result '%s'." % run_id)
		return
	_log_result_summary(result)


func _log_result_summary(result) -> void:
	var lines: PackedStringArray = []
	lines.append("[color=cyan]Test Result[/color]")
	lines.append("  Test: %s" % result.display_name)
	lines.append("  Run ID: %s" % result.run_id)
	lines.append("  Status: [color=%s]%s[/color]" % [
		"light_green" if result.passed else "tomato",
		"PASS" if result.passed else "FAIL"
	])
	lines.append("  Checks: %d" % result.code_checks.size())
	lines.append("  Visuals: %d" % result.visual_checks.size())
	lines.append("  Logs: %d" % result.logs.size())
	lines.append("  Artifact: %s" % result.artifact_path)
	console.log(["\n".join(lines)], LogLevel.MESSAGE, "Tests")


func _collect_active_logs() -> void:
	if _active_result == null or console == null or not console.has_method("get_log_entries"):
		return
	var log_entries = console.get_log_entries()
	for index in range(_active_log_start_index, log_entries.size()):
		var entry = log_entries[index]
		var log_record = LogotTestLogRecordScript.new()
		log_record.level = int(entry.level)
		log_record.channel = str(entry.channel)
		log_record.timestamp = str(entry.timestamp)
		log_record.formatted = str(entry.formatted_full)
		log_record.stack_trace = str(entry.stack_trace)
		log_record.message = console._format_objects(entry.objects)
		_active_result.logs.append(log_record)


func _compute_result_passed(result) -> bool:
	for check_result in result.code_checks:
		if not check_result.passed:
			return false
	for visual_result in result.visual_checks:
		if not visual_result.passed:
			return false
	for log_record in result.logs:
		if int(log_record.level) == LogLevel.ERROR:
			return false
	return true


func _ensure_effective_assertion(result) -> void:
	if result == null:
		return
	if not result.code_checks.is_empty() or not result.visual_checks.is_empty():
		return
	var check_result = LogotTestCheckResultScript.new()
	check_result.name = EFFECTIVE_ASSERTION_CHECK
	check_result.passed = false
	check_result.details = EFFECTIVE_ASSERTION_DETAILS
	check_result.timestamp = _timestamp_now()
	result.code_checks.append(check_result)


func _build_result_summary(result) -> String:
	return "%s: %d code checks, %d visual checks, %d logs" % [
		"PASS" if result.passed else "FAIL",
		result.code_checks.size(),
		result.visual_checks.size(),
		result.logs.size()
	]


func _persist_result(result) -> void:
	var artifact_dir_path := ProjectSettings.globalize_path(result.artifact_directory)
	var visual_dir_path := ProjectSettings.globalize_path(result.visual_directory)
	DirAccess.make_dir_recursive_absolute(artifact_dir_path)
	DirAccess.make_dir_recursive_absolute(visual_dir_path)
	var save_error := ResourceSaver.save(result, result.artifact_path)
	if save_error != OK:
		_print_error("Failed to save test result '%s' (error %d)." % [result.run_id, save_error])


func _command_test_token(test_id: String) -> String:
	return _sanitize_token(
		test_id,
		["/", "\\", ":", " ", "\t", "\n", "\r", "\"", "'", "[", "]", "(", ")", "{", "}", ",", "."],
		"test"
	)


func _list_gd_files(root_path: String) -> Array[String]:
	return _collect_files(root_path, ".gd")


func _list_tres_files(root_path: String) -> Array[String]:
	return _collect_files(root_path, ".tres")


func _collect_files(root_path: String, suffix: String) -> Array[String]:
	var results: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		return results
	_walk_directory(root_path, suffix, results)
	results.sort()
	return results


func _walk_directory(path: String, suffix: String, out: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var child_path := "%s/%s" % [path, entry]
		if directory.current_is_dir():
			_walk_directory(child_path, suffix, out)
		elif entry.ends_with(suffix):
			out.append(child_path)
	directory.list_dir_end()


func _sanitize_file_component(value: String) -> String:
	return _sanitize_token(
		value,
		["/", "\\", ":", " ", "\t", "\n", "\r", "\"", "'", "[", "]", "(", ")", "{", "}", ","],
		"artifact"
	)


func _sanitize_token(value: String, invalid_characters: Array[String], fallback: String) -> String:
	var sanitized := value.strip_edges().to_lower()
	for character in invalid_characters:
		sanitized = sanitized.replace(str(character), "_")
	while sanitized.find("__") != -1:
		sanitized = sanitized.replace("__", "_")
	sanitized = sanitized.strip_edges().trim_prefix("_").trim_suffix("_")
	return sanitized if not sanitized.is_empty() else fallback


func _build_run_id() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d_%03d" % [
		int(now.get("year", 1970)),
		int(now.get("month", 1)),
		int(now.get("day", 1)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
		int(Time.get_ticks_msec() % 1000)
	]


func _timestamp_now() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(now.get("year", 1970)),
		int(now.get("month", 1)),
		int(now.get("day", 1)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0))
	]


func _get_console_log_count() -> int:
	if console == null or not console.has_method("get_log_entries"):
		return 0
	return console.get_log_entries().size()


func _build_discovery_report() -> Dictionary:
	var discovered_test_ids: Array[String] = []
	for test_case in get_tests():
		discovered_test_ids.append(str(test_case.id))
	return {
		"ok": _invalid_test_messages.is_empty(),
		"test_count": discovered_test_ids.size(),
		"test_ids": discovered_test_ids,
		"invalid_test_messages": get_invalid_test_messages(),
	}


func _build_batch_report(run_entries: Array[Dictionary], error_text := "") -> Dictionary:
	var passed_test_ids: Array[String] = []
	var failed_test_ids: Array[String] = []
	var failing_tests: Array[Dictionary] = []
	for entry in run_entries:
		if bool(entry.get("passed", false)):
			passed_test_ids.append(str(entry.get("test_id", "")))
		else:
			failed_test_ids.append(str(entry.get("test_id", "")))
			failing_tests.append(entry.duplicate(true))
	var resolved_error := str(error_text)
	if resolved_error.is_empty() and not failed_test_ids.is_empty():
		resolved_error = "%d of %d Logot test(s) failed." % [failed_test_ids.size(), run_entries.size()]
	var ok := resolved_error.is_empty() and failed_test_ids.is_empty() and not run_entries.is_empty() and _invalid_test_messages.is_empty()
	return {
		"ok": ok,
		"error": resolved_error,
		"total_tests": run_entries.size(),
		"passed_test_ids": passed_test_ids,
		"failed_test_ids": failed_test_ids,
		"failing_tests": failing_tests,
		"results": run_entries.duplicate(true),
		"invalid_test_messages": get_invalid_test_messages(),
	}


func _serialize_batch_result(result) -> Dictionary:
	return {
		"test_id": str(result.test_id),
		"display_name": str(result.display_name),
		"passed": bool(result.passed),
		"run_id": str(result.run_id),
		"artifact_path": str(result.artifact_path),
		"summary": str(result.summary),
		"check_count": result.code_checks.size(),
		"visual_count": result.visual_checks.size(),
		"log_count": result.logs.size(),
	}


func _log_invalid_test_messages() -> void:
	for message in _invalid_test_messages:
		_print_error(message)


func _print_line(message: String) -> void:
	if console != null and console.has_method("log"):
		console.log([message], LogLevel.MESSAGE, "Tests")


func _print_error(message: String) -> void:
	if console != null and console.has_method("log"):
		console.log([message], LogLevel.ERROR, "Tests")
