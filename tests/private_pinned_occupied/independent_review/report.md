# Independent Logot occupied-bounds review

Pinned candidate `bef2b82c9c06f67ab0da9037bbf3e2a7b33a3256`, published base `3af9ab9ea324cb36bc640c42ae52ddc627b6389f`. Runtime and test blob IDs/SHA256 are explicitly recorded in `probes.json`; evidence/docs-only amendments do not replace those reviewed pins. No demonstrated concrete introduced blocker found in this bounded source review. Normal compatibility and host visual acceptance remain required before publication/adoption claims.

## API and geometry contract

`addons/logot/logot_display.gd:3255-3269` exposes a detached four-corner value dictionary and the coordinate-owning Viewport. Empty/hidden corners use Rect2(); detached/queued-deletion displays expose empty/null. The contract is the last settled visible row Control AABB, including overflow, not glyph ink, CSS/screen coordinates or clipped viewport content.

`:3344-3367` filters registered/current pins and valid visible rows in the owning viewport and overlay subtree, transforms all four row corners with `get_global_transform_with_canvas`, and merges each effective-corner AABB. This is correct for rotation/nonuniform scaling; a two-point shortcut would not be. Publication compares rectangles and viewport identity before emitting. Public getters expose no row nodes or mutable internal dictionaries.

`addons/logot/logot.gd:2288-2342` uses a dedicated weak runtime display rather than `_get_active_display` or external/editor fallback. Runtime setup binds it explicitly. Rebinding disconnects both old forwarding hooks, clears ownership before its empty/null notification, then binds the replacement. Display exit clears synchronous availability before notifications. Existing display/editor APIs and preferences were not removed or repurposed.

## Observation, settling and lifetime

`logot_display.gd:3281-3297` observes inherited row transforms through a nonvisual Node2D child. It now calls its own global-transform getter before invalidation, rearming its dirty cache rather than sampling only the row. Guards reject detached/queued observers and invalid callbacks. Ordinary geometry signals and container sorts also invalidate; connections and observer creation are deduplicated.

`:3316-3342` coalesces into a fixed two-frame deadline without restarting it on every invalidation. The sampler disconnects before reading and does not modify layout. Exit cancels pending sampling and clears state; re-entry schedules fresh work. Row/column reparenting preserves controls and adds no layout or preference mutation.

The process-disabled segments are meaningful isolation, not a hidden substitute: `case.gd:101-116,209-218` explicitly checks requested rotations and processing-off premises, then compares actual row geometry and exactly one changed publication, including the same row after exit/re-entry. Its oracle reads row transforms and never primes the observer cache. Source05 reproduces eight exact failures on the faulty observer and passes on the correction. The display-level O1 transform comparison remains necessary for CanvasLayer/viewport-canvas changes; its operation while display processing is disabled is not claimed by these row-only isolation segments.

## Evidence verified, not rerun

Verified source05 freeze SHA256 `b7cfb465094f49adea0eb02f88c8a9d883ada5ac03c02007817c215af96de75b`, fixture manifests/files and identical72-check case bytes. Before cac17e49 collected72/64pass/8fail with exactly the enforced transform/publication labels; after matches bef runtime bytes and collected72/72pass. Gate records no runtime/cleanup failure and equal boundary manifests. The three known font/SVG UID fallback warnings per case remain qualified, not erased as zero-warning acceptance.

Against cac17e49, only the observer callback changes in production; Console is byte-identical. Source04's failed59/58/1 result and22 evidence hashes remain intact. All159 prior published private-layout files are byte-identical. Thus earlier failure evidence is not retroactively labelled accepted. Readiness/diagnosis still contain preparation-era NOT RUN language at this pin; owner should reconcile that documentation with preserved source05 results before publication, without changing runtime/test pins.

## Smallest remaining gates and limits

Rerun the already defined normal291 compatibility scope at these runtime pins in a bounded isolated grant:123 normal-context checks plus the168 responsive layout case, retaining the explicit headless visual skip. Add a minimal real Console/Main getter/viewport-forwarding assertion if the old normal cases never query this capability; the focused occupied case manually binds the runtime display. No broad package suite is required solely for this additive getter.

Then the host must adopt the exact tested pin, export normally and verify default version/FPS/wrapped-DEV-summary clearance at390 CSS portrait and the already required320-width case. Verify growth/shrink, role visibility teardown, viewport-to-host coordinate conversion and no clearance feedback loop. This package source review cannot establish actual host layout or browser acceptance.

Performance is bounded structurally, not benchmarked: one observer per row, O1 display fallback, finite coalescing and O(number of rows) scans on invalidation. Existing periodic layout can still invalidate unchanged bounds and incur scans. Large pin counts, sustained animated geometry and adversarial signal-listener free/rebind reentrancy were not runtime-tested. No performance guarantee or universal fit claim.

No engine/browser, DB/provider/network/services, product/canonical/vault/index writes or delegation. Review artifacts only. No restart needed for review. Package publication, host gitlink adoption, Web export/client reload and any actual activation remain root-owned. HOLD.
