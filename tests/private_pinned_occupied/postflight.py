#!/usr/bin/env python3
"""Preserve logs and remove only exact fresh tokens proved by this gate."""
import argparse
import hashlib
import json
import pathlib
import shutil


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pair", type=pathlib.Path)
    parser.add_argument("--proved-tokens", required=True)
    args = parser.parse_args()
    pair = args.pair.resolve()
    freeze = json.loads((pair / "freeze.json").read_text())
    proved = set(json.loads(args.proved_tokens))
    known = {info["token"] for info in freeze["fixtures"].values()}
    if not proved <= known:
        raise SystemExit("Unknown cleanup token")
    records = {}
    for stage, info in freeze["fixtures"].items():
        token = info["token"]
        if not token.startswith("logot-pinned-private-occupied-") or "/" in token or "\\" in token:
            raise SystemExit("Unsafe cleanup token")
        path = pathlib.Path.home() / "Library/Application Support" / token
        if path.is_symlink():
            raise SystemExit("Refusing symlink userdata")
        record = {"proved": token in proved, "existed": path.exists(), "removed": False}
        records[token] = record
        if token not in proved:
            continue
        if path.exists():
            record["files"] = {str(p.relative_to(path)): {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(path.rglob("*")) if p.is_file()}
            logs = pair / "private-userdata-logs" / stage
            logs.mkdir(parents=True, exist_ok=True)
            for log in (path / "logs").glob("*.log"):
                shutil.copyfile(log, logs / log.name)
            # Persist the inventory before deleting this exact proved directory.
            (pair / "cleanup.json").write_text(json.dumps(records, indent=2) + "\n")
            shutil.rmtree(path)
        record["removed"] = not path.exists()
    (pair / "cleanup.json").write_text(json.dumps(records, indent=2) + "\n")
    if any(not record["removed"] for record in records.values() if record["proved"]):
        raise SystemExit("Proved private userdata remains")
    if any(record["existed"] and not record["proved"] for record in records.values()):
        raise SystemExit("Unproved userdata remains; not authorized to delete")
    print("Owned proved-token cleanup complete")


if __name__ == "__main__":
    main()
