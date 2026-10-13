# Minimum-reservation frozen review handoff

Candidate commit `a32b7f3c5d15d4fbc8fffdd0052aa0966fcc80e1`; clean worktree. Production delta from `990128557eb1a7d647f949412c4a021b2aacff9c` is exactly 16 added lines in `addons/logot/logot_display.gd`, no deletions. No public API, ordering, corner, focus/control-identity or cleanup behavior changes. The system-doc UID remains unchanged.

Frozen bundle SHA256: `826901440c87d0ad210facf5ba009fda506b8e245c53b2ef959b603fc4af96b1` (`freeze.json`). Production source SHA256: `892050a9ccc41390f7c5fcd99e65281c5d7f053bceff145eb719d5c79291f974`. Corrected normal-compatible registered case SHA256: `9be490e95d63e9c0f43f91970eb237c2a4d63a29203af318e386d03f83aab823`. Unchanged focused case SHA256: `0e0bba9206c03559ee406fe0c7847c7213ac70ba94c0d0e5331b030d2e0ba226`.

`production.patch` SHA256 `63751d0f511f179abedecbcfc33bcb57c12bc15cb2e5afa46de5ba6d83e512a9` contains the entire narrow production delta. Independent review is requested before a new runtime grant. No engine has run against this candidate.

## Allocation algorithm

For each corner, measure the greatest combined minimum width of its native widget rows. RichText display-variable rows contribute no irreducible native-widget minimum, because their complete text can wrap. After the existing natural-demand allocation, bound the left lane by its native minimum and the remaining available width minus the right native minimum. Then bound the right lane by its minimum and the remaining width after the left lane. If the sum of native minima already exceeds the available width, retain those minima and requested corners; do not fabricate containment. Existing column packing, height handling, row/control reparenting, preference ownership and overflow behavior remain unchanged. There is still no universal finite-fit guarantee for multiple columns, saturated height or unbounded content.

## Legacy fixture proof and correction

Original candidate and base both collected all 73 registered assertions. The candidate failed 4, the base 13. The two narrow widget/prose overlap failures are real remaining finite-layout issues. The other two are fixture preconditions: the old helper test counted 3 columns and selected the stale first column.

Source trace proves why: unpin queues the last row, then `_refresh_pinned_display_variables` returns for an empty address list before `_layout_pinned_overlay_rows` removes old columns. The append-only two-argument helper adds two columns to that existing last column. Both frozen result sets preserve the count 3, the passing rightmost-two-control assertion, and the failing adjacent-column assertion.

The fresh case waits for queued deletions and asserts exactly one empty old column. If that premise fails, it returns and the collector rejects partial collection; it does not advance to the helper. It installs a genuinely new HBoxContainer in only the fixture corner map, asserts 0 children, calls the exact legacy two-argument helper with Control-only rows, checks its finite two-column geometry/order, and restores the original map. No product cleanup was changed. The same fresh case bytes exist in the prepared base and candidate fixtures.

Four additional assertions cover opposing native minima that cannot fit: both pins survive, neither 240-unit widget shrinks, and requested corners remain. No containment assertion is fabricated for that negative case. Together with two legacy premise assertions, the corrected case collects 79 code checks rather than the original 73. The old and new cases must not be mislabeled as byte-identical before/post cases.

## Frozen fixtures and exact expected collection

The `normal` pair contains 53 explicit source/import dependencies each. It uses byte-identical normal runner/Main and the real Logot lifecycle, manager and context. No mock console, editor plugin, autoload bootstrap, canonical cache or normal preferences are copied. The actual IBM font/theme/scene and SVG dependencies are present and audited. The real manager's headless screenshot behavior remains intact.

| Candidate case | Expected code checks | Expected visual checks |
| --- | ---: | ---: |
| command_palette_pinned_variables | 24 | 1 explicitly headless-skipped checkpoint |
| render_scale_settings | 20 | 0 |
| registered_pin_compatibility | 79 | 0 |
| Separate unchanged focused case, only after normal success | 168 | 0 |

All-success path: 4 cases, 291 code assertions, 1 explicitly skipped visual checkpoint. No screenshot or host/browser acceptance is implied. The optional matching original-base normal case is a failure-classification path, not additional success acceptance.

Normal freeze SHA256 `9894796f013bf3cfbd54343458a6aa8ba49b964a775b2adeabad74dd1333fad4`; candidate manifest `d9b4c4568b71468df35e33b88afe1f4f4537ebba14fe084419e0f7f747d4ac44`; original-base manifest `f4f7a7cf77a643f02c4ce1db7b09ad5e30d48cfdec486107fcbf65ab55490698`. Focus freeze SHA256 `74348c762b9e7dd495134b0d496e877feb748a561e2fc3fbd8dd5e0508fe1e00`; candidate manifest `d6dedc04b33cef1e7b4edd598e5174d3bb7f69d643ab8d23c291650c7f4267d9`. Every file hash and preload/scene/theme dependency was verified without engine use.

## Finite runtime plan, pending review and explicit START

The normal launcher bounds proof/import/parse/case including teardown at 10/30/15/30 seconds. Candidate three-case hard sum is 185 seconds. Only after all normal cases pass, run the separate unchanged focused case using its already preserved launcher; its proof/import/parse/case bounds are 12/45/20/45 seconds, hard sum 146 seconds. Maximum success path is 331 seconds, leaving 29 seconds for cleanup within a six-minute grant.

If a normal case has a valid, fully collected assertion failure and no engine error, stop that launcher and optionally run only the matching original-base case. This adds at most 105 seconds, so that path is bounded to 290 seconds. Do not run the focused case on this failure path. Parser/import/runtime/leak/timeout/partial-collection errors stop immediately, with no advance to another fixture.

Every nonproof invocation is preceded by a fresh separate actual OS-userdata proof against the real private `project.godot` and unique relative custom token. Exact Godot 4.7.2 is enforced. No override.cfg, XDG isolation, browser or canonical write is used. Capture exact pre/post normal-cache/preferences/icon/Git-state boundaries, full process output, ResourceSaver/result checks, private logs and cleanup before immediate RELEASE.

Prepared commands, which require a new explicit grant:

```sh
python3 tests/private_pinned_layout/run_compatibility.py /tmp/logot-pinned-minimum-reservation-freeze-02/normal/candidate --granted-slot EXACT_NEW_GRANTED_GATE
python3 tests/private_pinned_layout/run.py /tmp/logot-pinned-minimum-reservation-freeze-02/focus/after --granted-slot EXACT_NEW_GRANTED_GATE
```

Failure-only alternative to the second command:

```sh
python3 tests/private_pinned_layout/run_compatibility.py /tmp/logot-pinned-minimum-reservation-freeze-02/normal/base --granted-slot EXACT_NEW_GRANTED_GATE --case EXACT_FAILED_NORMAL_CASE
```

## Preserved evidence and status

The da5 focused evidence and the 990 compatibility freeze/results remain byte-exact. Full 990 commands, private logs, ResourceSaver results, all 73-case failures and identical boundary manifests are versioned in `tests/private_pinned_layout/compatibility_evidence_01`. Its candidate overall FAILED 69/73; the two normal suites passed, with the pinned-variable visual explicitly skipped. Nothing in this handoff upgrades that failed candidate to acceptance or implies host acceptance.

The new candidate is source-complete, frozen and unrun. Root owns independent review, new gate scheduling, canonical publication and host pin adoption. Owner is HOLD and finishing its turn so the existing reviewer can use the capacity slot.
