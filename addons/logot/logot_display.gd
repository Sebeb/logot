@tool
class_name LogotDisplay
extends Control

## Logot display functionality.
## Provides all filtering, display, sidebar, and settings logic.
## Used via composition by logot.gd and logot_editor_panel.gd.

# =============================================================================
# SIGNALS
# =============================================================================

signal custom_setting_changed(setting_name: String, value: bool)
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

	func _init(
		in_function: Callable,
		in_arguments: PackedStringArray,
		in_required: int = 0,
		in_description: String = "",
		in_argument_options: Array = [],
		in_argument_options_provider: Callable = Callable(),
		in_value_getter: Callable = Callable()
	):
		function = in_function
		arguments = in_arguments
		required = in_required
		description = in_description
		argument_options = in_argument_options
		argument_options_provider = in_argument_options_provider
		value_getter = in_value_getter


class LogotDisplayVariable:
	var getter: Callable

	func _init(in_getter: Callable):
		getter = in_getter


class AutocompleteCommandColumn:
	extends Control

	const CELL_GAP := 12.0
	const CONTENT_PADDING_X := 12.0
	const HEADER_TOP_PADDING := 8.0
	const HEADER_BOTTOM_PADDING := 8.0
	const HEADER_CONTENT_GAP := 4.0
	const VALUE_PILL_PADDING_X := 10.0
	const VALUE_PILL_HEIGHT := 20.0
	const ACTION_ICON_DIAMETER := 18.0
	const ACTION_ICON_GAP := 6.0

	var _rows: Array[Dictionary] = []
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
	var _value_pill_color := Color(0.19, 0.2, 0.24, 0.95)
	var _value_pill_border_color := Color(0.38, 0.4, 0.48, 1.0)
	var _selected_value_pill_color := Color(0.24, 0.34, 0.48, 0.98)
	var _selected_value_pill_border_color := Color(0.55, 0.7, 0.9, 1.0)
	var _inactive_selected_value_pill_color := Color(0.22, 0.27, 0.34, 0.96)
	var _inactive_selected_value_pill_border_color := Color(0.44, 0.52, 0.64, 1.0)
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

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		_header_label = RichTextLabel.new()
		_header_label.bbcode_enabled = true
		_header_label.fit_content = true
		_header_label.scroll_active = false
		_header_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_header_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header_label.focus_mode = Control.FOCUS_NONE
		add_child(_header_label)
		_configure_value_pill_styles()

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
		_selected_stylebox = theme_source.get_theme_stylebox("selected")
		_selected_focus_stylebox = theme_source.get_theme_stylebox("selected_focus")
		_configure_inactive_selection_styles()
		_configure_value_pill_styles()
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
		_update_header_layout()
		_ensure_selection_visible()
		queue_redraw()

	func get_row_count() -> int:
		return _rows.size()

	func ensure_current_is_visible() -> void:
		_ensure_selection_visible()
		queue_redraw()

	func _ensure_selection_visible() -> void:
		if _rows.is_empty():
			_scroll_row = 0
			return

		var visible_rows := _get_visible_row_capacity()
		var max_scroll := maxi(0, _rows.size() - visible_rows)
		if _is_preview:
			_scroll_row = max_scroll
			return

		if _selected_index < 0:
			_scroll_row = 0
			return

		if _selected_index < _scroll_row:
			_scroll_row = _selected_index
		elif _selected_index >= _scroll_row + visible_rows:
			_scroll_row = _selected_index - visible_rows + 1

		_scroll_row = clampi(_scroll_row, 0, max_scroll)

	func _get_visible_row_capacity() -> int:
		return maxi(1, int(floor(maxf(0.0, size.y - _header_height) / maxf(1.0, float(_row_height)))))

	func _draw() -> void:
		var visible_rows := _get_visible_row_capacity()
		var start_index := clampi(_scroll_row, 0, maxi(0, _rows.size() - visible_rows))
		var end_index := mini(_rows.size(), start_index + visible_rows)
		var baseline_offset := _get_baseline_offset()
		var rows_top := _header_height
		var rows_area_height := maxf(0.0, size.y - _header_height)
		if _rows.size() <= visible_rows:
			var drawn_rows := maxi(0, end_index - start_index)
			var drawn_height := float(drawn_rows * _row_height)
			rows_top += maxf(0.0, rows_area_height - drawn_height)

		for row_index in range(start_index, end_index):
			var row_top := rows_top + float((row_index - start_index) * _row_height)
			var row_rect := Rect2(0.0, row_top, size.x, _row_height)
			var row_data: Dictionary = _rows[row_index]
			var selection_state := _get_row_selection_state(row_index)
			_draw_row_background(row_rect, row_data, selection_state)
			_draw_row_content(row_rect, row_data, selection_state, baseline_offset)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_update_header_layout()

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
		_header_label.position = Vector2(CONTENT_PADDING_X, HEADER_TOP_PADDING)
		_header_label.size = Vector2(
			maxf(0.0, size.x - CONTENT_PADDING_X * 2.0),
			maxf(0.0, size.y - HEADER_TOP_PADDING)
		)

		var content_height := float(_header_label.get_content_height())
		_header_height = HEADER_TOP_PADDING + content_height + HEADER_BOTTOM_PADDING + HEADER_CONTENT_GAP

	func _escape_bbcode(text: String) -> String:
		return text.replace("[", "[lb]").replace("]", "[rb]")

	func _get_row_selection_state(row_index: int) -> int:
		if row_index != _selected_index:
			return 0
		if _is_preview:
			return 1
		if _selected_is_active:
			return 2
		return 1

	func _draw_row_background(row_rect: Rect2, row_data: Dictionary, selection_state: int) -> void:
		if selection_state != 0:
			var stylebox: StyleBox = _inactive_selected_stylebox if selection_state == 1 else (_selected_focus_stylebox if _selected_focus_stylebox != null else _selected_stylebox)
			if stylebox != null:
				stylebox.draw(get_canvas_item(), row_rect)
		var row_tint = row_data.get("row_background_tint")
		if row_tint is Color:
			draw_rect(row_rect, row_tint as Color, true)

	func _draw_row_content(row_rect: Rect2, row_data: Dictionary, selection_state: int, baseline_offset: float) -> void:
		if _font == null:
			return

		var value_width := float(_metrics.get("value_width", 0))
		var action_width := float(_metrics.get("action_width", 0))
		var text_color := _resolve_row_text_color(selection_state)
		var text_baseline := row_rect.position.y + baseline_offset
		var content_left := row_rect.position.x + CONTENT_PADDING_X
		var content_right := row_rect.position.x + row_rect.size.x - CONTENT_PADDING_X
		var info_cursor_x := content_right

		var action_rect := Rect2()
		if action_width > 0.0:
			action_rect = Rect2(info_cursor_x - action_width, row_rect.position.y, action_width, row_rect.size.y)
			info_cursor_x = action_rect.position.x - CELL_GAP

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
		var label_text := _fit_text_to_width(str(row_data.get("label", "")), label_max_width)
		if not label_text.is_empty():
			draw_string(_font, Vector2(content_left, text_baseline), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)

		var value_text := str(row_data.get("value_text", ""))
		if not value_text.is_empty() and value_rect.size.x > 0.0:
			var value_text_max_width := maxf(0.0, value_rect.size.x - VALUE_PILL_PADDING_X * 2.0)
			var fitted_value_text := _fit_text_to_width(value_text, value_text_max_width)
			draw_style_box(_resolve_value_pill_style(selection_state), value_rect)
			if not fitted_value_text.is_empty():
				draw_string(_font, Vector2(value_rect.position.x + VALUE_PILL_PADDING_X, text_baseline), fitted_value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, text_color)

		if action_rect.size.x > 0.0:
			_draw_action_icons(
				action_rect,
				bool(row_data.get("has_children", false)),
				bool(row_data.get("can_submit", false)),
				selection_state,
				text_color
			)

	func _draw_action_icons(action_rect: Rect2, has_children: bool, can_submit: bool, selection_state: int, icon_color: Color) -> void:
		if action_rect.size.x <= 0.0:
			return

		var icon_count := 0
		if has_children:
			icon_count += 1
		if can_submit:
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

	func _get_baseline_offset() -> float:
		if _font == null:
			return float(_row_height) * 0.7
		var font_height := _font.get_height(_font_size)
		return floor((float(_row_height) - font_height) * 0.5) + _font.get_ascent(_font_size)

	func _measure_text(text: String) -> float:
		if _font == null:
			return text.length() * 8.0
		return _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x

	func _fit_text_to_width(text: String, max_width: float) -> String:
		if text.is_empty() or max_width <= 0.0:
			return ""
		if _measure_text(text) <= max_width:
			return text

		var ellipsis := "..."
		if _measure_text(ellipsis) > max_width:
			return ""

		var truncated := text
		while not truncated.is_empty() and _measure_text(truncated + ellipsis) > max_width:
			truncated = truncated.left(truncated.length() - 1)

		return truncated + ellipsis

	func _configure_value_pill_styles() -> void:
		for stylebox in [_value_pill_style, _selected_value_pill_style, _inactive_selected_value_pill_style]:
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
const AUTOCOMPLETE_ITEM_HEIGHT := 28
const AUTOCOMPLETE_MAX_VISIBLE_ITEMS := 10
const AUTOCOMPLETE_FIXED_VISIBLE_ITEMS := 10
const AUTOCOMPLETE_COLUMN_PADDING := 24
const AUTOCOMPLETE_VALUE_PILL_EXTRA_WIDTH := 20
const AUTOCOMPLETE_ACTION_ICON_DIAMETER := 18
const AUTOCOMPLETE_ACTION_ICON_GAP := 6
const AUTOCOMPLETE_CELL_GAP := 12
const AUTOCOMPLETE_POPUP_GAP := 4
const AUTOCOMPLETE_COLUMN_MAX_FALLBACK_WIDTH := 480
const AUTOCOMPLETE_COLUMN_MIN_WIDTH := 180
const AUTOCOMPLETE_COLUMN_HARD_MAX_WIDTH := 320
const AUTOCOMPLETE_VALUE_MAX_WIDTH := 180
const AUTOCOMPLETE_HEADER_WIDTH_BUFFER := 28
const AUTOCOMPLETE_ROOT_COMMANDS_HINT := "press down for history"
const AUTOCOMPLETE_HISTORY_HINT := "press up for commands"
const AUTOCOMPLETE_GLOBAL_SEARCH_PREFIX := "__global_search__"
const AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND := "search"
const PINS_VIEW_ALIAS_PREFIX := "pins/view/"
const INVALID_INPUT_ROW_BG_COLOR := Color(0.5, 0.12, 0.12, 0.5)
const DEBUG_AUTOCOMPLETE_DEFAULT := false
const DEBUG_AUTOCOMPLETE_ENV := "LOGOT_DEBUG_AUTOCOMPLETE"
const DEBUG_AUTOCOMPLETE_SETTING := "debug/logot/autocomplete_trace"


