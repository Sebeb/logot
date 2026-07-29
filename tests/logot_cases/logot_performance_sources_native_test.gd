extends "res://addons/logot/testing/logot_test_case.gd"


func _init() -> void:
	id = "logot_performance_sources_native"
	display_name = "Logot Performance Allocation Native Bridge"
	scene_path = "res://Main.tscn"
	fail_fast = false


func run(ctx) -> void:
	await ctx.wait_frames(2)
	if not Engine.has_singleton("LogotProfilerBridge"):
		ctx.check("native_bridge_optional", not OS.get_environment("LOGOT_REQUIRE_PROFILER_BRIDGE") == "1", "Profiler-enabled Godot build required")
		return

	Console._set_performance_source_cpu_mode("both")
	Console._set_performance_pin_mode("detailed", false)
	for _index in 120:
		# Keep the same two-frame lease that a visible GPU allocation widget issues.
		# This makes the bridge integration deterministic even when the command
		# runner temporarily suppresses the in-game pinned overlay.
		Console.request_performance_source_collection("gpu")
		Console.request_performance_source_collection("cpu", "both")
		await ctx.wait_frames(1)
		# SceneTree --script runs do not invoke Logot's game-only _process path on
		# editor binaries, so drive the same monitor tick explicitly.
		Console._update_performance_monitor(1.0 / 60.0)
	var snapshot: Dictionary = Console.get_performance_source_snapshot(true)
	var current: Dictionary = snapshot.get("current", {}) as Dictionary
	var render_cpu: Dictionary = current.get("render_cpu", {}) as Dictionary
	var whole_cpu: Dictionary = current.get("whole_cpu", {}) as Dictionary
	var gpu: Dictionary = current.get("gpu", {}) as Dictionary
	var bridge_status: Dictionary = snapshot.get("bridge_status", {}) as Dictionary
	var gpu_timestamps_available := bool(bridge_status.get("gpu_timestamps_available", false))
	var gpu_timing_mode := str(bridge_status.get("gpu_timing_mode", "unknown"))
	ctx.check("native_render_cpu_sample", not render_cpu.is_empty(), str(snapshot))
	ctx.check("native_whole_cpu_sample", not whole_cpu.is_empty(), str(snapshot))
	ctx.check("native_gpu_state", not gpu.is_empty() if gpu_timestamps_available else gpu.is_empty(), str(snapshot))
	if not render_cpu.is_empty():
		ctx.check("native_render_cpu_sources", not (render_cpu.get("sources", []) as Array).is_empty(), str(render_cpu))
	if not whole_cpu.is_empty():
		var whole_sources: Array = whole_cpu.get("sources", []) as Array
		ctx.check("native_whole_cpu_sources", not whole_sources.is_empty(), str(whole_cpu))
		var paths_are_named := true
		for source_variant in whole_sources:
			if source_variant is Dictionary and str((source_variant as Dictionary).get("path", "")).is_empty():
				paths_are_named = false
				break
		ctx.check("native_whole_cpu_paths", paths_are_named, str(whole_cpu))
	if gpu_timing_mode == "breakdown" and not gpu.is_empty():
		ctx.check("native_gpu_sources", not (gpu.get("sources", []) as Array).is_empty(), str(gpu))
	elif gpu_timing_mode == "total_only" and not gpu.is_empty():
		ctx.check("native_gpu_total", float(gpu.get("total_ms", 0.0)) > 0.0, str(gpu))
		ctx.check("native_gpu_no_fake_sources", (gpu.get("sources", []) as Array).is_empty(), str(gpu))
		ctx.check("native_gpu_fallback_note", not str(gpu.get("note", "")).is_empty(), str(gpu))
	else:
		var warnings: Dictionary = snapshot.get("availability_warnings", {}) as Dictionary
		ctx.check("native_gpu_unavailable_reported", warnings.has("gpu"), str(snapshot))
	var path: String = Console.save_performance_source_snapshot("native-bridge-test")
	ctx.check("native_snapshot_written", not path.is_empty() and FileAccess.file_exists(path), path)
	Console._set_performance_pin_mode("fps", false)
	Console._set_performance_source_cpu_mode("render")
	for _index in 5:
		Console.request_performance_source_collection("cpu", "render")
		await ctx.wait_frames(1)
		Console._update_performance_monitor(1.0 / 60.0)
	var cpu_only_status: Dictionary = (Engine.get_singleton("LogotProfilerBridge") as Object).call("get_status") as Dictionary
	ctx.check("native_cpu_capture_without_gpu", bool(cpu_only_status.get("render_requested", false)) and not bool(cpu_only_status.get("gpu_capture_requested", true)), str(cpu_only_status))
	ctx.check("native_cpu_capture_gpu_measurement_off", not bool(Console._performance_gpu_measurement_enabled), str(Console._performance_gpu_measurement_enabled))
	await ctx.wait_frames(5)
	var stopped_status: Dictionary = (Engine.get_singleton("LogotProfilerBridge") as Object).call("get_status") as Dictionary
	ctx.check("native_capture_stopped", not bool(stopped_status.get("render_requested", true)) and not bool(stopped_status.get("owns_render_profiling", true)), str(stopped_status))
	ctx.check("native_gpu_capture_stopped", not bool(stopped_status.get("gpu_capture_requested", true)), str(stopped_status))
	ctx.check("native_gpu_measurement_stopped", not bool(Console._performance_gpu_measurement_enabled), str(Console._performance_gpu_measurement_enabled))
