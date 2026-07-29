@tool
extends "res://addons/logot/widgets/performance_widget_base.gd"

const PALETTE := [
	Color8(56, 189, 248),
	Color8(167, 139, 250),
	Color8(244, 114, 182),
	Color8(251, 146, 60),
	Color8(250, 204, 21),
	Color8(74, 222, 128),
	Color8(45, 212, 191),
	Color8(96, 165, 250),
	Color8(248, 113, 113),
	Color8(192, 132, 252),
]
const OTHER_COLOR := Color(0.48, 0.51, 0.57, 0.88)
# The profiler bridge folds everything past its retained-source cap into this bucket, which is
# the same thing this widget's own "Other" remainder represents.
const OTHER_PATH := "__other__"
const PINNED_WIDGET_WIDTH := 210.0
const PALETTE_WIDGET_WIDTH := 220.0
const PANEL_HEIGHT := 226.0
const GRAPH_HEIGHT := 70.0
const NOW_BAR_WIDTH := 10.5
const HISTORY_SLICE_MAX_WIDTH := NOW_BAR_WIDTH
const HISTORY_SLICE_MIN_WIDTH := 1.0
const GRAPH_SCALE_HEADROOM := 1.12
const GRAPH_MIN_SCALE_MS := 0.05
const LEGEND_TIME_PILL_WIDTH := 31.0
const LEGEND_TIME_PILL_HEIGHT := 9.0
const LEGEND_NAME_FONT_SIZE := 10
const ORDER_CHANGE_THRESHOLD_PERCENTAGE_POINTS := 3.0
const ORDER_CHANGE_HOLD_SECONDS := 1.0
const DEFAULT_UI_REFRESH_INTERVAL_SEC := 0.25

var _address := ""
var _widget_kind := "cpu"
var _panels: Array[SourceBreakdownPanel] = []
var _last_cpu_mode := ""
var _snapshot_refresh_elapsed := DEFAULT_UI_REFRESH_INTERVAL_SEC