# =============================================================================
# UI REFERENCES
# =============================================================================

var rich_label: RichTextLabel
var line_edit: LineEdit
var _sidebar  # LogotSidebar - type removed to avoid circular dependency
var _sidebar_toggle_btn: Button
var _clear_btn: Button
var _main_container: Control
var _logot_container: VBoxContainer
var _input_row: HBoxContainer


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

var _last_displayed_entry = null
var _last_displayed_count: int = 0
var _bbcode_before_last_entry: String = ""  # Stores BBCode content before the last displayed entry

# Composition support - providers set by owner
var _settings_file: String = ""
var _welcome_message: String = "Logot\n"
var _log_entries_provider: Callable
var _entry_text_provider: Callable
var _commands_provider: Callable  # Returns Dictionary of command_name -> command_data
var _display_variables_provider: Callable  # Returns Dictionary of address -> display_variable
var _rejected_level_count_provider: Callable  # Returns int for a given level
var _rejected_channel_count_provider: Callable  # Returns int for a given channel
var _level_visibility_getter: Callable  # Returns int (VisibilityMode) for a given level
var _level_visibility_setter: Callable  # Sets visibility mode for a given level
var _channel_visibility_getter: Callable  # Returns int (VisibilityMode) for a given channel
var _channel_visibility_setter: Callable  # Sets visibility mode for a given channel
var _instance_visibility_getter: Callable  # Returns int (VisibilityMode) for a given session_id
var _custom_settings: Array = []

# Autocomplete state
var _history_autocomplete_popup: ItemList
var _command_autocomplete_popup: PanelContainer
var _command_autocomplete_scroll: ScrollContainer
var _command_autocomplete_columns_container: HBoxContainer
var _autocomplete_selected_index := -1
var _autocomplete_column_states: Array[Dictionary] = []
var _autocomplete_column_nodes: Array[Control] = []
var _autocomplete_active_column_index := -1
var _autocomplete_highlighted_tiers: Dictionary = {}
var _pending_autocomplete_column_sync_start := -1
var _autocomplete_column_sync_queued := false
var _autocomplete_global_search_mode := false
var _suggestions := []
var _current_suggest := 0
var _suggesting := false
var _command_entry_mode := false

# Command history
var _command_history: Array[String] = []
var _max_history_size := 50
var _history_can_switch_to_commands := false

# Display variables
var _pinned_display_variables: Array[String] = []
var _pinned_overlay_label: RichTextLabel
var _saved_pin_overlays: Dictionary = {}  # {overlay_name: Array[String]}


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


func set_display_variables_provider(provider: Callable) -> void:
	_display_variables_provider = provider


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


func set_command_autocomplete_popup(popup: PanelContainer, scroll: ScrollContainer, columns_container: HBoxContainer) -> void:
	_command_autocomplete_popup = popup
	_command_autocomplete_scroll = scroll
	_command_autocomplete_columns_container = columns_container
	if _command_autocomplete_popup:
		_command_autocomplete_popup.clip_contents = true
	if _command_autocomplete_scroll:
		_command_autocomplete_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_command_autocomplete_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_command_autocomplete_scroll.clip_contents = true


func add_custom_setting(name: String, label: String, default: bool) -> void:
	_custom_settings.append({"name": name, "label": label, "default": default})
	if _sidebar:
		_sidebar.configure_settings(_build_sidebar_settings())
		_sync_sidebar_state()


func set_custom_setting(name: String, value: bool) -> void:
	if _sidebar:
		_sidebar.set_setting(name, value)


func initialize_display() -> void:
	_init_base()
	_setup_ui_nodes()
	_connect_ui_signals()
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
	return fallback


func apply_setting(name: String, value: bool) -> void:
	if _sidebar:
		_sidebar.set_setting(name, value)
	_on_setting_changed(name, value)


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


