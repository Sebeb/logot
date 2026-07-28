extends "res://addons/logot/testing/logot_test_case.gd"

const CPU_WIDGET_PATH := "dev/performance/allocation/cpu"
const GPU_WIDGET_PATH := "dev/performance/allocation/gpu"
const OVERVIEW_WIDGET_PATH := "dev/performance/overview"
const PERFORMANCE_TIME_RANGE_PATH := "dev/performance/time_range"
const PERFORMANCE_ALLOCATION_UPDATE_SPEED_PATH := "dev/performance/allocation/update_speed"
const PERFORMANCE_ALLOCATION_CPU_MODE_PATH := "dev/performance/allocation/cpu/mode"
const LEGACY_OVERVIEW_TIME_RANGE_PATH := "dev/performance/overview/time_range"
const LEGACY_CPU_SOURCES_WIDGET_PATH := "dev/performance/sources/cpu"
const LEGACY_GPU_SOURCES_WIDGET_PATH := "dev/performance/sources/gpu"
const LEGACY_SOURCES_SNAPSHOT_PATH := "dev/performance/sources/snapshot"
const PERFORMANCE_WIDGET_BASE_PATH := "res://addons/logot/widgets/performance_widget_base.gd"


func _init() -> void:
	id = "logot_performance_sources"
	display_name = "Logot Performance Allocation"
	scene_path = "res://Main.tscn"
	fail_fast = false


