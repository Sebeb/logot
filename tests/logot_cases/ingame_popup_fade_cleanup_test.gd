extends LogotTestCase


func _init() -> void:
	id = "ingame_popup_fade_cleanup"
	display_name = "Ingame Popup Fade Cleanup"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var popup_parent := Control.new()
	ctx.scene_root.add_child(popup_parent)

	var popup_panel := PanelContainer.new()
	popup_panel.modulate = Color(1, 1, 1, 0.25)
	popup_parent.add_child(popup_panel)

	ctx.check("popup starts without fade meta", not popup_panel.has_meta("fade_tween"))

	console._free_ingame_popup(popup_panel)

	ctx.check("popup detached from parent", popup_panel.get_parent() == null)
	ctx.check("popup queued for deletion", popup_panel.is_queued_for_deletion())
	ctx.check("fade meta remains absent after cleanup", not popup_panel.has_meta("fade_tween"))
	ctx.check("fade cleanup restores popup alpha", is_equal_approx(popup_panel.modulate.a, 1.0), "alpha=%s" % popup_panel.modulate.a)
