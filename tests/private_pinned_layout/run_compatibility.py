#!/usr/bin/env python3
"""Externally bounded exact normal targeted runner, only under a granted slot."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import time

ENGINE = "/opt/homebrew/bin/godot"
LIMITS = {"proof": 10, "import": 30, "parse": 15, "case": 30}
ERROR_MARKERS = ["SCRIPT ERROR", "Parse Error", "ObjectDB instances leaked", "Resources still in use"]


def parse_result(path):
    source = path.read_text()
    sections = re.split(r"(?=^\[)", source, flags=re.MULTILINE)
    external = {}
    resources = {}
    main = ""
    for section in sections:
        heading = section.splitlines()[0] if section else ""
        if heading.startswith("[ext_resource"):
            resource_id = re.search(r' id="([^"]+)"', heading)
            resource_path = re.search(r' path="([^"]+)"', heading)
            if resource_id and resource_path:
                external[resource_id.group(1)] = resource_path.group(1)
        elif heading.startswith("[sub_resource"):
            resource_id = re.search(r' id="([^"]+)"', heading)
            if resource_id:
                resources[resource_id.group(1)] = section
        elif heading == "[resource]":
            main = section
    result = {"passed": bool(re.search(r"^passed = true$", main, re.MULTILINE)), "checks": {}, "artifact": str(path)}
    for kind in ["code", "visual"]:
        field = re.search(r"^" + kind + r"_checks = (.*)$", main, re.MULTILINE)
        ids = re.findall(r'SubResource\("([^"]+)"\)', field.group(1)) if field else []
        checks = []
        for resource_id in ids:
            section = resources[resource_id]
            script_id = re.search(r'script = ExtResource\("([^"]+)"\)', section).group(1)
            expected_suffix = "logot_test_check_result.gd" if kind == "code" else "logot_test_visual_result.gd"
            if not external[script_id].endswith(expected_suffix):
                raise RuntimeError("Unexpected serialized check type")
            checks.append({"serialized_id": resource_id, "passed": bool(re.search(r"^passed = true$", section, re.MULTILINE)), "serialized": section})
        result["checks"][kind] = checks
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=pathlib.Path)
    parser.add_argument("--granted-slot", required=True)
    parser.add_argument("--case", action="append", help="Defaults to all frozen expected cases")
    args = parser.parse_args()
    project = args.fixture.resolve()
    evidence = project.parent
    stage = project.name
    frozen = json.loads((evidence / "freeze.json").read_text())
    info = frozen["fixtures"][stage]
    manifest_file = evidence / (stage + "-source-manifest.json")
    if hashlib.sha256(manifest_file.read_bytes()).hexdigest() != info["manifest_sha256"]:
        raise SystemExit("Source manifest hash mismatch")
    for name, expected_hash in json.loads(manifest_file.read_text()).items():
        if hashlib.sha256((project / name).read_bytes()).hexdigest() != expected_hash:
            raise SystemExit("Frozen source mismatch: " + name)
    selected = args.case or frozen["cases"]
    if any(name not in frozen["expected"] for name in selected):
        raise SystemExit("Unknown unfrozen case")
    records = []
    results = {}
    started = time.monotonic()
    userdata = pathlib.Path.home() / "Library/Application Support" / info["token"]
    if not info["token"].startswith("logot-pinned-private-") or "/" in info["token"]:
        raise SystemExit("Unsafe private userdata token")
    env = dict(os.environ)
    env.pop("GODOT_USER_DIR", None)
    env.pop("XDG_DATA_HOME", None)

    def save():
        (evidence / (stage + "-commands.json")).write_text(json.dumps({"slot": args.granted_slot, "total_seconds": round(time.monotonic() - started, 3), "limits": LIMITS, "records": records}, indent=2) + "\n")
        (evidence / (stage + "-results.json")).write_text(json.dumps(results, indent=2) + "\n")

    def invoke(label, switches, timeout):
        command = [ENGINE, "--headless", "--path", str(project)] + switches
        begin = time.monotonic()
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout, env=env)
            record = {"label": label, "command": command, "limit_seconds": timeout, "seconds": round(time.monotonic() - begin, 3), "exit": completed.returncode, "stdout": completed.stdout, "stderr": completed.stderr}
        except subprocess.TimeoutExpired as error:
            record = {"label": label, "command": command, "limit_seconds": timeout, "seconds": round(time.monotonic() - begin, 3), "timeout": True, "stdout": str(error.stdout), "stderr": str(error.stderr)}
        records.append(record)
        save()
        print(label, record.get("exit", "TIMEOUT"), record["seconds"], flush=True)
        output = record["stdout"] + record["stderr"]
        if record.get("timeout") or record.get("exit") not in [0, 1] or any(marker in output for marker in ERROR_MARKERS):
            raise RuntimeError("Engine/parser/runtime/teardown error; stop")
        return record

    def require_clean(record):
        if record["exit"] != 0 or "ERROR:" in record["stdout"] + record["stderr"]:
            raise RuntimeError("Proof/import/parse failed; stop")

    def prove():
        record = invoke("userdata-proof", ["--script", "res://tests/private_pinned_layout/userdata_proof.gd"], LIMITS["proof"])
        require_clean(record)
        output = record["stdout"] + record["stderr"]
        if "Godot Engine v4.7.2" not in output or "USERDATA_PROOF=" + str(userdata) not in output:
            raise RuntimeError("Wrong engine version or actual OS userdata; stop")

    try:
        prove()
        require_clean(invoke("cold-import", ["--editor", "--import"], LIMITS["import"]))
        prove()
        require_clean(invoke("parse-normal-runner", ["--check-only", "--script", "res://tests/run_logot_test.gd"], LIMITS["parse"]))
        for test_id in selected:
            prove()
            prior = set((userdata / "artifacts/tests" / test_id).glob("*.tres"))
            record = invoke(test_id + "-normal-case-and-teardown", ["--script", "res://tests/run_logot_test.gd", "--", test_id], LIMITS["case"])
            files = set((userdata / "artifacts/tests" / test_id).glob("*.tres")) - prior
            if len(files) != 1:
                raise RuntimeError("Expected one collected normal result; stop")
            result_file = files.pop()
            result = parse_result(result_file)
            results[test_id] = result
            save()
            shutil.copyfile(result_file, evidence / (stage + "-" + test_id + "-result.tres"))
            expected = frozen["expected"][test_id]
            actual = {kind: len(result["checks"][kind]) for kind in ["code", "visual"]}
            print(test_id, "collected", actual, "passed", result["passed"], flush=True)
            if actual != {kind: expected[kind] for kind in actual}:
                raise RuntimeError("Unexpected assertion collection, including fail-fast partial run; stop")
            if (record["exit"] == 0) != result["passed"]:
                raise RuntimeError("Case exit/result mismatch; stop")
            output = record["stdout"] + record["stderr"]
            errors = [line for line in output.splitlines() if "ERROR:" in line]
            # The unchanged normal runner calls push_error on a collected FAIL
            # summary. Only that expected assertion-report line is permitted.
            expected_summary = "ERROR: FAIL: %d code checks, %d visual checks," % (actual["code"], actual["visual"])
            if any(expected_summary not in line for line in errors) or (result["passed"] and errors):
                raise RuntimeError("Non-assertion engine error; stop")
            if not result["passed"]:
                raise RuntimeError("Valid collected assertion failure; stop and report before any next case")
    finally:
        if userdata.exists():
            private_manifest = {str(path.relative_to(userdata)): {"bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted(userdata.rglob("*")) if path.is_file()}
            (evidence / (stage + "-userdata-post-manifest.json")).write_text(json.dumps(private_manifest, indent=2) + "\n")
            logs = evidence / (stage + "-private-userdata-logs")
            logs.mkdir(exist_ok=True)
            for log in (userdata / "logs").glob("*.log"):
                shutil.copyfile(log, logs / log.name)
            shutil.rmtree(userdata)
        post = {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(project.rglob("*")) if path.is_file() and ".godot" not in path.parts}
        (evidence / (stage + "-post-manifest.json")).write_text(json.dumps(post, indent=2) + "\n")
        save()
        print("private userdata cleanup complete", flush=True)


if __name__ == "__main__":
    main()