class SourceBreakdownPanel:
	extends Control

	var title := ""
	var snapshot: Dictionary = {}
	var source_colors: Dictionary = {}
	var top_sources: Array[Dictionary] = []
	var debug_state: Dictionary = {}
	var ordered_paths: Array[String] = []
	var overtake_elapsed: Dictionary = {}
	var graph_scale_ms := GRAPH_MIN_SCALE_MS

	func _init(panel_title: String) -> void:
		title = panel_title
		custom_minimum_size = Vector2(PINNED_WIDGET_WIDTH, PANEL_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_snapshot(value: Dictionary, delta: float = 0.0) -> void:
		snapshot = value
		_update_top_sources(delta)
		queue_redraw()

	func _update_top_sources(delta: float) -> void:
		var current: Dictionary = snapshot.get("current", {}) as Dictionary
		var raw_sources: Variant = current.get("sources", [])
		var ranked_sources: Array[Dictionary] = []
		if raw_sources is Array:
			for source_variant in raw_sources:
				if not (source_variant is Dictionary):
					continue
				var raw_source := source_variant as Dictionary
				if str(raw_source.get("path", "")) == OTHER_PATH:
					continue
				if float(raw_source.get("duration_ms", 0.0)) > 0.0:
					ranked_sources.append(raw_source.duplicate(true))
		ranked_sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_duration := float(a.get("duration_ms", 0.0))
			var b_duration := float(b.get("duration_ms", 0.0))
			if is_equal_approx(a_duration, b_duration):
				return str(a.get("path", "")) < str(b.get("path", ""))
			return a_duration > b_duration
		)
		if ranked_sources.size() > 10:
			ranked_sources.resize(10)
		var current_by_path := {}
		var ranked_paths: Array[String] = []
		for source in ranked_sources:
			var path := str(source.get("path", ""))
			current_by_path[path] = source
			ranked_paths.append(path)
		for index in range(ordered_paths.size() - 1, -1, -1):
			if not ranked_paths.has(ordered_paths[index]):
				ordered_paths.remove_at(index)
		for path in ranked_paths:
			if not ordered_paths.has(path):
				ordered_paths.append(path)
		_apply_order_hysteresis(current_by_path, float(current.get("total_ms", 0.0)), delta)
		top_sources.clear()
		for path in ordered_paths:
			if current_by_path.has(path):
				top_sources.append((current_by_path[path] as Dictionary).duplicate(true))
		_assign_distinguishing_names()

		var next_colors := {}
		var used_colors: Array[int] = []
		for source in top_sources:
			var path := str(source.get("path", ""))
			if source_colors.has(path):
				var palette_index := int(source_colors[path])
				next_colors[path] = palette_index
				used_colors.append(palette_index)
		for source in top_sources:
			var path := str(source.get("path", ""))
			if next_colors.has(path):
				continue
			for palette_index in PALETTE.size():
				if not used_colors.has(palette_index):
					next_colors[path] = palette_index
					used_colors.append(palette_index)
					break
		source_colors = next_colors

	func _apply_order_hysteresis(current_by_path: Dictionary, total_ms: float, delta: float) -> void:
		var active_pairs := {}
		for index in range(1, ordered_paths.size()):
			var incumbent_path := ordered_paths[index - 1]
			var challenger_path := ordered_paths[index]
			if not current_by_path.has(incumbent_path) or not current_by_path.has(challenger_path):
				continue
			var incumbent_ms := float((current_by_path[incumbent_path] as Dictionary).get("duration_ms", 0.0))
			var challenger_ms := float((current_by_path[challenger_path] as Dictionary).get("duration_ms", 0.0))
			var lead_points := (challenger_ms - incumbent_ms) * 100.0 / total_ms if total_ms > 0.0 else 0.0
			var pair_key := "%s\n%s" % [challenger_path, incumbent_path]
			if lead_points > ORDER_CHANGE_THRESHOLD_PERCENTAGE_POINTS:
				active_pairs[pair_key] = true
				overtake_elapsed[pair_key] = float(overtake_elapsed.get(pair_key, 0.0)) + maxf(0.0, delta)
				if float(overtake_elapsed[pair_key]) >= ORDER_CHANGE_HOLD_SECONDS:
					ordered_paths[index - 1] = challenger_path
					ordered_paths[index] = incumbent_path
					overtake_elapsed.clear()
					return
			else:
				overtake_elapsed.erase(pair_key)
		for pair_key in overtake_elapsed.keys():
			if not active_pairs.has(pair_key):
				overtake_elapsed.erase(pair_key)

	func _assign_distinguishing_names() -> void:
		var name_counts := {}
		for source in top_sources:
			var base_name := str(source.get("name", source.get("path", ""))).strip_edges()
			name_counts[base_name] = int(name_counts.get(base_name, 0)) + 1
		for source in top_sources:
			var base_name := str(source.get("name", source.get("path", ""))).strip_edges()
			if int(name_counts.get(base_name, 0)) <= 1:
				source["display_name"] = base_name
				continue
			var path := str(source.get("path", ""))
			var segments := path.split("/", false)
			var chosen := path
			for parent_depth in range(1, maxi(2, segments.size())):
				var parent_start := maxi(0, segments.size() - 1 - parent_depth)
				var parent := "/".join(segments.slice(parent_start, maxi(0, segments.size() - 1)))
				var candidate := "%s / %s" % [parent, base_name] if not parent.is_empty() else base_name
				var distinct := true
				for other in top_sources:
					if other == source or str(other.get("name", other.get("path", ""))).strip_edges() != base_name:
						continue
					var other_segments := str(other.get("path", "")).split("/", false)
					var other_start := maxi(0, other_segments.size() - 1 - parent_depth)
					var other_parent := "/".join(other_segments.slice(other_start, maxi(0, other_segments.size() - 1)))
					var other_candidate := "%s / %s" % [other_parent, base_name] if not other_parent.is_empty() else base_name
					if other_candidate == candidate:
						distinct = false
						break
				if distinct:
					chosen = candidate
					break
			source["display_name"] = chosen

	func _draw() -> void:
		var panel_rect := Rect2(Vector2.ZERO, size)
		draw_rect(panel_rect, Color(0.015, 0.02, 0.03, 0.88), true)
		draw_rect(panel_rect, Color(0.55, 0.65, 0.82, 0.25), false, 1.0)
		var font := get_theme_default_font()
		var title_color := Color(0.9, 0.93, 0.98)
		var current: Dictionary = snapshot.get("current", {}) as Dictionary
		var total_ms := float(current.get("total_ms", 0.0))
		var title_text := "%s  %.2f ms" % [title, total_ms]
		draw_string(font, Vector2(8.0, 18.0), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, title_color)

		if not bool(snapshot.get("available", false)) or current.is_empty():
			var message := str(snapshot.get("message", "Waiting for profiler samples…"))
			var message_lines := message.split("\n", false)
			for line_index in message_lines.size():
				draw_string(font, Vector2(8.0, 48.0 + float(line_index) * 16.0), message_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 11, Color(0.72, 0.75, 0.82))
			debug_state = {"available": false, "message": message, "title": title}
			return
		var note := str(current.get("note", ""))
		if not note.is_empty():
			var note_lines := note.split("\n", false)
			for line_index in note_lines.size():
				draw_string(font, Vector2(8.0, 48.0 + float(line_index) * 16.0), note_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 10, Color(0.72, 0.75, 0.82))
			debug_state = {"available": true, "title": title, "total_ms": total_ms, "note": note, "timing_mode": str(current.get("timing_mode", "total_only"))}
			return

		var now_width := NOW_BAR_WIDTH
		var now_rect := Rect2(size.x - now_width - 8.0, 30.0, now_width, GRAPH_HEIGHT)
		var graph_rect := Rect2(8.0, 30.0, now_rect.position.x - 16.0, GRAPH_HEIGHT)
		var legend_rect := Rect2(8.0, graph_rect.end.y + 7.0, size.x - 16.0, size.y - graph_rect.end.y - 15.0)
		graph_scale_ms = _graph_scale_ms(graph_rect)
		_draw_history(graph_rect)
		_draw_now(now_rect, current)
		_draw_legend(font, legend_rect, total_ms)
		debug_state = {
			"available": true,
			"title": title,
			"top_paths": top_sources.map(func(source: Dictionary) -> String: return str(source.get("path", ""))),
			"display_names": top_sources.map(func(source: Dictionary) -> String: return str(source.get("display_name", source.get("name", "")))),
			"colors": source_colors.duplicate(),
			"total_ms": total_ms,
			"now_width": now_width,
			"now_label_visible": false,
			"legend_time_pill_width": LEGEND_TIME_PILL_WIDTH,
			"legend_percentage_visible": false,
			"legend_name_font_size": LEGEND_NAME_FONT_SIZE,
			"legend_name_width": maxf(0.0, legend_rect.size.x - LEGEND_TIME_PILL_WIDTH - 6.0),
			"stack_top_to_bottom_paths": _get_stack_top_to_bottom_paths(current),
			"time_precision_digits": 2,
			"note": note,
			"history_count": (snapshot.get("history", []) as Array).size(),
			"current_accounted_ms": _sum_current_sources(current),
			"gray_history_paths": _get_gray_history_paths(),
			"widget_width": size.x,
			"graph_above_legend": graph_rect.end.y <= legend_rect.position.y,
			"time_range_sec": float(snapshot.get("graph_time_range_sec", 0.0)),
			"visible_sample_count": int(snapshot.get("visible_sample_count", 0)),
			"overtake_elapsed": overtake_elapsed.duplicate(),
			"history_columns_gapless": _history_columns_are_gapless(graph_rect),
			"history_column_count": _drawable_history_count(graph_rect),
			"history_slice_width": float(_history_layout(graph_rect).get("slice_width", 0.0)),
			"history_blank_left_width": maxf(0.0, float(_history_layout(graph_rect).get("start_x", graph_rect.end.x)) - graph_rect.position.x),
			"history_renderer": "right_packed_fixed_width_slices",
			"graph_scale_ms": graph_scale_ms,
			"graph_scale_mode": "auto_peak_visible",
			"current_stack_height_fraction": clampf(total_ms / graph_scale_ms, 0.0, 1.0) if graph_scale_ms > 0.0 else 0.0,
		}

	func _draw_legend(font: Font, rect: Rect2, total_ms: float) -> void:
		var row_height := 11.0
		for index in top_sources.size():
			var source := top_sources[index]
			var path := str(source.get("path", ""))
			var color := _color_for_path(path)
			var y := rect.position.y + float(index) * row_height
			var duration_ms := float(source.get("duration_ms", 0.0))
			var pill_rect := Rect2(rect.position.x, y + 1.0, LEGEND_TIME_PILL_WIDTH, LEGEND_TIME_PILL_HEIGHT)
			_draw_time_pill(font, pill_rect, duration_ms, color)
			var name := str(source.get("display_name", source.get("name", path)))
			var name_x := pill_rect.end.x + 6.0
			draw_string(font, Vector2(name_x, y + 10.0), name, HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - name_x, LEGEND_NAME_FONT_SIZE, Color(0.9, 0.92, 0.96))
		var top_total := 0.0
		for source in top_sources:
			top_total += float(source.get("duration_ms", 0.0))
		var other_ms := maxf(0.0, total_ms - top_total)
		if other_ms > 0.0001:
			var y := rect.position.y + float(top_sources.size()) * row_height
			var pill_rect := Rect2(rect.position.x, y + 1.0, LEGEND_TIME_PILL_WIDTH, LEGEND_TIME_PILL_HEIGHT)
			_draw_time_pill(font, pill_rect, other_ms, OTHER_COLOR)
			var name_x := pill_rect.end.x + 6.0
			draw_string(font, Vector2(name_x, y + 10.0), "Other", HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - name_x, LEGEND_NAME_FONT_SIZE, Color(0.8, 0.82, 0.86))

	func _draw_time_pill(font: Font, rect: Rect2, duration_ms: float, color: Color) -> void:
		var radius := rect.size.y * 0.5
		var fill := color
		var border := color.lightened(0.22) if _color_luminance(color) < 0.45 else color.darkened(0.22)
		draw_rect(Rect2(rect.position.x + radius, rect.position.y, rect.size.x - rect.size.y, rect.size.y), fill, true)
		draw_circle(rect.position + Vector2(radius, radius), radius, fill)
		draw_circle(rect.position + Vector2(rect.size.x - radius, radius), radius, fill)
		draw_arc(rect.position + Vector2(radius, radius), radius, PI * 0.5, PI * 1.5, 12, border, 1.0)
		draw_arc(rect.position + Vector2(rect.size.x - radius, radius), radius, -PI * 0.5, PI * 0.5, 12, border, 1.0)
		draw_line(rect.position + Vector2(radius, 0.0), rect.position + Vector2(rect.size.x - radius, 0.0), border, 1.0)
		draw_line(rect.position + Vector2(radius, rect.size.y), rect.position + Vector2(rect.size.x - radius, rect.size.y), border, 1.0)
		var text_color := Color(0.04, 0.05, 0.07) if _color_luminance(fill) > 0.58 else Color(0.96, 0.97, 1.0)
		draw_string(font, rect.position + Vector2(0.0, 7.0), "%.2f" % duration_ms, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 7, text_color)

	func _color_luminance(color: Color) -> float:
		return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722

	func _draw_history(rect: Rect2) -> void:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.28), true)
		var layout := _history_layout(rect)
		var samples: Array[Dictionary] = layout.get("samples", [] as Array[Dictionary])
		var slice_width := float(layout.get("slice_width", 0.0))
		var start_x := float(layout.get("start_x", rect.position.x))
		for index in samples.size():
			# Share edges between neighbours so packed slices never leave a background seam.
			var left := start_x + slice_width * float(index)
			var right := start_x + slice_width * float(index + 1)
			_draw_source_stack(Rect2(left, rect.position.y, right - left, rect.size.y), samples[index])

	# Time slices keep a fixed width and pack against the "now" bar, so a partly filled
	# history leaves blank space on the left instead of stretching across the graph.
	func _history_layout(rect: Rect2) -> Dictionary:
		var samples := _drawable_history_samples()
		if rect.size.x <= 0.0 or samples.is_empty():
			return {"samples": [] as Array[Dictionary], "slice_width": 0.0, "start_x": rect.end.x}
		var max_slices := maxi(1, floori(rect.size.x / HISTORY_SLICE_MIN_WIDTH))
		if samples.size() > max_slices:
			samples = samples.slice(samples.size() - max_slices)
		var slice_width := minf(HISTORY_SLICE_MAX_WIDTH, rect.size.x / float(samples.size()))
		return {
			"samples": samples,
			"slice_width": slice_width,
			"start_x": rect.end.x - slice_width * float(samples.size()),
		}

	func _draw_now(rect: Rect2, current: Dictionary) -> void:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.36), true)
		_draw_source_stack(rect, current)
		draw_rect(rect, Color(0.75, 0.8, 0.9, 0.32), false, 1.0)

	func _draw_source_stack(rect: Rect2, sample: Dictionary) -> void:
		var total_ms := float(sample.get("total_ms", 0.0))
		var top_y := _total_to_y(total_ms, rect)
		var bottom := rect.end.y
		var stack_height := bottom - top_y
		if stack_height <= 0.0 or total_ms <= 0.0:
			return
		var source_values := _source_value_map(sample)
		var fractions: Array[float] = []
		var top_fraction_total := 0.0
		for source in top_sources:
			var path := str(source.get("path", ""))
			var fraction := clampf(float(source_values.get(path, 0.0)) / total_ms, 0.0, maxf(0.0, 1.0 - top_fraction_total))
			fractions.append(fraction)
			top_fraction_total += fraction
		var consumed_fraction := 0.0
		var other_fraction := maxf(0.0, 1.0 - top_fraction_total)
		if other_fraction > 0.0:
			var segment_height := stack_height * other_fraction
			var y := bottom - segment_height
			draw_rect(Rect2(rect.position.x, y, rect.size.x, segment_height + 0.5), OTHER_COLOR, true)
			consumed_fraction += other_fraction
		for index in range(top_sources.size() - 1, -1, -1):
			var fraction := fractions[index] if index < fractions.size() else 0.0
			if fraction <= 0.0:
				continue
			var segment_height := stack_height * fraction
			var y := bottom - stack_height * consumed_fraction - segment_height
			var path := str(top_sources[index].get("path", ""))
			draw_rect(Rect2(rect.position.x, y, rect.size.x, segment_height + 0.5), _color_for_path(path), true)
			consumed_fraction += fraction

	func _get_stack_top_to_bottom_paths(sample: Dictionary) -> Array[String]:
		var paths: Array[String] = []
		for source in top_sources:
			paths.append(str(source.get("path", "")))
		var top_total := 0.0
		for source in top_sources:
			top_total += float(source.get("duration_ms", 0.0))
		if maxf(0.0, float(sample.get("total_ms", 0.0)) - top_total) > 0.0001:
			paths.append(OTHER_PATH)
		return paths

	func _total_to_y(total_ms: float, rect: Rect2) -> float:
		var fraction := clampf(total_ms / graph_scale_ms, 0.0, 1.0) if graph_scale_ms > 0.0 else 0.0
		return rect.end.y - rect.size.y * fraction

	# A panel measures a slice of the frame (render CPU is ~1 ms of an ~8 ms frame), so a
	# fixed frame-time scale would peg every bar to the top. Scale to the tallest sample on
	# screen instead, which keeps the bar heights readable as relative CPU/GPU usage.
	func _graph_scale_ms(rect: Rect2) -> float:
		var peak_ms := float((snapshot.get("current", {}) as Dictionary).get("total_ms", 0.0))
		for sample in _history_layout(rect).get("samples", []) as Array:
			peak_ms = maxf(peak_ms, float((sample as Dictionary).get("total_ms", 0.0)))
		return maxf(GRAPH_MIN_SCALE_MS, peak_ms * GRAPH_SCALE_HEADROOM)

	func _source_value_map(sample: Dictionary) -> Dictionary:
		var values := {}
		var raw_sources: Variant = sample.get("sources", [])
		if raw_sources is Array:
			for source_variant in raw_sources:
				if source_variant is Dictionary:
					var source := source_variant as Dictionary
					values[str(source.get("path", ""))] = float(source.get("duration_ms", 0.0))
		return values

	func _sum_current_sources(current: Dictionary) -> float:
		var total := 0.0
		for source_variant in current.get("sources", []) as Array:
			if source_variant is Dictionary:
				total += float((source_variant as Dictionary).get("duration_ms", 0.0))
		return total

	func _get_gray_history_paths() -> Array[String]:
		var current_paths: Array[String] = []
		for source in top_sources:
			current_paths.append(str(source.get("path", "")))
		var gray_paths: Array[String] = []
		for sample_variant in snapshot.get("history", []) as Array:
			if not (sample_variant is Dictionary):
				continue
			for source_variant in (sample_variant as Dictionary).get("sources", []) as Array:
				if not (source_variant is Dictionary):
					continue
				var path := str((source_variant as Dictionary).get("path", ""))
				if not current_paths.has(path) and not gray_paths.has(path):
					gray_paths.append(path)
		return gray_paths

	func _drawable_history_count(rect: Rect2) -> int:
		return (_history_layout(rect).get("samples", []) as Array).size()

	func _history_columns_are_gapless(rect: Rect2) -> bool:
		var layout := _history_layout(rect)
		var samples: Array = layout.get("samples", []) as Array
		if samples.is_empty():
			return true
		# Slices are laid out on shared edges and empty samples are packed out, so the
		# only way a hole can appear is a zero-width slice.
		return float(layout.get("slice_width", 0.0)) > 0.0

	# Samples that would render nothing (unavailable, or captured with no measured time)
	# are dropped rather than reserving an empty column between neighbouring slices.
	func _drawable_history_samples() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for sample_variant in snapshot.get("history", []) as Array:
			if not (sample_variant is Dictionary):
				continue
			var sample := sample_variant as Dictionary
			if not bool(sample.get("available", false)):
				continue
			if float(sample.get("total_ms", 0.0)) <= 0.0:
				continue
			result.append(sample)
		return result

	func _color_for_path(path: String) -> Color:
		if source_colors.has(path):
			return PALETTE[int(source_colors[path]) % PALETTE.size()]
		return OTHER_COLOR

	func _truncate_name(value: String, max_characters: int) -> String:
		if value.length() <= max_characters:
			return value
		return value.left(maxi(1, max_characters - 1)) + "…"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_in_background = false
	add_theme_constant_override("separation", 4)
	_rebuild_panels()


