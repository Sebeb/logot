#!/usr/bin/env python3
"""Source-only fixture preparation. Never starts Godot or accesses a remote."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid
import re

ROOT = Path(__file__).resolve().parents[2]
BASE = "98d26210ecb4be64efda8ef7a2e204316fb15f19"
PLUGIN = "addons/logot/logot_plugin.gd"
PANEL = "addons/logot/editor/logot_editor_panel.gd"


def git(*args):
    return subprocess.check_output(["git", "--no-lazy-fetch", *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit("Fresh nonexistent destination required")
    git("merge-base", "--is-ancestor", BASE, "HEAD")
    files = git("ls-tree", "-r", "--name-only", BASE, "addons/logot").decode().splitlines()
    driver = (ROOT / "tests/private_plugin_lifecycle/editor_cases.gd").read_bytes()
    if driver.count(b"\t_check(") != 30:
        raise SystemExit("Unexpected editor fixture assertion count")
    manifest = {"base_commit": BASE, "status": "PREPARED_UNRUN", "driver_contract": {"main_checks": 24, "preexisting_checks": 6, "required_user_argument": "--lifecycle-deadline-unix-ms=<fixed admitted absolute Unix milliseconds>", "requires_ready_marker": True, "requires_witness_per_check": True, "identity_checks": {"base": 1, "candidate": 8}, "panel_checks_per_driven_process": 3, "marker_contract_sha256": sha((ROOT / "tests/private_plugin_lifecycle/marker-contract.json").read_bytes())}, "fixtures": {}}
    destination.mkdir(parents=True)
    for revision in ("base", "candidate"):
        for scenario in ("cold", "cases", "preexisting"):
            if revision == "base" and scenario == "cold":
                continue  # Historical clean control remains in immutable v4.
            project = destination / (revision + "-" + scenario)
            project.mkdir()
            for name in files:
                path = project / name
                path.parent.mkdir(parents=True, exist_ok=True)
                content = (ROOT / name).read_bytes() if revision == "candidate" and name in (PLUGIN, PANEL) else git("show", BASE + ":" + name)
                path.write_bytes(content)
            fixture = project / "fixture"
            fixture.mkdir()
            (fixture / "foreign_console.gd").write_text("@tool\nextends Node\n")
            token = "logot-lifecycle-" + uuid.uuid4().hex
            plugin_cfg = "res://addons/logot/plugin.cfg"
            if scenario != "cold":
                (fixture / "editor_cases.gd").write_bytes(driver)
                (fixture / "identity_contract.gd").write_bytes((ROOT / "tests/private_plugin_lifecycle/identity_contract.gd").read_bytes())
                (fixture / "panel_contract.gd").write_bytes((ROOT / "tests/private_plugin_lifecycle/panel_contract.gd").read_bytes())
                (fixture / "marker-contract.json").write_bytes((ROOT / "tests/private_plugin_lifecycle/marker-contract.json").read_bytes())
                (fixture / "plugin.cfg").write_text('[plugin]\nname="Logot lifecycle regression"\ndescription="Real production plugin subclass"\nauthor="Logot"\nversion="1"\nscript="editor_cases.gd"\n')
                plugin_cfg = "res://fixture/plugin.cfg"
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Private Logot lifecycle"\n'
                'config/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + token + '"\n'
                '[editor_plugins]\nenabled=PackedStringArray("' + plugin_cfg + '")\n'
                '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
                '[lifecycle_test]\npreexisting=' + ('true' if scenario == 'preexisting' else 'false') + '\n')
            sources = {str(p.relative_to(project)): sha(p.read_bytes()) for p in sorted(project.rglob("*")) if p.is_file()}
            manifest["fixtures"][project.name] = {"path": str(project), "userdata_token": token, "source_sha256": sources}
    (destination / "freeze.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"destination": str(destination), "fixtures": list(manifest["fixtures"]), "status": "PREPARED_UNRUN"}))


if __name__ == "__main__":
    main()
