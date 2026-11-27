#!/usr/bin/env bash
# Render four PNGs of the real MVP slice (checkpoint, mounted approach, boss phase 2, victory).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${REPO_ROOT}/docs/captures"
mkdir -p "$OUT"
cmd=(godot --path "$REPO_ROOT" --resolution 1280x720 --rendering-driver vulkan \
  res://tools/capture/final_slice.tscn -- --out "$OUT")
if command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"
elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
  "${cmd[@]}"
else
  echo "final_slice.sh: no display available" >&2
  exit 1
fi