func show_command_entry_mode(prefill_text: String = "/") -> void:
	_command_entry_mode = true
	_update_command_entry_mode_visibility()
	if not line_edit:
		return

	line_edit.text = prefill_text
	line_edit.caret_column = line_edit.text.length()
	line_edit.grab_focus()
	on_text_changed_autocomplete(line_edit.text)


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

	if _sidebar:
		_sidebar.visible = _sidebar_visible and not _command_entry_mode

	_refresh_pinned_display_variables()


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


func pin_display_variable(address: String) -> void:
	if address.is_empty() or _pinned_display_variables.has(address):
		return
	_pinned_display_variables.append(address)
	_save_filter_settings()
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()


func unpin_display_variable(address: String) -> void:
	var index := _pinned_display_variables.find(address)
	if index == -1:
		return
	_pinned_display_variables.remove_at(index)
	_save_filter_settings()
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()


func set_display_variable_pinned(address: String, pinned: bool) -> void:
	if pinned:
		pin_display_variable(address)
	else:
		unpin_display_variable(address)


func is_display_variable_pinned(address: String) -> bool:
	return _pinned_display_variables.has(address)


func get_pinned_display_variables() -> Array[String]:
	return _pinned_display_variables.duplicate()


func clear_pinned_display_variables() -> void:
	if _pinned_display_variables.is_empty():
		return
	_pinned_display_variables.clear()
	_save_filter_settings()
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
	_saved_pin_overlays[overlay_name] = _pinned_display_variables.duplicate()
	_save_filter_settings()
	return true


func load_pinned_overlay(name: String) -> bool:
	var overlay_name := name.strip_edges()
	if overlay_name.is_empty() or not _saved_pin_overlays.has(overlay_name):
		return false

	_pinned_display_variables.clear()
	var stored_addresses = _saved_pin_overlays[overlay_name]
	if stored_addresses is Array:
		for address in stored_addresses:
			var address_str := str(address)
			if address_str.is_empty() or _pinned_display_variables.has(address_str):
				continue
			_pinned_display_variables.append(address_str)

	_save_filter_settings()
	_refresh_pinned_display_variables()
	_refresh_pin_option_autocomplete_state()
	return true


func _refresh_pin_option_autocomplete_state() -> void:
	if _is_command_popup_visible():
		update_autocomplete_popup()


## Called when a custom setting changes
func _on_custom_setting_changed(setting_name: String, value: bool) -> void:
	custom_setting_changed.emit(setting_name, value)


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
	if _main_container and _main_container.has_node("Sidebar"):
		_sidebar = _main_container.get_node("Sidebar")


func _connect_ui_signals() -> void:
	if rich_label:
		rich_label.meta_clicked.connect(_on_log_meta_clicked)
		rich_label.meta_underlined = false
		rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _wrap_text else TextServer.AUTOWRAP_OFF

	if _clear_btn:
		_clear_btn.pressed.connect(_clear_logs)

	if _sidebar_toggle_btn:
		_sidebar_toggle_btn.toggled.connect(_on_sidebar_toggle)
		_sidebar_toggle_btn.button_pressed = _sidebar_visible

	if _sidebar:
		_sidebar.visible = _sidebar_visible and not _command_entry_mode


func _setup_sidebar() -> void:
	if not _sidebar:
		return

	_sidebar.configure_settings(_build_sidebar_settings())
	_sidebar.level_visibility_changed.connect(_on_level_visibility_changed)
	_sidebar.channel_visibility_changed.connect(_on_channel_visibility_changed)
	_sidebar.channel_deleted.connect(_on_channel_deleted)
	_sidebar.setting_changed.connect(_on_setting_changed)

	_sync_sidebar_state()


func _init_display() -> void:
	_ensure_pinned_overlay()
	if rich_label:
		rich_label.append_text(_get_welcome_message())
	_refresh_pinned_display_variables()


func _process(_delta: float) -> void:
	if _is_command_popup_visible():
		_refresh_command_autocomplete_popup_values()
	_refresh_pinned_display_variables()


func _ensure_pinned_overlay() -> void:
	if _pinned_overlay_label:
		return

	_pinned_overlay_label = RichTextLabel.new()
	_pinned_overlay_label.name = "PinnedDisplayVariables"
	_pinned_overlay_label.bbcode_enabled = true
	_pinned_overlay_label.scroll_active = false
	_pinned_overlay_label.fit_content = true
	_pinned_overlay_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pinned_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pinned_overlay_label.position = Vector2(8, 8)
	_pinned_overlay_label.visible = false
	_pinned_overlay_label.z_index = 200
	if _main_container and _main_container.theme:
		_pinned_overlay_label.theme = _main_container.theme
	add_child(_pinned_overlay_label)


func _refresh_pinned_display_variables() -> void:
	if not _pinned_overlay_label:
		return

	var lines: PackedStringArray = []
	for address in _pinned_display_variables:
		if not _has_display_variable(address):
			continue
		var row_text := "%s: %s" % [address, _get_display_variable_display_text(address, true)]
		lines.append("[bgcolor=#1a202acc]  %s  [/bgcolor]" % [_escape_overlay_bbcode(row_text)])

	_pinned_overlay_label.clear()
	if lines.is_empty():
		_pinned_overlay_label.visible = false
		return

	_pinned_overlay_label.append_text("\n".join(lines))
	_pinned_overlay_label.visible = true


func _escape_overlay_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _init_default_levels() -> void:
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
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
		var search_text := _format_objects(entry.objects).to_lower()
		if not search_text.contains(_search_filter):
			return false

	return level_mode == VisibilityMode.SHOWN and channel_mode == VisibilityMode.SHOWN and instance_mode == VisibilityMode.SHOWN


func _format_objects(objects: Array) -> String:
	var parts: PackedStringArray = []
	for obj in objects:
		parts.append(str(obj))
	return " ".join(parts)


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
	var color: String = LogotDisplay._get_level_color_hex(level)

	# Build extra lines indicator for collapsed view
	var extra_indicator := ""
	if is_collapsed and extra_lines > 0:
		extra_indicator = " [i][color=dim_gray]+%d[/color][/i]" % extra_lines

	# Determine if this entry has expandable content and the toggle action
	var has_expandable := extra_lines > 0 or stack_trace != ""
	var toggle_action := "expand" if is_collapsed else "collapse"

	# Build message content
	var message_content := "[color=%s]%s[/color]%s" % [color, text, extra_indicator]
	# Append formatted stack trace for expanded view
	if not is_collapsed and formatted_stack_trace != "":
		message_content += "\n" + formatted_stack_trace

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

	# Wrap contents in URL if expandable (URLs must wrap text, not tables)
	if has_expandable and entry_id >= 0:
		var url_action := "%s:%d" % [toggle_action, entry_id]
		timestamp_content = "[url=%s]%s[/url]" % [url_action, timestamp_content]
		if instance_content != "":
			instance_content = "[url=%s]%s[/url]" % [url_action, instance_content]
		if channel_content != "":
			channel_content = "[url=%s]%s[/url]" % [url_action, channel_content]
		if count_content != "":
			count_content = "[url=%s]%s[/url]" % [url_action, count_content]
		message_content = "[url=%s]%s[/url]" % [url_action, message_content]

	# Build single row: [timestamp] [instance + channel + count] [message]
	return "[table=3][cell]%s [/cell] [cell]%s%s%s%s[/cell][/table]" % [timestamp_content, instance_content, channel_content, count_content, message_content]


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


func _scroll_to_bottom() -> void:
	if not rich_label:
		return
	var scrollbar := rich_label.get_v_scroll_bar()
	if scrollbar:
		scrollbar.value = scrollbar.max_value


