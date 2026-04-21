extends LogotTestCase

const LogLevel = preload("res://addons/logot/log_level.gd")


func _init() -> void:
	id = "popup_bbcode"
	display_name = "Popup BBCode"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var collapsed_markup: String = console._format_ingame_popup_text(
		"[b]Bold[/b] [color=gold]popup[/color]\nSecond line",
		LogLevel.MESSAGE,
		"UI",
		1,
		false
	)
	ctx.check("collapsed popup preserves bbcode", collapsed_markup.contains("[b]Bold[/b] [color=gold]popup[/color]"), collapsed_markup)
	ctx.check("collapsed popup keeps extra-line indicator", collapsed_markup.contains("+1"), collapsed_markup)

	var expanded_markup: String = console._format_ingame_popup_text(
		"[i]First[/i]\n[url=open_file:res://Main.tscn:1]Second[/url]",
		LogLevel.MESSAGE,
		"",
		1,
		true
	)
	ctx.check("expanded popup preserves url markup", expanded_markup.contains("[url=open_file:res://Main.tscn:1]Second[/url]"), expanded_markup)
