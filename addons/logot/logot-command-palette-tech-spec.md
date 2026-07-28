Synced with 3ab398a9-b8d1-8158-a67f-ec9c201ba0cc

# Tech Spec

## Implementation Overview

This Tech Spec owns the generic Logot command-catalog and multi-column command-palette capabilities added for PGO-111: optional group tints and recursive default-child routing. It is deliberately limited to reusable addon behavior; it neither introduces nor documents state layers, state-specific paths, persistence, or color conventions.

Groups can be titled or untitled. Both command groups and command option groups may carry an optional `Color` tint. The palette derives a readable header color, a subtle fill, and a border from the tint. A titled group renders its tinted header; an untitled tinted group renders a headerless boxed run of rows. Omitted or transparent tint retains the pre-existing group appearance and ordering. Group presentation never replaces explicit row/value colors, disabled alpha, or the filled active-selection appearance.

Commands with child paths can declare a static relative `default_child_path` or a `default_child_provider`. The shared resolver recursively follows the current default through command tiers until it reaches a callable command or a text-input option terminal. Direct execution of an otherwise argument-free parent invokes that terminal once, preserving the resolver's injected option arguments. The same resolver supplies predictive palette previews, so every reachable default tier is shown at once and its focused row is outlined rather than selected.

## Key Files and Interfaces

`addons/logot/logot_display.gd` defines `LogotDisplay.LogotCommand`, which stores the existing callable/catalog fields plus `group_tint`, `option_group_tint`, `default_child_path`, and `default_child_provider`. Its constructor keeps legacy positional registrations valid by appending the new optional fields. `addons/logot/logot.gd` extends `add_command()` and `add_command_with_options()` with the same optional trailing metadata.

Dictionary-backed commands remain supported. The display normalizes either `group`/`option_group` dictionaries containing `name`, `priority`, and `tint`, or the equivalent flat fields. The catalog resolver accepts `default_child_path`, `default_child`, `default_child_provider`, and the nested dictionary form of `default_child` with `path`/`value` and `provider`.

`Logot.resolve_default_child_chain(command_name)` is the single resolver shared by validation, direct execution, and display prediction. Its successful result carries `terminal_command`, `injected_arguments`, and ordered `focus_paths`; an invalid result carries the origin and an actionable `Invalid default child for '/…'` diagnostic. `Logot._notify_command_catalog_changed()` runs `_validate_default_child_commands()` before invalidating live displays, and `_execute_command()` routes an argument-free non-option parent through the resolver before dispatching the terminal callable.

`LogotDisplay.set_default_child_resolver()` receives that resolver from `Logot`. The display's group-data normalization and tier-match builder preserve tint for both titled and empty-title groups. `_append_default_child_preview_columns()` appends one preview state per resolver focus path, while `_refresh_command_preview_option_state()` rebuilds those marked preview states whenever the palette refreshes.

## State, Lifecycle, and Data Flow

Registration constructs typed metadata or consumes dictionary metadata, then calls `_notify_command_catalog_changed()`. At that refresh boundary the catalog evaluates each declared default and emits diagnostics before a user attempts execution. Dynamic providers are evaluated at this same resolution/refresh seam rather than polled per frame, which keeps dynamic paths current without retaining stale preview columns.

Resolution begins with a normalized command path, obtains its current default specification, and normalizes a relative target against the current command. It resolves the target through the existing command/option-path machinery, records each newly traversed tier in `focus_paths`, and repeats if the target is another command with a default. A terminal option subcommand contributes injected arguments; a terminal callable or text-input option is valid. The direct-execution path consumes this complete result only when the parent was invoked without explicit arguments, so explicit option submissions retain their normal semantics.

For palette prediction, the active column obtains the same resolver result. The display creates a preview column for every `focus_path`, finds that path in the tier's matches, and marks the matched row `default_focus`. Preview columns are non-active: the active column maintains normal keyboard/mouse selection and the preview rows render a 2-pixel rectangular outline in the option-highlight color after normal row and group drawing. Rebuilding the catalog or a preview replaces the preview chain from current resolver data, so a changing dynamic provider cannot leave obsolete columns or focus state behind.