func _display_entry(entry) -> void:
	if not rich_label:
		return

	# Check if we should auto-scroll after adding content
	var was_at_bottom := _is_scrolled_to_bottom()

	var display_text: String = _get_entry_display_text(entry, _truncate_multiline)

	var is_duplicate := false
	if _collapse_duplicates and _last_displayed_entry != null:
		var last_content := _format_objects(_last_displayed_entry.objects)
		var current_content := _format_objects(entry.objects)
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
		_scroll_to_bottom()


func _rebuild_display() -> void:
	if not rich_label:
		return

	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	_bbcode_before_last_entry = _get_welcome_message()
	rich_label.clear()
	rich_label.append_text(_get_welcome_message())

	for entry in _get_log_entries():
		_ensure_channel_exists(entry.channel)
		_update_stats_for_entry(entry)
		if _should_display(entry):
			_display_entry(entry)
		else:
			entry.visible = false

	_update_sidebar_stats()
	display_rebuilt.emit()


# =============================================================================
# STATISTICS
# =============================================================================

func _update_stats_for_entry(entry) -> void:
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
		var search_text := _format_objects(entry.objects).to_lower()
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


func _reset_stats() -> void:
	for level in _level_stats:
		_level_stats[level].reset()
	for channel in _channel_stats:
		_channel_stats[channel].reset()


func _update_sidebar_stats() -> void:
	if not _sidebar:
		return

	for level in _level_stats:
		var stats: FilterStats = _level_stats[level]
		# Get rejected count from provider (logs that were never created due to can_log failing)
		var rejected_count := 0
		if _rejected_level_count_provider.is_valid():
			rejected_count = _rejected_level_count_provider.call(level)
		_sidebar.set_level_stats(level, stats.shown_count, stats.hidden_count, rejected_count)

	for channel in _channel_stats:
		var stats: FilterStats = _channel_stats[channel]
		# Get rejected count from provider (logs that were never created due to can_log failing)
		var rejected_count := 0
		if _rejected_channel_count_provider.is_valid():
			rejected_count = _rejected_channel_count_provider.call(channel)
		_sidebar.set_channel_stats(channel, stats.shown_count, stats.hidden_count, rejected_count)


# =============================================================================
# VISIBILITY CONTROL
# =============================================================================

func can_log(level: int, channel: String = "") -> bool:
	if _get_level_visibility(level) == VisibilityMode.OFF:
		return false
	if channel != "" and _get_channel_visibility(channel) == VisibilityMode.OFF:
		return false
	return true


func set_level_visibility(level: int, mode: int) -> void:
	_set_level_visibility(level, mode)
	_save_filter_settings()
	_rebuild_display()


func set_channel_visibility(channel: String, mode: int) -> void:
	_set_channel_visibility(channel, mode)
	_save_filter_settings()
	_rebuild_display()


# =============================================================================
# SIDEBAR SIGNAL HANDLERS
# =============================================================================

func _on_level_visibility_changed(level: int, mode: int) -> void:
	_set_level_visibility(level, mode)
	_save_filter_settings()
	_rebuild_display()
	level_visibility_changed.emit(level, mode)


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
			_on_custom_setting_changed(setting_name, value)


func _on_sidebar_toggle(toggled_on: bool) -> void:
	_sidebar_visible = toggled_on
	if _sidebar:
		_sidebar.visible = _sidebar_visible
	_save_filter_settings()


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
			EditorInterface.edit_script(script, line)
		else:
			push_warning("Could not load script: %s" % file_path)
	else:
		var absolute_path := ProjectSettings.globalize_path(file_path)
		OS.shell_open(absolute_path)


# =============================================================================
# CLEAR LOGS
# =============================================================================

func _clear_logs() -> void:
	_reset_stats()
	_last_displayed_entry = null
	_last_displayed_count = 0
	_bbcode_before_last_entry = _get_welcome_message()
	if rich_label:
		rich_label.clear()
		rich_label.append_text(_get_welcome_message())
	if _sidebar:
		_sidebar.reset_stats()
	_on_cleared()


# =============================================================================
# PERSISTENCE
# =============================================================================

func _save_filter_settings() -> void:
	var settings_file := _get_settings_file()
	if settings_file.is_empty():
		return

	var config := ConfigFile.new()

	# Save level visibility - use local dictionary or query provider for known levels
	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		config.set_value("levels", str(level), _get_level_visibility(level))

	# Save channel visibility
	for channel in _known_channels:
		var key: String = channel if channel != "" else "__general__"
		config.set_value("channels", key, _get_channel_visibility(channel))

	config.set_value("settings", "collapse_duplicates", _collapse_duplicates)
	config.set_value("settings", "wrap_text", _wrap_text)
	config.set_value("settings", "truncate_multiline", _truncate_multiline)
	config.set_value("settings", "sidebar_visible", _sidebar_visible)
	config.set_value("display_variables", "pinned", _pinned_display_variables)

	var serialized_pin_overlays := {}
	for overlay_name in _saved_pin_overlays:
		var overlay_key := str(overlay_name).strip_edges()
		if overlay_key.is_empty():
			continue

		var serialized_overlay_addresses: Array[String] = []
		var overlay_addresses = _saved_pin_overlays[overlay_name]
		if overlay_addresses is Array:
			for address in overlay_addresses:
				var address_str := str(address)
				if address_str.is_empty() or serialized_overlay_addresses.has(address_str):
					continue
				serialized_overlay_addresses.append(address_str)

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

	if config.has_section("display_variables"):
		var pinned_addresses = config.get_value("display_variables", "pinned", [])
		_pinned_display_variables.clear()
		if pinned_addresses is Array:
			for address in pinned_addresses:
				var address_str := str(address)
				if address_str.is_empty() or _pinned_display_variables.has(address_str):
					continue
				_pinned_display_variables.append(address_str)

		_saved_pin_overlays.clear()
		var pin_overlays = config.get_value("display_variables", "pin_overlays", {})
		if pin_overlays is Dictionary:
			for overlay_name in pin_overlays:
				var overlay_key := str(overlay_name).strip_edges()
				if overlay_key.is_empty():
					continue

				var overlay_addresses: Array[String] = []
				var stored_overlay_addresses = (pin_overlays as Dictionary)[overlay_name]
				if stored_overlay_addresses is Array:
					for address in stored_overlay_addresses:
						var address_str := str(address)
						if address_str.is_empty() or overlay_addresses.has(address_str):
							continue
						overlay_addresses.append(address_str)

				_saved_pin_overlays[overlay_key] = overlay_addresses

	_load_custom_settings(config)


func _save_custom_settings(_config: ConfigFile) -> void:
	pass


func _load_custom_settings(_config: ConfigFile) -> void:
	pass


func _sync_sidebar_state() -> void:
	if not _sidebar:
		return

	var levels := [LogLevel.ERROR, LogLevel.WARN, LogLevel.COMMAND, LogLevel.MESSAGE,
				   LogLevel.INFO, LogLevel.VERBOSE, LogLevel.DEBUG]
	for level in levels:
		_sidebar.set_level_visibility(level, _get_level_visibility(level))

	for channel in _known_channels:
		_sidebar.add_channel(channel)
		_sidebar.set_channel_visibility(channel, _get_channel_visibility(channel))

	_sidebar.set_setting("collapse_duplicates", _collapse_duplicates)
	_sidebar.set_setting("wrap_text", _wrap_text)
	_sidebar.set_setting("truncate_multiline", _truncate_multiline)


