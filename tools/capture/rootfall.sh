#!/usr/bin/env bash
# Render the 3 fixed Rootfall Hollow captures (approach, arena wide, hero) plus nothing else.
#
# Usage: tools/capture/rootfall.sh [out_dir] [--frames N]
#   out_dir defaults to docs/captures. Size: CAPTURE_SIZE=WxH (default 1920x1080 here).
# Needs a display (see capture.sh). On a Hyprland/Wayland dev box without xvfb the live
# session is used: XDG_RUNTIME_DIR and WAYLAND_DISPLAY are filled in when unset.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/docs/captures}"
[ $# -gt 0 ] && shift
export CAPTURE_SIZE="${CAPTURE_SIZE:-1920x1080}"
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && ! command -v xvfb-run >/dev/null 2>&1; then
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi
# Longer warm-up than the sandbox: volumetric fog and SDFGI need a few dozen frames to converge.
FRAMES="${FRAMES:-120}"

for entry in approach:CamApproach arena_wide:CamArenaWide hero:CamHero; do
	name="${entry%%:*}"
	camera="${entry##*:}"
	"$REPO_ROOT/tools/capture/capture.sh" tools/capture/rootfall_capture.tscn \
		"$OUT_DIR/rootfall_$name.png" --camera "$camera" --frames "$FRAMES" "$@"
done
