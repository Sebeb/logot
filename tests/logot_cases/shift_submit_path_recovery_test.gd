extends LogotTestCase

var _console = null


func _init() -> void:
	id = "shift_submit_path_recovery"
	display_name = "Shift Submit Path Recovery"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	_console = ctx.console
	var display = _console._get_active_display()
	ctx.check("active display exists", display != null)
	if display == null:
		return

	_console.add_command("path_recovery/item/delete", _delete_item_commands)
	_console.line_edit.text = "/path_recovery/item/delete"
	_console.line_edit.caret_column = _console.line_edit.text.length()
	display.on_text_changed_autocomplete(_console.line_edit.text)
	await ctx.wait_frames(2)

	_console._submit_line_edit_input(_console.line_edit.text, true, false)
	await ctx.wait_frames(2)
	ctx.check(
		"shift submit backs up to nearest valid command path",
		_console.line_edit.text == "/path_recovery/",
		"text=%s" % _console.line_edit.text
	)

	_console.remove_command("path_recovery/remaining")
	display.reconcile_retained_command_path()
	ctx.check(
		"missing ancestors back up to root",
		_console.line_edit.text == "/",
		"text=%s" % _console.line_edit.text
	)


func _delete_item_commands() -> void:
	_console.remove_command("path_recovery/item/delete")
	_console.add_command("path_recovery/remaining", func(): pass)