func _append_unique_address(addresses: Array[String], address: String) -> void:
	if address.is_empty() or addresses.has(address):
		return
	addresses.append(address)


func _get_base_registered_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for command in _get_commands():
		_append_unique_address(addresses, str(command))
	for address in _get_display_variables():
		_append_unique_address(addresses, str(address))
	return addresses


func _get_default_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	var addresses: Array[String] = []
	var base_addresses := _get_base_registered_addresses()
	if normalized_path.is_empty():
		for address in base_addresses:
			_append_unique_address(addresses, address)
		return addresses

	var path_prefix := normalized_path + "/"
	for base_address in base_addresses:
		if str(base_address).begins_with(path_prefix):
			_append_unique_address(addresses, str(base_address))

	if _get_command_data_direct(normalized_path) != null:
		for option_address in _get_command_option_subcommand_addresses(normalized_path, 0):
			_append_unique_address(addresses, option_address)

	if _has_display_variable_direct(normalized_path):
		for pin_option_address in _get_display_variable_pin_action_subcommand_addresses(normalized_path):
			_append_unique_address(addresses, pin_option_address)

	return addresses


func _get_available_pinned_display_variables() -> Array[String]:
	var addresses: Array[String] = []
	for address in _pinned_display_variables:
		var address_str := str(address)
		if address_str.is_empty() or not _has_display_variable_direct(address_str) or addresses.has(address_str):
			continue
		addresses.append(address_str)
	addresses.sort()
	return addresses


func _encode_pins_view_alias_token(address: String) -> String:
	return address.uri_encode()


