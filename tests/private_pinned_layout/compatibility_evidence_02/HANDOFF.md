# Final reviewed responsive-pin package handoff

Production candidate: `a32b7f3c5d15d4fbc8fffdd0052aa0966fcc80e1`. Production source SHA256: `892050a9ccc41390f7c5fcd99e65281c5d7f053bceff145eb719d5c79291f974`. Registered compatibility case SHA256: `9be490e95d63e9c0f43f91970eb237c2a4d63a29203af318e386d03f83aab823`. Unchanged focused case SHA256: `0e0bba9206c03559ee406fe0c7847c7213ac70ba94c0d0e5331b030d2e0ba226`.

The reviewed production correction remains exactly 16 added lines relative to `9901285`, reserving native widget minimum width before distributing wrappable text. Public APIs, corner/order/preferences, focus/control identity, and production cleanup behavior remain unchanged by that correction. If opposing minima cannot fit, widgets remain pinned at their minima and requested corners, with possible overflow. No universal fit or host acceptance is claimed. The UID-preserved package system doc records the implementation and limits.

## Final gate and result

Exclusive START `2026-10-13 02:10:11 UTC`; RELEASE `2026-10-13 02:11:32 UTC`. The gate used 81 seconds including all work after START and cleanup, within its seven-minute grant. Every nonproof engine invocation had a fresh separate actual OS-userdata proof against its real private project, unique relative token and exact Godot 4.7.2. No plugins/autoloads initialized during bootstrap, no canonical/cache/preference writes occurred, and no production code changed during the gate.

| Case | Collected code | Passed code | Visual result | Engine case exit |
| --- | ---: | ---: | --- | ---: |
| command_palette_pinned_variables | 24 | 24 | 1 explicitly headless-skipped checkpoint | 0 |
| render_scale_settings | 20 | 20 | none | 0 |
| registered_pin_compatibility | 79 | 79 | none | 0 |
| Unchanged focused responsive-pin case | 168 | 168 | none | 0 |

Total: **291/291 code assertions**, plus **one skipped visual checkpoint**, four cases. The manager recorded `declared_wrapping_column_and_overlay` as `Skipped: screenshot capture is not available in headless mode.` Its serialized passed flag reflects the harness skip policy, not screenshot or visual acceptance.

All normal cases fully collected and passed before focus began. At `02:10:40 UTC`, 391 seconds remained, exceeding the required 206-second threshold: 146-second focused process bound plus 60 seconds for cleanup/overhead. The optional matching-base path was not used. Normal proof/import/parse/case process exits were ten zeros; focused exits were six zeros. No parser, import, engine runtime, leak, timeout, partial-collection or teardown errors occurred. Both launchers exited 0.

**This was not warning-free.** Bootstrap/normal loading emitted resource UID fallback warnings for `IBMPlexMono-Regular.ttf`, `Clear.svg`, and `AnimationFilter.svg`, then loaded their successfully imported dependencies using the exact text paths. Original stderr, actual private userdata logs and `warning-records.json` preserve those warnings. Repeated entries in the warning record can represent the same warning retained in different output/log artifacts; no distinct-emission count is inferred.

Normal process limits were proof 10 seconds, import 30 seconds, parse 15 seconds, and case including teardown 30 seconds; the candidate three-case hard process sum was 185 seconds. Focus used the unchanged launcher's proof/import/parse/case limits of 12/45/20/45 seconds, hard sum 146 seconds. Process sums exclude Python manifest/log/cleanup overhead. The externally observed gate duration includes that overhead. Neither individual nor gate limits were approached.

## Exact evidence and manifests

| Artifact | SHA256 |
| --- | --- |
| freeze.json | 826901440c87d0ad210facf5ba009fda506b8e245c53b2ef959b603fc4af96b1 |
| final-path-manifest.json | 69012b438c74981aa7f2af9569b89114e11a64509d00fd73f373512ba80403fb |
| normal/candidate-source-manifest.json | d9b4c4568b71468df35e33b88afe1f4f4537ebba14fe084419e0f7f747d4ac44 |
| normal/candidate-post-manifest.json | 00e6060fb88ceca4a406b0d9bd26e6161b107ac942a45b7629a12393906f9021 |
| normal/candidate-commands.json | 887cb6433c43c6c85198f0dfe675591f98b9444f7905f9373bb3f2b8290e2e85 |
| normal/candidate-results.json | 298e3331bc7d870cba3913f650d51d0a5ff586bb596b89bc780848ac74bf66cb |
| focus/after-source-manifest.json | d6dedc04b33cef1e7b4edd598e5174d3bb7f69d643ab8d23c291650c7f4267d9 |
| focus/after-post-manifest.json | 8587e6888e2d4ae07c92e5e9b784b160a0b3c658d2f7bfae4dc2e7ea518dc1a2 |
| focus/after-commands.json | 5b24e2a303d90e258ab1377d453e369b9f0d67f5c0ba384482f817c655749f93 |
| focus/after-result.json | 598a952a6b1aa747f663e2db1ca373c495a88e9e2e0625b0311946b3f92ad537 |
| boundary-pre.json and boundary-post.json | 934d90bfed2a15d474102a904ca447b952b2ea055e27ff0a2fca8091ea23ee07 |

The final path manifest enumerates 158 changed payload paths from base `622f2288155b5a88fbbf950bde6aa21eb023b395`, each with byte count and SHA256. It explicitly excludes its own file, this HANDOFF, and the evidence hash index to avoid recursive metadata hashes. `evidence-hashes.json` hashes those metadata files except itself and all evidence artifacts. Commit identity supplies the outer integrity boundary.

Full exact commands, outputs, separate stdout/stderr logs for the normal runner, focused outputs, ResourceSaver resources and collected checks remain under `normal` and `focus`. Actual private userdata logs and pre-cleanup userdata manifests are retained. All original frozen source bytes were reverified unchanged after runtime. Unique runtime userdata directories were removed, and no fixture engine process remained at RELEASE. Boundary manifests are byte-identical for canonical Git state, cache, unrelated untracked icon and normal Logot/AdInf userdata; this is evidence for this gate, not a promise about other agents' subsequent work.

## Historical evidence and compatibility qualification

Original da5 168-case evidence remains immutable in `../evidence`. Original 990 73-case compatibility evidence remains immutable in `../compatibility_evidence_01`, including candidate 69/73 and matching base 60/73 failures. Those original candidates are not retroactively relabeled as passes. The corrected 79-case source differs from the historical 73-case source and is not an identical-case historical before/post comparison.

The fresh registered case passed the guarded premise proving one old empty column after last unpin, the genuinely empty helper fixture premise, legacy two-argument helper behavior, finite two-column order/containment, actual registered 240-unit LineEdit opposite complete prose at 360/390, real registration/row/control identity, draft/caret/focus across resize and user pin rearrangement, explicit getter update, and retention of two opposing minima that cannot fit. No production cleanup was changed to satisfy the helper test.

The successful normal suite closes the requested compact/wrapped/custom-BBCode, visibility/touch-suppression, render-scale-default and corner-redirect policy coverage at package level. It does not establish screenshots, actual host activation, rendered touch layout, performance-widget geometry, saturated-height fit, arbitrary pin counts, or unbounded-content navigation. Native minima remain authoritative and excessive content can still overflow without forced unpinning, truncation or font shrink.

Root owns verification, canonical publication and AdInf pin adoption, followed by host visual scheduling. This owner has completed the reviewed package implementation and bounded validation and is HOLD with no further engine grant.