func configure_logot_widget(address: String, mode: String, _corner: String) -> void:
	_address = address
	_widget_kind = "gpu" if address.ends_with("/gpu") else "cpu"
	custom_minimum_size = Vector2(PALETTE_WIDGET_WIDTH if mode == "palette" else PINNED_WIDGET_WIDTH, PANEL_HEIGHT)
	if is_inside_tree():
		_rebuild_panels()


func refresh_logot_widget(delta: float) -> void:
	var console := _get_logot_console()
	if console == null:
		return
	var cpu_mode := str(console.call("get_performance_source_cpu_mode")) if console.has_method("get_performance_source_cpu_mode") else "render"
	if _widget_kind == "cpu" and cpu_mode != _last_cpu_mode:
		_rebuild_panels()
	var force_refresh := bool(console.call("is_performance_source_test_mode")) if console.has_method("is_performance_source_test_mode") else false
	var refresh_interval := DEFAULT_UI_REFRESH_INTERVAL_SEC
	if console.has_method("get_performance_source_update_interval_sec"):
		refresh_interval = maxf(1.0 / 60.0, float(console.call("get_performance_source_update_interval_sec")))
	_snapshot_refresh_elapsed += maxf(0.0, delta)
	if not force_refresh and _snapshot_refresh_elapsed < refresh_interval and _panels_have_snapshots():
		return
	var snapshot_delta := delta if force_refresh else _snapshot_refresh_elapsed
	_snapshot_refresh_elapsed = 0.0 if force_refresh else fmod(_snapshot_refresh_elapsed, refresh_interval)
	if console.has_method("request_performance_source_collection"):
		console.call("request_performance_source_collection", _widget_kind, cpu_mode)
	for panel in _panels:
		var kind := str(panel.get_meta("source_kind", "gpu"))
		var snapshot: Dictionary = console.call("get_performance_source_widget_snapshot", kind) as Dictionary if console.has_method("get_performance_source_widget_snapshot") else {}
		panel.set_snapshot(snapshot, snapshot_delta)


