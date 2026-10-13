#!/usr/bin/env python3
"""Preserve normal serialized results, then reuse proved-token cleanup."""
import argparse
import json
import pathlib
import runpy
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
    for stage, info in freeze["fixtures"].items():
        token = info["token"]
        if token not in proved:
            continue
        if not token.startswith("logot-pinned-private-occupied-") or "/" in token or "\\" in token:
            raise SystemExit("Unsafe private token")
        userdata = pathlib.Path.home() / "Library/Application Support" / token
        if userdata.is_symlink():
            raise SystemExit("Refusing symlink userdata")
        for result in (userdata / "artifacts/tests").rglob("*.tres"):
            if result.is_symlink():
                raise SystemExit("Refusing symlink result")
            target = pair / "private-userdata-results" / stage / result.relative_to(userdata)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(result, target)
    runpy.run_path(str(pathlib.Path(__file__).with_name("postflight.py")), run_name="__main__")


if __name__ == "__main__":
    main()
