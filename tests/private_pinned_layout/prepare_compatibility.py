#!/usr/bin/env python3
"""Create minimal normal-lifecycle compatibility fixtures without engine use."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = "622f2288155b5a88fbbf950bde6aa21eb023b395"
CANDIDATE = "da5f0fcb63ef245e20b031c282e88fcde6ef359e"
RUNTIME = ["logot.gd", "logot_display.gd", "logot_command_input.gd", "log_level.gd", "logot_sidebar.gd", "performance_source_monitor.gd", "logot.tscn", "logot_sidebar.tscn", "logot_theme.tres", "IBMPlexMono-Regular.ttf"]
RUNTIME += ["widgets/" + name for name in ["performance_widget_base.gd", "performance_overview_widget.gd", "performance_source_graph_widget.gd", "performance_overview_widget.tscn", "performance_source_graph_widget.tscn"]]
RUNTIME += ["testing/" + name for name in ["logot_test_case.gd", "logot_test_context.gd", "logot_test_manager.gd", "logot_test_panel.gd"]]
RUNTIME += ["testing/resources/" + name for name in ["logot_test_run_result.gd", "logot_test_check_result.gd", "logot_test_visual_result.gd", "logot_test_log_record.gd"]]
RUNTIME += ["assets/" + name + ".svg" for name in ["channel_visible", "channel_hidden", "channel_off", "channel_mixed", "Clear", "AnimationFilter"]]
RUNTIME = ["addons/logot/" + name for name in RUNTIME]
RUNTIME += [name + ".uid" for name in list(RUNTIME) if name.endswith(".gd") and (ROOT / (name + ".uid")).is_file()]
ORIGINAL = ["Main.tscn", "tests/run_logot_test.gd", "tests/logot_cases/command_palette_pinned_variables_test.gd", "tests/logot_cases/render_scale_settings_test.gd"]
TOOLING = {"tests/private_pinned_layout/registered_pin_compatibility_test.gd": "tests/logot_cases/registered_pin_compatibility_test.gd", "tests/private_pinned_layout/userdata_proof.gd": "tests/private_pinned_layout/userdata_proof.gd"}
EXPECTED = {"command_palette_pinned_variables": {"code": 24, "visual": 1, "headless_visual_skipped": 1}, "render_scale_settings": {"code": 20, "visual": 0}, "registered_pin_compatibility": {"code": 73, "visual": 0}}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit("Use a new destination; never rewrite frozen evidence")
    destination.mkdir(parents=True)
    freeze = {"candidate_commit": CANDIDATE, "base": BASE, "expected": EXPECTED, "cases": list(EXPECTED), "source_mapping": TOOLING, "fixtures": {}}
    for stage, ref in [("candidate", CANDIDATE), ("base", BASE)]:
        target = destination / stage
        token = "logot-pinned-private-" + uuid.uuid4().hex + "-compat-" + stage
        for name in RUNTIME + ORIGINAL:
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(subprocess.check_output(["git", "show", ref + ":" + name], cwd=ROOT))
        for source, name in TOOLING.items():
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / source, path)
        # The unchanged normal targeted runner constructs the actual Logot Node
        # and runs _enter_tree/_ready, the real manager/context and exact Main.
        # No mock console is used. No autoload or plugin runs during import/proof.
        (target / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Private Logot compatibility"\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + token + '"\nrun/main_scene="res://Main.tscn"\n[display]\nwindow/size/viewport_width=1152\nwindow/size/viewport_height=720\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[editor_plugins]\nenabled=PackedStringArray()\n')
        manifest = {str(path.relative_to(target)): digest(path) for path in sorted(target.rglob("*")) if path.is_file()}
        manifest_file = destination / (stage + "-source-manifest.json")
        manifest_file.write_text(json.dumps(manifest, indent=2) + "\n")
        freeze["fixtures"][stage] = {"path": str(target), "token": token, "manifest_sha256": digest(manifest_file), "sources": len(manifest)}
    freeze["tooling_sha256"] = {str(path.relative_to(ROOT)): digest(path) for path in [pathlib.Path(__file__), ROOT / "tests/private_pinned_layout/run_compatibility.py", ROOT / "tests/private_pinned_layout/registered_pin_compatibility_test.gd"]}
    (destination / "freeze.json").write_text(json.dumps(freeze, indent=2) + "\n")
    print(json.dumps(freeze, indent=2))


if __name__ == "__main__":
    main()
