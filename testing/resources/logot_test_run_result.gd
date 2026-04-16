class_name LogotTestRunResult
extends Resource

const LogotTestCheckResult = preload("res://addons/logot/testing/resources/logot_test_check_result.gd")
const LogotTestVisualResult = preload("res://addons/logot/testing/resources/logot_test_visual_result.gd")
const LogotTestLogRecord = preload("res://addons/logot/testing/resources/logot_test_log_record.gd")


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