func get_debug_state() -> Dictionary:
	var panel_states: Array = []
	for panel in _panels:
		panel_states.append(panel.debug_state.duplicate(true))
	var update_interval := DEFAULT_UI_REFRESH_INTERVAL_SEC
	var console := _get_logot_console()
	if console != null and console.has_method("get_performance_source_update_interval_sec"):
		update_interval = float(console.call("get_performance_source_update_interval_sec"))
	return {
		"kind": _widget_kind,
		"cpu_mode": _last_cpu_mode,
		"panel_count": _panels.size(),
		"panels": panel_states,
		"update_interval_sec": update_interval,
	}


func _rebuild_panels() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_panels.clear()
	_snapshot_refresh_elapsed = DEFAULT_UI_REFRESH_INTERVAL_SEC
	var console := _get_logot_console()
	_last_cpu_mode = str(console.call("get_performance_source_cpu_mode")) if console != null and console.has_method("get_performance_source_cpu_mode") else "render"
	if _widget_kind == "gpu":
		_add_panel("GPU Allocation", "gpu")
	elif _last_cpu_mode == "whole":
		_add_panel("Whole Frame CPU Allocation", "whole_cpu")
	elif _last_cpu_mode == "both":
		_add_panel("Render CPU Allocation", "render_cpu")
		_add_panel("Whole Frame CPU Allocation", "whole_cpu")
	else:
		_add_panel("Render CPU Allocation", "render_cpu")
	custom_minimum_size.y = PANEL_HEIGHT * float(maxi(1, _panels.size())) + 4.0 * float(maxi(0, _panels.size() - 1))


func _add_panel(title: String, source_kind: String) -> void:
	var panel := SourceBreakdownPanel.new(title)
	panel.set_meta("source_kind", source_kind)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(panel)
	_panels.append(panel)


func _panels_have_snapshots() -> bool:
	if _panels.is_empty():
		return false
	for panel in _panels:
		if panel.snapshot.is_empty():
			return false
	return true
