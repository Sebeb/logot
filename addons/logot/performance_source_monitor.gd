extends RefCounted

const API_VERSION := 1
const HISTORY_LIMIT := 500
const OTHER_PATH := "__other__"
const NATIVE_REMAINDER_PATH := "__engine_native_unattributed__"

var render_cpu_history: Array[Dictionary] = []
var gpu_history: Array[Dictionary] = []
var whole_cpu_history: Array[Dictionary] = []

var _bridge: Object
var _bridge_status: Dictionary = {}
var _bridge_error := ""
var _render_requested := false
var _scripts_requested := false
var _test_mode := false


func initialize() -> void:
	_bridge = null
	_bridge_status = {}
	_bridge_error = ""
	if not Engine.has_singleton("LogotProfilerBridge"):
		_bridge_error = "Profiler-enabled Godot debug build required"
		return
	_bridge = Engine.get_singleton("LogotProfilerBridge")
	if _bridge == null or not _bridge.has_method("get_api_version"):
		_bridge = null
		_bridge_error = "LogotProfilerBridge API is unavailable"
		return
	var bridge_api_version := int(_bridge.call("get_api_version"))
	if bridge_api_version != API_VERSION:
		_bridge_error = "Profiler bridge API mismatch (expected %d, found %d)" % [API_VERSION, bridge_api_version]
		_bridge = null
		return
	refresh_status()


func is_available() -> bool:
	return _test_mode or _bridge != null


func get_error() -> String:
	return _bridge_error


func refresh_status() -> Dictionary:
	if _bridge != null and _bridge.has_method("get_status"):
		var value: Variant = _bridge.call("get_status")
		_bridge_status = value as Dictionary if value is Dictionary else {}
	return _bridge_status.duplicate(true)


func set_capture_enabled(render_sources: bool, script_sources: bool) -> void:
	_render_requested = render_sources
	_scripts_requested = script_sources
	if _bridge != null and _bridge.has_method("set_capture_enabled"):
		_bridge.call("set_capture_enabled", render_sources, script_sources)


func is_capture_enabled() -> bool:
	return _render_requested or _scripts_requested


func is_test_mode() -> bool:
	return _test_mode


func drain_bridge_frames(whole_frame_total_ms: float) -> Dictionary:
	var latest_totals := {}
	if _bridge == null or not _bridge.has_method("drain_frames"):
		return latest_totals
	if _bridge.has_method("poll_frame"):
		_bridge.call("poll_frame")
	var raw_frames: Variant = _bridge.call("drain_frames")
	if not (raw_frames is Array):
		return latest_totals
	for raw_frame in raw_frames:
		if not (raw_frame is Dictionary):
			continue
		var frame := raw_frame as Dictionary
		match str(frame.get("kind", "")):
			"render":
				var render_totals := ingest_render_frame(frame)
				if not render_totals.is_empty():
					latest_totals = render_totals
			"script":
				ingest_script_frame(frame, whole_frame_total_ms)
	refresh_status()
	return latest_totals


func ingest_render_frame(frame: Dictionary) -> Dictionary:
	var frame_number := int(frame.get("frame_number", 0))
	var cpu_total := maxf(0.0, float(frame.get("render_cpu_total_ms", 0.0)))
	var gpu_total := maxf(0.0, float(frame.get("gpu_total_ms", 0.0)))
	var gpu_available := bool(frame.get("gpu_available", gpu_total > 0.0))
	var raw_sources: Variant = frame.get("render_sources", [])
	var cpu_sources: Array[Dictionary] = []
	var gpu_sources: Array[Dictionary] = []
	if raw_sources is Array:
		for raw_source in raw_sources:
			if not (raw_source is Dictionary):
				continue
			var source := raw_source as Dictionary
			var path := str(source.get("path", ""))
			var name := str(source.get("name", path))
			var cpu_ms := maxf(0.0, float(source.get("cpu_ms", 0.0)))
			var gpu_ms := maxf(0.0, float(source.get("gpu_ms", 0.0)))
			if cpu_ms > 0.0:
				cpu_sources.append(_make_source(path, name, cpu_ms))
			if gpu_ms > 0.0:
				gpu_sources.append(_make_source(path, name, gpu_ms))

	var cpu_sample := _make_sample(frame_number, cpu_total, cpu_sources)
	_upsert_history(render_cpu_history, cpu_sample)
	if gpu_available:
		_upsert_history(gpu_history, _make_sample(frame_number, gpu_total, gpu_sources))
	else:
		_upsert_history(gpu_history, {
			"frame_number": frame_number,
			"available": false,
			"warning": "GPU timestamps unavailable for this renderer",
		})
	return {"cpu_ms": cpu_total, "gpu_ms": gpu_total}


