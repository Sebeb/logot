# Private responsive pin regression

This direct case uses `ctx.tree` and `ctx.theme`; it must stay outside normal Logot test discovery. Preparation maps the byte-identical private case to `res://tests/logot_cases/pinned_display_responsive_layout_test.gd` inside each private fixture. The accepted frozen case hash is `0e0bba9206c03559ee406fe0c7847c7213ac70ba94c0d0e5331b030d2e0ba226`.

Prepare a new minimal pair without starting Godot:

```sh
python3 tests/private_pinned_layout/prepare.py /tmp/logot-pinned-private-NEW --font '/path/to/rainyhearts.ttf'
```

The baseline comes from `622f2288155b5a88fbbf950bde6aa21eb023b395`; candidate files come from this checkout. Supply the actual host font as a read-only input when reproducing the accepted geometry. No host font is vendored in this package.

Obtain the coordinator's finite exclusive headless grant before running either command. The gate label records authorization; it does not acquire a scheduling lock. Every fixture uses its own actual `project.godot` with `use_custom_user_dir=true` and a unique relative custom token. No autoload or plugin starts during cold import. Font/theme and SVG dependencies import before the case loads. No override.cfg or XDG isolation is used.

```sh
python3 tests/private_pinned_layout/run.py /tmp/logot-pinned-private-NEW/before --granted-slot EXACT_GRANTED_GATE
python3 tests/private_pinned_layout/run.py /tmp/logot-pinned-private-NEW/after --granted-slot EXACT_GRANTED_GATE
```

Run post only after a valid baseline assertion failure, with all 168 assertions collected and no engine/import/parser/runtime/teardown error. The launcher checks frozen hashes, separate actual OS-userdata proofs, exact Godot 4.7.2, result count and exit consistency. Each process has a hard bound: proof 12 seconds, import 45 seconds, parse 20 seconds, case including teardown 45 seconds. Three proofs make 146 seconds per fixture, 292 seconds per pair. Scheduling and cleanup must fit inside the external finite slot. Unexpected failures stop the sequence; do not silently continue or relabel them as baseline regression evidence.

The checked-in `evidence` directory preserves the accepted full before/post results, all baseline failures, exact commands, full captured process outputs and their hashes, source manifests, freeze, and canonical/cache/preference boundary manifests. Boundary snapshots are read-only. Normal-suite coverage remains unrun; see the package system doc for API compatibility and finite overflow limits.
