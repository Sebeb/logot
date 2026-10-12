# Logot Guide for Agents

This guide captures the integration conventions established by the Pills God project. The Logot APIs are reusable, while StateStore and the final project-reference section describe that host project's architecture.

## What Logot is in this project

Logot is the project's in-game developer console, structured command palette, live diagnostic overlay, and integration-test harness. It is loaded as the `Console` autoload in `project.godot`, so runtime code normally talks to `Console` rather than constructing a Logot object.

Treat Logot as the game's operational interface. A well-integrated system should let a developer or agent:

- find its controls by browsing a predictable path;
- inspect important live values without reading the scene tree;
- change safe runtime state through the same public paths the game uses;
- invoke deliberate actions and cheats with useful feedback;
- see why an action is unavailable;
- pin useful values or widgets while playing; and
- drive the same commands from an automated Logot run.

Logot is not only a text console. Its command paths form a browsable, multi-column palette. Commands, values, descriptions, options, grouping, icons, disabled states, default actions, and widgets all contribute to that palette.

## Opening and using the command palette

In a running game:

- Press `/` while Logot is closed to open the command palette at the root.
- Press `Shift+backtick` while Logot is closed to reopen the command palette. Logot remembers the last hidden palette path.
- Press `backtick` to toggle the full log console.
- Press `Cmd/Ctrl+backtick` to open or resize the full console.
- Use `Up` and `Down` to move between rows.
- Use `Left` and `Right` to move between path columns.
- Use `Cmd/Ctrl+Up` and `Cmd/Ctrl+Down` to jump between groups.
- Use `Tab` to accept the highlighted completion.
- Use `Enter` to run the selected command.
- Use `Escape` to leave command-entry mode.

On touch devices, Logot exposes an edge button that opens the palette. Controller navigation is also supported by the addon.

The palette is path-oriented. Typing `/maze` shows the next tier under `maze`; choosing `generate` advances to `/maze/generate`. Descriptions explain the highlighted row, display variables put current values next to rows, and option providers add subsequent columns. This makes a path useful both as a command-line address and as a discoverable UI hierarchy.

Logot also supports nine temporary palette spaces. `Cmd/Ctrl+Alt+1` through `9` store the current palette position, and `Cmd/Ctrl+1` through `9` return to one. Spaces last for the current session and preserve the exact input, including partial filters and arguments.

## What Logot can expose

### Commands

Commands invoke actions. Project examples include generating a maze, teleporting the player, taking a pill, printing a profiler snapshot, and running a Logot test.

Use a command for an event or operation, especially when the result is not itself a lasting setting. Register command paths without a leading slash; users execute them with a leading slash.

```gdscript
const _REBUILD_COMMAND := "my_system/rebuild"

func _ready() -> void:
	if Console == null:
		return
	Console.add_command(_REBUILD_COMMAND, {
		"function": Callable(self, "_rebuild"),
		"description": "Rebuilds the current my-system runtime data.",
		"group": {"name": "Actions", "priority": 20},
		"display_label": "rebuild",
	})

func _exit_tree() -> void:
	if Console != null:
		Console.remove_command(_REBUILD_COMMAND)

func _rebuild() -> void:
	# Route through the system's normal public operation.
	Console.print_line("My system rebuilt.")
```

Prefer the named descriptor form shown above for new commands. It makes metadata reviewable and avoids fragile long positional calls. Important descriptor fields include:

- `function`: the callable to invoke;
- `arguments`: argument names shown by the palette;
- `required`: how many arguments are mandatory;
- `description`: what the command does and any important consequences;
- `display_label` and `icon`: presentation overrides;
- `group` and `option_group`: dictionaries with `name`, `priority`, and optional `tint`;
- `default_child` or `default_child_provider`: the relative route used when a parent command is invoked directly; and
- `keyboard_shortcut`: a command/control shortcut active in the visible palette column.

Descriptions should explain behavior, not repeat the path name. Commands that can fail should print an actionable error with `Console.print_error(...)`; successful human-facing actions should normally confirm with `Console.print_line(...)`.

### Commands with arguments and live options

Use `add_command_with_options` when an argument has a useful finite set of current choices. The provider is evaluated as the palette is refreshed, so it should return fresh, cheap-to-build data and should not retain dead node references.

```gdscript
func _register_target_command() -> void:
	Console.add_command_with_options("my_system/focus", {
		"function": Callable(self, "_focus_target"),
		"arguments": ["target_id"],
		"required": 1,
		"description": "Moves the debug focus to a live target.",
		"argument_options_provider": Callable(self, "_get_target_options"),
	})

func _get_target_options() -> Array:
	return _live_target_ids()

func _focus_target(target_id: String) -> void:
	# Resolve the identifier again here because the target can disappear
	# between palette display and command execution.
	pass
```

The maze command coordinator is the main project example. It exposes current level IDs for `/maze/generate` and current entity instances below `/entities/...`, while validating again at execution time.

### Set/get commands