func ingest_script_frame(frame: Dictionary, whole_frame_total_ms: float) -> void:
	var frame_number := int(frame.get("frame_number", 0))
	var total_ms := maxf(0.001, whole_frame_total_ms)
	var sources: Array[Dictionary] = []
	var function_total := 0.0
	var raw_sources: Variant = frame.get("script_sources", [])
	if raw_sources is Array:
		for raw_source in raw_sources:
			if not (raw_source is Dictionary):
				continue
			var source := raw_source as Dictionary
			var duration_ms := maxf(0.0, float(source.get("self_ms", 0.0)))
			if duration_ms <= 0.0:
				continue
			function_total += duration_ms
			var normalized_source := _make_source(
				str(source.get("path", "")),
				str(source.get("name", source.get("path", ""))),
				duration_ms
			)
			normalized_source["call_count"] = int(source.get("call_count", 0))
			sources.append(normalized_source)

	var normalized_due_to_timing_skew := function_total > total_ms and function_total > 0.0
	if normalized_due_to_timing_skew:
		var scale := total_ms / function_total
		for source in sources:
			source["duration_ms"] = float(source.get("duration_ms", 0.0)) * scale
		function_total = total_ms
	var remainder_ms := maxf(0.0, total_ms - function_total)
	if remainder_ms > 0.0:
		sources.append(_make_source(
			NATIVE_REMAINDER_PATH,
			"Engine / Native / Unattributed",
			remainder_ms
		))
	var sample := _make_sample(frame_number, total_ms, sources)
	sample["normalized_due_to_timing_skew"] = normalized_due_to_timing_skew
	_upsert_history(whole_cpu_history, sample)


func get_history(kind: String) -> Array[Dictionary]:
	match kind:
		"render_cpu":
			return render_cpu_history.duplicate(true)
		"gpu":
			return gpu_history.duplicate(true)
		"whole_cpu":
			return whole_cpu_history.duplicate(true)
	return []


func trim_history_limit(sample_count: int) -> void:
	var limit := HISTORY_LIMIT
	if sample_count > 0:
		limit = clampi(sample_count, 2, HISTORY_LIMIT)
	_trim_history(render_cpu_history, limit)
	_trim_history(gpu_history, limit)
	_trim_history(whole_cpu_history, limit)


func get_current(kind: String) -> Dictionary:
	var history := get_history(kind)
	for index in range(history.size() - 1, -1, -1):
		if bool(history[index].get("available", false)):
			return history[index].duplicate(true)
	return {}


func get_widget_snapshot(kind: String, visible_sample_count: int, time_range_sec: float) -> Dictionary:
	var history := _history_with_percentages(_get_history_ref(kind), visible_sample_count, false, true)
	return {
		"current": _with_percentages(get_current(kind)),
		"history": history,
		"graph_time_range_sec": time_range_sec,
		"visible_sample_count": visible_sample_count,
	}


func get_snapshot(include_history: bool, visible_sample_count: int, cpu_mode: String, time_range_sec: float) -> Dictionary:
	var snapshot := {
		"schema_version": 1,
		"captured_at_unix_msec": int(Time.get_unix_time_from_system() * 1000.0),
		"engine_version": Engine.get_version_info(),
		"bridge_api_version": API_VERSION if is_available() else 0,
		"bridge_status": refresh_status(),
		"available": is_available(),
		"availability_warning": _bridge_error,
		"availability_warnings": _get_availability_warnings(),
		"cpu_mode": cpu_mode,
		"time_range_sec": time_range_sec,
		"current": {
			"render_cpu": _with_percentages(get_current("render_cpu")),
			"whole_cpu": _with_percentages(get_current("whole_cpu")),
			"gpu": _with_percentages(get_current("gpu")),
		},
	}
	if include_history:
		snapshot["history"] = {
			"render_cpu": _history_with_percentages(render_cpu_history, visible_sample_count),
			"whole_cpu": _history_with_percentages(whole_cpu_history, visible_sample_count),
			"gpu": _history_with_percentages(gpu_history, visible_sample_count),
		}
	return snapshot


