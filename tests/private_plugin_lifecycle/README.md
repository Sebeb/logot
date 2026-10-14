# Logot lifecycle integrated identity successor

Status: SOURCE ONLY, all native/editor parsing and runtime checks UNRUN. This independent local package succeeds d1e0f4040fb1cb8422d97584648f554093bc211c without editing that package, frozen v2 projects, installed98d, standalone37ca, primary source or failed runtime receipts. No publication or adoption is authorized.

## Causal evidence and exact engine contracts

The released3be7 baseline ran the deferred driver after Starting file scan, before class/import completion, collected24/4 and exited1. Its stderr contains UID lookup/autoload/named-global failures and Scan thread aborted. Those are real failures, not accepted baseline noise. The actual raw Console setting was not logged, so its representation in that run is unproved.

Retained primary Godot source at ed1daf0bf is under upstream/, with original URLs and SHA256 inventory. editor_autoload_settings.cpp autoload_add stores a leading singleton marker plus ResourceUID.path_to_uid. editor_plugin.cpp delegates the production editor API to that implementation. The literal res-path creation assertion was therefore representation-specific. ResourceUID.get_id_path can error for missing mappings; has_id and text_to_id support a guarded resolver.

editor_file_system.cpp _update_scan_actions updates script classes before imports. Initial scan completion emits filesystem_changed and sources_changed after those actions and first_scan reset. is_scanning includes first_scan; is_importing is a bound API. Its editor progress code can reenter the main loop while importing, so a deferred callback, fixed frame count or false scanning state alone is insufficient. The new driver connects before production activation, observes script_classes_updated, filesystem_changed and sources_changed, then requires idle scanning/importing and the expected known Logot UID mapping. No scan, reimport, UID-cache injection or timed sleep is initiated by the driver.

## Narrow successor changes

Production still uses its real editor APIs. It clears ownership before teardown and checks setting existence. A direct path or registered UID must resolve to the exact Logot script before removal; unknown UID returns false without get_id_path. Creation is claimed only when the setting actually exists and resolves to that same identity. Preexisting settings, foreign replacements and unknown identities are preserved. The same-resource remove/re-add generation limitation remains explicit: this does not establish who last wrote an identical identity.

The fixture retains all24 main and6 separate preexisting labels, including the three baseline preservation failures. Resource comparisons still require the singleton marker to match and the exact target resource; accepted representation is either direct path or a registered UID mapping to that path. Each check emits a separate LIFECYCLE WITNESS JSON object with label, existence, exact raw value, resolved path, known status and singleton marker. Missing or unknown identities cannot pass an identity comparison.

The driver requires exactly one valid --lifecycle-deadline-unix-ms argument supplied by the reviewed runner using the existing fixed admitted editor deadline, no later than the enclosing work deadline. Missing/expired admission exits2. Its process callback checks that deadline while waiting. The external supervisor remains authoritative during synchronous editor work and must retain the existing process-family timeout and cleanup reserve. The READY marker records completion flags, idle states and deadline. No default new timeout or deadline extension is introduced.

## Frozen five-project contract

prepare.py creates a fresh destination from exact98d addon objects, replacing only the candidate production plugin and installing identical successor driver bytes in base/candidate cases and preexisting projects. Each private project has a distinct userdata token. The already retained base minimal cold control is not rerun; the new freeze contains base-cases, base-preexisting, candidate-cold, candidate-cases and candidate-preexisting. See successor-contract.json for exact freeze/driver/plugin hashes, labels, source-line sites and deadline argument. No editor may run on these frozen originals; the shared runner owner materializes independent copies and retains mutations/cache evidence.

Reviewed expected outcomes, not results:

- Base minimal cold can be clean; it is a separate control, not reproduction of historical Mobile failure.
- Base main cases:24 checks,3 main failures, separately counted identity1 expected capability-absent failure, exit1. Failed labels remain replaced.preserved, repeated.foreign_preserved, unstarred.foreign_preserved. Exactly three missing-setting diagnostic pairs are expected at the mapped call sites, with ERROR get_order and WARNING get_setting_with_override. All unrelated diagnostics, including UID/autoload/named-global/scan-aborted errors, fail the gate.
- Base preexisting:6/0, exit0, clean diagnostics.
- Candidate minimal cold, main24/0 plus separately counted identity8/0, and preexisting6/0 must all be clean. Require READY and per-check identity witnesses for driven projects in addition to exact labels/result/exit.
- Original Mobile failure stays historical negative evidence. A fresh composed Mobile cold import must separately qualify any proposed shared-pin adoption. The actual operation removing Console there remains unproved.

Tooling owns runner/classifier changes and admission. This package does not alter either. Updated line sites and hashes require source review before any new grant; no retry is implied. Preserve all full streams and reject unknown diagnostics rather than modifying the allowlist after execution. The existing outer600 contract and cleanup reserve must remain fixed if the reviewed runner can admit the revised stages; this source package does not itself grant runtime.

identity_contract.gd now runs immediately after ordinary.released, before the remaining original main checks. It emits a distinct typed collection, ordered check records and result, described exactly in marker-contract.json. Baseline collects one capability_absent expected failure without generating an additional stderr diagnostic. Candidate collects eight identity checks; any identity failure or precondition error forces process exit1 independently of the main24 result. Preexisting6 remains separate and emits no identity markers. No new process family, warning suppression, classifier allowance or deadline budget is introduced. The main/preexisting assertion lines and bodies are source-compared with d1, allowing only this invocation and exit aggregation.

Candidate identity verifies singleton path, registered singleton UID, non-singleton path, foreign path refusal, unknown UID refusal, unknown preexisting setting unclaimed/preserved/released. Its unknown setting is fixture-owned metadata, never submitted to the editor autoload loader, and is erased before the original main cases resume. Collection requires ordinary teardown left Console absent. Readiness/precondition errors are fatal, not new expected negatives. The same-resource generation limitation remains unchanged. This is targeted identity behavior coverage, not evidence of the missing raw setting in the old failed run.

Marker order is READY, lifecycle checks1..4, IDENTITY COLLECTION, IDENTITY CHECK records, IDENTITY RESULT, lifecycle checks5..24, main RESULT. Witness and identity ordinals are independent. Typed marker schemas, exact labels and collection counts are frozen alongside sources. The fixed stage argument remains --lifecycle-deadline-unix-ms=<admitted editor deadline>, never later than the work deadline. The shared runner must bind these exact new bytes and review marker validation before START.

## Offline controls and remaining limits

source_controls.py checks unchanged30 labels, readiness/deadline/witness source structure, UID guard ordering, ownership-marker ordering, Python syntax, primary-source hashes and the relevant engine implementation constructs. It is not a GDScript parser and does not emulate or prove engine behavior. Five prepared inventories were checked against their hashes and baseline/candidate addon differences are restricted to the production plugin. git diff --check passed. All runtime outcomes, including whether initial creation acquires valid ownership, remain unproved and must fail honestly if their preconditions differ.

No primary change record or pin adoption is authored here. Integration owns the eventual tested upgrade/change record. No services were started and no restart is needed for source preparation. A later accepted adoption requires a fresh Godot client launch/export.
