#!/usr/bin/env bash

set -euo pipefail

current_root="$(git rev-parse --show-toplevel)"

if [ -d "$current_root/.godot" ]; then
  exit 0
fi

best_source=""
best_mtime=0

current_root_real="$(cd "$current_root" && pwd)"

while IFS= read -r worktree_path; do
  worktree_real="$(cd "$worktree_path" 2>/dev/null && pwd)" || continue

  if [ "$worktree_real" = "$current_root_real" ]; then
    continue
  fi

  candidate_dir="$worktree_real/.godot"
  if [ ! -d "$candidate_dir" ]; then
    continue
  fi

  metadata_file="$candidate_dir/editor/project_metadata.cfg"
  if [ -f "$metadata_file" ]; then
    candidate_mtime="$(stat -f %m "$metadata_file")"
  else
    candidate_mtime="$(stat -f %m "$candidate_dir")"
  fi

  if [ "$candidate_mtime" -gt "$best_mtime" ]; then
    best_source="$candidate_dir"
    best_mtime="$candidate_mtime"
  fi
done < <(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}')

if [ -z "$best_source" ]; then
  exit 0
fi

cp -R "$best_source" "$current_root/.godot"
