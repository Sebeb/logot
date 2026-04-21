extends SceneTree

const LogotScript = preload("res://addons/logot/logot.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.is_empty():
		push_error("Missing test id. Usage: godot --headless --path <project> --script res://tests/run_logot_test.gd -- <test_id>")
		quit(2)
		return

	var test_id := str(user_args[0]).strip_edges()
	if test_id.is_empty():
		push_error("Test id cannot be empty.")
		quit(2)
		return

	var console = root.get_node_or_null("Logot")
	if console == null:
		console = LogotScript.new()
		console.name = "Logot"
		root.add_child(console)

	await process_frame

	var manager = console.get_test_manager()
	if manager == null:
		push_error("Failed to initialize Logot test manager.")
		quit(3)
		return
	if not manager.run_test(test_id):
		push_error("Failed to start test '%s'." % test_id)
		quit(4)
		return

	var result = await manager.test_run_completed
	if result == null:
		push_error("Test runner did not receive a result for '%s'." % test_id)
		quit(5)
		return
	if not bool(result.passed):
		push_error(str(result.summary))
		quit(1)
		return

	print("PASS %s" % test_id)
	quit(0)
