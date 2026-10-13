#!/usr/bin/env python3
"""Prepare the unchanged normal123 and focused168 cases without Godot."""
import argparse
import hashlib
import json
import pathlib
import runpy
import shutil
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
TESTED = "bef2b82c9c06f67ab0da9037bbf3e2a7b33a3256"
FONT_SHA = "268e13c6353b2555355160f4f74e4c9c35e0c1155a8d6c85dc2c194381829c2b"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=pathlib.Path)
    parser.add_argument("--font", type=pathlib.Path, required=True, help="Read-only accepted rainyhearts font; no cache/vault copying")
    args = parser.parse_args()
    pair = args.destination.resolve()
    if pair.exists():
        raise SystemExit("New destination required")
    if sha(args.font) != FONT_SHA:
        raise SystemExit("Font differs from unchanged accepted168 fixture")
    compatibility = runpy.run_path(str(ROOT / "tests/private_pinned_layout/prepare_compatibility.py"))
    focused = runpy.run_path(str(ROOT / "tests/private_pinned_layout/prepare.py"))
    tooling = ["prepare_normal.py", "run_normal_gate.py", "postflight.py", "postflight_normal.py", "normal-plan.md", "normal_runtime_bridge.gd"]
    freeze = {"tested_runtime_commit": TESTED, "expected": compatibility["EXPECTED"], "cases": list(compatibility["EXPECTED"]), "font_read_only_source": str(args.font.resolve()), "font_sha256": FONT_SHA, "fixtures": {}, "boundary_script_sha256": sha(ROOT / "tests/private_pinned_layout/snapshot.py"), "result_parser_sha256": sha(ROOT / "tests/private_pinned_layout/run_compatibility.py"), "tooling": {"tests/private_pinned_occupied/" + name: sha(ROOT / "tests/private_pinned_occupied" / name) for name in tooling}}
    freeze["expected"]["occupied_bounds_runtime_bridge"] = {"code": 8, "visual": 0}
    freeze["cases"].append("occupied_bounds_runtime_bridge")
    pair.mkdir(parents=True)
    for stage in ["normal", "focus"]:
        project = pair / stage
        token = "logot-pinned-private-occupied-compat-" + uuid.uuid4().hex + "-" + stage
        names = compatibility["RUNTIME"] + compatibility["ORIGINAL"] if stage == "normal" else focused["SOURCES"]
        mapping = dict(compatibility["TOOLING"]) if stage == "normal" else {name: ("tests/logot_cases/pinned_display_responsive_layout_test.gd" if name.endswith("/pinned_display_responsive_layout_test.gd") else name) for name in focused["TESTS"]}
        if stage == "normal":
            mapping["tests/private_pinned_occupied/normal_runtime_bridge.gd"] = "tests/logot_cases/occupied_bounds_runtime_bridge_test.gd"
        for name in names:
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(subprocess.check_output(["git", "show", TESTED + ":" + name], cwd=ROOT))
        for source, name in mapping.items():
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            # Only unchanged cases/runner/proof from the prior291 preparation.
            shutil.copyfile(ROOT / source, path)
        settings = 'config_version=5\n[application]\nconfig/name="Private occupied compatibility"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + token + '"\n'
        if stage == "normal":
            settings += 'run/main_scene="res://Main.tscn"\n[display]\nwindow/size/viewport_width=1152\nwindow/size/viewport_height=720\n'
        settings += '[rendering]\nrenderer/rendering_method="gl_compatibility"\n[editor_plugins]\nenabled=PackedStringArray()\n'
        (project / "project.godot").write_text(settings)
        if stage == "focus":
            shutil.copyfile(args.font, project / "fixture_font.ttf")
            (project / "fixture_theme.tres").write_text('[gd_resource type="Theme" load_steps=2 format=3]\n[ext_resource type="FontFile" path="res://fixture_font.ttf" id="1"]\n[resource]\ndefault_font=ExtResource("1")\ndefault_font_size=40\n')
        manifest = {str(p.relative_to(project)): sha(p) for p in sorted(project.rglob("*")) if p.is_file()}
        manifest_path = pair / (stage + "-source-manifest.json")
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        freeze["fixtures"][stage] = {"path": str(project), "token": token, "manifest_sha256": sha(manifest_path)}
    (pair / "freeze.json").write_text(json.dumps(freeze, indent=2) + "\n")
    print(json.dumps(freeze, indent=2))


if __name__ == "__main__":
    main()
