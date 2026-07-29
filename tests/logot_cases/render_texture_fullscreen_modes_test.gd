extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "render_texture_fullscreen_modes"
	display_name = "Render Texture Fullscreen Modes"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var display = console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.9, 1.0))
	var texture := ImageTexture.create_from_image(image)
	var widget_address := "tests/render_texture/fullscreen_modes"

	console.add_render_texture_widget(widget_address, func() -> Texture2D:
		return texture
	)
	var preview_widget = display._create_widget_instance(widget_address, "preview")
	ctx.check("render texture preview can be created", preview_widget != null)
	if preview_widget != null:
		ctx.check(
			"render texture preview shows its resolution",
			preview_widget._resolution_label != null and preview_widget._resolution_label.text == "4 × 4",
			preview_widget._resolution_label.text if preview_widget._resolution_label != null else "missing label"
		)
		ctx.check(
			"resolution bar is attached beneath the texture",
			preview_widget._resolution_label.get_parent() is VBoxContainer
				and preview_widget._resolution_label.get_index() > preview_widget._texture_rect.get_parent().get_index()
		)
		var square_preview_size: Vector2 = preview_widget.get_logot_embedded_size(500.0)
		ctx.check(
			"square texture preview frame preserves its aspect ratio",
			is_equal_approx(square_preview_size.x, square_preview_size.y - 18.0),
			str(square_preview_size)
		)
		ctx.check("aspect-correct preview does not exceed its height cap", square_preview_size.y <= 160.0)
		preview_widget.queue_free()

	var viewport_size: Vector2 = display.get_viewport_rect().size
	var simulated_safe_area := Rect2(
		Vector2(7.0, 13.0),
		Vector2(maxf(1.0, viewport_size.x - 17.0), maxf(1.0, viewport_size.y - 31.0))
	)
	display._set_display_safe_area_override_for_tests(simulated_safe_area)

	var fullscreen_result: Dictionary = console._execute_command("/%s/fullscreen" % widget_address)
	ctx.check("fullscreen command executes", bool(fullscreen_result.get("ok", false)), str(fullscreen_result))
	ctx.check(
		"fullscreen mode is active",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
	)
	await ctx.wait_frames(2)
	var fullscreen_content_rect: Rect2 = display._render_texture_fullscreen_container.get_global_rect()
	ctx.check(
		"fullscreen content respects display safe area",
		fullscreen_content_rect.position.distance_to(simulated_safe_area.position) <= 1.0
			and fullscreen_content_rect.end.distance_to(simulated_safe_area.end) <= 1.0,
		"content=%s safe=%s" % [fullscreen_content_rect, simulated_safe_area]
	)
	display.show_command_entry_mode("/%s/fullscreen" % widget_address)
	var fullscreen_palette_text_before_escape: String = console.line_edit.text if console.line_edit != null else ""
	console._handle_escape_input()
	ctx.check(
		"escape clears fullscreen mode",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
	)
	ctx.check("escape keeps command palette active from fullscreen", display.is_command_entry_mode())
	ctx.check(
		"escape preserves command palette text from fullscreen",
		console.line_edit != null and console.line_edit.text == fullscreen_palette_text_before_escape
	)

	var overlay_result: Dictionary = console._execute_command("/%s/fullscreen_overlay" % widget_address)
	ctx.check("fullscreen overlay command executes", bool(overlay_result.get("ok", false)), str(overlay_result))
	ctx.check(
		"fullscreen overlay mode is active",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN_OVERLAY
	)
	display.show_command_entry_mode("/%s/fullscreen_overlay" % widget_address)
	var overlay_palette_text_before_escape: String = console.line_edit.text if console.line_edit != null else ""
	console._handle_escape_input()
	ctx.check(
		"escape clears fullscreen overlay mode",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
	)
	ctx.check("escape keeps command palette active from overlay", display.is_command_entry_mode())
	ctx.check(
		"escape preserves command palette text from overlay",
		console.line_edit != null and console.line_edit.text == overlay_palette_text_before_escape
	)

	var off_result: Dictionary = console._execute_command("/%s/fullscreen_off" % widget_address)
	ctx.check("fullscreen off command executes", bool(off_result.get("ok", false)), str(off_result))
	ctx.check(
		"fullscreen mode is cleared",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_NONE
	)

	console.remove_widget(widget_address)
	display._clear_display_safe_area_override_for_tests()
