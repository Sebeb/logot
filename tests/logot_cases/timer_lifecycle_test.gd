extends LogotTestCase

const LogotDisplay = preload("res://addons/logot/logot_display.gd")


func _init() -> void:
	id = "timer_lifecycle"
	display_name = "Timer Lifecycle"
	scene_path = "res://Main.tscn"
	fail_fast = true


func run(ctx) -> void:
	var console = ctx.console
	var timer_key: String = "build"
	var timer_name: String = "Build Timer"
	var timer_channel: String = "Timer"
	var timer_address: String = "timers/%s" % timer_key
	var old_name_address: String = "timers/%s/name" % timer_key
	var old_time_address: String = "timers/%s/time" % timer_key

	console.set_channel_visibility(timer_channel, LogotDisplay.VisibilityMode.SHOWN)

	ctx.check("start_timer returns true", console.start_timer(timer_key, timer_name, timer_channel))
	ctx.check("timer exists after start", console.has_timer(timer_key))
	ctx.check("timer name stored", console.get_timer_name(timer_key) == timer_name)
	ctx.check("timer channel stored", console.get_timer_channel(timer_key) == timer_channel)
	ctx.check("timer running after start", console.is_timer_running(timer_key))
	ctx.check("timer display variable created", console.get_display_variables().has(timer_address))
	ctx.check("old name display variable not created", not console.get_display_variables().has(old_name_address))
	ctx.check("old time display variable not created", not console.get_display_variables().has(old_time_address))
	ctx.check("timer pin active while shown", console.is_display_variable_pinned(timer_address))

	var display = console._get_active_display()
	if display != null:
		var timer_snapshot: Dictionary = display._get_display_variable_render_snapshot(timer_address)
		ctx.check("timer pin label uses timer name", str(timer_snapshot.get("display_label", "")) == timer_name, str(timer_snapshot))
		ctx.check("timer pin value uses elapsed time", str(timer_snapshot.get("text", "")).begins_with("00:00:"), str(timer_snapshot))

	await ctx.wait_seconds(0.05)
	var elapsed_after_start: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("elapsed can be queried while shown", elapsed_after_start >= 0.0, "elapsed=%s" % elapsed_after_start)
	ctx.check("elapsed text available", not console.get_timer_elapsed_text(timer_key).is_empty())

	console.set_channel_visibility(timer_channel, LogotDisplay.VisibilityMode.HIDDEN)
	await ctx.wait_seconds(0.05)
	var elapsed_while_hidden: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("timer keeps running while hidden", console.is_timer_running(timer_key))
	ctx.check("timer pin removed while hidden", not console.is_display_variable_pinned(timer_address))
	ctx.check("elapsed advances while hidden", elapsed_while_hidden >= elapsed_after_start + 0.04, "elapsed=%s start=%s" % [elapsed_while_hidden, elapsed_after_start])

	console.set_channel_visibility(timer_channel, LogotDisplay.VisibilityMode.OFF)
	var elapsed_at_off: float = console.get_timer_elapsed_seconds(timer_key)
	await ctx.wait_seconds(0.05)
	var elapsed_while_off: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("timer stops running while off", not console.is_timer_running(timer_key))
	ctx.check("elapsed freezes while off", absf(elapsed_while_off - elapsed_at_off) < 0.02, "off delta=%s" % absf(elapsed_while_off - elapsed_at_off))

	console.set_channel_visibility(timer_channel, LogotDisplay.VisibilityMode.SHOWN)
	await ctx.wait_seconds(0.05)
	var elapsed_after_shown_again: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("timer resumes when shown again", console.is_timer_running(timer_key))
	ctx.check("timer pin restored when shown again", console.is_display_variable_pinned(timer_address))
	ctx.check("elapsed advances after showing again", elapsed_after_shown_again >= elapsed_at_off + 0.04, "elapsed=%s off=%s" % [elapsed_after_shown_again, elapsed_at_off])

	ctx.check("pause_timer returns true", console.pause_timer(timer_key))
	ctx.check("timer paused", not console.is_timer_running(timer_key))
	ctx.check("timer pin removed while paused", not console.is_display_variable_pinned(timer_address))

	var elapsed_at_pause: float = console.get_timer_elapsed_seconds(timer_key)
	await ctx.wait_seconds(0.05)
	var elapsed_while_paused: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("elapsed remains stable while paused", absf(elapsed_while_paused - elapsed_at_pause) < 0.02, "paused delta=%s" % absf(elapsed_while_paused - elapsed_at_pause))

	ctx.check("resume_timer returns true", console.resume_timer(timer_key))
	ctx.check("timer running after resume", console.is_timer_running(timer_key))
	ctx.check("timer pin restored on resume", console.is_display_variable_pinned(timer_address))

	await ctx.wait_seconds(0.05)
	var elapsed_after_resume: float = console.get_timer_elapsed_seconds(timer_key)
	ctx.check("elapsed advances after resume", elapsed_after_resume >= elapsed_at_pause + 0.04, "elapsed=%s pause=%s" % [elapsed_after_resume, elapsed_at_pause])

	var log_count_before_stop: int = console.get_log_entries().size()
	ctx.check("stop_timer returns true", console.stop_timer(timer_key))
	ctx.check("timer removed after stop", not console.has_timer(timer_key))
	ctx.check("timer display variable removed", not console.get_display_variables().has(timer_address))

	var log_entries: Array = console.get_log_entries()
	ctx.check("stop created a log entry", log_entries.size() == log_count_before_stop + 1, "before=%s after=%s" % [log_count_before_stop, log_entries.size()])

	if log_entries.size() > 0:
		var last_entry = log_entries[log_entries.size() - 1]
		var last_message: String = console._format_objects(last_entry.objects)
		ctx.check("stop log uses timer channel", str(last_entry.channel) == timer_channel, "channel=%s" % last_entry.channel)
		ctx.check("stop log includes timer name", last_message.contains(timer_name), last_message)
		ctx.check("stop log includes stop text", last_message.contains("stopped at"), last_message)

	console.set_channel_visibility(timer_channel, LogotDisplay.VisibilityMode.SHOWN)
