#!/usr/bin/env bash
# Render PNGs of the real game (res://main.tscn) at 1280x720 through tools/capture/game_capture.gd.
#
# Usage: tools/capture/game.sh [--shots a,b,...] [--out DIR]
#   --shots  comma-separated shot names (default: all; see SHOTS in game_capture.gd)
#   --out    output dir (default ~/lab/artifacts/playable-sweep/gnome-rangers/next/)
#
# Display selection (never --headless): xvfb-run if present, else the live session.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
user_args=()
while [ $# -gt 0 ]; do
	case "$1" in
	--shots | --out)
		[ $# -ge 2 ] || { echo "game.sh: $1 needs a value" >&2; exit 2; }
		if [ "$1" = "--out" ]; then
			mkdir -p "$2"
			user_args+=("$1" "$(cd "$2" && pwd)")
		else
			user_args+=("$1" "$2")
		fi
		shift 2
		;;
	-h | --help) sed -n '2,8p' "$0"; exit 0 ;;
	*) echo "game.sh: unknown argument $1" >&2; exit 2 ;;
	esac
done
cmd=(godot --path "$REPO_ROOT" --resolution 1280x720 --rendering-driver vulkan \
	res://tools/capture/game_capture.tscn)
if [ ${#user_args[@]} -gt 0 ]; then
	cmd+=(-- "${user_args[@]}")
fi
if command -v xvfb-run >/dev/null 2>&1; then
	exec xvfb-run -a -s "-screen 0 1280x720x24" "${cmd[@]}"
elif [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
	exec "${cmd[@]}"
fi
echo "game.sh: no display available" >&2
exit 1
