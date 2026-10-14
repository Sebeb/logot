#!/usr/bin/env python3
"""Offline source invariants, not a GDScript parser or engine test."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OLD = "f7b0ee491b86f438226d370ed77e6c8912af73ad"


def main():
    driver = (HERE / "editor_cases.gd").read_text()
    old = subprocess.check_output(["git", "--no-lazy-fetch", "show", OLD + ":tests/private_plugin_lifecycle/editor_cases.gd"], cwd=ROOT, text=True)
    labels = lambda text: re.findall(r'^\s+_check\(.*?, "([^"]+)"\)$', text, re.M)
    assert labels(driver) == labels(old) and len(labels(driver)) == 30
    assert 'call_deferred("_run_lifecycle_cases")' not in driver
    for event in ("sources_changed", "script_classes_updated", "filesystem_changed"):
        assert event + ".connect(" in driver
    assert "_filesystem.is_scanning() or _filesystem.is_importing()" in driver
    assert "--lifecycle-deadline-unix-ms=" in driver
    assert "LIFECYCLE WITNESS " in driver and "LIFECYCLE READY " in driver
    product = (ROOT / "addons/logot/logot_plugin.gd").read_text()
    helper = product.split("func _is_logot_autoload_path", 1)[1]
    assert helper.index("ResourceUID.has_id(uid)") < helper.index("ResourceUID.get_id_path(uid)")
    assert "uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid)" in helper
    assert "return path == LOGOT_AUTOLOAD_PATH" in helper
    assert "_added_console_autoload = ProjectSettings.has_setting" in product
    assert product.index("_added_console_autoload = false", product.index("func _exit_tree")) < product.index('remove_autoload_singleton("Console")')
    ast.parse((HERE / "prepare.py").read_text())
    upstream = json.loads((HERE / "upstream/manifest.json").read_text())
    for name, item in upstream.items():
        assert hashlib.sha256((HERE / "upstream" / Path(name).name).read_bytes()).hexdigest() == item["sha256"]
    autoload = (HERE / "upstream/editor_autoload_settings.cpp").read_text()
    assert '"*" + ResourceUID::get_singleton()->path_to_uid(p_path)' in autoload
    filesystem = (HERE / "upstream/editor_file_system.cpp").read_text()
    assert "return scanning || scanning_changes || first_scan;" in filesystem
    assert '_update_script_classes();' in filesystem
    print("SOURCE CONTROLS PASS: 30 unchanged labels; signal/idle/deadline/witness source; guarded UID identity; primary-source hashes; Python AST")
    print("GDScript parsing, editor behavior and all runtime assertions UNRUN")


if __name__ == "__main__":
    main()
