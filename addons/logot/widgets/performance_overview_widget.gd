@tool
extends "res://addons/logot/widgets/performance_widget_base.gd"

const DEFAULT_HISTORY_NUM_FRAMES := 500
const DEFAULT_GRAPH_MIN_FPS := 10.0
const DEFAULT_GRAPH_MAX_FPS := 160.0

var _fps_label: Label
var _frame_time_label: Label
var _frame_number_label: Label
var _stats_grid: GridContainer
var _graphs: Dictionary = {}


class PerformanceOverviewGraphPanel:
	extends Panel

	var history: Array = []
	var graph_min_fps := 10.0
	var graph_max_fps := 160.0
	var graph_color := Color8(128, 226, 95)
	var values_are_fps := true

	func _init() -> void:
		custom_minimum_size = Vector2(150.0, 25.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.25098)
		add_theme_stylebox_override("panel", panel_style)

	func _draw() -> void:
		if history.is_empty():
			return

		var graph_width := maxf(1.0, size.x)
		var graph_height := maxf(1.0, size.y)
		var polyline := PackedVector2Array()
		polyline.resize(history.size())
		for index in history.size():
			var raw_value := float(history[index])
			var fps_value := raw_value if values_are_fps else (1000.0 / raw_value if raw_value > 0.0 else 0.0)
			polyline[index] = Vector2(
				remap(index, 0, history.size(), 0.0, graph_width),
				remap(clampf(fps_value, graph_min_fps, graph_max_fps), graph_min_fps, graph_max_fps, graph_height, 0.0)
			)
		draw_polyline(polyline, graph_color, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 1)
	custom_minimum_size = Vector2(210.0, 170.0)

	_fps_label = _make_label("0 FPS", 18, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_fps_label)

	_frame_time_label = _make_label("0.00 mspf", 12, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_frame_time_label)

	_frame_number_label = _make_label("Frame: 0", 12, HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_frame_number_label)

	_build_stats_grid()
	_add_graph_row("fps", "FPS: ^", true)
	_add_graph_row("total", "Total: v", false)
	_add_graph_row("cpu", "CPU: v", false)
	_add_graph_row("gpu", "GPU: v", false)

	refresh_logot_widget(0.0)


func configure_logot_widget(_address: String, mode: String, _corner: String) -> void:
	custom_minimum_size = Vector2(220.0, 180.0) if mode == "palette" else Vector2(210.0, 170.0)


func refresh_logot_widget(_delta: float) -> void:
	if _fps_label == null:
		return

	var snapshot := _get_performance_snapshot()
	var fps := float(snapshot.get("fps", 0.0))
	var graph_color: Color = snapshot.get("color", Color8(128, 226, 95))
	var fps_display_color: Color = snapshot.get("fps_display_color", graph_color)
	var frame_time_color: Color = snapshot.get("frame_time_color", graph_color)
	var graph_min_fps := float(snapshot.get("graph_min_fps", DEFAULT_GRAPH_MIN_FPS))
	var graph_max_fps := float(snapshot.get("graph_max_fps", DEFAULT_GRAPH_MAX_FPS))
	var visible_sample_count := _get_visible_sample_count(snapshot)

	_fps_label.text = "%s FPS" % str(snapshot.get("fps_display_text", "%d" % floori(fps)))
	_fps_label.modulate = fps_display_color
	_frame_time_label.text = str(snapshot.get("frame_time_text", "0.00 mspf"))
	_frame_time_label.modulate = frame_time_color
	_frame_number_label.text = "Frame: %d" % int(snapshot.get("frame_number", 0))

	_update_stats_row("total", snapshot.get("total_stats", {}))
	_update_stats_row("cpu", snapshot.get("cpu_stats", {}))
	_update_stats_row("gpu", snapshot.get("gpu_stats", {}))

	_update_graph("fps", _limit_history(snapshot.get("fps_history", []), visible_sample_count), true, graph_color, graph_min_fps, graph_max_fps)
	_update_graph("total", _limit_history(snapshot.get("total_history", []), visible_sample_count), false, snapshot.get("total_color", graph_color), graph_min_fps, graph_max_fps)
	_update_graph("cpu", _limit_history(snapshot.get("cpu_history", []), visible_sample_count), false, snapshot.get("cpu_color", graph_color), graph_min_fps, graph_max_fps)
	_update_graph("gpu", _limit_history(snapshot.get("gpu_history", []), visible_sample_count), false, snapshot.get("gpu_color", graph_color), graph_min_fps, graph_max_fps)


func _build_stats_grid() -> void:
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 5
	_stats_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_grid.size_flags_horizontal = Control.SIZE_SHRINK_END
	_stats_grid.add_theme_constant_override("h_separation", 4)
	_stats_grid.add_theme_constant_override("v_separation", 0)
	add_child(_stats_grid)

	_add_stats_cell("")
	_add_stats_cell("Average")
	_add_stats_cell("Best")
	_add_stats_cell("Worst")
	_add_stats_cell("Last")
	_add_stats_row("total", "Total:")
	_add_stats_row("cpu", "CPU:")
	_add_stats_row("gpu", "GPU:")


