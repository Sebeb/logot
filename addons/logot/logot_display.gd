@tool
class_name LogotDisplay
extends Control

const LogLevel = preload("res://addons/logot/log_level.gd")

## Logot display functionality.
## Provides all filtering, display, sidebar, and settings logic.
## Used via composition by logot.gd and logot_editor_panel.gd.

# =============================================================================
# SIGNALS
# =============================================================================

signal custom_setting_changed(setting_name: String, value: bool)
signal command_palette_submit_requested(command_text: String)
signal command_palette_execute_keep_open_requested(command_text: String)
signal command_palette_close_requested
signal cleared()
signal level_visibility_changed(level: int, mode: int)
signal channel_visibility_changed(channel: String, mode: int)
signal channel_deleted(channel: String)
signal display_rebuilt()  # Emitted after display is rebuilt, for external stats updates

# =============================================================================
# SHARED CLASSES
# =============================================================================

class FilterStats:
	var shown_count: int = 0
	var hidden_count: int = 0

	func reset() -> void:
		shown_count = 0
		hidden_count = 0


class LogEntry:
	var id: int
	var level: int              # LogLevel constant
	var channel: String         # "" for no channel (displayed as "General")
	var instance_name: String   # Name of the instance this log came from (empty for local)
	var session_id: int         # Session ID of the instance this log came from (-1 for editor)
	var objects: Array          # Original objects passed to log()
	var formatted: String       # Pre-formatted BBCode string for first line
	var formatted_full: String  # Full formatted text (all lines)
	var stack_trace: String     # Optional stack trace (hidden by default)
	var extra_line_count: int   # Number of additional lines beyond the first
	var visible: bool           # Currently displayed in RichTextLabel
	var expanded: bool          # Whether this entry is expanded to show all content
	var timestamp: String       # Captured at creation time (HH:MM:SS format)
	var collapse_count: int     # Number of duplicate entries collapsed into this one

	func _init(p_id: int, p_level: int, p_channel: String, p_objects: Array, p_formatted: String, p_formatted_full: String = "", p_stack_trace: String = "", p_extra_lines: int = 0, p_timestamp: String = "", p_instance_name: String = "", p_session_id: int = -1):
		id = p_id
		level = p_level
		channel = p_channel
		instance_name = p_instance_name
		session_id = p_session_id
		objects = p_objects
		formatted = p_formatted
		formatted_full = p_formatted_full if p_formatted_full != "" else p_formatted
		stack_trace = p_stack_trace
		extra_line_count = p_extra_lines
		visible = false
		expanded = false
		timestamp = p_timestamp
		collapse_count = 1

	## Returns true if this entry has expandable content
	func has_expandable_content() -> bool:
		return extra_line_count > 0 or stack_trace != ""


class LogotCommand:
	var function: Callable
	var arguments: PackedStringArray
	var required: int
	var description: String
	var argument_options: Array
	var argument_options_provider: Callable
	var value_getter: Callable
	var group_name: String
	var group_priority: int
	var option_group_name: String
	var option_group_priority: int
	var group_tint: Color
	var option_group_tint: Color
	var display_label: String
	var icon: Texture2D
	var default_child_path: String
	var default_child_provider: Callable
	var keyboard_shortcut: Key
	var orderable_group: String
	var orderable_object_id: Variant
	var orderable_order: int = 0

	func _init(
		in_function: Callable,
		in_arguments: PackedStringArray,
		in_required: int = 0,
		in_description: String = "",
		in_argument_options: Array = [],
		in_argument_options_provider: Callable = Callable(),
		in_value_getter: Callable = Callable(),
		in_group_name: String = "",
		in_group_priority: int = 0,
		in_option_group_name: String = "",
		in_option_group_priority: int = 0,
		in_display_label: String = "",
		in_icon: Texture2D = null,
		in_group_tint: Color = Color.TRANSPARENT,
		in_option_group_tint: Color = Color.TRANSPARENT,
		in_default_child_path: String = "",
		in_default_child_provider: Callable = Callable(),
		in_keyboard_shortcut: Key = KEY_NONE,
		in_orderable_group: String = "",
		in_orderable_object_id: Variant = null
	):
		function = in_function
		arguments = in_arguments
		required = in_required
		description = in_description
		argument_options = in_argument_options
		argument_options_provider = in_argument_options_provider
		value_getter = in_value_getter
		group_name = in_group_name.strip_edges()
		group_priority = in_group_priority if not group_name.is_empty() else 0
		option_group_name = in_option_group_name.strip_edges()
		option_group_priority = in_option_group_priority if not option_group_name.is_empty() else 0
		group_tint = in_group_tint
		option_group_tint = in_option_group_tint
		display_label = in_display_label.strip_edges()
		icon = in_icon
		default_child_path = in_default_child_path.strip_edges()
		default_child_provider = in_default_child_provider
		keyboard_shortcut = in_keyboard_shortcut
		orderable_group = in_orderable_group.strip_edges().trim_suffix("/")
		orderable_object_id = in_orderable_object_id


class LogotDisplayVariable:
	var getter: Callable
	var inline_color_provider: Callable
	var items_provider: Callable
	var pinnable: bool
	var group_name: String
	var group_priority: int
	var change_signal_source: Object
	var change_signal_name: StringName
	var display_label_provider: Callable
	var wrap_value: bool

	func _init(
		in_getter: Callable,
		in_inline_color_provider: Callable = Callable(),
		in_items_provider: Callable = Callable(),
		in_pinnable: bool = true,
		in_group_name: String = "",
		in_group_priority: int = 0,
		in_change_signal_source: Object = null,
		in_change_signal_name: StringName = &"",
		in_display_label_provider: Callable = Callable(),
		in_options: Dictionary = {}
	):
		getter = in_getter
		inline_color_provider = in_inline_color_provider
		items_provider = in_items_provider
		pinnable = in_pinnable
		group_name = in_group_name.strip_edges()
		group_priority = in_group_priority if not group_name.is_empty() else 0
		change_signal_source = in_change_signal_source
		change_signal_name = in_change_signal_name
		display_label_provider = in_display_label_provider
		wrap_value = bool(in_options.get("wrap_value", false))


class LogotWidget:
	var scene_or_path: Variant
	var description: String
	var display_label: String
	var group_name: String
	var group_priority: int
	var default_minimum_size: Vector2

	func _init(
		in_scene_or_path: Variant,
		in_description: String = "",
		in_group_name: String = "",
		in_group_priority: int = 0,
		in_default_minimum_size: Vector2 = Vector2.ZERO,
		in_display_label: String = ""
	):
		scene_or_path = in_scene_or_path
		description = in_description
		display_label = in_display_label.strip_edges()
		group_name = in_group_name.strip_edges()
		group_priority = in_group_priority if not group_name.is_empty() else 0
		default_minimum_size = in_default_minimum_size


class RenderTextureWidget:
	extends PanelContainer

	var refresh_in_background := true
	var _texture_getter: Callable = Callable()
	var _texture_rect: TextureRect = null
	var _empty_label: Label = null
	var _resolution_label: Label = null
	var _last_texture: Texture2D = null
	var _last_resolution := Vector2i(-1, -1)
	var _preview_size_cap := Vector2.ZERO

	func setup(widget_data: Dictionary, minimum_size: Vector2) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_size_cap = minimum_size
		if minimum_size.x > 0.0 or minimum_size.y > 0.0:
			custom_minimum_size = minimum_size

		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.02, 0.025, 0.035, 0.72)
		panel_style.border_color = Color(0.55, 0.65, 0.82, 0.22)
		panel_style.set_border_width_all(1)
		panel_style.set_content_margin_all(2.0)
		add_theme_stylebox_override("panel", panel_style)

		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 0)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(content)

		var stack := Control.new()
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(stack)

		_texture_rect = TextureRect.new()
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(_texture_rect)

		_empty_label = Label.new()
		_empty_label.text = "No texture"
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_empty_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(_empty_label)

		_resolution_label = Label.new()
		_resolution_label.custom_minimum_size.y = 18.0
		_resolution_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_resolution_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_resolution_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resolution_label.add_theme_font_size_override("font_size", 11)
		_resolution_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9, 1.0))
		var resolution_style := StyleBoxFlat.new()
		resolution_style.bg_color = Color(0.07, 0.085, 0.115, 0.96)
		resolution_style.border_color = Color(0.55, 0.65, 0.82, 0.22)
		resolution_style.border_width_top = 1
		_resolution_label.add_theme_stylebox_override("normal", resolution_style)
		content.add_child(_resolution_label)

		var getter_variant: Variant = widget_data.get("texture_getter", Callable())
		if getter_variant is Callable:
			_texture_getter = getter_variant as Callable
		refresh_logot_widget(0.0)

	func refresh_logot_widget(_delta: float) -> void:
		var next_texture: Texture2D = null
		if _texture_getter.is_valid():
			var texture_variant: Variant = _texture_getter.call()
			if texture_variant is Texture2D:
				next_texture = texture_variant as Texture2D
		if next_texture != _last_texture and _texture_rect != null:
			_last_texture = next_texture
			_texture_rect.texture = next_texture
		var next_resolution := next_texture.get_size() if next_texture != null else Vector2.ZERO
		var rounded_resolution := Vector2i(roundi(next_resolution.x), roundi(next_resolution.y))
		if rounded_resolution != _last_resolution and _resolution_label != null:
			_last_resolution = rounded_resolution
			_resolution_label.text = "%d × %d" % [rounded_resolution.x, rounded_resolution.y]
		if _empty_label != null:
			_empty_label.visible = next_texture == null
		if _resolution_label != null:
			_resolution_label.visible = next_texture != null

	func get_logot_embedded_size(maximum_width: float) -> Vector2:
		var maximum_height := _preview_size_cap.y
		if maximum_height <= 0.0:
			maximum_height = get_combined_minimum_size().y
		if _last_resolution.x <= 0 or _last_resolution.y <= 0:
			return Vector2(minf(maximum_width, _preview_size_cap.x), maximum_height)

		var frame_padding := 4.0
		var footer_height := 18.0
		var available_image_width := maxf(0.0, maximum_width - frame_padding)
		var available_image_height := maxf(0.0, maximum_height - footer_height - frame_padding)
		var texture_aspect := float(_last_resolution.x) / float(_last_resolution.y)
		var image_height := minf(available_image_height, available_image_width / texture_aspect)
		var desired_size := Vector2(image_height * texture_aspect + frame_padding, image_height + footer_height + frame_padding)
		custom_minimum_size = desired_size
		return desired_size


class AutocompleteCommandColumn:
	extends Control

	signal row_activated(row_index: int)
	signal row_long_pressed(row_index: int)
	signal row_reordered(from_row_index: int, to_row_index: int)
	signal header_navigation_pressed
	signal visible_rows_changed

	const CELL_GAP := 12.0
	const CONTENT_PADDING_X := 12.0
	const HEADER_TOP_PADDING := 8.0
	const HEADER_BOTTOM_PADDING := 8.0
	const HEADER_CONTENT_GAP := 4.0
	const HEADER_NAV_BUTTON_SIZE := Vector2(72.0, 38.0)
	const HEADER_NAV_BUTTON_GAP := 8.0
	const WIDGET_TOP_GAP := 2.0
	const WIDGET_BOTTOM_GAP := 3.0
	const VALUE_PILL_PADDING_X := 10.0
	const VALUE_PILL_HEIGHT := 20.0
	const VALUE_PILL_GAP := 6.0
	const ACTION_ICON_DIAMETER := 18.0
	const ACTION_ICON_GAP := 6.0
	const CUSTOM_VALUE_PILL_MIN_CONTRAST := 4.5
	const GROUP_BOX_INSET_X := 6.0
	const GROUP_BOX_INSET_Y := 2.0
	const GROUP_BOX_NEST_INSET_X := 6.0
	const GROUP_HEADER_FONT_SIZE_REDUCTION := 3
	const TOUCH_SCROLL_DRAG_THRESHOLD := 8.0
	const TOUCH_LONG_PRESS_SECONDS := 0.48
	const TOUCH_TAP_HIGHLIGHT_SECONDS := 0.11
	const TOUCH_FLASH_INTERVAL_SECONDS := 0.08

	## Where an embedded widget sits relative to the column's scrolling region.
	## PINNED keeps it between the header and the rows, always on screen; INLINE makes it
	## the first item of the scrollable content, so it scrolls away ahead of the rows.
	enum WidgetPlacement {
		PINNED,
		INLINE,
	}

	var _rows: Array[Dictionary] = []
	var _row_height_prefix := PackedFloat64Array([0.0])
	var _sticky_group_header_indices := PackedInt32Array()
	var _metrics: Dictionary = {"name_width": 0, "value_width": 0, "action_width": 0, "width": 0}
	var _selected_index := -1
	var _scroll_row := 0
	var _row_height := 28
	var _is_preview := false
	var _selected_is_active := true
	var _header_title := ""
	var _header_description := ""
	var _header_height := 0.0
	var _header_label: RichTextLabel
	var _header_nav_button: Button
	var _row_scrollbar: VScrollBar
	var _embedded_widget: Control
	var _embedded_widget_path := ""
	var _embedded_widget_height := 0.0
	var _embedded_widget_placement := WidgetPlacement.PINNED
	## Only meaningful for an INLINE widget: true once the content has been scrolled past the
	## widget's slot, which leaves the first row at the top of the scrolling region.
	var _inline_widget_scrolled_out := false
	var _updating_scrollbar := false
	var _touch_mode := false
	var _press_active := false
	var _press_pointer_id := -1
	var _press_start_position := Vector2.ZERO
	var _press_last_position := Vector2.ZERO
	var _press_row_index := -1
	var _press_moved := false
	var _press_long_press_sent := false
	var _press_reordering := false
	var _press_reorder_target_row := -1
	var _press_token := 0
	var _drag_scroll_remainder := 0.0
	var _transient_highlight_row := -1
	var _transient_highlight_token := 0
	var _flash_row := -1
	var _flash_visible := false
	var _flash_token := 0

	var _font: Font
	var _font_size := 16
	var _header_title_font_size := 22
	var _header_description_font_size := 12
	var _font_color := Color(0.8, 0.8, 0.8, 1.0)
	var _selected_font_color := Color(1, 1, 1, 1.0)
	var _preview_font_color := Color(0.65, 0.65, 0.7, 1.0)
	var _inactive_selected_font_color := Color(0.88, 0.88, 0.9, 1.0)
	var _header_title_color := Color(0.92, 0.92, 0.95, 1.0)
	var _header_description_color := Color(0.62, 0.62, 0.68, 1.0)
	var _search_match_text_color := Color(0.36, 0.67, 1.0, 1.0)
	var _value_pill_color := Color(0.19, 0.2, 0.24, 0.95)
	var _value_pill_border_color := Color(0.38, 0.4, 0.48, 1.0)
	var _selected_value_pill_color := Color(0.24, 0.34, 0.48, 0.98)
	var _selected_value_pill_border_color := Color(0.55, 0.7, 0.9, 1.0)
	var _inactive_selected_value_pill_color := Color(0.22, 0.27, 0.34, 0.96)
	var _inactive_selected_value_pill_border_color := Color(0.44, 0.52, 0.64, 1.0)
	var _group_header_color := Color(0.72, 0.74, 0.8, 1.0)
	var _group_box_fill_color := Color(0.2, 0.23, 0.3, 0.2)
	var _group_box_border_color := Color(0.44, 0.5, 0.62, 0.55)
	var _action_circle_color := Color(0.18, 0.19, 0.22, 0.95)
	var _action_circle_border_color := Color(0.42, 0.44, 0.5, 1.0)
	var _selected_action_circle_color := Color(0.21, 0.32, 0.46, 0.98)
	var _selected_action_circle_border_color := Color(0.6, 0.75, 0.92, 1.0)
	var _inactive_selected_action_circle_color := Color(0.2, 0.24, 0.3, 0.95)
	var _inactive_selected_action_circle_border_color := Color(0.47, 0.56, 0.68, 1.0)
	var _selected_stylebox: StyleBox
	var _selected_focus_stylebox: StyleBox
	var _inactive_selected_stylebox := StyleBoxFlat.new()
	var _value_pill_style := StyleBoxFlat.new()
	var _selected_value_pill_style := StyleBoxFlat.new()
	var _inactive_selected_value_pill_style := StyleBoxFlat.new()
	var _custom_value_pill_style := StyleBoxFlat.new()

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		_header_label = RichTextLabel.new()
		_header_label.bbcode_enabled = true
		_header_label.fit_content = true
		_header_label.scroll_active = false
		_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header_label.focus_mode = Control.FOCUS_NONE
		add_child(_header_label)
		_header_nav_button = Button.new()
		_header_nav_button.visible = false
		_header_nav_button.focus_mode = Control.FOCUS_NONE
		_header_nav_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_header_nav_button.pressed.connect(func() -> void:
			header_navigation_pressed.emit()
		)
		add_child(_header_nav_button)
		_row_scrollbar = VScrollBar.new()
		_row_scrollbar.visible = false
		_row_scrollbar.custom_minimum_size = Vector2(10.0, 0.0)
		_row_scrollbar.step = 1.0
		_row_scrollbar.page = 1.0
		_row_scrollbar.mouse_filter = Control.MOUSE_FILTER_STOP
		_row_scrollbar.focus_mode = Control.FOCUS_NONE
		_row_scrollbar.value_changed.connect(_on_row_scrollbar_value_changed)
		add_child(_row_scrollbar)
		_configure_value_pill_styles()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if _handle_mouse_wheel(mouse_event):
				accept_event()
				return
			if mouse_event.button_index != MOUSE_BUTTON_LEFT:
				return
			if mouse_event.pressed:
				_begin_pointer_press(mouse_event.position, -1)
			else:
				_end_pointer_press(mouse_event.position, -1)
			accept_event()
			return
		if event is InputEventMouseMotion:
			if _press_active and _press_pointer_id == -1:
				_update_pointer_press((event as InputEventMouseMotion).position)
				accept_event()
			return
		if event is InputEventScreenTouch:
			var touch_event := event as InputEventScreenTouch
			if touch_event.pressed:
				_begin_pointer_press(touch_event.position, touch_event.index)
			else:
				_end_pointer_press(touch_event.position, touch_event.index)
			accept_event()
			return
		if event is InputEventScreenDrag:
			var drag_event := event as InputEventScreenDrag
			if _press_active and _press_pointer_id == drag_event.index:
				_update_pointer_press(drag_event.position)
				accept_event()

	func _handle_mouse_wheel(mouse_event: InputEventMouseButton) -> bool:
		if mouse_event.pressed:
			return false
		match mouse_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_rows(-3)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_rows(3)
				return true
		return false

	func _begin_pointer_press(position: Vector2, pointer_id: int) -> void:
		_press_active = true
		_press_pointer_id = pointer_id
		_press_start_position = position
		_press_last_position = position
		_press_moved = false
		_press_long_press_sent = false
		_drag_scroll_remainder = 0.0
		_press_row_index = _get_row_index_at_position(position)
		if _press_row_index >= 0 and _press_row_index < _rows.size() and not bool((_rows[_press_row_index] as Dictionary).get("is_group_header", false)):
			_press_reordering = bool((_rows[_press_row_index] as Dictionary).get("draggable", false)) and position.x >= size.x - 48.0
			_press_reorder_target_row = _press_row_index
			_set_transient_highlight(_press_row_index)
			_schedule_long_press(_press_row_index)
		else:
			_press_row_index = -1

	func _update_pointer_press(position: Vector2) -> void:
		if not _press_active:
			return
		var movement := position - _press_start_position
		if movement.length() >= TOUCH_SCROLL_DRAG_THRESHOLD:
			_press_moved = true
			_clear_transient_highlight()
		if _press_reordering and _press_moved:
			var candidate := _get_row_index_at_position(position)
			if candidate >= 0 and candidate < _rows.size() and bool((_rows[candidate] as Dictionary).get("draggable", false)):
				_press_reorder_target_row = candidate
			return
		if _press_moved:
			_scroll_by_pixel_delta(_press_last_position.y - position.y)
		_press_last_position = position

	func _end_pointer_press(position: Vector2, pointer_id: int) -> void:
		if not _press_active or _press_pointer_id != pointer_id:
			return
		var row_index := _get_row_index_at_position(position)
		var should_activate := (
			not _press_moved
			and not _press_long_press_sent
			and row_index == _press_row_index
			and row_index >= 0
			and row_index < _rows.size()
		)
		var should_reorder := _press_reordering and _press_moved and _press_reorder_target_row >= 0 and _press_reorder_target_row != _press_row_index
		var reorder_from := _press_row_index
		var reorder_to := _press_reorder_target_row
		_press_active = false
		_press_reordering = false
		_press_reorder_target_row = -1
		_press_pointer_id = -1
		_press_token += 1
		if should_activate:
			var row_data: Dictionary = _rows[row_index]
			if not bool(row_data.get("is_group_header", false)):
				row_activated.emit(row_index)
		elif should_reorder:
			row_reordered.emit(reorder_from, reorder_to)
		_schedule_transient_highlight_clear()

	func _schedule_long_press(row_index: int) -> void:
		if not _touch_mode:
			return
		_press_token += 1
		var token := _press_token
		var timer := get_tree().create_timer(TOUCH_LONG_PRESS_SECONDS)
		timer.timeout.connect(func() -> void:
			if token != _press_token or not _press_active or _press_moved or _press_long_press_sent:
				return
			if row_index != _press_row_index:
				return
			_press_long_press_sent = true
			row_long_pressed.emit(row_index)
			_start_double_flash(row_index)
		)

	func _set_transient_highlight(row_index: int) -> void:
		_transient_highlight_row = row_index
		_transient_highlight_token += 1
		queue_redraw()

	func _clear_transient_highlight() -> void:
		if _transient_highlight_row == -1:
			return
		_transient_highlight_row = -1
		_transient_highlight_token += 1
		queue_redraw()

	func _schedule_transient_highlight_clear() -> void:
		if _transient_highlight_row == -1:
			return
		_transient_highlight_token += 1
		var token := _transient_highlight_token
		var timer := get_tree().create_timer(TOUCH_TAP_HIGHLIGHT_SECONDS)
		timer.timeout.connect(func() -> void:
			if token != _transient_highlight_token:
				return
			_transient_highlight_row = -1
			queue_redraw()
		)

	func _start_double_flash(row_index: int) -> void:
		_flash_token += 1
		var token := _flash_token
		_flash_row = row_index
		_flash_visible = true
		queue_redraw()
		for step in range(4):
			var timer := get_tree().create_timer(TOUCH_FLASH_INTERVAL_SECONDS * float(step + 1))
			timer.timeout.connect(func() -> void:
				if token != _flash_token:
					return
				_flash_visible = not _flash_visible
				if step == 3:
					_flash_row = -1
					_flash_visible = false
				queue_redraw()
			)

	func _scroll_rows(delta_rows: int) -> void:
		if delta_rows == 0:
			return
		var current_slot := _get_scroll_slot()
		var next_slot := clampi(current_slot + delta_rows, 0, _get_max_scroll_slot())
		if next_slot == current_slot:
			return
		_set_scroll_slot(next_slot)
		_update_row_scrollbar()
		queue_redraw()
		visible_rows_changed.emit()

	## An inline widget occupies a leading slot in the scrolling region, so scroll positions are
	## addressed in slots rather than row indices: slot 0 shows the widget with the rows starting
	## underneath it, and every slot above that maps to a row index one step lower.
	func _has_inline_widget_slot() -> bool:
		return (
			_embedded_widget != null
			and is_instance_valid(_embedded_widget)
			and _embedded_widget_placement == WidgetPlacement.INLINE
		)

	func _get_scroll_slot() -> int:
		if not _has_inline_widget_slot():
			return _scroll_row
		if _scroll_row > 0 or _inline_widget_scrolled_out:
			return _scroll_row + 1
		return 0

	func _set_scroll_slot(slot: int) -> void:
		if not _has_inline_widget_slot():
			_inline_widget_scrolled_out = false
			_scroll_row = clampi(slot, 0, _get_max_scroll_row())
			return
		var clamped_slot := clampi(slot, 0, _get_max_scroll_slot())
		_inline_widget_scrolled_out = clamped_slot > 0
		_scroll_row = maxi(0, clamped_slot - 1)

	func _get_max_scroll_slot() -> int:
		if not _has_inline_widget_slot():
			return _get_max_scroll_row()
		# The reachable range has to be measured from the top of the content, where the widget is
		# on screen and squeezing rows out of view -- once it has scrolled away the rows have the
		# whole region to themselves and would report a shorter range, stranding the widget.
		var was_scrolled_out := _inline_widget_scrolled_out
		_inline_widget_scrolled_out = false
		var max_scroll_row_from_top := _get_max_scroll_row()
		_inline_widget_scrolled_out = was_scrolled_out
		if max_scroll_row_from_top == 0:
			# Every row already fits alongside the widget, so there is nothing to scroll.
			return 0
		return max_scroll_row_from_top + 1

	func _scroll_by_pixel_delta(delta_y: float) -> void:
		_drag_scroll_remainder += delta_y
		while _drag_scroll_remainder >= maxf(1.0, _get_row_height(clampi(_scroll_row, 0, maxi(0, _rows.size() - 1)))):
			var step := maxf(1.0, _get_row_height(clampi(_scroll_row, 0, maxi(0, _rows.size() - 1))))
			_scroll_rows(1)
			_drag_scroll_remainder -= step
		while _drag_scroll_remainder <= -maxf(1.0, _get_row_height(clampi(_scroll_row - 1, 0, maxi(0, _rows.size() - 1)))):
			var step := maxf(1.0, _get_row_height(clampi(_scroll_row - 1, 0, maxi(0, _rows.size() - 1))))
			_scroll_rows(-1)
			_drag_scroll_remainder += step

	func set_touch_mode(enabled: bool) -> void:
		_touch_mode = enabled
		if not _touch_mode:
			_clear_transient_highlight()
			_flash_row = -1
			_flash_visible = false
		queue_redraw()

	func set_embedded_widget(widget: Control, widget_path: String = "", placement: WidgetPlacement = WidgetPlacement.PINNED) -> void:
		if _embedded_widget != null and is_instance_valid(_embedded_widget) and _embedded_widget != widget:
			remove_child(_embedded_widget)
			_embedded_widget.queue_free()
		_embedded_widget = widget
		_embedded_widget_path = widget_path.strip_edges()
		_embedded_widget_placement = placement
		_inline_widget_scrolled_out = false
		if _embedded_widget != null:
			_embedded_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if _embedded_widget.get_parent() != self:
				add_child(_embedded_widget)
			move_child(_embedded_widget, mini(1, get_child_count() - 1))
		_update_embedded_widget_layout()
		_ensure_selection_visible()
		_update_row_scrollbar()
		queue_redraw()

	func get_embedded_widget_path() -> String:
		return _embedded_widget_path

	func set_embedded_widget_placement(placement: WidgetPlacement) -> void:
		if _embedded_widget_placement == placement:
			return
		_embedded_widget_placement = placement
		_inline_widget_scrolled_out = false
		_update_embedded_widget_layout()
		_ensure_selection_visible()
		_update_row_scrollbar()
		queue_redraw()

	func get_embedded_widget_placement() -> WidgetPlacement:
		return _embedded_widget_placement

	func configure_theme(theme_source: Control) -> void:
		if theme_source == null:
			return
		theme = theme_source.theme
		_font = theme_source.get_theme_font("font")
		_font_size = theme_source.get_theme_font_size("font_size")
		if _font_size <= 0:
			_font_size = 16
		_header_title_font_size = maxi(20, _font_size + 6)
		_header_description_font_size = maxi(11, _font_size - 2)
		_font_color = theme_source.get_theme_color("font_color")
		_selected_font_color = theme_source.get_theme_color("font_selected_color")
		_preview_font_color = _font_color.lerp(Color(0.5, 0.5, 0.55, 1.0), 0.35)
		_header_title_color = _font_color.lerp(_selected_font_color, 0.25)
		_header_description_color = _font_color.lerp(Color(0.55, 0.55, 0.62, 1.0), 0.35)
		_group_header_color = _font_color.lerp(_selected_font_color, 0.18)
		_group_box_fill_color = _font_color
		_group_box_fill_color.a = 0.08
		_group_box_border_color = _font_color.lerp(_selected_font_color, 0.2)
		_group_box_border_color.a = 0.32
		_selected_stylebox = theme_source.get_theme_stylebox("selected")
		_selected_focus_stylebox = theme_source.get_theme_stylebox("selected_focus")
		_configure_inactive_selection_styles()
		_configure_value_pill_styles()
		if _header_nav_button:
			_header_nav_button.theme = theme
		_update_header_layout()

	func set_header_navigation(enabled: bool, label: String) -> void:
		if _header_nav_button == null:
			return
		_header_nav_button.visible = enabled
		_header_nav_button.text = label
		_header_nav_button.tooltip_text = label
		_update_header_layout()

	func set_column_data(rows: Array[Dictionary], metrics: Dictionary, selected_index: int, is_preview: bool, row_height: int, selected_is_active: bool = true, header_title: String = "", header_description: String = "") -> void:
		_rows = rows
		_metrics = metrics
		_selected_index = selected_index
		_is_preview = is_preview
		_row_height = row_height
		_selected_is_active = selected_is_active
		_header_title = header_title
		_header_description = header_description
		_rebuild_row_geometry_cache()
		var scrollbar_was_visible := _row_scrollbar != null and _row_scrollbar.visible
		_update_header_layout()
		_ensure_selection_visible()
		_update_row_scrollbar()
		if _row_scrollbar != null and _row_scrollbar.visible != scrollbar_was_visible:
			_update_header_layout()
			_ensure_selection_visible()
			_update_row_scrollbar()
		queue_redraw()

	func get_row_count() -> int:
		return _rows.size()

	func get_rows() -> Array:
		return _rows

	func get_visible_row_range() -> Vector2i:
		if _rows.is_empty():
			return Vector2i.ZERO
		var start_index := clampi(_scroll_row, 0, _get_max_scroll_row())
		return Vector2i(start_index, _get_visible_content_end_index_for_scroll(start_index))

	func replace_rows_preserving_scroll(rows: Array[Dictionary]) -> void:
		var previous_slot := _get_scroll_slot()
		_rows = rows
		_rebuild_row_geometry_cache()
		_set_scroll_slot(previous_slot)
		_update_row_scrollbar()
		queue_redraw()

	func get_visible_display_variable_addresses() -> Array[String]:
		var addresses: Array[String] = []
		if _rows.is_empty():
			return addresses

		var start_index := clampi(_scroll_row, 0, _get_max_scroll_row())
		var end_index := _get_visible_content_end_index_for_scroll(start_index)
		for row_index in range(start_index, end_index):
			var address := str((_rows[row_index] as Dictionary).get("display_variable_address", "")).strip_edges()
			if address.is_empty() or addresses.has(address):
				continue
			addresses.append(address)
		return addresses

	func ensure_current_is_visible() -> void:
		_ensure_selection_visible()
		_update_row_scrollbar()
		queue_redraw()

	func _ensure_selection_visible() -> void:
		# Re-anchoring the rows always measures from the top of the content, so an inline widget
		# that had been scrolled away comes back with them.
		_inline_widget_scrolled_out = false
		if _rows.is_empty():
			_scroll_row = 0
			return

		var max_scroll := _get_max_scroll_row()
		if _is_preview:
			var highlighted_rows: Array[int] = []
			for row_index in range(_rows.size()):
				var row: Dictionary = _rows[row_index]
				if bool(row.get("highlighted", false)) or bool(row.get("default_focus", false)):
					highlighted_rows.append(row_index)
			if highlighted_rows.size() > 1:
				_scroll_row = clampi(highlighted_rows[0], 0, max_scroll)
				return
			_scroll_row = 0 if _embedded_widget != null else max_scroll
			return

		if _selected_index < 0:
			_scroll_row = 0
			return

		_scroll_row = _find_best_scroll_row_for_selection(_selected_index, max_scroll)

	func _get_visible_row_capacity() -> int:
		return _get_visible_row_capacity_for_scroll(_scroll_row)

	func _get_visible_row_capacity_for_scroll(scroll_row: int) -> int:
		if _rows.is_empty():
			return 0
		var clamped_scroll_row := clampi(scroll_row, 0, _rows.size() - 1)
		return maxi(1, _get_visible_content_end_index_for_scroll(clamped_scroll_row) - clamped_scroll_row)

	func _find_best_scroll_row_for_selection(selected_row: int, max_scroll: int) -> int:
		if selected_row < 0 or _rows.is_empty():
			return 0

		var current_scroll := clampi(_scroll_row, 0, max_scroll)
		var best_scroll := current_scroll
		var best_center_distance := INF
		var best_scroll_delta := INF
		for candidate in range(max_scroll + 1):
			if not _is_row_visible_for_scroll(candidate, selected_row):
				continue
			var visible_height := _get_visible_content_height_for_scroll(candidate)
			if visible_height <= 0.0:
				continue

			# Compare visual centres, rather than the row's top edge.  Apart from
			# looking more natural, this makes the first and last selectable rows
			# settle at the true scroll limits when they cannot be centred.
			var content_center := visible_height * 0.5
			var selected_center := _get_row_offset_from_scroll(candidate, selected_row) + _get_row_height(selected_row) * 0.5
			var center_distance := absf(selected_center - content_center)
			var scroll_delta := absi(candidate - current_scroll)
			if center_distance < best_center_distance:
				best_center_distance = center_distance
				best_scroll_delta = scroll_delta
				best_scroll = candidate
				continue
			if is_equal_approx(center_distance, best_center_distance) and scroll_delta < best_scroll_delta:
				best_scroll_delta = scroll_delta
				best_scroll = candidate

		return clampi(best_scroll, 0, max_scroll)

	func _has_sticky_group_header_for_scroll(scroll_row: int) -> bool:
		return not _get_sticky_group_header_row_data_for_scroll(scroll_row).is_empty()

	func _get_effective_content_visible_row_capacity(scroll_row: int) -> int:
		if _rows.is_empty():
			return 0
		var total_visible_rows := _get_visible_row_capacity_for_scroll(scroll_row)
		if _has_sticky_group_header_for_scroll(scroll_row):
			return maxi(1, total_visible_rows - 1)
		return total_visible_rows

	func _get_visible_content_row_count_for_scroll(scroll_row: int) -> int:
		if _rows.is_empty():
			return 0
		var clamped_scroll_row := clampi(scroll_row, 0, maxi(0, _rows.size() - 1))
		return _get_visible_content_end_index_for_scroll(clamped_scroll_row) - clamped_scroll_row

	func _is_row_visible_for_scroll(scroll_row: int, row_index: int) -> bool:
		if row_index < 0 or row_index >= _rows.size():
			return false
		var clamped_scroll_row := clampi(scroll_row, 0, maxi(0, _rows.size() - 1))
		if row_index < clamped_scroll_row:
			return false
		if row_index == clamped_scroll_row:
			return true
		var consumed_height := _row_height_prefix[row_index + 1] - _row_height_prefix[clamped_scroll_row]
		return consumed_height <= _get_visible_content_height_for_scroll(clamped_scroll_row)

	func _get_max_scroll_row() -> int:
		if _rows.is_empty():
			return 0
		var candidate := _rows.size() - 1
		while candidate > 0 and _get_visible_content_end_index_for_scroll(candidate - 1) >= _rows.size():
			candidate -= 1
		return candidate

	func _get_row_height(row_index: int) -> float:
		if row_index < 0 or row_index >= _rows.size():
			return float(_row_height)
		var row_data: Dictionary = _rows[row_index]
		var multiplier := 2.0 if bool(row_data.get("two_line", false)) else float(row_data.get("row_height_multiplier", 1.0))
		return maxf(float(_row_height), float(_row_height) * maxf(1.0, multiplier))

	func _rebuild_row_geometry_cache() -> void:
		_remeasure_wrapped_rows()
		_row_height_prefix.resize(_rows.size() + 1)
		_row_height_prefix[0] = 0.0
		_sticky_group_header_indices.resize(_rows.size())
		# One slot per open nesting level, holding that level's header row (-1 when the
		# level is headerless).  A row pins the innermost header enclosing it.
		var header_stack := PackedInt32Array()
		for row_index in range(_rows.size()):
			_row_height_prefix[row_index + 1] = _row_height_prefix[row_index] + _get_row_height(row_index)
			var row_data: Dictionary = _rows[row_index]
			var levels := get_group_levels(row_data)
			var depth := levels.size()
			var is_header := bool(row_data.get("is_group_header", false))
			while header_stack.size() > depth:
				header_stack.remove_at(header_stack.size() - 1)
			while header_stack.size() < depth:
				header_stack.append(-1)
			for level_index in range(depth):
				if bool((levels[level_index] as Dictionary).get("start", false)):
					header_stack[level_index] = -1
			var enclosing_depth := depth - 1 if is_header else depth
			if is_header and depth > 0:
				header_stack[depth - 1] = row_index
			var sticky_index := -1
			for level_index in range(enclosing_depth):
				if header_stack[level_index] >= 0:
					sticky_index = header_stack[level_index]
			_sticky_group_header_indices[row_index] = sticky_index

	func _remeasure_wrapped_rows() -> void:
		if _font == null:
			return
		for row_data in _rows:
			if not bool(row_data.get("wrap_value", false)):
				continue
			var group_indent := get_group_content_indent(row_data)
			var action_width := float(row_data.get("measured_action_width", 0.0))
			var available_width := maxf(1.0, size.x - CONTENT_PADDING_X * 2.0 - group_indent * 2.0 - action_width - (CELL_GAP if action_width > 0.0 else 0.0))
			var lines := _wrap_text_to_width(str(row_data.get("value_text", "")), available_width)
			row_data["wrapped_value_lines"] = lines
			row_data["row_height_multiplier"] = 1.0 + maxf(1.0, float(lines.size()))
			row_data["two_line"] = false

	func _get_visible_content_height_for_scroll(scroll_row: int) -> float:
		var rows_top := _get_rows_top_for_scroll(scroll_row)
		var height := maxf(0.0, size.y - rows_top)
		if _has_sticky_group_header_for_scroll(scroll_row):
			height = maxf(0.0, height - float(_row_height))
		return height

	func _get_visible_content_end_index_for_scroll(scroll_row: int) -> int:
		if _rows.is_empty():
			return 0
		var clamped_scroll_row := clampi(scroll_row, 0, maxi(0, _rows.size() - 1))
		var target_height := _row_height_prefix[clamped_scroll_row] + _get_visible_content_height_for_scroll(clamped_scroll_row)
		var low := clamped_scroll_row + 1
		var high := _rows.size()
		var end_index := low
		while low <= high:
			var midpoint := (low + high) >> 1
			if midpoint == clamped_scroll_row + 1 or _row_height_prefix[midpoint] <= target_height:
				end_index = midpoint
				low = midpoint + 1
			else:
				high = midpoint - 1
		return end_index

	func _get_row_offset_from_scroll(scroll_row: int, row_index: int) -> float:
		if _rows.is_empty():
			return 0.0
		var start_index := clampi(scroll_row, 0, _rows.size() - 1)
		var end_index := clampi(row_index, start_index, _rows.size())
		return _row_height_prefix[end_index] - _row_height_prefix[start_index]

	func _draw() -> void:
		var start_index := clampi(_scroll_row, 0, _get_max_scroll_row())
		var total_visible_rows := _get_visible_row_capacity_for_scroll(start_index)
		var sticky_group_header_row := _get_sticky_group_header_row_data_for_scroll(start_index)
		var sticky_group_header_visible := not sticky_group_header_row.is_empty()
		var end_index := _get_visible_content_end_index_for_scroll(start_index)
		var rows_top := _get_rows_top_for_scroll(start_index)
		var rows_area_height := maxf(0.0, size.y - rows_top)
		var content_width := _get_column_content_width()
		if sticky_group_header_visible:
			var sticky_height := float(_row_height)
			var sticky_row_rect := Rect2(0.0, rows_top, content_width, sticky_height)
			_draw_row_background(sticky_row_rect, sticky_group_header_row, 0)
			_draw_row_content(sticky_row_rect, sticky_group_header_row, 0, _get_baseline_offset(sticky_height))
			rows_top += sticky_height
			rows_area_height = maxf(0.0, rows_area_height - sticky_height)

		if _embedded_widget == null and not sticky_group_header_visible and _rows.size() <= total_visible_rows:
			var drawn_height := 0.0
			for row_index in range(start_index, end_index):
				drawn_height += _get_row_height(row_index)
			rows_top += maxf(0.0, rows_area_height - drawn_height)

		var row_top := rows_top
		for row_index in range(start_index, end_index):
			var row_height := _get_row_height(row_index)
			var row_rect := Rect2(0.0, row_top, content_width, row_height)
			var row_data: Dictionary = _rows[row_index]
			var selection_state := _get_row_selection_state(row_index)
			_draw_row_background(row_rect, row_data, selection_state)
			_draw_row_content(row_rect, row_data, selection_state, _get_baseline_offset(row_height))
			row_top += row_height

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_rebuild_row_geometry_cache()
			var scrollbar_was_visible := _row_scrollbar != null and _row_scrollbar.visible
			_update_header_layout()
			_update_embedded_widget_layout()
			_ensure_selection_visible()
			_update_row_scrollbar()
			if _row_scrollbar != null and _row_scrollbar.visible != scrollbar_was_visible:
				_update_header_layout()
				_update_embedded_widget_layout()
				_ensure_selection_visible()
				_update_row_scrollbar()
			queue_redraw()

	func _update_header_layout() -> void:
		if _header_label == null:
			return

		var header_title := _header_title.strip_edges()
		if header_title.is_empty():
			_header_height = 0.0
			_header_label.visible = false
			return

		var bbcode := "[b][font_size=%d][color=#%s]%s[/color][/font_size][/b]" % [
			_header_title_font_size,
			_header_title_color.to_html(false),
			_escape_bbcode(header_title.to_upper()),
		]
		var header_description := _header_description.strip_edges()
		if not header_description.is_empty():
			bbcode += "\n[i][font_size=%d][color=#%s]%s[/color][/font_size][/i]" % [
				_header_description_font_size,
				_header_description_color.to_html(false),
				_escape_bbcode(header_description),
			]

		_header_label.visible = true
		_header_label.theme = theme
		_header_label.clear()
		_header_label.append_text(bbcode)
		var nav_width := 0.0
		if _header_nav_button != null and _header_nav_button.visible:
			_header_nav_button.position = Vector2(CONTENT_PADDING_X, HEADER_TOP_PADDING)
			_header_nav_button.size = HEADER_NAV_BUTTON_SIZE
			nav_width = HEADER_NAV_BUTTON_SIZE.x + HEADER_NAV_BUTTON_GAP
		_header_label.position = Vector2(CONTENT_PADDING_X + nav_width, HEADER_TOP_PADDING)
		_header_label.size = Vector2(
			maxf(0.0, _get_column_content_width() - CONTENT_PADDING_X * 2.0 - nav_width),
			maxf(0.0, size.y - HEADER_TOP_PADDING)
		)

		var available_width := maxf(1.0, _header_label.size.x)
		var fallback_content_height := _estimate_header_content_height(header_title.to_upper(), header_description, available_width)
		var content_height := maxf(float(_header_label.get_content_height()), fallback_content_height)
		_header_height = HEADER_TOP_PADDING + content_height + HEADER_BOTTOM_PADDING + HEADER_CONTENT_GAP
		_update_embedded_widget_layout()

	func _get_row_index_at_position(position: Vector2) -> int:
		if _rows.is_empty():
			return -1
		var start_index := clampi(_scroll_row, 0, _get_max_scroll_row())
		var total_visible_rows := _get_visible_row_capacity_for_scroll(start_index)
		var sticky_group_header_row := _get_sticky_group_header_row_data_for_scroll(start_index)
		var sticky_group_header_visible := not sticky_group_header_row.is_empty()
		var end_index := _get_visible_content_end_index_for_scroll(start_index)
		var rows_top := _get_rows_top_for_scroll(start_index)
		var rows_area_height := maxf(0.0, size.y - rows_top)

		if sticky_group_header_visible:
			var sticky_height := float(_row_height)
			if position.y >= rows_top and position.y < rows_top + sticky_height:
				return -1
			rows_top += sticky_height
			rows_area_height = maxf(0.0, rows_area_height - sticky_height)

		if _embedded_widget == null and not sticky_group_header_visible and _rows.size() <= total_visible_rows:
			var drawn_height := 0.0
			for row_index in range(start_index, end_index):
				drawn_height += _get_row_height(row_index)
			rows_top += maxf(0.0, rows_area_height - drawn_height)

		if position.y < rows_top:
			return -1
		var row_top := rows_top
		for row_index in range(start_index, end_index):
			var row_height := _get_row_height(row_index)
			if position.y >= row_top and position.y < row_top + row_height:
				return row_index
			row_top += row_height
		return -1

	func _update_embedded_widget_layout() -> void:
		if _embedded_widget == null or not is_instance_valid(_embedded_widget):
			_embedded_widget_height = 0.0
			return
		var content_width := _get_column_content_width()
		var widget_width := maxf(0.0, content_width - CONTENT_PADDING_X * 2.0)
		var widget_size := Vector2(widget_width, _embedded_widget.get_combined_minimum_size().y)
		if _embedded_widget.has_method("get_logot_embedded_size"):
			widget_size = _embedded_widget.call("get_logot_embedded_size", widget_width) as Vector2
		_embedded_widget_height = ceil(maxf(0.0, widget_size.y))
		_embedded_widget.visible = _is_embedded_widget_visible_for_scroll(_scroll_row)
		var widget_left := CONTENT_PADDING_X + maxf(0.0, (widget_width - widget_size.x) * 0.5)
		_embedded_widget.position = Vector2(widget_left, _header_height + WIDGET_TOP_GAP)
		_embedded_widget.size = Vector2(widget_size.x, _embedded_widget_height)

	func _get_rows_top() -> float:
		return _get_rows_top_for_scroll(_scroll_row)

	func _is_embedded_widget_visible_for_scroll(scroll_row: int) -> bool:
		if _embedded_widget == null or not is_instance_valid(_embedded_widget):
			return false
		if _embedded_widget_placement == WidgetPlacement.PINNED:
			return true
		return clampi(scroll_row, 0, maxi(0, _rows.size())) == 0 and not _inline_widget_scrolled_out

	func _get_rows_top_for_scroll(scroll_row: int) -> float:
		if not _is_embedded_widget_visible_for_scroll(scroll_row):
			return _header_height
		return _header_height + WIDGET_TOP_GAP + _embedded_widget_height + WIDGET_BOTTOM_GAP

	## Top of the scrolling region itself: a pinned widget is carved out above it, while an inline
	## widget lives inside it and so scrolls (and is tracked by the scrollbar) along with the rows.
	func _get_scroll_region_top() -> float:
		if _embedded_widget == null or not is_instance_valid(_embedded_widget):
			return _header_height
		if _embedded_widget_placement == WidgetPlacement.INLINE:
			return _header_height
		return _header_height + WIDGET_TOP_GAP + _embedded_widget_height + WIDGET_BOTTOM_GAP

	## Width the row scrollbar takes away from the drawable area, or 0 while it is hidden.
	func get_row_scrollbar_reserve_width() -> float:
		return _get_row_scrollbar_width()

	func _get_column_content_width() -> float:
		return maxf(0.0, size.x - _get_row_scrollbar_width())

	func _get_row_scrollbar_width() -> float:
		if _row_scrollbar == null or not _row_scrollbar.visible:
			return 0.0
		var width := _row_scrollbar.size.x
		if width <= 0.0:
			width = _row_scrollbar.custom_minimum_size.x
		if width <= 0.0:
			width = 10.0
		return width

	func _update_row_scrollbar() -> void:
		if _row_scrollbar == null:
			return
		_update_embedded_widget_layout()

		var max_slot := _get_max_scroll_slot()
		var has_overflow := max_slot > 0
		_row_scrollbar.visible = has_overflow

		var previous_slot := _get_scroll_slot()
		_set_scroll_slot(0 if not has_overflow else previous_slot)
		if _get_scroll_slot() != previous_slot:
			# Clamping can pull an inline widget back on screen, so its visibility is restated.
			_update_embedded_widget_layout()

		if not has_overflow:
			_updating_scrollbar = true
			_row_scrollbar.value = 0.0
			_row_scrollbar.page = 1.0
			_row_scrollbar.max_value = 1.0
			_updating_scrollbar = false
			return

		var visible_rows := _get_visible_content_row_count_for_scroll(_scroll_row)

		var scrollbar_width := maxf(8.0, _row_scrollbar.custom_minimum_size.x)
		var region_top := _get_scroll_region_top()
		_row_scrollbar.position = Vector2(maxf(0.0, size.x - scrollbar_width), region_top)
		_row_scrollbar.size = Vector2(scrollbar_width, maxf(0.0, size.y - region_top))

		_updating_scrollbar = true
		_row_scrollbar.min_value = 0.0
		_row_scrollbar.max_value = float(max_slot + visible_rows)
		_row_scrollbar.page = float(maxi(1, visible_rows))
		_row_scrollbar.value = float(_get_scroll_slot())
		_updating_scrollbar = false

	func _on_row_scrollbar_value_changed(value: float) -> void:
		if _updating_scrollbar:
			return
		var current_slot := _get_scroll_slot()
		var next_slot := clampi(int(round(value)), 0, _get_max_scroll_slot())
		if next_slot == current_slot:
			return
		_set_scroll_slot(next_slot)
		_update_row_scrollbar()
		queue_redraw()
		visible_rows_changed.emit()

	func _escape_bbcode(text: String) -> String:
		return text.replace("[", "[lb]").replace("]", "[rb]")

	func _estimate_header_content_height(title_text: String, description_text: String, available_width: float) -> float:
		var title_lines := _estimate_wrapped_line_count(title_text, _header_title_font_size, available_width)
		var content_height := float(title_lines) * _get_line_height(_header_title_font_size)
		if not description_text.is_empty():
			var description_lines := _estimate_wrapped_line_count(description_text, _header_description_font_size, available_width)
			content_height += float(description_lines) * _get_line_height(_header_description_font_size)
		return content_height

	func _estimate_wrapped_line_count(text: String, font_size: int, available_width: float) -> int:
		var normalized_text := text.strip_edges()
		if normalized_text.is_empty():
			return 0
		if available_width <= 0.0:
			return 1

		var line_count := 0
		for paragraph in normalized_text.split("\n"):
			var paragraph_text := str(paragraph)
			if paragraph_text.is_empty():
				line_count += 1
				continue
			var paragraph_width := _measure_text_width(paragraph_text, font_size)
			line_count += maxi(1, int(ceil(paragraph_width / available_width)))
		return maxi(1, line_count)

	func _measure_text_width(text: String, font_size: int) -> float:
		if text.is_empty():
			return 0.0
		if _font != null:
			return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		return float(text.length() * maxi(1, font_size)) * 0.5

	func _get_line_height(font_size: int) -> float:
		if _font != null:
			return _font.get_height(font_size)
		return float(maxi(1, font_size))

	func _get_row_selection_state(row_index: int) -> int:
		if row_index >= 0 and row_index < _rows.size() and bool((_rows[row_index] as Dictionary).get("default_focus", false)):
			return 0
		if _touch_mode:
			if row_index == _flash_row and _flash_visible:
				return 2
			if row_index == _transient_highlight_row:
				return 2
			return 0
		if row_index != _selected_index:
			return 0
		if _is_preview:
			return 1
		if _selected_is_active:
			return 2
		return 1

	func _get_sticky_group_header_row_data_for_scroll(scroll_row: int) -> Dictionary:
		if _rows.is_empty():
			return {}
		var clamped_scroll_row := clampi(scroll_row, 0, _rows.size() - 1)
		if clamped_scroll_row >= _sticky_group_header_indices.size():
			return {}
		var header_index := _sticky_group_header_indices[clamped_scroll_row]
		return _rows[header_index] if header_index >= 0 else {}

	# Group borders are drawn last so a selected row cannot punch a hole through the box
	# outline: the box has to read as one continuous frame around its options.
	func _draw_row_background(row_rect: Rect2, row_data: Dictionary, selection_state: int) -> void:
		var levels := get_group_levels(row_data)
		var interior_rect := _get_group_interior_rect(row_rect, levels)
		if not levels.is_empty() and (bool(row_data.get("is_group_header", false)) or selection_state == 0):
			draw_rect(interior_rect, _get_group_fill_color(row_data), true)
		if selection_state != 0:
			var stylebox: StyleBox = _inactive_selected_stylebox if selection_state == 1 else (_selected_focus_stylebox if _selected_focus_stylebox != null else _selected_stylebox)
			if stylebox != null:
				stylebox.draw(get_canvas_item(), interior_rect)
		var row_tint = row_data.get("row_background_tint")
		if row_tint is Color:
			draw_rect(interior_rect, row_tint as Color, true)
		if bool(row_data.get("default_focus", false)):
			var outline_rect := interior_rect.grow(-2.0)
			if outline_rect.size.x > 0.0 and outline_rect.size.y > 0.0:
				draw_rect(outline_rect, _selected_font_color, false, 2.0)
		if not levels.is_empty():
			_draw_group_boxes(row_rect, levels)

	func _draw_row_content(row_rect: Rect2, row_data: Dictionary, selection_state: int, baseline_offset: float) -> void:
		if _font == null:
			return
		if bool(row_data.get("is_group_header", false)):
			_draw_group_header_label(row_rect, str(row_data.get("label", "")), row_data)
			return

		var value_width := float(row_data.get("measured_value_width", 0))
		var action_width := float(row_data.get("measured_action_width", 0))
		var text_color := _resolve_row_text_color(selection_state)
		if bool(row_data.get("disabled", false)):
			text_color.a *= 0.45
		var group_indent := get_group_content_indent(row_data)
		var text_baseline := row_rect.position.y + baseline_offset
		var content_left := row_rect.position.x + CONTENT_PADDING_X + group_indent
		var icon_texture := row_data.get("icon") as Texture2D
		var reserve_icon_space := bool(row_data.get("column_has_icons", false))
		if reserve_icon_space:
			var icon_size := minf(row_rect.size.y - 8.0, 20.0)
			if icon_texture != null:
				var icon_rect := Rect2(content_left, row_rect.position.y + (row_rect.size.y - icon_size) * 0.5, icon_size, icon_size)
				draw_rect(icon_rect.grow(2.0), Color(0.0, 0.0, 0.0, 0.35), true)
				draw_texture_rect(icon_texture, icon_rect, false, text_color)
			content_left += icon_size + CELL_GAP
		var content_right := row_rect.position.x + row_rect.size.x - CONTENT_PADDING_X - group_indent
		var info_cursor_x := content_right

		var action_rect := Rect2()
		if action_width > 0.0:
			action_rect = Rect2(info_cursor_x - action_width, row_rect.position.y, action_width, row_rect.size.y)
			info_cursor_x = action_rect.position.x - CELL_GAP

		var value_items_variant: Variant = row_data.get("value_items", [])
		var value_items: Array = value_items_variant if value_items_variant is Array else []
		if value_items.is_empty():
			var value_text := str(row_data.get("value_text", ""))
			if not value_text.is_empty():
				value_items = [{
					"text": value_text,
					"color": row_data.get("value_text_color", null),
				}]

		var raw_label_text := str(row_data.get("label", ""))
		var truncate_label_from_start := bool(row_data.get("truncate_label_from_start", false))
		var label_highlight_ranges_variant = row_data.get("label_highlight_ranges", [])
		if bool(row_data.get("wrap_value", false)):
			var label_height := float(_row_height)
			var line_baseline_offset := _get_baseline_offset(label_height)
			var label_text_wrapped := _fit_text_to_width(raw_label_text, maxf(0.0, info_cursor_x - content_left), truncate_label_from_start)
			if not label_text_wrapped.is_empty():
				draw_string(_font, Vector2(content_left, row_rect.position.y + line_baseline_offset), label_text_wrapped, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)
			var wrapped_lines: PackedStringArray = row_data.get("wrapped_value_lines", PackedStringArray())
			if wrapped_lines.is_empty():
				wrapped_lines = _wrap_text_to_width(str(row_data.get("value_text", "")), maxf(1.0, info_cursor_x - content_left))
			var value_color_variant = row_data.get("value_text_color", null)
			var value_color := value_color_variant as Color if value_color_variant is Color else text_color
			for line_index in range(wrapped_lines.size()):
				draw_string(_font, Vector2(content_left, row_rect.position.y + label_height * (line_index + 1) + line_baseline_offset), wrapped_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, value_color)
			if action_rect.size.x > 0.0:
				_draw_action_icons(action_rect, bool(row_data.get("has_children", false)), bool(row_data.get("can_submit", false)), bool(row_data.get("draggable", false)), selection_state, text_color)
			return
		if bool(row_data.get("two_line", false)):
			var half_height := row_rect.size.y * 0.5
			var line_baseline_offset := _get_baseline_offset(half_height)
			var label_max_width_two_line := maxf(0.0, info_cursor_x - content_left)
			var label_text_two_line := _fit_text_to_width(raw_label_text, label_max_width_two_line, truncate_label_from_start)
			if not label_text_two_line.is_empty():
				if label_highlight_ranges_variant is Array and not (label_highlight_ranges_variant as Array).is_empty():
					_draw_highlighted_label(
						content_left,
						row_rect.position.y + line_baseline_offset,
						raw_label_text,
						label_text_two_line,
						label_highlight_ranges_variant as Array,
						text_color,
						truncate_label_from_start
					)
				else:
					draw_string(_font, Vector2(content_left, row_rect.position.y + line_baseline_offset), label_text_two_line, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)
			if not value_items.is_empty():
				var two_line_value_rect := Rect2(
					content_left,
					row_rect.position.y + half_height + (half_height - VALUE_PILL_HEIGHT) * 0.5,
					maxf(0.0, info_cursor_x - content_left),
					VALUE_PILL_HEIGHT
				)
				_draw_value_pills(two_line_value_rect, value_items, row_rect.position.y + half_height + line_baseline_offset, selection_state, text_color)
			if action_rect.size.x > 0.0:
				_draw_action_icons(
					action_rect,
					bool(row_data.get("has_children", false)),
					bool(row_data.get("can_submit", false)),
					bool(row_data.get("draggable", false)),
					selection_state,
					text_color
				)
			return

		var value_rect := Rect2()
		if value_width > 0.0:
			value_rect = Rect2(
				info_cursor_x - value_width,
				row_rect.position.y + (row_rect.size.y - VALUE_PILL_HEIGHT) * 0.5,
				value_width,
				VALUE_PILL_HEIGHT
			)
			info_cursor_x = value_rect.position.x - CELL_GAP

		var label_max_width := maxf(0.0, info_cursor_x - content_left)
		var label_text := _fit_text_to_width(raw_label_text, label_max_width, truncate_label_from_start)
		if not label_text.is_empty():
			if label_highlight_ranges_variant is Array and not (label_highlight_ranges_variant as Array).is_empty():
				_draw_highlighted_label(
					content_left,
					text_baseline,
					raw_label_text,
					label_text,
					label_highlight_ranges_variant as Array,
					text_color,
					truncate_label_from_start
				)
			else:
				draw_string(_font, Vector2(content_left, text_baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)

		if not value_items.is_empty() and value_rect.size.x > 0.0:
			_draw_value_pills(value_rect, value_items, text_baseline, selection_state, text_color)

		if action_rect.size.x > 0.0:
			_draw_action_icons(
				action_rect,
				bool(row_data.get("has_children", false)),
				bool(row_data.get("can_submit", false)),
				bool(row_data.get("draggable", false)),
				selection_state,
				text_color
			)

	func _wrap_text_to_width(text: String, max_width: float) -> PackedStringArray:
		var lines := PackedStringArray()
		var normalized := text.replace("\r\n", "\n").replace("\r", "\n")
		for paragraph in normalized.split("\n", true):
			var current := ""
			for word_variant in paragraph.split(" ", false):
				var word := str(word_variant)
				var candidate := word if current.is_empty() else "%s %s" % [current, word]
				if current.is_empty() or _font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x <= max_width:
					current = candidate
					continue
				lines.append(current)
				current = ""
				for character in word:
					var split_candidate := current + character
					if not current.is_empty() and _font.get_string_size(split_candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x > max_width:
						lines.append(current)
						current = character
					else:
						current = split_candidate
			if not current.is_empty() or paragraph.is_empty():
				lines.append(current)
		if lines.is_empty():
			lines.append("")
		return lines

	func _get_group_tint(row_data: Dictionary) -> Color:
		var tint = row_data.get("group_tint", Color.TRANSPARENT)
		return tint as Color if tint is Color else Color.TRANSPARENT

	func _get_group_fill_color(row_data: Dictionary) -> Color:
		var tint := _get_group_tint(row_data)
		if tint.a <= 0.0:
			return _group_box_fill_color
		var fill := _group_box_fill_color.lerp(tint, 0.62)
		fill.a = maxf(_group_box_fill_color.a, minf(0.18, tint.a * 0.18))
		return fill

	func _get_group_border_color(row_data: Dictionary) -> Color:
		return _resolve_group_border_color(_get_group_tint(row_data))

	func _resolve_group_border_color(tint: Color) -> Color:
		if tint.a <= 0.0:
			return _group_box_border_color
		var border := _group_box_border_color.lerp(tint, 0.72)
		border.a = maxf(_group_box_border_color.a, minf(0.84, tint.a * 0.84))
		return border

	func _get_group_header_color(row_data: Dictionary) -> Color:
		var tint := _get_group_tint(row_data)
		if tint.a <= 0.0:
			return _group_header_color
		var header := _group_header_color.lerp(tint, 0.68)
		if header.get_luminance() < 0.38:
			header = header.lightened(0.42)
		header.a = 1.0
		return header

	func _draw_group_header_label(row_rect: Rect2, label_text: String, row_data: Dictionary) -> void:
		var header_text := label_text.strip_edges().to_upper()
		if header_text.is_empty():
			return
		var font_size: int = maxi(10, _font_size - GROUP_HEADER_FONT_SIZE_REDUCTION)
		var baseline: float = row_rect.position.y + floor((row_rect.size.y - float(_font.get_height(font_size))) * 0.5) + float(_font.get_ascent(font_size))
		var label_left := row_rect.position.x + CONTENT_PADDING_X + get_group_content_indent(row_data)
		draw_string(_font, Vector2(label_left, baseline), header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _get_group_header_color(row_data))

	# One entry per group box the row sits inside, outermost first.
	static func get_group_levels(row_data: Dictionary) -> Array:
		var levels_variant = row_data.get("group_levels", [])
		return levels_variant as Array if levels_variant is Array else []

	# Boxed rows are pushed in on both sides so their text clears the enclosing borders. This
	# matches the innermost box's inset, so a boxed row keeps the same padding inside its
	# border that a loose row gets from the column edge instead of crowding the outline.
	static func get_group_content_indent(row_data: Dictionary) -> float:
		var depth := get_group_levels(row_data).size()
		if depth <= 0:
			return 0.0
		return GROUP_BOX_INSET_X + float(depth - 1) * GROUP_BOX_NEST_INSET_X

	# A row only carries the box edges that start or end on it, so a level's side lines run
	# from row edge to row edge and meet the neighbouring row without a seam.
	func _get_group_level_rect(row_rect: Rect2, levels: Array, level_index: int) -> Rect2:
		var level_data: Dictionary = levels[level_index]
		var inset_x := GROUP_BOX_INSET_X + float(level_index) * GROUP_BOX_NEST_INSET_X
		var left := row_rect.position.x + inset_x
		var right := row_rect.position.x + row_rect.size.x - inset_x
		var top := row_rect.position.y + (GROUP_BOX_INSET_Y if bool(level_data.get("start", false)) else 0.0)
		var bottom := row_rect.position.y + row_rect.size.y - (GROUP_BOX_INSET_Y if bool(level_data.get("end", false)) else 0.0)
		return Rect2(left, top, maxf(0.0, right - left), maxf(0.0, bottom - top))

	# The area a row may paint into: inside the innermost box, so headers, fills and
	# selection stop at the border instead of spilling across it.
	func _get_group_interior_rect(row_rect: Rect2, levels: Array) -> Rect2:
		if levels.is_empty():
			return row_rect
		var box_rect := _get_group_level_rect(row_rect, levels, levels.size() - 1)
		return box_rect.grow_individual(-1.0, 0.0, -1.0, 0.0)

	func _draw_group_boxes(row_rect: Rect2, levels: Array) -> void:
		for level_index in range(levels.size()):
			var box_rect := _get_group_level_rect(row_rect, levels, level_index)
			if box_rect.size.x <= 0.0 or box_rect.size.y <= 0.0:
				continue
			var level_data: Dictionary = levels[level_index]
			var level_tint = level_data.get("tint", Color.TRANSPARENT)
			var border_color := _resolve_group_border_color(level_tint as Color if level_tint is Color else Color.TRANSPARENT)
			var left := box_rect.position.x
			var right := box_rect.position.x + box_rect.size.x
			var top := box_rect.position.y
			var bottom := box_rect.position.y + box_rect.size.y
			draw_line(Vector2(left, top), Vector2(left, bottom), border_color, 1.0)
			draw_line(Vector2(right, top), Vector2(right, bottom), border_color, 1.0)
			if bool(level_data.get("start", false)):
				draw_line(Vector2(left, top), Vector2(right, top), border_color, 1.0)
			if bool(level_data.get("end", false)):
				draw_line(Vector2(left, bottom), Vector2(right, bottom), border_color, 1.0)

	func _draw_action_icons(action_rect: Rect2, has_children: bool, can_submit: bool, draggable: bool, selection_state: int, icon_color: Color) -> void:
		if action_rect.size.x <= 0.0:
			return

		var icon_count := 0
		if has_children:
			icon_count += 1
		if can_submit:
			icon_count += 1
		if draggable:
			icon_count += 1
		if icon_count == 0:
			return

		var total_width := ACTION_ICON_DIAMETER * icon_count + ACTION_ICON_GAP * maxi(0, icon_count - 1)
		var current_x := action_rect.position.x + action_rect.size.x - total_width
		var center_y := action_rect.position.y + action_rect.size.y * 0.5

		if has_children:
			_draw_action_icon(Vector2(current_x + ACTION_ICON_DIAMETER * 0.5, center_y), true, false, selection_state, icon_color)
			current_x += ACTION_ICON_DIAMETER + ACTION_ICON_GAP
		if can_submit:
			_draw_action_icon(Vector2(current_x + ACTION_ICON_DIAMETER * 0.5, center_y), false, true, selection_state, icon_color)
			current_x += ACTION_ICON_DIAMETER + ACTION_ICON_GAP
		if draggable:
			_draw_action_symbol(Vector2(current_x + ACTION_ICON_DIAMETER * 0.5, center_y), "≡", icon_color)

	func _draw_action_icon(center: Vector2, draw_filled_arrow: bool, draw_return_symbol: bool, selection_state: int, icon_color: Color) -> void:
		# var radius := ACTION_ICON_DIAMETER * 0.5
		# draw_circle(center, radius, _resolve_action_circle_color(selection_state))
		# draw_arc(center, radius - 0.5, 0.0, TAU, 20, _resolve_action_circle_border_color(selection_state), 1.0, true)

		if draw_filled_arrow:
			_draw_action_symbol(center, "▶︎", icon_color)
		elif draw_return_symbol:
			_draw_action_symbol(center, "⏎", icon_color)

	func _draw_action_symbol(center: Vector2, symbol: String, icon_color: Color) -> void:
		if _font == null:
			return
		var symbol_font_size := clampi(_font_size, 11, 14)
		var symbol_size := _font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, symbol_font_size)
		var ascent := _font.get_ascent(symbol_font_size)
		var descent := _font.get_descent(symbol_font_size)
		var draw_position := Vector2(
			center.x - symbol_size.x * 0.5,
			center.y + (ascent - descent) * 0.5
		)
		draw_string(_font, draw_position, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, symbol_font_size, icon_color)

	func _draw_value_pills(value_rect: Rect2, value_items: Array, text_baseline: float, selection_state: int, default_text_color: Color) -> void:
		var pill_rects := _layout_value_pill_rects(value_rect, value_items)
		var item_count := mini(value_items.size(), pill_rects.size())
		for item_index in range(item_count):
			var item_variant: Variant = value_items[item_index]
			if not (item_variant is Dictionary):
				continue
			var item := item_variant as Dictionary
			var pill_rect := pill_rects[item_index]
			var fitted_value_text := _fit_text_to_width(str(item.get("text", "")), maxf(0.0, pill_rect.size.x - VALUE_PILL_PADDING_X * 2.0))
			var value_text_color := default_text_color
			var custom_value_text_color: Variant = item.get("color", null)
			var value_pill_style := _resolve_value_pill_style(selection_state)
			if custom_value_text_color is Color and (custom_value_text_color as Color).a > 0.0:
				value_text_color = custom_value_text_color as Color
				value_pill_style = _resolve_custom_value_pill_style(selection_state, custom_value_text_color)
			draw_style_box(value_pill_style, pill_rect)
			if not fitted_value_text.is_empty():
				draw_string(_font, Vector2(pill_rect.position.x + VALUE_PILL_PADDING_X, text_baseline), fitted_value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, value_text_color)

	func _layout_value_pill_rects(value_rect: Rect2, value_items: Array) -> Array[Rect2]:
		var pill_rects: Array[Rect2] = []
		if value_items.is_empty():
			return pill_rects
		var content_width := maxf(0.0, value_rect.size.x)
		if content_width <= 0.0:
			return pill_rects
		var cursor_x := value_rect.position.x + value_rect.size.x
		for item_index in range(value_items.size() - 1, -1, -1):
			var item_variant: Variant = value_items[item_index]
			if not (item_variant is Dictionary):
				continue
			var item := item_variant as Dictionary
			var remaining_width := maxf(0.0, cursor_x - value_rect.position.x)
			if remaining_width <= 0.0:
				break
			var pill_width := minf(_measure_value_pill_width(str(item.get("text", ""))), remaining_width)
			cursor_x -= pill_width
			pill_rects.push_front(Rect2(
				cursor_x,
				value_rect.position.y,
				pill_width,
				value_rect.size.y
			))
			if item_index > 0:
				cursor_x -= VALUE_PILL_GAP
		return pill_rects

	func _measure_value_pill_width(text: String) -> float:
		return _measure_text_width(text, _font_size) + VALUE_PILL_PADDING_X * 2.0

	func _draw_highlighted_label(
		start_x: float,
		baseline_y: float,
		full_text: String,
		display_text: String,
		highlight_ranges: Array,
		base_color: Color,
		truncate_from_start: bool = false
	) -> void:
		if _font == null or display_text.is_empty():
			return

		var draw_runs := _build_highlighted_label_runs(full_text, display_text, highlight_ranges, truncate_from_start)
		var cursor_x := start_x
		for run in draw_runs:
			var run_text := str(run.get("text", ""))
			if run_text.is_empty():
				continue

			var run_color := _search_match_text_color if bool(run.get("highlighted", false)) else base_color
			draw_string(_font, Vector2(cursor_x, baseline_y), run_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, run_color)
			cursor_x += _measure_text(run_text)

	func _build_highlighted_label_runs(full_text: String, display_text: String, highlight_ranges: Array, truncate_from_start: bool = false) -> Array[Dictionary]:
		var runs: Array[Dictionary] = []
		if display_text.is_empty():
			return runs

		var visible_char_count := display_text.length()
		var has_trailing_ellipsis := display_text.ends_with("...") and full_text.length() > display_text.length()
		var has_leading_ellipsis := truncate_from_start and display_text.begins_with("...") and full_text.length() > display_text.length()
		if has_trailing_ellipsis or has_leading_ellipsis:
			visible_char_count = maxi(0, visible_char_count - 3)

		var visible_start := 0
		if has_leading_ellipsis:
			visible_start = maxi(0, full_text.length() - visible_char_count)

		var visible_text := full_text.substr(visible_start, visible_char_count)
		if visible_text.is_empty():
			if has_trailing_ellipsis or has_leading_ellipsis:
				runs.append({"text": "...", "highlighted": false})
			return runs

		var highlight_flags := PackedByteArray()
		highlight_flags.resize(visible_text.length())
		for index in range(highlight_flags.size()):
			highlight_flags[index] = 0

		for range_data in highlight_ranges:
			if not (range_data is Dictionary):
				continue
			var range_dict := range_data as Dictionary
			var start_index := maxi(0, int(range_dict.get("start", -1)))
			var end_index := maxi(start_index, int(range_dict.get("end", start_index)))
			if end_index <= visible_start:
				continue
			start_index = maxi(start_index, visible_start) - visible_start
			end_index = mini(end_index, visible_start + visible_text.length()) - visible_start
			if start_index >= visible_text.length():
				continue
			for mark_index in range(start_index, end_index):
				highlight_flags[mark_index] = 1

		var run_start := 0
		var current_highlighted := highlight_flags[0] == 1
		for index in range(1, visible_text.length() + 1):
			var next_highlighted := false
			if index < visible_text.length():
				next_highlighted = highlight_flags[index] == 1
			if index == visible_text.length() or next_highlighted != current_highlighted:
				runs.append({
					"text": visible_text.substr(run_start, index - run_start),
					"highlighted": current_highlighted,
				})
				run_start = index
				current_highlighted = next_highlighted

		if has_leading_ellipsis:
			runs.push_front({"text": "...", "highlighted": false})
		elif has_trailing_ellipsis:
			runs.append({"text": "...", "highlighted": false})
		return runs

	func _get_baseline_offset(row_height: float = -1.0) -> float:
		var effective_row_height := row_height if row_height > 0.0 else float(_row_height)
		if _font == null:
			return effective_row_height * 0.7
		var font_height := _font.get_height(_font_size)
		return floor((effective_row_height - font_height) * 0.5) + _font.get_ascent(_font_size)

	func _measure_text(text: String) -> float:
		if _font == null:
			return text.length() * 8.0
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x

	func _fit_text_to_width(text: String, max_width: float, truncate_from_start: bool = false) -> String:
		if text.is_empty() or max_width <= 0.0:
			return ""
		if _measure_text(text) <= max_width:
			return text

		var ellipsis := "..."
		if _measure_text(ellipsis) > max_width:
			return ""

		var truncated := text
		if truncate_from_start:
			while not truncated.is_empty() and _measure_text(ellipsis + truncated) > max_width:
				truncated = truncated.substr(1)
			return ellipsis + truncated

		while not truncated.is_empty() and _measure_text(truncated + ellipsis) > max_width:
			truncated = truncated.left(truncated.length() - 1)

		return truncated + ellipsis

	func _configure_value_pill_styles() -> void:
		for stylebox in [_value_pill_style, _selected_value_pill_style, _inactive_selected_value_pill_style, _custom_value_pill_style]:
			stylebox.corner_radius_top_left = 8
			stylebox.corner_radius_top_right = 8
			stylebox.corner_radius_bottom_right = 8
			stylebox.corner_radius_bottom_left = 8
			stylebox.border_width_left = 1
			stylebox.border_width_top = 1
			stylebox.border_width_right = 1
			stylebox.border_width_bottom = 1

		_value_pill_style.bg_color = _value_pill_color
		_value_pill_style.border_color = _value_pill_border_color
		_selected_value_pill_style.bg_color = _selected_value_pill_color
		_selected_value_pill_style.border_color = _selected_value_pill_border_color
		_inactive_selected_value_pill_style.bg_color = _inactive_selected_value_pill_color
		_inactive_selected_value_pill_style.border_color = _inactive_selected_value_pill_border_color

	func _configure_inactive_selection_styles() -> void:
		_inactive_selected_font_color = _font_color.lerp(_selected_font_color, 0.45)
		_inactive_selected_value_pill_color = _value_pill_color.lerp(_selected_value_pill_color, 0.45)
		_inactive_selected_value_pill_border_color = _value_pill_border_color.lerp(_selected_value_pill_border_color, 0.45)
		_inactive_selected_action_circle_color = _action_circle_color.lerp(_selected_action_circle_color, 0.45)
		_inactive_selected_action_circle_border_color = _action_circle_border_color.lerp(_selected_action_circle_border_color, 0.45)

		var selected_bg := Color(0.2, 0.4, 0.6, 0.8)
		if _selected_focus_stylebox is StyleBoxFlat:
			selected_bg = (_selected_focus_stylebox as StyleBoxFlat).bg_color
		elif _selected_stylebox is StyleBoxFlat:
			selected_bg = (_selected_stylebox as StyleBoxFlat).bg_color

		var inactive_bg := _font_color.lerp(selected_bg, 0.3)
		inactive_bg.a = selected_bg.a * 0.55
		_inactive_selected_stylebox.bg_color = inactive_bg

		if _selected_focus_stylebox is StyleBoxFlat:
			var selected_flat := _selected_focus_stylebox as StyleBoxFlat
			_inactive_selected_stylebox.corner_radius_top_left = selected_flat.corner_radius_top_left
			_inactive_selected_stylebox.corner_radius_top_right = selected_flat.corner_radius_top_right
			_inactive_selected_stylebox.corner_radius_bottom_right = selected_flat.corner_radius_bottom_right
			_inactive_selected_stylebox.corner_radius_bottom_left = selected_flat.corner_radius_bottom_left
		elif _selected_stylebox is StyleBoxFlat:
			var selected_flat := _selected_stylebox as StyleBoxFlat
			_inactive_selected_stylebox.corner_radius_top_left = selected_flat.corner_radius_top_left
			_inactive_selected_stylebox.corner_radius_top_right = selected_flat.corner_radius_top_right
			_inactive_selected_stylebox.corner_radius_bottom_right = selected_flat.corner_radius_bottom_right
			_inactive_selected_stylebox.corner_radius_bottom_left = selected_flat.corner_radius_bottom_left
		else:
			_inactive_selected_stylebox.corner_radius_top_left = 2
			_inactive_selected_stylebox.corner_radius_top_right = 2
			_inactive_selected_stylebox.corner_radius_bottom_right = 2
			_inactive_selected_stylebox.corner_radius_bottom_left = 2

	func _resolve_row_text_color(selection_state: int) -> Color:
		if selection_state == 2:
			return _selected_font_color
		if selection_state == 1:
			return _inactive_selected_font_color
		return _preview_font_color if _is_preview else _font_color

	func _resolve_value_pill_style(selection_state: int) -> StyleBoxFlat:
		if selection_state == 2:
			return _selected_value_pill_style
		if selection_state == 1:
			return _inactive_selected_value_pill_style
		return _value_pill_style

	func _resolve_custom_value_pill_style(selection_state: int, custom_text_color: Variant) -> StyleBoxFlat:
		var base_style := _resolve_value_pill_style(selection_state)
		if not (custom_text_color is Color):
			return base_style
		var text_color := custom_text_color as Color
		var text_color_opaque := Color(text_color.r, text_color.g, text_color.b, 1.0)
		var background_color := _get_custom_value_pill_background_color(text_color_opaque)
		background_color.a = base_style.bg_color.a
		var border_color := background_color.lerp(text_color_opaque, 0.35).lerp(base_style.border_color, 0.25)
		border_color.a = base_style.border_color.a
		_custom_value_pill_style.bg_color = background_color
		_custom_value_pill_style.border_color = border_color
		return _custom_value_pill_style

	func _get_custom_value_pill_background_color(text_color: Color) -> Color:
		var dark_candidate := text_color.lerp(Color(0.0, 0.0, 0.0, 1.0), 0.68)
		var light_candidate := text_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.68)
		var dark_contrast := _get_color_contrast_ratio(text_color, dark_candidate)
		var light_contrast := _get_color_contrast_ratio(text_color, light_candidate)
		var use_dark := dark_contrast >= light_contrast
		var selected_candidate := dark_candidate if use_dark else light_candidate
		var selected_contrast := dark_contrast if use_dark else light_contrast
		if selected_contrast >= CUSTOM_VALUE_PILL_MIN_CONTRAST:
			return selected_candidate
		var contrast_target := Color(0.0, 0.0, 0.0, 1.0) if use_dark else Color(1.0, 1.0, 1.0, 1.0)
		for _step in range(6):
			selected_candidate = selected_candidate.lerp(contrast_target, 0.22)
			selected_contrast = _get_color_contrast_ratio(text_color, selected_candidate)
			if selected_contrast >= CUSTOM_VALUE_PILL_MIN_CONTRAST:
				break
		return selected_candidate

	func _get_color_contrast_ratio(color_a: Color, color_b: Color) -> float:
		var luminance_a := _get_relative_luminance(color_a)
		var luminance_b := _get_relative_luminance(color_b)
		var lighter := maxf(luminance_a, luminance_b)
		var darker := minf(luminance_a, luminance_b)
		return (lighter + 0.05) / (darker + 0.05)

	func _get_relative_luminance(color: Color) -> float:
		return (
			0.2126 * _get_linear_luminance_channel(color.r) +
			0.7152 * _get_linear_luminance_channel(color.g) +
			0.0722 * _get_linear_luminance_channel(color.b)
		)

	func _get_linear_luminance_channel(channel: float) -> float:
		if channel <= 0.03928:
			return channel / 12.92
		return pow((channel + 0.055) / 1.055, 2.4)

	func _resolve_action_circle_color(selection_state: int) -> Color:
		if selection_state == 2:
			return _selected_action_circle_color
		if selection_state == 1:
			return _inactive_selected_action_circle_color
		return _action_circle_color

	func _resolve_action_circle_border_color(selection_state: int) -> Color:
		if selection_state == 2:
			return _selected_action_circle_border_color
		if selection_state == 1:
			return _inactive_selected_action_circle_border_color
		return _action_circle_border_color


# =============================================================================
# CONSTANTS
# =============================================================================

enum VisibilityMode { SHOWN, HIDDEN, OFF }

const LEVEL_COLORS := {
	LogLevel.ERROR: Color8(204, 101, 102),
	LogLevel.WARN: Color8(240, 198, 116),
	LogLevel.COMMAND: Color8(133, 255, 98),
	LogLevel.MESSAGE: Color8(255, 255, 255),
	LogLevel.INFO: Color8(136, 215, 179),
	LogLevel.VERBOSE: Color8(210, 180, 162),
	LogLevel.DEBUG: Color8(128, 128, 128),
}
const ICON_VISIBLE := preload("res://addons/logot/assets/channel_visible.svg")
const ICON_HIDDEN := preload("res://addons/logot/assets/channel_hidden.svg")
const ICON_OFF := preload("res://addons/logot/assets/channel_off.svg")
const LOG_LEVELS := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
					 LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
const LEVEL_BUTTON_LABELS := {
	LogLevel.ERROR: "ERR",
	LogLevel.WARN: "WRN",
	LogLevel.COMMAND: "CMD",
	LogLevel.MESSAGE: "MSG",
	LogLevel.INFO: "INF",
	LogLevel.VERBOSE: "VRB",
	LogLevel.DEBUG: "DBG",
}
const AUTOCOMPLETE_ITEM_HEIGHT := 28
const AUTOCOMPLETE_MAX_VISIBLE_ITEMS := 10
const AUTOCOMPLETE_FIXED_VISIBLE_ITEMS := 15
const AUTOCOMPLETE_COLUMN_PADDING := 24
const AUTOCOMPLETE_ROW_ICON_WIDTH := 20
const AUTOCOMPLETE_VALUE_PILL_EXTRA_WIDTH := 20
const AUTOCOMPLETE_ACTION_ICON_DIAMETER := 18
const AUTOCOMPLETE_ACTION_ICON_GAP := 6
const AUTOCOMPLETE_CELL_GAP := 12
const AUTOCOMPLETE_POPUP_GAP := 4
const AUTOCOMPLETE_COLUMN_MAX_FALLBACK_WIDTH := 480
const AUTOCOMPLETE_COLUMN_MIN_WIDTH := 180
const AUTOCOMPLETE_COLUMN_HARD_MAX_WIDTH := 380
const AUTOCOMPLETE_VALUE_MAX_WIDTH := 180
const AUTOCOMPLETE_HEADER_WIDTH_BUFFER := 28
const AUTOCOMPLETE_TEXT_WIDTH_CACHE_LIMIT := 4096
const AUTOCOMPLETE_VALUE_MEASUREMENT_SAMPLE_COUNT := 8
const AUTOCOMPLETE_COMMAND_SLIDE_DURATION := 0.16
const AUTOCOMPLETE_COMMAND_SLIDE_DISTANCE := 28.0
const COMMAND_PALETTE_RESIZE_HANDLE_WIDTH := 56.0
const COMMAND_PALETTE_RESIZE_HANDLE_HEIGHT := 12.0
const COMMAND_PALETTE_RESIZE_HANDLE_GRIP_WIDTH := 28.0
const COMMAND_PALETTE_RESIZE_HANDLE_GRIP_HEIGHT := 4.0
const COMMAND_PALETTE_RESIZE_HANDLE_GAP := 3.0
const COMMAND_PALETTE_RESIZE_GRIP_COLOR := Color(0.65, 0.75, 0.92, 0.55)
const COMMAND_PALETTE_RESIZE_GRIP_HOVER_COLOR := Color(0.82, 0.89, 1.0, 0.95)

# Stacking order for the console's free-floating overlays. They all share one canvas
# layer, so these decide who occludes whom. The command palette sits above the pinned
# variables: pins are glanceable clutter, the palette is what you are actively driving.
# Logot's in-game popup overlay sits above all of these, at 210.
const OVERLAY_Z_PINNED_VARIABLES := 200
const OVERLAY_Z_COMMAND_PALETTE := 202
const OVERLAY_Z_COMMAND_PALETTE_RESIZE_HANDLE := 203
const OVERLAY_Z_RENDER_TEXTURE_FULLSCREEN := 205
const AUTOCOMPLETE_ROOT_COMMANDS_HINT := "press down for history"
const AUTOCOMPLETE_HISTORY_HINT := "press up for commands"
const AUTOCOMPLETE_ROOT_COMMANDS_LOCKED_HINT := "down wraps to top (Esc resets history access)"
const AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX := "__global_search__"
const AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND := "search"
const INPUT_ACTION_BUTTON_HEIGHT := 56.0
const INPUT_ICON_BUTTON_WIDTH := 56.0
const COLLAPSED_FILTER_BUTTON_HEIGHT := 56.0
const COLLAPSED_FILTER_BUTTON_MIN_WIDTH := 60.0
const COLLAPSED_FILTER_ICON_SIZE := 22.0
const COLLAPSED_FILTER_COUNT_FONT_SIZE := 16
const SCROLL_TO_BOTTOM_BUTTON_DIAMETER := 34.0
const SCROLL_TO_BOTTOM_BUTTON_MARGIN := 8.0
const SCROLL_TO_BOTTOM_SCROLLBAR_GAP := 4.0
const SCROLL_TO_BOTTOM_ANIMATION_DURATION := 0.16
const PINNED_OVERLAY_MARGIN := 8.0
const PINNED_OVERLAY_COLUMN_SEPARATION := 6
const PINNED_OVERLAY_MOUSE_SWAP_PADDING := 36.0
const PINNED_OVERLAY_MOUSE_RETURN_PADDING := 72.0
const PINNED_OVERLAY_LAYOUT_POLL_INTERVAL_SEC := 0.25
const PINNED_OVERLAY_CORNER_TOP_LEFT := "top_left"
const PINNED_OVERLAY_CORNER_TOP_RIGHT := "top_right"
const PINNED_OVERLAY_CORNER_BOTTOM_LEFT := "bottom_left"
const PINNED_OVERLAY_CORNER_BOTTOM_RIGHT := "bottom_right"
const PINNED_OVERLAY_CORNERS := [
	PINNED_OVERLAY_CORNER_TOP_LEFT,
	PINNED_OVERLAY_CORNER_TOP_RIGHT,
	PINNED_OVERLAY_CORNER_BOTTOM_LEFT,
	PINNED_OVERLAY_CORNER_BOTTOM_RIGHT,
]
## Addresses Logot no longer registers. Settings files written by older versions
## still list them, and a pin whose widget cannot be resolved renders a
## "Widget unavailable" row, so they are dropped while loading pin state.
const RETIRED_PIN_ADDRESSES := [
	"dev/performance/graphs",
]
const PINNED_OVERLAY_OPPOSITE_CORNER := {
	PINNED_OVERLAY_CORNER_TOP_LEFT: PINNED_OVERLAY_CORNER_TOP_RIGHT,
	PINNED_OVERLAY_CORNER_TOP_RIGHT: PINNED_OVERLAY_CORNER_TOP_LEFT,
	PINNED_OVERLAY_CORNER_BOTTOM_LEFT: PINNED_OVERLAY_CORNER_BOTTOM_RIGHT,
	PINNED_OVERLAY_CORNER_BOTTOM_RIGHT: PINNED_OVERLAY_CORNER_BOTTOM_LEFT,
}
const PINS_ALIAS_PREFIX := "pins/"
const COMMAND_GROUP_PATH_SEPARATOR := "/"
const HEADERLESS_COMMAND_GROUP_PREFIX := "."
const PINNED_COMMAND_GROUP_NAME := "pinned variables"
const PINNED_COMMAND_GROUP_PRIORITY := -100
const INVALID_INPUT_ROW_BG_COLOR := Color(0.5, 0.12, 0.12, 0.5)
const DEBUG_AUTOCOMPLETE_DEFAULT := false
const DEBUG_AUTOCOMPLETE_ENV := "LOGOT_DEBUG_AUTOCOMPLETE"
const DEBUG_AUTOCOMPLETE_SETTING := "debug/logot/autocomplete_trace"
const INPUT_METHOD_KEYBOARD := "keyboard"
const INPUT_METHOD_CONTROLLER := "controller"
const INPUT_METHOD_TOUCH := "touch"
const RENDER_SCALE_TARGET_LOG := "log"
const RENDER_SCALE_TARGET_COMMAND_PALETTE := "command_palette"
const RENDER_SCALE_TARGET_PINNED_VARIABLES := "pinned_variables"
const RENDER_SCALE_MIN_PERCENT := 50.0
const RENDER_SCALE_MAX_PERCENT := 300.0
const DEFAULT_RENDER_SCALE_KEYBOARD := 100.0
const DEFAULT_RENDER_SCALE_CONTROLLER_LOG := 120.0
const DEFAULT_RENDER_SCALE_CONTROLLER_COMMAND_PALETTE := 120.0
const DEFAULT_RENDER_SCALE_CONTROLLER_PINNED_VARIABLES := 100.0
const DEFAULT_RENDER_SCALE_TOUCH_LOG := 125.0
const DEFAULT_RENDER_SCALE_TOUCH_COMMAND_PALETTE := 135.0
const DEFAULT_RENDER_SCALE_TOUCH_PINNED_VARIABLES := 110.0
const PINNED_OVERLAY_MAX_VARIABLE_WIDTH := 500.0
const PINNED_OVERLAY_VARIABLE_WIDTH_PADDING := 18.0
const PINNED_OVERLAY_ROW_BG_COLOR := Color(0.102, 0.125, 0.165, 0.8)
const RENDER_TEXTURE_VIEW_MODE_NONE := "none"
const RENDER_TEXTURE_VIEW_MODE_FULLSCREEN := "fullscreen"
const RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY := "fullscreen_overlay"


# =============================================================================
# UI REFERENCES
# =============================================================================

var rich_label: RichTextLabel
var line_edit: LineEdit
var _sidebar  # LogotSidebar - type removed to avoid circular dependency
var _sidebar_toggle_btn: Button
var _clear_btn: Button
var _collapsed_level_buttons_container: VBoxContainer
var _collapsed_level_buttons_row: HBoxContainer
var _main_container: Control
var _logot_container: VBoxContainer
var _input_row: HBoxContainer
var _command_palette_log_spacer: Control
var _scroll_to_bottom_button: Button
var _rich_label_scrollbar: VScrollBar


# =============================================================================
# STATE
# =============================================================================

var _level_visibility: Dictionary = {}
var _channel_visibility: Dictionary = {}
var _known_channels: Array[String] = []
var _level_stats: Dictionary = {}
var _channel_stats: Dictionary = {}
var _search_filter: String = ""

var _collapse_duplicates := false
var _wrap_text := false
var _truncate_multiline := true
var _sidebar_visible := false
var _collapsed_level_buttons: Dictionary = {}  # {level: Dictionary}
var _touch_sidebar_fullscreen_enabled := false
var _base_sidebar_custom_minimum_size := Vector2.ZERO
var _base_main_split_offset := 0
var _base_main_dragger_visibility := -1

var _last_displayed_entry = null
var _last_displayed_count: int = 0
var _bbcode_before_last_entry: String = ""  # Stores BBCode content before the last displayed entry
var _entry_plain_text_cache: Dictionary = {}

# Composition support - providers set by owner
var _settings_file: String = ""
var _welcome_message: String = "Logot\n"
var _log_entries_provider: Callable
var _entry_text_provider: Callable
var _commands_provider: Callable  # Returns Dictionary of command_name -> command_data
var _command_path_disabled_provider: Callable  # Returns whether a command path is disabled
var _default_child_resolver: Callable  # Resolves recursive default-child command paths
var _orderable_reorder_handler: Callable
var _display_variables_provider: Callable  # Returns Dictionary of address -> display_variable
var _widgets_provider: Callable  # Returns Dictionary of address -> widget_data
var _rejected_level_count_provider: Callable  # Returns int for a given level
var _rejected_channel_count_provider: Callable  # Returns int for a given channel
var _level_visibility_getter: Callable  # Returns int (VisibilityMode) for a given level
var _level_visibility_setter: Callable  # Sets visibility mode for a given level
var _channel_visibility_getter: Callable  # Returns int (VisibilityMode) for a given channel
var _channel_visibility_setter: Callable  # Sets visibility mode for a given channel
var _instance_visibility_getter: Callable  # Returns int (VisibilityMode) for a given session_id
var _custom_settings: Array = []
var _custom_setting_values: Dictionary = {}

# Autocomplete state
var _history_autocomplete_popup: ItemList
var _command_autocomplete_popup: PanelContainer
var _command_autocomplete_scroll: ScrollContainer
var _command_autocomplete_columns_container: HBoxContainer
var _command_autocomplete_animation_tween: Tween
var _command_autocomplete_target_global_position := Vector2.ZERO
var _command_autocomplete_target_size := Vector2.ZERO
var _command_autocomplete_slide_offset := 0.0
var _command_autocomplete_touch_slide_offset_x := 0.0
var _command_autocomplete_alpha := 1.0
var _command_palette_resize_handle: Control
var _command_palette_resize_grip: Panel
var _command_palette_height_override := 0.0
var _command_palette_resize_dragging := false
var _command_palette_resize_drag_start_y := 0.0
var _command_palette_resize_drag_start_height := 0.0
var _autocomplete_selected_index := -1
var _autocomplete_column_states: Array[Dictionary] = []
var _autocomplete_column_nodes: Array[Control] = []
var _autocomplete_active_column_index := -1
var _autocomplete_highlighted_tiers: Dictionary = {}
var _autocomplete_pre_filter_highlighted_tiers: Dictionary = {}
var _autocomplete_shortcut_winners: Dictionary = {}
var _pending_autocomplete_column_sync_start := -1
var _autocomplete_column_sync_queued := false
var _pending_autocomplete_column_sync_scroll_to_end := false
var _pending_touch_column_slide_direction := 0
var _autocomplete_global_search_mode := false
var _suggestions := []
var _current_suggest := 0
var _suggesting := false
var _command_entry_mode := false
var _suppress_autocomplete_text_changes := false
var _pending_autocomplete_text := ""
var _autocomplete_text_update_queued := false
var _debug_autocomplete_update_count := 0

# Command history
var _command_history: Array[String] = []
var _max_history_size := 50
var _history_can_switch_to_commands := false
var _history_access_locked_until_reset := false
var _root_command_selection_reset_pending := false

# Display variables
var _pinned_display_variables: Array[String] = []
var _transient_pinned_display_variables: Dictionary = {}
var _pinned_overlay_root: Control
var _pinned_overlay_corner_containers: Dictionary = {}
var _pinned_overlay_rows: Dictionary = {}
var _pinned_row_render_cache: Dictionary = {}
var _pinned_row_render_snapshots: Dictionary = {}
var _pinned_row_poll_signatures: Dictionary = {}
var _pinned_display_variable_corners: Dictionary = {}
var _pinned_corner_enabled := {
	PINNED_OVERLAY_CORNER_TOP_LEFT: true,
	PINNED_OVERLAY_CORNER_TOP_RIGHT: true,
	PINNED_OVERLAY_CORNER_BOTTOM_LEFT: true,
	PINNED_OVERLAY_CORNER_BOTTOM_RIGHT: true,
}
var _pinned_overlay_visible := true
var _pinned_overlay_suppressed := false
var _pinned_corner_redirects: Dictionary = {}
var _pinned_overlay_layout_poll_signature := ""
var _pinned_overlay_layout_poll_accum_sec := 0.0
var _saved_pin_overlays: Dictionary = {}  # {overlay_name: Array[String]}
var _render_texture_fullscreen_root: Control
var _render_texture_fullscreen_backdrop: ColorRect
var _render_texture_fullscreen_container: Control
var _render_texture_fullscreen_widget: Control
var _render_texture_fullscreen_address := ""
var _render_texture_fullscreen_mode := RENDER_TEXTURE_VIEW_MODE_NONE
var _display_safe_area_override_enabled := false
var _display_safe_area_override := Rect2()
var _palette_widget_instances: Dictionary = {}
var _command_catalog_dirty := true
var _ui_update_batch_depth := 0
var _ui_update_catalog_dirty := false
var _ui_update_catalog_refresh_popup := false
var _ui_update_pins_dirty := false
var _ui_update_settings_dirty := false
var _ui_update_pin_options_dirty := false
var _debug_command_catalog_flush_count := 0
var _debug_pinned_refresh_count := 0
var _debug_filter_settings_save_count := 0
var _debug_display_variable_invalidation_count := 0
var _base_registered_addresses_cache: Array[String] = []
var _default_menu_hierarchy_cache: Dictionary = {}
var _all_known_autocomplete_tiers_cache: Array[String] = []
var _all_known_autocomplete_tiers_cache_valid := false
var _autocomplete_tiers_with_children: Dictionary = {}
var _tier_command_group_cache: Dictionary = {}
var _signal_backed_display_snapshot_cache: Dictionary = {}
var _autocomplete_text_width_cache: Dictionary = {}
var _autocomplete_display_value_cache: Dictionary = {}
var _autocomplete_visible_address_columns: Dictionary = {}
var _visible_getter_autocomplete_signatures: Dictionary = {}
var _ingame_overlay_top_edge_override := 0.0
var _ingame_overlay_left_edge_override := 0.0
var _ingame_overlay_right_edge_override := 0.0
var _ingame_overlay_bottom_edge_override := 0.0
var _scroll_to_bottom_tween: Tween
var _pending_animated_scroll_to_bottom := false
var _current_input_method := INPUT_METHOD_KEYBOARD
var _render_scale_settings: Dictionary = {
	INPUT_METHOD_KEYBOARD: {
		RENDER_SCALE_TARGET_LOG: DEFAULT_RENDER_SCALE_KEYBOARD,
		RENDER_SCALE_TARGET_COMMAND_PALETTE: DEFAULT_RENDER_SCALE_KEYBOARD,
		RENDER_SCALE_TARGET_PINNED_VARIABLES: DEFAULT_RENDER_SCALE_KEYBOARD,
	},
	INPUT_METHOD_CONTROLLER: {
		RENDER_SCALE_TARGET_LOG: DEFAULT_RENDER_SCALE_CONTROLLER_LOG,
		RENDER_SCALE_TARGET_COMMAND_PALETTE: DEFAULT_RENDER_SCALE_CONTROLLER_COMMAND_PALETTE,
		RENDER_SCALE_TARGET_PINNED_VARIABLES: DEFAULT_RENDER_SCALE_CONTROLLER_PINNED_VARIABLES,
	},
	INPUT_METHOD_TOUCH: {
		RENDER_SCALE_TARGET_LOG: DEFAULT_RENDER_SCALE_TOUCH_LOG,
		RENDER_SCALE_TARGET_COMMAND_PALETTE: DEFAULT_RENDER_SCALE_TOUCH_COMMAND_PALETTE,
		RENDER_SCALE_TARGET_PINNED_VARIABLES: DEFAULT_RENDER_SCALE_TOUCH_PINNED_VARIABLES,
	},
}
var _base_log_font_size := 0
var _base_command_font_size := 0
var _base_pinned_font_size := 0
var _base_line_edit_min_height := 0.0


# =============================================================================
# COMPOSITION CONFIGURATION METHODS
# =============================================================================

func set_settings_file(path: String) -> void:
	_settings_file = path


func set_welcome_message(msg: String) -> void:
	_welcome_message = msg


func set_log_entries_provider(provider: Callable) -> void:
	_log_entries_provider = provider


func set_entry_text_provider(provider: Callable) -> void:
	_entry_text_provider = provider


func set_commands_provider(provider: Callable) -> void:
	_commands_provider = provider
	invalidate_command_catalog(false)


func set_command_path_disabled_provider(provider: Callable) -> void:
	_command_path_disabled_provider = provider
	invalidate_command_catalog(false)


## Supplies the shared catalog resolver used by recursive predictive previews.
func set_default_child_resolver(provider: Callable) -> void:
	_default_child_resolver = provider
	invalidate_command_catalog(false)


func set_orderable_reorder_handler(handler: Callable) -> void:
	_orderable_reorder_handler = handler


func set_display_variables_provider(provider: Callable) -> void:
	_display_variables_provider = provider
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()


func set_widgets_provider(provider: Callable) -> void:
	_widgets_provider = provider
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()


func begin_ui_update_batch() -> void:
	_ui_update_batch_depth += 1


func end_ui_update_batch() -> void:
	if _ui_update_batch_depth <= 0:
		return
	_ui_update_batch_depth -= 1
	if _ui_update_batch_depth > 0:
		return
	var save_settings := _ui_update_settings_dirty
	var refresh_catalog := _ui_update_catalog_dirty
	var refresh_popup := _ui_update_catalog_refresh_popup
	var refresh_pins := _ui_update_pins_dirty
	var refresh_pin_options := _ui_update_pin_options_dirty
	_ui_update_settings_dirty = false
	_ui_update_catalog_dirty = false
	_ui_update_catalog_refresh_popup = false
	_ui_update_pins_dirty = false
	_ui_update_pin_options_dirty = false
	if save_settings:
		_save_filter_settings()
	if refresh_catalog:
		invalidate_command_catalog(refresh_popup)
	elif refresh_pins:
		_refresh_pinned_display_variables()
	if refresh_pin_options and not refresh_catalog:
		_refresh_pin_option_autocomplete_state()


func get_debug_update_counters() -> Dictionary:
	return {
		"catalog_flushes": _debug_command_catalog_flush_count,
		"pinned_refreshes": _debug_pinned_refresh_count,
		"settings_saves": _debug_filter_settings_save_count,
		"display_invalidations": _debug_display_variable_invalidation_count,
	}


func invalidate_command_catalog(refresh_popup: bool = true) -> void:
	_command_catalog_dirty = true
	_base_registered_addresses_cache.clear()
	_default_menu_hierarchy_cache.clear()
	_all_known_autocomplete_tiers_cache.clear()
	_all_known_autocomplete_tiers_cache_valid = false
	_autocomplete_tiers_with_children.clear()
	_tier_command_group_cache.clear()
	_signal_backed_display_snapshot_cache.clear()
	if _ui_update_batch_depth > 0:
		_ui_update_catalog_dirty = true
		_ui_update_catalog_refresh_popup = _ui_update_catalog_refresh_popup or refresh_popup
		_ui_update_pins_dirty = true
		return
	_debug_command_catalog_flush_count += 1
	_refresh_pinned_display_variables()
	if refresh_popup and _is_command_popup_visible():
		update_autocomplete_popup()


func invalidate_display_variable(address: String) -> void:
	var normalized_address := _resolve_alias_command_path(address.strip_edges())
	if normalized_address.is_empty():
		return
	_signal_backed_display_snapshot_cache.erase(normalized_address)
	_autocomplete_display_value_cache.erase(normalized_address)
	_debug_display_variable_invalidation_count += 1
	if _pinned_display_variables.has(normalized_address):
		_update_pinned_corner_redirects()
		_refresh_pinned_display_variable_row(normalized_address)
	if _autocomplete_visible_address_columns.has(normalized_address):
		_refresh_command_autocomplete_columns_for_addresses([normalized_address])


func set_rejected_level_count_provider(provider: Callable) -> void:
	_rejected_level_count_provider = provider


func set_rejected_channel_count_provider(provider: Callable) -> void:
	_rejected_channel_count_provider = provider


func set_level_visibility_provider(getter: Callable, setter: Callable) -> void:
	_level_visibility_getter = getter
	_level_visibility_setter = setter


func set_channel_visibility_provider(getter: Callable, setter: Callable) -> void:
	_channel_visibility_getter = getter
	_channel_visibility_setter = setter


func set_instance_visibility_provider(getter: Callable) -> void:
	_instance_visibility_getter = getter


## Get level visibility mode (uses provider if set, otherwise local dictionary)
func _get_level_visibility(level: int) -> int:
	if _level_visibility_getter.is_valid():
		return _level_visibility_getter.call(level)
	return _level_visibility.get(level, VisibilityMode.SHOWN)


## Set level visibility mode (uses provider if set, otherwise local dictionary)
func _set_level_visibility(level: int, mode: int) -> void:
	if _level_visibility_setter.is_valid():
		_level_visibility_setter.call(level, mode)
	else:
		_level_visibility[level] = mode


## Get channel visibility mode (uses provider if set, otherwise local dictionary)
func _get_channel_visibility(channel: String) -> int:
	if _channel_visibility_getter.is_valid():
		return _channel_visibility_getter.call(channel)
	return _channel_visibility.get(channel, VisibilityMode.SHOWN)


## Set channel visibility mode (uses provider if set, otherwise local dictionary)
func _set_channel_visibility(channel: String, mode: int) -> void:
	if _channel_visibility_setter.is_valid():
		_channel_visibility_setter.call(channel, mode)
	else:
		_channel_visibility[channel] = mode


## Get instance visibility mode (uses provider if set, otherwise SHOWN)
func _get_instance_visibility(session_id: int) -> int:
	if _instance_visibility_getter.is_valid():
		return _instance_visibility_getter.call(session_id)
	return VisibilityMode.SHOWN


func set_history_autocomplete_popup(popup: ItemList) -> void:
	_history_autocomplete_popup = popup
	if _history_autocomplete_popup:
		_history_autocomplete_popup.z_index = OVERLAY_Z_COMMAND_PALETTE


func set_ingame_overlay_edge_overrides(top: float = 0.0, left: float = 0.0, right: float = 0.0, bottom: float = 0.0) -> void:
	_ingame_overlay_top_edge_override = maxf(0.0, top)
	_ingame_overlay_left_edge_override = maxf(0.0, left)
	_ingame_overlay_right_edge_override = maxf(0.0, right)
	_ingame_overlay_bottom_edge_override = maxf(0.0, bottom)
	_refresh_pinned_display_variables()


func get_ingame_overlay_top_edge_override() -> float:
	return _ingame_overlay_top_edge_override


func get_ingame_overlay_left_edge_override() -> float:
	return _ingame_overlay_left_edge_override


func get_ingame_overlay_right_edge_override() -> float:
	return _ingame_overlay_right_edge_override


func get_ingame_overlay_bottom_edge_override() -> float:
	return _ingame_overlay_bottom_edge_override


func set_command_autocomplete_popup(popup: PanelContainer, scroll: ScrollContainer, columns_container: HBoxContainer) -> void:
	_command_autocomplete_popup = popup
	_command_autocomplete_scroll = scroll
	_command_autocomplete_columns_container = columns_container
	if _command_autocomplete_popup:
		_command_autocomplete_popup.clip_contents = true
		_command_autocomplete_popup.modulate = Color(1, 1, 1, 0)
		_command_autocomplete_popup.z_index = OVERLAY_Z_COMMAND_PALETTE
	if _command_autocomplete_scroll:
		_command_autocomplete_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_command_autocomplete_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_command_autocomplete_scroll.clip_contents = true
	_ensure_command_palette_resize_handle()
	_apply_command_palette_render_scale()


func is_command_palette_active() -> bool:
	return _command_autocomplete_popup != null and _command_autocomplete_popup.visible


func get_command_palette_reserved_height() -> float:
	if not is_command_palette_active() or _command_autocomplete_popup == null:
		return 0.0
	var layout_rect := _get_safe_area_layout_rect()
	return maxf(0.0, layout_rect.end.y - _command_autocomplete_popup.global_position.y + _get_scaled_autocomplete_popup_gap())


func get_command_palette_log_reserved_height() -> float:
	if _command_palette_log_spacer == null:
		return 0.0
	return _command_palette_log_spacer.custom_minimum_size.y


func refresh_safe_area_layout() -> void:
	_update_sidebar_visibility_and_layout()
	if _is_command_popup_visible():
		_position_command_autocomplete_popup()
	elif _is_history_popup_visible():
		_position_history_autocomplete_popup()
	else:
		_update_command_palette_log_reserved_space()
	_layout_render_texture_fullscreen_overlay()
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()
	_refresh_pinned_display_variables()


func _get_safe_area_layout_rect() -> Rect2:
	var rect := get_global_rect()
	if rect.size.x > 0.0 and rect.size.y > 0.0:
		return rect.intersection(_get_display_safe_area_layout_rect())
	return _get_display_safe_area_layout_rect()


func _set_display_safe_area_override_for_tests(rect: Rect2) -> void:
	_display_safe_area_override_enabled = true
	_display_safe_area_override = rect
	refresh_safe_area_layout()


func _clear_display_safe_area_override_for_tests() -> void:
	_display_safe_area_override_enabled = false
	_display_safe_area_override = Rect2()
	refresh_safe_area_layout()


func _should_apply_display_safe_area() -> bool:
	return _display_safe_area_override_enabled or OS.get_name() == "Android" or OS.has_feature("android") or OS.has_feature("ios")


func _get_display_safe_area_layout_rect() -> Rect2:
	var viewport_rect := get_viewport_rect()
	if not _should_apply_display_safe_area():
		return viewport_rect
	if _display_safe_area_override_enabled:
		return viewport_rect.intersection(_display_safe_area_override)
	if DisplayServer.get_name() == "headless":
		return viewport_rect

	var safe_area := Rect2(DisplayServer.get_display_safe_area())
	if safe_area.size.x <= 0.0 or safe_area.size.y <= 0.0:
		return viewport_rect

	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return viewport_rect.intersection(safe_area)

	var viewport_scale := Vector2(viewport_rect.size.x / window_size.x, viewport_rect.size.y / window_size.y)
	var scaled_safe_area := Rect2(
		viewport_rect.position + safe_area.position * viewport_scale,
		safe_area.size * viewport_scale
	)
	return viewport_rect.intersection(scaled_safe_area)


func add_custom_setting(name: String, label: String, default: bool) -> void:
	for index in range(_custom_settings.size()):
		var existing = _custom_settings[index]
		if str(existing.get("name", "")) == name:
			_custom_settings[index] = {"name": name, "label": label, "default": default}
			if not _custom_setting_values.has(name):
				_custom_setting_values[name] = default
			if _sidebar:
				_sidebar.configure_settings(_build_sidebar_settings())
				_sync_sidebar_state()
			return

	_custom_settings.append({"name": name, "label": label, "default": default})
	if not _custom_setting_values.has(name):
		_custom_setting_values[name] = default
	if _sidebar:
		_sidebar.configure_settings(_build_sidebar_settings())
		_sync_sidebar_state()


func set_custom_setting(name: String, value: bool) -> void:
	_custom_setting_values[name] = value
	if _sidebar:
		_sidebar.set_setting(name, value)


func initialize_display() -> void:
	_init_base()
	_setup_ui_nodes()
	_connect_ui_signals()
	_apply_render_scales()
	_setup_sidebar()
	_init_display()


func ensure_channel(channel: String) -> void:
	_ensure_channel_exists(channel)


func ensure_level(level: int) -> void:
	_ensure_level_exists(level)


func update_stats_for_entry(entry) -> void:
	_update_stats_for_entry(entry)


func should_display_entry(entry) -> bool:
	return _should_display(entry)


func display_entry(entry) -> void:
	_display_entry(entry)


func update_sidebar_statistics() -> void:
	_update_sidebar_stats()


func rebuild_display() -> void:
	_rebuild_display()


func clear_logs() -> void:
	_clear_logs()


func format_objects_for_display(objects: Array) -> String:
	return _format_objects(objects)


func format_stack_trace_for_display(stack_trace: String) -> String:
	return _format_stack_trace(stack_trace)


func set_search_filter(text: String) -> void:
	_search_filter = text


func get_level_visibility_snapshot() -> Dictionary:
	return _level_visibility.duplicate()


func get_channel_visibility_snapshot() -> Dictionary:
	return _channel_visibility.duplicate()


func get_setting(name: String, fallback: bool = false) -> bool:
	if _sidebar:
		return _sidebar.get_setting(name)
	if _custom_setting_values.has(name):
		return bool(_custom_setting_values[name])
	return fallback


func apply_setting(name: String, value: bool) -> void:
	_custom_setting_values[name] = value
	if _sidebar:
		_sidebar.set_setting(name, value)
	_on_setting_changed(name, value)


func get_current_input_method() -> String:
	return _current_input_method


func set_current_input_method(input_method: String) -> void:
	var normalized_method := _normalize_input_method(input_method)
	if _current_input_method == normalized_method:
		return
	_current_input_method = normalized_method
	_apply_render_scales()
	_update_sidebar_visibility_and_layout()
	_update_pinned_corner_redirects()


func set_touch_sidebar_fullscreen_enabled(value: bool) -> void:
	_touch_sidebar_fullscreen_enabled = value
	_update_sidebar_visibility_and_layout()


func close_touch_sidebar() -> bool:
	if not _is_touch_sidebar_fullscreen_layout():
		return false
	_set_sidebar_visible(false)
	return true


func get_render_scale_percent(target: String, input_method: String = "") -> float:
	var method_text := input_method.strip_edges()
	var normalized_method := _normalize_input_method(method_text if not method_text.is_empty() else _current_input_method)
	var normalized_target := _normalize_render_scale_target(target)
	var method_settings: Dictionary = _render_scale_settings.get(normalized_method, {})
	return float(method_settings.get(normalized_target, _get_default_render_scale_percent(normalized_method, normalized_target)))


func set_render_scale_percent(target: String, input_method: String, percent: float) -> void:
	var normalized_method := _normalize_input_method(input_method)
	var normalized_target := _normalize_render_scale_target(target)
	var method_settings: Dictionary = _render_scale_settings.get(normalized_method, {}).duplicate()
	method_settings[normalized_target] = _normalize_render_scale_percent(percent)
	_render_scale_settings[normalized_method] = method_settings
	_save_filter_settings()
	if normalized_method == _current_input_method:
		_apply_render_scales()


func has_sidebar() -> bool:
	return _sidebar != null


func add_instance(instance_id: int, instance_name: String, instance_number: int = -1) -> void:
	if _sidebar:
		_sidebar.add_instance(instance_id, instance_name, instance_number)


func remove_instance(instance_id: int) -> void:
	if _sidebar:
		_sidebar.remove_instance(instance_id)


func get_instance_sidebar_visibility(instance_id: int) -> int:
	if _sidebar:
		return _sidebar.get_instance_visibility(instance_id)
	return VisibilityMode.SHOWN


func connect_instance_visibility_changed(callback: Callable) -> void:
	if not _sidebar or not callback.is_valid():
		return
	if not _sidebar.instance_visibility_changed.is_connected(callback):
		_sidebar.instance_visibility_changed.connect(callback)


func set_instance_sidebar_stats(instance_id: int, shown: int, hidden: int, off: int) -> void:
	if _sidebar:
		_sidebar.set_instance_stats(instance_id, shown, hidden, off)


func is_command_entry_mode() -> bool:
	return _command_entry_mode


func show_command_entry_mode(prefill_text: String = "/", focus_input: bool = true) -> void:
	_command_entry_mode = true
	_update_command_entry_mode_visibility()
	if not line_edit:
		return

	_suppress_autocomplete_text_changes = true
	line_edit.text = prefill_text
	line_edit.caret_column = line_edit.text.length()
	_suppress_autocomplete_text_changes = false
	if focus_input:
		line_edit.grab_focus()
	else:
		line_edit.release_focus()
	on_text_changed_autocomplete(line_edit.text)
	# Child controls finish their first layout next frame; only geometry needs refreshing.
	call_deferred("_refresh_command_entry_geometry_deferred")


func _refresh_command_entry_geometry_deferred() -> void:
	if not _command_entry_mode or not line_edit:
		return
	if not line_edit.text.begins_with("/") or not _is_command_popup_visible():
		return
	_update_touch_command_autocomplete_column_visibility()
	_position_command_autocomplete_popup()


func hide_command_entry_mode(clear_input: bool = true) -> void:
	_command_entry_mode = false
	hide_autocomplete()

	if line_edit and clear_input:
		line_edit.clear()

	if _search_filter != "":
		_search_filter = ""
		_rebuild_display()

	_update_command_entry_mode_visibility()


func _update_command_entry_mode_visibility() -> void:
	if _logot_container:
		_logot_container.alignment = BoxContainer.ALIGNMENT_END if _command_entry_mode else BoxContainer.ALIGNMENT_BEGIN

	if rich_label:
		rich_label.visible = not _command_entry_mode

	if _clear_btn:
		_clear_btn.visible = not _command_entry_mode

	if _sidebar_toggle_btn:
		_sidebar_toggle_btn.visible = not _command_entry_mode

	_update_sidebar_visibility_and_layout()

	_update_collapsed_level_buttons_visibility()
	_update_command_palette_log_reserved_space()

	_refresh_pinned_display_variables()


func _set_sidebar_visible(value: bool, save: bool = true) -> void:
	_sidebar_visible = value
	if _sidebar_toggle_btn and _sidebar_toggle_btn.button_pressed != value:
		_sidebar_toggle_btn.button_pressed = value
	_update_sidebar_visibility_and_layout()
	_update_collapsed_level_buttons_visibility()
	if save:
		_save_filter_settings()


func _is_touch_sidebar_fullscreen_layout() -> bool:
	return _touch_sidebar_fullscreen_enabled and _current_input_method == INPUT_METHOD_TOUCH and _sidebar_visible and not _command_entry_mode


func _update_sidebar_visibility_and_layout() -> void:
	if _sidebar:
		var sidebar_should_show := _sidebar_visible and not _command_entry_mode
		_sidebar.visible = sidebar_should_show
		if _sidebar.has_method("set_touch_close_visible"):
			_sidebar.set_touch_close_visible(_is_touch_sidebar_fullscreen_layout())

	var use_fullscreen_sidebar := _is_touch_sidebar_fullscreen_layout()
	if _logot_container:
		_logot_container.visible = not use_fullscreen_sidebar
	if _sidebar:
		if _base_sidebar_custom_minimum_size == Vector2.ZERO:
			_base_sidebar_custom_minimum_size = _sidebar.custom_minimum_size
		_sidebar.custom_minimum_size = Vector2(get_viewport_rect().size.x, 0.0) if use_fullscreen_sidebar else _base_sidebar_custom_minimum_size
	if _main_container is SplitContainer:
		var split := _main_container as SplitContainer
		if _base_main_dragger_visibility < 0:
			_base_main_dragger_visibility = split.dragger_visibility
		if _base_main_split_offset == 0:
			_base_main_split_offset = split.split_offset
		split.dragger_visibility = SplitContainer.DRAGGER_HIDDEN_COLLAPSED if use_fullscreen_sidebar else _base_main_dragger_visibility
		if use_fullscreen_sidebar:
			split.split_offset = 0
		else:
			split.split_offset = _base_main_split_offset


func _on_sidebar_close_requested() -> void:
	_set_sidebar_visible(false)


# =============================================================================
# VIRTUAL METHODS - Override in subclass
# =============================================================================

## Return the settings file path
func _get_settings_file() -> String:
	return _settings_file


## Return the welcome message
func _get_welcome_message() -> String:
	return _welcome_message


## Return log entries array
func _get_log_entries() -> Array:
	if _log_entries_provider.is_valid():
		return _log_entries_provider.call()
	return []


## Return display text for an entry
func _get_entry_display_text(entry, truncate: bool, count: int = 1) -> String:
	if _entry_text_provider.is_valid():
		var text: String = _entry_text_provider.call(entry, truncate)
		return text

	var full_text := _format_objects(entry.objects)
	var display_text: String
	var extra_lines: int
	var instance_name: String = entry.instance_name if "instance_name" in entry else ""

	if entry.expanded:
		# Expanded: show full text with stack trace
		display_text = full_text
		extra_lines = 0
		var formatted_trace := _format_stack_trace(entry.stack_trace) if entry.stack_trace != "" else ""
		return format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, false, extra_lines, entry.stack_trace, count, formatted_trace, instance_name)
	else:
		# Collapsed: show first line only if truncating
		if truncate and entry.extra_line_count > 0:
			display_text = full_text.split("\n")[0] if "\n" in full_text else full_text
		else:
			display_text = full_text
		extra_lines = entry.extra_line_count if truncate else 0
		return format_display_text(display_text, entry.level, entry.channel, entry.timestamp, entry.id, true, extra_lines, entry.stack_trace, count, "", instance_name)


## Return additional sidebar settings
func _get_sidebar_settings() -> Array:
	return []


func _build_sidebar_settings() -> Array:
	var settings := [
		{"name": "collapse_duplicates", "label": "Collapse duplicates", "default": false},
		{"name": "wrap_text", "label": "Wrap text", "default": false},
		{"name": "truncate_multiline", "label": "Truncate multiline logs", "default": true},
	]
	settings.append_array(_get_sidebar_settings())
	settings.append_array(_custom_settings)
	return settings


## Return logot commands dictionary
func _get_commands() -> Dictionary:
	if _commands_provider.is_valid():
		return _commands_provider.call()
	return {}


func _get_display_variables() -> Dictionary:
	if _display_variables_provider.is_valid():
		return _display_variables_provider.call()
	return {}


func _get_widgets() -> Dictionary:
	if _widgets_provider.is_valid():
		return _widgets_provider.call()
	return {}


func _normalize_pin_corner(corner: String) -> String:
	var normalized_corner := corner.strip_edges().to_lower()
	if PINNED_OVERLAY_CORNERS.has(normalized_corner):
		return normalized_corner
	return PINNED_OVERLAY_CORNER_TOP_LEFT


func pin_display_variable(address: String, corner: String = PINNED_OVERLAY_CORNER_TOP_LEFT) -> void:
	_transient_pinned_display_variables.erase(address)
	if address.is_empty() or _pinned_display_variables.has(address):
		if _pinned_display_variables.has(address):
			_pinned_display_variable_corners[address] = _normalize_pin_corner(corner)
			_save_filter_settings()
			_refresh_pinned_display_variables()
			_refresh_pin_option_autocomplete_state()
		return
	_pinned_display_variables.append(address)
	_pinned_display_variable_corners[address] = _normalize_pin_corner(corner)
	_save_filter_settings()
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()


func unpin_display_variable(address: String) -> void:
	_transient_pinned_display_variables.erase(address)
	var index := _pinned_display_variables.find(address)
	if index == -1:
		return
	_pinned_display_variables.remove_at(index)
	_pinned_display_variable_corners.erase(address)
	_save_filter_settings()
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()


func set_display_variable_pinned(address: String, pinned: bool, corner: String = PINNED_OVERLAY_CORNER_TOP_LEFT) -> void:
	if pinned:
		pin_display_variable(address, corner)
	else:
		unpin_display_variable(address)


func set_display_variable_transiently_pinned(address: String, pinned: bool, corner: String = PINNED_OVERLAY_CORNER_TOP_LEFT) -> void:
	var normalized_address := address.strip_edges()
	if normalized_address.is_empty():
		return
	if pinned:
		_transient_pinned_display_variables[normalized_address] = true
		var normalized_corner := _normalize_pin_corner(corner)
		if _pinned_display_variables.has(normalized_address):
			if _pinned_display_variable_corners.get(normalized_address, "") == normalized_corner:
				return
			_pinned_display_variable_corners[normalized_address] = normalized_corner
			_refresh_pinned_display_variables()
			_refresh_pin_option_autocomplete_state()
			return
		_pinned_display_variables.append(normalized_address)
		_pinned_display_variable_corners[normalized_address] = normalized_corner
		invalidate_command_catalog(false)
		_refresh_pin_option_autocomplete_state()
		return
	if not _transient_pinned_display_variables.has(normalized_address):
		return
	_transient_pinned_display_variables.erase(normalized_address)
	var index := _pinned_display_variables.find(normalized_address)
	if index >= 0:
		_pinned_display_variables.remove_at(index)
	_pinned_display_variable_corners.erase(normalized_address)
	invalidate_command_catalog(false)
	_refresh_pin_option_autocomplete_state()


func is_display_variable_pinned(address: String) -> bool:
	return _pinned_display_variables.has(address)


func is_display_variable_transiently_pinned(address: String) -> bool:
	return _transient_pinned_display_variables.has(address)


func get_pinned_display_variables() -> Array[String]:
	return _pinned_display_variables.duplicate()


func get_pinned_display_variable_corner(address: String) -> String:
	return _normalize_pin_corner(str(_pinned_display_variable_corners.get(address, PINNED_OVERLAY_CORNER_TOP_LEFT)))


func set_pinned_corner_enabled(corner: String, enabled: bool) -> bool:
	var normalized_corner := _normalize_pin_corner(corner)
	if bool(_pinned_corner_enabled.get(normalized_corner, true)) == enabled:
		return true
	if not enabled and get_enabled_pinned_corners().size() <= 1:
		return false
	_pinned_corner_enabled[normalized_corner] = enabled
	_pinned_corner_redirects.erase(normalized_corner)
	_refresh_pinned_display_variables()
	return true


func is_pinned_corner_enabled(corner: String) -> bool:
	return bool(_pinned_corner_enabled.get(_normalize_pin_corner(corner), true))


func get_enabled_pinned_corners() -> Array[String]:
	var enabled_corners: Array[String] = []
	for corner in PINNED_OVERLAY_CORNERS:
		if bool(_pinned_corner_enabled.get(corner, true)):
			enabled_corners.append(corner)
	return enabled_corners


func get_effective_pinned_display_variable_corner(address: String) -> String:
	return _get_effective_pinned_corner_for_address(address)


func set_pinned_display_variables_visible(visible: bool) -> void:
	if _pinned_overlay_visible == visible:
		return
	_pinned_overlay_visible = visible
	_save_filter_settings()
	_refresh_pinned_display_variables()


func set_pinned_display_variables_suppressed(suppressed: bool) -> void:
	if _pinned_overlay_suppressed == suppressed:
		return
	_pinned_overlay_suppressed = suppressed
	_refresh_pinned_display_variables()


func toggle_pinned_display_variables_visible() -> bool:
	set_pinned_display_variables_visible(not _pinned_overlay_visible)
	return _pinned_overlay_visible


func is_pinned_display_variables_visible() -> bool:
	return _pinned_overlay_visible


func _are_pinned_display_variables_effectively_visible() -> bool:
	return _pinned_overlay_visible and not _pinned_overlay_suppressed


func clear_pinned_display_variables() -> void:
	if _pinned_display_variables.is_empty():
		return
	_pinned_display_variables.clear()
	_pinned_display_variable_corners.clear()
	_save_filter_settings()
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()


func get_saved_pinned_overlay_names() -> Array[String]:
	var names: Array[String] = []
	for overlay_name in _saved_pin_overlays:
		names.append(str(overlay_name))
	names.sort()
	return names


func save_pinned_overlay(name: String) -> bool:
	var overlay_name := name.strip_edges()
	if overlay_name.is_empty():
		return false
	var overlay_entries: Array[Dictionary] = []
	for address in _pinned_display_variables:
		overlay_entries.append({
			"address": address,
			"corner": get_pinned_display_variable_corner(address),
		})
	_saved_pin_overlays[overlay_name] = overlay_entries
	_save_filter_settings()
	return true


func load_pinned_overlay(name: String) -> bool:
	var overlay_name := name.strip_edges()
	if overlay_name.is_empty() or not _saved_pin_overlays.has(overlay_name):
		return false

	_pinned_display_variables.clear()
	_pinned_display_variable_corners.clear()
	var stored_addresses = _saved_pin_overlays[overlay_name]
	if stored_addresses is Array:
		for address_entry in stored_addresses:
			var address_str := ""
			var corner := PINNED_OVERLAY_CORNER_TOP_LEFT
			if address_entry is Dictionary:
				address_str = str((address_entry as Dictionary).get("address", ""))
				corner = _normalize_pin_corner(str((address_entry as Dictionary).get("corner", PINNED_OVERLAY_CORNER_TOP_LEFT)))
			else:
				address_str = str(address_entry)
			if address_str.is_empty() or _pinned_display_variables.has(address_str):
				continue
			_pinned_display_variables.append(address_str)
			_pinned_display_variable_corners[address_str] = corner

	_save_filter_settings()
	invalidate_command_catalog(false)
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()
	return true


func _refresh_pin_option_autocomplete_state() -> void:
	if _ui_update_batch_depth > 0:
		_ui_update_pin_options_dirty = true
		return
	if _is_command_popup_visible():
		update_autocomplete_popup()


## Called when a custom setting changes
func _on_custom_setting_changed(setting_name: String, value: bool) -> void:
	custom_setting_changed.emit(setting_name, value)


func _normalize_input_method(input_method: String) -> String:
	var normalized := input_method.strip_edges().to_lower()
	if normalized == INPUT_METHOD_CONTROLLER:
		return INPUT_METHOD_CONTROLLER
	if normalized == INPUT_METHOD_TOUCH:
		return INPUT_METHOD_TOUCH
	return INPUT_METHOD_KEYBOARD


func _normalize_render_scale_target(target: String) -> String:
	var normalized := target.strip_edges().to_lower()
	if normalized in [RENDER_SCALE_TARGET_COMMAND_PALETTE, "commands", "command", "palette"]:
		return RENDER_SCALE_TARGET_COMMAND_PALETTE
	if normalized in [RENDER_SCALE_TARGET_PINNED_VARIABLES, "pinned", "pins"]:
		return RENDER_SCALE_TARGET_PINNED_VARIABLES
	return RENDER_SCALE_TARGET_LOG


func _get_default_render_scale_percent(input_method: String, target: String) -> float:
	if input_method == INPUT_METHOD_CONTROLLER:
		if target == RENDER_SCALE_TARGET_LOG:
			return DEFAULT_RENDER_SCALE_CONTROLLER_LOG
		if target == RENDER_SCALE_TARGET_COMMAND_PALETTE:
			return DEFAULT_RENDER_SCALE_CONTROLLER_COMMAND_PALETTE
		if target == RENDER_SCALE_TARGET_PINNED_VARIABLES:
			return DEFAULT_RENDER_SCALE_CONTROLLER_PINNED_VARIABLES
	if input_method == INPUT_METHOD_TOUCH:
		if target == RENDER_SCALE_TARGET_LOG:
			return DEFAULT_RENDER_SCALE_TOUCH_LOG
		if target == RENDER_SCALE_TARGET_COMMAND_PALETTE:
			return DEFAULT_RENDER_SCALE_TOUCH_COMMAND_PALETTE
		if target == RENDER_SCALE_TARGET_PINNED_VARIABLES:
			return DEFAULT_RENDER_SCALE_TOUCH_PINNED_VARIABLES
	return DEFAULT_RENDER_SCALE_KEYBOARD


func _normalize_render_scale_percent(percent: float) -> float:
	return clampf(percent, RENDER_SCALE_MIN_PERCENT, RENDER_SCALE_MAX_PERCENT)


func _get_active_render_scale_percent(target: String) -> float:
	return get_render_scale_percent(target, _current_input_method)


func _get_render_scale_multiplier(target: String) -> float:
	return _get_active_render_scale_percent(target) / 100.0


func _get_control_font_size(control: Control, theme_item: String, fallback: int = 16) -> int:
	if control == null:
		return fallback
	var font_size := control.get_theme_font_size(theme_item)
	if font_size <= 0:
		return fallback
	return font_size


func _get_scaled_font_size(base_size: int, target: String) -> int:
	var scale := _get_render_scale_multiplier(target)
	return maxi(1, int(round(float(base_size) * scale)))


func _apply_rich_text_label_font_size(label: RichTextLabel, font_size: int) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	label.add_theme_font_size_override("bold_italics_font_size", font_size)
	label.add_theme_font_size_override("mono_font_size", font_size)


func _measure_pinned_variable_text_width(row: RichTextLabel, text: String) -> float:
	if row == null or text.is_empty():
		return 0.0
	var font := row.get_theme_font("normal_font")
	if font == null:
		font = row.get_theme_font("font")
	var font_size := row.get_theme_font_size("normal_font_size")
	if font_size <= 0:
		font_size = _get_scaled_font_size(_base_pinned_font_size, RENDER_SCALE_TARGET_PINNED_VARIABLES) if _base_pinned_font_size > 0 else 16
	if font != null:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return float(text.length() * maxi(1, font_size)) * 0.5


func _apply_pinned_variable_width_cap(row: RichTextLabel, plain_text: String = "") -> void:
	if row == null:
		return
	var content_width := float(row.get_content_width())
	if not plain_text.is_empty():
		content_width = maxf(content_width, _measure_pinned_variable_text_width(row, plain_text))
	if content_width <= 0.0:
		content_width = PINNED_OVERLAY_MAX_VARIABLE_WIDTH
	var capped_width := minf(ceil(content_width + PINNED_OVERLAY_VARIABLE_WIDTH_PADDING), PINNED_OVERLAY_MAX_VARIABLE_WIDTH)
	row.custom_minimum_size.x = capped_width
	row.size.x = capped_width


func _append_pinned_display_variable_value(row: RichTextLabel, value_text: String, value_color: Color, value_items: Array = []) -> void:
	if value_items.is_empty():
		if value_color.a > 0.0:
			row.push_color(value_color)
		row.append_text(value_text)
		if value_color.a > 0.0:
			row.pop()
		return

	for item_index in range(value_items.size()):
		if item_index > 0:
			row.add_text(" ")
		var item := value_items[item_index] as Dictionary
		var item_text := str(item.get("text", ""))
		var item_color := item.get("color", Color.TRANSPARENT) as Color
		if item_color.a > 0.0:
			row.push_color(item_color)
		row.append_text(item_text)
		if item_color.a > 0.0:
			row.pop()


func _get_pinned_display_variable_value_plain_text(value_text: String, value_items: Array = []) -> String:
	if value_items.is_empty():
		return value_text
	var item_texts: Array[String] = []
	for value_item in value_items:
		item_texts.append(str((value_item as Dictionary).get("text", "")))
	return " ".join(item_texts)


func _pinned_display_variable_value_has_line_break(value_text: String, value_items: Array = []) -> bool:
	if value_text.contains("\n") or value_text.contains("\r"):
		return true
	for value_item in value_items:
		var item_text := str((value_item as Dictionary).get("text", ""))
		if item_text.contains("\n") or item_text.contains("\r"):
			return true
	return false


func _should_stack_pinned_display_variable_value(row: RichTextLabel, display_address: String, value_text: String, value_items: Array = [], wrap_value: bool = false) -> bool:
	if row == null:
		return false
	if wrap_value:
		return true
	if _pinned_display_variable_value_has_line_break(value_text, value_items):
		return true
	var usable_width := PINNED_OVERLAY_MAX_VARIABLE_WIDTH - PINNED_OVERLAY_VARIABLE_WIDTH_PADDING
	var title_width := _measure_pinned_variable_text_width(row, "%s:" % display_address)
	if title_width > usable_width:
		return true
	var value_width := _measure_pinned_variable_text_width(row, _get_pinned_display_variable_value_plain_text(value_text, value_items))
	var inline_value_width := maxf(1.0, usable_width - title_width)
	return ceili(value_width / inline_value_width) > 2


func _append_pinned_display_variable_row_text(row: RichTextLabel, display_address: String, value_text: String, value_color: Color, align_right: bool, value_items: Array = [], wrap_value: bool = false) -> void:
	if row == null:
		return
	row.push_bgcolor(PINNED_OVERLAY_ROW_BG_COLOR)
	var stack_value := _should_stack_pinned_display_variable_value(row, display_address, value_text, value_items, wrap_value)
	row.set_meta("logot_pin_stacked_value", stack_value)
	row.push_table(1 if stack_value else 2)
	if stack_value:
		row.set_table_column_expand(0, true)
		row.push_cell()
		row.add_text("%s:" % display_address)
		row.newline()
		row.push_indent(1)
		_append_pinned_display_variable_value(row, value_text, value_color, value_items)
		row.pop()
		row.pop()
		row.pop()
		row.pop()
		return
	if align_right:
		row.set_table_column_expand(0, true)
		row.set_table_column_expand(1, false)
		row.push_cell()
		_append_pinned_display_variable_value(row, value_text, value_color, value_items)
		row.pop()
		row.push_cell()
		row.add_text(display_address)
		row.pop()
	else:
		row.set_table_column_expand(0, false)
		row.set_table_column_expand(1, true)
		row.push_cell()
		row.add_text("%s:" % display_address)
		row.pop()
		row.push_cell()
		_append_pinned_display_variable_value(row, value_text, value_color, value_items)
		row.pop()
	row.pop()
	row.pop()


func _apply_render_scales() -> void:
	_apply_log_render_scale()
	_apply_command_palette_render_scale()
	_apply_pinned_variables_render_scale()


func _apply_log_render_scale() -> void:
	if not rich_label:
		return
	if _base_log_font_size <= 0:
		_base_log_font_size = _get_control_font_size(rich_label, "normal_font_size", 16)
	_apply_rich_text_label_font_size(rich_label, _get_scaled_font_size(_base_log_font_size, RENDER_SCALE_TARGET_LOG))
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()


func _apply_command_palette_render_scale() -> void:
	if _base_command_font_size <= 0:
		if line_edit:
			_base_command_font_size = _get_control_font_size(line_edit, "font_size", 16)
		elif _history_autocomplete_popup:
			_base_command_font_size = _get_control_font_size(_history_autocomplete_popup, "font_size", 16)
		else:
			_base_command_font_size = 16

	var font_size := _get_scaled_font_size(_base_command_font_size, RENDER_SCALE_TARGET_COMMAND_PALETTE)
	if line_edit:
		if _base_line_edit_min_height <= 0.0:
			_base_line_edit_min_height = maxf(line_edit.custom_minimum_size.y, 0.0)
		line_edit.add_theme_font_size_override("font_size", font_size)
		if _base_line_edit_min_height > 0.0:
			line_edit.custom_minimum_size.y = ceil(_base_line_edit_min_height * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE))
	if _history_autocomplete_popup:
		_history_autocomplete_popup.add_theme_font_size_override("font_size", font_size)
	_refresh_input_action_button_layout()
	for node in _autocomplete_column_nodes:
		if node is AutocompleteCommandColumn and _history_autocomplete_popup:
			(node as AutocompleteCommandColumn).configure_theme(_history_autocomplete_popup)
	if _is_command_popup_visible():
		_render_command_autocomplete_popup()
	elif _is_history_popup_visible():
		_position_history_autocomplete_popup()


func _apply_pinned_variables_render_scale() -> void:
	if _base_pinned_font_size <= 0:
		if _main_container:
			_base_pinned_font_size = _get_control_font_size(_main_container, "normal_font_size", 16)
		else:
			_base_pinned_font_size = 16
	var font_size := _get_scaled_font_size(_base_pinned_font_size, RENDER_SCALE_TARGET_PINNED_VARIABLES)
	for row in _pinned_overlay_rows.values():
		if row is RichTextLabel and is_instance_valid(row):
			_apply_rich_text_label_font_size(row as RichTextLabel, font_size)
	_pinned_row_render_cache.clear()
	_refresh_pinned_display_variables()


func _get_scaled_autocomplete_item_height() -> int:
	var touch_target_multiplier := 2.0 if _is_touch_command_palette_layout() else 1.0
	var scaled_height := float(AUTOCOMPLETE_ITEM_HEIGHT) * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE) * touch_target_multiplier
	return maxi(1, int(round(scaled_height)))


func _get_scaled_autocomplete_popup_gap() -> float:
	return AUTOCOMPLETE_POPUP_GAP * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE)


func _is_touch_command_palette_layout() -> bool:
	return _current_input_method == INPUT_METHOD_TOUCH


## Called after logs are cleared
func _on_cleared() -> void:
	cleared.emit()


## Toggle entry expansion (override if entries stored elsewhere)
func _toggle_entry_expansion(entry_id: int) -> void:
	for entry in _get_log_entries():
		if entry.id == entry_id:
			entry.expanded = not entry.expanded
			_rebuild_display()
			return


# =============================================================================
# INITIALIZATION
# =============================================================================

func _init_base() -> void:
	_init_default_levels()
	_load_filter_settings()
	set_process(true)


func _setup_ui_nodes() -> void:
	# Find the UI root - either direct child LogotUI or self
	var ui_root: Node = self
	if has_node("LogotUI"):
		ui_root = get_node("LogotUI")

	# Get nodes from UI root
	if ui_root.has_node("MainContainer"):
		_main_container = ui_root.get_node("MainContainer")
	if _main_container and _main_container.has_node("LogotContainer"):
		_logot_container = _main_container.get_node("LogotContainer")
	if _logot_container and _logot_container.has_node("RichTextLabel"):
		rich_label = _logot_container.get_node("RichTextLabel")
		_ensure_command_palette_log_spacer()
	if _logot_container and _logot_container.has_node("InputRow"):
		_input_row = _logot_container.get_node("InputRow")
	elif _logot_container and _logot_container.has_node("VBoxContainer/InputRow"):
		_input_row = _logot_container.get_node("VBoxContainer/InputRow")
	if _input_row:
		if _input_row.has_node("LineEdit"):
			line_edit = _input_row.get_node("LineEdit")
		if _input_row.has_node("ClearButton"):
			_clear_btn = _input_row.get_node("ClearButton")
		if _input_row.has_node("SidebarToggleButton"):
			_sidebar_toggle_btn = _input_row.get_node("SidebarToggleButton")
		if _input_row.has_node("CollapsedLevelButtons"):
			_collapsed_level_buttons_container = _input_row.get_node("CollapsedLevelButtons") as VBoxContainer
	if _main_container and _main_container.has_node("Sidebar"):
		_sidebar = _main_container.get_node("Sidebar")


func _connect_ui_signals() -> void:
	if rich_label:
		rich_label.meta_clicked.connect(_on_log_meta_clicked)
		rich_label.meta_underlined = false
		rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _wrap_text else TextServer.AUTOWRAP_OFF
		rich_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_ensure_scroll_to_bottom_button()
		_connect_rich_label_scroll_tracking()
		_update_scroll_to_bottom_button_visibility()

	if _clear_btn:
		_clear_btn.pressed.connect(_clear_logs)

	if _sidebar_toggle_btn:
		_sidebar_toggle_btn.toggled.connect(_on_sidebar_toggle)
		_sidebar_toggle_btn.button_pressed = _sidebar_visible

	if _sidebar:
		_sidebar.visible = _sidebar_visible and not _command_entry_mode
		if _sidebar.has_signal("close_requested") and not _sidebar.close_requested.is_connected(_on_sidebar_close_requested):
			_sidebar.close_requested.connect(_on_sidebar_close_requested)

	_refresh_input_action_button_layout()
	_update_sidebar_visibility_and_layout()
	_setup_collapsed_level_buttons()


func refresh_input_action_button_layout() -> void:
	_refresh_input_action_button_layout()


func _refresh_input_action_button_layout() -> void:
	if not _input_row or not line_edit:
		return
	var is_after_input := false
	for child in _input_row.get_children():
		if child == line_edit:
			is_after_input = true
			continue
		if not is_after_input:
			continue
		if child is Button:
			_style_input_action_button(child as Button)


func _style_input_action_button(button: Button) -> void:
	var min_width := INPUT_ICON_BUTTON_WIDTH if button.text.strip_edges().is_empty() else maxf(button.custom_minimum_size.x, INPUT_ICON_BUTTON_WIDTH)
	button.custom_minimum_size = Vector2(min_width, INPUT_ACTION_BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.16, 1.0)
	normal.border_color = Color(0.48, 0.52, 0.62, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.22, 0.28, 1.0)
	hover.border_color = Color(0.64, 0.7, 0.82, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.16, 0.24, 0.34, 1.0)
	pressed.border_color = Color(0.72, 0.82, 0.96, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 16)


func _ensure_scroll_to_bottom_button() -> void:
	if not rich_label or _scroll_to_bottom_button:
		return

	var button := Button.new()
	button.name = "ScrollToBottomButton"
	button.text = "v"
	button.tooltip_text = "Scroll to bottom"
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.visible = false
	button.z_index = 120
	button.custom_minimum_size = Vector2(SCROLL_TO_BOTTOM_BUTTON_DIAMETER, SCROLL_TO_BOTTOM_BUTTON_DIAMETER)
	_style_scroll_to_bottom_button(button)
	button.pressed.connect(_on_scroll_to_bottom_button_pressed)
	rich_label.add_child(button)
	_scroll_to_bottom_button = button
	_update_scroll_to_bottom_button_layout()


func _style_scroll_to_bottom_button(button: Button) -> void:
	var radius := int(round(SCROLL_TO_BOTTOM_BUTTON_DIAMETER * 0.5))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.16, 0.2, 0.92)
	normal.border_color = Color(0.48, 0.52, 0.62, 0.95)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = radius
	normal.corner_radius_top_right = radius
	normal.corner_radius_bottom_right = radius
	normal.corner_radius_bottom_left = radius

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.24, 0.34, 0.96)
	hover.border_color = Color(0.62, 0.7, 0.84, 1.0)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.14, 0.2, 0.28, 0.98)
	pressed.border_color = Color(0.54, 0.64, 0.8, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_font_size_override("font_size", 14)


func _connect_rich_label_scroll_tracking() -> void:
	if not rich_label:
		return
	if not rich_label.resized.is_connected(_on_rich_label_resized):
		rich_label.resized.connect(_on_rich_label_resized)
	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		return
	_rich_label_scrollbar = scrollbar
	if not _rich_label_scrollbar.value_changed.is_connected(_on_rich_label_scrollbar_value_changed):
		_rich_label_scrollbar.value_changed.connect(_on_rich_label_scrollbar_value_changed)
	if not _rich_label_scrollbar.changed.is_connected(_on_rich_label_scrollbar_changed):
		_rich_label_scrollbar.changed.connect(_on_rich_label_scrollbar_changed)
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()


func _ensure_command_palette_log_spacer() -> void:
	if _command_palette_log_spacer != null and is_instance_valid(_command_palette_log_spacer):
		return
	if _logot_container == null or rich_label == null:
		return

	var spacer := Control.new()
	spacer.name = "CommandPaletteLogSpacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.visible = false
	spacer.custom_minimum_size = Vector2.ZERO
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_logot_container.add_child(spacer)
	_logot_container.move_child(spacer, rich_label.get_index() + 1)
	_command_palette_log_spacer = spacer


func _should_reserve_command_palette_log_space() -> bool:
	return (
		_command_autocomplete_popup != null
		and _command_autocomplete_popup.visible
		and not _autocomplete_column_states.is_empty()
		and rich_label != null
		and rich_label.visible
		and not _command_entry_mode
	)


func _get_command_palette_log_reserve_target_height() -> float:
	if not _should_reserve_command_palette_log_space():
		return 0.0
	return float(_get_command_autocomplete_target_height()) + _get_scaled_autocomplete_popup_gap()


func _update_command_palette_log_reserved_space() -> void:
	if _command_palette_log_spacer == null or not is_instance_valid(_command_palette_log_spacer):
		return

	var was_at_bottom := _is_scrolled_to_bottom()
	var target_height := _get_command_palette_log_reserve_target_height()
	if is_equal_approx(_command_palette_log_spacer.custom_minimum_size.y, target_height):
		return

	_command_palette_log_spacer.custom_minimum_size.y = target_height
	_command_palette_log_spacer.visible = target_height > 0.0
	if was_at_bottom:
		call_deferred("_scroll_to_bottom_after_palette_reserve_changed")


func _scroll_to_bottom_after_palette_reserve_changed() -> void:
	if rich_label != null and rich_label.visible:
		_scroll_to_bottom(false)
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()


func _update_scroll_to_bottom_button_layout() -> void:
	if not _scroll_to_bottom_button or not rich_label:
		return

	var diameter := SCROLL_TO_BOTTOM_BUTTON_DIAMETER
	var scrollbar_offset := 0.0
	if _rich_label_scrollbar and _rich_label_scrollbar.visible:
		scrollbar_offset = maxf(_rich_label_scrollbar.size.x, _rich_label_scrollbar.custom_minimum_size.x)
		if scrollbar_offset > 0.0:
			scrollbar_offset += SCROLL_TO_BOTTOM_SCROLLBAR_GAP

	var x := rich_label.size.x - diameter - SCROLL_TO_BOTTOM_BUTTON_MARGIN - scrollbar_offset
	var y := rich_label.size.y - diameter - SCROLL_TO_BOTTOM_BUTTON_MARGIN
	_scroll_to_bottom_button.position = Vector2(maxf(0.0, x), maxf(0.0, y))
	_scroll_to_bottom_button.size = Vector2(diameter, diameter)


func _update_scroll_to_bottom_button_visibility() -> void:
	if not _scroll_to_bottom_button:
		return

	if not rich_label or _pending_animated_scroll_to_bottom:
		_scroll_to_bottom_button.visible = false
		return

	if _scroll_to_bottom_tween and is_instance_valid(_scroll_to_bottom_tween):
		_scroll_to_bottom_button.visible = false
		return

	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		_scroll_to_bottom_button.visible = false
		return

	var has_overflow := scrollbar.max_value > scrollbar.page + 1.0
	_scroll_to_bottom_button.visible = has_overflow and not _is_scrolled_to_bottom()


func _on_scroll_to_bottom_button_pressed() -> void:
	_scroll_to_bottom(true)


func _on_rich_label_resized() -> void:
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()


func _on_rich_label_scrollbar_value_changed(_value: float) -> void:
	_update_scroll_to_bottom_button_visibility()


func _on_rich_label_scrollbar_changed() -> void:
	_update_scroll_to_bottom_button_layout()
	_update_scroll_to_bottom_button_visibility()


func _setup_sidebar() -> void:
	if not _sidebar:
		return

	_sidebar.configure_settings(_build_sidebar_settings())
	_sidebar.level_visibility_changed.connect(_on_level_visibility_changed)
	_sidebar.channel_visibility_changed.connect(_on_channel_visibility_changed)
	_sidebar.channel_deleted.connect(_on_channel_deleted)
	_sidebar.setting_changed.connect(_on_setting_changed)
	if _sidebar.has_signal("close_requested") and not _sidebar.close_requested.is_connected(_on_sidebar_close_requested):
		_sidebar.close_requested.connect(_on_sidebar_close_requested)

	_sync_sidebar_state()
	_update_sidebar_visibility_and_layout()


func _setup_collapsed_level_buttons() -> void:
	if not _collapsed_level_buttons_container:
		return

	for child in _collapsed_level_buttons_container.get_children():
		child.queue_free()
	_collapsed_level_buttons.clear()
	_collapsed_level_buttons_row = HBoxContainer.new()
	_collapsed_level_buttons_row.name = "ButtonsRow"
	_collapsed_level_buttons_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapsed_level_buttons_row.add_theme_constant_override("separation", 4)
	_collapsed_level_buttons_container.add_child(_collapsed_level_buttons_row)

	for level in LOG_LEVELS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(COLLAPSED_FILTER_BUTTON_MIN_WIDTH, COLLAPSED_FILTER_BUTTON_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.text = ""
		button.clip_contents = true
		_style_collapsed_level_button(button, level)

		var content := HBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 8)
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 10
		content.offset_top = 6
		content.offset_right = -10
		content.offset_bottom = -6
		button.add_child(content)

		var state_icon := _create_collapsed_icon(_get_visibility_icon(_get_level_visibility(level)))
		content.add_child(state_icon)

		var counts := HBoxContainer.new()
		counts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		counts.add_theme_constant_override("separation", 2)
		content.add_child(counts)

		var shown_count := _create_collapsed_count_widget(ICON_VISIBLE)
		var hidden_count := _create_collapsed_count_widget(ICON_HIDDEN)
		var off_count := _create_collapsed_count_widget(ICON_OFF)
		counts.add_child(shown_count["container"])
		counts.add_child(hidden_count["container"])
		counts.add_child(off_count["container"])

		button.pressed.connect(_on_collapsed_level_button_pressed.bind(level))
		_collapsed_level_buttons_row.add_child(button)
		_collapsed_level_buttons[level] = {
			"button": button,
			"content": content,
			"counts": counts,
			"state_icon": state_icon,
			"shown_container": shown_count["container"],
			"shown_label": shown_count["label"],
			"shown_icon": shown_count["icon"],
			"hidden_container": hidden_count["container"],
			"hidden_label": hidden_count["label"],
			"hidden_icon": hidden_count["icon"],
			"off_container": off_count["container"],
			"off_label": off_count["label"],
			"off_icon": off_count["icon"],
		}

	_refresh_collapsed_level_buttons()
	_update_collapsed_level_buttons_visibility()
	_refresh_input_action_button_layout()


func _style_collapsed_level_button(button: Button, level: int) -> void:
	var level_color: Color = LEVEL_COLORS.get(level, Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(level_color.r, level_color.g, level_color.b, 0.12)
	normal.border_color = Color(level_color.r, level_color.g, level_color.b, 0.72)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_right = 4
	normal.corner_radius_bottom_left = 4
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(level_color.r, level_color.g, level_color.b, 0.28)
	hover.border_color = Color(level_color.r, level_color.g, level_color.b, 0.9)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(level_color.r, level_color.g, level_color.b, 0.38)
	pressed.border_color = Color(level_color.r, level_color.g, level_color.b, 1.0)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)


func _create_collapsed_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = texture
	icon.custom_minimum_size = Vector2(COLLAPSED_FILTER_ICON_SIZE, COLLAPSED_FILTER_ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _create_collapsed_count_widget(icon_texture: Texture2D) -> Dictionary:
	var container := HBoxContainer.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_theme_constant_override("separation", 4)
	container.custom_minimum_size = Vector2(36, 0)

	var icon := _create_collapsed_icon(icon_texture)
	container.add_child(icon)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "0"
	label.add_theme_font_size_override("font_size", COLLAPSED_FILTER_COUNT_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 0.95))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	container.add_child(label)

	return {"container": container, "label": label, "icon": icon}


func _update_collapsed_level_buttons_visibility() -> void:
	if not _collapsed_level_buttons_container:
		return
	_collapsed_level_buttons_container.visible = not _command_entry_mode and not _sidebar_visible
	_refresh_input_action_button_layout()


func _refresh_collapsed_level_buttons() -> void:
	if _collapsed_level_buttons.is_empty():
		return

	for level in LOG_LEVELS:
		var controls: Dictionary = _collapsed_level_buttons.get(level, {})
		if controls.is_empty():
			continue

		var button := controls.get("button") as Button
		var content := controls.get("content") as HBoxContainer
		var state_icon := controls.get("state_icon") as TextureRect
		var counts := controls.get("counts") as HBoxContainer
		var shown_container := controls.get("shown_container") as HBoxContainer
		var shown_label := controls.get("shown_label") as Label
		var shown_icon := controls.get("shown_icon") as TextureRect
		var hidden_container := controls.get("hidden_container") as HBoxContainer
		var hidden_label := controls.get("hidden_label") as Label
		var hidden_icon := controls.get("hidden_icon") as TextureRect
		var off_container := controls.get("off_container") as HBoxContainer
		var off_label := controls.get("off_label") as Label
		var off_icon := controls.get("off_icon") as TextureRect
		if not button:
			continue

		var mode := _get_level_visibility(level)
		var stats: FilterStats = _level_stats.get(level)
		var shown_count := stats.shown_count if stats != null else 0
		var hidden_count := stats.hidden_count if stats != null else 0
		var off_count := _get_rejected_level_count(level)

		if state_icon:
			state_icon.texture = _get_visibility_icon(mode)
		_set_collapsed_count_widget_state(shown_container, shown_label, shown_count, shown_count > 0)
		_set_collapsed_count_widget_state(hidden_container, hidden_label, hidden_count, hidden_count > 0)
		_set_collapsed_count_widget_state(off_container, off_label, off_count, off_count > 0)
		_set_collapsed_count_group_style(shown_label, shown_icon, Color(0.86, 0.86, 0.86, 0.72))
		_set_collapsed_count_group_style(hidden_label, hidden_icon, Color(0.82, 0.82, 0.82, 0.62))
		_set_collapsed_count_group_style(off_label, off_icon, Color(0.74, 0.74, 0.74, 0.5))
		if counts:
			counts.visible = shown_count > 0 or hidden_count > 0 or off_count > 0
		button.custom_minimum_size = Vector2(_measure_collapsed_level_button_width(button, content), COLLAPSED_FILTER_BUTTON_HEIGHT)

		button.tooltip_text = _build_level_button_tooltip(level, mode, shown_count, hidden_count, off_count)


func _set_collapsed_count_widget_state(container: HBoxContainer, label: Label, count: int, visible: bool) -> void:
	if container:
		container.visible = visible
	if label:
		label.text = str(count)


func _set_collapsed_count_group_style(label: Label, icon: TextureRect, color: Color) -> void:
	if label:
		label.add_theme_color_override("font_color", color)
	if icon:
		icon.modulate = color


func _measure_collapsed_level_button_width(button: Button, content: HBoxContainer) -> float:
	if not button or not content:
		return COLLAPSED_FILTER_BUTTON_MIN_WIDTH

	var content_width := content.get_combined_minimum_size().x
	var horizontal_padding := content.offset_left - content.offset_right
	return maxf(COLLAPSED_FILTER_BUTTON_MIN_WIDTH, content_width + horizontal_padding)


func _build_level_button_tooltip(level: int, mode: int, shown_count: int, hidden_count: int, off_count: int) -> String:
	var parts := PackedStringArray()
	parts.append("shown:%d" % shown_count)
	if hidden_count > 0:
		parts.append("hidden:%d" % hidden_count)
	if off_count > 0:
		parts.append("off:%d" % off_count)
	return "%s is %s (%s). Click to cycle shown -> hidden -> off." % [
		LogLevel.names.get(level, str(level)),
		_get_visibility_mode_label(mode),
		", ".join(parts)
	]


func _get_visibility_icon(mode: int) -> Texture2D:
	match mode:
		VisibilityMode.HIDDEN:
			return ICON_HIDDEN
		VisibilityMode.OFF:
			return ICON_OFF
		_:
			return ICON_VISIBLE


func _get_level_button_label(level: int) -> String:
	return str(LEVEL_BUTTON_LABELS.get(level, str(level)))


func _get_visibility_mode_label(mode: int) -> String:
	match mode:
		VisibilityMode.HIDDEN:
			return "hidden"
		VisibilityMode.OFF:
			return "off"
		_:
			return "shown"


func _get_rejected_level_count(level: int) -> int:
	if _rejected_level_count_provider.is_valid():
		return int(_rejected_level_count_provider.call(level))
	return 0


func _on_collapsed_level_button_pressed(level: int) -> void:
	var current_mode := _get_level_visibility(level)
	var next_mode := VisibilityMode.SHOWN
	match current_mode:
		VisibilityMode.SHOWN:
			next_mode = VisibilityMode.HIDDEN
		VisibilityMode.HIDDEN:
			next_mode = VisibilityMode.OFF
		_:
			next_mode = VisibilityMode.SHOWN
	_apply_level_visibility_change(level, next_mode, true, true)


func _init_display() -> void:
	_ensure_pinned_overlay()
	_ensure_render_texture_fullscreen_overlay()
	if rich_label:
		rich_label.append_text(_get_welcome_message())
		_update_scroll_to_bottom_button_visibility()
	_refresh_pinned_display_variables()


func _process(delta: float) -> void:
	_poll_visible_display_variable_consumers(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		refresh_safe_area_layout()


func _stop_command_autocomplete_animation() -> void:
	if _command_autocomplete_animation_tween != null and is_instance_valid(_command_autocomplete_animation_tween):
		_command_autocomplete_animation_tween.kill()
	_command_autocomplete_animation_tween = null


func _apply_command_autocomplete_popup_visual_state() -> void:
	if not _command_autocomplete_popup:
		return
	_command_autocomplete_popup.global_position = _command_autocomplete_target_global_position + Vector2(_command_autocomplete_touch_slide_offset_x, _command_autocomplete_slide_offset)
	_command_autocomplete_popup.size = _command_autocomplete_target_size
	_command_autocomplete_popup.modulate = Color(1, 1, 1, clampf(_command_autocomplete_alpha, 0.0, 1.0))
	_update_command_palette_resize_handle()


func _ensure_command_palette_resize_handle() -> void:
	if _command_palette_resize_handle != null and is_instance_valid(_command_palette_resize_handle):
		return
	if _command_autocomplete_popup == null or _command_autocomplete_popup.get_parent() == null:
		return

	var handle := Control.new()
	handle.name = "CommandPaletteResizeHandle"
	handle.visible = false
	handle.z_index = OVERLAY_Z_COMMAND_PALETTE_RESIZE_HANDLE
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	handle.tooltip_text = "Drag to resize the command palette"
	handle.gui_input.connect(_on_command_palette_resize_handle_gui_input)
	_command_autocomplete_popup.get_parent().add_child(handle)

	var grip := Panel.new()
	grip.name = "Grip"
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grip_style := StyleBoxFlat.new()
	grip_style.bg_color = COMMAND_PALETTE_RESIZE_GRIP_COLOR
	grip_style.set_corner_radius_all(int(COMMAND_PALETTE_RESIZE_HANDLE_GRIP_HEIGHT * 0.5))
	grip.add_theme_stylebox_override("panel", grip_style)
	handle.add_child(grip)

	handle.mouse_entered.connect(_set_command_palette_resize_grip_highlighted.bind(true))
	handle.mouse_exited.connect(_set_command_palette_resize_grip_highlighted.bind(false))

	_command_palette_resize_handle = handle
	_command_palette_resize_grip = grip


func _set_command_palette_resize_grip_highlighted(highlighted: bool) -> void:
	if _command_palette_resize_grip == null or not is_instance_valid(_command_palette_resize_grip):
		return
	if not highlighted and _command_palette_resize_dragging:
		return
	var grip_style := _command_palette_resize_grip.get_theme_stylebox("panel")
	if grip_style is StyleBoxFlat:
		(grip_style as StyleBoxFlat).bg_color = COMMAND_PALETTE_RESIZE_GRIP_HOVER_COLOR if highlighted else COMMAND_PALETTE_RESIZE_GRIP_COLOR


## Keeps the drag handle centred just above the palette, following its slide/fade animation.
func _update_command_palette_resize_handle() -> void:
	if _command_palette_resize_handle == null or not is_instance_valid(_command_palette_resize_handle):
		return
	if _command_autocomplete_popup == null or not _command_autocomplete_popup.visible or _is_touch_command_palette_layout():
		_command_palette_resize_handle.visible = false
		return

	var multiplier := _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE)
	var handle_size := Vector2(COMMAND_PALETTE_RESIZE_HANDLE_WIDTH, COMMAND_PALETTE_RESIZE_HANDLE_HEIGHT) * multiplier
	var popup_position := _command_autocomplete_popup.global_position
	var popup_size := _command_autocomplete_popup.size

	_command_palette_resize_handle.size = handle_size
	_command_palette_resize_handle.global_position = Vector2(
		popup_position.x + (popup_size.x - handle_size.x) * 0.5,
		popup_position.y - COMMAND_PALETTE_RESIZE_HANDLE_GAP * multiplier - handle_size.y
	)
	_command_palette_resize_handle.modulate = Color(1, 1, 1, clampf(_command_autocomplete_alpha, 0.0, 1.0))
	_command_palette_resize_handle.visible = true

	if _command_palette_resize_grip != null and is_instance_valid(_command_palette_resize_grip):
		var grip_size := Vector2(COMMAND_PALETTE_RESIZE_HANDLE_GRIP_WIDTH, COMMAND_PALETTE_RESIZE_HANDLE_GRIP_HEIGHT) * multiplier
		_command_palette_resize_grip.size = grip_size
		_command_palette_resize_grip.position = (handle_size - grip_size) * 0.5


func _on_command_palette_resize_handle_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if button_event.pressed:
			_command_palette_resize_dragging = true
			_command_palette_resize_drag_start_y = button_event.global_position.y
			_command_palette_resize_drag_start_height = float(_get_command_autocomplete_target_height())
			_set_command_palette_resize_grip_highlighted(true)
		elif _command_palette_resize_dragging:
			_command_palette_resize_dragging = false
			# The pointer often ends the drag away from the handle, so drop the hover tint.
			_set_command_palette_resize_grip_highlighted(
				_command_palette_resize_handle.get_global_rect().has_point(button_event.global_position)
			)
			_save_filter_settings()
		_command_palette_resize_handle.accept_event()
	elif event is InputEventMouseMotion and _command_palette_resize_dragging:
		var motion_event := event as InputEventMouseMotion
		var drag_delta := _command_palette_resize_drag_start_y - motion_event.global_position.y
		_set_command_palette_height_override(_command_palette_resize_drag_start_height + drag_delta)
		_command_palette_resize_handle.accept_event()


func _set_command_palette_height_override(height: float) -> void:
	var clamped := _clamp_command_palette_height(height)
	if is_equal_approx(_command_palette_height_override, clamped):
		return
	_command_palette_height_override = clamped
	if _is_command_popup_visible():
		_position_command_autocomplete_popup()


func _set_command_autocomplete_slide_offset(value: float) -> void:
	_command_autocomplete_slide_offset = value
	_apply_command_autocomplete_popup_visual_state()


func _set_command_autocomplete_touch_slide_offset_x(value: float) -> void:
	_command_autocomplete_touch_slide_offset_x = value
	_apply_command_autocomplete_popup_visual_state()


func _set_command_autocomplete_alpha(value: float) -> void:
	_command_autocomplete_alpha = value
	_apply_command_autocomplete_popup_visual_state()


func _animate_touch_command_column(direction: int) -> void:
	if not _is_touch_command_palette_layout() or direction == 0 or not _command_autocomplete_popup:
		return
	if _command_autocomplete_animation_tween != null and is_instance_valid(_command_autocomplete_animation_tween):
		_command_autocomplete_animation_tween.kill()
	var distance := maxf(AUTOCOMPLETE_COMMAND_SLIDE_DISTANCE, _command_autocomplete_target_size.x)
	_command_autocomplete_touch_slide_offset_x = distance * float(direction)
	_apply_command_autocomplete_popup_visual_state()
	_command_autocomplete_animation_tween = create_tween()
	_command_autocomplete_animation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_command_autocomplete_animation_tween.set_trans(Tween.TRANS_CUBIC)
	_command_autocomplete_animation_tween.set_ease(Tween.EASE_OUT)
	_command_autocomplete_animation_tween.tween_method(Callable(self, "_set_command_autocomplete_touch_slide_offset_x"), _command_autocomplete_touch_slide_offset_x, 0.0, AUTOCOMPLETE_COMMAND_SLIDE_DURATION)
	_command_autocomplete_animation_tween.finished.connect(func() -> void:
		_command_autocomplete_animation_tween = null
		_command_autocomplete_touch_slide_offset_x = 0.0
		_apply_command_autocomplete_popup_visual_state()
	)


func _show_command_autocomplete_popup(animated: bool = true) -> void:
	if not _command_autocomplete_popup:
		return
	if _command_autocomplete_popup.visible and is_zero_approx(_command_autocomplete_slide_offset) and is_equal_approx(_command_autocomplete_alpha, 1.0):
		_apply_command_autocomplete_popup_visual_state()
		return
	_stop_command_autocomplete_animation()
	if not animated:
		_command_autocomplete_popup.visible = true
		_command_autocomplete_slide_offset = 0.0
		_command_autocomplete_touch_slide_offset_x = 0.0
		_command_autocomplete_alpha = 1.0
		_apply_command_autocomplete_popup_visual_state()
		_update_command_palette_log_reserved_space()
		return

	var start_offset := _command_autocomplete_slide_offset
	var start_alpha := _command_autocomplete_alpha
	if not _command_autocomplete_popup.visible:
		start_offset = AUTOCOMPLETE_COMMAND_SLIDE_DISTANCE
		start_alpha = 0.0
	_command_autocomplete_popup.visible = true
	_command_autocomplete_slide_offset = start_offset
	_command_autocomplete_alpha = start_alpha
	_apply_command_autocomplete_popup_visual_state()
	_update_command_palette_log_reserved_space()
	_command_autocomplete_animation_tween = create_tween()
	_command_autocomplete_animation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_command_autocomplete_animation_tween.set_trans(Tween.TRANS_CUBIC)
	_command_autocomplete_animation_tween.set_ease(Tween.EASE_OUT)
	_command_autocomplete_animation_tween.parallel().tween_method(Callable(self, "_set_command_autocomplete_slide_offset"), start_offset, 0.0, AUTOCOMPLETE_COMMAND_SLIDE_DURATION)
	_command_autocomplete_animation_tween.parallel().tween_method(Callable(self, "_set_command_autocomplete_alpha"), start_alpha, 1.0, AUTOCOMPLETE_COMMAND_SLIDE_DURATION)
	_command_autocomplete_animation_tween.finished.connect(func() -> void:
		_command_autocomplete_animation_tween = null
		_command_autocomplete_slide_offset = 0.0
		_command_autocomplete_touch_slide_offset_x = 0.0
		_command_autocomplete_alpha = 1.0
		_apply_command_autocomplete_popup_visual_state()
	)


func _hide_command_autocomplete_popup(animated: bool = true) -> void:
	if not _command_autocomplete_popup:
		return
	_stop_command_autocomplete_animation()
	if not _command_autocomplete_popup.visible:
		return
	if not animated:
		_command_autocomplete_popup.visible = false
		_command_autocomplete_slide_offset = 0.0
		_command_autocomplete_touch_slide_offset_x = 0.0
		_command_autocomplete_alpha = 1.0
		_apply_command_autocomplete_popup_visual_state()
		_update_command_palette_log_reserved_space()
		return

	var start_offset := _command_autocomplete_slide_offset
	var start_alpha := _command_autocomplete_alpha
	_command_autocomplete_animation_tween = create_tween()
	_command_autocomplete_animation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_command_autocomplete_animation_tween.set_trans(Tween.TRANS_CUBIC)
	_command_autocomplete_animation_tween.set_ease(Tween.EASE_IN)
	_command_autocomplete_animation_tween.parallel().tween_method(Callable(self, "_set_command_autocomplete_slide_offset"), start_offset, AUTOCOMPLETE_COMMAND_SLIDE_DISTANCE, AUTOCOMPLETE_COMMAND_SLIDE_DURATION)
	_command_autocomplete_animation_tween.parallel().tween_method(Callable(self, "_set_command_autocomplete_alpha"), start_alpha, 0.0, AUTOCOMPLETE_COMMAND_SLIDE_DURATION)
	_command_autocomplete_animation_tween.finished.connect(func() -> void:
		_command_autocomplete_animation_tween = null
		if _command_autocomplete_popup:
			_command_autocomplete_popup.visible = false
			_command_autocomplete_slide_offset = 0.0
			_command_autocomplete_touch_slide_offset_x = 0.0
			_command_autocomplete_alpha = 1.0
			_apply_command_autocomplete_popup_visual_state()
			_update_command_palette_log_reserved_space()
	)


func _ensure_pinned_overlay() -> void:
	if _pinned_overlay_root:
		return

	_pinned_overlay_root = Control.new()
	_pinned_overlay_root.name = "PinnedDisplayVariables"
	_pinned_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pinned_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pinned_overlay_root.visible = false
	_pinned_overlay_root.z_index = OVERLAY_Z_PINNED_VARIABLES
	add_child(_pinned_overlay_root)

	for corner in PINNED_OVERLAY_CORNERS:
		var container := HBoxContainer.new()
		container.name = "PinnedDisplayVariables_%s" % corner
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.alignment = BoxContainer.ALIGNMENT_END if corner in [PINNED_OVERLAY_CORNER_TOP_RIGHT, PINNED_OVERLAY_CORNER_BOTTOM_RIGHT] else BoxContainer.ALIGNMENT_BEGIN
		container.add_theme_constant_override("separation", PINNED_OVERLAY_COLUMN_SEPARATION)
		_pinned_overlay_root.add_child(container)
		_pinned_overlay_corner_containers[corner] = container


func _normalize_render_texture_view_mode(mode: String) -> String:
	var normalized_mode := mode.strip_edges().to_lower()
	if normalized_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
		return RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
	if normalized_mode in [RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY, "overlay", "fullscreen/overlay"]:
		return RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY
	return RENDER_TEXTURE_VIEW_MODE_NONE


func _ensure_render_texture_fullscreen_overlay() -> void:
	if _render_texture_fullscreen_root != null and is_instance_valid(_render_texture_fullscreen_root):
		_layout_render_texture_fullscreen_overlay()
		return

	var overlay_root := Control.new()
	overlay_root.name = "RenderTextureFullscreenOverlay"
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_root.visible = false
	overlay_root.z_index = OVERLAY_Z_RENDER_TEXTURE_FULLSCREEN
	add_child(overlay_root)
	_render_texture_fullscreen_root = overlay_root

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color(0.0, 0.0, 0.0, 0.96)
	overlay_root.add_child(backdrop)
	_render_texture_fullscreen_backdrop = backdrop

	var content := Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(content)
	_render_texture_fullscreen_container = content
	_layout_render_texture_fullscreen_overlay()


func _layout_render_texture_fullscreen_overlay() -> void:
	if _render_texture_fullscreen_root == null or not is_instance_valid(_render_texture_fullscreen_root):
		return
	_render_texture_fullscreen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_render_texture_fullscreen_root.offset_left = 0.0
	_render_texture_fullscreen_root.offset_top = 0.0
	_render_texture_fullscreen_root.offset_right = 0.0
	_render_texture_fullscreen_root.offset_bottom = 0.0
	if _render_texture_fullscreen_backdrop != null and is_instance_valid(_render_texture_fullscreen_backdrop):
		_render_texture_fullscreen_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_render_texture_fullscreen_backdrop.offset_left = 0.0
		_render_texture_fullscreen_backdrop.offset_top = 0.0
		_render_texture_fullscreen_backdrop.offset_right = 0.0
		_render_texture_fullscreen_backdrop.offset_bottom = 0.0
	if _render_texture_fullscreen_container == null or not is_instance_valid(_render_texture_fullscreen_container):
		return

	var root_rect := _render_texture_fullscreen_root.get_global_rect()
	if root_rect.size.x <= 0.0 or root_rect.size.y <= 0.0:
		root_rect = get_global_rect()
	if root_rect.size.x <= 0.0 or root_rect.size.y <= 0.0:
		root_rect = get_viewport_rect()

	var content_rect := root_rect.intersection(_get_display_safe_area_layout_rect())
	if content_rect.size.x <= 0.0 or content_rect.size.y <= 0.0:
		content_rect = root_rect

	_render_texture_fullscreen_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_render_texture_fullscreen_container.offset_left = content_rect.position.x - root_rect.position.x
	_render_texture_fullscreen_container.offset_top = content_rect.position.y - root_rect.position.y
	_render_texture_fullscreen_container.offset_right = content_rect.end.x - root_rect.end.x
	_render_texture_fullscreen_container.offset_bottom = content_rect.end.y - root_rect.end.y


func _clear_render_texture_fullscreen_widget() -> void:
	if _render_texture_fullscreen_widget != null and is_instance_valid(_render_texture_fullscreen_widget):
		_render_texture_fullscreen_widget.queue_free()
	_render_texture_fullscreen_widget = null


func _refresh_render_texture_fullscreen_overlay() -> void:
	_ensure_render_texture_fullscreen_overlay()
	if _render_texture_fullscreen_root == null:
		return
	_layout_render_texture_fullscreen_overlay()

	if _render_texture_fullscreen_mode == RENDER_TEXTURE_VIEW_MODE_NONE or _render_texture_fullscreen_address.is_empty():
		_clear_render_texture_fullscreen_widget()
		_render_texture_fullscreen_root.visible = false
		return
	if not _is_render_texture_widget_path(_render_texture_fullscreen_address):
		_clear_render_texture_fullscreen_widget()
		_render_texture_fullscreen_address = ""
		_render_texture_fullscreen_mode = RENDER_TEXTURE_VIEW_MODE_NONE
		_render_texture_fullscreen_root.visible = false
		return

	if _render_texture_fullscreen_widget == null or not is_instance_valid(_render_texture_fullscreen_widget):
		var widget_instance := _create_widget_instance(_render_texture_fullscreen_address, "fullscreen")
		if widget_instance == null:
			var fallback := Label.new()
			fallback.text = "Render texture unavailable: %s" % _render_texture_fullscreen_address
			fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			widget_instance = fallback
		widget_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		widget_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _render_texture_fullscreen_container != null:
			_render_texture_fullscreen_container.add_child(widget_instance)
		_render_texture_fullscreen_widget = widget_instance

	if _render_texture_fullscreen_backdrop != null:
		_render_texture_fullscreen_backdrop.color = Color(0.0, 0.0, 0.0, 0.48) if _render_texture_fullscreen_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY else Color(0.0, 0.0, 0.0, 0.96)
	_render_texture_fullscreen_root.visible = true
	_refresh_logot_widget_instance(_render_texture_fullscreen_widget, 0.0, true)


func set_render_texture_widget_view_mode(address: String, mode: String) -> bool:
	var normalized_mode := _normalize_render_texture_view_mode(mode)
	if normalized_mode == RENDER_TEXTURE_VIEW_MODE_NONE:
		clear_render_texture_widget_view_mode()
		return true

	var resolved_address := _resolve_alias_command_path(address.strip_edges())
	if resolved_address.is_empty() or not _is_render_texture_widget_path(resolved_address):
		return false

	var requires_widget_rebuild := resolved_address != _render_texture_fullscreen_address
	_render_texture_fullscreen_address = resolved_address
	_render_texture_fullscreen_mode = normalized_mode
	if requires_widget_rebuild:
		_clear_render_texture_fullscreen_widget()
	_refresh_render_texture_fullscreen_overlay()
	return true


func clear_render_texture_widget_view_mode() -> void:
	_render_texture_fullscreen_address = ""
	_render_texture_fullscreen_mode = RENDER_TEXTURE_VIEW_MODE_NONE
	_refresh_render_texture_fullscreen_overlay()


func is_render_texture_widget_view_mode_active() -> bool:
	return _render_texture_fullscreen_mode != RENDER_TEXTURE_VIEW_MODE_NONE and not _render_texture_fullscreen_address.is_empty()


func get_render_texture_widget_view_mode(address: String) -> String:
	var resolved_address := _resolve_alias_command_path(address.strip_edges())
	if resolved_address.is_empty() or resolved_address != _render_texture_fullscreen_address:
		return RENDER_TEXTURE_VIEW_MODE_NONE
	return _render_texture_fullscreen_mode


func _get_pinned_overlay_container(corner: String) -> HBoxContainer:
	return _pinned_overlay_corner_containers.get(_normalize_pin_corner(corner), null) as HBoxContainer


func _get_pinned_overlay_size_for_corner(corner: String) -> Vector2:
	var container := _get_pinned_overlay_container(corner)
	if container == null:
		return Vector2.ZERO
	var overlay_size := container.get_combined_minimum_size()
	if overlay_size.x <= 0.0 or overlay_size.y <= 0.0:
		overlay_size = container.size
	return Vector2(ceil(overlay_size.x), ceil(overlay_size.y))


func _get_pinned_overlay_rect_for_corner(corner: String, overlay_size: Vector2) -> Rect2:
	var normalized_corner := _normalize_pin_corner(corner)
	var viewport_size := get_viewport_rect().size
	var margin_top := PINNED_OVERLAY_MARGIN + _ingame_overlay_top_edge_override
	var margin_left := PINNED_OVERLAY_MARGIN + _ingame_overlay_left_edge_override
	var margin_right := PINNED_OVERLAY_MARGIN + _ingame_overlay_right_edge_override
	var margin_bottom := PINNED_OVERLAY_MARGIN + _ingame_overlay_bottom_edge_override
	var position := Vector2(margin_left, margin_top)
	if normalized_corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or normalized_corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT:
		position.x = maxf(margin_left, viewport_size.x - overlay_size.x - margin_right)
	if normalized_corner == PINNED_OVERLAY_CORNER_BOTTOM_LEFT or normalized_corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT:
		position.y = maxf(margin_top, viewport_size.y - overlay_size.y - margin_bottom)
	return Rect2(position, overlay_size)


func _can_swap_pinned_corner_to_target_side(target_corner: String, source_size: Vector2) -> bool:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return false
	var target_rect := _get_pinned_overlay_rect_for_corner(target_corner, source_size)
	var viewport_width := get_viewport_rect().size.x
	if viewport_width <= 0.0:
		return false
	var midpoint := viewport_width * 0.5
	var is_right_corner := target_corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or target_corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
	if is_right_corner:
		return target_rect.position.x >= midpoint
	return target_rect.end.x <= midpoint


func _resolve_pinned_corner_pair_swap_conflict(corner_a: String, corner_b: String, desired_redirects: Dictionary, current_redirects: Dictionary) -> void:
	var wants_a := bool(desired_redirects.get(corner_a, false))
	var wants_b := bool(desired_redirects.get(corner_b, false))
	if not wants_a or not wants_b:
		return
	var current_a := bool(current_redirects.get(corner_a, false))
	var current_b := bool(current_redirects.get(corner_b, false))
	if current_a == current_b:
		desired_redirects[corner_a] = false
		desired_redirects[corner_b] = false
	elif current_a:
		desired_redirects[corner_b] = false
	else:
		desired_redirects[corner_a] = false


func _update_pinned_corner_redirects() -> void:
	if _current_input_method == INPUT_METHOD_TOUCH:
		_pinned_corner_redirects.clear()
		return
	if not get_setting("pinned_auto_swap_on_hover", false):
		_pinned_corner_redirects.clear()
		return
	var viewport := get_viewport()
	if viewport == null:
		_pinned_corner_redirects.clear()
		return
	var mouse_position := viewport.get_mouse_position()
	var current_redirects := _pinned_corner_redirects.duplicate()
	var desired_redirects: Dictionary = {}
	for corner in PINNED_OVERLAY_CORNERS:
		if not is_pinned_corner_enabled(corner):
			desired_redirects[corner] = false
			continue
		var source_size := _get_pinned_overlay_size_for_corner(corner)
		if source_size.x <= 0.0 or source_size.y <= 0.0:
			desired_redirects[corner] = false
			continue
		var target_corner := str(PINNED_OVERLAY_OPPOSITE_CORNER.get(corner, corner))
		var source_hotspot := _get_pinned_overlay_rect_for_corner(corner, source_size).grow(PINNED_OVERLAY_MOUSE_SWAP_PADDING)
		var target_size := _get_pinned_overlay_size_for_corner(target_corner)
		var target_hotspot := _get_pinned_overlay_rect_for_corner(target_corner, target_size).grow(PINNED_OVERLAY_MOUSE_RETURN_PADDING)
		var wants_redirect := false
		if bool(current_redirects.get(corner, false)):
			if source_hotspot.has_point(mouse_position) or target_hotspot.has_point(mouse_position):
				wants_redirect = true
		elif source_hotspot.has_point(mouse_position):
			wants_redirect = true
			if not _can_swap_pinned_corner_to_target_side(target_corner, source_size):
				wants_redirect = false
		desired_redirects[corner] = wants_redirect

	_resolve_pinned_corner_pair_swap_conflict(
		PINNED_OVERLAY_CORNER_TOP_LEFT,
		PINNED_OVERLAY_CORNER_TOP_RIGHT,
		desired_redirects,
		current_redirects
	)
	_resolve_pinned_corner_pair_swap_conflict(
		PINNED_OVERLAY_CORNER_BOTTOM_LEFT,
		PINNED_OVERLAY_CORNER_BOTTOM_RIGHT,
		desired_redirects,
		current_redirects
	)

	for corner in PINNED_OVERLAY_CORNERS:
		if bool(desired_redirects.get(corner, false)):
			_pinned_corner_redirects[corner] = true
		else:
			_pinned_corner_redirects.erase(corner)


func _get_effective_pinned_corner(corner: String) -> String:
	var normalized_corner := _normalize_pin_corner(corner)
	if bool(_pinned_corner_redirects.get(normalized_corner, false)):
		normalized_corner = str(PINNED_OVERLAY_OPPOSITE_CORNER.get(normalized_corner, normalized_corner))
	return _resolve_enabled_pinned_corner(normalized_corner)


func _resolve_enabled_pinned_corner(corner: String) -> String:
	var normalized_corner := _normalize_pin_corner(corner)
	if is_pinned_corner_enabled(normalized_corner):
		return normalized_corner
	var fallback_order: Array[String] = []
	fallback_order.append(str(PINNED_OVERLAY_OPPOSITE_CORNER.get(normalized_corner, normalized_corner)))
	match normalized_corner:
		PINNED_OVERLAY_CORNER_BOTTOM_LEFT:
			fallback_order.append(PINNED_OVERLAY_CORNER_TOP_LEFT)
			fallback_order.append(PINNED_OVERLAY_CORNER_TOP_RIGHT)
		PINNED_OVERLAY_CORNER_BOTTOM_RIGHT:
			fallback_order.append(PINNED_OVERLAY_CORNER_TOP_RIGHT)
			fallback_order.append(PINNED_OVERLAY_CORNER_TOP_LEFT)
		PINNED_OVERLAY_CORNER_TOP_LEFT:
			fallback_order.append(PINNED_OVERLAY_CORNER_BOTTOM_LEFT)
			fallback_order.append(PINNED_OVERLAY_CORNER_BOTTOM_RIGHT)
		PINNED_OVERLAY_CORNER_TOP_RIGHT:
			fallback_order.append(PINNED_OVERLAY_CORNER_BOTTOM_RIGHT)
			fallback_order.append(PINNED_OVERLAY_CORNER_BOTTOM_LEFT)
	for fallback_corner in fallback_order:
		if is_pinned_corner_enabled(fallback_corner):
			return fallback_corner
	return normalized_corner


func _get_effective_pinned_corner_for_address(address: String) -> String:
	return _get_effective_pinned_corner(get_pinned_display_variable_corner(address))


func _is_pinned_item_available(address: String) -> bool:
	return _has_display_variable(address) or _has_widget(address)


func _layout_pinned_overlay_containers() -> void:
	if not _pinned_overlay_root:
		return
	_pinned_overlay_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pinned_overlay_root.position = Vector2.ZERO
	for corner in PINNED_OVERLAY_CORNERS:
		var container := _get_pinned_overlay_container(corner)
		if container == null:
			continue
		var container_size := _get_pinned_overlay_size_for_corner(corner)
		container.size = container_size
		container.position = _get_pinned_overlay_rect_for_corner(corner, container_size).position
		var align_right: bool = corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
		var horizontal_alignment := HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
		for row in container.get_children():
			if row is Control:
				(row as Control).size_flags_horizontal = Control.SIZE_SHRINK_END if align_right else Control.SIZE_SHRINK_BEGIN
			_apply_pinned_overlay_row_alignment(row, horizontal_alignment, align_right)


func _apply_pinned_overlay_row_alignment(row: Node, horizontal_alignment: HorizontalAlignment, align_right: bool) -> void:
	if row == null or not is_instance_valid(row):
		return
	if row is RichTextLabel:
		(row as RichTextLabel).horizontal_alignment = horizontal_alignment
		if bool(row.get_meta("logot_pin_widget_header", false)):
			_update_pinned_widget_header_markup(row as RichTextLabel, align_right)
	for child in row.get_children():
		_apply_pinned_overlay_row_alignment(child, horizontal_alignment, align_right)


func _update_pinned_widget_header_markup(header: RichTextLabel, align_right: bool, base_name_counts: Dictionary = {}) -> void:
	if header == null or not is_instance_valid(header):
		return
	var address := str(header.get_meta("logot_pin_widget_address", "")).strip_edges()
	if address.is_empty():
		return
	var display_address := _get_widget_display_label(address)
	if display_address.is_empty():
		display_address = _get_pinned_item_display_address(address, base_name_counts)
	if display_address.is_empty():
		display_address = address
	var markup := "[bgcolor=#1a202acc] %s [/bgcolor]" % _escape_overlay_bbcode(display_address)
	if align_right:
		markup = "[right]%s[/right]" % markup
	header.set_meta("logot_pin_widget_header_alignment", "right" if align_right else "left")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
	header.clear()
	header.append_text(markup)
	var content_height := float(header.get_content_height())
	if content_height > 0.0:
		header.custom_minimum_size.y = ceil(content_height)


func _update_pinned_widget_headers_in_row(node: Node, align_right: bool, base_name_counts: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is RichTextLabel and bool((node as RichTextLabel).get_meta("logot_pin_widget_header", false)):
		_update_pinned_widget_header_markup(node as RichTextLabel, align_right, base_name_counts)
	for child in node.get_children():
		_update_pinned_widget_headers_in_row(child, align_right, base_name_counts)


func _layout_pinned_overlay_rows(visible_addresses: Array[String]) -> void:
	var rows_by_corner: Dictionary = {}
	for corner in PINNED_OVERLAY_CORNERS:
		var container := _get_pinned_overlay_container(corner)
		if container != null:
			rows_by_corner[corner] = []
			for column in container.get_children():
				for child in column.get_children():
					column.remove_child(child)
				container.remove_child(column)
				column.free()

	var base_name_counts := _get_visible_pinned_item_base_name_counts()
	var placed_row_ids: Dictionary = {}
	for address in visible_addresses:
		var row = _pinned_overlay_rows.get(address, null)
		if not (row is Control) or not is_instance_valid(row):
			continue
		var row_id := int((row as Node).get_instance_id())
		if placed_row_ids.has(row_id):
			continue
		placed_row_ids[row_id] = true
		var effective_corner := _get_effective_pinned_corner_for_address(address)
		if not rows_by_corner.has(effective_corner):
			continue
		var parent := (row as Node).get_parent()
		if parent != null:
			(parent as Node).remove_child(row)
		var align_right: bool = effective_corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or effective_corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
		var horizontal_alignment := HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
		if row is Control:
			(row as Control).size_flags_horizontal = Control.SIZE_SHRINK_END if align_right else Control.SIZE_SHRINK_BEGIN
		if _has_display_variable(address):
			_apply_pinned_display_variable_row_snapshot(address, base_name_counts, false)
		_apply_pinned_overlay_row_alignment(row, horizontal_alignment, align_right)
		_update_pinned_widget_headers_in_row(row as Node, align_right, base_name_counts)
		(rows_by_corner[effective_corner] as Array).append(row)

	for corner in PINNED_OVERLAY_CORNERS:
		_layout_pinned_overlay_corner_columns(corner, rows_by_corner.get(corner, []) as Array)


func _layout_pinned_overlay_corner_columns(corner: String, rows: Array) -> void:
	var container := _get_pinned_overlay_container(corner)
	if container == null or rows.is_empty():
		return
	var viewport_height := get_viewport_rect().size.y
	var max_column_height := maxf(1.0, viewport_height - PINNED_OVERLAY_MARGIN * 2.0 - _ingame_overlay_top_edge_override - _ingame_overlay_bottom_edge_override)
	var columns: Array[Array] = []
	var current_column: Array = []
	var current_height := 0.0
	for row in rows:
		if not (row is Control):
			continue
		var row_height := ceil((row as Control).get_combined_minimum_size().y)
		if not current_column.is_empty() and current_height + row_height > max_column_height:
			columns.append(current_column)
			current_column = []
			current_height = 0.0
		current_column.append(row)
		current_height += row_height
	if not current_column.is_empty():
		columns.append(current_column)

	var align_right := corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
	if align_right:
		columns.reverse()
	for column_rows in columns:
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.alignment = BoxContainer.ALIGNMENT_END if corner in [PINNED_OVERLAY_CORNER_BOTTOM_LEFT, PINNED_OVERLAY_CORNER_BOTTOM_RIGHT] else BoxContainer.ALIGNMENT_BEGIN
		column.add_theme_constant_override("separation", 0)
		container.add_child(column)
		for row in column_rows:
			column.add_child(row)


func _refresh_pinned_display_variables() -> void:
	if _ui_update_batch_depth > 0:
		_ui_update_pins_dirty = true
		return
	_debug_pinned_refresh_count += 1
	if not _pinned_overlay_root:
		return

	var visible_addresses: Array[String] = []
	for address in _pinned_display_variables:
		if not _is_pinned_item_available(address):
			continue
		visible_addresses.append(address)
	var base_name_counts := _get_visible_pinned_item_base_name_counts()

	_sync_pinned_overlay_rows(visible_addresses)
	if visible_addresses.is_empty() or not _are_pinned_display_variables_effectively_visible():
		if _pinned_overlay_root:
			_pinned_overlay_root.visible = false
		return

	for address in visible_addresses:
		if _has_display_variable(address):
			_refresh_pinned_display_variable_row(address, base_name_counts, true)

	_layout_pinned_overlay_rows(visible_addresses)
	_layout_pinned_overlay_containers()
	_update_pinned_corner_redirects()
	_layout_pinned_overlay_rows(visible_addresses)
	_layout_pinned_overlay_containers()
	_pinned_overlay_root.visible = true


func _sync_pinned_overlay_rows(visible_addresses: Array[String]) -> void:
	if not _pinned_overlay_root:
		return

	for existing_address in _pinned_overlay_rows.keys():
		var normalized_existing := str(existing_address)
		if visible_addresses.has(normalized_existing):
			continue
		var row = _pinned_overlay_rows[normalized_existing]
		if row is Node and is_instance_valid(row):
			(row as Node).queue_free()
		_pinned_overlay_rows.erase(normalized_existing)
		_pinned_row_render_cache.erase(normalized_existing)
		_pinned_row_render_snapshots.erase(normalized_existing)
		_pinned_row_poll_signatures.erase(normalized_existing)

	for address in visible_addresses:
		var row = _pinned_overlay_rows.get(address, null)
		var should_be_widget := _has_widget(address)
		var row_valid := row is Control and is_instance_valid(row)
		if row_valid and should_be_widget and str((row as Control).get_meta("logot_pin_type", "")) != "widget":
			(row as Control).queue_free()
			row_valid = false
		if row_valid and not should_be_widget and str((row as Control).get_meta("logot_pin_type", "")) != "display_variable":
			(row as Control).queue_free()
			row_valid = false
		if not row_valid:
			if should_be_widget:
				row = _create_pinned_overlay_widget_row(address)
			else:
				row = _create_pinned_overlay_row()
			if row is Control:
				_pinned_overlay_rows[address] = row


func _create_pinned_overlay_row() -> RichTextLabel:
	var row := RichTextLabel.new()
	row.set_meta("logot_pin_type", "display_variable")
	row.bbcode_enabled = true
	row.scroll_active = false
	row.fit_content = true
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size.x = PINNED_OVERLAY_MAX_VARIABLE_WIDTH
	if _main_container and _main_container.theme:
		row.theme = _main_container.theme
	if _base_pinned_font_size <= 0:
		_base_pinned_font_size = _get_control_font_size(row, "normal_font_size", 16)
	_apply_rich_text_label_font_size(row, _get_scaled_font_size(_base_pinned_font_size, RENDER_SCALE_TARGET_PINNED_VARIABLES))
	_apply_pinned_variable_width_cap(row)
	return row


func _create_pinned_overlay_widget_row(address: String) -> Control:
	var panel := PanelContainer.new()
	panel.set_meta("logot_pin_type", "widget")
	# A pinned widget may contain controls. PASS keeps the chrome transparent
	# while allowing its widget descendants to receive pointer input.
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.055, 0.075, 0.72)
	panel_style.border_color = Color(0.65, 0.75, 0.92, 0.30)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(1.0)
	panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_theme_constant_override("separation", 1)
	panel.add_child(content)

	var header := RichTextLabel.new()
	header.set_meta("logot_pin_widget_header", true)
	header.set_meta("logot_pin_widget_address", address)
	header.bbcode_enabled = true
	header.scroll_active = false
	# Keep header text from expanding pinned widget width.
	header.fit_content = false
	header.clip_contents = true
	header.autowrap_mode = TextServer.AUTOWRAP_OFF
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.custom_minimum_size.y = 18.0
	var align_header_right := get_pinned_display_variable_corner(address) == PINNED_OVERLAY_CORNER_TOP_RIGHT or get_pinned_display_variable_corner(address) == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
	_update_pinned_widget_header_markup(header, align_header_right)
	if _main_container and _main_container.theme:
		header.theme = _main_container.theme
	content.add_child(header)

	var widget := _create_widget_instance(address, "pin", get_pinned_display_variable_corner(address))
	if widget == null:
		var fallback := Label.new()
		fallback.text = "Widget unavailable: %s" % address
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		widget = fallback
	content.add_child(widget)
	return panel


func _refresh_pinned_display_variable_row(address: String, base_name_counts: Dictionary = {}, force: bool = false, update_redirects: bool = true) -> void:
	if not _pinned_overlay_rows.has(address):
		return
	if not _has_display_variable(address):
		return

	var row = _pinned_overlay_rows[address]
	if not (row is RichTextLabel) or not is_instance_valid(row):
		return

	if base_name_counts.is_empty():
		base_name_counts = _get_visible_pinned_item_base_name_counts()

	var snapshot := _get_display_variable_render_snapshot(address)
	if not bool(snapshot.get("exists", false)):
		return
	_pinned_row_render_snapshots[address] = snapshot
	_apply_pinned_display_variable_row_snapshot(address, base_name_counts, force)

	if str(snapshot.get("update_mode", "getter")) == "getter":
		_pinned_row_poll_signatures[address] = "%s|%s" % [str(snapshot.get("signature", "")), _get_effective_pinned_corner_for_address(address)]
	else:
		_pinned_row_poll_signatures.erase(address)

	(row as RichTextLabel).visible = _are_pinned_display_variables_effectively_visible()
	if update_redirects and _pinned_overlay_root and _pinned_overlay_root.visible:
		_update_pinned_corner_redirects()
		_layout_pinned_overlay_containers()


func _apply_pinned_display_variable_row_snapshot(address: String, base_name_counts: Dictionary = {}, force: bool = false) -> void:
	if not _pinned_overlay_rows.has(address):
		return
	if not _has_display_variable(address):
		return

	var row = _pinned_overlay_rows[address]
	if not (row is RichTextLabel) or not is_instance_valid(row):
		return

	var snapshot: Dictionary = _pinned_row_render_snapshots.get(address, {})
	if snapshot.is_empty():
		_refresh_pinned_display_variable_row(address, base_name_counts, force, false)
		return
	if not bool(snapshot.get("exists", false)):
		return

	if base_name_counts.is_empty():
		base_name_counts = _get_visible_pinned_item_base_name_counts()

	var display_label := str(snapshot.get("display_label", "")).strip_edges()
	var display_address := display_label
	if display_address.is_empty():
		display_address = _get_pinned_item_display_address(address, base_name_counts)
	var effective_corner := _get_effective_pinned_corner_for_address(address)
	var align_right := effective_corner == PINNED_OVERLAY_CORNER_TOP_RIGHT or effective_corner == PINNED_OVERLAY_CORNER_BOTTOM_RIGHT
	var signature := var_to_str({
		"display_address": display_address,
		"render": str(snapshot.get("signature", "")),
		"align_right": align_right,
		"inline_color": (snapshot.get("inline_color", Color.TRANSPARENT) as Color).to_html(true),
		"wrap_value": bool(snapshot.get("wrap_value", false)),
	})
	if force or _pinned_row_render_cache.get(address, "") != signature:
		var value_text := str(snapshot.get("text", ""))
		var value_color: Color = snapshot.get("inline_color", Color.TRANSPARENT)
		var value_items: Array = snapshot.get("items", [])
		(row as RichTextLabel).clear()
		_append_pinned_display_variable_row_text(row as RichTextLabel, display_address, value_text, value_color, align_right, value_items, bool(snapshot.get("wrap_value", false)))
		var plain_text := "%s %s" % [value_text, display_address] if align_right else "%s: %s" % [display_address, value_text]
		_apply_pinned_variable_width_cap(row as RichTextLabel, plain_text)
		_pinned_row_render_cache[address] = signature

	(row as RichTextLabel).visible = _are_pinned_display_variables_effectively_visible()


func _get_visible_pinned_item_base_name_counts() -> Dictionary:
	var base_name_counts: Dictionary = {}
	for address in _pinned_display_variables:
		if not _is_pinned_item_available(address):
			continue
		var base_name := _get_address_tail(address)
		base_name_counts[base_name] = int(base_name_counts.get(base_name, 0)) + 1
	return base_name_counts


func _get_pinned_item_display_address(address: String, base_name_counts: Dictionary = {}) -> String:
	var normalized_address := address.strip_edges().trim_suffix("/")
	if normalized_address.is_empty():
		return ""
	if base_name_counts.is_empty():
		base_name_counts = _get_visible_pinned_item_base_name_counts()
	var base_name := _get_address_tail(normalized_address)
	return normalized_address if int(base_name_counts.get(base_name, 0)) > 1 else base_name


func _poll_visible_display_variable_consumers(delta: float) -> void:
	_poll_visible_pinned_display_variable_rows(delta)
	_poll_visible_autocomplete_display_variable_rows()
	_poll_visible_logot_widgets(delta)


func _poll_visible_pinned_display_variable_rows(delta: float) -> void:
	if not _are_pinned_display_variables_effectively_visible() or _pinned_overlay_root == null or not _pinned_overlay_root.visible:
		return

	var base_name_counts := _get_visible_pinned_item_base_name_counts()
	for address in _pinned_row_poll_signatures.keys():
		if not _pinned_display_variables.has(str(address)) or not _has_display_variable(str(address)):
			_pinned_row_poll_signatures.erase(address)

	for address in _pinned_display_variables:
		if not _pinned_overlay_rows.has(address) or not _has_display_variable(address):
			continue
		if _is_signal_backed_display_variable(address):
			_pinned_row_poll_signatures.erase(address)
			continue
		var snapshot := _get_display_variable_render_snapshot(address)
		if str(snapshot.get("update_mode", "getter")) != "getter":
			_pinned_row_poll_signatures.erase(address)
			continue
		var signature := "%s|%s" % [str(snapshot.get("signature", "")), _get_effective_pinned_corner_for_address(address)]
		if _pinned_row_poll_signatures.get(address, "") == signature:
			continue
		_pinned_row_poll_signatures[address] = signature
		_refresh_pinned_display_variable_row(address, base_name_counts)
	var visible_addresses: Array[String] = []
	for address in _pinned_display_variables:
		if _is_pinned_item_available(address):
			visible_addresses.append(address)
	_pinned_overlay_layout_poll_accum_sec += maxf(0.0, delta)
	var layout_signature := _get_pinned_overlay_poll_layout_signature(visible_addresses)
	var should_refresh_layout := layout_signature != _pinned_overlay_layout_poll_signature
	if _pinned_overlay_layout_poll_accum_sec >= PINNED_OVERLAY_LAYOUT_POLL_INTERVAL_SEC:
		should_refresh_layout = true
	if should_refresh_layout:
		_pinned_overlay_layout_poll_accum_sec = 0.0
		_update_pinned_corner_redirects()
		_pinned_overlay_layout_poll_signature = _get_pinned_overlay_poll_layout_signature(visible_addresses)
		_layout_pinned_overlay_rows(visible_addresses)
		_layout_pinned_overlay_containers()


func _get_pinned_overlay_poll_layout_signature(visible_addresses: Array[String]) -> String:
	var row_signatures: Array[String] = []
	for address in visible_addresses:
		var address_text := str(address)
		var row = _pinned_overlay_rows.get(address_text, null)
		var row_size := Vector2.ZERO
		if row is Control and is_instance_valid(row):
			row_size = (row as Control).get_combined_minimum_size()
		row_signatures.append("%s|%s|%s|%s" % [
			address_text,
			_get_effective_pinned_corner_for_address(address_text),
			roundi(row_size.x),
			roundi(row_size.y),
		])
	return var_to_str({
		"rows": row_signatures,
		"viewport": get_viewport_rect().size.round(),
		"top": roundi(_ingame_overlay_top_edge_override),
		"left": roundi(_ingame_overlay_left_edge_override),
		"right": roundi(_ingame_overlay_right_edge_override),
		"bottom": roundi(_ingame_overlay_bottom_edge_override),
		"redirects": _pinned_corner_redirects.duplicate(),
	})


func _get_display_variable_entry(address: String) -> Dictionary:
	var resolved_address := _resolve_alias_command_path(address)
	return {
		"resolved_address": resolved_address,
		"display_variable": _get_display_variables().get(resolved_address, null),
	}


func _get_display_variable_wrap_value(address: String) -> bool:
	if address.is_empty():
		return false
	var entry := _get_display_variable_entry(address)
	var display_variable = entry.get("display_variable", null)
	return display_variable is LogotDisplayVariable and (display_variable as LogotDisplayVariable).wrap_value


func _is_signal_backed_display_variable(address: String) -> bool:
	var entry := _get_display_variable_entry(address)
	var display_variable = entry.get("display_variable", null)
	if not (display_variable is LogotDisplayVariable):
		return false

	var display_variable_object := display_variable as LogotDisplayVariable
	return (
		display_variable_object.change_signal_source != null
		and is_instance_valid(display_variable_object.change_signal_source)
		and display_variable_object.change_signal_name != &""
	)


func _get_display_variable_render_snapshot(address: String) -> Dictionary:
	var entry := _get_display_variable_entry(address)
	var resolved_address := str(entry.get("resolved_address", ""))
	var display_variable = entry.get("display_variable", null)
	if resolved_address.is_empty() or display_variable == null:
		return {"exists": false, "signature": "", "update_mode": "getter"}
	var signal_backed := false
	if display_variable is LogotDisplayVariable:
		var signal_display_variable := display_variable as LogotDisplayVariable
		signal_backed = (
			signal_display_variable.change_signal_source != null
			and is_instance_valid(signal_display_variable.change_signal_source)
			and signal_display_variable.change_signal_name != &""
		)
	if signal_backed and _signal_backed_display_snapshot_cache.has(resolved_address):
		return (_signal_backed_display_snapshot_cache[resolved_address] as Dictionary).duplicate(true)

	var current_value: Variant = null
	var items: Array[Dictionary] = []
	var inline_color := Color.TRANSPARENT
	var display_label := ""
	var wrap_value := false
	if display_variable is LogotDisplayVariable:
		var display_variable_object := display_variable as LogotDisplayVariable
		wrap_value = display_variable_object.wrap_value
		if display_variable_object.getter.is_valid():
			current_value = display_variable_object.getter.call()
		if display_variable_object.items_provider.is_valid():
			items = _normalize_display_variable_items(display_variable_object.items_provider.call())
		if display_variable_object.inline_color_provider.is_valid():
			inline_color = _resolve_display_variable_inline_color(display_variable_object.inline_color_provider.call())
		if display_variable_object.display_label_provider.is_valid():
			display_label = str(display_variable_object.display_label_provider.call()).replace("\n", " ").replace("\r", " ").strip_edges()
	elif display_variable is Callable:
		var getter := display_variable as Callable
		if getter.is_valid():
			current_value = getter.call()

	if items.is_empty():
		var item_text := _get_command_option_label_for_value(resolved_address, current_value, 0)
		if item_text.is_empty():
			item_text = str(current_value)
		if not item_text.is_empty():
			var item_color := inline_color
			if item_color.a <= 0.0:
				item_color = _get_default_display_variable_inline_color(current_value)
			var item: Dictionary = {"text": item_text}
			if item_color.a > 0.0:
				item["color"] = item_color
			items.append(item)

	if inline_color.a <= 0.0:
		inline_color = _get_default_display_variable_inline_color(current_value)

	var text_parts: PackedStringArray = []
	var item_signatures: PackedStringArray = []
	var autocomplete_color := inline_color
	for item in items:
		var item_dict := item as Dictionary
		var item_text := str(item_dict.get("text", "")).replace("\n", " ").replace("\r", " ")
		text_parts.append(item_text)
		var item_color = item_dict.get("color", null)
		var item_color_html := ""
		if item_color is Color and (item_color as Color).a > 0.0:
			item_color_html = (item_color as Color).to_html(false)
			if autocomplete_color.a <= 0.0:
				autocomplete_color = item_color as Color
		item_signatures.append("%s|%s" % [item_text, item_color_html])

	if autocomplete_color.a <= 0.0 and not items.is_empty():
		var first_item_color = (items[0] as Dictionary).get("color", null)
		if first_item_color is Color and (first_item_color as Color).a > 0.0:
			autocomplete_color = first_item_color as Color

	var text := " ".join(text_parts)
	var snapshot := {
		"exists": true,
		"resolved_address": resolved_address,
		"text": text,
		"display_label": display_label,
		"wrap_value": wrap_value,
		"items": items,
		"inline_color": inline_color,
		"autocomplete_color": autocomplete_color,
		"update_mode": "signal" if signal_backed else "getter",
		"signature": var_to_str({
			"text": text,
			"display_label": display_label,
			"wrap_value": wrap_value,
			"items": item_signatures,
			"inline_color": inline_color.to_html(false),
			"autocomplete_color": autocomplete_color.to_html(false),
		}),
	}
	if signal_backed:
		_signal_backed_display_snapshot_cache[resolved_address] = snapshot.duplicate(true)
	return snapshot


func _get_address_tail(address: String) -> String:
	if address.is_empty():
		return address
	var normalized_address := address.trim_suffix("/")
	var separator_index := normalized_address.rfind("/")
	if separator_index == -1:
		return normalized_address
	return normalized_address.substr(separator_index + 1)


func _escape_overlay_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _init_default_levels() -> void:
	for level in LOG_LEVELS:
		# Only initialize local dictionary if no provider is set
		if not _level_visibility_getter.is_valid() and level not in _level_visibility:
			_level_visibility[level] = VisibilityMode.SHOWN
		if level not in _level_stats:
			_level_stats[level] = FilterStats.new()
	_ensure_channel_exists("")


# =============================================================================
# CHANNEL AND LEVEL MANAGEMENT
# =============================================================================

func _ensure_channel_exists(channel: String) -> void:
	if channel not in _known_channels:
		_known_channels.append(channel)
		# Only initialize local dictionary if no provider is set
		if not _channel_visibility_getter.is_valid() and channel not in _channel_visibility:
			_channel_visibility[channel] = VisibilityMode.SHOWN
		if channel not in _channel_stats:
			_channel_stats[channel] = FilterStats.new()
		if _sidebar:
			_sidebar.add_channel(channel)


func _ensure_level_exists(level: int) -> void:
	# Only initialize local dictionary if no provider is set
	if not _level_visibility_getter.is_valid() and level not in _level_visibility:
		_level_visibility[level] = VisibilityMode.SHOWN
	if level not in _level_stats:
		_level_stats[level] = FilterStats.new()


func get_known_channels() -> Array[String]:
	return _known_channels


# =============================================================================
# DISPLAY LOGIC
# =============================================================================

func _should_display(entry) -> bool:
	var level_mode = _get_level_visibility(entry.level)
	var channel_mode = _get_channel_visibility(entry.channel)

	# Check instance visibility using the entry's session_id
	var instance_mode = _get_instance_visibility(entry.session_id)

	if _search_filter != "":
		var search_text := _get_entry_plain_text(entry).to_lower()
		if not search_text.contains(_search_filter):
			return false

	return level_mode == VisibilityMode.SHOWN and channel_mode == VisibilityMode.SHOWN and instance_mode == VisibilityMode.SHOWN


func _format_objects(objects: Array) -> String:
	var parts: PackedStringArray = []
	for obj in objects:
		parts.append(str(obj))
	return " ".join(parts)


func _get_entry_plain_text(entry) -> String:
	var entry_id := int(entry.id)
	if _entry_plain_text_cache.has(entry_id):
		return str(_entry_plain_text_cache[entry_id])
	if _entry_plain_text_cache.size() >= 2048:
		_entry_plain_text_cache.clear()
	var text := _format_objects(entry.objects)
	_entry_plain_text_cache[entry_id] = text
	return text


static func _get_level_color_hex(level: int) -> String:
	var color: Color = LEVEL_COLORS.get(level, Color.WHITE)
	return "#" + color.to_html(false)


## Formats text for display as a BBCode table row with timestamp, channel, and message.
## This is the core static formatting function for all log entry display.
## Parameters:
##   - text: The message text to display
##   - level: Log level (determines color)
##   - channel: Channel name (can be empty)
##   - timestamp: Timestamp string
##   - entry_id: Entry ID for URL actions (use -1 if not applicable)
##   - is_collapsed: Whether this is a collapsed view
##   - extra_lines: Number of hidden lines (for collapsed view indicator)
##   - stack_trace: Stack trace string (for expanded view, or to determine expandability)
##   - collapse_count: Number of collapsed duplicates (badge shown after channel)
##   - formatted_stack_trace: Pre-formatted stack trace BBCode (for expanded view)
##   - instance_name: Name of the instance this log came from (empty for local/editor)
static func format_display_text(text: String, level: int, channel: String, timestamp: String, entry_id: int = -1, is_collapsed: bool = true, extra_lines: int = 0, stack_trace: String = "", collapse_count: int = 0, formatted_stack_trace: String = "", instance_name: String = "") -> String:
	var color: String = _get_level_color_hex(level)

	# Build extra lines indicator for collapsed view
	var extra_indicator := ""
	if is_collapsed and extra_lines > 0:
		extra_indicator = " [i][color=dim_gray]+%d[/color][/i]" % extra_lines

	# Determine if this entry has expandable content and the toggle action
	var has_expandable := extra_lines > 0 or stack_trace != ""
	var toggle_action := "expand" if is_collapsed else "collapse"

	# Build message content.
	# Keep stack-trace links outside the row-level toggle URL so expanded traces can still
	# open files instead of being swallowed by a nested expand/collapse URL.
	var primary_message_content := "[color=%s]%s[/color]%s" % [color, text, extra_indicator]
	var stack_trace_content := ""
	if not is_collapsed and formatted_stack_trace != "":
		stack_trace_content = "\n" + formatted_stack_trace

	# Build cell contents
	var timestamp_content := "[color=dim_gray]%s[/color]" % timestamp

	# Instance content (shown before channel if from a remote instance)
	var instance_content := ""
	if instance_name != "":
		instance_content = "[color=dim_gray][%s][/color] " % instance_name

	# Channel content with optional collapse count badge
	var channel_content := ""
	if channel != "":
		channel_content = "[color=%s][%s][/color]" % [color, channel]

	var count_content := ""
	if collapse_count > 0:
		var space := " " if channel_content != "" else ""
		count_content = "%s[color=%s][%d][/color]" % [space, color, collapse_count]

	# Wrap row controls in URL if expandable (URLs must wrap text, not tables)
	if has_expandable and entry_id >= 0:
		var url_action := "%s:%d" % [toggle_action, entry_id]
		timestamp_content = "[url=%s]%s[/url]" % [url_action, timestamp_content]
		if instance_content != "":
			instance_content = "[url=%s]%s[/url]" % [url_action, instance_content]
		if channel_content != "":
			channel_content = "[url=%s]%s[/url]" % [url_action, channel_content]
		if count_content != "":
			count_content = "[url=%s]%s[/url]" % [url_action, count_content]
		primary_message_content = "[url=%s]%s[/url]" % [url_action, primary_message_content]

	var metadata_content := "%s%s%s" % [instance_content, channel_content, count_content]
	var message_content := "%s%s" % [primary_message_content, stack_trace_content]

	# Build single row: [timestamp] [instance + channel + count] [message]
	# The message cell must be the flexible column or RichTextLabel wrapping never has room to work.
	return "[table=3][cell expand=0 shrink=true]%s [/cell][cell expand=0 shrink=true]%s[/cell][cell expand=1 shrink=false]%s[/cell][/table]" % [timestamp_content, metadata_content, message_content]


## Parse and format a single stack frame line
## Returns formatted "function (filename:line)" with clickable URL, or empty string if no match
func _format_single_stack_frame(line: String) -> String:
	var stripped := line.strip_edges()
	if stripped.is_empty():
		return ""
	# Skip header lines
	if stripped.begins_with("GDScript backtrace"):
		return ""
	# Regex to match stack frame lines like "    [0] function_name (res://path/file.gd:123)"
	var regex := RegEx.new()
	regex.compile("\\[\\d+\\]\\s+([^\\(]+)\\s*\\(([^\\)]+)\\)")
	var match_result := regex.search(line)
	if match_result:
		var function_name := match_result.get_string(1).strip_edges()
		var location := match_result.get_string(2)  # e.g., "res://path/file.gd:123"
		var last_colon := location.rfind(":")
		if last_colon != -1:
			var file_path := location.substr(0, last_colon)
			var line_num := location.substr(last_colon + 1)
			var file_name := file_path.get_file()
			var display_text := "%s (%s:%s)" % [function_name, file_name, line_num]
			return "[url=open_file:%s:%s][color=dim_gray]%s[/color][/url]" % [file_path, line_num, display_text]
	return ""


func _get_top_stack_frame(stack_trace: String) -> String:
	if stack_trace.is_empty():
		return ""
	var lines := stack_trace.split("\n")
	for line in lines:
		var formatted := _format_single_stack_frame(line)
		if not formatted.is_empty():
			return formatted
	return ""


func _format_stack_trace(stack_trace: String) -> String:
	if stack_trace.is_empty():
		return ""
	var lines := stack_trace.split("\n")
	var formatted_lines: PackedStringArray = []
	for line in lines:
		var formatted := _format_single_stack_frame(line)
		if not formatted.is_empty():
			formatted_lines.append(formatted)
	return "\n".join(formatted_lines)


func _is_scrolled_to_bottom() -> bool:
	if not rich_label:
		return true
	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		return true
	# Consider "at bottom" if within 1 pixel of the maximum scroll value
	return scrollbar.value >= scrollbar.max_value - scrollbar.page - 1.0


func _scroll_to_bottom(animated: bool = false) -> void:
	if not rich_label:
		return
	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		return

	if not animated:
		_pending_animated_scroll_to_bottom = false
		if _scroll_to_bottom_tween and is_instance_valid(_scroll_to_bottom_tween):
			_scroll_to_bottom_tween.kill()
			_scroll_to_bottom_tween = null
		scrollbar.value = scrollbar.max_value
		_update_scroll_to_bottom_button_visibility()
		return

	if _pending_animated_scroll_to_bottom:
		return
	_pending_animated_scroll_to_bottom = true
	call_deferred("_scroll_to_bottom_animated_deferred")


func _scroll_to_bottom_animated_deferred() -> void:
	_pending_animated_scroll_to_bottom = false
	if not rich_label:
		return
	var scrollbar := rich_label.get_v_scroll_bar()
	if not scrollbar:
		return

	if _scroll_to_bottom_tween and is_instance_valid(_scroll_to_bottom_tween):
		_scroll_to_bottom_tween.kill()

	_scroll_to_bottom_tween = create_tween()
	_scroll_to_bottom_tween.set_trans(Tween.TRANS_QUAD)
	_scroll_to_bottom_tween.set_ease(Tween.EASE_OUT)
	_scroll_to_bottom_tween.tween_property(scrollbar, "value", scrollbar.max_value, SCROLL_TO_BOTTOM_ANIMATION_DURATION)
	_scroll_to_bottom_tween.finished.connect(_on_scroll_to_bottom_tween_finished)
	_update_scroll_to_bottom_button_visibility()


func _on_scroll_to_bottom_tween_finished() -> void:
	_scroll_to_bottom_tween = null
	_update_scroll_to_bottom_button_visibility()


func _display_entry(entry, animate_auto_scroll: bool = true) -> void:
	if not rich_label:
		return

	# Check if we should auto-scroll after adding content
	var was_at_bottom := _is_scrolled_to_bottom()

	var display_text: String = _get_entry_display_text(entry, _truncate_multiline)

	var is_duplicate := false
	if _collapse_duplicates and _last_displayed_entry != null:
		var last_content := _get_entry_plain_text(_last_displayed_entry)
		var current_content := _get_entry_plain_text(entry)
		is_duplicate = (current_content == last_content
			and entry.level == _last_displayed_entry.level
			and entry.channel == _last_displayed_entry.channel)

	if is_duplicate:
		_last_displayed_count += 1
		_last_displayed_entry.collapse_count = _last_displayed_count
		_last_displayed_entry.timestamp = entry.timestamp

		# Rebuild display using stored BBCode (preserves formatting and URLs)
		rich_label.clear()
		rich_label.append_text(_bbcode_before_last_entry)

		var entry_text := _get_entry_display_text(_last_displayed_entry, _truncate_multiline, _last_displayed_count)
		rich_label.append_text(entry_text + "\n")
	else:
		# Accumulate the previous entry's BBCode before moving to the new entry
		if _last_displayed_entry != null:
			var prev_text: String = _get_entry_display_text(_last_displayed_entry, _truncate_multiline, _last_displayed_count)
			_bbcode_before_last_entry += prev_text + "\n"

		_last_displayed_entry = entry
		_last_displayed_count = 1
		rich_label.append_text(display_text + "\n")

	entry.visible = true

	# Only auto-scroll if we were already at the bottom
	if was_at_bottom:
		_scroll_to_bottom(animate_auto_scroll)
	else:
		_update_scroll_to_bottom_button_visibility()


func _rebuild_display() -> void:
	if not rich_label:
		return

	var was_at_bottom := _is_scrolled_to_bottom()
	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	var welcome_message := _get_welcome_message()
	var bbcode_parts := PackedStringArray([welcome_message])
	var collapsed_entry = null
	var collapsed_content := ""
	var collapsed_count := 0

	for entry in _get_log_entries():
		_ensure_channel_exists(entry.channel)
		if not _update_stats_for_entry(entry):
			entry.visible = false
			continue

		entry.visible = true
		var entry_content := _get_entry_plain_text(entry)
		var is_duplicate: bool = (
			_collapse_duplicates
			and collapsed_entry != null
			and entry_content == collapsed_content
			and entry.level == collapsed_entry.level
			and entry.channel == collapsed_entry.channel
		)
		if is_duplicate:
			collapsed_count += 1
			collapsed_entry.collapse_count = collapsed_count
			collapsed_entry.timestamp = entry.timestamp
			continue

		if collapsed_entry != null:
			bbcode_parts.append(_get_entry_display_text(collapsed_entry, _truncate_multiline, collapsed_count) + "\n")
		collapsed_entry = entry
		collapsed_content = entry_content
		collapsed_count = 1

	_bbcode_before_last_entry = "".join(bbcode_parts)
	if collapsed_entry != null:
		bbcode_parts.append(_get_entry_display_text(collapsed_entry, _truncate_multiline, collapsed_count) + "\n")
		_last_displayed_entry = collapsed_entry
		_last_displayed_count = collapsed_count

	rich_label.clear()
	rich_label.append_text("".join(bbcode_parts))

	_update_sidebar_stats()
	if was_at_bottom:
		_scroll_to_bottom(false)
	else:
		_update_scroll_to_bottom_button_visibility()
	display_rebuilt.emit()


# =============================================================================
# STATISTICS
# =============================================================================

func _update_stats_for_entry(entry) -> bool:
	var level_mode = _get_level_visibility(entry.level)
	var channel_mode = _get_channel_visibility(entry.channel)
	var instance_mode = _get_instance_visibility(entry.session_id)

	var level_stats: FilterStats = _level_stats.get(entry.level)
	var channel_stats: FilterStats = _channel_stats.get(entry.channel)

	if level_stats == null:
		level_stats = FilterStats.new()
		_level_stats[entry.level] = level_stats
	if channel_stats == null:
		channel_stats = FilterStats.new()
		_channel_stats[entry.channel] = channel_stats

	var hidden_by_search := false
	if _search_filter != "":
		var search_text := _get_entry_plain_text(entry).to_lower()
		hidden_by_search = not search_text.contains(_search_filter)

	# Entry is shown only if all filters allow it
	var is_shown: bool = (level_mode == VisibilityMode.SHOWN) and (channel_mode == VisibilityMode.SHOWN) and (instance_mode == VisibilityMode.SHOWN) and not hidden_by_search

	# Note: We no longer track off_count here. Logs that exist but are hidden by OFF mode
	# are just hidden, not "off". The off_count is now only for logs that were never created
	# because they failed can_log() - tracked separately via rejected counts.
	if is_shown:
		level_stats.shown_count += 1
		channel_stats.shown_count += 1
	else:
		level_stats.hidden_count += 1
		channel_stats.hidden_count += 1
	return is_shown


func _reset_stats() -> void:
	for level in _level_stats:
		_level_stats[level].reset()
	for channel in _channel_stats:
		_channel_stats[channel].reset()


func _update_sidebar_stats() -> void:
	if _sidebar:
		for level in _level_stats:
			var stats: FilterStats = _level_stats[level]
			var rejected_count := _get_rejected_level_count(level)
			_sidebar.set_level_stats(level, stats.shown_count, stats.hidden_count, rejected_count)

		for channel in _channel_stats:
			var stats: FilterStats = _channel_stats[channel]
			# Get rejected count from provider (logs that were never created due to can_log failing)
			var rejected_count := 0
			if _rejected_channel_count_provider.is_valid():
				rejected_count = _rejected_channel_count_provider.call(channel)
			_sidebar.set_channel_stats(channel, stats.shown_count, stats.hidden_count, rejected_count)

	_refresh_collapsed_level_buttons()


# =============================================================================
# VISIBILITY CONTROL
# =============================================================================

func can_log(level: int, channel: String = "") -> bool:
	if _get_level_visibility(level) == VisibilityMode.OFF:
		return false
	if channel != "" and _get_channel_visibility(channel) == VisibilityMode.OFF:
		return false
	return true


func _apply_level_visibility_change(level: int, mode: int, emit_change_signal: bool, sync_sidebar_state: bool = false) -> void:
	_set_level_visibility(level, mode)
	if sync_sidebar_state and _sidebar:
		_sidebar.set_level_visibility(level, mode)
	_save_filter_settings()
	_rebuild_display()
	if emit_change_signal:
		level_visibility_changed.emit(level, mode)


func set_level_visibility(level: int, mode: int) -> void:
	_apply_level_visibility_change(level, mode, false, true)


func set_channel_visibility(channel: String, mode: int) -> void:
	_set_channel_visibility(channel, mode)
	_save_filter_settings()
	_rebuild_display()


# =============================================================================
# SIDEBAR SIGNAL HANDLERS
# =============================================================================

func _on_level_visibility_changed(level: int, mode: int) -> void:
	_apply_level_visibility_change(level, mode, true, false)


func _on_channel_visibility_changed(channel: String, mode: int) -> void:
	_set_channel_visibility(channel, mode)
	_save_filter_settings()
	_rebuild_display()

	channel_visibility_changed.emit(channel, mode)


func _on_channel_deleted(channel: String) -> void:
	# Remove from local tracking if using local visibility
	if not _channel_visibility_getter.is_valid():
		_channel_visibility.erase(channel)
	_known_channels.erase(channel)
	_channel_stats.erase(channel)
	_save_filter_settings()
	_rebuild_display()

	channel_deleted.emit(channel)


func _on_setting_changed(setting_name: String, value: bool) -> void:
	match setting_name:
		"collapse_duplicates":
			_collapse_duplicates = value
			_save_filter_settings()
			_rebuild_display()
		"wrap_text":
			_wrap_text = value
			if rich_label:
				rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _wrap_text else TextServer.AUTOWRAP_OFF
			_save_filter_settings()
		"truncate_multiline":
			_truncate_multiline = value
			_save_filter_settings()
			_rebuild_display()
		_:
			_custom_setting_values[setting_name] = value
			_save_filter_settings()
			_on_custom_setting_changed(setting_name, value)


func _on_sidebar_toggle(toggled_on: bool) -> void:
	_set_sidebar_visible(toggled_on)


# =============================================================================
# LOG META CLICK HANDLING
# =============================================================================

func _on_log_meta_clicked(meta: Variant) -> void:
	var meta_str := str(meta)
	if meta_str.begins_with("expand:") or meta_str.begins_with("collapse:"):
		var parts := meta_str.split(":")
		if parts.size() >= 2:
			var entry_id := int(parts[1])
			_toggle_entry_expansion(entry_id)
	elif meta_str.begins_with("open_file:"):
		var content := meta_str.substr(len("open_file:"))
		var last_colon := content.rfind(":")
		if last_colon != -1:
			var file_path := content.substr(0, last_colon)
			var line_num := int(content.substr(last_colon + 1))
			_open_file_in_editor(file_path, line_num)


func _open_file_in_editor(file_path: String, line: int) -> void:
	if Engine.is_editor_hint():
		var script := load(file_path)
		if script:
			# EditorInterface is editor-only; look up by name so exported
			# game builds don't fail to parse this script.
			Engine.get_singleton("EditorInterface").edit_script(script, line)
		else:
			push_warning("Could not load script: %s" % file_path)
	else:
		var absolute_path := ProjectSettings.globalize_path(file_path)
		OS.shell_open(absolute_path)


# =============================================================================
# CLEAR LOGS
# =============================================================================

func _clear_logs() -> void:
	_entry_plain_text_cache.clear()
	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	_bbcode_before_last_entry = _get_welcome_message()
	if rich_label:
		rich_label.clear()
		rich_label.append_text(_get_welcome_message())
		_update_scroll_to_bottom_button_visibility()
	if _sidebar:
		_sidebar.reset_stats()
	_refresh_collapsed_level_buttons()
	_on_cleared()


# =============================================================================
# PERSISTENCE
# =============================================================================

func _save_filter_settings() -> void:
	if _ui_update_batch_depth > 0:
		_ui_update_settings_dirty = true
		return
	var settings_file := _get_settings_file()
	if settings_file.is_empty():
		return
	_debug_filter_settings_save_count += 1

	var config := ConfigFile.new()
	config.load(settings_file)

	# Save level visibility - use local dictionary or query provider for known levels
	for level in LOG_LEVELS:
		config.set_value("levels", str(level), _get_level_visibility(level))

	# Save channel visibility
	for channel in _known_channels:
		var key: String = channel if channel != "" else "__general__"
		config.set_value("channels", key, _get_channel_visibility(channel))

	config.set_value("settings", "collapse_duplicates", _collapse_duplicates)
	config.set_value("settings", "wrap_text", _wrap_text)
	config.set_value("settings", "truncate_multiline", _truncate_multiline)
	config.set_value("settings", "sidebar_visible", _sidebar_visible)
	for setting in _custom_settings:
		var setting_name := str(setting.get("name", ""))
		if setting_name.is_empty():
			continue
		config.set_value("settings", setting_name, bool(_custom_setting_values.get(setting_name, setting.get("default", false))))
	var persistent_pins: Array[String] = []
	var persistent_pin_corners: Dictionary = {}
	for pinned_address in _pinned_display_variables:
		if _transient_pinned_display_variables.has(pinned_address):
			continue
		persistent_pins.append(pinned_address)
		persistent_pin_corners[pinned_address] = _pinned_display_variable_corners.get(pinned_address, PINNED_OVERLAY_CORNER_TOP_LEFT)
	config.set_value("display_variables", "pinned", persistent_pins)
	config.set_value("display_variables", "pinned_corners", persistent_pin_corners)
	config.set_value("display_variables", "pinned_visible", _pinned_overlay_visible)

	var serialized_pin_overlays := {}
	for overlay_name in _saved_pin_overlays:
		var overlay_key := str(overlay_name).strip_edges()
		if overlay_key.is_empty():
			continue

		var serialized_overlay_addresses: Array = []
		var serialized_overlay_seen: Dictionary = {}
		var overlay_addresses = _saved_pin_overlays[overlay_name]
		if overlay_addresses is Array:
			for address_entry in overlay_addresses:
				var address_str := ""
				var corner := PINNED_OVERLAY_CORNER_TOP_LEFT
				if address_entry is Dictionary:
					address_str = str((address_entry as Dictionary).get("address", ""))
					corner = _normalize_pin_corner(str((address_entry as Dictionary).get("corner", PINNED_OVERLAY_CORNER_TOP_LEFT)))
				else:
					address_str = str(address_entry)
				if address_str.is_empty() or serialized_overlay_seen.has(address_str):
					continue
				serialized_overlay_seen[address_str] = true
				serialized_overlay_addresses.append({
					"address": address_str,
					"corner": corner,
				})

		serialized_pin_overlays[overlay_key] = serialized_overlay_addresses
	config.set_value("display_variables", "pin_overlays", serialized_pin_overlays)

	_save_custom_settings(config)

	config.save(settings_file)


func _load_filter_settings() -> void:
	var settings_file := _get_settings_file()
	if settings_file.is_empty():
		return

	var config := ConfigFile.new()
	if config.load(settings_file) != OK:
		return

	if config.has_section("levels"):
		for key in config.get_section_keys("levels"):
			_set_level_visibility(int(key), config.get_value("levels", key))

	if config.has_section("channels"):
		for key in config.get_section_keys("channels"):
			var channel := "" if key == "__general__" else key
			_set_channel_visibility(channel, config.get_value("channels", key))
			if channel not in _known_channels:
				_known_channels.append(channel)

	if config.has_section("settings"):
		_collapse_duplicates = config.get_value("settings", "collapse_duplicates", false)
		_wrap_text = config.get_value("settings", "wrap_text", false)
		_truncate_multiline = config.get_value("settings", "truncate_multiline", true)
		_sidebar_visible = config.get_value("settings", "sidebar_visible", false)
		for setting in _custom_settings:
			var setting_name := str(setting.get("name", ""))
			if setting_name.is_empty():
				continue
			_custom_setting_values[setting_name] = bool(config.get_value("settings", setting_name, setting.get("default", false)))

	if config.has_section("display_variables"):
		var pinned_addresses = config.get_value("display_variables", "pinned", [])
		_transient_pinned_display_variables.clear()
		_pinned_display_variables.clear()
		_pinned_display_variable_corners.clear()
		if pinned_addresses is Array:
			for address in pinned_addresses:
				var address_str := str(address)
				if address_str.is_empty() or _pinned_display_variables.has(address_str):
					continue
				if address_str in RETIRED_PIN_ADDRESSES:
					continue
				_pinned_display_variables.append(address_str)
				_pinned_display_variable_corners[address_str] = PINNED_OVERLAY_CORNER_TOP_LEFT
		var pinned_corners = config.get_value("display_variables", "pinned_corners", {})
		if pinned_corners is Dictionary:
			for address in _pinned_display_variables:
				_pinned_display_variable_corners[address] = _normalize_pin_corner(str((pinned_corners as Dictionary).get(address, _pinned_display_variable_corners.get(address, PINNED_OVERLAY_CORNER_TOP_LEFT))))
		_pinned_overlay_visible = bool(config.get_value("display_variables", "pinned_visible", true))

		_saved_pin_overlays.clear()
		var pin_overlays = config.get_value("display_variables", "pin_overlays", {})
		if pin_overlays is Dictionary:
			for overlay_name in pin_overlays:
				var overlay_key := str(overlay_name).strip_edges()
				if overlay_key.is_empty():
					continue

				var overlay_addresses: Array = []
				var stored_overlay_addresses = (pin_overlays as Dictionary)[overlay_name]
				if stored_overlay_addresses is Array:
					for address_entry in stored_overlay_addresses:
						var address_str := ""
						var corner := PINNED_OVERLAY_CORNER_TOP_LEFT
						if address_entry is Dictionary:
							address_str = str((address_entry as Dictionary).get("address", ""))
							corner = _normalize_pin_corner(str((address_entry as Dictionary).get("corner", PINNED_OVERLAY_CORNER_TOP_LEFT)))
						else:
							address_str = str(address_entry)
						if address_str.is_empty() or address_str in RETIRED_PIN_ADDRESSES:
							continue
						var duplicate := false
						for existing_entry in overlay_addresses:
							if existing_entry is Dictionary and str((existing_entry as Dictionary).get("address", "")) == address_str:
								duplicate = true
								break
						if duplicate:
							continue
						overlay_addresses.append({
							"address": address_str,
							"corner": corner,
						})

				_saved_pin_overlays[overlay_key] = overlay_addresses

	_load_custom_settings(config)


func _save_custom_settings(_config: ConfigFile) -> void:
	_config.set_value("command_palette", "height", _command_palette_height_override)
	for input_method in [INPUT_METHOD_KEYBOARD, INPUT_METHOD_CONTROLLER, INPUT_METHOD_TOUCH]:
		for target in [RENDER_SCALE_TARGET_LOG, RENDER_SCALE_TARGET_COMMAND_PALETTE, RENDER_SCALE_TARGET_PINNED_VARIABLES]:
			_config.set_value("render_scale", "%s/%s" % [input_method, target], get_render_scale_percent(target, input_method))


func _load_custom_settings(_config: ConfigFile) -> void:
	# Stored raw; clamped on use, since the window and line edit may not be laid out yet.
	_command_palette_height_override = maxf(0.0, float(_config.get_value("command_palette", "height", 0.0)))

	if not _config.has_section("render_scale"):
		return
	for input_method in [INPUT_METHOD_KEYBOARD, INPUT_METHOD_CONTROLLER, INPUT_METHOD_TOUCH]:
		var method_settings: Dictionary = _render_scale_settings.get(input_method, {}).duplicate()
		for target in [RENDER_SCALE_TARGET_LOG, RENDER_SCALE_TARGET_COMMAND_PALETTE, RENDER_SCALE_TARGET_PINNED_VARIABLES]:
			var key := "%s/%s" % [input_method, target]
			method_settings[target] = _normalize_render_scale_percent(float(_config.get_value(
				"render_scale",
				key,
				_get_default_render_scale_percent(input_method, target)
			)))
		_render_scale_settings[input_method] = method_settings


func _sync_sidebar_state() -> void:
	if not _sidebar:
		return

	for level in LOG_LEVELS:
		_sidebar.set_level_visibility(level, _get_level_visibility(level))

	for channel in _known_channels:
		_sidebar.add_channel(channel)
		_sidebar.set_channel_visibility(channel, _get_channel_visibility(channel))

	_sidebar.set_setting("collapse_duplicates", _collapse_duplicates)
	_sidebar.set_setting("wrap_text", _wrap_text)
	_sidebar.set_setting("truncate_multiline", _truncate_multiline)
	for setting in _custom_settings:
		var setting_name := str(setting.get("name", ""))
		if setting_name.is_empty():
			continue
		_sidebar.set_setting(setting_name, bool(_custom_setting_values.get(setting_name, setting.get("default", false))))
	_refresh_collapsed_level_buttons()


func _append_unique_address(addresses: Array[String], address: String) -> void:
	if address.is_empty() or addresses.has(address):
		return
	addresses.append(address)


func _get_base_registered_addresses() -> Array[String]:
	if not _command_catalog_dirty:
		return _base_registered_addresses_cache.duplicate()

	var addresses: Array[String] = []
	for command in _get_commands():
		_append_unique_address(addresses, str(command))
	for address in _get_display_variables():
		_append_unique_address(addresses, str(address))
	for widget_path in _get_widgets():
		_append_unique_address(addresses, str(widget_path))
	_base_registered_addresses_cache = addresses.duplicate()
	_command_catalog_dirty = false
	return addresses


func _get_default_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if _default_menu_hierarchy_cache.has(normalized_path):
		var cached_addresses: Array[String] = []
		for cached_address in _default_menu_hierarchy_cache[normalized_path]:
			cached_addresses.append(str(cached_address))
		return cached_addresses

	var addresses: Array[String] = []
	var base_addresses := _get_base_registered_addresses()
	if normalized_path.is_empty():
		for address in base_addresses:
			_append_unique_address(addresses, address)
		_default_menu_hierarchy_cache[normalized_path] = addresses.duplicate()
		return addresses

	var path_prefix := normalized_path + "/"
	for base_address in base_addresses:
		if str(base_address).begins_with(path_prefix):
			_append_unique_address(addresses, str(base_address))

	if _get_command_data_direct(normalized_path) != null:
		for option_address in _get_command_option_subcommand_addresses(normalized_path, 0):
			_append_unique_address(addresses, option_address)

	if _is_pinnable_item_direct(normalized_path):
		for pin_option_address in _get_pin_action_subcommand_addresses(normalized_path):
			_append_unique_address(addresses, pin_option_address)

	if normalized_path.ends_with("/pin"):
		var pin_parent_address := normalized_path.trim_suffix("/pin")
		if _is_pinnable_item_direct(pin_parent_address):
			for corner in PINNED_OVERLAY_CORNERS:
				_append_unique_address(addresses, "%s/%s" % [normalized_path, corner])

	_default_menu_hierarchy_cache[normalized_path] = addresses.duplicate()
	return addresses


func _has_widget_direct(address: String) -> bool:
	return _get_widgets().has(address)


func _has_widget(address: String) -> bool:
	return _has_widget_direct(_resolve_alias_command_path(address))


func _get_widget_data(address: String) -> Variant:
	return _get_widgets().get(_resolve_alias_command_path(address), null)


func _get_widget_default_minimum_size(widget: Variant) -> Vector2:
	if widget is LogotWidget:
		return (widget as LogotWidget).default_minimum_size
	if widget is Dictionary:
		var min_size = (widget as Dictionary).get("default_minimum_size", Vector2.ZERO)
		if min_size is Vector2:
			return min_size
	return Vector2.ZERO


func _is_render_texture_widget_data(widget: Variant) -> bool:
	return widget is Dictionary and str((widget as Dictionary).get("widget_type", "")).strip_edges().to_lower() == "render_texture"


func _is_render_texture_widget_path(address: String) -> bool:
	var resolved_address := _resolve_alias_command_path(address.strip_edges())
	if resolved_address.is_empty():
		return false
	return _is_render_texture_widget_data(_get_widgets().get(resolved_address, null))


func _create_widget_instance(address: String, mode: String, corner: String = PINNED_OVERLAY_CORNER_TOP_LEFT) -> Control:
	var resolved_address := _resolve_alias_command_path(address)
	var widget = _get_widgets().get(resolved_address, null)
	if widget == null:
		return null

	if _is_render_texture_widget_data(widget):
		var render_widget := RenderTextureWidget.new()
		var min_size := _get_widget_default_minimum_size(widget)
		render_widget.setup(widget as Dictionary, min_size)
		render_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if render_widget.has_method("configure_logot_widget"):
			render_widget.call("configure_logot_widget", resolved_address, mode, _normalize_pin_corner(corner))
		return render_widget

	var scene_or_path: Variant = widget
	if widget is LogotWidget:
		scene_or_path = (widget as LogotWidget).scene_or_path
	elif widget is Dictionary:
		scene_or_path = (widget as Dictionary).get("scene_or_path", null)

	var packed_scene: PackedScene = null
	if scene_or_path is PackedScene:
		packed_scene = scene_or_path as PackedScene
	elif scene_or_path is String:
		var loaded = load(str(scene_or_path))
		if loaded is PackedScene:
			packed_scene = loaded as PackedScene

	if packed_scene == null:
		push_warning("Logot widget '%s' does not reference a valid PackedScene." % resolved_address)
		return null

	var instance = packed_scene.instantiate()
	if not (instance is Control):
		if instance is Node:
			(instance as Node).queue_free()
		push_warning("Logot widget '%s' must instantiate a Control root." % resolved_address)
		return null

	var control := instance as Control
	var min_size := _get_widget_default_minimum_size(widget)
	if min_size.x > 0.0 or min_size.y > 0.0:
		control.custom_minimum_size = min_size
	# Widgets own their own interaction policy. In particular, pinned widgets may
	# expose buttons or pointer-driven controls; forcing IGNORE here makes those
	# controls unreachable through the otherwise passive overlay containers.
	if control.has_method("configure_logot_widget"):
		control.call("configure_logot_widget", resolved_address, mode, _normalize_pin_corner(corner))
	return control


func _logot_widget_refreshes_in_background(widget: Control) -> bool:
	if widget == null or not is_instance_valid(widget):
		return false
	var refresh_value = widget.get("refresh_in_background")
	return bool(refresh_value) if refresh_value != null else false


func _refresh_logot_widget_instance(widget: Control, delta: float, force: bool = false) -> void:
	if widget == null or not is_instance_valid(widget):
		return
	if not widget.is_inside_tree():
		return
	if not widget.has_method("refresh_logot_widget"):
		return
	if not force and not widget.is_visible_in_tree() and not _logot_widget_refreshes_in_background(widget):
		return
	widget.call("refresh_logot_widget", delta)


func _collect_logot_widget_instances(node: Node, out_widgets: Array[Control], seen_instances: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control and (node as Control).has_method("refresh_logot_widget"):
		var instance_id := node.get_instance_id()
		if not seen_instances.has(instance_id):
			seen_instances[instance_id] = true
			out_widgets.append(node as Control)
	for child in node.get_children():
		_collect_logot_widget_instances(child, out_widgets, seen_instances)


func _poll_visible_logot_widgets(delta: float) -> void:
	var widgets: Array[Control] = []
	var seen_instances: Dictionary = {}
	if _render_texture_fullscreen_mode != RENDER_TEXTURE_VIEW_MODE_NONE:
		if _render_texture_fullscreen_address.is_empty() or not _is_render_texture_widget_path(_render_texture_fullscreen_address):
			clear_render_texture_widget_view_mode()
	for row in _pinned_overlay_rows.values():
		if row is Node:
			_collect_logot_widget_instances(row as Node, widgets, seen_instances)
	if _render_texture_fullscreen_root is Node and is_instance_valid(_render_texture_fullscreen_root):
		_collect_logot_widget_instances(_render_texture_fullscreen_root, widgets, seen_instances)
	for column_node in _autocomplete_column_nodes:
		if column_node is Node:
			_collect_logot_widget_instances(column_node as Node, widgets, seen_instances)
	for widget in widgets:
		_refresh_logot_widget_instance(widget, delta)


func _is_widget_pinnable_direct(address: String) -> bool:
	return _has_widget_direct(address)


func _is_pinnable_item_direct(address: String) -> bool:
	return (_has_display_variable_direct(address) and _is_display_variable_pinnable_direct(address)) or _is_widget_pinnable_direct(address)


func _is_pinnable_item(address: String) -> bool:
	return _is_pinnable_item_direct(_resolve_alias_command_path(address))


func _get_available_pinned_display_variables() -> Array[String]:
	var addresses: Array[String] = []
	for address in _pinned_display_variables:
		var address_str := str(address)
		if address_str.is_empty() or not _is_pinnable_item_direct(address_str) or addresses.has(address_str):
			continue
		addresses.append(address_str)
	addresses.sort()
	return addresses


func _encode_pins_view_alias_token(address: String) -> String:
	return address.uri_encode()


func _decode_pins_view_alias_token(token: String) -> String:
	return token.uri_decode()


func _get_pins_alias_path(address: String) -> String:
	return PINS_ALIAS_PREFIX + _encode_pins_view_alias_token(address)


func _resolve_pins_view_alias_token_target(token: String) -> String:
	if token.is_empty():
		return ""
	var decoded_address := _decode_pins_view_alias_token(token)
	if decoded_address.is_empty():
		return ""
	for address in _get_available_pinned_display_variables():
		if address == decoded_address:
			return decoded_address
	return ""


func _resolve_pins_view_alias_target_path(alias_remainder: String) -> String:
	var normalized_remainder := alias_remainder.strip_edges().trim_prefix("/")
	if normalized_remainder.is_empty():
		return ""

	var first_separator := normalized_remainder.find("/")
	var alias_token := normalized_remainder if first_separator == -1 else normalized_remainder.substr(0, first_separator)
	var token_suffix := "" if first_separator == -1 else normalized_remainder.substr(first_separator)
	var token_target := _resolve_pins_view_alias_token_target(alias_token)
	if not token_target.is_empty():
		return token_target + token_suffix

	var best_match := ""
	for address in _get_available_pinned_display_variables():
		if normalized_remainder == address or normalized_remainder.begins_with(address + "/"):
			if address.length() > best_match.length():
				best_match = address

	if best_match.is_empty():
		return ""
	return best_match + normalized_remainder.substr(best_match.length())


func _resolve_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if _get_command_data_direct(normalized_path) != null or not normalized_path.begins_with(PINS_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return normalized_path

	var alias_target := _resolve_pins_view_alias_target_path(alias_remainder)
	return normalized_path if alias_target.is_empty() else alias_target


func _get_display_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if _get_command_data_direct(normalized_path) != null or not normalized_path.begins_with(PINS_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return normalized_path

	var first_separator := alias_remainder.find("/")
	var alias_token := alias_remainder if first_separator == -1 else alias_remainder.substr(0, first_separator)
	var token_suffix := "" if first_separator == -1 else alias_remainder.substr(first_separator)
	var token_target := _resolve_pins_view_alias_token_target(alias_token)
	if token_target.is_empty():
		return normalized_path
	return PINS_ALIAS_PREFIX + token_target + token_suffix


func _get_internal_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if _get_command_data_direct(normalized_path) != null or not normalized_path.begins_with(PINS_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return normalized_path

	var first_separator := alias_remainder.find("/")
	var alias_token := alias_remainder if first_separator == -1 else alias_remainder.substr(0, first_separator)
	if not _resolve_pins_view_alias_token_target(alias_token).is_empty():
		return normalized_path

	var best_match := ""
	for address in _get_available_pinned_display_variables():
		if alias_remainder == address or alias_remainder.begins_with(address + "/"):
			if address.length() > best_match.length():
				best_match = address

	if best_match.is_empty():
		return normalized_path

	var suffix := alias_remainder.substr(best_match.length())
	return PINS_ALIAS_PREFIX + _encode_pins_view_alias_token(best_match) + suffix


func _set_line_edit_command_path(command_path: String, include_trailing_separator: bool) -> void:
	if not line_edit:
		return

	var normalized_path := _get_display_alias_command_path(command_path.strip_edges().trim_suffix("/"))
	if normalized_path.is_empty():
		line_edit.text = "/"
	else:
		line_edit.text = "/" + normalized_path + ("/" if include_trailing_separator else "")
	line_edit.caret_column = line_edit.text.length()


## Repositions a retained command input at its nearest valid ancestor after a
## command changes the catalog. Root is always a valid fallback.
func reconcile_retained_command_path() -> void:
	if not line_edit:
		return

	var input_text := line_edit.text.strip_edges()
	if not input_text.begins_with("/") or input_text.begins_with("//"):
		return
	var input_state := _get_autocomplete_input_state()
	if not _build_tier_matches(
		str(input_state.get("prefix", "")),
		str(input_state.get("query", ""))
	).is_empty():
		return

	var command_path := input_text.substr(1).trim_suffix("/")
	var argument_separator := command_path.find(" ")
	if argument_separator != -1:
		command_path = command_path.substr(0, argument_separator)
	command_path = _resolve_alias_command_path(command_path)

	var registered_addresses := _get_registered_addresses()
	if _is_registered_command_path_or_parent(command_path, registered_addresses):
		return

	var separator := command_path.rfind("/")
	command_path = command_path.substr(0, separator) if separator != -1 else ""
	while not command_path.is_empty():
		if _is_registered_command_path_or_parent(command_path, registered_addresses):
			_set_line_edit_command_path(command_path, true)
			on_text_changed_autocomplete(line_edit.text)
			return

		var parent_separator := command_path.rfind("/")
		command_path = command_path.substr(0, parent_separator) if parent_separator != -1 else ""

	_set_line_edit_command_path("", false)
	on_text_changed_autocomplete(line_edit.text)


func _is_registered_command_path_or_parent(command_path: String, registered_addresses: Array[String]) -> bool:
	if registered_addresses.has(command_path):
		return true
	for address in registered_addresses:
		if str(address).begins_with(command_path + "/"):
			return true
	return false


func _get_pins_view_dynamic_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	var addresses: Array[String] = []
	if normalized_path != "pins" and not normalized_path.begins_with(PINS_ALIAS_PREFIX):
		return addresses

	for pinned_address in _get_available_pinned_display_variables():
		var alias_path := _get_pins_alias_path(pinned_address)
		if _get_command_data_direct(alias_path) == null:
			_append_unique_address(addresses, alias_path)

	if not normalized_path.begins_with(PINS_ALIAS_PREFIX):
		return addresses

	var alias_remainder := normalized_path.substr(PINS_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return addresses

	var alias_target := _resolve_pins_view_alias_target_path(alias_remainder)
	if alias_target.is_empty():
		return addresses

	var target_children := _get_default_menu_hierarchy_addresses(alias_target)
	var target_prefix := alias_target + "/"
	for target_child in target_children:
		if not str(target_child).begins_with(target_prefix):
			continue
		var suffix := str(target_child).substr(alias_target.length())
		var alias_token := alias_remainder
		var first_separator := alias_remainder.find("/")
		if first_separator != -1:
			alias_token = alias_remainder.substr(0, first_separator)
		_append_unique_address(addresses, PINS_ALIAS_PREFIX + alias_token + suffix)

	return addresses


func _get_dynamic_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	return _get_pins_view_dynamic_menu_hierarchy_addresses(command_path)


func _get_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	var addresses := _get_default_menu_hierarchy_addresses(command_path)
	for dynamic_address in _get_dynamic_menu_hierarchy_addresses(command_path):
		_append_unique_address(addresses, dynamic_address)
	return addresses


func _get_registered_addresses() -> Array[String]:
	return _get_menu_hierarchy_addresses("")


func _normalize_command_group_data(raw_name: Variant, raw_priority: Variant, raw_tint: Variant = Color.TRANSPARENT) -> Dictionary:
	var group_name := str(raw_name).strip_edges()
	var group_priority := int(raw_priority)
	if group_name.is_empty():
		group_priority = 0
	var group_tint := _resolve_display_variable_inline_color(raw_tint)
	return {"name": group_name, "priority": group_priority, "tint": group_tint}


func _normalize_display_variable_items(raw_items: Variant) -> Array[Dictionary]:
	var normalized_items: Array[Dictionary] = []
	if not (raw_items is Array):
		return normalized_items
	for item_variant in raw_items:
		if item_variant is Dictionary:
			var item := item_variant as Dictionary
			var text := str(item.get("text", "")).strip_edges()
			if text.is_empty():
				continue
			var normalized_item: Dictionary = {
				"text": text,
			}
			var item_color := _resolve_display_variable_inline_color(item.get("color", null))
			if item_color.a > 0.0:
				normalized_item["color"] = item_color
			normalized_items.append(normalized_item)
			continue
		var item_text := str(item_variant).strip_edges()
		if item_text.is_empty():
			continue
		normalized_items.append({
			"text": item_text,
		})
	return normalized_items


func _get_command_group_data(command_name: String) -> Dictionary:
	var command_data = _get_command_data(command_name)
	if command_data == null:
		return {"name": "", "priority": 0}
	if command_data is LogotCommand:
		var logot_command := command_data as LogotCommand
		return _normalize_command_group_data(logot_command.group_name, logot_command.group_priority, logot_command.group_tint)
	if command_data is Dictionary:
		var command_dict := command_data as Dictionary
		var nested_group = command_dict.get("group", null)
		if nested_group is Dictionary:
			var group_dict := nested_group as Dictionary
			return _normalize_command_group_data(group_dict.get("name", ""), group_dict.get("priority", 0), group_dict.get("tint", Color.TRANSPARENT))
		return _normalize_command_group_data(command_dict.get("group_name", ""), command_dict.get("group_priority", 0), command_dict.get("group_tint", Color.TRANSPARENT))
	return {"name": "", "priority": 0}


func _get_command_option_group_data(command_name: String) -> Dictionary:
	var command_data = _get_command_data(command_name)
	if command_data == null:
		return {"name": "", "priority": 0}
	if command_data is LogotCommand:
		var logot_command := command_data as LogotCommand
		return _normalize_command_group_data(logot_command.option_group_name, logot_command.option_group_priority, logot_command.option_group_tint)
	if command_data is Dictionary:
		var command_dict := command_data as Dictionary
		var nested_group = command_dict.get("option_group", null)
		if nested_group is Dictionary:
			var group_dict := nested_group as Dictionary
			return _normalize_command_group_data(group_dict.get("name", ""), group_dict.get("priority", 0), group_dict.get("tint", Color.TRANSPARENT))
		return _normalize_command_group_data(command_dict.get("option_group_name", ""), command_dict.get("option_group_priority", 0), command_dict.get("option_group_tint", Color.TRANSPARENT))
	return {"name": "", "priority": 0}


func _get_command_keyboard_shortcut(command_name: String) -> Key:
	var command_data = _get_command_data(command_name)
	if command_data is LogotCommand:
		return (command_data as LogotCommand).keyboard_shortcut
	if command_data is Dictionary:
		var raw_key = (command_data as Dictionary).get("keyboard_shortcut", KEY_NONE)
		if raw_key is int:
			return int(raw_key) as Key
	return KEY_NONE


func _get_command_orderable_data(command_name: String) -> Dictionary:
	var command_data = _get_command_data(command_name)
	if command_data is LogotCommand:
		var command := command_data as LogotCommand
		if not command.orderable_group.is_empty() and command.orderable_object_id != null:
			return {"group": command.orderable_group, "id": command.orderable_object_id, "order": command.orderable_order}
	if command_data is Dictionary:
		var data := command_data as Dictionary
		if not str(data.get("orderable_group", "")).is_empty() and data.has("orderable_object_id"):
			return {"group": str(data.get("orderable_group")), "id": data.get("orderable_object_id"), "order": int(data.get("orderable_order", 0))}
	return {}


func _get_display_variable_group_data(address: String) -> Dictionary:
	var resolved_address := _resolve_alias_command_path(address)
	var display_variable = _get_display_variables().get(resolved_address)
	if display_variable is LogotDisplayVariable:
		var display_variable_object := display_variable as LogotDisplayVariable
		return _normalize_command_group_data(display_variable_object.group_name, display_variable_object.group_priority)
	return {"name": "", "priority": 0}


func _get_widget_group_data(address: String) -> Dictionary:
	var widget = _get_widget_data(address)
	if widget is LogotWidget:
		var logot_widget := widget as LogotWidget
		return _normalize_command_group_data(logot_widget.group_name, logot_widget.group_priority)
	if widget is Dictionary:
		var widget_dict := widget as Dictionary
		return _normalize_command_group_data(widget_dict.get("group_name", ""), widget_dict.get("group_priority", 0))
	return {"name": "", "priority": 0}


func _get_widget_display_label(address: String) -> String:
	var widget = _get_widget_data(address)
	if widget is LogotWidget:
		return (widget as LogotWidget).display_label
	if widget is Dictionary:
		return str((widget as Dictionary).get("display_label", "")).strip_edges()
	return ""


func _get_tier_command_group_data(tier: String) -> Dictionary:
	var cache_key := tier.strip_edges().trim_suffix("/")
	if _tier_command_group_cache.has(cache_key):
		return (_tier_command_group_cache[cache_key] as Dictionary).duplicate()
	var group_data := _calculate_tier_command_group_data(cache_key)
	_tier_command_group_cache[cache_key] = group_data.duplicate()
	return group_data


func _calculate_tier_command_group_data(tier: String) -> Dictionary:
	var resolved_tier := _resolve_alias_command_path(tier)
	if _is_command_option_subcommand_tier(resolved_tier):
		var option_command_name := resolved_tier.substr(0, resolved_tier.rfind("/"))
		var option_group := _get_command_option_group_data(option_command_name)
		if not str(option_group.get("name", "")).strip_edges().is_empty() or (option_group.get("tint", Color.TRANSPARENT) as Color).a > 0.0:
			return option_group
	var direct_group := _get_command_group_data(resolved_tier)
	var direct_group_name := str(direct_group.get("name", "")).strip_edges()
	if not direct_group_name.is_empty() or (direct_group.get("tint", Color.TRANSPARENT) as Color).a > 0.0:
		return direct_group
	var display_variable_group := _get_display_variable_group_data(resolved_tier)
	var display_variable_group_name := str(display_variable_group.get("name", "")).strip_edges()
	if not display_variable_group_name.is_empty():
		return display_variable_group
	var widget_group := _get_widget_group_data(resolved_tier)
	var widget_group_name := str(widget_group.get("name", "")).strip_edges()
	if not widget_group_name.is_empty():
		return widget_group
	return {"name": "", "priority": 0}


func _build_tier_match_data(tier_text: String, score: int, prefix: String) -> Dictionary:
	var has_children := false
	for address in _get_menu_hierarchy_addresses(tier_text):
		if str(address).begins_with(tier_text + "/"):
			has_children = true
			break

	if not has_children and not _get_command_option_subcommand_addresses(tier_text, 0).is_empty():
		has_children = true
	if not has_children and not _get_pin_action_subcommand_addresses(tier_text).is_empty():
		has_children = true
	if not has_children and _is_setget_command_name(tier_text):
		has_children = true
	if not has_children and _is_text_input_command_path(tier_text):
		has_children = true

	var has_option_command := _is_command_option_subcommand_tier(tier_text) or _is_display_variable_pin_action_subcommand_tier(tier_text) or _is_text_input_option_subcommand_tier(tier_text)
	var resolved_tier := _resolve_alias_command_path(tier_text)
	var has_direct_command := _get_commands().has(resolved_tier)
	var has_widget := _has_widget_direct(resolved_tier)
	var tier_label_override := ""
	if prefix == PINS_ALIAS_PREFIX and _get_command_data_direct(tier_text) == null and tier_text.begins_with(PINS_ALIAS_PREFIX):
		var alias_token := tier_text.substr(PINS_ALIAS_PREFIX.length())
		var token_target := _resolve_pins_view_alias_token_target(alias_token)
		if not token_target.is_empty():
			tier_label_override = token_target

	var match_data := {
		"tier": tier_text,
		"score": score,
		"has_children": has_children,
		"has_command": has_direct_command or has_option_command or has_widget,
		"has_display_variable": _has_display_variable(tier_text),
		"has_widget": has_widget,
		"disabled": _is_command_path_disabled(tier_text),
		"keyboard_shortcut": _get_command_keyboard_shortcut(resolved_tier),
	}
	var orderable_data := _get_command_orderable_data(resolved_tier)
	if not orderable_data.is_empty():
		match_data["draggable"] = true
		match_data["orderable_group"] = orderable_data.get("group")
		match_data["orderable_object_id"] = orderable_data.get("id")
		match_data["display_order"] = int(orderable_data.get("order", 0))
	if not tier_label_override.is_empty():
		match_data["tier_label_override"] = tier_label_override

	var command_group := _get_tier_command_group_data(tier_text)
	var group_name := str(command_group.get("name", "")).strip_edges()
	var group_tint = command_group.get("tint", Color.TRANSPARENT)
	if not group_name.is_empty():
		match_data["group_name"] = group_name
		match_data["group_priority"] = int(command_group.get("priority", 0))
	if group_tint is Color and (group_tint as Color).a > 0.0:
		match_data["group_tint"] = group_tint
	if (tier_text == "pins" and not prefix.is_empty()) or not tier_label_override.is_empty():
		match_data["group_name"] = PINNED_COMMAND_GROUP_NAME
		match_data["group_priority"] = PINNED_COMMAND_GROUP_PRIORITY

	return match_data


func _merge_tier_match(matches: Array[Dictionary], candidate: Dictionary) -> void:
	var candidate_tier := str(candidate.get("tier", ""))
	if candidate_tier.is_empty():
		return

	for match_index in range(matches.size()):
		var existing_match := matches[match_index]
		if str(existing_match.get("tier", "")) != candidate_tier:
			continue

		existing_match["score"] = maxi(int(existing_match.get("score", 0)), int(candidate.get("score", 0)))
		existing_match["has_children"] = bool(existing_match.get("has_children", false)) or bool(candidate.get("has_children", false))
		existing_match["has_command"] = bool(existing_match.get("has_command", false)) or bool(candidate.get("has_command", false))
		existing_match["has_display_variable"] = bool(existing_match.get("has_display_variable", false)) or bool(candidate.get("has_display_variable", false))
		existing_match["has_widget"] = bool(existing_match.get("has_widget", false)) or bool(candidate.get("has_widget", false))

		var candidate_group_name := str(candidate.get("group_name", "")).strip_edges()
		if not candidate_group_name.is_empty():
			var existing_group_name := str(existing_match.get("group_name", "")).strip_edges()
			var existing_group_priority := int(existing_match.get("group_priority", 0))
			var candidate_group_priority := int(candidate.get("group_priority", 0))
			if existing_group_name.is_empty() or candidate_group_priority < existing_group_priority:
				existing_match["group_name"] = candidate_group_name
				existing_match["group_priority"] = candidate_group_priority
				if candidate.get("group_tint", null) is Color:
					existing_match["group_tint"] = candidate.get("group_tint")

		var candidate_label_override := str(candidate.get("tier_label_override", "")).strip_edges()
		if not candidate_label_override.is_empty():
			existing_match["tier_label_override"] = candidate_label_override

		matches[match_index] = existing_match
		return

	matches.append(candidate)


func _sort_tier_matches(matches: Array[Dictionary], apply_group_sorting: bool) -> void:
	matches.sort_custom(func(a, b):
		if apply_group_sorting:
			var group_priority_a := int(a.get("group_priority", 0))
			var group_priority_b := int(b.get("group_priority", 0))
			if group_priority_a != group_priority_b:
				return group_priority_a < group_priority_b
			var group_name_a := str(a.get("group_name", "")).strip_edges()
			var group_name_b := str(b.get("group_name", "")).strip_edges()
			if group_name_a != group_name_b:
				return group_name_a.nocasecmp_to(group_name_b) < 0

		var score_a := int(a.get("score", 0))
		var score_b := int(b.get("score", 0))
		if score_a != score_b:
			return score_a < score_b
		if a.has("display_order") or b.has("display_order"):
			var order_a := int(a.get("display_order", 0))
			var order_b := int(b.get("display_order", 0))
			if order_a != order_b:
				return order_a < order_b

		return str(a.get("tier", "")).nocasecmp_to(str(b.get("tier", ""))) < 0
	)


func _has_display_variable_direct(address: String) -> bool:
	return _get_display_variables().has(address)


func _has_display_variable(address: String) -> bool:
	return _has_display_variable_direct(_resolve_alias_command_path(address))


func _is_display_variable_pinnable_direct(address: String) -> bool:
	var display_variable = _get_display_variables().get(address)
	if display_variable is LogotDisplayVariable:
		return bool((display_variable as LogotDisplayVariable).pinnable)
	return display_variable != null


func _get_display_variable_value(address: String) -> Variant:
	var resolved_address := _resolve_alias_command_path(address)
	var display_variable = _get_display_variables().get(resolved_address)
	if display_variable == null:
		return null

	if display_variable is LogotDisplayVariable:
		if display_variable.getter.is_valid():
			return display_variable.getter.call()
	elif display_variable is Callable:
		var getter := display_variable as Callable
		if getter.is_valid():
			return getter.call()

	return null


func _get_display_variable_items(address: String) -> Array[Dictionary]:
	var resolved_address := _resolve_alias_command_path(address)
	var display_variable = _get_display_variables().get(resolved_address)
	if display_variable is LogotDisplayVariable:
		var display_variable_object := display_variable as LogotDisplayVariable
		if display_variable_object.items_provider.is_valid():
			var provided_items := _normalize_display_variable_items(display_variable_object.items_provider.call())
			if not provided_items.is_empty():
				return provided_items

	var value: Variant = _get_display_variable_value(address)
	var text := _get_command_option_label_for_value(address, value, 0)
	if text.is_empty():
		text = str(value)
		text = text.replace("\n", " ").replace("\r", " ")
	if text.is_empty():
		return []
	var inline_color := _get_display_variable_inline_color(address)
	var item: Dictionary = {
		"text": text,
	}
	if inline_color.a > 0.0:
		item["color"] = inline_color
	return [item]


func _resolve_display_variable_inline_color(raw_color: Variant) -> Color:
	if raw_color is Color:
		return raw_color as Color
	if raw_color is String:
		var parsed := Color.from_string(str(raw_color), Color.TRANSPARENT)
		return parsed
	return Color.TRANSPARENT


func _get_default_display_variable_inline_color(value: Variant) -> Color:
	if (typeof(value) == TYPE_BOOL and bool(value)) or (value is String and str(value).strip_edges().to_lower() == "true"):
		return Color(0.42, 0.9, 0.42, 1.0)
	return Color.TRANSPARENT


func _get_display_variable_inline_color(address: String) -> Color:
	var custom_color := _get_display_variable_custom_inline_color(address)
	if custom_color.a > 0.0:
		return custom_color
	var value: Variant
	value = _get_display_variable_value(address)
	return _get_default_display_variable_inline_color(value)


func _get_display_variable_custom_inline_color(address: String) -> Color:
	var resolved_address := _resolve_alias_command_path(address)
	var display_variable = _get_display_variables().get(resolved_address)
	if display_variable is LogotDisplayVariable:
		var display_variable_object := display_variable as LogotDisplayVariable
		if display_variable_object.inline_color_provider.is_valid():
			var custom_color := _resolve_display_variable_inline_color(display_variable_object.inline_color_provider.call())
			if custom_color.a > 0.0:
				return custom_color
	return Color.TRANSPARENT


func _get_display_variable_value_text(address: String, single_line: bool = true) -> String:
	var value: Variant
	value = _get_display_variable_value(address)
	var text := str(value)
	if single_line:
		text = text.replace("\n", " ").replace("\r", " ")
	return text


func _get_display_variable_display_text(address: String, single_line: bool = true) -> String:
	var items := _get_display_variable_items(address)
	if items.size() > 1:
		var parts: PackedStringArray = []
		for item in items:
			parts.append(str((item as Dictionary).get("text", "")))
		return " ".join(parts)
	if not items.is_empty():
		var item := items[0] as Dictionary
		var item_text := str(item.get("text", ""))
		if single_line:
			item_text = item_text.replace("\n", " ").replace("\r", " ")
		return item_text

	var value: Variant
	value = _get_display_variable_value(address)
	var option_label := _get_command_option_label_for_value(address, value, 0)
	if not option_label.is_empty():
		return option_label

	var text := str(value)
	if single_line:
		text = text.replace("\n", " ").replace("\r", " ")
	return text


func _is_debug_autocomplete_enabled() -> bool:
	var env_toggle := OS.get_environment(DEBUG_AUTOCOMPLETE_ENV).strip_edges().to_lower()
	if env_toggle in ["1", "true", "yes", "on"]:
		return true
	if env_toggle in ["0", "false", "no", "off"]:
		return false

	if ProjectSettings.has_setting(DEBUG_AUTOCOMPLETE_SETTING):
		return bool(ProjectSettings.get_setting(DEBUG_AUTOCOMPLETE_SETTING))

	return DEBUG_AUTOCOMPLETE_DEFAULT


func _debug_autocomplete(message: String, extra: String = "") -> void:
	if not _is_debug_autocomplete_enabled():
		return

	var input_text := line_edit.text if line_edit else "<no line edit>"
	var active_column := _autocomplete_active_column_index
	var column_count := _autocomplete_column_states.size()
	var history_visible := _is_history_popup_visible()
	var command_visible := _is_command_popup_visible()
	var output := "[logot autocomplete] %s | input='%s' active=%d columns=%d history=%s command=%s" % [
		message,
		input_text,
		active_column,
		column_count,
		str(history_visible),
		str(command_visible),
	]
	if not extra.is_empty():
		output += " | " + extra
	print(output)


func _build_tier_matches(prefix: String, query: String) -> Array[Dictionary]:
	var tier_matches: Dictionary = {}
	var menu_path := prefix.trim_suffix("/")
	var addresses := _get_menu_hierarchy_addresses(menu_path)

	for address in addresses:
		if not address.begins_with(prefix):
			continue

		var next_tier := _get_next_tier(address, prefix)
		if next_tier.is_empty():
			continue

		var tier_segment := next_tier.substr(prefix.length())
		var score := _calculate_match_score(tier_segment, query)
		if score < 0:
			continue

		if not tier_matches.has(next_tier) or tier_matches[next_tier] < score:
			tier_matches[next_tier] = score

	var matches: Array[Dictionary] = []
	for tier in tier_matches:
		var tier_text := str(tier)
		_merge_tier_match(matches, _build_tier_match_data(tier_text, int(tier_matches[tier]), prefix))

	var text_input_match := _build_text_input_tier_match(prefix, query)
	if not text_input_match.is_empty():
		_merge_tier_match(matches, text_input_match)
	if prefix.is_empty():
		var existing_search_index := -1
		for row_index in range(matches.size()):
			if str(matches[row_index].get("tier", "")) == AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND:
				existing_search_index = row_index
				break

		if existing_search_index != -1:
			matches[existing_search_index]["has_children"] = true
		else:
			var search_score := _calculate_match_score(AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND, query)
			if search_score >= 0:
				_merge_tier_match(matches, {
					"tier": AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND,
					"score": search_score,
					"has_children": true,
					"has_command": false,
					"has_display_variable": false,
				})
		for match_index in range(matches.size()):
			if str(matches[match_index].get("tier", "")) in ["console", "pins"]:
				matches[match_index]["group_name"] = "console"
				matches[match_index]["group_priority"] = 0

	_sort_tier_matches(matches, query.is_empty())
	return matches


func _get_all_known_autocomplete_tiers() -> Array[String]:
	if _all_known_autocomplete_tiers_cache_valid:
		return _all_known_autocomplete_tiers_cache.duplicate()

	var tiers: Array[String] = []
	var known_tiers: Dictionary = {}
	var visited_menu_paths: Dictionary = {}
	var queue: Array[String] = [""]
	var queue_index := 0

	while queue_index < queue.size():
		var menu_path: String
		menu_path = str(queue[queue_index])
		queue_index += 1
		if visited_menu_paths.has(menu_path):
			continue
		visited_menu_paths[menu_path] = true

		var prefix := ""
		if not menu_path.is_empty():
			prefix = menu_path + "/"

		for address_variant in _get_menu_hierarchy_addresses(menu_path):
			var address := str(address_variant)
			if not address.begins_with(prefix):
				continue

			var next_tier := _get_next_tier(address, prefix)
			if next_tier.is_empty():
				continue

			if not known_tiers.has(next_tier):
				known_tiers[next_tier] = true
				tiers.append(next_tier)
				queue.append(next_tier)

	_autocomplete_tiers_with_children.clear()
	for tier in tiers:
		var separator := tier.rfind("/")
		if separator > 0:
			_autocomplete_tiers_with_children[tier.substr(0, separator)] = true
	_all_known_autocomplete_tiers_cache = tiers.duplicate()
	_all_known_autocomplete_tiers_cache_valid = true
	return tiers


func _has_autocomplete_tier_children(tier: String) -> bool:
	if _autocomplete_tiers_with_children.has(tier):
		return true
	if not _get_command_option_subcommand_addresses(tier, 0).is_empty():
		return true
	if not _get_pin_action_subcommand_addresses(tier).is_empty():
		return true
	if _is_setget_command_name(tier):
		return true
	if _is_text_input_command_path(tier):
		return true
	return false


func _calculate_global_command_search_match_score(tier: String, query: String) -> int:
	if query.is_empty():
		return 0

	var leaf_segment := tier.get_slice("/", tier.get_slice_count("/") - 1)
	var leaf_lower := leaf_segment.to_lower()
	var query_lower := query.to_lower()
	var depth_penalty := maxi(0, tier.get_slice_count("/") - 1) * 20

	if leaf_lower == query_lower:
		return 5000 - depth_penalty
	if leaf_lower.begins_with(query_lower):
		return 4500 - leaf_segment.length() - depth_penalty

	var leaf_score := _calculate_match_score(leaf_segment, query)
	if leaf_score < 0:
		return -1
	return 3000 + leaf_score - depth_penalty


func _collect_search_match_ranges(text: String, query: String) -> Array[Dictionary]:
	var ranges: Array[Dictionary] = []
	if query.is_empty():
		return ranges

	var query_lower := query.to_lower()
	var query_len := query_lower.length()
	if query_len <= 0:
		return ranges

	var lower_text := text.to_lower()
	var cursor := 0
	while cursor < text.length():
		var match_index := lower_text.find(query_lower, cursor)
		if match_index == -1:
			break
		ranges.append({"start": match_index, "end": match_index + query_len})
		cursor = match_index + query_len

	return ranges


func _build_global_command_search_matches(query: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var all_tiers := _get_all_known_autocomplete_tiers()

	for tier in all_tiers:
		if tier == AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND:
			continue

		var score := _calculate_global_command_search_match_score(tier, query)
		if score < 0:
			continue

		var has_option_command := _is_command_option_subcommand_tier(tier) or _is_display_variable_pin_action_subcommand_tier(tier) or _is_text_input_option_subcommand_tier(tier)
		var resolved_tier := _resolve_alias_command_path(tier)
		var has_direct_command := _get_commands().has(resolved_tier)
		var has_widget := _has_widget_direct(resolved_tier)
		var full_label := "/" + tier
		matches.append({
			"tier": tier,
			"score": score,
			"has_children": _has_autocomplete_tier_children(tier),
			"has_command": has_direct_command or has_option_command or has_widget,
			"has_display_variable": _has_display_variable(tier),
			"has_widget": has_widget,
			"full_label_override": full_label,
			"label_highlight_ranges": _collect_search_match_ranges(full_label, query),
			"suppress_value_text": true,
		})

	matches.sort_custom(func(a, b): return int(a.get("score", 0)) < int(b.get("score", 0)))
	return matches


func _get_autocomplete_tier_label(prefix: String, match_data: Dictionary) -> String:
	var full_label_override := str(match_data.get("full_label_override", ""))
	if not full_label_override.is_empty():
		return full_label_override
	if match_data.get("is_text_input", false):
		return str(match_data.get("input_label", ""))
	var tier_label_override := str(match_data.get("tier_label_override", ""))
	if not tier_label_override.is_empty():
		return tier_label_override
	var tier: String = match_data.get("tier", "")
	var display_label := _get_command_display_label(tier)
	if not display_label.is_empty():
		return display_label
	return tier.substr(prefix.length()) if tier.begins_with(prefix) else tier


func _build_command_autocomplete_row_data(prefix: String, match_data: Dictionary) -> Dictionary:
	var tier := str(match_data.get("tier", ""))
	var disabled := bool(match_data.get("disabled", false))
	var icon := _get_command_icon(tier)
	var shortcut := int(match_data.get("keyboard_shortcut", KEY_NONE)) as Key
	var shortcut_items: Array = []
	if shortcut != KEY_NONE:
		shortcut_items.append({
			"text": "Cmd/Ctrl + %s" % OS.get_keycode_string(shortcut).to_upper(),
			"color": Color(0.75, 0.78, 0.86, 0.45 if bool(match_data.get("shortcut_trumped", false)) else 1.0),
		})
	var orderable_fields := {
		"draggable": bool(match_data.get("draggable", false)),
		"orderable_group": match_data.get("orderable_group", ""),
		"orderable_object_id": match_data.get("orderable_object_id"),
	}
	if match_data.get("is_text_input", false):
		return {
			"label": _get_autocomplete_tier_label(prefix, match_data),
			"label_highlight_ranges": [],
			"value_text": "",
			"has_children": false,
			"can_submit": match_data.get("has_command", false),
			"disabled": disabled,
			"icon": icon,
			"row_background_tint": match_data.get("row_background_tint", null),
			"default_focus": bool(match_data.get("default_focus", false)),
		}

	if match_data.get("is_option", false):
		var option_row := {
			"label": str(match_data.get("option_label", "")),
			"label_highlight_ranges": [],
			"value_text": "",
			"has_children": false,
			"can_submit": false,
			"disabled": disabled,
			"icon": icon,
			"default_focus": bool(match_data.get("default_focus", false)),
			"highlighted": bool(match_data.get("highlighted", false)),
			"value_items": shortcut_items,
		}
		option_row.merge(orderable_fields)
		return option_row
	if match_data.get("suppress_value_text", false):
		var suppressed_row := {
			"label": _get_autocomplete_tier_label(prefix, match_data),
			"label_highlight_ranges": match_data.get("label_highlight_ranges", []),
			"truncate_label_from_start": true,
			"value_text": "",
			"value_items": shortcut_items,
			"display_variable_address": "",
			"value_loaded": true,
			"has_children": match_data.get("has_children", false),
			"can_submit": match_data.get("has_command", false),
			"default_focus": bool(match_data.get("default_focus", false)),
			"highlighted": bool(match_data.get("highlighted", false)),
		}
		suppressed_row.merge(orderable_fields)
		return suppressed_row

	var display_variable_address := ""
	if match_data.get("has_display_variable", false):
		display_variable_address = _resolve_alias_command_path(str(match_data.get("tier", "")))
	# Row geometry needs to know that a value wraps before its getter is hydrated. The
	# declaration is available without resolving the value, so keep the expensive text
	# lookup lazy while giving wrapped rows their correct layout mode from the start.
	var wrap_value := _get_display_variable_wrap_value(display_variable_address)
	var row := {
		"label": _get_autocomplete_tier_label(prefix, match_data),
		"label_highlight_ranges": match_data.get("label_highlight_ranges", []),
		"truncate_label_from_start": true,
		"value_text": "",
		"value_text_color": null,
		"value_items": shortcut_items,
		"display_variable_address": display_variable_address,
		"wrap_value": wrap_value,
		"value_loaded": display_variable_address.is_empty(),
		"has_children": match_data.get("has_children", false),
		"can_submit": match_data.get("has_command", false),
		"disabled": disabled,
		"icon": icon,
		"default_focus": bool(match_data.get("default_focus", false)),
		"highlighted": bool(match_data.get("highlighted", false)),
	}
	row.merge(orderable_fields)
	return row


func _should_show_command_groups(_prefix: String, query: String, _is_preview: bool) -> bool:
	if _autocomplete_global_search_mode:
		return false
	return query.strip_edges().is_empty()


# A group name is a path: "state/limits" nests a box inside a box.  A segment is headerless
# when it is empty ("state/") or prefixed with a dot (".core"), which draws a plain box
# around its options; the dotted form keeps a name so sibling boxes stay distinct.
func _split_command_group_path(group_name: String) -> Array:
	var trimmed := group_name.strip_edges()
	if trimmed.is_empty():
		return []
	var path: Array = []
	for raw_segment in trimmed.split(COMMAND_GROUP_PATH_SEPARATOR, true):
		path.append(str(raw_segment).strip_edges())
	return path


func _get_command_group_segment_label(segment: String) -> String:
	if segment.begins_with(HEADERLESS_COMMAND_GROUP_PREFIX):
		return ""
	return segment


# Rows carry the path of boxes they sit inside; which edges those boxes draw follows from
# comparing neighbours, so rewriting the row list (collapsing, filtering) cannot strand a
# box open. Re-run this whenever rows are added or removed.
func _assign_group_levels(rows: Array[Dictionary]) -> void:
	for row_index in range(rows.size()):
		var row_data: Dictionary = rows[row_index]
		var path: Array = row_data.get("group_path", []) if row_data.get("group_path", []) is Array else []
		if path.is_empty():
			row_data["group_levels"] = []
			continue
		var tints: Array = row_data.get("group_level_tints", []) if row_data.get("group_level_tints", []) is Array else []
		var previous_path: Array = _get_row_group_path(rows, row_index - 1)
		var next_path: Array = _get_row_group_path(rows, row_index + 1)
		var levels: Array[Dictionary] = []
		var started := false
		var ended := false
		for level_index in range(path.size()):
			# Once a level differs from the neighbouring row every deeper level differs too,
			# even when two unrelated boxes happen to share a key at that depth.
			if not started and (level_index >= previous_path.size() or str(previous_path[level_index]) != str(path[level_index])):
				started = true
			if not ended and (level_index >= next_path.size() or str(next_path[level_index]) != str(path[level_index])):
				ended = true
			var level_tint: Variant = tints[level_index] if level_index < tints.size() else Color.TRANSPARENT
			levels.append({
				"start": started,
				"end": ended,
				"tint": level_tint if level_tint is Color else Color.TRANSPARENT,
			})
		row_data["group_levels"] = levels


func _get_row_group_path(rows: Array[Dictionary], row_index: int) -> Array:
	if row_index < 0 or row_index >= rows.size():
		return []
	var path: Variant = rows[row_index].get("group_path", [])
	return path as Array if path is Array else []


func _build_command_autocomplete_rows(prefix: String, matches: Array, selected_match_index: int, show_groups: bool) -> Dictionary:
	var rows: Array[Dictionary] = []
	var selected_row_index := -1
	var open_path: Array = []
	var open_tints: Array = []

	for match_index in range(matches.size()):
		var match_data: Dictionary = matches[match_index]
		var group_name := str(match_data.get("group_name", "")).strip_edges() if show_groups else ""
		var group_tint: Variant = match_data.get("group_tint", Color.TRANSPARENT) if show_groups else Color.TRANSPARENT
		var group_path := _split_command_group_path(group_name)
		# An unnamed but tinted group still earns a box; key it by the tint so neighbouring
		# tinted runs do not merge into one another.
		if group_path.is_empty() and group_tint is Color and (group_tint as Color).a > 0.0:
			group_path = ["%s%s" % [HEADERLESS_COMMAND_GROUP_PREFIX, str(group_tint)]]

		var shared_depth := 0
		while (
			shared_depth < open_path.size()
			and shared_depth < group_path.size()
			and str(open_path[shared_depth]) == str(group_path[shared_depth])
		):
			shared_depth += 1
		open_path.resize(shared_depth)
		open_tints.resize(shared_depth)

		for level_index in range(shared_depth, group_path.size()):
			var segment := str(group_path[level_index])
			open_path.append(segment)
			# A box keeps the tint of whichever option opened it, so its border colour does
			# not shift part-way down when nested options are tinted differently.
			open_tints.append(group_tint if group_tint is Color else Color.TRANSPARENT)
			var segment_label := _get_command_group_segment_label(segment)
			if not segment_label.is_empty():
				rows.append({
					"is_group_header": true,
					"label": segment_label,
					"has_children": false,
					"can_submit": false,
					"value_text": "",
					"group_tint": open_tints[level_index],
					"group_path": open_path.duplicate(),
					"group_level_tints": open_tints.duplicate(),
				})

		var row := _build_command_autocomplete_row_data(prefix, match_data)
		row["match_index"] = match_index
		if not open_path.is_empty():
			row["group_tint"] = open_tints[open_tints.size() - 1]
			row["group_path"] = open_path.duplicate()
			row["group_level_tints"] = open_tints.duplicate()
		rows.append(row)

		if match_index == selected_match_index:
			selected_row_index = rows.size() - 1

	_assign_group_levels(rows)

	return {
		"rows": rows,
		"selected_row_index": selected_row_index,
	}


func _collapse_rows_between_highlights(rows: Array[Dictionary], capacity: int) -> Array[Dictionary]:
	var highlighted: Array[int] = []
	for row_index in range(rows.size()):
		if bool(rows[row_index].get("highlighted", false)) or bool(rows[row_index].get("default_focus", false)):
			highlighted.append(row_index)
	if highlighted.size() < 2 or highlighted[-1] - highlighted[0] + 1 <= capacity:
		return rows

	var gaps: Array[Dictionary] = []
	for highlight_index in range(highlighted.size() - 1):
		var indices: Array[int] = []
		for row_index in range(highlighted[highlight_index] + 1, highlighted[highlight_index + 1]):
			if not bool(rows[row_index].get("is_group_header", false)):
				indices.append(row_index)
		gaps.append({"indices": indices, "hidden": []})

	var projected_span := highlighted[-1] - highlighted[0] + 1
	var gap_cursor := 0
	while projected_span > capacity:
		var changed := false
		for step in range(gaps.size()):
			var gap_index := (gap_cursor + step) % gaps.size()
			var gap: Dictionary = gaps[gap_index]
			var indices: Array = gap.get("indices", [])
			if indices.is_empty():
				continue
			var hidden: Array = gap.get("hidden", [])
			var hide_position := indices.size() / 2
			hidden.append(indices.pop_at(hide_position))
			gap["indices"] = indices
			gap["hidden"] = hidden
			gaps[gap_index] = gap
			# The first hidden option becomes the placeholder; later ones reduce height.
			if hidden.size() > 1:
				projected_span -= 1
			gap_cursor = (gap_index + 1) % gaps.size()
			changed = true
			break
		if not changed:
			break

	var gap_by_row: Dictionary = {}
	var hidden_rows: Dictionary = {}
	for gap in gaps:
		var hidden: Array = gap.get("hidden", [])
		if hidden.is_empty():
			continue
		hidden.sort()
		var anchor := int(hidden[0])
		gap_by_row[anchor] = hidden.size()
		for row_index in hidden:
			hidden_rows[int(row_index)] = true

	var result: Array[Dictionary] = []
	for row_index in range(rows.size()):
		if gap_by_row.has(row_index):
			# The placeholder stands in for options inside a box, so it has to sit inside
			# that same box or the outline would break around it.
			var placeholder := {
				"label": "+ %d hidden options" % int(gap_by_row[row_index]),
				"disabled": true,
				"has_children": false,
				"can_submit": false,
				"value_text": "",
			}
			var hidden_row: Dictionary = rows[row_index]
			if hidden_row.get("group_path", []) is Array and not (hidden_row.get("group_path", []) as Array).is_empty():
				placeholder["group_path"] = (hidden_row.get("group_path") as Array).duplicate()
				placeholder["group_level_tints"] = (hidden_row.get("group_level_tints", []) as Array).duplicate()
				placeholder["group_tint"] = hidden_row.get("group_tint", Color.TRANSPARENT)
			result.append(placeholder)
		if hidden_rows.has(row_index):
			continue
		result.append(rows[row_index])
	# Hiding rows moves where each box starts and ends, so the edges have to be redrawn.
	_assign_group_levels(result)
	return result


func _hydrate_visible_command_autocomplete_rows(list: AutocompleteCommandColumn, column_state: Dictionary, rows: Array[Dictionary]) -> bool:
	if list == null or rows.is_empty():
		return false
	var visible_range := list.get_visible_row_range()
	var matches: Array = column_state.get("matches", [])
	# Rows draw into the column minus whatever the scrollbar overlays, so compare against that.
	var column_width := int(column_state.get("content_width", 0))
	if column_width <= 0:
		column_width = maxi(AUTOCOMPLETE_COLUMN_MIN_WIDTH, int(column_state.get("width", list.size.x)) - int(ceil(list.get_row_scrollbar_reserve_width())))
	var changed := false
	for row_index in range(visible_range.x, mini(visible_range.y, rows.size())):
		var row_data: Dictionary = rows[row_index]
		if bool(row_data.get("is_group_header", false)) or bool(row_data.get("value_loaded", false)):
			continue
		var match_index := int(row_data.get("match_index", -1))
		if match_index < 0 or match_index >= matches.size():
			continue
		var match_data: Dictionary = matches[match_index]
		var value_data := _get_autocomplete_display_variable_value_data(match_data)
		_cache_autocomplete_display_value(value_data)
		_apply_autocomplete_row_display_value(row_data, value_data, true)
		var row_value_width := _get_command_autocomplete_row_value_width(list, row_data)
		var row_action_width := _get_command_autocomplete_row_action_width(row_data)
		row_data["measured_value_width"] = row_value_width
		row_data["measured_action_width"] = row_action_width
		var row_name_width := int(row_data.get("measured_name_width", 0))
		if row_name_width <= 0:
			row_name_width = _measure_autocomplete_text_width(list, str(row_data.get("label", "")))
			row_name_width += int(ceil(AutocompleteCommandColumn.get_group_content_indent(row_data) * 2.0))
			if bool(row_data.get("column_has_icons", false)):
				row_name_width += AUTOCOMPLETE_ROW_ICON_WIDTH + int(AutocompleteCommandColumn.CELL_GAP)
		var single_line_width := AUTOCOMPLETE_COLUMN_PADDING + row_name_width
		if row_value_width > 0:
			single_line_width += AUTOCOMPLETE_CELL_GAP + row_value_width
		if row_action_width > 0:
			single_line_width += AUTOCOMPLETE_CELL_GAP + row_action_width
		var needs_two_line := not bool(row_data.get("wrap_value", false)) and row_value_width > 0 and single_line_width > column_width
		row_data["two_line"] = needs_two_line
		row_data["row_height_multiplier"] = 2.0 if needs_two_line else 1.0
		rows[row_index] = row_data
		changed = true
	if changed:
		list.replace_rows_preserving_scroll(rows)
	return changed


func _get_autocomplete_display_variable_value_data(match_data: Dictionary) -> Dictionary:
	if not match_data.get("has_display_variable", false):
		return {"text": "", "color": null, "items": [], "address": ""}

	return _get_autocomplete_display_variable_value_data_for_address(str(match_data.get("tier", "")))


func _get_autocomplete_display_variable_value_data_for_address(address: String) -> Dictionary:
	var tier := _resolve_alias_command_path(address.strip_edges())
	if tier.is_empty():
		return {"text": "", "color": null, "items": [], "address": ""}

	var snapshot := _get_display_variable_render_snapshot(tier)
	var inline_color: Variant = snapshot.get("autocomplete_color", null)
	return {
		"text": str(snapshot.get("text", "")),
		"color": inline_color if inline_color is Color and (inline_color as Color).a > 0.0 else null,
		"items": snapshot.get("items", []),
		"address": tier,
		"wrap_value": bool(snapshot.get("wrap_value", false)),
	}


## Keeps value-width measurements across catalog rebuilds without making cached data authoritative
## for visible rows. Hydration always refreshes visible values from their getter.
func _cache_autocomplete_display_value(value_data: Dictionary) -> void:
	var address := _resolve_alias_command_path(str(value_data.get("address", "")).strip_edges())
	if address.is_empty():
		return
	if _autocomplete_display_value_cache.size() >= AUTOCOMPLETE_TEXT_WIDTH_CACHE_LIMIT:
		_autocomplete_display_value_cache.clear()
	_autocomplete_display_value_cache[address] = value_data.duplicate(true)


func _apply_autocomplete_row_display_value(row_data: Dictionary, value_data: Dictionary, value_loaded: bool) -> void:
	row_data["value_text"] = str(value_data.get("text", ""))
	row_data["value_text_color"] = value_data.get("color", null)
	row_data["value_items"] = value_data.get("items", [])
	row_data["wrap_value"] = bool(value_data.get("wrap_value", false))
	row_data["display_variable_address"] = str(value_data.get("address", row_data.get("display_variable_address", "")))
	row_data["value_loaded"] = value_loaded


func _apply_cached_autocomplete_row_display_value(row_data: Dictionary) -> bool:
	var address := _resolve_alias_command_path(str(row_data.get("display_variable_address", "")).strip_edges())
	if address.is_empty():
		return false
	if not _autocomplete_display_value_cache.has(address):
		return false
	_apply_autocomplete_row_display_value(row_data, _autocomplete_display_value_cache[address] as Dictionary, false)
	return true


## A bounded sample gives a new column a useful first width. Uncached values remain lazy and
## are measured when they scroll into view, where they can widen the column if necessary.
func _sample_autocomplete_row_display_value(row_data: Dictionary, snapshot_cache: Dictionary) -> bool:
	if bool(row_data.get("value_loaded", false)):
		return false
	var address := _resolve_alias_command_path(str(row_data.get("display_variable_address", "")).strip_edges())
	if address.is_empty():
		return false
	if _apply_cached_autocomplete_row_display_value(row_data):
		return false
	var value_data: Dictionary = snapshot_cache.get(address, {})
	if value_data.is_empty():
		value_data = _get_autocomplete_display_variable_value_data_for_address(address)
		snapshot_cache[address] = value_data
	_cache_autocomplete_display_value(value_data)
	_apply_autocomplete_row_display_value(row_data, value_data, false)
	return true


func _get_command_autocomplete_column_name(prefix: String) -> String:
	var command_path := prefix.trim_suffix("/")
	if command_path.is_empty():
		return "Commands"
	var widget_label := _get_widget_display_label(command_path)
	if not widget_label.is_empty():
		return widget_label
	var segments := command_path.split("/", false)
	if segments.is_empty():
		return command_path
	if segments.size() == 3 and segments[0] == "pins" and segments[1] == "view":
		var token_target := _resolve_pins_view_alias_token_target(str(segments[2]))
		if not token_target.is_empty():
			return token_target
	return str(segments[segments.size() - 1])


func _get_command_autocomplete_description(command_name: String) -> String:
	if command_name.is_empty():
		return ""

	var command_data = _get_command_data(command_name)
	if command_data == null:
		var action_details := _get_pinnable_item_action_details(command_name)
		if action_details.get("valid", false) == true:
			var action_name := str(action_details.get("action", ""))
			if action_name == "unpin":
				return "Unpin this item."
			if action_name == "pin":
				return "Pin this item."
			if action_name == "render_texture_view_mode":
				var view_mode := str(action_details.get("view_mode", RENDER_TEXTURE_VIEW_MODE_NONE))
				if view_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
					return "Show this render texture fullscreen."
				if view_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY:
					return "Show this render texture fullscreen with a semi-transparent overlay."
				return "Close render texture fullscreen mode."
		var widget = _get_widget_data(command_name)
		if widget is LogotWidget:
			return str((widget as LogotWidget).description)
		if widget is Dictionary:
			return str((widget as Dictionary).get("description", ""))
		if _has_display_variable(command_name):
			return "Display variable commands."
		return ""
	if command_data is LogotCommand:
		return str((command_data as LogotCommand).description)
	if command_data is Dictionary:
		return str((command_data as Dictionary).get("description", ""))
	if command_data is Object:
		var description = (command_data as Object).get("description")
		return "" if description == null else str(description)
	return ""


func _get_command_autocomplete_column_description(prefix: String, command_name: String) -> String:
	if prefix.is_empty():
		if _history_access_locked_until_reset:
			return AUTOCOMPLETE_ROOT_COMMANDS_LOCKED_HINT
		return "%s, %s" % [AUTOCOMPLETE_ROOT_COMMANDS_HINT, AUTOCOMPLETE_HISTORY_HINT]
	return _get_command_autocomplete_description(command_name)


func _get_command_data_direct(command_name: String) -> Variant:
	if command_name.is_empty():
		return null
	var commands := _get_commands()
	if not commands.has(command_name):
		return null
	return commands[command_name]


func _get_command_data(command_name: String) -> Variant:
	return _get_command_data_direct(_resolve_alias_command_path(command_name))


func _is_command_path_disabled(command_path: String) -> bool:
	return _command_path_disabled_provider.is_valid() and bool(_command_path_disabled_provider.call(command_path))


func _get_command_display_label(command_name: String) -> String:
	var command_data := _get_command_data(command_name)
	if command_data is LogotCommand:
		return str((command_data as LogotCommand).display_label)
	if command_data is Dictionary:
		return str((command_data as Dictionary).get("display_label", ""))
	return ""


func _get_command_icon(command_name: String) -> Texture2D:
	var command_data := _get_command_data(command_name)
	if command_data is LogotCommand:
		return (command_data as LogotCommand).icon
	if command_data is Dictionary:
		return (command_data as Dictionary).get("icon") as Texture2D
	return null


func _command_path_takes_parameter(command_name: String) -> bool:
	var command_data = _get_command_data(command_name)
	if command_data is LogotCommand:
		return (command_data as LogotCommand).arguments.size() > 0
	if command_data is Dictionary:
		var arguments = (command_data as Dictionary).get("arguments", [])
		if arguments is Array or arguments is PackedStringArray:
			return arguments.size() > 0
	return false


func _enter_touch_parameter_command(command_name: String) -> void:
	if not line_edit:
		return
	var normalized_path := _get_display_alias_command_path(command_name.strip_edges().trim_suffix("/"))
	if normalized_path.is_empty():
		return
	line_edit.text = "/" + normalized_path + " "
	line_edit.caret_column = line_edit.text.length()
	line_edit.grab_focus()
	hide_autocomplete()


func _is_setget_command_name(command_name: String) -> bool:
	var command_data = _get_command_data(command_name)
	if command_data is LogotCommand:
		return (command_data as LogotCommand).value_getter.is_valid()
	if command_data is Dictionary:
		return bool((command_data as Dictionary).get("is_setget", false))
	return false


func _normalize_single_command_option_list(option_data: Variant) -> Array:
	var values: Array = []
	if option_data is Array:
		for option_value in option_data:
			values.append(option_value)
		return values
	if option_data is PackedStringArray:
		for option_value in option_data:
			values.append(option_value)
		return values
	values.append(option_data)
	return values


func _normalize_command_option_values(options_data: Variant) -> Array:
	var normalized: Array = []
	if not (options_data is Array):
		return normalized

	var options_array: Array = options_data
	if options_array.is_empty():
		return normalized

	var first_value = options_array[0]
	if first_value is Array or first_value is PackedStringArray:
		for option_group in options_array:
			normalized.append(_normalize_single_command_option_list(option_group))
	else:
		normalized.append(_normalize_single_command_option_list(options_array))
	return normalized


func _get_command_argument_option_values(command_name: String, argument_index: int = 0) -> Array:
	if argument_index < 0:
		return []

	var command_data = _get_command_data(command_name)
	if command_data == null:
		return []

	if command_data is LogotCommand:
		var logot_command := command_data as LogotCommand
		if logot_command.argument_options_provider.is_valid():
			var provided_options = _normalize_command_option_values(logot_command.argument_options_provider.call())
			if argument_index < provided_options.size():
				return provided_options[argument_index]

		var static_options = _normalize_command_option_values(logot_command.argument_options)
		if argument_index < static_options.size():
			return static_options[argument_index]
		return []

	if command_data is Dictionary:
		var options_data = (command_data as Dictionary).get("argument_options", [])
		var normalized_options = _normalize_command_option_values(options_data)
		if argument_index < normalized_options.size():
			return normalized_options[argument_index]
		return []

	return []


func _get_command_current_value(command_name: String) -> Variant:
	var command_data = _get_command_data(command_name)
	if command_data is LogotCommand:
		var value_getter := (command_data as LogotCommand).value_getter
		if value_getter.is_valid():
			return value_getter.call()

	if _has_display_variable(command_name):
		return _get_display_variable_value(command_name)

	return null


func _build_command_option_matches(command_name: String, argument_index: int = 0) -> Array[Dictionary]:
	var option_values := _get_command_argument_option_values(command_name, argument_index)
	var option_matches: Array[Dictionary] = []
	var option_group := _get_command_option_group_data(command_name)
	var option_group_name := str(option_group.get("name", "")).strip_edges()
	var option_group_priority := int(option_group.get("priority", 0))
	for option_entry in option_values:
		var option_value: Variant
		option_value = _get_command_option_entry_value(option_entry)
		var option_label := _get_command_option_entry_label(option_entry)
		var match_data := {
			"is_option": true,
			"option_label": option_label,
			"option_value": option_value,
		}
		if not option_group_name.is_empty():
			match_data["group_name"] = option_group_name
			match_data["group_priority"] = option_group_priority
		var option_group_tint = option_group.get("tint", Color.TRANSPARENT)
		if option_group_tint is Color and (option_group_tint as Color).a > 0.0:
			match_data["group_tint"] = option_group_tint
		option_matches.append(match_data)
	return option_matches


func _get_command_option_entry_value(option_entry: Variant) -> Variant:
	if option_entry is Dictionary:
		return (option_entry as Dictionary).get("value")
	return option_entry


func _get_command_option_entry_label(option_entry: Variant) -> String:
	if option_entry is Dictionary:
		var option_label := str((option_entry as Dictionary).get("label", "")).strip_edges()
		if not option_label.is_empty():
			return option_label
	return str(_get_command_option_entry_value(option_entry))


func _get_command_option_subcommand_segment(option_entry: Variant) -> String:
	return _get_command_option_entry_label(option_entry).strip_edges()


func _get_command_option_label_for_value(command_name: String, value: Variant, argument_index: int = 0) -> String:
	var options := _get_command_argument_option_values(command_name, argument_index)
	if options.is_empty():
		return ""

	var value_text := str(value)
	for option_entry in options:
		var option_value: Variant = _get_command_option_entry_value(option_entry)
		var exact_match: bool = typeof(option_value) == typeof(value) and option_value == value
		if exact_match or str(option_value) == value_text:
			return _get_command_option_entry_label(option_entry)
	return ""


func _get_command_option_subcommand_addresses(command_name: String, argument_index: int = 0) -> Array[String]:
	var addresses: Array[String] = []
	var option_values := _get_command_argument_option_values(command_name, argument_index)
	for option_entry in option_values:
		var option_segment := _get_command_option_subcommand_segment(option_entry)
		if option_segment.is_empty():
			continue
		addresses.append("%s/%s" % [command_name, option_segment])
	return addresses


func _get_pin_action_values(address: String) -> Array:
	var resolved_address := _resolve_alias_command_path(address)
	if not _is_pinnable_item_direct(resolved_address):
		return []
	var is_pinned := is_display_variable_pinned(resolved_address)
	var values: Array = [
		{"label": "pin", "value": true, "corner": PINNED_OVERLAY_CORNER_TOP_LEFT},
	]
	if is_pinned:
		values.append({"label": "unpin", "value": false})
	if _is_render_texture_widget_path(resolved_address):
		values.append({"label": RENDER_TEXTURE_VIEW_MODE_FULLSCREEN, "value": RENDER_TEXTURE_VIEW_MODE_FULLSCREEN})
		values.append({"label": RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY, "value": RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY})
		if get_render_texture_widget_view_mode(resolved_address) != RENDER_TEXTURE_VIEW_MODE_NONE:
			values.append({"label": "fullscreen_off", "value": RENDER_TEXTURE_VIEW_MODE_NONE})
	return values


func _get_pin_action_subcommand_addresses(address: String) -> Array[String]:
	var addresses: Array[String] = []
	for option_entry in _get_pin_action_values(address):
		var option_segment := _get_command_option_subcommand_segment(option_entry)
		if option_segment.is_empty():
			continue
		addresses.append("%s/%s" % [address, option_segment])
		if option_segment == "pin":
			for corner in PINNED_OVERLAY_CORNERS:
				addresses.append("%s/pin/%s" % [address, corner])
	return addresses


func _get_display_variable_pin_action_values(address: String) -> Array:
	return _get_pin_action_values(address)


func _get_display_variable_pin_action_subcommand_addresses(address: String) -> Array[String]:
	return _get_pin_action_subcommand_addresses(address)


func _get_render_texture_view_mode_for_action_segment(option_segment: String) -> String:
	var normalized_segment := option_segment.strip_edges().to_lower()
	if normalized_segment == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
		return RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
	if normalized_segment in [RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY, "overlay", "fullscreen/overlay"]:
		return RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY
	if normalized_segment in ["fullscreen_off", "fullscreen/off", "fullscreen_none", "fullscreen/none"]:
		return RENDER_TEXTURE_VIEW_MODE_NONE
	return ""


func _get_pinnable_item_action_details(command_path: String) -> Dictionary:
	var resolved_tier := _resolve_alias_command_path(command_path)
	if resolved_tier.ends_with("/unpin"):
		var unpin_address := resolved_tier.trim_suffix("/unpin")
		if _is_pinnable_item_direct(unpin_address) and is_display_variable_pinned(unpin_address):
			return {"valid": true, "address": unpin_address, "action": "unpin"}
		return {}

	if resolved_tier.ends_with("/pin"):
		var pin_address := resolved_tier.trim_suffix("/pin")
		if _is_pinnable_item_direct(pin_address):
			return {"valid": true, "address": pin_address, "action": "pin"}

	for corner in PINNED_OVERLAY_CORNERS:
		var corner_suffix := "/pin/%s" % corner
		if not resolved_tier.ends_with(corner_suffix):
			continue
		var corner_address := resolved_tier.trim_suffix(corner_suffix)
		if _is_pinnable_item_direct(corner_address):
			return {"valid": true, "address": corner_address, "action": "pin"}
		return {}

	for view_suffix in [
		"/fullscreen/overlay",
		"/fullscreen/none",
		"/fullscreen/off",
		"/fullscreen_overlay",
		"/fullscreen_none",
		"/fullscreen_off",
		"/fullscreen",
		"/overlay",
	]:
		if not resolved_tier.ends_with(view_suffix):
			continue
		var render_address := resolved_tier.trim_suffix(view_suffix)
		if not _is_render_texture_widget_path(render_address):
			continue
		var option_segment: String = str(view_suffix).trim_prefix("/")
		var view_mode := _get_render_texture_view_mode_for_action_segment(option_segment)
		if view_mode == RENDER_TEXTURE_VIEW_MODE_NONE and get_render_texture_widget_view_mode(render_address) == RENDER_TEXTURE_VIEW_MODE_NONE:
			return {}
		if not view_mode.is_empty():
			return {"valid": true, "address": render_address, "action": "render_texture_view_mode", "view_mode": view_mode}
	return {}


func _is_command_option_subcommand_tier(tier: String) -> bool:
	var resolved_tier := _resolve_alias_command_path(tier)
	var last_separator := resolved_tier.rfind("/")
	if last_separator <= 0:
		return false

	var command_name := resolved_tier.substr(0, last_separator)
	if command_name.is_empty() or _get_command_data_direct(command_name) == null:
		return false
	var option_segment := resolved_tier.substr(last_separator + 1)
	if option_segment.is_empty():
		return false

	var option_match := _match_setget_option_text(option_segment, _get_command_argument_option_values(command_name, 0))
	return option_match.get("matched", false)


func _is_display_variable_pin_action_subcommand_tier(tier: String) -> bool:
	return _get_pinnable_item_action_details(tier).get("valid", false) == true


func _is_text_input_command_path(command_name: String) -> bool:
	var resolved_command := _resolve_alias_command_path(command_name)
	if resolved_command == "pins/save":
		return true
	if not _is_setget_command_name(resolved_command):
		return false
	return _get_command_argument_option_values(resolved_command, 0).is_empty()


func _get_input_type_label_from_value(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "boolean"
		TYPE_INT:
			return "integer"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		TYPE_STRING_NAME:
			return "string"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR3:
			return "Vector3"
		TYPE_VECTOR4:
			return "Vector4"
		TYPE_COLOR:
			return "Color"
		TYPE_ARRAY:
			return "Array"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_NIL:
			return "value"
		_:
			return "value"


func _parse_bool_from_string(text: String) -> Dictionary:
	var lowered := text.strip_edges().to_lower()
	if lowered in ["true", "1", "yes", "y", "on"]:
		return {"ok": true, "value": true}
	if lowered in ["false", "0", "no", "n", "off"]:
		return {"ok": true, "value": false}
	return {"ok": false}


func _convert_setget_input_to_value(raw_value: String, current_value: Variant, discrete_options: Array) -> Dictionary:
	var option_match := _match_setget_option_text(raw_value, discrete_options)
	if option_match.get("matched", false):
		return {"ok": true, "value": option_match.get("value")}

	var current_type := typeof(current_value)
	match current_type:
		TYPE_BOOL:
			var parsed_bool := _parse_bool_from_string(raw_value)
			if parsed_bool.get("ok", false):
				return {"ok": true, "value": parsed_bool.get("value", false)}
			return {"ok": false}
		TYPE_INT:
			var trimmed := raw_value.strip_edges()
			if trimmed.is_valid_int():
				return {"ok": true, "value": int(trimmed)}
			if trimmed.is_valid_float():
				var float_value := float(trimmed)
				if is_equal_approx(float_value, round(float_value)):
					return {"ok": true, "value": int(float_value)}
			return {"ok": false}
		TYPE_FLOAT:
			var trimmed_float := raw_value.strip_edges()
			if trimmed_float.is_valid_float() or trimmed_float.is_valid_int():
				return {"ok": true, "value": float(trimmed_float)}
			return {"ok": false}
		TYPE_STRING:
			return {"ok": true, "value": raw_value}
		TYPE_STRING_NAME:
			return {"ok": true, "value": StringName(raw_value)}
		_:
			var parsed_value = str_to_var(raw_value)
			if typeof(parsed_value) == current_type:
				return {"ok": true, "value": parsed_value}
			return {"ok": false}


func _validate_pin_overlay_name_for_input(raw_name: String) -> Dictionary:
	var overlay_name := raw_name.strip_edges()
	if overlay_name.is_empty():
		return {"valid": false}
	for invalid_character in ["/", "\\", " ", "\t", "\n", "\r"]:
		if overlay_name.find(invalid_character) != -1:
			return {"valid": false}
	return {"valid": true}


func _validate_text_input_for_command_path(command_name: String, raw_input: String) -> Dictionary:
	var resolved_command := _resolve_alias_command_path(command_name)
	if resolved_command == "pins/save":
		var save_valid := _validate_pin_overlay_name_for_input(raw_input)
		return {
			"valid": bool(save_valid.get("valid", false)),
			"accepted_type": "overlay name",
		}

	if not _is_setget_command_name(resolved_command):
		return {"valid": false, "accepted_type": "value"}

	var current_value: Variant
	current_value = _get_command_current_value(resolved_command)
	var accepted_type := _get_input_type_label_from_value(current_value)
	var converted := _convert_setget_input_to_value(raw_input, current_value, _get_command_argument_option_values(resolved_command, 0))
	return {
		"valid": bool(converted.get("ok", false)),
		"accepted_type": accepted_type,
	}


func _build_text_input_tier_match(prefix: String, query: String) -> Dictionary:
	if prefix.is_empty() or not prefix.ends_with("/"):
		return {}

	var command_path := prefix.trim_suffix("/")
	if not _is_text_input_command_path(command_path):
		return {}

	var validation := _validate_text_input_for_command_path(command_path, query)
	var accepted_type := str(validation.get("accepted_type", "value"))
	var is_valid := not query.is_empty() and bool(validation.get("valid", false))
	var current_input := query if not query.is_empty() else "type a valid %s" % accepted_type
	var synthetic_tier_suffix := query if not query.is_empty() else "__pending_input__"
	var row_data := {
		"tier": prefix + synthetic_tier_suffix,
		"score": 2000,
		"has_children": false,
		"has_command": is_valid,
		"has_display_variable": false,
		"is_text_input": true,
		"input_label": "set to [%s]" % current_input,
	}
	if not query.is_empty() and not is_valid:
		row_data["row_background_tint"] = INVALID_INPUT_ROW_BG_COLOR
	return row_data


func _is_text_input_option_subcommand_tier(tier: String) -> bool:
	var last_separator := tier.rfind("/")
	if last_separator <= 0:
		return false

	var command_name := tier.substr(0, last_separator)
	var option_segment := tier.substr(last_separator + 1)
	if option_segment.is_empty() or not _is_text_input_command_path(command_name):
		return false

	var validation := _validate_text_input_for_command_path(command_name, option_segment)
	return bool(validation.get("valid", false))


func _find_setget_preview_option_selected_index(command_name: String, preview_prefix: String, preview_matches: Array) -> int:
	if command_name.is_empty() or preview_prefix.is_empty() or preview_matches.is_empty():
		return -1

	var current_value: Variant
	current_value = _get_command_current_value(command_name)
	var current_text := str(current_value)
	var option_values := _get_command_argument_option_values(command_name, 0)
	for option_index in range(preview_matches.size()):
		var option_tier := str(preview_matches[option_index].get("tier", ""))
		if not option_tier.begins_with(preview_prefix):
			continue
		var option_segment := option_tier.substr(preview_prefix.length())
		var option_match := _match_setget_option_text(option_segment, option_values)
		if not option_match.get("matched", false):
			continue
		var option_value = option_match.get("value")
		var exact_match: bool = typeof(option_value) == typeof(current_value) and option_value == current_value
		if exact_match or str(option_value) == current_text:
			return option_index

	if _is_pinnable_item(command_name):
		var resolved_command_name := _resolve_alias_command_path(command_name)
		if _is_render_texture_widget_path(resolved_command_name):
			var active_view_mode := get_render_texture_widget_view_mode(resolved_command_name)
			var expected_view_segment := ""
			if active_view_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN:
				expected_view_segment = RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
			elif active_view_mode == RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY:
				expected_view_segment = RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY
			elif active_view_mode == RENDER_TEXTURE_VIEW_MODE_NONE:
				expected_view_segment = "fullscreen_off"
			if not expected_view_segment.is_empty():
				for option_index in range(preview_matches.size()):
					var option_tier := str(preview_matches[option_index].get("tier", ""))
					if not option_tier.begins_with(preview_prefix):
						continue
					var option_segment := option_tier.substr(preview_prefix.length()).to_lower()
					if option_segment == expected_view_segment:
						return option_index
		var expected_pin_segment := "unpin" if is_display_variable_pinned(resolved_command_name) else "pin"
		for option_index in range(preview_matches.size()):
			var option_tier := str(preview_matches[option_index].get("tier", ""))
			if not option_tier.begins_with(preview_prefix):
				continue
			var option_segment := option_tier.substr(preview_prefix.length()).to_lower()
			if option_segment == expected_pin_segment:
				return option_index

	return -1


func _match_setget_option_text(raw_value: String, options: Array) -> Dictionary:
	var trimmed_value := raw_value.strip_edges()
	if trimmed_value.is_empty():
		return {"matched": false}

	var lowered_value := trimmed_value.to_lower()
	for option_entry in options:
		var option_value: Variant = _get_command_option_entry_value(option_entry)
		var option_label := _get_command_option_entry_label(option_entry)
		for candidate in [option_label, str(option_value)]:
			if candidate == trimmed_value or candidate.to_lower() == lowered_value:
				return {"matched": true, "value": option_value}
	return {"matched": false}


func _find_command_option_match_index(command_name: String, option_matches: Array[Dictionary]) -> int:
	if option_matches.is_empty():
		return -1

	var current_value: Variant
	current_value = _get_command_current_value(command_name)
	if current_value == null:
		return -1

	var current_text := str(current_value)
	for option_index in range(option_matches.size()):
		var option_data := option_matches[option_index]
		var option_value = option_data.get("option_value")
		var exact_match: bool = typeof(option_value) == typeof(current_value) and option_value == current_value
		if exact_match or str(option_value) == current_text:
			return option_index
	return -1


# =============================================================================
# AUTOCOMPLETE
# =============================================================================

## Calculate match score for sorting (higher = better match)
## Returns -1 if no match
func _calculate_match_score(command: String, query: String) -> int:
	if query.is_empty():
		return 0  # All commands match with neutral score when no query

	var cmd_lower := command.to_lower()
	var query_lower := query.to_lower()

	# Exact match at start is best
	if cmd_lower.begins_with(query_lower):
		return 1000 - command.length()  # Shorter commands rank higher for prefix matches

	# Contains match
	var index := cmd_lower.find(query_lower)
	if index != -1:
		return 500 - index  # Earlier position = higher score

	# Fuzzy match: check if all query chars appear in order
	var query_idx := 0
	var score := 0
	var consecutive_bonus := 0
	for i in range(cmd_lower.length()):
		if query_idx < query_lower.length() and cmd_lower[i] == query_lower[query_idx]:
			score += 10
			if consecutive_bonus > 0:
				score += consecutive_bonus * 5  # Bonus for consecutive matches
			consecutive_bonus += 1
			query_idx += 1
		else:
			consecutive_bonus = 0

	if query_idx == query_lower.length():
		return score  # All characters found

	return -1  # No match


## Get the next tier suggestion for a command given the current prefix
## For "console/test/foo" with prefix "console/", returns "console/test"
## For "console" with prefix "", returns "console"
func _get_next_tier(command: String, prefix: String) -> String:
	if not command.begins_with(prefix):
		return ""
	var remainder := command.substr(prefix.length())
	var next_slash := remainder.find("/")
	if next_slash == -1:
		return command  # Full command, no more tiers
	return prefix + remainder.substr(0, next_slash)  # Return up to next tier


func _find_autocomplete_match_index(matches: Array[Dictionary], tier: String) -> int:
	if tier.is_empty():
		return -1
	for i in range(matches.size()):
		if str(matches[i].get("tier", "")) == tier:
			return i
	return -1


func _store_autocomplete_highlighted_tier(prefix: String, matches: Array, selected_index: int) -> void:
	if selected_index < 0 or selected_index >= matches.size():
		return
	var selected_match: Dictionary = matches[selected_index]
	var selected_tier := str(selected_match.get("tier", ""))
	if selected_tier.is_empty():
		return
	_autocomplete_highlighted_tiers[prefix] = selected_tier


func _cache_pre_filter_autocomplete_highlight(prefix: String, fallback_tier: String = "") -> void:
	if _autocomplete_pre_filter_highlighted_tiers.has(prefix):
		return

	var cached_tier := str(_autocomplete_highlighted_tiers.get(prefix, ""))
	if cached_tier.is_empty():
		cached_tier = fallback_tier
	if cached_tier.is_empty():
		return
	_autocomplete_pre_filter_highlighted_tiers[prefix] = cached_tier


func _consume_pre_filter_autocomplete_highlight(prefix: String) -> String:
	if not _autocomplete_pre_filter_highlighted_tiers.has(prefix):
		return ""

	var cached_tier := str(_autocomplete_pre_filter_highlighted_tiers.get(prefix, ""))
	_autocomplete_pre_filter_highlighted_tiers.erase(prefix)
	return cached_tier


func _split_autocomplete_segments(path: String) -> Array[String]:
	var segments: Array[String] = []
	if path.is_empty():
		return segments

	for segment in path.split("/", false):
		if not str(segment).is_empty():
			segments.append(str(segment))
	return segments


func _get_autocomplete_input_state() -> Dictionary:
	var committed_segments: Array[String] = []
	var committed_prefix := ""
	var query := ""

	if not line_edit:
		return {"segments": committed_segments, "prefix": committed_prefix, "query": query}

	var text := line_edit.text
	if not text.begins_with("/"):
		return {"segments": committed_segments, "prefix": committed_prefix, "query": query}

	# "//" is a shorthand entry for global command search mode.
	if text.begins_with("//"):
		committed_segments.append(AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND)
		committed_prefix = AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND + "/"
		query = text.substr(2)
		return {"segments": committed_segments, "prefix": committed_prefix, "query": query}

	var raw_full_text := text.substr(1)
	var had_trailing_separator := raw_full_text.ends_with("/")
	var normalized_full_text := _get_internal_alias_command_path(raw_full_text.trim_suffix("/"))

	# Keep "/search" working as an entry point to global search mode.
	if normalized_full_text == AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND and not had_trailing_separator:
		committed_segments.append(AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND)
		committed_prefix = AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND + "/"
		query = ""
		return {"segments": committed_segments, "prefix": committed_prefix, "query": query}

	var full_text := normalized_full_text + ("/" if had_trailing_separator and not normalized_full_text.is_empty() else "")
	query = full_text

	if full_text.ends_with("/"):
		query = ""
		var without_trailing := full_text.left(full_text.length() - 1)
		committed_segments = _split_autocomplete_segments(without_trailing)
		committed_prefix = full_text
	else:
		var last_slash := full_text.rfind("/")
		if last_slash != -1:
			committed_prefix = full_text.substr(0, last_slash + 1)
			committed_segments = _split_autocomplete_segments(committed_prefix.left(committed_prefix.length() - 1))
			query = full_text.substr(last_slash + 1)

	return {"segments": committed_segments, "prefix": committed_prefix, "query": query}


func _build_command_autocomplete_state() -> bool:
	var input_state := _get_autocomplete_input_state()
	var committed_segments: Array[String] = []
	for segment in input_state.get("segments", []):
		committed_segments.append(str(segment))
	var query: String = input_state.get("query", "")

	_autocomplete_column_states.clear()
	_autocomplete_global_search_mode = false

	if committed_segments.size() == 1 and committed_segments[0] == AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND:
		return _build_global_command_autocomplete_state(query)

	_autocomplete_active_column_index = committed_segments.size()

	var prefix := ""
	for column_index in range(_autocomplete_active_column_index + 1):
		var column_query := query if column_index == _autocomplete_active_column_index else ""
		var matches := _build_tier_matches(prefix, column_query)
		if matches.is_empty():
			if column_index == _autocomplete_active_column_index and column_query.is_empty() and column_index > 0:
				_autocomplete_column_states.append({
					"prefix": prefix,
					"query": column_query,
					"matches": [],
					"selected_index": -1,
					"preview": false,
					"left_width": 0,
					"width": 0,
				})
				break
			_autocomplete_active_column_index = -1
			return false

		var selected_tier := str(_autocomplete_highlighted_tiers.get(prefix, ""))
		if column_index < committed_segments.size():
			selected_tier = prefix + committed_segments[column_index]

		var selected_index := -1
		var is_active_column := column_index == _autocomplete_active_column_index
		var is_filtering_active_column := is_active_column and not column_query.is_empty()
		if is_filtering_active_column:
			_cache_pre_filter_autocomplete_highlight(prefix, selected_tier)
			selected_index = matches.size() - 1
		else:
			if is_active_column and column_query.is_empty():
				var restored_tier := _consume_pre_filter_autocomplete_highlight(prefix)
				if not restored_tier.is_empty():
					selected_tier = restored_tier

			selected_index = _find_autocomplete_match_index(matches, selected_tier)
			if selected_index == -1:
				if column_index < committed_segments.size():
					_autocomplete_active_column_index = -1
					return false
				var use_neutral_root_selection := (
					_root_command_selection_reset_pending
					and column_index == _autocomplete_active_column_index
					and column_index == 0
					and committed_segments.is_empty()
					and column_query.is_empty()
					and prefix.is_empty()
				)
				if not use_neutral_root_selection:
					selected_index = matches.size() - 1

		_store_autocomplete_highlighted_tier(prefix, matches, selected_index)
		_autocomplete_column_states.append({
			"prefix": prefix,
			"query": column_query,
			"matches": matches,
			"selected_index": selected_index,
			"preview": false,
			"left_width": 0,
			"width": 0,
		})

		if column_index < committed_segments.size():
			prefix = str(matches[selected_index].get("tier", "")) + "/"

	_refresh_active_preview_column_state()
	return not _autocomplete_column_states.is_empty()


func _build_global_command_autocomplete_state(query: String) -> bool:
	var matches := _build_global_command_search_matches(query)
	if matches.is_empty():
		_autocomplete_active_column_index = -1
		return false

	_autocomplete_global_search_mode = true
	_autocomplete_active_column_index = 0

	var selected_tier := str(_autocomplete_highlighted_tiers.get(AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX, ""))
	var selected_index := -1
	if query.is_empty():
		var restored_tier := _consume_pre_filter_autocomplete_highlight(AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX)
		if not restored_tier.is_empty():
			selected_tier = restored_tier
		selected_index = _find_autocomplete_match_index(matches, selected_tier)
		if selected_index == -1:
			selected_index = matches.size() - 1
	else:
		_cache_pre_filter_autocomplete_highlight(AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX, selected_tier)
		selected_index = matches.size() - 1

	_store_autocomplete_highlighted_tier(AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX, matches, selected_index)

	_autocomplete_column_states.append({
		"prefix": AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX,
		"query": query,
		"matches": matches,
		"selected_index": selected_index,
		"preview": false,
		"column_name_override": "Search",
		"column_description_override": "all command paths, right reveals, enter runs executable commands",
		"left_width": 0,
		"width": 0,
	})
	return true


func _get_preview_column_state_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for column_state in _autocomplete_column_states:
		if not bool(column_state.get("preview", false)):
			continue
		var selected_tier := ""
		var selected_index := int(column_state.get("selected_index", -1))
		var matches: Array = column_state.get("matches", [])
		if selected_index >= 0 and selected_index < matches.size():
			selected_tier = str(matches[selected_index].get("tier", ""))
		snapshot.append({
			"prefix": str(column_state.get("prefix", "")),
			"selected_tier": selected_tier,
			"selected_index": selected_index,
			"match_count": matches.size(),
			"preview_parent_tier": str(column_state.get("preview_parent_tier", "")),
			"preview_command": str(column_state.get("preview_command", "")),
		})
	return snapshot


func _refresh_active_preview_column_state() -> bool:
	if _autocomplete_global_search_mode:
		return false

	var previous_preview_snapshot := _get_preview_column_state_snapshot()

	while _autocomplete_column_states.size() > _autocomplete_active_column_index + 1:
		_autocomplete_column_states.remove_at(_autocomplete_column_states.size() - 1)

	if _autocomplete_active_column_index < 0 or _autocomplete_active_column_index >= _autocomplete_column_states.size():
		return previous_preview_snapshot != _get_preview_column_state_snapshot()

	var active_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
	var selected_index := int(active_state.get("selected_index", -1))
	var matches: Array = active_state.get("matches", [])
	if selected_index < 0 or selected_index >= matches.size():
		return previous_preview_snapshot != _get_preview_column_state_snapshot()

	var selected_match: Dictionary = matches[selected_index]
	var selected_tier := str(selected_match.get("tier", ""))
	if selected_tier.is_empty():
		return previous_preview_snapshot != _get_preview_column_state_snapshot()
	if _default_child_resolver.is_valid():
		var default_result = _default_child_resolver.call(selected_tier)
		if bool(default_result.get("has_default", false)) and bool(default_result.get("valid", false)):
			var default_focus_paths: Array = default_result.get("focus_paths", [])
			if _append_default_child_preview_columns(selected_tier, default_focus_paths):
				return previous_preview_snapshot != _get_preview_column_state_snapshot()

	if selected_match.get("has_widget", false):
		var preview_prefix := selected_tier + "/"
		var preview_matches := _build_tier_matches(preview_prefix, "") if bool(selected_match.get("has_children", false)) else []
		var preview_selected_index := _find_setget_preview_option_selected_index(selected_tier, preview_prefix, preview_matches)
		if preview_selected_index == -1 and not preview_matches.is_empty():
			preview_selected_index = preview_matches.size() - 1
		if not preview_matches.is_empty():
			_store_autocomplete_highlighted_tier(preview_prefix, preview_matches, preview_selected_index)
		_autocomplete_column_states.append({
			"prefix": preview_prefix,
			"query": "",
			"matches": preview_matches,
			"selected_index": preview_selected_index,
			"preview": true,
			"widget_preview": true,
			"preview_widget_path": selected_tier,
			"column_name_override": _get_command_autocomplete_column_name(selected_tier + "/"),
			"column_description_override": _get_command_autocomplete_description(selected_tier),
			"left_width": 0,
			"width": 0,
		})
		return previous_preview_snapshot != _get_preview_column_state_snapshot()

	if selected_match.get("has_children", false):
		var preview_prefix := selected_tier + "/"
		var preview_matches := _build_tier_matches(preview_prefix, "")
		if not preview_matches.is_empty():
			var preview_selected_index := _find_setget_preview_option_selected_index(selected_tier, preview_prefix, preview_matches)
			if preview_selected_index == -1:
				preview_selected_index = preview_matches.size() - 1
			_store_autocomplete_highlighted_tier(preview_prefix, preview_matches, preview_selected_index)

			_autocomplete_column_states.append({
				"prefix": preview_prefix,
				"query": "",
				"matches": preview_matches,
				"selected_index": preview_selected_index,
				"preview": true,
				"preview_parent_tier": selected_tier,
				"left_width": 0,
				"width": 0,
			})

	# Show a dedicated command details column for executable leaf selections.
	if selected_match.get("has_command", false) and not selected_match.get("has_children", false) and not _is_command_option_subcommand_tier(selected_tier) and not _is_display_variable_pin_action_subcommand_tier(selected_tier) and not _is_text_input_option_subcommand_tier(selected_tier):
		var option_matches := _build_command_option_matches(selected_tier, 0)
		var option_selected_index := _find_command_option_match_index(selected_tier, option_matches)
		if not option_matches.is_empty():
			_autocomplete_column_states.append({
				"prefix": selected_tier + "/",
				"query": "",
				"matches": option_matches,
				"selected_index": option_selected_index,
				"preview": true,
				"preview_command": selected_tier,
				"preview_argument_index": 0,
				"column_name_override": _get_command_autocomplete_column_name(selected_tier + "/"),
				"column_description_override": _get_command_autocomplete_description(selected_tier),
				"left_width": 0,
				"width": 0,
			})
			return previous_preview_snapshot != _get_preview_column_state_snapshot()

		_autocomplete_column_states.append({
			"prefix": selected_tier + "/",
			"query": "",
			"matches": [],
			"selected_index": -1,
			"preview": true,
			"column_description_override": _get_command_autocomplete_description(selected_tier),
			"left_width": 0,
			"width": 0,
		})

	return previous_preview_snapshot != _get_preview_column_state_snapshot()


func _append_default_child_preview_columns(parent_tier: String, focus_paths: Array) -> bool:
	var current_parent := parent_tier
	var appended := false
	for focus_path_variant in focus_paths:
		var focus_path := str(focus_path_variant).strip_edges()
		var preview_prefix := current_parent + "/"
		if focus_path.is_empty() or not focus_path.begins_with(preview_prefix):
			return appended
		var preview_matches := _build_tier_matches(preview_prefix, "")
		var preview_selected_index := _find_autocomplete_match_index(preview_matches, focus_path)
		if preview_selected_index < 0:
			return appended
		var focused_match: Dictionary = preview_matches[preview_selected_index]
		focused_match["default_focus"] = true
		preview_matches[preview_selected_index] = focused_match
		_autocomplete_column_states.append({
			"prefix": preview_prefix,
			"query": "",
			"matches": preview_matches,
			"selected_index": preview_selected_index,
			"preview": true,
			"preview_parent_tier": current_parent,
			"default_focus_tier": focus_path,
			"left_width": 0,
			"width": 0,
		})
		current_parent = focus_path
		appended = true
	return appended


func _measure_autocomplete_text_width(control: Control, text: String) -> int:
	var font_size := control.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = 16
	return _measure_autocomplete_text_width_with_font_size(control, text, font_size)


func _measure_autocomplete_text_width_with_font_size(control: Control, text: String, font_size: int) -> int:
	var font := control.get_theme_font("font")
	if font == null:
		return text.length() * 8
	if font_size <= 0:
		font_size = 16
	var cache_key := "%d:%d:%s" % [font.get_instance_id(), font_size, text]
	if _autocomplete_text_width_cache.has(cache_key):
		return int(_autocomplete_text_width_cache[cache_key])
	var measured_width := int(ceil(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x))
	if _autocomplete_text_width_cache.size() >= AUTOCOMPLETE_TEXT_WIDTH_CACHE_LIMIT:
		_autocomplete_text_width_cache.clear()
	_autocomplete_text_width_cache[cache_key] = measured_width
	return measured_width


func _get_command_autocomplete_max_column_width() -> int:
	var max_width := 0
	if line_edit:
		max_width = int(line_edit.size.x)
		if max_width <= 0:
			max_width = int(line_edit.get_global_rect().size.x)
	if max_width <= 0 and _command_autocomplete_popup:
		max_width = int(_command_autocomplete_popup.size.x)
	if max_width <= 0:
		max_width = AUTOCOMPLETE_COLUMN_MAX_FALLBACK_WIDTH
	max_width = mini(max_width, AUTOCOMPLETE_COLUMN_HARD_MAX_WIDTH)
	return maxi(AUTOCOMPLETE_COLUMN_MIN_WIDTH, max_width)


func _get_command_autocomplete_row_value_width(control: Control, row_data: Dictionary) -> int:
	var current_value_width := 0
	var value_items_variant: Variant = row_data.get("value_items", [])
	if value_items_variant is Array and not (value_items_variant as Array).is_empty():
		var value_items := value_items_variant as Array
		for item_index in range(value_items.size()):
			if item_index > 0:
				current_value_width += int(AutocompleteCommandColumn.VALUE_PILL_GAP)
			var item_variant: Variant = value_items[item_index]
			var item_text := str((item_variant as Dictionary).get("text", "")) if item_variant is Dictionary else str(item_variant)
			current_value_width += _measure_autocomplete_text_width(control, item_text) + AUTOCOMPLETE_VALUE_PILL_EXTRA_WIDTH
	else:
		var value_text := str(row_data.get("value_text", ""))
		if not value_text.is_empty():
			current_value_width = _measure_autocomplete_text_width(control, value_text) + AUTOCOMPLETE_VALUE_PILL_EXTRA_WIDTH
	return current_value_width if bool(row_data.get("wrap_value", false)) else mini(current_value_width, AUTOCOMPLETE_VALUE_MAX_WIDTH)


func _get_command_autocomplete_row_action_width(row_data: Dictionary) -> int:
	var action_count := 0
	if row_data.get("has_children", false):
		action_count += 1
	if row_data.get("can_submit", false):
		action_count += 1
	if row_data.get("draggable", false):
		action_count += 1
	if action_count <= 0:
		return 0

	var current_action_width := AUTOCOMPLETE_ACTION_ICON_DIAMETER * action_count
	if action_count > 1:
		current_action_width += AUTOCOMPLETE_ACTION_ICON_GAP * (action_count - 1)
	return current_action_width


func _measure_command_autocomplete_column_layout(control: Control, prefix: String, rows: Array[Dictionary], column_name: String, column_description: String, reserved_width: int = 0, unloaded_value_sample_count: int = AUTOCOMPLETE_VALUE_MEASUREMENT_SAMPLE_COUNT) -> Dictionary:
	var column_has_icons := false
	for candidate_row in rows:
		if (candidate_row as Dictionary).get("icon") is Texture2D:
			column_has_icons = true
			break
	var name_width := 0
	var value_width := 0
	var action_width := 0
	var total_width := 0
	var value_snapshot_cache: Dictionary = {}
	var remaining_value_samples := maxi(0, unloaded_value_sample_count)
	for row_index in range(rows.size()):
		var row_data: Dictionary = rows[row_index]
		var row_name_width := _measure_autocomplete_text_width(control, str(row_data.get("label", "")))
		# Boxed rows are pushed in on both sides to clear their enclosing group borders.
		row_name_width += int(ceil(AutocompleteCommandColumn.get_group_content_indent(row_data) * 2.0))
		if column_has_icons and not bool(row_data.get("is_group_header", false)):
			row_name_width += AUTOCOMPLETE_ROW_ICON_WIDTH + int(AutocompleteCommandColumn.CELL_GAP)
			row_data["column_has_icons"] = true
		row_data["measured_name_width"] = row_name_width
		var row_value_width := 0
		var row_action_width := 0
		if bool(row_data.get("is_group_header", false)):
			name_width = maxi(name_width, row_name_width)
			total_width = maxi(total_width, AUTOCOMPLETE_COLUMN_PADDING + row_name_width)
			row_data["measured_value_width"] = 0
			row_data["measured_action_width"] = 0
			rows[row_index] = row_data
			continue
		name_width = maxi(name_width, row_name_width)
		if not bool(row_data.get("value_loaded", false)) and not _apply_cached_autocomplete_row_display_value(row_data) and remaining_value_samples > 0:
			if _sample_autocomplete_row_display_value(row_data, value_snapshot_cache):
				remaining_value_samples -= 1
		row_value_width = _get_command_autocomplete_row_value_width(control, row_data)
		row_action_width = _get_command_autocomplete_row_action_width(row_data)
		if row_value_width > 0:
			value_width = maxi(value_width, row_value_width)
		if row_action_width > 0:
			action_width = maxi(action_width, row_action_width)
		var row_total_width := AUTOCOMPLETE_COLUMN_PADDING + row_name_width
		if row_value_width > 0:
			row_total_width += AUTOCOMPLETE_CELL_GAP + row_value_width
		if row_action_width > 0:
			row_total_width += AUTOCOMPLETE_CELL_GAP + row_action_width
		total_width = maxi(total_width, row_total_width)
		row_data["measured_value_width"] = row_value_width
		row_data["measured_action_width"] = row_action_width
		rows[row_index] = row_data

	var base_font_size := control.get_theme_font_size("font_size")
	if base_font_size <= 0:
		base_font_size = 16
	var header_title_size := maxi(20, base_font_size + 6)
	var header_description_size := maxi(11, base_font_size - 2)
	var header_content_width := _measure_autocomplete_text_width_with_font_size(control, column_name.to_upper(), header_title_size)
	if not column_description.strip_edges().is_empty():
		header_content_width = maxi(header_content_width, _measure_autocomplete_text_width_with_font_size(control, column_description, header_description_size))
	# Keep a small safety margin because title text is rendered bold via BBCode and can
	# be a few pixels wider than plain font metrics (which otherwise causes wrap artifacts).
	var header_total_width := int(ceil(AutocompleteCommandColumn.CONTENT_PADDING_X * 2.0)) + header_content_width + AUTOCOMPLETE_HEADER_WIDTH_BUFFER
	# The row scrollbar overlays the right-hand edge, so the rows never get to draw into it.
	var preferred_width := maxi(total_width, header_total_width) + reserved_width
	if prefix == AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX:
		total_width = maxi(AUTOCOMPLETE_COLUMN_MIN_WIDTH, preferred_width)
	else:
		var max_width := _get_command_autocomplete_max_column_width()
		total_width = clampi(preferred_width, AUTOCOMPLETE_COLUMN_MIN_WIDTH, max_width)
	var content_width := maxi(0, total_width - reserved_width)

	for row_index in range(rows.size()):
		var row_data: Dictionary = rows[row_index]
		if bool(row_data.get("is_group_header", false)):
			continue
		var row_name_width := int(row_data.get("measured_name_width", 0))
		var row_value_width := int(row_data.get("measured_value_width", 0))
		var row_action_width := int(row_data.get("measured_action_width", 0))
		var single_line_width := AUTOCOMPLETE_COLUMN_PADDING + row_name_width
		if row_value_width > 0:
			single_line_width += AUTOCOMPLETE_CELL_GAP + row_value_width
		if row_action_width > 0:
			single_line_width += AUTOCOMPLETE_CELL_GAP + row_action_width
		var needs_two_line := not bool(row_data.get("wrap_value", false)) and row_value_width > 0 and single_line_width > content_width
		row_data["two_line"] = needs_two_line
		row_data["row_height_multiplier"] = 2.0 if needs_two_line else 1.0
		rows[row_index] = row_data

	return {
		"name_width": name_width,
		"value_width": value_width,
		"action_width": action_width,
		"width": total_width,
		"content_width": content_width,
		"scrollbar_reserve": reserved_width,
	}


func _create_command_autocomplete_column() -> AutocompleteCommandColumn:
	var list := AutocompleteCommandColumn.new()
	if _history_autocomplete_popup:
		list.configure_theme(_history_autocomplete_popup)
	list.row_activated.connect(_on_command_autocomplete_column_row_activated.bind(list))
	list.row_long_pressed.connect(_on_command_autocomplete_column_row_long_pressed.bind(list))
	list.row_reordered.connect(_on_command_autocomplete_column_rows_reordered.bind(list))
	list.header_navigation_pressed.connect(_on_command_autocomplete_header_navigation_pressed)
	list.visible_rows_changed.connect(_on_command_autocomplete_column_visible_rows_changed.bind(list))
	return list


func _on_command_autocomplete_column_rows_reordered(from_row_index: int, to_row_index: int, list: AutocompleteCommandColumn) -> void:
	if not _orderable_reorder_handler.is_valid():
		return
	var from_context := _get_command_autocomplete_row_context(from_row_index, list)
	var to_context := _get_command_autocomplete_row_context(to_row_index, list)
	if from_context.is_empty() or to_context.is_empty():
		return
	var from_match: Dictionary = from_context.get("match_data", {})
	var to_match: Dictionary = to_context.get("match_data", {})
	var group := str(from_match.get("orderable_group", ""))
	if group.is_empty() or group != str(to_match.get("orderable_group", "")):
		return
	_orderable_reorder_handler.call(group, from_match.get("orderable_object_id"), to_match.get("orderable_object_id"))


func _get_autocomplete_column_index_for_node(list: AutocompleteCommandColumn) -> int:
	for column_index in range(_autocomplete_column_nodes.size()):
		if _autocomplete_column_nodes[column_index] == list:
			return column_index
	return -1


func _on_command_autocomplete_column_visible_rows_changed(list: AutocompleteCommandColumn) -> void:
	var column_index := _get_autocomplete_column_index_for_node(list)
	if column_index < 0 or column_index >= _autocomplete_column_states.size():
		return
	var rows: Array[Dictionary] = []
	for row_variant in list.get_rows():
		if row_variant is Dictionary:
			rows.append(row_variant as Dictionary)
	if _hydrate_visible_command_autocomplete_rows(list, _autocomplete_column_states[column_index], rows):
		_autocomplete_column_states[column_index] = _refresh_autocomplete_column_layout_after_visible_hydration(list, _autocomplete_column_states[column_index], column_index, rows)
		_update_touch_command_autocomplete_column_visibility()
		_position_command_autocomplete_popup()
		_ensure_active_command_column_visible()
		_refresh_autocomplete_visible_address_tracking()


func _on_command_autocomplete_column_row_activated(row_index: int, list: AutocompleteCommandColumn) -> void:
	var row_context := _get_command_autocomplete_row_context(row_index, list)
	if row_context.is_empty():
		return
	var column_index := int(row_context.get("column_index", -1))
	var column_state: Dictionary = row_context.get("column_state", {})
	var match_index := int(row_context.get("match_index", -1))
	var match_data: Dictionary = row_context.get("match_data", {})

	_autocomplete_active_column_index = column_index
	column_state["selected_index"] = match_index
	_autocomplete_column_states[column_index] = column_state
	_autocomplete_highlighted_tiers[str(column_state.get("prefix", ""))] = str(match_data.get("tier", ""))
	_sync_visible_command_autocomplete_columns(0, false)
	_activate_command_autocomplete_match(column_state, match_data)


func _on_command_autocomplete_column_row_long_pressed(row_index: int, list: AutocompleteCommandColumn) -> void:
	var row_context := _get_command_autocomplete_row_context(row_index, list)
	if row_context.is_empty():
		return
	var column_state: Dictionary = row_context.get("column_state", {})
	var match_data: Dictionary = row_context.get("match_data", {})
	var submission_text := _get_submission_text_for_autocomplete_match(column_state, match_data)
	if submission_text.strip_edges().is_empty():
		return
	command_palette_execute_keep_open_requested.emit(submission_text)


func _get_command_autocomplete_row_context(row_index: int, list: AutocompleteCommandColumn) -> Dictionary:
	if list == null or not _is_command_popup_visible():
		return {}
	var column_index := _get_autocomplete_column_index_for_node(list)
	if column_index < 0 or column_index >= _autocomplete_column_states.size():
		return {}
	if _is_touch_command_palette_layout() and column_index != _autocomplete_active_column_index:
		return {}

	var column_state: Dictionary = _autocomplete_column_states[column_index]
	var matches: Array = column_state.get("matches", [])
	var rows: Array = list.get_rows()
	if row_index < 0 or row_index >= rows.size():
		return {}
	var row_data: Dictionary = rows[row_index]
	if bool(row_data.get("is_group_header", false)):
		return {}
	var match_index := int(row_data.get("match_index", -1))
	if match_index < 0 or match_index >= matches.size():
		return {}
	return {
		"column_index": column_index,
		"column_state": column_state,
		"match_index": match_index,
		"match_data": matches[match_index],
	}


func _get_submission_text_for_autocomplete_match(column_state: Dictionary, match_data: Dictionary) -> String:
	if bool(match_data.get("is_option", false)):
		var preview_command := str(column_state.get("preview_command", "")).strip_edges()
		if preview_command.is_empty():
			return ""
		return "/%s %s" % [preview_command, str(match_data.get("option_value", ""))]
	var tier := str(match_data.get("tier", "")).strip_edges()
	if tier.is_empty() or not bool(match_data.get("has_command", false)):
		return ""
	return "/%s" % tier


func _activate_command_autocomplete_match(column_state: Dictionary, match_data: Dictionary) -> void:
	if match_data.is_empty():
		return
	if bool(match_data.get("disabled", false)):
		return
	if bool(match_data.get("is_option", false)):
		var option_submission_text := _get_submission_text_for_autocomplete_match(column_state, match_data)
		if not option_submission_text.is_empty():
			command_palette_submit_requested.emit(option_submission_text)
		return

	if bool(match_data.get("has_children", false)):
		autocomplete_move_right(true)
		return

	if bool(match_data.get("has_command", false)):
		if _is_touch_command_palette_layout():
			var tier := str(match_data.get("tier", "")).strip_edges()
			if not tier.is_empty() and _command_path_takes_parameter(tier):
				_enter_touch_parameter_command(tier)
				return
		var submission_text := get_active_command_submission_text()
		if not submission_text.strip_edges().is_empty():
			command_palette_submit_requested.emit(submission_text)


func _on_command_autocomplete_header_navigation_pressed() -> void:
	touch_command_palette_back_or_close()


func _clear_command_autocomplete_columns() -> void:
	if not _command_autocomplete_columns_container:
		return

	for child in _command_autocomplete_columns_container.get_children():
		_command_autocomplete_columns_container.remove_child(child)
		child.queue_free()
	_autocomplete_column_nodes.clear()


func _position_history_autocomplete_popup() -> void:
	if not _history_autocomplete_popup or not line_edit:
		return

	var line_edit_rect := line_edit.get_global_rect()
	var item_count := mini(_history_autocomplete_popup.item_count, AUTOCOMPLETE_MAX_VISIBLE_ITEMS)
	var desired_height := item_count * _get_scaled_autocomplete_item_height() + int(round(8.0 * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE)))
	var popup_gap := _get_scaled_autocomplete_popup_gap()
	var available_height := maxi(0.0, line_edit_rect.position.y - popup_gap)
	var popup_height := minf(desired_height, available_height)
	var popup_y := maxi(0.0, line_edit_rect.position.y - popup_gap - popup_height)
	var popup_width := line_edit_rect.size.x
	if line_edit.size.x > 0.0:
		popup_width = minf(popup_width, line_edit.size.x)
	var viewport_rect := get_viewport_rect()
	var popup_x: float
	popup_x = clampf(line_edit_rect.position.x, 0.0, maxf(0.0, viewport_rect.size.x - popup_width))

	_history_autocomplete_popup.global_position = Vector2(popup_x, popup_y)
	_history_autocomplete_popup.size = Vector2(popup_width, popup_height)


func _position_command_autocomplete_popup() -> void:
	if not _command_autocomplete_popup or not line_edit:
		return

	if _is_touch_command_palette_layout():
		var touch_layout_rect := _get_safe_area_layout_rect()
		_command_autocomplete_target_global_position = touch_layout_rect.position
		_command_autocomplete_target_size = touch_layout_rect.size
		_apply_command_autocomplete_popup_visual_state()
		_update_command_palette_log_reserved_space()
		_debug_command_popup_height("_position_command_autocomplete_popup.touch")
		return

	var line_edit_rect := line_edit.get_global_rect()
	var popup_height := _get_command_autocomplete_target_height()
	var popup_y := maxi(0.0, line_edit_rect.position.y - _get_scaled_autocomplete_popup_gap() - popup_height)
	var popup_width := line_edit_rect.size.x
	if line_edit.size.x > 0.0:
		popup_width = minf(popup_width, line_edit.size.x)
	var viewport_rect := get_viewport_rect()
	var popup_x: float
	popup_x = clampf(line_edit_rect.position.x, 0.0, maxf(0.0, viewport_rect.size.x - popup_width))

	_command_autocomplete_target_global_position = Vector2(popup_x, popup_y)
	_command_autocomplete_target_size = Vector2(popup_width, popup_height)
	_apply_command_autocomplete_popup_visual_state()
	_update_command_palette_log_reserved_space()
	call_deferred("_fit_command_autocomplete_columns_to_viewport")

	_debug_command_popup_height("_position_command_autocomplete_popup")


func _scroll_command_autocomplete_columns_to_end() -> void:
	if not _command_autocomplete_scroll or not _command_autocomplete_columns_container:
		return

	var viewport_width := int(_command_autocomplete_popup.size.x)
	var content_width := 0
	for column_state in _autocomplete_column_states:
		content_width += int(column_state.get("width", 0))
	var separation := _command_autocomplete_columns_container.get_theme_constant("separation")
	if _autocomplete_column_states.size() > 1:
		content_width += separation * (_autocomplete_column_states.size() - 1)
	var target_scroll := maxi(0, content_width - viewport_width)
	_command_autocomplete_scroll.scroll_horizontal = target_scroll


func _ensure_active_command_column_visible() -> void:
	if not _command_autocomplete_scroll or _autocomplete_active_column_index < 0:
		return
	if _autocomplete_active_column_index >= _autocomplete_column_states.size():
		return

	var separation := 0
	if _command_autocomplete_columns_container:
		separation = _command_autocomplete_columns_container.get_theme_constant("separation")

	var active_start := separation * _autocomplete_active_column_index
	for i in range(_autocomplete_active_column_index):
		active_start += int(_autocomplete_column_states[i].get("width", 0))

	var active_width := int(_autocomplete_column_states[_autocomplete_active_column_index].get("width", 0))
	var active_end := active_start + active_width
	var viewport_width := int(_command_autocomplete_popup.size.x)
	var current_scroll := _command_autocomplete_scroll.scroll_horizontal
	var target_scroll := current_scroll

	if active_start < current_scroll:
		target_scroll = active_start
	elif active_end > current_scroll + viewport_width:
		target_scroll = active_end - viewport_width

	if target_scroll < 0:
		target_scroll = 0
	_command_autocomplete_scroll.scroll_horizontal = target_scroll


func _queue_command_autocomplete_column_sync(start_index: int, scroll_to_end: bool = false) -> void:
	_debug_autocomplete("_queue_command_autocomplete_column_sync", "start_index=%d" % start_index)
	if _pending_autocomplete_column_sync_start == -1:
		_pending_autocomplete_column_sync_start = start_index
	else:
		_pending_autocomplete_column_sync_start = mini(_pending_autocomplete_column_sync_start, start_index)
	if scroll_to_end:
		_pending_autocomplete_column_sync_scroll_to_end = true

	if _autocomplete_column_sync_queued:
		return

	_autocomplete_column_sync_queued = true
	call_deferred("_flush_command_autocomplete_column_sync")


func _flush_command_autocomplete_column_sync() -> void:
	_autocomplete_column_sync_queued = false
	var start_index := maxi(0, _pending_autocomplete_column_sync_start)
	var scroll_to_end := _pending_autocomplete_column_sync_scroll_to_end
	_pending_autocomplete_column_sync_start = -1
	_pending_autocomplete_column_sync_scroll_to_end = false
	_debug_autocomplete("_flush_command_autocomplete_column_sync", "start_index=%d" % start_index)
	_sync_visible_command_autocomplete_columns(start_index, scroll_to_end)


func _debug_command_popup_height(source: String) -> void:
	if not _is_debug_autocomplete_enabled():
		return
	if not _command_autocomplete_popup:
		return

	var scroll_size := Vector2.ZERO
	if _command_autocomplete_scroll:
		scroll_size = _command_autocomplete_scroll.size

	_debug_autocomplete(
		source,
		"popup_height=%.1f popup_size=%s popup_min=%s scroll_size=%s popup_visible=%s in_tree=%s" % [
			_command_autocomplete_popup.size.y,
			str(_command_autocomplete_popup.size),
			str(_command_autocomplete_popup.custom_minimum_size),
			str(scroll_size),
			str(_command_autocomplete_popup.visible),
			str(_command_autocomplete_popup.is_visible_in_tree()),
		]
	)


## Vertical space the drag handle needs above the palette so it stays on screen.
func _get_command_palette_resize_handle_reserve() -> float:
	if _is_touch_command_palette_layout():
		return 0.0
	return (COMMAND_PALETTE_RESIZE_HANDLE_HEIGHT + COMMAND_PALETTE_RESIZE_HANDLE_GAP) * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE)


func _get_command_palette_default_height() -> int:
	return AUTOCOMPLETE_FIXED_VISIBLE_ITEMS * _get_scaled_autocomplete_item_height() + int(round(8.0 * _get_render_scale_multiplier(RENDER_SCALE_TARGET_COMMAND_PALETTE)))


func _get_command_palette_max_height() -> float:
	var available_height := get_viewport_rect().size.y
	if line_edit:
		available_height = minf(available_height, line_edit.get_global_rect().position.y - _get_scaled_autocomplete_popup_gap())
	return maxf(1.0, available_height - _get_command_palette_resize_handle_reserve())


func _clamp_command_palette_height(height: float) -> float:
	var max_height := _get_command_palette_max_height()
	var min_height := minf(float(_get_command_palette_default_height()) * 0.5, max_height)
	return clampf(height, min_height, max_height)


func _get_command_autocomplete_popup_height() -> int:
	if _command_palette_height_override > 0.0:
		return maxi(1, int(round(_clamp_command_palette_height(_command_palette_height_override))))
	return _get_command_palette_default_height()


func _get_command_autocomplete_target_height() -> int:
	if _is_touch_command_palette_layout():
		return maxi(1, int(floor(_get_safe_area_layout_rect().size.y)))
	if not line_edit:
		return _get_command_autocomplete_popup_height()

	return maxi(1, int(floor(minf(float(_get_command_autocomplete_popup_height()), _get_command_palette_max_height()))))


func _get_command_autocomplete_column_viewport_height() -> int:
	var target_height := _get_command_autocomplete_target_height()
	if _command_autocomplete_scroll == null or not _command_autocomplete_scroll.is_inside_tree():
		return target_height

	var horizontal_scrollbar := _command_autocomplete_scroll.get_h_scroll_bar()
	var measured_height := _calculate_command_autocomplete_column_viewport_height(
		_command_autocomplete_scroll.size.y,
		horizontal_scrollbar.size.y if horizontal_scrollbar != null else 0.0,
		horizontal_scrollbar != null and horizontal_scrollbar.visible,
		target_height
	)
	# The measured height lags behind a shrinking palette: the columns' own minimum
	# size holds the scroll container open until they are told to shrink first.
	var column_ceiling := maxi(1, target_height - int(ceil(_get_command_autocomplete_panel_vertical_margin())))
	return mini(measured_height, column_ceiling)


## Vertical space the palette panel's stylebox consumes around its columns.
func _get_command_autocomplete_panel_vertical_margin() -> float:
	if _command_autocomplete_popup == null:
		return 0.0
	var panel_style := _command_autocomplete_popup.get_theme_stylebox("panel")
	if panel_style == null:
		return 0.0
	return maxf(panel_style.get_margin(SIDE_TOP) + panel_style.get_margin(SIDE_BOTTOM), panel_style.get_minimum_size().y)


func _calculate_command_autocomplete_column_viewport_height(scroll_height: float, horizontal_scrollbar_height: float, horizontal_scrollbar_visible: bool, fallback_height: int) -> int:
	var viewport_height := scroll_height
	if horizontal_scrollbar_visible:
		viewport_height -= horizontal_scrollbar_height
	if viewport_height <= 0.0:
		return fallback_height
	return maxi(1, int(floor(viewport_height)))


func _get_command_autocomplete_target_width() -> int:
	if _is_touch_command_palette_layout():
		return maxi(1, int(floor(_get_safe_area_layout_rect().size.x)))
	if _command_autocomplete_popup:
		return maxi(1, int(floor(_command_autocomplete_popup.size.x)))
	if line_edit:
		return maxi(1, int(floor(line_edit.get_global_rect().size.x)))
	return AUTOCOMPLETE_COLUMN_MAX_FALLBACK_WIDTH


func _get_touch_command_autocomplete_column_size() -> Vector2:
	var target_size := _get_safe_area_layout_rect().size
	if _command_autocomplete_popup:
		var panel_style := _command_autocomplete_popup.get_theme_stylebox("panel")
		if panel_style != null:
			var margin_size := Vector2(
				panel_style.get_margin(SIDE_LEFT) + panel_style.get_margin(SIDE_RIGHT),
				panel_style.get_margin(SIDE_TOP) + panel_style.get_margin(SIDE_BOTTOM)
			)
			var minimum_size := panel_style.get_minimum_size()
			target_size.x -= maxf(margin_size.x, minimum_size.x)
			target_size.y -= maxf(margin_size.y, minimum_size.y)
	return Vector2(maxf(1.0, floor(target_size.x)), maxf(1.0, floor(target_size.y)))


func _is_command_autocomplete_column_displayed(column_index: int, column_state: Dictionary) -> bool:
	if not _is_touch_command_palette_layout():
		return true
	if column_index < 0:
		return false
	if bool(column_state.get("preview", false)):
		return false
	return column_index == _autocomplete_active_column_index


func _update_touch_command_autocomplete_column_visibility() -> void:
	if _command_autocomplete_scroll:
		_command_autocomplete_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _is_touch_command_palette_layout() else ScrollContainer.SCROLL_MODE_AUTO
		if _is_touch_command_palette_layout():
			var touch_scroll_size := _get_touch_command_autocomplete_column_size()
			_command_autocomplete_scroll.custom_minimum_size = touch_scroll_size
			_command_autocomplete_scroll.size = touch_scroll_size
	for column_index in range(mini(_autocomplete_column_nodes.size(), _autocomplete_column_states.size())):
		var node := _autocomplete_column_nodes[column_index] as Control
		if node == null:
			continue
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		node.visible = _is_command_autocomplete_column_displayed(column_index, column_state)
		if node.visible and _is_touch_command_palette_layout():
			var touch_column_size := _get_touch_command_autocomplete_column_size()
			node.custom_minimum_size = touch_column_size
			node.size = touch_column_size
	if _command_autocomplete_scroll and _is_touch_command_palette_layout():
		_command_autocomplete_scroll.scroll_horizontal = 0


func _refresh_command_preview_option_state(column_state: Dictionary) -> Dictionary:
	if not column_state.get("preview", false):
		return column_state
	var default_focus_tier := str(column_state.get("default_focus_tier", ""))
	if not default_focus_tier.is_empty():
		var default_preview_prefix := str(column_state.get("prefix", ""))
		var default_preview_matches := _build_tier_matches(default_preview_prefix, "")
		var default_selected_index := _find_autocomplete_match_index(default_preview_matches, default_focus_tier)
		if default_selected_index >= 0:
			var default_match: Dictionary = default_preview_matches[default_selected_index]
			default_match["default_focus"] = true
			default_preview_matches[default_selected_index] = default_match
		column_state["matches"] = default_preview_matches
		column_state["selected_index"] = default_selected_index
		return column_state

	var preview_parent_tier := str(column_state.get("preview_parent_tier", column_state.get("preview_parent_command", "")))
	if not preview_parent_tier.is_empty():
		var preview_prefix := str(column_state.get("prefix", ""))
		var preview_matches := _build_tier_matches(preview_prefix, "")
		column_state["matches"] = preview_matches
		column_state["selected_index"] = _find_setget_preview_option_selected_index(preview_parent_tier, preview_prefix, preview_matches)
		_store_autocomplete_highlighted_tier(preview_prefix, preview_matches, int(column_state.get("selected_index", -1)))
		return column_state

	var preview_command := str(column_state.get("preview_command", ""))
	if preview_command.is_empty():
		return column_state

	var argument_index := int(column_state.get("preview_argument_index", 0))
	var option_matches := _build_command_option_matches(preview_command, argument_index)
	column_state["matches"] = option_matches
	column_state["selected_index"] = _find_command_option_match_index(preview_command, option_matches)
	return column_state


func _configure_command_autocomplete_column(list: AutocompleteCommandColumn, column_state: Dictionary, column_index: int) -> Dictionary:
	_resolve_visible_keyboard_shortcuts()
	if column_index >= 0 and column_index < _autocomplete_column_states.size():
		column_state = _autocomplete_column_states[column_index]
	column_state = _refresh_command_preview_option_state(column_state)
	var prefix: String = column_state.get("prefix", "")
	var command_name := prefix.trim_suffix("/")
	var column_name := str(column_state.get("column_name_override", _get_command_autocomplete_column_name(prefix)))
	var column_description := str(column_state.get("column_description_override", _get_command_autocomplete_column_description(prefix, command_name)))
	var matches: Array = column_state.get("matches", [])
	var widget_path := _get_widget_path_for_autocomplete_column_state(column_state)
	var selected_match_index := int(column_state.get("selected_index", -1))
	var show_groups := _should_show_command_groups(prefix, str(column_state.get("query", "")), bool(column_state.get("preview", false)))
	var row_build_result := _build_command_autocomplete_rows(prefix, matches, selected_match_index, show_groups)
	var rows: Array[Dictionary] = []
	for row_variant in row_build_result.get("rows", []):
		if row_variant is Dictionary:
			rows.append(row_variant as Dictionary)
	var selected_row_index := int(row_build_result.get("selected_row_index", -1))
	var tracked_display_variable_addresses: Array[String] = []
	for row_data in rows:
		var tracked_address := _resolve_alias_command_path(str(row_data.get("display_variable_address", "")).strip_edges())
		if tracked_address.is_empty() or tracked_display_variable_addresses.has(tracked_address):
			continue
		tracked_display_variable_addresses.append(tracked_address)
	column_state["tracked_display_variable_addresses"] = tracked_display_variable_addresses

	var layout := _measure_command_autocomplete_column_layout(list, prefix, rows, column_name, column_description)
	_resolve_autocomplete_column_width(list, column_state, column_index, layout, widget_path, 0)

	var column_height := _get_command_autocomplete_column_viewport_height()
	if _is_touch_command_palette_layout() and _is_command_autocomplete_column_displayed(column_index, column_state):
		column_height = int(_get_touch_command_autocomplete_column_size().y)
	if bool(column_state.get("preview", false)):
		var estimated_header_height := 72
		var available_preview_height := float(maxi(0, column_height - estimated_header_height))
		var row_capacity := 0
		var base_row_height := float(maxi(1, _get_scaled_autocomplete_item_height()))
		for row_data in rows:
			var candidate_height := base_row_height * maxf(1.0, float((row_data as Dictionary).get("row_height_multiplier", 1.0)))
			if row_capacity > 0 and candidate_height > available_preview_height:
				break
			available_preview_height -= candidate_height
			row_capacity += 1
		row_capacity = maxi(1, row_capacity)
		var fitted_rows := _collapse_rows_between_highlights(rows, row_capacity)
		if fitted_rows.size() != rows.size():
			rows = fitted_rows
			layout = _measure_command_autocomplete_column_layout(list, prefix, rows, column_name, column_description)
			_resolve_autocomplete_column_width(list, column_state, column_index, layout, widget_path, 0)
	list.custom_minimum_size = Vector2(column_state["width"], column_height)
	list.size = list.custom_minimum_size
	_configure_autocomplete_column_widget(list, widget_path, _get_autocomplete_column_widget_placement(column_state))

	var is_active_column := column_index == _autocomplete_active_column_index
	list.set_touch_mode(_is_touch_command_palette_layout())
	list.set_column_data(
		rows,
		layout,
		selected_row_index,
		column_state.get("preview", false),
		_get_scaled_autocomplete_item_height(),
		is_active_column,
		column_name,
		column_description
	)
	# The row scrollbar overlays the column's right-hand edge, but only settles once the rows
	# have been applied, so measure it back in afterwards. Reserving the space can only make
	# rows taller (never shorter), so the scrollbar cannot vanish and one pass suffices.
	var scrollbar_reserve := int(ceil(list.get_row_scrollbar_reserve_width()))
	if scrollbar_reserve > 0:
		layout = _measure_command_autocomplete_column_layout(list, prefix, rows, column_name, column_description, scrollbar_reserve)
		_resolve_autocomplete_column_width(list, column_state, column_index, layout, widget_path, scrollbar_reserve)
		list.custom_minimum_size = Vector2(column_state["width"], column_height)
		list.size = list.custom_minimum_size
		list.set_column_data(
			rows,
			layout,
			selected_row_index,
			column_state.get("preview", false),
			_get_scaled_autocomplete_item_height(),
			is_active_column,
			column_name,
			column_description
		)

	if _hydrate_visible_command_autocomplete_rows(list, column_state, rows):
		column_state = _refresh_autocomplete_column_layout_after_visible_hydration(list, column_state, column_index, rows)
	var show_touch_navigation := _is_touch_command_palette_layout() and is_active_column and not bool(column_state.get("preview", false))
	var navigation_label := "Close" if str(column_state.get("prefix", "")).is_empty() else "Back"
	list.set_header_navigation(show_touch_navigation, navigation_label)

	return column_state


## Visible values own the final column width. The bounded first-pass sample avoids a full
## getter sweep, then each newly hydrated scroll window converges the layout on real values.
func _refresh_autocomplete_column_layout_after_visible_hydration(list: AutocompleteCommandColumn, column_state: Dictionary, column_index: int, rows: Array[Dictionary]) -> Dictionary:
	var prefix := str(column_state.get("prefix", ""))
	var command_name := prefix.trim_suffix("/")
	var column_name := str(column_state.get("column_name_override", _get_command_autocomplete_column_name(prefix)))
	var column_description := str(column_state.get("column_description_override", _get_command_autocomplete_column_description(prefix, command_name)))
	var widget_path := _get_widget_path_for_autocomplete_column_state(column_state)
	var scrollbar_reserve := int(ceil(list.get_row_scrollbar_reserve_width()))
	var layout := _measure_command_autocomplete_column_layout(list, prefix, rows, column_name, column_description, scrollbar_reserve, 0)
	var previous_width := int(column_state.get("width", 0))
	_resolve_autocomplete_column_width(list, column_state, column_index, layout, widget_path, scrollbar_reserve)
	if int(column_state.get("width", 0)) == previous_width:
		return column_state

	var selected_row_index := -1
	var selected_match_index := int(column_state.get("selected_index", -1))
	for row_index in range(rows.size()):
		if int((rows[row_index] as Dictionary).get("match_index", -1)) == selected_match_index:
			selected_row_index = row_index
			break
	var column_height := list.custom_minimum_size.y
	if column_height <= 0.0:
		column_height = list.size.y
	list.custom_minimum_size = Vector2(column_state["width"], column_height)
	list.size = list.custom_minimum_size
	list.set_column_data(
		rows,
		layout,
		selected_row_index,
		column_state.get("preview", false),
		_get_scaled_autocomplete_item_height(),
		column_index == _autocomplete_active_column_index,
		column_name,
		column_description
	)
	return column_state


## Folds the embedded widget's minimum width and the row scrollbar's reserve into a measured
## layout, then writes the resolved widths onto column_state.
func _resolve_autocomplete_column_width(list: AutocompleteCommandColumn, column_state: Dictionary, column_index: int, layout: Dictionary, widget_path: String, reserved_width: int) -> void:
	if not widget_path.is_empty():
		var widget_min := _get_widget_default_minimum_size(_get_widget_data(widget_path))
		if widget_min.x <= 0.0 or widget_min.y <= 0.0:
			var embedded_widget_for_measure := list.get_node_or_null("LogotEmbeddedWidget") as Control
			if embedded_widget_for_measure != null:
				widget_min = embedded_widget_for_measure.get_combined_minimum_size()
		layout["width"] = maxi(int(layout.get("width", 0)), int(ceil(widget_min.x + AutocompleteCommandColumn.CONTENT_PADDING_X * 2.0)) + reserved_width)
	column_state["left_width"] = int(layout.get("name_width", 0))
	column_state["value_width"] = int(layout.get("value_width", 0))
	column_state["action_width"] = int(layout.get("action_width", 0))
	column_state["width"] = int(layout.get("width", 0))
	if _is_touch_command_palette_layout() and _is_command_autocomplete_column_displayed(column_index, column_state):
		column_state["width"] = int(_get_touch_command_autocomplete_column_size().x)
	column_state["content_width"] = maxi(0, int(column_state["width"]) - reserved_width)
	layout["content_width"] = int(column_state["content_width"])


func _resolve_visible_keyboard_shortcuts() -> void:
	var winners: Dictionary = {}
	# The current column is considered first, then the preview replaces its winners.
	for candidate_column_index in [_autocomplete_active_column_index, _autocomplete_active_column_index + 1]:
		if candidate_column_index < 0 or candidate_column_index >= _autocomplete_column_states.size():
			continue
		var state: Dictionary = _autocomplete_column_states[candidate_column_index]
		var matches: Array = state.get("matches", [])
		for match_index in range(matches.size()):
			var match_data: Dictionary = matches[match_index]
			match_data.erase("shortcut_trumped")
			match_data.erase("highlighted")
			var shortcut := int(match_data.get("keyboard_shortcut", KEY_NONE)) as Key
			if shortcut == KEY_NONE or bool(match_data.get("disabled", false)):
				matches[match_index] = match_data
				continue
			var key := int(shortcut)
			if winners.has(key):
				var old: Dictionary = winners[key]
				var old_column := int(old.get("column", -1))
				if old_column == candidate_column_index:
					match_data["shortcut_trumped"] = true
				else:
					var old_state: Dictionary = _autocomplete_column_states[old_column]
					var old_matches: Array = old_state.get("matches", [])
					var old_index := int(old.get("index", -1))
					if old_index >= 0 and old_index < old_matches.size():
						var old_match: Dictionary = old_matches[old_index]
						old_match["shortcut_trumped"] = true
						old_matches[old_index] = old_match
						old_state["matches"] = old_matches
						_autocomplete_column_states[old_column] = old_state
					winners[key] = {"column": candidate_column_index, "index": match_index}
			if not winners.has(key):
				winners[key] = {"column": candidate_column_index, "index": match_index}
			if candidate_column_index == _autocomplete_active_column_index + 1:
				match_data["highlighted"] = true
			matches[match_index] = match_data
		state["matches"] = matches
		_autocomplete_column_states[candidate_column_index] = state
	_autocomplete_shortcut_winners = winners


func handle_command_palette_shortcut(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not event.is_command_or_control_pressed() or not _is_command_popup_visible():
		return false
	_resolve_visible_keyboard_shortcuts()
	var key := int(event.keycode) | (KEY_MASK_SHIFT if event.shift_pressed else 0)
	if not _autocomplete_shortcut_winners.has(key):
		key = int(event.physical_keycode) | (KEY_MASK_SHIFT if event.shift_pressed else 0)
	if not _autocomplete_shortcut_winners.has(key):
		return false
	var winner: Dictionary = _autocomplete_shortcut_winners[key]
	var column_index := int(winner.get("column", -1))
	if column_index < 0 or column_index >= _autocomplete_column_states.size():
		return false
	var state: Dictionary = _autocomplete_column_states[column_index]
	var matches: Array = state.get("matches", [])
	var match_index := int(winner.get("index", -1))
	if match_index < 0 or match_index >= matches.size():
		return false
	var submission_text := _get_submission_text_for_autocomplete_match(state, matches[match_index])
	if submission_text.is_empty():
		return false
	command_palette_submit_requested.emit(submission_text)
	return true


func _get_widget_path_for_autocomplete_column_state(column_state: Dictionary) -> String:
	var preview_widget_path := str(column_state.get("preview_widget_path", "")).strip_edges()
	if not preview_widget_path.is_empty():
		return preview_widget_path
	var command_path := str(column_state.get("prefix", "")).trim_suffix("/")
	return command_path if _has_widget(command_path) else ""


## A preview column is a read-only look ahead, so its widget stays pinned under the header where
## it always reads as the column's subject. The current and past columns are browsed, so theirs
## belongs inline with the rows it introduces and scrolls away as the user works down the list.
func _get_autocomplete_column_widget_placement(column_state: Dictionary) -> AutocompleteCommandColumn.WidgetPlacement:
	if bool(column_state.get("preview", false)):
		return AutocompleteCommandColumn.WidgetPlacement.PINNED
	return AutocompleteCommandColumn.WidgetPlacement.INLINE


func _configure_autocomplete_column_widget(list: AutocompleteCommandColumn, widget_path: String, placement: AutocompleteCommandColumn.WidgetPlacement) -> void:
	var normalized_widget_path := widget_path.strip_edges()
	if normalized_widget_path.is_empty():
		list.set_embedded_widget(null, "")
		return
	if list.get_embedded_widget_path() == normalized_widget_path:
		# The column is being reused for the same widget, but it may have changed phase since.
		list.set_embedded_widget_placement(placement)
		return
	var widget_instance := _create_widget_instance(normalized_widget_path, "palette")
	if widget_instance != null:
		widget_instance.name = "LogotEmbeddedWidget"
		widget_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		widget_instance.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	else:
		var label := Label.new()
		label.name = "LogotEmbeddedWidget"
		label.text = "Widget unavailable"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		widget_instance = label
	list.set_embedded_widget(widget_instance, normalized_widget_path, placement)


func _create_widget_autocomplete_preview_column(column_state: Dictionary) -> AutocompleteCommandColumn:
	var widget_path := str(column_state.get("preview_widget_path", "")).strip_edges()
	column_state["widget_preview"] = true
	if str(column_state.get("prefix", "")).strip_edges().is_empty() and not widget_path.is_empty():
		column_state["prefix"] = "%s/" % widget_path
	var list := _create_command_autocomplete_column()
	_configure_command_autocomplete_column(list, column_state, -1)
	return list


func _is_widget_autocomplete_preview_state(column_state: Dictionary) -> bool:
	return bool(column_state.get("widget_preview", false))


func _create_autocomplete_column_for_state(column_state: Dictionary) -> Control:
	return _create_command_autocomplete_column()


func _autocomplete_column_matches_state(node: Control, column_state: Dictionary) -> bool:
	return node is AutocompleteCommandColumn


func _replace_autocomplete_column_node(column_index: int, column_state: Dictionary) -> Control:
	var old_node := _autocomplete_column_nodes[column_index] as Control
	var new_node := _create_autocomplete_column_for_state(column_state)
	_command_autocomplete_columns_container.add_child(new_node)
	_command_autocomplete_columns_container.move_child(new_node, old_node.get_index())
	_autocomplete_column_nodes[column_index] = new_node
	_command_autocomplete_columns_container.remove_child(old_node)
	old_node.queue_free()
	return new_node


func _sync_visible_command_autocomplete_columns(start_index: int = 0, scroll_to_end: bool = false) -> void:
	_debug_autocomplete("_sync_visible_command_autocomplete_columns", "start_index=%d" % start_index)
	if not _command_autocomplete_popup or not _command_autocomplete_columns_container:
		return
	if _autocomplete_column_states.is_empty():
		_autocomplete_visible_address_columns.clear()
		_visible_getter_autocomplete_signatures.clear()
		_hide_command_autocomplete_popup(false)
		_debug_autocomplete("_sync_visible_command_autocomplete_columns.empty")
		return

	_debug_autocomplete(
		"_sync_visible_command_autocomplete_columns.pre",
		"start=%d state_columns=%d node_columns=%d child_count=%d popup_visible=%s in_tree=%s" % [
			start_index,
			_autocomplete_column_states.size(),
			_autocomplete_column_nodes.size(),
			_command_autocomplete_columns_container.get_child_count(),
			str(_command_autocomplete_popup.visible),
			str(_command_autocomplete_popup.is_visible_in_tree()),
		]
	)

	while _autocomplete_column_nodes.size() > _autocomplete_column_states.size():
		var node: Control
		node = _autocomplete_column_nodes.pop_back() as Control
		_command_autocomplete_columns_container.remove_child(node)
		node.queue_free()
		_debug_autocomplete(
			"_sync_visible_command_autocomplete_columns.removed_node",
			"remaining_nodes=%d child_count=%d" % [
				_autocomplete_column_nodes.size(),
				_command_autocomplete_columns_container.get_child_count(),
			]
		)

	while _autocomplete_column_nodes.size() < _autocomplete_column_states.size():
		var new_list := _create_autocomplete_column_for_state(_autocomplete_column_states[_autocomplete_column_nodes.size()])
		_command_autocomplete_columns_container.add_child(new_list)
		_autocomplete_column_nodes.append(new_list)
		_debug_autocomplete(
			"_sync_visible_command_autocomplete_columns.added_node",
			"nodes=%d child_count=%d" % [
				_autocomplete_column_nodes.size(),
				_command_autocomplete_columns_container.get_child_count(),
			]
		)

	for column_index in range(start_index, _autocomplete_column_states.size()):
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		var node := _autocomplete_column_nodes[column_index] as Control
		if not _autocomplete_column_matches_state(node, column_state):
			node = _replace_autocomplete_column_node(column_index, column_state)
		var list := node as AutocompleteCommandColumn
		column_state = _configure_command_autocomplete_column(list, column_state, column_index)
		_autocomplete_column_states[column_index] = column_state
		_debug_autocomplete(
			"_sync_visible_command_autocomplete_columns.column",
			"column=%d items=%d selected=%d preview=%s size=%s min_size=%s" % [
				column_index,
				(node as AutocompleteCommandColumn).get_row_count() if node is AutocompleteCommandColumn else 1,
				int(column_state.get("selected_index", -1)) if not column_state.get("preview", false) and column_index == _autocomplete_active_column_index else -1,
				str(column_state.get("preview", false)),
				str(node.size),
				str(node.custom_minimum_size),
			]
		)

	_update_touch_command_autocomplete_column_visibility()
	_position_command_autocomplete_popup()
	_show_command_autocomplete_popup()
	var touch_slide_direction := _pending_touch_column_slide_direction
	_pending_touch_column_slide_direction = 0
	if _is_touch_command_palette_layout() and touch_slide_direction != 0:
		_animate_touch_command_column(touch_slide_direction)
	if _is_touch_command_palette_layout():
		if _command_autocomplete_scroll:
			_command_autocomplete_scroll.scroll_horizontal = 0
	elif scroll_to_end:
		_scroll_command_autocomplete_columns_to_end()
	else:
		_ensure_active_command_column_visible()
	_refresh_autocomplete_visible_address_tracking()
	var active_item_count := -1
	if _autocomplete_active_column_index >= 0 and _autocomplete_active_column_index < _autocomplete_column_states.size():
		active_item_count = _autocomplete_column_states[_autocomplete_active_column_index].get("matches", []).size()
	_debug_autocomplete(
		"_sync_visible_command_autocomplete_columns.post",
		"active=%d active_items=%d node_columns=%d child_count=%d popup_visible=%s in_tree=%s popup_size=%s popup_pos=%s" % [
			_autocomplete_active_column_index,
			active_item_count,
			_autocomplete_column_nodes.size(),
			_command_autocomplete_columns_container.get_child_count(),
			str(_command_autocomplete_popup.visible),
			str(_command_autocomplete_popup.is_visible_in_tree()),
			str(_command_autocomplete_popup.size),
			str(_command_autocomplete_popup.position),
		]
	)


func _render_command_autocomplete_popup() -> void:
	if not _command_autocomplete_popup or not _command_autocomplete_columns_container:
		return
	if _autocomplete_column_states.is_empty():
		_autocomplete_visible_address_columns.clear()
		_visible_getter_autocomplete_signatures.clear()
		_hide_command_autocomplete_popup(false)
		return

	_clear_command_autocomplete_columns()

	for column_index in range(_autocomplete_column_states.size()):
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		var node := _create_autocomplete_column_for_state(column_state)
		if _is_widget_autocomplete_preview_state(column_state):
			column_state["width"] = int(ceil(node.custom_minimum_size.x))
		else:
			column_state = _configure_command_autocomplete_column(node as AutocompleteCommandColumn, column_state, column_index)
		_autocomplete_column_states[column_index] = column_state

		_command_autocomplete_columns_container.add_child(node)
		_autocomplete_column_nodes.append(node)

	_update_touch_command_autocomplete_column_visibility()
	_position_command_autocomplete_popup()
	_show_command_autocomplete_popup()
	var touch_slide_direction := _pending_touch_column_slide_direction
	_pending_touch_column_slide_direction = 0
	if _is_touch_command_palette_layout() and touch_slide_direction != 0:
		_animate_touch_command_column(touch_slide_direction)
	if _is_touch_command_palette_layout():
		if _command_autocomplete_scroll:
			_command_autocomplete_scroll.scroll_horizontal = 0
	else:
		_scroll_command_autocomplete_columns_to_end()
	_refresh_autocomplete_visible_address_tracking()


func _fit_command_autocomplete_columns_to_viewport() -> void:
	if not _is_command_popup_visible() or _is_touch_command_palette_layout():
		return
	var viewport_height := _get_command_autocomplete_column_viewport_height()
	for node in _autocomplete_column_nodes:
		if not (node is AutocompleteCommandColumn):
			continue
		var list := node as AutocompleteCommandColumn
		if is_equal_approx(list.custom_minimum_size.y, float(viewport_height)) and is_equal_approx(list.size.y, float(viewport_height)):
			list.ensure_current_is_visible()
			continue
		list.custom_minimum_size.y = viewport_height
		list.size.y = viewport_height
		list.ensure_current_is_visible()
	_refresh_autocomplete_visible_address_tracking()


func _refresh_command_autocomplete_popup_values() -> void:
	if not _is_command_popup_visible():
		return

	var needs_layout_refresh := false
	for column_index in range(mini(_autocomplete_column_states.size(), _autocomplete_column_nodes.size())):
		var column_state: Dictionary = _refresh_command_preview_option_state(_autocomplete_column_states[column_index])
		if _is_widget_autocomplete_preview_state(column_state):
			_autocomplete_column_states[column_index] = column_state
			continue
		var matches: Array = column_state.get("matches", [])
		var prefix: String = column_state.get("prefix", "")
		var command_name := prefix.trim_suffix("/")
		var column_name := str(column_state.get("column_name_override", _get_command_autocomplete_column_name(prefix)))
		var column_description := str(column_state.get("column_description_override", _get_command_autocomplete_column_description(prefix, command_name)))
		var list := _autocomplete_column_nodes[column_index] as AutocompleteCommandColumn
		if list == null:
			continue
		var selected_match_index := int(column_state.get("selected_index", -1))
		var show_groups := _should_show_command_groups(prefix, str(column_state.get("query", "")), bool(column_state.get("preview", false)))
		var row_build_result := _build_command_autocomplete_rows(prefix, matches, selected_match_index, show_groups)
		var rows: Array[Dictionary] = []
		for row_variant in row_build_result.get("rows", []):
			if row_variant is Dictionary:
				rows.append(row_variant as Dictionary)
		var selected_row_index := int(row_build_result.get("selected_row_index", -1))

		var layout := _measure_command_autocomplete_column_layout(list, prefix, rows, column_name, column_description)
		var new_width := int(layout.get("width", 0))
		if new_width != int(column_state.get("width", 0)):
			column_state["left_width"] = int(layout.get("name_width", 0))
			column_state["value_width"] = int(layout.get("value_width", 0))
			column_state["action_width"] = int(layout.get("action_width", 0))
			column_state["width"] = new_width
			_autocomplete_column_states[column_index] = column_state
			list.custom_minimum_size = Vector2(new_width, list.custom_minimum_size.y)
			list.size = list.custom_minimum_size
			needs_layout_refresh = true

		var is_active_column := column_index == _autocomplete_active_column_index
		list.set_touch_mode(_is_touch_command_palette_layout())
		list.set_column_data(
			rows,
			layout,
			selected_row_index,
			column_state.get("preview", false),
			_get_scaled_autocomplete_item_height(),
			is_active_column,
			column_name,
			column_description
		)
		_hydrate_visible_command_autocomplete_rows(list, column_state, rows)
		var show_touch_navigation := _is_touch_command_palette_layout() and is_active_column and not bool(column_state.get("preview", false))
		var navigation_label := "Close" if str(column_state.get("prefix", "")).is_empty() else "Back"
		list.set_header_navigation(show_touch_navigation, navigation_label)
		_autocomplete_column_states[column_index] = column_state

	if needs_layout_refresh:
		_update_touch_command_autocomplete_column_visibility()
		_position_command_autocomplete_popup()
		if _is_touch_command_palette_layout():
			if _command_autocomplete_scroll:
				_command_autocomplete_scroll.scroll_horizontal = 0
		else:
			_ensure_active_command_column_visible()
	else:
		_update_touch_command_autocomplete_column_visibility()
	_refresh_autocomplete_visible_address_tracking()


func _refresh_autocomplete_visible_address_tracking() -> void:
	var previous_getter_signatures := _visible_getter_autocomplete_signatures.duplicate()
	_autocomplete_visible_address_columns.clear()
	_visible_getter_autocomplete_signatures.clear()
	if not _is_command_popup_visible():
		return

	for column_index in range(mini(_autocomplete_column_nodes.size(), _autocomplete_column_states.size())):
		var list := _autocomplete_column_nodes[column_index]
		if not (list is AutocompleteCommandColumn):
			continue
		if _is_touch_command_palette_layout() and not list.visible:
			continue
		for raw_address in (list as AutocompleteCommandColumn).get_visible_display_variable_addresses():
			var address := _resolve_alias_command_path(str(raw_address).strip_edges())
			if address.is_empty():
				continue
			var tracked_columns: Array = _autocomplete_visible_address_columns.get(address, [])
			if not tracked_columns.has(column_index):
				tracked_columns.append(column_index)
			_autocomplete_visible_address_columns[address] = tracked_columns
			if _is_signal_backed_display_variable(address):
				continue
			if previous_getter_signatures.has(address):
				_visible_getter_autocomplete_signatures[address] = str(previous_getter_signatures[address])
				continue
			var snapshot := _get_display_variable_render_snapshot(address)
			_visible_getter_autocomplete_signatures[address] = str(snapshot.get("signature", ""))


func _poll_visible_autocomplete_display_variable_rows() -> void:
	if not _is_command_popup_visible():
		_autocomplete_visible_address_columns.clear()
		_visible_getter_autocomplete_signatures.clear()
		return
	_refresh_autocomplete_visible_address_tracking()

	var changed_addresses: Array[String] = []
	for raw_address in _visible_getter_autocomplete_signatures.keys():
		var address := str(raw_address)
		var snapshot := _get_display_variable_render_snapshot(address)
		var signature := str(snapshot.get("signature", ""))
		if _visible_getter_autocomplete_signatures.get(address, "") == signature:
			continue
		_visible_getter_autocomplete_signatures[address] = signature
		changed_addresses.append(address)

	if not changed_addresses.is_empty():
		_refresh_command_autocomplete_columns_for_addresses(changed_addresses)


func _refresh_command_autocomplete_columns_for_addresses(addresses: Array[String]) -> void:
	if not _is_command_popup_visible():
		return

	var column_indices: Array[int] = []
	for raw_address in addresses:
		var address := _resolve_alias_command_path(str(raw_address).strip_edges())
		var tracked_columns = _autocomplete_visible_address_columns.get(address, [])
		for raw_column_index in tracked_columns:
			var column_index := int(raw_column_index)
			if column_indices.has(column_index):
				continue
			column_indices.append(column_index)

	if column_indices.is_empty():
		return

	column_indices.sort()
	var needs_layout_refresh := false
	for column_index in column_indices:
		if column_index < 0 or column_index >= _autocomplete_column_states.size() or column_index >= _autocomplete_column_nodes.size():
			continue
		var list := _autocomplete_column_nodes[column_index]
		if not (list is AutocompleteCommandColumn):
			continue
		var previous_width := int(_autocomplete_column_states[column_index].get("width", 0))
		var column_state: Dictionary = _refresh_command_preview_option_state(_autocomplete_column_states[column_index])
		column_state = _configure_command_autocomplete_column(list as AutocompleteCommandColumn, column_state, column_index)
		_autocomplete_column_states[column_index] = column_state
		if int(column_state.get("width", 0)) != previous_width:
			needs_layout_refresh = true

	if needs_layout_refresh:
		_update_touch_command_autocomplete_column_visibility()
		_position_command_autocomplete_popup()
	else:
		_update_touch_command_autocomplete_column_visibility()
	_refresh_autocomplete_visible_address_tracking()
	if _is_touch_command_palette_layout():
		if _command_autocomplete_scroll:
			_command_autocomplete_scroll.scroll_horizontal = 0
	else:
		_ensure_active_command_column_visible()


func refresh_setget_option_highlight(command_name: String) -> void:
	if command_name.is_empty() or not _is_command_popup_visible():
		return

	var refreshed := false
	for column_index in range(_autocomplete_column_states.size()):
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		var tracked_command := str(column_state.get("preview_parent_tier", column_state.get("preview_parent_command", column_state.get("preview_command", ""))))
		if tracked_command != command_name:
			continue
		_autocomplete_column_states[column_index] = _refresh_command_preview_option_state(column_state)
		refreshed = true

	if refreshed:
		_queue_command_autocomplete_column_sync(0, true)


func _set_history_autocomplete_selection(index: int) -> void:
	if not _history_autocomplete_popup:
		return
	if index < 0 or index >= _history_autocomplete_popup.item_count:
		_autocomplete_selected_index = -1
		_history_autocomplete_popup.deselect_all()
		return

	_autocomplete_selected_index = index
	_history_autocomplete_popup.select(_autocomplete_selected_index)
	_history_autocomplete_popup.ensure_current_is_visible()


func _set_active_command_column_selection(index: int) -> void:
	_debug_autocomplete("_set_active_command_column_selection.begin", "requested_index=%d" % index)
	if _autocomplete_active_column_index < 0 or _autocomplete_active_column_index >= _autocomplete_column_states.size():
		_debug_autocomplete("_set_active_command_column_selection.no_active")
		return

	var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
	var matches: Array = column_state.get("matches", [])
	if matches.is_empty():
		_debug_autocomplete("_set_active_command_column_selection.no_matches")
		return

	if index < 0:
		index = matches.size() - 1
	elif index >= matches.size():
		index = 0
	var selection_step := -1 if int(column_state.get("selected_index", -1)) > index else 1
	var attempts := 0
	while bool(matches[index].get("disabled", false)) and attempts < matches.size():
		index = posmod(index + selection_step, matches.size())
		attempts += 1
	if bool(matches[index].get("disabled", false)):
		return

	column_state["selected_index"] = index
	_autocomplete_column_states[_autocomplete_active_column_index] = column_state
	_autocomplete_highlighted_tiers[str(column_state.get("prefix", ""))] = str(matches[index].get("tier", ""))
	_debug_autocomplete("_set_active_command_column_selection.selected", "resolved_index=%d tier=%s" % [index, str(matches[index].get("tier", ""))])
	_debug_command_popup_height("_set_active_command_column_selection.selected_height")
	var preview_column_changed := false
	if not _autocomplete_global_search_mode:
		preview_column_changed = _refresh_active_preview_column_state()
	_sync_visible_command_autocomplete_columns(0, preview_column_changed)
	call_deferred("_debug_command_popup_height", "_set_active_command_column_selection.deferred_height")


func _get_active_autocomplete_match() -> Dictionary:
	if _autocomplete_active_column_index < 0 or _autocomplete_active_column_index >= _autocomplete_column_states.size():
		return {}

	var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
	var matches: Array = column_state.get("matches", [])
	var selected_index := int(column_state.get("selected_index", -1))
	if selected_index < 0 or selected_index >= matches.size():
		return {}

	return matches[selected_index]


func has_active_command_autocomplete_match() -> bool:
	if not _is_command_popup_visible():
		return false
	return not _get_active_autocomplete_match().is_empty()


func is_active_command_match_submittable() -> bool:
	if not _is_command_popup_visible():
		return false
	var match_data := _get_active_autocomplete_match()
	return not match_data.is_empty() and bool(match_data.get("has_command", false))


func get_active_command_submission_text() -> String:
	if not line_edit:
		return ""

	var input_text := line_edit.text.strip_edges()
	if not _is_command_popup_visible():
		return input_text

	var match_data := _get_active_autocomplete_match()
	if match_data.is_empty():
		return input_text

	var tier := str(match_data.get("tier", ""))
	if tier.is_empty():
		return input_text
	return "/" + tier


## Update the autocomplete popup with filtered and sorted suggestions
func update_autocomplete_popup() -> void:
	_debug_autocomplete_update_count += 1
	_debug_autocomplete("update_autocomplete_popup.begin")
	if not _command_autocomplete_popup or not line_edit:
		return

	if not line_edit.text.begins_with("/"):
		_debug_autocomplete("update_autocomplete_popup.hide_non_command")
		hide_autocomplete()
		return

	if _get_registered_addresses().is_empty():
		_debug_autocomplete("update_autocomplete_popup.hide_no_addresses")
		hide_autocomplete()
		return

	if not _build_command_autocomplete_state():
		_debug_autocomplete("update_autocomplete_popup.hide_no_state")
		hide_autocomplete()
		return

	if _history_autocomplete_popup:
		_history_autocomplete_popup.visible = false
	_sync_visible_command_autocomplete_columns(0, false)
	_debug_autocomplete("update_autocomplete_popup.end")


## Hide the autocomplete popup
func hide_autocomplete() -> void:
	_debug_autocomplete("hide_autocomplete.begin")
	if _history_autocomplete_popup:
		_history_autocomplete_popup.visible = false
		_history_autocomplete_popup.tooltip_text = ""
		_autocomplete_selected_index = -1
		_history_autocomplete_popup.deselect_all()

	if _command_autocomplete_popup:
		_hide_command_autocomplete_popup()

	_history_can_switch_to_commands = false
	_autocomplete_column_states.clear()
	_autocomplete_active_column_index = -1
	_autocomplete_global_search_mode = false
	_autocomplete_pre_filter_highlighted_tiers.clear()
	_pending_autocomplete_column_sync_start = -1
	_autocomplete_column_sync_queued = false
	_pending_autocomplete_column_sync_scroll_to_end = false
	_autocomplete_visible_address_columns.clear()
	_visible_getter_autocomplete_signatures.clear()
	_debug_autocomplete("hide_autocomplete.end")


## Check if autocomplete popup is visible
func is_autocomplete_visible() -> bool:
	return _is_history_popup_visible() or _is_command_popup_visible()


func _is_command_popup_visible() -> bool:
	return _command_autocomplete_popup and _command_autocomplete_popup.visible and not _autocomplete_column_states.is_empty()


func _is_history_popup_visible() -> bool:
	return _history_autocomplete_popup and _history_autocomplete_popup.visible and _history_autocomplete_popup.item_count > 0


func _should_show_recent_history() -> bool:
	if not line_edit:
		return false

	var input_text := line_edit.text.strip_edges()
	return input_text.is_empty() or input_text == "/"


func begin_command_palette_reset_navigation() -> void:
	_history_access_locked_until_reset = false
	_root_command_selection_reset_pending = true


func _show_command_popup_for_default_input() -> void:
	if not line_edit:
		return

	_history_can_switch_to_commands = false
	_history_access_locked_until_reset = true
	_root_command_selection_reset_pending = false
	if line_edit.text.strip_edges().is_empty():
		line_edit.text = "/"
		line_edit.caret_column = line_edit.text.length()

	update_autocomplete_popup()


func _show_root_command_popup() -> void:
	if not line_edit:
		return

	_history_can_switch_to_commands = false
	_history_access_locked_until_reset = true
	_root_command_selection_reset_pending = false
	line_edit.text = "/"
	line_edit.caret_column = line_edit.text.length()
	update_autocomplete_popup()


func _show_recent_history_popup(query: String = "", allow_switch_to_commands: bool = false) -> void:
	_history_can_switch_to_commands = allow_switch_to_commands
	_root_command_selection_reset_pending = false
	if _history_autocomplete_popup:
		_history_autocomplete_popup.tooltip_text = AUTOCOMPLETE_HISTORY_HINT if allow_switch_to_commands else ""
	_update_history_popup(query)
	if _history_autocomplete_popup and _history_autocomplete_popup.visible and _history_autocomplete_popup.item_count > 0:
		_set_history_autocomplete_selection(0)


## Select the previous item in the autocomplete (moving up visually)
func autocomplete_select_prev() -> void:
	_debug_autocomplete("autocomplete_select_prev.begin")
	if line_edit and line_edit.text.strip_edges().is_empty():
		if not is_autocomplete_visible():
			_show_command_popup_for_default_input()
			return
	elif line_edit and line_edit.text == "/":
		if not _is_command_popup_visible():
			update_autocomplete_popup()
			return

	# If input doesn't start with /, show command history
	if line_edit and not line_edit.text.begins_with("/"):
		if not _is_history_popup_visible():
			_show_recent_history_popup(line_edit.text, false)
			return

	if _is_command_popup_visible():
		_history_access_locked_until_reset = true
		_root_command_selection_reset_pending = false
		var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
		var selected_index := int(column_state.get("selected_index", -1)) - 1
		_debug_autocomplete("autocomplete_select_prev.command", "next_index=%d" % selected_index)
		_set_active_command_column_selection(selected_index)
		return

	if not _is_history_popup_visible() or not _history_autocomplete_popup:
		return
	if _history_autocomplete_popup.item_count == 0:
		return

	var next_index := _autocomplete_selected_index - 1
	if _autocomplete_selected_index < 0:
		next_index = _history_autocomplete_popup.item_count - 1
	elif next_index < 0:
		if _history_can_switch_to_commands and _autocomplete_selected_index == 0:
			_show_root_command_popup()
			return
		next_index = _history_autocomplete_popup.item_count - 1

	_set_history_autocomplete_selection(next_index)


## Select the next item in the autocomplete (moving down visually)
func autocomplete_select_next() -> void:
	_debug_autocomplete("autocomplete_select_next.begin")
	if _should_show_recent_history() and not _is_history_popup_visible() and not _is_command_popup_visible():
		if _history_access_locked_until_reset:
			_show_command_popup_for_default_input()
		else:
			_show_recent_history_popup("", true)
		return

	if _is_command_popup_visible():
		var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
		var matches: Array = column_state.get("matches", [])
		if matches.is_empty():
			_debug_autocomplete("autocomplete_select_next.command_no_matches")
			return
		var selected_index := int(column_state.get("selected_index", -1))
		var is_root_column := str(column_state.get("prefix", "")).is_empty()
		if is_root_column and selected_index < 0 and not _history_access_locked_until_reset:
			_show_recent_history_popup("", true)
			return
		if is_root_column and selected_index >= matches.size() - 1 and not _history_access_locked_until_reset:
			_show_recent_history_popup("", true)
			return
		var next_index := selected_index + 1
		_debug_autocomplete("autocomplete_select_next.command", "next_index=%d" % next_index)
		_set_active_command_column_selection(next_index)
		return

	if not _is_history_popup_visible() or not _history_autocomplete_popup:
		return
	if _history_autocomplete_popup.item_count == 0:
		return

	var next_index := _autocomplete_selected_index + 1
	if _autocomplete_selected_index < 0:
		next_index = _history_autocomplete_popup.item_count - 1
	elif next_index >= _history_autocomplete_popup.item_count:
		next_index = 0

	_set_history_autocomplete_selection(next_index)


func _find_autocomplete_group_navigation_index(matches: Array, selected_index: int, direction: int) -> int:
	if matches.is_empty() or direction == 0:
		return -1
	if selected_index < 0 or selected_index >= matches.size():
		return -1

	var current_group_name := str(matches[selected_index].get("group_name", "")).strip_edges()
	if current_group_name.is_empty():
		return -1

	var candidate_index := selected_index + direction
	while candidate_index >= 0 and candidate_index < matches.size():
		var candidate_group_name := str(matches[candidate_index].get("group_name", "")).strip_edges()
		if candidate_group_name.is_empty():
			return -1
		if candidate_group_name != current_group_name:
			while candidate_index > 0 and str(matches[candidate_index - 1].get("group_name", "")).strip_edges() == candidate_group_name:
				candidate_index -= 1
			return candidate_index
		candidate_index += direction

	return -1


func _select_autocomplete_group(direction: int) -> bool:
	if not _is_command_popup_visible():
		return false
	if _autocomplete_active_column_index < 0 or _autocomplete_active_column_index >= _autocomplete_column_states.size():
		return false

	var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
	var matches: Array = column_state.get("matches", [])
	var selected_index := int(column_state.get("selected_index", -1))
	var group_index := _find_autocomplete_group_navigation_index(matches, selected_index, direction)
	if group_index == -1:
		return false

	_history_access_locked_until_reset = true
	_root_command_selection_reset_pending = false
	_set_active_command_column_selection(group_index)
	return true


func autocomplete_select_prev_group() -> bool:
	return _select_autocomplete_group(-1)


func autocomplete_select_next_group() -> bool:
	return _select_autocomplete_group(1)


func get_selected_history_command() -> String:
	if not _is_history_popup_visible() or not _history_autocomplete_popup:
		return ""
	if _autocomplete_selected_index < 0 or _autocomplete_selected_index >= _history_autocomplete_popup.item_count:
		return ""

	var metadata = _history_autocomplete_popup.get_item_metadata(_autocomplete_selected_index)
	if metadata is Dictionary and metadata.get("history", false):
		return str(metadata.get("command", "")).strip_edges()
	return _history_autocomplete_popup.get_item_text(_autocomplete_selected_index).strip_edges()


func _reveal_selected_history_command_path() -> bool:
	if not line_edit:
		return false

	var selected_command := get_selected_history_command()
	if selected_command.is_empty() or not selected_command.begins_with("/"):
		return false

	var command_path := selected_command.substr(1)
	var first_space := command_path.find(" ")
	if first_space != -1:
		command_path = command_path.substr(0, first_space)
	command_path = command_path.strip_edges()
	while command_path.ends_with("/"):
		command_path = command_path.left(command_path.length() - 1)
	return _reveal_command_path(command_path)


func _reveal_command_path(command_path: String) -> bool:
	if not line_edit:
		return false

	var segments := _split_autocomplete_segments(command_path)
	if segments.is_empty():
		_set_line_edit_command_path("", false)
		update_autocomplete_popup()
		return true

	var prefix := ""
	for segment_index in range(segments.size()):
		var tier := prefix + segments[segment_index]
		_autocomplete_highlighted_tiers[prefix] = tier
		if segment_index < segments.size() - 1:
			prefix = tier + "/"

	if segments.size() == 1:
		_set_line_edit_command_path("", false)
	else:
		var committed_segments := segments.slice(0, segments.size() - 1)
		_set_line_edit_command_path("/".join(committed_segments), true)
	update_autocomplete_popup()
	return true


func _can_move_right_into_command_column(tier: String, match_data: Dictionary) -> bool:
	if tier.is_empty():
		return false

	if tier == AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND:
		return true

	if match_data.get("has_children", false):
		return not _build_tier_matches(tier + "/", "").is_empty()

	if not match_data.get("has_command", false):
		return false

	return not _build_command_option_matches(tier, 0).is_empty()


func autocomplete_move_right(require_actionable_destination: bool = false) -> void:
	if _is_history_popup_visible():
		_reveal_selected_history_command_path()
		return

	if not line_edit or not _is_command_popup_visible():
		return

	var match_data := _get_active_autocomplete_match()
	if match_data.is_empty():
		return

	var tier := str(match_data.get("tier", "")).strip_edges()
	if tier.is_empty():
		return

	if _autocomplete_global_search_mode:
		_reveal_command_path(tier)
		return

	if require_actionable_destination and not _can_move_right_into_command_column(tier, match_data):
		return

	if _is_touch_command_palette_layout():
		_pending_touch_column_slide_direction = 1
	_set_line_edit_command_path(tier, true)
	update_autocomplete_popup()


func autocomplete_move_left() -> void:
	if not line_edit or not line_edit.text.begins_with("/"):
		return

	var input_state := _get_autocomplete_input_state()
	var committed_segments: Array[String] = []
	for segment in input_state.get("segments", []):
		committed_segments.append(str(segment))
	if committed_segments.is_empty():
		return

	committed_segments.remove_at(committed_segments.size() - 1)
	if committed_segments.is_empty():
		_set_line_edit_command_path("", false)
	else:
		_set_line_edit_command_path("/".join(committed_segments), true)
	if _is_touch_command_palette_layout():
		_pending_touch_column_slide_direction = -1
	update_autocomplete_popup()


func touch_command_palette_back_or_close() -> bool:
	if not _is_touch_command_palette_layout() or not _is_command_popup_visible():
		return false
	if line_edit != null and line_edit.text.strip_edges().begins_with("/"):
		var input_state := _get_autocomplete_input_state()
		if not (input_state.get("segments", []) as Array).is_empty():
			autocomplete_move_left()
			return true
	if _autocomplete_active_column_index <= 0:
		command_palette_close_requested.emit()
		return true
	autocomplete_move_left()
	return true


## Confirm the autocomplete selection and close the popup
func confirm_autocomplete() -> void:
	if _is_history_popup_visible():
		autocomplete_move_right()
		if line_edit:
			line_edit.grab_focus()
		return

	if _is_command_popup_visible():
		autocomplete_move_right()
		if line_edit:
			line_edit.grab_focus()
		return

	hide_autocomplete()
	if line_edit:
		line_edit.grab_focus()


## Handle autocomplete via Tab key (legacy behavior + popup support)
func autocomplete() -> void:
	if is_autocomplete_visible():
		confirm_autocomplete()
		return

	# Legacy behavior for when popup is not used (updated for multi-tier)
	var addresses := _get_registered_addresses()
	if addresses.is_empty():
		return

	var text := line_edit.text
	if not text.begins_with("/"):
		return

	var full_text := text.substr(1)  # Remove leading /

	# Determine current prefix
	var prefix := ""
	var last_slash := full_text.rfind("/")
	if last_slash != -1:
		prefix = full_text.substr(0, last_slash + 1)

	if _suggesting:
		for i in range(_suggestions.size()):
			if _current_suggest == i:
				var suggestion: Dictionary = _suggestions[i]
				var tier: String = suggestion.get("tier", "")
				var has_children: bool = suggestion.get("has_children", false)
				_set_line_edit_command_path(tier, has_children)

				# If has children, refresh suggestions for the new prefix
				if has_children:
					_suggesting = false
					_suggestions.clear()
					_current_suggest = 0
					return

				if _current_suggest == _suggestions.size() - 1:
					_current_suggest = 0
				else:
					_current_suggest += 1
				return
	else:
		_suggesting = true
		_suggestions = _build_tier_matches(prefix, "")

		_suggestions.sort_custom(func(a, b): return str(a.get("tier", "")) < str(b.get("tier", "")))
		autocomplete()


## Reset autocomplete state
func reset_autocomplete() -> void:
	_suggestions.clear()
	_current_suggest = 0
	_suggesting = false
	hide_autocomplete()


func clear_autocomplete_highlight_memory() -> void:
	_autocomplete_highlighted_tiers.clear()
	_autocomplete_pre_filter_highlighted_tiers.clear()


## Add a command to the history
func add_to_command_history(command: String) -> void:
	if command.is_empty():
		return
	# Remove duplicate if it exists
	var existing_index := _command_history.find(command)
	if existing_index != -1:
		_command_history.remove_at(existing_index)
	# Add to end (most recent)
	_command_history.append(command)
	# Trim history if too large
	while _command_history.size() > _max_history_size:
		_command_history.remove_at(0)


func clear_command_history() -> void:
	_command_history.clear()
	hide_autocomplete()


## Update autocomplete popup to show command history
func _update_history_popup(query: String = "") -> void:
	if not _history_autocomplete_popup or not line_edit:
		return

	if _command_history.is_empty():
		hide_autocomplete()
		return

	# Filter history by query if provided
	var filtered_history: Array[String] = []
	var query_lower := query.to_lower()
	for cmd in _command_history:
		if query.is_empty() or cmd.to_lower().contains(query_lower):
			filtered_history.append(cmd)

	if filtered_history.is_empty():
		hide_autocomplete()
		return

	# Populate newest first so Down walks older commands.
	_history_autocomplete_popup.clear()
	for i in range(filtered_history.size() - 1, -1, -1):
		var cmd := filtered_history[i]
		_history_autocomplete_popup.add_item(cmd)
		_history_autocomplete_popup.set_item_metadata(_history_autocomplete_popup.item_count - 1, {
			"history": true,
			"command": cmd,
			"has_children": true,
			"has_command": true,
		})

	# Position the popup above the input line
	_position_history_autocomplete_popup()

	# Show the popup
	if _command_autocomplete_popup:
		_command_autocomplete_popup.visible = false
		_update_command_palette_log_reserved_space()
	_history_autocomplete_popup.visible = true
	_set_history_autocomplete_selection(0)


## Handle text changes for autocomplete
func on_text_changed_autocomplete(new_text: String) -> void:
	if _suppress_autocomplete_text_changes:
		return
	_pending_autocomplete_text = new_text
	if _autocomplete_text_update_queued:
		return
	_autocomplete_text_update_queued = true
	call_deferred("_flush_autocomplete_text_update")


func _flush_autocomplete_text_update() -> void:
	_autocomplete_text_update_queued = false
	var new_text := _pending_autocomplete_text
	if line_edit != null and new_text != line_edit.text:
		return
	_debug_autocomplete("on_text_changed_autocomplete.begin", "new_text=%s" % new_text)
	# Reset old autocomplete state
	_suggestions.clear()
	_current_suggest = 0
	_suggesting = false
	if new_text.strip_edges() != "/":
		_root_command_selection_reset_pending = false

	if new_text.begins_with("/"):
		# It's a command being typed, show autocomplete popup
		if _search_filter != "":
			_search_filter = ""
			_rebuild_display()
		update_autocomplete_popup()
	elif _command_entry_mode:
		hide_autocomplete()
	else:
		# Apply search filter and hide autocomplete
		hide_autocomplete()
		_search_filter = new_text.strip_edges().to_lower()
		_rebuild_display()
