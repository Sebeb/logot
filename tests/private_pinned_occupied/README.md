# Occupied pin bounds source readiness

The observer re-arm correction passed the released source05 focused gate: faulty baseline72/64/8 at the exact declared labels, corrected candidate72/72/0. Evidence_05 preserves exact results, warnings and cleanup. The earlier59/58/1 candidate failure remains unchanged in evidence_04. Independent source review found no demonstrated introduced blocker; normal compatibility299 subsequently passed and is archived in evidence_normal_02; host acceptance and root publication remain separate. See diagnosis.md and normal-plan.md. Earlier private pinned-layout cases and all compatibility_evidence_02 evidence remain immutable.

The public contract is `get_pinned_overlay_occupied_rects() -> Dictionary[String, Rect2]`, `get_pinned_overlay_viewport() -> Viewport`, and no-payload `pinned_overlay_occupied_rects_changed`. Console uses its runtime display only. External/editor consumers use their explicit LogotDisplay. Four named effective-corner viewport-space AABBs include actual visible live registered row rectangles and overflow. Empty corners are Rect2(), absent coordinate ownership is null, and snapshots contain detached values only.

Prepare without Godot:

```sh
python3 tests/private_pinned_occupied/prepare.py /tmp/logot-pinned-occupied-NEW
```

The next before source is the tested faulty observer commit cac17e49da86f99ca8c7f556f67f7330044fe2d5; after source comes from this worktree. Both get identical case/runner/proof bytes. Preparation copies only the explicit package runtime dependencies from the existing private compatibility preparation, the focused case, runner, proof and package font. It copies no caches, primary vault, host source or primary project. Each actual project.godot enables custom userdata with its own relative token and no autoloads/plugins. The source manifests and freeze record exact SHA-256 hashes.

After root separately grants an exclusive START, a proposed 350-second slot runs exactly:

```sh
python3 tests/private_pinned_occupied/run_gate.py /private/tmp/logot-pinned-occupied-NEW --root-start EXACT_START --deadline-epoch EXACT_ROOT_DEADLINE
```

The label and deadline do not acquire exclusivity or authorize themselves. The command must stay held until root grants that exact slot. Standard /opt/homebrew/bin/godot must report 4.7.2; no suffix binary or standalone version invocation is used. The launcher refuses less than 332 seconds remaining, including bounded boundary preflight and owned cleanup. Each project runs a separate actual OS-userdata proof immediately before cold import, runner parse, and case/teardown. Each proof is bounded at 12 seconds, import at 45, parse at 20, and case at 45. Six proofs plus the two import/parse/case sequences total at most 292 seconds, reserving at least 30 seconds for owner-executed cleanup and postflight; boundary preflight has a separate 10-second limit. Timeout kills the invocation's owned process group. Unexpected parser/import/runtime/teardown errors or result collection mismatches stop the pair immediately.

Before must collect all 72 checks with exactly the eight named transform/publication failures declared by the frozen launcher, 64 passes and exit 1, with no engine error. Fixture-premise failures or any changed collection/failure label stop the gate. Only after that valid regression failure may after run. After must collect all 72 checks with zero failures and exit 0. The extended case bytes are identical in both fixtures, and all original 59 checks remain. Source-level checks and declared counts do not constitute test acceptance.

The launcher owns postflight within the same 350-second slot, on success and failure. It records read-only canonical .godot, icon smol.png and normal Logot/Adventure Infinitum userdata boundaries before engine use (10-second limit). It preserves private userdata inventories and logs, removes only the exact fresh tokens that passed actual OS proof (10-second limit), then compares boundary manifests and verifies frozen source hashes (boundary subprocess limited to 10 seconds). Owned process groups must exit; survivors are killed and fail the gate. Unproved-token remnants are reported as a cleanup failure and never silently deleted. Captured commands, case results, logs, manifests and cleanup report remain in the private pair. No post-deadline root cleanup is part of acceptance. Existing 291-check normal compatibility and host/browser acceptance need additional separately bounded gates; this focused pair makes no such claim.
