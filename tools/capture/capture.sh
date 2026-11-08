#!/usr/bin/env bash
# Render a scene and save a PNG of the viewport.
#
# Usage: tools/capture/capture.sh <scene.tscn> <out.png> [--camera <NodePath>] [--frames N]
#
# Display selection (rendering needs a real Vulkan device, never --headless):
#   1. xvfb-run present  -> virtual X server (CI: Xvfb + Mesa lavapipe, mesa-vulkan-drivers).
#   2. WAYLAND_DISPLAY or DISPLAY set -> the live desktop session (dev box without Xvfb).
#   3. otherwise fail with instructions.
# Set CAPTURE_SIZE=WxH (default 1280x720) to change the window size.
set -euo pipefail

if [ $# -lt 2 ]; then
	sed -n '2,10p' "$0"
	exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCENE="$1"
OUT="$2"
shift 2
SIZE="${CAPTURE_SIZE:-1280x720}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"
case "$SCENE" in
res://*) ;;
"$REPO_ROOT"/*) SCENE="res://${SCENE#"$REPO_ROOT"/}" ;;
*) SCENE="res://$SCENE" ;;
esac

cmd=(godot --path "$REPO_ROOT" --resolution "$SIZE" --rendering-driver vulkan -s tools/capture/capture.gd -- "$SCENE" "$OUT" --size "$SIZE" "$@")

if command -v xvfb-run >/dev/null 2>&1; then
	echo "capture.sh: using xvfb-run"
	xvfb-run -a -s "-screen 0 ${SIZE}x24" "${cmd[@]}"
elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
	echo "capture.sh: no xvfb-run; using live session (WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-} DISPLAY=${DISPLAY:-})"
	"${cmd[@]}"
else
	echo "capture.sh: no display. Install xvfb (CI: apt install xvfb mesa-vulkan-drivers) or run in a desktop session." >&2
	exit 1
fi
