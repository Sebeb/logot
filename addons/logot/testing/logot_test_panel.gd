class_name LogotTestPanel
extends PanelContainer

const LogotTestRunResultScript = preload("res://Addons/logot/testing/resources/logot_test_run_result.gd")

var _manager = null
var _selected_test_id := ""
var _selected_run_id := ""

var _tests_list: ItemList
var _recent_list: ItemList
var _summary_label: RichTextLabel
var _checks_tree: Tree
var _visuals_list: ItemList
var _preview_texture: TextureRect
var _preview_path_label: Label
var _logs_text: RichTextLabel
var _run_button: Button
var _close_button: Button
var _refresh_button: Button


func _ready() -> void:
	_ensure_ui_built()
	hide()


func set_manager(manager) -> void:
	_ensure_ui_built()
	if _manager == manager:
		return
	if _manager != null:
		if _manager.tests_changed.is_connected(_refresh_lists):
			_manager.tests_changed.disconnect(_refresh_lists)
		if _manager.recent_results_changed.is_connected(_refresh_recent_results):
			_manager.recent_results_changed.disconnect(_refresh_recent_results)
		if _manager.test_run_completed.is_connected(_on_test_run_completed):
			_manager.test_run_completed.disconnect(_on_test_run_completed)
		if _manager.running_state_changed.is_connected(_on_running_state_changed):
			_manager.running_state_changed.disconnect(_on_running_state_changed)

	_manager = manager
	if _manager != null:
		_manager.tests_changed.connect(_refresh_lists)
		_manager.recent_results_changed.connect(_refresh_recent_results)
		_manager.test_run_completed.connect(_on_test_run_completed)
		_manager.running_state_changed.connect(_on_running_state_changed)
	_refresh_all()


func toggle_visible() -> void:
	_ensure_ui_built()
	visible = not visible
	if visible:
		_refresh_all()


func _ensure_ui_built() -> void:
	if _tests_list != null:
		return
	_build_ui()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 24
	offset_top = 24
	offset_right = -24
	offset_bottom = -24
	mouse_filter = Control.MOUSE_FILTER_STOP

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.06, 0.06, 0.07, 0.96)
	background.border_width_left = 1
	background.border_width_top = 1
	background.border_width_right = 1
	background.border_width_bottom = 1
	background.border_color = Color(0.24, 0.24, 0.28, 1.0)
	background.corner_radius_top_left = 6
	background.corner_radius_top_right = 6
	background.corner_radius_bottom_right = 6
	background.corner_radius_bottom_left = 6
	add_theme_stylebox_override("panel", background)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "Logot Tests"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.pressed.connect(_on_refresh_pressed)
	header.add_child(_refresh_button)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(func(): hide())
	header.add_child(_close_button)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 280
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)

	_run_button = Button.new()
	_run_button.text = "Run Selected Test"
	_run_button.disabled = true
	_run_button.pressed.connect(_on_run_selected_pressed)
	left.add_child(_run_button)

	var tests_label := Label.new()
	tests_label.text = "Tests"
	left.add_child(tests_label)

	_tests_list = ItemList.new()
	_tests_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tests_list.custom_minimum_size = Vector2(0, 180)
	_tests_list.item_selected.connect(_on_test_selected)
	_tests_list.item_activated.connect(_on_test_activated)
	left.add_child(_tests_list)

	var recent_label := Label.new()
	recent_label.text = "Recent Runs"
	left.add_child(recent_label)

	_recent_list = ItemList.new()
	_recent_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recent_list.item_selected.connect(_on_recent_selected)
	left.add_child(_recent_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = false
	_summary_label.scroll_active = true
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label.custom_minimum_size = Vector2(0, 120)
	right.add_child(_summary_label)

	var body_tabs := TabContainer.new()
	body_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body_tabs)

	_checks_tree = Tree.new()
	_checks_tree.columns = 3
	_checks_tree.column_titles_visible = true
	_checks_tree.set_column_title(0, "Check")
	_checks_tree.set_column_title(1, "Result")
	_checks_tree.set_column_title(2, "Details")
	body_tabs.add_child(_checks_tree)
	_checks_tree.name = "Checks"

	var visuals_box := HSplitContainer.new()
	body_tabs.add_child(visuals_box)
	visuals_box.name = "Visuals"

	_visuals_list = ItemList.new()
	_visuals_list.custom_minimum_size = Vector2(220, 0)
	_visuals_list.item_selected.connect(_on_visual_selected)
	visuals_box.add_child(_visuals_list)

	var preview_box := VBoxContainer.new()
	visuals_box.add_child(preview_box)

	_preview_path_label = Label.new()
	_preview_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_box.add_child(_preview_path_label)

	_preview_texture = TextureRect.new()
	_preview_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_box.add_child(_preview_texture)

	_logs_text = RichTextLabel.new()
	_logs_text.bbcode_enabled = false
	_logs_text.scroll_active = true
	_logs_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_tabs.add_child(_logs_text)
	_logs_text.name = "Logs"


func _refresh_all() -> void:
	_refresh_lists()
	_refresh_recent_results()
	_refresh_selected_detail()