Tint travels from typed or dictionary metadata through `_normalize_command_group_data()`, `_get_tier_command_group_data()`, and tier matches as `group_tint`. Row construction gives an empty-title tinted group a stable synthetic grouping key so adjacent rows form one headerless box. Rendering blends tint into group fill, border, and header only; it does not alter command/value styling, disabled treatment, or selection fill.

## Invariants and Failure Modes

Default paths are relative to the declaring command after trimming slash and whitespace noise. Empty segments and `.` are ignored; `..` may move upward only while the path remains rooted. A chain has a 32-step maximum and tracks visited command paths, so cycles cannot execute indefinitely. Targets must resolve to a registered command or valid option/text-input subcommand and must not be disabled. A final non-callable, non-text-input command is rejected.

Invalid provider return types, missing or stale targets, escaped/empty paths, cycles, disabled targets, non-executable terminals, and excessive recursion all yield a clear diagnostic. Invalid routes never execute an intermediate command or a partial default chain. Untinted catalog entries and groups retain legacy behavior, including group priority/order, ordinary preview selection fallback, filtering, history, autocomplete, scrolling, and navigation.

Tints are additive metadata. Title emptiness suppresses only priority/header text; it must not discard a non-transparent tint. This preserves headerless visual grouping while avoiding a new special command type. The implementation is generic to the vendored Logot addon and must not encode application- or state-specific color/path knowledge.

## Verification

`tests/logot_cases/logot_tinted_groups_and_default_children_test.gd` covers typed and dictionary tint normalization, static multi-tier and recursive defaults, dynamic resolution refresh, direct execution exactly once, cycle/missing/disabled rejection, and text-input terminals. `tests/logot_cases/logot_tinted_groups_and_default_children_visual_test.gd` assembles a titled warm group, an untitled blue two-row group, and recursive defaults; it asserts two populated opaque preview columns and captures the rendered palette.

The successful PGO-111 retest ran the focused behavior suite headlessly (18/18 checks) and the rendered suite (4/4 checks plus one capture) from an isolated Godot project and HOME. It also reran command-palette regression coverage for incremental autocomplete updates, group scoping, multi-column scroll visibility, and hidden-path restoration. The rendered capture confirmed the titleless tint box, titled tint, two recursive preview columns, and thick selection-colored default outlines distinct from the filled active root selection. The retest's catalog-rebuild probe also confirmed the missing-default diagnostic is emitted before execution.

## Orderable Groups, Shortcuts, and Multi-Highlights

`Logot.add_orderable_group(path, fetch_objects, get_order, set_order)` registers a group whose provider returns `{id, label}` dictionaries. The palette sorts those generated object commands by `get_order`, renders a drag handle on each row, and rewrites zero-based orders through `set_order` after a handle drag. `refresh_orderable_group(path)` rebuilds the generated catalog when membership or labels change. Every object receives a `move` submenu with move-up, move-down, move-to-top, and move-to-bottom commands bound to Cmd/Ctrl+Up, Cmd/Ctrl+Down, Cmd/Ctrl+Shift+Up, and Cmd/Ctrl+Shift+Down.

Commands accept an optional trailing `keyboard_shortcut: Key`. Visible shortcuts are resolved across the active column and its immediate preview: preview bindings replace active-column bindings, while the first row wins within one column. Losing bindings remain visible with reduced alpha. A command/control key event submits the winning command directly.

Preview matches can carry multiple highlights. Default-child focus uses the existing blue outline, while shortcut highlights are layout-only. When the inclusive range between the first and last highlight exceeds the current row capacity, alternating gaps replace middle rows with disabled `+ X hidden options` summaries until every highlighted row fits. Column reconstruction on palette resize recalculates those summaries, restoring rows as height becomes available.

`tests/logot_cases/orderable_groups_shortcuts_and_highlights_test.gd` covers generated command metadata, all movement modes, display ordering, drag reorder semantics, shortcut precedence, invisible preview highlights, and height-dependent gap collapsing.