func _get_availability_warnings() -> Dictionary:
	var warnings := {}
	if not _bridge_error.is_empty():
		warnings["bridge"] = _bridge_error
	if bool(_bridge_status.get("render_profile_seen", false)) and not bool(_bridge_status.get("gpu_timestamps_available", false)):
		var driver := RenderingServer.get_current_rendering_driver_name()
		if driver == "metal":
			warnings["gpu"] = "Godot 4.7 Metal does not implement GPU timestamp queries; use a Vulkan profiling run on Windows or Linux for real per-pass GPU timings"
		else:
			warnings["gpu"] = "GPU timestamps unavailable for %s/%s" % [RenderingServer.get_current_rendering_method(), driver]
	if bool(_bridge_status.get("script_profile_seen", false)) and not bool(_bridge_status.get("script_signatures_available", false)):
		warnings["script_signatures"] = "GDScript timings are available, but function names require scripts compiled with an active engine debugger"
	return warnings


func set_test_histories(render_cpu: Array, gpu: Array, whole_cpu: Array = []) -> void:
	_test_mode = true
	_bridge_error = ""
	render_cpu_history = _normalize_test_history(render_cpu)
	gpu_history = _normalize_test_history(gpu)
	whole_cpu_history = _normalize_test_history(whole_cpu)


func clear_test_mode() -> void:
	_test_mode = false
	render_cpu_history.clear()
	gpu_history.clear()
	whole_cpu_history.clear()
	initialize()


func _normalize_test_history(raw_history: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_sample in raw_history:
		if raw_sample is Dictionary:
			result.append((raw_sample as Dictionary).duplicate(true))
	return result


func _make_source(path: String, name: String, duration_ms: float) -> Dictionary:
	return {
		"path": path,
		"name": name,
		"duration_ms": duration_ms,
	}


func _make_sample(frame_number: int, total_ms: float, sources: Array[Dictionary]) -> Dictionary:
	return {
		"frame_number": frame_number,
		"available": true,
		"total_ms": total_ms,
		"sources": sources,
	}


func _upsert_history(history: Array[Dictionary], sample: Dictionary) -> void:
	var frame_number := int(sample.get("frame_number", 0))
	for index in history.size():
		if int(history[index].get("frame_number", -1)) == frame_number:
			history[index] = sample
			return
	var insert_at := history.size()
	while insert_at > 0 and int(history[insert_at - 1].get("frame_number", -1)) > frame_number:
		insert_at -= 1
	if insert_at == history.size() and not history.is_empty():
		var previous_frame := int(history[-1].get("frame_number", frame_number))
		var gap_count := mini(maxi(0, frame_number - previous_frame - 1), HISTORY_LIMIT)
		for missing_offset in gap_count:
			history.append({
				"frame_number": previous_frame + missing_offset + 1,
				"available": false,
				"generated_gap": true,
			})
		history.append(sample)
	else:
		history.insert(insert_at, sample)
	while history.size() > HISTORY_LIMIT:
		history.pop_front()


func _get_history_ref(kind: String) -> Array[Dictionary]:
	match kind:
		"render_cpu":
			return render_cpu_history
		"gpu":
			return gpu_history
		"whole_cpu":
			return whole_cpu_history
	return []


func _trim_history(history: Array[Dictionary], limit: int) -> void:
	while history.size() > limit:
		history.pop_front()


func _with_percentages(sample: Dictionary) -> Dictionary:
	if sample.is_empty():
		return {}
	var result := sample.duplicate(true)
	var total_ms := maxf(0.0, float(result.get("total_ms", 0.0)))
	var sources: Array = result.get("sources", []) as Array
	for source_variant in sources:
		if source_variant is Dictionary:
			var source := source_variant as Dictionary
			source["percentage"] = float(source.get("duration_ms", 0.0)) * 100.0 / total_ms if total_ms > 0.0 else 0.0
	return result


func _history_with_percentages(history: Array[Dictionary], visible_sample_count: int, include_generated_gaps: bool = true, available_only: bool = false) -> Array:
	var start_index := 0
	if visible_sample_count > 0:
		start_index = maxi(0, history.size() - visible_sample_count)
	var result: Array = []
	for index in range(start_index, history.size()):
		if not include_generated_gaps and bool(history[index].get("generated_gap", false)):
			continue
		if available_only and not bool(history[index].get("available", false)):
			continue
		result.append(_with_percentages(history[index]))
	return result
