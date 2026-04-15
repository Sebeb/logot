class_name LogotCommandInput
extends RefCounted


static func extract_command_name(command_input: String, parse_line_input: Callable = Callable()) -> String:
	var trimmed_input := command_input.strip_edges()
	if not trimmed_input.begins_with("/"):
		return ""

	var command_text := trimmed_input.substr(1)
	if command_text.is_empty():
		return ""

	var text_split := PackedStringArray()
	if parse_line_input.is_valid():
		text_split = parse_line_input.call(command_text)
	else:
		text_split = command_text.split(" ", false)
	if text_split.is_empty():
		return ""
	return str(text_split[0]).strip_edges()


static func resolve_submitted_text(raw_text: String, prefer_autocomplete_selection: bool, display) -> String:
	var submitted_text := raw_text.strip_edges()
	if not prefer_autocomplete_selection:
		return submitted_text
	if not submitted_text.begins_with("/"):
		return submitted_text
	if not display or not display.has_active_command_autocomplete_match():
		return submitted_text
	return display.get_active_command_submission_text().strip_edges()


static func get_selected_history_command(display) -> String:
	if not display or not display.has_method("get_selected_history_command"):
		return ""
	return str(display.get_selected_history_command()).strip_edges()


static func is_submit_event(event: InputEventKey, line_edit: LineEdit) -> bool:
	if not event.pressed or event.echo:
		return false
	if not line_edit or not line_edit.has_focus():
		return false
	return event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER


static func handle_autocomplete_navigation(event: InputEventKey, display, line_edit: LineEdit, on_escape_from_command_entry: Callable = Callable()) -> bool:
	if not event.pressed or event.echo:
		return false
	if not display or not line_edit or not line_edit.has_focus():
		return false

	if display.is_autocomplete_visible():
		match event.keycode:
			KEY_DOWN:
				display.autocomplete_select_next()
				return true
			KEY_UP:
				display.autocomplete_select_prev()
				return true
			KEY_RIGHT:
				display.autocomplete_move_right(true)
				return true
			KEY_LEFT:
				display.autocomplete_move_left()
				return true
			KEY_TAB:
				display.confirm_autocomplete()
				return true
			KEY_ESCAPE:
				if display.is_command_entry_mode():
					if on_escape_from_command_entry.is_valid():
						on_escape_from_command_entry.call()
					else:
						display.hide_command_entry_mode()
				else:
					display.hide_autocomplete()
				return true
		return false

	match event.keycode:
		KEY_UP:
			display.autocomplete_select_prev()
			return true
		KEY_DOWN:
			display.autocomplete_select_next()
			return true
		KEY_ESCAPE:
			if display.is_command_entry_mode():
				if on_escape_from_command_entry.is_valid():
					on_escape_from_command_entry.call()
				else:
					display.hide_command_entry_mode()
				return true
	return false
