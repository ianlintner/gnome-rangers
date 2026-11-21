#!/usr/bin/env bash
# Fly-through fps log for Rootfall Hollow (needs a display; see capture.sh).
#
# Usage: tools/capture/perf.sh [--tier high|dev] [--seconds N] [--size WxH] [--out log.txt]
# Defaults: dev tier, 30 s, 1920x1080. Prints per-second fps and the average.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && ! command -v xvfb-run >/dev/null 2>&1; then
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi
cmd=(godot --path "$REPO_ROOT" --resolution 1920x1080 --rendering-driver vulkan
	-s tools/capture/perf.gd -- "$@")
if command -v xvfb-run >/dev/null 2>&1 && [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
	xvfb-run -a -s "-screen 0 1920x1080x24" "${cmd[@]}"
else
	"${cmd[@]}"
fi
