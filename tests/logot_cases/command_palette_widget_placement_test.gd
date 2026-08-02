extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")

const COLUMN_SIZE := Vector2(280.0, 224.0)
const ROW_HEIGHT := 28
const WIDGET_SIZE := Vector2(120.0, 60.0)


func _init() -> void:
	id = "command_palette_widget_placement"
	display_name = "Command Palette Widget Placement"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	_check_placement_mapping(ctx, display)
	_check_inline_placement(ctx, display)
	_check_pinned_placement(ctx, display)
	_check_inline_without_overflow(ctx, display)


func _make_column(display, rows: Array[Dictionary], placement: int):
	var list := LogotDisplay.AutocompleteCommandColumn.new()
	list.configure_theme(display._history_autocomplete_popup)
	list.size = COLUMN_SIZE
	var widget := ColorRect.new()
	widget.custom_minimum_size = WIDGET_SIZE
	list.set_embedded_widget(widget, "test/widget", placement)
	list.set_column_data(rows, {}, -1, false, ROW_HEIGHT)
	return list


func _make_rows(count: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row_index in range(count):
		rows.append({
			"label": "option_%02d" % row_index,
			"has_children": false,
			"can_submit": true,
		})
	return rows


## Preview columns keep their widget pinned under the header; the current and past columns show
## theirs inline with the rows.
func _check_placement_mapping(ctx, display) -> void:
	var pinned = LogotDisplay.AutocompleteCommandColumn.WidgetPlacement.PINNED
	var inline = LogotDisplay.AutocompleteCommandColumn.WidgetPlacement.INLINE
	ctx.check(
		"preview column pins its widget",
		display._get_autocomplete_column_widget_placement({"preview": true}) == pinned
	)
	ctx.check(
		"current column shows its widget inline",
		display._get_autocomplete_column_widget_placement({"preview": false}) == inline
	)
	ctx.check(
		"past column shows its widget inline",
		display._get_autocomplete_column_widget_placement({}) == inline
	)


func _check_inline_placement(ctx, display) -> void:
	var rows := _make_rows(24)
	var list = _make_column(display, rows, LogotDisplay.AutocompleteCommandColumn.WidgetPlacement.INLINE)
	var header_height: float = list._header_height

	ctx.check("inline widget is visible at the top of the content", list._embedded_widget.visible)
	ctx.check(
		"inline widget pushes the rows down",
		list._get_rows_top() > header_height,
		"rows_top=%s header=%s" % [list._get_rows_top(), header_height]
	)
	ctx.check("inline content starts on the first row", list.get_visible_row_range().x == 0)

	# One scroll step consumes the widget's slot only: the first row stays put.
	list._scroll_rows(1)
	ctx.check("one scroll step hides the inline widget", not list._embedded_widget.visible)
	ctx.check(
		"first row survives the inline widget scrolling away",
		list.get_visible_row_range().x == 0,
		"range=%s" % list.get_visible_row_range()
	)
	ctx.check(
		"rows reclaim the inline widget's space",
		is_equal_approx(list._get_rows_top(), header_height),
		"rows_top=%s header=%s" % [list._get_rows_top(), header_height]
	)

	list._scroll_rows(1)
	ctx.check(
		"the next scroll step advances the rows",
		list.get_visible_row_range().x == 1,
		"range=%s" % list.get_visible_row_range()
	)

	list._scroll_rows(-2)
	ctx.check("scrolling back to the top restores the inline widget", list._embedded_widget.visible)
	ctx.check("scrolling back to the top restores the first row", list.get_visible_row_range().x == 0)

	# The scrollbar tracks the widget's slot, so it spans the whole region under the header.
	ctx.check(
		"inline widget is inside the scrollbar's region",
		is_equal_approx(list._row_scrollbar.position.y, header_height),
		"scrollbar_top=%s header=%s" % [list._row_scrollbar.position.y, header_height]
	)
	list.queue_free()


func _check_pinned_placement(ctx, display) -> void:
	var rows := _make_rows(24)
	var list = _make_column(display, rows, LogotDisplay.AutocompleteCommandColumn.WidgetPlacement.PINNED)
	var header_height: float = list._header_height
	var pinned_rows_top: float = list._get_rows_top()

	ctx.check("pinned widget is visible", list._embedded_widget.visible)
	ctx.check(
		"pinned widget sits between the header and the rows",
		pinned_rows_top > header_height,
		"rows_top=%s header=%s" % [pinned_rows_top, header_height]
	)
	ctx.check(
		"pinned widget is above the scrollbar's region",
		is_equal_approx(list._row_scrollbar.position.y, pinned_rows_top),
		"scrollbar_top=%s rows_top=%s" % [list._row_scrollbar.position.y, pinned_rows_top]
	)

	list._scroll_rows(1)
	ctx.check("pinned widget survives scrolling", list._embedded_widget.visible)
	ctx.check(
		"pinned widget keeps its band while the rows scroll",
		is_equal_approx(list._get_rows_top(), pinned_rows_top),
		"rows_top=%s expected=%s" % [list._get_rows_top(), pinned_rows_top]
	)
	ctx.check(
		"the first scroll step advances the rows past a pinned widget",
		list.get_visible_row_range().x == 1,
		"range=%s" % list.get_visible_row_range()
	)
	list.queue_free()


## An inline widget only earns a scroll slot when it actually costs the rows their space.
func _check_inline_without_overflow(ctx, display) -> void:
	var rows := _make_rows(2)
	var list = _make_column(display, rows, LogotDisplay.AutocompleteCommandColumn.WidgetPlacement.INLINE)

	ctx.check("a column that fits has no row scrollbar", not list._row_scrollbar.visible)
	list._scroll_rows(1)
	ctx.check("an inline widget cannot be scrolled away when everything fits", list._embedded_widget.visible)
	ctx.check("the rows stay put when everything fits", list.get_visible_row_range().x == 0)
	list.queue_free()
