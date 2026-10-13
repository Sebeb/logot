#!/usr/bin/env python3
"""Run a frozen fixture only during an explicitly granted headless slot."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import time

ENGINE = "/opt/homebrew/bin/godot"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=pathlib.Path)
    parser.add_argument("--granted-slot", required=True, help="Coordinator's finite gate identifier")
    args = parser.parse_args()
    project = args.fixture.resolve()
    evidence = project.parent
    stage = project.name
    records = []
    limits = {"proof": 12, "import": 45, "parse": 20, "case": 45}
    expected = json.loads((evidence / (stage + "-source-manifest.json")).read_text())
    for name, expected_hash in expected.items():
        if hashlib.sha256((project / name).read_bytes()).hexdigest() != expected_hash:
            raise SystemExit("Frozen source mismatch: " + name)
    started = time.monotonic()
    env = dict(os.environ)
    env.pop("GODOT_USER_DIR", None)
    env.pop("XDG_DATA_HOME", None)

    def invoke(label, switches, timeout):
        command = [ENGINE, "--headless", "--path", str(project)] + switches
        begin = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, env=env)
            record = {"label": label, "command": command, "limit_seconds": timeout, "seconds": round(time.monotonic() - begin, 3), "exit": result.returncode, "output": result.stdout + result.stderr}
        except subprocess.TimeoutExpired as error:
            record = {"label": label, "command": command, "limit_seconds": timeout, "seconds": round(time.monotonic() - begin, 3), "timeout": True, "output": str(error.stdout) + str(error.stderr)}
        records.append(record)
        (evidence / (stage + "-commands.json")).write_text(json.dumps({"slot": args.granted_slot, "total_seconds": round(time.monotonic() - started, 3), "records": records}, indent=2) + "\n")
        print(label, record.get("exit", "TIMEOUT"), record["seconds"], flush=True)
        if record.get("timeout") or record.get("exit") not in [0, 1] or any(marker in record["output"] for marker in ["SCRIPT ERROR", "Parse Error", "ERROR:", "ObjectDB instances leaked", "Resources still in use"]):
            raise SystemExit("Engine failure; inspect preserved commands before continuing")
        return record

    def prove():
        record = invoke("userdata-proof", ["--script", "res://tests/private_pinned_layout/userdata_proof.gd"], limits["proof"])
        if record["exit"] != 0 or "USERDATA_PROOF=" not in record["output"] or "Godot Engine v4.7.2" not in record["output"]:
            raise SystemExit("Isolation proof failed")

    # The proof process itself runs only the isolated project and its proof script.
    # Every later engine process is preceded by a fresh independent OS proof.
    prove()
    imported = invoke("cold-import", ["--editor", "--import"], limits["import"])
    if imported["exit"] != 0:
        raise SystemExit("Import failed")
    prove()
    parsed = invoke("parse-runner", ["--check-only", "--script", "res://tests/private_pinned_layout/runner.gd"], limits["parse"])
    if parsed["exit"] != 0:
        raise SystemExit("Parse failed")
    prove()
    result = invoke("case-and-teardown", ["--script", "res://tests/private_pinned_layout/runner.gd"], limits["case"])
    if not (project / "result.json").exists():
        raise SystemExit("No collected result; not a behavioral regression result")
    collected = json.loads((project / "result.json").read_text())
    if collected.get("collected") != 168 or (result["exit"] == 0) != (collected.get("failed") == 0):
        raise SystemExit("Unexpected assertion collection or exit status; stop")
    print(json.dumps({key: collected[key] for key in ["collected", "passed", "failed"]}))
    manifest = {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(project.rglob("*")) if path.is_file() and ".godot" not in path.parts}
    (evidence / (stage + "-post-manifest.json")).write_text(json.dumps(manifest, indent=2) + "\n")
    raise SystemExit(result["exit"])


if __name__ == "__main__":
    main()
