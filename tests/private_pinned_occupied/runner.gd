extends SceneTree

class Context extends RefCounted:
	var tree: SceneTree
	var theme: Theme
	var checks: Array[Dictionary] = []
	func check(label: String, passed: bool, details: String = "") -> void:
		checks.append({"label": label, "passed": passed, "details": details})
	func wait_frames(count: int) -> void:
		for frame in range(count):
			await tree.process_frame

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ctx := Context.new()
	ctx.tree = self
	ctx.theme = load("res://fixture_theme.tres")
	var case = load("res://tests/private_pinned_occupied/case.gd").new()
	await case.run(ctx)
	var failures := ctx.checks.filter(func(record): return not record.passed)
	var result := {"collected": ctx.checks.size(), "passed": ctx.checks.size() - failures.size(), "failed": failures.size(), "checks": ctx.checks}
	var file := FileAccess.open("res://result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("OCCUPIED_RESULT collected=", ctx.checks.size(), " failed=", failures.size())
	quit(0 if failures.is_empty() else 1)