func _add_stats_row(key: String, title: String) -> void:
	_add_stats_cell(title)
	for column in ["avg", "min", "max", "last"]:
		var label := _add_stats_cell("0.00")
		_stats_grid.set_meta("%s_%s" % [key, column], label)


func _add_stats_cell(text: String) -> Label:
	var label := _make_label(text, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	label.custom_minimum_size = Vector2(38.0, 0.0)
	_stats_grid.add_child(label)
	return label


func _update_stats_row(key: String, stats: Variant) -> void:
	var stats_dict := stats as Dictionary if stats is Dictionary else {}
	for column in ["avg", "min", "max", "last"]:
		var label = _stats_grid.get_meta("%s_%s" % [key, column], null)
		if label is Label:
			var value := float(stats_dict.get(column, 0.0))
			(label as Label).text = str(value).pad_decimals(2)
			(label as Label).modulate = _color_for_frametime(value)


func _add_graph_row(key: String, title_text: String, values_are_fps: bool) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)

	var title := _make_label(title_text, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	title.custom_minimum_size = Vector2(46.0, 25.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)

	var graph := PerformanceOverviewGraphPanel.new()
	graph.values_are_fps = values_are_fps
	graph.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(graph)
	_graphs[key] = graph


func _update_graph(key: String, history: Variant, values_are_fps: bool, color: Variant, min_fps: float, max_fps: float) -> void:
	var graph = _graphs.get(key, null)
	if not (graph is PerformanceOverviewGraphPanel):
		return
	var panel := graph as PerformanceOverviewGraphPanel
	panel.history = history as Array if history is Array else []
	panel.values_are_fps = values_are_fps
	panel.graph_color = color if color is Color else Color8(128, 226, 95)
	panel.graph_min_fps = min_fps
	panel.graph_max_fps = max_fps
	panel.queue_redraw()


func _make_label(text: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _get_visible_sample_count(snapshot: Dictionary) -> int:
	if snapshot.has("visible_sample_count"):
		return maxi(0, int(snapshot.get("visible_sample_count", 0)))
	var range_sec := float(snapshot.get("graph_time_range_sec", 0.0))
	if range_sec <= 0.0:
		return 0
	var fps := maxf(1.0, float(snapshot.get("fps", 60.0)))
	return maxi(2, roundi(range_sec * fps))


func _limit_history(history: Variant, sample_count: int) -> Array:
	var values: Array = history as Array if history is Array else []
	if sample_count <= 0 or values.size() <= sample_count:
		return values
	return values.slice(values.size() - sample_count, values.size())


func _color_for_frametime(frametime_msec: float) -> Color:
	var fps := 1000.0 / frametime_msec if frametime_msec > 0.0 else 0.0
	var normalized := remap(fps, DEFAULT_GRAPH_MIN_FPS, DEFAULT_GRAPH_MAX_FPS, 0.0, 1.0)
	if normalized < 0.3333:
		return Color8(239, 68, 68).lerp(Color8(250, 204, 21), normalized / 0.3333)
	if normalized < 0.6667:
		return Color8(250, 204, 21).lerp(Color8(128, 226, 95), (normalized - 0.3333) / 0.3334)
	return Color8(128, 226, 95).lerp(Color8(56, 189, 248), (normalized - 0.6667) / 0.3333)


func _get_performance_snapshot() -> Dictionary:
	var console := _get_logot_console()
	if console != null and console.has_method("get_performance_snapshot"):
		return console.call("get_performance_snapshot") as Dictionary
	return _empty_snapshot()


func _empty_snapshot() -> Dictionary:
	var history: Array[float] = []
	history.resize(DEFAULT_HISTORY_NUM_FRAMES)
	history.fill(DEFAULT_GRAPH_MIN_FPS)
	return {
		"fps": DEFAULT_GRAPH_MIN_FPS,
		"frame_number": 0,
		"fps_display_text": str(DEFAULT_GRAPH_MIN_FPS),
		"fps_display_color": Color8(128, 226, 95),
		"frame_time_text": "0.00 mspf",
		"frame_time_color": Color8(128, 226, 95),
		"fps_history": history,
		"total_history": history,
		"cpu_history": history,
		"gpu_history": history,
		"total_stats": {},
		"cpu_stats": {},
		"gpu_stats": {},
		"graph_min_fps": DEFAULT_GRAPH_MIN_FPS,
		"graph_max_fps": DEFAULT_GRAPH_MAX_FPS,
		"graph_time_range_sec": 0.0,
		"color": Color8(128, 226, 95),
		"information_text": "",
		"settings_text": "",
	}
