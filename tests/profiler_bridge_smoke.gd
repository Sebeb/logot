extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Engine.has_singleton("LogotProfilerBridge"):
		push_error("LogotProfilerBridge singleton is missing")
		quit(2)
		return
	var bridge: Object = Engine.get_singleton("LogotProfilerBridge")
	if bridge == null or int(bridge.call("get_api_version")) != 1:
		push_error("LogotProfilerBridge API handshake failed")
		quit(3)
		return
	bridge.call("set_capture_enabled", true, true)
	print("LOGOT_PROFILER_SMOKE_START status=%s" % str(bridge.call("get_status")))
	for _index in 30:
		await process_frame
		bridge.call("poll_frame")
	var frames: Array = bridge.call("drain_frames") as Array
	print("LOGOT_PROFILER_SMOKE_DRAIN status=%s" % str(bridge.call("get_status")))
	bridge.call("set_capture_enabled", false, false)
	var found_script := false
	for frame_variant in frames:
		if frame_variant is Dictionary and str((frame_variant as Dictionary).get("kind", "")) == "script":
			found_script = true
			break
	var console := root.get_node_or_null("Logot")
	if console == null:
		console = root.get_node_or_null("Console")
	if not found_script and console != null and console.has_method("get_performance_source_snapshot"):
		var snapshot: Dictionary = console.call("get_performance_source_snapshot", true) as Dictionary
		var current: Dictionary = snapshot.get("current", {}) as Dictionary
		found_script = not (current.get("whole_cpu", {}) as Dictionary).is_empty()
		var snapshot_path := str(console.call("save_performance_source_snapshot", "bridge-smoke"))
		if snapshot_path.is_empty() or not FileAccess.file_exists(snapshot_path):
			push_error("Logot failed to save the bridge smoke snapshot")
			quit(5)
			return
	if not found_script:
		push_error("Profiler bridge returned no script data: %s" % str(frames))
		quit(4)
		return
	print("LOGOT_PROFILER_SMOKE_PASS frames=%d status=%s" % [frames.size(), str(bridge.call("get_status"))])
	quit(0)
