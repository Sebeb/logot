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

	var fullscreen_result: Dictionary = console._execute_command("/%s/fullscreen" % widget_address)
	ctx.check("fullscreen command executes", bool(fullscreen_result.get("ok", false)), str(fullscreen_result))
	ctx.check(
		"fullscreen mode is active",
		console.get_render_texture_widget_view_mode(widget_address) == LogotDisplay.RENDER_TEXTURE_VIEW_MODE_FULLSCREEN
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
