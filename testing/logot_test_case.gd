class_name LogotTestCase
extends RefCounted


var id := ""
var display_name := ""
var scene_path := ""
var fail_fast := false


func run(_ctx) -> void:
	push_warning("%s must implement run(ctx)." % get_script().resource_path)
