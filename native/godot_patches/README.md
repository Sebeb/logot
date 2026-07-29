# Logot Godot patches

This directory contains ordered `git format-patch`-compatible diffs against
Godot commit `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88` (4.7-stable).

`scripts/build_profiler_godot.sh` resets its engine checkout to that commit and
applies every `*.patch` file in lexical order before copying the Logot module and
building. Keep numeric filename prefixes stable so patch ordering is explicit.
