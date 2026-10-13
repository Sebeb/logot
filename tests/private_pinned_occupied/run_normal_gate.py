#!/usr/bin/env python3
"""Finite frozen pair. Requires root's separate exclusive START, not a lock."""
import argparse
import hashlib
import json
import os
import pathlib
import runpy
import shutil
import signal
import sys
import subprocess
import time

ENGINE = "/opt/homebrew/bin/godot"
NORMAL_LIMITS = {"proof": 10, "import": 30, "parse": 15, "case": 30}
FOCUS_LIMITS = {"proof": 12, "import": 45, "parse": 20, "case": 45}
ERRORS = ["SCRIPT ERROR", "Parse Error", "ERROR:", "ObjectDB instances leaked", "Resources still in use"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pair", type=pathlib.Path)
    parser.add_argument("--root-start", required=True, help="Exact separately granted exclusive START identifier")
    parser.add_argument("--deadline-epoch", required=True, type=float, help="Root's finite slot deadline, UTC epoch seconds")
    args = parser.parse_args()
    pair = args.pair.resolve()
    freeze = json.loads((pair / "freeze.json").read_text())
    if sha(pathlib.Path(__file__)) != freeze["tooling"]["tests/private_pinned_occupied/run_normal_gate.py"]:
        raise SystemExit("Frozen launcher mismatch")
    root = pathlib.Path(__file__).resolve().parents[2]
    boundary_script = root / "tests/private_pinned_layout/snapshot.py"
    cleanup_script = pathlib.Path(__file__).with_name("postflight_normal.py")
    if sha(boundary_script) != freeze["boundary_script_sha256"] or sha(cleanup_script) != freeze["tooling"]["tests/private_pinned_occupied/postflight_normal.py"]:
        raise SystemExit("Frozen boundary/cleanup tooling mismatch")
    parser_script = root / "tests/private_pinned_layout/run_compatibility.py"
    if sha(parser_script) != freeze["result_parser_sha256"]:
        raise SystemExit("Frozen serialized-result parser mismatch")
    parse_result = runpy.run_path(str(parser_script))["parse_result"]
    if sha(pathlib.Path(__file__).with_name("postflight.py")) != freeze["tooling"]["tests/private_pinned_occupied/postflight.py"]:
        raise SystemExit("Frozen delegated cleanup mismatch")
    records = []
    results = {}
    proved_tokens = set()
    process_groups = []
    env = dict(os.environ)
    env.pop("GODOT_USER_DIR", None)
    env.pop("XDG_DATA_HOME", None)
    for stage in ["normal", "focus"]:
        info = freeze["fixtures"][stage]
        project = pathlib.Path(info["path"])
        manifest_path = pair / (stage + "-source-manifest.json")
        if project != pair / stage or sha(manifest_path) != info["manifest_sha256"]:
            raise SystemExit("Frozen fixture identity/manifest mismatch")
        for name, expected in json.loads(manifest_path.read_text()).items():
            if sha(project / name) != expected:
                raise SystemExit("Frozen source mismatch: " + name)
    for info in freeze["fixtures"].values():
        token = info["token"]
        if not token.startswith("logot-pinned-private-occupied-") or "/" in token or "\\" in token:
            raise SystemExit("Unsafe private token")
        if (pathlib.Path.home() / "Library/Application Support" / token).exists():
            raise SystemExit("Token must be fresh; no existing userdata may be adopted")
    # Normal225 + focus146 + preflight10 + owned cleanup reserve50 fit480s.
    # Authorization is external; a deadline/label does not acquire exclusivity.
    if args.deadline_epoch - time.time() < 431:
        raise SystemExit("Insufficient granted slot remaining; no engine started")

    def invoke(stage, label, switches, limit):
        remaining = args.deadline_epoch - time.time() - 50
        if remaining < limit:
            raise RuntimeError("Insufficient slot time; no next process started")
        project = pair / stage
        command = [ENGINE, "--headless", "--path", str(project)] + switches
        started = time.monotonic()
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env, start_new_session=True)
        process_groups.append(process.pid)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=limit)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
        record = {"stage": stage, "label": label, "command": command, "limit": limit, "seconds": time.monotonic() - started, "exit": process.returncode, "timeout": timed_out, "stdout": stdout, "stderr": stderr}
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            record["surviving_process_group"] = False
        else:
            record["surviving_process_group"] = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        records.append(record)
        (pair / "commands.json").write_text(json.dumps({"root_start": args.root_start, "deadline_epoch": args.deadline_epoch, "records": records}, indent=2) + "\n")
        if timed_out or record["surviving_process_group"] or any(marker in stdout + stderr for marker in ERRORS):
            raise RuntimeError("Engine/parser/import/runtime/teardown failure; stop")
        return record

    def prove(stage, limits):
        token = freeze["fixtures"][stage]["token"]
        expected = str(pathlib.Path.home() / "Library/Application Support" / token)
        record = invoke(stage, "separate-OS-userdata-proof", ["--script", "res://tests/private_pinned_layout/userdata_proof.gd"], limits["proof"])
        output = record["stdout"] + record["stderr"]
        if record["exit"] != 0 or "Godot Engine v4.7.2" not in output or "USERDATA_PROOF=" + expected + "\n" not in output:
            raise RuntimeError("Actual engine version/OS userdata proof failed; stop")
        proved_tokens.add(token)

    def bounded_python(label, command, limit):
        if args.deadline_epoch - time.time() < limit:
            raise RuntimeError("Insufficient time for owned " + label)
        result = subprocess.run(command, capture_output=True, text=True, timeout=limit, env=env)
        (pair / (label + ".stdout.log")).write_text(result.stdout)
        (pair / (label + ".stderr.log")).write_text(result.stderr)
        if result.returncode != 0:
            raise RuntimeError("Owned " + label + " failed")

    bounded_python("boundary-preflight", [sys.executable, str(boundary_script), str(pair / "boundary-pre.json")], 10)
    gate_error = None
    try:
        for stage in ["normal", "focus"]:
            limits = NORMAL_LIMITS if stage == "normal" else FOCUS_LIMITS
            if stage == "focus" and args.deadline_epoch - time.time() < 196:
                raise RuntimeError("Do not start focus: less than146s plus50s cleanup/overhead remains")
            prove(stage, limits)
            record = invoke(stage, "cold-import", ["--editor", "--import"], limits["import"])
            if record["exit"] != 0:
                raise RuntimeError("Import failed; stop")
            prove(stage, limits)
            runner = "res://tests/run_logot_test.gd" if stage == "normal" else "res://tests/private_pinned_layout/runner.gd"
            record = invoke(stage, "parse-runner", ["--check-only", "--script", runner], limits["parse"])
            if record["exit"] != 0:
                raise RuntimeError("Parse failed; stop")
            if stage == "normal":
                userdata = pathlib.Path.home() / "Library/Application Support" / freeze["fixtures"][stage]["token"]
                for test_id in freeze["cases"]:
                    prove(stage, limits)
                    artifacts = userdata / "artifacts/tests" / test_id
                    prior = set(artifacts.glob("*.tres"))
                    record = invoke(stage, test_id + "-normal-case-and-teardown", ["--script", runner, "--", test_id], limits["case"])
                    files = set(artifacts.glob("*.tres")) - prior
                    if len(files) != 1:
                        raise RuntimeError("Expected one fully collected serialized normal result; stop")
                    result_file = files.pop()
                    result = parse_result(result_file)
                    results[test_id] = result
                    shutil.copyfile(result_file, pair / (test_id + "-result.tres"))
                    (pair / "normal-results.json").write_text(json.dumps(results, indent=2) + "\n")
                    expected = freeze["expected"][test_id]
                    if not result["passed"] or record["exit"] != 0:
                        raise RuntimeError("Normal assertion failure; no next case/focus")
                    for kind in ["code", "visual"]:
                        if len(result["checks"][kind]) != expected[kind] or any(not check["passed"] for check in result["checks"][kind]):
                            raise RuntimeError("Normal incomplete collection/failure; stop")
                    skipped = sum("Skipped: screenshot capture is not available in headless mode." in check["serialized"] for check in result["checks"]["visual"])
                    if skipped != expected.get("headless_visual_skipped", 0):
                        raise RuntimeError("Unexpected visual skip qualification; stop")
                    print(test_id, "code", expected["code"], "headless_visual_skipped", skipped, flush=True)
            else:
                prove(stage, limits)
                record = invoke(stage, "unchanged-focused168-and-teardown", ["--script", runner], limits["case"])
                result = json.loads((pair / stage / "result.json").read_text())
                shutil.copyfile(pair / stage / "result.json", pair / "focused-result.json")
                if record["exit"] != 0 or result["collected"] != 168 or result["passed"] != 168 or result["failed"] != 0:
                    raise RuntimeError("Focused168 assertion/collection/exit failure; stop")
                print("focused",168,168,0,flush=True)
    except BaseException as error:
        gate_error = str(error)
    finally:
        # Finish all owner cleanup inside the slot, including failure paths.
        cleanup_errors = []
        for group in process_groups:
            try:
                os.killpg(group, 0)
            except ProcessLookupError:
                continue
            try:
                os.killpg(group, signal.SIGKILL)
            except ProcessLookupError:
                pass
            cleanup_errors.append("Owned process group survived invocation: " + str(group))
        try:
            bounded_python("owned-cleanup", [sys.executable, str(cleanup_script), str(pair), "--proved-tokens", json.dumps(sorted(proved_tokens))], 20)
        except BaseException as error:
            cleanup_errors.append(str(error))
        try:
            bounded_python("boundary-postflight", [sys.executable, str(boundary_script), str(pair / "boundary-post.json")], 10)
            if (pair / "boundary-pre.json").read_bytes() != (pair / "boundary-post.json").read_bytes():
                raise RuntimeError("Canonical cache/icon/normal-userdata boundary changed")
            for stage in ["normal", "focus"]:
                manifest = json.loads((pair / (stage + "-source-manifest.json")).read_text())
                if any(sha(pair / stage / name) != expected for name, expected in manifest.items()):
                    raise RuntimeError("Frozen source changed during gate")
        except BaseException as error:
            cleanup_errors.append(str(error))
        result = {"gate_error": gate_error, "cleanup_errors": cleanup_errors, "completed_before_deadline": time.time() <= args.deadline_epoch, "proved_tokens": sorted(proved_tokens)}
        (pair / "gate-result.json").write_text(json.dumps(result, indent=2) + "\n")
        if gate_error or cleanup_errors or not result["completed_before_deadline"]:
            raise SystemExit("Gate/postflight failed; preserved gate-result.json")
    print("Unchanged123 + real-runtime bridge8 + focused168 =299 code checks and1explicit visual skip; owned cleanup complete", flush=True)


if __name__ == "__main__":
    main()