Use `Console.add_setget_command(...)` for a runtime property that should be both visible and editable. It registers a setter command and a display variable at the same address. Boolean values automatically get `false` and `true` options; a custom options provider can supply enums or another finite domain.

```gdscript
signal debug_enabled_changed

var _debug_enabled := false

func _register_debug_toggle() -> void:
	Console.add_setget_command(
		"my_system/debug_enabled",
		Callable(self, "_set_debug_enabled"),
		Callable(self, "_get_debug_enabled"),
		"Shows or hides my-system diagnostics.",
		Callable(),
		Callable(),
		"Debug",
		10,
		"",
		0,
		self,
		&"debug_enabled_changed"
	)

func _set_debug_enabled(value: bool) -> void:
	if _debug_enabled == value:
		return
	_debug_enabled = value
	debug_enabled_changed.emit()

func _get_debug_enabled() -> bool:
	return _debug_enabled
```

Supplying a change signal is important. It lets Logot update that row when the value changes elsewhere without polling the getter every frame. The project uses this pattern in the maze command coordinator, fog and renderer diagnostics, changelog controls, and frame-sample profiler.

Because `add_setget_command` creates both registrations, scene-owned cleanup must call both `Console.remove_command(path)` and `Console.remove_display_variable(path)`.

### Display variables and pins

A display variable adds live read-only information at an address. It can share an address with a command, which puts the current value beside the action, or stand alone as an inspectable palette row.

```gdscript
signal active_count_changed

func _register_count() -> void:
	Console.add_display_variable(
		"my_system/active_count",
		Callable(self, "_get_active_count"),
		Callable(),
		Callable(),
		true,
		"Status",
		0,
		self,
		&"active_count_changed"
	)
```

The `pinnable` argument controls whether the user can keep the value in the in-game overlay. For a diagnostic that should start pinned, use `Console.pin(key, getter, signal_source, signal_name)`. Use `Console.unpin(key)` during teardown. `F4` toggles all pins, and pin APIs support the four screen corners.

Prefer signal-backed refresh. If there is no suitable signal, call `Console.notify_display_variable_changed(address)` after a mutation. Avoid putting expensive traversal, allocation, or rendering work in a getter because palette rows and pins may evaluate it repeatedly.

Display variables can also provide an inline color, several small value items, a dynamic label, and wrapped prose. Use those features when they clarify state, not as decoration.

### Widgets and render textures

Use `Console.add_widget(...)` for richer diagnostics, such as the project's gameplay timer and audio panels. The widget scene should implement `configure_logot_widget(address, mode, corner)` and `refresh_logot_widget(delta)` when it needs those lifecycle hooks.

Use `Console.add_render_texture_widget(...)` when a live `Texture2D` is the diagnostic, such as a render mask or simulation surface. Widgets appear inside the relevant palette column and can also participate in pinned overlay modes. Always remove scene-owned widgets in teardown.

### Logs, timers, screenshots, performance, and tests

Other useful Logot surfaces include:

- `Console.try_log(...)` for lazy, level- and channel-filtered structured logs;
- `Console.start_timer(...)` and `Console.stop_timer(...)` for named runtime timings;
- `Console.capture_screenshot(...)` and `/bridge/screenshot` for visual evidence;
- performance overview and source widgets, with `F3` cycling performance pins;
- `/test/list`, `/test/reload`, `/test/recent`, `/test/last`, and `/test/<test_id>` for the discovered test harness; and
- `Console.execute_console_command(...)` for tests or runtime code that intentionally composes an existing command surface.

Use `try_log` for potentially frequent diagnostics because it avoids constructing the message when its level or channel is disabled. Do not use Logot output as the authoritative state store.

## Exposing game state: use StateStore first

Most lasting, typed game configuration in this project belongs in `StateStore`, not in an ad hoc field with a custom console command. A `StateVariableDef` is automatically represented in Logot unless it is fully hidden. This gives the palette a consistent state tree with:

- the resolved value at the variable path;
- `default`, `base`, and `override` layers;
- finite option rows for booleans and enums;
- typed input for continuous values;
- active claim inspection and temporary claim muting;
- removal commands for local layers; and
- folder-level counts and bulk removal actions.

For a new configurable gameplay value, define it through the project's state-variable workflow with a clear path, type, default, resolver, description, and possible values. Then have runtime code observe that state. Do not add a second Logot setter for the same value.

The relevant visibility flags have distinct meanings:

- `console_exposed = true`: the root is editable and its layers are inspectable.
- `console_exposed = false`: the root edit command is omitted, but its layers remain inspectable.
- `console_hidden = true`: the variable is absent from Logot, including its layers. Reserve this for cases where even the diagnostic overhead is undesirable.

The override layer is generally best for temporary developer changes. It is explicit, visible, and removable, and it does not silently rewrite the authored default or persisted base value. Use normal `StateStore` APIs from gameplay code so claim resolution and signals remain correct.

## Designing a good palette tree

