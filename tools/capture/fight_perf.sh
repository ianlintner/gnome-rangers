#!/usr/bin/env bash
# Log per-second FPS across a full scripted on-foot Grukk fight on a real rendering device.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${REPO_ROOT}/docs/perf/final_fight_fps.txt"
mkdir -p "$(dirname "$OUT")"
cmd=(godot --path "$REPO_ROOT" --resolution 1280x720 --rendering-driver vulkan \
  res://tools/capture/fight_perf.tscn -- --out "$OUT")
if command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"
elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
  "${cmd[@]}"
else
  echo "fight_perf.sh: no display available" >&2
  exit 1
fi
