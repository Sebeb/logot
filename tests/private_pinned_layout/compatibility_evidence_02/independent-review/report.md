# Independent minimum-reservation delta review

Candidate `a32b7f3c5d15d4fbc8fffdd0052aa0966fcc80e1`, previous `990128557eb1a7d647f949412c4a021b2aacff9c`. No demonstrated concrete blocker in this source-only delta. Candidate remains unrun; this is readiness for a bounded gate, not package acceptance or publication approval.

## Production correction

The production diff is exactly16 additions in `addons/logot/logot_display.gd`. `:4924-4927` records each corner's largest native widget combined minimum. `:4947-4957` reserves both minima after natural allocation and before text wrapping. When minima fit available width A, left allocation becomes at least its minimum and at most A minus the right minimum. Right is then at least its minimum and at most A minus allocated left. Consequently both minima are retained and total allocation is at most A. The existing6-unit inter-corner separation is already removed from A when both groups exist. Compact single-sided demand remains unchanged.

When native minima cannot fit, the branch retains their demand and requested corners. Subsequent usable-width caps bound the text budget; they do not shrink widget controls, whose actual combined minima remain authoritative. No impossible no-overlap promise is made. This is a bounded correction to the previously demonstrated240-unit widget opposite wrappable prose, not a universal content-fit scheme.

Public method signatures are unchanged. No corner/preference/order/control-identity/focus/cleanup path changes in this production delta. Prior multi-column and saturated-height limits remain: the corner reservation is a maximum single-row widget minimum, not a guarantee that every column or arbitrarily tall paragraph fits.

## Compatibility fixture correction

`tests/private_pinned_layout/registered_pin_compatibility_test.gd:57-72` retains the actual registered widget/prose identity, draft, caret, focus, corner, order, containment and collision assertions, including360/390 widths. The genuine finite-collision checks were not removed or weakened.

`:155-164` now waits for queued row deletion and asserts exactly one empty old column. This matches the preexisting source path: unpin queues the row; empty-address refresh returns before rebuilding columns. The private helper appends columns, so an old remaining column made the old count/first-column assumptions invalid on both base and candidate. Failed preconditions terminate the case and the launcher rejects incomplete collection (`run_compatibility.py:131-146`); they cannot be hidden as a pass.

`:167-190` installs a genuinely fresh fixture-only container, calls the exact legacy two-argument helper with supported Control rows, checks both column order and containment, restores the original map and frees the temporary container. Product cleanup remains unchanged. This exercises helper compatibility rather than editing production to satisfy a stale fixture.

`:108-123` adds the negative native-minimum case: both pins and requested corners survive and240-unit minima are retained. It deliberately asserts no containment/collision success when those minima cannot fit. That is appropriate for the accepted overflow contract.

Fresh base and candidate use byte-identical corrected79-check registered cases. They differ from the prior73-check case and must not be described as identical historical before/post fixtures. Old failures remain historical evidence.

## Proposed next gate

The proposed normal gate is a sufficient scoped next step: `command_palette_pinned_variables`24code plus1 explicitly headless-skipped visual, `render_scale_settings`20code, and corrected `registered_pin_compatibility`79code, totalling123code assertions. Only after complete normal success should the unchanged168-assertion focused case run. Total successful scope is291code plus1skip. It covers the demonstrated mixed-minimum correction and original focused regressions; no browser/host/touch-rendered acceptance is implied.

Actual engine process timeout sum is185+146=331seconds, leaving29seconds within360. Failure classification adds a matching-base case instead of focus:185+105=290seconds. These sums exclude source verification, result serialization, boundary capture, private-log preservation and cleanup. `run_compatibility.py:147-159` does that work outside individual engine timeouts. Treat331 as a process bound, not a total wall-clock guarantee. Root should reserve cleanup time and start focus only when remaining time exceeds its146-second bound plus that reserve and overhead; otherwise split the normal and focused gates. Parser/import/runtime/leak/timeout/partial collection failures must stop immediately; valid collected normal failure may use only the matching base case.

## Verified evidence and limits

Verified requested freeze SHA256,8 referenced artifact hashes, exact production patch identity against Git and supplied delta,3 pinned source/case hashes, normal53+53source files, focus12+12source files, and corrected case equality in fresh base/candidate. Public signatures match. Details in `probes.json`.

No engines, browser, runtime tests, source/canonical/host/vault/index writes, services, network or publication operations. Review artifacts only. No restart needed for review. Root retains gate scheduling, package publication and host adoption.
