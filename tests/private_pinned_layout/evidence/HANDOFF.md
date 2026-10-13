# Responsive pinned-display owner handoff

Branch: `fix/m1-pinned-display-responsive-layout`. Base: `622f2288155b5a88fbbf950bde6aa21eb023b395`. Production source remains the tested frozen candidate with SHA256 `bfaa1e179ae34b14e78239b531e3f0efdac36f426b5994186e702d450b3f6b80`. The exact byte-identical case now resides at `tests/private_pinned_layout/pinned_display_responsive_layout_test.gd`, SHA256 `0e0bba9206c03559ee406fe0c7847c7213ac70ba94c0d0e5331b030d2e0ba226`. `prepare.py` explicitly maps that source to the original frozen fixture destination `tests/logot_cases/pinned_display_responsive_layout_test.gd`; neither frozen fixture was rewritten after the run. The private case is outside normal discovery because it requires the private tree/theme adapter.

Ownership is exactly the nine source, docs and tooling paths enumerated in `owned-before-manifest.json` and `owned-after-manifest.json`, plus this evidence directory. The package system-doc UID remains `sdoc-399e8f4a-645c-40f4-af08-59f3d4827671`. No public method signature, pin option, preference format, saved corner/order, visibility policy, font-size policy or host source changes. Existing private two-argument `_layout_pinned_overlay_corner_columns(corner, rows)` calls remain syntactically supported through optional arguments.

## Accepted finite runtime gate

START `2026-10-13 01:25:52 UTC`; RELEASE `2026-10-13 01:26:57 UTC`; 65 seconds including cleanup within the six-minute exclusive headless grant. Actual engine banner: Godot 4.7.2. Every nonproof invocation had a separate fresh proof using its actual private project and `OS.get_user_data_dir()`. No autoloads/plugins started. Cold import included the three SVGs and supplied real font before the theme/case were loaded. No browser or native window was used.

| Stage | Collected | Passed | Failed | Proof/import/proof/parse/proof/case exits |
| --- | ---: | ---: | ---: | --- |
| Base | 168 | 154 | 14 | 0, 0, 0, 0, 0, 1 |
| Candidate | 168 | 168 | 0 | 0, 0, 0, 0, 0, 0 |

The baseline failures are twelve narrow viewport containment assertions, one opposing bottom-corner overlap assertion, and one widget-focus assertion. All exact assertion names/details, including passes, remain in `before-result.json`. No parser, import, runtime, timeout, leak, or teardown error occurred. The post used the same frozen case; its full results remain in `after-result.json`.

Each process was bounded: OS proof 12 seconds, cold import 45 seconds, parser 20 seconds, case plus teardown 45 seconds. Three proofs yield a hard process sum of 146 seconds per fixture, 292 seconds per pair. Both launchers completed far below those bounds. Exact commands and captured stdout/stderr are preserved in the two `*-commands.json` files and twelve separate `.log` files. `evidence-hashes.json` hashes every preserved artifact except itself. The normal private userdata log directories were deleted during cleanup; their complete captured process output remains here. No fixture engine process remained.

## Immutable manifests

| Artifact | SHA256 |
| --- | --- |
| owned-before-manifest.json | 9b6102ccf0b02c56d8c97e478698f17d518e1afa0e4b0d5125a944cb6caf9042 |
| owned-after-manifest.json | 922e3e4fe0eea81f1782d043dcd1034117b4b0b6e1785cf3d101dfd319c59799 |
| before-source-manifest.json | 5dca16cb3edf6aad654b327b8f6ab881d9141e5e812498ae9c805768d192e574 |
| after-source-manifest.json | dec5f5e9190dc19167ddf68cbabc89a4ac8e8827248258d39016e5525ff2c1c4 |
| before-post-manifest.json | 875cd2aae0b1d06fa14220be9172d9956f43f4a12b243257ebb6ec6e278245be |
| after-post-manifest.json | 3402eadceff4d2e132f21b48cfc26ce4f64000de6429fad0e8e1bc6ff9abcf71 |
| before-commands.json | 526ec7050faa277f090ae72de5eda695a7ed7c7235042d4d377e55d096b57aeb |
| after-commands.json | 308c6d611d7f792070e8a1a9882dddf776883108a04f9a858054e60d7888784e |
| before-result.json | 8012fca2f7510cdfd9d7b5f83df1e28ea5adb60a0155e9c52c7be9881c0a5a98 |
| after-result.json | 598a952a6b1aa747f663e2db1ca373c495a88e9e2e0625b0311946b3f92ad537 |
| freeze.json | c874ed0f5706a6413471c67bb5124d9fd2343f02f7791c1351921b014744028d |
| boundary-pre.json and boundary-post.json | 934d90bfed2a15d474102a904ca447b952b2ea055e27ff0a2fca8091ea23ee07 |

Boundary manifests are exactly equal, covering canonical Git HEAD/status, canonical cache files, the unrelated untracked `icon smol.png`, and normal Logot/Adventure Infinitum userdata. No canonical, AdInf, vault, vendor or unrelated package file was written. Boundary equality is evidence for this owner's gate, not an assertion about other agents' later work.

## Coverage and remaining limits

The focused case checks real RichText rows for version, FPS and the active DEV summary at CSS 360/390 with the actual supplied rainyhearts font size 40. Canvas-to-CSS ratios 0.5 and 1 map to canvas widths 720/780 and 360/390 respectively. It exercises insets 112/7/11/13, resize and getter changes, multiline complete content, four-corner horizontal containment/collision, measured content width/height, stable row identities, interactive widget identity/focus/caret/draft, unchanged corner/order, and retention of unbounded prose.

This focused passing case does not establish actual Main/browser acceptance, touch/render-scale modes, saturated top/bottom height allocation, multiple overflow columns, rich BBCode variants or performance-widget geometry. Normal targeted suites remain callable using `tests/run_logot_test.gd` and a properly isolated Console/Main/import fixture: `command_palette_pinned_variables`, `render_scale_settings`, `command_palette_widget_placement`, `widget_display_order`, and `logot_performance_sources`. They were not run. The minimal direct runner does not provide their normal context or visual checkpoints, and the normal runner itself has no hard wall-clock timeout. Any future run needs an external bound plus a new scheduling grant and userdata proof.

Finite-fit behavior preserves compact rows and requested corners when content fits. Display-variable width budgets wrap complete values instead of permitting intrinsic table overflow. Corner packing remeasures heights after wrapping and restores focused controls after reparenting. Native widget minimum dimensions remain authoritative. Unbounded prose/pin counts, extremely restrictive insets, paragraphs taller than their assigned lane, and irreducibly wide widgets may still overflow. No hidden loss, font shrink, forced unpin, invented scrolling UI or universal no-overlap guarantee is claimed. General overflow navigation requires separate UI design.

Root owns independent review, canonical integration/publication and the AdInf gitlink. This owner has finished its package candidate and is holding without further engine launches.