Choose paths as a user-facing information architecture:

- Start with the owning domain: `maze/...`, `audio/...`, `debug_tools/...`, or the canonical state path.
- Use lowercase `snake_case` segments.
- Put related actions and values beside one another.
- Keep paths stable so scripts, tests, history, and agent instructions remain valid.
- Prefer identifiers over array positions for dynamic objects.
- Avoid aliases unless compatibility requires them.
- Do not duplicate a StateStore path with a separate command hierarchy.

Use groups to separate actions such as `Status`, `Actions`, `Debug`, and `Remove` inside one column. Priorities control stable group order. Tints can express a real semantic category, as StateStore does for default, base, override, and claims, but should not become the only carrier of meaning.

A parent may declare a static or dynamic default child. This lets direct execution of the parent choose the currently sensible action, and the palette previews the route in later columns. Default-child routes must remain valid, enabled, and cycle-free. Prefer them when there is one safe, unsurprising primary action. Do not hide a destructive or context-sensitive choice behind an implicit default.

Use `Console.set_command_path_disabled(path, disabled)` when a command is temporarily unavailable. By default this disables descendants too. Pass `false` as the third argument only when sibling or descendant-looking routes are independently owned. Disabled rows are preferable to accepting an action that cannot succeed, but the command callback must still validate because state can change after the row was rendered.

For dynamic catalogs, update only what changed. Wrap bulk registrations and removals in `Console.batch_ui_updates(func(): ...)`. This project has thousands of catalog entries, and each catalog change can trigger validation and palette refresh work. Cache disabled states and skip redundant calls, as `PillManager` does.

## Registration and ownership rules

Register an interface where its runtime owner becomes ready, and unregister every scene-owned command, display variable, and widget when that owner exits. Autoload-owned registrations may live for the process lifetime, but should still keep their registration code centralized.

Recommended pattern:

1. Keep address constants beside the owning system.
2. Put registration in one `_register_console_bindings()` method.
3. Put symmetrical cleanup in `_unregister_console_bindings()`.
4. Guard both methods when `Console == null` if the code can run in stripped or isolated contexts.
5. Bind callbacks to the owner, not to transient children that may be freed first.
6. Re-resolve dynamic targets during execution.
7. Batch large catalog changes.

Do not mutate `Console.console_commands` or `Console.display_variables` directly. Use the public add, remove, disable, pin, and notification APIs so Logot can update its indexes and active displays.

## Agent and automated usage

The shell bridge executes the same command surface without manual UI interaction:

```sh
./scripts/logot_cmd.sh /maze/generate
./scripts/logot_cmd.sh /test/reload
./scripts/logot_cmd.sh /test/maze_console_commands
```

Use `--no-focus` when appropriate for a background rendered run. Tests with `ctx.capture_visual(...)` require rendering:

```sh
LOGOT_BRIDGE_HEADLESS=0 ./scripts/logot_cmd.sh /test/<test_id>
```

A successful test command needs `ok: true` and, when present, `test_passed: true`. Record the run ID and artifact path. For command integration tests, prefer executing the registered command with `Console.execute_console_command(...)` rather than calling its private callback directly. This verifies the address, argument parsing, disabled state, and registration lifecycle as well as the underlying behavior.

Do not put secrets in command arguments. Logot persists command history. Use a masked prompt or another dedicated secret-entry flow, as the feedback GitHub token command does.

## Integration checklist

Before finishing a Logot integration, check that:

- the path is stable, predictable, and owned by one system;
- durable typed state uses StateStore rather than an ad hoc setter;
- every action has an accurate description and useful success or failure output;
- live values use a signal-backed display variable where possible;
- dynamic options and callbacks revalidate stale selections;
- unavailable actions are disabled without relying on that as the only guard;
- scene-owned registrations are removed on teardown;
- bulk catalog changes use `batch_ui_updates` and avoid redundant refreshes;
- no getter performs expensive work every frame;
- no secret can enter persisted console history; and
- the interface is verified through the palette or `scripts/logot_cmd.sh`, with a focused Logot test when the behavior is substantial or regression-prone.

## Useful Pills God project references

- `project.godot`: `Console` autoload registration.
- `addons/logot/logot.gd`: public registration, execution, logging, pin, widget, timer, screenshot, and bridge APIs.
- `addons/logot/logot-command-palette-tech-spec.md`: advanced palette behavior such as default children, group tints, shortcuts, widgets, orderable groups, and spaces.
- `systems/autoload/state_store.gd`: the canonical layered state-to-palette integration.
- `systems/maze/maze_scene_console_command_coordinator.gd`: lifecycle-owned actions, dynamic options, display variables, and set/get commands.
- `systems/pills/pill_manager.gd`: dynamic command trees, display values, disabled states, and batched catalog updates.
- `systems/debug/frame_sample_profiler.gd`: a small, clear set/get plus action-command example.
- `tests/logot_cases/`: examples of testing command registration, execution, display metadata, widgets, and live refresh.
