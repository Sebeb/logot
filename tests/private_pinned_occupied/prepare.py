#!/usr/bin/env python3
"""Source-only preparation. Never invokes Godot or copies caches/vaults."""
import argparse
import hashlib
import runpy
import json
import pathlib
import shutil
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "cac17e49da86f99ca8c7f556f67f7330044fe2d5"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit("New destination required; frozen evidence is immutable")
    sources = runpy.run_path(str(ROOT / "tests/private_pinned_layout/prepare_compatibility.py"))["RUNTIME"]
    tooling = ["tests/private_pinned_occupied/case.gd", "tests/private_pinned_occupied/runner.gd", "tests/private_pinned_layout/userdata_proof.gd"]
    freeze = {"base": BASE, "candidate_parent": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "boundary_script_sha256": digest(ROOT / "tests/private_pinned_layout/snapshot.py"), "fixtures": {}, "tooling": {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / "tests/private_pinned_occupied").glob("*")) if p.is_file() and p.name != "readiness.json"}}
    destination.mkdir(parents=True)
    for stage in ["before", "after"]:
        project = destination / stage
        token = "logot-pinned-private-occupied-" + uuid.uuid4().hex + "-" + stage
        for name in sources + tooling:
            path = project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if stage == "before" and name in sources:
                path.write_bytes(subprocess.check_output(["git", "show", BASE + ":" + name], cwd=ROOT))
            else:
                shutil.copyfile(ROOT / name, path)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Private Logot occupied bounds"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + token + '"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[editor_plugins]\nenabled=PackedStringArray()\n')
        (project / "fixture_theme.tres").write_text('[gd_resource type="Theme" load_steps=2 format=3]\n[ext_resource type="FontFile" path="res://addons/logot/IBMPlexMono-Regular.ttf" id="1"]\n[resource]\ndefault_font=ExtResource("1")\ndefault_font_size=40\n')
        manifest = {str(p.relative_to(project)): digest(p) for p in sorted(project.rglob("*")) if p.is_file()}
        manifest_path = destination / (stage + "-source-manifest.json")
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        freeze["fixtures"][stage] = {"path": str(project), "token": token, "manifest_sha256": digest(manifest_path)}
    (destination / "freeze.json").write_text(json.dumps(freeze, indent=2) + "\n")
    print(json.dumps(freeze, indent=2))


if __name__ == "__main__":
    main()