func run(ctx) -> void:
	await ctx.wait_frames(2)
	if not ctx.check("console_available", Console != null):
		return
	if not ctx.check("source_api_available", Console.has_method("set_performance_source_test_histories")):
		return
	var original_time_range := Console._get_performance_graph_time_range()
	var original_performance_mode := Console._performance_pin_mode
	var original_update_rate := Console.get_performance_source_update_rate_hz()

	var histories := _build_histories()
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])
	Console._set_performance_source_cpu_mode("render")
	Console._set_performance_graph_time_range(10.0)
	Console._set_performance_source_update_rate_hz(10.0)

	var snapshot: Dictionary = Console.get_performance_source_snapshot(true)
	ctx.check("snapshot_schema", int(snapshot.get("schema_version", 0)) == 1, str(snapshot))
	ctx.check("snapshot_reports_test_bridge", bool(snapshot.get("available", false)), str(snapshot))
	var current: Dictionary = snapshot.get("current", {}) as Dictionary
	ctx.check("snapshot_has_render_cpu", not (current.get("render_cpu", {}) as Dictionary).is_empty())
	ctx.check("snapshot_has_gpu", not (current.get("gpu", {}) as Dictionary).is_empty())
	ctx.check("snapshot_has_whole_cpu", not (current.get("whole_cpu", {}) as Dictionary).is_empty())
	ctx.check(
		"timestamp_query_limit_supports_render_profiling",
		int(ProjectSettings.get_setting("debug/settings/profiler/max_timestamp_query_elements", 256)) >= 4096,
		str(ProjectSettings.get_setting("debug/settings/profiler/max_timestamp_query_elements", 256))
	)
	var commands: Dictionary = Console.get_console_commands()
	ctx.check("time_range_command_moved_to_performance_root", commands.has(PERFORMANCE_TIME_RANGE_PATH), str(commands.keys()))
	ctx.check("allocation_update_speed_command_registered", commands.has(PERFORMANCE_ALLOCATION_UPDATE_SPEED_PATH), str(commands.keys()))
	ctx.check("legacy_overview_time_range_command_removed", not commands.has(LEGACY_OVERVIEW_TIME_RANGE_PATH), str(commands.keys()))
	ctx.check(
		"legacy_sources_commands_renamed_to_allocation",
		not commands.has(LEGACY_CPU_SOURCES_WIDGET_PATH) and not commands.has(LEGACY_GPU_SOURCES_WIDGET_PATH) and not commands.has(LEGACY_SOURCES_SNAPSHOT_PATH),
		str(commands.keys())
	)

	# Option labels such as "Render CPU" and "10 Hz" become palette sub-command paths, and a
	# label containing a space must still execute instead of failing on argument count.
	var spaced_option_failures: Array[String] = []
	for option_path in [
		"%s/Render CPU" % PERFORMANCE_ALLOCATION_CPU_MODE_PATH,
		"%s/Whole Frame" % PERFORMANCE_ALLOCATION_CPU_MODE_PATH,
		"%s/10 Hz" % PERFORMANCE_ALLOCATION_UPDATE_SPEED_PATH,
	]:
		var option_result: Dictionary = Console.execute_console_command(option_path)
		if not bool(option_result.get("ok", false)):
			spaced_option_failures.append("%s -> %s" % [option_path, option_result.get("error", "")])
	ctx.check("options_with_spaced_labels_execute", spaced_option_failures.is_empty(), str(spaced_option_failures))
	ctx.check(
		"options_with_spaced_labels_apply_their_value",
		Console.get_performance_source_cpu_mode() == "whole" and is_equal_approx(Console.get_performance_source_update_rate_hz(), 10.0),
		"mode=%s rate=%f" % [Console.get_performance_source_cpu_mode(), Console.get_performance_source_update_rate_hz()]
	)
	Console._set_performance_source_cpu_mode("render")
	Console._set_performance_source_update_rate_hz(10.0)

	var display: LogotDisplay = Console._get_active_display()
	if not ctx.check("active_display", display != null):
		Console._set_performance_graph_time_range(original_time_range)
		Console._set_performance_source_update_rate_hz(original_update_rate)
		Console._set_performance_pin_mode(original_performance_mode, true)
		Console.clear_performance_source_test_histories()
		return
	Console._set_performance_pin_mode("detailed", false)
	await ctx.wait_frames(2)
	ctx.check(
		"detailed_widgets_are_pinned",
		not display.is_display_variable_pinned("dev/performance/fps")
			and display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	ctx.check(
		"detailed_widgets_share_top_right_corner",
		display.get_pinned_display_variable_corner(OVERVIEW_WIDGET_PATH) == "top_right"
			and display.get_pinned_display_variable_corner(CPU_WIDGET_PATH) == "top_right"
			and display.get_pinned_display_variable_corner(GPU_WIDGET_PATH) == "top_right"
	)
	Console._set_performance_pin_mode("fps", false)
	await ctx.wait_frames(1)
	ctx.check(
		"fps_mode_pins_only_fps_number",
		display.is_display_variable_pinned("dev/performance/fps")
			and not display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and not display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and not display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	Console._cycle_performance_pin_mode()
	await ctx.wait_frames(1)
	ctx.check(
		"f3_cycle_overview_mode_pins_only_overview",
		Console._performance_pin_mode == "overview"
			and not display.is_display_variable_pinned("dev/performance/fps")
			and display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and not display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and not display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	Console._cycle_performance_pin_mode()
	await ctx.wait_frames(1)
	ctx.check(
		"f3_cycle_detailed_mode_pins_overview_cpu_and_available_gpu",
		Console._performance_pin_mode == "detailed"
			and not display.is_display_variable_pinned("dev/performance/fps")
			and display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	Console._cycle_performance_pin_mode()
	await ctx.wait_frames(1)
	ctx.check(
		"f3_cycle_hidden_mode_pins_nothing",
		Console._performance_pin_mode == "hidden"
			and not display.is_display_variable_pinned("dev/performance/fps")
			and not display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and not display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and not display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	Console._cycle_performance_pin_mode()
	await ctx.wait_frames(1)
	ctx.check(
		"f3_cycle_returns_to_fps_mode",
		Console._performance_pin_mode == "fps"
			and display.is_display_variable_pinned("dev/performance/fps")
			and not display.is_display_variable_pinned(OVERVIEW_WIDGET_PATH)
			and not display.is_display_variable_pinned(CPU_WIDGET_PATH)
			and not display.is_display_variable_pinned(GPU_WIDGET_PATH)
	)
	# Empty test histories keep test mode on while reporting no allocation data on any build.
	Console.set_performance_source_test_histories([], [], [])
	Console._set_performance_pin_mode("overview", false)
	ctx.check(
		"f3_skips_detailed_without_allocation_data",
		Console._next_performance_pin_mode("overview") == "hidden",
		Console._next_performance_pin_mode("overview")
	)
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])
	ctx.check(
		"f3_includes_detailed_with_allocation_data",
		Console._next_performance_pin_mode("overview") == "detailed",
		Console._next_performance_pin_mode("overview")
	)
	Console._set_performance_pin_mode("overview", true)
	Console._set_performance_source_update_rate_hz(12.0)
	Console._performance_pin_mode = "fps"
	Console._performance_source_update_rate_hz = 4.0
	Console._load_performance_pin_mode()
	ctx.check("performance_display_mode_persists_between_sessions", Console._performance_pin_mode == "overview", Console._performance_pin_mode)
	ctx.check("allocation_update_speed_persists_between_sessions", is_equal_approx(Console.get_performance_source_update_rate_hz(), 12.0), str(Console.get_performance_source_update_rate_hz()))
	Console._set_performance_source_update_rate_hz(10.0)
	Console._set_performance_pin_mode("fps", false)
	var registered_widgets: Dictionary = Console.get_widgets()
	ctx.check(
		"performance_widgets_registered_in_logot_framework",
		registered_widgets.has(OVERVIEW_WIDGET_PATH) and registered_widgets.has(CPU_WIDGET_PATH) and registered_widgets.has(GPU_WIDGET_PATH),
		str(registered_widgets.keys())
	)
	ctx.check("legacy_graphs_widget_renamed", not registered_widgets.has("dev/performance/graphs"), str(registered_widgets.keys()))
	ctx.check(
		"performance_widget_labels",
		str(registered_widgets[OVERVIEW_WIDGET_PATH].get("display_label")) == "Performance Overview"
			and str(registered_widgets[CPU_WIDGET_PATH].get("display_label")) == "CPU Allocation"
			and str(registered_widgets[GPU_WIDGET_PATH].get("display_label")) == "GPU Allocation"
	)
	var widget: Control = display._create_widget_instance(CPU_WIDGET_PATH, "palette")
	if not ctx.check("cpu_widget_created", widget != null):
		Console._set_performance_graph_time_range(original_time_range)
		Console._set_performance_source_update_rate_hz(original_update_rate)
		Console._set_performance_pin_mode(original_performance_mode, true)
		Console.clear_performance_source_test_histories()
		return
	var gpu_widget: Control = display._create_widget_instance(GPU_WIDGET_PATH, "palette")
	var overview_widget: Control = display._create_widget_instance(OVERVIEW_WIDGET_PATH, "palette")
	ctx.check("gpu_widget_created_by_framework", gpu_widget != null)
	ctx.check("overview_widget_created_by_framework", overview_widget != null)
	if gpu_widget != null and overview_widget != null:
		ctx.check(
			"source_widgets_match_overview_width",
			is_equal_approx(widget.custom_minimum_size.x, overview_widget.custom_minimum_size.x)
				and is_equal_approx(gpu_widget.custom_minimum_size.x, overview_widget.custom_minimum_size.x),
			"cpu=%s gpu=%s overview=%s" % [widget.custom_minimum_size.x, gpu_widget.custom_minimum_size.x, overview_widget.custom_minimum_size.x]
		)
		var cpu_base := widget.get_script().get_base_script() as Script
		var gpu_base := gpu_widget.get_script().get_base_script() as Script
		var overview_base := overview_widget.get_script().get_base_script() as Script
		ctx.check(
			"performance_widgets_share_exact_framework_base",
			cpu_base != null and gpu_base == cpu_base and overview_base == cpu_base and cpu_base.resource_path == PERFORMANCE_WIDGET_BASE_PATH,
			"cpu=%s gpu=%s overview=%s" % [cpu_base, gpu_base, overview_base]
		)
		ctx.check(
			"performance_widgets_share_framework_lifecycle",
			widget.has_method("configure_logot_widget") and widget.has_method("refresh_logot_widget")
				and gpu_widget.has_method("configure_logot_widget") and gpu_widget.has_method("refresh_logot_widget")
				and overview_widget.has_method("configure_logot_widget") and overview_widget.has_method("refresh_logot_widget")
		)
		ctx.check("source_widget_refreshes_foreground_only", not bool(widget.get("refresh_in_background")) and not bool(gpu_widget.get("refresh_in_background")))
	if gpu_widget != null:
		gpu_widget.free()
	if overview_widget != null:
		overview_widget.free()
	display.add_child(widget)
	await ctx.wait_frames(1)
	widget.refresh_logot_widget(0.0)
	await ctx.wait_frames(1)
	var debug: Dictionary = widget.get_debug_state()
	var panels: Array = debug.get("panels", []) as Array
	ctx.check("render_mode_has_one_panel", int(debug.get("panel_count", 0)) == 1, str(debug))
	if not panels.is_empty():
		var panel: Dictionary = panels[0] as Dictionary
		var top_paths: Array = panel.get("top_paths", []) as Array
		var colors: Dictionary = panel.get("colors", {}) as Dictionary
		var stack_top_to_bottom_paths: Array = panel.get("stack_top_to_bottom_paths", []) as Array
		ctx.check("current_top_ten", top_paths.size() == 10, str(top_paths))
		ctx.check("bridge_other_bucket_is_not_a_legend_source", not top_paths.has("__other__"), str(top_paths))
		ctx.check("top_ten_colors_unique", _unique_values(colors.values()).size() == 10, str(colors))
		ctx.check(
			"graph_stack_order_matches_source_list_order",
			stack_top_to_bottom_paths.size() >= top_paths.size() and stack_top_to_bottom_paths.slice(0, top_paths.size()) == top_paths,
			"stack=%s top=%s" % [stack_top_to_bottom_paths, top_paths]
		)
		var display_names: Array = panel.get("display_names", []) as Array
		ctx.check(
			"duplicate_leaf_names_are_distinguished",
			display_names.size() >= 2 and str(display_names[0]) != str(display_names[1]) and str(display_names[0]).ends_with("Shared") and str(display_names[1]).ends_with("Shared"),
			str(display_names)
		)
		ctx.check("departed_source_is_gray", (panel.get("gray_history_paths", []) as Array).has("source/departed"), str(panel))
		ctx.check(
			"stack_accounts_for_total",
			is_equal_approx(float(panel.get("current_accounted_ms", 0.0)), float(panel.get("total_ms", -1.0))),
			str(panel)
		)
		ctx.check("now_bar_is_quarter_width", is_equal_approx(float(panel.get("now_width", 0.0)), 10.5), str(panel))
		ctx.check("now_label_hidden", not bool(panel.get("now_label_visible", true)), str(panel))
		ctx.check("legend_hides_percentages", not bool(panel.get("legend_percentage_visible", true)), str(panel))
		ctx.check("legend_uses_slightly_narrower_time_pill", float(panel.get("legend_time_pill_width", 0.0)) >= 30.0 and float(panel.get("legend_time_pill_width", 0.0)) < 34.0, str(panel))
		ctx.check("legend_times_use_two_decimals", int(panel.get("time_precision_digits", 0)) == 2, str(panel))
		ctx.check("legend_source_titles_are_larger", int(panel.get("legend_name_font_size", 0)) > 9, str(panel))
		ctx.check("legend_source_titles_use_full_row_width", float(panel.get("legend_name_width", 0.0)) >= 145.0, str(panel))
		ctx.check("source_list_is_below_graph", bool(panel.get("graph_above_legend", false)), str(panel))
		ctx.check("history_columns_are_gapless", bool(panel.get("history_columns_gapless", false)), str(panel))
		ctx.check("history_uses_right_packed_slices", str(panel.get("history_renderer", "")) == "right_packed_fixed_width_slices", str(panel))
		ctx.check(
			"history_slices_are_never_stretched",
			float(panel.get("history_slice_width", 0.0)) > 0.0 and float(panel.get("history_slice_width", 0.0)) <= 10.5,
			str(panel)
		)
		ctx.check(
			"short_history_leaves_blank_space_on_the_left",
			float(panel.get("history_blank_left_width", -1.0)) > 0.0,
			str(panel)
		)
		ctx.check(
			"empty_samples_do_not_reserve_a_column",
			int(panel.get("history_column_count", -1)) == 2 and int(panel.get("history_count", 0)) == 3,
			str(panel)
		)
		var overview_snapshot: Dictionary = Console.get_performance_snapshot()
		ctx.check(
			"source_history_matches_overview_time_window",
			is_equal_approx(float(panel.get("time_range_sec", -1.0)), float(overview_snapshot.get("graph_time_range_sec", -2.0)))
				and int(panel.get("history_count", 0)) <= int(panel.get("visible_sample_count", -1)),
			"panel=%s overview=%s" % [panel, overview_snapshot]
		)

	var stable_gpu := histories["gpu"] as Array
	var stable_whole := histories["whole"] as Array

	# Sub-millisecond render-CPU totals must still scale across the graph height instead of
	# pegging every bar to the top, and a quiet frame must draw shorter than a busy one.
	Console.set_performance_source_test_histories(_make_scale_history(1.2, 0.3), stable_gpu, stable_whole)
	widget.refresh_logot_widget(0.0)
	await ctx.wait_frames(1)
	var quiet_panel: Dictionary = ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary)
	var quiet_fraction := float(quiet_panel.get("current_stack_height_fraction", -1.0))
	Console.set_performance_source_test_histories(_make_scale_history(1.2, 1.2), stable_gpu, stable_whole)
	widget.refresh_logot_widget(0.0)
	await ctx.wait_frames(1)
	var busy_panel: Dictionary = ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary)
	var busy_fraction := float(busy_panel.get("current_stack_height_fraction", -1.0))
	ctx.check("graph_height_autoscales_to_visible_peak", str(busy_panel.get("graph_scale_mode", "")) == "auto_peak_visible", str(busy_panel))
	ctx.check(
		"submillisecond_totals_use_the_graph_height",
		quiet_fraction > 0.0 and quiet_fraction < 0.5 and busy_fraction > 0.8 and busy_fraction <= 1.0,
		"quiet=%f busy=%f quiet_panel=%s busy_panel=%s" % [quiet_fraction, busy_fraction, quiet_panel, busy_panel]
	)
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])

	var long_history := _make_long_history(500)
	Console.set_performance_source_test_histories(long_history, stable_gpu, stable_whole)
	Console._set_performance_graph_time_range(1.0)
	var retained_history: Array = Console._performance_source_monitor.call("get_history", "render_cpu") as Array
	var retained_visible_count := Console._get_performance_source_visible_sample_count()
	ctx.check(
		"source_history_remembered_within_time_range",
		retained_history.size() <= mini(500, retained_visible_count),
		"retained=%d visible=%d" % [retained_history.size(), retained_visible_count]
	)
	Console._set_performance_graph_time_range(10.0)
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])

	Console.set_performance_source_test_histories([], stable_gpu, stable_whole)
	Console._performance_source_monitor.call("ingest_render_frame", _make_sparse_render_frame(300, 5.0, 3.0))
	Console._performance_source_monitor.call("ingest_render_frame", _make_sparse_render_frame(330, 4.0, 4.0))
	var stored_sparse_history: Array = Console._performance_source_monitor.call("get_history", "render_cpu") as Array
	var drawable_sparse_snapshot: Dictionary = Console.get_performance_source_widget_snapshot("render_cpu")
	var drawable_sparse_history: Array = drawable_sparse_snapshot.get("history", []) as Array
	ctx.check(
		"sampled_history_compacts_generated_gaps_for_display",
		stored_sparse_history.size() > drawable_sparse_history.size() and drawable_sparse_history.size() == 2,
		"stored=%d drawable=%d history=%s" % [stored_sparse_history.size(), drawable_sparse_history.size(), drawable_sparse_history]
	)
	Console.set_performance_source_test_histories(_make_unavailable_gap_history(), stable_gpu, stable_whole)
	drawable_sparse_snapshot = Console.get_performance_source_widget_snapshot("render_cpu")
	drawable_sparse_history = drawable_sparse_snapshot.get("history", []) as Array
	ctx.check(
		"sampled_history_compacts_unavailable_gaps_for_display",
		drawable_sparse_history.size() == 2,
		"drawable=%d history=%s" % [drawable_sparse_history.size(), drawable_sparse_history]
	)
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])

	Console.set_performance_source_test_histories(_make_order_history(6.0, 4.0), stable_gpu, stable_whole)
	widget.refresh_logot_widget(0.0)
	await ctx.wait_frames(1)
	var order_paths := ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary).get("top_paths", []) as Array
	ctx.check("ranking_starts_by_current_usage", order_paths == ["order/a", "order/b"], str(order_paths))
	Console.set_performance_source_test_histories(_make_order_history(4.0, 6.0), stable_gpu, stable_whole)
	widget.refresh_logot_widget(0.99)
	await ctx.wait_frames(1)
	order_paths = ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary).get("top_paths", []) as Array
	ctx.check("ranking_holds_before_one_second", order_paths == ["order/a", "order/b"], str(order_paths))
	widget.refresh_logot_widget(0.02)
	await ctx.wait_frames(1)
	order_paths = ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary).get("top_paths", []) as Array
	ctx.check("ranking_changes_after_sustained_three_percent_lead", order_paths == ["order/b", "order/a"], str(order_paths))
	Console.set_performance_source_test_histories(_make_order_history(5.1, 4.9), stable_gpu, stable_whole)
	widget.refresh_logot_widget(2.0)
	await ctx.wait_frames(1)
	order_paths = ((widget.get_debug_state().get("panels", []) as Array)[0] as Dictionary).get("top_paths", []) as Array
	ctx.check("ranking_ignores_leads_below_three_percent", order_paths == ["order/b", "order/a"], str(order_paths))
	Console.set_performance_source_test_histories(histories["render"], histories["gpu"], histories["whole"])

	Console._set_performance_source_cpu_mode("both")
	widget.refresh_logot_widget(0.0)
	await ctx.wait_frames(2)
	debug = widget.get_debug_state()
	ctx.check("allocation_update_speed_controls_widget_interval", is_equal_approx(float(debug.get("update_interval_sec", 0.0)), 0.1), str(debug))
	ctx.check("both_mode_has_two_panels", int(debug.get("panel_count", 0)) == 2, str(debug))

	var saved_path := Console.save_performance_source_snapshot("logot-test")
	ctx.check("snapshot_file_written", not saved_path.is_empty() and FileAccess.file_exists(saved_path), saved_path)
	if FileAccess.file_exists(saved_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(saved_path))
		ctx.check("snapshot_json_valid", parsed is Dictionary, str(parsed))
		if parsed is Dictionary:
			ctx.check("snapshot_includes_history", (parsed as Dictionary).has("history"), str(parsed))

	widget.queue_free()
	Console._set_performance_source_cpu_mode("render")
	Console._set_performance_graph_time_range(original_time_range)
	Console._set_performance_source_update_rate_hz(original_update_rate)
	Console._set_performance_pin_mode(original_performance_mode, true)
	Console.clear_performance_source_test_histories()