func _decode_pins_view_alias_token(token: String) -> String:
	return token.uri_decode()


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
	if normalized_path == "pins/view" or not normalized_path.begins_with(PINS_VIEW_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_VIEW_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return normalized_path

	var alias_target := _resolve_pins_view_alias_target_path(alias_remainder)
	return normalized_path if alias_target.is_empty() else alias_target


func _get_display_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if normalized_path == "pins/view" or not normalized_path.begins_with(PINS_VIEW_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_VIEW_ALIAS_PREFIX.length())
	if alias_remainder.is_empty():
		return normalized_path

	var first_separator := alias_remainder.find("/")
	var alias_token := alias_remainder if first_separator == -1 else alias_remainder.substr(0, first_separator)
	var token_suffix := "" if first_separator == -1 else alias_remainder.substr(first_separator)
	var token_target := _resolve_pins_view_alias_token_target(alias_token)
	if token_target.is_empty():
		return normalized_path
	return PINS_VIEW_ALIAS_PREFIX + token_target + token_suffix


func _get_internal_alias_command_path(command_path: String) -> String:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	if normalized_path == "pins/view" or not normalized_path.begins_with(PINS_VIEW_ALIAS_PREFIX):
		return normalized_path

	var alias_remainder := normalized_path.substr(PINS_VIEW_ALIAS_PREFIX.length())
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
	return PINS_VIEW_ALIAS_PREFIX + _encode_pins_view_alias_token(best_match) + suffix


func _set_line_edit_command_path(command_path: String, include_trailing_separator: bool) -> void:
	if not line_edit:
		return

	var normalized_path := _get_display_alias_command_path(command_path.strip_edges().trim_suffix("/"))
	if normalized_path.is_empty():
		line_edit.text = "/"
	else:
		line_edit.text = "/" + normalized_path + ("/" if include_trailing_separator else "")
	line_edit.caret_column = line_edit.text.length()


func _get_pins_view_dynamic_menu_hierarchy_addresses(command_path: String) -> Array[String]:
	var normalized_path := command_path.strip_edges().trim_suffix("/")
	var addresses: Array[String] = []
	if normalized_path != "pins/view" and not normalized_path.begins_with(PINS_VIEW_ALIAS_PREFIX):
		return addresses

	for pinned_address in _get_available_pinned_display_variables():
		_append_unique_address(addresses, PINS_VIEW_ALIAS_PREFIX + _encode_pins_view_alias_token(pinned_address))

	if not normalized_path.begins_with(PINS_VIEW_ALIAS_PREFIX):
		return addresses

	var alias_remainder := normalized_path.substr(PINS_VIEW_ALIAS_PREFIX.length())
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
		_append_unique_address(addresses, PINS_VIEW_ALIAS_PREFIX + alias_token + suffix)

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


func _has_display_variable_direct(address: String) -> bool:
	return _get_display_variables().has(address)


func _has_display_variable(address: String) -> bool:
	return _has_display_variable_direct(_resolve_alias_command_path(address))


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


func _get_display_variable_value_text(address: String, single_line: bool = true) -> String:
	var value := _get_display_variable_value(address)
	var text := str(value)
	if single_line:
		text = text.replace("\n", " ").replace("\r", " ")
	return text


func _get_display_variable_display_text(address: String, single_line: bool = true) -> String:
	var value := _get_display_variable_value(address)
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
		var has_children := false
		for address in _get_menu_hierarchy_addresses(tier_text):
			if str(address).begins_with(tier_text + "/"):
				has_children = true
				break

		if not has_children and not _get_command_option_subcommand_addresses(tier_text, 0).is_empty():
			has_children = true
		if not has_children and not _get_display_variable_pin_action_subcommand_addresses(tier_text).is_empty():
			has_children = true
		if not has_children and _is_setget_command_name(tier_text):
			has_children = true
		if not has_children and _is_text_input_command_path(tier_text):
			has_children = true
		var has_option_command := _is_command_option_subcommand_tier(tier_text) or _is_display_variable_pin_action_subcommand_tier(tier_text) or _is_text_input_option_subcommand_tier(tier_text)
		var resolved_tier := _resolve_alias_command_path(tier_text)
		var has_direct_command := _get_commands().has(resolved_tier)
		var tier_label_override := ""
		if prefix == PINS_VIEW_ALIAS_PREFIX and tier_text.begins_with(PINS_VIEW_ALIAS_PREFIX):
			var alias_token := tier_text.substr(PINS_VIEW_ALIAS_PREFIX.length())
			var token_target := _resolve_pins_view_alias_token_target(alias_token)
			if not token_target.is_empty():
				tier_label_override = token_target

		matches.append({
			"tier": tier_text,
			"score": int(tier_matches[tier]),
			"has_children": has_children,
			"has_command": has_direct_command or has_option_command,
			"has_display_variable": _has_display_variable(str(tier)),
			"tier_label_override": tier_label_override,
		})

	var text_input_match := _build_text_input_tier_match(prefix, query)
	if not text_input_match.is_empty():
		matches.append(text_input_match)
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
				matches.append({
					"tier": AUTOCOMPLETE_GLOBAL_SEARCH_COMMAND,
					"score": search_score,
					"has_children": true,
					"has_command": false,
					"has_display_variable": false,
				})

	matches.sort_custom(func(a, b): return int(a.get("score", 0)) < int(b.get("score", 0)))
	return matches


func _get_all_known_autocomplete_tiers() -> Array[String]:
	var tiers: Array[String] = []
	var visited_menu_paths: Dictionary = {}
	var queue: Array[String] = [""]

	while not queue.is_empty():
		var menu_path := queue.pop_front()
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

			_append_unique_address(tiers, next_tier)
			if not visited_menu_paths.has(next_tier):
				queue.append(next_tier)

	return tiers


func _has_autocomplete_tier_children(tier: String, all_tiers: Array[String]) -> bool:
	for candidate in all_tiers:
		if candidate.begins_with(tier + "/"):
			return true

	if not _get_command_option_subcommand_addresses(tier, 0).is_empty():
		return true
	if not _get_display_variable_pin_action_subcommand_addresses(tier).is_empty():
		return true
	if _is_setget_command_name(tier):
		return true
	if _is_text_input_command_path(tier):
		return true
	return false


func _calculate_global_command_search_match_score(tier: String, query: String) -> int:
	if query.is_empty():
		return 0

	var tier_lower := tier.to_lower()
	var query_lower := query.to_lower()

	if tier_lower == query_lower:
		return 5000
	if tier_lower.begins_with(query_lower):
		return 4500 - tier.length()

	var best_score := -1
	var segments := _split_autocomplete_segments(tier)
	for segment_index in range(segments.size()):
		var segment := segments[segment_index]
		var segment_score := _calculate_match_score(segment, query)
		if segment_score >= 0:
			best_score = maxi(best_score, 3000 + segment_score - segment_index * 20)

		var contains_index := segment.to_lower().find(query_lower)
		if contains_index != -1:
			best_score = maxi(best_score, 2500 - segment_index * 20 - contains_index)

	if best_score >= 0:
		return best_score

	var full_path_index := tier_lower.find(query_lower)
	if full_path_index != -1:
		return 2000 - full_path_index
	return -1


func _highlight_search_match_text(text: String, query: String) -> String:
	if query.is_empty():
		return text

	var query_lower := query.to_lower()
	var query_len := query_lower.length()
	if query_len <= 0:
		return text

	var lower_text := text.to_lower()
	var highlighted := ""
	var cursor := 0
	while cursor < text.length():
		var match_index := lower_text.find(query_lower, cursor)
		if match_index == -1:
			highlighted += text.substr(cursor)
			break

		highlighted += text.substr(cursor, match_index - cursor)
		highlighted += "[" + text.substr(match_index, query_len) + "]"
		cursor = match_index + query_len

	return highlighted


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
		matches.append({
			"tier": tier,
			"score": score,
			"has_children": _has_autocomplete_tier_children(tier, all_tiers),
			"has_command": has_direct_command or has_option_command,
			"has_display_variable": _has_display_variable(tier),
			"full_label_override": _highlight_search_match_text("/" + tier, query),
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
	return tier.substr(prefix.length()) if tier.begins_with(prefix) else tier


func _format_autocomplete_item_text(prefix: String, match_data: Dictionary, left_column_width: int) -> String:
	var left_text := _get_autocomplete_tier_label(prefix, match_data)
	if not match_data.get("has_display_variable", false):
		return left_text

	var value_text := _get_display_variable_value_text(match_data.get("tier", ""), true)
	var padding := maxi(2, left_column_width - left_text.length() + 4)
	return left_text + " ".repeat(padding) + value_text


func _build_command_autocomplete_row_data(prefix: String, match_data: Dictionary) -> Dictionary:
	if match_data.get("is_text_input", false):
		return {
			"label": _get_autocomplete_tier_label(prefix, match_data),
			"value_text": "",
			"has_children": false,
			"can_submit": match_data.get("has_command", false),
			"row_background_tint": match_data.get("row_background_tint", null),
		}

	if match_data.get("is_option", false):
		return {
			"label": str(match_data.get("option_label", "")),
			"value_text": "",
			"has_children": false,
			"can_submit": false,
		}

	return {
		"label": _get_autocomplete_tier_label(prefix, match_data),
		"value_text": "" if match_data.get("suppress_value_text", false) else _get_autocomplete_display_variable_value_text(match_data),
		"has_children": match_data.get("has_children", false),
		"can_submit": match_data.get("has_command", false),
	}


func _get_autocomplete_display_variable_value_text(match_data: Dictionary) -> String:
	if not match_data.get("has_display_variable", false):
		return ""

	var tier := str(match_data.get("tier", ""))
	if tier.is_empty():
		return ""
	return _get_display_variable_display_text(tier, true)


func _get_command_autocomplete_column_name(prefix: String) -> String:
	var command_path := prefix.trim_suffix("/")
	if command_path.is_empty():
		return "Commands"
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
		if _is_display_variable_pin_action_subcommand_tier(command_name):
			var option_segment := command_name.substr(command_name.rfind("/") + 1).to_lower()
			return "Pin this display variable." if option_segment == "pin" else "Unpin this display variable."
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
	for option_entry in option_values:
		var option_value := _get_command_option_entry_value(option_entry)
		var option_label := _get_command_option_entry_label(option_entry)
		option_matches.append({
			"is_option": true,
			"option_label": option_label,
			"option_value": option_value,
		})
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
		var option_value := _get_command_option_entry_value(option_entry)
		if option_value == value or str(option_value) == value_text:
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


func _get_display_variable_pin_action_values(address: String) -> Array:
	var resolved_address := _resolve_alias_command_path(address)
	if not _has_display_variable_direct(resolved_address):
		return []
	var is_pinned := is_display_variable_pinned(resolved_address)
	return [{"label": "unpin", "value": false}] if is_pinned else [{"label": "pin", "value": true}]


func _get_display_variable_pin_action_subcommand_addresses(address: String) -> Array[String]:
	var addresses: Array[String] = []
	for option_entry in _get_display_variable_pin_action_values(address):
		var option_segment := _get_command_option_subcommand_segment(option_entry)
		if option_segment.is_empty():
			continue
		addresses.append("%s/%s" % [address, option_segment])
	return addresses


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
	var resolved_tier := _resolve_alias_command_path(tier)
	var last_separator := resolved_tier.rfind("/")
	if last_separator <= 0:
		return false

	var address := resolved_tier.substr(0, last_separator)
	if address.is_empty():
		return false

	var option_segment := resolved_tier.substr(last_separator + 1)
	if option_segment.is_empty():
		return false

	var lowered_option := option_segment.strip_edges().to_lower()
	for option_entry in _get_display_variable_pin_action_values(address):
		var option_label := _get_command_option_entry_label(option_entry).strip_edges().to_lower()
		if not option_label.is_empty() and option_label == lowered_option:
			return true
	return false


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

	var current_value := _get_command_current_value(resolved_command)
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

	var current_value := _get_command_current_value(command_name)
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
		if option_value == current_value or str(option_value) == current_text:
			return option_index

	if _has_display_variable(command_name):
		var resolved_command_name := _resolve_alias_command_path(command_name)
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
		var option_value := _get_command_option_entry_value(option_entry)
		var option_label := _get_command_option_entry_label(option_entry)
		for candidate in [option_label, str(option_value)]:
			if candidate == trimmed_value or candidate.to_lower() == lowered_value:
				return {"matched": true, "value": option_value}
	return {"matched": false}


func _find_command_option_match_index(command_name: String, option_matches: Array[Dictionary]) -> int:
	if option_matches.is_empty():
		return -1

	var current_value := _get_command_current_value(command_name)
	if current_value == null:
		return -1

	var current_text := str(current_value)
	for option_index in range(option_matches.size()):
		var option_data := option_matches[option_index]
		var option_value = option_data.get("option_value")
		if option_value == current_value:
			return option_index
		if str(option_value) == current_text:
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

	var raw_full_text := text.substr(1)
	var had_trailing_separator := raw_full_text.ends_with("/")
	var normalized_full_text := _get_internal_alias_command_path(raw_full_text.trim_suffix("/"))
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

		var selected_index := _find_autocomplete_match_index(matches, selected_tier)
		if selected_index == -1:
			if column_index < committed_segments.size():
				_autocomplete_active_column_index = -1
				return false
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
	var selected_index := _find_autocomplete_match_index(matches, selected_tier)
	if selected_index == -1:
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


func _refresh_active_preview_column_state() -> void:
	if _autocomplete_global_search_mode:
		return

	while _autocomplete_column_states.size() > _autocomplete_active_column_index + 1:
		_autocomplete_column_states.remove_at(_autocomplete_column_states.size() - 1)

	if _autocomplete_active_column_index < 0 or _autocomplete_active_column_index >= _autocomplete_column_states.size():
		return

	var active_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
	var selected_index := int(active_state.get("selected_index", -1))
	var matches: Array = active_state.get("matches", [])
	if selected_index < 0 or selected_index >= matches.size():
		return

	var selected_match: Dictionary = matches[selected_index]
	var selected_tier := str(selected_match.get("tier", ""))
	if selected_tier.is_empty():
		return

	if selected_match.get("has_children", false):
		var preview_prefix := selected_tier + "/"
		var preview_matches := _build_tier_matches(preview_prefix, "")
		if not preview_matches.is_empty():
			var preview_selected_index := _find_setget_preview_option_selected_index(selected_tier, preview_prefix, preview_matches)
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
			return

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


func _measure_autocomplete_text_width(control: Control, text: String) -> int:
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	if font == null:
		return text.length() * 8
	if font_size <= 0:
		font_size = 16
	return int(ceil(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x))


func _measure_autocomplete_text_width_with_font_size(control: Control, text: String, font_size: int) -> int:
	var font := control.get_theme_font("font")
	if font == null:
		return text.length() * 8
	if font_size <= 0:
		font_size = 16
	return int(ceil(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x))


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


func _measure_command_autocomplete_column_layout(control: Control, prefix: String, matches: Array, column_name: String, column_description: String) -> Dictionary:
	var name_width := 0
	var value_width := 0
	var action_width := 0
	for match_data in matches:
		var row_data := _build_command_autocomplete_row_data(prefix, match_data)
		name_width = maxi(name_width, _measure_autocomplete_text_width(control, str(row_data.get("label", ""))))

		var value_text := str(row_data.get("value_text", ""))
		if not value_text.is_empty():
			value_width = maxi(value_width, _measure_autocomplete_text_width(control, value_text) + AUTOCOMPLETE_VALUE_PILL_EXTRA_WIDTH)

		var action_count := 0
		if row_data.get("has_children", false):
			action_count += 1
		if row_data.get("can_submit", false):
			action_count += 1
		if action_count > 0:
			var current_action_width := AUTOCOMPLETE_ACTION_ICON_DIAMETER * action_count
			if action_count > 1:
				current_action_width += AUTOCOMPLETE_ACTION_ICON_GAP * (action_count - 1)
			action_width = maxi(action_width, current_action_width)

	value_width = mini(value_width, AUTOCOMPLETE_VALUE_MAX_WIDTH)

	var total_width := AUTOCOMPLETE_COLUMN_PADDING + name_width
	if value_width > 0:
		total_width += AUTOCOMPLETE_CELL_GAP + value_width
	if action_width > 0:
		total_width += AUTOCOMPLETE_CELL_GAP + action_width

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
	var preferred_width := maxi(total_width, header_total_width)
	var max_width := _get_command_autocomplete_max_column_width()
	total_width = clampi(preferred_width, AUTOCOMPLETE_COLUMN_MIN_WIDTH, max_width)

	return {
		"name_width": name_width,
		"value_width": value_width,
		"action_width": action_width,
		"width": total_width,
	}


func _create_command_autocomplete_column() -> AutocompleteCommandColumn:
	var list := AutocompleteCommandColumn.new()
	if _history_autocomplete_popup:
		list.configure_theme(_history_autocomplete_popup)
	return list


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
	var desired_height := item_count * AUTOCOMPLETE_ITEM_HEIGHT + 8
	var available_height := maxi(0.0, line_edit_rect.position.y - AUTOCOMPLETE_POPUP_GAP)
	var popup_height := minf(desired_height, available_height)
	var popup_y := maxi(0.0, line_edit_rect.position.y - AUTOCOMPLETE_POPUP_GAP - popup_height)
	var popup_width := line_edit_rect.size.x
	if line_edit.size.x > 0.0:
		popup_width = minf(popup_width, line_edit.size.x)
	var viewport_rect := get_viewport_rect()
	var popup_x := clamp(line_edit_rect.position.x, 0.0, maxf(0.0, viewport_rect.size.x - popup_width))

	_history_autocomplete_popup.global_position = Vector2(popup_x, popup_y)
	_history_autocomplete_popup.size = Vector2(popup_width, popup_height)


func _position_command_autocomplete_popup() -> void:
	if not _command_autocomplete_popup or not line_edit:
		return

	var line_edit_rect := line_edit.get_global_rect()
	var popup_height := _get_command_autocomplete_target_height()
	var popup_y := maxi(0.0, line_edit_rect.position.y - AUTOCOMPLETE_POPUP_GAP - popup_height)
	var popup_width := line_edit_rect.size.x
	if line_edit.size.x > 0.0:
		popup_width = minf(popup_width, line_edit.size.x)
	var viewport_rect := get_viewport_rect()
	var popup_x := clamp(line_edit_rect.position.x, 0.0, maxf(0.0, viewport_rect.size.x - popup_width))

	_command_autocomplete_popup.global_position = Vector2(popup_x, popup_y)
	_command_autocomplete_popup.size = Vector2(popup_width, popup_height)

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


func _queue_command_autocomplete_column_sync(start_index: int) -> void:
	_debug_autocomplete("_queue_command_autocomplete_column_sync", "start_index=%d" % start_index)
	if _pending_autocomplete_column_sync_start == -1:
		_pending_autocomplete_column_sync_start = start_index
	else:
		_pending_autocomplete_column_sync_start = mini(_pending_autocomplete_column_sync_start, start_index)

	if _autocomplete_column_sync_queued:
		return

	_autocomplete_column_sync_queued = true
	call_deferred("_flush_command_autocomplete_column_sync")


func _flush_command_autocomplete_column_sync() -> void:
	_autocomplete_column_sync_queued = false
	var start_index := maxi(0, _pending_autocomplete_column_sync_start)
	_pending_autocomplete_column_sync_start = -1
	_debug_autocomplete("_flush_command_autocomplete_column_sync", "start_index=%d" % start_index)
	_sync_visible_command_autocomplete_columns(start_index)


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


func _get_command_autocomplete_popup_height() -> int:
	return AUTOCOMPLETE_FIXED_VISIBLE_ITEMS * AUTOCOMPLETE_ITEM_HEIGHT + 8


func _get_command_autocomplete_target_height() -> int:
	if not line_edit:
		return _get_command_autocomplete_popup_height()

	var line_edit_rect := line_edit.get_global_rect()
	var desired_height := float(_get_command_autocomplete_popup_height())
	var available_height := maxi(0.0, line_edit_rect.position.y - AUTOCOMPLETE_POPUP_GAP)
	return maxi(1, int(floor(minf(desired_height, available_height))))


func _refresh_command_preview_option_state(column_state: Dictionary) -> Dictionary:
	if not column_state.get("preview", false):
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
	column_state = _refresh_command_preview_option_state(column_state)
	var prefix: String = column_state.get("prefix", "")
	var command_name := prefix.trim_suffix("/")
	var column_name := str(column_state.get("column_name_override", _get_command_autocomplete_column_name(prefix)))
	var column_description := str(column_state.get("column_description_override", _get_command_autocomplete_column_description(prefix, command_name)))
	var matches: Array = column_state.get("matches", [])
	var rows: Array[Dictionary] = []
	for match_data in matches:
		rows.append(_build_command_autocomplete_row_data(prefix, match_data))

	var layout := _measure_command_autocomplete_column_layout(list, prefix, matches, column_name, column_description)
	column_state["left_width"] = int(layout.get("name_width", 0))
	column_state["value_width"] = int(layout.get("value_width", 0))
	column_state["action_width"] = int(layout.get("action_width", 0))
	column_state["width"] = int(layout.get("width", 0))

	var column_height := _get_command_autocomplete_target_height()
	list.custom_minimum_size = Vector2(column_state["width"], column_height)
	list.size = list.custom_minimum_size

	var selected_index := int(column_state.get("selected_index", -1))
	var is_active_column := column_index == _autocomplete_active_column_index
	list.set_column_data(
		rows,
		layout,
		selected_index,
		column_state.get("preview", false),
		AUTOCOMPLETE_ITEM_HEIGHT,
		is_active_column,
		column_name,
		column_description
	)

	return column_state


func _sync_visible_command_autocomplete_columns(start_index: int = 0) -> void:
	_debug_autocomplete("_sync_visible_command_autocomplete_columns", "start_index=%d" % start_index)
	if not _command_autocomplete_popup or not _command_autocomplete_columns_container:
		return
	if _autocomplete_column_states.is_empty():
		_command_autocomplete_popup.visible = false
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
		var node := _autocomplete_column_nodes.pop_back()
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
		var new_list := _create_command_autocomplete_column()
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
		var list := _autocomplete_column_nodes[column_index] as AutocompleteCommandColumn
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		column_state = _configure_command_autocomplete_column(list, column_state, column_index)
		_autocomplete_column_states[column_index] = column_state
		_debug_autocomplete(
			"_sync_visible_command_autocomplete_columns.column",
			"column=%d items=%d selected=%d preview=%s size=%s min_size=%s" % [
				column_index,
				list.get_row_count(),
				int(column_state.get("selected_index", -1)) if not column_state.get("preview", false) and column_index == _autocomplete_active_column_index else -1,
				str(column_state.get("preview", false)),
				str(list.size),
				str(list.custom_minimum_size),
			]
		)

	_position_command_autocomplete_popup()
	_command_autocomplete_popup.visible = true
	_ensure_active_command_column_visible()
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
		_command_autocomplete_popup.visible = false
		return

	_clear_command_autocomplete_columns()

	for column_index in range(_autocomplete_column_states.size()):
		var list := _create_command_autocomplete_column()
		var column_state: Dictionary = _autocomplete_column_states[column_index]
		column_state = _configure_command_autocomplete_column(list, column_state, column_index)
		_autocomplete_column_states[column_index] = column_state

		_command_autocomplete_columns_container.add_child(list)
		_autocomplete_column_nodes.append(list)

	_position_command_autocomplete_popup()
	_command_autocomplete_popup.visible = true
	_scroll_command_autocomplete_columns_to_end()


func _refresh_command_autocomplete_popup_values() -> void:
	if not _is_command_popup_visible():
		return

	var needs_layout_refresh := false
	for column_index in range(mini(_autocomplete_column_states.size(), _autocomplete_column_nodes.size())):
		var column_state: Dictionary = _refresh_command_preview_option_state(_autocomplete_column_states[column_index])
		var matches: Array = column_state.get("matches", [])
		var prefix: String = column_state.get("prefix", "")
		var command_name := prefix.trim_suffix("/")
		var column_name := str(column_state.get("column_name_override", _get_command_autocomplete_column_name(prefix)))
		var column_description := str(column_state.get("column_description_override", _get_command_autocomplete_column_description(prefix, command_name)))
		var list := _autocomplete_column_nodes[column_index] as AutocompleteCommandColumn
		var rows: Array[Dictionary] = []
		for match_data in matches:
			rows.append(_build_command_autocomplete_row_data(prefix, match_data))

		var layout := _measure_command_autocomplete_column_layout(list, prefix, matches, column_name, column_description)
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

		var selected_index := int(column_state.get("selected_index", -1))
		var is_active_column := column_index == _autocomplete_active_column_index
		list.set_column_data(
			rows,
			layout,
			selected_index,
			column_state.get("preview", false),
			AUTOCOMPLETE_ITEM_HEIGHT,
			is_active_column,
			column_name,
			column_description
		)
		_autocomplete_column_states[column_index] = column_state

	if needs_layout_refresh:
		_position_command_autocomplete_popup()
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
		_queue_command_autocomplete_column_sync(0)


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

	column_state["selected_index"] = index
	_autocomplete_column_states[_autocomplete_active_column_index] = column_state
	_autocomplete_highlighted_tiers[str(column_state.get("prefix", ""))] = str(matches[index].get("tier", ""))
	_debug_autocomplete("_set_active_command_column_selection.selected", "resolved_index=%d tier=%s" % [index, str(matches[index].get("tier", ""))])
	_debug_command_popup_height("_set_active_command_column_selection.selected_height")
	if not _autocomplete_global_search_mode:
		_refresh_active_preview_column_state()
	_sync_visible_command_autocomplete_columns(0)
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
	_render_command_autocomplete_popup()
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
		_command_autocomplete_popup.visible = false

	_history_can_switch_to_commands = false
	_autocomplete_column_states.clear()
	_autocomplete_column_nodes.clear()
	_autocomplete_active_column_index = -1
	_autocomplete_global_search_mode = false
	_pending_autocomplete_column_sync_start = -1
	_autocomplete_column_sync_queued = false
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


func _show_command_popup_for_default_input() -> void:
	if not line_edit:
		return

	_history_can_switch_to_commands = false
	if line_edit.text.strip_edges().is_empty():
		line_edit.text = "/"
		line_edit.caret_column = line_edit.text.length()

	update_autocomplete_popup()


func _show_root_command_popup() -> void:
	if not line_edit:
		return

	_history_can_switch_to_commands = false
	line_edit.text = "/"
	line_edit.caret_column = line_edit.text.length()
	update_autocomplete_popup()


func _show_recent_history_popup(query: String = "", allow_switch_to_commands: bool = false) -> void:
	_history_can_switch_to_commands = allow_switch_to_commands
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
		_show_recent_history_popup("", true)
		return

	if _is_command_popup_visible():
		var column_state: Dictionary = _autocomplete_column_states[_autocomplete_active_column_index]
		var matches: Array = column_state.get("matches", [])
		if matches.is_empty():
			_debug_autocomplete("autocomplete_select_next.command_no_matches")
			return
		var selected_index := int(column_state.get("selected_index", -1))
		if str(column_state.get("prefix", "")).is_empty() and selected_index >= matches.size() - 1:
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


func autocomplete_move_right() -> void:
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
	update_autocomplete_popup()


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
	_history_autocomplete_popup.visible = true
	_set_history_autocomplete_selection(0)


## Handle text changes for autocomplete
func on_text_changed_autocomplete(new_text: String) -> void:
	_debug_autocomplete("on_text_changed_autocomplete.begin", "new_text=%s" % new_text)
	# Reset old autocomplete state
	_suggestions.clear()
	_current_suggest = 0
	_suggesting = false

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
