#!/usr/bin/env python3
"""Prepare only. Never starts Godot. Runtime requires a coordinator slot."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "622f2288155b5a88fbbf950bde6aa21eb023b395"
SOURCES = ["addons/logot/logot_display.gd", "addons/logot/log_level.gd", "addons/logot/testing/logot_test_case.gd"]
SOURCES += ["addons/logot/assets/channel_" + name + ".svg" for name in ["visible", "hidden", "off"]]
TESTS = ["tests/private_pinned_layout/pinned_display_responsive_layout_test.gd", "tests/private_pinned_layout/runner.gd", "tests/private_pinned_layout/userdata_proof.gd"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def manifest(root):
    return {str(path.relative_to(root)): digest(path) for path in sorted(root.rglob("*")) if path.is_file() and ".godot" not in path.parts}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=pathlib.Path)
    parser.add_argument("--font", type=pathlib.Path, required=True)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit("Destination must be new to preserve earlier evidence")
    destination.mkdir(parents=True)
    freeze = {"base": BASE, "source": {name: digest(ROOT / name) for name in SOURCES + TESTS}, "font_source": str(args.font.resolve()), "font_sha256": digest(args.font), "fixtures": {}}
    for stage in ["before", "after"]:
        target = destination / stage
        token = "logot-pinned-private-" + uuid.uuid4().hex + "-" + stage
        for name in SOURCES + TESTS:
            fixture_name = "tests/logot_cases/pinned_display_responsive_layout_test.gd" if name.endswith("/pinned_display_responsive_layout_test.gd") else name
            path = target / fixture_name
            path.parent.mkdir(parents=True, exist_ok=True)
            if stage == "before" and name in SOURCES:
                path.write_bytes(subprocess.check_output(["git", "show", BASE + ":" + name], cwd=ROOT))
            else:
                shutil.copyfile(ROOT / name, path)
        shutil.copyfile(args.font, target / "fixture_font.ttf")
        # Neither autoloads nor enabled plugins are present. The theme is not
        # referenced by project settings during cold import; runner loads it later.
        (target / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Private pinned layout"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + token + '"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[editor_plugins]\nenabled=PackedStringArray()\n')
        (target / "fixture_theme.tres").write_text('[gd_resource type="Theme" load_steps=2 format=3]\n[ext_resource type="FontFile" path="res://fixture_font.ttf" id="1"]\n[resource]\ndefault_font=ExtResource("1")\ndefault_font_size=40\n')
        frozen = manifest(target)
        (destination / (stage + "-source-manifest.json")).write_text(json.dumps(frozen, indent=2) + "\n")
        freeze["fixtures"][stage] = {"path": str(target), "token": token, "manifest_sha256": digest(destination / (stage + "-source-manifest.json"))}
    (destination / "freeze.json").write_text(json.dumps(freeze, indent=2) + "\n")
    print(json.dumps(freeze, indent=2))


if __name__ == "__main__":
    main()