func _build_histories() -> Dictionary:
	var old_sources: Array[Dictionary] = [{"path": "source/departed", "name": "Departed", "duration_ms": 5.0}]
	for index in 11:
		old_sources.append({"path": "source/%02d" % index, "name": "Source %02d" % index, "duration_ms": 0.3 + index * 0.1})
	var current_sources: Array[Dictionary] = []
	var total := 0.0
	for index in 12:
		var duration := 2.4 - index * 0.12
		var path := "source/%02d" % index
		var name := "Source %02d" % index
		if index < 2:
			path = "source/group_%s/shared" % ("a" if index == 0 else "b")
			name = "Shared"
		current_sources.append({"path": path, "name": name, "duration_ms": duration})
		total += duration
	# The profiler bridge reports its own overflow bucket, which must merge into the widget's
	# "Other" remainder instead of claiming the largest legend row.
	current_sources.append({"path": "__other__", "name": "Other", "duration_ms": 3.0})
	total += 3.0
	var render := [
		{"frame_number": 100, "available": true, "total_ms": 16.0, "sources": old_sources},
		{"frame_number": 101, "available": false},
		{"frame_number": 102, "available": true, "total_ms": 0.0, "sources": [] as Array[Dictionary]},
		{"frame_number": 103, "available": true, "total_ms": total, "sources": current_sources},
	]
	var gpu := [
		{"frame_number": 100, "available": true, "total_ms": 12.0, "sources": old_sources},
		{"frame_number": 102, "available": true, "total_ms": total, "sources": current_sources},
	]
	var whole_sources := current_sources.duplicate(true)
	whole_sources.append({"path": "__engine_native_unattributed__", "name": "Engine / Native / Unattributed", "duration_ms": 8.0})
	var whole_total := total + 8.0
	var whole := [{"frame_number": 102, "available": true, "total_ms": whole_total, "sources": whole_sources}]
	return {"render": render, "gpu": gpu, "whole": whole}


