class_name LogotExternalTestCase
extends LogotTestCase

signal body_completed()

## Called as body.call(self, ctx). The body calls complete() when done.
var body: Callable
var _done := false


func run(ctx) -> void:
	_done = false
	if not body.is_valid():
		ctx.fail("external_body_missing", "No body was set on this case.")
		return
	body.call(self, ctx)
	if not _done:
		await body_completed


func complete() -> void:
	if _done:
		return
	_done = true
	body_completed.emit()
