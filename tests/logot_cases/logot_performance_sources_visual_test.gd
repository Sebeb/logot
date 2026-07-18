extends "res://addons/logot/testing/logot_test_case.gd"


func _init() -> void:
	id = "logot_performance_sources_visual"
	display_name = "Logot Performance Allocation Visual"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	await ctx.wait_frames(2)
	var render: Array = []
	var gpu: Array = []
	for frame_offset in 80:
		var sources: Array[Dictionary] = []
		var gpu_sources: Array[Dictionary] = []
		var render_total := 0.0
		var gpu_total := 0.0
		for index in 10:
			var render_duration := 0.35 + absf(sin(float(frame_offset + index * 4) * 0.08)) * (1.1 - index * 0.06)
			var gpu_duration := 0.25 + absf(cos(float(frame_offset + index * 3) * 0.07)) * (0.9 - index * 0.045)
			sources.append({"path": "render/stage_%02d" % index, "name": "Stage %02d" % index, "duration_ms": render_duration})
			gpu_sources.append({"path": "gpu/pass_%02d" % index, "name": "Pass %02d" % index, "duration_ms": gpu_duration})
			render_total += render_duration
			gpu_total += gpu_duration
		render.append({"frame_number": 1000 + frame_offset, "available": true, "total_ms": render_total, "sources": sources})
		gpu.append({"frame_number": 1000 + frame_offset, "available": true, "total_ms": gpu_total, "sources": gpu_sources})

	Console.set_performance_source_test_histories(render, gpu, [])
	Console._set_performance_source_cpu_mode("render")
	Console._set_performance_pin_mode("detailed", false)
	await ctx.wait_frames(5)
	await ctx.capture_visual("performance_source_graphs")
	Console._set_performance_pin_mode("fps", false)
	Console.clear_performance_source_test_histories()
