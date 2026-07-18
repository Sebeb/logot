class_name LogotTestContext
extends RefCounted


var test_id := ""
var scene_root: Node = null
var console: Node = null
var _manager = null
var _aborted := false


func _init(manager, in_console: Node, in_test_id: String, in_scene_root: Node) -> void:
	_manager = manager
	console = in_console
	test_id = in_test_id
	scene_root = in_scene_root


func check(name: String, condition: bool, details := "") -> bool:
	if _aborted:
		return false
	if _manager == null:
		return condition
	var passed := bool(condition)
	_manager.record_code_check(name, passed, str(details))
	if not passed and _manager.should_abort_after_failure():
		_aborted = true
	return passed


func fail(name: String, details := "") -> bool:
	check(name, false, details)
	return false


func log(objects: Array, level: int = 16, channel := "") -> void:
	if _aborted:
		return
	if console == null or not console.has_method("log"):
		return
	console.log(objects, level, channel)


func capture_visual(name: String, path := ""):
	if _aborted:
		return {"ok": false, "error": "Test aborted after fail_fast failure."}
	if _manager == null:
		return {}
	return await _manager.capture_visual_checkpoint(name, str(path))


func wait_frames(frame_count := 1):
	if _aborted:
		return
	if console == null or console.get_tree() == null:
		return
	for _index in range(maxi(1, frame_count)):
		await console.get_tree().process_frame


func wait_seconds(duration_sec: float):
	if _aborted:
		return
	if console == null or console.get_tree() == null:
		return
	await console.get_tree().create_timer(maxf(0.0, duration_sec)).timeout


func should_abort() -> bool:
	return _aborted