func _refresh_lists() -> void:
	_tests_list.clear()
	_run_button.disabled = true
	if _manager == null:
		return
	for test_case in _manager.get_tests():
		var index := _tests_list.add_item("%s" % test_case.display_name)
		_tests_list.set_item_metadata(index, str(test_case.id))
		if str(test_case.id) == _selected_test_id:
			_tests_list.select(index)
			_run_button.disabled = false


func _refresh_recent_results() -> void:
	_recent_list.clear()
	if _manager == null:
		return
	var recent = _manager.get_recent_results(25)
	for result in recent:
		var label := "[%s] %s %s" % [
			result.completed_at,
			"PASS" if result.passed else "FAIL",
			result.display_name
		]
		var index := _recent_list.add_item(label)
		_recent_list.set_item_metadata(index, str(result.run_id))
		if str(result.run_id) == _selected_run_id:
			_recent_list.select(index)


func _refresh_selected_detail() -> void:
	if _manager == null:
		_summary_label.text = "No test manager connected."
		_checks_tree.clear()
		_visuals_list.clear()
		_logs_text.text = ""
		_preview_texture.texture = null
		_preview_path_label.text = ""
		return

	var result = null
	if not _selected_run_id.is_empty():
		result = _manager.get_result_by_run_id(_selected_run_id)
	elif not _selected_test_id.is_empty():
		result = _manager.get_latest_result_for_test(_selected_test_id)

	if result == null:
		_summary_label.text = "Select a test or recent run."
		_checks_tree.clear()
		_visuals_list.clear()
		_logs_text.text = ""
		_preview_texture.texture = null
		_preview_path_label.text = ""
		return

	_summary_label.text = _build_summary_text(result)
	_refresh_checks_tree(result)
	_refresh_visuals(result)
	_refresh_logs(result)


func _build_summary_text(result) -> String:
	return "[b]%s[/b]\nRun ID: %s\nStatus: [color=%s]%s[/color]\nScene: %s\nArtifact: %s\nSummary: %s" % [
		result.display_name,
		result.run_id,
		"light_green" if result.passed else "tomato",
		"PASS" if result.passed else "FAIL",
		result.scene_path,
		result.artifact_path,
		result.summary
	]


func _refresh_checks_tree(result) -> void:
	_checks_tree.clear()
	var root = _checks_tree.create_item()
	for check_result in result.code_checks:
		var item = _checks_tree.create_item(root)
		item.set_text(0, check_result.name)
		item.set_text(1, "PASS" if check_result.passed else "FAIL")
		item.set_text(2, check_result.details)


func _refresh_visuals(result) -> void:
	_visuals_list.clear()
	_preview_texture.texture = null
	_preview_path_label.text = ""
	for visual_result in result.visual_checks:
		var label := "%s - %s" % [
			visual_result.name,
			"PASS" if visual_result.passed else "FAIL"
		]
		var index := _visuals_list.add_item(label)
		_visuals_list.set_item_metadata(index, visual_result)
	if _visuals_list.item_count > 0:
		_visuals_list.select(0)
		_on_visual_selected(0)


func _refresh_logs(result) -> void:
	var lines: PackedStringArray = []
	for log_record in result.logs:
		lines.append("[%s] %s %s" % [log_record.timestamp, log_record.channel, log_record.message])
	_logs_text.text = "\n".join(lines)


func _on_test_selected(index: int) -> void:
	_selected_test_id = str(_tests_list.get_item_metadata(index))
	_selected_run_id = ""
	_run_button.disabled = false
	_refresh_selected_detail()


func _on_test_activated(index: int) -> void:
	_on_test_selected(index)
	_on_run_selected_pressed()


func _on_recent_selected(index: int) -> void:
	_selected_run_id = str(_recent_list.get_item_metadata(index))
	_refresh_selected_detail()


func _on_visual_selected(index: int) -> void:
	var visual_result = _visuals_list.get_item_metadata(index)
	if visual_result == null:
		return
	var image_path := str(visual_result.image_path).strip_edges()
	if image_path.is_empty():
		_preview_path_label.text = str(visual_result.details)
		_preview_texture.texture = null
		return

	_preview_path_label.text = image_path
	var absolute_path := ProjectSettings.globalize_path(image_path)
	if not FileAccess.file_exists(absolute_path):
		_preview_texture.texture = null
		return
	var image := Image.load_from_file(absolute_path)
	if image == null or image.is_empty():
		_preview_texture.texture = null
		return
	_preview_texture.texture = ImageTexture.create_from_image(image)


func _on_run_selected_pressed() -> void:
	if _manager == null or _selected_test_id.is_empty():
		return
	_manager.run_test(_selected_test_id)


func _on_refresh_pressed() -> void:
	if _manager != null:
		_manager.refresh()


func _on_test_run_completed(result) -> void:
	_selected_run_id = str(result.run_id)
	_refresh_recent_results()
	_refresh_selected_detail()


func _on_running_state_changed(is_running: bool) -> void:
	_run_button.disabled = is_running or _selected_test_id.is_empty()
