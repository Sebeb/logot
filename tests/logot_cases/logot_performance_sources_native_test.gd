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
	var snapshot: Dictionary = Console.get_performance_source_snapshot(true)
	var current: Dictionary = snapshot.get("current", {}) as Dictionary
	var render_cpu: Dictionary = current.get("render_cpu", {}) as Dictionary
	var whole_cpu: Dictionary = current.get("whole_cpu", {}) as Dictionary
	var gpu: Dictionary = current.get("gpu", {}) as Dictionary
	var bridge_status: Dictionary = snapshot.get("bridge_status", {}) as Dictionary
	var gpu_timestamps_available := bool(bridge_status.get("gpu_timestamps_available", false))
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
	if gpu_timestamps_available and not gpu.is_empty():
		ctx.check("native_gpu_sources", not (gpu.get("sources", []) as Array).is_empty(), str(gpu))
	else:
		var warnings: Dictionary = snapshot.get("availability_warnings", {}) as Dictionary
		ctx.check("native_gpu_unavailable_reported", warnings.has("gpu"), str(snapshot))
	var path := Console.save_performance_source_snapshot("native-bridge-test")
	ctx.check("native_snapshot_written", not path.is_empty() and FileAccess.file_exists(path), path)
	Console._set_performance_pin_mode("fps", false)
	Console._set_performance_source_cpu_mode("render")
