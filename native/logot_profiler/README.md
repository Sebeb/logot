# Logot profiler Godot module

This debug-only module exposes Godot's internal render timestamp and script
profiling data to the Logot addon through the `LogotProfilerBridge` engine
singleton. It is built into a custom editor or debug export template; it is not
a GDExtension and cannot be added to an existing Godot binary.

Use `scripts/build_profiler_godot.sh` from the Logot repository to build a
matching Godot 4.7-stable binary.
