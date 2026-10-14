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
    d1 = subprocess.check_output(["git", "--no-lazy-fetch", "show", "d1e0f4040fb1cb8422d97584648f554093bc211c:tests/private_plugin_lifecycle/editor_cases.gd"], cwd=ROOT, text=True)
    def body(text, name):
        return text.split("func " + name + "(", 1)[1].split("\n\nfunc ", 1)[0]
    main = body(driver, "_run_lifecycle_cases").replace("\n\t_run_identity_contract()", "").replace(" and _identity_failures == 0", "")
    assert main == body(d1, "_run_lifecycle_cases")
    assert body(driver, "_run_preexisting_activation") == body(d1, "_run_preexisting_activation")
    assert driver.index('_run_identity_contract()', driver.index('func _run_lifecycle_cases')) > driver.index('"ordinary.released"')
    assert "and _identity_failures == 0 else 1" in driver
    assert 'call_deferred("_run_lifecycle_cases")' not in driver
    for event in ("sources_changed", "script_classes_updated", "filesystem_changed"):
        assert event + ".connect(" in driver
    assert "_filesystem.is_scanning() or _filesystem.is_importing()" in driver
    assert "--lifecycle-deadline-unix-ms=" in driver
    assert "LIFECYCLE WITNESS " in driver and "LIFECYCLE READY " in driver
    product = (ROOT / "addons/logot/logot_plugin.gd").read_text()
    assert hashlib.sha256(product.encode()).hexdigest() == "9a392bbf5bada287ba4e4c5ef0b0ef827dea794fa27c58dca734034d0597d987"
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
    markers = json.loads((HERE / "marker-contract.json").read_text())
    identity = (HERE / "identity_contract.gd").read_text()
    for label in markers["identity_labels"]["base"] + markers["identity_labels"]["candidate"]:
        assert label in identity
    print("SOURCE CONTROLS PASS: 30 unchanged labels; signal/idle/deadline/witness source; guarded UID identity; primary-source hashes; Python AST")
    print("GDScript parsing, editor behavior and all runtime assertions UNRUN")


if __name__ == "__main__":
    main()