func _make_scale_history(peak_ms: float, current_ms: float) -> Array:
	return [
		{
			"frame_number": 400,
			"available": true,
			"total_ms": peak_ms,
			"sources": [{"path": "scale/a", "name": "Scale A", "duration_ms": peak_ms}] as Array[Dictionary],
		},
		{
			"frame_number": 401,
			"available": true,
			"total_ms": current_ms,
			"sources": [{"path": "scale/a", "name": "Scale A", "duration_ms": current_ms}] as Array[Dictionary],
		},
	]


func _unique_values(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if not result.has(value):
			result.append(value)
	return result


func _make_order_history(a_duration: float, b_duration: float) -> Array:
	return [{
		"frame_number": 200,
		"available": true,
		"total_ms": a_duration + b_duration,
		"sources": [
			{"path": "order/a", "name": "A", "duration_ms": a_duration},
			{"path": "order/b", "name": "B", "duration_ms": b_duration},
		],
	}]


func _make_sparse_render_frame(frame_number: int, a_cpu_ms: float, b_cpu_ms: float) -> Dictionary:
	return {
		"kind": "render",
		"frame_number": frame_number,
		"render_cpu_total_ms": a_cpu_ms + b_cpu_ms,
		"gpu_total_ms": 0.0,
		"gpu_available": false,
		"render_sources": [
			{"path": "sparse/a", "name": "A", "cpu_ms": a_cpu_ms, "gpu_ms": 0.0},
			{"path": "sparse/b", "name": "B", "cpu_ms": b_cpu_ms, "gpu_ms": 0.0},
		],
	}


func _make_unavailable_gap_history() -> Array:
	return [
		{
			"frame_number": 400,
			"available": true,
			"total_ms": 8.0,
			"sources": [{"path": "gap/a", "name": "A", "duration_ms": 8.0}],
		},
		{
			"frame_number": 401,
			"available": false,
		},
		{
			"frame_number": 402,
			"available": true,
			"total_ms": 6.0,
			"sources": [{"path": "gap/a", "name": "A", "duration_ms": 6.0}],
		},
	]


func _make_long_history(count: int) -> Array:
	var history: Array[Dictionary] = []
	for index in count:
		history.append({
			"frame_number": 1000 + index,
			"available": true,
			"total_ms": 10.0,
			"sources": [
				{"path": "long/a", "name": "A", "duration_ms": 6.0},
				{"path": "long/b", "name": "B", "duration_ms": 4.0},
			],
		})
	return history
