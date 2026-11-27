#!/usr/bin/env bash
# Capture the rider mid-gallop and mid-pounce in the sandbox.
#
# Usage: tools/capture/mount.sh [out_dir]
#   out_dir defaults to docs/captures. Size: CAPTURE_SIZE=WxH (default 1920x1080).
# Needs a display: xvfb-run when present, else the live session (XDG_RUNTIME_DIR and
# WAYLAND_DISPLAY are filled in when unset, as in rootfall.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/docs/captures}"
SIZE="${CAPTURE_SIZE:-1920x1080}"
case "$OUT_DIR" in /*) ;; *) OUT_DIR="$PWD/$OUT_DIR" ;; esac
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && ! command -v xvfb-run >/dev/null 2>&1; then
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi
cmd=(godot --path "$REPO_ROOT" --resolution "$SIZE" --rendering-driver vulkan
	res://tools/capture/mount_capture.tscn -- "$OUT_DIR")
if command -v xvfb-run >/dev/null 2>&1; then
	xvfb-run -a -s "-screen 0 ${SIZE}x24" "${cmd[@]}"
else
	"${cmd[@]}"
fi
