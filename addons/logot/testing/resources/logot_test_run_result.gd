class_name LogotTestRunResult
extends Resource


@export var run_id := ""
@export var test_id := ""
@export var display_name := ""
@export var scene_path := ""
@export var started_at := ""
@export var completed_at := ""
@export var fail_fast := false
@export var passed := false
@export var artifact_path := ""
@export var artifact_directory := ""
@export var visual_directory := ""
@export var summary := ""
@export var code_checks: Array[LogotTestCheckResult] = []
@export var visual_checks: Array[LogotTestVisualResult] = []
@export var logs: Array[LogotTestLogRecord] = []
