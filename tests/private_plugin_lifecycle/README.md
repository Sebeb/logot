# Editor autoload lifecycle regression, source preparation

Status: SOURCE ONLY. No Godot process, import, runtime assertion, publication or host adoption has occurred for this package.

The package starts at exact published `98d26210ecb4be64efda8ef7a2e204316fb15f19`. The plugin preimage SHA256 is `96a154fb655d6a3f3c621d08e6972ef9138722228a17fdfd3045285ff4b6bd9c`. The correction matches the coordinator proposal: release the ownership flag first, check setting existence, then remove only the exact owned script path, allowing Godot's optional leading singleton marker. There is no error suppression or plugin disabling. All other plugin behavior remains unchanged.

The flag means this plugin activation created the entry. A preexisting entry is unclaimed even if it points at the same Logot script. If another owner replaces the setting with a different path before exit, the plugin leaves it alone. Setting existence and path comparison protect the observed shutdown case. Path equality cannot detect an external remove/re-add of the identical value; this patch does not claim generation identity or establish why the editor removed the setting first.

## Prepared fixtures

`prepare.py DESTINATION` requires a fresh destination and performs only local Git reads and file writes. It uses `git --no-lazy-fetch`, takes every addon file from exact98d, and substitutes only the candidate plugin. It writes six independent projects, each with a unique custom-userdata token and a complete SHA256 inventory in `freeze.json`. No existing failed Mobile project or cache is reused.

The `cold` projects enable the original production `addons/logot/plugin.cfg`, with Console initially absent. They exercise real cold editor import and shutdown. The `cases` projects enable a test plugin that inherits the actual production plugin and executes its complete `_enter_tree`, then the actual `_ensure_console_autoload` and `_exit_tree` methods. They use real editor add/remove methods, without mocks or method overrides for those operations. They do not instantiate a second implementation of autoload ownership.

The 24 main case assertions cover ordinary creation/removal and released ownership; an entry absent before exit; a foreign preexisting entry; a foreign replacement; repeated exit with foreign and absent settings; owned and foreign non-singleton spellings; and final released editor references. The complete initial activation covers debugger/dock creation and first teardown. Subsequent entry checks exercise the production autoload helper directly, avoiding unrelated repeated panel construction. A separate preexisting project installs a real foreign entry before the complete production activation and adds six assertions for full enter/exit, repeated exit and editor reference cleanup.

## Proposed bounded engine contract, NOT authorized or executed

Use the coordinator's sole exclusive native slot and approved supervisor. Review this source and freeze before granting START. Native editor execution is required because EditorPlugin registration/removal and editor shutdown are not covered by a game/browser process.

1. Freeze the exact Godot binary SHA256 and require `4.7.2.stable.official.ed1daf0bf`, matching the Mobile failure. Snapshot the installed98d checkout, standalone37ca checkout including its untracked icon, primary pin and normal userdata/cache boundaries without modifying them. Assert no grant-owned process family exists yet. Record original negative receipt separately.
2. Recheck every prepared source hash before each invocation. Prove actual OS userdata resolution for that project's exact token using the coordinator's existing isolated proof process, bounded to 10 seconds. Abort on any token/path mismatch. No normal userdata, shared cache, browser or services may be used. Proof source/hash and binary must be included in the admission packet before START.
3. Run these six commands in sequence using the frozen binary. Each has an external 60-second process-family timeout. `--quit` is for cold import; the case driver quits itself after its result marker. No retries, plugin disable, warm-cache fallback or source changes are permitted within the grant:

   ```text
   GODOT --headless --editor --path BASE_COLD --import --quit
   GODOT --headless --editor --path BASE_CASES
   GODOT --headless --editor --path BASE_PREEXISTING
   GODOT --headless --editor --path CANDIDATE_COLD --import --quit
   GODOT --headless --editor --path CANDIDATE_CASES
   GODOT --headless --editor --path CANDIDATE_PREEXISTING
   ```

4. Preserve full stdout/stderr and exit status for every invocation. Baseline is an expected negative, never an acceptance: require the original missing `autoload/Console` diagnostic/backtrace and record all additional failures honestly. Baseline cases can produce replacement/repeated-exit failures as the old implementation removes foreign settings. Any unrelated baseline failure prevents an exact isolated comparison and requires review. Candidate cold import must exit 0 without errors, resource leaks or teardown diagnostics. Candidate cases must exit 0 with exactly one `LIFECYCLE RESULT checks=24 failures=0` marker and all 24 PASS labels. Candidate preexisting activation must separately exit 0 with exactly one `LIFECYCLE RESULT checks=6 failures=0` marker and all six PASS labels. A marker or exit 0 alone cannot waive full-stream errors, Group/PagedAllocator/ObjectDB/RID diagnostics, warnings, incomplete collection or timeout. Any diagnostic requires explicit review before acceptance; no automatic allowlist is introduced.
5. Admission requires an external 600-second total deadline, including six proof processes (60 seconds maximum), six editor families (360 seconds maximum), and a 60-second cleanup/postflight reserve. Stop before launching any stage that cannot fit its complete bound plus reserve. This leaves 120 seconds for preflight, archival and scheduling overhead. The supervisor must record PID, process start identity and descendants per family, terminate only owned live families on deadline, and prove all owned families absent. A future runnable supervisor and complete proof packet still require coordinator review; this document alone is not an executable grant.
6. Archive raw logs, exact source inventories, binary proof, case markers and cleanup receipts before deleting only proved custom userdata. Preserve fixture sources/caches and any failed packet as evidence. Recheck immutable addon/test hashes and protected checkout boundaries. The editor may update its private project settings; record exact changes and verify Console is absent at successful final teardown rather than silently excluding settings changes. Release only after listener/process/ownership postflight, with uncertainties explicitly reported.

Even a successful package gate does not prove the Mobile23 suite, composed Main activation, browser UI or human review. Those require separate reviewed adoption and fresh bounded grants. Publication and primary gitlink changes remain unauthorized.

## Offline checks performed

- Python preparation source parsed with `ast.parse`.
- Six fresh projects prepared without engine execution; each contains the same 30-assertion case source (24 main plus six separate full foreign-activation checks) where applicable.
- Base and candidate addon inventories compared: only `addons/logot/logot_plugin.gd` differs.
- Plugin preimage and candidate match the exact coordinator proposal hashes.
- `git diff --check` passed.

GDScript parser validity and real engine behavior remain unverified until the reviewed native grant. No runtime success is implied by these source checks.
