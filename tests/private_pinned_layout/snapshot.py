#!/usr/bin/env python3
"""Read-only boundary manifest for canonical caches, icon and normal preferences."""
import hashlib
import json
import pathlib
import subprocess
import sys

home = pathlib.Path.home()
canonical = home / "Documents/Logot"
paths = [canonical / ".godot", canonical / "icon smol.png"]
paths += [home / "Library/Application Support/Godot/app_userdata" / name for name in ["Logot", "Adventure Infinitum"]]
records = {}
for root in paths:
    if not root.exists():
        records[str(root)] = {"exists": False}
        continue
    files = [root] if root.is_file() else sorted(root.rglob("*"))
    records[str(root)] = {"exists": True, "files": {str(path.relative_to(root)) if root.is_dir() else path.name: {"bytes": path.stat().st_size, "mtime_ns": path.stat().st_mtime_ns, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in files if path.is_file()}}
records["canonical_git"] = {"head": subprocess.check_output(["git", "-C", str(canonical), "rev-parse", "HEAD"], text=True).strip(), "status": subprocess.check_output(["git", "--no-optional-locks", "-C", str(canonical), "status", "--porcelain=v1", "--untracked-files=all"], text=True)}
pathlib.Path(sys.argv[1]).write_text(json.dumps(records, indent=2, sort_keys=True) + "\n")
print("boundary manifest", sys.argv[1], hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
